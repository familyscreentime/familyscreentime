/// App usage statistics, independent of the rules.
library;

import 'package:screentime_engine/screentime_engine.dart';

/// Segments of the same app closer than this count as one session.
const sessionGap = Duration(minutes: 1);

/// An app first used this recently is flagged as new.
const newAppWindow = Duration(days: 7);

/// Hours counted as night: 22:00 to 06:00.
bool isNightHour(int hour) => hour >= 22 || hour < 6;

class AppUsage {
  final String appId;
  final Duration total;
  final int sessions;

  /// Time per day of the period, keyed by midnight.
  final Map<DateTime, Duration> byDay;

  /// Time per hour of the day over the period, index 0 to 23.
  final List<Duration> byHour;

  /// First and last use in the whole loaded history, not only the period.
  final DateTime firstSeen;
  final DateTime lastSeen;

  /// First used recently, and the history goes back further than that.
  final bool isNew;

  /// Time of the period by what the app was used for, when the device
  /// could tell (a browser: video, quick scrolling, other).
  final Map<String, Duration> byActivity;

  const AppUsage({
    required this.appId,
    required this.total,
    required this.sessions,
    required this.byDay,
    required this.byHour,
    required this.firstSeen,
    required this.lastSeen,
    required this.isNew,
    this.byActivity = const {},
  });

  Duration get night {
    var d = Duration.zero;
    for (var h = 0; h < 24; h++) {
      if (isNightHour(h)) d += byHour[h];
    }
    return d;
  }
}

class UsageReport {
  /// Days of the period, oldest first.
  final List<DateTime> days;
  final Map<DateTime, Duration> totalByDay;
  final List<Duration> totalByHour;
  final Duration total;

  /// Apps sorted by time, most used first.
  final List<AppUsage> apps;

  /// Earliest recorded use, or `null` when nothing was recorded.
  final DateTime? historyStart;

  const UsageReport({
    required this.days,
    required this.totalByDay,
    required this.totalByHour,
    required this.total,
    required this.apps,
    required this.historyStart,
  });

  /// Average per day, over the days since recording started.
  Duration get dailyAverage {
    final start = historyStart;
    final counted = start == null
        ? 0
        : days.where((d) => !d.isBefore(dayOf(start))).length;
    return counted == 0 ? Duration.zero : total ~/ counted;
  }
}

/// Splits [from, to) at every hour boundary and calls [add] for each piece.
void _byHour(
  DateTime from,
  DateTime to,
  void Function(DateTime, Duration) add,
) {
  var t = from;
  while (t.isBefore(to)) {
    final next = DateTime(t.year, t.month, t.day, t.hour + 1);
    final end = next.isBefore(to) ? next : to;
    add(t, end.difference(t));
    t = end;
  }
}

/// The time each device's screen was in use within [from, to), by device:
/// [segments] merged, so that apps on screen together count once.
/// [together]: the devices' time at once counts once too (the family's
/// choice, see [SimultaneousCounting.elapsed]): one list for all.
Map<String, List<Interval>> screenTime(
  Iterable<UsageSegment> segments,
  DateTime from,
  DateTime to, {
  bool together = false,
}) {
  final byDevice = <String, List<Interval>>{};
  for (final s in segments) {
    final part = s.clip(from, to);
    if (part == null) continue;
    byDevice.putIfAbsent(together ? '' : s.deviceId ?? '', () => []).add(part);
  }
  return {for (final e in byDevice.entries) e.key: mergeIntervals(e.value)};
}

