/// One device's part in the family log: it signs what it records or what
/// the parent decides on it, checks what other devices send, and merges.
library;

import 'dart:async';
import 'dart:isolate';

import 'event.dart';
import 'hlc.dart';
import 'keys.dart';
import 'log.dart';
import 'replica.dart';

/// The family's root of trust, received when a device joins: its id and
/// the parent key's public half.
class FamilyRoot {
  final String familyId;

  /// Ed25519 public key (base64) that parent events must be signed with.
  final String parentKey;

  /// The key (32 bytes, base64) the family's events are encrypted with
  /// for a relay server, which cannot read them. Families made before it
  /// existed have none until a parent sets a server up.
  final String? contentKey;

  const FamilyRoot(this.familyId, this.parentKey, {this.contentKey});

  Map<String, Object?> toJson() => {
    'familyId': familyId,
    'parentKey': parentKey,
    'contentKey': ?contentKey,
  };

  factory FamilyRoot.fromJson(Map<String, Object?> j) => FamilyRoot(
    j['familyId'] as String,
    j['parentKey'] as String,
    contentKey: j['contentKey'] as String?,
  );
}

/// Where events taken in come from when it is another device, directly or
/// through a relay (as opposed to this device's own processes).
abstract interface class RemoteSource {}

/// Keys of the entities the sync layer itself relies on.
abstract final class SyncKeys {
  /// A member device: `signKey` (base64), `name`, `role` (`child` or
  /// `parent`), `childId`, `platform`; `revoked` when removed.
  static String device(String id) => 'device/$id';
  static const devicePrefix = 'device/';

  /// Family-wide sync data: `vault`, the parent key sealed by the code;
  /// `content`, the content key sealed by the code (see
  /// [FamilyRoot.contentKey]), for families that had none.
  static const family = 'sync/family';

  /// The relay server: `url`. Absent: local network only.
  static const server = 'sync/server';

  /// The devices a relay must let in, signed by the parent key (see
  /// `signMembers`): `statement`, `sig`.
  static const members = 'sync/members';

  /// Since when the family's events are cut per child (see [epochKey]).
  static const epoch = epochKey;
}

/// What a device may sign with its own key (anything signed by the parent
/// key is accepted).
abstract class SyncPolicy {
  const SyncPolicy();

  /// Whether [device] (its registration) may sign [e]. [replica] is the
  /// merged state before [e].
  bool deviceMay(SyncEvent e, Map<String, Object?> device, MergedState replica);

  /// The child an entity ([key], with [value]) or a use of apps (key
  /// `usage`) concerns only, or [parentsOnly]; `null` for the whole
  /// family. Its events then go only to the devices concerned (see
  /// [Audience]).
  String? scopeOf(
    String key,
    Map<String, Object?> value,
    MergedState replica,
  ) => null;
}

/// Devices may only sign their own use of apps.
class UsageOnlyPolicy extends SyncPolicy {
  const UsageOnlyPolicy();

  @override
  bool deviceMay(
    SyncEvent e,
    Map<String, Object?> device,
    MergedState replica,
  ) =>
      e.type == EventType.usage &&
      e.data['deviceId'] == deviceOfOrigin(e.origin) &&
      e.data['childId'] == device['childId'];
}

/// Events accepted, from a peer ([source]) or made here (`null`).
class Accepted {
  final List<SyncEvent> events;
  final Object? source;

  /// Whether the merged settings changed.
  final bool replicaChanged;

  const Accepted(this.events, this.source, {required this.replicaChanged});
}

class SyncNode {
  final DeviceIdentity me;
  final FamilyRoot root;
  final SyncStore store;
  final HlcClock clock;
  final SyncPolicy policy;

  final _accepted = StreamController<Accepted>.broadcast(sync: true);

  /// Emits and ingests run one at a time: each checks the next number
  /// expected before adding.
  Future<void> _queue = Future.value();

