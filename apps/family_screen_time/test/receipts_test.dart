import 'dart:io';

import 'package:family_screen_time/src/controller.dart';
import 'package:family_screen_time/src/platform.dart' show AppVersion;
import 'package:family_screen_time/src/store.dart';
import 'package:family_screen_time/src/sync/family_sync.dart';
import 'package:family_screen_time/src/sync/receipts.dart';
import 'package:family_screen_time/src/ui/changes_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screentime_engine/screentime_engine.dart';
import 'package:screentime_sync/screentime_sync.dart';

/// What [from] has that [to] lacks, as on the network.
Future<void> pass(FamilySync from, FamilySync to) async {
  await to.node.ingest(
    from.node.store.missingFor(to.node.store.vector, limit: 1 << 30),
  );
}

void main() {
  test('the parent sees which change reached which device', () async {
    final dirT = await Directory.systemTemp.createTemp('fst-t');
    final dirP = await Directory.systemTemp.createTemp('fst-p');
    addTearDown(() => dirT.delete(recursive: true));
    addTearDown(() => dirP.delete(recursive: true));
    const family = FamilyData(
      children: [Child(id: 'emma', name: 'Emma')],
    );
    final (tablet, key) = await FamilySync.create(
      store: LocalStore(dirT),
      settings: const AppSettings(
        deviceId: 'tablet',
        language: 'fr',
        setupDone: true,
        childId: 'emma',
      ),
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
      store: LocalStore(dirP),
      identity: phoneId,
      welcome: Welcome(
        tablet.node.root,
        tablet.node.store.missingFor(const {}, limit: 1 << 30),
      ),
    );
    await phone.commit();
    // What it got when it joined, it says it has.
    expect(await recordReceipts(phone), isTrue);
    await pass(phone, tablet);
    // A brother's tablet: Emma's limits are not waited for there.
    final leoId = await DeviceIdentity.generate('leo-tab');
    await tablet.node.emit([
      EventDraft.put(SyncKeys.device('leo-tab'), {
        'name': 'Léo',
        'role': 'child',
        'childId': 'leo',
        'signKey': leoId.signing.publicKey,
      }),
    ], parentKey: key);
    await pass(tablet, phone);
    await recordReceipts(phone);
    await pass(phone, tablet);

    // A limit added on the phone, not yet on the tablet.
    final more = family.copyWith(
      state: const FamilyState(
        rules: [
          Rule(id: 'all', childId: 'emma', dailyQuota: Duration(hours: 2)),
        ],
      ),
    );
    await phone.recordChange(family, more, parentKey: key);
    var changes = recentChanges(phone);
    final change = changes.first;
    expect(change.device, 'phone');
    expect(change.events.single.key, 'rule/all');
    expect(targetsOf(phone, change), ['tablet']);
    expect(receivedBy(phone, 'tablet', change), isNull);
    // Léo's tablet (which never answers here) only waits for the new
    // device, which concerns everybody.
    expect(pendingByDevice(phone), {'tablet': 1, 'leo-tab': 1});

    // The tablet gets it and says so; the phone learns it.
    await pass(phone, tablet);
    expect(await recordReceipts(tablet), isTrue);
    await pass(tablet, phone);
    expect(receivedBy(phone, 'tablet', change), isNotNull);
    expect(pendingByDevice(phone), {'leo-tab': 1});

    // Receipts do not answer one another without end.
    for (var i = 0; i < 3; i++) {
      await recordReceipts(phone);
      await pass(phone, tablet);
      await recordReceipts(tablet);
      await pass(tablet, phone);
    }
    expect(await recordReceipts(phone), isFalse);
    expect(await recordReceipts(tablet), isFalse);
    changes = recentChanges(phone);
    expect(changes.where((c) => c.device == 'phone'), hasLength(1));
    await phone.close();
    await tablet.close();
  });

  testWidgets('the log of changes, on the parent\'s phone', (tester) async {
    final dirP = Directory.systemTemp.createTempSync('fst-p');
    addTearDown(() => dirP.deleteSync(recursive: true));
    late AppController c;
    await tester.runAsync(() async {
      final store = LocalStore(dirP);
      const settings = AppSettings(
        deviceId: 'tablet',
        language: 'fr',
        setupDone: true,
        childId: 'emma',
      );
      const family = FamilyData(
        children: [Child(id: 'emma', name: 'Emma')],
      );
      await store.saveFamily(family);
      final (log, key) = await FamilySync.create(
        store: store,
        settings: settings,
        family: family,
        parentCode: '123456',
        deviceName: 'Tablette',
      );
      await log.node.emit([
        EventDraft.put(SyncKeys.device('phone'), {
          'name': 'Papa',
          'role': 'parent',
          'signKey': (await DeviceIdentity.generate('phone')).signing.publicKey,
        }),
      ], parentKey: key);
      await log.recordChange(
        family,
        family.copyWith(graceReminderMinutes: 5),
        parentKey: key,
      );
      await log.close();
      c = AppController(store, settings, family);
      await c.openSync();
    });
    await tester.pumpWidget(MaterialApp(home: ChangesScreen(controller: c)));
    for (var i = 0; i < 50 && find.byType(Card).evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(find.text('Réglages généraux'), findsOneWidget);
    expect(find.text('Papa : en attente'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  test('each device says its version, accepted by every version', () async {
    final dirT = await Directory.systemTemp.createTemp('fst-t');
    final dirP = await Directory.systemTemp.createTemp('fst-p');
    addTearDown(() => dirT.delete(recursive: true));
    addTearDown(() => dirP.delete(recursive: true));
    const family = FamilyData(
      children: [Child(id: 'emma', name: 'Emma')],
    );
    final (tablet, key) = await FamilySync.create(
      store: LocalStore(dirT),
      settings: const AppSettings(
        deviceId: 'tablet',
        language: 'fr',
        setupDone: true,
        childId: 'emma',
      ),
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
      store: LocalStore(dirP),
      identity: phoneId,
      welcome: Welcome(
        tablet.node.root,
        tablet.node.store.missingFor(const {}, limit: 1 << 30),
      ),
    );
    await phone.commit();

    // Once per version.
    expect(await recordVersion(tablet, const AppVersion('0.28.0', 54)), isTrue);
    expect(
      await recordVersion(tablet, const AppVersion('0.28.0', 54)),
      isFalse,
    );
    // The parent's phone, which may sign nothing else alone, says its own.
    expect(await recordVersion(phone, const AppVersion('0.28.1', 55)), isTrue);
    // Receipts after the version: both kept.
    await recordReceipts(phone);
    await pass(phone, tablet);
    await pass(tablet, phone);
    expect(versionOf(phone, 'tablet')?.name, '0.28.0');
    expect(versionOf(tablet, 'phone')?.build, 55);
    expect(versionOf(phone, 'phone')?.name, '0.28.1');
    // The receipts are still read by origin, the version field aside.
    expect(
      phone.node.replica[seenKey('phone')]!.keys.where((k) => k != 'app'),
      isNotEmpty,
    );
  });
}
