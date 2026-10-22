import 'dart:convert';

import 'package:screentime_engine/screentime_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// Encodes, goes through a real JSON string, and decodes.
T roundTrip<T>(T value, Json Function(T) encode, T Function(Json) decode) =>
    decode(jsonDecode(jsonEncode(encode(value))) as Json);

void main() {
  group('JSON', () {
    test('a fully specified rule survives a round trip', () {
      final rule = Rule(
        id: 'games',
        childId: child,
        profileId: 'normal',
        appTarget: const AppTarget.group('games'),
        deviceTarget: const DeviceTarget.device(tablet),
        schedule: WeeklySchedule({
          DateTime.monday: [
            TimeRange.hm(8, 0, 12, 0),
            TimeRange.hm(14, 0, 20, 0),
          ],
          DateTime.saturday: [TimeRange.hm(9, 0, 21, 0)],
        }),
        dailyQuota: min(60),
        weeklyQuota: min(300),
        rollingQuota: RollingQuota(days: 3, quota: min(150)),
        breakPolicy: BreakPolicy(after: min(30), length: min(10)),
        grace: GracePolicy(
          length: min(10),
          hardening: HardeningPolicy(threshold: min(5), days: 2, window: 7),
        ),
        carryOver: const CarryOverPolicy.spread(3),
        rollover: RolloverPolicy(days: 1, cap: min(30)),
        setByChild: true,
      );
      final copy = roundTrip(rule, ruleToJson, ruleFromJson);
      expect(ruleToJson(copy), ruleToJson(rule));
      expect(copy.schedule!.allows(at(5, 9)), isTrue);
      expect(copy.schedule!.allows(at(5, 13)), isFalse);
      expect(copy.rollover!.cap, min(30));
      expect(copy.carryOver.days, 3);
    });

    test('a minimal rule stays minimal', () {
      final rule = Rule(id: 'r', childId: child, dailyQuota: min(45));
      expect(ruleToJson(rule).keys, {
        'id',
        'childId',
        'appTarget',
        'deviceTarget',
        'dailyQuota',
      });
      final copy = roundTrip(rule, ruleToJson, ruleFromJson);
      expect(copy.appTarget, const AppTarget.all());
      expect(copy.carryOver.mode, CarryOverMode.none);
      expect(copy.rollover, isNull);
    });

    test('the family configuration survives a round trip', () {
      final cfg = configWith(
        counting: SimultaneousCounting.elapsed,
        weekStart: DateTime.sunday,
        profiles: [
          Profile(
            id: 'holidays',
            name: 'Holidays',
            kind: ProfileKind.vacation,
            periods: [DateRange(at(12, 0), at(16, 0))],
          ),
        ],
      );
      final copy = roundTrip(cfg, familyConfigToJson, familyConfigFromJson);
      expect(familyConfigToJson(copy), familyConfigToJson(cfg));
      expect(copy.profiles.single.isScheduledOn(at(14, 10)), isTrue);
    });

    test('state and usage survive a round trip and give the same decision', () {
      final state = FamilyState(
        rules: [
          Rule(
            id: 'games',
            childId: child,
            appTarget: const AppTarget.group('games'),
            dailyQuota: min(60),
          ),
        ],
        usage: [
          use(tablet, 'minecraft', at(5, 9), 30),
          UsageSegment.injected(
            childId: child,
            injectedTarget: const AppTarget.group('games'),
            start: at(5, 15),
            end: at(5, 15, 10),
          ),
        ],
        bonuses: [
          Bonus.forRule(
            id: 'b',
            childId: child,
            ruleId: 'games',
            amount: min(5),
            grantedAt: at(5, 10),
            validUntil: at(6, 0),
          ),
        ],
        temporaryBlocks: [
          TemporaryBlock(
            id: 't',
            childId: child,
            deviceTarget: const DeviceTarget.group('tablets'),
            from: at(4, 9),
            until: at(4, 10),
          ),
          TemporaryBlock(
            id: 'p',
            childId: child,
            from: at(4, 15),
            until: at(4, 15).add(min(15)),
            voluntary: true,
          ),
        ],
        dayUnlocks: [DayUnlock(id: 'u', childId: child, day: at(1, 0))],
        familyBlocks: [FamilyBlock(id: 'f', from: at(3, 8), until: at(3, 9))],
      );
      final copy = roundTrip(
        state,
        (s) => familyStateToJson(s, includeUsage: true),
        familyStateFromJson,
      );
      expect(
        familyStateToJson(copy, includeUsage: true),
        familyStateToJson(state, includeUsage: true),
      );
      expect(check(copy, at(5, 16)).remaining, min(25));
      expect(copy.temporaryBlocks.last.voluntary, isTrue);
      expect(copy.temporaryBlocks.first.voluntary, isFalse);
    });

    test('calendar days are written as YYYY-MM-DD', () {
      expect(dayToJson(at(5, 23)), '2026-10-05');
      expect(dayFromJson('2026-10-05'), DateTime(2026, 10, 5));
    });
  });
}
