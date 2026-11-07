import 'dart:io';

import 'package:family_screen_time/src/controller.dart';
import 'package:family_screen_time/src/family.dart';
import 'package:family_screen_time/src/store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screentime_engine/screentime_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 10, 30, 10);
  const games = Rule(
    id: 'g',
    childId: 'emma',
    appTarget: AppTarget.group('games'),
    dailyQuota: Duration(hours: 2),
  );
  FamilyData family(List<Rule> rules) => FamilyData(
    children: const [Child(id: 'emma', name: 'Emma')],
    state: FamilyState(rules: rules),
  );
  Rule only(FamilyData f) => f.state.rules.single;

  test('a stricter limit keeps the one it replaces', () {
    const shorter = Rule(
      id: 'g',
      childId: 'emma',
      appTarget: AppTarget.group('games'),
      dailyQuota: Duration(hours: 1),
    );
    final after = withRuleVersions(family([games]), family([shorter]), now);
    final v = only(after).history.single;
    expect(v.until, now);
    expect(v.dailyQuota, const Duration(hours: 2));
    expect(only(after).dailyQuota, const Duration(hours: 1));
  });

  test('a new rule had none before; turning off is a change', () {
    final created = withRuleVersions(family([]), family([games]), now);
    expect(only(created).history.single.active, isFalse);
    final off = withRuleVersions(
      family([games]),
      family([games.withEnabled(false)]),
      now,
    );
    expect(only(off).history.single.active, isTrue);
  });

  test('other changes keep the versions as they are', () {
    final earlier = games.withHistory([
      RuleVersion(
        until: now.subtract(const Duration(days: 3)),
        dailyQuota: const Duration(hours: 3),
      ),
    ]);
    // The editor rebuilds the rule without its versions: they are kept.
    const sameLimitNewBreak = Rule(
      id: 'g',
      childId: 'emma',
      appTarget: AppTarget.group('games'),
      dailyQuota: Duration(hours: 2),
      breakPolicy: BreakPolicy(
        after: Duration(minutes: 30),
        length: Duration(minutes: 5),
      ),
    );
    final after = withRuleVersions(
      family([earlier]),
      family([sameLimitNewBreak]),
      now,
    );
    expect(only(after).history, hasLength(1));
    expect(only(after).breakPolicy, isNotNull);
    // Nothing changed: the same family.
    final same = family([earlier]);
    expect(identical(withRuleVersions(same, same, now), same), isTrue);
  });

  test('versions older than the usage looked at are dropped', () {
    final old = games.withHistory([
      RuleVersion(
        until: now.subtract(const Duration(days: 60)),
        dailyQuota: const Duration(hours: 3),
      ),
    ]);
    const shorter = Rule(
      id: 'g',
      childId: 'emma',
      dailyQuota: Duration(hours: 1),
    );
    final after = withRuleVersions(family([old]), family([shorter]), now);
    expect(only(after).history.single.dailyQuota, const Duration(hours: 2));
  });

  test('a change saved from the interface keeps the former limit', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('org.familyscreentime/platform'),
          (_) async => null,
        );
    final dir = Directory.systemTemp.createTempSync('fst-versions');
    addTearDown(() => dir.deleteSync(recursive: true));
    final c = AppController(
      LocalStore(dir),
      const AppSettings(deviceId: 'd', language: 'fr', childId: 'emma'),
      family([games]),
    );
    const shorter = Rule(
      id: 'g',
      childId: 'emma',
      appTarget: AppTarget.group('games'),
      dailyQuota: Duration(hours: 1),
    );
    await c.updateFamily(
      c.family.copyWith(state: c.family.state.copyWith(rules: [shorter])),
    );
    final stored = (await LocalStore(dir).loadFamily()).state.rules.single;
    expect(stored.history.single.dailyQuota, const Duration(hours: 2));
  });
}
