/// Where a device keeps the family log and its merged entities: in memory
/// (tests, a device joining), or in SQLite (see `SqliteSyncStore`).
library;

import 'event.dart';
import 'hlc.dart';
import 'replica.dart';

/// What a device has: for each device of origin, the number of its last
/// event held.
typedef Vector = Map<String, int>;

/// Origin of the use of apps recorded under [origin]: kept apart, because
/// use is only kept a few weeks.
String usageOrigin(String origin) => '$origin#usage';

/// Whether [origin] numbers use of apps ([usageOrigin]). Their old events
/// are removed after a while, so gaps are allowed there; every other
/// origin is kept whole and numbered without gaps.
bool isUsageOrigin(String origin) => origin.endsWith('#usage');

/// Events sent at most per page.
const defaultPage = 500;

abstract class SyncStore {
  /// The last event number held for each device of origin.
  Vector get vector;

  /// Number of the last event held from [origin]; 0 for none.
  int lastSeq(String origin);

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

  /// Events a device with [peer] lacks, oldest first by clock (a device's
  /// registration then comes before what that device signed): at most
  /// [limit], those after [after].
  List<SyncEvent> missingFor(
    Vector peer, {
    Hlc? after,
    int limit = defaultPage,
  });

  /// Every event a device with [peer] lacks, page by page.
  Iterable<List<SyncEvent>> pagesFor(
    Vector peer, {
    int page = defaultPage,
  }) sync* {
    Hlc? after;
    while (true) {
      final events = missingFor(peer, after: after, limit: page);
      if (events.isEmpty) return;
      yield events;
      if (events.length < page) return;
      after = events.last.hlc;
    }
  }

  /// Events added by another process sharing the store since last asked;
  /// none for a store of its own.
  List<SyncEvent> addedElsewhere() => const [];

  /// Removes the use of apps that ended before [before]; how many events.
  int prune(DateTime before);

  /// Runs [body] as one transaction.
  T transaction<T>(T Function() body) => body();

  void close() {}
}

/// A store in memory.
class MemorySyncStore extends SyncStore {
  final Map<String, List<SyncEvent>> _byOrigin = {};
  final Map<String, int> _last = {};
  final Replica replica = Replica();

  @override
  MergedState get merged => replica;

  @override
  Vector get vector => {..._last};

  @override
  int lastSeq(String origin) => _last[origin] ?? 0;

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
    return replica.apply(e);
  }

  @override
  List<SyncEvent> missingFor(
    Vector peer, {
    Hlc? after,
    int limit = defaultPage,
  }) {
    final missing = [
      for (final e in _byOrigin.entries)
        for (final ev in e.value)
          if (ev.seq > (peer[e.key] ?? 0) && (after == null || ev.hlc > after))
            ev,
    ]..sort((a, b) => a.hlc.compareTo(b.hlc));
    return missing.take(limit).toList();
  }

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
}
