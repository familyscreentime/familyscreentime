/// Sync through a relay server the family hosts (see `server/` at the
/// repository's root): each device sends the events the server lacks, and
/// takes in those it received from the others since it last asked.
///
/// The server cannot read the events: each is encrypted with the family's
/// content key, which only the devices hold. It knows the devices by their
/// public keys, from a list signed by the parent key ([signMembers]), and
/// each request is signed by the device making it.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

import 'canonical.dart';
import 'event.dart';
import 'keys.dart';
import 'log.dart';
import 'node.dart';

/// Encrypts events for the relay with the family's content key
/// (XChaCha20-Poly1305), bound to their family, origin and number.
class ContentCipher {
  final String familyId;
  final SecretKey _key;
  static final _aead = Xchacha20.poly1305Aead();

  ContentCipher(List<int> key, this.familyId) : _key = SecretKey(key);

  List<int> _aad(String origin, int seq) =>
      utf8.encode('fst-relay-v1|$familyId|$origin|$seq');

  Future<String> seal(SyncEvent e) async {
    final box = await _aead.encrypt(
      utf8.encode(canonicalJson(e.toJson())),
      secretKey: _key,
      aad: _aad(e.origin, e.seq),
    );
    return b64([...box.nonce, ...box.cipherText, ...box.mac.bytes]);
  }

  /// The event sealed in [body] as [origin]'s number [seq]; `null` if it
  /// does not open, or is not that event.
  Future<SyncEvent?> open(String origin, int seq, String body) async {
    try {
      final raw = unb64(body);
      final clear = await _aead.decrypt(
        SecretBox(
          raw.sublist(24, raw.length - 16),
          nonce: raw.sublist(0, 24),
          mac: Mac(raw.sublist(raw.length - 16)),
        ),
        secretKey: _key,
        aad: _aad(origin, seq),
      );
      final e = SyncEvent.fromJson(
        Map<String, Object?>.from(jsonDecode(utf8.decode(clear)) as Map),
      );
      return e.origin == origin && e.seq == seq ? e : null;
    } on Object {
      return null;
    }
  }
}

/// The list of devices a relay lets in, signed by the parent key: the
/// family's id, a [version] (later lists replace earlier ones) and each
/// device's public key by id. [scopes]: what each device receives (see
/// [Audience.key]: `*` for all, a child's id, or empty for the family's
/// only); a device left out receives all. [floors]: by origin, the last
/// number the snapshot replaced, which the relay may forget.
Future<Map<String, Object?>> signMembers({
  required String familyId,
  required int version,
  required Map<String, String> devices,
  required SigningKey parentKey,
  Map<String, String> scopes = const {},
  Map<String, int> floors = const {},
}) async {
  final statement = canonicalJson({
    'familyId': familyId,
    'version': version,
    'devices': devices,
    if (scopes.isNotEmpty) 'scopes': scopes,
    if (floors.isNotEmpty) 'floors': floors,
  });
  return {
    'statement': statement,
    'sig': await parentKey.sign(utf8.encode('fst-members-v1\n$statement')),
  };
}

/// What a signed list says ([signMembers]).
typedef Members = ({
  int version,
  Map<String, String> devices,
  Map<String, String> scopes,
  Map<String, int> floors,
});

/// The devices, version, scopes and floors of a signed list.
Members? readMembers(Map<String, Object?>? members) {
  final statement = members?['statement'];
  if (statement is! String) return null;
  try {
    final j = jsonDecode(statement) as Map;
    return (
      version: (j['version'] as num).toInt(),
      devices: Map<String, String>.from(j['devices'] as Map),
      scopes: Map<String, String>.from(j['scopes'] as Map? ?? const {}),
      floors: {
        for (final e in (j['floors'] as Map? ?? const {}).entries)
          e.key as String: (e.value as num).toInt(),
      },
    );
  } on Object {
    return null;
  }
}

/// The devices of [node]'s family, removed ones left out, with their keys.
Map<String, String> memberKeys(SyncNode node) => {
  for (final e in node.replica.withPrefix(SyncKeys.devicePrefix).entries)
    if (e.value['revoked'] != true && e.value['signKey'] is String)
      e.key.substring(SyncKeys.devicePrefix.length):
          e.value['signKey'] as String,
};

