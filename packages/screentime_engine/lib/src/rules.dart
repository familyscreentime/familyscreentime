/// Rules: target, schedule, quotas, breaks, grace, carry-over and savings.
library;

import 'schedule.dart';
import 'targets.dart';

/// Quota over a rolling window of [days] days ending today.
class RollingQuota {
  final int days;
  final Duration quota;

  const RollingQuota({required this.days, required this.quota})
    : assert(days >= 1);
}

/// Mandatory break of [length] after [after] of continuous use.
/// An interruption shorter than [length] does not reset the counter.
class BreakPolicy {
  final Duration after;
  final Duration length;

  const BreakPolicy({required this.after, required this.length});
}

/// Grace hardening: when the grace used exceeded [threshold] (V) on at
/// least [days] days (X) out of the last [window] days (N), the limit turns
/// firm. Today is left out of the count so the rule does not change in the
/// middle of the day.
///
/// With [deductOverruns], the overruns of the window are also deducted
/// from the following days' time when the limit turns firm, each one once.
/// Ignored when the rule already carries overruns over.
class HardeningPolicy {
  final Duration threshold;
  final int days;
  final int window;
  final bool deductOverruns;

  const HardeningPolicy({
    required this.threshold,
    required this.days,
    required this.window,
    this.deductOverruns = false,
  }) : assert(days >= 1),
       assert(window >= days);
}

/// Grace period once a quota is exhausted.
class GracePolicy {
  final Duration length;
  final HardeningPolicy? hardening;

  const GracePolicy({required this.length, this.hardening});
}

enum CarryOverMode {
  /// Overrun is only logged.
  none,

  /// Overrun is deducted from the next day.
  nextDay,

  /// Overrun is spread in equal shares over the next [CarryOverPolicy.days] days.
  spread,
}

/// Carry-over of daily overruns onto the following days.
class CarryOverPolicy {
  final CarryOverMode mode;
  final int days;

  const CarryOverPolicy.none() : mode = CarryOverMode.none, days = 0;

  const CarryOverPolicy.nextDay() : mode = CarryOverMode.nextDay, days = 1;

  const CarryOverPolicy.spread(this.days)
    : mode = CarryOverMode.spread,
      assert(days >= 1);
}

/// Saved time: unused daily quota stays available for [days] days. It is
/// spent after the day's own quota, oldest first. Only the nominal quota is
/// saved (carry-over deducted, bonuses excluded). Weekly and rolling quotas
/// still apply.
///
/// Savings belong to the rule, so they can be limited to one kind of time:
/// put the policy on a "Games" rule and not on the "All" rule.
class RolloverPolicy {
  final int days;

  /// Optional cap on the savings balance; savings beyond it are lost.
  final Duration? cap;

  const RolloverPolicy({required this.days, this.cap}) : assert(days >= 1);
}

/// "Listen only", for music apps: once the rule's time is used up, the app
/// still opens for [openFor] to pick the music, then goes to the
/// background, where the music keeps playing; it opens again [reopenAfter]
/// after it was left. The time it is open then does not count for the
/// rule (it still counts for total screen time).
class ListenOnlyPolicy {
  final Duration openFor;
  final Duration reopenAfter;

  const ListenOnlyPolicy({
    this.openFor = const Duration(minutes: 1),
    this.reopenAfter = const Duration(minutes: 2),
  });

  @override
  bool operator ==(Object other) =>
      other is ListenOnlyPolicy &&
      other.openFor == openFor &&
      other.reopenAfter == reopenAfter;

  @override
  int get hashCode => Object.hash(openFor, reopenAfter);
}

/// Usage id of [appId] while it is open in "listen only": counted for
/// total screen time, but not for the rules naming the app or its group.
String listenOnlyUse(String appId) => '$appId$listenOnlySuffix';

/// Suffix of [listenOnlyUse] ids.
const listenOnlySuffix = '#listen';

/// The app behind a usage id, "listen only" or not.
String usedApp(String usageId) => usageId.endsWith(listenOnlySuffix)
    ? usageId.substring(0, usageId.length - listenOnlySuffix.length)
    : usageId;

/// Rule applied to a child.
///
/// It applies to an app A on a device D when [appTarget] covers A,
/// [deviceTarget] covers D, and its profile is active ([profileId] `null`:
/// every profile). All applicable rules add up and the strictest wins. A
/// limit the child set for themselves ([setByChild]) is an ordinary rule.
/// A rule turned off ([enabled] false) is kept but never applies.
class Rule {
  final String id;
  final String childId;
  final String? profileId;
  final AppTarget appTarget;
  final DeviceTarget deviceTarget;
  final WeeklySchedule? schedule;

  /// Time per day; [dailyQuotaByWeekday] overrides it for given weekdays.
  final Duration? dailyQuota;

  /// Time per day for given weekdays ([DateTime.monday] … [DateTime.sunday]).
  /// A weekday missing here uses [dailyQuota]; with neither, that day has
  /// no daily limit.
  final Map<int, Duration> dailyQuotaByWeekday;
  final Duration? weeklyQuota;
  final RollingQuota? rollingQuota;
  final BreakPolicy? breakPolicy;
  final GracePolicy? grace;
  final CarryOverPolicy carryOver;

  /// Saved time; `null`: disabled (default).
  final RolloverPolicy? rollover;

  /// "Listen only" once the time is used up; `null`: the app is blocked.
  final ListenOnlyPolicy? listenOnly;
  final bool setByChild;
  final bool enabled;

  const Rule({
    required this.id,
    required this.childId,
    this.profileId,
    this.appTarget = const AppTarget.all(),
    this.deviceTarget = const DeviceTarget.all(),
    this.schedule,
    this.dailyQuota,
    this.dailyQuotaByWeekday = const {},
    this.weeklyQuota,
    this.rollingQuota,
    this.breakPolicy,
    this.grace,
    this.carryOver = const CarryOverPolicy.none(),
    this.rollover,
    this.listenOnly,
    this.setByChild = false,
    this.enabled = true,
  });

  /// The same rule, turned on or off.
  Rule withEnabled(bool enabled) => Rule(
    id: id,
    childId: childId,
    profileId: profileId,
    appTarget: appTarget,
    deviceTarget: deviceTarget,
    schedule: schedule,
    dailyQuota: dailyQuota,
    dailyQuotaByWeekday: dailyQuotaByWeekday,
    weeklyQuota: weeklyQuota,
    rollingQuota: rollingQuota,
    breakPolicy: breakPolicy,
    grace: grace,
    carryOver: carryOver,
    rollover: rollover,
    listenOnly: listenOnly,
    setByChild: setByChild,
    enabled: enabled,
  );

  bool get hasDailyQuota =>
      dailyQuota != null || dailyQuotaByWeekday.isNotEmpty;

  bool get hasQuota =>
      hasDailyQuota || weeklyQuota != null || rollingQuota != null;

  /// Daily limit on [day], or `null` when there is none that day.
  Duration? dailyQuotaOn(DateTime day) =>
      dailyQuotaByWeekday[day.weekday] ?? dailyQuota;
}
