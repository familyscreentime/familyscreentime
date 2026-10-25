/// The app's side of the family log: creating the family, recording the
/// changes made here, signed by the parent key in parent mode, and the use
/// of apps recorded by the monitor.
///
/// On a child's device two processes share the log folder: the interface
/// writes its events under `<device>~ui`, the monitor (always running)
/// under `<device>`, and each reads the other's file.
library;

import 'dart:convert';
import 'dart:io';

import 'package:screentime_engine/screentime_engine.dart';
import 'package:screentime_sync/screentime_sync.dart';

import '../family.dart';
import '../platform.dart';
import '../store.dart';
import 'family_entities.dart';

/// What a device may sign with its own key, outside parent mode: its use
/// of apps, the limits the child sets for themselves and their record, and
/// the child's voluntary breaks.
class FamilySyncPolicy extends SyncPolicy {
  const FamilySyncPolicy();

  @override
  bool deviceMay(
    SyncEvent e,
    Map<String, Object?> device,
    MergedState replica,
  ) {
    // What it has received from the others: its own receipts only.
    if (e.key.startsWith('seen/')) {
      return e.key == 'seen/${deviceOfOrigin(e.origin)}' &&
          (e.type == EventType.put || e.type == EventType.patch);
    }
    final child = device['childId'];
    if (child == null) return false;
    if (e.type == EventType.usage) {
      return e.data['deviceId'] == deviceOfOrigin(e.origin) &&
          e.data['childId'] == child &&
          e.data['injectedTarget'] == null;
    }
    bool own(Map<String, Object?>? item, {String flag = 'setByChild'}) =>
        item != null && item[flag] == true && item['childId'] == child;
    if (e.key.startsWith(FamilyKeys.rule)) {
      final current = replica[e.key];
      return switch (e.type) {
        EventType.put => own(e.data) && (current == null || own(current)),
        EventType.patch =>
          own(current) &&
              !e.data.containsKey('setByChild') &&
              !e.data.containsKey('childId'),
        EventType.delete => own(current),
        _ => false,
      };
    }
    if (e.key.startsWith(FamilyKeys.temporaryBlock)) {
      // A break the child takes; it cannot be cut short.
      return e.type == EventType.put &&
          replica[e.key] == null &&
          own(e.data, flag: 'voluntary');
    }
    if (e.key.startsWith(FamilyKeys.selfLimitLog)) {
      return e.type == EventType.put;
    }
    // Its own installed apps: names and icons, for the other devices.
    if (e.key.startsWith(appsOf(deviceOfOrigin(e.origin)))) return true;
    // Its own system components (home screen…).
    if (e.key == systemOf(deviceOfOrigin(e.origin))) {
      return e.type == EventType.put || e.type == EventType.patch;
    }
    return false;
  }

  /// What concerns one child only, from 0.25, goes only to that child's
  /// devices and the parents': their rules, groups of apps, bonuses,
  /// blocks, unlocks, time away, own limits and use of apps, and the apps
  /// of their devices. A device's receipts go to the parents only. The
  /// rest (the children's names, the devices, periods, family settings…)
  /// goes to every device.
  @override
  String? scopeOf(String key, Map<String, Object?> value, MergedState replica) {
    String? child() => switch (value['childId']) {
      final String id => id,
      _ => null,
    };
    if (key == 'usage') return child();
    if (key.startsWith('seen/')) return parentsOnly;
    if (key.startsWith('app/') || key.startsWith('system/')) {
      final at = key.indexOf('/') + 1;
      final slash = key.indexOf('/', at);
      final id = key.substring(at, slash < 0 ? key.length : slash);
      final device = replica[SyncKeys.device(id)];
      if (device == null) return null;
      final audience = Audience.of(device);
      return audience.all ? parentsOnly : audience.child;
    }
    for (final prefix in childKeys) {
      if (key.startsWith(prefix)) return child();
    }
    return null;
  }

  /// Entities that concern one child (their `childId`).
  static const childKeys = [
    FamilyKeys.rule,
    FamilyKeys.group,
    FamilyKeys.bonus,
    FamilyKeys.temporaryBlock,
    FamilyKeys.dayUnlock,
    FamilyKeys.hoursUnlock,
    FamilyKeys.injected,
    FamilyKeys.selfLimitLog,
  ];
}

