/// Small editing widgets: a duration picker and a time-range list.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:screentime_engine/screentime_engine.dart';

import '../strings.dart';

const _presets = [15, 30, 45, 60, 90, 120, 180];

/// A list tile showing a duration; tapping it opens presets, "none" and a
/// custom value.
class DurationTile extends StatelessWidget {
  final S s;
  final String title;
  final Duration? value;
  final ValueChanged<Duration?> onChanged;

  /// Label for "no value"; defaults to "None".
  final String? noneLabel;

  /// Offers 0 minutes among the presets (a day without time).
  final bool allowZero;

  final bool dense;

  /// Choices offered, in minutes.
  final List<int> presets;

  const DurationTile({
    super.key,
    required this.s,
    required this.title,
    required this.value,
    required this.onChanged,
    this.noneLabel,
    this.allowZero = false,
    this.dense = false,
    this.presets = _presets,
  });

  @override
  Widget build(BuildContext context) => ListTile(
    dense: dense,
    title: Text(title),
    trailing: Text(
      value == null ? noneLabel ?? s.t('none') : s.duration(value!),
    ),
    onTap: () async {
      final picked = await showModalBottomSheet<_Pick>(
        context: context,
        builder: (context) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                title: Text(noneLabel ?? s.t('none')),
                onTap: () => Navigator.pop(context, const _Pick(null)),
              ),
              for (final m in [if (allowZero) 0, ...presets])
                ListTile(
                  title: Text(s.duration(Duration(minutes: m))),
                  onTap: () =>
                      Navigator.pop(context, _Pick(Duration(minutes: m))),
                ),
              ListTile(
                leading: const Icon(Icons.edit),
                title: Text(s.t('minutes')),
                onTap: () async {
                  final custom = await _askMinutes(context, s, value);
                  if (context.mounted && custom != null) {
                    Navigator.pop(context, _Pick(custom));
                  }
                },
              ),
            ],
          ),
        ),
      );
      if (picked != null) onChanged(picked.value);
    },
  );
}

/// A whole number with − and + buttons.
class CountTile extends StatelessWidget {
  final String title;
  final String valueText;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  const CountTile({
    super.key,
    required this.title,
    required this.valueText,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => ListTile(
    dense: true,
    title: Text(title),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.remove),
          onPressed: value > min ? () => onChanged(value - 1) : null,
        ),
        Text(valueText),
        IconButton(
          icon: const Icon(Icons.add),
          onPressed: value < max ? () => onChanged(value + 1) : null,
        ),
      ],
    ),
  );
}

class _Pick {
  final Duration? value;

  const _Pick(this.value);
}

Future<Duration?> _askMinutes(BuildContext context, S s, Duration? current) {
  final field = TextEditingController(
    text: current == null ? '' : '${current.inMinutes}',
  );
  return showDialog<Duration>(
    context: context,
    builder: (context) => AlertDialog(
      content: TextField(
        controller: field,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(suffixText: s.t('minutes')),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(s.t('cancel')),
        ),
        FilledButton(
          onPressed: () {
            final m = int.tryParse(field.text);
            Navigator.pop(
              context,
              m == null || m <= 0 ? null : Duration(minutes: m),
            );
          },
          child: Text(s.t('ok')),
        ),
      ],
    ),
  );
}

String hm(int minutes) {
  final m = minutes == 1440 ? 0 : minutes;
  return '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
}

/// Sorts ranges and merges those that overlap or touch.
List<TimeRange> normalizeRanges(List<TimeRange> ranges) {
  final sorted = [...ranges]
    ..sort((a, b) => a.startMinute.compareTo(b.startMinute));
  final out = <TimeRange>[];
  for (final r in sorted) {
    if (out.isNotEmpty && r.startMinute <= out.last.endMinute) {
      final last = out.removeLast();
      out.add(
        TimeRange(
          last.startMinute,
          r.endMinute > last.endMinute ? r.endMinute : last.endMinute,
        ),
      );
    } else {
      out.add(r);
    }
  }
  return out;
}

/// Editable list of allowed time ranges; tap a range to change it.
class TimeRangesEditor extends StatelessWidget {
  final S s;
  final String? title;
  final List<TimeRange> ranges;
  final ValueChanged<List<TimeRange>> onChanged;

  const TimeRangesEditor({
    super.key,
    required this.s,
    required this.title,
    required this.ranges,
    required this.onChanged,
  });

