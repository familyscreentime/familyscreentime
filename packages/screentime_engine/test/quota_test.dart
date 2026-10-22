import 'package:screentime_engine/screentime_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  final games60 = Rule(
    id: 'games',
    childId: child,
    appTarget: const AppTarget.group('games'),
    dailyQuota: min(60),
  );

  group('Daily quota', () {
    test('time on all of the child\'s devices adds up', () {
      final state = FamilyState(
        rules: [games60],
        usage: [
          use(tablet, 'minecraft', at(5, 9), 20),
          use(phone, 'roblox', at(5, 10), 15),
          use(phone, 'youtube', at(5, 10, 30), 40), // not in the group
          use(tablet, 'minecraft', at(4, 9), 50), // the day before
          use(tablet, 'minecraft', at(5, 9), 30, childId: 'leo'),
        ],
      );
      final d = check(state, at(5, 11));
      expect(d.reason, Reason.withinLimits);
      expect(d.remaining, min(25));
      expect(d.limiter, Limiter.quota);
      expect(d.ruleId, 'games');
    });

    test('quota exhausted, no grace: blocked', () {
      final state = FamilyState(
        rules: [games60],
        usage: [use(tablet, 'minecraft', at(5, 9), 60)],
      );
      final d = check(state, at(5, 10));
      expect(d.allowed, isFalse);
      expect(d.reason, Reason.quotaExhausted);
      expect(d.ruleId, 'games');
    });
  });

  group('Simultaneous use', () {
    final state = FamilyState(
      rules: [games60],
      usage: [
        use(tablet, 'minecraft', at(5, 9), 30),
        use(phone, 'roblox', at(5, 9, 10), 30),
      ],
    );

    test('by default, both durations count', () {
      expect(check(state, at(5, 10)).reason, Reason.quotaExhausted);
    });

    test('optionally, only elapsed time counts', () {
      final cfg = configWith(counting: SimultaneousCounting.elapsed);
      expect(check(state, at(5, 10), cfg: cfg).remaining, min(20));
    });
  });

  test('an app in two groups is subject to both limits', () {
    final state = FamilyState(
      rules: [
        games60,
        Rule(
          id: 'creative',
          childId: child,
          appTarget: const AppTarget.group('creative'),
          dailyQuota: min(30),
        ),
      ],
      usage: [use(tablet, 'minecraft', at(5, 9), 20)],
    );
    final minecraft = check(state, at(5, 10), app: 'minecraft');
    expect(minecraft.remaining, min(10));
    expect(minecraft.ruleId, 'creative');
    expect(check(state, at(5, 10), app: 'roblox').remaining, min(40));
  });

  test('always-allowed apps and system components consume nothing', () {
    final state = FamilyState(
      rules: [Rule(id: 'all', childId: child, dailyQuota: min(60))],
      usage: [
        use(phone, 'sms', at(5, 9), 30),
        use(phone, 'launcher', at(5, 9, 30), 20),
        use(phone, 'youtube', at(5, 10), 10),
      ],
    );
    expect(check(state, at(5, 11), app: 'youtube').remaining, min(50));
  });

  test('a limit set by the child restricts like any other', () {
    final state = FamilyState(
      rules: [
        games60,
        Rule(
          id: 'mine',
          childId: child,
          appTarget: const AppTarget.app('roblox'),
          dailyQuota: min(15),
          setByChild: true,
        ),
      ],
    );
    expect(check(state, at(5, 10), app: 'roblox').remaining, min(15));
    expect(check(state, at(5, 10), app: 'minecraft').remaining, min(60));
  });

  group('Week and rolling window', () {
    final weekly = Rule(id: 'w', childId: child, weeklyQuota: min(120));

    test('the weekly quota adds up the days of the week', () {
      final state = FamilyState(
        rules: [weekly],
        usage: [
          use(tablet, 'minecraft', at(5, 9), 60),
          use(tablet, 'minecraft', at(6, 9), 50),
        ],
      );
      expect(check(state, at(7, 10)).remaining, min(10));
    });

    test('the first day of the week is configurable', () {
      // The 4th is a Sunday.
      final state = FamilyState(
        rules: [weekly],
        usage: [use(tablet, 'minecraft', at(4, 9), 60)],
      );
      expect(check(state, at(5, 10)).remaining, min(120));
      final sunday = configWith(weekStart: DateTime.sunday);
      expect(check(state, at(5, 10), cfg: sunday).remaining, min(60));
    });

    test('the X-day window slides and ends today', () {
      final state = FamilyState(
        rules: [
          Rule(
            id: 'x',
            childId: child,
            rollingQuota: RollingQuota(days: 3, quota: min(100)),
          ),
        ],
        usage: [
          use(
            tablet,
            'minecraft',
            at(3, 9),
            50,
          ), // outside the window on the 6th
          use(tablet, 'minecraft', at(4, 9), 30),
          use(tablet, 'minecraft', at(5, 9), 10),
        ],
      );
      expect(check(state, at(6, 10)).remaining, min(60));
    });
  });

  group('Injected time', () {
    final allDevices = games60;
    final tabletsOnly = Rule(
      id: 'tablets',
      childId: child,
      appTarget: const AppTarget.group('games'),
      deviceTarget: const DeviceTarget.group('tablets'),
      dailyQuota: min(60),
    );

    test('it counts towards rules that target all devices', () {
      final state = FamilyState(
        rules: [allDevices, tabletsOnly],
        usage: [
          UsageSegment.injected(
            childId: child,
            injectedTarget: const AppTarget.group('games'),
            start: at(5, 15),
            end: at(5, 15, 30),
          ),
        ],
      );
      final d = check(state, at(5, 16));
      expect(d.remaining, min(30));
      expect(d.ruleId, 'games');
    });

    test('an injected app counts towards the groups containing it', () {
      final state = FamilyState(
        rules: [allDevices],
        usage: [
          UsageSegment.injected(
            childId: child,
            injectedTarget: const AppTarget.app('minecraft'),
            start: at(5, 15),
            end: at(5, 15, 45),
          ),
        ],
      );
      expect(check(state, at(5, 16), app: 'roblox').remaining, min(15));
    });
  });
}
