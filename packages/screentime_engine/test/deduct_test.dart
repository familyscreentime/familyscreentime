import 'package:screentime_engine/screentime_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

Rule firm({
  bool deduct = true,
  Duration grace = const Duration(minutes: 10),
  CarryOverPolicy carry = const CarryOverPolicy.none(),
}) => Rule(
  id: 'games',
  childId: child,
  appTarget: const AppTarget.group('games'),
  dailyQuota: min(60),
  grace: GracePolicy(
    length: grace,
    hardening: HardeningPolicy(
      threshold: min(5),
      days: 2,
      window: 7,
      deductOverruns: deduct,
    ),
  ),
  carryOver: carry,
);

void main() {
  group('Deducting overruns when the limit turns firm', () {
    // 9 minutes over on the 1st, 8 on the 3rd: firm from the 4th.
    final usage = [
      use(tablet, 'minecraft', at(1, 9), 69),
      use(tablet, 'minecraft', at(3, 9), 68),
    ];

    test('the overruns of the window are deducted once', () {
      final state = FamilyState(rules: [firm()], usage: usage);
      final engine = RuleEngine(config);
      expect(check(state, at(4, 8)).remaining, min(43));
      // Already paid: the next firm day is not charged again.
      expect(check(state, at(5, 8)).remaining, min(60));
      final day = engine
          .dailyLedger(state, firm(), childId: child, now: at(4, 8))
          .last;
      expect(day.deducted, min(17));
    });

    test('without the option, nothing is deducted', () {
      final state = FamilyState(rules: [firm(deduct: false)], usage: usage);
      expect(check(state, at(4, 8)).remaining, min(60));
    });

    test('a debt larger than a day is paid over the next days', () {
      final state = FamilyState(
        rules: [firm(grace: min(60))],
        usage: [
          use(tablet, 'minecraft', at(1, 9), 110), // 50 over
          use(tablet, 'minecraft', at(3, 9), 100), // 40 over
        ],
      );
      expect(check(state, at(4, 8)).reason, Reason.quotaExhausted);
      expect(check(state, at(5, 8)).remaining, min(30));
      expect(check(state, at(6, 8)).remaining, min(60));
    });

    test('with a carry-over, the option has no effect', () {
      final state = FamilyState(
        rules: [firm(carry: const CarryOverPolicy.nextDay())],
        usage: usage,
      );
      expect(
        check(state, at(4, 8)).remaining,
        min(52),
      ); // 8 carried from the 3rd
    });

    test('the option survives a JSON round trip', () {
      final copy = ruleFromJson(ruleToJson(firm()));
      expect(copy.grace!.hardening!.deductOverruns, isTrue);
    });
  });
}
