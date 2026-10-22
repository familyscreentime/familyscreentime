import 'package:screentime_engine/screentime_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  // The 5th is a Monday, the 7th a Wednesday, the 10th a Saturday.
  Rule games({
    Duration? daily,
    CarryOverPolicy carry = const CarryOverPolicy.none(),
    RolloverPolicy? rollover,
  }) => Rule(
    id: 'games',
    childId: child,
    appTarget: const AppTarget.group('games'),
    dailyQuota: daily,
    dailyQuotaByWeekday: {
      DateTime.wednesday: min(60),
      DateTime.saturday: min(120),
      DateTime.monday: Duration.zero,
    },
    carryOver: carry,
    rollover: rollover,
  );

  group('Daily time by weekday', () {
    test('each weekday has its own time', () {
      final state = FamilyState(rules: [games()]);
      expect(check(state, at(7, 10)).remaining, min(60));
      expect(check(state, at(10, 10)).remaining, min(120));
    });

    test('zero minutes blocks the day', () {
      final state = FamilyState(rules: [games()]);
      expect(check(state, at(5, 10)).reason, Reason.quotaExhausted);
    });

    test('a weekday without time uses the default, or has no limit', () {
      final withDefault = FamilyState(rules: [games(daily: min(30))]);
      expect(check(withDefault, at(6, 10)).remaining, min(30)); // Tuesday
      final without = FamilyState(rules: [games()]);
      final tuesday = check(without, at(6, 10));
      expect(tuesday.reason, Reason.withinLimits);
      expect(tuesday.remaining, isNull);
    });

    test('an overrun is measured against that day\'s time', () {
      final r = games(carry: const CarryOverPolicy.nextDay());
      final state = FamilyState(
        rules: [r],
        usage: [use(tablet, 'minecraft', at(10, 9), 150)], // Saturday
      );
      expect(
        RuleEngine(
          config,
        ).dailyOverrun(state, r, childId: child, day: at(10, 0)),
        min(30),
      );
    });

    test('a day without a limit takes no carry-over', () {
      final r = games(carry: const CarryOverPolicy.nextDay());
      final state = FamilyState(
        rules: [r],
        usage: [use(tablet, 'minecraft', at(7, 9), 90)], // Wednesday
      );
      // Thursday has no limit: nothing to deduct, use stays unlimited.
      expect(check(state, at(8, 10)).remaining, isNull);
    });

    test('savings keep the time of the day they come from', () {
      final state = FamilyState(
        rules: [games(rollover: const RolloverPolicy(days: 1), daily: min(30))],
        usage: [use(tablet, 'minecraft', at(10, 9), 100)], // Saturday: 20 left
      );
      // Sunday uses the default 30, plus Saturday's 20.
      expect(check(state, at(11, 10)).remaining, min(50));
    });

    test('the weekday times survive a JSON round trip', () {
      final r = games(daily: min(30));
      final copy = ruleFromJson(ruleToJson(r));
      expect(copy.dailyQuotaByWeekday, r.dailyQuotaByWeekday);
      expect(copy.dailyQuotaOn(at(6, 0)), min(30));
      expect(copy.dailyQuotaOn(at(5, 0)), Duration.zero);
    });
  });
}
