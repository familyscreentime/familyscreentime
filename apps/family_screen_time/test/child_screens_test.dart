import 'dart:io';

import 'package:family_screen_time/src/controller.dart';
import 'package:family_screen_time/src/store.dart';
import 'package:family_screen_time/src/ui/child_home.dart';
import 'package:family_screen_time/src/ui/child_settings.dart';
import 'package:family_screen_time/src/ui/rule_history_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screentime_engine/screentime_engine.dart';

void main() {
  const channel = MethodChannel('org.familyscreentime/platform');

  late Directory dir;
  late LocalStore store;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('fst');
    store = LocalStore(dir);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'permissionStatus') {
            return {
              for (final k in [
                'accessibility',
                'usageAccess',
                'overlay',
                'notifications',
                'battery',
                'deviceAdmin',
              ])
                k: true,
            };
          }
          if (call.method == 'appInfo') return <String, Object?>{};
          return null;
        });
  });

  tearDown(() => dir.deleteSync(recursive: true));

  AppController controller(List<Rule> rules) => AppController(
    store,
    const AppSettings(
      deviceId: 'd',
      language: 'fr',
      setupDone: true,
      childId: 'emma',
      historyImported: true,
    ),
    FamilyData(
      children: const [Child(id: 'emma', name: 'Emma')],
      config: const FamilyConfig(
        appGroups: {
          'games': {'minecraft'},
        },
      ),
      state: FamilyState(rules: rules),
      groupNames: const {'games': 'Jeux'},
    ),
  );

  /// Lets file reads finish, outside the test's fake clock.
  Future<void> settle(WidgetTester tester, Finder until) async {
    for (var i = 0; i < 1000 && until.evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump();
    }
  }

  Future<void> addGames(DateTime start, int minutes) => store.appendUsage(
    UsageSegment.device(
      childId: 'emma',
      deviceId: 'd',
      appId: 'minecraft',
      start: start,
      end: start.add(Duration(minutes: minutes)),
    ),
  );

  testWidgets('the child picks the warnings and the countdown', (tester) async {
    final c = controller(const []);
    await tester.pumpWidget(MaterialApp(home: ChildSettings(controller: c)));
    expect(c.settings.warningMinutes, [10, 5, 1]);

    await tester.tap(find.text('5 min'));
    await tester.pump();
    expect(c.settings.warningMinutes, [10, 1]);
    await tester.tap(find.text('30 min'));
    await tester.pump();
    expect(c.settings.warningMinutes, [30, 10, 1]);

    await tester.tap(find.text('Disque'));
    await tester.pump();
    expect(c.settings.overlay, 'disc');
  });

  testWidgets('the child picks which limits the countdown shows', (
    tester,
  ) async {
    final c = controller(const [
      Rule(
        id: 'games',
        childId: 'emma',
        appTarget: AppTarget.group('games'),
        dailyQuota: Duration(minutes: 30),
      ),
      Rule(id: 'all', childId: 'emma', dailyQuota: Duration(hours: 2)),
    ]);
    await tester.pumpWidget(MaterialApp(home: ChildSettings(controller: c)));
    // Only with a floating countdown.
    expect(find.text('Décompte pour'), findsNothing);
    await tester.tap(find.text('Disque'));
    await settle(tester, find.text('Décompte pour'));
    expect(find.text('Décompte pour'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Temps total d\'utilisation')).dx,
      lessThan(tester.getTopLeft(find.text('Jeux')).dx),
    );
    await tester.tap(find.text('Jeux'));
    await tester.pump();
    expect(c.settings.hiddenCountdowns, {'group:games'});
    await tester.tap(find.text('Jeux'));
    await tester.pump();
    expect(c.settings.hiddenCountdowns, isEmpty);
  });

  testWidgets('total screen time shows no app list, but its history', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final c = controller(const [
      Rule(
        id: 'games',
        childId: 'emma',
        appTarget: AppTarget.group('games'),
        dailyQuota: Duration(minutes: 30),
      ),
      Rule(id: 'all', childId: 'emma', dailyQuota: Duration(hours: 2)),
    ]);
    final now = DateTime.now();
    await tester.runAsync(
      () => addGames(now.subtract(const Duration(minutes: 1)), 0),
    );
    await tester.pumpWidget(MaterialApp(home: ChildHome(controller: c)));
    await settle(tester, find.text('Jeux'));

    expect(find.text('Temps total d\'utilisation'), findsOneWidget);
    // Total screen time comes first, whatever the order of the rules.
    expect(
      tester.getTopLeft(find.text('Temps total d\'utilisation')).dy,
      lessThan(tester.getTopLeft(find.text('Jeux')).dy),
    );
    // Only the games card lists its apps.
    expect(find.text('Rien utilisé aujourd\'hui.'), findsOneWidget);
    // Neither rule keeps unused time: no word of savings.
    expect(find.text('Dépassements'), findsNWidgets(2));
    // The countdown choice moved to the child's settings.
    expect(find.text('Décompte à l\'écran'), findsNothing);
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('time away and single apps by name on the cards', (tester) async {
    final now = DateTime.now();
    if (now.difference(dayOf(now)) < const Duration(minutes: 21)) {
      return markTestSkipped('too close to midnight');
    }
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'appInfo') {
            return {
              'com.roblox.client': {'label': 'Roblox'},
            };
          }
          if (call.method == 'permissionStatus') {
            return {
              for (final k in [
                'accessibility',
                'usageAccess',
                'overlay',
                'notifications',
                'battery',
                'deviceAdmin',
              ])
                k: true,
            };
          }
          return null;
        });
    final c = controller(const [
      Rule(
        id: 'games',
        childId: 'emma',
        appTarget: AppTarget.group('games'),
        dailyQuota: Duration(minutes: 30),
      ),
      Rule(id: 'all', childId: 'emma', dailyQuota: Duration(hours: 2)),
      Rule(
        id: 'roblox',
        childId: 'emma',
        appTarget: AppTarget.app('com.roblox.client'),
        dailyQuota: Duration(minutes: 20),
      ),
    ]);
    await tester.runAsync(
      () => c.addAwayTime(
        const AppTarget.group('games'),
        const Duration(minutes: 20),
      ),
    );
    await tester.pumpWidget(MaterialApp(home: ChildHome(controller: c)));
    await settle(tester, find.text('Roblox'));

    expect(find.text('Roblox'), findsOneWidget);
    expect(find.text('com.roblox.client'), findsNothing);
    // The games card lists the time away instead of "nothing used".
    expect(find.text('Rien utilisé aujourd\'hui.'), findsNothing);
    expect(find.text('Sur un autre appareil'), findsOneWidget);
    // The total counts it too.
    expect(find.text('20 min utilisées sur un autre appareil'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the history shows overruns and the firm limit', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    const rule = Rule(
      id: 'games',
      childId: 'emma',
      appTarget: AppTarget.group('games'),
      dailyQuota: Duration(minutes: 30),
      grace: GracePolicy(
        length: Duration(minutes: 15),
        hardening: HardeningPolicy(
          threshold: Duration(minutes: 5),
          days: 2,
          window: 3,
          deductOverruns: true,
        ),
      ),
    );
    final c = controller(const [rule]);
    final today = dayOf(DateTime.now());
    await tester.runAsync(
      () => addGames(addDays(today, -2).add(const Duration(hours: 15)), 40),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: RuleHistoryScreen(controller: c, rule: rule),
      ),
    );
    await settle(tester, find.text('Les 3 derniers jours'));

    expect(find.text('Jeux'), findsOneWidget);
    expect(find.text('Les 3 derniers jours'), findsOneWidget);
    expect(find.text('Aujourd\'hui'), findsOneWidget);
    expect(find.text('Dépassement : 10 min'), findsOneWidget);
    expect(find.text('40 min sur 30 min'), findsOneWidget);
    expect(
      find.text(
        'Jours avec plus de 5 min de dépassement sur les 3 derniers jours : '
        '1. La limite devient ferme à partir de 2.',
      ),
      findsOneWidget,
    );
    expect(
      find.text('Encore un jour comme ça et la limite devient ferme.'),
      findsOneWidget,
    );
  });

  testWidgets('the child sets a limit for themselves, without any code', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final c = controller(const []);
    await tester.pumpWidget(MaterialApp(home: ChildHome(controller: c)));
    await settle(tester, find.text('Me fixer une limite'));

    await tester.tap(find.text('Me fixer une limite'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Tes parents voient'), findsOneWidget);
    await tester.tap(find.text('Jeux'));
    await tester.tap(find.text('15 min'));
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.text('Enregistrer'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    await settle(tester, find.text('Jeux · ma limite'));

    final mine = c.selfLimits.single;
    expect(mine.appTarget, const AppTarget.group('games'));
    expect(mine.dailyQuota, const Duration(minutes: 15));
    expect(find.text('Jeux · ma limite'), findsOneWidget);
    expect(c.family.selfLimitLog, hasLength(1));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('outside the hours, the app itself asks for the parent code', (
    tester,
  ) async {
    final c = controller([
      Rule(id: 'all', childId: 'emma', schedule: WeeklySchedule(const {})),
    ]);
    await tester.pumpWidget(MaterialApp(home: ChildHome(controller: c)));
    await settle(tester, find.text('En dehors des horaires'));
    expect(find.text('En dehors des horaires'), findsOneWidget);
    expect(find.text('Mode parent'), findsOneWidget);
    expect(find.text('Me fixer une limite'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('extra time shows apart from the usual time', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    const games = Rule(
      id: 'games',
      childId: 'emma',
      appTarget: AppTarget.group('games'),
      dailyQuota: Duration(minutes: 30),
    );
    final c = controller(const [games]);
    await tester.runAsync(
      () => c.giveBonus(games, const Duration(minutes: 15)),
    );
    await tester.pumpWidget(MaterialApp(home: ChildHome(controller: c)));
    await settle(tester, find.text('+15 min de bonus'));
    expect(find.text('+15 min de bonus'), findsOneWidget);
    expect(find.text('30 min prévues'), findsOneWidget);
    expect(find.text('Reste aujourd\'hui : 45 min'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('0 min a day, and no word of savings when none are kept', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final c = controller(const [
      Rule(
        id: 'games',
        childId: 'emma',
        appTarget: AppTarget.group('games'),
        dailyQuota: Duration.zero,
      ),
    ]);
    await tester.pumpWidget(MaterialApp(home: ChildHome(controller: c)));
    await settle(tester, find.text('Seulement avec du temps en plus'));
    expect(find.text('Seulement avec du temps en plus'), findsOneWidget);
    expect(find.text('Dépassements'), findsOneWidget);
    expect(find.textContaining('pargne'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
