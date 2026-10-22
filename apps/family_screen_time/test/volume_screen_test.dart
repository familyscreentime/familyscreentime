import 'dart:io';

import 'package:family_screen_time/src/controller.dart';
import 'package:family_screen_time/src/store.dart';
import 'package:family_screen_time/src/ui/volume_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the parent caps the volume with headphones', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('org.familyscreentime/platform'),
          (_) async => null,
        );
    final dir = Directory.systemTemp.createTempSync('fst');
    addTearDown(() => dir.deleteSync(recursive: true));
    final c = AppController(
      LocalStore(dir),
      const AppSettings(deviceId: 'd', language: 'fr', childId: 'emma'),
      const FamilyData(
        children: [Child(id: 'emma', name: 'Emma')],
      ),
    );
    await tester.pumpWidget(MaterialApp(home: VolumeScreen(controller: c)));
    expect(find.text('Sans limite'), findsNWidgets(2));
    expect(find.byType(Slider), findsNothing);

    await tester.tap(find.text('Avec des écouteurs'));
    await tester.pump();
    expect(find.text('60 %'), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);
    expect(c.child!.volumeHeadphones, 60);
    expect(c.child!.volumeSpeaker, isNull);
  });
}
