/// What a child does in a browser, measured without reading the pages:
/// every 15 seconds while a browser is in front, Android reports how much
/// it scrolled and whether something was playing. Each stretch is then
/// classed as video, quick scrolling (a feed) or other (reading, searching,
/// writing). For now this is measured only: nothing is limited by it.
library;

import 'package:screentime_engine/screentime_engine.dart';

/// One stretch of a few seconds in a browser, as Android measured it.
class BrowserSample {
  /// The browser.
  final String package;
  final DateTime start;
  final DateTime end;

  /// Scroll events (browsers send at most about ten a second).
  final int scrolls;

  /// Scroll gestures: scrolls more than a second apart from the previous.
  final int bursts;

  /// Distance scrolled, in the page's own units (not comparable between
  /// browsers).
  final int scrollDistance;

  /// Time something played that began while the browser was in front.
  final Duration media;

  /// Time something played that was already playing before (music from
  /// another app, most likely).
  final Duration otherMedia;

  const BrowserSample({
    required this.package,
    required this.start,
    required this.end,
    this.scrolls = 0,
    this.bursts = 0,
    this.scrollDistance = 0,
    this.media = Duration.zero,
    this.otherMedia = Duration.zero,
  });

  Duration get length => end.difference(start);

  Json toJson() => {
    'package': package,
    'start': instantToJson(start),
    'end': instantToJson(end),
    'scrolls': scrolls,
    'bursts': bursts,
    'scrollDistance': scrollDistance,
    'mediaMs': media.inMilliseconds,
    'otherMediaMs': otherMedia.inMilliseconds,
  };

  factory BrowserSample.fromJson(Json j) => BrowserSample(
    package: j['package'] as String,
    start: instantFromJson(j['start']),
    end: instantFromJson(j['end']),
    scrolls: (j['scrolls'] as num?)?.toInt() ?? 0,
    bursts: (j['bursts'] as num?)?.toInt() ?? 0,
    scrollDistance: (j['scrollDistance'] as num?)?.toInt() ?? 0,
    media: Duration(milliseconds: (j['mediaMs'] as num?)?.toInt() ?? 0),
    otherMedia: Duration(
      milliseconds: (j['otherMediaMs'] as num?)?.toInt() ?? 0,
    ),
  );

  /// From the platform channel: times in milliseconds since the epoch.
  factory BrowserSample.fromPlatform(Map<Object?, Object?> m) => BrowserSample(
    package: m['package'] as String,
    start: DateTime.fromMillisecondsSinceEpoch((m['start'] as num).toInt()),
    end: DateTime.fromMillisecondsSinceEpoch((m['end'] as num).toInt()),
    scrolls: (m['scrolls'] as num?)?.toInt() ?? 0,
    bursts: (m['bursts'] as num?)?.toInt() ?? 0,
    scrollDistance: (m['scrollDistance'] as num?)?.toInt() ?? 0,
    media: Duration(milliseconds: (m['mediaMs'] as num?)?.toInt() ?? 0),
    otherMedia: Duration(
      milliseconds: (m['otherMediaMs'] as num?)?.toInt() ?? 0,
    ),
  );
}

/// Share of a sample with something playing from which it counts as video.
const videoShare = 0.5;

/// Scroll gestures in the last minute from which scrolling counts as quick
/// (a feed rather than a page being read). To be checked against real use.
const quickScrollBursts = 12;

/// The window [quickScrollBursts] is counted over.
const quickScrollWindow = Duration(minutes: 1);

/// What [sample] was, given the samples of the same browser just before
/// it ([recent], any order; older ones are ignored).
String classify(BrowserSample sample, Iterable<BrowserSample> recent) {
  final length = sample.length.inMilliseconds;
  if (length > 0 && sample.media.inMilliseconds >= length * videoShare) {
    return UsageActivity.video;
  }
  final from = sample.end.subtract(quickScrollWindow);
  var bursts = sample.bursts;
  for (final r in recent) {
    if (identical(r, sample) || r.package != sample.package) continue;
    if (!r.end.isAfter(from) || r.end.isAfter(sample.start)) continue;
    bursts += r.bursts;
  }
  return bursts >= quickScrollBursts
      ? UsageActivity.scroll
      : UsageActivity.other;
}

/// Time of [app] by activity in [segments] (those with one).
Map<String, Duration> activityTimes(
  Iterable<UsageSegment> segments,
  String app,
) {
  final out = <String, Duration>{};
  for (final s in segments) {
    final a = s.activity;
    if (s.appId != app || a == null) continue;
    out[a] = (out[a] ?? Duration.zero) + s.length;
  }
  return out;
}

// --- Calibration export (temporary) ------------------------------------------

/// The samples as CSV, oldest first, to check the thresholds against real
/// use: one line per sample with what was measured, the scroll gestures of
/// the last minute and the share of sound (what the thresholds look at),
/// and the class given. To be removed once the thresholds are set.
String browserSamplesCsv(
  List<BrowserSample> samples,
  String Function(String package) appName,
) {
  final sorted = [...samples]..sort((a, b) => a.start.compareTo(b.start));
  final b = StringBuffer(
    '﻿start,end,browser,package,seconds,scrolls,bursts,scroll_distance,'
    'media_seconds,other_media_seconds,media_share,bursts_last_minute,'
    'activity\r\n',
  );
  for (var i = 0; i < sorted.length; i++) {
    final s = sorted[i];
    final from = s.end.subtract(quickScrollWindow);
    var minute = s.bursts;
    for (var j = i - 1; j >= 0 && sorted[j].end.isAfter(from); j--) {
      final r = sorted[j];
      if (r.package == s.package && !r.end.isAfter(s.start)) minute += r.bursts;
    }
    final length = s.length.inMilliseconds;
    final share = length == 0 ? 0.0 : s.media.inMilliseconds / length;
    final name = appName(s.package);
    b
      ..writeAll([
        _iso(s.start),
        _iso(s.end),
        name.contains(RegExp('[",\n\r]'))
            ? '"${name.replaceAll('"', '""')}"'
            : name,
        s.package,
        (length / 1000).toStringAsFixed(1),
        s.scrolls,
        s.bursts,
        s.scrollDistance,
        (s.media.inMilliseconds / 1000).toStringAsFixed(1),
        (s.otherMedia.inMilliseconds / 1000).toStringAsFixed(1),
        share.toStringAsFixed(2),
        minute,
        classify(s, sorted.sublist(0, i)),
      ], ',')
      ..write('\r\n');
  }
  return b.toString();
}

/// Local time, to the second, with its offset.
String _iso(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  final o = t.timeZoneOffset;
  final m = o.inMinutes.abs();
  return '${t.year}-${two(t.month)}-${two(t.day)}T${two(t.hour)}:'
      '${two(t.minute)}:${two(t.second)}${o.isNegative ? '-' : '+'}'
      '${two(m ~/ 60)}:${two(m % 60)}';
}
