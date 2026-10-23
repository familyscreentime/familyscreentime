/// Encrypted sessions between two devices, over any channel that carries
/// frames (a WebSocket on the local network, an in-memory pipe in tests).
///
/// Two handshakes:
/// - members of the family authenticate each other with their device keys,
///   registered in the family log;
/// - a device joining the family has no key known yet: both screens then
///   show a 6-digit code derived from the exchange, which the parent
///   compares (a man in the middle has one chance in a million of making
///   them match, thanks to a commitment sent first).
///
/// Both derive session keys from an ephemeral X25519 exchange (HKDF-SHA256);
/// messages are then encrypted with ChaCha20-Poly1305.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'canonical.dart';
import 'keys.dart';

/// A two-way channel of frames (byte strings).
abstract class FrameChannel {
  /// Incoming frames; listened to once.
  Stream<List<int>> get frames;
  void send(List<int> frame);
  Future<void> close();
}

/// Two channels joined back to back, for tests and same-process use.
(FrameChannel, FrameChannel) memoryChannelPair() {
  final aToB = StreamController<List<int>>();
  final bToA = StreamController<List<int>>();
  return (
    _MemoryChannel(bToA.stream, aToB, bToA),
    _MemoryChannel(aToB.stream, bToA, aToB),
  );
}

class _MemoryChannel implements FrameChannel {
  @override
  final Stream<List<int>> frames;
  final StreamController<List<int>> _out;
  final StreamController<List<int>> _in;

  _MemoryChannel(this.frames, this._out, this._in);

  @override
  void send(List<int> frame) {
    if (!_out.isClosed) _out.add(frame);
  }

  @override
  Future<void> close() async {
    if (!_out.isClosed) await _out.close();
    if (!_in.isClosed) await _in.close();
  }
}

/// Reads frames one at a time.
class FrameReader {
  final _queue = Queue<List<int>>();
  Completer<List<int>>? _waiting;
  bool _done = false;

  FrameReader(Stream<List<int>> frames) {
    frames.listen(
      (f) {
        final w = _waiting;
        if (w != null) {
          _waiting = null;
          w.complete(f);
        } else {
          _queue.add(f);
        }
      },
      onError: (Object e) => _finish(),
      onDone: _finish,
      cancelOnError: true,
    );
  }

  void _finish() {
    _done = true;
    final w = _waiting;
    _waiting = null;
    w?.completeError(const ChannelClosed());
  }

  /// The next frame; fails with [ChannelClosed] once the channel is closed.
  Future<List<int>> next() {
    if (_queue.isNotEmpty) return Future.value(_queue.removeFirst());
    if (_done) return Future.error(const ChannelClosed());
    return (_waiting = Completer<List<int>>()).future;
  }
}

class ChannelClosed implements Exception {
  const ChannelClosed();
  @override
  String toString() => 'Channel closed';
}

/// A handshake that failed: wrong family, unknown device, bad signature…
class HandshakeFailed implements Exception {
  final String reason;
  const HandshakeFailed(this.reason);
  @override
  String toString() => 'Handshake failed: $reason';
}

const handshakeTimeout = Duration(seconds: 20);

/// An encrypted channel to another device, once the handshake is done.
class SecureChannel {
  final FrameChannel _channel;
  final FrameReader _reader;
  final SecretKey _sendKey;
  final SecretKey _receiveKey;

  /// The device at the other end.
  final String peerId;

  int _sent = 0;
  int _received = 0;
  Future<void> _sending = Future.value();
  final _messages = StreamController<Map<String, Object?>>();

  SecureChannel._(
    this._channel,
    this._reader,
    List<int> sendKey,
    List<int> receiveKey,
    this.peerId,
  ) : _sendKey = SecretKey(sendKey),
      _receiveKey = SecretKey(receiveKey) {
    _read();
  }

  static final _aead = Chacha20.poly1305Aead();

  static List<int> _nonce(int n) {
    final b = ByteData(12)..setUint64(4, n);
    return b.buffer.asUint8List();
  }

  /// Decrypted messages, in order; done when the channel closes or a frame
  /// fails to decrypt (the channel is then closed).
  Stream<Map<String, Object?>> get messages => _messages.stream;