/// What each of [node]'s family's devices receives ([Audience.key]).
Map<String, String> memberScopes(SyncNode node) => {
  for (final e in node.replica.withPrefix(SyncKeys.devicePrefix).entries)
    if (e.value['revoked'] != true && e.value['signKey'] is String)
      e.key.substring(SyncKeys.devicePrefix.length): Audience.of(e.value).key,
};

/// Whether a device receiving [scope] (see [Audience.key]) gets [origin]'s
/// events from a relay, which knows each device's scope ([scopes]) but
/// cannot read the events: use of apps from before 0.25 goes by the
/// device that recorded it.
bool relayAllows(String scope, String origin, Map<String, String> scopes) {
  if (scope == '*') return true;
  final s = scopeOfOrigin(origin);
  if (s != null) return s.isEmpty || s == scope;
  if (!isUsageOrigin(origin)) return true;
  return scope.isNotEmpty && scopes[deviceOfOrigin(origin)] == scope;
}

/// An event as the relay holds it: encrypted, with its origin and number
/// (and, received from it, its place in the relay's order).
class RelayEvent {
  final String origin;
  final int seq;
  final String body;
  final int? n;

  const RelayEvent(this.origin, this.seq, this.body, [this.n]);

  Map<String, Object?> toJson() => {'o': origin, 's': seq, 'b': body};

  factory RelayEvent.fromJson(Map<String, Object?> j) => RelayEvent(
    j['o'] as String,
    (j['s'] as num).toInt(),
    j['b'] as String,
    (j['n'] as num?)?.toInt(),
  );
}

/// What the relay holds: the last number of each origin, the version of
/// its list of devices, and when each device was last in contact.
class RelayHeads {
  final Vector heads;
  final int members;
  final Map<String, DateTime> seen;

  const RelayHeads(this.heads, this.members, this.seen);
}

class RelayPage {
  final List<RelayEvent> events;
  final int next;
  final bool more;

  const RelayPage(this.events, this.next, {required this.more});
}

/// Refused by the relay: [code] says why (`unknown_device`, `no_family`,
/// `bad_invitation`, `clock`…); [status] 0 when it could not be reached.
class RelayError implements Exception {
  final int status;
  final String code;
  final String message;

  const RelayError(this.status, this.code, [this.message = '']);

  @override
  String toString() =>
      'RelayError($status, $code${message.isEmpty ? '' : ': $message'})';
}

/// The relay's API, for one device of one family.
abstract class RelayApi {
  /// Registers the family, with an [invitation] from the server's
  /// administrator. Whether it was created (`false`: there already).
  Future<bool> createFamily({
    required String invitation,
    required String parentKey,
    required Map<String, Object?> members,
  });

  /// Sends a newer list of devices; the version the relay now holds.
  Future<int> postMembers(Map<String, Object?> members);

  Future<RelayHeads> heads();

  /// Sends events; those refused, because the relay lacks the ones before.
  Future<List<RelayEvent>> putEvents(List<RelayEvent> events);

  /// Events received after [after], in the order received.
  Future<RelayPage> getEvents(int after, {int limit = 500});
}

/// The relay's API over HTTPS (or HTTP, on a local network): [endpoint] is
/// the server's `api.php`. Requests are signed with [identity]'s key.
class HttpRelayApi implements RelayApi {
  final Uri endpoint;
  final String familyId;
  final String deviceId;
  final SigningKey _key;
  final HttpClient _client;

  /// The server's clock minus this device's, learned from its answers.
  Duration _offset = Duration.zero;

