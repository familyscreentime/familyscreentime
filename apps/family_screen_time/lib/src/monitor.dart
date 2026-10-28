/// The monitor: runs in the foreground service, records usage, asks the
/// rule engine for a decision and has it carried out (countdown, warnings,
/// block screen).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:screentime_engine/screentime_engine.dart';

import 'availability.dart';
import 'eye_breaks.dart';

import 'package:screentime_sync/screentime_sync.dart'
    show Accepted, LanDirectory, LanSync, RemoteSource;

import 'sync/bonsoir_directory.dart';
import 'sync/family_sync.dart';
import 'sync/receipts.dart';
import 'sync/relay_runner.dart';
import 'family.dart';
import 'platform.dart';
import 'store.dart';
import 'strings.dart';

/// Longest grace time for which reminders are planned.
const _maxGraceReminders = Duration(hours: 4);

/// Time shown in a warning: whole minutes rounded up, so a warning sent at
/// 4 min 59 s says "5 min"; seconds under half a minute.
Duration warningTime(Duration d) {
  if (d < const Duration(seconds: 30)) return d;
  return Duration(minutes: (d.inSeconds + 59) ~/ 60);
}

class Monitor {
  static const _channel = MethodChannel('org.familyscreentime/monitor');

  final LocalStore store;

  /// Finds the family's devices on the network (DNS-SD by default).
  final LanDirectory Function() lanDirectory;

  Monitor(this.store, {LanDirectory Function()? lanDirectory})
    : lanDirectory = lanDirectory ?? BonsoirDirectory.new;

  AppSettings? _settings;
  FamilyData _family = const FamilyData();
  List<UsageSegment> _usage = [];
  S _s = const S('en');

  String? _foreground;

  /// Usage id the foreground app is recorded under: the app itself, or
  /// its "listen only" id while it is open only to pick the music.
  String? _recordAs;
  DateTime? _openStart;
  bool _screenOn = true;

  Timer? _next;
  Timer? _heartbeat;
  final _warned = <String>{};
  String? _blockedApp;
  DateTime? _blockedAt;

  /// Apps on screen, from Android (with the accessibility service): the
  /// one in front and those beside it (split screen, floating video,
  /// free windows).
  Set<String> _visible = {};

  /// The apps on screen besides the one in front, with when the stretch
  /// of their use not recorded yet began.
  final Map<String, DateTime> _alsoOpen = {};

  /// When each of them was last blocked.
  final Map<String, DateTime> _alsoBlocked = {};

  /// Time until one of them runs out, set by the last evaluation.
  Duration? _alsoSoonest;
  bool _busy = false;
  bool _again = false;

  /// End of the time shown by the floating countdown, set by the last
  /// evaluation; `null` hides it.
  DateTime? _overlayEnd;
  DateTime? _overlaySentEnd;
  String? _overlaySentStyle;

  /// The child's eye breaks on this device.
  final _eye = EyeBreaks();

  /// Time until the next eye-break step, set by the last evaluation.
  Duration? _eyeNext;

  Future<void> start() async {
    // A parent's device limits nothing: Android started this by mistake.
    if ((await store.loadSettings()).parentDevice) {
      await _channel.invokeMethod('unwanted');
      return;
    }
    _channel.setMethodCallHandler(_onCall);
    await _load();
    await _prune();
    await _recoverOpenSegment();
    await _fillGap();
    final state =
        await _channel.invokeMapMethod<String, Object?>('state') ?? {};
    _screenOn = state['screenOn'] as bool? ?? true;
    final fg = state['foreground'] as String?;
    if (_screenOn && fg != null) {
      _foreground = fg;
      _recordAs = fg;
      _openStart = DateTime.now();
    }
    _heartbeat = Timer.periodic(const Duration(seconds: 30), (_) => _tick());
    await _evaluate();
  }

  Future<void> _load() async {
    _settings = await store.loadSettings();
    _s = S.of(_settings!.language);
    _family = withKnownSystem(await store.loadFamily());
    final since = addDays(dayOf(DateTime.now()), -usageHistoryDays);
    await _loadLabels();
    // Time entered by the parent counts too.
    _usage = [...await store.loadUsage(since: since), ..._family.injected];
    await _syncVolume();
    await _openLog();
  }

  /// Forgets the use of apps older than the family keeps it (once a day).
  Future<void> _prune() async {
    try {
      await store.pruneUsage(_family.usageKeptDays);
    } on Object catch (e) {
      debugPrint('Old usage not removed: $e');
    }
  }

  /// The family log, once the family exists on this device.
  FamilySync? _log;

