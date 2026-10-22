/// Parent's follow-up of the limits the child sets: facts only — kept and
/// exceeded days, changes, removals — with no judgement or advice.
library;

import 'package:flutter/material.dart';
import 'package:screentime_engine/screentime_engine.dart';

import '../controller.dart';
import '../self_limits.dart';
import '../strings.dart';

class SelfLimitReportScreen extends StatefulWidget {
  final AppController controller;

  /// Current time; for tests.
  final DateTime Function() clock;

  const SelfLimitReportScreen({
    super.key,
    required this.controller,
    this.clock = DateTime.now,
  });

  @override
  State<SelfLimitReportScreen> createState() => _SelfLimitReportScreenState();
}

class _SelfLimitReportScreenState extends State<SelfLimitReportScreen> {
  int _period = 7;
  List<UsageSegment>? _usage;

  AppController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    c.recentUsage().then((u) {
      if (mounted) setState(() => _usage = u);
    });
    c.loadLabels({
      for (final e in c.family.selfLimitLog)
        if (e.target.kind == TargetKind.single) e.target.id!,
    });
  }

  String _name(AppTarget t) =>
      t == const AppTarget.all() ? c.s.t('allScreens') : c.targetLabel(t);

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      final s = c.s;
      final child = c.child?.name ?? '';
      final usage = _usage;
      final now = widget.clock();
      final report = usage == null
          ? null
          : selfLimitReport(
              engine: RuleEngine(c.family.config),
              log: c.family.selfLimitLog,
              usage: usage,
              childId: c.settings.childId!,
              now: now,
              period: _period,
            );
      return Scaffold(
        appBar: AppBar(title: Text(s.t('selfReportTitle', {'name': child}))),
        body: report == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  SegmentedButton<int>(
                    segments: [
                      ButtonSegment(value: 7, label: Text(s.days(7))),
                      ButtonSegment(value: 30, label: Text(s.days(30))),
                    ],
                    selected: {_period},
                    onSelectionChanged: (v) =>
                        setState(() => _period = v.first),
                  ),
                  const SizedBox(height: 16),
                  if (report.stories.isEmpty)
                    Text(s.t('selfReportNone', {'name': child}))
                  else ...[
                    _figures(context, s, report, now),
                    const SizedBox(height: 8),
                    Text(
                      s.t('selfReportLegend'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    for (final story in report.stories)
                      _story(context, s, story),
                  ],
                  const SizedBox(height: 16),
                  Text(
                    s.t('selfReportHint', {'name': child}),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
      );
    },
  );

  Widget _figures(
    BuildContext context,
    S s,
    SelfLimitReport report,
    DateTime now,
  ) {
    final theme = Theme.of(context);
    final share = report.keptShare;
    final lifetime = report.averageLifetime(now);
    final gap = report.averageGap;
    Widget line(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(value, style: theme.textTheme.titleMedium),
        ],
      ),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            line(
              s.t('selfReportKept'),
              share == null
                  ? '–'
                  : '${(share * 100).round()} % '
                        '(${report.count(DayOutcome.kept)}/'
                        '${report.count(DayOutcome.kept) + report.count(DayOutcome.exceeded)})',
            ),
            line(s.t('selfReportRemovals'), '${report.removals}'),
            line(
              s.t('selfReportLifetime'),
              lifetime == null
                  ? '–'
                  : lifetime.inDays >= 1
                  ? s.days(lifetime.inDays)
                  : s.duration(lifetime),
            ),
            line(
              s.t('selfReportGap'),
              gap == null
                  ? '–'
                  : gap.isNegative
                  ? s.t('selfReportGapBelow', {'time': s.duration(-gap)})
                  : s.t('selfReportGapAbove', {'time': s.duration(gap)}),
            ),
          ],
        ),
      ),
    );
  }

  Widget _story(BuildContext context, S s, SelfLimitStory story) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final kept = story.days.where((d) => d == DayOutcome.kept).length;
    final exceeded = story.days.where((d) => d == DayOutcome.exceeded).length;
    Widget dot(DayOutcome o) => Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: switch (o) {
          DayOutcome.kept => Colors.green,
          DayOutcome.exceeded => scheme.error,
          DayOutcome.none => scheme.surfaceContainerHighest,
          DayOutcome.ongoing => null,
        },
        border: o == DayOutcome.ongoing
            ? Border.all(color: scheme.outline, width: 2)
            : null,
      ),
    );
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_name(story.target), style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [for (final o in story.days) dot(o)],
            ),
            const SizedBox(height: 6),
            Text(
              s.t('selfReportDaysKept', {
                'kept': '$kept',
                'exceeded': '$exceeded',
              }),
            ),
            const SizedBox(height: 6),
            for (final e in story.events)
              Text(switch (e.action) {
                SelfLimitAction.created => s.t('selfReportCreated', {
                  'date': s.date(e.at),
                  'time': s.duration(e.daily ?? Duration.zero),
                }),
                SelfLimitAction.changed => s.t('selfReportChanged', {
                  'date': s.date(e.at),
                  'time': s.duration(e.daily ?? Duration.zero),
                }),
                SelfLimitAction.removed => s.t('selfReportRemoved', {
                  'date': s.date(e.at),
                }),
              }, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
