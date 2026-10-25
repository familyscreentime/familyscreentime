/// The child's use of apps over several months, and its export for other
/// software (spreadsheets, ActivityWatch).
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:screentime_engine/screentime_engine.dart';

import '../controller.dart';
import '../platform.dart';
import '../store.dart';
import '../strings.dart';
import '../usage_export.dart';
import '../usage_trends.dart';
import 'usage_screen.dart' show barChart, deviceChips, devicesOf;

const _monthChoices = [3, 6, 12];

/// "1 an", "Sans limite"…: how long use is kept.
String keptLabel(S s, int days) =>
    usageKeptChoices.contains(days) ? s.t('keep$days') : s.days(days);

class TrendsScreen extends StatefulWidget {
  final AppController controller;

  const TrendsScreen({super.key, required this.controller});

  @override
  State<TrendsScreen> createState() => _TrendsScreenState();
}

class _TrendsScreenState extends State<TrendsScreen> {
  int _months = 3;
  List<UsageSegment>? _history;
  Map<String, AppInfo> _info = const {};

  /// Apps not counted: system components, home screens.
  Set<String> _excluded = const {};

  /// The device shown; `null`: all of them.
  String? _device;
  Map<String, String> _names = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Twice the longest period: the one before is compared.
  Future<void> _load() async {
    final c = widget.controller;
    _excluded = await c.usageExcluded();
    _names = await c.deviceNames();
    final today = dayOf(DateTime.now());
    var since = DateTime(today.year - 2, today.month, today.day);
    final first = await c.store.firstUsageDay();
    if (first != null && first.isAfter(since)) since = first;
    final history = [
      ...await c.store.loadImported(since: since),
      ...await c.store.loadUsage(since: since),
    ];
    if (!mounted) return;
    setState(() => _history = history);
    final apps = {
      for (final s in history)
        if (s.appId != null) usedApp(s.appId!),
    };
    try {
      final info = await c.appInfo(apps);
      if (mounted) setState(() => _info = info);
    } on Object {
      // Package names are shown instead.
    }
  }

  UsageTrends _trends(List<UsageSegment> history) {
    final c = widget.controller;
    final config = c.family.config;
    return buildTrends(
      history,
      childId: c.childId ?? '',
      now: DateTime.now(),
      months: _months,
      monthly: _months > 6,
      weekStart: config.weekStart,
      exclude: _excluded,
      together: config.counting == SimultaneousCounting.elapsed,
      groups: {
        for (final id in c.childGroups.keys)
          id: config.appGroups[id] ?? const {},
      },
    );
  }

