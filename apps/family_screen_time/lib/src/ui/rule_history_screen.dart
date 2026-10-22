/// The child's view of a rule's recent days: overruns, savings and where
/// the firm limit stands.
library;

import 'package:flutter/material.dart';
import 'package:screentime_engine/screentime_engine.dart';

import '../controller.dart';
import '../rule_history.dart';
import '../strings.dart';

class RuleHistoryScreen extends StatefulWidget {
  final AppController controller;
  final Rule rule;

  /// Instant the history stops at; now by default (for tests).
  final DateTime? now;

  const RuleHistoryScreen({
    super.key,
    required this.controller,
    required this.rule,
    this.now,
  });

  @override
  State<RuleHistoryScreen> createState() => _RuleHistoryScreenState();
}

class _RuleHistoryScreenState extends State<RuleHistoryScreen> {
  RuleHistory? _history;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final c = widget.controller;
    final usage = await c.recentUsage();
    final s = c.family.state;
    final state = s.copyWith(usage: usage);
    final history = ruleHistory(
      RuleEngine(c.family.config),
      state,
      widget.rule,
      childId: c.settings.childId!,
      now: widget.now ?? DateTime.now(),
    );
    if (mounted) setState(() => _history = history);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final s = c.s;
    final h = _history;
    return Scaffold(
      appBar: AppBar(title: Text(c.labelOf(widget.rule))),
      body: h == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _summary(context, s, h),
                const SizedBox(height: 8),
                for (final (i, day) in h.days.indexed)
                  _dayTile(context, s, h, day, today: i == 0),
              ],
            ),
    );
  }

  Widget _summary(BuildContext context, S s, RuleHistory h) {
    final theme = Theme.of(context);
    final hardening = h.hardening;
    Widget figure(String label, Duration value, {Color? color}) => Expanded(
      child: Column(
        children: [
          Text(
            s.duration(value),
            style: theme.textTheme.titleLarge?.copyWith(color: color),
          ),
          Text(
            label,
            style: theme.textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              s.t('historyPeriod', {'count': '${h.period}'}),
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                figure(
                  s.t('historyTotalOverrun'),
                  h.totalOverrun,
                  color: h.totalOverrun > Duration.zero
                      ? theme.colorScheme.error
                      : null,
                ),
                if (h.savingsLeft != null) ...[
                  figure(s.t('historyTotalSaved'), h.totalSaved),
                  figure(s.t('historySavingsLeft'), h.savingsLeft!),
                ],
              ],
            ),
            if (hardening != null) ...[
              const Divider(height: 24),
              Text(s.t('historyFirmTitle'), style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(
                s.t('historyFirmCount', {
                  'threshold': s.duration(hardening.threshold),
                  'window': '${hardening.window}',
                  'count': '${h.firmCount}',
                  'days': '${hardening.days}',
                }),
              ),
              if (h.firm)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    s.t('historyFirmOn'),
                    style: TextStyle(
                      color: theme.colorScheme.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              else if (h.firmNext)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(s.t('historyFirmNext')),
                ),
              if (hardening.deductOverruns)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    s.t('historyFirmDeduct'),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _dayTile(
    BuildContext context,
    S s,
    RuleHistory h,
    DayLedger d, {
    required bool today,
  }) {
    final theme = Theme.of(context);
    final title = today
        ? s.t('today')
        : '${s.weekday(d.day.weekday)} ${s.date(d.day)}';
    if (!d.active) {
      return ListTile(
        dense: true,
        title: Text(title),
        subtitle: Text(s.t('historyNoLimit')),
      );
    }
    // As on the home screen: the day's own time and the savings usable.
    final total = d.allowance + d.savingsAvailable;
    final error = theme.colorScheme.error;
    final lines = <(String, Color?)>[
      if (d.unlocked) (s.t('historyUnlocked'), null),
      if (d.overrun > Duration.zero)
        (
          s.t('historyOverrun', {'time': s.duration(d.overrun)}),
          h.counts(d) ? error : null,
        ),
      if (d.bonus > Duration.zero)
        (s.t('historyBonus', {'time': s.duration(d.bonus)}), null),
      if (d.carriedIn > Duration.zero)
        (s.t('historyCarried', {'time': s.duration(d.carriedIn)}), null),
      if (d.deducted > Duration.zero)
        (s.t('historyDeducted', {'time': s.duration(d.deducted)}), null),
      if (d.savingsUsed > Duration.zero)
        (s.t('historySavingsUsed', {'time': s.duration(d.savingsUsed)}), null),
      if (d.saved > Duration.zero)
        (s.t('historySaved', {'time': s.duration(d.saved)}), null),
    ];
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(title, style: theme.textTheme.titleSmall)),
                Text(
                  s.t('historyUsedOf', {
                    'used': s.duration(d.consumed),
                    'total': s.duration(total),
                  }),
                ),
              ],
            ),
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: total == Duration.zero
                  ? (d.consumed > Duration.zero ? 1 : 0)
                  : (d.consumed.inSeconds / total.inSeconds).clamp(0, 1),
              color: d.overrun > Duration.zero ? error : null,
              minHeight: 6,
              borderRadius: BorderRadius.circular(3),
            ),
            for (final (text, color) in lines)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  text,
                  style: theme.textTheme.bodySmall?.copyWith(color: color),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
