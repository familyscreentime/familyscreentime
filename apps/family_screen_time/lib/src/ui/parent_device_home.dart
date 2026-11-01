/// Home of a parent's device. Locked: the app's name and the unlock button,
/// nothing else. Unlocked: each child with their time today (total screen
/// time, and the groups of apps with a time limit; in red with no time
/// left), extra time and locking or unlocking in one tap, then the linked
/// devices and the family's settings. Nothing is limited on this device.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../children_glance.dart';
import '../controller.dart';
import '../ordering.dart';
import '../store.dart';
import 'devices_screen.dart';
import 'family_settings.dart';
import 'parent_home.dart';
import 'pin_dialog.dart';
import 'quick_actions.dart';

class ParentDeviceHome extends StatelessWidget {
  final AppController controller;

  /// Current time; for tests.
  final DateTime Function() clock;

  const ParentDeviceHome({
    super.key,
    required this.controller,
    this.clock = DateTime.now,
  });

  Future<void> _unlock(BuildContext context) async {
    if (!await askParentPin(context, controller)) return;
    controller.enterParentMode();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final c = controller;
      final s = c.s;
      final theme = Theme.of(context);
      if (!c.parentMode) {
        return Scaffold(
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Family Screen Time',
                      style: theme.textTheme.headlineMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    FilledButton.icon(
                      icon: const Icon(Icons.lock_open),
                      label: Text(s.t('parentDeviceUnlock')),
                      onPressed: () => _unlock(context),
                    ),
                    if (c.demoCode != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        s.t('demoCode', {'code': c.demoCode!}),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      }
      return Scaffold(
        appBar: AppBar(
          title: const Text('Family Screen Time'),
          actions: [
            IconButton(
              tooltip: s.t('lock'),
              icon: const Icon(Icons.lock),
              onPressed: c.leaveParentMode,
            ),
          ],
        ),
        body: _Children(controller: c, clock: clock),
      );
    },
  );
}

/// The children, whether each is locked out now, and the actions that fit;
/// then the linked devices and the family's settings.
class _Children extends StatefulWidget {
  final AppController controller;
  final DateTime Function() clock;

  const _Children({required this.controller, required this.clock});

  @override
  State<_Children> createState() => _ChildrenState();
}

class _ChildrenState extends State<_Children> {
  /// The children who can use none of their devices; `null` until known.
  Set<String>? _locked;

  /// Each child's time today, by child; empty until known.
  Map<String, ChildTimes> _times = const {};

  /// Locks change on their own (time used up, hours over).
  Timer? _refresh;

  AppController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    _load();
    _refresh = Timer.periodic(const Duration(minutes: 1), (_) => _load());
    c.addListener(_load);
  }

  @override
  void dispose() {
    _refresh?.cancel();
    c.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final now = widget.clock();
    final locked = await c.lockedChildren(now);
    final times = await c.childrenTimes(now);
    if (mounted) {
      setState(() {
        _locked = locked;
        _times = times;
      });
    }
  }

