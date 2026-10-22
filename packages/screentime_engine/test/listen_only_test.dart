import 'package:screentime_engine/screentime_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  // Music apps: 15 min with the app open, then listen only.
  final music = FamilyConfig(
    appGroups: {
      'music': {'spotify'},
    },
    neverBlocked: config.neverBlocked,
  );
  const clips = Rule(
    id: 'clips',
    childId: child,
    appTarget: AppTarget.group('music'),
    dailyQuota: Duration(minutes: 15),
    listenOnly: ListenOnlyPolicy(),
  );
  Decision spotify(
    List<UsageSegment> usage,
    DateTime now, {
    Rule rule = clips,
  }) => check(
    FamilyState(rules: [rule], usage: usage),
    now,
    app: 'spotify',
    cfg: music,
  );
  final watched = use(tablet, 'spotify', at(5, 9), 15);

  test('time used up: the app opens for a minute to pick the music', () {
    final d = spotify([watched], at(5, 10));
    expect(d.allowed, isTrue);
    expect(d.reason, Reason.listenOnly);
    expect(d.remaining, min(1));
    expect(d.limiter, Limiter.listenOnly);
  });

  test('the minute counts down while open, then the app closes', () {
    final open = UsageSegment.device(
      childId: child,
      deviceId: tablet,
      appId: listenOnlyUse('spotify'),
      start: at(5, 10),
      end: at(5, 10).add(const Duration(seconds: 40)),
    );
    final now = at(5, 10).add(const Duration(seconds: 40));
    expect(
      spotify([watched, open], now).remaining,
      const Duration(seconds: 20),
    );
    final over = spotify([watched, open], at(5, 10, 1));
    expect(over.allowed, isFalse);
    expect(over.reason, Reason.quotaExhausted);
    expect(over.ruleId, 'clips');
  });

  test('it opens again two minutes after it was left', () {
    final picked = use(tablet, listenOnlyUse('spotify'), at(5, 10), 1);
    final launcher = use(tablet, 'launcher', at(5, 10, 1), 1);
    final soon = spotify([watched, picked, launcher], at(5, 10, 2));
    expect(soon.allowed, isFalse);
    expect(soon.until, at(5, 10, 3));
    expect(spotify([watched, picked, launcher], at(5, 10, 3)).allowed, isTrue);
  });

  test('time picking the music counts for screen time, not for the clips', () {
    final engine = RuleEngine(music);
    const total = Rule(
      id: 'all',
      childId: child,
      dailyQuota: Duration(hours: 2),
    );
    final state = FamilyState(
      rules: const [clips, total],
      usage: [watched, use(tablet, listenOnlyUse('spotify'), at(5, 10), 1)],
    );
    Duration used(Rule r) => engine.consumption(
      state,
      r,
      childId: child,
      from: at(5, 0),
      to: at(5, 11),
    );
    expect(used(clips), min(15));
    expect(used(total), min(16));
    expect(usedApp(listenOnlyUse('spotify')), 'spotify');
  });

  test('grace comes first, then listen only', () {
    const withGrace = Rule(
      id: 'clips',
      childId: child,
      appTarget: AppTarget.group('music'),
      dailyQuota: Duration(minutes: 15),
      grace: GracePolicy(length: Duration(minutes: 5)),
      listenOnly: ListenOnlyPolicy(),
    );
    final playing = use(tablet, 'spotify', at(5, 9), 17);
    expect(
      spotify([playing], at(5, 9, 17), rule: withGrace).reason,
      Reason.gracePeriod,
    );
    expect(
      spotify([playing], at(5, 11), rule: withGrace).reason,
      Reason.listenOnly,
    );
  });

  test('another limit used up still blocks', () {
    final state = FamilyState(
      rules: [
        clips,
        const Rule(
          id: 'all',
          childId: child,
          dailyQuota: Duration(minutes: 15),
        ),
      ],
      usage: [watched],
    );
    final d = check(state, at(5, 10), app: 'spotify', cfg: music);
    expect(d.allowed, isFalse);
    expect(d.ruleId, 'all');
  });

  test('survives a JSON round trip', () {
    const r = Rule(
      id: 'clips',
      childId: child,
      dailyQuota: Duration.zero,
      listenOnly: ListenOnlyPolicy(
        openFor: Duration(minutes: 2),
        reopenAfter: Duration(minutes: 5),
      ),
    );
    final back = ruleFromJson(ruleToJson(r));
    expect(back.listenOnly, r.listenOnly);
    expect(
      ruleFromJson(ruleToJson(clips.withEnabled(false))).listenOnly,
      const ListenOnlyPolicy(),
    );
  });
}
