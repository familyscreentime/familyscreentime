/// Rule engine: evaluation order and available-time computation.
library;

import 'calendar.dart';
import 'modifiers.dart';
import 'rules.dart';
import 'targets.dart';
import 'usage.dart';

/// How simultaneous use on several devices is counted.
enum SimultaneousCounting {
  /// Every device counts: 10 min on two devices at once = 20 min (two
  /// apps on one screen at once count once).
  sum,

  /// Only elapsed time counts: overlapping minutes are counted once.
  elapsed,
}

/// Family-wide settings.
class FamilyConfig {
  /// App group → apps. An app may belong to several groups.
  final Map<String, Set<String>> appGroups;

  /// Device group → devices.
  final Map<String, Set<String>> deviceGroups;

  /// "Always allowed" list shown to parents (phone and SMS by default).
  final Set<String> alwaysAllowed;

  /// System components that are never blocked (launcher, system UI,
  /// Google's parental supervision, Google Play services…). Internal list,
  /// separate from [alwaysAllowed].
  final Set<String> neverBlocked;

  /// Apps never counted nor limited by time (messages, say), but only open
  /// within the hours and outside blocks, unlike [alwaysAllowed].
  final Set<String> allowedInHours;

  final List<Profile> profiles;

  /// First day of the week, using the [DateTime.weekday] convention.
  final int weekStart;

  final SimultaneousCounting counting;

  const FamilyConfig({
    this.appGroups = const {},
    this.deviceGroups = const {},
    this.alwaysAllowed = const {},
    this.neverBlocked = const {},
    this.allowedInHours = const {},
    this.profiles = const [],
    this.weekStart = DateTime.monday,
    this.counting = SimultaneousCounting.sum,
  });

  FamilyConfig copyWith({
    Map<String, Set<String>>? appGroups,
    Map<String, Set<String>>? deviceGroups,
    Set<String>? alwaysAllowed,
    Set<String>? neverBlocked,
    Set<String>? allowedInHours,
    List<Profile>? profiles,
    int? weekStart,
    SimultaneousCounting? counting,
  }) => FamilyConfig(
    appGroups: appGroups ?? this.appGroups,
    deviceGroups: deviceGroups ?? this.deviceGroups,
    alwaysAllowed: alwaysAllowed ?? this.alwaysAllowed,
    neverBlocked: neverBlocked ?? this.neverBlocked,
    allowedInHours: allowedInHours ?? this.allowedInHours,
    profiles: profiles ?? this.profiles,
    weekStart: weekStart ?? this.weekStart,
    counting: counting ?? this.counting,
  );
}

/// Family state rebuilt from the event log.
class FamilyState {
  final List<Rule> rules;
  final List<UsageSegment> usage;
  final List<Bonus> bonuses;
  final List<TemporaryBlock> temporaryBlocks;
  final List<DayUnlock> dayUnlocks;
  final List<FamilyBlock> familyBlocks;
  final List<HoursUnlock> hoursUnlocks;

  const FamilyState({
    this.rules = const [],
    this.usage = const [],
    this.bonuses = const [],
    this.temporaryBlocks = const [],
    this.dayUnlocks = const [],
    this.familyBlocks = const [],
    this.hoursUnlocks = const [],
  });

  FamilyState copyWith({
    List<Rule>? rules,
    List<UsageSegment>? usage,
    List<Bonus>? bonuses,
    List<TemporaryBlock>? temporaryBlocks,
    List<DayUnlock>? dayUnlocks,
    List<FamilyBlock>? familyBlocks,
    List<HoursUnlock>? hoursUnlocks,
  }) => FamilyState(
    rules: rules ?? this.rules,
    usage: usage ?? this.usage,
    bonuses: bonuses ?? this.bonuses,
    temporaryBlocks: temporaryBlocks ?? this.temporaryBlocks,
    dayUnlocks: dayUnlocks ?? this.dayUnlocks,
    familyBlocks: familyBlocks ?? this.familyBlocks,
    hoursUnlocks: hoursUnlocks ?? this.hoursUnlocks,
  );
}

/// Reason for a decision, in evaluation order.
enum Reason {
  alwaysAllowed,
  familyBlock,
  temporaryBlock,
  dayUnlocked,
  noRule,
  outsideSchedule,
  mandatoryBreak,
  quotaExhausted,
  gracePeriod,

  /// Time used up, but the app opens briefly to pick the music
  /// ([Rule.listenOnly]).
  listenOnly,
  withinLimits,
}

/// What sets the remaining time shown by the countdown.
enum Limiter { quota, schedule, breakDue, grace, listenOnly }

/// Decision for an app on a device at a given instant.
class Decision {
  final bool allowed;
  final Reason reason;

