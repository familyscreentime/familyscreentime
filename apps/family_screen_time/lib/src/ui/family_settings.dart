/// Settings shared by the whole family rather than one child: special
/// periods, devices used at the same time, how long use is kept, and the
/// parent code. Their own page on a parent's device; at the end of the
/// settings on a child's device.
library;

import 'package:flutter/material.dart';
import 'package:screentime_engine/screentime_engine.dart';

import '../controller.dart';
import '../store.dart';
import 'periods_screen.dart';
import 'pin_dialog.dart';
import 'trends_screen.dart' show keptLabel;

/// The special period now running, else the next one, if any.
String periodsSummary(AppController c, DateTime now) {
  final s = c.s;
  final running = c.activePeriod(now);
  if (running != null) {
    return '${c.periodName(running)} · ${nextDates(s, running, now)}';
  }
  (Profile, DateTime)? next;
  for (final p in c.specialPeriods) {
    for (final r in p.periods) {
      if (r.first.isAfter(now) && (next == null || r.first.isBefore(next.$2))) {
        next = (p, r.first);
      }
    }
  }
  if (next != null) {
    return '${c.periodName(next.$1)} · ${nextDates(s, next.$1, now)}';
  }
  return c.specialPeriods.isEmpty
      ? s.t('periodsNone')
      : c.specialPeriods.map(c.periodName).join(', ');
}

/// The family's settings, as a list of tiles to put in a page.
class FamilySettingsSection extends StatelessWidget {
  final AppController controller;

  const FamilySettingsSection({super.key, required this.controller});

  Future<void> _changePin(BuildContext context) async {
    final pin = await askNewPin(context, controller);
    if (pin == null) return;
    await controller.changeParentCode(pin);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(controller.s.t('pinChanged'))));
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final c = controller;
      final s = c.s;
      final theme = Theme.of(context);
      final header = theme.textTheme.titleMedium;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: const Icon(Icons.event_outlined),
            title: Text(s.t('periodsTitle')),
            subtitle: Text(periodsSummary(c, DateTime.now())),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => PeriodsScreen(controller: c),
              ),
            ),
          ),
          const Divider(),
          ListTile(title: Text(s.t('countingTitle'), style: header)),
          RadioGroup<SimultaneousCounting>(
            groupValue: c.family.config.counting,
            onChanged: (v) {
              if (v != null) {
                c.updateFamily(
                  c.family.copyWith(
                    config: c.family.config.copyWith(counting: v),
                  ),
                );
              }
            },
            child: Column(
              children: [
                for (final (mode, title, hint) in [
                  (SimultaneousCounting.sum, 'countingSum', 'countingSumHint'),
                  (
                    SimultaneousCounting.elapsed,
                    'countingOnce',
                    'countingOnceHint',
                  ),
                ])
                  RadioListTile<SimultaneousCounting>(
                    value: mode,
                    title: Text(s.t(title)),
                    subtitle: Text(s.t(hint)),
                  ),
              ],
            ),
          ),
          const Divider(),
          ListTile(title: Text(s.t('historyTitle'), style: header)),
          ListTile(
            leading: const Icon(Icons.history),
            title: Text(s.t('usageKept')),
            subtitle: DropdownButton<int>(
              value: c.family.usageKeptDays,
              isExpanded: true,
              items: [
                for (final d in {...usageKeptChoices, c.family.usageKeptDays})
                  DropdownMenuItem(value: d, child: Text(keptLabel(s, d))),
              ],
              onChanged: (d) {
                if (d != null) {
                  c.updateFamily(c.family.copyWith(usageKeptDays: d));
                }
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(72, 0, 16, 8),
            child: Text(s.t('usageKeptHint'), style: theme.textTheme.bodySmall),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.password),
            title: Text(s.t('changePin')),
            onTap: () => _changePin(context),
          ),
        ],
      );
    },
  );
}

/// The family's settings on their own page (a parent's device).
class FamilySettingsScreen extends StatelessWidget {
  final AppController controller;

  const FamilySettingsScreen({super.key, required this.controller});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(controller.s.t('familySettingsTitle'))),
    body: ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [FamilySettingsSection(controller: controller)],
    ),
  );
}
