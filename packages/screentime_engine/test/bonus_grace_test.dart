import 'package:screentime_engine/screentime_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  final games60 = Rule(
    id: 'games',
    childId: child,
    appTarget: const AppTarget.group('games'),
    dailyQuota: min(60),
  );

  group('Bonuses', () {
    final used = [use(tablet, 'minecraft', at(5, 9), 60)];

    test('a bonus on the blocking rule gives time back', () {
      final state = FamilyState(
        rules: [games60],
        usage: used,
        bonuses: [
          Bonus.forRule(
            id: 'b',
            childId: child,
            ruleId: 'games',
            amount: min(15),
            grantedAt: at(5, 10, 15),
            validUntil: at(6, 0),
          ),
        ],
      );
      final d = check(state, at(5, 10, 30));
      expect(d.allowed, isTrue);
      expect(d.remaining, min(15));
    });

    test('a bonus on a target applies to rules with the same target', () {
      final state = FamilyState(
        rules: [games60],
        usage: used,
        bonuses: [
          Bonus.forTarget(
            id: 'b',
            childId: child,
            appTarget: const AppTarget.group('games'),
            amount: min(20),
            grantedAt: at(5, 10, 15),
            validUntil: at(6, 0),
          ),
        ],
      );
      expect(check(state, at(5, 10, 30)).remaining, min(20));
    });

    test('a bonus on "All" does not unlock the "Games" limit', () {
      final state = FamilyState(
        rules: [games60],
        usage: used,
        bonuses: [
          Bonus.forTarget(
            id: 'b',
            childId: child,
            appTarget: const AppTarget.all(),
            amount: min(20),
            grantedAt: at(5, 10, 15),
            validUntil: at(6, 0),
          ),
        ],
      );
      expect(check(state, at(5, 10, 30)).allowed, isFalse);
    });

    test('an expired bonus only counts for the part used', () {
      final weekly = Rule(id: 'w', childId: child, weeklyQuota: min(120));
      final state = FamilyState(
        rules: [weekly],
        usage: [use(tablet, 'minecraft', at(5, 9), 10)],
        bonuses: [
          Bonus.forRule(
            id: 'b',
            childId: child,
            ruleId: 'w',
            amount: min(30),
            grantedAt: at(5, 8),
            validUntil: at(5, 12),
          ),
        ],
      );
      // Valid: 120 + 30 − 10.
      expect(check(state, at(5, 11)).remaining, min(140));
      // Expired: only the 10 minutes used while valid remain.
      expect(check(state, at(6, 10)).remaining, min(120));
    });
  });

  group('Grace period', () {
    final withGrace = Rule(
      id: 'games',
      childId: child,
      appTarget: const AppTarget.group('games'),
      dailyQuota: min(60),
      grace: const GracePolicy(length: Duration(minutes: 10)),
    );

    test('once exhausted, grace lets the child finish', () {
      final state = FamilyState(
        rules: [withGrace],
        usage: [use(tablet, 'minecraft', at(5, 9), 65)],
      );
      final d = check(state, at(5, 10, 5));
      expect(d.allowed, isTrue);
      expect(d.reason, Reason.gracePeriod);
      expect(d.remaining, min(5));
      expect(d.limiter, Limiter.grace);
    });

    test('grace is for finishing, not for opening another app', () {
      final state = FamilyState(
        rules: [withGrace],
        usage: [
          use(tablet, 'minecraft', at(5, 9), 60),
          // Roblox opened two minutes after time ran out.
          use(tablet, 'roblox', at(5, 10, 2), 1),
        ],
      );
      final d = check(state, at(5, 10, 3), app: 'roblox');
      expect(d.allowed, isFalse);
      expect(d.reason, Reason.quotaExhausted);
      // Nor going back to Minecraft after leaving it.
      expect(check(state, at(5, 10, 3)).allowed, isFalse);
    });

    test('grace goes on across back-to-back records of the same app', () {
      final state = FamilyState(
        rules: [withGrace],
        usage: [
          use(tablet, 'minecraft', at(5, 9), 58),
          use(tablet, 'minecraft', at(5, 9, 58), 4),
        ],
      );
      expect(check(state, at(5, 10, 2)).reason, Reason.gracePeriod);
    });

    test('a short visit to another app also ends grace', () {
      final state = FamilyState(
        rules: [withGrace],
        usage: [
          use(tablet, 'minecraft', at(5, 9), 61),
          use(tablet, 'launcher', at(5, 10, 1), 1),
          use(tablet, 'minecraft', at(5, 10, 2), 1),
        ],
      );
      expect(check(state, at(5, 10, 3)).reason, Reason.quotaExhausted);
    });

    test('once grace is used up, it is blocked', () {
      final state = FamilyState(
        rules: [withGrace],
        usage: [use(tablet, 'minecraft', at(5, 9), 70)],
      );
      expect(check(state, at(5, 10, 10)).reason, Reason.quotaExhausted);
    });

    test('a nearer limit is still shown during grace', () {
      final state = FamilyState(
        rules: [
          withGrace,
          Rule(id: 'all', childId: child, dailyQuota: min(67)),
        ],
        usage: [use(tablet, 'minecraft', at(5, 9), 65)],
      );
      final d = check(state, at(5, 10, 5));
      expect(d.reason, Reason.gracePeriod);
      expect(d.remaining, min(2));
      expect(d.limiter, Limiter.quota);
      expect(d.ruleId, 'all');
    });
  });

  group('Grace hardening', () {
    // 10 min of grace, firm after 2 days over 5 min of grace out of 7.
    final hardened = Rule(
      id: 'games',
      childId: child,
      appTarget: const AppTarget.group('games'),
      dailyQuota: min(60),
      grace: const GracePolicy(
        length: Duration(minutes: 10),
        hardening: HardeningPolicy(
          threshold: Duration(minutes: 5),
          days: 2,
          window: 7,
        ),
      ),
    );
    final today = use(tablet, 'minecraft', at(5, 9), 60);

    test('a single day over the threshold: grace remains', () {
      final state = FamilyState(
        rules: [hardened],
        usage: [
          use(tablet, 'minecraft', at(3, 9), 68), // 8 min of grace
          use(tablet, 'minecraft', at(4, 9), 63), // 3 min: under the threshold
          today,
        ],
      );
      expect(check(state, at(5, 10)).reason, Reason.gracePeriod);
      expect(
        RuleEngine(
          config,
        ).hardeningCount(state, hardened, childId: child, now: at(5, 10)),
        1,
      );
    });

    test('two days over the threshold: the limit turns firm', () {
      final state = FamilyState(
        rules: [hardened],
        usage: [
          use(tablet, 'minecraft', at(1, 9), 69),
          use(tablet, 'minecraft', at(3, 9), 68),
          today,
        ],
      );
      expect(check(state, at(5, 10)).reason, Reason.quotaExhausted);
    });

    test('an overrun that is too old leaves the window', () {
      final state = FamilyState(
        rules: [hardened],
        usage: [
          use(tablet, 'minecraft', at(5 - 8, 9), 69),
          use(tablet, 'minecraft', at(3, 9), 68),
          today,
        ],
      );
      expect(check(state, at(5, 10)).reason, Reason.gracePeriod);
    });

    test('an unlocked day does not count as an overrun', () {
      final state = FamilyState(
        rules: [hardened],
        usage: [
          use(tablet, 'minecraft', at(1, 9), 69),
          use(tablet, 'minecraft', at(3, 9), 68),
          today,
        ],
        dayUnlocks: [DayUnlock(id: 'u', childId: child, day: at(1, 0))],
      );
      expect(check(state, at(5, 10)).reason, Reason.gracePeriod);
    });
  });

  test('0 min a day: only open with extra time', () {
    const rule = Rule(
      id: 'r',
      childId: child,
      appTarget: AppTarget.app('minecraft'),
      dailyQuota: Duration.zero,
    );
    final closed = check(const FamilyState(rules: [rule]), at(5, 15));
    expect(closed.allowed, isFalse);
    expect(closed.reason, Reason.quotaExhausted);
    final state = FamilyState(
      rules: const [rule],
      bonuses: [
        Bonus.forRule(
          id: 'b',
          childId: child,
          ruleId: 'r',
          amount: min(15),
          grantedAt: at(5, 14),
          validUntil: at(6, 0),
        ),
      ],
    );
    expect(check(state, at(5, 15)).remaining, min(15));
  });
}
