/// Where a rule stands today, for the child's home screen.
library;

import 'package:screentime_engine/screentime_engine.dart';

class RuleStatus {
  final Rule rule;

  /// Time left, the tightest of the day, the week and the rolling window;
  /// `null` when no quota applies today.
  final Duration? remaining;

  /// Today's total under the daily limit: the day's time, bonuses and
  /// carry-over included, plus saved time; `null` without a daily limit.
  final Duration? dayTotal;

  /// Extra time given today, included in [dayTotal].
  final Duration bonusToday;

  /// Time counted by the rule today.
  final Duration usedToday;

  /// Part of [usedToday] spent away from the devices, as entered by the
  /// parent.
  final Duration awayToday;

  /// The week (or rolling window) leaves less than the day.
  final bool limitedByPeriod;

  /// Saved time still available, when the rule keeps unused time.
  final Duration? savingsLeft;

  /// Today's allowed time ranges, when the rule has set hours.
  final List<TimeRange>? rangesToday;

  /// Apps counted by the rule today, most used first.
  final List<(String, Duration)> apps;

  const RuleStatus({
    required this.rule,
    required this.remaining,
    required this.dayTotal,
    this.bonusToday = Duration.zero,
    required this.usedToday,
    this.awayToday = Duration.zero,
    required this.limitedByPeriod,
    required this.savingsLeft,
    required this.rangesToday,
    required this.apps,
  });
}

RuleStatus ruleStatus(
  RuleEngine engine,
  FamilyState state,
  Rule r, {
  required String childId,
  required DateTime now,
}) {
  final today = dayOf(now);
  final remaining = r.hasQuota
      ? engine.remainingQuota(state, r, childId: childId, now: now)
      : null;

  Duration? dayTotal;
  Duration? dayLeft;
  var bonus = Duration.zero;
  if (r.hasDailyQuota) {
    final day = engine.dailyLedger(state, r, childId: childId, now: now).last;
    if (day.active) {
      dayTotal = day.allowance + day.savingsAvailable;
      dayLeft = dayTotal - day.consumed;
      bonus = day.bonus;
    }
  }

  final byApp = <String, Duration>{};
  var away = Duration.zero;
  for (final s in state.usage) {
    if (s.childId != childId || !engine.segmentCounts(r, s)) continue;
    final part = s.clip(today, now);
    if (part == null) continue;
    final app = s.appId;
    if (s.injectedTarget != null) {
      away += part.length;
    } else if (app != null) {
      byApp[app] = (byApp[app] ?? Duration.zero) + part.length;
    }
  }
  final apps = [for (final e in byApp.entries) (e.key, e.value)]
    ..sort((a, b) => b.$2.compareTo(a.$2));

  return RuleStatus(
    rule: r,
    remaining: remaining,
    dayTotal: dayTotal,
    bonusToday: bonus,
    usedToday: engine.consumption(
      state,
      r,
      childId: childId,
      from: today,
      to: now,
    ),
    awayToday: away,
    limitedByPeriod:
        remaining != null && dayLeft != null && remaining < dayLeft,
    savingsLeft: r.rollover == null
        ? null
        : engine.savingsLeft(state, r, childId: childId, now: now),
    rangesToday: r.schedule?.rangesOn(now),
    apps: apps,
  );
}
