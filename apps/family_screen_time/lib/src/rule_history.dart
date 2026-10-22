/// A rule's recent days, for the child: overruns, savings and the firm
/// limit.
library;

import 'package:screentime_engine/screentime_engine.dart';

/// Days shown when the rule has no firm limit, whose window sets the period
/// otherwise.
const defaultHistoryDays = 7;

class RuleHistory {
  final Rule rule;

  /// Number of days before today that are shown.
  final int period;

  /// Today first, then the previous days, newest first.
  final List<DayLedger> days;

  /// Days of the window whose overrun counts towards the firm limit, today
  /// excluded; 0 without a firm limit.
  final int firmCount;

  /// Savings still usable today, when the rule keeps unused time.
  final Duration? savingsLeft;

  const RuleHistory({
    required this.rule,
    required this.period,
    required this.days,
    required this.firmCount,
    required this.savingsLeft,
  });

  HardeningPolicy? get hardening => rule.grace?.hardening;

  /// No grace time today: too many overruns in the window.
  bool get firm => hardening != null && firmCount >= hardening!.days;

  /// One more counted day would make the limit firm.
  bool get firmNext => hardening != null && firmCount == hardening!.days - 1;

  /// Whether [day]'s overrun counts towards the firm limit.
  bool counts(DayLedger day) =>
      hardening != null && day.overrun > hardening!.threshold;

  Duration get totalOverrun =>
      days.fold(Duration.zero, (sum, d) => sum + d.overrun);

  Duration get totalSaved =>
      days.fold(Duration.zero, (sum, d) => sum + d.saved);
}

/// The history of [r], which must have a daily limit; `null` otherwise.
RuleHistory? ruleHistory(
  RuleEngine engine,
  FamilyState state,
  Rule r, {
  required String childId,
  required DateTime now,
}) {
  if (!r.hasDailyQuota) return null;
  final period = r.grace?.hardening?.window ?? defaultHistoryDays;
  final ledger = engine.dailyLedger(
    state,
    r,
    childId: childId,
    now: now,
    history: period,
  );
  final shown = ledger.length > period + 1
      ? ledger.sublist(ledger.length - period - 1)
      : ledger;
  return RuleHistory(
    rule: r,
    period: period,
    days: shown.reversed.toList(),
    firmCount: engine.hardeningCount(state, r, childId: childId, now: now),
    savingsLeft: r.rollover == null
        ? null
        : engine.savingsLeft(state, r, childId: childId, now: now),
  );
}
