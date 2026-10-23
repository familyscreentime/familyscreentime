/// Creates or edits a rule of one kind of time (total screen time, a group
/// or an app): daily and weekly time, allowed hours.
///
/// Settings this screen does not show yet (grace, savings, breaks…) are kept
/// as they are.
library;

import 'package:flutter/material.dart';
import 'package:screentime_engine/screentime_engine.dart';

import '../controller.dart';
import '../store.dart';
import 'widgets.dart';

class RuleEditor extends StatefulWidget {
  final AppController controller;

  /// Rule to edit; `null` creates a new one.
  final Rule? rule;

  /// Target of a new rule.
  final AppTarget? initialTarget;

  const RuleEditor({
    super.key,
    required this.controller,
    this.rule,
    this.initialTarget,
  });

  @override
  State<RuleEditor> createState() => _RuleEditorState();
}

String _capitalize(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

const _defaultRange = TimeRange(8 * 60, 20 * 60);

class _RuleEditorState extends State<RuleEditor> {
  late AppTarget _target;
  bool _enabled = true;

  /// Calendar profile: null (always), normal times, or a special period.
  String? _profile;
  Duration? _daily;
  Duration? _weekly;

  bool _rolling = false;
  int _rollingDays = 3;
  Duration _rollingQuota = const Duration(hours: 4);

  bool _breaks = false;
  Duration _breakAfter = const Duration(minutes: 45);
  Duration _breakLength = const Duration(minutes: 10);

  CarryOverMode _carry = CarryOverMode.none;
  int _carryDays = 3;

  Duration? _grace;
  bool _hardening = false;
  Duration _hardeningThreshold = const Duration(minutes: 5);
  int _hardeningDays = 2;
  int _hardeningWindow = 7;
  bool _deductOverruns = false;

  bool _listenOnly = false;
  Duration _listenOpenFor = const Duration(minutes: 1);
  Duration _listenReopenAfter = const Duration(minutes: 2);

  bool _rollover = false;
  int _rolloverDays = 1;
  Duration? _rolloverCap;

  /// Daily time set separately for each weekday; `null` = no daily limit.
  bool _dailyByDay = false;
  late Map<int, Duration?> _dailyDays;
  bool _limitHours = false;

  /// Allowed ranges per weekday, [DateTime.monday] to [DateTime.sunday].
  /// A day without ranges is blocked all day.
  late Map<int, List<TimeRange>> _days;

  @override
  void initState() {
    super.initState();
    final r = widget.rule;
    _target = r?.appTarget ?? widget.initialTarget ?? const AppTarget.all();
    _enabled = r?.enabled ?? true;
    _profile = r?.profileId;
    _daily = r?.dailyQuota ?? (r == null ? const Duration(minutes: 60) : null);
    _weekly = r?.weeklyQuota;
    final rolling = r?.rollingQuota;
    if (rolling != null) {
      _rolling = true;
      _rollingDays = rolling.days;
      _rollingQuota = rolling.quota;
    }
    final listen = r?.listenOnly;
    if (listen != null) {
      _listenOnly = true;
      _listenOpenFor = listen.openFor;
      _listenReopenAfter = listen.reopenAfter;
    }
    final breaks = r?.breakPolicy;
    if (breaks != null) {
      _breaks = true;
      _breakAfter = breaks.after;
      _breakLength = breaks.length;
    }
    _carry = r?.carryOver.mode ?? CarryOverMode.none;
    if (_carry == CarryOverMode.spread) _carryDays = r!.carryOver.days;
    _dailyByDay = r?.dailyQuotaByWeekday.isNotEmpty ?? false;
    _dailyDays = {
      for (var d = DateTime.monday; d <= DateTime.sunday; d++)
        d: r?.dailyQuotaByWeekday[d] ?? r?.dailyQuota ?? _daily,
    };
    if (_dailyByDay) _daily = null;
    _grace = r?.grace?.length;
    final h = r?.grace?.hardening;
    if (h != null) {
      _hardening = true;
      _hardeningThreshold = h.threshold;
      _hardeningDays = h.days;
      _hardeningWindow = h.window;
      _deductOverruns = h.deductOverruns;
    }
    final keep = r?.rollover;
    if (keep != null) {
      _rollover = true;
      _rolloverDays = keep.days;
      _rolloverCap = keep.cap;
    }
    final schedule = r?.schedule;
    _limitHours = schedule != null;
    _days = {
      for (var d = DateTime.monday; d <= DateTime.sunday; d++)
        d: schedule == null
            ? const [_defaultRange]
            : [...?schedule.byWeekday[d]],
    };
  }

  /// Daily time as the engine stores it: one value when every day is the
  /// same, else a value per weekday (days without one have no limit).
  (Duration?, Map<int, Duration>) _dailyQuotas() {
    if (!_dailyByDay) return (_daily, const {});
    final values = _dailyDays.values.toSet();
    if (values.length == 1) return (values.single, const {});
    return (
      null,
      {
        for (final e in _dailyDays.entries)
          if (e.value != null) e.key: e.value!,
      },
    );
  }

  WeeklySchedule? _schedule() =>
      _limitHours ? WeeklySchedule({..._days}) : null;

  Future<void> _copyDay(int from) async {
    final s = widget.controller.s;
    final chosen = <int>{};
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(s.t('copyDayTitle', {'day': s.weekday(from)})),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var d = DateTime.monday; d <= DateTime.sunday; d++)
                if (d != from)
                  CheckboxListTile(
                    dense: true,
                    value: chosen.contains(d),
                    title: Text(_capitalize(s.weekday(d))),
                    onChanged: (v) => setState(() {
                      if (v == true) {
                        chosen.add(d);
                      } else {
                        chosen.remove(d);
                      }
                    }),
                  ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(s.t('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(s.t('ok')),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    setState(() {
      for (final d in chosen) {
        _days[d] = [..._days[from]!];
      }
    });
  }

  Widget _dayTile(int day) {
    final s = widget.controller.s;
    final ranges = _days[day]!;
    final summary = ranges.isEmpty
        ? s.t('dayBlocked')
        : ranges
              .map((r) => '${hm(r.startMinute)}–${hm(r.endMinute)}')
              .join(', ');
    return ExpansionTile(
      key: PageStorageKey('day$day'),
      title: Text(_capitalize(s.weekday(day))),
      subtitle: Text(
        summary,
        style: ranges.isEmpty
            ? TextStyle(color: Theme.of(context).colorScheme.error)
            : null,
      ),
      children: [
        TimeRangesEditor(
          s: s,
          title: null,
          ranges: ranges,
          onChanged: (r) => setState(() => _days[day] = r),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                icon: const Icon(Icons.wb_sunny_outlined),
                label: Text(s.t('allDay')),
                onPressed: () =>
                    setState(() => _days[day] = [const TimeRange(0, 1440)]),
              ),
              TextButton.icon(
                icon: const Icon(Icons.block),
                label: Text(s.t('dayBlocked')),
                onPressed: () => setState(() => _days[day] = []),
              ),
              TextButton.icon(
                icon: const Icon(Icons.copy),
                label: Text(s.t('copyDay')),
                onPressed: () => _copyDay(day),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _save() async {
    final c = widget.controller;
    final old = widget.rule;
    final daily = _dailyQuotas();
    final rule = Rule(
      id: old?.id ?? newId(),
      childId: c.childId!,
      profileId: _profile,
      appTarget: _target,
      deviceTarget: old?.deviceTarget ?? const DeviceTarget.all(),
      schedule: _schedule(),
      dailyQuota: daily.$1,
      dailyQuotaByWeekday: daily.$2,
      weeklyQuota: _weekly,
      rollingQuota: _rolling
          ? RollingQuota(days: _rollingDays, quota: _rollingQuota)
          : null,
      breakPolicy: _breaks
          ? BreakPolicy(after: _breakAfter, length: _breakLength)
          : null,
      grace: _grace == null
          ? null
          : GracePolicy(
              length: _grace!,
              hardening: _hardening
                  ? HardeningPolicy(
                      threshold: _hardeningThreshold,
                      days: _hardeningDays,
                      window: _hardeningWindow,
                      deductOverruns: _deductOverruns,
                    )
                  : null,
            ),
      carryOver: !(daily.$1 != null || daily.$2.isNotEmpty)
          ? const CarryOverPolicy.none()
          : switch (_carry) {
              CarryOverMode.none => const CarryOverPolicy.none(),
              CarryOverMode.nextDay => const CarryOverPolicy.nextDay(),
              CarryOverMode.spread => CarryOverPolicy.spread(_carryDays),
            },
      rollover: _rollover && (daily.$1 != null || daily.$2.isNotEmpty)
          ? RolloverPolicy(days: _rolloverDays, cap: _rolloverCap)
          : null,
      // Total screen time has no "listen only": it would leave every app.
      listenOnly: _listenOnly && _target != const AppTarget.all()
          ? ListenOnlyPolicy(
              openFor: _listenOpenFor,
              reopenAfter: _listenReopenAfter,
            )
          : null,
      setByChild: old?.setByChild ?? false,
      enabled: _enabled,
    );
    final rules = [
      for (final r in c.family.state.rules)
        if (r.id != rule.id) r,
      rule,
    ];
    await c.updateFamily(
      c.family.copyWith(state: stateWithRules(c.family.state, rules)),
    );
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final c = widget.controller;
    if (!await confirm(context, c.s, c.s.t('deleteRuleConfirm'))) return;
    final rules = c.family.state.rules
        .where((r) => r.id != widget.rule!.id)
        .toList();
    await c.updateFamily(
      c.family.copyWith(state: stateWithRules(c.family.state, rules)),
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final s = c.s;
    // A rule belongs to one kind of time, chosen where it was created.
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _target == const AppTarget.all()
              ? s.t('allScreens')
              : c.targetLabel(_target),
        ),
        actions: [
          if (widget.rule != null)
            IconButton(
              tooltip: s.t('delete'),
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
          TextButton(onPressed: _save, child: Text(s.t('save'))),
        ],
      ),
      body: ListView(
        children: [
          SwitchListTile(
            title: Text(s.t('ruleEnabled')),
            subtitle: _enabled ? null : Text(s.t('ruleEnabledHint')),
            value: _enabled,
            onChanged: (v) => setState(() => _enabled = v),
          ),
          // With special periods: always, in normal times, or during one.
          if (c.specialPeriods.isNotEmpty)
            ListTile(
              title: Text(s.t('ruleWhen')),
              subtitle: DropdownButton<String?>(
                value: _profile,
                isExpanded: true,
                items: [
                  DropdownMenuItem(
                    value: null,
                    child: Text(s.t('ruleWhenAlways')),
                  ),
                  DropdownMenuItem(
                    value: normalProfileId,
                    child: Text(s.t('ruleWhenNormal')),
                  ),
                  for (final p in c.specialPeriods)
                    DropdownMenuItem(
                      value: p.id,
                      child: Text(
                        s.t('ruleWhenDuring', {'name': c.periodName(p)}),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (v) => setState(() => _profile = v),
              ),
            ),
          SwitchListTile(
            title: Text(s.t('dailyQuotaByDay')),
            value: _dailyByDay,
            onChanged: (v) => setState(() {
              _dailyByDay = v;
              if (v) {
                _dailyDays = {for (final d in _dailyDays.keys) d: _daily};
              } else {
                // Back to one value: keep the most common one.
                final counts = <Duration?, int>{};
                for (final d in _dailyDays.values) {
                  counts[d] = (counts[d] ?? 0) + 1;
                }
                _daily = counts.entries
                    .reduce((a, b) => b.value > a.value ? b : a)
                    .key;
              }
            }),
          ),
          if (!_dailyByDay)
            DurationTile(
              s: s,
              title: s.t('dailyQuota'),
              value: _daily,
              noneLabel: s.t('noLimit'),
              allowZero: true,
              onChanged: (d) => setState(() => _daily = d),
            ),
          if (!_dailyByDay && _daily == Duration.zero)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                s.t('zeroQuotaHint'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (_dailyByDay)
            for (var d = DateTime.monday; d <= DateTime.sunday; d++)
              DurationTile(
                s: s,
                dense: true,
                title: _capitalize(s.weekday(d)),
                value: _dailyDays[d],
                noneLabel: s.t('noLimit'),
                allowZero: true,
                onChanged: (v) => setState(() => _dailyDays[d] = v),
              ),
          DurationTile(
            s: s,
            title: s.t('weeklyQuota'),
            value: _weekly,
            noneLabel: s.t('noLimit'),
            onChanged: (d) => setState(() => _weekly = d),
          ),
          SwitchListTile(
            title: Text(s.t('rollingQuota')),
            subtitle: Text(s.t('rollingQuotaHint')),
            value: _rolling,
            onChanged: (v) => setState(() => _rolling = v),
          ),
          if (_rolling) ...[
            CountTile(
              title: s.t('rollingDays'),
              valueText: s.days(_rollingDays),
              value: _rollingDays,
              min: 2,
              max: 30,
              onChanged: (v) => setState(() => _rollingDays = v),
            ),
            DurationTile(
              s: s,
              dense: true,
              title: s.t('rollingTime'),
              value: _rollingQuota,
              presets: const [60, 120, 180, 240, 300, 360, 480, 600, 720],
              onChanged: (d) =>
                  setState(() => _rollingQuota = d ?? _rollingQuota),
            ),
          ],
          const Divider(),
          DurationTile(
            s: s,
            title: s.t('grace'),
            value: _grace,
            presets: const [1, 2, 5, 10, 15, 30],
            onChanged: (d) => setState(() => _grace = d),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              s.t('graceHint'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          if (_grace != null) ...[
            SwitchListTile(
              title: Text(s.t('hardening')),
              value: _hardening,
              onChanged: (v) => setState(() => _hardening = v),
            ),
            if (_hardening) ...[
              DurationTile(
                s: s,
                dense: true,
                title: s.t('hardeningThreshold'),
                value: _hardeningThreshold,
                presets: const [1, 2, 5, 10, 15],
                onChanged: (d) => setState(
                  () => _hardeningThreshold = d ?? const Duration(minutes: 5),
                ),
              ),
              CountTile(
                title: s.t('hardeningDays'),
                valueText: '$_hardeningDays',
                value: _hardeningDays,
                min: 1,
                max: _hardeningWindow,
                onChanged: (v) => setState(() => _hardeningDays = v),
              ),
              CountTile(
                title: s.t('hardeningWindow'),
                valueText: s.days(_hardeningWindow),
                value: _hardeningWindow,
                min: _hardeningDays,
                max: 31,
                onChanged: (v) => setState(() => _hardeningWindow = v),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  s.t('hardeningSummary', {
                    'threshold': s.duration(_hardeningThreshold),
                    'days': '$_hardeningDays',
                    'window': '$_hardeningWindow',
                  }),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              SwitchListTile(
                title: Text(s.t('hardeningDeduct')),
                subtitle: Text(
                  s.t('hardeningDeductHint', {'window': '$_hardeningWindow'}),
                ),
                value: _deductOverruns,
                onChanged: (v) => setState(() => _deductOverruns = v),
              ),
            ],
          ],
          if (_dailyByDay || _daily != null) ...[
            const Divider(),
            ListTile(
              title: Text(s.t('carryOver')),
              subtitle: Text(s.t('carryOverHint')),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SegmentedButton<CarryOverMode>(
                segments: [
                  ButtonSegment(
                    value: CarryOverMode.none,
                    label: Text(s.t('carryOverNone')),
                  ),
                  ButtonSegment(
                    value: CarryOverMode.nextDay,
                    label: Text(s.t('carryOverNextDay')),
                  ),
                  ButtonSegment(
                    value: CarryOverMode.spread,
                    label: Text(s.t('carryOverSpread')),
                  ),
                ],
                selected: {_carry},
                onSelectionChanged: (v) => setState(() => _carry = v.first),
              ),
            ),
            if (_carry == CarryOverMode.spread)
              CountTile(
                title: s.t('carryOverDays'),
                valueText: s.days(_carryDays),
                value: _carryDays,
                min: 2,
                max: 14,
                onChanged: (v) => setState(() => _carryDays = v),
              ),
            if (_carry != CarryOverMode.none && _hardening && _deductOverruns)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text(
                  s.t('carryOverDeduct'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            const Divider(),
            SwitchListTile(
              title: Text(s.t('rollover')),
              subtitle: Text(s.t('rolloverHint')),
              value: _rollover,
              onChanged: (v) => setState(() => _rollover = v),
            ),
            if (_rollover) ...[
              CountTile(
                title: s.t('rolloverDays'),
                valueText: s.days(_rolloverDays),
                value: _rolloverDays,
                min: 1,
                max: 14,
                onChanged: (v) => setState(() => _rolloverDays = v),
              ),
              DurationTile(
                s: s,
                dense: true,
                title: s.t('rolloverCap'),
                value: _rolloverCap,
                noneLabel: s.t('noLimit'),
                onChanged: (d) => setState(() => _rolloverCap = d),
              ),
            ],
          ],
          const Divider(),
          SwitchListTile(
            title: Text(s.t('breakPolicy')),
            subtitle: Text(s.t('breakPolicyHint')),
            value: _breaks,
            onChanged: (v) => setState(() => _breaks = v),
          ),
          if (_breaks) ...[
            DurationTile(
              s: s,
              dense: true,
              title: s.t('breakAfter'),
              value: _breakAfter,
              presets: const [15, 20, 30, 45, 60, 90, 120],
              onChanged: (d) => setState(() => _breakAfter = d ?? _breakAfter),
            ),
            DurationTile(
              s: s,
              dense: true,
              title: s.t('breakLength'),
              value: _breakLength,
              // The child's usual durations, and a few short ones.
              presets: ({5, 10, ...c.presets}.toList()..sort()),
              onChanged: (d) =>
                  setState(() => _breakLength = d ?? _breakLength),
            ),
          ],
          if (_target != const AppTarget.all()) ...[
            const Divider(),
            SwitchListTile(
              title: Text(s.t('listenOnly')),
              subtitle: Text(s.t('listenOnlyHint')),
              value: _listenOnly,
              onChanged: (v) => setState(() => _listenOnly = v),
            ),
            if (_listenOnly) ...[
              DurationTile(
                s: s,
                dense: true,
                title: s.t('listenOpenFor'),
                value: _listenOpenFor,
                presets: const [1, 2, 3, 5],
                onChanged: (d) =>
                    setState(() => _listenOpenFor = d ?? _listenOpenFor),
              ),
              DurationTile(
                s: s,
                dense: true,
                title: s.t('listenReopenAfter'),
                value: _listenReopenAfter,
                presets: const [1, 2, 5, 10, 15],
                onChanged: (d) => setState(
                  () => _listenReopenAfter = d ?? _listenReopenAfter,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  s.t('listenOnlyNote'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ],
          const Divider(),
          SwitchListTile(
            title: Text(s.t('limitHours')),
            value: _limitHours,
            onChanged: (v) => setState(() => _limitHours = v),
          ),
          if (_limitHours) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(s.t('scheduleIntro')),
            ),
            for (var d = DateTime.monday; d <= DateTime.sunday; d++)
              _dayTile(d),
          ],
        ],
      ),
    );
  }
}