  /// Opens the family log once it exists, and takes in what the interface
  /// recorded there. Never stops the monitor.
  Future<void> _openLog() async {
    try {
      // Linked to other devices, or unlinked, from the interface: the log
      // in use changed.
      final current = await SyncFiles(store).currentDatabase();
      if (_log != null && _log!.dbName != current) await _closeLog();
      final log = _log ??= await FamilySync.open(store, background: true);
      if (log == null) return;
      await log.readOthers();
      // What concerns the other children goes (see FamilySync.tidy).
      if (await log.tidy(store) != null) {
        _family = withKnownSystem(await store.loadFamily());
        final since = addDays(dayOf(DateTime.now()), -usageHistoryDays);
        _usage = [...await store.loadUsage(since: since), ..._family.injected];
        try {
          await _channel.invokeMethod('familyChanged');
        } on Object {
          // The interface reads it when next opened.
        }
      }
      await _logUsageHistory(log);
      // Joined a family: the use of the other devices before counts too.
      if (await log.importOthersUsage(store) > 0) {
        final since = addDays(dayOf(DateTime.now()), -usageHistoryDays);
        _usage = [...await store.loadUsage(since: since), ..._family.injected];
      }
      log.pruneUsage();
      await _startLan(log);
      _receiptsSoon(log);
      final relay = _relay ??= RelayRunner(log)..screenOn = _screenOn;
      await relay.update();
      await _publishApps(log);
    } on Object catch (e) {
      debugPrint('Family log: $e');
    }
  }

  /// Shares the names and icons of the apps installed here with the
  /// family's devices, once a day and whenever an app is installed or
  /// removed.
  Future<void> _publishApps(FamilySync log, {bool now = false}) async {
    try {
      final done = log.files.appsPublished;
      final today = dayToJson(DateTime.now());
      if (!now && await done.exists() && await done.readAsString() == today) {
        return;
      }
      final watch = Stopwatch()..start();
      const platform = PlatformApi();
      final apps = await platform.launcherApps();
      final shared = log.publishedApps();
      // Icons are drawn only for the apps not shared yet.
      final icons = await platform.appInfo([
        for (final a in apps)
          if (!shared.containsKey(a.package)) a.package,
      ], iconSize: sharedIconSize);
      final changes = await log.publishApps({
        for (final a in apps) a.package: a.label,
      }, icons: icons);
      debugPrint(
        'Apps shared: ${apps.length} apps, $changes changes, '
        '${watch.elapsedMilliseconds} ms',
      );
      final system = await platform.systemPackages();
      await log.publishSystem({system.self, ...system.launchers});
      await done.writeAsString(today);
    } on Object catch (e) {
      debugPrint('Apps not shared: $e');
    }
  }

  LanSync? _lan;
  Future<void> _remoteQueue = Future.value();

  /// The relay server, when the parent set one up.
  RelayRunner? _relay;

  Timer? _receipts;

  /// Says in the log, a few seconds after things came in, what this
  /// device now holds (the parent sees what reached it).
  void _receiptsSoon(FamilySync log) {
    _receipts?.cancel();
    _receipts = Timer(const Duration(seconds: 3), () async {
      try {
        if (identical(_log, log)) await recordReceipts(log);
      } on Object catch (e) {
        debugPrint('Receipts not recorded: $e');
      }
    });
  }

  Future<void> _closeLog() async {
    final lan = _lan;
    _lan = null;
    final relay = _relay;
    _relay = null;
    final log = _log;
    _log = null;
    await lan?.stop();
    await relay?.stop();
    await log?.close();
  }

  /// The family's other devices on the local network: kept in sync while
  /// they are reachable.
  Future<void> _startLan(FamilySync log) async {
    if (_lan != null) return;
    final lan = _lan = LanSync(
      log.node,
      lanDirectory(),
      onPeersChanged: () => _savePeers(log),
    );
    log.node.accepted.listen((a) {
      if (a.source is! RemoteSource) return;
      // One at a time: each may rewrite the family file and reload.
      _remoteQueue = _remoteQueue.then((_) => _onRemote(log, a));
    });
    try {
      await lan.start();
    } on Object catch (e) {
      debugPrint('Local network sync not started: $e');
    }
  }

  Future<void> _savePeers(FamilySync log) async {
    final lan = _lan;
    if (lan == null) return;
    try {
      await log.savePeers(lan.peers);
    } on Object catch (e) {
      debugPrint('Devices not saved: $e');
    }
  }

  /// Something came from another device: use of apps, or the family's
  /// settings changed there.
  Future<void> _onRemote(FamilySync log, Accepted a) async {
    try {
      _receiptsSoon(log);
      final family = await log.applyRemote(a, store);
      await _load();
      await _evaluate();
      if (family != null) await _channel.invokeMethod('familyChanged');
    } on Object catch (e) {
      debugPrint('Change from another device not applied: $e');
    }
  }

