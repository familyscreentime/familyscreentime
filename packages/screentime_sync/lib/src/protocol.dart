/// The exchange between two members once their session is open: each says
/// what it has, sends what the other lacks, then passes on new events as
/// they come, its own and those relayed from other devices.
library;

import 'dart:async';

import 'event.dart';
import 'log.dart';
import 'node.dart';
import 'session.dart';

/// Events sent per message.
const eventsPerMessage = 200;

class SyncSession implements RemoteSource {
  final SyncNode node;
  final SecureChannel channel;

  /// The other device's vector, as last told.
  Map<String, int> peerVector = {};

  /// Whether the other device understands origins cut per child (it says
  /// so in its hello, from 0.25).
  bool _peerScoped = false;

  /// What the other device receives: the family's events, and those of
  /// its child (all, for a parent's device).
  Audience get audience => Audience.of(
    node.replica[SyncKeys.device(deviceOfOrigin(peerId))],
    scoped: _peerScoped,
  );

  /// Called with each message that is not part of the sync itself
  /// (commands, acknowledgements…).
  final void Function(Map<String, Object?> message)? onOther;

  StreamSubscription<Accepted>? _forward;
  final _done = Completer<void>();
  final _caughtUp = Completer<void>();

  SyncSession(this.node, this.channel, {this.onOther});

  String get peerId => channel.peerId;

  /// Completes when the session ends.
  Future<void> get done => _done.future;

  /// Completes once the other device has sent what this one lacked.
  Future<void> get caughtUp => _caughtUp.future;

  /// Starts exchanging; returns at once.
  void start() {
    // New events, made here or received from another device, are passed
    // on as they come.
    final me = SyncKeys.device(deviceOfOrigin(node.deviceId));
    _forward = node.accepted.listen((a) {
      if (identical(a.source, this)) return;
      final to = audience;
      _sendEvents([
        for (final e in a.events)
          if (to.allows(e)) e,
      ]);
      // This device now belongs to another child, or to the parents: what
      // it receives changes, so it says again what it has.
      if (a.events.any((e) => e.key == me)) _sendHello();
    });
    channel.messages.listen(
      _onMessage,
      onDone: _finish,
      onError: (Object _) => _finish(),
    );
    _sendHello();
  }

  void _sendHello() =>
      channel.send({'t': 'hello', 'v': node.store.vector, 'c': 1});

  void _sendEvents(List<SyncEvent> events) {
    if (events.isEmpty) return;
    for (var i = 0; i < events.length; i += eventsPerMessage) {
      final chunk = events.skip(i).take(eventsPerMessage);
      channel.send({
        't': 'events',
        'e': [for (final e in chunk) e.toJson()],
      });
    }
  }

  Future<void> _onMessage(Map<String, Object?> m) async {
    switch (m['t']) {
      case 'hello':
        peerVector = {
          for (final e in (m['v'] as Map).entries)
            e.key as String: (e.value as num).toInt(),
        };
        _peerScoped = m['c'] == 1;
        for (final page in node.store.pagesFor(peerVector, to: audience)) {
          _sendEvents(page);
        }
        channel.send({'t': 'sent'});
      case 'events':
        final events = [
          for (final e in m['e'] as List)
            SyncEvent.fromJson(Map<String, Object?>.from(e as Map)),
        ];
        final result = await node.ingest(events, source: this);
        // Something came after a gap: ask again from what is held.
        if (result.gap) _sendHello();
      case 'sent':
        // Once the events received before it are taken in.
        await node.ingest(const [], source: this);
        if (!_caughtUp.isCompleted) _caughtUp.complete();
      default:
        onOther?.call(m);
    }
  }

  /// Sends a message outside the sync itself.
  Future<void> send(Map<String, Object?> message) => channel.send(message);

  Future<void> _finish() async {
    await _forward?.cancel();
    if (!_caughtUp.isCompleted) _caughtUp.complete();
    if (!_done.isCompleted) _done.complete();
  }

  Future<void> close() async {
    await channel.close();
    await _finish();
  }
}
