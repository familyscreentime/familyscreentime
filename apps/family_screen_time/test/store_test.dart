import 'dart:io';

import 'package:family_screen_time/src/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screentime_engine/screentime_engine.dart';

void main() {
  late Directory dir;
  late LocalStore store;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('fst');
    store = LocalStore(dir);
  });

  tearDown(() => dir.delete(recursive: true));

  test('settings are created once, then read back', () async {
    final first = await store.loadSettings(defaultLanguage: 'fr');
    expect(first.language, 'fr');
    final again = await store.loadSettings(defaultLanguage: 'nl');
    expect(again.deviceId, first.deviceId);
    expect(again.language, 'fr');
  });

  test('family data survives a round trip', () async {
    final family = FamilyData(
      children: const [Child(id: 'c', name: 'Emma')],
      config: const FamilyConfig(
        appGroups: {
          'g': {'minecraft'},
        },
      ),
      state: const FamilyState(
        rules: [
          Rule(
            id: 'r',
            childId: 'c',
            appTarget: AppTarget.group('g'),
            dailyQuota: Duration(minutes: 45),
          ),
        ],
      ),
      groupNames: const {'g': 'Jeux'},
    );
    await store.saveFamily(family);
    final copy = await store.loadFamily();
    expect(copy.toJson(), ownGroups(family).toJson());
    expect(copy.child('c')?.name, 'Emma');
  });

  test('volume caps survive a round trip', () {
    const child = Child(id: 'emma', name: 'Emma', volumeHeadphones: 60);
    final back = Child.fromJson(child.toJson());
    expect(back.volumeHeadphones, 60);
    expect(back.volumeSpeaker, isNull);
    expect(back.withPresets(const [10]).volumeHeadphones, 60);
  });

  test('eye breaks: on by default, settings survive a round trip', () {
    final saved = const Child(id: 'emma', name: 'Emma').toJson()
      ..remove('eyeBreak');
    expect(Child.fromJson(saved).eyeBreak, const EyeBreakPolicy());
    const policy = EyeBreakPolicy(every: Duration(minutes: 30), snoozes: 1);
    final child = const Child(
      id: 'emma',
      name: 'Emma',
    ).withEyeBreak(policy).withVolume(headphones: 50);
    expect(Child.fromJson(child.toJson()).eyeBreak, policy);
  });

  test('reminder choices survive a round trip, with defaults', () async {
    final settings = await store.loadSettings(defaultLanguage: 'fr');
    expect(settings.warningMinutes, [10, 5, 1]);
    await store.saveSettings(settings.copyWith(warningMinutes: [15, 2]));
    expect((await store.loadSettings()).warningMinutes, [15, 2]);
    await store.saveSettings(settings.copyWith(warningMinutes: []));
    expect((await store.loadSettings()).warningMinutes, isEmpty);
    await store.saveSettings(
      settings.copyWith(hiddenCountdowns: {'all', 'group:games'}),
    );
    expect((await store.loadSettings()).hiddenCountdowns, {
      'all',
      'group:games',
    });

    expect((await store.loadFamily()).graceReminderMinutes, 1);
    await store.saveFamily(const FamilyData(graceReminderMinutes: 3));
    expect((await store.loadFamily()).graceReminderMinutes, 3);
  });

  test('usage is stored per day and read back from a given day', () async {
    final today = dayOf(DateTime.now());
    final yesterday = addDays(today, -1);
    UsageSegment seg(DateTime day, int hour) => UsageSegment.device(
      childId: 'c',
      deviceId: 'd',
      appId: 'minecraft',
      start: day.add(Duration(hours: hour)),
      end: day.add(Duration(hours: hour, minutes: 20)),
    );
    await store.appendUsage(seg(yesterday, 9));
    await store.appendUsage(seg(today, 0));
    expect(await store.loadUsage(since: yesterday), hasLength(2));
    expect(await store.loadUsage(since: today), hasLength(1));
    expect(
      File('${dir.path}/usage/${dayToJson(yesterday)}.jsonl').existsSync(),
      isTrue,
    );
  });

  test('a line cut short by a crash is skipped', () async {
    final today = dayOf(DateTime.now());
    await store.appendUsage(
      UsageSegment.device(
        childId: 'c',
        deviceId: 'd',
        appId: 'a',
        start: today,
        end: today.add(const Duration(minutes: 1)),
      ),
    );
    await File('${dir.path}/usage/${dayToJson(today)}.jsonl')
        .writeAsString('{"childId":"c","dev', mode: FileMode.append);
    expect(await store.loadUsage(since: today), hasLength(1));
  });
}
