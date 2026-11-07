/// The demonstration build: a parent's device with a made-up family of two
/// children, their limits and some use today. It links to no device and
/// keeps nothing: every launch starts again from the same family. Used to
/// check the screens and take screenshots.
library;

import 'dart:io';
import 'dart:ui';

import 'package:path_provider/path_provider.dart';
import 'package:screentime_engine/screentime_engine.dart';

import 'controller.dart';
import 'pin.dart';
import 'store.dart';
import 'strings.dart';

/// The parent code of the demonstration, shown on its locked home.
const demoParentCode = '1234';

/// A made-up family at [now]: Léa can use her devices, Tom is blocked
/// for an hour with a message.
FamilyData demoFamily(DateTime now) {
  final afterSchool = WeeklySchedule({
    for (var d = 1; d <= 7; d++) d: const [TimeRange.hm(7, 0, 22, 0)],
  });
  // [minutes] of [app], begun [ago] minutes before now.
  UsageSegment used(
    String child,
    String device,
    String app,
    int ago,
    int minutes,
  ) {
    final start = now.subtract(Duration(minutes: ago));
    return UsageSegment.device(
      childId: child,
      deviceId: device,
      appId: app,
      start: start,
      end: start.add(Duration(minutes: minutes)),
    );
  }

  return FamilyData(
    children: const [
      Child(id: 'lea', name: 'Léa', presets: [15, 30, 45, 60]),
      Child(id: 'tom', name: 'Tom', presets: [15, 25, 35, 45]),
    ],
    config: const FamilyConfig(
      appGroups: {
        'lea-games': {'com.mojang.minecraftpe', 'com.roblox.client'},
        'lea-video': {'com.google.android.youtube'},
        'tom-games': {'com.mojang.minecraftpe', 'com.supercell.brawlstars'},
      },
    ),
    groupNames: const {
      'lea-games': 'Jeux',
      'lea-video': 'Vidéos',
      'tom-games': 'Jeux',
    },
    groupOwners: const {
      'lea-games': 'lea',
      'lea-video': 'lea',
      'tom-games': 'tom',
    },
    state: FamilyState(
      rules: [
        Rule(
          id: 'lea-all',
          childId: 'lea',
          schedule: afterSchool,
          dailyQuota: const Duration(hours: 2),
        ),
        const Rule(
          id: 'lea-games',
          childId: 'lea',
          appTarget: AppTarget.group('lea-games'),
          dailyQuota: Duration(hours: 1),
        ),
        const Rule(
          id: 'lea-video',
          childId: 'lea',
          appTarget: AppTarget.group('lea-video'),
          dailyQuota: Duration(minutes: 45),
        ),
        Rule(
          id: 'tom-all',
          childId: 'tom',
          schedule: afterSchool,
          dailyQuota: const Duration(minutes: 90),
        ),
        const Rule(
          id: 'tom-games',
          childId: 'tom',
          appTarget: AppTarget.group('tom-games'),
          dailyQuota: Duration(minutes: 45),
          breakPolicy: BreakPolicy(
            after: Duration(minutes: 30),
            length: Duration(minutes: 10),
          ),
        ),
      ],
      temporaryBlocks: [
        TemporaryBlock(
          id: 'tom-homework',
          childId: 'tom',
          from: now.subtract(const Duration(minutes: 5)),
          until: now.add(const Duration(hours: 1)),
          message: 'Devoirs d\'abord',
        ),
      ],
      usage: [
        used('lea', 'demo-lea', 'com.mojang.minecraftpe', 95, 20),
        used('lea', 'demo-lea', 'com.google.android.youtube', 60, 15),
        used('tom', 'demo-tom', 'com.supercell.brawlstars', 80, 25),
      ],
    ),
  );
}

/// The controller of the demonstration, on a fresh, empty storage.
Future<AppController> loadDemo() async {
  final base = await getTemporaryDirectory();
  final dir = Directory('${base.path}/demo');
  if (await dir.exists()) await dir.delete(recursive: true);
  await dir.create(recursive: true);
  final store = LocalStore(dir);
  final now = DateTime.now();
  final family = demoFamily(now);
  final language = S.of(PlatformDispatcher.instance.locale.languageCode);
  final settings = await withNewPin(
    AppSettings(
      deviceId: 'demo-parent',
      language: language.language,
      setupDone: true,
      parentDevice: true,
      blockMessages: const ['À table !', 'Au lit !'],
    ),
    demoParentCode,
  );
  await store.saveSettings(settings);
  // The use lives with the recorded use, as on a real device.
  for (final u in family.state.usage) {
    await store.appendUsage(u);
  }
  final kept = family.copyWith(state: family.state.copyWith(usage: const []));
  await store.saveFamily(kept);
  return AppController(store, settings, kept, demoCode: demoParentCode);
}