  Future<void> _read() async {
    try {
      while (true) {
        final frame = await _reader.next();
        if (frame.length < 16) throw const HandshakeFailed('short frame');
        final clear = await _aead.decrypt(
          SecretBox(
            frame.sublist(0, frame.length - 16),
            nonce: _nonce(_received++),
            mac: Mac(frame.sublist(frame.length - 16)),
          ),
          secretKey: _receiveKey,
        );
        _messages.add(
          Map<String, Object?>.from(jsonDecode(utf8.decode(clear)) as Map),
        );
      }
    } on Object {
      await close();
    }
  }

  /// Sends [message], encrypted; messages leave in the order sent.
  Future<void> send(Map<String, Object?> message) {
    final n = _sent++;
    final clear = utf8.encode(jsonEncode(message));
    return _sending = _sending.then((_) async {
      final box = await _aead.encrypt(
        clear,
        secretKey: _sendKey,
        nonce: _nonce(n),
      );
      _channel.send([...box.cipherText, ...box.mac.bytes]);
    });
  }

  Future<void> close() async {
    await _sending.catchError((Object _) {});
    await _channel.close();
    // Not awaited: a listener that stopped reading would hold it forever.
    if (!_messages.isClosed) unawaited(_messages.close());
  }
}

Future<Map<String, Object?>> _readJson(FrameReader r) async {
  final frame = await r.next().timeout(handshakeTimeout);
  final decoded = jsonDecode(utf8.decode(frame));
  if (decoded is! Map) throw const HandshakeFailed('bad message');
  return Map<String, Object?>.from(decoded);
}

void _sendJson(FrameChannel c, Map<String, Object?> m) =>
    c.send(utf8.encode(jsonEncode(m)));

/// Session keys from the shared secret: initiator to responder, then the
/// other way.
Future<(List<int>, List<int>)> _keys(List<int> shared, List<int> th) async {
  final k = await Hkdf(hmac: Hmac.sha256(), outputLength: 64).deriveKey(
    secretKey: SecretKey(shared),
    nonce: th,
    info: utf8.encode('fst-session-v1'),
  );
  final b = await k.extractBytes();
  return (b.sublist(0, 32), b.sublist(32));
}

String _field(Map<String, Object?> m, String name) {
  final v = m[name];
  if (v is! String) throw HandshakeFailed('missing $name');
  return v;
}

void _expect(Map<String, Object?> m, String type) {
  if (m['t'] != type) throw HandshakeFailed('expected $type, got ${m['t']}');
}

/// Opens a session between two members of family [familyId]. [keyOf] gives
/// a device's registered signing key (base64), or `null` when the device
/// is not (or no longer) a member.
Future<SecureChannel> memberHandshake({
  required FrameChannel channel,
  required DeviceIdentity me,
  required String familyId,
  required FutureOr<String?> Function(String deviceId) keyOf,
  required bool initiator,
}) async {
  final reader = FrameReader(channel.frames);
  try {
    final eph = await AgreementKey.generate();
    if (initiator) {
      _sendJson(channel, {
        't': 'm1',
        'f': familyId,
        'd': me.deviceId,
        'e': eph.publicKey,
      });
      final m2 = await _readJson(reader);
      _expect(m2, 'm2');
      final peer = _field(m2, 'd');
      final peerEph = _field(m2, 'e');
      final peerKey = await keyOf(peer);
      if (peerKey == null) throw HandshakeFailed('unknown device $peer');
      final th = await sha256Bytes(
        canonicalBytes([
          'fst-m',
          familyId,
          me.deviceId,
          eph.publicKey,
          peer,
          peerEph,
        ]),
      );
      if (!await verifySignature(
        canonicalBytes(['responder', b64(th)]),
        _field(m2, 's'),
        peerKey,
      )) {
        throw const HandshakeFailed('bad signature');
      }
      _sendJson(channel, {
        't': 'm3',
        's': await me.signing.sign(canonicalBytes(['initiator', b64(th)])),
      });
      final (out, back) = await _keys(await eph.agree(peerEph), th);
      return SecureChannel._(channel, reader, out, back, peer);
    } else {
      final m1 = await _readJson(reader);
      _expect(m1, 'm1');
      if (m1['f'] != familyId) throw const HandshakeFailed('other family');
      final peer = _field(m1, 'd');
      final peerEph = _field(m1, 'e');
      final peerKey = await keyOf(peer);
      if (peerKey == null) throw HandshakeFailed('unknown device $peer');
      final th = await sha256Bytes(
        canonicalBytes([
          'fst-m',
          familyId,
          peer,
          peerEph,
          me.deviceId,
          eph.publicKey,
        ]),
      );
      _sendJson(channel, {
        't': 'm2',
        'd': me.deviceId,
        'e': eph.publicKey,
        's': await me.signing.sign(canonicalBytes(['responder', b64(th)])),
      });
      final m3 = await _readJson(reader);
      _expect(m3, 'm3');
      if (!await verifySignature(
        canonicalBytes(['initiator', b64(th)]),
        _field(m3, 's'),
        peerKey,
      )) {
        throw const HandshakeFailed('bad signature');
      }
      final (inbound, out) = await _keys(await eph.agree(peerEph), th);
      return SecureChannel._(channel, reader, out, inbound, peer);
    }
  } on Object {
    await channel.close();
    rethrow;
  }
}

