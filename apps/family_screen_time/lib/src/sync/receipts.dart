/// What each linked device has received: every device says, in the log,
/// how far it holds each other device's settings (`seen/<device>`), so the
/// parent sees which changes reached which device, and when.
library;

import 'package:screentime_sync/screentime_sync.dart';

import 'family_entities.dart';
import 'family_sync.dart';

/// Key of what device [id] has received: by origin, `[seq, ms]`, the last
/// number held and when it came.
String seenKey(String id) => '$seenPrefix$id';
const seenPrefix = 'seen/';

/// Whether [e] counts for the receipts: settings, not receipts themselves
/// (which would answer one another without end).
bool _counts(SyncEvent e) =>
    e.type != EventType.usage && !e.key.startsWith(seenPrefix);

/// Says, in the log, what this device holds now (after events came in).
/// Only what changed since last said; nothing when nothing did.
Future<bool> recordReceipts(FamilySync log, {DateTime? now}) async {
  final node = log.node;
  final me = log.deviceId;
  final said = node.replica[seenKey(me)] ?? const {};
  final held = <String, int>{};
  for (final origin in node.store.vector.keys) {
    if (isUsageOrigin(origin) || deviceOfOrigin(origin) == me) continue;
    if (SyncNode.isSnapshotOrigin(origin)) continue;
    final last = node.store.lastSeq(origin);
    final before = said[origin];
    final saidSeq = before is List && before.isNotEmpty
        ? (before.first as num).toInt()
        : 0;
    if (last <= saidSeq) continue;
    // The last event that counts: receipts that came after it change
    // nothing.
    var seq = 0;
    int? cursor;
    search:
    while (true) {
      final page = node.store.lastEvents(origin, limit: 50, before: cursor);
      if (page.isEmpty) break;
      for (final e in page) {
        if (e.seq <= saidSeq) break search;
        if (_counts(e)) {
          seq = e.seq;
          break search;
        }
      }
      cursor = page.last.seq;
    }
    if (seq > saidSeq) held[origin] = seq;
  }
  if (held.isEmpty) return false;
  final at = (now ?? DateTime.now()).millisecondsSinceEpoch;
  await node.emit([
    said.isEmpty
        ? EventDraft.put(seenKey(me), {
            for (final e in held.entries) e.key: [e.value, at],
          })
        : EventDraft.patch(seenKey(me), {
            for (final e in held.entries) e.key: [e.value, at],
          }),
  ]);
  return true;
}

/// One change made in parent mode: the events recorded together.
class Change {
  /// Where it was made.
  final String origin;
  final DateTime at;
  final List<SyncEvent> events;

  const Change(this.origin, this.at, this.events);

  String get device => deviceOfOrigin(origin);
  int get lastSeq => events.map((e) => e.seq).reduce((a, b) => a > b ? a : b);
}

/// Whether [e] is something the parent changed, or a limit the child set
/// themselves, worth showing.
bool _shown(SyncEvent e) {
  if (!_counts(e)) return false;
  if (e.signer == Signer.device) return e.key.startsWith(FamilyKeys.rule);
  if (e.key == SyncKeys.members || e.key == SyncKeys.epoch) return false;
  if (e.key.startsWith('app/')) return false;
  if (e.key == SyncKeys.family) return e.data.containsKey('vault');
  // Groups given to each child (0.22.1): not the parent's doing.
  if (e.key.startsWith(FamilyKeys.group) &&
      e.type == EventType.patch &&
      e.data.keys.every((k) => k == 'childId')) {
    return false;
  }
  return e.key != FamilyKeys.selfLimitLog;
}

/// The changes made in parent mode in the last [days], newest first.
List<Change> recentChanges(FamilySync log, {int days = 7, int max = 100}) {
  final node = log.node;
  final since = DateTime.now().subtract(Duration(days: days));
  final events = <SyncEvent>[];
  for (final origin in node.store.vector.keys) {
    // Not changes: the settings recorded again, once (0.25).
    if (isUsageOrigin(origin) || SyncNode.isSnapshotOrigin(origin)) continue;
    int? cursor;
    while (true) {
      final page = node.store.lastEvents(origin, limit: 200, before: cursor);
      if (page.isEmpty) break;
      var older = false;
      for (final e in page) {
        if (e.hlc.millis < since.millisecondsSinceEpoch) {
          older = true;
          break;
        }
        if (_shown(e)) events.add(e);
      }
      if (older) break;
      cursor = page.last.seq;
    }
  }
  events.sort((a, b) => b.hlc.compareTo(a.hlc));
  // Events of one origin within a few seconds: one change.
  final changes = <Change>[];
  for (final e in events) {
    final last = changes.isEmpty ? null : changes.last;
    if (last != null &&
        last.origin == e.origin &&
        last.events.last.hlc.millis - e.hlc.millis < 3000) {
      last.events.add(e);
      continue;
    }
    if (changes.length >= max) break;
    changes.add(
      Change(e.origin, DateTime.fromMillisecondsSinceEpoch(e.hlc.millis), [e]),
    );
  }
  return changes;
}

/// When device [id] received [change]; `null` while it has not.
DateTime? receivedBy(FamilySync log, String id, Change change) {
  // This device holds what its log holds.
  if (id == log.deviceId) return change.at;
  final seen = log.node.replica[seenKey(id)]?[change.origin];
  if (seen is! List || seen.length < 2) return null;
  if ((seen[0] as num).toInt() < change.lastSeq) return null;
  return DateTime.fromMillisecondsSinceEpoch((seen[1] as num).toInt());
}

/// The devices [change] is for: those of the child it concerns, and the
/// parents' (every other device when it concerns the whole family, or
/// when that cannot be told).
List<String> targetsOf(FamilySync log, Change change) {
  // From 0.25 its origin says (see Audience).
  if (scopeOfOrigin(change.origin) != null) {
    return [
      for (final e in log.devices.entries)
        if (e.key != change.device &&
            Audience.of(e.value).allowsOrigin(change.origin))
          e.key,
    ];
  }
  final child = childOf(log, change);
  return [
    for (final e in log.devices.entries)
      if (e.key != change.device &&
          (child == null ||
              e.value['childId'] == null ||
              e.value['childId'] == child))
        e.key,
  ];
}

/// The one child [change] concerns, if it concerns only one.
String? childOf(FamilySync log, Change change) {
  String? found;
  for (final e in change.events) {
    final child = e.data['childId'] ?? log.node.replica[e.key]?['childId'];
    if (child is! String) return null;
    if (found != null && found != child) return null;
    found = child;
  }
  return found;
}

/// Devices that have not yet received a change of the last [days].
Map<String, int> pendingByDevice(FamilySync log, {int days = 7}) {
  final pending = <String, int>{};
  for (final c in recentChanges(log, days: days)) {
    for (final id in targetsOf(log, c)) {
      if (receivedBy(log, id, c) == null) {
        pending[id] = (pending[id] ?? 0) + 1;
      }
    }
  }
  return pending;
}
