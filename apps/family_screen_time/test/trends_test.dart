import 'dart:convert';
import 'dart:io';

import 'package:family_screen_time/src/controller.dart';
import 'package:family_screen_time/src/store.dart';
import 'package:family_screen_time/src/sync/family_entities.dart';
import 'package:family_screen_time/src/ui/trends_screen.dart';
import 'package:family_screen_time/src/usage_export.dart';
import 'package:family_screen_time/src/usage_report.dart';
import 'package:family_screen_time/src/usage_trends.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screentime_engine/screentime_engine.dart';

UsageSegment use(
  String app,
  DateTime start,
  Duration length, {
  String child = 'emma',
  String device = 'tab',
}) => UsageSegment.device(
  childId: child,
  deviceId: device,
  appId: app,
  start: start,
  end: start.add(length),
);

/// Every day from [from] to the day before [to]: an hour of games on
/// weekdays, two at weekends, and [video] of video.
List<UsageSegment> days(DateTime from, DateTime to, {Duration? video}) => [
  for (var d = from; d.isBefore(to); d = addDays(d, 1)) ...[
    use(
      'game',
      d.add(const Duration(hours: 16)),
      Duration(hours: d.weekday >= DateTime.saturday ? 2 : 1),
    ),
    if (video != null) use('video', d.add(const Duration(hours: 19)), video),
  ],
];

