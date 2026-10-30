/// State of the interface: settings, family data and parent mode.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:screentime_engine/screentime_engine.dart';
import 'package:screentime_sync/screentime_sync.dart'
    show
        HttpRelayApi,
        LanDirectory,
        LanSync,
        PeerState,
        RelayError,
        RelayState,
        RemoteSource,
        SigningKey;

import 'family.dart';
import 'pin.dart';
import 'platform.dart';
import 'self_limits.dart';
import 'store.dart';
import 'strings.dart';
import 'sync/bonsoir_directory.dart';
import 'sync/family_entities.dart';
import 'sync/family_sync.dart';
import 'sync/link_merge.dart';
import 'sync/receipts.dart';
import 'sync/relay_runner.dart';

/// How far back Android's history is asked for; it keeps about ten days.
const historyImportSpan = Duration(days: 30);

/// Parent mode closes after this long without a touch.
const parentModeTimeout = Duration(minutes: 5);

/// Calendar profile of normal times, outside every special period.
const normalProfileId = 'normal';

class AppController extends ChangeNotifier {
  final LocalStore store;
  final PlatformApi platform;
  final navigatorKey = GlobalKey<NavigatorState>();

  AppSettings settings;
  FamilyData family;
  bool _parentMode = false;
  Timer? _parentTimer;

  /// The family log, once the family exists on this device.
  Future<FamilySync?>? _sync;

  /// The parent key while in parent mode, unlocked by the code entered.
  Future<SigningKey?>? _parentKey;

  /// The demonstration build: its parent code, shown on the locked home.
  /// It links to no device and keeps nothing.
  final String? demoCode;

  bool get demo => demoCode != null;

  AppController(
    this.store,
    this.settings,
    FamilyData family, {
    this.platform = const PlatformApi(),
    this.demoCode,
  }) : family = ownGroups(family);

  static Future<AppController> load() async {
    final store = await LocalStore.open();
    final deviceLanguage = PlatformDispatcher.instance.locale.languageCode;
    final settings = await store.loadSettings(
      defaultLanguage: S.of(deviceLanguage).language,
    );
    final family = withKnownSystem(await store.loadFamily());
    final c = AppController(store, settings, family);
    await c.openSync();
    unawaited(_prune(store, family));
    // A parent's device has no monitor: it syncs while the app runs.
    if (settings.parentDevice) {
      unawaited(c.startLanSync());
    } else if (settings.setupDone) {
      // Android may have stopped the monitor (some manufacturers do,
      // without telling): opening the app starts it again.
      unawaited(c.platform.startMonitor().catchError((Object _) {}));
    }
    return c;
  }

  S get s => S.of(settings.language);

  /// The child shown: this device's child, or on a parent's device the
  /// child chosen ([selectChild]), the first one by default.
  String? get childId =>
      settings.childId ??
      _selectedChild ??
      (family.children.isEmpty ? null : family.children.first.id);

  String? _selectedChild;

  /// On a parent's device: the child whose settings are shown.
  void selectChild(String id) {
    _selectedChild = id;
    notifyListeners();
  }

  Child? get child => family.child(childId);

  List<Rule> get childRules =>
      family.state.rules.where((r) => r.childId == childId).toList();

  Future<void> updateSettings(AppSettings next) async {
    settings = next;
    await store.saveSettings(next);
    notifyListeners();
    await _reloadMonitor();
  }

  /// Forgets the use of apps older than the family keeps it.
  static Future<void> _prune(LocalStore store, FamilyData family) async {
    try {
      await store.pruneUsage(family.usageKeptDays);
    } on Object catch (e) {
      debugPrint('Old usage not removed: $e');
    }
  }

  Future<void> updateFamily(FamilyData next) async {
    final before = family;
    // Each rule keeps the daily limit it had before a change, so past days
    // are judged by the limit in force then.
    next = withRuleVersions(before, ownGroups(next), DateTime.now());
    if (next.usageKeptDays != before.usageKeptDays) {
      unawaited(_prune(store, next));
    }
    family = next;
    await store.saveFamily(next);
    notifyListeners();
    await _recordInLog(before, next);
    await _reloadMonitor();
  }

  // --- Family log -------------------------------------------------------------

  /// The family log, opened once.
  Future<FamilySync?> get sync => _sync ?? Future.value(null);

  /// Opens the family log (at start, and once the family exists).
  Future<FamilySync?> openSync() {
    final opening = _sync = FamilySync.open(store, background: false)
        .catchError((Object e) {
          debugPrint('Family log not opened: $e');
          return null;
        });
    // Which version runs here, for the list of linked devices (a parent's
    // device has no monitor to say it).
    unawaited(
      opening
          .then((log) async {
            if (log == null) return;
            final version = await platform.appVersion();
            if (version != null) await recordVersion(log, version);
          })
          .catchError((Object e) => debugPrint('Version not recorded: $e')),
    );
    return opening;
  }

  /// Records the change in the family log, signed by the parent key in
  /// parent mode. A failure never stops the change made here.
  Future<void> _recordInLog(FamilyData before, FamilyData after) async {
    try {
      // First the key: entering the code may be creating the family.
      final key = _parentMode ? await _parentKey : null;
      final log = await sync;
      if (log == null) return;
      await log.readOthers();
      if (key != null) {
        await log.recordGroupOwners(key);
        await log.recordMembers(key);
      }
      await log.recordChange(before, after, parentKey: key);
    } on Object catch (e) {
      debugPrint('Change not recorded in the family log: $e');
    }
  }

  /// The code entered for parent mode, kept while it lasts: linking this
  /// device to another seals the key of the linked devices with it.
  String? _enteredCode;

