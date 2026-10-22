import 'dart:io';

import 'package:family_screen_time/src/controller.dart';
import 'package:family_screen_time/src/family.dart';
import 'package:family_screen_time/src/store.dart';
import 'package:family_screen_time/src/ui/rule_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screentime_engine/screentime_engine.dart';

void main() {
  testWidgets('each day has its own ranges, and a day can be copied', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 7000);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('org.familyscreentime/platform'),
          (_) async => null,
        );

    final dir = Directory.systemTemp.createTempSync('fst');
    addTearDown(() => dir.deleteSync(recursive: true));
    // Games on Wednesday, Saturday and Sunday only, at different hours.
    final rule = Rule(
      id: 'games',
      childId: 'emma',
      appTarget: const AppTarget.group('g'),
      schedule: WeeklySchedule({
        DateTime.wednesday: [TimeRange.hm(14, 0, 17, 0)],
        DateTime.saturday: [
          TimeRange.hm(10, 0, 12, 0),
          TimeRange.hm(14, 0, 18, 0),
        ],
        DateTime.sunday: [TimeRange.hm(9, 0, 12, 0)],
      }),
    );
    final controller = AppController(
      LocalStore(dir),
      const AppSettings(deviceId: 'd', language: 'fr', childId: 'emma'),
      FamilyData(
        children: const [Child(id: 'emma', name: 'Emma')],
        config: const FamilyConfig(
          appGroups: {
            'g': {'minecraft'},
          },
        ),
        state: FamilyState(rules: [rule]),
        groupNames: const {'g': 'Jeux'},
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => RuleEditor(controller: controller, rule: rule),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Mercredi'), findsOneWidget);
    expect(find.text('14:00–17:00'), findsOneWidget);
    expect(find.text('10:00–12:00, 14:00–18:00'), findsOneWidget);
    expect(find.text('Bloqué toute la journée'), findsNWidgets(4));

    await tester.tap(find.text('Mercredi'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copier vers…'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Vendredi'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('14:00–17:00'), findsNWidgets(2));

    await tester.runAsync(() async {
      await tester.tap(find.text('Enregistrer'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();

    final saved = controller.family.state.rules.single.schedule!;
    expect(saved.allows(DateTime(2026, 10, 23, 15)), isTrue); // Friday
    expect(saved.allows(DateTime(2026, 10, 22, 15)), isFalse); // Thursday
    expect(saved.allows(DateTime(2026, 10, 24, 13)), isFalse); // Saturday gap
    expect(saved.allows(DateTime(2026, 10, 24, 15)), isTrue);
  });

  testWidgets('daily time can differ for each weekday', (tester) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('org.familyscreentime/platform'),
          (_) async => null,
        );
    final dir = Directory.systemTemp.createTempSync('fst');
    addTearDown(() => dir.deleteSync(recursive: true));
    const rule = Rule(
      id: 'games',
      childId: 'emma',
      appTarget: AppTarget.group('g'),
      dailyQuota: Duration(minutes: 30),
    );
    final controller = AppController(
      LocalStore(dir),
      const AppSettings(deviceId: 'd', language: 'fr', childId: 'emma'),
      const FamilyData(
        children: [Child(id: 'emma', name: 'Emma')],
        config: FamilyConfig(
          appGroups: {
            'g': {'minecraft'},
          },
        ),
        state: FamilyState(rules: [rule]),
        groupNames: {'g': 'Jeux'},
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: RuleEditor(controller: controller, rule: rule),
      ),
    );
    await tester.tap(find.text('Différent selon le jour'));
    await tester.pumpAndSettle();
    expect(find.text('30 min'), findsNWidgets(7));

    Future<void> pick(String day, String value) async {
      await tester.tap(find.text(day));
      await tester.pumpAndSettle();
      await tester.tap(find.text(value).last);
      await tester.pumpAndSettle();
    }

    await pick('Lundi', '0 min');
    await pick('Samedi', '2 h');
    await pick('Dimanche', 'Pas de limite');

    await tester.runAsync(() async {
      await tester.tap(find.text('Enregistrer'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();

    final saved = controller.family.state.rules.single;
    expect(saved.dailyQuota, isNull);
    expect(saved.dailyQuotaOn(DateTime(2026, 10, 19)), Duration.zero);
    expect(
      saved.dailyQuotaOn(DateTime(2026, 10, 20)),
      const Duration(minutes: 30),
    );
    expect(
      saved.dailyQuotaOn(DateTime(2026, 10, 24)),
      const Duration(hours: 2),
    );
    expect(saved.dailyQuotaOn(DateTime(2026, 10, 25)), isNull);
  });

  testWidgets('grace, firm limit and saved time can be set', (tester) async {
    tester.view.physicalSize = const Size(1080, 5000);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('org.familyscreentime/platform'),
          (_) async => null,
        );
    final dir = Directory.systemTemp.createTempSync('fst');
    addTearDown(() => dir.deleteSync(recursive: true));
    const rule = Rule(
      id: 'games',
      childId: 'emma',
      appTarget: AppTarget.group('g'),
      dailyQuota: Duration(minutes: 30),
    );
    final controller = AppController(
      LocalStore(dir),
      const AppSettings(deviceId: 'd', language: 'fr', childId: 'emma'),
      const FamilyData(
        children: [Child(id: 'emma', name: 'Emma')],
        config: FamilyConfig(
          appGroups: {
            'g': {'minecraft'},
          },
        ),
        state: FamilyState(rules: [rule]),
        groupNames: {'g': 'Jeux'},
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: RuleEditor(controller: controller, rule: rule),
      ),
    );

    await tester.tap(find.text('Temps de grâce'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('10 min').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Limite ferme après des dépassements répétés'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('au moins 2 jours sur les 7 derniers'),
      findsOneWidget,
    );
    await tester.tap(find.text('Décompter les dépassements'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Garder le temps non utilisé'));
    await tester.pumpAndSettle();
    expect(find.text('1 jour'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.text('Enregistrer'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();

    final saved = controller.family.state.rules.single;
    expect(saved.grace!.length, const Duration(minutes: 10));
    expect(saved.grace!.hardening!.threshold, const Duration(minutes: 5));
    expect(saved.grace!.hardening!.days, 2);
    expect(saved.grace!.hardening!.window, 7);
    expect(saved.grace!.hardening!.deductOverruns, isTrue);
    expect(saved.rollover!.days, 1);
    expect(saved.rollover!.cap, isNull);
  });

  testWidgets('breaks, a rolling maximum and carry-over can be set', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('fst');
    addTearDown(() => dir.deleteSync(recursive: true));
    const rule = Rule(
      id: 'games',
      childId: 'emma',
      appTarget: AppTarget.group('g'),
      dailyQuota: Duration(minutes: 30),
    );
    final controller = AppController(
      LocalStore(dir),
      const AppSettings(deviceId: 'd', language: 'fr', childId: 'emma'),
      const FamilyData(
        children: [Child(id: 'emma', name: 'Emma')],
        config: FamilyConfig(
          appGroups: {
            'g': {'minecraft'},
          },
        ),
        state: FamilyState(rules: [rule]),
        groupNames: {'g': 'Jeux'},
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: RuleEditor(controller: controller, rule: rule),
      ),
    );
    final list = find.byType(Scrollable).first;
    Future<void> tap(String text) async {
      await tester.scrollUntilVisible(find.text(text), 200, scrollable: list);
      await tester.tap(find.text(text));
      await tester.pumpAndSettle();
    }

    await tap('Maximum sur plusieurs jours');
    expect(find.text('3 jours'), findsOneWidget);
    await tap('Lendemain');
    await tap('Pause obligatoire');
    expect(find.text('45 min'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.text('Enregistrer'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();

    final saved = controller.family.state.rules.single;
    expect(saved.rollingQuota!.days, 3);
    expect(saved.rollingQuota!.quota, const Duration(hours: 4));
    expect(saved.carryOver.mode, CarryOverMode.nextDay);
    expect(saved.breakPolicy!.after, const Duration(minutes: 45));
    expect(saved.breakPolicy!.length, const Duration(minutes: 10));
    expect(
      ruleSummary(saved, controller.s),
      contains('pause de 10 min toutes les 45 min'),
    );
  });

  testWidgets('listen only, for music apps', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('fst');
    addTearDown(() => dir.deleteSync(recursive: true));
    const rule = Rule(
      id: 'clips',
      childId: 'emma',
      appTarget: AppTarget.group('m'),
      dailyQuota: Duration(minutes: 15),
    );
    final controller = AppController(
      LocalStore(dir),
      const AppSettings(deviceId: 'd', language: 'fr', childId: 'emma'),
      const FamilyData(
        children: [Child(id: 'emma', name: 'Emma')],
        config: FamilyConfig(
          appGroups: {
            'm': {'spotify'},
          },
        ),
        state: FamilyState(rules: [rule]),
        groupNames: {'m': 'Musique'},
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: RuleEditor(controller: controller, rule: rule),
      ),
    );
    final list = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.text('Écoute seule'),
      200,
      scrollable: list,
    );
    await tester.tap(find.text('Écoute seule'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Avant de pouvoir la rouvrir'),
      200,
      scrollable: list,
    );
    expect(find.text('2 min'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.text('Enregistrer'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();

    final saved = controller.family.state.rules.single;
    expect(saved.listenOnly, const ListenOnlyPolicy());
    expect(ruleSummary(saved, controller.s), contains('écoute seule'));
  });

  testWidgets('0 min a day can be set, for an app open only with extra time', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('fst');
    addTearDown(() => dir.deleteSync(recursive: true));
    final controller = AppController(
      LocalStore(dir),
      const AppSettings(deviceId: 'd', language: 'fr', childId: 'emma'),
      const FamilyData(
        children: [Child(id: 'emma', name: 'Emma')],
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: RuleEditor(
          controller: controller,
          initialTarget: const AppTarget.app('minecraft'),
        ),
      ),
    );
    // The rule's kind of time is fixed: no choice offered.
    expect(find.text('S\'applique à'), findsNothing);
    expect(find.text('minecraft'), findsOneWidget);

    await tester.tap(find.text('Temps par jour'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('0 min').last);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('seulement avec du temps en plus'),
      findsOneWidget,
    );

    await tester.runAsync(() async {
      await tester.tap(find.text('Enregistrer'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();
    final saved = controller.family.state.rules.single;
    expect(saved.dailyQuota, Duration.zero);
    expect(saved.appTarget, const AppTarget.app('minecraft'));
  });
}
