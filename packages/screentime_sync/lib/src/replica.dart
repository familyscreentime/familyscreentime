/// The family's settings merged from every device's events: the last
/// change wins, field by field, whatever order the events arrive in.
library;

import 'canonical.dart';
import 'event.dart';
import 'hlc.dart';

/// A field's value and when it was written.
class FieldState {
  final Hlc hlc;

  /// `null`: cleared.
  final Object? value;

  const FieldState(this.hlc, this.value);
}

/// What the log says about one entity.
class EntityState {
  /// Last time the whole entity was written (`put`).
  Hlc? created;

  /// Last time it was removed.
  Hlc? deleted;
  final Map<String, FieldState> fields = {};

  /// The last time anything was written to it.
  Hlc? get lastWrite {
    Hlc? last = created;
    for (final f in fields.values) {
      if (last == null || f.hlc > last) last = f.hlc;
    }
    if (deleted != null && (last == null || deleted! > last)) last = deleted;
    return last;
  }

  /// Created, and not removed since.
  bool get exists =>
      created != null && (deleted == null || created! > deleted!);

  /// Its current fields, cleared ones left out.
  Map<String, Object?> get value => {
    for (final e in fields.entries)
      if (e.value.value != null) e.key: e.value.value,
  };

  Map<String, Object?> toJson() => {
    if (created != null) 'c': created!.pack(),
    if (deleted != null) 'x': deleted!.pack(),
    'f': {
      for (final e in fields.entries)
        e.key: [e.value.hlc.pack(), e.value.value],
    },
  };

  static EntityState fromJson(Map<String, Object?> j) {
    final s = EntityState()
      ..created = j['c'] == null ? null : Hlc.parse(j['c'] as String)
      ..deleted = j['x'] == null ? null : Hlc.parse(j['x'] as String);
    for (final e in (j['f'] as Map).entries) {
      final v = e.value as List<Object?>;
      s.fields[e.key as String] = FieldState(Hlc.parse(v[0] as String), v[1]);
    }
    return s;
  }
}

/// Merges [e] into [s] (a `put`, `patch` or `delete`); whether what [s]
/// shows changed. Merging events in any order gives the same result.
bool mergeEvent(EntityState s, SyncEvent e) {
  String? visible() => s.exists ? canonicalJson(s.value) : null;
  void write(String name, Object? value) {
    final old = s.fields[name];
    if (old == null || e.hlc > old.hlc) {
      s.fields[name] = FieldState(e.hlc, value);
    }
  }

  final before = visible();
  switch (e.type) {
    case EventType.put:
      if (s.created == null || e.hlc > s.created!) s.created = e.hlc;
      // A whole entity: fields it leaves out are cleared as of now.
      for (final name in {...s.fields.keys, ...e.data.keys}) {
        write(name, e.data[name]);
      }
    case EventType.patch:
      for (final f in e.data.entries) {
        write(f.key, f.value);
      }
    case EventType.delete:
      if (s.deleted == null || e.hlc > s.deleted!) s.deleted = e.hlc;
    default:
      return false;
  }
  return before != visible();
}

/// Whether [e] is merged into the entities (as opposed to usage and other
/// records passed on as they are).
bool isMerged(SyncEvent e) =>
    e.type == EventType.put ||
    e.type == EventType.patch ||
    e.type == EventType.delete;

/// The family's entities as merged so far: read access, and merging.
abstract class MergedState {
  /// The entity at [key], or `null` when it does not exist.
  Map<String, Object?>? operator [](String key);

  /// Existing entities whose key starts with [prefix], by key.
  Map<String, Map<String, Object?>> withPrefix(String prefix);

  /// Every existing entity, by key.
  Map<String, Map<String, Object?>> get entities => withPrefix('');

  /// Merges [e]; whether anything visible changed.
  bool apply(SyncEvent e);

  /// When the entity at [key] was last written to; `null` if never.
  Hlc? lastWrite(String key);
}

/// Merged entities kept in memory.
class Replica extends MergedState {
  final Map<String, EntityState> _entities = {};

  @override
  bool apply(SyncEvent e) {
    if (!isMerged(e)) return false;
    return mergeEvent(_entities.putIfAbsent(e.key, EntityState.new), e);
  }

  @override
  Map<String, Object?>? operator [](String key) {
    final s = _entities[key];
    return s != null && s.exists ? s.value : null;
  }

  @override
  Hlc? lastWrite(String key) => _entities[key]?.lastWrite;

  @override
  Map<String, Map<String, Object?>> withPrefix(String prefix) => {
    for (final e in _entities.entries)
      if (e.key.startsWith(prefix) && e.value.exists) e.key: e.value.value,
  };

  Map<String, Object?> toJson() => {
    for (final e in _entities.entries) e.key: e.value.toJson(),
  };

  static Replica fromJson(Map<String, Object?> j) {
    final r = Replica();
    for (final e in j.entries) {
      r._entities[e.key] = EntityState.fromJson(
        Map<String, Object?>.from(e.value as Map),
      );
    }
    return r;
  }
}

/// The changes turning [before] into [after] (entities by key): a `put` for
/// a new entity, a `patch` of the fields that changed, a `delete` for one
/// that is gone.
List<EventDraft> diffEntities(
  Map<String, Map<String, Object?>> before,
  Map<String, Map<String, Object?>> after,
) {
  final drafts = <EventDraft>[];
  for (final e in after.entries) {
    final old = before[e.key];
    if (old == null) {
      drafts.add(EventDraft.put(e.key, e.value));
      continue;
    }
    final changed = <String, Object?>{
      for (final name in {...old.keys, ...e.value.keys})
        if (!sameJson(old[name], e.value[name])) name: e.value[name],
    };
    if (changed.isNotEmpty) drafts.add(EventDraft.patch(e.key, changed));
  }
  for (final key in before.keys) {
    if (!after.containsKey(key)) drafts.add(EventDraft.delete(key));
  }
  return drafts;
}
