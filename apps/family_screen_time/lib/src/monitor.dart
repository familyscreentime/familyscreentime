/// The monitor: runs in the foreground service, records usage, asks the
/// rule engine for a decision and has it carried out (countdown, warnings,
/// block screen).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:screentime_engine/screentime_engine.dart';

import 'availability.dart';
import 'sync/family_sync.dart';
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

  Monitor(this.store);

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
  bool _busy = false;
  bool _again = false;

  /// End of the time shown by the floating countdown, set by the last
  /// evaluation; `null` hides it.
  DateTime? _overlayEnd;
  DateTime? _overlaySentEnd;
  String? _overlaySentStyle;

  Future<void> start() async {
    _channel.setMethodCallHandler(_onCall);
    await _load();
    await _recoverOpenSegment();
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

  /// The family log, once the family exists on this device.
  FamilySync? _log;

  /// Opens the family log once it exists, and takes in what the interface
  /// recorded there. Never stops the monitor.
  Future<void> _openLog() async {
    try {
      final log = _log ??= await FamilySync.open(store, background: true);
      if (log == null) return;
      await log.readOthers();
      await _logUsageHistory(log);
      log.pruneUsage();
    } on Object catch (e) {
      debugPrint('Family log: $e');
    }
  }

  /// Puts the use recorded before the family existed into the log, once,
  /// so the family's other devices know today's time and the recent days.
  Future<void> _logUsageHistory(FamilySync log) async {
    final done = log.files.usageHistory;
    if (await done.exists()) return;
    final since = addDays(dayOf(DateTime.now()), -usageHistoryDays);
    final recorded = await store.loadUsage(since: since);
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
      _labels = {for (final e in info.entries) e.key: e.value.label};
    } on Object {
      // Package names are shown instead.
    }
  }

  /// Closes a segment left open by a crash or a kill, at its last sighting.
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
      case 'screen':
        final args = call.arguments as Map<Object?, Object?>;
        _screenOn = args['on'] as bool? ?? true;
        if (!_screenOn) await _switchTo(null);
      case 'reload':
        await _load();
        await _evaluate();
    }
    return null;
  }

  Future<void> _switchTo(String? app) async {
    final now = DateTime.now();
    await _closeOpen(now);
    _foreground = app;
    _recordAs = app;
    _openStart = app == null ? null : now;
    if (app != null) {
      await store.saveOpen(OpenSegment(app, now, now));
    } else {
      await store.clearOpen();
    }
    await _evaluate();
  }

  Future<void> _closeOpen(DateTime now) async {
    final app = _recordAs;
    final start = _openStart;
    if (app == null || start == null) return;
    await _record(app, start, now);
    _openStart = now;
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
    final settings = _settings;
    final now = DateTime.now();
    if (settings == null || settings.childId == null) {
      await _countdown(_s.t('monitorSetup'));
      return;
    }
    final app = _foreground;
    if (!_screenOn || app == null) {
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
      await _block(app, d, now);
      _schedule(_untilDelay(d.until, now));
      return;
    }
    _blockedApp = null;

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
    _schedule(_nextDelay(remaining, _thresholds(d)));
  }

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
    final blocks = [
      for (final b in _family.state.temporaryBlocks)
        if (b.childId == _settings?.childId &&
            b.isActiveAt(now) &&
            b.appTarget.covers(app, _family.config.appGroups))
          b,
    ];
    final pause =
        d.reason == Reason.temporaryBlock &&
        blocks.isNotEmpty &&
        blocks.every((b) => b.voluntary);
    final message = switch (d.reason) {
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

  Future<void> _block(String app, Decision d, DateTime now) async {
    final (title, message) = _explain(app, d, now);
    await _countdown(message);
    // Show the block screen once per arrival in the app; again after 10 s
    // in case the child is still there (no accessibility service).
    final again =
        _blockedAt == null ||
        now.difference(_blockedAt!) > const Duration(seconds: 10);
    if (_blockedApp == app && !again) return;
    _blockedApp = app;
    _blockedAt = now;
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
    _next?.cancel();
    _next = Timer(delay, () => _evaluate());
  }

  void dispose() {
    _next?.cancel();
    _heartbeat?.cancel();
  }
}
