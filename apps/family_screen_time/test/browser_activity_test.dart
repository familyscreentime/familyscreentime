import 'dart:io';

import 'package:family_screen_time/src/browser_activity.dart';
import 'package:family_screen_time/src/store.dart';
import 'package:family_screen_time/src/usage_report.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screentime_engine/screentime_engine.dart';

void main() {
  final t0 = DateTime(2026, 10, 28, 16);
  BrowserSample sample(
    int at, {
    int bursts = 0,
    int mediaS = 0,
    int otherMediaS = 0,
    String package = 'org.mozilla.firefox',
  }) => BrowserSample(
    package: package,
    start: t0.add(Duration(seconds: at)),
    end: t0.add(Duration(seconds: at + 15)),
    scrolls: bursts * 4,
    bursts: bursts,
    media: Duration(seconds: mediaS),
    otherMedia: Duration(seconds: otherMediaS),
  );

  test('playing for most of the sample: video', () {
    expect(classify(sample(0, mediaS: 10), const []), UsageActivity.video);
    expect(classify(sample(0, mediaS: 5), const []), UsageActivity.other);
    // Music from another app does not make it a video.
    expect(classify(sample(0, otherMediaS: 15), const []), UsageActivity.other);
  });

  test('many scroll gestures in a minute: quick scrolling', () {
    final recent = [sample(0, bursts: 4), sample(15, bursts: 4)];
    expect(classify(sample(30, bursts: 4), recent), UsageActivity.scroll);
    // Reading: a scroll now and then.
    final reading = [sample(0, bursts: 2), sample(15, bursts: 1)];
    expect(classify(sample(30, bursts: 2), reading), UsageActivity.other);
    // Older than a minute, or another browser: not counted.
    final old = [
      sample(-120, bursts: 20),
      sample(15, bursts: 6, package: 'com.android.chrome'),
    ];
    expect(classify(sample(30, bursts: 4), old), UsageActivity.other);
  });

  test('samples survive storage and the platform channel', () async {
    final dir = await Directory.systemTemp.createTemp('fst-browser');
    addTearDown(() => dir.delete(recursive: true));
    final store = LocalStore(dir);
    final now = DateTime.now();
    final s = BrowserSample(
      package: 'com.android.chrome',
      start: now.subtract(const Duration(seconds: 15)),
      end: now,
      scrolls: 30,
      bursts: 7,
      scrollDistance: 4200,
      media: const Duration(seconds: 3),
    );
    await store.appendBrowserSample(s);
    final back = (await store.loadBrowserSamples(since: dayOf(now))).single;
    expect(back.toJson(), s.toJson());
    final fromAndroid = BrowserSample.fromPlatform({
      'package': 'com.android.chrome',
      'start': s.start.millisecondsSinceEpoch,
      'end': s.end.millisecondsSinceEpoch,
      'scrolls': 30,
      'bursts': 7,
      'scrollDistance': 4200,
      'mediaMs': 3000,
      'otherMediaMs': 0,
    });
    expect(fromAndroid.toJson(), s.toJson());
  });

  test('the report gives a browser\'s time by activity', () {
    UsageSegment seg(int fromMin, int minutes, String? activity) =>
        UsageSegment.device(
          childId: 'emma',
          deviceId: 'tab',
          appId: 'com.android.chrome',
          start: t0.add(Duration(minutes: fromMin)),
          end: t0.add(Duration(minutes: fromMin + minutes)),
          activity: activity,
        );
    final history = [
      seg(0, 10, null),
      seg(10, 5, UsageActivity.video),
      seg(15, 3, UsageActivity.scroll),
      seg(18, 2, UsageActivity.other),
      seg(20, 4, UsageActivity.video),
    ];
    final report = buildUsageReport(
      history,
      childId: 'emma',
      now: t0.add(const Duration(hours: 1)),
      days: 1,
    );
    final app = report.apps.single;
    expect(app.total, const Duration(minutes: 24));
    expect(app.byActivity, {
      UsageActivity.video: const Duration(minutes: 9),
      UsageActivity.scroll: const Duration(minutes: 3),
      UsageActivity.other: const Duration(minutes: 2),
    });
    // And the activity goes through JSON (the sync).
    final json = usageSegmentToJson(history[1]);
    expect(usageSegmentFromJson(json).activity, UsageActivity.video);
    expect(usageSegmentToJson(history[0]).containsKey('activity'), isFalse);
  });

  test('the calibration export: one line per sample, with the class', () {
    final samples = [
      sample(30, bursts: 4),
      sample(0, bursts: 4),
      sample(15, bursts: 4),
      sample(45, mediaS: 15),
    ];
    final lines = browserSamplesCsv(
      samples,
      (p) => 'Firefox, "beta"',
    ).split('\r\n').where((l) => l.isNotEmpty).toList();
    expect(lines.first, startsWith('﻿start,end,browser,package,seconds'));
    expect(lines, hasLength(5));
    expect(lines[1], contains(',"Firefox, ""beta""",'));
    // Oldest first; the third has 12 gestures in its minute.
    expect(lines[1], endsWith(',4,other'));
    expect(lines[3], endsWith(',12,scroll'));
    expect(lines[4], contains(',1.00,'));
    expect(lines[4], endsWith(',video'));
  });
}