  Future<void> _open(Widget page) async {
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => page));
    await _load();
  }

  Future<void> _openChild(String id) async {
    c.selectChild(id);
    await _open(ParentHome(controller: c));
  }

  Future<void> _giveTime(Child child) async {
    c.selectChild(child.id);
    await showBonusSheet(context, c, clock: widget.clock);
  }

  Future<void> _blockChild(Child child) async {
    c.selectChild(child.id);
    await showBlockSheet(context, c, clock: widget.clock);
  }

  /// Unlocks [child], and says until when.
  Future<void> _unlockChild(Child child) async {
    final until = await c.unlockChild(child.id, now: widget.clock());
    if (!mounted) return;
    _say(_unlockedText(child, until));
  }

  String _unlockedText(Child child, DateTime? until) {
    final s = c.s;
    final now = widget.clock();
    if (until == null) return s.t('childUnlocked', {'name': child.name});
    final midnight =
        !until.isAfter(now) || (until.hour == 0 && until.minute == 0);
    return midnight
        ? s.t('childUnlockedMidnight', {'name': child.name})
        : s.t('childUnlockedUntil', {
            'name': child.name,
            'time': s.time(until),
          });
  }

  void _say(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _lockAll(List<Child> children) async {
    await showBlockSheet(
      context,
      c,
      clock: widget.clock,
      children: [for (final child in children) child.id],
    );
  }

  Future<void> _unlockAll(List<Child> children) async {
    for (final child in children) {
      await c.unlockChild(child.id, now: widget.clock());
    }
    if (mounted) _say(c.s.t('allUnlocked'));
  }

  Widget _childCard(Child child, bool? locked) {
    final s = c.s;
    final theme = Theme.of(context);
    final times = _times[child.id];
    Color? color(TimeToday t) => t.over ? theme.colorScheme.error : null;
    final small = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openChild(child.id),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            child.name,
                            style: theme.textTheme.titleMedium,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (times != null) ...[
                          const SizedBox(width: 12),
                          // Total screen time today, red with no time left.
                          Text(
                            s.duration(times.total.used),
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: color(times.total),
                              fontWeight: times.total.over
                                  ? FontWeight.bold
                                  : null,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
              // The groups of apps with a time limit, in smaller type.
              if (times != null && times.groups.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2, right: 32),
                  child: Text.rich(
                    TextSpan(
                      style: small,
                      children: [
                        for (final (i, e) in times.groups.entries.indexed) ...[
                          if (i > 0) const TextSpan(text: ' · '),
                          TextSpan(
                            text:
                                '${c.groupName(e.key)} '
                                '${s.duration(e.value.used)}',
                            style: e.value.over
                                ? TextStyle(color: theme.colorScheme.error)
                                : null,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 4),
              Row(
                children: [
                  IconButton.filledTonal(
                    tooltip: s.t('bonusAction'),
                    icon: const Icon(Icons.more_time),
                    onPressed: () => _giveTime(child),
                  ),
                  const SizedBox(width: 8),
                  // Its state as the action that changes it.
                  if (locked == true)
                    IconButton.filledTonal(
                      tooltip: s.t('unlockChild'),
                      icon: const Icon(Icons.lock_open),
                      onPressed: () => _unlockChild(child),
                    )
                  else if (locked == false)
                    IconButton.filledTonal(
                      tooltip: s.t('blockAction'),
                      icon: const Icon(Icons.lock),
                      onPressed: () => _blockChild(child),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = c.s;
    final locked = _locked;
    final children = childrenByName(c.family.children);
    final allLocked =
        locked != null &&
        children.isNotEmpty &&
        children.every((child) => locked.contains(child.id));
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final child in children)
          _childCard(child, locked?.contains(child.id)),
        if (children.length > 1 && locked != null) ...[
          const SizedBox(height: 8),
          Center(
            child: allLocked
                ? OutlinedButton.icon(
                    icon: const Icon(Icons.lock_open),
                    label: Text(s.t('unlockAll')),
                    onPressed: () => _unlockAll(children),
                  )
                : OutlinedButton.icon(
                    icon: const Icon(Icons.lock),
                    label: Text(s.t('lockAll')),
                    onPressed: () => _lockAll(children),
                  ),
          ),
        ],
        const SizedBox(height: 16),
        Card(
          child: ListTile(
            leading: const Icon(Icons.devices_outlined),
            title: Text(s.t('devicesTitle')),
            subtitle: Text(s.t('devicesSubtitle')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _open(DevicesScreen(controller: c)),
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.family_restroom),
            title: Text(s.t('familySettingsTitle')),
            subtitle: Text(s.t('familySettingsSubtitle')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _open(FamilySettingsScreen(controller: c)),
          ),
        ),
      ],
    );
  }
}