  HttpRelayApi(this.endpoint, this.familyId, DeviceIdentity identity)
    : deviceId = deviceOfOrigin(identity.deviceId),
      _key = identity.signing,
      _client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 15)
        ..idleTimeout = const Duration(seconds: 30)
        ..userAgent = 'FamilyScreenTime';

  void close() => _client.close(force: true);

  Future<Map<String, Object?>> _call(
    String method,
    Map<String, String> query, [
    Object? body,
    bool retried = false,
  ]) async {
    final queryString = [
      for (final e in query.entries)
        '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}',
    ].join('&');
    final bytes = body == null ? <int>[] : utf8.encode(jsonEncode(body));
    final time = DateTime.now().add(_offset).millisecondsSinceEpoch.toString();
    final message = [
      'fst-req-v1',
      method,
      queryString,
      familyId,
      deviceId,
      time,
      _hex(await sha256Bytes(bytes)),
    ].join('\n');
    final uri = endpoint.replace(query: queryString);
    final int status;
    final String text;
    final String? serverTime;
    try {
      final request = await _client.openUrl(method, uri);
      request.headers
        ..set('X-FST-Family', familyId)
        ..set('X-FST-Device', deviceId)
        ..set('X-FST-Time', time)
        ..set('X-FST-Signature', await _key.sign(utf8.encode(message)))
        ..contentType = ContentType.json;
      request.contentLength = bytes.length;
      request.add(bytes);
      final response = await request.close().timeout(
        const Duration(seconds: 60),
      );
      status = response.statusCode;
      serverTime = response.headers.value('X-FST-Server-Time');
      text = await utf8
          .decodeStream(response)
          .timeout(const Duration(seconds: 60));
    } on Object catch (e) {
      // A connection kept from before the device slept, or a network
      // waking up: tried once more, on a new connection.
      if (!retried) {
        await Future<void>.delayed(const Duration(seconds: 2));
        return _call(method, query, body, true);
      }
      throw RelayError(0, 'unreachable', '$e');
    }
    final Map<String, Object?> json;
    try {
      json = Map<String, Object?>.from(jsonDecode(text) as Map);
    } on Object {
      throw RelayError(
        status,
        'not_a_relay',
        'Not a Family Screen Time server',
      );
    }
    if (status == 200) return json;
    final code = json['error'] as String? ?? 'error';
    // A device clock far off: retried once on the server's.
    if (code == 'clock' && !retried && serverTime != null) {
      final server = int.tryParse(serverTime);
      if (server != null) {
        _offset = Duration(
          milliseconds: server - DateTime.now().millisecondsSinceEpoch,
        );
        return _call(method, query, body, true);
      }
    }
    throw RelayError(status, code, json['message'] as String? ?? '');
  }

  static String _hex(List<int> bytes) =>
      [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')].join();

  @override
  Future<bool> createFamily({
    required String invitation,
    required String parentKey,
    required Map<String, Object?> members,
  }) async {
    final j = await _call(
      'POST',
      {'r': 'family'},
      {'invitation': invitation, 'parentKey': parentKey, 'members': members},
    );
    return j['created'] == true;
  }

  @override
  Future<int> postMembers(Map<String, Object?> members) async {
    final j = await _call('POST', {'r': 'members'}, members);
    return (j['version'] as num).toInt();
  }

  @override
  Future<RelayHeads> heads() async {
    final j = await _call('GET', {'r': 'heads'});
    return RelayHeads(
      {
        for (final e in (j['heads'] as Map).entries)
          e.key as String: (e.value as num).toInt(),
      },
      (j['members'] as num).toInt(),
      {
        for (final e in (j['seen'] as Map).entries)
          if ((e.value as num) > 0)
            e.key as String: DateTime.fromMillisecondsSinceEpoch(
              (e.value as num).toInt(),
            ),
      },
    );
  }

  @override
  Future<List<RelayEvent>> putEvents(List<RelayEvent> events) async {
    final j = await _call(
      'POST',
      {'r': 'events'},
      {
        'events': [for (final e in events) e.toJson()],
      },
    );
    final refused = {
      for (final r in j['refused'] as List) '${(r as Map)['o']}/${r['s']}',
    };
    return [
      for (final e in events)
        if (refused.contains('${e.origin}/${e.seq}')) e,
    ];
  }

  @override
  Future<RelayPage> getEvents(int after, {int limit = 500}) async {
    final j = await _call('GET', {
      'r': 'events',
      'after': '$after',
      'limit': '$limit',
    });
    return RelayPage(
      [
        for (final e in j['events'] as List)
          RelayEvent.fromJson(Map<String, Object?>.from(e as Map)),
      ],
      (j['next'] as num).toInt(),
      more: j['more'] == true,
    );
  }
}

/// Where a device is with a relay: the last event taken in, and events
/// that came before what they depend on (tried again on each pass).
class RelayState {
  final int cursor;
  final List<RelayEvent> pending;
  final DateTime? lastOk;
  final String? lastError;
  final DateTime? errorAt;

  /// When each device was last in contact with the relay.
  final Map<String, DateTime> seen;

  /// What this device received ([Audience.key]) when [cursor] was set:
  /// when it changes, the relay is read again from the start.
  final String? audience;

