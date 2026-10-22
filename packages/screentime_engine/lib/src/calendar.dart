/// Days, weeks and calendar profiles (Normal, Holidays, custom).
///
/// All dates are in local time. Days are built with
/// `DateTime(year, month, day)` so they stay right across daylight-saving
/// changes, when a day does not always last 24 hours.
library;

/// Midnight (local time) of the day of [t].
DateTime dayOf(DateTime t) => DateTime(t.year, t.month, t.day);

/// Midnight of the day [n] days after [day] (negative: before).
DateTime addDays(DateTime day, int n) =>
    DateTime(day.year, day.month, day.day + n);

/// Midnight of the first day of the week containing [t].
/// [weekStart] follows the [DateTime.weekday] convention (Monday = 1).
DateTime startOfWeek(DateTime t, int weekStart) {
  final day = dayOf(t);
  final offset = (day.weekday - weekStart) % 7;
  return addDays(day, -offset);
}

/// True when [a] and [b] fall on the same day.
bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Range of whole days, both ends included.
class DateRange {
  final DateTime first;
  final DateTime last;

  DateRange(DateTime first, DateTime last)
    : first = dayOf(first),
      last = dayOf(last) {
    if (this.last.isBefore(this.first)) {
      throw ArgumentError('The range ends before it starts.');
    }
  }

  bool contains(DateTime t) {
    final day = dayOf(t);
    return !day.isBefore(first) && !day.isAfter(last);
  }
}

enum ProfileKind { normal, vacation, custom }

/// Calendar profile. A holiday or custom profile is only active during its
/// [periods]; the normal profile covers the rest of the time.
class Profile {
  final String id;
  final String name;
  final ProfileKind kind;
  final List<DateRange> periods;

  const Profile({
    required this.id,
    required this.name,
    required this.kind,
    this.periods = const [],
  });

  bool isScheduledOn(DateTime t) => periods.any((p) => p.contains(t));
}

/// Profile active at [t]: holidays first, then custom, then normal.
/// Returns `null` when no profile is configured or applies.
String? activeProfileId(List<Profile> profiles, DateTime t) {
  for (final kind in const [ProfileKind.vacation, ProfileKind.custom]) {
    for (final p in profiles) {
      if (p.kind == kind && p.isScheduledOn(t)) return p.id;
    }
  }
  for (final p in profiles) {
    if (p.kind == ProfileKind.normal) return p.id;
  }
  return null;
}
