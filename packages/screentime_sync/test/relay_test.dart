import 'dart:convert';
import 'dart:io';

import 'package:screentime_sync/screentime_sync.dart';
import 'package:test/test.dart';

import 'node_test.dart' show Family;
import 'scope_test.dart' show relayKeepsChildrenApart;

/// The signed list of [node]'s family's devices, as of now.
Future<Map<String, Object?>> membersOf(
  SyncNode node,
  SigningKey parentKey, {
  int? version,
}) => signMembers(
  familyId: node.root.familyId,
  version: version ?? DateTime.now().millisecondsSinceEpoch,
  devices: memberKeys(node),
  parentKey: parentKey,
);

RelaySync relaySync(
  SyncNode node,
  RelayApi api,
  Map<String, Object?>? Function() members,
) => RelaySync(
  node: node,
  api: api,
  cipher: ContentCipher(unb64(node.root.contentKey!), node.root.familyId),
  members: members,
  save: (_) async {},
);

/// Both directions, through [a] then [b].
Future<void> exchange(RelaySync a, RelaySync b) async {
  await a.syncOnce();
  await b.syncOnce();
  await a.syncOnce();
}

void main() {
  test('events cross the relay encrypted, both ways', () async {
    final f = await Family.create();
    final phone = await f.add('phone');
    final relay = MemoryRelay()..invitations.add('INVITE');
    var members = await membersOf(f.tablet, f.parentKey);
    expect(
      await relay
          .client('fam', 'tablet')
          .createFamily(
            invitation: 'INVITE',
            parentKey: f.root.parentKey,
            members: members,
          ),
      isTrue,
    );
    final a = relaySync(f.tablet, relay.client('fam', 'tablet'), () => members);
    final b = relaySync(phone, relay.client('fam', 'phone'), () => members);

    await f.tablet.emit([
      EventDraft.put('rule/r', {'childId': 'emma', 'quota': 30}),
    ], parentKey: f.parentKey);
    await phone.emit([
      EventDraft(EventType.usage, 'usage', {
        'childId': 'emma',
        'deviceId': 'phone',
        'appId': 'minecraft',
        'start': 1,
        'end': 2,
      }),
    ]);
    await exchange(a, b);
    expect(phone.replica['rule/r']?['quota'], 30);
    expect(f.tablet.store.lastSeq(usageOrigin('phone@')), 1);
    // The relay cannot read them.
    final bodies = relay.families['fam']!.events.map((e) => e.body).join();
    expect(bodies, isNot(contains('emma')));
    expect(bodies, isNot(contains('minecraft')));
    // Nothing more to send or take the next time.
    final again = await b.syncOnce();
    expect((again.sent, again.received), (0, 0));
    expect(b.state.seen.keys, containsAll(['tablet', 'phone']));

    // A device removed by the parent is let in no more.
    await f.tablet.emit([
      EventDraft.patch(SyncKeys.device('phone'), {'revoked': true}),
    ], parentKey: f.parentKey);
    members = await membersOf(
      f.tablet,
      f.parentKey,
      version: DateTime.now().millisecondsSinceEpoch + 1,
    );
    await a.syncOnce();
    expect(
      () => relay.client('fam', 'phone').heads(),
      throwsA(isA<RelayError>()),
    );
  });

  test('a new device\'s events wait for its registration', () async {
    final f = await Family.create();
    final phone = await f.add('phone');
    final relay = MemoryRelay()..invitations.add('INVITE');
    // The tablet registered a laptop, and has not been in touch since.
    final laptop = await f.add('laptop');
    final members = await membersOf(f.tablet, f.parentKey);
    await relay
        .client('fam', 'tablet')
        .createFamily(
          invitation: 'INVITE',
          parentKey: f.root.parentKey,
          members: members,
        );
    await laptop.emit([
      EventDraft(EventType.usage, 'usage', {
        'childId': 'emma',
        'deviceId': 'laptop',
        'appId': 'game',
        'start': 1,
        'end': 2,
      }),
    ]);
    // Only its own event reaches the relay first.
    final cipher = ContentCipher(unb64(f.root.contentKey!), 'fam');
    final own = laptop.store.missingFor({
      for (final o in laptop.store.vector.keys)
        if (!o.startsWith('laptop')) o: laptop.store.lastSeq(o),
    });
    await relay.client('fam', 'laptop').putEvents([
      for (final e in own) RelayEvent(e.origin, e.seq, await cipher.seal(e)),
    ]);
    final b = relaySync(phone, relay.client('fam', 'phone'), () => members);
    await b.syncOnce();
    expect(phone.store.lastSeq(usageOrigin('laptop@')), 0);
    expect(b.state.pending, hasLength(1));
    // Once the tablet has sent the registration, it is taken in.
    final a = relaySync(f.tablet, relay.client('fam', 'tablet'), () => members);
    await a.syncOnce();
    await b.syncOnce();
    expect(phone.store.lastSeq(usageOrigin('laptop@')), 1);
    expect(b.state.pending, isEmpty);
  });

  test('each child\'s devices get theirs through the relay', () async {
    final relay = MemoryRelay()..invitations.add('INV');
    await relayKeepsChildrenApart(
      (node) => relay.client(node.root.familyId, node.deviceId),
      (api, members, parentKey) => api.createFamily(
        invitation: 'INV',
        parentKey: parentKey,
        members: members,
      ),
    );
  });

  test('a body from another family or place does not open', () async {
    final f = await Family.create();
    final e = f.tablet.store.missingFor(const {}).first;
    final key = unb64(f.root.contentKey!);
    final sealed = await ContentCipher(key, 'fam').seal(e);
    expect(
      await ContentCipher(key, 'fam').open(e.origin, e.seq, sealed),
      isNotNull,
    );
    expect(
      await ContentCipher(key, 'other').open(e.origin, e.seq, sealed),
      isNull,
    );
    expect(
      await ContentCipher(key, 'fam').open(e.origin, e.seq + 1, sealed),
      isNull,
    );
  });

  group('the PHP server', () {
    late Directory dir;
    late Process php;
    late Uri endpoint;
    late String invitation;
    final source = Directory('../../server');

    setUpAll(() async {
      dir = await Directory.systemTemp.createTemp('fst-relay');
      await Process.run('cp', ['-r', '${source.path}/.', dir.path]);
      // FST_TEST_MYSQL=host:db:user:password tests MySQL instead of SQLite.
      final mysql = Platform.environment['FST_TEST_MYSQL']?.split(':');
      final install = await Process.run('php', [
        'lib/cli.php',
        if (mysql == null) ...[
          'install-sqlite',
        ] else ...[
          'install-mysql',
          ...mysql,
        ],
        'test-password-12',
      ], workingDirectory: dir.path);
      expect(install.stdout, contains('installed'));
      final invite = await Process.run('php', [
        'lib/cli.php',
        'invite',
        'test',
      ], workingDirectory: dir.path);
      invitation = (invite.stdout as String).trim();
      final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = socket.port;
      await socket.close();
      php = await Process.start('php', [
        '-S',
        '127.0.0.1:$port',
      ], workingDirectory: dir.path);
      endpoint = Uri.parse('http://127.0.0.1:$port/api.php');
      for (var i = 0; i < 50; i++) {
        try {
          final c = HttpClient();
          final r = await (await c.getUrl(
            endpoint.replace(query: 'r=info'),
          )).close();
          await r.drain<void>();
          c.close();
          break;
        } on Object {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }
    });

    tearDownAll(() async {
      php.kill();
      await dir.delete(recursive: true);
    });

    test('registers, then relays both ways', () async {
      final f = await Family.create();
      final phone = await f.add('phone');
      final members = await membersOf(f.tablet, f.parentKey);
      final apiA = HttpRelayApi(endpoint, 'fam', f.tablet.me);
      final apiB = HttpRelayApi(endpoint, 'fam', phone.me);
      // Unknown until registered.
      await expectLater(apiB.heads(), throwsA(isA<RelayError>()));
      await expectLater(
        apiA.createFamily(
          invitation: 'WRONG-CODE',
          parentKey: f.root.parentKey,
          members: members,
        ),
        throwsA(
          isA<RelayError>().having((e) => e.code, 'code', 'bad_invitation'),
        ),
      );
      expect(
        await apiA.createFamily(
          invitation: invitation,
          parentKey: f.root.parentKey,
          members: members,
        ),
        isTrue,
      );
      final a = relaySync(f.tablet, apiA, () => members);
      final b = relaySync(phone, apiB, () => members);
      await f.tablet.emit([
        EventDraft.put('rule/r', {'childId': 'emma', 'quota': 45}),
      ], parentKey: f.parentKey);
      for (var i = 0; i < 3; i++) {
        await phone.emit([
          EventDraft(EventType.usage, 'usage', {
            'childId': 'emma',
            'deviceId': 'phone',
            'appId': 'app$i',
            'start': i,
            'end': i + 1,
          }),
        ]);
      }
      await exchange(a, b);
      expect(phone.replica['rule/r']?['quota'], 45);
      expect(f.tablet.store.lastSeq(usageOrigin('phone@')), 3);
      // The invitation served once.
      final other = await Family.create();
      await expectLater(
        HttpRelayApi(endpoint, 'other', other.tablet.me).createFamily(
          invitation: invitation,
          parentKey: other.root.parentKey,
          members: await membersOf(other.tablet, other.parentKey),
        ),
        throwsA(isA<RelayError>()),
      );
      // A request signed with another key is refused.
      final impostor = HttpRelayApi(
        endpoint,
        'fam',
        await DeviceIdentity.generate('phone'),
      );
      await expectLater(impostor.heads(), throwsA(isA<RelayError>()));
      apiA.close();
      apiB.close();
      impostor.close();
    });

    test('keeps each child\'s events apart', () async {
      final invite = await Process.run('php', [
        'lib/cli.php',
        'invite',
        'scopes',
      ], workingDirectory: dir.path);
      final code = (invite.stdout as String).trim();
      final apis = <HttpRelayApi>[];
      await relayKeepsChildrenApart(
        (node) {
          final api = HttpRelayApi(endpoint, 'famscopes', node.me);
          apis.add(api);
          return api;
        },
        (api, members, parentKey) => api.createFamily(
          invitation: code,
          parentKey: parentKey,
          members: members,
        ),
        familyId: 'famscopes',
      );
      for (final api in apis) {
        api.close();
      }
    });

    test('the API checks the signature of the device list', () async {
      final f = await Family.create();
      final members = await membersOf(f.tablet, f.parentKey);
      final forged = {
        ...members,
        'statement': (members['statement'] as String).replaceFirst(
          'tablet',
          'tablex',
        ),
      };
      final api = HttpRelayApi(endpoint, 'fam2', f.tablet.me);
      await expectLater(
        api.createFamily(
          invitation: 'X',
          parentKey: f.root.parentKey,
          members: forged,
        ),
        throwsA(isA<RelayError>()),
      );
      api.close();
      expect(jsonDecode(members['statement'] as String)['familyId'], 'fam');
    });
  }, skip: _phpReady() ? null : 'no php with sodium and SQLite');
}

/// PHP with sodium and SQLite, to run the server.
bool _phpReady() {
  try {
    return Process.runSync('php', [
          '-r',
          "exit(function_exists('sodium_crypto_sign_verify_detached') && extension_loaded('pdo_sqlite') ? 0 : 1);",
        ]).exitCode ==
        0;
  } on Object {
    return false;
  }
}