  const RelayState({
    this.cursor = 0,
    this.pending = const [],
    this.lastOk,
    this.lastError,
    this.errorAt,
    this.seen = const {},
    this.audience,
  });

  RelayState copyWith({
    int? cursor,
    List<RelayEvent>? pending,
    DateTime? lastOk,
    String? lastError,
    DateTime? errorAt,
    Map<String, DateTime>? seen,
    String? audience,
    bool clearError = false,
  }) => RelayState(
    cursor: cursor ?? this.cursor,
    pending: pending ?? this.pending,
    lastOk: lastOk ?? this.lastOk,
    lastError: clearError ? null : lastError ?? this.lastError,
    errorAt: clearError ? null : errorAt ?? this.errorAt,
    seen: seen ?? this.seen,
    audience: audience ?? this.audience,
  );

  Map<String, Object?> toJson() => {
    'cursor': cursor,
    if (pending.isNotEmpty)
      'pending': [
        for (final e in pending) {...e.toJson(), 'n': ?e.n},
      ],
    if (lastOk != null) 'lastOk': lastOk!.millisecondsSinceEpoch,
    'lastError': ?lastError,
    if (errorAt != null) 'errorAt': errorAt!.millisecondsSinceEpoch,
    'seen': {
      for (final e in seen.entries) e.key: e.value.millisecondsSinceEpoch,
    },
    'audience': ?audience,
  };

  factory RelayState.fromJson(Map<String, Object?> j) {
    DateTime? at(Object? v) =>
        v is num ? DateTime.fromMillisecondsSinceEpoch(v.toInt()) : null;
    return RelayState(
      cursor: (j['cursor'] as num?)?.toInt() ?? 0,
      pending: [
        for (final e in j['pending'] as List? ?? const [])
          RelayEvent.fromJson(Map<String, Object?>.from(e as Map)),
      ],
      lastOk: at(j['lastOk']),
      lastError: j['lastError'] as String?,
      errorAt: at(j['errorAt']),
      seen: {
        for (final e in (j['seen'] as Map? ?? const {}).entries)
          e.key as String: at(e.value)!,
      },
      audience: j['audience'] as String?,
    );
  }
}

/// What one pass did.
class RelayReport {
  final int sent;
  final int received;

  const RelayReport(this.sent, this.received);
}

/// Keeps [node] in sync through a relay: a pass now and then, and soon
/// after this device records something.
class RelaySync implements RemoteSource {
  final SyncNode node;
  final RelayApi api;
  final ContentCipher cipher;

  /// The signed list of devices held in the log (see [SyncKeys.members]).
  final Map<String, Object?>? Function() members;

  /// Saves the state after each pass.
  final Future<void> Function(RelayState) save;

  RelayState state;

  /// At most this many pages of events sent or received per pass.
  final int pagesPerPass;

  RelaySync({
    required this.node,
    required this.api,
    required this.cipher,
    required this.members,
    required this.save,
    this.state = const RelayState(),
    this.pagesPerPass = 20,
  });

  Future<RelayReport>? _running;
  Timer? _timer;
  Timer? _soon;
  StreamSubscription<Accepted>? _local;
  Duration _interval = const Duration(minutes: 1);
  bool _stopped = false;

  /// One pass: sends what the relay lacks, then takes in what it received.
  /// Never two at once.
  Future<RelayReport> syncOnce() =>
      _running ??= _pass().whenComplete(() => _running = null);

  Future<RelayReport> _pass() async {
    try {
      final report = await _exchange();
      state = state.copyWith(lastOk: DateTime.now(), clearError: true);
      await save(state);
      return report;
    } on RelayError catch (e) {
      state = state.copyWith(lastError: e.code, errorAt: DateTime.now());
      await save(state);
      rethrow;
    }
  }

