import 'package:family_screen_time/src/strings.dart';
import 'package:family_screen_time/src/usage_period.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final s = S.of('fr');
  // Wednesday 18 November 2026.
  final now = DateTime(2026, 11, 18, 15);

  UsagePeriod at(PeriodKind kind, [int weekStart = DateTime.monday]) =>
      UsagePeriod.at(kind, now, weekStart: weekStart);

  test('days are named from today', () {
    final day = at(PeriodKind.day);
    expect(day.label(s, now), "Aujourd'hui");
    expect(day.shifted(-1, weekStart: 1).label(s, now), 'Hier');
    expect(day.shifted(-2, weekStart: 1).label(s, now), 'Lundi 16/11');
  });

  test('weeks begin on the family\'s first day', () {
    final week = at(PeriodKind.week);
    expect(week.first, DateTime(2026, 11, 16));
    expect(week.length, 7);
    expect(week.label(s, now), 'Cette semaine');
    expect(week.shifted(-1, weekStart: 1).label(s, now), 'Semaine dernière');
    expect(week.shifted(-2, weekStart: 1).label(s, now), 'Du 02/11 au 08/11');
    expect(at(PeriodKind.week, DateTime.sunday).first, DateTime(2026, 11, 15));
  });

  test('months have their own number of days', () {
    final month = at(PeriodKind.month);
    expect(month.first, DateTime(2026, 11));
    expect(month.length, 30);
    expect(month.label(s, now), 'Novembre 2026');
    final feb = month.shifted(-9, weekStart: 1);
    expect(feb.first, DateTime(2026, 2));
    expect(feb.length, 28);
    // Across a daylight saving change: still whole days.
    expect(month.shifted(-1, weekStart: 1).length, 31);
    expect(
      month.shifted(-1, weekStart: 1).label(S.of('en'), now),
      'October 2026',
    );
    expect(month.shifted(2, weekStart: 1).label(s, now), 'Janvier 2027');
  });
}
