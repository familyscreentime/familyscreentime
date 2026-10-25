/// The changes made in parent mode lately, and which linked device has
/// received each, and when.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:screentime_engine/screentime_engine.dart';
import 'package:screentime_sync/screentime_sync.dart';

import '../controller.dart';
import '../strings.dart';
import '../sync/family_entities.dart';
import '../sync/family_sync.dart';
import '../sync/receipts.dart';
import 'devices_screen.dart' show contactTime;

/// What [e] changed, in a few words.
String describeEvent(AppController c, SyncEvent e) {
  final s = c.s;
  final key = e.key;
  final id = key.contains('/') ? key.substring(key.indexOf('/') + 1) : key;
  final removed = e.type == EventType.delete;
  final added = e.type == EventType.put;
  String childPrefix(Object? childId) {
    if (c.family.children.length < 2) return '';
    final child = c.family.child(childId as String?);
    return child == null ? '' : '${child.name} : ';
  }

  if (key.startsWith(FamilyKeys.rule)) {
    final rule = [
      for (final r in c.family.state.rules)
        if (r.id == id) r,
    ].firstOrNull;
    final target = e.data['appTarget'] is Map
        ? appTargetFromJson(
            Map<String, Object?>.from(e.data['appTarget'] as Map),
          )
        : rule?.appTarget;
    final label = target == null ? '' : c.targetLabel(target);
    final who = childPrefix(e.data['childId'] ?? rule?.childId);
    // A limit the child set themselves, from their device.
    final own = e.signer == Signer.device;
    if (removed) {
      return '$who${s.t(own ? 'changeSelfLimitRemoved' : 'changeRuleRemoved')}';
    }
    final what = own
        ? (added ? 'changeSelfLimitAdded' : 'changeSelfLimitChanged')
        : (added ? 'changeRuleAdded' : 'changeRuleChanged');
    return '$who${s.t(what, {'target': label})}';
  }
  if (key.startsWith(FamilyKeys.group)) {
    final name = e.data['name'] as String? ?? c.family.groupNames[id] ?? '';
    if (removed) return s.t('changeGroupRemoved');
    return s.t(added ? 'changeGroupAdded' : 'changeGroupChanged', {
      'name': name,
    });
  }
  if (key.startsWith(FamilyKeys.bonus)) {
    final seconds = (e.data['amount'] as num?)?.toInt() ?? 0;
    return '${childPrefix(e.data['childId'])}${removed ? s.t('changeBonusRemoved') : s.t('changeBonus', {'minutes': '${seconds ~/ 60}'})}';
  }
  if (key.startsWith(FamilyKeys.temporaryBlock)) {
    return '${childPrefix(e.data['childId'])}${s.t(removed ? 'changeBlockRemoved' : 'changeBlock')}';
  }
  if (key.startsWith(FamilyKeys.familyBlock)) return s.t('changeFamilyBlock');
  if (key.startsWith(FamilyKeys.dayUnlock) ||
      key.startsWith(FamilyKeys.hoursUnlock)) {
    return '${childPrefix(e.data['childId'])}${s.t('changeUnlock')}';
  }
  if (key.startsWith(FamilyKeys.injected)) {
    return '${childPrefix(e.data['childId'])}${s.t('changeAway')}';
  }
  if (key.startsWith(FamilyKeys.child)) {
    final name = e.data['name'] as String? ?? c.family.child(id)?.name ?? '';
    return s.t('changeChild', {'name': name});
  }
  if (key.startsWith(FamilyKeys.profile)) return s.t('changePeriod');
  if (key.startsWith(FamilyKeys.appName)) return s.t('changeAppName');
  if (key == FamilyKeys.family) return s.t('changeSettings');
  if (key == SyncKeys.family) return s.t('changeCode');
  if (key == SyncKeys.server) return s.t('changeServer');
  if (key.startsWith(SyncKeys.devicePrefix)) return s.t('changeDevices');
  return s.t('changeOther');
}

/// The lines of [change]: each different one once, the first few.
List<String> describeChange(AppController c, Change change, {int max = 3}) {
  final lines = <String>[];
  for (final e in change.events) {
    final line = describeEvent(c, e);
    if (!lines.contains(line)) lines.add(line);
  }
  if (lines.length <= max) return lines;
  return [
    ...lines.take(max),
    c.s.t('changeMore', {'n': '${lines.length - max}'}),
  ];
}

class ChangesScreen extends StatefulWidget {
  final AppController controller;

  const ChangesScreen({super.key, required this.controller});

  @override
  State<ChangesScreen> createState() => _ChangesScreenState();
}

class _ChangesScreenState extends State<ChangesScreen> {
  FamilySync? _log;
  List<Change>? _changes;

  /// Receipts come in on their own.
  Timer? _refresh;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_load);
    _load();
    _refresh = Timer.periodic(const Duration(seconds: 5), (_) => _load());
  }

  @override
  void dispose() {
    _refresh?.cancel();
    widget.controller.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final log = await widget.controller.sync;
    final changes = log == null ? const <Change>[] : recentChanges(log);
    if (mounted) {
      setState(() {
        _log = log;
        _changes = changes;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final s = c.s;
    final changes = _changes;
    final log = _log;
    return Scaffold(
      appBar: AppBar(title: Text(s.t('changesTitle'))),
      body: changes == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(s.t('changesHint')),
                  const SizedBox(height: 8),
                  if (changes.isEmpty || log == null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(s.t('changesNone')),
                    )
                  else
                    for (final change in changes)
                      _changeCard(context, s, log, change),
                ],
              ),
            ),
    );
  }

  Widget _changeCard(BuildContext context, S s, FamilySync log, Change change) {
    final c = widget.controller;
    final theme = Theme.of(context);
    final now = DateTime.now();
    final devices = log.devices;
    String name(String id) => devices[id]?['name'] as String? ?? id;
    final targets = targetsOf(log, change);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final line in describeChange(c, change))
              Text(line, style: theme.textTheme.bodyLarge),
            const SizedBox(height: 4),
            Text(
              s.t('changeMadeOn', {
                'device': change.device == log.deviceId
                    ? s.t('devicesThis')
                    : name(change.device),
                'time': contactTime(s, change.at, now),
              }),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final id in targets)
                  _receipt(
                    context,
                    s,
                    name(id),
                    receivedBy(log, id, change),
                    now,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _receipt(
    BuildContext context,
    S s,
    String device,
    DateTime? at,
    DateTime now,
  ) {
    final theme = Theme.of(context);
    return Chip(
      visualDensity: VisualDensity.compact,
      avatar: Icon(
        at == null ? Icons.schedule : Icons.check_circle,
        size: 18,
        color: at == null ? theme.colorScheme.outline : Colors.green,
      ),
      label: Text(
        at == null
            ? s.t('changePending', {'device': device})
            : s.t('changeReceived', {
                'device': device,
                'time': contactTime(s, at, now),
              }),
      ),
    );
  }
}
