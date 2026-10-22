import 'dart:io';

import 'package:family_screen_time/src/controller.dart';
import 'package:family_screen_time/src/store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screentime_engine/screentime_engine.dart';

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

  final exams = Profile(
    id: 'exams',
    name: 'Examens',
    kind: ProfileKind.custom,
    periods: [DateRange(DateTime(2026, 12, 7), DateTime(2026, 12, 18))],
  );
  final grandparents = Profile(
    id: 'gp',
    name: 'Chez les grands-parents',
    kind: ProfileKind.custom,
    periods: [DateRange(DateTime(2026, 12, 14), DateTime(2026, 12, 20))],
  );

  AppController controller(List<Rule> rules, {List<Profile>? profiles}) =>
      AppController(
        LocalStore(dir),
        const AppSettings(deviceId: 'd', language: 'fr', childId: 'emma'),
        FamilyData(
          children: const [Child(id: 'emma', name: 'Emma')],
          config: FamilyConfig(profiles: profiles ?? const []),
          state: FamilyState(rules: rules),
        ),
      );

  const normal = Rule(
    id: 'normal',
    childId: 'emma',
    profileId: normalProfileId,
    dailyQuota: Duration(hours: 2),
  );
  const examRule = Rule(
    id: 'exam',
    childId: 'emma',
    profileId: 'exams',
    dailyQuota: Duration(minutes: 30),
  );
  const gpRule = Rule(
    id: 'gp',
    childId: 'emma',
    profileId: 'gp',
    dailyQuota: Duration(hours: 4),
  );

  Duration? left(AppController c, DateTime t) => RuleEngine(c.family.config)
      .evaluate(
        c.family.state,
        childId: 'emma',
        deviceId: 'd',
        appId: 'youtube',
        now: t,
      )
      .remaining;

  test('named periods replace normal rules; the first one wins', () async {
    final c = controller(const [normal, examRule, gpRule]);
    await c.setSpecialPeriods([exams, grandparents]);
    expect(left(c, DateTime(2026, 12, 1, 10)), const Duration(hours: 2));
    expect(left(c, DateTime(2026, 12, 8, 10)), const Duration(minutes: 30));
    // Both overlap on the 15th: exams come first.
    expect(left(c, DateTime(2026, 12, 15, 10)), const Duration(minutes: 30));
    expect(left(c, DateTime(2026, 12, 19, 10)), const Duration(hours: 4));
    expect(c.activePeriod(DateTime(2026, 12, 19))?.id, 'gp');
    expect(c.summaryOf(examRule), startsWith('pendant « Examens »'));

    // Reordered, the grandparents win.
    await c.setSpecialPeriods([grandparents, exams]);
    expect(left(c, DateTime(2026, 12, 15, 10)), const Duration(hours: 4));
  });

  test('deleting a period deletes the rules meant for it', () async {
    final c = controller(const [normal, examRule, gpRule]);
    await c.setSpecialPeriods([exams, grandparents]);
    await c.setSpecialPeriods([grandparents]);
    expect(c.family.state.rules.map((r) => r.id), ['normal', 'gp']);
    expect(c.family.config.profiles.first.id, normalProfileId);
  });
}