/// Keys of a device's installed apps in the log: `app/<device>/<package>`,
/// with `label` and `icon` (PNG, base64). Each device writes its own.
String appsOf(String deviceId) => 'app/$deviceId/';

/// Key of a device's system components in the log (`packages`): its home
/// screen and the like, never counted in the statistics.
String systemOf(String deviceId) => 'system/$deviceId';

/// Width of the icons shared with the family's devices, in pixels.
const sharedIconSize = 48;

/// Files of the sync, in the app's folder.
class SyncFiles {
  final Directory dir;

  SyncFiles(LocalStore store) : dir = Directory('${store.dir.path}/sync');

  File get identity => File('${dir.path}/identity.json');
  File get root => File('${dir.path}/root.json');

  /// A log and its merged entities (SQLite), shared by the interface and
  /// the monitor. Each link to other devices starts a new one, named in
  /// [root] (`family.db` before 0.22).
  String database(String name) => '${dir.path}/$name';

  /// Name of the log in use; `null` while this device is linked to none.
  Future<String?> currentDatabase() async {
    try {
      if (!await exist) return null;
      return (await _read(root))['db'] as String? ?? legacyDatabase;
    } on Object {
      return null;
    }
  }

  static const legacyDatabase = 'family.db';

  /// A name for a new log.
  static String newDatabase() => 'family-${newId()}.db';

  /// Files of the link in use, other than its log: forgotten when this
  /// device joins other devices or leaves them.
  List<File> get _linkFiles => [
    identity,
    root,
    peers,
    appsPublished,
    othersUsage,
    usageHistory,
    relayState,
  ];

  /// Deletes the logs other than [keep] (left by an earlier link). Another
  /// process still using one keeps it until it closes it.
  Future<void> removeStale({String? keep}) async {
    if (!await dir.exists()) return;
    await for (final f in dir.list()) {
      final name = f.uri.pathSegments.last;
      if (!name.startsWith('family') || !name.contains('.db')) continue;
      if (keep != null && name.startsWith(keep)) continue;
      try {
        await f.delete();
      } on Object {
        // Tried again next time.
      }
    }
  }

  /// The family's devices as the monitor last saw them on the network
  /// (written by the monitor, read by the interface).
  File get peers => File('${dir.path}/peers.json');

  /// The day this device last shared its installed apps.
  File get appsPublished => File('${dir.path}/apps-published');

  /// Present once the use recorded by the family's other devices, held in
  /// the log, has been added to this device's use (see
  /// `FamilySync.importOthersUsage`).
  File get othersUsage => File('${dir.path}/others-usage.done');

  /// Present once the monitor has put the usage recorded before the
  /// family existed into the log.
  File get usageHistory => File('${dir.path}/usage-history.done');

  /// Where this device is with the relay server (see [RelayState]),
  /// written by the process that syncs with it.
  File get relayState => File('${dir.path}/relay-state.json');

  Future<bool> get exist async =>
      await identity.exists() && await root.exists();

  static Future<Map<String, Object?>> _read(File f) async =>
      Map<String, Object?>.from(jsonDecode(await f.readAsString()) as Map);

  static Future<void> _write(File f, Map<String, Object?> data) async {
    await f.parent.create(recursive: true);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(data), flush: true);
    await tmp.rename(f.path);
  }
}

class FamilySync {
  final SyncNode node;
  final SyncFiles files;

  /// This device's id (the interface writes as [uiOrigin]).
  final String deviceId;

  /// Name of the log file (see [SyncFiles.database]).
  final String dbName;

  /// Until [commit]: the identity of a device joining others.
  DeviceIdentity? _pending;

  /// Until [commit]: the content key opened with the parent code, when the
  /// welcome came without it.
  List<int>? _pendingContentKey;

  FamilySync._(this.node, this.files, this.deviceId, this.dbName);

  static String uiOrigin(String deviceId) => '$deviceId~ui';

  static const policy = FamilySyncPolicy();

