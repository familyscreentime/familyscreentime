import 'package:family_screen_time/src/store.dart';
import 'package:family_screen_time/src/sync/link_merge.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screentime_engine/screentime_engine.dart';

void main() {
  const group = FamilyData(
    children: [Child(id: 'emma', name: 'Emma')],
    config: FamilyConfig(
      appGroups: {
        'games': {'minecraft'},
      },
      alwaysAllowed: {'phone'},
    ),
    state: FamilyState(
      rules: [Rule(id: 'all', childId: 'emma', dailyQuota: Duration(hours: 2))],
    ),
    groupNames: {'games': 'Jeux'},
  );
  final local = FamilyData(
    children: const [Child(id: 'lucas', name: 'Lucas', volumeSpeaker: 40)],
    config: const FamilyConfig(
      appGroups: {
        'video': {'youtube'},
      },
      alwaysAllowed: {'maps'},
    ),
    state: FamilyState(
      rules: const [
        Rule(
          id: 'all',
          childId: 'lucas',
          appTarget: AppTarget.group('video'),
          dailyQuota: Duration(hours: 1),
        ),
      ],
      bonuses: [
        Bonus.forRule(
          id: 'b',
          childId: 'lucas',
          ruleId: 'all',
          amount: const Duration(minutes: 10),
          grantedAt: DateTime(2026, 10, 23, 9),
          validUntil: DateTime(2026, 10, 23, 23),
        ),
      ],
    ),
    groupNames: const {'video': 'Vidéo'},
  );

  test('a new child comes with all their rules', () {
    final merged = mergeJoining(
      group: group,
      local: local,
      localChild: 'lucas',
      groupChild: 'lucas',
      newChild: true,
      keepRules: false,
      deviceId: 'tablet2',
    );
    expect(merged.children.map((c) => c.name), ['Emma', 'Lucas']);
    expect(merged.children.last.volumeSpeaker, 40);
    expect(merged.groupNames.values, containsAll(['Jeux', 'Vidéo']));
    final rules = merged.state.rules.where((r) => r.childId == 'lucas');
    // Same id as Emma's rule: given another.
    expect(rules.single.id, isNot('all'));
    expect(rules.single.deviceTarget, const DeviceTarget.all());
    expect(merged.state.bonuses.single.childId, 'lucas');
    expect(merged.config.alwaysAllowed, {'phone', 'maps'});
  });

  test('a known child: this device\'s rules dropped, or kept here only', () {
    final dropped = mergeJoining(
      group: group,
      local: local,
      localChild: 'lucas',
      groupChild: 'emma',
      newChild: false,
      keepRules: false,
      deviceId: 'tablet2',
    );
    expect(dropped.children.map((c) => c.id), ['emma']);
    expect(dropped.state.rules.map((r) => r.id), ['all']);
    // No new group nobody uses.
    expect(dropped.config.appGroups.keys, ['games']);

    final kept = mergeJoining(
      group: group,
      local: local,
      localChild: 'lucas',
      groupChild: 'emma',
      newChild: false,
      keepRules: true,
      deviceId: 'tablet2',
    );
    final mine = kept.state.rules.last;
    expect(mine.childId, 'emma');
    expect(mine.deviceTarget, const DeviceTarget.device('tablet2'));
    expect(kept.config.appGroups['video'], {'youtube'});
    expect(kept.state.bonuses, isEmpty);
  });

  test('leaving keeps the child and what applies on this device', () {
    const f = FamilyData(
      children: [
        Child(id: 'emma', name: 'Emma'),
        Child(id: 'lucas', name: 'Lucas'),
      ],
      state: FamilyState(
        rules: [
          Rule(id: 'a', childId: 'emma', dailyQuota: Duration(hours: 2)),
          Rule(
            id: 'b',
            childId: 'emma',
            deviceTarget: DeviceTarget.device('phone'),
            dailyQuota: Duration(hours: 1),
          ),
          Rule(id: 'c', childId: 'lucas', dailyQuota: Duration(hours: 1)),
        ],
      ),
    );
    final left = keepOnLeaving(f, 'emma', 'tablet');
    expect(left.children.map((c) => c.id), ['emma']);
    expect(left.state.rules.map((r) => r.id), ['a']);
  });
}
