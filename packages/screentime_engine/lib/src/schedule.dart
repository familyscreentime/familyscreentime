/// Allowed time ranges, day by day.
///
/// Fixed breaks (meals, homework…) are simply gaps between two allowed
/// ranges.
library;

import 'calendar.dart';

/// Time range [start, end) in minutes since midnight, from 0 to 1440.
class TimeRange {
  final int startMinute;
  final int endMinute;

  const TimeRange(this.startMinute, this.endMinute)
    : assert(startMinute >= 0),
      assert(endMinute <= 1440),
      assert(startMinute < endMinute);

  /// Readable shorthand: `TimeRange.hm(8, 0, 12, 30)` for 8:00–12:30.
  const TimeRange.hm(int startHour, int startMin, int endHour, int endMin)
    : this(startHour * 60 + startMin, endHour * 60 + endMin);

  bool containsSecond(int secondOfDay) =>
      secondOfDay >= startMinute * 60 && secondOfDay < endMinute * 60;
}

int _secondOfDay(DateTime t) => t.hour * 3600 + t.minute * 60 + t.second;

DateTime _at(DateTime day, int minute) =>
    DateTime(day.year, day.month, day.day, 0, minute);

/// Allowed ranges per weekday ([DateTime.monday] … [DateTime.sunday]).
/// A missing day has no allowed range.
class WeeklySchedule {
  final Map<int, List<TimeRange>> byWeekday;

  WeeklySchedule(Map<int, List<TimeRange>> byWeekday)
    : byWeekday = {
        for (final e in byWeekday.entries)
          e.key: ([...e.value]
            ..sort((a, b) => a.startMinute.compareTo(b.startMinute))),
      };

  /// The same ranges every day.
  factory WeeklySchedule.everyDay(List<TimeRange> ranges) =>
      WeeklySchedule({for (var d = 1; d <= 7; d++) d: ranges});

  List<TimeRange> rangesOn(DateTime day) => byWeekday[day.weekday] ?? const [];

  /// True when [t] falls in an allowed range.
  bool allows(DateTime t) {
    final s = _secondOfDay(t);
    return rangesOn(t).any((r) => r.containsSecond(s));
  }

  /// Time left before the end of the current allowed range, chaining
  /// contiguous ranges (across midnight too). `null` when [t] is outside
  /// any range.
  Duration? untilEnd(DateTime t) {
    var day = dayOf(t);
    final s = _secondOfDay(t);
    TimeRange? current;
    for (final r in rangesOn(day)) {
      if (r.containsSecond(s)) current = r;
    }
    if (current == null) return null;
    var end = current.endMinute;
    // Chain at most 8 days to avoid an endless loop.
    for (var guard = 0; guard < 8 * 48; guard++) {
      final next = _rangeStartingAt(day, end);
      if (next != null) {
        end = next.endMinute;
        continue;
      }
      if (end == 1440) {
        final tomorrow = addDays(day, 1);
        final first = _rangeStartingAt(tomorrow, 0);
        if (first != null) {
          day = tomorrow;
          end = first.endMinute;
          continue;
        }
      }
      break;
    }
    return _at(day, end).difference(t);
  }

  TimeRange? _rangeStartingAt(DateTime day, int minute) {
    if (minute >= 1440) return null;
    for (final r in rangesOn(day)) {
      if (r.startMinute == minute) return r;
    }
    return null;
  }

  /// Start of the next allowed range after [t], within 7 days.
  /// `null` when the schedule never allows anything.
  DateTime? nextStart(DateTime t) {
    final s = _secondOfDay(t);
    final today = dayOf(t);
    for (final r in rangesOn(today)) {
      if (r.startMinute * 60 > s) return _at(today, r.startMinute);
    }
    for (var i = 1; i <= 7; i++) {
      final day = addDays(today, i);
      final ranges = rangesOn(day);
      if (ranges.isNotEmpty) return _at(day, ranges.first.startMinute);
    }
    return null;
  }
}
