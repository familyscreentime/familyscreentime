/// One-off actions: bonuses, blocks, day unlocks, family blocks.
library;

import 'calendar.dart';
import 'targets.dart';

/// Extra time granted to a child.
///
/// It targets either one rule ([ruleId]: the UI default, which offers the
/// limit currently blocking), or every rule of the child with exactly the
/// same app target ([appTarget]).
class Bonus {
  final String id;
  final String childId;
  final String? ruleId;
  final AppTarget? appTarget;
  final Duration amount;
  final DateTime grantedAt;

  /// End of validity, usually midnight of the day it was granted.
  final DateTime validUntil;

  const Bonus.forRule({
    required this.id,
    required this.childId,
    required String this.ruleId,
    required this.amount,
    required this.grantedAt,
    required this.validUntil,
  }) : appTarget = null;

  const Bonus.forTarget({
    required this.id,
    required this.childId,
    required AppTarget this.appTarget,
    required this.amount,
    required this.grantedAt,
    required this.validUntil,
  }) : ruleId = null;

  bool isValidAt(DateTime t) => t.isBefore(validUntil);
}

/// Temporary block of a target, a device, a device group or the whole child,
/// until [until] (`null`: until explicitly lifted, which produces a new
/// version with [until] set).
///
/// A [voluntary] block is a break the child chose to take: it blocks the
/// same way, and only the wording differs.
class TemporaryBlock {
  final String id;
  final String childId;
  final AppTarget appTarget;
  final DeviceTarget deviceTarget;
  final DateTime from;
  final DateTime? until;
  final bool voluntary;

  const TemporaryBlock({
    required this.id,
    required this.childId,
    this.appTarget = const AppTarget.all(),
    this.deviceTarget = const DeviceTarget.all(),
    required this.from,
    this.until,
    this.voluntary = false,
  });

  /// The same block, ending at [end].
  TemporaryBlock endingAt(DateTime end) => TemporaryBlock(
    id: id,
    childId: childId,
    appTarget: appTarget,
    deviceTarget: deviceTarget,
    from: from,
    until: end,
    voluntary: voluntary,
  );

  bool isActiveAt(DateTime t) =>
      !t.isBefore(from) && (until == null || t.isBefore(until!));
}

/// Restrictions (schedules, quotas, breaks) lifted until midnight.
/// Usage is still recorded but produces no overrun.
class DayUnlock {
  final String id;
  final String childId;
  final DateTime day;

  DayUnlock({required this.id, required this.childId, required DateTime day})
    : day = dayOf(day);

  bool coversDay(DateTime t) => sameDay(day, t);
}

/// A rule's hours opened early by the parent, from [from] to [until]: the
/// rule's schedule does not apply meanwhile (its time limits still do).
class HoursUnlock {
  final String id;
  final String childId;
  final String ruleId;
  final DateTime from;
  final DateTime until;

  const HoursUnlock({
    required this.id,
    required this.childId,
    required this.ruleId,
    required this.from,
    required this.until,
  });

  bool isActiveAt(DateTime t) => !t.isBefore(from) && t.isBefore(until);
}

/// Block of every device of every child.
class FamilyBlock {
  final String id;
  final DateTime from;
  final DateTime? until;

  const FamilyBlock({required this.id, required this.from, this.until});

  bool isActiveAt(DateTime t) =>
      !t.isBefore(from) && (until == null || t.isBefore(until!));
}
