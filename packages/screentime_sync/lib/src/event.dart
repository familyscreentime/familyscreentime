/// Events of the family log: what a device recorded or a parent decided,
/// signed by its author.
library;

import 'canonical.dart';
import 'hlc.dart';

/// Who signed an event: the parent (with the family's parent key, unlocked
/// by the parent code) or the device that recorded it (with its own key).
enum Signer { parent, device }

/// Event types understood by the merge (see `Replica`); other types (such
/// as [usageType]) are passed to the app as they are.
abstract final class EventType {
  /// A whole entity, created or replaced: fields left out are cleared.
  static const put = 'put';

  /// Some fields of an entity; a `null` value clears the field.
  static const patch = 'patch';

  /// An entity removed.
  static const delete = 'delete';

  /// A stretch of use of an app on a device.
  static const usage = 'usage';
}

/// What an event says, before it is numbered, dated and signed.
class EventDraft {
  final String type;

  /// The entity concerned (`rule/abc`, `device/xyz`…), or a topic for
  /// events that are not merged (`usage`).
  final String key;
  final Map<String, Object?> data;

  const EventDraft(this.type, this.key, [this.data = const {}]);

  const EventDraft.put(this.key, this.data) : type = EventType.put;
  const EventDraft.patch(this.key, this.data) : type = EventType.patch;
  const EventDraft.delete(this.key) : type = EventType.delete, data = const {};

  @override
  String toString() => '$type $key ${canonicalJson(data)}';
}

/// A signed event. [origin] and [seq] number the events of each device
/// from 1, without gaps: that is what lets devices tell each other what
/// they already have.
class SyncEvent {
  final String origin;
  final int seq;
  final Hlc hlc;
  final String type;
  final String key;
  final Map<String, Object?> data;
  final Signer signer;

  /// Ed25519 signature of [signedBytes], base64.
  final String sig;

  const SyncEvent({
    required this.origin,
    required this.seq,
    required this.hlc,
    required this.type,
    required this.key,
    required this.data,
    required this.signer,
    required this.sig,
  });

  /// Unique across the family.
  String get id => '$origin/$seq';

  Map<String, Object?> _body() => {
    'o': origin,
    'n': seq,
    'h': hlc.pack(),
    't': type,
    'k': key,
    'd': data,
    's': signer.name,
  };

  /// The bytes the signature covers: everything but the signature.
  List<int> get signedBytes => canonicalBytes(['fst-event-v1', _body()]);

  Map<String, Object?> toJson() => {..._body(), 'sig': sig};

  factory SyncEvent.fromJson(Map<String, Object?> j) => SyncEvent(
    origin: j['o'] as String,
    seq: (j['n'] as num).toInt(),
    hlc: Hlc.parse(j['h'] as String),
    type: j['t'] as String,
    key: j['k'] as String,
    data: Map<String, Object?>.from(j['d'] as Map),
    signer: Signer.values.byName(j['s'] as String),
    sig: j['sig'] as String,
  );

  @override
  String toString() => '$id $type $key';
}
