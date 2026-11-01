import 'package:screentime_engine/screentime_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  const leo = 'leo';
  // Emma has her own lists: messages at any time, the phone within the
  // hours. Leo keeps the family's (the phone and messages at any time).
  final cfg = config.withAccess(
    child,
    alwaysAllowed: {'sms'},
    allowedInHours: {'dialer', 'whatsapp'},
  );
  final engine = RuleEngine(cfg);
  final emmaHours = Rule(
    id: 'h-emma',
    childId: child,
    schedule: WeeklySchedule({
      for (var d = DateTime.monday; d <= DateTime.sunday; d++)
        d: [TimeRange.hm(9, 0, 18, 0)],
    }),
  );
  final leoHours = Rule(
    id: 'h-leo',
    childId: leo,
    schedule: WeeklySchedule({
      for (var d = DateTime.monday; d <= DateTime.sunday; d++)
        d: [TimeRange.hm(9, 0, 18, 0)],
    }),
  );
  const total = Rule(id: 'all', childId: child, dailyQuota: Duration(hours: 1));

  Decision eval(String who, String app, DateTime now) => engine.evaluate(
    FamilyState(rules: [emmaHours, leoHours, total]),
    childId: who,
    deviceId: tablet,
    appId: app,
    now: now,
  );

  test('each child their own lists, the others the family\'s', () {
    expect(cfg.alwaysAllowedFor(child), {'sms'});
    expect(cfg.allowedInHoursFor(child), {'dialer', 'whatsapp'});
    expect(cfg.alwaysAllowedFor(leo), {'sms', 'dialer'});
    expect(cfg.allowedInHoursFor(leo), isEmpty);
    expect(cfg.hasOwnAccess(child), isTrue);
    expect(cfg.hasOwnAccess(leo), isFalse);
  });

  test('outside the hours: only each child\'s apps at any time', () {
    final night = at(5, 21);
    expect(eval(child, 'sms', night).allowed, isTrue);
    expect(eval(child, 'dialer', night).allowed, isFalse);
    expect(eval(leo, 'dialer', night).allowed, isTrue);
    expect(eval(leo, 'whatsapp', night).allowed, isFalse);
  });

  test('within the hours, never counted for that child only', () {
    final usage = [
      use(tablet, 'whatsapp', at(5, 10), 40),
      use(tablet, 'minecraft', at(5, 11), 10),
    ];
    final used = engine.consumption(
      FamilyState(rules: const [total], usage: usage),
      total,
      childId: child,
      from: at(5, 0),
      to: at(5, 12),
    );
    expect(used, min(10));
    expect(eval(child, 'whatsapp', at(5, 12)).reason, Reason.alwaysAllowed);
  });

  test('survive JSON; none: the field is left out', () {
    final back = familyConfigFromJson(familyConfigToJson(cfg));
    expect(back.alwaysAllowedFor(child), {'sms'});
    expect(back.allowedInHoursFor(child), {'dialer', 'whatsapp'});
    expect(back.hasOwnAccess(leo), isFalse);
    expect(
      familyConfigToJson(config).containsKey('alwaysAllowedByChild'),
      isFalse,
    );
  });

  test('an empty list of one\'s own is still one\'s own', () {
    final none = config.withAccess(
      child,
      alwaysAllowed: {},
      allowedInHours: {},
    );
    final back = familyConfigFromJson(familyConfigToJson(none));
    expect(back.hasOwnAccess(child), isTrue);
    expect(back.alwaysAllowedFor(child), isEmpty);
  });
}
