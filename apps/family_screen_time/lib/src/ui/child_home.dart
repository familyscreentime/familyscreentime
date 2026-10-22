/// Child's home screen: time left per rule, and the way into parent mode.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:screentime_engine/screentime_engine.dart';

import '../availability.dart';
import '../controller.dart';
import '../platform.dart';
import '../rule_status.dart';
import '../strings.dart';
import 'child_settings.dart';
import 'parent_home.dart';
import 'permissions.dart';
import 'pin_dialog.dart';
import 'quick_actions.dart';
import 'rule_history_screen.dart';
import 'self_limit_editor.dart';
import 'usage_screen.dart';
import 'widgets.dart';

class ChildHome extends StatefulWidget {
  final AppController controller;

  const ChildHome({super.key, required this.controller});

  @override
  State<ChildHome> createState() => _ChildHomeState();
}

class _ChildHomeState extends State<ChildHome> with WidgetsBindingObserver {
  List<RuleStatus> _status = const [];

  /// "Your time for today is up. See you tomorrow from 9.", when it is.
  String? _timeOver;

  /// Outside the hours set for all apps: the app itself is closed, but for
  /// parent mode. The text says until when.
  String? _closed;
  Map<String, AppInfo> _info = const {};
  bool _missingPermission = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_refresh);
    _refresh();
    // Statistics from the first day: import Android's history once.
    widget.controller.importHistoryIfNeeded();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.controller.removeListener(_refresh);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final c = widget.controller;
    // Android's names of the apps limited on their own, for the cards.
    await c.loadLabels();
    final usage = await c.recentUsage();
    final missing = await missingRequiredPermission(c);
    final now = DateTime.now();
    final engine = RuleEngine(c.family.config);
    final s = c.family.state;
    final state = s.copyWith(usage: usage);
    final childId = c.settings.childId!;
    // The parent's total screen time first, then the groups and apps, then
    // the limits the child set.
    int rank(Rule r) => r.setByChild
        ? 2
        : r.appTarget.kind == TargetKind.all
        ? 0
        : 1;
    final rules = [
      for (final r in c.activeChildRules)
        if (c.ruleInForce(r, now)) r,
    ]..sort((a, b) => rank(a).compareTo(rank(b)));
    final status = [
      for (final r in rules)
        ruleStatus(engine, state, r, childId: childId, now: now),
    ];
    final probe = engine.evaluate(
      state,
      childId: childId,
      deviceId: c.settings.deviceId,
      appId: probeApp,
      now: now,
    );
    final timeOver =
        !probe.allowed &&
            (probe.reason == Reason.quotaExhausted ||
                probe.reason == Reason.outsideSchedule)
        ? timeOverMessage(
            c.s,
            nextAvailable(
              engine,
              state,
              childId: childId,
              deviceId: c.settings.deviceId,
              now: now,
            ),
            now,
          )
        : null;
    final unknown = {
      for (final st in status)
        for (final a in st.apps)
          if (!_info.containsKey(a.$1)) a.$1,
    };
    if (unknown.isNotEmpty) {
      try {
        final info = await c.platform.appInfo(unknown);
        _info = {..._info, ...info};
      } on Object {
        // Package names are shown instead.
      }
    }
    if (mounted) {
      setState(() {
        _status = status;
        _timeOver = timeOver;
        _closed = !probe.allowed && probe.reason == Reason.outsideSchedule
            ? timeOver ??
                  (probe.until == null
                      ? c.s.t('blockSchedule')
                      : c.s.t('blockScheduleUntil', {
                          'time': c.s.time(probe.until!),
                        }))
            : null;
        _missingPermission = missing;
      });
    }
  }

  /// The child takes a break: every app is blocked for the chosen time.
  Future<void> _takePause() async {
    final c = widget.controller;
    final s = c.s;
    final minutes = await showModalBottomSheet<int>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                s.t('pauseAction'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(s.t('pauseHint')),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final m in c.presets)
                    FilledButton.tonal(
                      onPressed: () => Navigator.pop(context, m),
                      child: Text(s.duration(Duration(minutes: m))),
                    ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: Text(s.t('customDurationShort')),
                    onPressed: () async {
                      final d = await askDuration(context, s);
                      if (d != null && context.mounted) {
                        Navigator.pop(context, d.inMinutes);
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (minutes == null) return;
    await c.startPause(Duration(minutes: minutes));
    await _refresh();
  }

  Future<void> _openSelfLimit(Rule? rule) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            SelfLimitEditor(controller: widget.controller, rule: rule),
      ),
    );
    await _refresh();
  }

  Future<void> _openParentMode() async {
    final c = widget.controller;
    if (!await askParentPin(context, c)) return;
    c.enterParentMode();
    if (!mounted) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => ParentHome(controller: c)));
    c.leaveParentMode();
  }

  String _ranges(List<TimeRange> ranges) {
    String hm(int minutes) =>
        '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';
    return ranges
        .map((r) => '${hm(r.startMinute)}–${hm(r.endMinute)}')
        .join(', ');
  }

  static const _shownApps = 8;

  Widget _ruleCard(BuildContext context, RuleStatus st) {
    final c = widget.controller;
    final s = c.s;
    final theme = Theme.of(context);
    final remaining = st.remaining;
    final total = st.dayTotal;
    final left = remaining == null || remaining.isNegative
        ? Duration.zero
        : remaining;
    // Total screen time stands out: tinted, larger, its own icon.
    final isTotal =
        st.rule.appTarget.kind == TargetKind.all && !st.rule.setByChild;
    final mine = st.rule.setByChild;
    final scheme = theme.colorScheme;
    return Card(
      color: isTotal ? scheme.primaryContainer : null,
      elevation: isTotal ? 2 : null,
      child: Padding(
        padding: EdgeInsets.all(isTotal ? 20 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isTotal ? Icons.hourglass_bottom : Icons.folder_outlined,
                  size: isTotal ? 26 : 20,
                  color: isTotal ? scheme.onPrimaryContainer : scheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    mine
                        ? '${c.labelOf(st.rule)} · ${s.t('selfLimitMine')}'
                        : c.labelOf(st.rule),
                    style: isTotal
                        ? theme.textTheme.titleLarge?.copyWith(
                            color: scheme.onPrimaryContainer,
                          )
                        : theme.textTheme.titleMedium,
                  ),
                ),
                if (mine)
                  IconButton(
                    tooltip: s.t('selfLimitTitle'),
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => _openSelfLimit(st.rule),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            if (remaining != null && total != null) ...[
              Text(
                st.bonusToday > Duration.zero
                    ? s.t('leftToday', {'time': s.duration(left)})
                    // 0 min a day: only open with extra time.
                    : total == Duration.zero
                    ? s.t('zeroQuotaChild')
                    : s.t('leftOf', {
                        'left': s.duration(left),
                        'total': s.duration(total),
                      }),
                style: isTotal
                    ? theme.textTheme.headlineMedium?.copyWith(
                        color: scheme.onPrimaryContainer,
                      )
                    : theme.textTheme.headlineSmall,
              ),
              // Extra time given today, set apart from the usual time.
              if (st.bonusToday > Duration.zero)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Wrap(
                    spacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        s.t('usualTime', {
                          'time': s.duration(total - st.bonusToday),
                        }),
                      ),
                      Chip(
                        avatar: const Icon(Icons.card_giftcard, size: 18),
                        label: Text(
                          s.t('bonusChip', {'time': s.duration(st.bonusToday)}),
                        ),
                        backgroundColor: scheme.tertiaryContainer,
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 6),
              LinearProgressIndicator(
                value: total == Duration.zero
                    ? 1
                    : (st.usedToday.inSeconds / total.inSeconds).clamp(0, 1),
                minHeight: isTotal ? 12 : 8,
                borderRadius: BorderRadius.circular(4),
              ),
            ] else if (remaining != null)
              Text(
                remaining <= Duration.zero
                    ? s.t('used')
                    : s.t('leftToday', {'time': s.duration(remaining)}),
                style: theme.textTheme.headlineSmall,
              ),
            if (st.limitedByPeriod)
              Text(s.t('limitedByWeek'), style: theme.textTheme.bodySmall),
            if (st.rule.listenOnly != null)
              Text(
                s.t('listenOnlyChild', {
                  'time': s.duration(st.rule.listenOnly!.openFor),
                }),
              ),
            if (st.savingsLeft != null && st.savingsLeft! > Duration.zero)
              Text(s.t('savings', {'time': s.duration(st.savingsLeft!)})),
            if (st.rangesToday != null)
              Text(
                st.rangesToday!.isEmpty
                    ? s.t('noScheduleToday')
                    : s.t('scheduleToday', {
                        'ranges': _ranges(st.rangesToday!),
                      }),
              ),
            // Total screen time and single apps: no list of apps.
            if (st.rule.appTarget.kind != TargetKind.group) ...[
              if (st.awayToday > Duration.zero)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    s.t('awayUsed', {'time': s.duration(st.awayToday)}),
                  ),
                ),
            ] else if (st.apps.isEmpty && st.awayToday == Duration.zero) ...[
              const SizedBox(height: 8),
              Text(s.t('noAppsToday'), style: theme.textTheme.bodySmall),
            ] else ...[
              const SizedBox(height: 8),
              Text(
                s.t('usedToday', {'time': s.duration(st.usedToday)}),
                style: theme.textTheme.labelLarge,
              ),
              for (final (app, time) in st.apps.take(_shownApps))
                _appRow(context, s, app, time),
              if (st.awayToday > Duration.zero) _awayRow(s, st.awayToday),
              if (st.apps.length > _shownApps)
                Text(
                  s.t('moreApps', {'count': '${st.apps.length - _shownApps}'}),
                  style: theme.textTheme.bodySmall,
                ),
            ],
            if (st.rule.hasDailyQuota && !mine)
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton.icon(
                  icon: const Icon(Icons.history, size: 18),
                  // "Savings" only when this limit keeps unused time.
                  label: Text(
                    s.t(
                      st.rule.rollover == null
                          ? 'historyButtonOverruns'
                          : 'historyButton',
                    ),
                  ),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          RuleHistoryScreen(controller: c, rule: st.rule),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Time spent away from the devices, entered by the parent.
  Widget _awayRow(S s, Duration time) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        const Icon(Icons.devices_other, size: 20),
        const SizedBox(width: 8),
        Expanded(child: Text(s.t('awayRow'))),
        Text(s.duration(time)),
      ],
    ),
  );

  Widget _appRow(BuildContext context, S s, String app, Duration time) {
    final info = _info[app];
    final icon = info?.icon;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          if (icon != null)
            Image.memory(icon, width: 20, height: 20, gaplessPlayback: true)
          else
            const Icon(Icons.android, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.controller.appName(app, androidLabel: info?.label),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(s.duration(time)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final s = c.s;
    final theme = Theme.of(context);
    final closed = _closed;
    if (closed != null) {
      return Scaffold(
        appBar: AppBar(title: Text(c.child?.name ?? s.t('appName'))),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.bedtime_outlined,
                  size: 64,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  s.t('appClosedTitle'),
                  style: theme.textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(closed, textAlign: TextAlign.center),
                const SizedBox(height: 24),
                Text(
                  s.t('appClosedHint'),
                  style: theme.textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  icon: const Icon(Icons.lock_outline),
                  label: Text(s.t('parentMode')),
                  onPressed: _openParentMode,
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(c.child?.name ?? s.t('appName')),
        actions: [
          IconButton(
            tooltip: s.t('usageTitle'),
            icon: const Icon(Icons.bar_chart),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => UsageScreen(controller: c),
              ),
            ),
          ),
          IconButton(
            tooltip: s.t('childSettingsTitle'),
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ChildSettings(controller: c),
              ),
            ),
          ),
          IconButton(
            tooltip: s.t('parentMode'),
            icon: const Icon(Icons.lock_outline),
            onPressed: _openParentMode,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_missingPermission)
              Card(
                color: theme.colorScheme.errorContainer,
                child: ListTile(
                  leading: const Icon(Icons.warning_amber),
                  title: Text(s.t('setupIncomplete')),
                ),
              ),
            if (c.activePeriod(DateTime.now()) case final period?)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.event_outlined),
                  title: Text(
                    s.t('periodNowChild', {'name': c.periodName(period)}),
                  ),
                ),
              ),
            if (_timeOver != null)
              Card(
                color: theme.colorScheme.tertiaryContainer,
                child: ListTile(
                  leading: const Icon(Icons.bedtime_outlined),
                  title: Text(_timeOver!),
                ),
              ),
            // What the parent decided for today.
            if (c.dayUnlocked(DateTime.now()))
              Card(
                color: theme.colorScheme.primaryContainer,
                child: ListTile(
                  leading: const Icon(Icons.lock_open),
                  title: Text(s.t('monitorDayUnlocked')),
                ),
              ),
            for (final b in c.activeBlocks(DateTime.now()))
              Card(
                color: b.voluntary
                    ? theme.colorScheme.secondaryContainer
                    : theme.colorScheme.errorContainer,
                child: ListTile(
                  leading: Icon(
                    b.voluntary ? Icons.self_improvement : Icons.block,
                  ),
                  title: Text(blockLine(s, c, b)),
                ),
              ),
            if (_status.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Text(s.t('noLimits'), textAlign: TextAlign.center),
              ),
            for (final st in _status) _ruleCard(context, st),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.add),
                  label: Text(s.t('selfLimitAdd')),
                  onPressed: () => _openSelfLimit(null),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.self_improvement),
                  label: Text(s.t('pauseAction')),
                  onPressed: _takePause,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