  /// The parent code was just entered: unlocks the key of the linked
  /// devices, if this one is linked.
  void parentCodeEntered(String code) {
    _enteredCode = code;
    _parentKey = () async {
      try {
        final log = await sync;
        if (log == null) return null;
        final key = await log.unlock(code);
        // The relay's key may just have come with it.
        if (key != null && log.relayUrl != null) {
          unawaited(_afterRelayChange());
        }
        if (key != null) unawaited(_rebase(log, key));
        return key;
      } on Object catch (e) {
        debugPrint('Parent key not unlocked: $e');
        return null;
      }
    }();
  }

  /// Devices linked before 0.25: each child's are given only what
  /// concerns them, once, from a parent's device (see [FamilySync.rebase]).
  Future<void> _rebase(FamilySync log, SigningKey key) async {
    try {
      if (!await log.rebase(key)) return;
      if (await log.tidy(store) != null) await reloadFamily();
      await _relay?.update();
    } on Object catch (e) {
      debugPrint('Family log not cut per child: $e');
    }
  }

  /// The log to welcome another device with, and the parent key (parent
  /// mode only). A device working on its own starts one, with its family
  /// and the code entered. `null` without the key.
  Future<(FamilySync, SigningKey)?> startLinking() async {
    final log = await sync;
    if (log != null) {
      final key = await parentKey;
      return key == null ? null : (log, key);
    }
    final code = _enteredCode;
    if (!_parentMode || code == null) return null;
    final (created, key) = await FamilySync.create(
      store: store,
      settings: settings,
      family: family,
      parentCode: code,
      deviceName: await platform.deviceName(),
    );
    _sync = Future.value(created);
    _parentKey = Future.value(key);
    await _reloadMonitor();
    return (created, key);
  }

  /// Whether this device shares its settings with other devices.
  Future<bool> get linked async => ((await sync)?.devices.length ?? 0) > 1;

  /// The parent key, in parent mode; `null` outside it or if the code
  /// entered does not open it.
  Future<SigningKey?> get parentKey async =>
      _parentMode ? await _parentKey : null;

  /// The family file changed (from another device): read it again.
  Future<void> reloadFamily() async {
    family = withKnownSystem(await store.loadFamily());
    notifyListeners();
  }

  /// Whether [code] opens the parent key of the family: the code may have
  /// been changed on another device. If it does, it becomes this device's
  /// code too.
  Future<bool> codeOpensFamily(String code) async {
    try {
      final log = await sync;
      if (log == null || await log.unlock(code) == null) return false;
      await updateSettings(await withNewPin(settings, code));
      return true;
    } on Object {
      return false;
    }
  }

  /// Whether, joining other devices with [log], this one must choose what
  /// becomes of its rules: set up already, for a child the others know and
  /// who has rules here.
  bool joinAsksForRules(FamilySync log) {
    final reg = log.registration;
    final local = settings.childId;
    if (!settings.setupDone || settings.parentDevice || local == null) {
      return false;
    }
    if (reg?['role'] == 'parent' || reg?['newChild'] == true) return false;
    final known = log.node.replica['${FamilyKeys.child}${reg?['childId']}'];
    return known != null && family.state.rules.any((r) => r.childId == local);
  }

  /// This device was just welcomed by other devices ([log], not committed
  /// yet); [code] is their parent code, which becomes this device's. Takes
  /// their family and this device's child. A device set up already brings
  /// its own (see [mergeJoining]); its rules for a child the others know
  /// only when [keepRules].
  Future<void> completeJoin(
    FamilySync log,
    String code, {
    bool keepRules = false,
  }) async {
    final system = await platform.systemPackages();
    final reg = log.registration;
    final childId = reg?['childId'] as String?;
    final parent = reg?['role'] == 'parent';
    final configured = settings.setupDone && !settings.parentDevice;
    var joined = log.compose(
      configured ? family : FamilyData(config: initialConfig(system)),
    );
    final localChild = settings.childId;
    if (configured && !parent) {
      final key = await log.unlock(code);
      final merged = mergeJoining(
        group: joined,
        local: family,
        localChild: localChild,
        groupChild: childId,
        newChild: reg?['newChild'] == true,
        keepRules: keepRules,
        deviceId: log.deviceId,
      );
      if (key != null) await log.recordChange(joined, merged, parentKey: key);
      joined = merged;
      // The use recorded here is the child's under their id there.
      if (localChild != null && childId != null && localChild != childId) {
        await store.rewriteUsage(
          (u) => u.childId != localChild
              ? u
              : usageSegmentFromJson({
                  ...usageSegmentToJson(u),
                  'childId': childId,
                }),
        );
      }
    }
    final previous = await sync;
    await log.commit();
    if (previous != null && !identical(previous, log)) await previous.close();
    await log.files.removeStale(keep: log.dbName);
    _sync = Future.value(log);
    await store.saveFamily(joined);
    family = joined;
    await updateSettings(
      (await withNewPin(settings, code)).copyWith(
        childId: childId,
        parentDevice: parent,
        // A parent's device needs no permissions: set up already.
        setupDone: parent ? true : null,
      ),
    );
    if (parent) {
      await log.importOthersUsage(store);
      await startLanSync();
    } else {
      // A monitor running already moves to the new log.
      await _reloadMonitor();
      await platform.startMonitor();
    }
  }

  /// Unlinks this child's device from the others (parent mode): it works
  /// on its own again, with its child, their rules that apply here and
  /// the time used here. The others are told, if they can be reached in a
  /// moment. Returns whether it was done.
  Future<bool> detach({
    Duration tellOthers = const Duration(seconds: 2),
  }) async {
    final log = await sync;
    final key = await parentKey;
    final childId = settings.childId;
    if (log == null || key == null || childId == null) return false;
    if (settings.parentDevice) return false;
    try {
      await log.removeDevice(log.deviceId, key);
      await _reloadMonitor();
      await Future<void>.delayed(tellOthers);
    } on Object catch (e) {
      debugPrint('The other devices were not told: $e');
    }
    final kept = keepOnLeaving(family, childId, settings.deviceId);
    _sync = null;
    _parentKey = null;
    await log.close();
    await FamilySync.leave(store);
    // Only the time used here counts from now on.
    await store.rewriteUsage(
      (u) => u.deviceId == null || u.deviceId == settings.deviceId ? u : null,
    );
    family = kept;
    await store.saveFamily(kept);
    notifyListeners();
    await _reloadMonitor();
    return true;
  }

