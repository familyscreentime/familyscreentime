import 'package:screentime_engine/screentime_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

Rule daily60(CarryOverPolicy carry) =>
    Rule(id: 'r', childId: child, dailyQuota: min(60), carryOver: carry);

void main() {
  // On the 4th: 90 minutes for a 60-minute quota, i.e. a 30-minute overrun.
  final overrunYesterday = [use(tablet, 'minecraft', at(4, 9), 90)];

  group('Overrun carry-over', () {
    test('without carry-over, the overrun is only logged', () {
      final r = daily60(const CarryOverPolicy.none());
      final state = FamilyState(rules: [r], usage: overrunYesterday);
      expect(check(state, at(5, 8)).remaining, min(60));
      expect(
        RuleEngine(
          config,
        ).dailyOverrun(state, r, childId: child, day: at(4, 0)),
        min(30),
      );
    });

    test('carried over to the next day', () {
      final state = FamilyState(
        rules: [daily60(const CarryOverPolicy.nextDay())],
        usage: overrunYesterday,
      );
      expect(check(state, at(5, 8)).remaining, min(30));
      expect(check(state, at(6, 8)).remaining, min(60));
    });

    test('spread over three days', () {
      final state = FamilyState(
        rules: [daily60(const CarryOverPolicy.spread(3))],
        usage: overrunYesterday,
      );
      expect(check(state, at(5, 8)).remaining, min(50));
      expect(check(state, at(6, 8)).remaining, min(50));
      expect(check(state, at(7, 8)).remaining, min(50));
      expect(check(state, at(8, 8)).remaining, min(60));
    });

    test(
      'a carry-over larger than the quota blocks without going negative',
      () {
        final state = FamilyState(
          rules: [daily60(const CarryOverPolicy.nextDay())],
          usage: [use(tablet, 'minecraft', at(4, 9), 260)],
        );
        final d = check(state, at(5, 8));
        expect(d.allowed, isFalse);
        expect(d.reason, Reason.quotaExhausted);
      },
    );

    test('carry-overs do not snowball from day to day', () {
      // On the 5th the child uses exactly the nominal quota: no new
      // overrun, so nothing is carried over to the 6th.
      final state = FamilyState(
        rules: [daily60(const CarryOverPolicy.nextDay())],
        usage: [...overrunYesterday, use(tablet, 'minecraft', at(5, 9), 60)],
      );
      expect(check(state, at(6, 8)).remaining, min(60));
    });
  });
}
