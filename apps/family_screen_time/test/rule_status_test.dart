import 'package:family_screen_time/src/rule_status.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screentime_engine/screentime_engine.dart';

Duration min(int m) => Duration(minutes: m);

void main() {
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

  UsageSegment use(String app, DateTime start, int minutes) =>
      UsageSegment.device(
        childId: 'emma',
        deviceId: 'd',
        appId: app,
        start: start,
        end: start.add(min(minutes)),
      );

  final usage = [
    use('minecraft', addDays(today, -1).add(const Duration(hours: 15)), 20),
    use('minecraft', today.add(const Duration(hours: 14)), 12),
    use('roblox', today.add(const Duration(hours: 15)), 6),
    use('youtube', today.add(const Duration(hours: 16)), 30),
  ];

  test('time left of the day\'s total, with the apps used today', () {
    const rule = Rule(
      id: 'r',
      childId: 'emma',
      appTarget: AppTarget.group('games'),
      dailyQuota: Duration(minutes: 30),
      rollover: RolloverPolicy(days: 1),
    );
    final st = ruleStatus(
      engine,
      FamilyState(rules: const [rule], usage: usage),
      rule,
      childId: 'emma',
      now: now,
    );
    // 30 for today plus 10 saved yesterday.
    expect(st.dayTotal, min(40));
    expect(st.usedToday, min(18));
    expect(st.remaining, min(22));
    expect(st.savingsLeft, min(10));
    expect(st.limitedByPeriod, isFalse);
    expect(st.apps, [('minecraft', min(12)), ('roblox', min(6))]);
  });

  test('a tighter weekly limit is flagged', () {
    const rule = Rule(
      id: 'r',
      childId: 'emma',
      appTarget: AppTarget.group('games'),
      dailyQuota: Duration(minutes: 30),
      weeklyQuota: Duration(minutes: 45),
    );
    final st = ruleStatus(
      engine,
      FamilyState(rules: const [rule], usage: usage),
      rule,
      childId: 'emma',
      now: now,
    );
    expect(st.dayTotal, min(30));
    expect(st.remaining, min(7)); // 45 − 38 this week
    expect(st.limitedByPeriod, isTrue);
  });
}
