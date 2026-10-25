import 'package:screentime_sync/screentime_sync.dart';
import 'package:test/test.dart';

import 'node_test.dart' show connect, settle;

/// Rules and use of apps concern one child; the rest the whole family.
/// With [cut] false, as before 0.25: everything under the family's origins.
class ScopedPolicy extends UsageOnlyPolicy {
  final bool cut;

  const ScopedPolicy({this.cut = true});

  @override
  String? scopeOf(
    String key,
    Map<String, Object?> value,
    MergedState replica,
  ) => cut && (key.startsWith('rule/') || key == 'usage')
      ? value['childId'] as String?
      : null;
}

/// A parent's phone, and a tablet for Emma and one for Léo.
class Family {
  final SyncNode phone;
  final SigningKey key;
  final Map<String, DeviceIdentity> ids;
  SyncNode emma;
  SyncNode leo;

  Family(this.phone, this.key, this.ids, this.emma, this.leo);

  static Future<Family> create(
    SyncStore Function() store, {
    bool cut = true,
    String familyId = 'fam',
  }) async {
    final policy = ScopedPolicy(cut: cut);
    final created = await createFamily(
      familyId: familyId,
      device: await DeviceIdentity.generate('phone'),
      parentCode: '123456',
      deviceInfo: {'name': 'Papa', 'role': 'parent'},
      store: store(),
      policy: policy,
    );
    final phone = created.node;
    final ids = <String, DeviceIdentity>{};
    final nodes = <SyncNode>[];
    for (final (id, child) in [('tabE', 'emma'), ('tabL', 'leo')]) {
      final identity = ids[id] = await DeviceIdentity.generate(id);
      await phone.emit([
        EventDraft.put(SyncKeys.device(id), {
          'name': id,
          'role': 'child',
          'childId': child,
          'signKey': identity.signing.publicKey,
        }),
      ], parentKey: created.parentKey);
      final node = SyncNode(
        me: identity,
        root: created.root,
        store: store(),
        policy: policy,
      );
      await node.ingest(
        phone.store.missingFor(
          const {},
          limit: 1 << 30,
          to: Audience.of(phone.replica[SyncKeys.device(id)]),
        ),
      );
      nodes.add(node);
    }
    return Family(phone, created.parentKey, ids, nodes[0], nodes[1]);
  }

  /// The same devices with the app of 0.25 (their logs kept).
  void update() {
    SyncNode again(SyncNode n) => SyncNode(
      me: n.me,
      root: n.root,
      store: n.store,
      policy: const ScopedPolicy(),
    );
    emma = again(emma);
    leo = again(leo);
  }
}

/// Records [drafts] on [node] as the app did before 0.25: under the
/// device's origin, whatever they concern.
Future<void> legacyEmit(
  SyncNode node,
  List<EventDraft> drafts, {
  SigningKey? parentKey,
}) async {
  var hlc = Hlc(DateTime.now().millisecondsSinceEpoch, 0, node.deviceId);
  for (final d in drafts) {
    final origin = d.type == EventType.usage
        ? usageOrigin(node.deviceId)
        : node.deviceId;
    hlc = Hlc(hlc.millis, hlc.counter + 1, hlc.node);
    final e = await signEvent(
      origin: origin,
      seq: node.store.lastSeq(origin) + 1,
      hlc: hlc,
      draft: d,
      signer: parentKey == null ? Signer.device : Signer.parent,
      key: parentKey ?? node.me.signing,
    );
    node.store.add(e);
  }
}

/// What [to] lacks of [from]'s, as on the network.
Future<void> pass(SyncNode from, SyncNode to) async {
  await to.ingest(
    from.store.missingFor(
      to.store.vector,
      limit: 1 << 30,
      to: Audience.of(from.replica[SyncKeys.device(to.deviceId)]),
    ),
  );
}

Map<String, Object?> usage(String device, String child, int start) => {
  'deviceId': device,
  'childId': child,
  'appId': 'game',
  'start': start,
  'end': start + 60000,
};