  /// Renames device [id] for every linked device (parent mode).
  Future<void> renameDevice(String id, String name) async {
    final log = await sync;
    final key = await parentKey;
    if (log == null || key == null) return;
    await log.renameDevice(id, name, key);
    notifyListeners();
    await _reloadMonitor();
  }

  // --- A parent's device ----------------------------------------------------

  LanSync? _lan;
  Future<void> _remoteQueue = Future.value();

  /// On a parent's device, the family's devices on the local network,
  /// kept in sync while the app runs (there is no monitor).
  Future<void> startLanSync({LanDirectory Function()? directory}) async {
    if (!settings.parentDevice || _lan != null) return;
    final log = await sync;
    if (log == null) return;
    final lan = _lan = LanSync(
      log.node,
      (directory ?? BonsoirDirectory.new)(),
      onPeersChanged: () {
        final current = _lan;
        if (current != null) unawaited(log.savePeers(current.peers));
        notifyListeners();
      },
    );
    log.node.accepted.listen((a) {
      if (a.source is! RemoteSource) return;
      _remoteQueue = _remoteQueue.then((_) async {
        try {
          await _relay?.update();
          _receiptsSoon(log);
          if (await log.applyRemote(a, store) != null) await reloadFamily();
        } on Object catch (e) {
          debugPrint('Change from another device not applied: $e');
        }
      });
    });
    try {
      await lan.start();
    } on Object catch (e) {
      debugPrint('Local network sync not started: $e');
    }
    // And through the relay server, if there is one.
    await (_relay = RelayRunner(log)).update();
    _receiptsSoon(log);
    try {
      if (await log.tidy(store) != null) await reloadFamily();
    } on Object catch (e) {
      debugPrint('Family log not tidied: $e');
    }
  }

  RelayRunner? _relay;
  Timer? _receipts;

  /// On a parent's device: says in the log what it now holds.
  void _receiptsSoon(FamilySync log) {
    _receipts?.cancel();
    _receipts = Timer(const Duration(seconds: 3), () async {
      try {
        await recordReceipts(log);
        notifyListeners();
      } on Object catch (e) {
        debugPrint('Receipts not recorded: $e');
      }
    });
  }

  /// The changes made in parent mode lately, and who received them.
  Future<List<Change>> recentChangesLog() async {
    final log = await sync;
    return log == null ? const [] : recentChanges(log);
  }

  /// How many recent changes each device has not received yet.
  Future<Map<String, int>> pendingChanges() async {
    final log = await sync;
    return log == null ? const {} : pendingByDevice(log);
  }

  /// The family's devices seen on the network from this one.
  List<PeerState> get lanPeers => _lan?.peers ?? const [];

  /// Removes a device from the family (in parent mode).
  Future<void> removeDevice(String id) async {
    final log = await sync;
    final key = await parentKey;
    if (log == null || key == null) return;
    await log.removeDevice(id, key);
    await log.recordMembers(key);
    notifyListeners();
    await _reloadMonitor();
  }

  /// A device was welcomed from this one: the monitor passes it on, and
  /// the relay server lets it in.
  Future<void> deviceWelcomed() async {
    final log = await sync;
    final key = await parentKey;
    if (log != null && key != null) await log.recordMembers(key);
    notifyListeners();
    await _reloadMonitor();
  }

  // --- Relay server ---------------------------------------------------------

  /// Sets up the relay server at [address] for every linked device (parent
  /// mode): registers these devices there with an [invitation] from its
  /// administrator (not needed when another device registered them). A
  /// device on its own starts linking now. Returns the server's error
  /// code (`unreachable`, `bad_invitation`…), or `null` once set up.
  Future<String?> setUpRelay(String address, String invitation) async {
    final uri = relayEndpoint(address);
    if (uri == null) return 'bad_address';
    final linking = await startLinking();
    final code = _enteredCode;
    if (linking == null || code == null) return 'no_key';
    final (log, key) = linking;
    await log.ensureContentKey(key, code);
    await log.recordMembers(key);
    final api = HttpRelayApi(uri, log.node.root.familyId, log.node.me);
    try {
      final members = log.members!;
      if (invitation.trim().isEmpty) {
        // Registered from another device already: this one is let in once
        // the list of devices is there.
        await api.postMembers(members);
      } else {
        final created = await api.createFamily(
          invitation: invitation.trim(),
          parentKey: key.publicKey,
          members: members,
        );
        if (!created) await api.postMembers(members);
      }
      await api.heads();
    } on RelayError catch (e) {
      return e.code == 'unknown_device' && invitation.trim().isEmpty
          ? 'invitation_needed'
          : e.code;
    } finally {
      api.close();
    }
    await log.setRelay(uri.toString(), key);
    await _afterRelayChange();
    return null;
  }

  /// No relay server any more, for every linked device (parent mode).
  Future<void> removeRelay() async {
    final log = await sync;
    final key = await parentKey;
    if (log == null || key == null) return;
    await log.setRelay(null, key);
    await _afterRelayChange();
  }

  Future<void> _afterRelayChange() async {
    notifyListeners();
    if (settings.parentDevice) {
      await (_relay ??= RelayRunner((await sync)!)).update();
    } else {
      await _reloadMonitor();
    }
  }

  /// The relay server's address, if set up, and this device's last
  /// exchange with it.
  Future<(String, RelayState)?> relayStatus() async {
    final log = await sync;
    final url = log?.relayUrl;
    if (log == null || url == null) return null;
    return (url, await log.loadRelayState(url));
  }