void main() {
  final now = DateTime(2026, 10, 25, 12);
  final today = dayOf(now);
  final to = addDays(today, 1);

  test('trends over three months, compared with the three before', () {
    final from = DateTime(to.year, to.month - 3, to.day);
    final before = DateTime(from.year, from.month - 3, from.day);
    final history = [
      ...days(before, from),
      ...days(from, to, video: const Duration(minutes: 30)),
      // Another child's and time away are left out.
      use('game', today, const Duration(hours: 5), child: 'leo'),
      UsageSegment.injected(
        childId: 'emma',
        injectedTarget: const AppTarget.all(),
        start: today,
        end: today.add(const Duration(hours: 3)),
      ),
    ];
    final t = buildTrends(
      history,
      childId: 'emma',
      now: now,
      months: 3,
      groups: {
        'games': {'game'},
      },
    );
    expect(t.from, from);
    expect(t.days, to.difference(from).inDays);
    expect(t.weekdayPerDay, const Duration(hours: 1, minutes: 30));
    expect(t.weekendPerDay, const Duration(hours: 2, minutes: 30));
    // Video is new: games stayed the same.
    expect(t.apps.map((a) => a.id), ['game', 'video']);
    // About the same (weekends fall differently).
    expect(t.apps.first.change, inInclusiveRange(-2, 2));
    expect(t.apps.last.change, isNull);
    expect(t.groups.single.id, 'games');
    expect(t.change, greaterThan(0));
    // Week by week, every week of the period.
    expect(t.buckets.first.start.weekday, DateTime.monday);
    expect(t.buckets.last.end.isAfter(today), isTrue);
    expect(t.buckets[1].perDay, const Duration(minutes: 5 * 90 + 2 * 150) ~/ 7);

    // A year, month by month, from a history of three months: counted
    // from its first day, nothing to compare with.
    final year = buildTrends(
      days(from, to),
      childId: 'emma',
      now: now,
      months: 12,
      monthly: true,
    );
    expect(year.buckets, hasLength(13));
    expect(year.buckets.first.days, 0);
    expect(year.historyStart, from);
    expect(year.days, t.days);
    expect(year.before, isNull);
  });

  test('two devices at once: added up, or counted once', () {
    final at = today.add(const Duration(hours: 10));
    final history = [
      use('game', at, const Duration(minutes: 30)),
      use('video', at, const Duration(minutes: 20), device: 'phone'),
      // Beside the game on the tablet's screen: counted once there.
      use('chat', at, const Duration(minutes: 10)),
    ];
    UsageReport report({bool together = false}) => buildUsageReport(
      history,
      childId: 'emma',
      now: now,
      days: 1,
      together: together,
    );
    expect(report().total, const Duration(minutes: 50));
    expect(report(together: true).total, const Duration(minutes: 30));
    expect(report().apps, hasLength(3));
    final week = buildTrends(
      history,
      childId: 'emma',
      now: now,
      months: 3,
      together: true,
    );
    expect(week.total, const Duration(minutes: 30));
  });

  test('CSV and ActivityWatch exports', () {
    final start = DateTime(2026, 10, 24, 15, 0, 5);
    final segments = exportedSegments(
      [
        use('com.game', start, const Duration(minutes: 10)),
        use('com.video', start, const Duration(hours: 1), device: 'pc'),
        use('launcher', start, const Duration(minutes: 1)),
        use('com.game', start, const Duration(hours: 1), child: 'leo'),
      ],
      children: {'emma'},
      from: start.add(const Duration(minutes: 5)),
      exclude: {'launcher'},
    );
    expect(segments, hasLength(2));
    final names = ExportNames(
      child: (id) => {'emma': 'Emma'}[id] ?? id,
      device: (id) => {'tab': 'Tablette, salon', 'pc': 'PC'}[id] ?? id,
      app: (p) => {'com.game': 'Jeu "X"'}[p] ?? p,
    );
    final csv = usageCsv(segments, names).split('\r\n');
    expect(
      csv.first,
      '\uFEFFchild,device,app,package,start,end,seconds,activity',
    );
    expect(
      csv[1],
      startsWith(
        'Emma,"Tablette, salon","Jeu ""X""",com.game,'
        '${isoLocal(start.add(const Duration(minutes: 5)))},',
      ),
    );
    expect(csv[1], endsWith(',300,'));
    expect(isoLocal(start), matches(r'^2026-10-24T15:00:05[+-]\d\d:\d\d$'));

    final aw = jsonDecode(activityWatchJson(segments, names)) as Map;
    final buckets = aw['buckets'] as Map;
    expect(buckets.keys, {
      'aw-watcher-familyscreentime_tablette-salon',
      'aw-watcher-familyscreentime_pc',
    });
    final tab = buckets['aw-watcher-familyscreentime_tablette-salon'] as Map;
    expect(tab['type'], 'currentwindow');
    expect(tab['hostname'], 'Tablette, salon');
    final event = (tab['events'] as List).single as Map;
    expect(event['duration'], 300);
    expect(event['timestamp'], endsWith('Z'));
    expect(event['data'], {
      'app': 'Jeu "X"',
      'title': 'Jeu "X"',
      'package': 'com.game',
      'child': 'Emma',
    });
  });

  test('old use goes after the time chosen, never before 40 days', () async {
    final dir = await Directory.systemTemp.createTemp('fst-prune');
    addTearDown(() => dir.delete(recursive: true));
    final store = LocalStore(dir);
    // Read up to the real today.
    final now = DateTime.now();
    final today = dayOf(now);
    for (final ago in [0, 39, 41, 100, 400]) {
      await store.appendUsage(
        use('game', addDays(today, -ago), const Duration(minutes: 1)),
      );
    }
    Future<int> left() async =>
        (await store.loadUsage(since: addDays(today, -500))).length;
    expect(await store.firstUsageDay(), addDays(today, -400));
    expect(await store.pruneUsage(0, now: now), 0);
    expect(await store.pruneUsage(365, now: now), 1);
    expect(await left(), 4);
    // Once a day for the same choice.
    expect(await store.pruneUsage(365, now: now), 0);
    expect(await store.pruneUsage(10, now: now), 2);
    expect(await left(), 2);
  });

  test('how long use is kept is shared with the family', () {
    const f = FamilyData(usageKeptDays: 180);
    final back = familyFromEntities(familyEntities(f), const FamilyData());
    expect(back.usageKeptDays, 180);
    expect(
      familyFromEntities(const {}, const FamilyData()).usageKeptDays,
      defaultUsageKeptDays,
    );
    expect(FamilyData.fromJson(const {}).usageKeptDays, 365);
  });

  testWidgets('the analysis screen', (tester) async {
    final dir = Directory.systemTemp.createTempSync('fst-trends');
    addTearDown(() => dir.deleteSync(recursive: true));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('org.familyscreentime/platform'),
          (_) async => null,
        );
    late AppController c;
    await tester.runAsync(() async {
      final store = LocalStore(dir);
      final real = dayOf(DateTime.now());
      for (final s in days(addDays(real, -60), addDays(real, 1))) {
        await store.appendUsage(s);
      }
      c = AppController(
        store,
        const AppSettings(
          deviceId: 'tab',
          language: 'fr',
          setupDone: true,
          childId: 'emma',
        ),
        const FamilyData(
          children: [Child(id: 'emma', name: 'Emma')],
        ),
      );
    });
    // Its files are read for real.
    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(home: TrendsScreen(controller: c)));
      for (
        var i = 0;
        i < 100 && find.textContaining('par jour').evaluate().isEmpty;
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      }
    });
    expect(find.textContaining('par jour en moyenne'), findsOneWidget);
    expect(find.text('game'), findsOneWidget);
    expect(find.textContaining('Historique conservé : 1 an'), findsOneWidget);
    await tester.tap(find.text('1 an'));
    await tester.pump();
    expect(find.text('Moyenne par jour, mois par mois'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.ios_share));
    await tester.pumpAndSettle();
    expect(find.text('ActivityWatch'), findsOneWidget);
    c.dispose();
  });
}