void main() {
  for (final (name, store) in [
    ('memory', MemorySyncStore.new),
    ('SQLite', SqliteSyncStore.inMemory),
  ]) {
    group('($name)', () {
      test('each child receives the family\'s events and their own', () async {
        final f = await Family.create(store);
        await f.phone.emit([
          const EventDraft.put('rule/a', {'childId': 'emma', 'quota': 60}),
          const EventDraft.put('rule/b', {'childId': 'leo', 'quota': 30}),
          const EventDraft.put('family', {'weekStart': 1}),
        ], parentKey: f.key);
        expect(f.phone.store.vector.keys, contains('phone@emma'));
        final (p1, e1) = await connect(f.phone, f.emma);
        final (p2, l1) = await connect(f.phone, f.leo);
        await settle();
        expect(f.emma.replica['rule/a'], isNotNull);
        expect(f.emma.replica['rule/b'], isNull);
        expect(f.emma.replica['family'], isNotNull);
        expect(f.leo.replica['rule/a'], isNull);
        expect(f.leo.replica['rule/b'], isNotNull);

        // Emma's use goes to the parents, not to her brother.
        await f.emma.emit([
          EventDraft(EventType.usage, 'usage', usage('tabE', 'emma', 0)),
        ]);
        await settle();
        expect(f.phone.store.vector['tabE@emma#usage'], 1);
        expect(f.leo.store.vector.containsKey('tabE@emma#usage'), isFalse);

        // Directly between the children's tablets: only the family's.
        final (e2, l2) = await connect(f.emma, f.leo);
        await settle();
        expect(f.leo.replica['rule/a'], isNull);
        expect(f.leo.store.vector.containsKey('tabE@emma#usage'), isFalse);

        // A rule given to the other child leaves the first one's devices.
        await f.phone.emit([
          const EventDraft.patch('rule/a', {'childId': 'leo'}),
        ], parentKey: f.key);
        await settle();
        expect(f.emma.replica['rule/a'], isNull);
        expect(f.leo.replica['rule/a'], {'childId': 'leo', 'quota': 60});
        expect(f.phone.replica['rule/a'], {'childId': 'leo', 'quota': 60});
        for (final s in [p1, e1, p2, l1, e2, l2]) {
          await s.close();
        }
      });

      test('a family from before is cut per child once', () async {
        final f = await Family.create(store, cut: false);
        await legacyEmit(f.phone, [
          const EventDraft.put('rule/a', {'childId': 'emma', 'quota': 60}),
          const EventDraft.put('rule/b', {'childId': 'leo', 'quota': 30}),
          const EventDraft.put('family', {'weekStart': 1}),
        ], parentKey: f.key);
        await legacyEmit(f.emma, [
          EventDraft(EventType.usage, 'usage', usage('tabE', 'emma', 0)),
        ]);
        for (final (a, b) in [
          (f.phone, f.emma),
          (f.phone, f.leo),
          (f.emma, f.phone),
          (f.phone, f.leo),
        ]) {
          // As the app sent them before 0.25: everything.
          await b.ingest(a.store.missingFor(b.store.vector, limit: 1 << 30));
        }
        // As before: everything everywhere.
        expect(f.leo.replica['rule/a'], isNotNull);
        expect(f.leo.store.vector['tabE#usage'], 1);

        f.update();
        // Changed on Emma's tablet (in parent mode); the phone does not
        // know yet.
        await f.emma.emit([
          const EventDraft.patch('rule/a', {'quota': 90}),
        ], parentKey: f.key);
        final phone = SyncNode(
          me: f.phone.me,
          root: f.phone.root,
          store: f.phone.store,
          policy: const ScopedPolicy(),
        );
        expect(await phone.tidy(), isFalse);
        expect(await phone.rebase(f.key), isTrue);
        expect(await phone.rebase(f.key), isFalse);
        final floors = phone.store.floors;
        expect(floors['phone'], greaterThan(0));

        // Léo's tablet takes the snapshot, then drops the rest.
        await pass(phone, f.leo);
        expect(f.leo.store.floors, floors);
        expect(await f.leo.tidy(), isTrue);
        expect(await f.leo.tidy(), isFalse);
        expect(f.leo.replica['rule/a'], isNull);
        expect(f.leo.replica['rule/b'], {'childId': 'leo', 'quota': 30});
        expect(f.leo.replica['family'], {'weekStart': 1});
        expect(f.leo.replica[SyncKeys.device('tabE')], isNotNull);
        expect([
          for (final e in f.leo.store.missingFor(const {}, limit: 1 << 30))
            if (e.key.startsWith('rule/') || e.type == EventType.usage)
              e.data['childId'],
        ], everyElement('leo'));
        expect(f.leo.store.lastEvents('tabE#usage'), isEmpty);
        // Nothing from before the snapshot any more.
        expect(f.leo.store.lastEvents('phone'), isEmpty);
        expect(f.leo.store.lastSeq('phone'), floors['phone']);

        // The parent's phone keeps everything that matters.
        expect(await phone.tidy(), isTrue);
        expect(phone.replica['rule/a'], isNotNull);
        expect(phone.replica['rule/b'], isNotNull);
        expect(phone.store.lastEvents('tabE#usage'), hasLength(1));

        // Emma's tablet, still behind, catches up with the phone: the
        // snapshot does not undo what it changed since.
        await pass(phone, f.emma);
        expect(await f.emma.tidy(), isTrue);
        expect(f.emma.replica['rule/a'], {'childId': 'emma', 'quota': 90});
        await pass(f.emma, phone);
        expect(phone.replica['rule/a'], {'childId': 'emma', 'quota': 90});
        expect(f.emma.replica['rule/b'], isNull);
        expect(f.emma.store.lastEvents('tabE#usage'), hasLength(1));

        // A tablet linked now gets nothing from before, nor Léo's.
        final identity = await DeviceIdentity.generate('tabE2');
        await phone.emit([
          EventDraft.put(SyncKeys.device('tabE2'), {
            'role': 'child',
            'childId': 'emma',
            'signKey': identity.signing.publicKey,
          }),
        ], parentKey: f.key);
        final emma2 = SyncNode(
          me: identity,
          root: phone.root,
          store: store(),
          policy: const ScopedPolicy(),
        );
        await pass(phone, emma2);
        expect(emma2.replica['rule/a'], isNotNull);
        expect(emma2.replica['rule/b'], isNull);
        expect(emma2.store.lastEvents('phone'), isEmpty);
        expect(emma2.store.vector['phone'], floors['phone']);
        expect(emma2.store.vector['phone@'], phone.store.lastSeq('phone@'));

        // Changes go on as usual.
        await phone.emit([
          const EventDraft.patch('rule/b', {'quota': 45}),
        ], parentKey: f.key);
        await pass(phone, f.leo);
        await pass(phone, emma2);
        expect(f.leo.replica['rule/b']?['quota'], 45);
        expect(emma2.store.vector.containsKey('phone@leo'), isFalse);
      });

      test('a device given to another child drops the first one\'s', () async {
        final f = await Family.create(store);
        await f.phone.startScoped(f.key);
        await f.phone.emit([
          const EventDraft.put('rule/a', {'childId': 'emma', 'quota': 60}),
          const EventDraft.put('rule/b', {'childId': 'leo', 'quota': 30}),
        ], parentKey: f.key);
        await pass(f.phone, f.emma);
        expect(await f.emma.tidy(), isTrue);
        expect(f.emma.replica['rule/a'], isNotNull);
        await f.phone.emit([
          const EventDraft.patch('device/tabE', {'childId': 'leo'}),
        ], parentKey: f.key);
        await pass(f.phone, f.emma);
        expect(await f.emma.tidy(), isTrue);
        expect(f.emma.replica['rule/a'], isNull);
        expect(f.emma.replica['rule/b'], isNotNull);
      });
    });
  }
}

