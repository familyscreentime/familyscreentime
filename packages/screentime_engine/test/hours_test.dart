import 'package:screentime_engine/screentime_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  // Hours 10:00–12:00 every day, 1 h a day.
  final rule = Rule(
    id: 'r',
    childId: child,
    dailyQuota: const Duration(hours: 1),
    schedule: WeeklySchedule({
      for (var d = DateTime.monday; d <= DateTime.sunday; d++)
        d: [TimeRange.hm(10, 0, 12, 0)],
    }),
  );

  group('Hours opened early', () {
    test('open from 9:20, closed again at 12:00', () {
      final state = FamilyState(
        rules: [rule],
        hoursUnlocks: [
          HoursUnlock(
            id: 'u',
            childId: child,
            ruleId: 'r',
            from: at(5, 9, 20),
            until: at(5, 12),
          ),
        ],
      );
      final early = check(state, at(5, 9, 30));
      expect(early.allowed, isTrue);
      // The time limit still applies, and the opening ends at 12:00.
      expect(early.remaining, min(60));
      expect(check(state, at(5, 11, 30)).remaining, min(30));
      expect(check(state, at(5, 12, 5)).reason, Reason.outsideSchedule);
      expect(
        check(const FamilyState().copyWith(rules: [rule]), at(5, 9, 30)).reason,
        Reason.outsideSchedule,
      );
    });

    test('survives a round trip', () {
      final state = FamilyState(
        rules: [rule],
        hoursUnlocks: [
          HoursUnlock(
            id: 'u',
            childId: child,
            ruleId: 'r',
            from: at(5, 9, 20),
            until: at(5, 12),
          ),
        ],
      );
      final copy = familyStateFromJson(familyStateToJson(state));
      expect(copy.hoursUnlocks.single.until, at(5, 12));
      expect(check(copy, at(5, 9, 30)).allowed, isTrue);
    });
  });

  group('Apps open within the hours', () {
    final config = FamilyConfig(
      alwaysAllowed: const {'dialer'},
      allowedInHours: const {'sms'},
    );
    Decision ask(FamilyState s, DateTime t, String app) => RuleEngine(
      config,
    ).evaluate(s, childId: child, deviceId: tablet, appId: app, now: t);

    test('not limited by time, but closed outside the hours', () {
      final state = FamilyState(
        rules: [rule],
        usage: [use(tablet, 'youtube', at(5, 10), 60)],
      );
      // Time used up: other apps are blocked, messages are not.
      expect(ask(state, at(5, 11, 10), 'youtube').allowed, isFalse);
      expect(ask(state, at(5, 11, 10), 'sms').allowed, isTrue);
      // Outside the hours: messages closed, the phone still open.
      expect(ask(state, at(5, 13), 'sms').reason, Reason.outsideSchedule);
      expect(ask(state, at(5, 13), 'dialer').allowed, isTrue);
    });

    test('their time is not counted', () {
      final state = FamilyState(
        rules: [rule],
        usage: [use(tablet, 'sms', at(5, 10), 50)],
      );
      expect(ask(state, at(5, 11), 'youtube').remaining, min(60));
      final json = familyConfigFromJson(familyConfigToJson(config));
      expect(json.allowedInHours, {'sms'});
    });
  });
}
