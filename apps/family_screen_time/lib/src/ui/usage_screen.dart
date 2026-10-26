/// App usage, whatever the rules: list of apps by time over a period, with
/// flags that help spot apps worth a closer look, and a detail per app.
library;

import 'package:flutter/material.dart';
import 'package:screentime_engine/screentime_engine.dart';

import '../controller.dart';
import '../family.dart';
import '../ordering.dart';
import '../platform.dart';
import '../strings.dart';
import '../usage_report.dart';
import 'group_chips.dart';
import 'limit_screen.dart';

const _periods = [1, 7, 30];

class UsageScreen extends StatefulWidget {
  final AppController controller;

  /// Opened from parent mode: apps can be put in groups from here.
  final bool parent;

  const UsageScreen({super.key, required this.controller, this.parent = false});

  @override
  State<UsageScreen> createState() => _UsageScreenState();
}

/// The devices [childId] used in [history], by name.
List<String> devicesOf(
  List<UsageSegment> history,
  String childId,
  Map<String, String> names,
) {
  final ids = {
    for (final s in history)
      if (s.childId == childId && !s.isInjected && s.deviceId != null)
        s.deviceId!,
  }.toList();
  return ids..sort((a, b) {
    final c = compareNames(names[a] ?? a, names[b] ?? b);
    return c != 0 ? c : a.compareTo(b);
  });
}

/// Name of device [id], or the start of its id.
String deviceLabel(Map<String, String> names, String id) =>
    names[id] ?? (id.length > 8 ? id.substring(0, 8) : id);

/// One chip per device, and one for all of them ([selected] `null`);
/// [totals], when given, after each name.
Widget deviceChips(
  S s, {
  required List<String> devices,
  required Map<String, String> names,
  required String? selected,
  required void Function(String?) onSelected,
  Map<String?, Duration> totals = const {},
}) {
  String label(String? id, String name) =>
      totals[id] == null ? name : '$name · ${s.duration(totals[id]!)}';
  return SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Row(
      children: [
        for (final id in <String?>[null, ...devices])
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(
                label(
                  id,
                  id == null ? s.t('allDevices') : deviceLabel(names, id),
                ),
              ),
              selected: selected == id,
              onSelected: (_) => onSelected(id),
            ),
          ),
      ],
    ),
  );
}

class _UsageScreenState extends State<UsageScreen> {
  int _days = 1;

  /// The device shown; `null`: all of them.
  String? _device;
  Map<String, String> _names = const {};
  List<UsageSegment>? _history;
  DateTime? _importedUntil;
  Map<String, AppInfo> _info = const {};

