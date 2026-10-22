import 'dart:io';

import 'package:family_screen_time/src/controller.dart';
import 'package:family_screen_time/src/store.dart';
import 'package:family_screen_time/src/ui/permissions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const channel = MethodChannel('org.familyscreentime/platform');

  testWidgets('protection is turned off here, after a confirmation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    var admin = true;
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          if (call.method == 'permissionStatus') return {'deviceAdmin': admin};
          if (call.method == 'disableDeviceAdmin') admin = false;
          return null;
        });
    final dir = Directory.systemTemp.createTempSync('fst');
    addTearDown(() => dir.deleteSync(recursive: true));
    final c = AppController(
      LocalStore(dir),
      const AppSettings(deviceId: 'd', language: 'fr', childId: 'emma'),
      const FamilyData(),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: PermissionsView(controller: c)),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Désactiver'), findsOneWidget);
    await tester.ensureVisible(find.text('Désactiver'));
    await tester.tap(find.text('Désactiver'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // The dialog's own button.
    expect(find.text('Désactiver'), findsNWidgets(2));
    await tester.tap(find.text('Désactiver').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(calls, contains('disableDeviceAdmin'));
    expect(find.text('Désactiver'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('accessibility is explained and agreed to before it opens', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final opened = <Object?>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'permissionStatus') return <String, bool>{};
          if (call.method == 'openPermissionSettings') {
            opened.add((call.arguments as Map<Object?, Object?>)['kind']);
          }
          return null;
        });
    final dir = Directory.systemTemp.createTempSync('fst');
    addTearDown(() => dir.deleteSync(recursive: true));
    final c = AppController(
      LocalStore(dir),
      const AppSettings(deviceId: 'd', language: 'fr', childId: 'emma'),
      const FamilyData(),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: PermissionsView(controller: c)),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Activer').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.textContaining('rien n\'est envoyé ni partagé'),
      findsOneWidget,
    );
    await tester.tap(find.text('Refuser'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(opened, isEmpty);

    await tester.tap(find.text('Activer').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Accepter et activer'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(opened, ['accessibility']);
    await tester.pumpWidget(const SizedBox());
  });
}
