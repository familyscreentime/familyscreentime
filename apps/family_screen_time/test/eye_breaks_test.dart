import 'package:family_screen_time/src/eye_breaks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screentime_engine/screentime_engine.dart';

void main() {
  const policy = EyeBreakPolicy();
  final start = DateTime(2026, 10, 28, 15);
  DateTime t(int minutes, [int seconds = 0]) =>
      start.add(Duration(minutes: minutes, seconds: seconds));

  late EyeBreaks eye;
  setUp(() => eye = EyeBreaks());

  /// [rested]: the screen has been unused long enough, no stretch.
  EyeStep step(
    DateTime now, {
    DateTime? from,
    bool rested = false,
    bool blockSoon = false,
  }) => eye.step(
    policy: policy,
    stretchStart: rested ? null : from ?? start,
    now: now,
    blockSoon: blockSoon,
  );

  test('nothing before 20 minutes of use, then the next step is due', () {
    expect(step(t(12)).kind, EyeStepKind.none);
    expect(
      eye.next(policy: policy, stretchStart: start, now: t(12)),
      const Duration(minutes: 8),
    );
  });

  test('announced, then the veil after 10 seconds, for 20 seconds', () {
    final notice = step(t(20));
    expect(notice.kind, EyeStepKind.notice);
    expect(notice.snoozesLeft, 3);
    expect(step(t(20, 5)).kind, EyeStepKind.none);
    final veil = step(t(20, 10));
    expect(veil.kind, EyeStepKind.veil);
    expect(veil.length, const Duration(seconds: 20));
    expect(veil.until, t(20, 30));
    expect(eye.veilUntil(t(20, 20)), t(20, 30));
    expect(step(t(20, 20)).kind, EyeStepKind.none);
    expect(step(t(20, 30)).kind, EyeStepKind.hide);
    expect(eye.restedAt, t(20, 30));
    expect(eye.veilUntil(t(20, 31)), isNull);
  });

  test('"now" starts the veil at once', () {
    step(t(20));
    eye.startNow(t(20, 2));
    expect(step(t(20, 2)).kind, EyeStepKind.veil);
  });

  test('put off by a minute, three times, each break longer', () {
    expect(step(t(20)).snoozesLeft, 3);
    expect(eye.snooze(policy, t(20, 3)), isTrue);
    expect(step(t(21)).kind, EyeStepKind.none);
    expect(step(t(21, 3)).snoozesLeft, 2);
    eye.snooze(policy, t(21, 4));
    expect(step(t(22, 4)).snoozesLeft, 1);
    eye.snooze(policy, t(22, 5));
    final last = step(t(23, 5));
    expect(last.kind, EyeStepKind.notice);
    expect(last.snoozesLeft, 0);
    expect(eye.snooze(policy, t(23, 6)), isFalse);
    final veil = step(t(23, 15));
    expect(veil.kind, EyeStepKind.veil);
    expect(veil.length, const Duration(seconds: 23));
  });

  test('a new stretch of use gives the put-offs back', () {
    step(t(20));
    eye.snooze(policy, t(20, 1));
    // The screen stayed off: the next stretch starts later.
    expect(step(t(25), rested: true).kind, EyeStepKind.none);
    final later = t(30);
    expect(step(later.add(policy.every), from: later).snoozesLeft, 3);
  });

  test('the screen going off takes the notice down', () {
    step(t(20));
    expect(step(t(20, 4), rested: true).kind, EyeStepKind.hide);
  });

  test('a limit about to end comes first', () {
    expect(step(t(20), blockSoon: true).kind, EyeStepKind.none);
    expect(eye.next(policy: policy, stretchStart: start, now: t(20)), isNull);
  });

  test('during a call, tried again 30 seconds later', () {
    step(t(20));
    eye.busy(t(20, 1));
    expect(step(t(20, 20)).kind, EyeStepKind.none);
    final again = step(t(20, 31));
    expect(again.kind, EyeStepKind.notice);
    expect(again.snoozesLeft, 3);
  });

  test('reminder only: no veil, and the stretch ends', () {
    final reminder = eye.step(
      policy: policy.copyWith(veil: false),
      stretchStart: start,
      now: t(20),
    );
    expect(reminder.kind, EyeStepKind.reminder);
    expect(reminder.length, const Duration(seconds: 20));
    expect(eye.restedAt, t(20));
  });

  test('turned off: nothing, and what was shown goes', () {
    step(t(20));
    final off = eye.step(
      policy: policy.copyWith(enabled: false),
      stretchStart: start,
      now: t(20, 1),
    );
    expect(off.kind, EyeStepKind.hide);
  });
}
