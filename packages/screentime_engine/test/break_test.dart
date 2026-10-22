import 'package:screentime_engine/screentime_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  // 10-minute break after 30 minutes of continuous use.
  FamilyState state(List<UsageSegment> usage) => FamilyState(
    rules: [
      Rule(
        id: 'p',
        childId: child,
        breakPolicy: BreakPolicy(after: min(30), length: min(10)),
      ),
    ],
    usage: usage,
  );

  group('Mandatory break', () {
    test('30 continuous minutes trigger a 10-minute break', () {
      final s = state([use(tablet, 'minecraft', at(5, 9), 30)]);
      final d = check(s, at(5, 9, 30));
      expect(d.allowed, isFalse);
      expect(d.reason, Reason.mandatoryBreak);
      expect(d.until, at(5, 9, 40));
    });

    test('after the break, the counter starts from zero', () {
      final s = state([use(tablet, 'minecraft', at(5, 9), 30)]);
      final d = check(s, at(5, 9, 40));
      expect(d.allowed, isTrue);
      expect(d.remaining, min(30));
      expect(d.limiter, Limiter.breakDue);
    });

    test('the countdown shows the time before the break', () {
      final s = state([use(tablet, 'minecraft', at(5, 9), 12)]);
      expect(check(s, at(5, 9, 12)).remaining, min(18));
    });

    test('a short interruption does not reset the counter', () {
      final s = state([
        use(tablet, 'minecraft', at(5, 9), 20),
        use(tablet, 'minecraft', at(5, 9, 25), 8),
      ]);
      expect(check(s, at(5, 9, 33)).remaining, min(2));
      final full = state([
        use(tablet, 'minecraft', at(5, 9), 20),
        use(tablet, 'minecraft', at(5, 9, 25), 10),
      ]);
      expect(check(full, at(5, 9, 35)).until, at(5, 9, 45));
    });

    test('an interruption as long as the break resets it', () {
      final s = state([
        use(tablet, 'minecraft', at(5, 9), 20),
        use(tablet, 'minecraft', at(5, 9, 35), 5),
      ]);
      expect(check(s, at(5, 9, 40)).remaining, min(25));
    });

    test('no use for the length of a break resets everything', () {
      final s = state([use(tablet, 'minecraft', at(5, 9), 20)]);
      expect(check(s, at(5, 9, 35)).remaining, min(30));
      expect(check(s, at(5, 9, 25)).remaining, min(10));
    });

    test('two devices at once make a single session', () {
      final s = state([
        use(tablet, 'minecraft', at(5, 9), 20),
        use(phone, 'roblox', at(5, 9, 10), 15),
      ]);
      expect(check(s, at(5, 9, 25)).remaining, min(5));
    });

    test('injected time does not trigger a break', () {
      final s = state([
        UsageSegment.injected(
          childId: child,
          injectedTarget: const AppTarget.all(),
          start: at(5, 9),
          end: at(5, 9, 40),
        ),
      ]);
      expect(check(s, at(5, 9, 40)).allowed, isTrue);
    });
  });
}
