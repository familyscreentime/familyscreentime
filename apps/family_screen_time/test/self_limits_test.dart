import 'dart:io';

import 'package:family_screen_time/src/controller.dart';
import 'package:family_screen_time/src/self_limits.dart';
import 'package:family_screen_time/src/store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screentime_engine/screentime_engine.dart';

Duration min(int m) => Duration(minutes: m);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Wednesday 21 October 2026, 18:00.
  final now = DateTime(2026, 10, 21, 18);
  final today = dayOf(now);
  final engine = RuleEngine(
    const FamilyConfig(
      appGroups: {
        'games': {'minecraft', 'roblox'},
      },
    ),
  );

  UsageSegment use(String app, int daysAgo, int minutes) => UsageSegment.device(
    childId: 'emma',
    deviceId: 'd',
    appId: app,
    start: addDays(today, -daysAgo).add(const Duration(hours: 15)),
    end: addDays(today, -daysAgo).add(Duration(hours: 15, minutes: minutes)),
  );

  SelfLimitEvent event(
    int daysAgo,
    SelfLimitAction action, {
    String id = 'mc',
    int? minutes,
    int hour = 9,
  }) => SelfLimitEvent(
    at: addDays(today, -daysAgo).add(Duration(hours: hour)),
    ruleId: id,
    action: action,
    target: const AppTarget.app('minecraft'),
    daily: minutes == null ? null : min(minutes),
  );

  test('days kept and exceeded, changes and removals, as facts', () {
    final report = selfLimitReport(
      engine: engine,
      log: [
        event(5, SelfLimitAction.created, minutes: 15),
        event(3, SelfLimitAction.changed, minutes: 30, hour: 20),
        event(1, SelfLimitAction.removed, hour: 20),
      ],
      usage: [
        use('minecraft', 5, 10), // kept
        use('minecraft', 4, 15), // kept (exactly)
        use('minecraft', 3, 25), // 30 at the end of the day: kept
        use('minecraft', 2, 40), // exceeded
        use('roblox', 2, 60), // another app
        use('minecraft', 1, 5), // kept, removed in the evening
      ],
      childId: 'emma',
      now: now,
      period: 7,
    );
    final story = report.stories.single;
    expect(story.days, [
      DayOutcome.none,
      DayOutcome.kept,
      DayOutcome.kept,
      DayOutcome.kept,
      DayOutcome.exceeded,
      DayOutcome.kept,
      DayOutcome.none, // removed yesterday
    ]);
    expect(report.removals, 1);
    expect(report.keptShare, 0.8);
    expect(story.removedAt, isNotNull);
    expect(report.averageLifetime(now), const Duration(days: 4, hours: 11));
    // -5, 0, -5, +10, -25 over 5 days.
    expect(report.averageGap, min(-5));
  });

  test('today is ongoing; limits removed before the period are left out', () {
    final report = selfLimitReport(
      engine: engine,
      log: [
        event(20, SelfLimitAction.created, id: 'old', minutes: 10),
        event(15, SelfLimitAction.removed, id: 'old'),
        event(0, SelfLimitAction.created, minutes: 20, hour: 8),
      ],
      usage: const [],
      childId: 'emma',
      now: now,
      period: 7,
    );
    expect(report.stories.single.ruleId, 'mc');
    expect(report.stories.single.days.last, DayOutcome.ongoing);
    expect(report.keptShare, isNull);
    expect(report.removals, 0);
  });

  test(
    'the child\'s changes are logged and kept apart from the parent\'s rules',
    () async {
      final dir = Directory.systemTemp.createTempSync('fst');
      addTearDown(() => dir.deleteSync(recursive: true));
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('org.familyscreentime/platform'),
            (_) async => null,
          );
      final c = AppController(
        LocalStore(dir),
        const AppSettings(deviceId: 'd', language: 'fr', childId: 'emma'),
        const FamilyData(
          children: [Child(id: 'emma', name: 'Emma')],
          state: FamilyState(
            rules: [
              Rule(id: 'all', childId: 'emma', dailyQuota: Duration(hours: 2)),
            ],
          ),
        ),
      );
      await c.saveSelfLimit(
        const AppTarget.app('minecraft'),
        min(15),
        now: now,
      );
      final mine = c.selfLimits.single;
      expect(mine.setByChild, isTrue);
      expect(c.targetRules(const AppTarget.app('minecraft')), isEmpty);
      expect(c.parentRules.map((r) => r.id), ['all']);

      // It blocks like any rule.
      final d = RuleEngine(c.family.config).evaluate(
        FamilyState(
          rules: c.family.state.rules,
          usage: [use('minecraft', 0, 16)],
        ),
        childId: 'emma',
        deviceId: 'd',
        appId: 'minecraft',
        now: now,
      );
      expect(d.allowed, isFalse);
      expect(d.ruleId, mine.id);

      await c.saveSelfLimit(
        mine.appTarget,
        min(30),
        id: mine.id,
        now: now.add(const Duration(hours: 1)),
      );
      await c.removeSelfLimit(
        c.selfLimits.single,
        now: now.add(const Duration(hours: 2)),
      );
      expect(c.selfLimits, isEmpty);
      expect(c.family.selfLimitLog.map((e) => e.action), [
        SelfLimitAction.created,
        SelfLimitAction.changed,
        SelfLimitAction.removed,
      ]);
      final again = await LocalStore(dir).loadFamily();
      expect(again.selfLimitLog, hasLength(3));
      expect(again.selfLimitLog[1].daily, min(30));
    },
  );
}
