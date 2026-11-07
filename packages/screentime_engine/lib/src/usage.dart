/// Usage segments and duration arithmetic over intervals.
library;

import 'targets.dart';

/// Basic unit of all time accounting.
///
/// Either use measured on a device ([deviceId] and [appId] set), or time
/// injected by hand for use outside any supported device (game console,
/// TV…), charged to [injectedTarget].
class UsageSegment {
  final String childId;
  final String? deviceId;
  final String? appId;
  final AppTarget? injectedTarget;

  /// Start, included.
  final DateTime start;

  /// End, excluded. For ongoing use, the caller passes the current instant.
  final DateTime end;

  /// What the app was used for, when the device could tell: in a browser,
  /// [UsageActivity.video], [UsageActivity.scroll] or [UsageActivity.other].
  /// The rules do not look at it.
  final String? activity;

  UsageSegment.device({
    required this.childId,
    required String this.deviceId,
    required String this.appId,
    required this.start,
    required this.end,
    this.activity,
  }) : injectedTarget = null {
    _check();
  }

  UsageSegment.injected({
    required this.childId,
    required AppTarget this.injectedTarget,
    required this.start,
    required this.end,
  }) : deviceId = null,
       appId = null,
       activity = null {
    _check();
  }

  void _check() {
    if (end.isBefore(start)) {
      throw ArgumentError('The segment ends before it starts.');
    }
  }

  bool get isInjected => injectedTarget != null;

  Duration get length => end.difference(start);

  /// Part of the segment within [from, to), or `null` when empty.
  Interval? clip(DateTime from, DateTime to) =>
      Interval(start, end).clip(from, to);
}

/// The videos played in any browser, as an app of their own: the parent
/// puts it in a group (with the video apps, say) or limits it alone. The
/// time a browser plays a video ([UsageActivity.video]) counts for it, as
/// well as for the browser. Not a package name: none starts with `@`.
const browserVideoApp = '@browser-video';

/// What a browser was used for, as [UsageSegment.activity].
abstract final class UsageActivity {
  /// A video or other media playing.
  static const video = 'video';

  /// Scrolling in quick bursts, as through a feed.
  static const scroll = 'scroll';

  /// Anything else: reading, searching, writing…
  static const other = 'other';

  static const all = [video, scroll, other];
}

/// Interval [start, end).
class Interval {
  final DateTime start;
  final DateTime end;

  const Interval(this.start, this.end);

  Duration get length => end.difference(start);

  Interval? clip(DateTime from, DateTime to) {
    final s = start.isBefore(from) ? from : start;
    final e = end.isAfter(to) ? to : end;
    return e.isAfter(s) ? Interval(s, e) : null;
  }
}

/// Merges intervals that overlap or touch.
List<Interval> mergeIntervals(Iterable<Interval> intervals) {
  final sorted = intervals.toList()..sort((a, b) => a.start.compareTo(b.start));
  final merged = <Interval>[];
  for (final i in sorted) {
    if (merged.isNotEmpty && !i.start.isAfter(merged.last.end)) {
      final last = merged.removeLast();
      merged.add(
        Interval(last.start, i.end.isAfter(last.end) ? i.end : last.end),
      );
    } else {
      merged.add(i);
    }
  }
  return merged;
}

/// Sum of the lengths.
Duration totalLength(Iterable<Interval> intervals) =>
    intervals.fold(Duration.zero, (sum, i) => sum + i.length);
