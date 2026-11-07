/// The children at a glance, on the parent's device: their time today,
/// whether each can use their devices now, and unlocking them in one tap.
library;

import 'package:screentime_engine/screentime_engine.dart';

import 'availability.dart';
import 'controller.dart';
import 'ordering.dart';
import 'rule_status.dart';
import 'store.dart';

/// Time used today under a limit: total screen time, or a group of apps.
class TimeToday {
  final Duration used;

  /// A limit on it has no time left.
  final bool over;

  const TimeToday(this.used, {this.over = false});
}

/// A child's time today, on the parent's home.
class ChildTimes {
  /// Total screen time, as its limits count it.
  final TimeToday total;

  /// Each group of apps with a time limit in force, by group id, in the
  /// order of their names.
  final Map<String, TimeToday> groups;

  const ChildTimes(this.total, this.groups);
}

/// [childId]'s time today at [now]: total screen time, and each group of
/// apps that a limit of the parent's in force ([inForce]) gives a time
/// limit. A limit with no time left makes it [TimeToday.over].
ChildTimes childTimes(
  FamilyData family,
  List<UsageSegment> usage,
  String childId,
  DateTime now, {
  required bool Function(Rule r) inForce,
}) {
  final engine = RuleEngine(family.config);
  final state = family.state.copyWith(usage: usage);
  final today = dayOf(now);
  final limits = [
    for (final r in family.state.rules)
      if (r.childId == childId &&
          r.enabled &&
          !r.setByChild &&
          r.hasQuota &&
          inForce(r))
        r,
  ];
  TimeToday of(AppTarget target) => TimeToday(
    engine.consumption(
      state,
      Rule(id: '', childId: childId, appTarget: target),
      childId: childId,
      from: today,
      to: now,
    ),
    over: limits.any((r) {
      if (r.appTarget != target) return false;
      final left = ruleStatus(
        engine,
        state,
        r,
        childId: childId,
        now: now,
      ).remaining;
      return left != null && left <= Duration.zero;
    }),
  );
  final groups =
      {
        for (final r in limits)
          if (r.appTarget.kind == TargetKind.group) r.appTarget.id!,
      }.toList()..sort(
        (a, b) =>
            compareNames(family.groupNames[a] ?? a, family.groupNames[b] ?? b),
      );
  return ChildTimes(of(const AppTarget.all()), {
    for (final id in groups) id: of(AppTarget.group(id)),
  });
}

/// Whether [childId] can use none of their devices at [now]: only the
/// rules on all apps (total screen time, hours, blocks, breaks) count, as
/// for the device lock. With no device known, a device of no group is
/// assumed.
bool childLocked(
  FamilyData family,
  List<UsageSegment> usage,
  String childId,
  Iterable<String> devices,
  DateTime now,
) {
  final engine = RuleEngine(family.config);
  final state = family.state.copyWith(usage: usage);
  final ids = devices.isEmpty ? const [''] : devices;
  return ids.every(
    (d) => !engine
        .evaluate(
          state,
          childId: childId,
          deviceId: d,
          appId: probeApp,
          now: now,
        )
        .allowed,
  );
}

/// What unlocking a child does: the family as it becomes, and until when
/// the child can use their devices (`null`: no end planned today).
class UnlockPlan {
  final FamilyData family;
  final DateTime? until;

  const UnlockPlan(this.family, this.until);
}

/// Unlocks [childId] at [now]: lifts the blocks; then, if the hours
/// still keep them out, opens them early until the end of the next allowed
/// range today; if that is not enough (no range left today, or no time
/// left), lifts every restriction until midnight.
UnlockPlan planUnlock(
  FamilyData family,
  List<UsageSegment> usage,
  String childId,
  Iterable<String> devices,
  DateTime now, {
  required List<(Rule, DateTime)> openable,
  required String Function() newId,
}) {
  bool locked(FamilyData f) => childLocked(f, usage, childId, devices, now);

  final lifted = family.copyWith(
    state: stateWith(
      family.state,
      temporaryBlocks: [
        for (final b in family.state.temporaryBlocks)
          b.childId == childId && b.isActiveAt(now) ? b.endingAt(now) : b,
      ],
    ),
  );
  if (!locked(lifted)) return UnlockPlan(lifted, null);

  if (openable.isNotEmpty) {
    final opened = lifted.copyWith(
      state: stateWith(
        lifted.state,
        hoursUnlocks: [
          ...lifted.state.hoursUnlocks,
          for (final (rule, end) in openable)
            HoursUnlock(
              id: newId(),
              childId: childId,
              ruleId: rule.id,
              from: now,
              until: end,
            ),
        ],
      ),
    );
    if (!locked(opened)) {
      final ends = [for (final (_, end) in openable) end]..sort();
      return UnlockPlan(opened, ends.first);
    }
  }

  return UnlockPlan(
    lifted.copyWith(
      state: stateWith(
        lifted.state,
        dayUnlocks: [
          ...lifted.state.dayUnlocks,
          DayUnlock(id: newId(), childId: childId, day: now),
        ],
      ),
    ),
    addDays(dayOf(now), 1),
  );
}

extension ChildrenAtAGlance on AppController {
  /// The devices of each child, from the family log.
  Future<Map<String, Set<String>>> childDevices() async {
    final log = await sync;
    final result = <String, Set<String>>{};
    for (final e in (log?.devices ?? const {}).entries) {
      final child = e.value['childId'];
      if (child is String) (result[child] ??= {}).add(e.key);
    }
    return result;
  }

  /// Each child's time today at [now] (see [childTimes]).
  Future<Map<String, ChildTimes>> childrenTimes(DateTime now) async {
    final usage = await recentUsage();
    return {
      for (final c in family.children)
        c.id: childTimes(
          family,
          usage,
          c.id,
          now,
          inForce: (r) => ruleInForce(r, now),
        ),
    };
  }

  /// The children who can use none of their devices at [now].
  Future<Set<String>> lockedChildren(DateTime now) async {
    final usage = await recentUsage();
    final devices = await childDevices();
    return {
      for (final c in family.children)
        if (childLocked(family, usage, c.id, devices[c.id] ?? const {}, now))
          c.id,
    };
  }

  /// Unlocks [childId] (see [planUnlock]); until when they can use their
  /// devices.
  Future<DateTime?> unlockChild(String childId, {DateTime? now}) async {
    final t = now ?? DateTime.now();
    final plan = planUnlock(
      family,
      await recentUsage(),
      childId,
      (await childDevices())[childId] ?? const {},
      t,
      openable: openableEarly(t, forChild: childId),
      newId: newId,
    );
    await updateFamily(plan.family);
    return plan.until;
  }
}