  /// Time before the next block, when use is allowed and limited.
  final Duration? remaining;

  /// What sets [remaining].
  final Limiter? limiter;

  /// When the decision changes by itself, if known (end of a block or a
  /// break, start of the next allowed time range).
  final DateTime? until;

  /// Rule behind the decision or the remaining time.
  final String? ruleId;

  const Decision({
    required this.allowed,
    required this.reason,
    this.remaining,
    this.limiter,
    this.until,
    this.ruleId,
  });

  @override
  String toString() =>
      'Decision(${allowed ? 'allowed' : 'blocked'}, '
      '$reason, remaining: $remaining, limiter: $limiter, '
      'until: $until, rule: $ruleId)';
}

/// One day's account of a rule's daily limit.
class DayLedger {
  final DateTime day;

  /// False when the rule was not in force that day (another profile).
  final bool active;
  final bool unlocked;
  final Duration quota;
  final Duration bonus;

  /// Past overruns carried over and deducted that day.
  final Duration carriedIn;

  /// Overruns that turned the limit firm, deducted that day.
  final Duration deducted;
  final Duration consumed;

  /// Savings usable that day, before any consumption.
  final Duration savingsAvailable;

  /// Part of those savings consumed that day.
  final Duration savingsUsed;

  /// Savings built up that day, usable on the following days.
  final Duration saved;

  /// Overrun beyond the quota, bonuses and savings used.
  final Duration overrun;

  const DayLedger({
    required this.day,
    required this.active,
    required this.unlocked,
    required this.quota,
    required this.bonus,
    required this.carriedIn,
    this.deducted = Duration.zero,
    required this.consumed,
    required this.savingsAvailable,
    required this.savingsUsed,
    required this.saved,
    required this.overrun,
  });

  DayLedger.inactive(this.day)
    : active = false,
      unlocked = false,
      quota = Duration.zero,
      bonus = Duration.zero,
      carriedIn = Duration.zero,
      deducted = Duration.zero,
      consumed = Duration.zero,
      savingsAvailable = Duration.zero,
      savingsUsed = Duration.zero,
      saved = Duration.zero,
      overrun = Duration.zero;

  /// The day's own time, savings excluded:
  /// max(0, quota + bonus − carry-over − deducted overruns).
  Duration get allowance {
    final a = quota + bonus - carriedIn - deducted;
    return a < Duration.zero ? Duration.zero : a;
  }
}

/// One day's savings, identified by its position in the simulation.
class _SavingsPot {
  final int index;
  Duration left;

  _SavingsPot(this.index, this.left);
}

/// Mandatory-break state of a rule.
class BreakStatus {
  /// End of the current break, or `null` when there is none.
  final DateTime? breakUntil;

  /// Use left before the next break (zero during a break).
  final Duration untilBreak;

  const BreakStatus({this.breakUntil, required this.untilBreak});

  bool get inBreak => breakUntil != null;
}

/// Computes decisions. Stateless: everything comes from [FamilyState] and
/// the instant passed in, so every device holding the same log reaches the
/// same decision.
class RuleEngine {
  final FamilyConfig config;

  const RuleEngine(this.config);

  /// How far back continuous use is examined for mandatory breaks.
  static const _breakLookback = Duration(hours: 24);

