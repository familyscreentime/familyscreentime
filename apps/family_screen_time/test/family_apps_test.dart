import 'dart:io';

import 'package:family_screen_time/src/controller.dart';
import 'package:family_screen_time/src/store.dart';
import 'package:family_screen_time/src/sync/family_sync.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screentime_sync/screentime_sync.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('on a parent\'s phone, groups list the child\'s apps', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('org.familyscreentime/platform'),
          (call) async => call.method == 'launcherApps'
              ? [
                  {'package': 'com.bank', 'label': 'Banque'},
                ]
              : null,
        );
    final dir = await Directory.systemTemp.createTemp('fst-apps');
    addTearDown(() => dir.delete(recursive: true));
    final store = LocalStore(dir);
    const settings = AppSettings(
      deviceId: 'papa',
      language: 'fr',
      setupDone: true,
      parentDevice: true,
    );
    const family = FamilyData(
      children: [
        Child(id: 'emma', name: 'Emma'),
        Child(id: 'lucas', name: 'Lucas'),
      ],
    );
    final (log, key) = await FamilySync.create(
      store: store,
      settings: settings,
      family: family,
      parentCode: '123456',
      deviceName: 'Papa',
    );
    for (final (device, child, app) in [
      ('tablet', 'emma', 'minecraft'),
      ('pc', 'lucas', 'roblox'),
    ]) {
      await log.node.emit([
        EventDraft.put(SyncKeys.device(device), {
          'name': device,
          'role': 'child',
          'childId': child,
          'signKey': (await DeviceIdentity.generate(device)).signing.publicKey,
        }),
        EventDraft.put('${appsOf(device)}$app', {'label': app}),
      ], parentKey: key);
    }
    await log.close();
    final c = AppController(store, settings, family);
    await c.openSync();
    c.selectChild('emma');
    expect((await c.familyApps()).map((a) => a.package), ['minecraft']);
    c.selectChild('lucas');
    expect((await c.familyApps()).map((a) => a.package), ['roblox']);
    c.dispose();
  });
}
