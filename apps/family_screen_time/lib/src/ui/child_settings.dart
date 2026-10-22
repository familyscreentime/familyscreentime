/// Settings the child chooses alone: the floating countdown and the
/// warnings before time runs out.
library;

import 'package:flutter/material.dart';
import 'package:screentime_engine/screentime_engine.dart';

import '../controller.dart';
import '../store.dart';

/// Warnings the child can pick, in minutes left.
const warningChoices = [30, 15, 10, 5, 2, 1];

class ChildSettings extends StatefulWidget {
  final AppController controller;

  const ChildSettings({super.key, required this.controller});

  @override
  State<ChildSettings> createState() => _ChildSettingsState();
}

class _ChildSettingsState extends State<ChildSettings> {
  AppController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    // Android's names of the apps limited on their own.
    controller.loadLabels();
  }

  /// Total screen time, groups and apps with a limit for the child.
  List<AppTarget> _targets() {
    // Total screen time first, then the groups, then the apps.
    int rank(AppTarget t) => switch (t.kind) {
      TargetKind.all => 0,
      TargetKind.group => 1,
      TargetKind.single => 2,
    };
    final targets = {
      for (final r in controller.activeChildRules)
        if (r.hasQuota || r.schedule != null) r.appTarget,
    }.toList();
    return targets..sort((a, b) {
      final byKind = rank(a).compareTo(rank(b));
      return byKind != 0
          ? byKind
          : controller.targetLabel(a).compareTo(controller.targetLabel(b));
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final c = controller;
      final s = c.s;
      final theme = Theme.of(context);
      final warnings = c.settings.warningMinutes.toSet();
      return Scaffold(
        appBar: AppBar(title: Text(s.t('childSettingsTitle'))),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(s.t('overlayTitle'), style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'off', label: Text(s.t('overlayOff'))),
                ButtonSegment(
                  value: 'digits',
                  icon: const Icon(Icons.timer_outlined),
                  label: Text(s.t('overlayDigits')),
                ),
                ButtonSegment(
                  value: 'disc',
                  icon: const Icon(Icons.pie_chart_outline),
                  label: Text(s.t('overlayDisc')),
                ),
              ],
              selected: {c.settings.overlay},
              onSelectionChanged: (v) =>
                  c.updateSettings(c.settings.copyWith(overlay: v.first)),
            ),
            const SizedBox(height: 6),
            Text(s.t('overlayHint'), style: theme.textTheme.bodySmall),
            if (c.settings.overlay != 'off' && _targets().length > 1) ...[
              const SizedBox(height: 16),
              Text(s.t('countdownFor'), style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final t in _targets())
                    FilterChip(
                      label: Text(
                        t.kind == TargetKind.all
                            ? s.t('allScreens')
                            : c.targetLabel(t),
                      ),
                      selected: !c.settings.hiddenCountdowns.contains(
                        countdownKey(t),
                      ),
                      onSelected: (_) {
                        // From the current settings: an earlier tap may not
                        // have been redrawn yet.
                        final next = {...c.settings.hiddenCountdowns};
                        final key = countdownKey(t);
                        if (!next.remove(key)) next.add(key);
                        c.updateSettings(
                          c.settings.copyWith(hiddenCountdowns: next),
                        );
                      },
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(s.t('countdownForHint'), style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: 24),
            Text(s.t('warningsTitle'), style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final m in {
                  ...warningChoices,
                  ...warnings,
                }.toList()..sort((a, b) => b.compareTo(a)))
                  FilterChip(
                    label: Text(s.duration(Duration(minutes: m))),
                    selected: warnings.contains(m),
                    onSelected: (on) {
                      // The current settings: an earlier tap may not have
                      // been redrawn yet.
                      final next = {...c.settings.warningMinutes};
                      on ? next.add(m) : next.remove(m);
                      c.updateSettings(
                        c.settings.copyWith(
                          warningMinutes: next.toList()
                            ..sort((a, b) => b.compareTo(a)),
                        ),
                      );
                    },
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(s.t('warningsHint'), style: theme.textTheme.bodySmall),
          ],
        ),
      );
    },
  );
}