  Decision evaluate(
    FamilyState state, {
    required String childId,
    required String deviceId,
    required String appId,
    required DateTime now,
  }) {
    // 1. Always allowed, even during a family block.
    if (config.neverBlocked.contains(appId) ||
        config.alwaysAllowed.contains(appId)) {
      return const Decision(allowed: true, reason: Reason.alwaysAllowed);
    }

    // 2. Family block.
    final family = state.familyBlocks.where((b) => b.isActiveAt(now)).toList();
    if (family.isNotEmpty) {
      return Decision(
        allowed: false,
        reason: Reason.familyBlock,
        until: _latestEnd(family.map((b) => b.until)),
      );
    }

    // 3. Temporary block on the app, the device or the child.
    final blocks = state.temporaryBlocks
        .where(
          (b) =>
              b.childId == childId &&
              b.isActiveAt(now) &&
              b.appTarget.covers(appId, config.appGroups) &&
              b.deviceTarget.covers(deviceId, config.deviceGroups),
        )
        .toList();
    if (blocks.isNotEmpty) {
      return Decision(
        allowed: false,
        reason: Reason.temporaryBlock,
        until: _latestEnd(blocks.map((b) => b.until)),
      );
    }

    // 4. Restrictions lifted for the day.
    if (isDayUnlocked(state, childId, now)) {
      return Decision(
        allowed: true,
        reason: Reason.dayUnlocked,
        until: addDays(dayOf(now), 1),
      );
    }

    // 5. Today's profile and the applicable rules.
    final rules = applicableRules(
      state,
      childId: childId,
      deviceId: deviceId,
      appId: appId,
      now: now,
    );
    if (rules.isEmpty) {
      return const Decision(allowed: true, reason: Reason.noRule);
    }

    // 6. Schedules, unless the parent opened a rule's hours early.
    final outside = rules.where(
      (r) =>
          r.schedule != null &&
          !r.schedule!.allows(now) &&
          hoursUnlockEnd(state, r, now) == null,
    );
    if (outside.isNotEmpty) {
      DateTime? until;
      for (final r in outside) {
        final next = r.schedule!.nextStart(now);
        if (next != null && (until == null || next.isAfter(until))) {
          until = next;
        }
      }
      return Decision(
        allowed: false,
        reason: Reason.outsideSchedule,
        until: until,
        ruleId: outside.first.id,
      );
    }

    // Apps open within the hours but never limited by time.
    if (config.allowedInHours.contains(appId)) {
      return const Decision(allowed: true, reason: Reason.alwaysAllowed);
    }

    // 7. Mandatory breaks.
    final breaks = <Rule, BreakStatus>{};
    for (final r in rules.where((r) => r.breakPolicy != null)) {
      final status = breakStatus(state, r, childId: childId, now: now);
      if (status.inBreak) {
        return Decision(
          allowed: false,
          reason: Reason.mandatoryBreak,
          until: status.breakUntil,
          ruleId: r.id,
        );
      }
      breaks[r] = status;
    }

    // 8. Quotas, then grace period.
    final remainingByRule = <Rule, Duration>{};
    for (final r in rules.where((r) => r.hasQuota)) {
      final remaining = remainingQuota(state, r, childId: childId, now: now);
      if (remaining != null) remainingByRule[r] = remaining;
    }
    // Nearest quota limit among the rules that are not exhausted.
    (Duration, String)? quota;
    for (final e in remainingByRule.entries) {
      if (e.value <= Duration.zero) continue;
      if (quota == null || e.value < quota.$1) quota = (e.value, e.key.id);
    }
    final exhausted = remainingByRule.entries.where(
      (e) => e.value <= Duration.zero,
    );
    if (exhausted.isNotEmpty) {
      Duration? graceLeft;
      String? graceRule;
      Rule? listening;
      // Grace lets the child finish what they were doing, not start
      // something new: only the app already in use when time ran out.
      final session = sessionStart(
        state,
        childId: childId,
        deviceId: deviceId,
        appId: appId,
        now: now,
      );
      for (final e in exhausted) {
        final overrun = -e.value;
        final left =
            effectiveGrace(state, e.key, childId: childId, now: now) - overrun;
        final ranOut = now.subtract(overrun);
        if (left <= Duration.zero ||
            session == null ||
            !session.isBefore(ranOut)) {
          // Listen only: the app may still open briefly.
          if (e.key.listenOnly != null) {
            listening ??= e.key;
            continue;
          }
          return Decision(
            allowed: false,
            reason: Reason.quotaExhausted,
            ruleId: e.key.id,
          );
        }
        if (graceLeft == null || left < graceLeft) {
          graceLeft = left;
          graceRule = e.key.id;
        }
      }
      if (listening != null) {
        final open = listenOnlyLeft(
          state,
          listening,
          childId: childId,
          deviceId: deviceId,
          appId: appId,
          now: now,
        );
        if (open.$1 <= Duration.zero) {
          return Decision(
            allowed: false,
            reason: Reason.quotaExhausted,
            ruleId: listening.id,
            until: open.$2,
          );
        }
        final limit = _tightest(
          state: state,
          quota: quota,
          grace: graceLeft != null && graceLeft < open.$1
              ? (graceLeft, graceRule!)
              : (open.$1, listening.id),
          rules: rules,
          breaks: breaks,
          now: now,
        );
        return Decision(
          allowed: true,
          reason: Reason.listenOnly,
          remaining: limit.$1,
          limiter: limit.$2 == Limiter.grace ? Limiter.listenOnly : limit.$2,
          ruleId: limit.$3,
        );
      }
      final limit = _tightest(
        state: state,
        quota: quota,
        grace: (graceLeft!, graceRule!),
        rules: rules,
        breaks: breaks,
        now: now,
      );
      return Decision(
        allowed: true,
        reason: Reason.gracePeriod,
        remaining: limit.$1,
        limiter: limit.$2,
        ruleId: limit.$3,
      );
    }

    // 9. Allowed: the countdown shows the nearest limit.
    final limit = _tightest(
      state: state,
      quota: quota,
      grace: null,
      rules: rules,
      breaks: breaks,
      now: now,
    );
    return Decision(
      allowed: true,
      reason: Reason.withinLimits,
      remaining: limit.$1,
      limiter: limit.$2,
      ruleId: limit.$3,
    );
  }

