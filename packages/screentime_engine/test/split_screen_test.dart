import 'package:screentime_engine/screentime_engine.dart';
import 'package:test/test.dart';

void main() {
  final t0 = DateTime(2026, 10, 25, 15);
  UsageSegment use(String device, String app, int from, int to) =>
      UsageSegment.device(
        childId: 'emma',
        deviceId: device,
        appId: app,
        start: t0.add(Duration(minutes: from)),
        end: t0.add(Duration(minutes: to)),
      );
  Duration used(List<UsageSegment> usage, Rule r, {bool elapsed = false}) =>
      RuleEngine(
        FamilyConfig(
          appGroups: const {
            'games': {'game', 'video'},
          },
          counting: elapsed
              ? SimultaneousCounting.elapsed
              : SimultaneousCounting.sum,
        ),
      ).consumption(
        FamilyState(usage: usage),
        r,
        childId: 'emma',
        from: t0,
        to: t0.add(const Duration(hours: 2)),
      );

  test('two apps on one screen count once, two screens twice', () {
    const all = Rule(id: 'all', childId: 'emma');
    const games = Rule(
      id: 'games',
      childId: 'emma',
      appTarget: AppTarget.group('games'),
    );
    const video = Rule(
      id: 'video',
      childId: 'emma',
      appTarget: AppTarget.app('video'),
    );
    // Split screen on the tablet: a game, and a video beside it.
    final split = [use('tab', 'game', 0, 30), use('tab', 'video', 10, 40)];
    expect(used(split, all), const Duration(minutes: 40));
    expect(used(split, games), const Duration(minutes: 40));
    expect(used(split, video), const Duration(minutes: 30));
    // On two devices at once: both count (unless only elapsed time does).
    final two = [use('tab', 'game', 0, 30), use('phone', 'video', 10, 40)];
    expect(used(two, all), const Duration(minutes: 60));
    expect(used(two, all, elapsed: true), const Duration(minutes: 40));
  });
}
