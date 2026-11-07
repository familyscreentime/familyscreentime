import 'dart:io';

import 'package:family_screen_time/src/controller.dart';
import 'package:family_screen_time/src/store.dart';
import 'package:family_screen_time/src/ui/eye_break_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screentime_engine/screentime_engine.dart';

void main() {
  late Directory dir;
  late AppController c;

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('org.familyscreentime/platform'),
          (_) async => null,
        );
    dir = Directory.systemTemp.createTempSync('fst');
    c = AppController(
      LocalStore(dir),
      const AppSettings(deviceId: 'd', language: 'fr', childId: 'emma'),
      const FamilyData(
        children: [Child(id: 'emma', name: 'Emma')],
      ),
    );
  });

  tearDown(() => dir.deleteSync(recursive: true));

  testWidgets('on by default; the parent sets the put-offs', (tester) async {
    await tester.pumpWidget(MaterialApp(home: EyeBreakScreen(controller: c)));
    expect(find.text('20 min'), findsOneWidget);
    expect(find.text('20 s'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.remove));
    await tester.pump();
    expect(c.child!.eyeBreak.snoozes, 2);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('turned off, the settings are kept', (tester) async {
    await tester.pumpWidget(MaterialApp(home: EyeBreakScreen(controller: c)));
    await tester.tap(find.byType(Switch).first);
    await tester.pump();
    expect(c.child!.eyeBreak, const EyeBreakPolicy(enabled: false));
    expect(find.text('20 min'), findsNothing);
    expect(eyeBreakSummary(c.s, c.child!.eyeBreak), 'Désactivées');
  });
}