  /// Whether this device holds the key to use the relay server (devices
  /// linked before 0.23 take it when the parent code is entered there).
  Future<bool> get hasRelayKey async =>
      await (await sync)?.contentKey() != null;

  /// The app is back on screen: on a parent's device, which syncs only
  /// while the app runs, a pass with the relay server soon.
  void resumed() {
    if (settings.parentDevice) unawaited(_relay?.update());
  }

  /// A pass with the relay server now.
  Future<void> syncRelayNow() async {
    if (settings.parentDevice) {
      try {
        await _relay?.sync?.syncOnce();
      } on Object {
        // Shown from the saved state.
      }
      notifyListeners();
    } else {
      await _reloadMonitor();
    }
  }

  /// Saves a new parent code, here and, sealed with the parent key, for
  /// every device of the family.
  Future<void> changeParentCode(String code) async {
    await updateSettings(await withNewPin(settings, code));
    try {
      final log = await sync;
      final key = await _parentKey;
      if (log != null && key != null) await log.changeCode(key, code);
    } on Object catch (e) {
      debugPrint('New code not sealed in the family log: $e');
    }
  }

  Future<void> _reloadMonitor() async {
    try {
      await platform.reloadMonitor();
    } on Object {
      // The monitor is not running yet; it will read the files when it starts.
    }
  }

  /// Usage the rules look at: recorded on this device, plus the time the
  /// parent entered for away from the devices.
  Future<List<UsageSegment>> recentUsage() async {
    final since = addDays(dayOf(DateTime.now()), -usageHistoryDays);
    return [...await store.loadUsage(since: since), ...family.injected];
  }

  /// Finishes the first-launch setup.
  Future<void> completeSetup({
    required String pin,
    required String childName,
  }) async {
    final system = await platform.systemPackages();
    final childId = newId();
    final withPin = await withNewPin(settings, pin);
    await updateFamily(
      FamilyData(
        children: [Child(id: childId, name: childName)],
        config: initialConfig(system),
      ),
    );
    // setupDone is set once the permissions step is over.
    await updateSettings(withPin.copyWith(childId: childId));
    await platform.startMonitor();
  }

  /// Refreshes the default apps and home screens, which can change.
  Future<void> refreshSystemPackages() async {
    final system = await platform.systemPackages();
    await updateFamily(
      family.copyWith(config: refreshSystemLists(family.config, system)),
    );
  }

  // --- Usage history --------------------------------------------------------

  /// Imports Android's own usage history once, up to the first use recorded
  /// by this app, so statistics are available from the first day. The
  /// imported usage serves statistics only, never the rules.
  Future<bool> importHistoryIfNeeded() async {
    final childId = this.childId;
    if (settings.historyImported || settings.parentDevice || childId == null) {
      return false;
    }
    try {
      final status = await platform.permissionStatus();
      if (status['usageAccess'] != true) return false;
      final now = DateTime.now();
      final recorded = await recentUsage();
      var until = now;
      for (final s in recorded) {
        if (s.start.isBefore(until)) until = s.start;
      }
      final raw = await platform.usageHistory(
        until.subtract(historyImportSpan),
        until,
      );
      if (raw == null) return false;
      await store.saveImported([
        for (final r in raw)
          if (r.end.isAfter(r.start))
            UsageSegment.device(
              childId: childId,
              deviceId: settings.deviceId,
              appId: r.package,
              start: r.start,
              end: r.end.isAfter(until) ? until : r.end,
            ),
      ]);
      await updateSettings(settings.copyWith(historyImported: true));
      return true;
    } on Object {
      // Tried again next time.
      return false;
    }
  }

  /// Usage for statistics: imported history plus usage recorded here.
  Future<List<UsageSegment>> statisticsUsage() async {
    final since = addDays(dayOf(DateTime.now()), -usageHistoryDays);
    return [
      ...await store.loadImported(since: since),
      ...await store.loadUsage(since: since),
    ];
  }

  /// Display name of a group.
  String groupName(String id) => family.groupNames[id] ?? id;

  /// The child's groups of apps, by id, with their names, by name.
  Map<String, String> get childGroups => family.groupsOf(childId);

  /// The other children's groups, by id: what can be copied for this one.
  Map<String, String> get otherChildrenGroups => {
    for (final c in family.children)
      if (c.id != childId)
        for (final e in family.groupsOf(c.id).entries) e.key: e.value,
  };

  /// Copies [ids], other children's groups, for this child: a group of the
  /// same name takes their apps, the others come as new groups.
  Future<void> copyGroups(Iterable<String> ids) async {
    final child = childId;
    if (child == null) return;
    final groups = {...family.config.appGroups};
    final names = {...family.groupNames};
    final owners = {...family.groupOwners};
    for (final id in ids) {
      final name = names[id] ?? id;
      final apps = groups[id] ?? const <String>{};
      final same = family
          .groupsOf(child)
          .entries
          .where((e) => e.value.toLowerCase() == name.toLowerCase())
          .firstOrNull;
      final copy = same?.key ?? newId();
      groups[copy] = {...?groups[copy], ...apps};
      names[copy] = same?.value ?? name;
      owners[copy] = child;
    }
    await updateFamily(
      family.copyWith(
        config: configWithGroups(family.config, groups),
        groupNames: names,
        groupOwners: owners,
      ),
    );
  }

  /// The child's groups containing [app], ordered by name.
  List<String> groupsOf(String app) => [
    for (final id in childGroups.keys)
      if (family.config.appGroups[id]?.contains(app) ?? false) id,
  ];

  /// The child's rules that apply: those not turned off.
  List<Rule> get activeChildRules =>
      childRules.where((r) => r.enabled).toList();

  // --- Special periods -------------------------------------------------------

