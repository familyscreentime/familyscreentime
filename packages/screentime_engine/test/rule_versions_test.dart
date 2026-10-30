import 'package:screentime_engine/screentime_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  final engine = RuleEngine(config);

  // Two hours of games every day from the 1st to the 4th.
  final usage = [
    for (var d = 1; d <= 4; d++) use(tablet, 'minecraft', at(d, 14), 120),
  ];

  List<DayLedger> ledger(Rule r, DateTime now) => engine.dailyLedger(
    FamilyState(rules: [r], usage: usage),
    r,
    childId: child,
    now: now,
    history: 7,
  );

  DayLedger on(List<DayLedger> l, int day) =>
      l.firstWhere((d) => sameDay(d.day, at(day, 0)));

  const games = AppTarget.group('games');
  final hardening = GracePolicy(
    length: min(10),
    hardening: HardeningPolicy(threshold: min(5), days: 2, window: 7),
  );

  test('a stricter limit does not turn earlier days into overruns', () {
    // Three hours a day until the evening of the 3rd, then one hour.
    final r = Rule(
      id: 'g',
      childId: child,
      appTarget: games,
      dailyQuota: min(60),
      grace: hardening,
      history: [RuleVersion(until: at(3, 20), dailyQuota: min(180))],
    );
    final l = ledger(r, at(5, 10));
    expect(on(l, 1).overrun, Duration.zero);
    expect(on(l, 2).overrun, Duration.zero);
    expect(on(l, 2).quota, min(180));
    // The day of the change: judged by the more generous limit.
    expect(on(l, 3).overrun, Duration.zero);
    expect(on(l, 3).quota, min(60));
    // From then on, the new limit.
    expect(on(l, 4).overrun, min(60));
    expect(on(l, 4).quota, min(60));
    // Only one day counts towards the firm limit.
    final state = FamilyState(rules: [r], usage: usage);
    expect(engine.hardeningCount(state, r, childId: child, now: at(5, 10)), 1);
    expect(
      engine.effectiveGrace(state, r, childId: child, now: at(5, 10)),
      min(10),
    );
  });

  test('without the versions, every day overran (the former behaviour)', () {
    final r = Rule(
      id: 'g',
      childId: child,
      appTarget: games,
      dailyQuota: min(60),
      grace: hardening,
    );
    final state = FamilyState(rules: [r], usage: usage);
    expect(engine.hardeningCount(state, r, childId: child, now: at(5, 10)), 4);
  });

  test('a rule created, or turned on, does not judge the days before', () {
    final created = Rule(
      id: 'g',
      childId: child,
      appTarget: games,
      dailyQuota: min(60),
      history: [RuleVersion.none(at(4, 9))],
    );
    final l = ledger(created, at(5, 10));
    expect(on(l, 2).active, isFalse);
    expect(on(l, 3).active, isFalse);
    // Created on the morning of the 4th, before the games: still no
    // overrun that day, part of it had no rule.
    expect(on(l, 4).overrun, Duration.zero);
    final off = RuleVersion.of(created.withEnabled(false), at(4, 9));
    final turnedOn = created.withHistory([off]);
    expect(on(ledger(turnedOn, at(5, 10)), 3).active, isFalse);
  });

  test('a looser limit applies from its change only', () {
    // One hour until the 3rd, then three.
    final r = Rule(
      id: 'g',
      childId: child,
      appTarget: games,
      dailyQuota: min(180),
      history: [RuleVersion(until: at(3, 0), dailyQuota: min(60))],
    );
    final l = ledger(r, at(5, 10));
    expect(on(l, 2).overrun, min(60));
    expect(on(l, 3).overrun, Duration.zero);
    expect(on(l, 4).overrun, Duration.zero);
  });

  test('today: the time left follows the limit in force now', () {
    final r = Rule(
      id: 'g',
      childId: child,
      appTarget: games,
      dailyQuota: min(60),
      history: [RuleVersion(until: at(5, 9), dailyQuota: min(180))],
    );
    final state = FamilyState(
      rules: [r],
      usage: [use(tablet, 'minecraft', at(5, 8), 30)],
    );
    expect(check(state, at(5, 10)).remaining, min(30));
  });

  test('today follows the current limit, whatever the clock says', () {
    // Changed at 9 on the 5th; the clock set back to 8 the same day, or
    // a day before: still the current limit.
    final r = Rule(
      id: 'g',
      childId: child,
      appTarget: games,
      dailyQuota: min(30),
      history: [RuleVersion(until: at(5, 9), dailyQuota: min(180))],
    );
    final state = FamilyState(
      rules: [r],
      usage: [use(tablet, 'minecraft', at(5, 7), 40)],
    );
    expect(check(state, at(5, 8)).allowed, isFalse);
    final created = r.withHistory([RuleVersion.none(at(5, 9))]);
    expect(
      check(
        FamilyState(rules: [created], usage: state.usage),
        at(5, 8),
      ).allowed,
      isFalse,
    );
  });

  test('versions survive JSON', () {
    final r = Rule(
      id: 'g',
      childId: child,
      dailyQuota: min(60),
      history: [
        RuleVersion.none(at(1, 8)),
        RuleVersion(
          until: at(3, 20),
          dailyQuota: min(180),
          dailyQuotaByWeekday: {DateTime.saturday: min(240)},
        ),
      ],
    );
    final back = ruleFromJson(ruleToJson(r));
    expect(ruleToJson(back), ruleToJson(r));
    expect(back.dailyQuotaAt(at(2, 12)), min(180));
    expect(back.dailyQuotaAt(at(3, 21)), min(60));
    expect(back.dailyQuotaAt(at(1, 7)), isNull);
  });
}
