import 'package:screentime_engine/screentime_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  // Total screen time: 2 hours a day, from 9:00 to 18:00.
  final hours = WeeklySchedule({
    for (var d = DateTime.monday; d <= DateTime.sunday; d++)
      d: [TimeRange.hm(9, 0, 18, 0)],
  });
  final total = Rule(
    id: 'all',
    childId: child,
    dailyQuota: const Duration(hours: 2),
    schedule: hours,
  );
  // Hours only, no time limit.
  final evening = Rule(
    id: 'h',
    childId: child,
    appTarget: const AppTarget.group('games'),
    schedule: hours,
  );

  Bonus bonus(String rule, DateTime at, int minutes) => Bonus.forRule(
    id: 'b-$rule-${at.hour}',
    childId: child,
    ruleId: rule,
    amount: min(minutes),
    grantedAt: at,
    validUntil: addDays(dayOf(at), 1),
  );

  FamilyState state(
    List<Rule> rules,
    List<Bonus> bonuses, [
    List<UsageSegment> usage = const [],
  ]) => FamilyState(
    rules: rules,
    bonuses: bonuses,
    usage: [use(tablet, 'youtube', at(5, 10), 60), ...usage],
  );

  test('given outside the hours: open for that time, then closed', () {
    final s = state([total], [bonus('all', at(5, 20), 30)]);
    final d = check(s, at(5, 20), app: 'youtube');
    expect(d.allowed, isTrue);
    expect(d.remaining, min(30));
    // Twenty minutes later, ten are left.
    final later = state([total], [bonus('all', at(5, 20), 30)], [
      use(tablet, 'youtube', at(5, 20), 20),
    ]);
    expect(check(later, at(5, 20, 20), app: 'youtube').remaining, min(10));
    // Used up: outside the hours again.
    final done = state([total], [bonus('all', at(5, 20), 30)], [
      use(tablet, 'youtube', at(5, 20), 30),
    ]);
    final closed = check(done, at(5, 20, 30), app: 'youtube');
    expect(closed.allowed, isFalse);
    expect(closed.reason, Reason.outsideSchedule);
  });

  test('given within the hours: more time then, not later', () {
    final s = state([total], [bonus('all', at(5, 14), 30)]);
    expect(check(s, at(5, 20), app: 'youtube').allowed, isFalse);
  });

  test('a limit of hours only opens for the time given too', () {
    final s = state([evening], [bonus('h', at(5, 19), 15)]);
    final d = check(s, at(5, 19, 5));
    expect(d.allowed, isTrue);
    expect(d.remaining, min(15));
    // Another limit still closed blocks.
    final both = state([evening, total], [bonus('h', at(5, 19), 15)]);
    expect(check(both, at(5, 19, 5)).allowed, isFalse);
  });

  test('the day\'s time limit still applies', () {
    // Two hours used already: thirty minutes more, granted at 20:00,
    // leave thirty minutes in all.
    final s = state([total], [bonus('all', at(5, 20), 30)], [
      use(tablet, 'youtube', at(5, 14), 60),
    ]);
    final d = check(s, at(5, 20), app: 'youtube');
    expect(d.allowed, isTrue);
    expect(d.remaining, min(30));
    // A bonus from yesterday evening opens nothing today.
    final old = state([total], [bonus('all', at(4, 20), 30)]);
    expect(check(old, at(5, 20), app: 'youtube').allowed, isFalse);
  });
}
