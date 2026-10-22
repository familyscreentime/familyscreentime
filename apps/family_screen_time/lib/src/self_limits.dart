/// Limits the child sets for themselves: the log of their changes, and the
/// facts the parent's follow-up view shows (no judgement, no advice).
library;

import 'package:screentime_engine/screentime_engine.dart';

enum SelfLimitAction { created, changed, removed }

/// One change the child made to one of their limits.
class SelfLimitEvent {
  final DateTime at;
  final String ruleId;
  final SelfLimitAction action;
  final AppTarget target;

  /// Time per day after the change; `null` once removed.
  final Duration? daily;

  const SelfLimitEvent({
    required this.at,
    required this.ruleId,
    required this.action,
    required this.target,
    this.daily,
  });

  Map<String, Object?> toJson() => {
    'at': instantToJson(at),
    'ruleId': ruleId,
    'action': action.name,
    'target': appTargetToJson(target),
    if (daily != null) 'daily': durationToJson(daily!),
  };

  factory SelfLimitEvent.fromJson(Map<String, Object?> j) => SelfLimitEvent(
    at: instantFromJson(j['at']),
    ruleId: j['ruleId'] as String,
    action: SelfLimitAction.values.byName(j['action'] as String),
    target: appTargetFromJson(j['target'] as Map<String, Object?>),
    daily: optionalDuration(j['daily']),
  );
}

/// How one day went for one limit.
enum DayOutcome {
  /// The limit did not exist that day.
  none,

  /// Today, still running.
  ongoing,

  /// Use stayed within the limit.
  kept,

  /// Use went beyond it (the limit was raised or removed during the day,
  /// or time was counted offline).
  exceeded,
}

/// The story of one limit over the period looked at.
class SelfLimitStory {
  final String ruleId;
  final AppTarget target;
  final List<SelfLimitEvent> events;

  /// Outcome per day of the period, oldest first.
  final List<DayOutcome> days;

  /// Use beyond (positive) or below (negative) the limit, per day it
  /// existed and is over.
  final List<Duration> gaps;

  const SelfLimitStory({
    required this.ruleId,
    required this.target,
    required this.events,
    required this.days,
    required this.gaps,
  });

  DateTime get createdAt => events.first.at;

  DateTime? get removedAt =>
      events.last.action == SelfLimitAction.removed ? events.last.at : null;

  /// Time per day now, or when it was removed.
  Duration? get lastDaily {
    for (final e in events.reversed) {
      if (e.daily != null) return e.daily;
    }
    return null;
  }
}

/// The facts over a period.
class SelfLimitReport {
  final List<DateTime> days;
  final List<SelfLimitStory> stories;

  /// Limits removed during the period.
  final int removals;

  const SelfLimitReport({
    required this.days,
    required this.stories,
    required this.removals,
  });

  int count(DayOutcome o) =>
      stories.fold(0, (n, s) => n + s.days.where((d) => d == o).length);

  /// Share of the finished limit-days that stayed within the limit; `null`
  /// without any.
  double? get keptShare {
    final kept = count(DayOutcome.kept);
    final total = kept + count(DayOutcome.exceeded);
    return total == 0 ? null : kept / total;
  }

  /// Average time between creating a limit and removing it (or now).
  Duration? averageLifetime(DateTime now) {
    if (stories.isEmpty) return null;
    final total = stories.fold(
      Duration.zero,
      (sum, s) => sum + (s.removedAt ?? now).difference(s.createdAt),
    );
    return total ~/ stories.length;
  }

  /// Average use beyond (positive) or below (negative) the limit.
  Duration? get averageGap {
    final gaps = [for (final s in stories) ...s.gaps];
    if (gaps.isEmpty) return null;
    return gaps.fold(Duration.zero, (a, b) => a + b) ~/ gaps.length;
  }
}

/// Builds the report over the [period] days ending today.
SelfLimitReport selfLimitReport({
  required RuleEngine engine,
  required List<SelfLimitEvent> log,
  required List<UsageSegment> usage,
  required String childId,
  required DateTime now,
  required int period,
}) {
  final today = dayOf(now);
  final days = [for (var i = period - 1; i >= 0; i--) addDays(today, -i)];
  final start = days.first;
  final byRule = <String, List<SelfLimitEvent>>{};
  for (final e in [...log]..sort((a, b) => a.at.compareTo(b.at))) {
    byRule.putIfAbsent(e.ruleId, () => []).add(e);
  }
  final state = FamilyState(usage: usage);
  final stories = <SelfLimitStory>[];
  var removals = 0;
  for (final entry in byRule.entries) {
    final events = entry.value;
    final removed = events.last.action == SelfLimitAction.removed
        ? events.last.at
        : null;
    // Only limits that existed during the period.
    if (removed != null && removed.isBefore(start)) continue;
    if (!events.first.at.isBefore(addDays(today, 1))) continue;
    if (removed != null) removals++;
    final target = events.last.target;
    final rule = Rule(id: entry.key, childId: childId, appTarget: target);
    final outcomes = <DayOutcome>[];
    final gaps = <Duration>[];
    for (final day in days) {
      final end = addDays(day, 1);
      final existed =
          events.first.at.isBefore(end) &&
          (removed == null || !removed.isBefore(day));
      if (!existed) {
        outcomes.add(DayOutcome.none);
        continue;
      }
      if (day == today) {
        outcomes.add(DayOutcome.ongoing);
        continue;
      }
      // The limit as it stood at the end of the day, or when removed.
      Duration? daily;
      for (final e in events) {
        if (!e.at.isBefore(end)) break;
        if (e.daily != null) daily = e.daily;
      }
      final used = engine.consumption(
        state,
        rule,
        childId: childId,
        from: day,
        to: end,
      );
      if (daily == null) {
        outcomes.add(DayOutcome.none);
        continue;
      }
      outcomes.add(used > daily ? DayOutcome.exceeded : DayOutcome.kept);
      gaps.add(used - daily);
    }
    stories.add(
      SelfLimitStory(
        ruleId: entry.key,
        target: target,
        events: events,
        days: outcomes,
        gaps: gaps,
      ),
    );
  }
  return SelfLimitReport(days: days, stories: stories, removals: removals);
}
