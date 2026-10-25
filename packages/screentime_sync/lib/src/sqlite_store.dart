/// The family log in SQLite: events numbered per device of origin, the
/// merged entities, and the use of apps kept a few weeks. Several
/// processes of a device (the interface and its background service) may
/// open the same file at once.
library;

import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

import 'canonical.dart';
import 'event.dart';
import 'hlc.dart';
import 'log.dart';
import 'replica.dart';

const _schema = '''
CREATE TABLE IF NOT EXISTS events (
  n INTEGER PRIMARY KEY AUTOINCREMENT,
  origin TEXT NOT NULL,
  seq INTEGER NOT NULL,
  hlc TEXT NOT NULL,
  usage_end INTEGER,
  body TEXT NOT NULL,
  UNIQUE (origin, seq)
);
CREATE INDEX IF NOT EXISTS events_hlc ON events (hlc);
CREATE INDEX IF NOT EXISTS events_usage ON events (usage_end)
  WHERE usage_end IS NOT NULL;
CREATE TABLE IF NOT EXISTS heads (
  origin TEXT PRIMARY KEY,
  last INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS entities (
  key TEXT PRIMARY KEY,
  state TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS meta (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
''';

class SqliteSyncStore extends SyncStore {
  final Database db;
  late final _SqliteMerged _merged = _SqliteMerged(db);

  /// Last row this connection saw, for [addedElsewhere].
  int _seen;

  /// Rows this connection added since [addedElsewhere] was last called.
  final _own = <int>{};

  SqliteSyncStore._(this.db) : _seen = 0 {
    _seen =
        db.select('SELECT coalesce(max(n), 0) AS n FROM events').first['n']
            as int;
  }

  /// Opens (or creates) the store at [path].
  factory SqliteSyncStore.open(String path) {
    final db = sqlite3.open(path);
    db.execute('PRAGMA journal_mode = WAL');
    db.execute('PRAGMA busy_timeout = 10000');
    db.execute('PRAGMA synchronous = NORMAL');
    db.execute(_schema);
    return SqliteSyncStore._(db);
  }

  /// A store in memory, for tests.
  factory SqliteSyncStore.inMemory() {
    final db = sqlite3.openInMemory();
    db.execute(_schema);
    return SqliteSyncStore._(db);
  }

  @override
  MergedState get merged => _merged;

  @override
  Vector get heldVector => {
    for (final r in db.select('SELECT origin, last FROM heads'))
      r['origin'] as String: r['last'] as int,
  };

  @override
  int heldSeq(String origin) {
    final rows = db.select('SELECT last FROM heads WHERE origin = ?', [origin]);
    return rows.isEmpty ? 0 : rows.first['last'] as int;
  }

  @override
  Hlc? get latestHlc {
    final v = db.select('SELECT max(hlc) AS h FROM events').first['h'];
    return v == null ? null : Hlc.parse(v as String);
  }

  @override
  T transaction<T>(T Function() body) {
    if (db.autocommit) {
      db.execute('BEGIN IMMEDIATE');
      try {
        final result = body();
        db.execute('COMMIT');
        return result;
      } on Object {
        db.execute('ROLLBACK');
        rethrow;
      }
    }
    return body();
  }

  @override
  bool add(SyncEvent e) => transaction(() {
    // Checked again inside the transaction: another process may have
    // added it meanwhile.
    if (!accepts(e)) {
      throw StateError(
        'Event ${e.id} out of order (have ${lastSeq(e.origin)})',
      );
    }
    db.execute(
      'INSERT INTO events (origin, seq, hlc, usage_end, body) VALUES (?, ?, ?, ?, ?)',
      [
        e.origin,
        e.seq,
        e.hlc.pack(),
        e.type == EventType.usage
            ? (e.data['end'] as num?)?.toInt() ?? 0
            : null,
        jsonEncode(e.toJson()),
      ],
    );
    _own.add(db.lastInsertRowId);
    db.execute(
      'INSERT INTO heads (origin, last) VALUES (?, ?) '
      'ON CONFLICT (origin) DO UPDATE SET last = excluded.last',
      [e.origin, e.seq],
    );
    final changed = _merged.apply(e);
    if (e.key == epochKey) forgetFloors();
    return changed;
  });

  static SyncEvent _event(Row r) => SyncEvent.fromJson(
    jsonDecode(r['body'] as String) as Map<String, Object?>,
  );

  @override
  List<SyncEvent> missingFor(
    Vector peer, {
    Hlc? after,
    int limit = defaultPage,
    Audience to = Audience.everything,
  }) {
    // Per origin held and received there: what comes after the peer's
    // last (and after what the snapshot replaced).
    final conditions = <String>[];
    final args = <Object?>[];
    for (final o in heldVector.keys) {
      if (!to.allowsOrigin(o)) continue;
      final from = fromFor(peer, o);
      if (!to.all && isUsageOrigin(o) && scopeOfOrigin(o) == null) {
        // Use recorded before 0.25: only the child's.
        conditions.add(
          "(origin = ? AND seq > ? AND json_extract(body, '\$.d.childId') = ?)",
        );
        args.addAll([o, from, to.child]);
      } else {
        conditions.add('(origin = ? AND seq > ?)');
        args.addAll([o, from]);
      }
    }
    if (conditions.isEmpty) return const [];
    final rows = db.select(
      'SELECT body FROM events WHERE (${conditions.join(' OR ')})'
      '${after == null ? '' : ' AND hlc > ?'} ORDER BY hlc LIMIT ?',
      [...args, if (after != null) after.pack(), limit],
    );
    return [for (final r in rows) _event(r)];
  }

