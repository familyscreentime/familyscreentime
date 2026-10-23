/// Sync on the local network: a device listens for the others, says on the
/// network that it is there (DNS-SD), and keeps a session open with each
/// member device it finds.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';

import 'keys.dart';
import 'node.dart';
import 'pairing.dart';
import 'protocol.dart';
import 'session.dart';
import 'ws.dart';

/// A service seen on the local network.
class LanService {
  final String name;
  final String host;
  final int port;
  final Map<String, String> attributes;

  /// Gone from the network.
  final bool lost;

  const LanService({
    required this.name,
    required this.host,
    required this.port,
    this.attributes = const {},
    this.lost = false,
  });
}

/// Saying on the network that a service is there, and finding others
/// (DNS-SD on Android and Windows; a fake in tests).
abstract class LanDirectory {
  Future<void> advertise({
    required String type,
    required String name,
    required int port,
    required Map<String, String> attributes,
  });

  Future<void> stopAdvertising(String type);

  /// Services of [type] as they are found, resolved or lost.
  Stream<LanService> discover(String type);
}

/// DNS-SD type of the family's devices.
const syncServiceType = '_fstime._tcp';

/// DNS-SD type of a device welcoming a new one (in parent mode).
const pairingServiceType = '_fstpair._tcp';

/// A short tag of the family, so devices of other families are ignored.
Future<String> familyTag(String familyId) async {
  final h = await Sha256().hash(utf8.encode('fst-family:$familyId'));
  return h.bytes.take(6).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// How a member device stands, as last seen here.
class PeerState {
  final String deviceId;
  final DateTime lastContact;
  final bool connected;

  const PeerState(this.deviceId, this.lastContact, {required this.connected});

  Map<String, Object?> toJson() => {
    'last': lastContact.millisecondsSinceEpoch,
    'connected': connected,
  };
}

/// Keeps sessions open with the family's other devices on the network.
class LanSync {
  final SyncNode node;
  final LanDirectory directory;

  /// Called when a device connects or disconnects.
  final void Function()? onPeersChanged;

  /// How often devices seen but not connected are tried again.
  final Duration retryEvery;

  HttpServer? _server;
  StreamSubscription<LanService>? _discovery;
  Timer? _retry;
  late final String _tag;
  final _sessions = <String, _Session>{};
  final _connecting = <String>{};
  final _known = <String, LanService>{};
  final _lastContact = <String, DateTime>{};

  LanSync(
    this.node,
    this.directory, {
    this.onPeersChanged,
    this.retryEvery = const Duration(minutes: 1),
  });

  /// This device as the others know it (without its `~ui` part).
  String get deviceId => deviceOfOrigin(node.deviceId);

  /// Port listened on, once started.
  int? get port => _server?.port;

  /// The devices seen, and whether they are connected now.
  List<PeerState> get peers => [
    for (final e in _lastContact.entries)
      PeerState(e.key, e.value, connected: _sessions.containsKey(e.key)),
  ];

  Future<void> start({InternetAddress? address}) async {
    _tag = await familyTag(node.root.familyId);
    _server = await serveFrames(onChannel: _incoming, address: address);
    // Found by the others even if saying it on the network fails: they
    // may still find this device by its own search.
    _discovery = directory
        .discover(syncServiceType)
        .listen(_found, onError: (Object _) {});
    _retry = Timer.periodic(retryEvery, (_) {
      for (final s in _known.values.toList()) {
        _found(s);
      }
    });
    await directory.advertise(
      type: syncServiceType,
      name: 'fst-$deviceId',
      port: _server!.port,
      attributes: {'f': _tag, 'd': deviceId},
    );
  }

  void _found(LanService s) {
    final peer = s.attributes['d'];
    if (peer == null || peer == deviceId || s.attributes['f'] != _tag) return;
    if (s.lost) {
      _known.remove(peer);
      return;
    }
    _known[peer] = s;
    if (_sessions.containsKey(peer) || _connecting.contains(peer)) return;
    if (node.memberKey(peer) == null) return;
    _connect(peer, s.host, s.port);
  }

  /// Connects to [peer] directly, at [host]:[port].
  Future<void> _connect(String peer, String host, int port) async {
    _connecting.add(peer);
    try {
      final channel = await connectFrames(host, port);
      final secure = await memberHandshake(
        channel: channel,
        me: node.me,
        familyId: node.root.familyId,
        keyOf: node.memberKey,
        initiator: true,
      );
      _add(secure, initiatedHere: true);
    } on Object {
      // Not reachable now; tried again later.
    } finally {
      _connecting.remove(peer);
    }
  }

  Future<void> _incoming(FrameChannel channel) async {
    try {
      final secure = await memberHandshake(
        channel: channel,
        me: node.me,
        familyId: node.root.familyId,
        keyOf: node.memberKey,
        initiator: false,
      );
      _add(secure, initiatedHere: false);
    } on Object {
      // Not a member, or gone: nothing to keep.
    }
  }

  void _add(SecureChannel secure, {required bool initiatedHere}) {
    final peer = deviceOfOrigin(secure.peerId);
    final existing = _sessions[peer];
    if (existing != null) {
      // Both connected at once: both keep the one the smaller id started.
      final keepNew = initiatedHere == (deviceId.compareTo(peer) < 0);
      if (!keepNew) {
        secure.close();
        return;
      }
      _sessions.remove(peer);
      existing.session.close();
    }
    final session = SyncSession(node, secure);
    final entry = _Session(session, initiatedHere);
    _sessions[peer] = entry;
    _lastContact[peer] = DateTime.now();
    session.start();
    onPeersChanged?.call();
    session.done.then((_) {
      if (identical(_sessions[peer], entry)) _sessions.remove(peer);
      _lastContact[peer] = DateTime.now();
      onPeersChanged?.call();
    });
  }

  /// Whether a session with [peer] is open.
  bool isConnected(String peer) => _sessions.containsKey(peer);

  /// Waits until [peer] is connected and caught up, at most [timeout].
  Future<bool> waitFor(
    String peer, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      final s = _sessions[peer];
      if (s != null) {
        await s.session.caughtUp;
        return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return false;
  }

  Future<void> stop() async {
    _retry?.cancel();
    await _discovery?.cancel();
    await directory.stopAdvertising(syncServiceType);
    for (final s in _sessions.values.toList()) {
      await s.session.close();
    }
    _sessions.clear();
    await _server?.close(force: true);
  }
}

/// A member device in parent mode, welcoming new devices: it listens, and
/// says on the network that it is ready, under [name].
class PairingHost {
  final SyncNode node;
  final SigningKey parentKey;
  final LanDirectory directory;
  final String name;

  /// Shows the code and what the new device says of itself; returns its
  /// registration (role, child…), or `null` to refuse.
  final Future<Map<String, Object?>?> Function(
    String code,
    Map<String, Object?> info,
  )
  confirm;

  /// Called with each device welcomed.
  final void Function(String deviceId)? onWelcomed;

  HttpServer? _server;

  PairingHost({
    required this.node,
    required this.parentKey,
    required this.directory,
    required this.name,
    required this.confirm,
    this.onWelcomed,
  });

  Future<void> start({InternetAddress? address}) async {
    _server = await serveFrames(onChannel: _incoming, address: address);
    await directory.advertise(
      type: pairingServiceType,
      name: 'fst-pair-${deviceOfOrigin(node.deviceId)}',
      port: _server!.port,
      attributes: {'d': deviceOfOrigin(node.deviceId), 'n': name},
    );
  }

  Future<void> _incoming(FrameChannel channel) async {
    try {
      final id = await welcomeDevice(
        channel: channel,
        node: node,
        parentKey: parentKey,
        confirm: confirm,
      );
      if (id != null) onWelcomed?.call(id);
    } on Object {
      // Refused or gone: the screen stays open for another try.
    }
  }

  Future<void> stop() async {
    await directory.stopAdvertising(pairingServiceType);
    await _server?.close(force: true);
  }
}

/// Devices ready to welcome this one, as they are found.
Stream<LanService> findPairingHosts(LanDirectory directory) =>
    directory.discover(pairingServiceType);

/// Joins the family through [host], found by [findPairingHosts].
Future<Welcome> joinThrough(
  LanService host, {
  required DeviceIdentity me,
  required Map<String, Object?> info,
  required Future<bool> Function(String code) confirm,
}) async => joinFamily(
  channel: await connectFrames(host.host, host.port),
  me: me,
  info: info,
  confirm: confirm,
);

class _Session {
  final SyncSession session;
  final bool initiatedHere;
  _Session(this.session, this.initiatedHere);
}

/// A fake network directory, shared by the devices of a test: what one
/// advertises, the others find (on the loopback interface).
class MemoryLanDirectory implements LanDirectory {
  final _Network _network;
  final _mine = <String, LanService>{};

  MemoryLanDirectory._(this._network);

  /// Directories that see each other.
  static List<MemoryLanDirectory> network(int count) {
    final n = _Network();
    return [for (var i = 0; i < count; i++) MemoryLanDirectory._(n)];
  }

  @override
  Future<void> advertise({
    required String type,
    required String name,
    required int port,
    required Map<String, String> attributes,
  }) async {
    final s = LanService(
      name: name,
      host: '127.0.0.1',
      port: port,
      attributes: attributes,
    );
    _mine[type] = s;
    _network.add(type, s);
  }

  @override
  Future<void> stopAdvertising(String type) async {
    final s = _mine.remove(type);
    if (s != null) _network.remove(type, s);
  }

  @override
  Stream<LanService> discover(String type) => _network.watch(type);
}

class _Network {
  final _services = <String, List<LanService>>{};
  final _watchers = <String, List<StreamController<LanService>>>{};

  void add(String type, LanService s) {
    _services.putIfAbsent(type, () => []).add(s);
    for (final w in _watchers[type] ?? const []) {
      w.add(s);
    }
  }

  void remove(String type, LanService s) {
    _services[type]?.remove(s);
    final lost = LanService(
      name: s.name,
      host: s.host,
      port: s.port,
      attributes: s.attributes,
      lost: true,
    );
    for (final w in _watchers[type] ?? const []) {
      w.add(lost);
    }
  }

  Stream<LanService> watch(String type) {
    late final StreamController<LanService> c;
    c = StreamController<LanService>(
      onListen: () {
        for (final s in [...?_services[type]]) {
          c.add(s);
        }
      },
      onCancel: () => _watchers[type]?.remove(c),
    );
    _watchers.putIfAbsent(type, () => []).add(c);
    return c.stream;
  }
}
