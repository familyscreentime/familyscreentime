/// Use of apps over several months: week by week or month by month,
/// weekdays and weekends, by group and by app, and the change since the
/// period before.
library;

import 'package:screentime_engine/screentime_engine.dart';

import 'store.dart' show splitByDay;
import 'usage_export.dart' show withTimes;
import 'usage_report.dart' show screenTime;

/// A week or a month of the period.
class TrendBucket {
  final DateTime start;

  /// The day after the bucket.
  final DateTime end;
  final Duration total;

  /// Days of the bucket counted: within the period and the history held.
  final int days;

  const TrendBucket(this.start, this.end, this.total, this.days);

  Duration get perDay => days == 0 ? Duration.zero : total ~/ days;
}

/// An app's (or a group's) time over the period, and in the one before.
class Trend {
  final String id;
  final Duration total;
  final Duration perDay;

  /// Time per day over the period before, when the history covers it.
  final Duration? before;

  const Trend(this.id, this.total, this.perDay, this.before);

  /// Change since the period before, in percent; `null` without it, or
  /// when the app was not used then.
  int? get change {
    final b = before;
    if (b == null || b == Duration.zero) return null;
    return ((perDay.inSeconds - b.inSeconds) * 100 / b.inSeconds).round();
  }
}

class UsageTrends {
  /// The period: from [from] to the day before [to].
  final DateTime from;
  final DateTime to;

  /// First day the history holds use of this child's devices.
  final DateTime? historyStart;

  /// Days of the period with history.
  final int days;
  final Duration total;
  final Duration weekdayPerDay;
  final Duration weekendPerDay;

  /// Weeks or months, oldest first.
  final List<TrendBucket> buckets;

  /// By time, most first.
  final List<Trend> apps;
  final List<Trend> groups;

  /// Time per day over the period before, when the history covers it.
  final Duration? before;

  const UsageTrends({
    required this.from,
    required this.to,
    required this.historyStart,
    required this.days,
    required this.total,
    required this.weekdayPerDay,
    required this.weekendPerDay,
    required this.buckets,
    required this.apps,
    required this.groups,
    required this.before,
  });

  Duration get perDay => days == 0 ? Duration.zero : total ~/ days;

  /// Change since the period before, in percent.
  int? get change => Trend('', total, perDay, before).change;
}

/// Days counted from [from] to the day before [to], from [start] on.
int _daysBetween(DateTime from, DateTime to, DateTime? start) {
  if (start == null) return 0;
  final first = start.isAfter(from) ? start : from;
  var n = 0;
  for (var d = first; d.isBefore(to); d = addDays(d, 1)) {
    n++;
  }
  return n;
}

