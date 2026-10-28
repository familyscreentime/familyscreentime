/// Parent's quick actions for today: extra time, lifting restrictions until
/// midnight, blocking now.
library;

import 'package:flutter/material.dart';
import 'package:screentime_engine/screentime_engine.dart';

import '../controller.dart';
import '../rule_status.dart';
import '../strings.dart';
import 'widgets.dart';

class QuickActions extends StatelessWidget {
  final AppController controller;

  /// Current time; for tests.
  final DateTime Function() clock;

  const QuickActions({
    super.key,
    required this.controller,
    this.clock = DateTime.now,
  });

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final c = controller;
      final s = c.s;
      final now = clock();
      final theme = Theme.of(context);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            title: Text(
              s.t('quickActions'),
              style: theme.textTheme.titleMedium,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.more_time),
            title: Text(s.t('bonusAction')),
            onTap: () => showBonusSheet(context, c, clock: clock),
          ),
          for (final b in c.activeBonuses(now))
            _activeLine(
              context,
              s.t('bonusActive', {
                'time': s.duration(b.amount),
                'label': _bonusLabel(b),
              }),
              s.t('bonusRemove'),
              () => c.removeBonus(b.id),
            ),
          ListTile(
            leading: const Icon(Icons.sports_esports_outlined),
            title: Text(s.t('awayAction')),
            subtitle: Text(s.t('awayHint')),
            onTap: () => _addAway(context),
          ),
          for (final u in c.injectedToday(now))
            _activeLine(
              context,
              s.t('awayActive', {
                'time': s.duration(u.length),
                'label': u.injectedTarget == const AppTarget.all()
                    ? s.t('allScreens')
                    : c.targetLabel(u.injectedTarget!),
              }),
              s.t('awayRemove'),
              () => c.removeAwayTime(u),
            ),
          // Outside the hours: open them now, until the end of the next
          // range (e.g. at 9:20 until 12:00 for hours from 10 to 12).
          for (final (rule, end) in c.openableEarly(now))
            ListTile(
              leading: const Icon(Icons.schedule),
              title: Text(
                s.t('openEarly', {
                  'label': c.labelOf(rule),
                  'time': s.time(end),
                }),
              ),
              onTap: () => c.openHoursEarly(rule, end, now: clock()),
            ),
          for (final u in c.hoursOpenedEarly(now))
            _activeLine(
              context,
              s.t('openEarlyActive', {
                'label': _ruleName(u.ruleId),
                'time': s.time(u.until),
              }),
              s.t('openEarlyClose'),
              () => c.closeHoursEarly(u.id, now: clock()),
            ),
          SwitchListTile(
            secondary: const Icon(Icons.lock_open),
            title: Text(s.t('unlockDay')),
            subtitle: Text(s.t('unlockDayHint')),
            value: c.dayUnlocked(now),
            onChanged: (on) => c.setDayUnlocked(on, now: clock()),
          ),
          ListTile(
            leading: const Icon(Icons.block),
            title: Text(s.t('blockAction')),
            onTap: () => showBlockSheet(context, c, clock: clock),
          ),
          for (final b in c.activeBlocks(now))
            _activeLine(
              context,
              blockLine(s, c, b),
              s.t('liftBlock'),
              () => c.liftBlock(b.id, now: clock()),
            ),
          ListTile(
            leading: const Icon(Icons.tune),
            title: Text(s.t('presetsTitle')),
            subtitle: Text(
              c.presets.map((m) => s.duration(Duration(minutes: m))).join(', '),
            ),
            onTap: () => editPresets(context, c),
          ),
        ],
      );
    },
  );

  String _ruleName(String id) {
    for (final r in controller.childRules) {
      if (r.id == id) return controller.labelOf(r);
    }
    return id;
  }

  String _bonusLabel(Bonus b) {
    final c = controller;
    for (final r in c.childRules) {
      if (r.id == b.ruleId) return c.labelOf(r);
    }
    return b.appTarget == null ? '' : c.targetLabel(b.appTarget!);
  }

  Widget _activeLine(
    BuildContext context,
    String text,
    String action,
    VoidCallback onPressed,
  ) => Padding(
    padding: const EdgeInsets.only(left: 72, right: 8),
    child: Row(
      children: [
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
        ),
        TextButton(onPressed: onPressed, child: Text(action)),
      ],
    ),
  );

  Future<void> _addAway(BuildContext context) async {
    final c = controller;
    final s = c.s;
    final targets = <AppTarget>[
      const AppTarget.all(),
      for (final id in c.childGroups.keys) AppTarget.group(id),
    ];
    // A group first (games on the console, videos on the TV): its time
    // counts in total screen time too.
    var target = targets.length > 1 ? targets[1] : targets.first;
    var amount = Duration(minutes: c.presets.first);
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => _Sheet(
          title: s.t('awayAction'),
          children: [
            Text(
              s.t('awayCountsAs'),
              style: Theme.of(context).textTheme.labelLarge,
            ),
            Wrap(
              spacing: 8,
              children: [
                for (final t in [...targets.skip(1), targets.first])
                  ChoiceChip(
                    label: Text(
                      t == const AppTarget.all()
                          ? s.t('awayTotalOnly')
                          : c.targetLabel(t),
                    ),
                    selected: t == target,
                    onSelected: (_) => setState(() => target = t),
                  ),
              ],
            ),
            Text(
              target == const AppTarget.all()
                  ? s.t('awayTotalOnlyHint')
                  : s.t('awayGroupHint', {'group': c.targetLabel(target)}),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Text(
              s.t('bonusAmount'),
              style: Theme.of(context).textTheme.labelLarge,
            ),
            DurationChoice(
              s: s,
              presets: c.presets,
              value: amount,
              onChanged: (d) => setState(() => amount = d),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(s.t('awayAdd', {'time': s.duration(amount)})),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      await c.addAwayTime(target, amount, now: clock());
    }
  }
}

/// Rules that extra time can raise for the child shown, the one closest
/// to running out first.
Future<List<Rule>> _bonusRules(AppController c, DateTime now) async {
  final rules = [
    // The child changes their own limits themselves.
    for (final r in c.activeChildRules)
      if (r.hasQuota && !r.setByChild) r,
  ];
  if (rules.length < 2) return rules;
  final state = c.family.state.copyWith(usage: await c.recentUsage());
  final engine = RuleEngine(c.family.config);
  final left = {
    for (final r in rules)
      r.id:
          ruleStatus(
            engine,
            state,
            r,
            childId: c.childId!,
            now: now,
          ).remaining ??
          const Duration(days: 365),
  };
  return rules..sort((a, b) => left[a.id]!.compareTo(left[b.id]!));
}

/// Gives the child shown extra time, on the limits the parent picks.
Future<void> showBonusSheet(
  BuildContext context,
  AppController c, {
  DateTime Function() clock = DateTime.now,
}) async {
  final s = c.s;
  final rules = await _bonusRules(c, clock());
  if (!context.mounted) return;
  if (rules.isEmpty) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(s.t('bonusNoRule'))));
    return;
  }
  // The limit closest to running out; others can be added (or it taken
  // away): extra game time need not raise total screen time.
  final chosen = {rules.first.id};
  var amount = Duration(minutes: c.presets.first);
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => _Sheet(
        title: s.t('bonusAction'),
        children: [
          Text(s.t('bonusFor'), style: Theme.of(context).textTheme.labelLarge),
          Wrap(
            spacing: 8,
            children: [
              for (final r in rules)
                FilterChip(
                  label: Text(c.labelOf(r)),
                  selected: chosen.contains(r.id),
                  onSelected: (on) => setState(
                    () => on ? chosen.add(r.id) : chosen.remove(r.id),
                  ),
                ),
            ],
          ),
          Text(
            s.t('bonusForHint'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Text(
            s.t('bonusAmount'),
            style: Theme.of(context).textTheme.labelLarge,
          ),
          DurationChoice(
            s: s,
            presets: c.presets,
            value: amount,
            onChanged: (d) => setState(() => amount = d),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: chosen.isEmpty
                ? null
                : () => Navigator.pop(context, true),
            child: Text(s.t('bonusGive', {'time': s.duration(amount)})),
          ),
        ],
      ),
    ),
  );
  if (ok == true) {
    for (final r in rules) {
      if (chosen.contains(r.id)) {
        await c.giveBonus(r, amount, now: clock());
      }
    }
  }
}

