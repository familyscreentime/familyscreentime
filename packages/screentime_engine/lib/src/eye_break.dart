/// Eye breaks: every [EyeBreakPolicy.every] of screen use, a few seconds
/// looking into the distance. Unlike a mandatory break, nothing is blocked:
/// the screen is veiled for a few seconds. Counted on each device on its
/// own, from that device's use.
library;

import 'json.dart';
import 'usage.dart';

class EyeBreakPolicy {
  /// Off: no eye breaks, the settings are kept.
  final bool enabled;

  /// Screen use between two breaks.
  final Duration every;

  /// Length of a break taken on time. A later break lasts longer, in
  /// proportion (see [lengthAfter]).
  final Duration length;

  /// How many times in a row the child may put a break off, by [snooze]
  /// each time.
  final int snoozes;

  /// `true`: the screen is veiled for the length of the break. `false`: a
  /// reminder only, which ends the stretch of use all the same.
  final bool veil;

  /// One put-off.
  static const snooze = Duration(minutes: 1);

  /// How long a break is announced before it starts.
  static const notice = Duration(seconds: 10);

  /// A break never lasts more than this many times [length].
  static const maxStretch = 3;

  const EyeBreakPolicy({
    this.enabled = true,
    this.every = const Duration(minutes: 20),
    this.length = const Duration(seconds: 20),
    this.snoozes = 3,
    this.veil = true,
  });

  /// Length of a break after [use] of screen: [length] for [every], in
  /// proportion beyond it (23 min → 23 s with the defaults), at most
  /// [maxStretch] times [length]; never less than [length].
  Duration lengthAfter(Duration use) {
    if (use <= every) return length;
    final ms =
        length.inMilliseconds * use.inMilliseconds ~/ every.inMilliseconds;
    // Whole seconds, so the countdown starts on a round number.
    final s = Duration(seconds: (ms + 500) ~/ 1000);
    final max = length * maxStretch;
    return s > max ? max : s;
  }

  EyeBreakPolicy copyWith({
    bool? enabled,
    Duration? every,
    Duration? length,
    int? snoozes,
    bool? veil,
  }) => EyeBreakPolicy(
    enabled: enabled ?? this.enabled,
    every: every ?? this.every,
    length: length ?? this.length,
    snoozes: snoozes ?? this.snoozes,
    veil: veil ?? this.veil,
  );

  Json toJson() => {
    'enabled': enabled,
    'every': durationToJson(every),
    'length': durationToJson(length),
    'snoozes': snoozes,
    'veil': veil,
  };

  /// Missing values take the defaults.
  factory EyeBreakPolicy.fromJson(Json j) {
    const d = EyeBreakPolicy();
    return EyeBreakPolicy(
      enabled: j['enabled'] as bool? ?? d.enabled,
      every: optionalDuration(j['every']) ?? d.every,
      length: optionalDuration(j['length']) ?? d.length,
      snoozes: (j['snoozes'] as num?)?.toInt() ?? d.snoozes,
      veil: j['veil'] as bool? ?? d.veil,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is EyeBreakPolicy &&
      other.enabled == enabled &&
      other.every == every &&
      other.length == length &&
      other.snoozes == snoozes &&
      other.veil == veil;

  @override
  int get hashCode => Object.hash(enabled, every, length, snoozes, veil);
}

/// How far back the use is examined.
const _lookback = Duration(hours: 6);

/// Start of the stretch of screen use on [deviceId] going on at [now]: use
/// with no gap of [rest] or more, beginning no earlier than [restedAt].
/// `null` when the screen has not been used for [rest] or more (the eyes
/// have rested).
///
/// The use of the apps beside the one in front overlaps that of the app in
/// front: overlapping segments count once.
DateTime? screenStretchStart(
  Iterable<UsageSegment> usage, {
  required String deviceId,
  required DateTime now,
  required Duration rest,
  DateTime? restedAt,
}) {
  final from = now.subtract(_lookback);
  final intervals = <Interval>[
    for (final u in usage)
      if (u.deviceId == deviceId) ?u.clip(from, now),
  ]..sort((a, b) => a.start.compareTo(b.start));
  if (intervals.isEmpty) return null;
  var start = intervals.first.start;
  var end = intervals.first.end;
  for (final i in intervals.skip(1)) {
    if (i.start.difference(end) >= rest) start = i.start;
    if (i.end.isAfter(end)) end = i.end;
  }
  if (now.difference(end) >= rest) return null;
  if (restedAt != null && start.isBefore(restedAt)) {
    return restedAt.isAfter(now) ? null : restedAt;
  }
  return start;
}
