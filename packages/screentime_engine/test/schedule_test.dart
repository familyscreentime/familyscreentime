import 'package:screentime_engine/screentime_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  // 8:00–12:00 and 14:00–20:00: the lunch break is a gap in the schedule.
  final schedule = WeeklySchedule.everyDay([
    TimeRange.hm(8, 0, 12, 0),
    TimeRange.hm(14, 0, 20, 0),
  ]);
  final state = FamilyState(
    rules: [Rule(id: 'h', childId: child, schedule: schedule)],
  );

  group('Schedules', () {
    test('outside a range: blocked until the next range starts', () {
      final lunch = check(state, at(5, 13));
      expect(lunch.allowed, isFalse);
      expect(lunch.reason, Reason.outsideSchedule);
      expect(lunch.until, at(5, 14));
      expect(check(state, at(5, 7)).until, at(5, 8));
      expect(check(state, at(5, 21)).until, at(6, 8));
    });

    test('the end of a range is excluded', () {
      expect(check(state, at(5, 12)).reason, Reason.outsideSchedule);
      expect(check(state, at(5, 11, 59)).allowed, isTrue);
    });

    test('inside a range: the countdown shows the end of the range', () {
      final d = check(state, at(5, 19, 30));
      expect(d.reason, Reason.withinLimits);
      expect(d.remaining, min(30));
      expect(d.limiter, Limiter.schedule);
      expect(d.ruleId, 'h');
    });

    test('two contiguous ranges act as one', () {
      final s = WeeklySchedule.everyDay([
        TimeRange.hm(8, 0, 10, 0),
        TimeRange.hm(10, 0, 12, 0),
      ]);
      expect(s.untilEnd(at(5, 9)), min(180));
    });

    test('a range running past midnight is chained', () {
      final s = WeeklySchedule({
        DateTime.monday: [TimeRange.hm(22, 0, 24, 0)],
        DateTime.tuesday: [TimeRange.hm(0, 0, 1, 0)],
      });
      // The 5th is a Monday.
      expect(s.untilEnd(at(5, 23)), min(120));
    });

    test('a day without ranges is fully blocked', () {
      final s = WeeklySchedule({
        DateTime.monday: [TimeRange.hm(8, 0, 9, 0)],
      });
      expect(s.allows(at(6, 8, 30)), isFalse);
      expect(s.nextStart(at(6, 8, 30)), at(12, 8));
    });
  });
}