  /// Opens the log, for the interface or for the [background] monitor;
  /// `null` while the family has not been created on this device.
  static Future<FamilySync?> open(
    LocalStore store, {
    required bool background,
  }) async {
    final files = SyncFiles(store);
    // 0.19.0 kept the log in JSON files: that family is made again, with
    // its keys, the next time the parent code is entered.
    final legacy = Directory('${files.dir.path}/log');
    if (await legacy.exists()) {
      await files.dir.delete(recursive: true);
      return null;
    }
    if (!await files.exist) return null;
    final identity = await DeviceIdentity.fromJson(
      await SyncFiles._read(files.identity),
    );
    final rootJson = await SyncFiles._read(files.root);
    final root = FamilyRoot.fromJson(rootJson);
    final db = rootJson['db'] as String? ?? SyncFiles.legacyDatabase;
    final id = identity.deviceId;
    final ui = uiOrigin(id);
    final node = SyncNode(
      me: background ? identity : DeviceIdentity(ui, identity.signing),
      root: root,
      store: SqliteSyncStore.open(files.database(db)),
      policy: policy,
    );
    return FamilySync._(node, files, id, db);
  }

  /// Starts linking this device to others, from the interface: its keys,
  /// the parent key sealed by [parentCode], this device's registration and
  /// the family's current data. Returns the sync and the parent key.
  static Future<(FamilySync, SigningKey)> create({
    required LocalStore store,
    required AppSettings settings,
    required FamilyData family,
    required String parentCode,
    required String deviceName,
  }) async {
    final files = SyncFiles(store);
    final db = SyncFiles.newDatabase();
    final identity = await DeviceIdentity.generate(settings.deviceId);
    final ui = uiOrigin(identity.deviceId);
    final created = await createFamily(
      familyId: newId(),
      device: DeviceIdentity(ui, identity.signing),
      parentCode: parentCode,
      deviceInfo: {
        'name': deviceName,
        'role': settings.childId == null ? 'parent' : 'child',
        'childId': ?settings.childId,
        'platform': Platform.operatingSystem,
      },
      store: await _openStore(files, db),
      policy: policy,
    );
    final sync = FamilySync._(created.node, files, identity.deviceId, db);
    await sync.recordChange(null, family, parentKey: created.parentKey);
    // Cut per child from the start.
    await created.node.startScoped(created.parentKey);
    await sync._writeLink(identity, created.root);
    return (sync, created.parentKey);
  }

  /// Takes in the log of the devices this one was welcomed by (checking
  /// it). Nothing changes on this device until [commit]: until then the
  /// link in use, if any, stays as it was.
  static Future<FamilySync> join({
    required LocalStore store,
    required DeviceIdentity identity,
    required Welcome welcome,
  }) async {
    final files = SyncFiles(store);
    final db = SyncFiles.newDatabase();
    final node = SyncNode(
      me: DeviceIdentity(uiOrigin(identity.deviceId), identity.signing),
      root: welcome.root,
      store: await _openStore(files, db),
      policy: policy,
    );
    await node.ingest(welcome.events);
    return FamilySync._(node, files, identity.deviceId, db)
      .._pending = identity;
  }

  /// Makes the log taken in by [join] this device's: the earlier link is
  /// forgotten. The monitor, told to reload, moves to it.
  Future<void> commit() async {
    final identity = _pending;
    if (identity == null) return;
    for (final f in files._linkFiles) {
      if (await f.exists()) await f.delete();
    }
    await _writeLink(identity, node.root);
    _pending = null;
  }

  /// Written last, the root names the log: the link exists on this device
  /// once both files are there.
  Future<void> _writeLink(DeviceIdentity identity, FamilyRoot root) async {
    final content = _pendingContentKey;
    await SyncFiles._write(files.identity, identity.toJson());
    await SyncFiles._write(files.root, {
      ...root.toJson(),
      if (root.contentKey == null && content != null)
        'contentKey': b64(content),
      'db': dbName,
    });
    _pendingContentKey = null;
  }

  /// Unlinks this device: it keeps working on its own, the log is
  /// forgotten (the monitor lets go of it when told to reload).
  static Future<void> leave(LocalStore store) async {
    final files = SyncFiles(store);
    for (final f in files._linkFiles) {
      if (await f.exists()) await f.delete();
    }
    await files.removeStale();
  }

  /// Renames device [id], for every device.
  Future<void> renameDevice(String id, String name, SigningKey parentKey) =>
      node.emit([
        EventDraft.patch(SyncKeys.device(id), {'name': name}),
      ], parentKey: parentKey);

  /// This device's registration (name, role, child…).
  Map<String, Object?>? get registration =>
      node.replica[SyncKeys.device(deviceId)];

