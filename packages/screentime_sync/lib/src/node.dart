/// One device's part in the family log: it signs what it records or what
/// the parent decides on it, checks what other devices send, and merges.
library;

import 'dart:async';

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

  const FamilyRoot(this.familyId, this.parentKey);

  Map<String, Object?> toJson() => {
    'familyId': familyId,
    'parentKey': parentKey,
  };

  factory FamilyRoot.fromJson(Map<String, Object?> j) =>
      FamilyRoot(j['familyId'] as String, j['parentKey'] as String);
}

/// The device behind an origin: a device may record events under several
/// origins (`<device>~ui` for its interface, `<device>` for its background
/// service), each numbered on its own, all signed with the device's key.
String deviceOfOrigin(String origin) {
  final i = origin.indexOf(RegExp('[~#]'));
  return i < 0 ? origin : origin.substring(0, i);
}

/// Keys of the entities the sync layer itself relies on.
abstract final class SyncKeys {
  /// A member device: `signKey` (base64), `name`, `role` (`child` or
  /// `parent`), `childId`, `platform`; `revoked` when removed.
  static String device(String id) => 'device/$id';
  static const devicePrefix = 'device/';

  /// Family-wide sync data: `vault`, the parent key sealed by the code.
  static const family = 'sync/family';
}

/// What a device may sign with its own key (anything signed by the parent
/// key is accepted).
abstract class SyncPolicy {
  const SyncPolicy();

  /// Whether [device] (its registration) may sign [e]. [replica] is the
  /// merged state before [e].
  bool deviceMay(SyncEvent e, Map<String, Object?> device, MergedState replica);
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
    final d = replica[SyncKeys.device(deviceId)];
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
    for (final d in drafts) {
      final origin = d.type == EventType.usage
          ? usageOrigin(deviceId)
          : deviceId;
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

  /// Checks and takes in [events] from [source]; returns those accepted.
  /// Events already held are skipped, as are those after a gap (they come
  /// again once the gap is filled) and those badly signed or not allowed.
  Future<IngestResult> ingest(List<SyncEvent> events, {Object? source}) =>
      _serial(() => _ingest(events, source: source));

  Future<IngestResult> _ingest(List<SyncEvent> events, {Object? source}) async {
    final taken = <SyncEvent>[];
    var gap = false;
    var changed = false;
    for (final e in events) {
      if (!store.accepts(e)) {
        if (e.seq > store.lastSeq(e.origin)) gap = true;
        continue;
      }
      if (!await _authorized(e)) continue;
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

  Future<bool> _authorized(SyncEvent e) async {
    // Use of apps only under usage origins, and only there.
    if ((e.type == EventType.usage) != isUsageOrigin(e.origin)) return false;
    switch (e.signer) {
      case Signer.parent:
        return verifyEvent(e, root.parentKey);
      case Signer.device:
        final id = deviceOfOrigin(e.origin);
        final device = replica[SyncKeys.device(id)];
        final key = memberKey(id);
        if (device == null || key == null) return false;
        if (!await verifyEvent(e, key)) return false;
        return policy.deviceMay(e, device, replica);
    }
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
  final root = FamilyRoot(familyId, parentKey.publicKey);
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
