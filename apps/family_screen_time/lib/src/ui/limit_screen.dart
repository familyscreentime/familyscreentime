/// Parent view of one kind of time — total screen time, an app group or a
/// single app —
/// with the rules that apply to it and, for a group, its apps.
library;

import 'package:flutter/material.dart';
import 'package:screentime_engine/screentime_engine.dart';

import '../controller.dart';
import '../platform.dart';
import 'group_editor.dart';
import 'rule_editor.dart';
import 'usage_screen.dart' show appIcon;
import 'widgets.dart';

/// Opens the view of [target].
Future<void> openLimit(
  BuildContext context,
  AppController c,
  AppTarget target,
) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => LimitScreen(controller: c, target: target),
  ),
);

class LimitScreen extends StatefulWidget {
  final AppController controller;

  /// [AppTarget.all], a group or a single app.
  final AppTarget target;

  const LimitScreen({
    super.key,
    required this.controller,
    required this.target,
  });

  @override
  State<LimitScreen> createState() => _LimitScreenState();
}

class _LimitScreenState extends State<LimitScreen> {
  Duration? _today;
  Map<String, AppInfo> _info = const {};

  AppController get c => widget.controller;
  String? get _groupId =>
      widget.target.kind == TargetKind.group ? widget.target.id : null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final id = _groupId;
    final today = await c.timeToday(widget.target);
    if (widget.target.kind == TargetKind.single) {
      await c.loadLabels([widget.target.id!]);
    }
    var info = _info;
    final apps = c.family.config.appGroups[id] ?? const <String>{};
    if (apps.isNotEmpty) {
      try {
        info = await c.appInfo(apps);
      } on Object {
        // Package names are shown instead.
      }
    }
    if (mounted) {
      setState(() {
        _today = today;
        _info = info;
      });
    }
  }

  Future<void> _push(Widget page) async {
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => page));
    await _load();
  }

  Future<void> _setEnabled(Rule rule, bool enabled) => c.updateFamily(
    c.family.copyWith(
      state: stateWithRules(c.family.state, [
        for (final r in c.family.state.rules)
          r.id == rule.id ? r.withEnabled(enabled) : r,
      ]),
    ),
  );

  Future<void> _deleteGroup() async {
    final id = _groupId!;
    if (!await confirm(context, c.s, c.s.t('deleteGroupConfirm'))) return;
    final groups = {...c.family.config.appGroups}..remove(id);
    final names = {...c.family.groupNames}..remove(id);
    final owners = {...c.family.groupOwners}..remove(id);
    final rules = c.family.state.rules
        .where((r) => r.appTarget != AppTarget.group(id))
        .toList();
    await c.updateFamily(
      c.family.copyWith(
        config: configWithGroups(c.family.config, groups),
        groupNames: names,
        groupOwners: owners,
        state: stateWithRules(c.family.state, rules),
      ),
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      final s = c.s;
      final theme = Theme.of(context);
      final id = _groupId;
      if (id != null && !c.family.groupNames.containsKey(id)) {
        // Deleted meanwhile.
        return const Scaffold();
      }
      final rules = c.targetRules(widget.target);
      final title = switch (widget.target.kind) {
        TargetKind.all => s.t('allScreens'),
        TargetKind.group => c.groupName(id!),
        TargetKind.single => c.targetLabel(widget.target),
      };
      final apps = [...?c.family.config.appGroups[id]]
        ..sort(
          (a, b) => c
              .appName(a, androidLabel: _info[a]?.label)
              .toLowerCase()
              .compareTo(
                c.appName(b, androidLabel: _info[b]?.label).toLowerCase(),
              ),
        );
      return Scaffold(
        appBar: AppBar(
          title: Text(title),
          actions: [
            if (id != null) ...[
              IconButton(
                tooltip: s.t('editGroup'),
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => _push(GroupEditor(controller: c, groupId: id)),
              ),
              IconButton(
                tooltip: s.t('delete'),
                icon: const Icon(Icons.delete_outline),
                onPressed: _deleteGroup,
              ),
            ],
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            if (_today != null)
              ListTile(
                leading: const Icon(Icons.today_outlined),
                title: Text(s.t('groupToday', {'time': s.duration(_today!)})),
              ),
            if (widget.target.kind != TargetKind.group)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  s.t(
                    widget.target.kind == TargetKind.all
                        ? 'totalHint'
                        : 'singleHint',
                  ),
                  style: theme.textTheme.bodySmall,
                ),
              ),
            const Divider(),
            ListTile(
              title: Text(s.t('rules'), style: theme.textTheme.titleMedium),
            ),
            if (rules.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(s.t('noLimit')),
              ),
            for (final r in rules)
              ListTile(
                leading: Icon(
                  Icons.timer_outlined,
                  color: r.enabled ? null : theme.disabledColor,
                ),
                title: Text(
                  c.summaryOf(r).isEmpty
                      ? s.t('ruleNoSetting')
                      : c.summaryOf(r),
                  style: r.enabled
                      ? null
                      : TextStyle(color: theme.disabledColor),
                ),
                subtitle: r.enabled ? null : Text(s.t('ruleOff')),
                trailing: Switch(
                  value: r.enabled,
                  onChanged: (v) => _setEnabled(r, v),
                ),
                onTap: () => _push(RuleEditor(controller: c, rule: r)),
              ),
            ListTile(
              leading: const Icon(Icons.add),
              title: Text(s.t('addRule')),
              onTap: () => _push(
                RuleEditor(controller: c, initialTarget: widget.target),
              ),
            ),
            if (id != null) ...[
              const Divider(),
              ListTile(
                title: Text(
                  s.t('groupApps'),
                  style: theme.textTheme.titleMedium,
                ),
                trailing: TextButton(
                  onPressed: () =>
                      _push(GroupEditor(controller: c, groupId: id)),
                  child: Text(s.t('editGroup')),
                ),
              ),
              if (apps.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(s.t('groupNoApps')),
                ),
              for (final app in apps)
                ListTile(
                  dense: true,
                  leading: _info[app]?.icon == null
                      ? const Icon(Icons.android)
                      : Image.memory(
                          _info[app]!.icon!,
                          width: 28,
                          height: 28,
                          gaplessPlayback: true,
                        ),
                  title: Text(c.appName(app, androidLabel: _info[app]?.label)),
                ),
            ],
          ],
        ),
      );
    },
  );
}

