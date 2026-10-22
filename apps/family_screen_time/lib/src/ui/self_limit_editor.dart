/// The child sets, changes or removes a limit for themselves, freely: "stop
/// Minecraft after 15 minutes, so I have time for Roblox too".
library;

import 'package:flutter/material.dart';
import 'package:screentime_engine/screentime_engine.dart';

import '../controller.dart';
import 'limit_screen.dart';
import 'widgets.dart';

/// Times per day offered, in minutes.
const selfLimitChoices = [5, 10, 15, 20, 30, 45, 60, 90, 120];

class SelfLimitEditor extends StatefulWidget {
  final AppController controller;

  /// Limit to change; `null` creates one.
  final Rule? rule;

  const SelfLimitEditor({super.key, required this.controller, this.rule});

  @override
  State<SelfLimitEditor> createState() => _SelfLimitEditorState();
}

class _SelfLimitEditorState extends State<SelfLimitEditor> {
  late AppTarget _target;
  late int _minutes;

  AppController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    _target = widget.rule?.appTarget ?? const AppTarget.all();
    _minutes = widget.rule?.dailyQuota?.inMinutes ?? 30;
  }

  Future<void> _pickApp() async {
    final app = await pickApp(context, c);
    if (app == null) return;
    await c.loadLabels([app]);
    setState(() => _target = AppTarget.app(app));
  }

  Future<void> _save() async {
    await c.saveSelfLimit(
      _target,
      Duration(minutes: _minutes),
      id: widget.rule?.id,
    );
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _remove() async {
    final s = c.s;
    if (!await confirm(context, s, s.t('selfLimitRemoveConfirm'))) return;
    await c.removeSelfLimit(widget.rule!);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final s = c.s;
    final theme = Theme.of(context);
    final targets = <AppTarget>[
      const AppTarget.all(),
      for (final id in c.family.groupNames.keys) AppTarget.group(id),
      if (_target.kind == TargetKind.single) _target,
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(s.t('selfLimitTitle')),
        actions: [
          if (widget.rule != null)
            IconButton(
              tooltip: s.t('delete'),
              icon: const Icon(Icons.delete_outline),
              onPressed: _remove,
            ),
          TextButton(onPressed: _save, child: Text(s.t('save'))),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(s.t('selfLimitWhat'), style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final t in targets)
                ChoiceChip(
                  label: Text(
                    t == const AppTarget.all()
                        ? s.t('allScreens')
                        : c.targetLabel(t),
                  ),
                  selected: t == _target,
                  onSelected: (_) => setState(() => _target = t),
                ),
              ActionChip(
                avatar: const Icon(Icons.apps, size: 18),
                label: Text(s.t('selfLimitOneApp')),
                onPressed: _pickApp,
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(s.t('selfLimitHowLong'), style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          DurationChoice(
            s: s,
            presets: selfLimitChoices,
            value: Duration(minutes: _minutes),
            onChanged: (d) => setState(() => _minutes = d.inMinutes),
          ),
          const SizedBox(height: 24),
          Text(s.t('selfLimitHint'), style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}