  /// The child's rules that target this app on this device, in the active
  /// profile.
  List<Rule> applicableRules(
    FamilyState state, {
    required String childId,
    required String deviceId,
    required String appId,
    required DateTime now,
  }) {
    final profileId = activeProfileId(config.profiles, now);
    return state.rules
        .where(
          (r) =>
              r.enabled &&
              r.childId == childId &&
              _profileMatches(r, profileId) &&
              r.appTarget.covers(appId, config.appGroups) &&
              r.deviceTarget.covers(deviceId, config.deviceGroups),
        )
        .toList();
  }

  bool _profileMatches(Rule r, String? activeProfile) {
    if (r.profileId == null) return true;
    if (config.profiles.isEmpty) return true;
    return r.profileId == activeProfile;
  }

  /// Start of the use of [appId] going on at [now] on [deviceId], joining
  /// back-to-back segments; `null` when the app is not in use. A pause of
  /// more than a few seconds, or another app used in between, ends it.
  DateTime? sessionStart(
    FamilyState state, {
    required String childId,
    required String deviceId,
    required String appId,
    required DateTime now,
  }) {
    const gap = Duration(seconds: 5);
    final onDevice = [
      for (final s in state.usage)
        if (s.childId == childId &&
            s.deviceId == deviceId &&
            s.injectedTarget == null)
          s,
    ]..sort((a, b) => b.end.compareTo(a.end));
    DateTime? start;
    var edge = now;
    for (final s in onDevice) {
      if (s.end.isBefore(edge.subtract(gap))) break;
      // Another app used since: the session is over.
      if (s.appId != appId) break;
      if (start == null || s.start.isBefore(start)) start = s.start;
      if (s.start.isBefore(edge)) edge = s.start;
    }
    return start;
  }

  /// "Listen only" for [appId] under [r]: the time it may stay open now,
  /// and when it opens again once that is over. The opening is recorded as
  /// [listenOnlyUse]; it starts when the app comes to the front, at the
  /// earliest [ListenOnlyPolicy.reopenAfter] after the last one ended.
  (Duration, DateTime?) listenOnlyLeft(
    FamilyState state,
    Rule r, {
    required String childId,
    required String deviceId,
    required String appId,
    required DateTime now,
  }) {
    final policy = r.listenOnly!;
    final listen = listenOnlyUse(appId);
    final start = sessionStart(
      state,
      childId: childId,
      deviceId: deviceId,
      appId: listen,
      now: now,
    );
    if (start != null) {
      final left = policy.openFor - now.difference(start);
      // Over: it opens again once left for the delay.
      return (left, left > Duration.zero ? null : now.add(policy.reopenAfter));
    }
    DateTime? lastEnd;
    for (final s in state.usage) {
      if (s.childId != childId || s.deviceId != deviceId || s.appId != listen) {
        continue;
      }
      if (lastEnd == null || s.end.isAfter(lastEnd)) lastEnd = s.end;
    }
    final reopen = lastEnd?.add(policy.reopenAfter);
    if (reopen != null && reopen.isAfter(now)) return (Duration.zero, reopen);
    return (policy.openFor, null);
  }

  /// End of an early opening of [r]'s hours in force at [now], if any.
  DateTime? hoursUnlockEnd(FamilyState state, Rule r, DateTime now) {
    DateTime? end;
    for (final u in state.hoursUnlocks) {
      if (u.ruleId == r.id && u.isActiveAt(now)) {
        if (end == null || u.until.isAfter(end)) end = u.until;
      }
    }
    return end;
  }

  bool isDayUnlocked(FamilyState state, String childId, DateTime t) =>
      state.dayUnlocks.any((u) => u.childId == childId && u.coversDay(t));

  /// True when the segment counts towards the rule.
  ///
  /// A browser's video time also counts for the rules covering
  /// [browserVideoApp]. Time in "always allowed" apps and never-blocked system components does
  /// not count. Injected time has no device: it counts towards rules that
  /// target all devices and whose app target is "All", the same target, or a
  /// group containing the injected app.
  bool segmentCounts(Rule r, UsageSegment s) {
    // A video in a browser counts for the rules naming the browser's
    // videos, even when the browser itself is never limited.
    if (s.activity == UsageActivity.video &&
        r.appTarget.kind != TargetKind.all &&
        r.appTarget.covers(browserVideoApp, config.appGroups)) {
      return r.deviceTarget.covers(s.deviceId!, config.deviceGroups);
    }
    final app = s.appId;
    if (app != null &&
        (config.alwaysAllowed.contains(app) ||
            config.allowedInHours.contains(app) ||
            config.neverBlocked.contains(app))) {
      return false;
    }
    final target = s.injectedTarget;
    if (target != null) {
      if (r.deviceTarget != const DeviceTarget.all()) return false;
      if (r.appTarget == const AppTarget.all() || r.appTarget == target) {
        return true;
      }
      return target.kind == TargetKind.single &&
          r.appTarget.covers(target.id!, config.appGroups);
    }
    return r.appTarget.covers(s.appId!, config.appGroups) &&
        r.deviceTarget.covers(s.deviceId!, config.deviceGroups);
  }

