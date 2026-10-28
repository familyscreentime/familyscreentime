/// Parent settings: limits by kind of time (total screen time, app groups),
/// reminders, permissions, parent code, language.
library;

import 'package:flutter/material.dart';
import 'package:screentime_engine/screentime_engine.dart';

import '../controller.dart';
import '../store.dart';
import '../strings.dart';
import 'accessible_apps_screen.dart';
import 'group_editor.dart';
import 'permissions.dart';
import 'quick_actions.dart';
import 'self_limit_report_screen.dart';
import 'limit_screen.dart';
import '../family.dart';
import 'trends_screen.dart';
import 'devices_screen.dart';
import 'usage_screen.dart';
import 'eye_break_screen.dart';
import 'family_settings.dart';
import 'volume_screen.dart';

class ParentHome extends StatefulWidget {
  final AppController controller;

  const ParentHome({super.key, required this.controller});

  @override
  State<ParentHome> createState() => _ParentHomeState();
}

class _ParentHomeState extends State<ParentHome> {
  Map<String, Duration> _groupTimes = const {};
  Duration? _totalTime;
  Map<String, Duration> _appTimes = const {};

  AppController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _loadTimes();
  }

  Future<void> _loadTimes() async {
    final times = await controller.groupTimesToday();
    final total = await controller.totalTimeToday();
    await controller.loadLabels();
    await controller.loadLabels({
      ...controller.family.config.alwaysAllowed,
      ...controller.family.config.allowedInHours,
    });
    final apps = {
      for (final app in singleAppTargets(controller.parentRules))
        app: await controller.timeToday(AppTarget.app(app)),
    };
    if (mounted) {
      setState(() {
        _groupTimes = times;
        _totalTime = total;
        _appTimes = apps;
      });
    }
  }

  /// One kind of time: its rules in short and today's time; opens its
  /// rules and, for a group, its apps.
  Widget _limitTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required AppTarget target,
    required Duration? today,
    int? apps,
  }) {
    final c = controller;
    final s = c.s;
    final rules = c.targetRules(target);
    final active = rules.where((r) => r.enabled).toList();
    final summary = active.isEmpty
        ? (rules.isEmpty
              ? s.t('noLimit')
              : '${s.t('noLimit')} (${s.t('ruleOff')})')
        : active.map(c.summaryOf).where((t) => t.isNotEmpty).join(' / ');
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(
        [
          summary,
          [
            if (apps != null) s.t('appsInGroup', {'count': '$apps'}),
            if (today != null) s.t('groupToday', {'time': s.duration(today)}),
          ].join(' · '),
        ].where((t) => t.isNotEmpty).join('\n'),
      ),
      isThreeLine: true,
      trailing: const Icon(Icons.chevron_right),
      onTap: () async {
        await openLimit(context, c, target);
        await _loadTimes();
      },
    );
  }

  Future<void> _open(BuildContext context, Widget page) async {
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => page));
    await _loadTimes();
  }

  /// Picks other children's groups to copy for this child.
  Future<void> _copyGroups(BuildContext context) async {
    final c = widget.controller;
    final s = c.s;
    final groups = c.otherChildrenGroups;
    String owner(String id) =>
        c.family.child(c.family.groupOwners[id])?.name ?? '';
    final chosen = <String>{};
    final picked = await showDialog<Set<String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(s.t('copyGroups')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.t('copyGroupsText')),
                const SizedBox(height: 8),
                for (final e in groups.entries)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: chosen.contains(e.key),
                    title: Text(e.value),
                    subtitle: Text(owner(e.key)),
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
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(s.t('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, chosen),
              child: Text(s.t('copy')),
            ),
          ],
        ),
      ),
    );
    if (picked == null || picked.isEmpty) return;
    await c.copyGroups(picked);
    await _loadTimes();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final c = controller;
      final s = c.s;
      final header = Theme.of(context).textTheme.titleMedium;
      return Scaffold(
        appBar: AppBar(
          title: Text(
            // On a parent's device: whose settings these are.
            c.settings.parentDevice && c.child != null
                ? c.child!.name
                : s.t('parentTitle'),
          ),
          actions: [
            IconButton(
              tooltip: s.t('lock'),
              icon: const Icon(Icons.lock),
              onPressed: c.leaveParentMode,
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            ListTile(
              leading: const Icon(Icons.bar_chart),
              title: Text(s.t('usageTitle')),
              onTap: () =>
                  _open(context, UsageScreen(controller: c, parent: true)),
            ),
            ListTile(
              leading: const Icon(Icons.insights),
              title: Text(s.t('trendsTitle')),
              subtitle: Text(s.t('trendsTileHint')),
              onTap: () => _open(context, TrendsScreen(controller: c)),
            ),
            const Divider(),
            QuickActions(controller: c),
            const Divider(),
            ListTile(title: Text(s.t('limitsTitle'), style: header)),
            _limitTile(
              context,
              icon: Icons.hourglass_bottom,
              title: s.t('allScreens'),
              target: const AppTarget.all(),
              today: _totalTime,
            ),
            for (final e in c.childGroups.entries)
              _limitTile(
                context,
                icon: Icons.folder_outlined,
                title: e.value,
                target: AppTarget.group(e.key),
                today: _groupTimes[e.key],
                apps: c.family.config.appGroups[e.key]?.length ?? 0,
              ),
            for (final app in singleAppTargets(c.parentRules))
              _limitTile(
                context,
                icon: Icons.apps,
                title: c.targetLabel(AppTarget.app(app)),
                target: AppTarget.app(app),
                today: _appTimes[app],
              ),
            if (c.childGroups.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(s.t('noGroups')),
              ),
            ListTile(
              leading: const Icon(Icons.add),
              title: Text(s.t('addGroup')),
              onTap: () async {
                final id = await Navigator.of(context).push<String>(
                  MaterialPageRoute(builder: (_) => GroupEditor(controller: c)),
                );
                // Created: straight to its page, to give it a limit.
                if (id != null && context.mounted) {
                  await openLimit(context, c, AppTarget.group(id));
                }
                await _loadTimes();
              },
            ),
            if (c.otherChildrenGroups.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.copy_all_outlined),
                title: Text(s.t('copyGroups')),
                onTap: () => _copyGroups(context),
              ),
            ListTile(
              leading: const Icon(Icons.add),
              title: Text(s.t('limitAnApp')),
              onTap: () async {
                final app = await pickApp(context, c);
                if (app == null || !context.mounted) return;
                await c.loadLabels([app]);
                if (!context.mounted) return;
                await openLimit(context, c, AppTarget.app(app));
                await _loadTimes();
              },
            ),
            ListTile(
              leading: const Icon(Icons.self_improvement),
              title: Text(
                s.t('selfReportTitle', {'name': c.child?.name ?? ''}),
              ),
              subtitle: Text(
                c.selfLimits.isEmpty
                    ? s.t('selfReportNone', {'name': c.child?.name ?? ''})
                    : c.selfLimits
                          .map(
                            (r) =>
                                '${c.labelOf(r)} ${s.duration(r.dailyQuota ?? Duration.zero)}',
                          )
                          .join(' · '),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _open(context, SelfLimitReportScreen(controller: c)),
            ),
            const Divider(),
            ListTile(title: Text(s.t('remindersTitle'), style: header)),
            ListTile(
              leading: const Icon(Icons.notifications_active_outlined),
              title: Text(s.t('graceReminders')),
              subtitle: DropdownButton<int>(
                value: c.family.graceReminderMinutes,
                isExpanded: true,
                items: [
                  for (final m in {
                    ...graceReminderChoices,
                    c.family.graceReminderMinutes,
                  })
                    DropdownMenuItem(
                      value: m,
                      child: Text(graceReminderLabel(s, m)),
                    ),
                ],
                onChanged: (m) {
                  if (m != null) {
                    c.updateFamily(c.family.copyWith(graceReminderMinutes: m));
                  }
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(72, 0, 16, 8),
              child: Text(
                s.t('graceRemindersHint'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const Divider(),
            ListTile(title: Text(s.t('outOfTimeTitle'), style: header)),
            RadioGroup<OutOfTime>(
              groupValue: c.family.outOfTime,
              onChanged: (m) {
                if (m != null) {
                  c.updateFamily(c.family.copyWith(outOfTime: m));
                }
              },
              child: Column(
                children: [
                  for (final (mode, title, hint) in [
                    (OutOfTime.apps, 'outOfTimeApps', 'outOfTimeAppsHint'),
                    (
                      OutOfTime.settings,
                      'outOfTimeSettings',
                      'outOfTimeSettingsHint',
                    ),
                    (
                      OutOfTime.device,
                      'outOfTimeDevice',
                      'outOfTimeDeviceHint',
                    ),
                  ])
                    RadioListTile<OutOfTime>(
                      value: mode,
                      title: Text(s.t(title)),
                      subtitle: Text(s.t(hint)),
                    ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.phone_outlined),
              title: Text(s.t('accessibleTitle')),
              subtitle: Text(
                [
                      ...c.family.config.alwaysAllowed,
                      ...c.family.config.allowedInHours,
                    ]
                    .map((a) => c.appName(a, androidLabel: c.androidLabels[a]))
                    .join(', '),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _open(context, AccessibleAppsScreen(controller: c)),
            ),
            SwitchListTile(
              title: Text(s.t('settingsParentOnly')),
              subtitle: Text(s.t('settingsParentOnlyHint')),
              value: c.family.settingsParentOnly,
              onChanged: (v) =>
                  c.updateFamily(c.family.copyWith(settingsParentOnly: v)),
            ),
            const Divider(),
            // On a parent's device, the linked devices are on the home.
            if (!c.settings.parentDevice)
              ListTile(
                leading: const Icon(Icons.devices_outlined),
                title: Text(s.t('devicesTitle')),
                subtitle: Text(s.t('devicesSubtitle')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _open(context, DevicesScreen(controller: c)),
              ),
            ListTile(
              leading: const Icon(Icons.volume_down_outlined),
              title: Text(s.t('volumeTitle')),
              subtitle: Text(
                s.t('volumeSummary', {
                  for (final (key, cap) in [
                    ('headphones', c.child?.volumeHeadphones),
                    ('speaker', c.child?.volumeSpeaker),
                  ])
                    key: cap == null
                        ? s.t('volumeNoCap').toLowerCase()
                        : s.t('volumePercent', {'percent': '$cap'}),
                }),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _open(context, VolumeScreen(controller: c)),
            ),
            ListTile(
              leading: const Icon(Icons.visibility_outlined),
              title: Text(s.t('eyeBreakTitle')),
              subtitle: Text(
                eyeBreakSummary(s, c.child?.eyeBreak ?? const EyeBreakPolicy()),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _open(context, EyeBreakScreen(controller: c)),
            ),
            // This device's permissions: none needed on a parent's device.
            if (!c.settings.parentDevice) ...[
              const Divider(),
              ListTile(title: Text(s.t('permissionsTitle'), style: header)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: PermissionsView(controller: c),
              ),
            ],
            const Divider(),
            ListTile(
              leading: const Icon(Icons.language),
              title: Text(s.t('language')),
              trailing: DropdownButton<String>(
                value: c.settings.language,
                items: [
                  for (final l in supportedLanguages)
                    DropdownMenuItem(
                      value: l,
                      child: Text(S(l).t('languageName')),
                    ),
                ],
                onChanged: (l) {
                  if (l != null) {
                    c.updateSettings(c.settings.copyWith(language: l));
                  }
                },
              ),
            ),
            // On a parent's device, the family's settings have their own
            // page, from the home.
            if (!c.settings.parentDevice) ...[
              const Divider(),
              ListTile(title: Text(s.t('familySettingsTitle'), style: header)),
              FamilySettingsSection(controller: c),
            ],
          ],
        ),
      );
    },
  );
}

/// Intervals offered for reminders during grace time; 0: at the start only.
const graceReminderChoices = [0, 1, 2, 3, 5, 10];

String graceReminderLabel(S s, int minutes) => switch (minutes) {
  0 => s.t('graceRemindersStart'),
  1 => s.t('everyMinute'),
  _ => s.t('everyMinutes', {'count': '$minutes'}),
};
