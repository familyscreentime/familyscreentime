import 'package:screentime_engine/screentime_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('Turned-off rules', () {
    const rule = Rule(id: 'r', childId: child, dailyQuota: Duration(hours: 1));

    test('a rule turned off never applies', () {
      final state = FamilyState(
        rules: [rule.withEnabled(false)],
        usage: [use(tablet, 'minecraft', at(5, 9), 90)],
      );
      final d = check(state, at(5, 12));
      expect(d.allowed, isTrue);
      expect(d.reason, Reason.noRule);
    });

    test('turned back on, it counts the day as usual', () {
      final state = FamilyState(
        rules: [rule.withEnabled(false).withEnabled(true)],
        usage: [use(tablet, 'minecraft', at(5, 9), 40)],
      );
      expect(check(state, at(5, 12)).remaining, min(20));
    });

    test('the switch survives a round trip, and is left out when on', () {
      final off = ruleFromJson(ruleToJson(rule.withEnabled(false)));
      expect(off.enabled, isFalse);
      expect(off.dailyQuota, const Duration(hours: 1));
      expect(ruleToJson(rule).containsKey('enabled'), isFalse);
      expect(ruleFromJson(ruleToJson(rule)).enabled, isTrue);
    });
  });
}
