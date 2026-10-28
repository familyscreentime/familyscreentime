/// The children at a glance, on the parent's device: whether each can use
/// their devices now, and unlocking them in one tap.
library;

import 'package:screentime_engine/screentime_engine.dart';

import 'availability.dart';
import 'controller.dart';
import 'store.dart';

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