  /// Time the child consumed for the rule over [from, to).
  Duration consumption(
    FamilyState state,
    Rule r, {
    required String childId,
    required DateTime from,
    required DateTime to,
  }) {
    final parts = <Interval>[];
    // Sum: each device counts on its own, but on one device, apps on
    // screen together (split screen, floating video) count once. Time
    // entered by hand adds up as it is.
    final byDevice = <String, List<Interval>>{};
    for (final s in state.usage) {
      if (s.childId != childId || !segmentCounts(r, s)) continue;
      final part = s.clip(from, to);
      if (part == null) continue;
      final device = s.deviceId;
      if (config.counting == SimultaneousCounting.sum && device != null) {
        byDevice.putIfAbsent(device, () => []).add(part);
      } else {
        parts.add(part);
      }
    }
    if (config.counting == SimultaneousCounting.elapsed) {
      return totalLength(mergeIntervals(parts));
    }
    var total = totalLength(parts);
    for (final l in byDevice.values) {
      total += totalLength(mergeIntervals(l));
    }
    return total;
  }

  /// The rule's bonuses granted within [from, to], valued at [asOf].
  ///
  /// A bonus that is still valid counts in full. An expired bonus only
  /// counts for the part consumed while it was valid (at most its amount),
  /// so an unused bonus does not inflate the week.
  Duration bonuses(
    FamilyState state,
    Rule r, {
    required String childId,
    required DateTime from,
    required DateTime to,
    required DateTime asOf,
  }) {
    var total = Duration.zero;
    for (final b in state.bonuses) {
      if (b.childId != childId) continue;
      final applies =
          b.ruleId == r.id ||
          (b.appTarget != null && b.appTarget == r.appTarget);
      if (!applies) continue;
      if (b.grantedAt.isBefore(from) || b.grantedAt.isAfter(to)) continue;
      if (b.isValidAt(asOf)) {
        total += b.amount;
      } else {
        final used = consumption(
          state,
          r,
          childId: childId,
          from: b.grantedAt,
          to: b.validUntil,
        );
        total += used < b.amount ? used : b.amount;
      }
    }
    return total;
  }

  /// Time available for the rule: the minimum over the day, the week and the
  /// rolling window. Negative when overrun; `null` when no quota applies
  /// right now (e.g. no daily time set for today's weekday).
  ///
  /// Day: max(0, quota + bonus − carry-over) + savings − consumed.
  /// Week and rolling window: quota + bonus − consumed. Carry-over and
  /// savings only affect the daily period.
  Duration? remainingQuota(
    FamilyState state,
    Rule r, {
    required String childId,
    required DateTime now,
  }) {
    final today = dayOf(now);
    Duration? best;

    void consider(Duration rem) {
      if (best == null || rem < best!) best = rem;
    }

    if (r.hasDailyQuota) {
      final day = dailyLedger(state, r, childId: childId, now: now).last;
      // Inactive: no daily limit today (another profile, or none set for
      // this weekday).
      if (day.active) {
        consider(day.allowance + day.savingsAvailable - day.consumed);
      }
    }

    void period(Duration quota, DateTime from) {
      final b = bonuses(
        state,
        r,
        childId: childId,
        from: from,
        to: now,
        asOf: now,
      );
      final used = consumption(state, r, childId: childId, from: from, to: now);
      consider(quota + b - used);
    }

    if (r.weeklyQuota != null) {
      period(r.weeklyQuota!, startOfWeek(now, config.weekStart));
    }
    if (r.rollingQuota != null) {
      final q = r.rollingQuota!;
      period(q.quota, addDays(today, -(q.days - 1)));
    }
    return best;
  }

