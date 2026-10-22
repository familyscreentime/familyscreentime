/// Special periods — holidays, exams, a week at the grandparents'… — each
/// with a name and dates. Rules can apply only during one of them, or only
/// in normal times.
library;

import 'package:flutter/material.dart';
import 'package:screentime_engine/screentime_engine.dart';

import '../controller.dart';
import '../store.dart';
import '../strings.dart';
import 'widgets.dart';

/// "From 20/10 to 03/11" (a single day: just the date).
String rangeLabel(S s, DateRange p) => sameDay(p.first, p.last)
    ? s.date(p.first)
    : s.t('periodRange', {'from': s.date(p.first), 'to': s.date(p.last)});

/// The current or next dates of [p], with "Now" when it runs today; `null`
/// when it has no dates left.
String? nextDates(S s, Profile p, DateTime now) {
  final today = dayOf(now);
  final ranges = [...p.periods]..sort((a, b) => a.first.compareTo(b.first));
  for (final r in ranges) {
    if (r.last.isBefore(today)) continue;
    return r.contains(today)
        ? '${s.t('periodNow')} · ${rangeLabel(s, r)}'
        : rangeLabel(s, r);
  }
  return null;
}

class PeriodsScreen extends StatelessWidget {
  final AppController controller;

  const PeriodsScreen({super.key, required this.controller});

  Future<void> _edit(BuildContext context, Profile? period) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PeriodEditor(controller: controller, period: period),
        ),
      );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final c = controller;
      final s = c.s;
      final periods = c.specialPeriods;
      final now = DateTime.now();
      return Scaffold(
        appBar: AppBar(title: Text(s.t('periodsTitle'))),
        floatingActionButton: FloatingActionButton.extended(
          icon: const Icon(Icons.add),
          label: Text(s.t('periodAdd')),
          onPressed: () => _edit(context, null),
        ),
        body: ReorderableListView(
          padding: const EdgeInsets.only(bottom: 96),
          header: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              periods.isEmpty
                  ? '${s.t('periodsHint')}\n\n${s.t('periodsNone')}'
                  : s.t('periodsHint'),
            ),
          ),
          // The new index is already adjusted for the removed item.
          onReorderItem: (from, to) {
            final list = [...periods];
            list.insert(to, list.removeAt(from));
            c.setSpecialPeriods(list);
          },
          children: [
            for (final p in periods)
              ListTile(
                key: ValueKey(p.id),
                leading: const Icon(Icons.event_outlined),
                title: Text(c.periodName(p)),
                subtitle: Text(nextDates(s, p, now) ?? s.t('periodNoDates')),
                trailing: const Icon(Icons.drag_handle),
                onTap: () => _edit(context, p),
              ),
          ],
        ),
      );
    },
  );
}

class PeriodEditor extends StatefulWidget {
  final AppController controller;

  /// Period to edit; `null` creates one.
  final Profile? period;

  const PeriodEditor({super.key, required this.controller, this.period});

  @override
  State<PeriodEditor> createState() => _PeriodEditorState();
}

class _PeriodEditorState extends State<PeriodEditor> {
  late final TextEditingController _name;
  late List<DateRange> _ranges;
  String? _error;

  AppController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    final p = widget.period;
    _name = TextEditingController(text: p == null ? '' : c.periodName(p));
    _ranges = [...?p?.periods]..sort((a, b) => a.first.compareTo(b.first));
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _addDates() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: addDays(dayOf(now), -365),
      lastDate: addDays(dayOf(now), 2 * 365),
    );
    if (range == null) return;
    setState(
      () =>
          _ranges = [..._ranges, DateRange(range.start, range.end)]
            ..sort((a, b) => a.first.compareTo(b.first)),
    );
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = c.s.t('periodNameMissing'));
      return;
    }
    final edited = Profile(
      id: widget.period?.id ?? newId(),
      name: name,
      kind: ProfileKind.custom,
      periods: _ranges,
    );
    final list = c.specialPeriods;
    final i = list.indexWhere((p) => p.id == edited.id);
    await c.setSpecialPeriods(
      i < 0 ? [...list, edited] : ([...list]..[i] = edited),
    );
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final s = c.s;
    if (!await confirm(context, s, s.t('periodDeleteConfirm'))) return;
    await c.setSpecialPeriods([
      for (final p in c.specialPeriods)
        if (p.id != widget.period!.id) p,
    ]);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final s = c.s;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(s.t('periodsTitle')),
        actions: [
          if (widget.period != null)
            IconButton(
              tooltip: s.t('delete'),
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
          TextButton(onPressed: _save, child: Text(s.t('save'))),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _name,
            decoration: InputDecoration(
              labelText: s.t('periodName'),
              errorText: _error,
              border: const OutlineInputBorder(),
            ),
          ),
          if (widget.period == null) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (var i = 1; i <= 6; i++)
                  ActionChip(
                    label: Text(s.t('periodSuggest$i')),
                    onPressed: () =>
                        setState(() => _name.text = s.t('periodSuggest$i')),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 24),
          Text(s.t('periodDates'), style: theme.textTheme.titleMedium),
          if (_ranges.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(s.t('periodNoDates')),
            ),
          for (final r in _ranges)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.date_range),
              title: Text(rangeLabel(s, r)),
              trailing: IconButton(
                tooltip: s.t('delete'),
                icon: const Icon(Icons.delete_outline),
                onPressed: () => setState(
                  () => _ranges = [
                    for (final o in _ranges)
                      if (!identical(o, r)) o,
                  ],
                ),
              ),
            ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              icon: const Icon(Icons.add),
              label: Text(s.t('periodAddDates')),
              onPressed: _addDates,
            ),
          ),
        ],
      ),
    );
  }
}