  /// Every child of the family, even on a child's device (which shows
  /// only its own): to link a device to another child from there.
  List<Child> allChildren() => familyFromEntities(
    node.replica.withPrefix(FamilyKeys.child),
    const FamilyData(),
  ).children;

  /// The family's devices, by id, removed ones left out.
  Map<String, Map<String, Object?>> get devices => {
    for (final e in node.replica.withPrefix(SyncKeys.devicePrefix).entries)
      if (e.value['revoked'] != true)
        e.key.substring(SyncKeys.devicePrefix.length): e.value,
  };

  /// Removes [id] from the family: its events are refused from now on.
  Future<void> removeDevice(String id, SigningKey parentKey) => node.emit([
    EventDraft.patch(SyncKeys.device(id), {'revoked': true}),
  ], parentKey: parentKey);

  /// When each device was last in contact, as the monitor saw it.
  Future<Map<String, PeerState>> peers() async {
    try {
      final j = await SyncFiles._read(files.peers);
      return {
        for (final e in j.entries)
          e.key: PeerState(
            e.key,
            DateTime.fromMillisecondsSinceEpoch(
              ((e.value as Map)['last'] as num).toInt(),
            ),
            connected: (e.value as Map)['connected'] == true,
          ),
      };
    } on Object {
      return const {};
    }
  }

  /// Saves the devices' contact as the monitor sees it.
  Future<void> savePeers(Iterable<PeerState> peers) => SyncFiles._write(
    files.peers,
    {for (final p in peers) p.deviceId: p.toJson()},
  );

  /// Takes in what came from another device: its use of apps goes with
  /// the use recorded here, and a change of the family's settings is
  /// written to the family file. Returns the family when it changed.
  Future<FamilyData?> applyRemote(Accepted a, LocalStore store) async {
    for (final e in a.events) {
      if (e.type != EventType.usage) continue;
      if (deviceOfOrigin(e.origin) == deviceId) continue;
      await store.appendUsage(usageSegmentFromJson(e.data));
    }
    // The snapshot came, or this device belongs to another child now.
    final tidied = await tidy(store);
    if (tidied != null) return tidied;
    // The family file is written again only if the family's data changed
    // (not for a device's apps or registration).
    if (!a.replicaChanged || !a.events.any((e) => isFamilyKey(e.key))) {
      return null;
    }
    final family = compose(await store.loadFamily());
    await store.saveFamily(family);
    return family;
  }

  /// Removes from this device what it needs no more (see [SyncNode.tidy]):
  /// on a child's device, what concerns the other children, the use of
  /// apps included. Returns the family when it changed.
  Future<FamilyData?> tidy(LocalStore store) async {
    if (!await node.tidy()) return null;
    final audience = node.audience;
    if (!audience.all) {
      await store.rewriteUsage((u) => u.childId == audience.child ? u : null);
    }
    final family = compose(await store.loadFamily());
    await store.saveFamily(family);
    return family;
  }

  /// Cuts the family's events per child, once, for devices linked before
  /// 0.25 (see [SyncNode.rebase]): from a parent's device only, which
  /// holds everything. Whether it was done now.
  Future<bool> rebase(SigningKey parentKey) async {
    if (!await node.rebase(parentKey)) return false;
    await recordMembers(parentKey);
    return true;
  }

  /// Whether [key] (with [value]) is another child's, on this device: a
  /// child's device keeps only the family's and its child's (and does not
  /// show the other children).
  bool _hidden(String key, Map<String, Object?> value) {
    final reg = registration;
    if (reg == null) return false;
    final audience = Audience.of(reg);
    if (audience.all) return false;
    if (key.startsWith(FamilyKeys.child)) {
      return key.substring(FamilyKeys.child.length) != audience.child;
    }
    final scope = policy.scopeOf(key, value, node.replica);
    return scope != null && scope.isNotEmpty && scope != audience.child;
  }