  /// Day-by-day account of the rule's daily limit, from the earliest
  /// relevant day up to today (last element, stopped at [now]).
  ///
  /// Each past day is judged by the daily limit in force that day
  /// ([Rule.history]): the limit at the end of the day sets the time
  /// allowed (today: the current limit, always); a day when the limit changed only overruns the most generous
  /// of its limits, and a day with no limit for part of it overruns
  /// nothing. A stricter limit is thus never applied to the time used
  /// before it.
  ///
  /// Days are simulated in order because carry-over and savings depend on
  /// it: a day's carry-over comes from the previous days' overruns, and
  /// savings build up and are spent over time. The oldest savings are
  /// spent first, after the day's own quota. Days when the rule is not in
  /// force (another profile) or has no daily limit (none set for that
  /// weekday) are inactive: they produce neither savings nor overruns, and
  /// take no carry-over.
  ///
  /// At least [history] days before today are included, for display.
  ///
  /// Empty when the rule has no daily limit on any day.
  List<DayLedger> dailyLedger(
    FamilyState state,
    Rule r, {
    required String childId,
    required DateTime now,
    int history = 0,
  }) {
    if (!r.hasDailyQuota) return const [];
    final today = dayOf(now);
    final carryDays = r.carryOver.mode == CarryOverMode.none
        ? 0
        : r.carryOver.days;
    final hardening = r.grace?.hardening;
    final window = hardening?.window ?? 0;
    final keep = r.rollover?.days ?? 0;
    final cap = r.rollover?.cap;
    // Deducting the overruns that made the limit firm; not combined with a
    // carry-over, which already deducts every overrun.
    final deduct =
        hardening != null &&
        hardening.deductOverruns &&
        r.carryOver.mode == CarryOverMode.none;
    // Enough days for the days we look at to no longer depend on where the
    // simulation starts.
    final needed = window * (deduct ? 3 : 1) + carryDays + 4 * keep + 1;
    final span = needed > history ? needed : history;
    final start = addDays(today, -span);

    final overruns = <Duration>[];
    Duration overrunBack(int index, int back) {
      final j = index - back;
      if (j >= 0) return overruns[j];
      return _standaloneOverrun(state, r, childId, addDays(start, j));
    }

    final pots = <_SavingsPot>[];
    final ledger = <DayLedger>[];
    var debt = Duration.zero;
    final billed = <int>{};
    for (var i = 0; i <= span; i++) {
      final day = addDays(start, i);
      final isToday = i == span;
      final end = isToday ? now : addDays(day, 1);
      pots.removeWhere((p) => p.index < i - keep);

      // Today: the rule as it is now, whatever the clock says (a clock set
      // back to before a change does not bring the former limit back).
      final quota = isToday
          ? r.dailyQuotaOn(day)
          : r.dailyQuotaAt(end.subtract(_instant));
      final overrunQuota = _overrunQuota(r, day, end);
      if (quota == null || !_ruleActiveOn(r, day)) {
        overruns.add(Duration.zero);
        ledger.add(DayLedger.inactive(day));
        continue;
      }

      final unlocked = isDayUnlocked(state, childId, day);
      final carry = _carry(r.carryOver, (back) => overrunBack(i, back));
      final bonus = bonuses(
        state,
        r,
        childId: childId,
        from: day,
        to: end,
        asOf: end,
      );
      final used = consumption(state, r, childId: childId, from: day, to: end);
      final available = pots.fold(Duration.zero, (sum, p) => sum + p.left);

      var deducted = Duration.zero;
      if (deduct) {
        // When the limit turns firm, the overruns of its window become a
        // debt, each one once, paid from the following days' time.
        var count = 0;
        for (var k = 1; k <= hardening.window && i - k >= 0; k++) {
          if (overruns[i - k] > hardening.threshold) count++;
        }
        if (count >= hardening.days) {
          for (var k = 1; k <= hardening.window && i - k >= 0; k++) {
            if (overruns[i - k] > Duration.zero && billed.add(i - k)) {
              debt += overruns[i - k];
            }
          }
        }
        var room = quota + bonus - carry;
        if (room < Duration.zero) room = Duration.zero;
        deducted = debt < room ? debt : room;
        debt -= deducted;
      }

      var allowance = quota + bonus - carry - deducted;
      if (allowance < Duration.zero) allowance = Duration.zero;

      var drawn = Duration.zero;
      if (!unlocked && used > allowance) {
        var need = used - allowance;
        for (final p in pots) {
          if (need <= Duration.zero) break;
          final take = p.left < need ? p.left : need;
          p.left -= take;
          need -= take;
          drawn += take;
        }
        pots.removeWhere((p) => p.left <= Duration.zero);
      }

      // Overrun is measured against the nominal quota so that carry-overs
      // do not snowball, and against the most generous limit of the day.
      var over = overrunQuota == null
          ? Duration.zero
          : used - (overrunQuota + bonus) - drawn;
      if (unlocked || over < Duration.zero) over = Duration.zero;
      overruns.add(over);

      // Savings: what is left of the day's quota, carry-over deducted,
      // bonuses excluded, within the optional cap on the balance.
      var saved = Duration.zero;
      if (keep > 0 && !isToday) {
        var base = quota - carry - deducted;
        if (base < Duration.zero) base = Duration.zero;
        if (base > used) saved = base - used;
        if (cap != null) {
          // Pots that expire tonight do not count against the cap.
          final kept = pots
              .where((p) => p.index > i - keep)
              .fold(Duration.zero, (sum, p) => sum + p.left);
          final room = cap - kept;
          if (saved > room) saved = room > Duration.zero ? room : Duration.zero;
        }
        if (saved > Duration.zero) pots.add(_SavingsPot(i, saved));
      }

      ledger.add(
        DayLedger(
          day: day,
          active: true,
          unlocked: unlocked,
          quota: quota,
          bonus: bonus,
          carriedIn: carry,
          deducted: deducted,
          consumed: used,
          savingsAvailable: available,
          savingsUsed: drawn,
          saved: saved,
          overrun: over,
        ),
      );
    }
    return ledger;
  }

