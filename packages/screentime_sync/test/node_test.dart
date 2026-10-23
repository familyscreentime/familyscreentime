import 'dart:async';
import 'dart:io';

import 'package:screentime_sync/screentime_sync.dart';
import 'package:test/test.dart';

/// A family created on a tablet, with a second device registered.
class Family {
  final NewFamily created;
  Family(this.created);

  SyncNode get tablet => created.node;
  SigningKey get parentKey => created.parentKey;
  FamilyRoot get root => created.root;

  static Future<Family> create() async => Family(
    await createFamily(
      familyId: 'fam',
      device: await DeviceIdentity.generate('tablet'),
      parentCode: '123456',
      deviceInfo: {'name': 'Tablette', 'role': 'child', 'childId': 'emma'},
    ),
  );

  /// Registers [id] (as a parent would on the tablet) and gives it the log.
  Future<SyncNode> add(String id, {String? childId = 'emma'}) async {
    final identity = await DeviceIdentity.generate(id);
    await tablet.emit([
      EventDraft.put(SyncKeys.device(id), {
        'name': id,
        'role': childId == null ? 'parent' : 'child',
        'childId': ?childId,
        'signKey': identity.signing.publicKey,
      }),
    ], parentKey: parentKey);
    final node = SyncNode(me: identity, root: root);
    await node.ingest(tablet.store.missingFor(const {}, limit: 1 << 30));
    return node;
  }
}

/// Connects [a] and [b] in memory; returns their sessions once caught up.
Future<(SyncSession, SyncSession)> connect(SyncNode a, SyncNode b) async {
  final (ca, cb) = memoryChannelPair();
  final (sa, sb) = await (
    memberHandshake(
      channel: ca,
      me: a.me,
      familyId: a.root.familyId,
      keyOf: a.memberKey,
      initiator: true,
    ),
    memberHandshake(
      channel: cb,
      me: b.me,
      familyId: b.root.familyId,
      keyOf: b.memberKey,
      initiator: false,
    ),
  ).wait;
  final x = SyncSession(a, sa)..start();
  final y = SyncSession(b, sb)..start();
  await Future.wait([x.caughtUp, y.caughtUp]);
  return (x, y);
}

/// Lets queued messages go through.
Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 50));

