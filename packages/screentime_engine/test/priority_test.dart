import 'package:screentime_engine/screentime_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('Evaluation order', () {
    test('"Always allowed" apps pass even during a family block', () {
      final state = FamilyState(
        familyBlocks: [FamilyBlock(id: 'f', from: at(5, 8))],
      );
      expect(check(state, at(5, 10), app: 'sms').reason, Reason.alwaysAllowed);
      expect(check(state, at(5, 10), app: 'launcher').allowed, isTrue);
    });

    test('a family block blocks everything, then lifts at its end', () {
      final state = FamilyState(
        familyBlocks: [FamilyBlock(id: 'f', from: at(5, 8), until: at(5, 12))],
      );
      final during = check(state, at(5, 11));
      expect(during.allowed, isFalse);
      expect(during.reason, Reason.familyBlock);
      expect(during.until, at(5, 12));
      expect(check(state, at(5, 12)).reason, Reason.noRule);
    });

    test('an open-ended family block announces no end', () {
      final state = FamilyState(
        familyBlocks: [FamilyBlock(id: 'f', from: at(5, 8))],
      );
      expect(check(state, at(5, 11)).until, isNull);
    });

    test('a temporary block can target a device group', () {
      final state = FamilyState(
        temporaryBlocks: [
          TemporaryBlock(
            id: 'b',
            childId: child,
            deviceTarget: const DeviceTarget.group('tablets'),
            from: at(5, 9),
            until: at(5, 11),
          ),
        ],
      );
      final onTablet = check(state, at(5, 10), device: tablet);
      expect(onTablet.reason, Reason.temporaryBlock);
      expect(onTablet.until, at(5, 11));
      expect(check(state, at(5, 10), device: phone).allowed, isTrue);
    });

    test('another child\'s block does not apply', () {
      final state = FamilyState(
        temporaryBlocks: [
          TemporaryBlock(id: 'b', childId: 'leo', from: at(5, 9)),
        ],
      );
      expect(check(state, at(5, 10)).allowed, isTrue);
    });

    test('a day unlock suspends schedules and quotas', () {
      final state = FamilyState(
        rules: [
          Rule(
            id: 'r',
            childId: child,
            schedule: WeeklySchedule.everyDay([TimeRange.hm(8, 0, 20, 0)]),
            dailyQuota: min(60),
          ),
        ],
        usage: [use(tablet, 'minecraft', at(5, 9), 120)],
        dayUnlocks: [DayUnlock(id: 'u', childId: child, day: at(5, 0))],
      );
      final d = check(state, at(5, 22));
      expect(d.allowed, isTrue);
      expect(d.reason, Reason.dayUnlocked);
      expect(d.until, at(6, 0));
      // The next day, the rules are back.
      expect(check(state, at(6, 22)).reason, Reason.outsideSchedule);
    });

    test('a temporary block wins over a day unlock', () {
      final state = FamilyState(
        dayUnlocks: [DayUnlock(id: 'u', childId: child, day: at(5, 0))],
        temporaryBlocks: [
          TemporaryBlock(id: 'b', childId: child, from: at(5, 9)),
        ],
      );
      expect(check(state, at(5, 10)).reason, Reason.temporaryBlock);
    });

    test('with no applicable rule, use is unrestricted', () {
      final state = FamilyState(
        rules: [
          Rule(
            id: 'video',
            childId: child,
            appTarget: const AppTarget.group('video'),
            dailyQuota: min(30),
          ),
        ],
      );
      final d = check(state, at(5, 10), app: 'minecraft');
      expect(d.reason, Reason.noRule);
      expect(d.remaining, isNull);
    });
  });
}
