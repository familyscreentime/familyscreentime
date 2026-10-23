import 'dart:async';
import 'dart:io';

import 'package:screentime_sync/screentime_sync.dart';
import 'package:test/test.dart';

Future<NewFamily> family() async => createFamily(
  familyId: 'fam',
  device: await DeviceIdentity.generate('tablet'),
  parentCode: '123456',
  deviceInfo: {'name': 'Tablette', 'role': 'child', 'childId': 'emma'},
);

Future<SyncNode> member(NewFamily f, String id, {String? childId}) async {
  final identity = await DeviceIdentity.generate(id);
  await f.node.emit([
    EventDraft.put(SyncKeys.device(id), {
      'name': id,
      'role': childId == null ? 'parent' : 'child',
      'childId': ?childId,
      'signKey': identity.signing.publicKey,
    }),
  ], parentKey: f.parentKey);
  final node = SyncNode(me: identity, root: f.root);
  await node.ingest(f.node.store.missingFor(const {}, limit: 1 << 30));
  return node;
}

Future<void> until(bool Function() done, {int tries = 200}) async {
  for (var i = 0; i < tries && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
}

void main() {
  final loopback = InternetAddress.loopbackIPv4;

  test('devices of the family find each other and stay in sync', () async {
    final f = await family();
    final phone = await member(f, 'phone');
    final [da, db] = MemoryLanDirectory.network(2);
    final a = LanSync(f.node, da);
    final b = LanSync(phone, db);
    await a.start(address: loopback);
    await b.start(address: loopback);
    addTearDown(a.stop);
    addTearDown(b.stop);
    expect(await a.waitFor('phone'), isTrue);
    expect(await b.waitFor('tablet'), isTrue);
    await phone.emit([
      const EventDraft.put('bonus/1', {'minutes': 15}),
    ], parentKey: f.parentKey);
    await until(() => f.node.replica['bonus/1'] != null);
    expect(f.node.replica['bonus/1'], {'minutes': 15});
    // Both connected at once: each side keeps the same, single session.
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(a.peers.single.connected, isTrue);
    expect(b.peers.single.connected, isTrue);
  });

  test('a device that is not a member is not connected', () async {
    final f = await family();
    final stranger = SyncNode(
      me: await DeviceIdentity.generate('stranger'),
      root: f.root,
    );
    final [da, db] = MemoryLanDirectory.network(2);
    final a = LanSync(f.node, da);
    final b = LanSync(stranger, db);
    await a.start(address: loopback);
    await b.start(address: loopback);
    addTearDown(a.stop);
    addTearDown(b.stop);
    expect(
      await a.waitFor('stranger', timeout: const Duration(seconds: 1)),
      isFalse,
    );
    expect(b.isConnected('tablet'), isFalse);
  });

  test('a new device joins through the network, then syncs', () async {
    final f = await family();
    final [dHost, dJoin] = MemoryLanDirectory.network(2);
    final welcomed = Completer<String>();
    final host = PairingHost(
      node: f.node,
      parentKey: f.parentKey,
      directory: dHost,
      name: 'Tablette',
      confirm: (code, info) async => {'role': 'parent'},
      onWelcomed: welcomed.complete,
    );
    await host.start(address: loopback);
    addTearDown(host.stop);

    final found = await findPairingHosts(dJoin).first;
    expect(found.attributes['n'], 'Tablette');
    final me = await DeviceIdentity.generate('phone');
    final welcome = await joinThrough(
      found,
      me: me,
      info: {'name': 'Téléphone'},
      confirm: (code) async => true,
    );
    expect(await welcomed.future, 'phone');
    final phone = SyncNode(me: me, root: welcome.root);
    await phone.ingest(welcome.events);
    expect(phone.memberKey('phone'), me.signing.publicKey);

    final a = LanSync(f.node, dHost);
    final b = LanSync(phone, dJoin);
    await a.start(address: loopback);
    await b.start(address: loopback);
    addTearDown(a.stop);
    addTearDown(b.stop);
    expect(await b.waitFor('tablet'), isTrue);
  });

  test('the interface\'s origin is its device for the others', () async {
    final f = await family();
    final phone = await member(f, 'phone');
    final ui = SyncNode(
      me: DeviceIdentity('phone~ui', phone.me.signing),
      root: f.root,
      store: phone.store,
    );
    final [da, db] = MemoryLanDirectory.network(2);
    final a = LanSync(f.node, da);
    final b = LanSync(ui, db);
    await a.start(address: loopback);
    await b.start(address: loopback);
    addTearDown(a.stop);
    addTearDown(b.stop);
    expect(await a.waitFor('phone'), isTrue);
  });
}
