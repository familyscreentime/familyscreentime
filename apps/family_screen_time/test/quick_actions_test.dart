import 'dart:io';

import 'package:family_screen_time/src/controller.dart';
import 'package:family_screen_time/src/store.dart';
import 'package:family_screen_time/src/ui/quick_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screentime_engine/screentime_engine.dart';

void main() {
  const channel = MethodChannel('org.familyscreentime/platform');
  // Wednesday 21 October 2026, 14:00.
  final now = DateTime(2026, 10, 21, 14);

  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('fst');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => null);
  });

  tearDown(() => dir.deleteSync(recursive: true));

  const games = Rule(
    id: 'games',
    childId: 'emma',
    appTarget: AppTarget.group('games'),
    dailyQuota: Duration(minutes: 30),
  );

  AppController controller({FamilyState state = const FamilyState()}) =>
      AppController(
        LocalStore(dir),
        const AppSettings(deviceId: 'd', language: 'fr', childId: 'emma'),
        FamilyData(
          children: const [Child(id: 'emma', name: 'Emma')],
          config: const FamilyConfig(
            appGroups: {
              'games': {'minecraft'},
            },
          ),
          state: FamilyState(
            rules: const [games],
            bonuses: state.bonuses,
            dayUnlocks: state.dayUnlocks,
            temporaryBlocks: state.temporaryBlocks,
          ),
          groupNames: const {'games': 'Jeux'},
        ),
      );

  Decision check(AppController c, DateTime t, {String app = 'minecraft'}) =>
      RuleEngine(c.family.config).evaluate(
        c.family.state,
        childId: 'emma',
        deviceId: 'd',
        appId: app,
        now: t,
      );

  group('controller', () {
    test(
      'a bonus raises the limit until midnight, and can be taken back',
      () async {
        final c = controller();
        await c.giveBonus(games, const Duration(minutes: 15), now: now);
        expect(check(c, now).remaining, const Duration(minutes: 45));
        final bonus = c.activeBonuses(now).single;
        expect(bonus.validUntil, DateTime(2026, 10, 22));
        expect(c.activeBonuses(DateTime(2026, 10, 22, 8)), isEmpty);
        await c.removeBonus(bonus.id);
        expect(check(c, now).remaining, const Duration(minutes: 30));
      },
    );

    test('restrictions are lifted for the day, then restored', () async {
      final c = controller();
      await c.setDayUnlocked(true, now: now);
      expect(c.dayUnlocked(now), isTrue);
      expect(check(c, now).reason, Reason.dayUnlocked);
      expect(c.dayUnlocked(DateTime(2026, 10, 22, 8)), isFalse);
      await c.setDayUnlocked(false, now: now);
      expect(check(c, now).reason, Reason.withinLimits);
    });

    test('a block holds until its end or until lifted', () async {
      final c = controller();
      await c.blockNow(
        const AppTarget.group('games'),
        now.add(const Duration(minutes: 30)),
        now: now,
      );
      final during = check(c, now.add(const Duration(minutes: 10)));
      expect(during.allowed, isFalse);
      expect(during.reason, Reason.temporaryBlock);
      expect(check(c, now, app: 'youtube').allowed, isTrue);
      expect(check(c, now.add(const Duration(minutes: 31))).allowed, isTrue);

      await c.blockNow(const AppTarget.all(), null, now: now);
      final open = c.activeBlocks(now).singleWhere((b) => b.until == null);
      expect(
        check(c, now.add(const Duration(hours: 5)), app: 'youtube').allowed,
        isFalse,
      );
      await c.liftBlock(open.id, now: now.add(const Duration(hours: 1)));
      expect(
        check(c, now.add(const Duration(hours: 2)), app: 'youtube').allowed,
        isTrue,
      );
      // Lifted, it stays in the history.
      expect(c.family.state.temporaryBlocks, hasLength(2));
    });

    test(
      'time away from the devices counts for its group and the total',
      () async {
        final c = AppController(
          LocalStore(dir),
          const AppSettings(deviceId: 'd', language: 'fr', childId: 'emma'),
          const FamilyData(
            children: [Child(id: 'emma', name: 'Emma')],
            config: FamilyConfig(
              appGroups: {
                'games': {'minecraft'},
              },
            ),
            state: FamilyState(
              rules: [
                games,
                Rule(
                  id: 'all',
                  childId: 'emma',
                  dailyQuota: Duration(hours: 2),
                ),
              ],
            ),
            groupNames: {'games': 'Jeux'},
          ),
        );
        await c.addAwayTime(
          const AppTarget.group('games'),
          const Duration(minutes: 20),
          now: now,
        );
        Duration left(String app) {
          final d = RuleEngine(c.family.config).evaluate(
            FamilyState(rules: c.family.state.rules, usage: c.family.injected),
            childId: 'emma',
            deviceId: 'd',
            appId: app,
            now: now,
          );
          return d.remaining!;
        }

        expect(left('minecraft'), const Duration(minutes: 10));
        expect(left('youtube'), const Duration(minutes: 100));
        expect(c.injectedToday(now), hasLength(1));
        expect(
          (await c.recentUsage()).where((u) => u.injectedTarget != null),
          hasLength(1),
        );

        // Saved with the family, read back.
        final again = await LocalStore(dir).loadFamily();
        expect(again.injected.single.length, const Duration(minutes: 20));

        await c.removeAwayTime(c.injectedToday(now).single);
        expect(c.family.injected, isEmpty);
      },
    );

    test('a break the child takes blocks everything until its end', () async {
      final c = controller();
      await c.startPause(const Duration(minutes: 15), now: now);
      final pause = c.activeBlocks(now).single;
      expect(pause.voluntary, isTrue);
      expect(pause.until, now.add(const Duration(minutes: 15)));
      expect(
        check(c, now.add(const Duration(minutes: 5)), app: 'youtube').allowed,
        isFalse,
      );
      expect(
        check(c, now.add(const Duration(minutes: 16)), app: 'youtube').allowed,
        isTrue,
      );
      await c.liftBlock(pause.id, now: now.add(const Duration(minutes: 1)));
      expect(c.family.state.temporaryBlocks.single.voluntary, isTrue);
    });

    test('durations offered in one tap are set per child', () async {
      final c = controller();
      expect(c.presets, [15, 30, 45, 60]);
      await c.setPresets([45, 15, 25, 35, 0]);
      expect(c.presets, [15, 25, 35, 45]);
      final again = await LocalStore(dir).loadFamily();
      expect(again.child('emma')!.presets, [15, 25, 35, 45]);
    });

    test('hours opened early until the end of the next range', () async {
      final scheduled = Rule(
        id: 'games',
        childId: 'emma',
        appTarget: const AppTarget.group('games'),
        dailyQuota: const Duration(minutes: 30),
        schedule: WeeklySchedule({
          for (var d = DateTime.monday; d <= DateTime.sunday; d++)
            d: [TimeRange.hm(10, 0, 12, 0)],
        }),
      );
      final c = AppController(
        LocalStore(dir),
        const AppSettings(deviceId: 'd', language: 'fr', childId: 'emma'),
        FamilyData(
          children: const [Child(id: 'emma', name: 'Emma')],
          config: const FamilyConfig(
            appGroups: {
              'games': {'minecraft'},
            },
          ),
          state: FamilyState(rules: [scheduled]),
          groupNames: const {'games': 'Jeux'},
        ),
      );
      final early = DateTime(2026, 10, 21, 9, 20);
      final (rule, end) = c.openableEarly(early).single;
      expect(rule.id, 'games');
      expect(end, DateTime(2026, 10, 21, 12));
      // Nothing to open after the last range of the day.
      expect(c.openableEarly(DateTime(2026, 10, 21, 13)), isEmpty);

      await c.openHoursEarly(rule, end, now: early);
      expect(check(c, DateTime(2026, 10, 21, 9, 30)).allowed, isTrue);
      expect(check(c, DateTime(2026, 10, 21, 12, 1)).allowed, isFalse);
      expect(c.openableEarly(early.add(const Duration(minutes: 5))), isEmpty);
      final u = c.hoursOpenedEarly(early).single;
      await c.closeHoursEarly(u.id, now: DateTime(2026, 10, 21, 9, 40));
      expect(check(c, DateTime(2026, 10, 21, 9, 45)).allowed, isFalse);
    });

    test('always available apps: at any hour, or within the hours', () async {
      final c = controller();
      await c.setAccessible('dialer', anyTime: true);
      await c.setAccessible('sms', anyTime: false);
      expect(c.family.config.alwaysAllowed, {'dialer'});
      expect(c.family.config.allowedInHours, {'sms'});
      await c.setAccessible('sms', anyTime: true);
      expect(c.family.config.alwaysAllowed, {'dialer', 'sms'});
      expect(c.family.config.allowedInHours, isEmpty);
      await c.removeAccessible('dialer');
      expect(c.family.config.alwaysAllowed, {'sms'});
      final again = await LocalStore(dir).loadFamily();
      expect(again.config.alwaysAllowed, {'sms'});
    });

    test('old actions are dropped when new ones are added', () async {
      final c = controller(
        state: FamilyState(
          bonuses: [
            Bonus.forRule(
              id: 'old',
              childId: 'emma',
              ruleId: 'games',
              amount: const Duration(minutes: 10),
              grantedAt: DateTime(2026, 8, 1, 10),
              validUntil: DateTime(2026, 8, 2),
            ),
          ],
          dayUnlocks: [
            DayUnlock(id: 'old', childId: 'emma', day: DateTime(2026, 8, 1)),
          ],
        ),
      );
      await c.giveBonus(games, const Duration(minutes: 5), now: now);
      await c.setDayUnlocked(true, now: now);
      expect(c.family.state.bonuses.map((b) => b.id), isNot(contains('old')));
      expect(
        c.family.state.dayUnlocks.map((u) => u.id),
        isNot(contains('old')),
      );
    });
  });

  testWidgets('the parent gives time, lifts and blocks from one place', (
    tester,
  ) async {
    /// Lets file writes finish, outside the test's fake clock.
    Future<void> settle() async {
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
    }

    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final c = controller();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: QuickActions(controller: c, clock: () => now),
          ),
        ),
      ),
    );

    // Extra time.
    await tester.tap(find.text('Donner du temps en plus'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('30 min'));
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.text('Donner 30 min'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    await settle();
    expect(c.activeBonuses(now).single.amount, const Duration(minutes: 30));
    expect(find.text('+30 min pour Jeux, jusqu\'à minuit'), findsOneWidget);

    // Lifting restrictions for the day.
    await tester.runAsync(() async {
      await tester.tap(find.text('Lever les restrictions aujourd\'hui'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    expect(c.dayUnlocked(now), isTrue);

    // Blocking the games until further notice.
    await tester.tap(find.text('Bloquer maintenant'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Jeux'));
    await tester.tap(find.text('Jusqu\'à nouvel ordre'));
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.text('Bloquer'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    await settle();
    expect(find.text('Jeux : bloqué jusqu\'à nouvel ordre'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.text('Lever'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await settle();
    expect(find.text('Jeux : bloqué jusqu\'à nouvel ordre'), findsNothing);
    expect(c.activeBlocks(now), isEmpty);
  });
}
