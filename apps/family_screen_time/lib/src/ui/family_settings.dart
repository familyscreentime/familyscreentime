/// Settings shared by the whole family rather than one child: special
/// periods, devices used at the same time, how long use is kept, and the
/// parent code. Their own page on a parent's device; at the end of the
/// settings on a child's device.
library;

import 'package:flutter/material.dart';
import 'package:screentime_engine/screentime_engine.dart';

import '../controller.dart';
import '../platform.dart' show BiometricStatus;
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
    final biometric = controller.biometricOn;
    await controller.changeParentCode(pin);
    // The fingerprint or face kept the former code: the new one, now.
    if (biometric) await controller.enableBiometric(pin);
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
          if (c.settings.parentDevice) _BiometricTile(controller: c),
        ],
      );
    },
  );
}

/// On a parent's device with a fingerprint or face: parent mode opened
/// with them, or not.
class _BiometricTile extends StatefulWidget {
  final AppController controller;

  const _BiometricTile({required this.controller});

  @override
  State<_BiometricTile> createState() => _BiometricTileState();
}

class _BiometricTileState extends State<_BiometricTile> {
  late final Future<bool> _available = widget.controller.biometricAvailable();
  bool _busy = false;

  Future<void> _set(bool on) async {
    final c = widget.controller;
    setState(() => _busy = true);
    if (!on) {
      await c.disableBiometric();
    } else if (c.parentCodeKnown ||
        await askParentPin(context, c, offerBiometric: false)) {
      final status = await c.enableBiometric();
      if (mounted &&
          status != BiometricStatus.ok &&
          status != BiometricStatus.cancelled) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(c.s.t('biometricFailed'))));
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
    future: _available,
    builder: (context, snap) {
      final c = widget.controller;
      // Shown while on, even if the device lost its fingerprints: it can
      // still be turned off.
      if (snap.data != true && !c.biometricOn) return const SizedBox.shrink();
      return SwitchListTile(
        secondary: const Icon(Icons.fingerprint),
        title: Text(c.s.t('biometricSetting')),
        subtitle: Text(c.s.t('biometricSettingHint')),
        value: c.biometricOn,
        onChanged: _busy ? null : _set,
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
