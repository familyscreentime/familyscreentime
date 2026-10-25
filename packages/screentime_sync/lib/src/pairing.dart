/// A device joining the family: after the pairing handshake, both screens
/// show the same 6-digit code, the parent confirms on both, and the member
/// device (in parent mode) registers the new one and hands it the log.
library;

import 'dart:async';

import 'event.dart';
import 'keys.dart';
import 'log.dart';
import 'node.dart';
import 'session.dart';

/// How long the parent has to compare and confirm the codes.
const pairingTimeout = Duration(minutes: 5);

class PairingRefused implements Exception {
  const PairingRefused();
  @override
  String toString() => 'Pairing refused';
}

/// What a joining device receives: the family's root and its log.
class Welcome {
  final FamilyRoot root;
  final List<SyncEvent> events;

  const Welcome(this.root, this.events);
}

/// Joins a family through [channel], opened to a member device in parent
/// mode. [confirm] shows the code and returns whether the parent confirmed
/// it matches the other screen. [info]: the device's name and platform.
Future<Welcome> joinFamily({
  required FrameChannel channel,
  required DeviceIdentity me,
  required Map<String, Object?> info,
  required Future<bool> Function(String code) confirm,
}) async {
  final pairing = await pairingHandshake(
    channel: channel,
    deviceId: me.deviceId,
    joining: true,
  );
  final secure = pairing.channel;
  final replies = StreamIterator(secure.messages);
  try {
    final first = replies.moveNext().timeout(pairingTimeout);
    // Its name and key go at once, so the other screen can show them with
    // the code; the welcome is only taken once the code is confirmed here.
    await secure.send({
      't': 'join',
      'info': {...info, 'signKey': me.signing.publicKey},
    });
    final confirmed = await confirm(pairing.code);
    if (!await first || !confirmed) throw const PairingRefused();
    final reply = replies.current;
    if (reply['t'] != 'welcome') throw const PairingRefused();
    final events = <SyncEvent>[];
    while (await replies.moveNext().timeout(pairingTimeout)) {
      final m = replies.current;
      if (m['t'] == 'end') break;
      for (final e in m['e'] as List) {
        events.add(SyncEvent.fromJson(Map<String, Object?>.from(e as Map)));
      }
    }
    return Welcome(
      FamilyRoot.fromJson(Map<String, Object?>.from(reply['root'] as Map)),
      events,
    );
  } finally {
    await replies.cancel();
    await secure.close();
  }
}

/// Welcomes a device into the family through [channel]. [confirm] shows
/// the code and what the device says of itself, and returns its
/// registration as the parent completed it (which child it belongs to…),
/// or `null` when the parent refuses. Returns the new device's id.
Future<String?> welcomeDevice({
  required FrameChannel channel,
  required SyncNode node,
  required SigningKey parentKey,
  required Future<Map<String, Object?>?> Function(
    String code,
    Map<String, Object?> info,
  )
  confirm,
}) async {
  final pairing = await pairingHandshake(
    channel: channel,
    deviceId: node.deviceId,
    joining: false,
  );
  final secure = pairing.channel;
  try {
    final join = await secure.messages.first.timeout(pairingTimeout);
    if (join['t'] != 'join') throw const PairingRefused();
    final info = Map<String, Object?>.from(join['info'] as Map);
    final signKey = info['signKey'];
    if (signKey is! String) throw const PairingRefused();
    final registration = await confirm(pairing.code, info);
    if (registration == null) {
      await secure.send({'t': 'refused'});
      return null;
    }
    final id = secure.peerId;
    await node.emit([
      EventDraft.put(SyncKeys.device(id), {
        ...info,
        ...registration,
        'signKey': signKey,
      }),
    ], parentKey: parentKey);
    await secure.send({'t': 'welcome', 'root': node.root.toJson()});
    // Then the log, page by page, and the end of it: what the device
    // receives (the family's, and its child's).
    final to = Audience.of(node.replica[SyncKeys.device(id)]);
    for (final page in node.store.pagesFor(const {}, to: to)) {
      await secure.send({
        't': 'events',
        'e': [for (final e in page) e.toJson()],
      });
    }
    await secure.send({'t': 'end'});
    return id;
  } finally {
    await secure.close();
  }
}
