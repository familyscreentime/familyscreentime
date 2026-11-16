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
    // Twenty days back, day by day: the arrows stop at the first day kept.
    for (var i = 0; i < 20; i++) {
      await tester.tap(find.byIcon(Icons.chevron_left));
      await tester.pumpAndSettle();
    }
    expect(find.text('Total : 10 min'), findsOneWidget);
    final back = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.chevron_left),
    );
    expect(back.onPressed, isNull);

    // The month, with the average over its days gone by.
    await tester.tap(find.text('Mois'));
    await tester.pumpAndSettle();
    final old = addDays(today, -20);
    if (old.month == today.month) {
      expect(find.text('Total : 1 h 10'), findsOneWidget);
    } else {
      expect(find.text('Total : 1 h'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.chevron_left));
      await tester.pumpAndSettle();
      expect(find.text('Total : 10 min'), findsOneWidget);
    }
  });

  testWidgets('earlier days, weeks and months, by name', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => null);
    final dir = Directory.systemTemp.createTempSync('fst');
    addTearDown(() => dir.deleteSync(recursive: true));
    final store = LocalStore(dir);
    final today = dayOf(DateTime.now());
    final controller = AppController(
      store,
      const AppSettings(
        deviceId: 'd',
        language: 'fr',
        setupDone: true,
        childId: 'emma',
        historyImported: true,
      ),
      const FamilyData(
        children: [Child(id: 'emma', name: 'Emma')],
      ),
    );
    await tester.runAsync(() async {
      for (final (back, minutes) in [(0, 5), (1, 25), (70, 15)]) {
        final day = addDays(today, -back).add(const Duration(hours: 10));
        await store.appendUsage(
          UsageSegment.device(
            childId: 'emma',
            deviceId: 'd',
            appId: 'minecraft',
            start: day,
            end: day.add(Duration(minutes: minutes)),
          ),
        );
      }
    });
    await tester.pumpWidget(
      MaterialApp(home: UsageScreen(controller: controller)),
    );
    for (
      var i = 0;
      i < 1000 && find.text('minecraft').evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump();
    }
    expect(find.text('Aujourd\'hui'), findsWidgets);
    expect(find.text('Total : 5 min'), findsOneWidget);
    // Nothing after today.
    final next = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.chevron_right),
    );
    expect(next.onPressed, isNull);
    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();
    expect(find.text('Hier'), findsOneWidget);
    expect(find.text('Total : 25 min'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();
    final before = addDays(today, -2);
    const days = [
      'Lundi',
      'Mardi',
      'Mercredi',
      'Jeudi',
      'Vendredi',
      'Samedi',
      'Dimanche',
    ];
    final day = before.day.toString().padLeft(2, '0');
    final month = before.month.toString().padLeft(2, '0');
    expect(
      find.text('${days[before.weekday - 1]} $day/$month'),
      findsOneWidget,
    );

    await tester.tap(find.text('Semaine'));
    await tester.pumpAndSettle();
    expect(find.text('Cette semaine'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();
    expect(find.text('Semaine dernière'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();
    expect(
      find.textContaining(RegExp(r'^Du \d\d/\d\d au \d\d/\d\d$')),
      findsOneWidget,
    );

    // Seventy days back: kept, so two or three months back.
    await tester.tap(find.text('Mois'));
    await tester.pumpAndSettle();
    const months = [
      'Janvier',
      'Février',
      'Mars',
      'Avril',
      'Mai',
      'Juin',
      'Juillet',
      'Août',
      'Septembre',
      'Octobre',
      'Novembre',
      'Décembre',
    ];
    expect(
      find.text('${months[today.month - 1]} ${today.year}'),
      findsOneWidget,
    );
    final old = addDays(today, -70);
    final steps = (today.year - old.year) * 12 + today.month - old.month;
    for (var i = 0; i < steps; i++) {
      await tester.tap(find.byIcon(Icons.chevron_left));
      await tester.pumpAndSettle();
    }
    expect(find.text('${months[old.month - 1]} ${old.year}'), findsOneWidget);
    expect(find.text('Total : 15 min'), findsOneWidget);
    final back = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.chevron_left),
    );
    expect(back.onPressed, isNull);
  });

  testWidgets('with several devices, each one\'s time', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'deviceName') return 'Tablette';
          return null;
        });
    final dir = Directory.systemTemp.createTempSync('fst');
    addTearDown(() => dir.deleteSync(recursive: true));
    final store = LocalStore(dir);
    final today = dayOf(DateTime.now());
    final controller = AppController(
      store,
      const AppSettings(
        deviceId: 'd',
        language: 'fr',
        setupDone: true,
        childId: 'emma',
        historyImported: true,
      ),
      const FamilyData(
        children: [Child(id: 'emma', name: 'Emma')],
      ),
    );
    await tester.runAsync(() async {
      for (final (device, app, minutes) in [
        ('d', 'minecraft', 40),
        ('phone1234567', 'youtube', 15),
      ]) {
        await store.appendUsage(
          UsageSegment.device(
            childId: 'emma',
            deviceId: device,
            appId: app,
            start: today,
            end: today.add(Duration(minutes: minutes)),
          ),
        );
      }
      // A device unlinked since, used three days ago, as this one.
      final before = addDays(today, -3);
      for (final device in ['old12345678', 'd']) {
        await store.appendUsage(
          UsageSegment.device(
            childId: 'emma',
            deviceId: device,
            appId: 'minecraft',
            start: before,
            end: before.add(const Duration(minutes: 30)),
          ),
        );
      }
    });
    await tester.pumpWidget(
      MaterialApp(home: UsageScreen(controller: controller, parent: true)),
    );
    for (var i = 0; i < 1000 && find.text('youtube').evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump();
    }
    expect(find.text('Total : 55 min'), findsOneWidget);
    expect(find.text('Tous les appareils · 55 min'), findsOneWidget);
    expect(find.text('Tablette · 40 min'), findsOneWidget);
    expect(find.text('phone123 · 15 min'), findsOneWidget);
    // Not used today: no chip at 0 min.
    expect(find.textContaining('old12345'), findsNothing);
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byIcon(Icons.chevron_left));
      await tester.pumpAndSettle();
    }
    expect(find.text('old12345 · 30 min'), findsOneWidget);
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pumpAndSettle();
    }
    await tester.ensureVisible(find.text('phone123 · 15 min'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('phone123 · 15 min'));
    await tester.pumpAndSettle();
    expect(find.text('Total : 15 min'), findsOneWidget);
    expect(find.text('minecraft'), findsNothing);
    expect(find.text('youtube'), findsOneWidget);
  });
}
