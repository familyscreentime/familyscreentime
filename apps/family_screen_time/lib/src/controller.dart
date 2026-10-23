/// State of the interface: settings, family data and parent mode.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:screentime_engine/screentime_engine.dart';
import 'package:screentime_sync/screentime_sync.dart' show SigningKey;

import 'family.dart';
import 'pin.dart';
import 'platform.dart';
import 'self_limits.dart';
import 'store.dart';
import 'strings.dart';
import 'sync/family_sync.dart';

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

  AppController(
    this.store,
    this.settings,
    this.family, {
    this.platform = const PlatformApi(),
  });

  static Future<AppController> load() async {
    final store = await LocalStore.open();
    final deviceLanguage = PlatformDispatcher.instance.locale.languageCode;
    final settings = await store.loadSettings(
      defaultLanguage: S.of(deviceLanguage).language,
    );
    final family = withKnownSystem(await store.loadFamily());
    return AppController(store, settings, family);
  }

  S get s => S.of(settings.language);

  Child? get child => family.child(settings.childId);

  List<Rule> get childRules =>
      family.state.rules.where((r) => r.childId == settings.childId).toList();

  Future<void> updateSettings(AppSettings next) async {
    settings = next;
    await store.saveSettings(next);
    notifyListeners();
    await _reloadMonitor();
  }

  Future<void> updateFamily(FamilyData next) async {
    final before = family;
    family = next;
    await store.saveFamily(next);
    notifyListeners();
    await _recordInLog(before, next);
    await _reloadMonitor();
  }

  // --- Family log -------------------------------------------------------------

  /// The family log, opened once.
  Future<FamilySync?> get sync => _sync ??=
      FamilySync.open(store, background: false).catchError((Object e) {
        debugPrint('Family log not opened: $e');
        return null;
      });

  /// Records the change in the family log, signed by the parent key in
  /// parent mode. A failure never stops the change made here.
  Future<void> _recordInLog(FamilyData before, FamilyData after) async {
    try {
      // First the key: entering the code may be creating the family.
      final key = _parentMode ? await _parentKey : null;
      final log = await sync;
      if (log == null) return;
      await log.readOthers();
      await log.recordChange(before, after, parentKey: key);
    } on Object catch (e) {
      debugPrint('Change not recorded in the family log: $e');
    }
  }

  /// The parent code was just entered: unlocks the parent key, or creates
  /// the family on this device the first time (the code seals its key).
  void parentCodeEntered(String code) {
    _parentKey = () async {
      try {
        final log = await sync;
        if (log != null) return await log.unlock(code);
        if (!settings.setupDone && settings.childId == null) return null;
        final (created, key) = await FamilySync.create(
          store: store,
          settings: settings,
          family: family,
          parentCode: code,
          deviceName: child?.name ?? 'Android',
        );
        _sync = Future.value(created);
        await _reloadMonitor();
        return key;
      } on Object catch (e) {
        debugPrint('Parent key not unlocked: $e');
        return null;
      }
    }();
  }

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

  /// This device was just welcomed into a family ([log]); [code] is the
  /// family's parent code. Takes the family's data and this device's child.
  Future<void> completeJoin(FamilySync log, String code) async {
    final system = await platform.systemPackages();
    final joined = log.compose(FamilyData(config: initialConfig(system)));
    _sync = Future.value(log);
    await store.saveFamily(joined);
    family = joined;
    final childId = log.registration?['childId'] as String?;
    await updateSettings(
      (await withNewPin(settings, code)).copyWith(childId: childId),
    );
    await platform.startMonitor();
  }

  /// Removes a device from the family (in parent mode).
  Future<void> removeDevice(String id) async {
    final log = await sync;
    final key = await parentKey;
    if (log == null || key == null) return;
    await log.removeDevice(id, key);
    notifyListeners();
    await _reloadMonitor();
  }

  /// A device was welcomed from this one: the monitor passes it on.
  Future<void> deviceWelcomed() async {
    notifyListeners();
    await _reloadMonitor();
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
    // The family log, with the code just chosen.
    parentCodeEntered(pin);
    await _parentKey;
    _parentKey = null;
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
    final childId = settings.childId;
    if (settings.historyImported || childId == null) return false;
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

  /// Groups containing [app], ordered by name.
  List<String> groupsOf(String app) =>
      [
        for (final e in family.config.appGroups.entries)
          if (e.value.contains(app)) e.key,
      ]..sort(
        (a, b) =>
            groupName(a).toLowerCase().compareTo(groupName(b).toLowerCase()),
      );

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
      if (b.childId == settings.childId && b.isValidAt(now)) b,
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
    (u) => u.childId == settings.childId && u.coversDay(now),
  );

  /// Lifts (or restores) every restriction until midnight.
  Future<void> setDayUnlocked(bool on, {DateTime? now}) {
    final t = now ?? DateTime.now();
    final childId = settings.childId!;
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

  /// Blocks of the child active at [now].
  List<TemporaryBlock> activeBlocks(DateTime now) => [
    for (final b in family.state.temporaryBlocks)
      if (b.childId == settings.childId && b.isActiveAt(now)) b,
  ];

  /// Blocks [target] from now until [until] (`null`: until lifted).
  Future<void> blockNow(AppTarget target, DateTime? until, {DateTime? now}) {
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
              childId: settings.childId!,
              appTarget: target,
              from: t,
              until: until,
            ),
          ],
        ),
      ),
    );
  }

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
              childId: settings.childId!,
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
  /// already opened, with a range later today.
  List<(Rule, DateTime)> openableEarly(DateTime now) => [
    for (final r in activeChildRules)
      if (!r.setByChild &&
          ruleInForce(r, now) &&
          !hoursOpenedEarly(now).any((u) => u.ruleId == r.id))
        if (nextRangeEnd(r, now) case final end?) (r, end),
  ];

  /// Early openings of hours in force at [now].
  List<HoursUnlock> hoursOpenedEarly(DateTime now) => [
    for (final u in family.state.hoursUnlocks)
      if (u.childId == settings.childId && u.isActiveAt(now)) u,
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
    final id = settings.childId;
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

  Future<void> setPresets(List<int> minutes) {
    final id = settings.childId;
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
      if (u.childId == settings.childId && sameDay(u.end, now)) u,
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
            childId: settings.childId!,
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

  /// Fetches Android's names of the apps limited on their own.
  Future<void> loadLabels([Iterable<String>? packages]) async {
    final missing = {
      for (final p in packages ?? singleAppTargets(family.state.rules))
        if (!androidLabels.containsKey(p)) p,
    };
    if (missing.isEmpty) return;
    try {
      final info = await platform.appInfo(missing);
      for (final e in info.entries) {
        androidLabels[e.key] = e.value.label;
      }
      if (info.isNotEmpty) notifyListeners();
    } on Object {
      // Package names are shown instead.
    }
  }

  /// Name shown for [r].
  String labelOf(Rule r) => ruleLabel(r, family, s, labels: androidLabels);

  /// Time spent today on [target], as its rules count it.
  Future<Duration> timeToday(AppTarget target) async {
    final childId = settings.childId;
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
    final childId = settings.childId;
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
      childId: settings.childId!,
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
    final childId = settings.childId;
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
      for (final id in family.config.appGroups.keys)
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
      family.appNames[package] ?? androidLabel ?? package;

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
    _parentTimer?.cancel();
    _tellPlatform(false);
    navigatorKey.currentState?.popUntil((route) => route.isFirst);
    notifyListeners();
  }

  @override
  void dispose() {
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
