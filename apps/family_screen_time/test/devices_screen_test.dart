import 'dart:io';

import 'package:family_screen_time/src/controller.dart';
import 'package:family_screen_time/src/store.dart';
import 'package:family_screen_time/src/sync/family_sync.dart';
import 'package:family_screen_time/src/ui/devices_screen.dart';
import 'package:family_screen_time/src/ui/parent_device_home.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screentime_sync/screentime_sync.dart';

void main() {
  late Directory dir;
  late LocalStore store;
  const settings = AppSettings(
    deviceId: 'tablet',
    language: 'fr',
    setupDone: true,
    childId: 'emma',
  );
  const family = FamilyData(
    children: [Child(id: 'emma', name: 'Emma')],
  );

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('fst-devices');
    store = LocalStore(dir);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('org.familyscreentime/platform'),
          (call) async => call.method == 'systemPackages'
              ? <String, Object?>{
                  'self': 'org.familyscreentime',
                  'launchers': [],
                }
              : null,
        );
  });
  tearDown(() => dir.delete(recursive: true));

  testWidgets('the family\'s devices, with their contact', (tester) async {
    late FamilySync log;
    await tester.runAsync(() async {
      final (created, key) = await FamilySync.create(
        store: store,
        settings: settings,
        family: family,
        parentCode: '123456',
        deviceName: 'Tablette',
      );
      log = created;
      final phone = await DeviceIdentity.generate('phone');
      await log.node.emit([
        EventDraft.put(SyncKeys.device('phone'), {
          'name': 'Téléphone',
          'role': 'child',
          'childId': 'emma',
          'signKey': phone.signing.publicKey,
        }),
      ], parentKey: key);
      await log.savePeers([
        PeerState('phone', DateTime.now(), connected: true),
      ]);
    });
    final c = AppController(store, settings, family);
    await tester.runAsync(c.openSync);
    await tester.pumpWidget(
      MaterialApp(
        home: DevicesScreen(
          controller: c,
          directory: () => MemoryLanDirectory.network(1).single,
        ),
      ),
    );
    for (var i = 0; i < 100 && find.text('Téléphone').evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(find.text('Tablette'), findsOneWidget);
    expect(find.text('Appareil de Emma · Cet appareil'), findsOneWidget);
    expect(find.textContaining('Appareil de Emma · Connecté'), findsOneWidget);
    expect(find.text('Relier un appareil'), findsOneWidget);
    expect(
      find.text('Détacher cet appareil', skipOffstage: false),
      findsOneWidget,
    );
    // The phone has not received the family yet: said under the list.
    expect(
      find.textContaining('Pas encore transmis à : Téléphone'),
      findsOneWidget,
    );
    // Each can be renamed; only the other device can be removed from here.
    await tester.tap(
      find.descendant(
        of: find.ancestor(
          of: find.text('Tablette'),
          matching: find.byType(ListTile),
        ),
        matching: find.byType(PopupMenuButton<String>),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Renommer'), findsOneWidget);
    expect(find.text('Retirer'), findsNothing);
    await tester.tapAt(Offset.zero);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.ancestor(
          of: find.text('Téléphone'),
          matching: find.byType(ListTile),
        ),
        matching: find.byType(PopupMenuButton<String>),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Retirer'), findsOneWidget);
    await tester.tapAt(Offset.zero);
    await tester.pumpAndSettle();
    await tester.runAsync(() => log.close());
  });

  test('a code changed on another device opens parent mode here', () async {
    final c = AppController(store, settings, family);
    final (log, key) = await FamilySync.create(
      store: store,
      settings: settings,
      family: family,
      parentCode: '123456',
      deviceName: 'Tablette',
    );
    await log.changeCode(key, '654321');
    await c.openSync();
    expect(await c.codeOpensFamily('000000'), isFalse);
    expect(await c.codeOpensFamily('654321'), isTrue);
    expect(c.settings.pinHash, isNotNull);
  });

  testWidgets('a parent\'s device: children behind the parent code', (
    tester,
  ) async {
    final c = AppController(
      store,
      const AppSettings(
        deviceId: 'papa',
        language: 'fr',
        setupDone: true,
        parentDevice: true,
      ),
      const FamilyData(
        children: [
          Child(id: 'emma', name: 'Emma'),
          Child(id: 'lucas', name: 'Lucas'),
        ],
      ),
    );
    await tester.pumpWidget(MaterialApp(home: ParentDeviceHome(controller: c)));
    await tester.pump();
    // Locked: the name of the app and the unlock button, nothing else.
    expect(find.text('Family Screen Time'), findsOneWidget);
    expect(find.text('Déverrouiller'), findsOneWidget);
    expect(find.text('Emma'), findsNothing);
    expect(find.text('Appareils reliés'), findsNothing);
    // No child of its own: the first one is shown until another is chosen.
    expect(c.childId, 'emma');
    c.enterParentMode();
    await tester.pump();
    expect(find.text('Emma'), findsOneWidget);
    expect(find.text('Lucas'), findsOneWidget);
    expect(find.text('Appareils reliés'), findsOneWidget);
    expect(find.text('Paramètres de la famille'), findsOneWidget);
    c.selectChild('lucas');
    expect(c.childId, 'lucas');
    expect(c.child?.name, 'Lucas');
    c.leaveParentMode();
    await tester.pump();
    expect(find.text('Lucas'), findsNothing);
    c.dispose();
  });
}
