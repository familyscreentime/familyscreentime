import 'dart:io';

import 'package:family_screen_time/src/store.dart';
import 'package:family_screen_time/src/sync/family_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screentime_engine/screentime_engine.dart';
import 'package:screentime_sync/screentime_sync.dart';

Future<void> until(bool Function() done, {int tries = 200}) async {
  for (var i = 0; i < tries && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
}

void main() {
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
}