  Future<T> _serial<T>(Future<T> Function() task) {
    final result = _queue.then((_) => task());
    _queue = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  SyncNode({
    required this.me,
    required this.root,
    SyncStore? store,
    this.policy = const UsageOnlyPolicy(),
  }) : store = store ?? MemorySyncStore(),
       clock = HlcClock(me.deviceId) {
    final latest = this.store.latestHlc;
    if (latest != null) clock.receive(latest);
  }

  String get deviceId => me.deviceId;

  /// The merged entities.
  MergedState get replica => store.merged;

  /// Events accepted, as they are.
  Stream<Accepted> get accepted => _accepted.stream;

  /// The signing key a member device registered, or `null` if it is not a
  /// member.
  String? memberKey(String deviceId) {
    final d = replica[SyncKeys.device(deviceOfOrigin(deviceId))];
    if (d == null || d['revoked'] == true) return null;
    return d['signKey'] as String?;
  }

  /// Records [drafts], signed with the [parentKey] when given (parent
  /// mode), otherwise with this device's key. Use of apps goes under this
  /// device's usage origin.
  Future<List<SyncEvent>> emit(
    List<EventDraft> drafts, {
    SigningKey? parentKey,
    DateTime? now,
  }) => _serial(() => _emit(drafts, parentKey: parentKey, now: now));

  Future<List<SyncEvent>> _emit(
    List<EventDraft> drafts, {
    SigningKey? parentKey,
    DateTime? now,
  }) async {
    // Another process of this device may have added events meanwhile.
    final latest = store.latestHlc;
    if (latest != null) clock.receive(latest, now);
    final made = <SyncEvent>[];
    final next = <String, int>{};
    for (final (d, scope) in _scoped(drafts)) {
      final base = scopedOrigin(deviceId, scope);
      final origin = d.type == EventType.usage ? usageOrigin(base) : base;
      final seq = next[origin] ?? store.lastSeq(origin) + 1;
      next[origin] = seq + 1;
      made.add(
        await signEvent(
          origin: origin,
          seq: seq,
          hlc: clock.now(now),
          draft: d,
          signer: parentKey == null ? Signer.device : Signer.parent,
          key: parentKey ?? me.signing,
        ),
      );
    }
    final changed = store.transaction(() {
      var changed = false;
      for (final e in made) {
        changed = store.add(e) || changed;
      }
      return changed;
    });
    if (made.isNotEmpty) {
      _accepted.add(Accepted(made, null, replicaChanged: changed));
    }
    return made;
  }

  /// [drafts] with the scope each goes under. An entity that changes
  /// scope (moved to another child…) is removed from the old one and put
  /// whole in the new one.
  List<(EventDraft, String?)> _scoped(List<EventDraft> drafts) {
    final out = <(EventDraft, String?)>[];
    String? scope(String key, Map<String, Object?>? value) =>
        value == null ? null : policy.scopeOf(key, value, replica);
    for (final d in drafts) {
      if (d.type != EventType.put &&
          d.type != EventType.patch &&
          d.type != EventType.delete) {
        out.add((d, scope(d.key, d.data)));
        continue;
      }
      final old = replica[d.key];
      final value = switch (d.type) {
        EventType.put => d.data,
        EventType.patch => {
          ...?old,
          ...d.data,
        }..removeWhere((_, v) => v == null),
        _ => old,
      };
      final was = scope(d.key, old);
      if (d.type == EventType.delete) {
        out.add((d, was));
        continue;
      }
      final now = scope(d.key, value);
      if (old != null && was != now) {
        out
          ..add((EventDraft.delete(d.key), was))
          ..add((EventDraft.put(d.key, value!), now));
      } else {
        out.add((d, now));
      }
    }
    return out;
  }

  /// Checks and takes in [events] from [source]; returns those accepted.
  /// Events already held are skipped, as are those after a gap (they come
  /// again once the gap is filled) and those badly signed or not allowed.
  Future<IngestResult> ingest(List<SyncEvent> events, {Object? source}) =>
      _serial(() => _ingest(events, source: source));

  Future<IngestResult> _ingest(List<SyncEvent> events, {Object? source}) async {
    final taken = <SyncEvent>[];
    var gap = false;
    var changed = false;
    // Signatures are checked all at once, away from this isolate: checking
    // hundreds of them would freeze an interface.
    final checked = await _checkSignatures([
      for (final e in events)
        if (store.accepts(e)) e,
    ]);
    var todo = events;
    while (true) {
      final later = <SyncEvent>[];
      final before = taken.length;
      for (final e in todo) {
        if (!store.accepts(e)) {
          if (e.seq > store.lastSeq(e.origin)) later.add(e);
          continue;
        }
        if (!await _authorized(e, checked[e])) continue;
        clock.receive(e.hlc);
        final added = store.transaction(() {
          // Another process may have added it while it was checked.
          if (!store.accepts(e)) return null;
          return store.add(e);
        });
        if (added == null) continue;
        changed = added || changed;
        taken.add(e);
      }
      // What came before what it follows (an event after the snapshot,
      // before the snapshot's record): tried again while it helps.
      if (later.isEmpty || taken.length == before) {
        gap = later.isNotEmpty;
        break;
      }
      todo = later;
    }
    if (taken.isNotEmpty) {
      _accepted.add(Accepted(taken, source, replicaChanged: changed));
    }
    return IngestResult(taken, gap: gap);
  }

  /// Passes on what another process of this device added to the shared
  /// store since it was last asked (it checked them already).
  Future<List<SyncEvent>> readOthers() => _serial(() async {
    final found = store.addedElsewhere();
    if (found.isNotEmpty) {
      for (final e in found) {
        clock.receive(e.hlc);
      }
      _accepted.add(Accepted(found, fromDisk, replicaChanged: true));
    }
    return found;
  });

  /// Source of the events passed on by [readOthers].
  static const fromDisk = 'disk';

  /// The key [e] must be signed with, as things stand; `null` if unknown.
  String? _keyFor(SyncEvent e) => switch (e.signer) {
    Signer.parent => root.parentKey,
    Signer.device => memberKey(deviceOfOrigin(e.origin)),
  };

  /// Checks the signatures of [events] whose key is known now, in another
  /// isolate when there are many: the key each was checked with, if valid.
  Future<Map<SyncEvent, String>> _checkSignatures(
    List<SyncEvent> events,
  ) async {
    final jobs = [
      for (final e in events)
        if (_keyFor(e) case final key?) (e, key),
    ];
    if (jobs.isEmpty) return const {};
    final inputs = [for (final (e, key) in jobs) (e.signedBytes, e.sig, key)];
    final results = inputs.length < 8
        ? await _verifyAll(inputs)
        : await Isolate.run(() => _verifyAll(inputs));
    return {
      for (var i = 0; i < jobs.length; i++)
        if (results[i]) jobs[i].$1: jobs[i].$2,
    };
  }

  static Future<List<bool>> _verifyAll(
    List<(List<int>, String, String)> inputs,
  ) async => [
    for (final (message, sig, key) in inputs)
      await verifySignature(message, sig, key),
  ];

  /// Whether [e] may be taken in. [checkedWith]: the key its signature was
  /// found valid with, if it was checked beforehand.
  Future<bool> _authorized(SyncEvent e, [String? checkedWith]) async {
    // Use of apps only under usage origins, and only there.
    if ((e.type == EventType.usage) != isUsageOrigin(e.origin)) return false;
    final key = _keyFor(e);
    if (key == null) return false;
    // Checked beforehand with the same key, or now (a device registered
    // earlier in the same batch).
    if (checkedWith != key && !await verifyEvent(e, key)) return false;
    if (e.signer == Signer.parent) return true;
    final device = replica[SyncKeys.device(deviceOfOrigin(e.origin))];
    if (device == null) return false;
    return policy.deviceMay(e, device, replica);
  }

  /// This device's audience: what it receives of the family's events.
  Audience get audience =>
      Audience.of(replica[SyncKeys.device(deviceOfOrigin(deviceId))]);

  /// Cuts the family's events per child, once, for a family linked before
  /// 0.25, from a parent's device (which holds everything): its settings
  /// are recorded again, each under the scope it concerns, signed by the
  /// [parentKey] (a snapshot); then what came before is dropped everywhere
  /// ([SyncKeys.epoch]). Whether it was done now.
  ///
  /// The snapshot keeps each entity's date, under origins of its own: it
  /// never wins over a change this device has not received yet.
  Future<bool> rebase(SigningKey parentKey) => _serial(() async {
    if (replica[SyncKeys.epoch] != null || !audience.all) return false;
    final floors = {
      for (final e in store.heldVector.entries)
        if (!isUsageOrigin(e.key) && scopeOfOrigin(e.key) == null)
          e.key: e.value,
    };
    final tag = [
      for (final b in randomBytes(3)) b.toRadixString(16).padLeft(2, '0'),
    ].join();
    final base = '${deviceOfOrigin(deviceId)}~snap$tag';
    final entities = [
      for (final e in replica.entities.entries)
        if (e.key != SyncKeys.epoch)
          (e.key, e.value, replica.lastWrite(e.key) ?? clock.now()),
    ]..sort((a, b) => a.$3.compareTo(b.$3));
    final made = <SyncEvent>[];
    final next = <String, int>{};
    for (final (key, value, hlc) in entities) {
      final origin = scopedOrigin(base, policy.scopeOf(key, value, replica));
      final seq = next[origin] = (next[origin] ?? 0) + 1;
      made.add(
        await signEvent(
          origin: origin,
          seq: seq,
          hlc: hlc,
          draft: EventDraft.put(key, value),
          signer: Signer.parent,
          key: parentKey,
        ),
      );
    }
    final changed = store.transaction(() {
      var changed = false;
      for (final e in made) {
        changed = store.add(e) || changed;
      }
      return changed;
    });
    if (made.isNotEmpty) {
      _accepted.add(Accepted(made, null, replicaChanged: changed));
    }
    await _emit([
      EventDraft.put(SyncKeys.epoch, {
        'id': tag,
        'floors': floors,
        'snapshot': next,
      }),
    ], parentKey: parentKey);
    return true;
  });

  /// Whether [origin] holds a snapshot ([rebase]).
  static bool isSnapshotOrigin(String origin) => origin.contains('~snap');

  /// Records that this new family's events are cut per child from the
  /// start: nothing to replace.
  Future<void> startScoped(SigningKey parentKey) => emit([
    EventDraft.put(SyncKeys.epoch, {
      'id': b64(randomBytes(9)),
      'floors': const <String, int>{},
      'snapshot': const <String, int>{},
    }),
  ], parentKey: parentKey);

  /// The note of the last [tidy] this node saw.
  String? _tidied;

  /// Removes from this device what it needs no more: what the snapshot
  /// replaced (once it holds the snapshot), and what concerns other
  /// children (on a child's device). Whether this device's data changed
  /// since this node last asked (another process may have done it).
  Future<bool> tidy() => _serial(() async {
    final me = deviceOfOrigin(deviceId);
    final registration = replica[SyncKeys.device(me)];
    // Not a member yet (joining): nothing to tell.
    if (registration == null) return false;
    final audience = Audience.of(registration);
    final epoch = replica[SyncKeys.epoch];
    final note = '${audience.key}|${epoch?['id'] ?? ''}';
    final done = store.meta('tidy');
    var purgedNow = false;
    if (done != note && epoch == null && audience.all) {
      // Everything kept: nothing to remove.
      store.setMeta('tidy', note);
    } else if (done != note) {
      if (epoch != null && !_holdsSnapshot(epoch, audience)) return false;
      store.transaction(() {
        store.purge(audience, ownDevice: me);
        store.setMeta('tidy', note);
      });
      purgedNow = true;
    }
    final before = _tidied;
    _tidied = note;
    // Or done by another process since this node last looked.
    return purgedNow || (before != null && before != note);
  });

  bool _holdsSnapshot(Map<String, Object?> epoch, Audience audience) {
    for (final e in (epoch['snapshot'] as Map? ?? const {}).entries) {
      final origin = e.key as String;
      if (!audience.allowsOrigin(origin)) continue;
      if (store.lastSeq(origin) < (e.value as num).toInt()) return false;
    }
    return true;
  }

  Future<void> close() async {
    await _accepted.close();
    store.close();
  }
}

class IngestResult {
  final List<SyncEvent> accepted;