  @override
  List<SyncEvent> lastEvents(String origin, {int limit = 100, int? before}) {
    final rows = db.select(
      'SELECT body FROM events WHERE origin = ?'
      '${before == null ? '' : ' AND seq < ?'} ORDER BY seq DESC LIMIT ?',
      [origin, ?before, limit],
    );
    return [for (final r in rows) _event(r)];
  }

  @override
  List<SyncEvent> addedElsewhere() {
    final rows = db.select(
      'SELECT n, body FROM events WHERE n > ? ORDER BY n',
      [_seen],
    );
    final found = <SyncEvent>[];
    for (final r in rows) {
      final n = r['n'] as int;
      if (n > _seen) _seen = n;
      if (!_own.remove(n)) found.add(_event(r));
    }
    _own.clear();
    if (found.any((e) => e.key == epochKey)) forgetFloors();
    return found;
  }

  @override
  int prune(DateTime before) {
    db.execute(
      'DELETE FROM events WHERE usage_end IS NOT NULL AND usage_end < ?',
      [before.millisecondsSinceEpoch],
    );
    return db.updatedRows;
  }

  @override
  void purge(Audience keep, {required String ownDevice}) => transaction(() {
    final floors = this.floors;
    for (final o in heldVector.keys) {
      final scope = scopeOfOrigin(o);
      if (!isUsageOrigin(o) && scope == null) {
        final floor = floors[o] ?? 0;
        if (floor > 0) {
          db.execute('DELETE FROM events WHERE origin = ? AND seq <= ?', [
            o,
            floor,
          ]);
        }
      } else if (scope != null && deviceOfOrigin(o) == ownDevice) {
        continue;
      } else if (!keep.allowsOrigin(o)) {
        db.execute('DELETE FROM events WHERE origin = ?', [o]);
        db.execute('DELETE FROM heads WHERE origin = ?', [o]);
      } else if (!keep.all && scope == null) {
        // Use recorded before 0.25: only the child's is kept.
        db.execute(
          "DELETE FROM events WHERE origin = ? AND "
          "json_extract(body, '\$.d.childId') IS NOT ?",
          [o, keep.child],
        );
      }
    }
    // Merged again from what is left.
    db.execute('DELETE FROM entities');
    final rows = db.select(
      'SELECT body FROM events WHERE usage_end IS NULL ORDER BY hlc',
    );
    for (final r in rows) {
      _merged.apply(_event(r));
    }
    forgetFloors();
  });

  @override
  String? meta(String key) {
    final rows = db.select('SELECT value FROM meta WHERE key = ?', [key]);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  @override
  void setMeta(String key, String value) => db.execute(
    'INSERT INTO meta (key, value) VALUES (?, ?) '
    'ON CONFLICT (key) DO UPDATE SET value = excluded.value',
    [key, value],
  );

  @override
  void close() => db.close();
}

class _SqliteMerged extends MergedState {
  final Database db;

  _SqliteMerged(this.db);

  EntityState? _state(String key) {
    final rows = db.select('SELECT state FROM entities WHERE key = ?', [key]);
    if (rows.isEmpty) return null;
    return EntityState.fromJson(
      jsonDecode(rows.first['state'] as String) as Map<String, Object?>,
    );
  }

  @override
  bool apply(SyncEvent e) {
    if (!isMerged(e)) return false;
    final s = _state(e.key) ?? EntityState();
    final before = canonicalJson(s.toJson());
    final changed = mergeEvent(s, e);
    final after = canonicalJson(s.toJson());
    if (after != before) {
      db.execute(
        'INSERT INTO entities (key, state) VALUES (?, ?) '
        'ON CONFLICT (key) DO UPDATE SET state = excluded.state',
        [e.key, after],
      );
    }
    return changed;
  }

  @override
  Hlc? lastWrite(String key) => _state(key)?.lastWrite;

  @override
  Map<String, Object?>? operator [](String key) {
    final s = _state(key);
    return s != null && s.exists ? s.value : null;
  }

  @override
  Map<String, Map<String, Object?>> withPrefix(String prefix) {
    final rows = db.select(
      "SELECT key, state FROM entities WHERE substr(key, 1, ?) = ? ORDER BY key",
      [prefix.length, prefix],
    );
    return {
      for (final r in rows)
        if (EntityState.fromJson(
              jsonDecode(r['state'] as String) as Map<String, Object?>,
            )
            case final s when s.exists)
          r['key'] as String: s.value,
    };
  }
}