  /// Puts the use recorded before the family existed into the log, once,
  /// so the family's other devices know today's time and the recent days.
  Future<void> _logUsageHistory(FamilySync log) async {
    final done = log.files.usageHistory;
    if (await done.exists()) return;
    final since = addDays(dayOf(DateTime.now()), -usageHistoryDays);
    final recorded = [
      for (final u in await store.loadUsage(since: since))
        if (u.deviceId == log.deviceId) u,
    ];
    for (var i = 0; i < recorded.length; i += 200) {
      await log.recordUsage(recorded.skip(i).take(200));
    }
    await done.writeAsString(DateTime.now().toIso8601String());
  }

  String? _volumeSent;

  /// Sends the child's volume caps to Android when they change.
  Future<void> _syncVolume() async {
    Child? child;
    for (final c in _family.children) {
      if (c.id == _settings?.childId) child = c;
    }
    final cap = {
      'headphones': child?.volumeHeadphones,
      'speaker': child?.volumeSpeaker,
      'message': _s.t('volumeCapped'),
    };
    final key = cap.toString();
    if (key == _volumeSent) return;
    _volumeSent = key;
    await _channel.invokeMethod('volumeCap', cap);
  }

  /// Android's names of the apps limited on their own, for messages.
  Map<String, String> _labels = const {};

  Future<void> _loadLabels() async {
    final packages = singleAppTargets(_family.state.rules);
    if (packages.isEmpty) return;
    try {
      final info = await const PlatformApi().appInfo(packages);
      // Apps installed only on the family's other devices.
      final shared = _log?.sharedApps(
        packages.where((p) => !info.containsKey(p)),
      );
      if (shared != null) info.addAll(shared);
      _labels = {for (final e in info.entries) e.key: e.value.label};
    } on Object {
      // Package names are shown instead.
    }
  }

  /// Closes a segment left open by a crash or a kill, at its last sighting.
  /// The use while the monitor was not running (Android stopped it for
  /// memory, say), from Android's own usage history: the time since the
  /// last use recorded here, up to 12 hours.
  Future<void> _fillGap() async {
    final settings = _settings;
    if (settings == null || settings.childId == null) return;
    final now = DateTime.now();
    DateTime? last;
    for (final u in _usage) {
      if (u.deviceId == settings.deviceId &&
          (last == null || u.end.isAfter(last))) {
        last = u.end;
      }
    }
    // Nothing recorded here yet: the import of Android's history covers it.
    if (last == null || !now.isAfter(last.add(const Duration(seconds: 5)))) {
      return;
    }
    final earliest = now.subtract(const Duration(hours: 12));
    final from = last.isAfter(earliest) ? last : earliest;
    try {
      final raw = await const PlatformApi().usageHistory(
        from,
        now,
        closeOpen: true,
      );
      if (raw == null) return;
      var added = Duration.zero;
      for (final r in raw) {
        final start = r.start.isBefore(from) ? from : r.start;
        final end = r.end.isAfter(now) ? now : r.end;
        if (end.difference(start) < const Duration(seconds: 1)) continue;
        await _record(r.package, start, end);
        added += end.difference(start);
      }
      debugPrint('Use while the monitor was stopped: ${added.inSeconds} s');
    } on Object catch (e) {
      debugPrint('Use while stopped not read: $e');
    }
  }

  Future<void> _recoverOpenSegment() async {
    final open = await store.loadOpen();
    if (open == null) return;
    await _record(open.appId, open.start, open.lastSeen);
    await store.clearOpen();
  }

  Future<Object?> _onCall(MethodCall call) async {
    switch (call.method) {
      case 'foreground':
        final args = call.arguments as Map<Object?, Object?>;
        await _switchTo(args['package'] as String?);
      case 'visible':
        final args = call.arguments as Map<Object?, Object?>;
        _visible = {
          for (final p in args['packages'] as List? ?? const []) p as String,
        };
        await _syncAlsoOpen(DateTime.now());
        await _evaluate();
      case 'screen':
        final args = call.arguments as Map<Object?, Object?>;
        _screenOn = args['on'] as bool? ?? true;
        _relay?.screenOn = _screenOn;
        if (!_screenOn) {
          _visible = {};
          await _eyeCancel();
          await _switchTo(null);
        }
      case 'eyeBreak':
        final args = call.arguments as Map<Object?, Object?>;
        final now = DateTime.now();
        switch (args['action']) {
          case 'later':
            _eye.snooze(_eyePolicy, now);
          case 'now':
            _eye.startNow(now);
          case 'busy':
            // The veil could not show (a call): its time counts after all.
            if (_eye.veilUntil(now) != null) _resumeRecording(now);
            _eye.busy(now);
        }
        await _evaluate();
      case 'reload':
        // Became a parent's device, by joining others.
        if ((await store.loadSettings()).parentDevice) {
          await _closeLog();
          await _channel.invokeMethod('unwanted');
          return null;
        }
        await _load();
        await _evaluate();
      case 'appsChanged':
        // Installed or removed just now: the family's devices know at once,
        // so the parent can limit a new app straight away.
        final log = _log;
        if (log != null) await _publishApps(log, now: true);
    }
    return null;
  }

