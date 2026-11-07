/// The child's eye breaks: how often, how long, how many put-offs, and
/// whether the screen is veiled.
library;

import 'package:flutter/material.dart';
import 'package:screentime_engine/screentime_engine.dart';

import '../controller.dart';
import '../strings.dart';
import 'widgets.dart';

/// Lengths offered for a break, in seconds.
const eyeBreakLengths = [10, 20, 30, 45, 60];

/// Screen time offered between two breaks, in minutes.
const eyeBreakIntervals = [10, 15, 20, 25, 30, 40];

/// Most put-offs in a row.
const eyeBreakMaxSnoozes = 5;

/// "20 s every 20 min", or "Off".
String eyeBreakSummary(S s, EyeBreakPolicy p) => p.enabled
    ? s.t('eyeBreakSummary', {
        'length': s.duration(p.length),
        'every': s.duration(p.every),
      })
    : s.t('eyeBreakOff');

class EyeBreakScreen extends StatefulWidget {
  final AppController controller;

  const EyeBreakScreen({super.key, required this.controller});

  @override
  State<EyeBreakScreen> createState() => _EyeBreakScreenState();
}

class _EyeBreakScreenState extends State<EyeBreakScreen> {
  late EyeBreakPolicy _policy;

  @override
  void initState() {
    super.initState();
    _policy = widget.controller.child?.eyeBreak ?? const EyeBreakPolicy();
  }

  void _set(EyeBreakPolicy p) {
    setState(() => _policy = p);
    widget.controller.setEyeBreak(p);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.controller.s;
    final theme = Theme.of(context);
    final p = _policy;
    return Scaffold(
      appBar: AppBar(title: Text(s.t('eyeBreakTitle'))),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.visibility_outlined),
            title: Text(s.t('eyeBreakTitle')),
            subtitle: Text(s.t('eyeBreakHint')),
            value: p.enabled,
            onChanged: (v) => _set(p.copyWith(enabled: v)),
          ),
          if (p.enabled) ...[
            const Divider(),
            DurationTile(
              s: s,
              title: s.t('eyeBreakEvery'),
              value: p.every,
              presets: eyeBreakIntervals,
              onChanged: (d) {
                if (d != null && d > Duration.zero) _set(p.copyWith(every: d));
              },
            ),
            ListTile(
              title: Text(s.t('eyeBreakLength')),
              trailing: DropdownButton<int>(
                value: eyeBreakLengths.contains(p.length.inSeconds)
                    ? p.length.inSeconds
                    : null,
                hint: Text(s.duration(p.length)),
                items: [
                  for (final l in eyeBreakLengths)
                    DropdownMenuItem(
                      value: l,
                      child: Text(s.duration(Duration(seconds: l))),
                    ),
                ],
                onChanged: (l) {
                  if (l != null) _set(p.copyWith(length: Duration(seconds: l)));
                },
              ),
            ),
            CountTile(
              title: s.t('eyeBreakSnoozes'),
              valueText: '${p.snoozes}',
              value: p.snoozes,
              min: 0,
              max: eyeBreakMaxSnoozes,
              onChanged: (n) => _set(p.copyWith(snoozes: n)),
            ),
            SwitchListTile(
              title: Text(s.t('eyeBreakVeil')),
              subtitle: Text(s.t('eyeBreakVeilHint')),
              value: p.veil,
              onChanged: (v) => _set(p.copyWith(veil: v)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Text(
                s.t('eyeBreakNote'),
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
