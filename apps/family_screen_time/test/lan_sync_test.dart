import 'dart:io';

import 'package:family_screen_time/src/controller.dart';
import 'package:family_screen_time/src/store.dart';
import 'package:family_screen_time/src/sync/family_sync.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screentime_engine/screentime_engine.dart';
import 'package:screentime_sync/screentime_sync.dart';

Future<void> until(bool Function() done, {int tries = 200}) async {
  for (var i = 0; i < tries && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final loopback = InternetAddress.loopbackIPv4;
  late Directory dirA;
  late Directory dirB;

  setUp(() async {
    dirA = await Directory.systemTemp.createTemp('fst-a');
    dirB = await Directory.systemTemp.createTemp('fst-b');
  });
  tearDown(() async {
    await dirA.delete(recursive: true);
    await dirB.delete(recursive: true);
  });

  test('a second device joins, then settings and use go both ways', () async {
    final storeA = LocalStore(dirA);
    final storeB = LocalStore(dirB);
    final family = FamilyData(
      children: const [Child(id: 'emma', name: 'Emma')],
      config: const FamilyConfig(
        appGroups: {
          'games': {'minecraft'},
        },
        neverBlocked: {'launcher.a'},
      ),
      state: const FamilyState(
        rules: [
          Rule(
            id: 'games',
            childId: 'emma',
            appTarget: AppTarget.group('games'),
            dailyQuota: Duration(minutes: 30),
          ),
        ],
      ),
      groupNames: const {'games': 'Jeux'},
    );
    await storeA.saveFamily(family);
    const settingsA = AppSettings(
      deviceId: 'tablet',
      language: 'fr',
      setupDone: true,
      childId: 'emma',
    );
    final (uiA, parentKey) = await FamilySync.create(
      store: storeA,
      settings: settingsA,
      family: family,
      parentCode: '123456',
      deviceName: 'Tablette',
    );
    final bgA = (await FamilySync.open(storeA, background: true))!;
    // The tablet was used this morning, before the phone joined.
    final morning = DateTime.now().subtract(const Duration(hours: 1));
    final earlier = UsageSegment.device(
      childId: 'emma',
      deviceId: 'tablet',
      appId: 'minecraft',
      start: morning,
      end: morning.add(const Duration(minutes: 20)),
    );
    await storeA.appendUsage(earlier);
    await bgA.recordUsage([earlier]);
    final [netA, netB] = MemoryLanDirectory.network(2);

    // The tablet, in parent mode, welcomes the phone.
    final host = PairingHost(
      node: uiA.node,
      parentKey: parentKey,
      directory: netA,
      name: 'Tablette',
      confirm: (code, info) async => {
        'name': 'Téléphone d\'Emma',
        'role': 'child',
        'childId': 'emma',
      },
    );
    await host.start(address: loopback);
    final found = await findPairingHosts(netB).first;
    final me = await DeviceIdentity.generate('phone');
    final welcome = await joinThrough(
      found,
      me: me,
      info: const {'name': 'Android'},
      confirm: (code) async => true,
    );
    await host.stop();
    final uiB = await FamilySync.join(
      store: storeB,
      identity: me,
      welcome: welcome,
    );
    // Nothing changes on the device until it is committed.
    expect(await SyncFiles(storeB).currentDatabase(), isNull);
    await uiB.commit();
    expect(await SyncFiles(storeB).currentDatabase(), uiB.dbName);
    expect(uiB.registration?['childId'], 'emma');
    expect(uiB.devices.keys, containsAll(['tablet', 'phone']));
    // The phone's own family, from the log, with its own system apps.
    final joined = uiB.compose(
      const FamilyData(config: FamilyConfig(neverBlocked: {'launcher.b'})),
    );
    expect(joined.state.rules.single.dailyQuota, const Duration(minutes: 30));
    expect(joined.config.neverBlocked, {'launcher.b'});
    await storeB.saveFamily(joined);
    expect(await uiB.unlock('123456'), isNotNull);

    // Both background services on the network.
    final bgB = (await FamilySync.open(storeB, background: true))!;
    // The tablet's use before the phone joined counts on the phone, once.
    expect(await bgB.importOthersUsage(storeB), 1);
    expect(await bgB.importOthersUsage(storeB), 0);
    expect(
      (await storeB.loadUsage(since: morning.subtract(const Duration(days: 1))))
          .single
          .deviceId,
      'tablet',
    );
    final remoteA = <Accepted>[];
    final remoteB = <Accepted>[];
    bgA.node.accepted.listen((a) {
      if (a.source is SyncSession) remoteA.add(a);
    });
    bgB.node.accepted.listen((a) {
      if (a.source is SyncSession) remoteB.add(a);
    });
    final lanA = LanSync(bgA.node, netA);
    final lanB = LanSync(bgB.node, netB);
    await lanA.start(address: loopback);
    await lanB.start(address: loopback);
    addTearDown(lanA.stop);
    addTearDown(lanB.stop);
    expect(await lanA.waitFor('phone'), isTrue);

    // A parent change on the tablet reaches the phone's family file.
    final changed = family.copyWith(graceReminderMinutes: 4);
    await uiA.recordChange(family, changed, parentKey: parentKey);
    await bgA.readOthers();
    await until(() => remoteB.any((a) => a.replicaChanged));
    for (final a in remoteB) {
      await bgB.applyRemote(a, storeB);
    }
    final onPhone = await storeB.loadFamily();
    expect(onPhone.graceReminderMinutes, 4);
    expect(onPhone.config.neverBlocked, {'launcher.b'});

    // Use on the phone counts on the tablet.
    final start = DateTime.now().subtract(const Duration(minutes: 10));
    await bgB.recordUsage([
      UsageSegment.device(
        childId: 'emma',
        deviceId: 'phone',
        appId: 'minecraft',
        start: start,
        end: start.add(const Duration(minutes: 5)),
      ),
    ]);
    await until(
      () => remoteA.any((a) => a.events.any((e) => e.type == 'usage')),
    );
    for (final a in remoteA) {
      await bgA.applyRemote(a, storeA);
    }
    final usage = await storeA.loadUsage(
      since: morning.subtract(const Duration(days: 1)),
    );
    expect(usage.map((u) => u.deviceId), containsAll(['tablet', 'phone']));
    // And nothing twice if it imports later on.
    await bgA.importOthersUsage(storeA);
    expect(
      await storeA.loadUsage(since: morning.subtract(const Duration(days: 1))),
      hasLength(2),
    );

    // Contact as the tablet's monitor sees it.
    await bgA.savePeers(lanA.peers);
    final peers = await uiA.peers();
    expect(peers['phone']?.connected, isTrue);
  });

  test('a parent\'s phone changes the settings from its own app', () async {
    final storeA = LocalStore(dirA);
    final storeP = LocalStore(dirB);
    final family = FamilyData(
      children: const [Child(id: 'emma', name: 'Emma')],
      state: const FamilyState(
        rules: [
          Rule(id: 'all', childId: 'emma', dailyQuota: Duration(hours: 2)),
        ],
      ),
    );
    await storeA.saveFamily(family);
    final (uiA, parentKey) = await FamilySync.create(
      store: storeA,
      settings: const AppSettings(
        deviceId: 'tablet',
        language: 'fr',
        setupDone: true,
        childId: 'emma',
      ),
      family: family,
      parentCode: '123456',
      deviceName: 'Tablette',
    );
    final bgA = (await FamilySync.open(storeA, background: true))!;
    final [netA, netP] = MemoryLanDirectory.network(2);
    final host = PairingHost(
      node: uiA.node,
      parentKey: parentKey,
      directory: netA,
      name: 'Tablette',
      confirm: (code, info) async => {'name': 'Papa', 'role': 'parent'},
    );
    await host.start(address: loopback);
    final me = await DeviceIdentity.generate('papa');
    final welcome = await joinThrough(
      await findPairingHosts(netP).first,
      me: me,
      info: const {'name': 'Android'},
      confirm: (code) async => true,
    );
    await host.stop();
    // The phone has no monitor: its interface is on the network.
    final phone = await FamilySync.join(
      store: storeP,
      identity: me,
      welcome: welcome,
    );
    await phone.commit();
    expect(phone.registration?['role'], 'parent');
    final onPhone = phone.compose(const FamilyData());
    await storeP.saveFamily(onPhone);

    final remoteA = <Accepted>[];
    bgA.node.accepted.listen((a) {
      if (a.source is SyncSession) remoteA.add(a);
    });
    final lanA = LanSync(bgA.node, netA);
    final lanP = LanSync(phone.node, netP);
    await lanA.start(address: loopback);
    await lanP.start(address: loopback);
    addTearDown(lanA.stop);
    addTearDown(lanP.stop);
    expect(await lanP.waitFor('tablet'), isTrue);

    // The parent code opens the family's key on the phone too.
    final key = (await phone.unlock('123456'))!;
    final more = onPhone.copyWith(
      state: onPhone.state.copyWith(
        rules: [
          const Rule(
            id: 'all',
            childId: 'emma',
            dailyQuota: Duration(hours: 3),
          ),
        ],
      ),
    );
    await phone.recordChange(onPhone, more, parentKey: key);
    await until(() => remoteA.any((a) => a.replicaChanged));
    for (final a in remoteA) {
      await bgA.applyRemote(a, storeA);
    }
    final onTablet = await storeA.loadFamily();
    expect(onTablet.state.rules.single.dailyQuota, const Duration(hours: 3));
    // Without the key, the phone signs nothing in the family's name.
    final events = await phone.recordChange(more, onPhone);
    expect(events, isEmpty);
  });

  test('a device set up on its own joins, then leaves again', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('org.familyscreentime/platform'),
          (call) async => switch (call.method) {
            'systemPackages' => <String, Object?>{
              'self': 'org.familyscreentime',
              'launchers': <String>[],
            },
            'deviceName' => 'Fairphone 5',
            _ => null,
          },
        );
    final storeA = LocalStore(dirA);
    final storeB = LocalStore(dirB);
    // The tablet, linked already (here, on its own in its log).
    final family = FamilyData(
      children: const [Child(id: 'emma', name: 'Emma')],
      config: const FamilyConfig(
        appGroups: {
          'games': {'minecraft'},
        },
      ),
      state: const FamilyState(
        rules: [
          Rule(
            id: 'games',
            childId: 'emma',
            appTarget: AppTarget.group('games'),
            dailyQuota: Duration(minutes: 30),
          ),
        ],
      ),
      groupNames: const {'games': 'Jeux'},
    );
    await storeA.saveFamily(family);
    final (uiA, parentKey) = await FamilySync.create(
      store: storeA,
      settings: const AppSettings(
        deviceId: 'tablet',
        language: 'fr',
        setupDone: true,
        childId: 'emma',
      ),
      family: family,
      parentCode: '123456',
      deviceName: 'Tablette',
    );
    final morning = DateTime.now().subtract(const Duration(hours: 2));
    await uiA.recordUsage([
      UsageSegment.device(
        childId: 'emma',
        deviceId: 'tablet',
        appId: 'minecraft',
        start: morning,
        end: morning.add(const Duration(minutes: 10)),
      ),
    ]);

    // The phone, set up on its own: Emma under another id, her own rules,
    // a group of the same name, and use already.
    final own = FamilyData(
      children: const [Child(id: 'em2', name: 'Emma', volumeSpeaker: 50)],
      config: const FamilyConfig(
        appGroups: {
          'g2': {'roblox'},
        },
      ),
      state: const FamilyState(
        rules: [
          Rule(
            id: 'r2',
            childId: 'em2',
            appTarget: AppTarget.group('g2'),
            dailyQuota: Duration(minutes: 45),
          ),
        ],
      ),
      groupNames: const {'g2': 'jeux'},
    );
    const settingsB = AppSettings(
      deviceId: 'phone',
      language: 'fr',
      setupDone: true,
      childId: 'em2',
    );
    await storeB.saveSettings(settingsB);
    await storeB.saveFamily(own);
    final used = UsageSegment.device(
      childId: 'em2',
      deviceId: 'phone',
      appId: 'roblox',
      start: morning.add(const Duration(minutes: 30)),
      end: morning.add(const Duration(minutes: 50)),
    );
    await storeB.appendUsage(used);
    final c = AppController(storeB, settingsB, own);

    // The tablet welcomes it as Emma's.
    final [netA, netB] = MemoryLanDirectory.network(2);
    Map<String, Object?>? told;
    final host = PairingHost(
      node: uiA.node,
      parentKey: parentKey,
      directory: netA,
      name: 'Tablette',
      confirm: (code, info) async {
        told = info;
        return {'name': 'Téléphone', 'role': 'child', 'childId': 'emma'};
      },
    );
    await host.start(address: loopback);
    final me = await DeviceIdentity.generate('phone');
    final welcome = await joinThrough(
      await findPairingHosts(netB).first,
      me: me,
      info: const {
        'name': 'Fairphone 5',
        'child': {'id': 'em2', 'name': 'Emma'},
      },
      confirm: (code) async => true,
    );
    await host.stop();
    expect(told?['child'], {'id': 'em2', 'name': 'Emma'});
    final log = await FamilySync.join(
      store: storeB,
      identity: me,
      welcome: welcome,
    );
    expect(c.joinAsksForRules(log), isTrue);
    await c.completeJoin(log, '123456', keepRules: true);

    // Her rules there, and hers from here for this phone only.
    expect(c.settings.childId, 'emma');
    expect(c.family.children.map((k) => k.id), ['emma']);
    expect(c.family.config.appGroups['games'], {'minecraft', 'roblox'});
    final kept = c.family.state.rules.firstWhere((r) => r.id == 'r2');
    expect(kept.childId, 'emma');
    expect(kept.appTarget, const AppTarget.group('games'));
    expect(kept.deviceTarget, const DeviceTarget.device('phone'));
    expect(log.node.replica['rule/r2'], isNotNull);
    // Her use here is hers there.
    final since = morning.subtract(const Duration(days: 1));
    expect((await storeB.loadUsage(since: since)).single.childId, 'emma');
    expect(await SyncFiles(storeB).currentDatabase(), log.dbName);
    expect(await storeB.loadFamily(), isA<FamilyData>());

    // The tablet's use came too, then the phone leaves.
    expect(await log.importOthersUsage(storeB), 1);
    c.parentCodeEntered('123456');
    c.enterParentMode();
    expect(await c.detach(tellOthers: Duration.zero), isTrue);
    expect(await SyncFiles(storeB).exist, isFalse);
    expect(await c.sync, isNull);
    expect(c.family.state.rules.map((r) => r.id), containsAll(['games', 'r2']));
    expect((await storeB.loadUsage(since: since)).map((u) => u.deviceId), [
      'phone',
    ]);
    c.leaveParentMode();
    c.dispose();
  });
}