  Future<void> _switchTo(String? app) async {
    final now = DateTime.now();
    await _closeOpen(now);
    _foreground = app;
    _recordAs = app;
    _openStart = app == null ? null : _recordingFrom(now);
    if (app != null) {
      await store.saveOpen(OpenSegment(app, _openStart!, now));
    } else {
      await store.clearOpen();
    }
    await _syncAlsoOpen(now);
    await _evaluate();
  }

  /// Starts or ends the recording of the apps on screen besides the one in
  /// front: an app that comes in front is recorded as such from now on,
  /// the one it replaces as beside it, if it stays on screen.
  Future<void> _syncAlsoOpen(DateTime now) async {
    final want = _screenOn && _foreground != null
        ? ({..._visible}..remove(_foreground))
        : <String>{};
    for (final app in _alsoOpen.keys.toList()) {
      if (want.contains(app)) continue;
      await _record(app, _alsoOpen.remove(app)!, now);
      _alsoBlocked.remove(app);
    }
    for (final app in want) {
      _alsoOpen.putIfAbsent(app, () => _recordingFrom(now));
    }
  }

  /// When use seen at [now] starts counting: at once, or once the eye
  /// break's veil is gone (the time under it is not screen time).
  DateTime _recordingFrom(DateTime now) => _eye.veilUntil(now) ?? now;

  /// Records the use of the apps beside the one in front so far, every
  /// few minutes (a stopped monitor loses little).
  Future<void> _flushAlsoOpen(DateTime now) async {
    for (final e in _alsoOpen.entries.toList()) {
      if (now.difference(e.value) < const Duration(minutes: 5)) continue;
      await _record(e.key, e.value, now);
      _alsoOpen[e.key] = now;
    }
  }

  Future<void> _closeOpen(DateTime now) async {
    final app = _recordAs;
    final start = _openStart;
    if (app == null || start == null) return;
    await _record(app, start, now);
    _openStart = _recordingFrom(now);
  }

  /// Records use of [app] from [start] to [end], split at midnight so each
  /// day's file holds that day's use.
  Future<void> _record(String app, DateTime start, DateTime end) async {
    final settings = _settings;
    if (settings == null || settings.childId == null) return;
    var from = start;
    while (end.difference(from) >= const Duration(seconds: 1)) {
      final midnight = addDays(dayOf(from), 1);
      final to = end.isAfter(midnight) ? midnight : end;
      final segment = UsageSegment.device(
        childId: settings.childId!,
        deviceId: settings.deviceId,
        appId: app,
        start: from,
        end: to,
      );
      _usage.add(segment);
      await store.appendUsage(segment);
      try {
        await _log?.recordUsage([segment]);
      } on Object catch (e) {
        debugPrint('Use not recorded in the family log: $e');
      }
      from = to;
    }
  }

  Future<void> _tick() async {
    final app = _recordAs;
    final start = _openStart;
    if (app != null && start != null) {
      await store.saveOpen(OpenSegment(app, start, DateTime.now()));
    }
    await _flushAlsoOpen(DateTime.now());
    // Once a day, whatever the number of calls.
    await _prune();
    await _evaluate();
  }

  /// Evaluates now. Calls that arrive while an evaluation runs are merged
  /// into one more evaluation afterwards.
  Future<void> _evaluate() async {
    if (_busy) {
      _again = true;
      return;
    }
    _busy = true;
    try {
      do {
        _again = false;
        _overlayEnd = null;
        await _evaluateOnce();
        await _syncOverlay();
      } while (_again);
    } finally {
      _busy = false;
    }
  }