  /// Adds to this device's use what the other devices recorded and the log
  /// holds, once (on a device that just joined, the use of the days
  /// before). Use already there is not added twice. Returns how many
  /// stretches of use were added.
  Future<int> importOthersUsage(LocalStore store) async {
    final done = files.othersUsage;
    if (await done.exists()) return 0;
    String key(UsageSegment u) =>
        '${u.deviceId}|${u.appId}|${u.start.millisecondsSinceEpoch}|'
        '${u.end.millisecondsSinceEpoch}';
    final since = DateTime.now().subtract(usageKept);
    final held = {for (final u in await store.loadUsage(since: since)) key(u)};
    var added = 0;
    for (final page in node.store.pagesFor(const {})) {
      for (final e in page) {
        if (e.type != EventType.usage) continue;
        if (deviceOfOrigin(e.origin) == deviceId) continue;
        final u = usageSegmentFromJson(e.data);
        if (u.end.isBefore(since) || !held.add(key(u))) continue;
        await store.appendUsage(u);
        added++;
      }
    }
    await done.writeAsString(DateTime.now().toIso8601String());
    return added;
  }

  /// Packages and names of the apps this device shared.
  Map<String, String> publishedApps() => _labels(appsOf(deviceId));

  Map<String, String> _labels(String prefix) => {
    for (final e in node.replica.withPrefix(prefix).entries)
      e.key.substring(e.key.indexOf('/', 4) + 1):
          e.value['label'] as String? ?? '',
  };

  /// Shares the apps installed here with the family's devices: [labels]
  /// by package, and [icons] of the apps not shared yet. Only what changed
  /// is recorded: new apps, names changed, apps removed.
  Future<int> publishApps(
    Map<String, String> labels, {
    Map<String, AppInfo> icons = const {},
  }) async {
    final prefix = appsOf(deviceId);
    final shared = publishedApps();
    final drafts = <EventDraft>[
      for (final e in labels.entries)
        if (!shared.containsKey(e.key))
          EventDraft.put('$prefix${e.key}', {
            'label': e.value,
            if (icons[e.key]?.icon case final icon?) 'icon': base64Encode(icon),
          })
        else if (shared[e.key] != e.value)
          EventDraft.patch('$prefix${e.key}', {'label': e.value}),
      for (final package in shared.keys)
        if (!labels.containsKey(package)) EventDraft.delete('$prefix$package'),
    ];
    if (drafts.isNotEmpty) await node.emit(drafts);
    return drafts.length;
  }

  /// Shares this device's system components (home screen…), so that no
  /// device counts them in the statistics. Whether they changed.
  Future<bool> publishSystem(Set<String> packages) async {
    final sorted = packages.toList()..sort();
    final held = node.replica[systemOf(deviceId)]?['packages'];
    if (held is List && sameJson(held, sorted)) return false;
    await node.emit([
      EventDraft.put(systemOf(deviceId), {'packages': sorted}),
    ]);
    return true;
  }

  /// The system components the family's devices shared.
  Set<String> sharedSystem() => {
    for (final e in node.replica.withPrefix('system/').values)
      for (final p in e['packages'] as List? ?? const []) p as String,
  };

  /// Names and icons of [packages] as the family's devices shared them.
  Map<String, AppInfo> sharedApps(Iterable<String> packages) {
    final found = <String, AppInfo>{};
    final devices = this.devices.keys.toList();
    for (final package in packages) {
      for (final d in devices) {
        final app = node.replica['${appsOf(d)}$package'];
        if (app == null) continue;
        final icon = app['icon'];
        found[package] = AppInfo(
          app['label'] as String? ?? package,
          icon is String ? base64Decode(icon) : null,
        );
        break;
      }
    }
    return found;
  }

  /// Every app the family's devices shared, by package, with its name.
  Map<String, String> sharedAppNames() => _labels('app/');

  /// The apps the devices of [childId] shared (this one left out), by
  /// package, with their names.
  Map<String, String> childAppNames(String childId) => {
    for (final e in devices.entries)
      if (e.key != deviceId && e.value['childId'] == childId)
        ..._labels(appsOf(e.key)),
  };

  /// The parent key, unlocked by [parentCode]; `null` if it does not open.
  /// The content key comes with it, on a device that lacked it.
  Future<SigningKey?> unlock(String parentCode) async {
    final key = await unlockParentKey(node, parentCode);
    if (key != null) await adoptContentKey(parentCode);
    return key;
  }

