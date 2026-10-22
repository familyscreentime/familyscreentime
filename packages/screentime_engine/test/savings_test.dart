import 'package:screentime_engine/screentime_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

Rule saving({
  int keep = 1,
  Duration? cap,
  CarryOverPolicy carry = const CarryOverPolicy.none(),
  GracePolicy? grace,
  Duration? weekly,
  String? profileId,
}) => Rule(
  id: 'r',
  childId: child,
  profileId: profileId,
  dailyQuota: min(60),
  weeklyQuota: weekly,
  rollover: RolloverPolicy(days: keep, cap: cap),
  carryOver: carry,
  grace: grace,
);

void main() {
  group('Saved time', () {
    test('time left unused yesterday is added to today', () {
      final state = FamilyState(
        rules: [saving()],
        usage: [use(tablet, 'minecraft', at(4, 9), 40)],
      );
      expect(check(state, at(5, 8)).remaining, min(80));
    });

    test('a day without any use saves its whole quota', () {
      final state = FamilyState(rules: [saving()]);
      expect(check(state, at(5, 8)).remaining, min(120));
    });

    test('without the policy, nothing is saved', () {
      final state = FamilyState(
        rules: [Rule(id: 'r', childId: child, dailyQuota: min(60))],
        usage: [use(tablet, 'minecraft', at(4, 9), 40)],
      );
      expect(check(state, at(5, 8)).remaining, min(60));
    });

    test('savings expire after the chosen number of days', () {
      final usage = [
        use(tablet, 'minecraft', at(3, 9), 40), // 20 saved on the 3rd
        use(tablet, 'minecraft', at(4, 9), 60), // nothing on the 4th
      ];
      final oneDay = FamilyState(rules: [saving(keep: 1)], usage: usage);
      expect(check(oneDay, at(5, 8)).remaining, min(60));
      final twoDays = FamilyState(rules: [saving(keep: 2)], usage: usage);
      expect(check(twoDays, at(5, 8)).remaining, min(80));
    });

    test('savings cover an overrun, which is then no overrun at all', () {
      final r = saving(keep: 2);
      final state = FamilyState(
        rules: [r],
        usage: [
          use(tablet, 'minecraft', at(2, 9), 60), // nothing saved on the 2nd
          use(tablet, 'minecraft', at(3, 9), 40), // 20 saved
          use(tablet, 'minecraft', at(4, 9), 70), // 10 drawn
        ],
      );
      expect(check(state, at(5, 8)).remaining, min(70));
      expect(
        RuleEngine(
          config,
        ).dailyOverrun(state, r, childId: child, day: at(4, 0)),
        Duration.zero,
      );
    });

    test('the day\'s quota is spent before savings', () {
      final r = saving();
      final state = FamilyState(
        rules: [r],
        usage: [
          use(tablet, 'minecraft', at(4, 9), 30), // 30 saved
          use(tablet, 'minecraft', at(5, 9), 70),
        ],
      );
      expect(check(state, at(5, 10, 10)).remaining, min(20));
      expect(
        RuleEngine(
          config,
        ).savingsLeft(state, r, childId: child, now: at(5, 10, 10)),
        min(20),
      );
    });

    test('the oldest savings are spent first', () {
      final state = FamilyState(
        rules: [saving(keep: 2)],
        usage: [
          use(tablet, 'minecraft', at(3, 9), 50), // 10 saved on the 3rd
          use(tablet, 'minecraft', at(4, 9), 40), // 20 saved on the 4th
          use(tablet, 'minecraft', at(5, 9), 70), // 10 drawn from the 3rd
        ],
      );
      // On the 6th: the 20 minutes from the 4th remain; the 3rd's expired.
      expect(check(state, at(6, 8)).remaining, min(80));
    });

    test('grace only starts once savings are used up', () {
      final r = saving(grace: const GracePolicy(length: Duration(minutes: 10)));
      final state = FamilyState(
        rules: [r],
        usage: [
          use(tablet, 'minecraft', at(4, 9), 50), // 10 saved
          use(tablet, 'minecraft', at(5, 9), 75),
        ],
      );
      final d = check(state, at(5, 10, 15));
      expect(d.reason, Reason.gracePeriod);
      expect(d.remaining, min(5));
    });

    test('a carry-over first reduces what can be saved', () {
      final state = FamilyState(
        rules: [saving(carry: const CarryOverPolicy.nextDay())],
        usage: [
          use(tablet, 'minecraft', at(2, 9), 60), // nothing saved on the 2nd
          use(tablet, 'minecraft', at(3, 9), 90), // 30 overrun
        ],
      );
      // On the 4th: quota cut to 30, nothing used, so 30 saved.
      expect(check(state, at(5, 8)).remaining, min(90));
    });

    test('a day when the rule is not in force saves nothing', () {
      final cfg = configWith(
        profiles: [
          const Profile(id: 'normal', name: 'Normal', kind: ProfileKind.normal),
          Profile(
            id: 'holidays',
            name: 'Holidays',
            kind: ProfileKind.vacation,
            periods: [DateRange(at(4, 0), at(4, 0))],
          ),
        ],
      );
      final state = FamilyState(rules: [saving(profileId: 'normal')]);
      expect(check(state, at(5, 8), cfg: cfg).remaining, min(60));
    });

    test('the weekly quota still caps', () {
      final state = FamilyState(
        rules: [saving(weekly: min(100))],
        usage: [use(tablet, 'minecraft', at(5, 9), 40)], // Monday
      );
      // Tuesday: 80 for the day, but only 60 left for the week.
      expect(check(state, at(6, 8)).remaining, min(60));
    });
  });

  group('Savings cap', () {
    test('savings beyond the cap are lost', () {
      final state = FamilyState(
        rules: [saving(cap: min(15))],
        usage: [use(tablet, 'minecraft', at(4, 9), 40)], // 20, capped at 15
      );
      expect(check(state, at(5, 8)).remaining, min(75));
    });

    test('the cap applies to the whole balance', () {
      final state = FamilyState(
        rules: [saving(keep: 2, cap: min(30))],
        usage: [
          use(tablet, 'minecraft', at(2, 9), 60), // nothing saved
          use(tablet, 'minecraft', at(3, 9), 40), // 20 saved
          use(tablet, 'minecraft', at(4, 9), 40), // 20, only 10 fit
        ],
      );
      expect(check(state, at(5, 8)).remaining, min(90));
    });

    test('savings that expire tonight do not count against the cap', () {
      // The 3rd (no use) saves 20 under the cap; those expire after the
      // 4th, so the 4th's 20 still fit.
      final state = FamilyState(
        rules: [saving(cap: min(20))],
        usage: [use(tablet, 'minecraft', at(4, 9), 40)],
      );
      expect(check(state, at(5, 8)).remaining, min(80));
    });
  });

  test('savings can be limited to one kind of time', () {
    // Games time can be saved; total screen time cannot.
    final state = FamilyState(
      rules: [
        Rule(id: 'all', childId: child, dailyQuota: min(150)),
        Rule(
          id: 'games',
          childId: child,
          appTarget: const AppTarget.group('games'),
          dailyQuota: min(60),
          rollover: const RolloverPolicy(days: 1),
        ),
      ],
      usage: [
        use(tablet, 'youtube', at(4, 9), 60), // no games on the 4th
      ],
    );
    final games = check(state, at(5, 8), app: 'minecraft');
    expect(games.remaining, min(120));
    expect(games.ruleId, 'games');
    // The 90 unused minutes of total time on the 4th are not kept.
    expect(check(state, at(5, 8), app: 'youtube').remaining, min(150));
  });

  test('the ledger goes back as far as asked, with the same today', () {
    final state = FamilyState(
      rules: [saving()],
      usage: [
        use(tablet, 'minecraft', at(2, 9), 150), // 60 + 60 saved + 30
        use(tablet, 'minecraft', at(4, 9), 40),
      ],
    );
    final r = state.rules.single;
    final engine = RuleEngine(const FamilyConfig());
    final short = engine.dailyLedger(state, r, childId: child, now: at(5, 8));
    final long = engine.dailyLedger(
      state,
      r,
      childId: child,
      now: at(5, 8),
      history: 10,
    );
    expect(long.length, 11);
    expect(long.length, greaterThan(short.length));
    expect(long.last.savingsAvailable, short.last.savingsAvailable);
    expect(long[long.length - 4].overrun, min(30)); // the 2nd
  });
}
