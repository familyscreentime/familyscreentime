/// Where a device keeps the family log and its merged entities: in memory
/// (tests, a device joining), or in SQLite (see `SqliteSyncStore`).
library;

import 'event.dart';
import 'hlc.dart';
import 'replica.dart';

/// What a device has: for each device of origin, the number of its last
/// event held.
typedef Vector = Map<String, int>;

// --- Origins ----------------------------------------------------------------
//
// A device records events under several origins, each numbered on its own:
// `<device>` for its background service, `<device>~ui` for its interface;
// then `@` and the child its events concern, if only one (see [Audience]),
// or nothing for the whole family; `#usage` for the use of apps. Origins
// without `@` are from before 0.25, when everything went everywhere.

/// The device behind an origin, all of whose origins are signed with the
/// device's key.
String deviceOfOrigin(String origin) {
  final i = origin.indexOf(RegExp('[~#@]'));
  return i < 0 ? origin : origin.substring(0, i);
}

/// Origin of [device]'s events (`<device>` or `<device>~ui`) that concern
/// only child [scope] (or only the parents, [parentsOnly]), or the whole
/// family (`null`).
String scopedOrigin(String device, String? scope) => '$device@${scope ?? ''}';

/// The child [origin]'s events concern, or [parentsOnly]; empty for the
/// whole family; `null` for an origin from before 0.25, which mixes
/// everything.
String? scopeOfOrigin(String origin) {
  final at = origin.indexOf('@');
  if (at < 0) return null;
  final hash = origin.indexOf('#', at);
  return origin.substring(at + 1, hash < 0 ? origin.length : hash);
}

/// Scope of what only the parents' devices receive (a device's receipts…).
const parentsOnly = '_parents';

/// Origin of the use of apps recorded under [origin]: kept apart, because
/// use is only kept a few weeks.
String usageOrigin(String origin) => '$origin#usage';

/// Whether [origin] numbers use of apps ([usageOrigin]). Their old events
/// are removed after a while, so gaps are allowed there; every other
/// origin is kept whole and numbered without gaps.
bool isUsageOrigin(String origin) => origin.endsWith('#usage');

/// Key of the entity saying since when the family's events are cut per
/// child (see `SyncNode.rebase`): `id`; `floors`, by origin from before,
/// the last number replaced by the snapshot (those events are dropped);
/// `snapshot`, by origin, the last number of the snapshot.
const epochKey = 'sync/epoch';

/// Which of the family's events a device receives: all of them (a
/// parent's device), or the family's and one child's ([child]; none while
/// the device belongs to no child yet).
class Audience {
  final bool all;
  final String? child;

  /// Whether it understands origins cut per child (devices before 0.25
  /// refuse them).
  final bool scoped;

  const Audience.all({this.scoped = true}) : all = true, child = null;
  const Audience.child(this.child, {this.scoped = true}) : all = false;

  static const everything = Audience.all();
  static const familyOnly = Audience.child(null);

  /// The audience of a device, from its registration (`role`, `childId`).
  factory Audience.of(Map<String, Object?>? device, {bool scoped = true}) {
    if (device == null) return Audience.child(null, scoped: scoped);
    if (device['role'] == 'parent') return Audience.all(scoped: scoped);
    final child = device['childId'];
    return Audience.child(child is String ? child : null, scoped: scoped);
  }

  /// Short form: `*` for all, the child's id, or empty.
  String get key => all ? '*' : child ?? '';

  /// Whether [origin]'s events may go there (use of apps recorded before
  /// 0.25 is told event by event, see [allows]).
  bool allowsOrigin(String origin) {
    final scope = scopeOfOrigin(origin);
    if (scope == null) return all || !isUsageOrigin(origin) || child != null;
    if (!scoped) return false;
    return all || scope.isEmpty || scope == child;
  }

