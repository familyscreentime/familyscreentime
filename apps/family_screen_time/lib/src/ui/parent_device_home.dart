/// Home of a parent's device: the family's children and devices, behind the
/// parent code. Nothing is limited on this device.
library;

import 'package:flutter/material.dart';
import 'package:screentime_sync/screentime_sync.dart'
    show PeerState, RelayState;

import '../controller.dart';
import '../sync/family_sync.dart';
import 'devices_screen.dart';
import 'parent_home.dart';
import 'pin_dialog.dart';

class ParentDeviceHome extends StatelessWidget {
  final AppController controller;

  const ParentDeviceHome({super.key, required this.controller});

  Future<void> _unlock(BuildContext context) async {
    if (!await askParentPin(context, controller)) return;
    controller.enterParentMode();
  }

  Future<void> _openChild(BuildContext context, String id) async {
    controller.selectChild(id);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ParentHome(controller: controller),
      ),
    );
  }

  /// The log, this device's last exchange with the relay, and what each
  /// device has not received yet.
  Future<(FamilySync?, RelayState?, Map<String, int>)> _summary(
    AppController c,
  ) async =>
      (await c.sync, (await c.relayStatus())?.$2, await c.pendingChanges());

  /// One linked device: its name (and child), and whether it is here now.
  Widget _deviceLine(
    BuildContext context,
    Map<String, Object?> device,
    PeerState? peer,
    DateTime? viaRelay,
    int pending,
    DateTime now,
  ) {
    final s = controller.s;
    final theme = Theme.of(context);
    final name = device['name'] as String? ?? '';
    final child = controller.family.child(device['childId'] as String?)?.name;
    final label = child == null || child == name ? name : '$name ($child)';
    final connected = peer?.connected ?? false;
    final last = [
      ?peer?.lastContact,
      ?viaRelay,
    ].fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);
    final status = connected
        ? s.t('deviceNow')
        : last == null
        ? s.t('deviceNeverSeen')
        : s.t('deviceLastContact', {'time': contactTime(s, last, now)});
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(
            Icons.circle,
            size: 10,
            color: connected ? Colors.green : theme.colorScheme.outlineVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              [
                '$label : $status',
                if (pending > 0) s.t('devicePending', {'n': '$pending'}),
              ].join(' · '),
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final c = controller;
      final s = c.s;
      final theme = Theme.of(context);
      return Scaffold(
        appBar: AppBar(
          title: const Text('Family Screen Time'),
          actions: [
            if (c.parentMode)
              IconButton(
                tooltip: s.t('lock'),
                icon: const Icon(Icons.lock),
                onPressed: c.leaveParentMode,
              ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(s.t('parentDeviceTitle'), style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            FutureBuilder(
              future: _summary(c),
              builder: (context, snapshot) {
                final data = snapshot.data;
                if (data == null) return const SizedBox.shrink();
                final (log, relay, pending) = data;
                final others = {
                  for (final e in (log?.devices ?? const {}).entries)
                    if (e.key != log?.deviceId) e.key: e.value,
                };
                if (others.isEmpty) {
                  return Text(
                    s.t('parentDeviceAlone'),
                    style: theme.textTheme.bodySmall,
                  );
                }
                final now = DateTime.now();
                final byId = {for (final p in c.lanPeers) p.deviceId: p};
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final e in others.entries)
                      _deviceLine(
                        context,
                        e.value,
                        byId[e.key],
                        relay?.seen[e.key],
                        pending[e.key] ?? 0,
                        now,
                      ),
                    const SizedBox(height: 4),
                    Text(
                      s.t('parentDeviceNowHint'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                    if (pending.values.any((n) => n > 0))
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          s.t('parentDevicePending', {
                            'devices': [
                              for (final e in pending.entries)
                                if (e.value > 0)
                                  others[e.key]?['name'] as String? ?? e.key,
                            ].join(', '),
                          }),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
            if (!c.parentMode)
              Center(
                child: FilledButton.icon(
                  icon: const Icon(Icons.lock_open),
                  label: Text(s.t('parentDeviceUnlock')),
                  onPressed: () => _unlock(context),
                ),
              )
            else ...[
              for (final child in c.family.children)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.child_care),
                    title: Text(child.name),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _openChild(context, child.id),
                  ),
                ),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.devices_outlined),
                  title: Text(s.t('devicesTitle')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => DevicesScreen(controller: c),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    },
  );
}