/// Blocks now, for the child shown or, with [children], for each of them
/// (then everything is blocked: groups belong to each child). The parent
/// may add a few words, shown to the child; those already written are
/// offered again. Whether a block was made.
Future<bool> showBlockSheet(
  BuildContext context,
  AppController c, {
  DateTime Function() clock = DateTime.now,
  List<String>? children,
}) async {
  final s = c.s;
  final targets = <AppTarget>[
    const AppTarget.all(),
    if (children == null)
      for (final id in c.childGroups.keys) AppTarget.group(id),
  ];
  var target = targets.first;
  // Minutes, or -1: until a chosen time, 0: until lifted.
  var length = c.presets.first;
  TimeOfDay? untilTime;
  final message = TextEditingController();
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final theme = Theme.of(context);
        return Padding(
          // Above the keyboard while the message is typed.
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: SingleChildScrollView(
            child: _Sheet(
              title: s.t(children == null ? 'blockAction' : 'lockAll'),
              children: [
                if (targets.length > 1) ...[
                  Text(s.t('blockWhat'), style: theme.textTheme.labelLarge),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final t in targets)
                        ChoiceChip(
                          label: Text(c.targetLabel(t)),
                          selected: t == target,
                          onSelected: (_) => setState(() => target = t),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                Text(s.t('blockHowLong'), style: theme.textTheme.labelLarge),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final m in c.presets)
                      ChoiceChip(
                        label: Text(s.duration(Duration(minutes: m))),
                        selected: m == length,
                        onSelected: (_) => setState(() => length = m),
                      ),
                    ChoiceChip(
                      avatar: const Icon(Icons.edit_outlined, size: 18),
                      label: Text(
                        length > 0 && !c.presets.contains(length)
                            ? s.duration(Duration(minutes: length))
                            : s.t('customDurationShort'),
                      ),
                      selected: length > 0 && !c.presets.contains(length),
                      onSelected: (_) async {
                        final d = await askDuration(context, s);
                        if (d != null) setState(() => length = d.inMinutes);
                      },
                    ),
                    ChoiceChip(
                      label: Text(
                        length == -1 && untilTime != null
                            ? s.t('blockUntilAt', {
                                'time':
                                    '${untilTime!.hour.toString().padLeft(2, '0')}:'
                                    '${untilTime!.minute.toString().padLeft(2, '0')}',
                              })
                            : s.t('blockUntilTime'),
                      ),
                      selected: length == -1,
                      onSelected: (_) async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay.fromDateTime(
                            clock().add(const Duration(hours: 1)),
                          ),
                        );
                        if (picked != null) {
                          setState(() {
                            untilTime = picked;
                            length = -1;
                          });
                        }
                      },
                    ),
                    ChoiceChip(
                      label: Text(s.t('blockUntilLifted')),
                      selected: length == 0,
                      onSelected: (_) => setState(() => length = 0),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: message,
                  maxLength: blockMessageMaxLength,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: s.t('blockMessage'),
                    hintText: s.t('blockMessageHint'),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                if (c.settings.blockMessages.isNotEmpty)
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final m in c.settings.blockMessages)
                        InputChip(
                          label: Text(m),
                          selected: message.text.trim() == m,
                          showCheckmark: false,
                          onPressed: () => setState(() => message.text = m),
                          deleteButtonTooltipMessage: s.t('blockMessageForget'),
                          onDeleted: () async {
                            await c.forgetBlockMessage(m);
                            setState(() {});
                          },
                        ),
                    ],
                  ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(s.t('blockGo')),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
  // Not disposed: the sheet may still be closing with the field in it.
  final text = message.text.trim();
  if (ok != true) return false;
  final now = clock();
  DateTime? until;
  if (length > 0) {
    until = now.add(Duration(minutes: length));
  } else if (length == -1 && untilTime != null) {
    until = DateTime(
      now.year,
      now.month,
      now.day,
      untilTime!.hour,
      untilTime!.minute,
    );
    // A time already past today means tomorrow.
    if (!until.isAfter(now)) {
      final tomorrow = addDays(dayOf(now), 1);
      until = tomorrow.add(
        Duration(hours: untilTime!.hour, minutes: untilTime!.minute),
      );
    }
  }
  await c.blockNow(target, until, now: now, children: children, message: text);
  if (text.isNotEmpty) await c.rememberBlockMessage(text);
  return true;
}

/// Longest message the parent may write with a block.
const blockMessageMaxLength = 60;

/// "Games: blocked until 15:30", until further notice, or "On a break
/// until 15:30" when the child chose it.
String blockLine(S s, AppController c, TemporaryBlock b) {
  final until = b.until;
  if (b.voluntary && until != null) {
    return s.t('pauseActive', {'time': s.time(until)});
  }
  final label = c.targetLabel(b.appTarget);
  return until == null
      ? s.t('blockActiveOpen', {'label': label})
      : s.t('blockActiveUntil', {'label': label, 'time': s.time(until)});
}

class _Sheet extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _Sheet({required this.title, required this.children});

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    ),
  );
}