  /// Apps not counted: system components, home screens.
  Set<String>? _excluded;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final c = widget.controller;
    _excluded = await c.usageExcluded();
    _names = await c.deviceNames();
    await c.importHistoryIfNeeded();
    final since = addDays(dayOf(DateTime.now()), -usageHistoryDays);
    final imported = await c.store.loadImported(since: since);
    final recorded = await c.store.loadUsage(since: since);
    DateTime? importedUntil;
    for (final s in imported) {
      if (importedUntil == null || s.end.isAfter(importedUntil)) {
        importedUntil = s.end;
      }
    }
    if (!mounted) return;
    setState(() {
      _history = [...imported, ...recorded];
      _importedUntil = importedUntil;
    });
    final history = _history!;
    final apps = {
      for (final s in history)
        if (s.appId != null) usedApp(s.appId!),
    };
    try {
      final info = await c.appInfo(apps);
      if (mounted) setState(() => _info = info);
    } on Object {
      // Names fall back to package names.
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final s = c.s;
    final history = _history;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.t('usageTitle'))),
      body: history == null
          ? const Center(child: CircularProgressIndicator())
          : ListenableBuilder(
              listenable: c,
              builder: (context, _) {
                final child = c.childId ?? '';
                final now = DateTime.now();
                final exclude = _excluded ?? c.family.config.neverBlocked;
                UsageReport reportOf(String? device) => buildUsageReport(
                  device == null
                      ? history
                      : [
                          for (final u in history)
                            if (u.deviceId == device) u,
                        ],
                  childId: child,
                  now: now,
                  days: _days,
                  exclude: exclude,
                  together:
                      c.family.config.counting == SimultaneousCounting.elapsed,
                );
                final devices = devicesOf(history, child, _names);
                final device = devices.contains(_device) ? _device : null;
                final report = reportOf(device);
                return RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: SegmentedButton<int>(
                          segments: [
                            for (final d in _periods)
                              ButtonSegment(
                                value: d,
                                label: Text(
                                  s.t(d == 1 ? 'periodToday' : 'period$d'),
                                ),
                              ),
                          ],
                          selected: {_days},
                          onSelectionChanged: (v) =>
                              setState(() => _days = v.first),
                        ),
                      ),
                      // Several devices: each one's time, and its apps.
                      if (devices.length > 1) ...[
                        const SizedBox(height: 12),
                        deviceChips(
                          s,
                          devices: devices,
                          names: _names,
                          selected: device,
                          onSelected: (d) => setState(() => _device = d),
                          totals: {
                            for (final d in <String?>[null, ...devices])
                              d: d == device ? report.total : reportOf(d).total,
                          },
                        ),
                      ],
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          s.t('usageTotal', {'time': s.duration(report.total)}),
                          style: theme.textTheme.headlineSmall,
                        ),
                      ),
                      if (_days > 1)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            s.t('usageAverage', {
                              'time': s.duration(report.dailyAverage),
                            }),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: _days == 1
                            ? hourChart(context, s, report.totalByHour)
                            : dayChart(
                                context,
                                s,
                                report.days,
                                report.totalByDay,
                              ),
                      ),
                      if (report.apps.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(s.t('usageEmpty')),
                        ),
                      for (final app in report.apps)
                        _AppTile(
                          controller: c,
                          parent: widget.parent,
                          app: app,
                          info: _info[app.appId],
                          share: report.total == Duration.zero
                              ? 0
                              : app.total.inSeconds / report.total.inSeconds,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => AppUsageScreen(
                                controller: c,
                                app: app,
                                days: report.days,
                                info: _info[app.appId],
                                parent: widget.parent,
                              ),
                            ),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          [
                            s.t('usageLegend'),
                            if (report.historyStart != null)
                              s.t('usageSince', {
                                'date': s.date(report.historyStart!),
                              }),
                            if (_importedUntil != null)
                              s.t('usageImported', {
                                'date': s.date(_importedUntil!),
                              }),
                          ].join('\n\n'),
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

/// Labels flagging an app; empty when there is nothing to point out.
List<String> appBadges(AppController c, AppUsage app) {
  final s = c.s;
  final config = c.family.config;
  final allowed = config.alwaysAllowed.contains(app.appId);
  final limited = c.activeChildRules.any(
    (r) =>
        (r.hasQuota || r.schedule != null) &&
        r.appTarget.covers(app.appId, config.appGroups),
  );
  return [
    if (app.isNew) s.t('badgeNew'),
    if (allowed) s.t('badgeAlwaysAllowed'),
    if (!allowed && !limited) s.t('badgeNoLimit'),
    if (app.night >= const Duration(minutes: 1)) s.t('badgeNight'),
  ];
}

Widget appIcon(AppInfo? info, {double size = 40}) {
  final icon = info?.icon;
  if (icon != null) {
    return Image.memory(icon, width: size, height: size, gaplessPlayback: true);
  }
  return Icon(Icons.android, size: size);
}

class _AppTile extends StatelessWidget {
  final AppController controller;
  final bool parent;
  final AppUsage app;
  final AppInfo? info;
  final double share;
  final VoidCallback onTap;