  /// Special periods (holidays, exams, a week at the grandparents'…), in
  /// priority order: when two overlap, the first one applies.
  List<Profile> get specialPeriods => [
    for (final p in family.config.profiles)
      if (p.kind != ProfileKind.normal) p,
  ];

  /// Name shown for a special period.
  String periodName(Profile p) => p.name;

  /// Special period names by id, for rule summaries.
  Map<String, String> get periodNames => {
    for (final p in specialPeriods) p.id: periodName(p),
  };

  /// One-line summary of [r], special periods named.
  String summaryOf(Rule r) => ruleSummary(r, s, periodNames: periodNames);

  /// The special period in force on [t], if any.
  Profile? activePeriod(DateTime t) {
    final id = activeProfileId(family.config.profiles, t);
    for (final p in specialPeriods) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Whether [r] applies on [t]'s day: always, in normal times, or during
  /// its special period.
  bool ruleInForce(Rule r, DateTime t) =>
      r.profileId == null ||
      family.config.profiles.isEmpty ||
      r.profileId == activeProfileId(family.config.profiles, t);

  /// Replaces the special periods, in priority order. Rules set for a
  /// period that is gone are deleted with it.
  Future<void> setSpecialPeriods(List<Profile> periods) {
    final ids = {normalProfileId, for (final p in periods) p.id};
    return updateFamily(
      family.copyWith(
        config: configWithProfiles(family.config, [
          const Profile(
            id: normalProfileId,
            name: 'normal',
            kind: ProfileKind.normal,
          ),
          // All of the same kind, so the list order decides overlaps.
          for (final p in periods)
            Profile(
              id: p.id,
              name: periodName(p),
              kind: ProfileKind.custom,
              periods: p.periods,
            ),
        ]),
        state: stateWithRules(family.state, [
          for (final r in family.state.rules)
            if (r.profileId == null || ids.contains(r.profileId)) r,
        ]),
      ),
    );
  }

  // --- One-off actions -------------------------------------------------------

  /// Actions older than the usage history are dropped: the engine no longer
  /// looks at them.
  bool _recent(DateTime t, DateTime now) =>
      !t.isBefore(addDays(dayOf(now), -usageHistoryDays));

  /// Bonuses of the child still valid at [now].
  List<Bonus> activeBonuses(DateTime now) => [
    for (final b in family.state.bonuses)
      if (b.childId == childId && b.isValidAt(now)) b,
  ];

  /// Gives [amount] more time on [rule], until midnight.
  Future<void> giveBonus(Rule rule, Duration amount, {DateTime? now}) {
    final t = now ?? DateTime.now();
    return updateFamily(
      family.copyWith(
        state: stateWith(
          family.state,
          bonuses: [
            for (final b in family.state.bonuses)
              if (_recent(b.validUntil, t)) b,
            Bonus.forRule(
              id: newId(),
              childId: rule.childId,
              ruleId: rule.id,
              amount: amount,
              grantedAt: t,
              validUntil: addDays(dayOf(t), 1),
            ),
          ],
        ),
      ),
    );
  }

  /// Takes back a bonus given by mistake.
  Future<void> removeBonus(String id) => updateFamily(
    family.copyWith(
      state: stateWith(
        family.state,
        bonuses: [
          for (final b in family.state.bonuses)
            if (b.id != id) b,
        ],
      ),
    ),
  );

  /// Whether restrictions are lifted for the child on [now]'s day.
  bool dayUnlocked(DateTime now) => family.state.dayUnlocks.any(
    (u) => u.childId == childId && u.coversDay(now),
  );

  /// Lifts (or restores) every restriction until midnight, for the child
  /// shown or [forChild].
  Future<void> setDayUnlocked(bool on, {DateTime? now, String? forChild}) {
    final t = now ?? DateTime.now();
    final childId = forChild ?? this.childId!;
    return updateFamily(
      family.copyWith(
        state: stateWith(
          family.state,
          dayUnlocks: [
            for (final u in family.state.dayUnlocks)
              if (_recent(u.day, t) &&
                  !(u.childId == childId && u.coversDay(t)))
                u,
            if (on) DayUnlock(id: newId(), childId: childId, day: t),
          ],
        ),
      ),
    );
  }

  /// Blocks of the child (or of [forChild]) active at [now].
  List<TemporaryBlock> activeBlocks(DateTime now, {String? forChild}) => [
    for (final b in family.state.temporaryBlocks)
      if (b.childId == (forChild ?? childId) && b.isActiveAt(now)) b,
  ];

  /// Blocks [target] from now until [until] (`null`: until lifted), for
  /// the child shown or each of [children], with the parent's [message].
  Future<void> blockNow(
    AppTarget target,
    DateTime? until, {
    DateTime? now,
    Iterable<String>? children,
    String? message,
  }) {
    final t = now ?? DateTime.now();
    final text = message?.trim();
    return updateFamily(
      family.copyWith(
        state: stateWith(
          family.state,
          temporaryBlocks: [
            for (final b in family.state.temporaryBlocks)
              if (b.until == null || _recent(b.until!, t)) b,
            for (final id in children ?? [childId!])
              TemporaryBlock(
                id: newId(),
                childId: id,
                appTarget: target,
                from: t,
                until: until,
                message: text == null || text.isEmpty ? null : text,
              ),
          ],
        ),
      ),
    );
  }

  /// Most block messages kept for the next time.
  static const blockMessagesKept = 8;

  /// Keeps [message] first among the messages offered with a block.
  Future<void> rememberBlockMessage(String message) {
    final text = message.trim();
    if (text.isEmpty) return Future.value();
    return updateSettings(
      settings.copyWith(
        blockMessages: [
          text,
          for (final m in settings.blockMessages)
            if (m != text) m,
        ].take(blockMessagesKept).toList(),
      ),
    );
  }

  /// No longer offers [message].
  Future<void> forgetBlockMessage(String message) => updateSettings(
    settings.copyWith(
      blockMessages: [
        for (final m in settings.blockMessages)
          if (m != message) m,
      ],
    ),
  );

  /// The child takes a break from every app (phone and messages aside)
  /// for [length], starting now. It cannot be cut short from the child's
  /// side: only the parent can lift it.
  Future<void> startPause(Duration length, {DateTime? now}) {
    final t = now ?? DateTime.now();
    return updateFamily(
      family.copyWith(
        state: stateWith(
          family.state,
          temporaryBlocks: [
            for (final b in family.state.temporaryBlocks)
              if (b.until == null || _recent(b.until!, t)) b,
            TemporaryBlock(
              id: newId(),
              childId: childId!,
              from: t,
              until: t.add(length),
              voluntary: true,
            ),
          ],
        ),
      ),
    );
  }

  /// End of the next allowed range of [r]'s hours, when [r] is outside its
  /// hours at [now] and the next range starts later today; `null` otherwise.
  DateTime? nextRangeEnd(Rule r, DateTime now) {
    final schedule = r.schedule;
    if (schedule == null || schedule.allows(now)) return null;
    final start = schedule.nextStart(now);
    if (start == null || !sameDay(start, now)) return null;
    final length = schedule.untilEnd(start);
    return length == null ? null : start.add(length);
  }

  /// Rules whose hours can be opened early now: outside their hours, not
  /// already opened, with a range later today; for the child shown or
  /// [forChild].
  List<(Rule, DateTime)> openableEarly(DateTime now, {String? forChild}) => [
    for (final r in family.state.rules)
      if (r.childId == (forChild ?? childId) &&
          r.enabled &&
          !r.setByChild &&
          ruleInForce(r, now) &&
          !hoursOpenedEarly(
            now,
            forChild: forChild,
          ).any((u) => u.ruleId == r.id))
        if (nextRangeEnd(r, now) case final end?) (r, end),
  ];

  /// Early openings of hours in force at [now].
  List<HoursUnlock> hoursOpenedEarly(DateTime now, {String? forChild}) => [
    for (final u in family.state.hoursUnlocks)
      if (u.childId == (forChild ?? childId) && u.isActiveAt(now)) u,
  ];

  /// Opens [r]'s hours from now until [until] (the end of its next range):
  /// its time limits still apply.
  Future<void> openHoursEarly(Rule r, DateTime until, {DateTime? now}) {
    final t = now ?? DateTime.now();
    return updateFamily(
      family.copyWith(
        state: stateWith(
          family.state,
          hoursUnlocks: [
            for (final u in family.state.hoursUnlocks)
              if (_recent(u.until, t)) u,
            HoursUnlock(
              id: newId(),
              childId: r.childId,
              ruleId: r.id,
              from: t,
              until: until,
            ),
          ],
        ),
      ),
    );
  }

  /// Ends an early opening now.
  Future<void> closeHoursEarly(String id, {DateTime? now}) {
    final t = now ?? DateTime.now();
    return updateFamily(
      family.copyWith(
        state: stateWith(
          family.state,
          hoursUnlocks: [
            for (final u in family.state.hoursUnlocks)
              u.id == id
                  ? HoursUnlock(
                      id: u.id,
                      childId: u.childId,
                      ruleId: u.ruleId,
                      from: u.from,
                      until: t,
                    )
                  : u,
          ],
        ),
      ),
    );
  }

  /// Durations offered in one tap for the child, in minutes, ascending.
  List<int> get presets => [...(child?.presets ?? defaultPresets)]..sort();

  /// Sets the durations offered in one tap for the child.
  /// Sets the media volume caps of this device's child, in percent (`null`:
  /// no cap).
  Future<void> setVolumeCap({int? headphones, int? speaker}) {
    final id = childId;
    return updateFamily(
      family.copyWith(
        children: [
          for (final c in family.children)
            c.id == id
                ? c.withVolume(headphones: headphones, speaker: speaker)
                : c,
        ],
      ),
    );
  }

  /// Sets the child's eye breaks.
  Future<void> setEyeBreak(EyeBreakPolicy policy) {
    final id = childId;
    return updateFamily(
      family.copyWith(
        children: [
          for (final c in family.children)
            c.id == id ? c.withEyeBreak(policy) : c,
        ],
      ),
    );
  }

  Future<void> setPresets(List<int> minutes) {
    final id = childId;
    final sorted = {...minutes}.where((m) => m > 0).toList()..sort();
    return updateFamily(
      family.copyWith(
        children: [
          for (final c in family.children)
            c.id == id ? c.withPresets(sorted) : c,
        ],
      ),
    );
  }

  /// Ends a block now; it stays in the history.
  Future<void> liftBlock(String id, {DateTime? now}) {
    final t = now ?? DateTime.now();
    return updateFamily(
      family.copyWith(
        state: stateWith(
          family.state,
          temporaryBlocks: [
            for (final b in family.state.temporaryBlocks)
              b.id == id ? b.endingAt(t) : b,
          ],
        ),
      ),
    );
  }

  /// Time entered today for away from the devices, latest first.
  List<UsageSegment> injectedToday(DateTime now) => [
    for (final u in family.injected.reversed)
      if (u.childId == childId && sameDay(u.end, now)) u,
  ];

  /// Counts [length] spent away from the devices on [target], as if it
  /// ended now.
  Future<void> addAwayTime(AppTarget target, Duration length, {DateTime? now}) {
    final t = now ?? DateTime.now();
    return updateFamily(
      family.copyWith(
        injected: [
          for (final u in family.injected)
            if (_recent(u.end, t)) u,
          UsageSegment.injected(
            childId: childId!,
            injectedTarget: target,
            start: t.subtract(length),
            end: t,
          ),
        ],
      ),
    );
  }

  /// Removes time entered by mistake.
  Future<void> removeAwayTime(UsageSegment segment) => updateFamily(
    family.copyWith(
      injected: [
        for (final u in family.injected)
          if (!identical(u, segment)) u,
      ],
    ),
  );

  // --- Always accessible apps ----------------------------------------------

  /// Apps never limited by time: [anyTime] ones even outside the hours, in
  /// blocks and on a locked device; the others only within the hours.
  Future<void> setAccessible(String app, {required bool anyTime}) =>
      updateFamily(
        family.copyWith(
          config: family.config.copyWith(
            alwaysAllowed: {
              ...family.config.alwaysAllowed.where((a) => a != app),
              if (anyTime) app,
            },
            allowedInHours: {
              ...family.config.allowedInHours.where((a) => a != app),
              if (!anyTime) app,
            },
          ),
        ),
      );

  /// Limits [app] like any other again.
  Future<void> removeAccessible(String app) => updateFamily(
    family.copyWith(
      config: family.config.copyWith(
        alwaysAllowed: {...family.config.alwaysAllowed.where((a) => a != app)},
        allowedInHours: {
          ...family.config.allowedInHours.where((a) => a != app),
        },
      ),
    ),
  );

  // --- App names ---------------------------------------------------------------

  /// Android's names of the apps limited on their own, by package.
  final Map<String, String> androidLabels = {};

  /// Names and icons of [packages]: from this device, or else as the
  /// family's other devices shared them (apps installed only there).
  Future<Map<String, AppInfo>> appInfo(Iterable<String> packages) async {
    final wanted = packages.toSet();
    final found = <String, AppInfo>{};
    try {
      found.addAll(await platform.appInfo(wanted));
    } on Object {
      // Not available here: the family's devices may know them.
    }
    final missing = wanted.difference(found.keys.toSet());
    if (missing.isNotEmpty) {
      try {
        final log = await sync;
        if (log != null) found.addAll(log.sharedApps(missing));
      } on Object {
        // Package names are shown instead.
      }
    }
    return found;
  }

  /// The apps of this device, and those installed only on the family's
  /// other devices (to limit them from here).
  /// The apps the parent can put in groups or limit: the child's, and
  /// the browsers' videos first.
  Future<List<InstalledApp>> familyApps() async => [
    InstalledApp(browserVideoApp, s.t('browserVideos')),
    for (final a in await _childApps())
      if (a.package != browserVideoApp) a,
  ];

  Future<List<InstalledApp>> _childApps() async {
    // A parent's own apps are not the child's: on a parent's device, only
    // those the child's devices shared.
    final parent = settings.parentDevice;
    final here = parent ? <InstalledApp>[] : await platform.launcherApps();
    final known = {for (final a in here) a.package};
    try {
      final log = await sync;
      final child = childId;
      if (log == null) return parent ? await platform.launcherApps() : here;
      var shared = child == null
          ? <String, String>{}
          : log.childAppNames(child);
      // None shared yet (devices from before 0.21): every device's.
      if (shared.isEmpty && parent) shared = log.sharedAppNames();
      if (shared.isEmpty && parent) return await platform.launcherApps();
      return [
        ...here,
        for (final e in shared.entries)
          if (known.add(e.key)) InstalledApp(e.key, e.value),
      ];
    } on Object {
      return here;
    }
  }

  /// Fetches Android's names of the apps limited on their own.
  Future<void> loadLabels([Iterable<String>? packages]) async {
    final missing = {
      for (final p in packages ?? singleAppTargets(family.state.rules))
        if (!androidLabels.containsKey(p)) p,
    };
    if (missing.isEmpty) return;
    try {
      final info = await appInfo(missing);
      for (final e in info.entries) {
        androidLabels[e.key] = e.value.label;
      }
      if (info.isNotEmpty) notifyListeners();
    } on Object {
      // Package names are shown instead.
    }
  }

  /// Names of the family's devices, by id, this one included.
  Future<Map<String, String>> deviceNames() async {
    final names = <String, String>{};
    try {
      final log = await sync;
      if (log != null) {
        for (final e in log.devices.entries) {
          final name = e.value['name'];
          if (name is String && name.isNotEmpty) names[e.key] = name;
        }
      }
    } on Object {
      // Ids are shown instead.
    }
    if (!names.containsKey(settings.deviceId)) {
      names[settings.deviceId] = await platform.deviceName();
    }
    return names;
  }

  /// Apps left out of the statistics: this device's system components,
  /// those the family's devices shared, and the usual home screens.
  Future<Set<String>> usageExcluded() async {
    final excluded = {...family.config.neverBlocked, ...knownLaunchers};
    try {
      final log = await sync;
      if (log != null) excluded.addAll(log.sharedSystem());
    } on Object {
      // This device's only.
    }
    return excluded;
  }

  /// Name shown for [r].
  String labelOf(Rule r) => ruleLabel(r, family, s, labels: androidLabels);

  /// Time spent today on [target], as its rules count it.
  Future<Duration> timeToday(AppTarget target) async {
    final childId = this.childId;
    if (childId == null) return Duration.zero;
    final now = DateTime.now();
    final today = dayOf(now);
    return RuleEngine(family.config).consumption(
      FamilyState(
        usage: [
          ...await store.loadUsage(since: today),
          ...family.injected,
        ],
      ),
      Rule(id: '', childId: childId, appTarget: target),
      childId: childId,
      from: today,
      to: now,
    );
  }

  /// Name of what [target] covers, in sentences about blocking.
  String targetLabel(AppTarget target) => switch (target.kind) {
    TargetKind.all => s.t('allApps'),
    TargetKind.group => groupName(target.id!),
    TargetKind.single => appName(
      target.id!,
      androidLabel: androidLabels[target.id],
    ),
  };

  /// Time spent today on every counted app, as total screen time counts it.
  Future<Duration> totalTimeToday() async {
    final childId = this.childId;
    if (childId == null) return Duration.zero;
    final now = DateTime.now();
    final today = dayOf(now);
    return RuleEngine(family.config).consumption(
      FamilyState(
        usage: [
          ...await store.loadUsage(since: today),
          ...family.injected,
        ],
      ),
      Rule(id: '', childId: childId),
      childId: childId,
      from: today,
      to: now,
    );
  }

  /// The child's rules targeting the group [id].
  List<Rule> groupRules(String id) => targetRules(AppTarget.group(id));

  /// The parent's rules with [target], turned off ones included (the
  /// child's own limits have their own place).
  List<Rule> targetRules(AppTarget target) =>
      childRules.where((r) => r.appTarget == target && !r.setByChild).toList();

  /// The parent's rules, without the limits the child set.
  List<Rule> get parentRules => childRules.where((r) => !r.setByChild).toList();

  /// Limits the child set for themselves.
  List<Rule> get selfLimits => childRules.where((r) => r.setByChild).toList();

  /// Creates or changes a limit the child sets for themselves, and logs it.
  Future<void> saveSelfLimit(
    AppTarget target,
    Duration daily, {
    String? id,
    DateTime? now,
  }) {
    final t = now ?? DateTime.now();
    final ruleId = id ?? newId();
    final rule = Rule(
      id: ruleId,
      childId: childId!,
      appTarget: target,
      dailyQuota: daily,
      setByChild: true,
    );
    return updateFamily(
      family.copyWith(
        state: stateWithRules(family.state, [
          for (final r in family.state.rules)
            if (r.id != ruleId) r,
          rule,
        ]),
        selfLimitLog: [
          ...family.selfLimitLog,
          SelfLimitEvent(
            at: t,
            ruleId: ruleId,
            action: id == null
                ? SelfLimitAction.created
                : SelfLimitAction.changed,
            target: target,
            daily: daily,
          ),
        ],
      ),
    );
  }

  /// Removes a limit the child set, and logs it.
  Future<void> removeSelfLimit(Rule rule, {DateTime? now}) => updateFamily(
    family.copyWith(
      state: stateWithRules(family.state, [
        for (final r in family.state.rules)
          if (r.id != rule.id) r,
      ]),
      selfLimitLog: [
        ...family.selfLimitLog,
        SelfLimitEvent(
          at: now ?? DateTime.now(),
          ruleId: rule.id,
          action: SelfLimitAction.removed,
          target: rule.appTarget,
        ),
      ],
    ),
  );

  /// Time spent today in each group, counted as the rules count it.
  Future<Map<String, Duration>> groupTimesToday() async {
    final childId = this.childId;
    if (childId == null) return const {};
    final now = DateTime.now();
    final today = dayOf(now);
    final state = FamilyState(
      usage: [
        ...await store.loadUsage(since: today),
        ...family.injected,
      ],
    );
    final engine = RuleEngine(family.config);
    return {
      for (final id in childGroups.keys)
        id: engine.consumption(
          state,
          Rule(id: '', childId: childId, appTarget: AppTarget.group(id)),
          childId: childId,
          from: today,
          to: now,
        ),
    };
  }

  /// Name shown for an app: the parent's name for it, else Android's.
  String appName(String package, {String? androidLabel}) =>
      family.appNames[package] ??
      androidLabel ??
      (package == browserVideoApp ? s.t('browserVideos') : package);

  Future<void> renameApp(String package, String? name) async {
    final names = {...family.appNames};
    if (name == null || name.trim().isEmpty) {
      names.remove(package);
    } else {
      names[package] = name.trim();
    }
    await updateFamily(family.copyWith(appNames: names));
  }

  // --- Parent mode ----------------------------------------------------------

  bool get parentMode => _parentMode;

  void enterParentMode() {
    _parentMode = true;
    touch();
    notifyListeners();
  }

  /// Any touch keeps parent mode open.
  void touch() {
    if (!_parentMode) return;
    _parentTimer?.cancel();
    _parentTimer = Timer(parentModeTimeout, leaveParentMode);
    _tellPlatform(true);
  }

  /// Lets the protected Android settings open while parent mode is on.
  void _tellPlatform(bool on) {
    platform
        .setParentMode(
          on,
          duration: parentModeTimeout,
          texts: {
            'title': s.t('parentModeOnTitle'),
            'text': s.t('parentModeOnText'),
            'leave': s.t('parentModeLeave'),
          },
        )
        .catchError((Object _) {});
  }

  void leaveParentMode() {
    if (!_parentMode) return;
    _parentMode = false;
    _parentKey = null;
    _enteredCode = null;
    _parentTimer?.cancel();
    _tellPlatform(false);
    navigatorKey.currentState?.popUntil((route) => route.isFirst);
    notifyListeners();
  }

  @override
  void dispose() {
    _receipts?.cancel();
    _lan?.stop();
    _relay?.stop();
    _parentTimer?.cancel();
    super.dispose();
  }
}

// --- Editing helpers ---------------------------------------------------------

FamilyConfig configWithGroups(
  FamilyConfig c,
  Map<String, Set<String>> appGroups,
) => c.copyWith(appGroups: appGroups);

/// [c] with its calendar profiles replaced.
FamilyConfig configWithProfiles(FamilyConfig c, List<Profile> profiles) =>
    c.copyWith(profiles: profiles);

/// [s] with some of its one-off actions replaced.
FamilyState stateWith(
  FamilyState s, {
  List<Bonus>? bonuses,
  List<TemporaryBlock>? temporaryBlocks,
  List<DayUnlock>? dayUnlocks,
  List<HoursUnlock>? hoursUnlocks,
}) => s.copyWith(
  bonuses: bonuses,
  temporaryBlocks: temporaryBlocks,
  dayUnlocks: dayUnlocks,
  hoursUnlocks: hoursUnlocks,
);

FamilyState stateWithRules(FamilyState s, List<Rule> rules) =>
    s.copyWith(rules: rules);