  Future<void> _evaluateOnce() async {
    _next?.cancel();
    _alsoSoonest = null;
    _eyeNext = null;
    final settings = _settings;
    final now = DateTime.now();
    if (settings == null || settings.childId == null) {
      await _countdown(_s.t('monitorSetup'));
      return;
    }
    final app = _foreground;
    if (!_screenOn || app == null) {
      await _eyeCancel();
      await _countdown(_s.t('monitorIdle'));
      _schedule(const Duration(minutes: 1));
      return;
    }

    final start = _openStart;
    final usage = [
      ..._usage,
      if (start != null && now.isAfter(start))
        UsageSegment.device(
          childId: settings.childId!,
          deviceId: settings.deviceId,
          appId: _recordAs ?? app,
          start: start,
          end: now,
        ),
      // The apps beside it count too.
      for (final e in _alsoOpen.entries)
        if (now.isAfter(e.value))
          UsageSegment.device(
            childId: settings.childId!,
            deviceId: settings.deviceId,
            appId: e.key,
            start: e.value,
            end: now,
          ),
    ];
    final s = _family.state;
    final state = s.copyWith(usage: usage);
    final engine = RuleEngine(_family.config);
    final d = engine.evaluate(
      state,
      childId: settings.childId!,
      deviceId: settings.deviceId,
      appId: app,
      now: now,
    );
    // Finishing in grace: no lock until the app is left.
    await _syncLock(
      engine,
      state,
      settings,
      now,
      finishing: d.reason == Reason.gracePeriod,
    );

    // Open only to pick the music: recorded apart from now on, so that
    // this time does not count for the music limit.
    if (d.reason == Reason.listenOnly && _recordAs != listenOnlyUse(app)) {
      await _closeOpen(now);
      _recordAs = listenOnlyUse(app);
      await store.saveOpen(OpenSegment(_recordAs!, now, now));
    }

    if (!d.allowed) {
      // A break (mandatory, or taken by the child) rests the eyes too.
      if (d.reason == Reason.mandatoryBreak || _pauseTaken(app, d, now)) {
        _eye.restedAt = d.until ?? now;
      }
      await _eyeCancel();
      await _block(app, d, now);
      _schedule(_untilDelay(d.until, now));
      return;
    }
    _blockedApp = null;

    // An app beside it with no time left (split screen, floating video):
    // closed too.
    for (final other in _alsoOpen.keys.toList()) {
      final od = engine.evaluate(
        state,
        childId: settings.childId!,
        deviceId: settings.deviceId,
        appId: other,
        now: now,
      );
      if (!od.allowed) {
        final last = _alsoBlocked[other];
        if (last == null ||
            now.difference(last) > const Duration(seconds: 10)) {
          _alsoBlocked[other] = now;
          await _block(other, od, now, beside: true);
        }
        _alsoSoonest = _untilDelay(od.until, now);
        continue;
      }
      final left = od.remaining;
      if (left != null && (_alsoSoonest == null || left < _alsoSoonest!)) {
        _alsoSoonest = left;
      }
    }

    final remaining = d.remaining;
    final label = _label(d.ruleId);
    if (d.reason == Reason.alwaysAllowed) {
      // Home screen, settings, phone, this app…
      await _countdown(_s.t('monitorIdle'));
    } else if (d.reason == Reason.dayUnlocked) {
      await _countdown(_s.t('monitorDayUnlocked'));
    } else if (remaining == null) {
      await _countdown(_s.t('monitorUnlimited'));
    } else {
      final key = switch (d.limiter) {
        Limiter.schedule => 'monitorSchedule',
        Limiter.breakDue => 'monitorBreak',
        Limiter.grace => 'monitorGrace',
        Limiter.listenOnly => 'monitorListenOnly',
        _ => 'monitorQuota',
      };
      await _countdown(_s.t(key, {'label': label}), endsAt: now.add(remaining));
      _overlayEnd =
          _shownEnd(engine, state, settings, app, now) ?? now.add(remaining);
      await _maybeWarn(d, label, remaining, now);
    }
    await _eyeStep(d, usage, settings, now);
    _schedule(_nextDelay(remaining, _thresholds(d)));
  }

  EyeBreakPolicy get _eyePolicy {
    for (final c in _family.children) {
      if (c.id == _settings?.childId) return c.eyeBreak;
    }
    return const EyeBreakPolicy(enabled: false);
  }

  DateTime? _eyeStretch(
    List<UsageSegment> usage,
    AppSettings settings,
    EyeBreakPolicy policy,
    DateTime now,
  ) => policy.enabled
      ? screenStretchStart(
          usage,
          deviceId: settings.deviceId,
          now: now,
          rest: policy.length,
          restedAt: _eye.restedAt,
        )
      : null;

  /// Announces, starts or ends the eye break due at [now], and sets when
  /// to look again.
  Future<void> _eyeStep(
    Decision d,
    List<UsageSegment> usage,
    AppSettings settings,
    DateTime now,
  ) async {
    final policy = _eyePolicy;
    final left = d.remaining;
    final step = _eye.step(
      policy: policy,
      stretchStart: _eyeStretch(usage, settings, policy, now),
      now: now,
      blockSoon: left != null && left <= eyeBlockSoon,
    );
    switch (step.kind) {
      case EyeStepKind.none:
        break;
      case EyeStepKind.notice:
        final count = step.snoozesLeft;
        await _channel.invokeMethod('eyeNotice', {
          'title': _s.t('eyeNoticeTitle'),
          'text': count > 0
              ? _s.t('eyeNoticeText', {'count': '$count'})
              : _s.t('eyeNoticeTextLast'),
          'now': _s.t('eyeNow'),
          'later': count > 0 ? _s.t('eyeLater') : null,
          'endsAt': now.add(EyeBreakPolicy.notice).millisecondsSinceEpoch,
        });
      case EyeStepKind.veil:
        await _pauseRecording(now, step.until!);
        await _channel.invokeMethod('eyeVeil', {
          'title': _s.t('eyeVeilTitle'),
          'text': _s.t('eyeVeilText'),
          'endsAt': step.until!.millisecondsSinceEpoch,
        });
      case EyeStepKind.reminder:
        await _channel.invokeMethod('warn', {
          'title': _s.t('eyeReminderTitle', {'time': _s.duration(step.length)}),
          'text': _s.t('eyeReminderText'),
        });
      case EyeStepKind.hide:
        await _channel.invokeMethod('eyeHide');
    }
    _eyeNext = _eye.next(
      policy: policy,
      stretchStart: _eyeStretch(usage, settings, policy, now),
      now: now,
    );
  }

