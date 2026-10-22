import 'package:family_screen_time/src/rule_history.dart';
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
        'games': {'minecraft'},
      },
    ),
  );

  UsageSegment games(int daysAgo, int minutes) => UsageSegment.device(
    childId: 'emma',
    deviceId: 'd',
    appId: 'minecraft',
    start: addDays(today, -daysAgo).add(const Duration(hours: 15)),
    end: addDays(today, -daysAgo).add(Duration(hours: 15, minutes: minutes)),
  );

  RuleHistory history(Rule rule, List<UsageSegment> usage) => ruleHistory(
    engine,
    FamilyState(rules: [rule], usage: usage),
    rule,
    childId: 'emma',
    now: now,
  )!;

  test('seven days by default, today first, with overruns and savings', () {
    const rule = Rule(
      id: 'r',
      childId: 'emma',
      appTarget: AppTarget.group('games'),
      dailyQuota: Duration(minutes: 30),
      rollover: RolloverPolicy(days: 1),
    );
    final h = history(rule, [games(2, 20), games(1, 50), games(0, 10)]);
    expect(h.period, 7);
    expect(h.days, hasLength(8));
    expect(h.days.first.day, today);
    expect(h.days[1].day, addDays(today, -1));
    // The 19th: 20 of 30, 10 saved; the 20th: 50 of 30 + 10 saved.
    expect(h.days[2].saved, min(10));
    expect(h.days[1].savingsUsed, min(10));
    expect(h.days[1].overrun, min(10));
    expect(h.totalOverrun, min(10));
    expect(h.savingsLeft, Duration.zero);
    expect(h.hardening, isNull);
    expect(h.firm, isFalse);
  });

  test('the firm limit sets the period and counts the days', () {
    const rule = Rule(
      id: 'r',
      childId: 'emma',
      appTarget: AppTarget.group('games'),
      dailyQuota: Duration(minutes: 30),
      grace: GracePolicy(
        length: Duration(minutes: 15),
        hardening: HardeningPolicy(
          threshold: Duration(minutes: 5),
          days: 2,
          window: 10,
        ),
      ),
    );
    final h = history(rule, [games(3, 33), games(1, 40)]);
    expect(h.period, 10);
    expect(h.days, hasLength(11));
    expect(h.firmCount, 1);
    expect(h.firm, isFalse);
    expect(h.firmNext, isTrue);
    expect(h.counts(h.days[1]), isTrue); // 10 min over
    expect(h.counts(h.days[3]), isFalse); // 3 min over, under the threshold

    final firm = history(rule, [games(3, 40), games(1, 40)]);
    expect(firm.firmCount, 2);
    expect(firm.firm, isTrue);
  });

  test('no history without a daily limit', () {
    const rule = Rule(
      id: 'r',
      childId: 'emma',
      weeklyQuota: Duration(hours: 5),
    );
    expect(
      ruleHistory(
        engine,
        const FamilyState(rules: [rule]),
        rule,
        childId: 'emma',
        now: now,
      ),
      isNull,
    );
  });
}
