import 'dart:io';

import 'package:family_screen_time/src/controller.dart';
import 'package:family_screen_time/src/store.dart';
import 'package:family_screen_time/src/sync/family_entities.dart';
import 'package:family_screen_time/src/sync/family_sync.dart';
import 'package:family_screen_time/src/sync/receipts.dart';
import 'package:family_screen_time/src/ui/changes_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screentime_engine/screentime_engine.dart';
import 'package:screentime_sync/screentime_sync.dart';

/// What [to] lacks of [from]'s, as the network passes it on.
Future<void> pass(FamilySync from, FamilySync to) async {
  await to.node.ingest(
    from.node.store.missingFor(
      to.node.store.vector,
      limit: 1 << 30,
      to: Audience.of(from.node.replica[SyncKeys.device(to.deviceId)]),
    ),
  );
}

void main() {
  final now = DateTime(2026, 10, 24, 15);
  final family = FamilyData(
    children: const [
      Child(id: 'emma', name: 'Emma'),
      Child(id: 'leo', name: 'Léo'),
    ],
    config: const FamilyConfig(
      appGroups: {
        'games': {'minecraft'},
        'games.leo': {'roblox'},
      },
    ),
    groupOwners: const {'games': 'emma', 'games.leo': 'leo'},
    state: const FamilyState(
      rules: [
        Rule(id: 'e', childId: 'emma', dailyQuota: Duration(hours: 1)),
        Rule(id: 'l', childId: 'leo', dailyQuota: Duration(hours: 2)),
      ],
    ),
  );

  late List<Directory> dirs;
  setUp(() => dirs = []);
  tearDown(() async {
    for (final d in dirs) {
      await d.delete(recursive: true);
    }
  });
  LocalStore newStore() {
    final d = Directory.systemTemp.createTempSync('fst-apart');
    dirs.add(d);
    return LocalStore(d);
  }

  /// The parent's phone, and a tablet for each child.
  Future<(FamilySync, SigningKey, FamilySync, FamilySync, LocalStore)>
  linked() async {
    final (phone, key) = await FamilySync.create(
      store: newStore(),
      settings: const AppSettings(
        deviceId: 'phone',
        language: 'fr',
        setupDone: true,
        parentDevice: true,
      ),
      family: family,
      parentCode: '123456',
      deviceName: 'Papa',
    );
    final tablets = <FamilySync>[];
    late LocalStore emmaStore;
    for (final (id, child) in [('tabE', 'emma'), ('tabL', 'leo')]) {
      final identity = await DeviceIdentity.generate(id);
      await phone.node.emit([
        EventDraft.put(SyncKeys.device(id), {
          'name': id,
          'role': 'child',
          'childId': child,
          'signKey': identity.signing.publicKey,
        }),
      ], parentKey: key);
      final store = newStore();
      if (child == 'emma') emmaStore = store;
      final tablet = await FamilySync.join(
        store: store,
        identity: identity,
        welcome: Welcome(
          phone.node.root,
          phone.node.store.missingFor(
            const {},
            limit: 1 << 30,
            to: Audience.of(phone.node.replica[SyncKeys.device(id)]),
          ),
        ),
      );
      await tablet.commit();
      tablets.add(tablet);
    }
    return (phone, key, tablets[0], tablets[1], emmaStore);
  }

  test('each child\'s tablet holds only the family\'s and theirs', () async {
    final (phone, key, emma, leo, emmaStore) = await linked();
    final onEmma = emma.compose(const FamilyData());
    expect(onEmma.children.map((c) => c.id), ['emma']);
    // To link a device to her brother from her tablet.
    expect(emma.allChildren().map((c) => c.id), ['emma', 'leo']);
    expect(onEmma.state.rules.map((r) => r.id), ['e']);
    expect(onEmma.config.appGroups.keys, ['games']);
    expect(leo.compose(const FamilyData()).state.rules.map((r) => r.id), ['l']);
    // The parent's phone shows everything.
    expect(phone.compose(const FamilyData()).children, hasLength(2));

    // A limit for Léo does not go to Emma's tablet.
    final more = family.copyWith(
      state: FamilyState(
        rules: [
          ...family.state.rules,
          const Rule(id: 'l2', childId: 'leo', dailyQuota: Duration(hours: 1)),
        ],
      ),
    );
    await phone.recordChange(family, more, parentKey: key);
    await pass(phone, emma);
    await pass(phone, leo);
    expect(emma.node.replica['${FamilyKeys.rule}l2'], isNull);
    expect(leo.node.replica['${FamilyKeys.rule}l2'], isNotNull);
    // Nor what Emma's tablet sends to Léo's directly.
    await pass(emma, leo);
    expect(leo.node.replica['${FamilyKeys.rule}e'], isNull);

    // In parent mode on Emma's tablet, only Emma's is changed: Léo's,
    // not shown there, are left as they are.
    final onEmmaNow = emma.compose(const FamilyData());
    final edited = onEmmaNow.copyWith(graceReminderMinutes: 7);
    final made = await emma.recordChange(
      family, // Still holding Léo's, as before 0.25.
      edited,
      parentKey: key,
    );
    expect(made.map((e) => e.key), isNot(contains('${FamilyKeys.rule}l')));
    expect(made.map((e) => e.key), isNot(contains('${FamilyKeys.child}leo')));

    // The use of apps Léo had there goes when the tablet is tidied.
    await emmaStore.appendUsage(
      UsageSegment.device(
        childId: 'leo',
        deviceId: 'tabL',
        appId: 'roblox',
        start: now,
        end: now.add(const Duration(minutes: 5)),
      ),
    );
    await emmaStore.appendUsage(
      UsageSegment.device(
        childId: 'emma',
        deviceId: 'tabE',
        appId: 'minecraft',
        start: now,
        end: now.add(const Duration(minutes: 5)),
      ),
    );
    expect(await emma.tidy(emmaStore), isNotNull);
    expect(
      (await emmaStore.loadUsage(since: now.subtract(const Duration(days: 1))))
          .map((u) => u.childId),
      ['emma'],
    );
    expect(await emma.tidy(emmaStore), isNull);
    for (final s in [phone, emma, leo]) {
      await s.close();
    }
  });

  test('a tablet\'s home screen is left out of the statistics', () async {
    final (phone, _, emma, leo, _) = await linked();
    expect(
      await emma.publishSystem({'com.miui.home', 'org.familyscreentime'}),
      isTrue,
    );
    expect(
      await emma.publishSystem({'org.familyscreentime', 'com.miui.home'}),
      isFalse,
    );
    await pass(emma, phone);
    await pass(emma, leo);
    expect(phone.sharedSystem(), contains('com.miui.home'));
    // Emma's devices' own: not her brother's.
    expect(leo.sharedSystem(), isEmpty);
    final c = AppController(
      newStore(),
      const AppSettings(deviceId: 'phone', language: 'fr', setupDone: true),
      const FamilyData(),
    );
    expect(await c.usageExcluded(), contains('com.miui.home'));
    c.dispose();
    for (final s in [phone, emma, leo]) {
      await s.close();
    }
  });

  test('a limit the child sets shows in the journal', () async {
    final (phone, key, emma, leo, _) = await linked();
    final onEmma = emma.compose(const FamilyData());
    final own = onEmma.copyWith(
      state: FamilyState(
        rules: [
          ...onEmma.state.rules,
          const Rule(
            id: 'mine',
            childId: 'emma',
            dailyQuota: Duration(minutes: 30),
            setByChild: true,
          ),
        ],
      ),
    );
    // Outside parent mode: signed by the tablet.
    final made = await emma.recordChange(onEmma, own);
    expect(made.map((e) => e.key), contains('${FamilyKeys.rule}mine'));
    await pass(emma, phone);
    final change = recentChanges(phone).firstWhere((c) => c.device == 'tabE');
    expect(change.events.single.signer, Signer.device);
    expect(targetsOf(phone, change), ['phone']);
    final c = AppController(
      newStore(),
      const AppSettings(deviceId: 'phone', language: 'fr', setupDone: true),
      phone.compose(const FamilyData()),
    );
    expect(describeChange(c, change), [
      "Emma : Limite fixée par l'enfant : ${c.targetLabel(const AppTarget.all())}",
    ]);
    c.dispose();
    for (final s in [phone, emma, leo]) {
      await s.close();
    }
  });
}