/// A pairing session: encrypted, but only trusted once both screens show
/// the same [code].
class PairingChannel {
  final SecureChannel channel;

  /// The 6-digit code both screens show.
  final String code;

  const PairingChannel(this.channel, this.code);
}

Future<String> _sas(List<int> shared, List<int> th) async {
  final k = await Hkdf(hmac: Hmac.sha256(), outputLength: 4).deriveKey(
    secretKey: SecretKey(shared),
    nonce: th,
    info: utf8.encode('fst-pairing-code-v1'),
  );
  final b = await k.extractBytes();
  final n = ByteData.sublistView(Uint8List.fromList(b)).getUint32(0);
  return (n % 1000000).toString().padLeft(6, '0');
}

/// Pairing handshake: [joining] is the device entering the family (it
/// starts), the other is a member in parent mode.
Future<PairingChannel> pairingHandshake({
  required FrameChannel channel,
  required String deviceId,
  required bool joining,
}) async {
  final reader = FrameReader(channel.frames);
  try {
    final eph = await AgreementKey.generate();
    if (joining) {
      // Commit to the key before seeing the other's.
      _sendJson(channel, {
        't': 'p1',
        'd': deviceId,
        'c': b64(await sha256Bytes(unb64(eph.publicKey))),
      });
      final p2 = await _readJson(reader);
      _expect(p2, 'p2');
      final host = _field(p2, 'd');
      final hostEph = _field(p2, 'e');
      _sendJson(channel, {'t': 'p3', 'e': eph.publicKey});
      final th = await sha256Bytes(
        canonicalBytes(['fst-p', deviceId, eph.publicKey, host, hostEph]),
      );
      final shared = await eph.agree(hostEph);
      final (out, back) = await _keys(shared, th);
      return PairingChannel(
        SecureChannel._(channel, reader, out, back, host),
        await _sas(shared, th),
      );
    } else {
      final p1 = await _readJson(reader);
      _expect(p1, 'p1');
      final joiner = _field(p1, 'd');
      final commitment = _field(p1, 'c');
      _sendJson(channel, {'t': 'p2', 'd': deviceId, 'e': eph.publicKey});
      final p3 = await _readJson(reader);
      _expect(p3, 'p3');
      final joinerEph = _field(p3, 'e');
      if (b64(await sha256Bytes(unb64(joinerEph))) != commitment) {
        throw const HandshakeFailed('commitment mismatch');
      }
      final th = await sha256Bytes(
        canonicalBytes(['fst-p', joiner, joinerEph, deviceId, eph.publicKey]),
      );
      final shared = await eph.agree(joinerEph);
      final (inbound, out) = await _keys(shared, th);
      return PairingChannel(
        SecureChannel._(channel, reader, out, inbound, joiner),
        await _sas(shared, th),
      );
    }
  } on Object {
    await channel.close();
    rethrow;
  }
}