  /// Asks for a start and an end; [current] pre-fills them when editing.
  Future<TimeRange?> _pick(BuildContext context, TimeRange? current) async {
    TimeOfDay at(int minutes) =>
        TimeOfDay(hour: (minutes ~/ 60) % 24, minute: minutes % 60);
    final start = await showTimePicker(
      context: context,
      initialTime: at(current?.startMinute ?? 8 * 60),
      helpText: s.t('from'),
    );
    if (start == null || !context.mounted) return null;
    final end = await showTimePicker(
      context: context,
      initialTime: at(current?.endMinute ?? 20 * 60),
      helpText: s.t('to'),
    );
    if (end == null) return null;
    final a = start.hour * 60 + start.minute;
    var b = end.hour * 60 + end.minute;
    // "00:00" as an end means midnight at the end of the day.
    if (b == 0) b = 1440;
    return b > a ? TimeRange(a, b) : null;
  }

  Future<void> _add(BuildContext context) async {
    final r = await _pick(context, null);
    if (r != null) onChanged(normalizeRanges([...ranges, r]));
  }

  Future<void> _edit(BuildContext context, TimeRange old) async {
    final r = await _pick(context, old);
    if (r != null) {
      onChanged(normalizeRanges([...ranges.where((x) => x != old), r]));
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (title != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(title!, style: Theme.of(context).textTheme.titleSmall),
        ),
      for (final r in ranges)
        ListTile(
          dense: true,
          title: Text('${hm(r.startMinute)} – ${hm(r.endMinute)}'),
          onTap: () => _edit(context, r),
          trailing: IconButton(
            icon: const Icon(Icons.close),
            tooltip: s.t('delete'),
            onPressed: () => onChanged([...ranges]..remove(r)),
          ),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          icon: const Icon(Icons.add),
          label: Text(s.t('addRange')),
          onPressed: () => _add(context),
        ),
      ),
    ],
  );
}

/// Asks to confirm a deletion.
/// Asks [question]; [action] names the button that goes ahead ("Delete"
/// by default).
Future<bool> confirm(
  BuildContext context,
  S s,
  String question, {
  String? action,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      content: Text(question),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(s.t('cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(action ?? s.t('delete')),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Asks for a duration of the parent's (or child's) choice, in hours and
/// minutes; `null` when cancelled.
Future<Duration?> askDuration(BuildContext context, S s) async {
  final hours = TextEditingController();
  final minutes = TextEditingController();
  final result = await showDialog<Duration>(
    context: context,
    builder: (context) {
      void done() {
        final h = int.tryParse(hours.text.trim()) ?? 0;
        final m = int.tryParse(minutes.text.trim()) ?? 0;
        final d = Duration(hours: h, minutes: m);
        if (d > Duration.zero && d <= const Duration(hours: 24)) {
          Navigator.pop(context, d);
        }
      }

      return AlertDialog(
        title: Text(s.t('customDuration')),
        content: Row(
          children: [
            Expanded(
              child: TextField(
                controller: hours,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(suffixText: s.t('hoursShort')),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: minutes,
                autofocus: true,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(suffixText: s.t('minutes')),
                onSubmitted: (_) => done(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(s.t('cancel')),
          ),
          FilledButton(onPressed: done, child: Text(s.t('ok'))),
        ],
      );
    },
  );
  hours.dispose();
  minutes.dispose();
  return result;
}

/// Duration chips from [presets] (minutes), plus "Other…" for any
/// duration; [value] is the one selected.
class DurationChoice extends StatelessWidget {
  final S s;
  final List<int> presets;
  final Duration value;
  final ValueChanged<Duration> onChanged;

  const DurationChoice({
    super.key,
    required this.s,
    required this.presets,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final custom =
        !presets.contains(value.inMinutes) || value.inSeconds % 60 != 0;
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (final m in presets)
          ChoiceChip(
            label: Text(s.duration(Duration(minutes: m))),
            selected: !custom && value.inMinutes == m,
            onSelected: (_) => onChanged(Duration(minutes: m)),
          ),
        ChoiceChip(
          avatar: const Icon(Icons.edit_outlined, size: 18),
          label: Text(custom ? s.duration(value) : s.t('customDurationShort')),
          selected: custom,
          onSelected: (_) async {
            final d = await askDuration(context, s);
            if (d != null) onChanged(d);
          },
        ),
      ],
    );
  }
}