  Future<RelayReport> _exchange() async {
    // This device receives other events now (another child's, or every
    // one): what the relay held back is read again.
    final audience = node.audience.key;
    if (state.audience == null) {
      // Before 0.25 the relay held nothing back.
      state = state.copyWith(audience: audience);
    } else if (state.audience != audience) {
      state = RelayState(
        lastOk: state.lastOk,
        seen: state.seen,
        audience: audience,
      );
    }
    final h = await api.heads();
    state = state.copyWith(seen: h.seen);
    final list = members();
    final version = readMembers(list)?.version;
    if (list != null && version != null && version > h.members) {
      await api.postMembers(list);
    }

    // What the relay lacks, oldest first: a device's registration then
    // comes before what it signed.
    var sent = 0;
    var pages = 0;
    for (final page in node.store.pagesFor(h.heads, page: 200)) {
      final out = [
        for (final e in page) RelayEvent(e.origin, e.seq, await cipher.seal(e)),
      ];
      final refused = await api.putEvents(out);
      sent += out.length - refused.length;
      // Out of step with the relay: the next pass starts from its heads.
      if (refused.isNotEmpty || ++pages >= pagesPerPass) break;
    }

    // What the others sent, then what waited for it.
    var received = 0;
    var cursor = state.cursor;
    final waiting = <RelayEvent>[...state.pending];
    for (var i = 0; i < pagesPerPass; i++) {
      final page = await api.getEvents(cursor);
      final batch = <(RelayEvent, SyncEvent)>[];
      for (final r in page.events) {
        if (r.seq <= node.store.lastSeq(r.origin)) continue;
        final e = await cipher.open(r.origin, r.seq, r.body);
        if (e != null) batch.add((r, e));
      }
      received += await _takeIn(batch, waiting);
      cursor = page.next;
      state = state.copyWith(cursor: cursor);
      if (!page.more) break;
    }
    if (waiting.isNotEmpty) {
      final retry = <(RelayEvent, SyncEvent)>[];
      for (final r in waiting.toList()) {
        waiting.remove(r);
        if (r.seq <= node.store.lastSeq(r.origin)) continue;
        final e = await cipher.open(r.origin, r.seq, r.body);
        if (e != null) retry.add((r, e));
      }
      received += await _takeIn(retry, waiting);
    }
    // Kept for later, within reason.
    state = state.copyWith(
      pending: waiting.length > 5000
          ? waiting.sublist(waiting.length - 5000)
          : waiting,
    );
    return RelayReport(sent, received);
  }

  /// Takes in [batch]; what could not be yet goes to [waiting].
  Future<int> _takeIn(
    List<(RelayEvent, SyncEvent)> batch,
    List<RelayEvent> waiting,
  ) async {
    if (batch.isEmpty) return 0;
    final result = await node.ingest([
      for (final (_, e) in batch) e,
    ], source: this);
    final taken = {for (final e in result.accepted) e.id};
    for (final (r, e) in batch) {
      if (!taken.contains(e.id) && e.seq > node.store.lastSeq(e.origin)) {
        waiting.add(r);
      }
    }
    return taken.length;
  }

  /// Passes every [interval], and a few seconds after this device records
  /// something.
  void start({Duration interval = const Duration(minutes: 1)}) {
    _stopped = false;
    _interval = interval;
    _local ??= node.accepted.listen((a) {
      if (a.source is! RemoteSource) poke();
    });
    _schedule(const Duration(seconds: 2));
  }

  /// How often to pass from now on (less often with the screen off, say).
  set interval(Duration interval) {
    _interval = interval;
    _schedule(interval);
  }

  /// A pass in a few seconds.
  void poke([Duration delay = const Duration(seconds: 5)]) {
    if (_stopped) return;
    _soon?.cancel();
    _soon = Timer(delay, _run);
  }

  void _schedule(Duration delay) {
    if (_stopped) return;
    _timer?.cancel();
    _timer = Timer(delay, _run);
  }

  Future<void> _run() async {
    var failed = false;
    try {
      await syncOnce();
    } on Object {
      // Kept in [state]; tried again later.
      failed = true;
    }
    // Not reached (the network waking up…): again soon, then as usual.
    final wait = failed && _retries++ < 3
        ? Duration(seconds: 20 * _retries)
        : _interval;
    if (!failed) _retries = 0;
    // A little jitter, so devices do not all ask at once.
    _schedule(wait + Duration(seconds: Random().nextInt(10)));
  }

  /// Passes failed in a row, retried sooner.
  int _retries = 0;

  Future<void> stop() async {
    _stopped = true;
    _timer?.cancel();
    _soon?.cancel();
    await _local?.cancel();
    _local = null;
    try {
      await _running;
    } on Object {
      // Stopping anyway.
    }
  }
}

/// A relay in memory, with the server's rules, for tests.
class MemoryRelay {
  final families = <String, _MemoryFamily>{};
  final invitations = <String>{};

