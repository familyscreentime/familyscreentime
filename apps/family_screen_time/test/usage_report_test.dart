import 'package:family_screen_time/src/usage_report.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screentime_engine/screentime_engine.dart';

DateTime at(int day, int hour, [int minute = 0]) =>
    DateTime(2026, 10, day, hour, minute);

Duration min(int m) => Duration(minutes: m);

UsageSegment use(
  String app,
  DateTime start,
  int minutes, {
  String child = 'emma',
}) => UsageSegment.device(
  childId: child,
  deviceId: 'tablet',
  appId: app,
  start: start,
  end: start.add(min(minutes)),
);

void main() {
  final history = [
    use('minecraft', at(1, 10), 30), // the 1st: starts the history
    use('youtube', at(18, 16), 45),
    use('minecraft', at(19, 9), 20),
    use('minecraft', at(19, 9, 20), 10), // right after: same session
    use('minecraft', at(19, 15), 15), // a second session
    use('tiktok', at(19, 23, 30), 60), // crosses midnight, at night
    use('launcher', at(19, 12), 5),
    use('minecraft', at(19, 9), 20, child: 'leo'),
    UsageSegment.injected(
      childId: 'emma',
      injectedTarget: const AppTarget.all(),
      start: at(19, 18),
      end: at(19, 19),
    ),
  ];

  UsageReport report(int days) => buildUsageReport(
    history,
    childId: 'emma',
    now: at(20, 12),
    days: days,
    exclude: {'launcher'},
  );

  test('today counts only today\'s part of a segment crossing midnight', () {
    final r = report(1);
    expect(r.days, [DateTime(2026, 10, 20)]);
    expect(r.apps.single.appId, 'tiktok');
    expect(r.total, min(30));
  });

  test('apps are sorted by time, with sessions and hours', () {
    final r = report(7);
    expect(r.apps.map((a) => a.appId), ['tiktok', 'minecraft', 'youtube']);
    final minecraft = r.apps[1];
    expect(minecraft.total, min(45));
    expect(minecraft.sessions, 2);
    expect(minecraft.byHour[9], min(30));
    expect(minecraft.byHour[15], min(15));
    expect(minecraft.byDay[DateTime(2026, 10, 19)], min(45));
    expect(r.total, min(150));
    expect(r.totalByDay[DateTime(2026, 10, 19)], min(75));
    expect(r.totalByDay[DateTime(2026, 10, 20)], min(30));
  });

  test('night time is spotted', () {
    final tiktok = report(7).apps.first;
    expect(tiktok.night, min(60));
    expect(report(7).apps[1].night, Duration.zero);
  });

  test('apps first used recently are new, unless recording just began', () {
    final r = report(30);
    final byId = {for (final a in r.apps) a.appId: a};
    expect(byId['tiktok']!.isNew, isTrue);
    expect(byId['minecraft']!.isNew, isFalse);
    expect(byId['minecraft']!.firstSeen, at(1, 10));

    final fresh = buildUsageReport(
      [use('tiktok', at(20, 9), 10)],
      childId: 'emma',
      now: at(20, 12),
      days: 7,
    );
    expect(fresh.apps.single.isNew, isFalse);
  });

  test('the average counts only days since recording started', () {
    final r = buildUsageReport(
      [use('youtube', at(19, 9), 60), use('youtube', at(20, 9), 30)],
      childId: 'emma',
      now: at(20, 12),
      days: 7,
    );
    expect(r.dailyAverage, min(45));
  });
}