  /// Whether [e] may go there.
  bool allows(SyncEvent e) {
    if (!allowsOrigin(e.origin)) return false;
    if (all || scopeOfOrigin(e.origin) != null) return true;
    return !isUsageOrigin(e.origin) || e.data['childId'] == child;
  }

  @override
  bool operator ==(Object other) =>
      other is Audience &&
      other.key == key &&
      other.all == all &&
      other.scoped == scoped;

  @override
  int get hashCode => Object.hash(key, all, scoped);

  @override
  String toString() => 'Audience($key)';
}

/// Events sent at most per page.
const defaultPage = 500;

abstract class SyncStore {
  /// The last event number held for each device of origin, as stored.
  Vector get heldVector;

  /// Number of the last event stored from [origin]; 0 for none.
  int heldSeq(String origin);

  /// For each origin, the last number this device has what it needs of:
  /// what it holds, or what the snapshot replaced ([floors]).
  Vector get vector {
    final v = heldVector;
    for (final f in floors.entries) {
      if (f.value > (v[f.key] ?? 0)) v[f.key] = f.value;
    }
    return v;
  }

  /// Number of the last event from [origin] this device needs no more
  /// before the next.
  int lastSeq(String origin) {
    final held = heldSeq(origin);
    final floor = floors[origin] ?? 0;
    return floor > held ? floor : held;
  }

  Map<String, int>? _floors;

  /// By origin, the last number replaced by the family's snapshot (see
  /// [epochKey]).
  Map<String, int> get floors => _floors ??= {
    for (final e in (merged[epochKey]?['floors'] as Map? ?? const {}).entries)
      e.key as String: (e.value as num).toInt(),
  };

  /// To call when the snapshot may have changed.
  void forgetFloors() => _floors = null;

  /// Whether [e] can be added: the next one of its origin (or, for use of
  /// apps, any later one).
  bool accepts(SyncEvent e) => isUsageOrigin(e.origin)
      ? e.seq > lastSeq(e.origin)
      : e.seq == lastSeq(e.origin) + 1;

  /// The latest clock of the events held.
  Hlc? get latestHlc;

  /// The merged entities.
  MergedState get merged;

  /// Adds [e] and merges it, together; whether the merged entities changed.
  /// [e] must be [accepts]ed.
  bool add(SyncEvent e);

  /// Events a device with [peer] lacks, among those [to] receives, oldest
  /// first by clock (a device's registration then comes before what that
  /// device signed): at most [limit], those after [after]. What the
  /// snapshot replaced is left out.
  List<SyncEvent> missingFor(
    Vector peer, {
    Hlc? after,
    int limit = defaultPage,
    Audience to = Audience.everything,
  });

  /// Every event a device with [peer] lacks, page by page.
  Iterable<List<SyncEvent>> pagesFor(
    Vector peer, {
    int page = defaultPage,
    Audience to = Audience.everything,
  }) sync* {
    Hlc? after;
    while (true) {
      final events = missingFor(peer, after: after, limit: page, to: to);
      if (events.isEmpty) return;
      yield events;
      if (events.length < page) return;
      after = events.last.hlc;
    }
  }

  /// The number after which [peer] lacks [origin]'s events.
  int fromFor(Vector peer, String origin) {
    final have = peer[origin] ?? 0;
    final floor = floors[origin] ?? 0;
    return floor > have ? floor : have;
  }

  /// Events added by another process sharing the store since last asked;
  /// none for a store of its own.
  List<SyncEvent> addedElsewhere() => const [];

  /// Removes the use of apps that ended before [before]; how many events.
  int prune(DateTime before);

  /// Removes what this device needs no more: what the snapshot replaced,
  /// and what [keep] does not receive (but what [ownDevice] recorded), then
  /// merges again what is left.
  void purge(Audience keep, {required String ownDevice});

  /// A note kept with the log ([setMeta]).
  String? meta(String key);

  void setMeta(String key, String value);

