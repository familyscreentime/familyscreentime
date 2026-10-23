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
    return false;
  }
}

/// Keys of a device's installed apps in the log: `app/<device>/<package>`,
/// with `label` and `icon` (PNG, base64). Each device writes its own.
String appsOf(String deviceId) => 'app/$deviceId/';

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
    await SyncFiles._write(files.identity, identity.toJson());
    await SyncFiles._write(files.root, {...root.toJson(), 'db': dbName});
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
    // The family file is written again only if the family's data changed
    // (not for a device's apps or registration).
    if (!a.replicaChanged || !a.events.any((e) => isFamilyKey(e.key))) {
      return null;
    }
    final family = compose(await store.loadFamily());
    await store.saveFamily(family);
    return family;
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

  /// The parent key, unlocked by [parentCode]; `null` if it does not open.
  Future<SigningKey?> unlock(String parentCode) =>
      unlockParentKey(node, parentCode);

  /// Seals the parent key with a new code, for every device.
  Future<void> changeCode(SigningKey parentKey, String parentCode) =>
      changeParentCode(node, parentKey, parentCode);

  /// Records what changed from [before] (`null`: nothing yet) to [after].
  /// Without the [parentKey], only what the device may sign itself is
  /// recorded (a child's own limits, breaks…).
  Future<List<SyncEvent>> recordChange(
    FamilyData? before,
    FamilyData after, {
    SigningKey? parentKey,
  }) async {
    var drafts = diffEntities(
      before == null ? const {} : familyEntities(before),
      familyEntities(after),
    );
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
  FamilyData compose(FamilyData local) => ownGroups(_composed(local));

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
