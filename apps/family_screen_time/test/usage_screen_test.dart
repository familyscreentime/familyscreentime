import 'dart:io';

import 'package:family_screen_time/src/controller.dart';
import 'package:family_screen_time/src/store.dart';
import 'package:family_screen_time/src/ui/usage_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screentime_engine/screentime_engine.dart';

void main() {
  const channel = MethodChannel('org.familyscreentime/platform');

  testWidgets('lists apps by time with their flags, in French', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'appInfo') {
            return {
              'com.zhiliaoapp.musically': {'label': 'TikTok'},
            };
          }
          return null;
        });

    final dir = Directory.systemTemp.createTempSync('fst');
    addTearDown(() => dir.deleteSync(recursive: true));
    final store = LocalStore(dir);
    final now = DateTime.now();
    final today = dayOf(now);
    final controller = AppController(
      store,
      const AppSettings(
        deviceId: 'd',
        language: 'fr',
        setupDone: true,
        childId: 'emma',
        // The import itself is covered by controller_test.dart.
        historyImported: true,
      ),
      FamilyData(
        children: const [Child(id: 'emma', name: 'Emma')],
        config: const FamilyConfig(
          appGroups: {
            'games': {'minecraft'},
          },
          neverBlocked: {'launcher'},
        ),
        state: const FamilyState(
          rules: [
            Rule(
              id: 'r',
              childId: 'emma',
              appTarget: AppTarget.group('games'),
              dailyQuota: Duration(minutes: 60),
            ),
          ],
        ),
        groupNames: const {'games': 'Jeux'},
      ),
    );

    await tester.runAsync(() async {
      Future<void> add(String app, DateTime start, int minutes) =>
          store.appendUsage(
            UsageSegment.device(
              childId: 'emma',
              deviceId: 'd',
              appId: app,
              start: start,
              end: start.add(Duration(minutes: minutes)),
            ),
          );
      await add(
        'minecraft',
        addDays(today, -20).add(const Duration(hours: 9)),
        10,
      );
      await add('minecraft', today, 20); // 00:00–00:20: at night
      await add(
        'com.zhiliaoapp.musically',
        today.add(const Duration(minutes: 30)),
        40,
      );
      await add('launcher', today.add(const Duration(minutes: 25)), 5);
    });

    await tester.pumpWidget(
      MaterialApp(home: UsageScreen(controller: controller, parent: true)),
    );
    // File reads complete outside the test's fake clock.
    for (var i = 0; i < 1000 && find.text('TikTok').evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump();
    }

    expect(find.text('Total : 1 h'), findsOneWidget);
    expect(find.text('TikTok'), findsOneWidget);
    expect(find.text('minecraft'), findsOneWidget);
    expect(find.text('launcher'), findsNothing);
    // TikTok is new, unlimited and used at night; Minecraft is limited.
    expect(find.text('Nouvelle'), findsOneWidget);
    expect(find.text('Sans limite'), findsOneWidget);
    expect(find.text('La nuit'), findsNWidgets(2));

    // The group label leads to the group: its rules and its apps.
    expect(find.text('Jeux'), findsOneWidget);
    await tester.tap(find.text('Jeux'));
    await tester.pumpAndSettle();
    expect(find.text('1 h par jour'), findsOneWidget);
    expect(find.text('Applis du groupe'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    await tester.tap(find.text('minecraft'));
    await tester.pumpAndSettle();
    expect(find.text('Limitée par : Jeux'), findsOneWidget);
    expect(find.text('Choisir les groupes'), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('30 jours'));
    await tester.pumpAndSettle();
    expect(find.text('Total : 1 h 10'), findsOneWidget);
  });
}
