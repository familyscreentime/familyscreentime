import 'dart:io';

import 'package:family_screen_time/src/controller.dart';
import 'package:family_screen_time/src/store.dart';
import 'package:family_screen_time/src/sync/family_entities.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screentime_engine/screentime_engine.dart';

void main() {
  // Before 0.22.1: one "Jeux" group for the whole family.
  const shared = FamilyData(
    children: [
      Child(id: 'emma', name: 'Emma'),
      Child(id: 'lucas', name: 'Lucas'),
    ],
    config: FamilyConfig(
      appGroups: {
        'games': {'minecraft'},
      },
    ),
    state: FamilyState(
      rules: [
        Rule(
          id: 'e',
          childId: 'emma',
          appTarget: AppTarget.group('games'),
          dailyQuota: Duration(hours: 1),
        ),
        Rule(
          id: 'l',
          childId: 'lucas',
          appTarget: AppTarget.group('games'),
          dailyQuota: Duration(minutes: 30),
        ),
      ],
    ),
    groupNames: {'games': 'Jeux'},
  );

  test('each child gets their own copy of the family\'s groups', () {
    final f = ownGroups(shared);
    expect(f.groupsOf('emma'), {'games': 'Jeux'});
    expect(f.groupsOf('lucas'), {'games.lucas': 'Jeux'});
    expect(f.config.appGroups['games.lucas'], {'minecraft'});
    final lucas = f.state.rules.firstWhere((r) => r.id == 'l');
    expect(lucas.appTarget, const AppTarget.group('games.lucas'));
    // Done once, the same everywhere.
    expect(identical(ownGroups(f), f), isTrue);
    expect(ownGroups(shared).toJson(), f.toJson());
    // And it goes through the log.
    final back = familyFromEntities(familyEntities(f), const FamilyData());
    expect(back.groupOwners, f.groupOwners);
  });

  test(
    'changing a child\'s group leaves the other\'s, and groups copy',
    () async {
      final dir = await Directory.systemTemp.createTemp('fst-groups');
      addTearDown(() => dir.delete(recursive: true));
      final store = LocalStore(dir);
      await store.saveFamily(shared);
      final family = await store.loadFamily();
      final c = AppController(
        store,
        const AppSettings(deviceId: 'd', language: 'fr', parentDevice: true),
        family,
      );
      c.selectChild('lucas');
      expect(c.childGroups, {'games.lucas': 'Jeux'});
      expect(c.otherChildrenGroups, {'games': 'Jeux'});
      // Emma's group gets an app; Lucas's copy brings it.
      await c.updateFamily(
        c.family.copyWith(
          config: configWithGroups(c.family.config, {
            ...c.family.config.appGroups,
            'games': {'minecraft', 'roblox'},
          }),
        ),
      );
      expect(c.family.config.appGroups['games.lucas'], {'minecraft'});
      await c.copyGroups(['games']);
      expect(c.childGroups.keys, ['games.lucas']);
      expect(c.family.config.appGroups['games.lucas'], {'minecraft', 'roblox'});
      c.dispose();
    },
  );
}