  /// [origin]'s last events, newest first: at most [limit], those before
  /// number [before] when given.
  List<SyncEvent> lastEvents(String origin, {int limit = 100, int? before});

  /// Runs [body] as one transaction.
  T transaction<T>(T Function() body) => body();

  void close() {}
}

/// Whether [e] (from [origin]) is to be dropped by a purge for [keep].
bool droppedByPurge(
  SyncEvent e,
  Audience keep,
  String ownDevice,
  Map<String, int> floors,
) {
  final o = e.origin;
  if (!isUsageOrigin(o) && scopeOfOrigin(o) == null) {
    return e.seq <= (floors[o] ?? 0);
  }
  if (deviceOfOrigin(o) == ownDevice && scopeOfOrigin(o) != null) return false;
  return !keep.allows(e);
}

/// A store in memory.
class MemorySyncStore extends SyncStore {
  final Map<String, List<SyncEvent>> _byOrigin = {};
  final Map<String, int> _last = {};
  final Map<String, String> _meta = {};
  Replica replica = Replica();

  @override
  MergedState get merged => replica;

  @override
  Vector get heldVector => {..._last};

  @override
  int heldSeq(String origin) => _last[origin] ?? 0;

  @override
  Hlc? get latestHlc {
    Hlc? latest;
    for (final l in _byOrigin.values) {
      for (final e in l) {
        if (latest == null || e.hlc > latest) latest = e.hlc;
      }
    }
    return latest;
  }

  @override
  bool add(SyncEvent e) {
    if (!accepts(e)) {
      throw StateError(
        'Event ${e.id} out of order (have ${lastSeq(e.origin)})',
      );
    }
    _byOrigin.putIfAbsent(e.origin, () => []).add(e);
    _last[e.origin] = e.seq;
    final changed = replica.apply(e);
    if (e.key == epochKey) forgetFloors();
    return changed;
  }

  @override
  List<SyncEvent> missingFor(
    Vector peer, {
    Hlc? after,
    int limit = defaultPage,
    Audience to = Audience.everything,
  }) {
    final missing = [
      for (final e in _byOrigin.entries)
        if (to.allowsOrigin(e.key))
          for (final ev in e.value)
            if (ev.seq > fromFor(peer, e.key) &&
                (after == null || ev.hlc > after) &&
                to.allows(ev))
              ev,
    ]..sort((a, b) => a.hlc.compareTo(b.hlc));
    return missing.take(limit).toList();
  }

  @override
  List<SyncEvent> lastEvents(String origin, {int limit = 100, int? before}) => [
    for (final e in (_byOrigin[origin] ?? const <SyncEvent>[]).reversed)
      if (before == null || e.seq < before) e,
  ].take(limit).toList();

  @override
  int prune(DateTime before) {
    var removed = 0;
    for (final l in _byOrigin.values) {
      final n = l.length;
      l.removeWhere(
        (e) =>
            e.type == EventType.usage &&
            (e.data['end'] as num? ?? 0) < before.millisecondsSinceEpoch,
      );
      removed += n - l.length;
    }
    return removed;
  }

  @override
  void purge(Audience keep, {required String ownDevice}) {
    final floors = this.floors;
    for (final origin in _byOrigin.keys.toList()) {
      final l = _byOrigin[origin]!
        ..removeWhere((e) => droppedByPurge(e, keep, ownDevice, floors));
      if (l.isEmpty &&
          !isUsageOrigin(origin) &&
          scopeOfOrigin(origin) != null) {
        _byOrigin.remove(origin);
        _last.remove(origin);
      }
    }
    replica = Replica();
    final all = [for (final l in _byOrigin.values) ...l]
      ..sort((a, b) => a.hlc.compareTo(b.hlc));
    for (final e in all) {
      replica.apply(e);
    }
    forgetFloors();
  }

  @override
  String? meta(String key) => _meta[key];

  @override
  void setMeta(String key, String value) => _meta[key] = value;
}