  const _AppTile({
    required this.controller,
    required this.parent,
    required this.app,
    required this.info,
    required this.share,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final s = controller.s;
    final badges = appBadges(controller, app);
    final theme = Theme.of(context);
    return ListTile(
      leading: appIcon(info),
      title: Text(controller.appName(app.appId, androidLabel: info?.label)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          LinearProgressIndicator(value: share, minHeight: 4),
          if (badges.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final b in badges)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      b,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSecondaryContainer,
                      ),
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 4),
          GroupChips(
            controller: controller,
            appId: app.appId,
            interactive: parent,
          ),
        ],
      ),
      trailing: Text(s.duration(app.total), style: theme.textTheme.titleSmall),
      onTap: onTap,
    );
  }
}

/// Detail of one app over the chosen period.
class AppUsageScreen extends StatelessWidget {
  final AppController controller;
  final AppUsage app;
  final List<DateTime> days;
  final AppInfo? info;
  final bool parent;

  const AppUsageScreen({
    super.key,
    required this.controller,
    required this.app,
    required this.days,
    required this.info,
    required this.parent,
  });

  Future<void> _rename(BuildContext context) async {
    final c = controller;
    final s = c.s;
    final field = TextEditingController(text: c.family.appNames[app.appId]);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.t('renameApp')),
        content: TextField(
          controller: field,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: s.t('appNameLabel'),
            hintText: info?.label ?? app.appId,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(s.t('cancel')),
          ),
          TextButton(
            // An empty name brings back Android's name.
            onPressed: () => Navigator.pop(context, ''),
            child: Text(s.t('resetName')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, field.text),
            child: Text(s.t('save')),
          ),
        ],
      ),
    );
    if (result != null) await c.renameApp(app.appId, result);
  }

  Future<void> _editGroups(BuildContext context) async {
    final c = controller;
    final groups = c.family.config.appGroups;
    final mine = c.childGroups;
    final chosen = {...c.groupsOf(app.appId)};
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(c.s.t('appEditGroups')),
          content: mine.isEmpty
              ? Text(c.s.t('noGroups'))
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final e in mine.entries)
                      CheckboxListTile(
                        value: chosen.contains(e.key),
                        title: Text(e.value),
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            chosen.add(e.key);
                          } else {
                            chosen.remove(e.key);
                          }
                        }),
                      ),
                  ],
                ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(c.s.t('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, chosen),
              child: Text(c.s.t('save')),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    // Only this child's groups change.
    final updated = {
      ...groups,
      for (final id in mine.keys)
        id: {
          ...?groups[id]?.where((p) => p != app.appId),
          if (result.contains(id)) app.appId,
        },
    };
    await c.updateFamily(
      c.family.copyWith(config: configWithGroups(c.family.config, updated)),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final c = controller;
      final s = c.s;
      final theme = Theme.of(context);
      final groups = [for (final id in c.groupsOf(app.appId)) c.groupName(id)];
      final limitedBy = [
        for (final r in c.activeChildRules)
          if ((r.hasQuota || r.schedule != null) &&
              r.appTarget.covers(app.appId, c.family.config.appGroups))
            c.labelOf(r),
      ];
      final badges = appBadges(c, app);
      final name = c.appName(app.appId, androidLabel: info?.label);
      final androidName = info?.label ?? app.appId;
      return Scaffold(
        appBar: AppBar(
          title: Text(name),
          actions: [
            if (parent)
              IconButton(
                tooltip: s.t('renameApp'),
                icon: const Icon(Icons.edit),
                onPressed: () => _rename(context),
              ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                appIcon(info, size: 48),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.duration(app.total),
                        style: theme.textTheme.headlineSmall,
                      ),
                      if (name != androidName)
                        Text(
                          s.t('androidName', {'name': androidName}),
                          style: theme.textTheme.bodySmall,
                        ),
                      Text(app.appId, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
            if (badges.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                children: [for (final b in badges) Chip(label: Text(b))],
              ),
            ],
            const SizedBox(height: 12),
            Text(s.t('appSessions', {'count': '${app.sessions}'})),
            if (app.night > Duration.zero)
              Text(s.t('appNight', {'time': s.duration(app.night)})),
            Text(
              s.t('appFirstSeen', {
                'date': '${s.date(app.firstSeen)} ${s.time(app.firstSeen)}',
              }),
            ),
            Text(
              s.t('appLastSeen', {
                'date': '${s.date(app.lastSeen)} ${s.time(app.lastSeen)}',
              }),
            ),
            if (days.length > 1) ...[
              const SizedBox(height: 20),
              Text(s.t('appByDay'), style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              dayChart(context, s, days, app.byDay),
            ],
            const SizedBox(height: 20),
            Text(s.t('appByHour'), style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            hourChart(context, s, app.byHour),
            const SizedBox(height: 20),
            Text(s.t('appGroups'), style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            if (groups.isEmpty)
              Text(s.t('appNoGroup'))
            else
              GroupChips(controller: c, appId: app.appId, interactive: parent),
            if (limitedBy.isNotEmpty)
              Text(s.t('appLimitedBy', {'rules': limitedBy.join(', ')})),
            if (parent) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.apps),
                      label: Text(s.t('appEditGroups')),
                      onPressed: () => _editGroups(context),
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.timer_outlined),
                      label: Text(s.t('appOwnLimits')),
                      onPressed: () async {
                        if (info != null) {
                          c.androidLabels[app.appId] = info!.label;
                        }
                        await openLimit(context, c, AppTarget.app(app.appId));
                      },
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      );
    },
  );
}

// --- Charts -----------------------------------------------------------------

/// Bars for each hour of the day; night hours in another colour.
Widget hourChart(BuildContext context, S s, List<Duration> byHour) => _Bars(
  values: byHour,
  labels: [for (var h = 0; h < 24; h++) h % 6 == 0 ? '$h' : null],
  highlight: [for (var h = 0; h < 24; h++) isNightHour(h)],
  s: s,
);

/// Bars for each day; weekday initials for a week, day numbers otherwise.
Widget dayChart(
  BuildContext context,
  S s,
  List<DateTime> days,
  Map<DateTime, Duration> byDay,
) => _Bars(
  values: [for (final d in days) byDay[d] ?? Duration.zero],
  labels: [
    for (var i = 0; i < days.length; i++)
      days.length <= 7
          ? s.t('weekdayShort${days[i].weekday}')
          : (i % 5 == 0 || i == days.length - 1)
          ? '${days[i].day}'
          : null,
  ],
  highlight: [for (final d in days) d.weekday >= DateTime.saturday],
  s: s,
);

/// Bars for [values], with [labels] under some of them.
Widget barChart(S s, List<Duration> values, List<String?> labels) => _Bars(
  values: values,
  labels: labels,
  highlight: List.filled(values.length, false),
  s: s,
);

class _Bars extends StatelessWidget {
  final List<Duration> values;
  final List<String?> labels;
  final List<bool> highlight;
  final S s;

  const _Bars({
    required this.values,
    required this.labels,
    required this.highlight,
    required this.s,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final max = values.fold(Duration.zero, (a, b) => b > a ? b : a);
    const height = 110.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          max == Duration.zero ? '' : s.duration(max),
          style: theme.textTheme.labelSmall,
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: height,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < values.length; i++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1),
                    child: Container(
                      height: max == Duration.zero
                          ? 0
                          : height * values[i].inSeconds / max.inSeconds,
                      decoration: BoxDecoration(
                        color: highlight[i]
                            ? theme.colorScheme.tertiary
                            : theme.colorScheme.primary,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        const SizedBox(height: 2),
        Row(
          children: [
            for (final l in labels)
              Expanded(
                child: Text(
                  l ?? '',
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.visible,
                  softWrap: false,
                  style: theme.textTheme.labelSmall,
                ),
              ),
          ],
        ),
      ],
    );
  }
}