  bool _ruleActiveOn(Rule r, DateTime day) =>
      _profileMatches(r, activeProfileId(config.profiles, day));

  static const _instant = Duration(microseconds: 1);

  /// The limit a day's overrun is measured against: the most generous of
  /// those in force from [day] to [end]; `null` when there was no limit
  /// for part of it.
  Duration? _overrunQuota(Rule r, DateTime day, DateTime end) {
    Duration? most;
    for (final q in r.dailyQuotasDuring(day, end)) {
      if (q == null) return null;
      if (most == null || q > most) most = q;
    }
    return most;
  }

  /// A day's overrun computed on its own (without savings), for days before
  /// the start of the simulation.
  Duration _standaloneOverrun(
    FamilyState state,
    Rule r,
    String childId,
    DateTime day,
  ) {
    final end = addDays(day, 1);
    final quota = _overrunQuota(r, day, end);
    if (quota == null || !_ruleActiveOn(r, day)) return Duration.zero;
    if (isDayUnlocked(state, childId, day)) return Duration.zero;
    final used = consumption(state, r, childId: childId, from: day, to: end);
    final b = bonuses(
      state,
      r,
      childId: childId,
      from: day,
      to: end,
      asOf: end,
    );
    final over = used - (quota + b);
    return over > Duration.zero ? over : Duration.zero;
  }

  /// Carry-over due for a day, from the previous days' overruns
  /// ([overrunBack] (1) = the day before).
  Duration _carry(
    CarryOverPolicy policy,
    Duration Function(int back) overrunBack,
  ) {
    switch (policy.mode) {
      case CarryOverMode.none:
        return Duration.zero;
      case CarryOverMode.nextDay:
        return overrunBack(1);
      case CarryOverMode.spread:
        var total = Duration.zero;
        for (var i = 1; i <= policy.days; i++) {
          final over = overrunBack(i).inMicroseconds;
          // Equal shares; the division remainder goes to the first day.
          var share = over ~/ policy.days;
          if (i == 1) share += over % policy.days;
          total += Duration(microseconds: share);
        }
        return total;
    }
  }

  DayLedger? _ledgerDay(
    FamilyState state,
    Rule r,
    String childId,
    DateTime day,
  ) {
    final d = dayOf(day);
    final ledger = dailyLedger(state, r, childId: childId, now: addDays(d, 1));
    for (final e in ledger) {
      if (sameDay(e.day, d)) return e;
    }
    return null;
  }

  /// Daily-limit overrun on a given day, beyond the nominal quota, bonuses
  /// and savings used. Zero when the rule has no daily limit, was not in
  /// force, or the day was unlocked.
  Duration dailyOverrun(
    FamilyState state,
    Rule r, {
    required String childId,
    required DateTime day,
  }) => _ledgerDay(state, r, childId, day)?.overrun ?? Duration.zero;

  /// Share of past overruns deducted from [day].
  Duration carriedOver(
    FamilyState state,
    Rule r, {
    required String childId,
    required DateTime day,
  }) {
    final ledger = dailyLedger(state, r, childId: childId, now: dayOf(day));
    return ledger.isEmpty ? Duration.zero : ledger.last.carriedIn;
  }

  /// Savings still available at [now], for display.
  Duration savingsLeft(
    FamilyState state,
    Rule r, {
    required String childId,
    required DateTime now,
  }) {
    final ledger = dailyLedger(state, r, childId: childId, now: now);
    if (ledger.isEmpty) return Duration.zero;
    return ledger.last.savingsAvailable - ledger.last.savingsUsed;
  }

