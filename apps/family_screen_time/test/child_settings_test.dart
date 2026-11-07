import 'dart:io';

import 'package:family_screen_time/src/controller.dart';
import 'package:family_screen_time/src/store.dart';
import 'package:family_screen_time/src/sync/family_entities.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('fst');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('org.familyscreentime/platform'),
          (_) async => null,
        );
  });
  tearDown(() => dir.deleteSync(recursive: true));

  // The family's settings from before 0.30: device locked, settings for the
  // parent only, a reminder every 5 minutes.
  const family = FamilyData(
    children: [
      Child(id: 'emma', name: 'Emma'),
      Child(id: 'leo', name: 'Léo'),
    ],
    graceReminderMinutes: 5,
    outOfTime: OutOfTime.device,
    settingsParentOnly: true,
  );

  test('without settings of their own, the family\'s', () {
    expect(family.graceReminderMinutesFor('emma'), 5);
    expect(family.outOfTimeFor('emma'), OutOfTime.device);
    expect(family.settingsParentOnlyFor('emma'), isTrue);
    // A child unknown here (none on this device yet): the family's too.
    expect(family.outOfTimeFor(null), OutOfTime.device);
  });

  test('each child their own, set for the child shown only', () async {
    final c = AppController(
      LocalStore(dir),
      const AppSettings(deviceId: 'p', language: 'fr', parentDevice: true),
      family,
    );
    c.selectChild('leo');
    await c.setChildSettings(
      graceReminderMinutes: 0,
      outOfTime: OutOfTime.apps,
      settingsParentOnly: false,
    );
    final f = c.family;
    expect(f.graceReminderMinutesFor('leo'), 0);
    expect(f.outOfTimeFor('leo'), OutOfTime.apps);
    expect(f.settingsParentOnlyFor('leo'), isFalse);
    // Emma and the family's settings stay as they were.
    expect(f.graceReminderMinutesFor('emma'), 5);
    expect(f.outOfTimeFor('emma'), OutOfTime.device);
    expect(f.settingsParentOnlyFor('emma'), isTrue);
    expect(f.outOfTime, OutOfTime.device);
    // One setting at a time: the others stay.
    await c.setChildSettings(outOfTime: OutOfTime.settings);
    expect(c.family.graceReminderMinutesFor('leo'), 0);
    expect(c.family.settingsParentOnlyFor('leo'), isFalse);
    // Kept on the device.
    final again = await LocalStore(dir).loadFamily();
    expect(again.outOfTimeFor('leo'), OutOfTime.settings);
  });

  test('synced with the child; left out while not set', () {
    final f = family.copyWith(
      children: [
        family.children.first.withSettings(outOfTime: OutOfTime.apps),
        family.children.last,
      ],
    );
    final entities = familyEntities(f);
    expect(entities['${FamilyKeys.child}emma']!['outOfTime'], 'apps');
    expect(
      entities['${FamilyKeys.child}leo']!.containsKey('outOfTime'),
      isFalse,
    );
    final back = familyFromEntities(entities, f);
    expect(back.outOfTimeFor('emma'), OutOfTime.apps);
    expect(back.outOfTimeFor('leo'), OutOfTime.device);
  });
}