/// Builds the report of [childId]'s device usage ([together]: time on
/// several devices at once counted once in the totals) over the [days] days
/// ending on the day of [now]. Injected time and apps in [exclude] (system
/// components) are left out.
UsageReport buildUsageReport(
  List<UsageSegment> history, {
  required String childId,
  required DateTime now,
  required int days,
  Set<String> exclude = const {},
  bool together = false,
}) {
  final today = dayOf(now);
  final from = addDays(today, -(days - 1));
  final periodDays = [for (var i = 0; i < days; i++) addDays(from, i)];
  final to = addDays(today, 1);

  // Time open only to pick the music counts as the app's.
  UsageSegment asApp(UsageSegment s) => usedApp(s.appId!) == s.appId
      ? s
      : UsageSegment.device(
          childId: s.childId,
          deviceId: s.deviceId!,
          appId: usedApp(s.appId!),
          start: s.start,
          end: s.end,
          activity: s.activity,
        );
  final segments =
      history
          .where((s) => s.childId == childId && !s.isInjected)
          .map(asApp)
          .where((s) => !exclude.contains(s.appId))
          .toList()
        ..sort((a, b) => a.start.compareTo(b.start));

  final first = <String, DateTime>{};
  final last = <String, DateTime>{};
  for (final s in segments) {
    first.putIfAbsent(s.appId!, () => s.start);
    final l = last[s.appId!];
    if (l == null || s.end.isAfter(l)) last[s.appId!] = s.end;
  }
  final historyStart = segments.isEmpty ? null : segments.first.start;

  final totals = <String, Duration>{};
  final byDay = <String, Map<DateTime, Duration>>{};
  final byHour = <String, List<Duration>>{};
  final sessions = <String, int>{};
  final activities = <String, Map<String, Duration>>{};
  final lastEnd = <String, DateTime>{};
  final totalByDay = {for (final d in periodDays) d: Duration.zero};
  final totalByHour = List.filled(24, Duration.zero);

  for (final s in segments) {
    final part = s.clip(from, to);
    if (part == null) continue;
    final app = s.appId!;
    final previous = lastEnd[app];
    if (previous == null || part.start.difference(previous) >= sessionGap) {
      sessions[app] = (sessions[app] ?? 0) + 1;
    }
    if (previous == null || part.end.isAfter(previous)) lastEnd[app] = part.end;
    totals[app] = (totals[app] ?? Duration.zero) + part.length;
    final activity = s.activity;
    if (activity != null) {
      final a = activities.putIfAbsent(app, () => {});
      a[activity] = (a[activity] ?? Duration.zero) + part.length;
    }
    final appDays = byDay.putIfAbsent(app, () => {});
    final appHours = byHour.putIfAbsent(
      app,
      () => List.filled(24, Duration.zero),
    );
    _byHour(part.start, part.end, (t, d) {
      final day = dayOf(t);
      appDays[day] = (appDays[day] ?? Duration.zero) + d;
      appHours[t.hour] += d;
    });
  }

  // The device's time: apps on screen together (split screen, floating
  // video) count once.
  var total = Duration.zero;
  for (final device in screenTime(
    segments,
    from,
    to,
    together: together,
  ).values) {
    for (final i in device) {
      total += i.length;
      _byHour(i.start, i.end, (t, d) {
        final day = dayOf(t);
        totalByDay[day] = (totalByDay[day] ?? Duration.zero) + d;
        totalByHour[t.hour] += d;
      });
    }
  }

  final apps =
      [
        for (final app in totals.keys)
          AppUsage(
            appId: app,
            total: totals[app]!,
            sessions: sessions[app] ?? 0,
            byDay: byDay[app] ?? const {},
            byHour: byHour[app]!,
            firstSeen: first[app]!,
            lastSeen: last[app]!,
            isNew:
                now.difference(first[app]!) < newAppWindow &&
                first[app]!.difference(historyStart!) > const Duration(days: 1),
            byActivity: activities[app] ?? const {},
          ),
      ]..sort((a, b) {
        final byTime = b.total.compareTo(a.total);
        return byTime != 0 ? byTime : a.appId.compareTo(b.appId);
      });

  return UsageReport(
    days: periodDays,
    totalByDay: totalByDay,
    totalByHour: totalByHour,
    total: total,
    apps: apps,
    historyStart: historyStart,
  );
}
