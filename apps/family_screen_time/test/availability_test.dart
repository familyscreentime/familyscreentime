import 'package:family_screen_time/src/availability.dart';
import 'package:family_screen_time/src/strings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screentime_engine/screentime_engine.dart';

void main() {
  const s = S('fr');
  // Wednesday 21 October 2026, 18:00.
  final now = DateTime(2026, 10, 21, 18);
  final today = dayOf(now);
  final engine = RuleEngine(const FamilyConfig());

  UsageSegment used(int minutes) => UsageSegment.device(
    childId: 'emma',
    deviceId: 'd',
    appId: 'youtube',
    start: today.add(const Duration(hours: 15)),
    end: today.add(Duration(hours: 15, minutes: minutes)),
  );

  String? message(Rule rule) {
    final state = FamilyState(rules: [rule], usage: [used(60)]);
    return timeOverMessage(
      s,
      nextAvailable(engine, state, childId: 'emma', deviceId: 'd', now: now),
      now,
    );
  }

  test('without hours, see you tomorrow', () {
    expect(
      message(
        const Rule(id: 'all', childId: 'emma', dailyQuota: Duration(hours: 1)),
      ),
      'Ton temps d\'aujourd\'hui est écoulé. On se retrouve demain.',
    );
  });

  test('with hours from 9, see you tomorrow from 9', () {
    final days = {
      for (var d = DateTime.monday; d <= DateTime.sunday; d++)
        d: [TimeRange.hm(9, 0, 20, 0)],
    };
    expect(
      message(
        Rule(
          id: 'all',
          childId: 'emma',
          dailyQuota: const Duration(hours: 1),
          schedule: WeeklySchedule(days),
        ),
      ),
      'Ton temps d\'aujourd\'hui est écoulé. On se retrouve demain à partir de 9h.',
    );
  });

  test('two days without screens: in 3 days', () {
    expect(
      message(
        const Rule(
          id: 'all',
          childId: 'emma',
          dailyQuota: Duration(hours: 1),
          // Thursday and Friday without screens.
          dailyQuotaByWeekday: {
            DateTime.thursday: Duration.zero,
            DateTime.friday: Duration.zero,
          },
        ),
      ),
      'Ton temps d\'aujourd\'hui est écoulé. On se retrouve dans 3 jours.',
    );
  });

  test('back later today: no "see you" message', () {
    final back = DateTime(2026, 10, 21, 19, 30);
    expect(timeOverMessage(s, back, now), isNull);
    expect(
      whenBack(s, DateTime(2026, 10, 23, 14, 30), now),
      'après-demain à partir de 14h30',
    );
    expect(const S('en').hour(DateTime(2026, 1, 1, 9)), '9:00');
    expect(const S('nl').hour(DateTime(2026, 1, 1, 9, 30)), '9.30 uur');
  });
}