  /// Takes down the eye break's notice or veil, if shown.
  Future<void> _eyeCancel() async {
    _eyeNext = null;
    if (_eye.cancel()) await _channel.invokeMethod('eyeHide');
  }

  /// Stops recording use from [now] to [until], the time of the veil.
  Future<void> _pauseRecording(DateTime now, DateTime until) async {
    if (_recordAs != null && _openStart != null) {
      await _closeOpen(now);
      _openStart = until;
    }
    for (final app in _alsoOpen.keys.toList()) {
      await _record(app, _alsoOpen[app]!, now);
      _alsoOpen[app] = until;
    }
  }

  /// Records use from [now] again, before the end of the veil.
  void _resumeRecording(DateTime now) {
    final start = _openStart;
    if (start != null && start.isAfter(now)) _openStart = now;
    for (final e in _alsoOpen.entries.toList()) {
      if (e.value.isAfter(now)) _alsoOpen[e.key] = now;
    }
  }

  /// Whether [app] is held only by breaks the child chose to take.
  bool _pauseTaken(String app, Decision d, DateTime now) {
    if (d.reason != Reason.temporaryBlock) return false;
    final blocks = _blocksHolding(app, now);
    return blocks.isNotEmpty && blocks.every((b) => b.voluntary);
  }

  List<TemporaryBlock> _blocksHolding(String app, DateTime now) => [
    for (final b in _family.state.temporaryBlocks)
      if (b.childId == _settings?.childId &&
          b.isActiveAt(now) &&
          b.appTarget.covers(app, _family.config.appGroups))
        b,
  ];

  /// "Your time for today is up. See you tomorrow from 9.", while screen
  /// time only comes back on a later day.
  String? _timeOver;

  /// Last lock state sent to Android, to send changes only.
  String? _lockSent;

  /// Works out whether any screen time is left at all, and has Android
  /// close the settings or lock the device as the parent chose.
  /// End of the floating countdown when the child left some limits out
  /// of it: the nearest end among the others that apply to [app]. `null`
  /// keeps the nearest end of all; [_never] hides the countdown.
  DateTime? _shownEnd(
    RuleEngine engine,
    FamilyState state,
    AppSettings settings,
    String app,
    DateTime now,
  ) {
    final hidden = settings.hiddenCountdowns;
    if (hidden.isEmpty) return null;
    final shown = engine.evaluate(
      state.copyWith(
        rules: [
          for (final r in state.rules)
            if (!hidden.contains(countdownKey(r.appTarget))) r,
        ],
      ),
      childId: settings.childId!,
      deviceId: settings.deviceId,
      appId: app,
      now: now,
    );
    final left = shown.remaining;
    if (!shown.allowed || left == null) return _never;
    return now.add(left);
  }

  /// Marks a countdown the child chose not to see.
  static final _never = DateTime.utc(9999);

  Future<void> _syncLock(
    RuleEngine engine,
    FamilyState state,
    AppSettings settings,
    DateTime now, {
    bool finishing = false,
  }) async {
    final childId = settings.childId!;
    final probe = engine.evaluate(
      state,
      childId: childId,
      deviceId: settings.deviceId,
      appId: probeApp,
      now: now,
    );
    final out = !probe.allowed && !finishing;
    _timeOver =
        out &&
            (probe.reason == Reason.quotaExhausted ||
                probe.reason == Reason.outsideSchedule)
        ? timeOverMessage(
            _s,
            nextAvailable(
              engine,
              state,
              childId: childId,
              deviceId: settings.deviceId,
              now: now,
            ),
            now,
          )
        : null;
    final mode = _family.outOfTime;
    final (title, message) = out ? _explain(probeApp, probe, now) : ('', '');
    final lock = {
      'settingsLocked':
          _family.settingsParentOnly || (out && mode != OutOfTime.apps),
      'deviceLocked': out && mode == OutOfTime.device,
      'title': title,
      'message': message,
      'settingsTitle': _s.t('settingsClosedTitle'),
      'settingsMessage': out ? message : _s.t('settingsClosedParent'),
      'open': _s.t('lockOpen'),
      // Apps that stay open on a locked device: those at any hour, and
      // those within the hours while it is within the hours.
      'exempt': [
        ..._family.config.alwaysAllowed,
        for (final app in _family.config.allowedInHours)
          if (engine
              .evaluate(
                state,
                childId: childId,
                deviceId: settings.deviceId,
                appId: app,
                now: now,
              )
              .allowed)
            app,
      ]..sort(),
    };
    final key = lock.toString();
    if (key == _lockSent) return;
    _lockSent = key;
    await _channel.invokeMethod('lockState', lock);
  }

