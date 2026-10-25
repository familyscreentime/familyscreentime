import 'dart:io';

import 'package:family_screen_time/src/controller.dart';
import 'package:family_screen_time/src/platform.dart';
import 'package:family_screen_time/src/self_limits.dart';
import 'package:family_screen_time/src/store.dart';
import 'package:family_screen_time/src/sync/family_entities.dart';
import 'package:family_screen_time/src/sync/family_sync.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screentime_engine/screentime_engine.dart';
import 'package:screentime_sync/screentime_sync.dart';

final _now = DateTime.utc(2026, 10, 23, 9);

FamilyData richFamily() => FamilyData(
  children: const [
    Child(id: 'emma', name: 'Emma', volumeHeadphones: 60),
    Child(id: 'lucas', name: 'Lucas'),
  ],
  config: FamilyConfig(
    appGroups: const {
      'games': {'minecraft', 'roblox'},
      'music': {'spotify'},
    },
    alwaysAllowed: const {'dialer'},
    allowedInHours: const {'sms'},
    neverBlocked: const {'launcher'},
    profiles: [
      Profile(
        id: 'z',
        name: 'Vacances',
        kind: ProfileKind.custom,
        periods: [DateRange(DateTime(2026, 12, 20), DateTime(2027, 1, 3))],
      ),
      const Profile(id: 'a', name: 'Examens', kind: ProfileKind.custom),
    ],
  ),
  state: FamilyState(
    rules: const [
      Rule(
        id: 'a1',
        childId: 'emma',
        appTarget: AppTarget.group('games'),
        dailyQuota: Duration(minutes: 30),
      ),
      Rule(id: 'b2', childId: 'emma', dailyQuota: Duration(hours: 2)),
    ],
    bonuses: [
      Bonus.forRule(
        id: 'bonus1',
        childId: 'emma',
        ruleId: 'a1',
        amount: const Duration(minutes: 15),
        grantedAt: _now,
        validUntil: _now.add(const Duration(hours: 12)),
      ),
    ],
  ),
  groupNames: const {'games': 'Jeux', 'music': 'Musique'},
  appNames: const {'minecraft': 'Minecraft'},
  graceReminderMinutes: 2,
  injected: [
    UsageSegment.injected(
      childId: 'emma',
      injectedTarget: const AppTarget.group('games'),
      start: _now.subtract(const Duration(minutes: 20)),
      end: _now,
    ),
  ],
  selfLimitLog: [
    SelfLimitEvent(
      at: _now,
      ruleId: 'r',
      action: SelfLimitAction.created,
      target: const AppTarget.all(),
      daily: const Duration(hours: 1),
    ),
  ],
  outOfTime: OutOfTime.device,
  settingsParentOnly: true,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the family survives being cut into entities and put back', () {
    final f = richFamily();
    final back = familyFromEntities(familyEntities(f), f);
    expect(canonicalJson(back.toJson()), canonicalJson(f.toJson()));
    // The periods keep their order of priority.
    expect(back.config.profiles.map((p) => p.id), ['z', 'a']);
    // What belongs to this device only is not shared.
    expect(canonicalJson(familyEntities(f)), isNot(contains('launcher')));
  });

  group('what a child device may sign alone', () {
    final device = <String, Object?>{'childId': 'emma', 'signKey': 'k'};
    SyncEvent event(String type, String key, Map<String, Object?> data) =>
        SyncEvent(
          origin: 'tablet~ui',
          seq: 1,
          hlc: Hlc.zero,
          type: type,
          key: key,
          data: data,
          signer: Signer.device,
          sig: '',
        );
    const policy = FamilySyncPolicy();
    final replica = Replica();

    test('its own limits and breaks, not the parent\'s rules', () {
      final own = ruleToJson(
        const Rule(
          id: 'mine',
          childId: 'emma',
          dailyQuota: Duration(hours: 1),
          setByChild: true,
        ),
      );
      expect(
        policy.deviceMay(event('put', 'rule/mine', own), device, replica),
        isTrue,
      );
      final parents = ruleToJson(
        const Rule(id: 'p', childId: 'emma', dailyQuota: Duration(hours: 5)),
      );
      expect(
        policy.deviceMay(event('put', 'rule/p', parents), device, replica),
        isFalse,
      );
      final other = ruleToJson(
        const Rule(id: 'l', childId: 'lucas', setByChild: true),
      );
      expect(
        policy.deviceMay(event('put', 'rule/l', other), device, replica),
        isFalse,
      );
      final pause = temporaryBlockToJson(
        TemporaryBlock(
          id: 'p1',
          childId: 'emma',
          from: _now,
          until: _now.add(const Duration(minutes: 15)),
          voluntary: true,
        ),
      );
      expect(
        policy.deviceMay(
          event('put', 'temporaryBlock/p1', pause),
          device,
          replica,
        ),
        isTrue,
      );
      expect(
        policy.deviceMay(
          event('delete', 'temporaryBlock/p1', {}),
          device,
          replica,
        ),
        isFalse,
      );
      expect(
        policy.deviceMay(event('put', 'bonus/x', {'id': 'x'}), device, replica),
        isFalse,
      );
    });

    test('its own apps\' names and icons', () {
      expect(
        policy.deviceMay(
          event('put', 'app/tablet/com.roblox.client', {'label': 'Roblox'}),
          device,
          replica,
        ),
        isTrue,
      );
      expect(
        policy.deviceMay(
          event('put', 'app/phone/com.roblox.client', {'label': 'Roblox'}),
          device,
          replica,
        ),
        isFalse,
      );
    });

    test('its own use only', () {
      expect(
        policy.deviceMay(
          event('usage', 'usage', {'childId': 'emma', 'deviceId': 'tablet'}),
          device,
          replica,
        ),
        isTrue,
      );
      expect(
        policy.deviceMay(
          event('usage', 'usage', {'childId': 'emma', 'deviceId': 'phone'}),
          device,
          replica,
        ),
        isFalse,
      );
    });
  });

  group('the family log on this device', () {
    late Directory dir;
    late LocalStore store;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('fst-sync');
      store = LocalStore(dir);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('org.familyscreentime/platform'),
            (_) async => null,
          );
    });
    tearDown(() => dir.delete(recursive: true));

    const settings = AppSettings(
      deviceId: 'tablet',
      language: 'fr',
      setupDone: true,
      childId: 'emma',
    );

    test('a log in JSON files from 0.19.0 is dropped', () async {
      final files = SyncFiles(store);
      await Directory('${files.dir.path}/log').create(recursive: true);
      await files.identity.writeAsString('{}');
      await files.root.writeAsString('{}');
      expect(await FamilySync.open(store, background: false), isNull);
      expect(await files.dir.exists(), isFalse);
    });

    test('created with the code, shared by interface and monitor', () async {
      final family = richFamily();
      final (sync, key) = await FamilySync.create(
        store: store,
        settings: settings,
        family: family,
        parentCode: '123456',
        deviceName: 'Tablette',
      );
      expect(await sync.unlock('123456'), isNotNull);
      expect(await sync.unlock('000000'), isNull);
      // Emma's tablet: her data and the family's, not her brother's.
      final emmas = familyFromEntities({
        for (final e in familyEntities(ownGroups(family)).entries)
          if (e.key != '${FamilyKeys.child}lucas' &&
              e.value['childId'] != 'lucas')
            e.key: e.value,
      }, family);
      expect(emmas.children.map((c) => c.id), ['emma']);
      expect(
        canonicalJson(sync.compose(family).toJson()),
        canonicalJson(emmas.toJson()),
      );

      final monitor = (await FamilySync.open(store, background: true))!;
      expect(
        canonicalJson(monitor.compose(family).toJson()),
        canonicalJson(emmas.toJson()),
      );
      // The interface changes a rule in parent mode; the monitor reads it.
      final changed = family.copyWith(
        graceReminderMinutes: 5,
        state: family.state.copyWith(rules: [family.state.rules.first]),
      );
      await sync.recordChange(family, changed, parentKey: key);
      final read = await monitor.readOthers();
      expect(read.map((e) => e.type), containsAll(['patch', 'delete']));
      expect(monitor.compose(family).graceReminderMinutes, 5);
      expect(monitor.compose(family).state.rules, hasLength(1));

      // The monitor records use; the interface sees it.
      await monitor.recordUsage([
        UsageSegment.device(
          childId: 'emma',
          deviceId: 'tablet',
          appId: 'minecraft',
          start: _now,
          end: _now.add(const Duration(minutes: 5)),
        ),
      ]);
      expect((await sync.readOthers()).single.type, 'usage');
    });

    test('installed apps are shared, only what changed', () async {
      final (sync, _) = await FamilySync.create(
        store: store,
        settings: settings,
        family: richFamily(),
        parentCode: '123456',
        deviceName: 'Tablette',
      );
      final roblox = AppInfo('Roblox', Uint8List.fromList([1, 2, 3]));
      expect(
        await sync.publishApps(
          {'com.roblox.client': 'Roblox'},
          icons: {'com.roblox.client': roblox},
        ),
        1,
      );
      expect(await sync.publishApps({'com.roblox.client': 'Roblox'}), 0);
      // A new name only.
      expect(await sync.publishApps({'com.roblox.client': 'Roblox 2'}), 1);
      expect(sync.sharedApps(['com.roblox.client']).values.single.icon, [
        1,
        2,
        3,
      ]);
      final shared = sync.sharedApps(['com.roblox.client', 'other']);
      expect(shared.keys, ['com.roblox.client']);
      expect(shared.values.single.label, 'Roblox 2');
      expect(shared.values.single.icon, [1, 2, 3]);
      expect(sync.sharedAppNames(), {'com.roblox.client': 'Roblox 2'});
      // Uninstalled: gone for the family too.
      expect(await sync.publishApps({}), 1);
      expect(sync.sharedAppNames(), isEmpty);
    });

    test(
      'outside parent mode, only what the child may change goes in',
      () async {
        final family = richFamily();
        final (sync, _) = await FamilySync.create(
          store: store,
          settings: settings,
          family: family,
          parentCode: '123456',
          deviceName: 'Tablette',
        );
        final withOwnLimit = family.copyWith(
          graceReminderMinutes: 9,
          state: family.state.copyWith(
            rules: [
              ...family.state.rules,
              const Rule(
                id: 'mine',
                childId: 'emma',
                dailyQuota: Duration(hours: 1),
                setByChild: true,
              ),
            ],
          ),
        );
        final events = await sync.recordChange(family, withOwnLimit);
        expect(events.map((e) => e.key), ['rule/mine']);
        expect(events.single.signer, Signer.device);
      },
    );

    test('the controller starts the log only when linking', () async {
      await store.saveSettings(settings);
      final c = AppController(store, settings, richFamily());
      expect(await c.sync, isNull);
      c.parentCodeEntered('123456');
      c.enterParentMode();
      // On its own, the device keeps no log.
      await c.updateFamily(c.family.copyWith(graceReminderMinutes: 6));
      expect(await c.sync, isNull);
      expect(await SyncFiles(store).exist, isFalse);
      final (log, _) = (await c.startLinking())!;
      expect(identical(await c.sync, log), isTrue);
      expect(log.compose(c.family).graceReminderMinutes, 6);
      await c.updateFamily(c.family.copyWith(graceReminderMinutes: 7));
      expect(log.compose(c.family).graceReminderMinutes, 7);
      final last = log.node.store.missingFor(const {}, limit: 1 << 30).last;
      expect(last.signer, Signer.parent);
      expect(await SyncFiles(store).exist, isTrue);
      // A new code reaches the log too.
      await c.changeParentCode('654321');
      expect(await log.unlock('654321'), isNotNull);
      c.leaveParentMode();
      c.dispose();
    });
  });
}
