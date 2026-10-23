/// Home of a parent's device: the family's children and devices, behind the
/// parent code. Nothing is limited on this device.
library;

import 'package:flutter/material.dart';

import '../controller.dart';
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

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final c = controller;
      final s = c.s;
      final theme = Theme.of(context);
      final peers = c.lanPeers.where((p) => p.connected).toList();
      final log = c.sync;
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
              future: log,
              builder: (context, snapshot) {
                final devices = snapshot.data?.devices ?? const {};
                final names = [
                  for (final p in peers)
                    devices[p.deviceId]?['name'] ?? p.deviceId,
                ];
                return Text(
                  names.isEmpty
                      ? s.t('parentDeviceAlone')
                      : s.t('parentDeviceConnected', {
                          'devices': names.join(', '),
                        }),
                  style: theme.textTheme.bodySmall,
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
