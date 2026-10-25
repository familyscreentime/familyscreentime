import 'dart:io';

import 'package:family_screen_time/src/controller.dart';
import 'package:family_screen_time/src/family.dart';
import 'package:family_screen_time/src/store.dart';
import 'package:family_screen_time/src/strings.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screentime_engine/screentime_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('org.familyscreentime/platform');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late Directory dir;
  late LocalStore store;
  late AppController controller;
  late List<MethodCall> calls;
  late bool usageAccess;

  final now = DateTime.now();
  final today = dayOf(now);
  // Android's history: the day before yesterday and yesterday.
  final day2 = addDays(today, -2).add(const Duration(hours: 20));
  final day1 = addDays(today, -1).add(const Duration(hours: 9));

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('fst');
    store = LocalStore(dir);
    calls = [];
    usageAccess = true;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'permissionStatus':
          return {'usageAccess': usageAccess};
        case 'usageHistory':
          final to = (call.arguments as Map<Object?, Object?>)['to'] as int;
          return [
            {
              'package': 'tiktok',
              // Crosses midnight.
              'start': day2.millisecondsSinceEpoch,
              'end': day2.add(const Duration(hours: 5)).millisecondsSinceEpoch,
            },
            {
              'package': 'minecraft',
              'start': day1.millisecondsSinceEpoch,
              // Runs past the first recorded use: clipped there.
              'end': to + 3600 * 1000,
            },
          ];
      }
      return null;
    });
    controller = AppController(
      store,
      const AppSettings(deviceId: 'd', language: 'fr', childId: 'emma'),
      const FamilyData(
        children: [Child(id: 'emma', name: 'Emma')],
      ),
    );
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
    await dir.delete(recursive: true);
  });

  test(
    'Android history is imported once, up to the first recorded use',
    () async {
      final firstRecorded = day1.add(const Duration(minutes: 30));
      await store.appendUsage(
        UsageSegment.device(
          childId: 'emma',
          deviceId: 'd',
          appId: 'youtube',
          start: firstRecorded,
          end: firstRecorded.add(const Duration(minutes: 10)),
        ),
      );

      expect(await controller.importHistoryIfNeeded(), isTrue);
      final request = calls.firstWhere((c) => c.method == 'usageHistory');
      final args = request.arguments as Map<Object?, Object?>;
      expect(args['to'], firstRecorded.millisecondsSinceEpoch);

      final imported = await store.loadImported(since: addDays(today, -5));
      // TikTok split at midnight, Minecraft clipped.
      expect(imported, hasLength(3));
      final minecraft = imported.singleWhere((s) => s.appId == 'minecraft');
      expect(minecraft.end, firstRecorded);
      expect(controller.settings.historyImported, isTrue);

      // Statistics see both sources; the rules only see recorded usage.
      expect(await controller.statisticsUsage(), hasLength(4));
      expect(await controller.recentUsage(), hasLength(1));

      calls.clear();
      expect(await controller.importHistoryIfNeeded(), isFalse);
      expect(calls, isEmpty);
    },
  );

  test('without usage access, the import waits for a later try', () async {
    usageAccess = false;
    expect(await controller.importHistoryIfNeeded(), isFalse);
    expect(controller.settings.historyImported, isFalse);
  });

  test('a renamed app keeps its name everywhere, and can be reset', () async {
    expect(controller.appName('tiktok', androidLabel: 'TikTok'), 'TikTok');
    await controller.renameApp('tiktok', '  Vidéos courtes ');
    expect(
      controller.appName('tiktok', androidLabel: 'TikTok'),
      'Vidéos courtes',
    );
    final rule = Rule(
      id: 'r',
      childId: 'emma',
      appTarget: const AppTarget.app('tiktok'),
    );
    expect(ruleLabel(rule, controller.family, const S('fr')), 'Vidéos courtes');
    expect((await store.loadFamily()).appNames['tiktok'], 'Vidéos courtes');

    await controller.renameApp('tiktok', '');
    expect(controller.appName('tiktok', androidLabel: 'TikTok'), 'TikTok');
  });

  test('time spent today is summed per group', () async {
    controller = AppController(
      store,
      const AppSettings(deviceId: 'd', language: 'fr', childId: 'emma'),
      const FamilyData(
        children: [Child(id: 'emma', name: 'Emma')],
        config: FamilyConfig(
          appGroups: {
            'games': {'minecraft', 'roblox'},
            'video': {'youtube'},
            'empty': {},
          },
        ),
      ),
    );
    // One after the other, as on one screen (seconds: whatever the time).
    var at = today;
    Future<void> add(String app, int seconds) {
      final start = at;
      at = at.add(Duration(seconds: seconds));
      return store.appendUsage(
        UsageSegment.device(
          childId: 'emma',
          deviceId: 'd',
          appId: app,
          start: start,
          end: at,
        ),
      );
    }

    await add('minecraft', 20);
    await add('roblox', 15);
    await add('youtube', 5);
    final times = await controller.groupTimesToday();
    expect(times['games'], const Duration(seconds: 35));
    expect(times['video'], const Duration(seconds: 5));
    expect(times['empty'], Duration.zero);
    expect(controller.groupsOf('minecraft'), ['games']);
  });

  test(
    'Android knows when parent mode is on, to open protected settings',
    () async {
      controller.enterParentMode();
      await Future<void>.delayed(Duration.zero);
      final on = calls.lastWhere((c) => c.method == 'parentMode');
      final args = on.arguments as Map<Object?, Object?>;
      expect(args['on'], isTrue);
      expect(args['forMs'], 5 * 60 * 1000);
      // With the notification's texts, and its button to leave.
      expect(args['title'], 'Mode parent actif');
      expect(args['leave'], 'Quitter le mode parent');

      controller.leaveParentMode();
      await Future<void>.delayed(Duration.zero);
      final off = calls.lastWhere((c) => c.method == 'parentMode');
      expect((off.arguments as Map<Object?, Object?>)['on'], isFalse);
    },
  );
}
