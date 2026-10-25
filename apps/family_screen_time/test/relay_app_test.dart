import 'dart:convert';
import 'dart:io';

import 'package:family_screen_time/src/controller.dart';
import 'package:family_screen_time/src/store.dart';
import 'package:family_screen_time/src/sync/family_sync.dart';
import 'package:family_screen_time/src/sync/relay_runner.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screentime_engine/screentime_engine.dart';
import 'package:screentime_sync/screentime_sync.dart';

/// The tablet's log as the phone would get it on the local network.
Future<void> overWifi(FamilySync from, FamilySync to) async {
  await from.readOthers();
  await to.node.ingest(
    from.node.store.missingFor(to.node.store.vector, limit: 1 << 30),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // PHP with sodium and SQLite, to run the server.
  final hasPhp = _phpReady();

  test('addresses typed by the parent', () {
    expect(
      relayEndpoint('exemple.org/fst').toString(),
      'https://exemple.org/fst/api.php',
    );
    expect(
      relayEndpoint('http://192.168.1.10:8080/').toString(),
      'http://192.168.1.10:8080/api.php',
    );
    expect(
      relayEndpoint('https://exemple.org/relais/api.php').toString(),
      'https://exemple.org/relais/api.php',
    );
    expect(relayEndpoint('ftp://x'), isNull);
    expect(relayEndpoint('  '), isNull);
  });

  group('with the PHP server', () {
    late Directory server;
    late Process php;
    late String endpoint;
    late Directory dirA;
    late Directory dirB;

    Future<String> invite() async =>
        ((await Process.run('php', [
                  'lib/cli.php',
                  'invite',
                  'test',
                ], workingDirectory: server.path)).stdout
                as String)
            .trim();

    setUpAll(() async {
      // Flutter's test binding answers every HTTP request with a 400.
      HttpOverrides.global = null;
      server = await Directory.systemTemp.createTemp('fst-relay-app');
      await Process.run('cp', ['-r', '../../server/.', server.path]);
      await Process.run('php', [
        'lib/cli.php',
        'install-sqlite',
        'test-password-12',
      ], workingDirectory: server.path);
      final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = socket.port;
      await socket.close();
      php = await Process.start('php', [
        '-S',
        '127.0.0.1:$port',
      ], workingDirectory: server.path);
      endpoint = 'http://127.0.0.1:$port/';
      for (var i = 0; i < 50; i++) {
        try {
          final c = HttpClient();
          await (await (await c.getUrl(
            Uri.parse('${endpoint}api.php?r=info'),
          )).close()).drain<void>();
          c.close();
          break;
        } on Object {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('org.familyscreentime/platform'),
            (call) async => call.method == 'deviceName' ? 'Tablette' : null,
          );
    });

    tearDownAll(() async {
      php.kill();
      await server.delete(recursive: true);
    });

    setUp(() async {
      dirA = await Directory.systemTemp.createTemp('fst-a');
      dirB = await Directory.systemTemp.createTemp('fst-b');
    });
    tearDown(() async {
      await dirA.delete(recursive: true);
      await dirB.delete(recursive: true);
    });

    /// A tablet and a phone linked on the local network, the phone set up
    /// by the welcome it got.
    Future<(AppController, FamilySync, FamilySync)> linked({
      bool oldFamily = false,
    }) async {
      final storeA = LocalStore(dirA);
      const family = FamilyData(
        children: [Child(id: 'emma', name: 'Emma')],
        state: FamilyState(
          rules: [
            Rule(id: 'all', childId: 'emma', dailyQuota: Duration(hours: 2)),
          ],
        ),
      );
      const settings = AppSettings(
        deviceId: 'tablet',
        language: 'fr',
        setupDone: true,
        childId: 'emma',
      );
      await storeA.saveSettings(settings);
      await storeA.saveFamily(family);
      final (tablet, parentKey) = await FamilySync.create(
        store: storeA,
        settings: settings,
        family: family,
        parentCode: '123456',
        deviceName: 'Tablette',
      );
      final phoneId = await DeviceIdentity.generate('phone');
      await tablet.node.emit([
        EventDraft.put(SyncKeys.device('phone'), {
          'name': 'Téléphone',
          'role': 'child',
          'childId': 'emma',
          'signKey': phoneId.signing.publicKey,
        }),
      ], parentKey: parentKey);
      var root = tablet.node.root;
      if (oldFamily) {
        // Linked before 0.23: no content key anywhere.
        root = FamilyRoot(root.familyId, root.parentKey);
        final file = SyncFiles(storeA).root;
        final j = jsonDecode(await file.readAsString()) as Map;
        await file.writeAsString(jsonEncode({...j}..remove('contentKey')));
      }
      final phone = await FamilySync.join(
        store: LocalStore(dirB),
        identity: phoneId,
        welcome: Welcome(
          root,
          tablet.node.store.missingFor(const {}, limit: 1 << 30),
        ),
      );
      await phone.commit();
      await tablet.close();
      final c = AppController(storeA, settings, family);
      await c.openSync();
      c.parentCodeEntered('123456');
      c.enterParentMode();
      return (c, (await c.sync)!, phone);
    }

    test('set up on the tablet, the phone syncs through it', () async {
      final (c, tablet, phone) = await linked();
      expect(await c.setUpRelay(endpoint, 'WRONG-CODE-0'), 'bad_invitation');
      expect(await c.setUpRelay(endpoint, ''), 'invitation_needed');
      expect(await c.setUpRelay(endpoint, await invite()), isNull);
      expect(tablet.relayUrl, '${endpoint}api.php');
      expect(readMembers(tablet.members)?.devices.keys, {'tablet', 'phone'});

      // The phone learns of the server on the local network, then syncs
      // through it from anywhere.
      await overWifi(tablet, phone);
      final onTablet = RelayRunner(tablet);
      final onPhone = RelayRunner(phone);
      await onTablet.update();
      await onPhone.update();
      await onTablet.sync!.syncOnce();
      await c.updateFamily(c.family.copyWith(graceReminderMinutes: 9));
      await onTablet.sync!.syncOnce();
      await onPhone.sync!.syncOnce();
      final onPhoneFamily = phone.compose(const FamilyData());
      expect(onPhoneFamily.graceReminderMinutes, 9);
      expect(onPhone.sync!.state.lastOk, isNotNull);
      await onTablet.sync!.syncOnce();
      final (url, state) = (await c.relayStatus())!;
      expect(url, '${endpoint}api.php');
      expect(state.seen.keys, containsAll(['tablet', 'phone']));

      // Use on the phone reaches the tablet.
      await phone.recordUsage([
        UsageSegment.device(
          childId: 'emma',
          deviceId: 'phone',
          appId: 'game',
          start: DateTime.now().subtract(const Duration(minutes: 5)),
          end: DateTime.now(),
        ),
      ]);
      await onPhone.sync!.syncOnce();
      await onTablet.sync!.syncOnce();
      expect(
        tablet.node.store.lastSeq(
          usageOrigin(scopedOrigin(phone.node.deviceId, 'emma')),
        ),
        1,
      );

      // Stopped for every device.
      await c.removeRelay();
      expect(tablet.relayUrl, isNull);
      await onTablet.update();
      expect(onTablet.sync, isNull);
      await onPhone.stop();
      c.leaveParentMode();
      c.dispose();
      await phone.close();
    });

    test('devices linked before take the key with the parent code', () async {
      final (c, tablet, phone) = await linked(oldFamily: true);
      expect(await tablet.contentKey(), isNull);
      expect(await c.setUpRelay(endpoint, await invite()), isNull);
      expect(await tablet.contentKey(), isNotNull);
      await overWifi(tablet, phone);
      expect(await phone.contentKey(), isNull);
      // No key: the phone cannot use the server yet.
      final onPhone = RelayRunner(phone);
      await onPhone.update();
      expect(onPhone.sync, isNull);
      expect(await phone.unlock('123456'), isNotNull);
      expect(await phone.contentKey(), await tablet.contentKey());
      await onPhone.update();
      expect(onPhone.sync, isNotNull);
      await onPhone.sync!.syncOnce();
      expect(onPhone.sync!.state.lastError, isNull);
      // A new code keeps the key sealed with it.
      await c.changeParentCode('654321');
      await overWifi(tablet, phone);
      final sealed = phone.node.replica[SyncKeys.family]!['content'] as Map;
      expect(
        await ParentVault.openBytes(
          Map<String, Object?>.from(sealed),
          '654321',
        ),
        await tablet.contentKey(),
      );
      // A device joining later gets it with the code it is asked for.
      final dirC = await Directory.systemTemp.createTemp('fst-c');
      addTearDown(() => dirC.delete(recursive: true));
      final laptopId = await DeviceIdentity.generate('laptop');
      final laptop = await FamilySync.join(
        store: LocalStore(dirC),
        identity: laptopId,
        welcome: Welcome(
          tablet.node.root,
          tablet.node.store.missingFor(const {}, limit: 1 << 30),
        ),
      );
      expect(tablet.node.root.contentKey, isNull);
      expect(await laptop.unlock('654321'), isNotNull);
      await laptop.commit();
      expect(await laptop.contentKey(), await tablet.contentKey());
      await laptop.close();
      await onPhone.stop();
      c.leaveParentMode();
      c.dispose();
      await phone.close();
    });
  }, skip: hasPhp ? null : 'no php');
}

bool _phpReady() {
  try {
    return Process.runSync('php', [
          '-r',
          "exit(function_exists('sodium_crypto_sign_verify_detached') && extension_loaded('pdo_sqlite') ? 0 : 1);",
        ]).exitCode ==
        0;
  } on Object {
    return false;
  }
}