/// Lets the parent pick an installed app; its package, or `null`.
Future<String?> pickApp(BuildContext context, AppController c) => Navigator.of(
  context,
).push(MaterialPageRoute<String>(builder: (_) => _AppPicker(controller: c)));

class _AppPicker extends StatefulWidget {
  final AppController controller;

  const _AppPicker({required this.controller});

  @override
  State<_AppPicker> createState() => _AppPickerState();
}

class _AppPickerState extends State<_AppPicker> {
  List<InstalledApp>? _apps;
  Map<String, AppInfo> _info = const {};
  String _query = '';

  @override
  void initState() {
    super.initState();
    final c = widget.controller;
    c.familyApps().then((apps) async {
      String name(InstalledApp a) =>
          c.appName(a.package, androidLabel: a.label).toLowerCase();
      if (!mounted) return;
      setState(
        () => _apps = [...apps]
          ..sort((a, b) {
            // The browsers' videos, then the apps by name.
            final va = a.package == browserVideoApp;
            if (va != (b.package == browserVideoApp)) return va ? -1 : 1;
            return name(a).compareTo(name(b));
          }),
      );
      // Then the icons, from here or the other devices.
      try {
        final info = await c.appInfo([for (final a in apps) a.package]);
        if (mounted) setState(() => _info = info);
      } on Object {
        // Without icons.
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final s = c.s;
    final q = _query.toLowerCase();
    final shown = _apps
        ?.where(
          (a) =>
              q.isEmpty ||
              c
                  .appName(a.package, androidLabel: a.label)
                  .toLowerCase()
                  .contains(q) ||
              a.package.contains(q),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(title: Text(s.t('limitAnApp'))),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: s.t('searchApps'),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: shown == null
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: shown.length,
                    itemBuilder: (context, i) {
                      final app = shown[i];
                      return ListTile(
                        leading: appIcon(
                          _info[app.package],
                          size: 36,
                          package: app.package,
                        ),
                        title: Text(
                          c.appName(app.package, androidLabel: app.label),
                        ),
                        subtitle: Text(app.package),
                        onTap: () => Navigator.pop(context, app.package),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