  /// Grace available today, taking hardening into account.
  Duration effectiveGrace(
    FamilyState state,
    Rule r, {
    required String childId,
    required DateTime now,
  }) {
    final grace = r.grace;
    if (grace == null) return Duration.zero;
    final h = grace.hardening;
    if (h == null) return grace.length;
    final count = hardeningCount(state, r, childId: childId, now: now);
    return count >= h.days ? Duration.zero : grace.length;
  }

  /// Number of days whose overrun exceeded the hardening threshold, within
  /// its window (today excluded). Lets the UI warn before the limit turns
  /// firm.
  int hardeningCount(
    FamilyState state,
    Rule r, {
    required String childId,
    required DateTime now,
  }) {
    final h = r.grace?.hardening;
    if (h == null) return 0;
    final ledger = dailyLedger(state, r, childId: childId, now: now);
    if (ledger.isEmpty) return 0;
    var count = 0;
    final last = ledger.length - 1;
    for (var i = 1; i <= h.window && last - i >= 0; i++) {
      if (ledger[last - i].overrun > h.threshold) count++;
    }
    return count;
  }

  /// The rule's mandatory-break state at [now].
  ///
  /// Use on all covered devices is merged (two devices at once = a single
  /// continuous session). Injected time is ignored. A gap at least as long
  /// as the break resets the counter.
  BreakStatus breakStatus(
    FamilyState state,
    Rule r, {
    required String childId,
    required DateTime now,
  }) {
    final policy = r.breakPolicy;
    if (policy == null ||
        policy.after <= Duration.zero ||
        policy.length <= Duration.zero) {
      return const BreakStatus(untilBreak: Duration(days: 365));
    }
    final from = now.subtract(_breakLookback);
    final parts = <Interval>[];
    for (final s in state.usage) {
      if (s.childId != childId || s.isInjected || !segmentCounts(r, s)) {
        continue;
      }
      final part = s.clip(from, now);
      if (part != null) parts.add(part);
    }

    var run = Duration.zero;
    DateTime? lastEnd;
    DateTime? breakUntil;
    for (final interval in mergeIntervals(parts)) {
      var start = interval.start;
      final end = interval.end;
      if (breakUntil != null) {
        if (!end.isAfter(breakUntil)) continue;
        if (start.isBefore(breakUntil)) start = breakUntil;
      }
      if (lastEnd != null && start.difference(lastEnd) >= policy.length) {
        run = Duration.zero;
      }
      while (true) {
        final need = policy.after - run;
        final available = end.difference(start);
        if (available < need) {
          run += available;
          lastEnd = end;
          break;
        }
        final reached = start.add(need);
        breakUntil = reached.add(policy.length);
        run = Duration.zero;
        lastEnd = breakUntil;
        if (!end.isAfter(breakUntil)) break;
        start = breakUntil;
      }
    }

    if (breakUntil != null && now.isBefore(breakUntil)) {
      return BreakStatus(breakUntil: breakUntil, untilBreak: Duration.zero);
    }
    if (lastEnd != null && now.difference(lastEnd) >= policy.length) {
      run = Duration.zero;
    }
    return BreakStatus(untilBreak: policy.after - run);
  }

  /// Nearest limit among quota (or grace), end of the time range and next
  /// break.
  (Duration?, Limiter?, String?) _tightest({
    required FamilyState state,
    required (Duration, String)? quota,
    required (Duration, String)? grace,
    required List<Rule> rules,
    required Map<Rule, BreakStatus> breaks,
    required DateTime now,
  }) {
    Duration? best;
    Limiter? limiter;
    String? ruleId;

    void consider(Duration d, Limiter l, String id) {
      if (best == null || d < best!) {
        best = d;
        limiter = l;
        ruleId = id;
      }
    }

    if (quota != null) consider(quota.$1, Limiter.quota, quota.$2);
    if (grace != null) consider(grace.$1, Limiter.grace, grace.$2);
    for (final r in rules) {
      var left = r.schedule?.untilEnd(now);
      // Hours opened early: until the end the parent set, or later.
      final unlocked = hoursUnlockEnd(state, r, now);
      if (unlocked != null) {
        final l = unlocked.difference(now);
        if (left == null || l > left) left = l;
      }
      if (left != null) consider(left, Limiter.schedule, r.id);
    }
    for (final e in breaks.entries) {
      consider(e.value.untilBreak, Limiter.breakDue, e.key.id);
    }
    return (best, limiter, ruleId);
  }

  /// Latest end; `null` when one of the blocks has no end.
  DateTime? _latestEnd(Iterable<DateTime?> ends) {
    DateTime? latest;
    for (final e in ends) {
      if (e == null) return null;
      if (latest == null || e.isAfter(latest)) latest = e;
    }
    return latest;
  }
}