  /// Times left at which a warning is due for decision [d]: the child's
  /// choice normally; during grace time, every few minutes as the parent
  /// set it.
  List<Duration> _thresholds(Decision d) {
    if (d.reason == Reason.gracePeriod) {
      final every = _family.graceReminderMinutes;
      if (every <= 0) return const [];
      return [
        for (
          var m = every;
          Duration(minutes: m) <= _maxGraceReminders;
          m += every
        )
          Duration(minutes: m),
      ];
    }
    return [
      for (final m in _settings?.warningMinutes ?? defaultWarningMinutes)
        if (m > 0) Duration(minutes: m),
    ];
  }

  /// Shows, moves or hides the floating countdown chosen by the child.
  /// Changes of under two seconds are not sent: the overlay counts down by
  /// itself.
  Future<void> _syncOverlay() async {
    final style = _settings?.overlay ?? 'off';
    final end = style == 'off' || _overlayEnd == _never ? null : _overlayEnd;
    final sent = _overlaySentEnd;
    if (end == null) {
      if (_overlaySentStyle == null) return;
      _overlaySentEnd = null;
      _overlaySentStyle = null;
      await _channel.invokeMethod('overlayHide');
      return;
    }
    if (style == _overlaySentStyle &&
        sent != null &&
        end.difference(sent).abs() < const Duration(seconds: 2)) {
      return;
    }
    _overlaySentEnd = end;
    _overlaySentStyle = style;
    await _channel.invokeMethod('overlay', {
      'endsAt': end.millisecondsSinceEpoch,
      'style': style,
    });
  }

  /// Title and message saying why [app] is blocked by [d].
  (String, String) _explain(String app, Decision d, DateTime now) {
    final until = d.until;
    // No screen time left today: say when it comes back.
    final over = _timeOver;
    if (over != null &&
        (d.reason == Reason.quotaExhausted ||
            d.reason == Reason.outsideSchedule)) {
      return (_s.t('blockTitleTime'), over);
    }
    // A break the child chose: every block holding the app is voluntary.
    final pause = _pauseTaken(app, d, now);
    // The parent's few words, from the latest block that has some.
    TemporaryBlock? latest;
    if (d.reason == Reason.temporaryBlock) {
      for (final b in _blocksHolding(app, now)) {
        if (b.message != null &&
            (latest == null || b.from.isAfter(latest.from))) {
          latest = b;
        }
      }
    }
    final said = latest?.message;
    final why = switch (d.reason) {
      Reason.familyBlock => _s.t('blockFamily'),
      Reason.temporaryBlock when pause => _s.t('blockPause', {
        'time': _s.time(until ?? now),
      }),
      Reason.temporaryBlock when until != null => _s.t('blockTemporaryUntil', {
        'time': _s.time(until),
      }),
      Reason.temporaryBlock => _s.t('blockTemporary'),
      Reason.outsideSchedule when until != null => _s.t('blockScheduleUntil', {
        'time': _s.time(until),
      }),
      Reason.outsideSchedule => _s.t('blockSchedule'),
      Reason.mandatoryBreak => _s.t('blockBreak', {
        'time': _s.time(until ?? now),
      }),
      Reason.quotaExhausted when _rule(d.ruleId)?.listenOnly != null => _s.t(
        until == null ? 'blockListenOnly' : 'blockListenOnlyUntil',
        {'label': _label(d.ruleId), 'time': _s.time(until ?? now)},
      ),
      _ when _rule(d.ruleId)?.setByChild ?? false => _s.t('blockSelfLimit', {
        'label': _label(d.ruleId),
        'time': _s.duration(_rule(d.ruleId)!.dailyQuota ?? Duration.zero),
      }),
      _ => _s.t('blockQuota', {'label': _label(d.ruleId)}),
    };
    final message = said == null ? why : '$said\n$why';
    // Out of time: said plainly, so the closing is not taken for a crash.
    final listen =
        d.reason == Reason.quotaExhausted &&
        _rule(d.ruleId)?.listenOnly != null;
    final title = _s.t(
      pause
          ? 'blockTitlePause'
          : listen
          ? 'blockTitleListen'
          : d.reason == Reason.quotaExhausted
          ? 'blockTitleTime'
          : 'blockTitle',
    );
    return (title, message);
  }