  /// Seals the parent key with a new code, for every device, and the
  /// content key if it is kept sealed in the log.
  Future<void> changeCode(SigningKey parentKey, String parentCode) async {
    await changeParentCode(node, parentKey, parentCode);
    final content = await contentKey();
    if (content != null && node.replica[SyncKeys.family]?['content'] != null) {
      await node.emit([
        EventDraft.patch(SyncKeys.family, {
          'content': await ParentVault.seal(content, parentCode),
        }),
      ], parentKey: parentKey);
    }
  }

  // --- Relay server ---------------------------------------------------------

  /// The key events are encrypted with for the relay (see
  /// [FamilyRoot.contentKey]), as this device holds it; `null` if not yet.
  Future<List<int>?> contentKey() async {
    try {
      final k = (await SyncFiles._read(files.root))['contentKey'];
      return k is String ? unb64(k) : null;
    } on Object {
      return null;
    }
  }

  Future<void> _saveContentKey(List<int> key) async {
    final root = await SyncFiles._read(files.root);
    await SyncFiles._write(files.root, {...root, 'contentKey': b64(key)});
  }

  /// The content key, made now if these devices had none (linked before
  /// 0.23): sealed by [parentCode] in the log, so that each device takes
  /// it when the code is next entered there.
  Future<List<int>> ensureContentKey(
    SigningKey parentKey,
    String parentCode,
  ) async {
    final held = await contentKey();
    if (held != null) return held;
    final sealed = node.replica[SyncKeys.family]?['content'];
    if (sealed is Map) {
      final opened = await ParentVault.openBytes(
        Map<String, Object?>.from(sealed),
        parentCode,
      );
      if (opened != null) {
        await _saveContentKey(opened);
        return opened;
      }
    }
    final key = randomBytes(32);
    await _saveContentKey(key);
    await node.emit([
      EventDraft.patch(SyncKeys.family, {
        'content': await ParentVault.seal(key, parentCode),
      }),
    ], parentKey: parentKey);
    return key;
  }

  /// Takes the content key sealed in the log, on a device that lacks it.
  /// Whether it was taken now.
  Future<bool> adoptContentKey(String parentCode) async {
    // Joining: kept for [commit] (the files are another link's still).
    if (_pending != null) {
      if (node.root.contentKey != null) return false;
      final sealed = node.replica[SyncKeys.family]?['content'];
      if (sealed is! Map) return false;
      _pendingContentKey = await ParentVault.openBytes(
        Map<String, Object?>.from(sealed),
        parentCode,
      );
      return _pendingContentKey != null;
    }
    if (await contentKey() != null) return false;
    final sealed = node.replica[SyncKeys.family]?['content'];
    if (sealed is! Map) return false;
    final key = await ParentVault.openBytes(
      Map<String, Object?>.from(sealed),
      parentCode,
    );
    if (key == null) return false;
    await _saveContentKey(key);
    return true;
  }

  /// The relay server's address, if the parent set one up.
  String? get relayUrl => node.replica[SyncKeys.server]?['url'] as String?;

  /// Sets the relay server up for every device (`null`: none any more).
  Future<void> setRelay(String? url, SigningKey parentKey) => node.emit([
    url == null
        ? EventDraft.delete(SyncKeys.server)
        : EventDraft.put(SyncKeys.server, {'url': url}),
  ], parentKey: parentKey);

  /// The devices the relay lets in, signed by the parent key.
  Map<String, Object?>? get members => node.replica[SyncKeys.members];