  RelayApi client(String familyId, String deviceId) =>
      _MemoryRelayApi(this, familyId, deviceOfOrigin(deviceId));
}

class _MemoryFamily {
  final String parentKey;
  Map<String, Object?> members;
  int version;
  Set<String> devices;
  Map<String, String> scopes = {};
  final events = <RelayEvent>[];
  final heads = <String, int>{};
  final seen = <String, DateTime>{};

  _MemoryFamily(this.parentKey, this.members, this.version, this.devices);
}

class _MemoryRelayApi implements RelayApi {
  final MemoryRelay relay;
  final String familyId;
  final String deviceId;

  _MemoryRelayApi(this.relay, this.familyId, this.deviceId);

  _MemoryFamily _family() {
    final f = relay.families[familyId];
    if (f == null) throw const RelayError(401, 'unknown_device');
    if (!f.devices.contains(deviceId)) {
      throw const RelayError(401, 'unknown_device');
    }
    f.seen[deviceId] = DateTime.now();
    return f;
  }

  static Future<Members> _check(
    Map<String, Object?> members,
    String familyId,
    String parentKey,
  ) async {
    final statement = members['statement'] as String;
    if (!await verifySignature(
      utf8.encode('fst-members-v1\n$statement'),
      members['sig'] as String,
      parentKey,
    )) {
      throw const RelayError(403, 'bad_members_signature');
    }
    final j = jsonDecode(statement) as Map;
    if (j['familyId'] != familyId) throw const RelayError(400, 'bad_members');
    return readMembers(members)!;
  }

  /// What the snapshot replaced, forgotten.
  static void _forget(_MemoryFamily f, Map<String, int> floors) {
    f.events.removeWhere((e) => e.seq <= (floors[e.origin] ?? 0));
  }

  @override
  Future<bool> createFamily({
    required String invitation,
    required String parentKey,
    required Map<String, Object?> members,
  }) async {
    if (relay.families.containsKey(familyId)) return false;
    if (!relay.invitations.remove(invitation)) {
      throw const RelayError(403, 'bad_invitation');
    }
    final list = await _check(members, familyId, parentKey);
    if (!list.devices.containsKey(deviceId)) {
      throw const RelayError(401, 'unknown_device');
    }
    relay.families[familyId] = _MemoryFamily(parentKey, members, list.version, {
      ...list.devices.keys,
    })..scopes = list.scopes;
    return true;
  }

  @override
  Future<int> postMembers(Map<String, Object?> members) async {
    final f = _family();
    final list = await _check(members, familyId, f.parentKey);
    if (list.version > f.version) {
      f
        ..members = members
        ..version = list.version
        ..devices = {...list.devices.keys}
        ..scopes = list.scopes;
      _forget(f, list.floors);
    }
    return f.version;
  }

  @override
  Future<RelayHeads> heads() async {
    final f = _family();
    return RelayHeads({...f.heads}, f.version, {...f.seen});
  }

  @override
  Future<List<RelayEvent>> putEvents(List<RelayEvent> events) async {
    final f = _family();
    final refused = <RelayEvent>[];
    final scope = f.scopes[deviceId] ?? '*';
    for (final e in events) {
      // Another child's, from a device of a child: not its to send.
      if (deviceOfOrigin(e.origin) != deviceId &&
          !relayAllows(scope, e.origin, f.scopes)) {
        throw const RelayError(403, 'not_allowed');
      }
      final head = f.heads[e.origin] ?? 0;
      if (e.seq <= head) continue;
      if (!isUsageOrigin(e.origin) && e.seq != head + 1) {
        refused.add(e);
        continue;
      }
      f.events.add(RelayEvent(e.origin, e.seq, e.body, f.events.length + 1));
      f.heads[e.origin] = e.seq;
    }
    return refused;
  }

  @override
  Future<RelayPage> getEvents(int after, {int limit = 500}) async {
    final f = _family();
    final scope = f.scopes[deviceId] ?? '*';
    final rest = f.events.where((e) => e.n! > after).toList();
    final page = rest.take(limit).toList();
    return RelayPage(
      [
        for (final e in page)
          if (relayAllows(scope, e.origin, f.scopes)) e,
      ],
      page.isEmpty ? after : page.last.n!,
      more: rest.length > page.length,
    );
  }
}