  /// Closes [app] and says why. [beside]: an app on screen beside the one
  /// in front, which stays in the countdown's notification.
  Future<void> _block(
    String app,
    Decision d,
    DateTime now, {
    bool beside = false,
  }) async {
    final (title, message) = _explain(app, d, now);
    if (!beside) {
      await _countdown(message);
      // Show the block screen once per arrival in the app; again after
      // 10 s in case the child is still there (no accessibility service).
      final again =
          _blockedAt == null ||
          now.difference(_blockedAt!) > const Duration(seconds: 10);
      if (_blockedApp == app && !again) return;
      _blockedApp = app;
      _blockedAt = now;
    }
    await _channel.invokeMethod('block', {
      'title': title,
      'message': message,
      // "{app}" is filled in by Android with the app's name, unless the
      // parent renamed it.
      'closed': _s.t(
        d.reason == Reason.quotaExhausted && _rule(d.ruleId)?.listenOnly != null
            ? 'blockListenClosed'
            : 'blockClosed',
        {if (_family.appNames[app] != null) 'app': _family.appNames[app]!},
      ),
      'package': app,
      'ok': _s.t('ok'),
      'home': _s.t('blockHome'),
      'open': _s.t('blockOpen'),
    });
  }

  Future<void> _maybeWarn(
    Decision d,
    String label,
    Duration remaining,
    DateTime now,
  ) async {
    // Listen only: said once per opening, no countdown warnings.
    if (d.reason == Reason.listenOnly) {
      final opening =
          '${d.ruleId}|listen|${_openStart?.millisecondsSinceEpoch}';
      if (_warned.add(opening)) {
        await _channel.invokeMethod('warn', {
          'title': _s.t('listenWarnTitle', {
            'time': _s.duration(warningTime(remaining)),
          }),
          'text': _s.t('listenWarnText'),
        });
      }
      return;
    }
    final grace = d.reason == Reason.gracePeriod;
    final prefix =
        '${dayToJson(now)}|${d.ruleId}|${grace ? 'grace' : d.limiter?.name}';
    String key(Object t) => '$prefix|$t';
    final ascending = [..._thresholds(d)]..sort();

    Future<void> warn() => _channel.invokeMethod('warn', {
      'title': _s.t(grace ? 'graceWarnTitle' : 'warnTitle', {
        'time': _s.duration(warningTime(remaining)),
      }),
      'text': _s.t(grace ? 'graceWarnText' : 'warnText', {'label': label}),
    });

    void markFrom(Duration t) {
      for (final other in ascending) {
        if (other >= t) _warned.add(key(other.inMinutes));
      }
    }

    // Entering grace time is always announced, whatever the reminders.
    if (grace && !_warned.contains(key('start'))) {
      _warned.add(key('start'));
      markFrom(remaining);
      await warn();
      return;
    }
    for (final t in ascending) {
      // The nearest threshold not yet passed below.
      if (remaining > t) continue;
      if (_warned.contains(key(t.inMinutes))) return;
      // Mark the larger thresholds too, so only one warning is sent.
      markFrom(t);
      await warn();
      return;
    }
  }

  Rule? _rule(String? id) {
    for (final r in _family.state.rules) {
      if (r.id == id) return r;
    }
    return null;
  }

  String _label(String? ruleId) {
    for (final r in _family.state.rules) {
      if (r.id == ruleId) return ruleLabel(r, _family, _s, labels: _labels);
    }
    return _s.t('allScreens');
  }

  Future<void> _countdown(String title, {DateTime? endsAt}) =>
      _channel.invokeMethod('countdown', {
        'title': title,
        if (endsAt != null) 'endsAt': endsAt.millisecondsSinceEpoch,
      });

  /// Next evaluation: at the end of the remaining time or at the next
  /// warning, and at least every minute.
  Duration _nextDelay(Duration? remaining, List<Duration> thresholds) {
    var delay = const Duration(minutes: 1);
    if (remaining != null) {
      final candidates = [
        remaining,
        for (final t in thresholds)
          if (remaining > t) remaining - t,
      ];
      for (final c in candidates) {
        if (c < delay) delay = c;
      }
    }
    return delay < const Duration(seconds: 1)
        ? const Duration(seconds: 1)
        : delay;
  }

  Duration _untilDelay(DateTime? until, DateTime now) {
    if (until == null) return const Duration(minutes: 1);
    final d = until.difference(now);
    if (d < const Duration(seconds: 1)) return const Duration(seconds: 1);
    return d > const Duration(minutes: 1) ? const Duration(minutes: 1) : d;
  }

  void _schedule(Duration delay) {
    // Sooner when an app beside the one in front runs out first, or an
    // eye break is due.
    for (final sooner in [_alsoSoonest, _eyeNext]) {
      if (sooner != null && sooner < delay) {
        delay = sooner < const Duration(seconds: 1)
            ? const Duration(seconds: 1)
            : sooner;
      }
    }
    _next?.cancel();
    _next = Timer(delay, () => _evaluate());
  }

  void dispose() {
    _receipts?.cancel();
    _lan?.stop();
    _relay?.stop();
    _log?.close();
    _next?.cancel();
    _heartbeat?.cancel();
  }
}
