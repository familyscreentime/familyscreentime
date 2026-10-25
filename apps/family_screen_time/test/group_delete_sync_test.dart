import 'dart:io';

import 'package:family_screen_time/src/controller.dart';
import 'package:family_screen_time/src/store.dart';
import 'package:family_screen_time/src/sync/family_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screentime_engine/screentime_engine.dart';
import 'package:screentime_sync/screentime_sync.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final shared in [true, false]) {
    test('a group deleted on the parent\'s phone goes on the child\'s tablet '
        '(${shared ? 'groups from before 0.22.1' : 'own groups'})', () async {
      final dirT = await Directory.systemTemp.createTemp('fst-t');
      final dirP = await Directory.systemTemp.createTemp('fst-p');
      addTearDown(() => dirT.delete(recursive: true));
      addTearDown(() => dirP.delete(recursive: true));
      final storeT = LocalStore(dirT);
      final storeP = LocalStore(dirP);
      final family = FamilyData(
        children: const [
          Child(id: 'emma', name: 'Emma'),
          Child(id: 'lucas', name: 'Lucas'),
        ],
        config: const FamilyConfig(
          appGroups: {
            'games': {'minecraft'},
          },
        ),
        state: const FamilyState(
          rules: [
            Rule(
              id: 'l',
              childId: 'lucas',
              appTarget: AppTarget.group('games'),
              dailyQuota: Duration(minutes: 30),
            ),
          ],
        ),
        groupNames: const {'games': 'Jeux'},
        groupOwners: shared ? const {} : const {'games': 'lucas'},
      );
      const settingsT = AppSettings(
        deviceId: 'tablet',
        language: 'fr',
        setupDone: true,
        childId: 'lucas',
      );
      await storeT.saveSettings(settingsT);
      await storeT.saveFamily(family);
      // The log as an earlier version wrote it: groups shared.
      final (tablet, key) = await FamilySync.create(
        store: storeT,
        settings: settingsT,
        family: family,
        parentCode: '123456',
        deviceName: 'Tablette',
      );
      final phoneId = await DeviceIdentity.generate('phone');
      await tablet.node.emit([
        EventDraft.put(SyncKeys.device('phone'), {
          'name': 'Papa',
          'role': 'parent',
          'signKey': phoneId.signing.publicKey,
        }),
      ], parentKey: key);
      final phone = await FamilySync.join(
        store: storeP,
        identity: phoneId,
        welcome: Welcome(
          tablet.node.root,
          tablet.node.store.missingFor(const {}, limit: 1 << 30),
        ),
      );
      await phone.commit();
      await storeP.saveFamily(phone.compose(const FamilyData()));
      await phone.close();

      // On the phone, in parent mode, Lucas's group is deleted.
      final c = AppController(
        storeP,
        const AppSettings(
          deviceId: 'phone',
          language: 'fr',
          setupDone: true,
          parentDevice: true,
        ),
        await storeP.loadFamily(),
      );
      await c.openSync();
      c.parentCodeEntered('123456');
      c.enterParentMode();
      c.selectChild('lucas');
      final id = c.childGroups.keys.single;
      final f = c.family;
      await c.updateFamily(
        f.copyWith(
          config: configWithGroups(
            f.config,
            {...f.config.appGroups}..remove(id),
          ),
          groupNames: {...f.groupNames}..remove(id),
          groupOwners: {...f.groupOwners}..remove(id),
          state: stateWithRules(f.state, [
            for (final r in f.state.rules)
              if (r.appTarget != AppTarget.group(id)) r,
          ]),
        ),
      );
      expect(c.childGroups, isEmpty);
      final onPhone = (await c.sync)!;

      // The tablet takes it in, as on the network.
      final result = await tablet.node.ingest(
        onPhone.node.store.missingFor(tablet.node.store.vector, limit: 1 << 30),
      );
      await tablet.applyRemote(
        Accepted(result.accepted, 'peer', replicaChanged: true),
        storeT,
      );
      final onTablet = await storeT.loadFamily();
      expect(onTablet.groupsOf('lucas'), isEmpty);
      expect(onTablet.state.rules.where((r) => r.childId == 'lucas'), isEmpty);
      c.leaveParentMode();
      c.dispose();
      await tablet.close();
    });
  }
}