/// Lets the parent choose the durations offered in one tap for the child.
Future<void> editPresets(BuildContext context, AppController c) async {
  final s = c.s;
  var minutes = c.presets;
  final field = TextEditingController();
  final result = await showDialog<List<int>>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        void add() {
          final m = int.tryParse(field.text.trim());
          if (m == null || m <= 0 || m > 24 * 60) return;
          setState(() => minutes = ({...minutes, m}.toList()..sort()));
          field.clear();
        }

        return AlertDialog(
          title: Text(s.t('presetsTitle')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                s.t('presetsHint', {'name': c.child?.name ?? ''}),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final m in minutes)
                    InputChip(
                      label: Text(s.duration(Duration(minutes: m))),
                      onDeleted: minutes.length <= 1
                          ? null
                          : () => setState(
                              () => minutes = [
                                for (final o in minutes)
                                  if (o != m) o,
                              ],
                            ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: field,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: s.t('presetsAdd'),
                        suffixText: s.t('minutes'),
                      ),
                      onSubmitted: (_) => add(),
                    ),
                  ),
                  IconButton(icon: const Icon(Icons.add), onPressed: add),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(s.t('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, minutes),
              child: Text(s.t('save')),
            ),
          ],
        );
      },
    ),
  );
  field.dispose();
  if (result != null) await c.setPresets(result);
}