  /// Some events came after a gap: ask again for what is missing.
  final bool gap;

  const IngestResult(this.accepted, {required this.gap});
}

/// A new family, created on its first device.
class NewFamily {
  final FamilyRoot root;
  final DeviceIdentity device;
  final SigningKey parentKey;
  final SyncNode node;

  const NewFamily(this.root, this.device, this.parentKey, this.node);
}

/// Creates a family on its first device: a family id, the parent key
/// (sealed by [parentCode] in the log, so any device can unlock it), and
/// this device's registration.
Future<NewFamily> createFamily({
  required String familyId,
  required DeviceIdentity device,
  required String parentCode,
  required Map<String, Object?> deviceInfo,
  SyncStore? store,
  SyncPolicy policy = const UsageOnlyPolicy(),
}) async {
  final parentKey = await SigningKey.generate();
  final root = FamilyRoot(
    familyId,
    parentKey.publicKey,
    contentKey: b64(randomBytes(32)),
  );
  final node = SyncNode(me: device, root: root, store: store, policy: policy);
  await node.emit([
    EventDraft.put(SyncKeys.family, {
      'vault': await ParentVault.seal(parentKey.seed, parentCode),
    }),
    EventDraft.put(SyncKeys.device(deviceOfOrigin(device.deviceId)), {
      ...deviceInfo,
      'signKey': device.signing.publicKey,
    }),
  ], parentKey: parentKey);
  return NewFamily(root, device, parentKey, node);
}

/// The parent key, unlocked with [code] from the vault in the log; `null`
/// when the code is wrong or there is no vault.
Future<SigningKey?> unlockParentKey(SyncNode node, String code) async {
  final vault = node.replica[SyncKeys.family]?['vault'];
  if (vault is! Map) return null;
  final key = await ParentVault.open(Map<String, Object?>.from(vault), code);
  if (key == null || key.publicKey != node.root.parentKey) return null;
  return key;
}

/// Seals the parent key with a new code, for every device.
Future<void> changeParentCode(
  SyncNode node,
  SigningKey parentKey,
  String newCode,
) async {
  final vault = await ParentVault.seal(parentKey.seed, newCode);
  await node.emit([
    EventDraft.patch(SyncKeys.family, {'vault': vault}),
  ], parentKey: parentKey);
}
