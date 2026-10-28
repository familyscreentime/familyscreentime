import 'dart:io';

import 'package:family_screen_time/src/children_glance.dart';
import 'package:family_screen_time/src/controller.dart';
import 'package:family_screen_time/src/store.dart';
import 'package:family_screen_time/src/ui/parent_device_home.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screentime_engine/screentime_engine.dart';

void main() {
  // Wednesday 28 October 2026.
  DateTime at(int hour, [int minute = 0]) =>
      DateTime(2026, 10, 28, hour, minute);

  /// Screen time from 7 to 8 and from 18 to 20, one hour a day.
  final hours = Rule(
    id: 'hours',
    childId: 'emma',
    schedule: WeeklySchedule({
      for (var d = 1; d <= 7; d++)
        d: const [TimeRange.hm(7, 0, 8, 0), TimeRange.hm(18, 0, 20, 0)],
    }),
    dailyQuota: const Duration(hours: 1),
  );

  FamilyData family({List<TemporaryBlock> blocks = const []}) => FamilyData(
    children: const [Child(id: 'emma', name: 'Emma')],
    state: FamilyState(rules: [hours], temporaryBlocks: blocks),
  );

  var ids = 0;
  String newId() => 'id${ids++}';

  UnlockPlan plan(FamilyData f, DateTime now, {List<UsageSegment>? usage}) =>
      planUnlock(
        f,
        usage ?? const [],
        'emma',
        const {'tablet'},
        now,
        openable: [
          for (final r in f.state.rules)
            if (_nextRangeEnd(r, now) case final end?) (r, end),
        ],
        newId: newId,
      );

  bool locked(FamilyData f, DateTime now, [List<UsageSegment>? usage]) =>
      childLocked(f, usage ?? const [], 'emma', const {'tablet'}, now);

  test('outside the hours: locked; opened until the end of the next range', () {
    final f = family();
    expect(locked(f, at(12)), isTrue);
    expect(locked(f, at(18, 30)), isFalse);
    final p = plan(f, at(12));
    expect(p.until, at(20));
    expect(locked(p.family, at(12)), isFalse);
    expect(p.family.state.dayUnlocks, isEmpty);
    expect(p.family.state.hoursUnlocks.single.until, at(20));
  });

  test('no range left today: unlocked until midnight', () {
    final p = plan(family(), at(21));
    expect(p.until, DateTime(2026, 10, 29));
    expect(p.family.state.hoursUnlocks, isEmpty);
    expect(locked(p.family, at(21)), isFalse);
  });

  test('time used up: opening the hours is not enough, so until midnight', () {
    final used = [
      UsageSegment.device(
        childId: 'emma',
        deviceId: 'tablet',
        appId: 'game',
        start: at(7),
        end: at(8),
      ),
    ];
    final p = plan(family(), at(12), usage: used);
    expect(p.until, DateTime(2026, 10, 29));
    expect(p.family.state.dayUnlocks, hasLength(1));
    expect(locked(p.family, at(12), used), isFalse);
  });

  test('a block is lifted first; nothing more within the hours', () {
    final f = family(
      blocks: [
        TemporaryBlock(id: 'b', childId: 'emma', from: at(18), message: 'Zut'),
      ],
    );
    expect(locked(f, at(18, 30)), isTrue);
    final p = plan(f, at(18, 30));
    expect(p.until, isNull);
    expect(p.family.state.temporaryBlocks.single.until, at(18, 30));
    expect(p.family.state.dayUnlocks, isEmpty);
    expect(p.family.state.hoursUnlocks, isEmpty);
  });

  group('home of a parent\'s device', () {
    late Directory dir;
    late AppController c;

    setUp(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('org.familyscreentime/platform'),
            (_) async => null,
          );
      dir = Directory.systemTemp.createTempSync('fst-glance');
      c = AppController(
        LocalStore(dir),
        const AppSettings(
          deviceId: 'papa',
          language: 'fr',
          setupDone: true,
          parentDevice: true,
        ),
        FamilyData(
          children: const [
            Child(id: 'lucas', name: 'Lucas'),
            Child(id: 'emma', name: 'Emma'),
          ],
          state: FamilyState(
            temporaryBlocks: [
              // Until lifted: locked whatever the time of the test.
              TemporaryBlock(
                id: 'b',
                childId: 'emma',
                from: DateTime.now().subtract(const Duration(hours: 1)),
              ),
            ],
          ),
        ),
      );
      c.enterParentMode();
    });

    tearDown(() {
      c.dispose();
      dir.deleteSync(recursive: true);
    });

    /// Lets the reads from disk go through: each needs a real moment and
    /// a frame.
    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 150; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 2)),
        );
        await tester.pump();
      }
    }

    testWidgets('each child with their state and the actions that fit', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(home: ParentDeviceHome(controller: c)),
      );
      await settle(tester);
      // By name.
      expect(
        tester.getTopLeft(find.text('Emma')).dy,
        lessThan(tester.getTopLeft(find.text('Lucas')).dy),
      );
      expect(find.byTooltip('Ses appareils sont verrouillés'), findsOneWidget);
      expect(find.byTooltip('Ses appareils sont utilisables'), findsOneWidget);
      expect(find.byTooltip('Donner du temps en plus'), findsOneWidget);
      expect(find.byTooltip('Bloquer maintenant'), findsOneWidget);
      // Not everyone is locked.
      expect(find.text('Tout verrouiller'), findsOneWidget);

      await tester.tap(find.byTooltip('Déverrouiller'));
      await settle(tester);
      expect(c.activeBlocks(DateTime.now(), forChild: 'emma'), isEmpty);
      expect(
        find.text('Emma peut à nouveau utiliser ses appareils.'),
        findsOneWidget,
      );
      expect(find.byTooltip('Bloquer maintenant'), findsNWidgets(2));
    });

    testWidgets('everyone blocked at once, with a message kept for later', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(home: ParentDeviceHome(controller: c)),
      );
      await settle(tester);
      await tester.tap(find.text('Tout verrouiller'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'À table !');
      await tester.tap(find.text('Jusqu\'à nouvel ordre'));
      await tester.tap(find.text('Bloquer'));
      await settle(tester);
      final now = DateTime.now();
      for (final id in ['emma', 'lucas']) {
        expect(
          c.activeBlocks(now, forChild: id).map((b) => b.message),
          contains('À table !'),
        );
      }
      expect(c.settings.blockMessages, ['À table !']);
      expect(find.text('Tout déverrouiller'), findsOneWidget);
    });
  });
}

/// End of [r]'s next range today, when outside its hours (as the
/// controller's own).
DateTime? _nextRangeEnd(Rule r, DateTime now) {
  final schedule = r.schedule;
  if (schedule == null || schedule.allows(now)) return null;
  final start = schedule.nextStart(now);
  if (start == null || !sameDay(start, now)) return null;
  final length = schedule.untilEnd(start);
  return length == null ? null : start.add(length);
}