void main() {
  test('the parent key opens with the code only', () async {
    final f = await Family.create();
    expect(await unlockParentKey(f.tablet, '000000'), isNull);
    final key = await unlockParentKey(f.tablet, '123456');
    expect(key!.publicKey, f.root.parentKey);
    await changeParentCode(f.tablet, key, '654321');
    expect(await unlockParentKey(f.tablet, '123456'), isNull);
    expect(await unlockParentKey(f.tablet, '654321'), isNotNull);
  });

  test('a parent change on one device reaches the other', () async {
    final f = await Family.create();
    final phone = await f.add('phone', childId: null);
    final (x, y) = await connect(f.tablet, phone);
    await phone.emit([
      const EventDraft.put('rule/games', {'quota': 30}),
    ], parentKey: f.parentKey);
    await settle();
    expect(f.tablet.replica['rule/games'], {'quota': 30});
    await f.tablet.emit([
      const EventDraft.patch('rule/games', {'quota': 45}),
    ], parentKey: f.parentKey);
    await settle();
    expect(phone.replica['rule/games'], {'quota': 45});
    await x.close();
    await y.done;
  });

  test('what was missed while apart comes on reconnection', () async {
    final f = await Family.create();
    final phone = await f.add('phone', childId: null);
    await f.tablet.emit([
      const EventDraft.put('rule/a', {'quota': 10}),
      const EventDraft.put('rule/b', {'quota': 20}),
    ], parentKey: f.parentKey);
    await phone.emit([
      const EventDraft.put('rule/c', {'quota': 30}),
    ], parentKey: f.parentKey);
    await connect(f.tablet, phone);
    expect(phone.replica.withPrefix('rule/').length, 3);
    expect(f.tablet.replica.withPrefix('rule/').length, 3);
    expect(phone.store.vector, f.tablet.store.vector);
  });

  test('events are relayed by a device in between', () async {
    final f = await Family.create();
    final phone = await f.add('phone', childId: null);
    final laptop = await f.add('laptop');
    // laptop ↔ tablet ↔ phone: laptop and phone never meet.
    await connect(f.tablet, phone);
    await connect(f.tablet, laptop);
    await laptop.emit([
      EventDraft(EventType.usage, 'usage', {
        'childId': 'emma',
        'deviceId': 'laptop',
        'appId': 'minecraft',
        'start': 1,
        'end': 2,
      }),
    ]);
    await settle();
    expect(phone.store.lastSeq('laptop#usage'), 1);
  });

  test('a child device cannot pass itself off as the parent', () async {
    final f = await Family.create();
    final laptop = await f.add('laptop');
    // Signed with the laptop's key but claiming to be from the parent.
    final forged = await signEvent(
      origin: 'laptop',
      seq: 1,
      hlc: laptop.clock.now(),
      draft: const EventDraft.put('bonus/1', {'minutes': 600}),
      signer: Signer.parent,
      key: laptop.me.signing,
    );
    final r = await f.tablet.ingest([forged]);
    expect(r.accepted, isEmpty);
    expect(f.tablet.replica['bonus/1'], isNull);
  });

  test('a device may only sign its own usage, for its own child', () async {
    final f = await Family.create();
    final laptop = await f.add('laptop');
    final [bonus] = await laptop.emit([
      const EventDraft.put('bonus/1', {'minutes': 600}),
    ]);
    expect((await f.tablet.ingest([bonus])).accepted, isEmpty);

    final other = await f.add('other');
    final [usage] = await other.emit([
      EventDraft(EventType.usage, 'usage', {
        'childId': 'lucas',
        'deviceId': 'other',
        'appId': 'x',
      }),
    ]);
    expect((await f.tablet.ingest([usage])).accepted, isEmpty);
  });

  test('an unknown or removed device is refused', () async {
    final f = await Family.create();
    final stranger = SyncNode(
      me: await DeviceIdentity.generate('stranger'),
      root: f.root,
    );
    final (ca, cb) = memoryChannelPair();
    // The stranger's side fails too once the tablet hangs up.
    final attempt = expectLater(
      memberHandshake(
        channel: ca,
        me: stranger.me,
        familyId: 'fam',
        keyOf: stranger.memberKey,
        initiator: true,
      ),
      throwsA(anything),
    );
    await expectLater(
      memberHandshake(
        channel: cb,
        me: f.tablet.me,
        familyId: 'fam',
        keyOf: f.tablet.memberKey,
        initiator: false,
      ),
      throwsA(isA<HandshakeFailed>()),
    );
    await attempt;

    final laptop = await f.add('laptop');
    await f.tablet.emit([
      EventDraft.patch(SyncKeys.device('laptop'), {'revoked': true}),
    ], parentKey: f.parentKey);
    expect(f.tablet.memberKey('laptop'), isNull);
    final [late] = await laptop.emit([
      EventDraft(EventType.usage, 'usage', {
        'childId': 'emma',
        'deviceId': 'laptop',
      }),
    ]);
    expect((await f.tablet.ingest([late])).accepted, isEmpty);
  });

  test('a tampered event is refused', () async {
    final f = await Family.create();
    final phone = await f.add('phone', childId: null);
    final [e] = await phone.emit([
      const EventDraft.put('bonus/1', {'minutes': 10}),
    ], parentKey: f.parentKey);
    final tampered = SyncEvent.fromJson({
      ...e.toJson(),
      'd': {'minutes': 600},
    });
    expect((await f.tablet.ingest([tampered])).accepted, isEmpty);
    expect((await f.tablet.ingest([e])).accepted, hasLength(1));
  });

  test('a node reopens from its file as it was', () async {
    final f = await Family.create();
    final dir = await Directory.systemTemp.createTemp('fst-node');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/family.db';
    final copy = SyncNode(
      me: f.tablet.me,
      root: f.root,
      store: SqliteSyncStore.open(path),
    );
    await copy.ingest(f.tablet.store.missingFor(const {}, limit: 1 << 30));
    await copy.emit([
      const EventDraft.put('rule/x', {'quota': 5}),
    ], parentKey: f.parentKey);
    final reopened = SyncNode(
      me: f.tablet.me,
      root: f.root,
      store: SqliteSyncStore.open(path),
    );
    expect(reopened.replica.entities, copy.replica.entities);
    expect(reopened.store.vector, copy.store.vector);
    expect(reopened.clock.now() > copy.store.latestHlc!, isTrue);
    await copy.close();
    await reopened.close();
  });

  test('interface and background service share the file', () async {
    final f = await Family.create();
    final dir = await Directory.systemTemp.createTemp('fst-shared');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/family.db';
    // The background service writes as `tablet`, the interface as
    // `tablet~ui`; both open the same file.
    final service = SyncNode(
      me: f.tablet.me,
      root: f.root,
      store: SqliteSyncStore.open(path),
    );
    await service.ingest(f.tablet.store.missingFor(const {}, limit: 1 << 30));
    final ui = SyncNode(
      me: DeviceIdentity('tablet~ui', f.tablet.me.signing),
      root: f.root,
      store: SqliteSyncStore.open(path),
    );
    expect(ui.replica.entities, service.replica.entities);
    await ui.emit([
      const EventDraft.put('rule/x', {'quota': 5}),
    ], parentKey: f.parentKey);
    // Seen at once by the service, and passed on to its peers.
    expect(service.replica['rule/x'], {'quota': 5});
    final passed = <SyncEvent>[];
    service.accepted.listen((a) => passed.addAll(a.events));
    expect(await service.readOthers(), hasLength(1));
    expect(passed.single.key, 'rule/x');
    // The interface's key is the tablet's: its use of apps is the tablet's.
    final [usage] = await service.emit([
      EventDraft(EventType.usage, 'usage', {
        'childId': 'emma',
        'deviceId': 'tablet',
      }),
    ]);
    expect(usage.origin, 'tablet#usage');
    expect((await ui.readOthers()).single.id, usage.id);
    expect(await service.readOthers(), isEmpty);
    await ui.close();
    await service.close();
  });

  test('use of apps only under a usage origin', () async {
    final f = await Family.create();
    final laptop = await f.add('laptop');
    final forged = await signEvent(
      origin: 'laptop',
      seq: 1,
      hlc: laptop.clock.now(),
      draft: EventDraft(EventType.usage, 'usage', {
        'childId': 'emma',
        'deviceId': 'laptop',
      }),
      signer: Signer.device,
      key: laptop.me.signing,
    );
    expect((await f.tablet.ingest([forged])).accepted, isEmpty);
  });

  group('pairing', () {
    test(
      'both screens show the same code; the new device gets the log',
      () async {
        final f = await Family.create();
        final newcomer = await DeviceIdentity.generate('phone');
        final (ca, cb) = memoryChannelPair();
        String? hostCode;
        String? joinCode;
        final welcomed = welcomeDevice(
          channel: cb,
          node: f.tablet,
          parentKey: f.parentKey,
          confirm: (code, info) async {
            hostCode = code;
            expect(info['name'], 'Téléphone de papa');
            return {'role': 'parent'};
          },
        );
        final welcome = await joinFamily(
          channel: ca,
          me: newcomer,
          info: {'name': 'Téléphone de papa', 'platform': 'android'},
          confirm: (code) async {
            joinCode = code;
            return true;
          },
        );
        expect(await welcomed, 'phone');
        expect(joinCode, hasLength(6));
        expect(joinCode, hostCode);
        expect(welcome.root.parentKey, f.root.parentKey);

        final phone = SyncNode(me: newcomer, root: welcome.root);
        await phone.ingest(welcome.events);
        expect(phone.replica[SyncKeys.device('phone')]?['role'], 'parent');
        expect(phone.memberKey('phone'), newcomer.signing.publicKey);
        // The parent code works there too.
        expect(await unlockParentKey(phone, '123456'), isNotNull);
        // And it is now a member for the tablet.
        await connect(f.tablet, phone);
      },
    );

    test('refused on either screen: nothing is registered', () async {
      final f = await Family.create();
      final (ca, cb) = memoryChannelPair();
      final welcomed = welcomeDevice(
        channel: cb,
        node: f.tablet,
        parentKey: f.parentKey,
        confirm: (code, info) async => null,
      );
      await expectLater(
        joinFamily(
          channel: ca,
          me: await DeviceIdentity.generate('phone'),
          info: const {},
          confirm: (code) async => true,
        ),
        throwsA(isA<PairingRefused>()),
      );
      expect(await welcomed, isNull);
      expect(f.tablet.memberKey('phone'), isNull);
    });

    test('a broken commitment stops the pairing', () async {
      final (ca, cb) = memoryChannelPair();
      final host = pairingHandshake(
        channel: cb,
        deviceId: 'tablet',
        joining: false,
      );
      // A joiner that commits to one key and reveals another.
      final reader = FrameReader(ca.frames);
      final eph = await AgreementKey.generate();
      final other = await AgreementKey.generate();
      ca.send(
        canonicalBytes({
          't': 'p1',
          'd': 'x',
          'c': b64(await sha256Bytes(unb64(eph.publicKey))),
        }),
      );
      await reader.next();
      ca.send(canonicalBytes({'t': 'p3', 'e': other.publicKey}));
      await expectLater(host, throwsA(isA<HandshakeFailed>()));
    });
  });

  test('over a WebSocket on the local network', () async {
    final f = await Family.create();
    final phone = await f.add('phone', childId: null);
    final serverSessions = <SyncSession>[];
    final server = await serveFrames(
      address: InternetAddress.loopbackIPv4,
      onChannel: (channel) async {
        final secure = await memberHandshake(
          channel: channel,
          me: f.tablet.me,
          familyId: 'fam',
          keyOf: f.tablet.memberKey,
          initiator: false,
        );
        serverSessions.add(SyncSession(f.tablet, secure)..start());
      },
    );
    addTearDown(() => server.close(force: true));
    final channel = await connectFrames('127.0.0.1', server.port);
    final secure = await memberHandshake(
      channel: channel,
      me: phone.me,
      familyId: 'fam',
      keyOf: phone.memberKey,
      initiator: true,
    );
    final session = SyncSession(phone, secure)..start();
    await session.caughtUp;
    await phone.emit([
      const EventDraft.put('bonus/1', {'minutes': 15}),
    ], parentKey: f.parentKey);
    await settle();
    expect(f.tablet.replica['bonus/1'], {'minutes': 15});
    await session.close();
  });
}