  String _appName(String package) {
    final c = widget.controller;
    return c.family.appNames[package] ?? _info[package]?.label ?? package;
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final s = c.s;
    final history = _history;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(s.t('trendsTitle')),
        actions: [
          IconButton(
            tooltip: s.t('exportTitle'),
            icon: const Icon(Icons.ios_share),
            onPressed: history == null ? null : () => _export(history),
          ),
        ],
      ),
      body: history == null
          ? const Center(child: CircularProgressIndicator())
          : Builder(
              builder: (context) {
                final devices = devicesOf(history, c.childId ?? '', _names);
                final device = devices.contains(_device) ? _device : null;
                final t = _trends(
                  device == null
                      ? history
                      : [
                          for (final u in history)
                            if (u.deviceId == device) u,
                        ],
                );
                final change = t.change;
                return ListView(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: SegmentedButton<int>(
                        segments: [
                          for (final m in _monthChoices)
                            ButtonSegment(
                              value: m,
                              label: Text(s.t('trendsMonths$m')),
                            ),
                        ],
                        selected: {_months},
                        onSelectionChanged: (v) =>
                            setState(() => _months = v.first),
                      ),
                    ),
                    if (devices.length > 1) ...[
                      const SizedBox(height: 12),
                      deviceChips(
                        s,
                        devices: devices,
                        names: _names,
                        selected: device,
                        onSelected: (d) => setState(() => _device = d),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.t('trendsPerDay', {'time': s.duration(t.perDay)}),
                            style: theme.textTheme.headlineSmall,
                          ),
                          if (change != null)
                            Text(
                              s.t('trendsChange$_months', {
                                'change': _percent(change),
                              }),
                            ),
                          Text(
                            s.t('trendsWeekdays', {
                              'weekday': s.duration(t.weekdayPerDay),
                              'weekend': s.duration(t.weekendPerDay),
                            }),
                          ),
                        ],
                      ),
                    ),
                    if (t.total == Duration.zero)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(s.t('trendsNone')),
                      )
                    else ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                        child: barChart(s, [
                          for (final b in t.buckets) b.perDay,
                        ], _labels(s, t)),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          s.t(_months > 6 ? 'trendsMonthly' : 'trendsWeekly'),
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                      if (t.groups.isNotEmpty) ...[
                        _header(context, s.t('trendsGroups')),
                        for (final g in t.groups)
                          _trendTile(
                            context,
                            s,
                            g,
                            c.childGroups[g.id] ?? g.id,
                            const Icon(Icons.folder_outlined),
                          ),
                      ],
                      _header(context, s.t('trendsApps')),
                      for (final a in t.apps.take(30))
                        _trendTile(context, s, a, _appName(a.id), _icon(a.id)),
                    ],
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        [
                          if (t.historyStart != null &&
                              t.historyStart!.isAfter(t.from))
                            s.t('trendsSince', {
                              'date': s.fullDate(t.historyStart!),
                            }),
                          s.t('trendsKept', {
                            'kept': keptLabel(s, c.family.usageKeptDays),
                          }),
                        ].join('\n\n'),
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }

  static String _percent(int change) => change > 0 ? '+$change %' : '$change %';

  /// Under the bars: every month's name, or the first week of each month.
  List<String?> _labels(S s, UsageTrends t) {
    final labels = <String?>[];
    int? lastMonth;
    for (final b in t.buckets) {
      final month = b.start.month;
      labels.add(
        _months > 6 || month != lastMonth ? s.monthShort(month) : null,
      );
      lastMonth = month;
    }
    return labels;
  }

  Widget _header(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium),
  );

  Widget _icon(String package) {
    final icon = _info[package]?.icon;
    return icon == null
        ? const Icon(Icons.apps)
        : Image.memory(icon, width: 32, height: 32);
  }

  Widget _trendTile(
    BuildContext context,
    S s,
    Trend t,
    String name,
    Widget leading,
  ) {
    final change = t.change;
    final theme = Theme.of(context);
    return ListTile(
      leading: SizedBox(width: 32, child: Center(child: leading)),
      title: Text(name),
      subtitle: Text(s.t('trendsPerDayShort', {'time': s.duration(t.perDay)})),
      trailing: change == null
          ? null
          : Text(
              _percent(change),
              style: theme.textTheme.labelLarge?.copyWith(
                color: change > 0
                    ? theme.colorScheme.error
                    : theme.colorScheme.primary,
              ),
            ),
    );
  }

  // --- Export -----------------------------------------------------------------

  Future<void> _export(List<UsageSegment> history) async {
    final c = widget.controller;
    final s = c.s;
    final child = c.child;
    var activityWatch = false;
    var allChildren = false;
    var whole = false;
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: Text(s.t('exportTitle')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.t('exportFormat')),
                RadioGroup<bool>(
                  groupValue: activityWatch,
                  onChanged: (v) => setDialog(() => activityWatch = v!),
                  child: Column(
                    children: [
                      RadioListTile(
                        value: false,
                        title: Text(s.t('exportCsv')),
                      ),
                      RadioListTile(
                        value: true,
                        title: Text(s.t('exportAw')),
                        subtitle: Text(s.t('exportAwHint')),
                      ),
                    ],
                  ),
                ),
                if (c.family.children.length > 1 && child != null) ...[
                  Text(s.t('exportWho')),
                  RadioGroup<bool>(
                    groupValue: allChildren,
                    onChanged: (v) => setDialog(() => allChildren = v!),
                    child: Column(
                      children: [
                        RadioListTile(
                          value: false,
                          title: Text(
                            s.t('exportThisChild', {'name': child.name}),
                          ),
                        ),
                        RadioListTile(
                          value: true,
                          title: Text(s.t('exportAllChildren')),
                        ),
                      ],
                    ),
                  ),
                ],
                Text(s.t('exportPeriod')),
                RadioGroup<bool>(
                  groupValue: whole,
                  onChanged: (v) => setDialog(() => whole = v!),
                  child: Column(
                    children: [
                      RadioListTile(
                        value: false,
                        title: Text(
                          '${s.t('exportShown')} (${s.t('trendsMonths$_months')})',
                        ),
                      ),
                      RadioListTile(value: true, title: Text(s.t('exportAll'))),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(s.t('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(s.t('exportGo')),
            ),
          ],
        ),
      ),
    );
    if (go != true || !mounted) return;
    final today = dayOf(DateTime.now());
    final to = addDays(today, 1);
    final segments = exportedSegments(
      history,
      children: allChildren || child == null ? null : {child.id},
      from: whole ? null : DateTime(to.year, to.month - _months, to.day),
      to: to,
      exclude: _excluded,
    );
    final messenger = ScaffoldMessenger.of(context);
    if (segments.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(s.t('exportEmpty'))));
      return;
    }
    final names = await _exportNames(segments);
    final content = activityWatch
        ? activityWatchJson(segments, names)
        : usageCsv(segments, names);
    final dir = Directory('${(await getTemporaryDirectory()).path}/exports');
    await dir.create(recursive: true);
    final who = allChildren || child == null ? 'family' : _fileSlug(child.name);
    final file = File(
      '${dir.path}/screen-time-$who-${dayToJson(today)}'
      '${activityWatch ? '.activitywatch.json' : '.csv'}',
    );
    await file.writeAsString(content, flush: true);
    final shared = await c.platform.shareFile(
      file.path,
      activityWatch ? 'application/json' : 'text/csv',
      s.t('exportSubject'),
    );
    if (!shared && mounted) {
      messenger.showSnackBar(
        SnackBar(content: Text(s.t('exportSaved', {'path': file.path}))),
      );
    }
  }

  static String _fileSlug(String name) {
    final slug = name
        .toLowerCase()
        .replaceAll(RegExp('[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return slug.isEmpty ? 'child' : slug;
  }

  /// Children's, devices' and apps' names for [segments].
  Future<ExportNames> _exportNames(List<UsageSegment> segments) async {
    final c = widget.controller;
    final devices = {..._names, ...await c.deviceNames()};
    final packages = {for (final s in segments) s.appId!};
    final missing = packages.where((p) => _appName(p) == p);
    if (missing.isNotEmpty) {
      try {
        _info = {..._info, ...await c.appInfo(missing)};
      } on Object {
        // Package names are used instead.
      }
    }
    return ExportNames(
      child: (id) => c.family.child(id)?.name ?? id,
      device: (id) => devices[id] ?? (id.length > 8 ? id.substring(0, 8) : id),
      app: _appName,
    );
  }
}
