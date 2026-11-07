import 'package:screentime_engine/screentime_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  // Videos: the YouTube app and the browsers' videos, 30 minutes a day.
  final cfg = FamilyConfig(
    appGroups: {
      ...config.appGroups,
      'video': {'youtube', browserVideoApp},
    },
    alwaysAllowed: config.alwaysAllowed,
    neverBlocked: config.neverBlocked,
    allowedInHours: const {'firefox-school'},
  );
  final engine = RuleEngine(cfg);
  const videos = Rule(
    id: 'v',
    childId: child,
    appTarget: AppTarget.group('video'),
    dailyQuota: Duration(minutes: 30),
  );
  const total = Rule(id: 'all', childId: child, dailyQuota: Duration(hours: 3));

  UsageSegment browsing(
    String app,
    DateTime start,
    int minutes, {
    String? activity,
  }) => UsageSegment.device(
    childId: child,
    deviceId: tablet,
    appId: app,
    start: start,
    end: start.add(min(minutes)),
    activity: activity,
  );

  Decision eval(FamilyState s, String app, DateTime now) => engine.evaluate(
    s,
    childId: child,
    deviceId: tablet,
    appId: app,
    now: now,
  );

  test('only the browser\'s video time counts for the videos', () {
    final s = FamilyState(
      rules: const [videos, total],
      usage: [
        browsing('firefox', at(5, 14), 10, activity: UsageActivity.other),
        browsing('firefox', at(5, 14, 10), 20, activity: UsageActivity.video),
        browsing('youtube', at(5, 15), 5),
      ],
    );
    final d = eval(s, browserVideoApp, at(5, 16));
    expect(d.allowed, isTrue);
    expect(d.remaining, min(5));
    expect(d.ruleId, 'v');
    // The browser itself is not in the group: only total time limits it.
    expect(eval(s, 'firefox', at(5, 16)).ruleId, 'all');
    expect(
      engine.consumption(
        s,
        total,
        childId: child,
        from: at(5, 0),
        to: at(5, 16),
      ),
      min(35),
    );
  });

  test('out of video time: videos stop, the browser stays open', () {
    final s = FamilyState(
      rules: const [videos, total],
      usage: [
        browsing('firefox', at(5, 14), 30, activity: UsageActivity.video),
      ],
    );
    expect(eval(s, browserVideoApp, at(5, 15)).allowed, isFalse);
    expect(eval(s, 'firefox', at(5, 15)).allowed, isTrue);
  });

  test('a browser open at any time still has its videos limited', () {
    final s = FamilyState(
      rules: const [videos, total],
      usage: [
        browsing(
          'firefox-school',
          at(5, 14),
          40,
          activity: UsageActivity.video,
        ),
      ],
    );
    expect(eval(s, browserVideoApp, at(5, 15)).allowed, isFalse);
    // Total screen time leaves it out, as before.
    expect(
      engine.consumption(
        s,
        total,
        childId: child,
        from: at(5, 0),
        to: at(5, 16),
      ),
      Duration.zero,
    );
  });

  test('the browser\'s videos limited on their own', () {
    const alone = Rule(
      id: 'bv',
      childId: child,
      appTarget: AppTarget.app(browserVideoApp),
      dailyQuota: Duration(minutes: 15),
    );
    final s = FamilyState(
      rules: const [alone],
      usage: [
        browsing('firefox', at(5, 14), 20, activity: UsageActivity.video),
        browsing('youtube', at(5, 15), 30),
      ],
    );
    expect(eval(s, browserVideoApp, at(5, 16)).allowed, isFalse);
    expect(eval(s, 'youtube', at(5, 16)).allowed, isTrue);
  });
}
