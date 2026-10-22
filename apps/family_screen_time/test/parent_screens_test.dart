import 'dart:io';

import 'package:family_screen_time/src/controller.dart';
import 'package:family_screen_time/src/store.dart';
import 'package:family_screen_time/src/ui/group_editor.dart';
import 'package:family_screen_time/src/ui/parent_home.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screentime_engine/screentime_engine.dart';

void main() {
  const channel = MethodChannel('org.familyscreentime/platform');

  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('fst');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'launcherApps':
              return [
                {'package': 'aardvark', 'label': 'Aardvark'},
                {'package': 'roblox', 'label': 'Roblox'},
                {'package': 'minecraft', 'label': 'Minecraft'},
                {'package': 'zoo', 'label': 'Zoo'},
              ];
            case 'appInfo':
              return <String, Object?>{};
            case 'permissionStatus':
              return <String, bool>{};
          }
          return null;
        });
  });

  tearDown(() => dir.deleteSync(recursive: true));

  AppController controller() => AppController(
    LocalStore(dir),
    const AppSettings(
      deviceId: 'd',
      language: 'fr',
      setupDone: true,
      childId: 'emma',
      historyImported: true,
    ),
    const FamilyData(
      children: [Child(id: 'emma', name: 'Emma')],
      config: FamilyConfig(
        appGroups: {
          'games': {'minecraft', 'roblox'},
        },
      ),
      state: FamilyState(
        rules: [
          Rule(id: 'all', childId: 'emma', dailyQuota: Duration(hours: 2)),
          Rule(
            id: 'games',
            childId: 'emma',
            appTarget: AppTarget.group('games'),
            dailyQuota: Duration(minutes: 30),
          ),
        ],
      ),
      groupNames: {'games': 'Jeux'},
    ),
  );

  testWidgets('one line per kind of time, leading to its rules', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 5000);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final c = controller();
    await tester.pumpWidget(MaterialApp(home: ParentHome(controller: c)));
    await tester.pump();

    expect(find.text('Limites'), findsOneWidget);
    expect(find.text('Temps total d\'utilisation'), findsOneWidget);
    expect(find.text('Jeux'), findsOneWidget);
    // No separate rule list repeating the groups.
    expect(find.text('Règles'), findsNothing);
    expect(find.textContaining('30 min par jour'), findsOneWidget);

    await tester.tap(find.text('Jeux'));
    await tester.pumpAndSettle();
    expect(find.text('Règles'), findsOneWidget);
    expect(find.text('Applis du groupe'), findsOneWidget);
    expect(find.text('minecraft'), findsOneWidget);
    expect(find.text('roblox'), findsOneWidget);

    // Turned off, the rule is kept.
    await tester.runAsync(() async {
      await tester.tap(find.byType(Switch));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    final games = c.family.state.rules.singleWhere((r) => r.id == 'games');
    expect(games.enabled, isFalse);
    expect(games.dailyQuota, const Duration(minutes: 30));
    expect(find.text('Désactivée'), findsOneWidget);
    expect(c.activeChildRules.map((r) => r.id), ['all']);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.textContaining('Pas de limite (Désactivée)'), findsOneWidget);
  });

  testWidgets('the group\'s apps come first in its editor', (tester) async {
    final c = controller();
    await tester.pumpWidget(
      MaterialApp(
        home: GroupEditor(controller: c, groupId: 'games'),
      ),
    );
    await tester.pumpAndSettle();
    final titles = [
      for (final tile in tester.widgetList<CheckboxListTile>(
        find.byType(CheckboxListTile),
      ))
        (tile.title! as Text).data,
    ];
    expect(titles, ['Minecraft', 'Roblox', 'Aardvark', 'Zoo']);

    // Ticking does not move anything.
    await tester.tap(find.text('Zoo'));
    await tester.pump();
    expect(
      (tester
                  .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
                  .last
                  .title!
              as Text)
          .data,
      'Zoo',
    );
  });
}