  /// Signs the list of devices again when it changed (a device linked,
  /// removed…), so the relay lets in the right ones. Whether it changed.
  Future<bool> recordMembers(SigningKey parentKey) async {
    final devices = memberKeys(node);
    final scopes = memberScopes(node);
    final floors = node.store.floors;
    final current = readMembers(members);
    if (current != null &&
        sameJson(current.devices, devices) &&
        sameJson(current.scopes, scopes) &&
        sameJson(current.floors, floors)) {
      return false;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final version = current == null || now > current.version
        ? now
        : current.version + 1;
    await node.emit([
      EventDraft.put(
        SyncKeys.members,
        await signMembers(
          familyId: node.root.familyId,
          version: version,
          devices: devices,
          scopes: scopes,
          floors: floors,
          parentKey: parentKey,
        ),
      ),
    ], parentKey: parentKey);
    return true;
  }

  Future<RelayState> loadRelayState(String url) async {
    try {
      final j = await SyncFiles._read(files.relayState);
      if (j['url'] != url) return const RelayState();
      return RelayState.fromJson(j);
    } on Object {
      return const RelayState();
    }
  }

  Future<void> saveRelayState(String url, RelayState state) =>
      SyncFiles._write(files.relayState, {...state.toJson(), 'url': url});

  /// Records what changed from [before] (`null`: nothing yet) to [after].
  /// Without the [parentKey], only what the device may sign itself is
  /// recorded (a child's own limits, breaks…).
  Future<List<SyncEvent>> recordChange(
    FamilyData? before,
    FamilyData after, {
    SigningKey? parentKey,
  }) async {
    final old = before == null
        ? const <String, Map<String, Object?>>{}
        : familyEntities(before);
    var drafts = [
      for (final d in diffEntities(old, familyEntities(after)))
        // Another child's, not shown here: left as it is.
        if (old[d.key] == null || !_hidden(d.key, old[d.key]!)) d,
    ];
    if (parentKey == null) {
      final device = node.replica[SyncKeys.device(deviceId)];
      if (device == null) return const [];
      drafts = [
        for (final d in drafts)
          if (policy.deviceMay(_probe(d), device, node.replica)) d,
      ];
    }
    return node.emit(drafts, parentKey: parentKey);
  }

  /// [d] as an event of this device, to ask the policy about it.
  SyncEvent _probe(EventDraft d) => SyncEvent(
    origin: node.deviceId,
    seq: 0,
    hlc: Hlc.zero,
    type: d.type,
    key: d.key,
    data: d.data,
    signer: Signer.device,
    sig: '',
  );

  /// Records use of an app on this device (from the monitor).
  Future<void> recordUsage(Iterable<UsageSegment> segments) => node.emit([
    for (final s in segments)
      EventDraft(EventType.usage, 'usage', usageSegmentToJson(s)),
  ]);

  /// Takes in what the other process of this device recorded.
  Future<List<SyncEvent>> readOthers() => node.readOthers();

  /// How long use of apps stays in the log: what the rules look at, and a
  /// week more.
  static const usageKept = Duration(days: usageHistoryDays + 7);

  /// Removes the use of apps older than [usageKept]; how many events.
  int pruneUsage([DateTime? now]) =>
      node.store.prune((now ?? DateTime.now()).subtract(usageKept));

  static Future<SqliteSyncStore> _openStore(SyncFiles files, String db) async {
    await files.dir.create(recursive: true);
    return SqliteSyncStore.open(files.database(db));
  }

  Future<void> close() => node.close();

  /// The family as merged from the log; what belongs to this device only
  /// comes from [local].
  /// On a child's device, only the family's and that child's: the other
  /// children are not shown.
  FamilyData compose(FamilyData local) {
    // Groups given to each child as on every device, with every child.
    final all = ownGroups(_composed(local));
    final reg = registration;
    if (reg == null || Audience.of(reg).all) return all;
    return familyFromEntities({
      for (final e in familyEntities(all).entries)
        if (!_hidden(e.key, e.value)) e.key: e.value,
    }, local);
  }

  FamilyData _composed(FamilyData local) => familyFromEntities({
    // Only the family's own entities: not the devices nor their apps.
    for (final prefix in familyPrefixes) ...node.replica.withPrefix(prefix),
  }, local);

  /// Records in the log that each child has their own groups of apps
  /// (see [ownGroups]), when it still holds groups shared by the family.
  /// Every device already reads them that way.
  Future<void> recordGroupOwners(SigningKey parentKey) async {
    final raw = _composed(const FamilyData());
    final owned = ownGroups(raw);
    if (identical(owned, raw)) return;
    await recordChange(raw, owned, parentKey: parentKey);
  }

  /// Keys of the entities making up the family's data.
  static final familyPrefixes = [
    FamilyKeys.family,
    FamilyKeys.child,
    FamilyKeys.group,
    FamilyKeys.deviceGroup,
    FamilyKeys.appName,
    FamilyKeys.profile,
    ...FamilyKeys.stateLists.values,
    FamilyKeys.injected,
    FamilyKeys.selfLimitLog,
  ];

  /// Whether [key] belongs to the family's data (see [compose]).
  static bool isFamilyKey(String key) => familyPrefixes.any(
    (p) => key == p || (p.endsWith('/') && key.startsWith(p)),
  );
}
