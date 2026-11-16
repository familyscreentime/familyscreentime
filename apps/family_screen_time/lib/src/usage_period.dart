/// The periods the usage statistics are shown for: a day, a week or a
/// month, today's or an earlier one.
library;

import 'package:screentime_engine/screentime_engine.dart';

import 'strings.dart';

enum PeriodKind { day, week, month }

class UsagePeriod {
  final PeriodKind kind;

  /// Midnight of its first day.
  final DateTime first;

  /// Its number of days.
  final int length;

  const UsagePeriod._(this.kind, this.first, this.length);

  /// The [kind] of period holding [t]; weeks begin on [weekStart]
  /// ([DateTime.weekday] convention).
  factory UsagePeriod.at(
    PeriodKind kind,
    DateTime t, {
    required int weekStart,
  }) {
    final day = dayOf(t);
    switch (kind) {
      case PeriodKind.day:
        return UsagePeriod._(kind, day, 1);
      case PeriodKind.week:
        return UsagePeriod._(kind, startOfWeek(day, weekStart), 7);
      case PeriodKind.month:
        final first = DateTime(day.year, day.month);
        final next = DateTime(day.year, day.month + 1);
        return UsagePeriod._(kind, first, _daysIn(first, next));
    }
  }

  /// Midnight of the day after its last.
  DateTime get end => addDays(first, length);

  DateTime get last => addDays(first, length - 1);

  /// The period of the same kind [n] periods later (earlier when negative).
  UsagePeriod shifted(int n, {required int weekStart}) => switch (kind) {
    PeriodKind.day => UsagePeriod.at(
      kind,
      addDays(first, n),
      weekStart: weekStart,
    ),
    PeriodKind.week => UsagePeriod.at(
      kind,
      addDays(first, 7 * n),
      weekStart: weekStart,
    ),
    PeriodKind.month => UsagePeriod.at(
      kind,
      DateTime(first.year, first.month + n),
      weekStart: weekStart,
    ),
  };

  bool contains(DateTime t) => !t.isBefore(first) && t.isBefore(end);

  /// "Aujourd'hui", "Hier", "Lundi 02/11"; "Cette semaine", "Semaine
  /// dernière", "Du 19/10 au 25/10"; "Octobre 2026".
  String label(S s, DateTime now) {
    final today = dayOf(now);
    switch (kind) {
      case PeriodKind.day:
        if (first == today) return s.t('periodToday');
        if (first == addDays(today, -1)) return s.t('periodYesterday');
        return '${_capitalized(s.weekday(first.weekday))} ${s.date(first)}';
      case PeriodKind.week:
        if (contains(today)) return s.t('periodThisWeek');
        if (contains(addDays(today, -7))) return s.t('periodLastWeek');
        return s.t('periodRange', {'from': s.date(first), 'to': s.date(last)});
      case PeriodKind.month:
        return '${_capitalized(s.t('month${first.month}'))} ${first.year}';
    }
  }

  @override
  bool operator ==(Object other) =>
      other is UsagePeriod && other.kind == kind && other.first == first;

  @override
  int get hashCode => Object.hash(kind, first);
}

/// Whole days from [a] to [b], both midnights (daylight saving changes
/// left aside).
int _daysIn(DateTime a, DateTime b) => DateTime.utc(
  b.year,
  b.month,
  b.day,
).difference(DateTime.utc(a.year, a.month, a.day)).inDays;

String _capitalized(String text) =>
    text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);