/// The trends of [childId]'s use over the [months] months ending on the
/// day of [now], week by week (month by month when [monthly]). Time
/// entered by hand and apps in [exclude] (system components) are left
/// out. [groups]: the child's groups of apps, by id.
UsageTrends buildTrends(
  List<UsageSegment> history, {
  required String childId,
  required DateTime now,
  required int months,
  bool monthly = false,
  int weekStart = DateTime.monday,
  Set<String> exclude = const {},
  Map<String, Set<String>> groups = const {},
  bool together = false,
}) {
  final today = dayOf(now);
  final to = addDays(today, 1);
  final from = DateTime(to.year, to.month - months, to.day);
  final previous = DateTime(from.year, from.month - months, from.day);

  final segments = [
    for (final s in history)
      if (s.childId == childId &&
          !s.isInjected &&
          !exclude.contains(usedApp(s.appId!)))
        s,
  ];
  DateTime? start;
  for (final s in segments) {
    final d = dayOf(s.start);
    if (start == null || d.isBefore(start)) start = d;
  }

  final current = <String, Duration>{};
  final then = <String, Duration>{};
  for (final s in segments) {
    final part = s.clip(previous, to);
    if (part == null) continue;
    final app = usedApp(s.appId!);
    for (final piece in splitByDay(withTimes(s, part.start, part.end))) {
      final day = dayOf(piece.start);
      if (day.isBefore(from)) {
        then[app] = (then[app] ?? Duration.zero) + piece.length;
      } else {
        current[app] = (current[app] ?? Duration.zero) + piece.length;
      }
    }
  }
  // The screens' time by day: apps on screen together count once.
  final byDay = <DateTime, Duration>{};
  var thenTotal = Duration.zero;
  for (final device in screenTime(
    segments,
    previous,
    to,
    together: together,
  ).values) {
    for (final i in device) {
      for (final piece in splitByDay(
        UsageSegment.device(
          childId: childId,
          deviceId: '',
          appId: '',
          start: i.start,
          end: i.end,
        ),
      )) {
        final day = dayOf(piece.start);
        if (day.isBefore(from)) {
          thenTotal += piece.length;
        } else {
          byDay[day] = (byDay[day] ?? Duration.zero) + piece.length;
        }
      }
    }
  }

  final days = _daysBetween(from, to, start);
  final daysBefore = _daysBetween(previous, from, start);
  // Compared only with a period before long enough to mean something.
  final compare = daysBefore >= 7;

  var weekday = Duration.zero;
  var weekend = Duration.zero;
  var weekdays = 0;
  var weekends = 0;
  if (start != null) {
    for (
      var d = start.isAfter(from) ? start : from;
      d.isBefore(to);
      d = addDays(d, 1)
    ) {
      final t = byDay[d] ?? Duration.zero;
      if (d.weekday >= DateTime.saturday) {
        weekend += t;
        weekends++;
      } else {
        weekday += t;
        weekdays++;
      }
    }
  }

  final buckets = <TrendBucket>[];
  var b = monthly
      ? DateTime(from.year, from.month)
      : startOfWeek(from, weekStart);
  while (b.isBefore(to)) {
    final next = monthly ? DateTime(b.year, b.month + 1) : addDays(b, 7);
    var total = Duration.zero;
    for (var d = b; d.isBefore(next); d = addDays(d, 1)) {
      if (!d.isBefore(from) && d.isBefore(to)) {
        total += byDay[d] ?? Duration.zero;
      }
    }
    final lo = b.isBefore(from) ? from : b;
    final hi = next.isAfter(to) ? to : next;
    buckets.add(TrendBucket(b, next, total, _daysBetween(lo, hi, start)));
    b = next;
  }

  Duration per(Duration d, int n) => n == 0 ? Duration.zero : d ~/ n;
  Trend trend(String id, Duration total, Duration? before) => Trend(
    id,
    total,
    per(total, days),
    compare ? per(before ?? Duration.zero, daysBefore) : null,
  );
  int byTime(Trend a, Trend b) {
    final c = b.total.compareTo(a.total);
    return c != 0 ? c : a.id.compareTo(b.id);
  }

  final apps = [
    for (final e in current.entries) trend(e.key, e.value, then[e.key]),
  ]..sort(byTime);
  final groupTrends = <Trend>[];
  for (final g in groups.entries) {
    var total = Duration.zero;
    var before = Duration.zero;
    for (final app in g.value) {
      total += current[app] ?? Duration.zero;
      before += then[app] ?? Duration.zero;
    }
    if (total > Duration.zero || before > Duration.zero) {
      groupTrends.add(trend(g.key, total, before));
    }
  }
  groupTrends.sort(byTime);

  final total = byDay.values.fold(Duration.zero, (a, b) => a + b);
  return UsageTrends(
    from: from,
    to: to,
    historyStart: start,
    days: days,
    total: total,
    weekdayPerDay: per(weekday, weekdays),
    weekendPerDay: per(weekend, weekends),
    buckets: buckets,
    apps: apps,
    groups: groupTrends,
    before: compare ? per(thenTotal, daysBefore) : null,
  );
}
