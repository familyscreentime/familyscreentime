import 'package:screentime_engine/screentime_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  const rest = Duration(seconds: 20);

  DateTime? stretch(
    List<UsageSegment> usage,
    DateTime now, {
    DateTime? restedAt,
  }) => screenStretchStart(
    usage,
    deviceId: tablet,
    now: now,
    rest: rest,
    restedAt: restedAt,
  );

  UsageSegment seconds(String device, String app, DateTime start, int s) =>
      UsageSegment.device(
        childId: child,
        deviceId: device,
        appId: app,
        start: start,
        end: start.add(Duration(seconds: s)),
      );

  group('Stretch of screen use', () {
    test('runs across apps, home screen included', () {
      final usage = [
        use(tablet, 'minecraft', at(5, 9), 10),
        use(tablet, 'launcher', at(5, 9, 10), 1),
        use(tablet, 'reader', at(5, 9, 11), 9),
      ];
      expect(stretch(usage, at(5, 9, 20)), at(5, 9));
    });

    test('a gap shorter than the rest does not end it', () {
      final usage = [
        use(tablet, 'minecraft', at(5, 9), 10),
        seconds(tablet, 'youtube', at(5, 9, 10).add(rest * 0.5), 600),
      ];
      expect(stretch(usage, at(5, 9, 16)), at(5, 9));
    });

    test('a gap as long as the rest starts a new one', () {
      final usage = [
        use(tablet, 'minecraft', at(5, 9), 10),
        seconds(tablet, 'youtube', at(5, 9, 10).add(rest), 600),
      ];
      expect(stretch(usage, at(5, 9, 16)), at(5, 9, 10).add(rest));
    });

    test('none once the screen has been unused for the rest', () {
      final usage = [use(tablet, 'minecraft', at(5, 9), 10)];
      expect(stretch(usage, at(5, 9, 10).add(rest)), isNull);
      expect(stretch(usage, at(5, 9, 10).add(rest * 0.5)), at(5, 9));
    });

    test('other devices do not count', () {
      final usage = [
        use(phone, 'minecraft', at(5, 9), 10),
        use(tablet, 'minecraft', at(5, 9, 10), 5),
      ];
      expect(stretch(usage, at(5, 9, 15)), at(5, 9, 10));
    });

    test('apps beside the one in front overlap it and count once', () {
      final usage = [
        use(tablet, 'minecraft', at(5, 9), 15),
        use(tablet, 'youtube', at(5, 9, 5), 20),
        use(tablet, 'reader', at(5, 9, 25), 5),
      ];
      expect(stretch(usage, at(5, 9, 30)), at(5, 9));
    });

    test('starts no earlier than the last rest', () {
      final usage = [use(tablet, 'minecraft', at(5, 9), 30)];
      expect(
        stretch(usage, at(5, 9, 30), restedAt: at(5, 9, 12)),
        at(5, 9, 12),
      );
      expect(stretch(usage, at(5, 9, 30), restedAt: at(5, 9, 40)), isNull);
    });
  });

  group('Eye break policy', () {
    const p = EyeBreakPolicy();

    test('20 minutes of use, then 20 seconds by default', () {
      expect(p.enabled, isTrue);
      expect(p.every, min(20));
      expect(p.length, const Duration(seconds: 20));
      expect(p.snoozes, 3);
      expect(p.veil, isTrue);
    });

    test('a later break lasts longer, in proportion', () {
      expect(p.lengthAfter(min(19)), const Duration(seconds: 20));
      expect(p.lengthAfter(min(20)), const Duration(seconds: 20));
      expect(p.lengthAfter(min(23)), const Duration(seconds: 23));
      expect(
        p.lengthAfter(const Duration(minutes: 21, seconds: 30)),
        const Duration(seconds: 22),
      );
      expect(
        p.lengthAfter(const Duration(hours: 3)),
        const Duration(seconds: 60),
      );
    });

    test('JSON round trip, defaults for what is missing', () {
      const changed = EyeBreakPolicy(
        enabled: false,
        every: Duration(minutes: 30),
        length: Duration(seconds: 40),
        snoozes: 0,
        veil: false,
      );
      expect(EyeBreakPolicy.fromJson(changed.toJson()), changed);
      expect(EyeBreakPolicy.fromJson(const {}), p);
    });
  });
}