/// Each child's devices get theirs through a relay ([client] for a node),
/// and what the snapshot replaced is forgotten there. [register]: the
/// family's first registration, with its list of devices.
Future<void> relayKeepsChildrenApart(
  RelayApi Function(SyncNode node) client,
  Future<void> Function(
    RelayApi api,
    Map<String, Object?> members,
    String parentKey,
  )
  register, {
  String familyId = 'fam',
}) async {
  final f = await Family.create(
    MemorySyncStore.new,
    cut: false,
    familyId: familyId,
  );
  await legacyEmit(f.phone, [
    const EventDraft.put('rule/a', {'childId': 'emma', 'quota': 60}),
    const EventDraft.put('rule/b', {'childId': 'leo', 'quota': 30}),
  ], parentKey: f.key);
  var version = 1;
  Future<Map<String, Object?>> sign(SyncNode phone) => signMembers(
    familyId: familyId,
    version: version++,
    devices: memberKeys(phone),
    scopes: memberScopes(phone),
    floors: phone.store.floors,
    parentKey: f.key,
  );
  var members = await sign(f.phone);
  final phoneApi = client(f.phone);
  await register(phoneApi, members, f.phone.root.parentKey);
  RelaySync sync(SyncNode node, RelayApi api) => RelaySync(
    node: node,
    api: api,
    cipher: ContentCipher(unb64(node.root.contentKey!), familyId),
    members: () => members,
    save: (_) async {},
  );
  final phone = sync(f.phone, phoneApi);
  await phone.syncOnce();
  final leoSync = sync(f.leo, client(f.leo));
  await leoSync.syncOnce();
  // From before: everything.
  expect(f.leo.replica['rule/a'], isNotNull);

  f.update();
  final node = SyncNode(
    me: f.phone.me,
    root: f.phone.root,
    store: f.phone.store,
    policy: const ScopedPolicy(),
  );
  await node.rebase(f.key);
  members = await sign(node);
  await sync(node, phoneApi).syncOnce();
  await sync(f.leo, client(f.leo)).syncOnce();
  expect(await f.leo.tidy(), isTrue);
  expect(f.leo.replica['rule/a'], isNull);
  expect(f.leo.replica['rule/b'], isNotNull);

  // A tablet for Léo linked now: nothing from before, nothing of Emma's.
  final identity = await DeviceIdentity.generate('tabL2');
  await node.emit([
    EventDraft.put(SyncKeys.device('tabL2'), {
      'role': 'child',
      'childId': 'leo',
      'signKey': identity.signing.publicKey,
    }),
  ], parentKey: f.key);
  members = await sign(node);
  await sync(node, phoneApi).syncOnce();
  // Its registration first (on the network, when it is linked).
  final leo2 = SyncNode(
    me: identity,
    root: node.root,
    policy: const ScopedPolicy(),
  );
  await leo2.ingest([
    for (final e in node.store.missingFor(const {}, limit: 1 << 30))
      if (e.key == SyncKeys.device('tabL2')) e,
  ]);
  final leo2Api = client(leo2);
  final received = <RelayEvent>[];
  var cursor = 0;
  while (true) {
    final page = await leo2Api.getEvents(cursor);
    received.addAll(page.events);
    cursor = page.next;
    if (!page.more) break;
  }
  expect(received.map((e) => e.origin), isNot(contains('phone')));
  expect(received.map((e) => e.origin), isNot(contains('phone@emma')));
  await sync(leo2, leo2Api).syncOnce();
  expect(leo2.replica['rule/b'], isNotNull);
  expect(leo2.replica['rule/a'], isNull);
  expect(leo2.store.vector['phone'], node.store.floors['phone']);

  // Emma's tablet may not send what is Léo's.
  final emmaApi = client(f.emma);
  final leoOrigin = node.store.vector.keys.firstWhere(
    (o) => scopeOfOrigin(o) == 'leo',
  );
  final leoEvent = node.store.lastEvents(leoOrigin).first;
  await expectLater(
    emmaApi.putEvents([RelayEvent(leoEvent.origin, leoEvent.seq + 100, 'x')]),
    throwsA(isA<RelayError>().having((e) => e.code, 'code', 'not_allowed')),
  );
}
