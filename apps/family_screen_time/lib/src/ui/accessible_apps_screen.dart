/// Apps the child can always use, never limited by time: the phone at any
/// hour, messages only within the hours…
library;

import 'package:flutter/material.dart';

import '../controller.dart';
import 'limit_screen.dart';

class AccessibleAppsScreen extends StatefulWidget {
  final AppController controller;

  const AccessibleAppsScreen({super.key, required this.controller});

  @override
  State<AccessibleAppsScreen> createState() => _AccessibleAppsScreenState();
}

class _AccessibleAppsScreenState extends State<AccessibleAppsScreen> {
  AppController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    c.loadLabels({
      ...c.family.config.alwaysAllowed,
      ...c.family.config.allowedInHours,
    });
  }

  Future<void> _add() async {
    final app = await pickApp(context, c);
    if (app == null) return;
    await c.loadLabels([app]);
    await c.setAccessible(app, anyTime: false);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      final s = c.s;
      final config = c.family.config;
      String name(String app) =>
          c.appName(app, androidLabel: c.androidLabels[app]);
      final apps = [
        ...config.alwaysAllowed,
        ...config.allowedInHours,
      ]..sort((a, b) => name(a).toLowerCase().compareTo(name(b).toLowerCase()));
      return Scaffold(
        appBar: AppBar(title: Text(s.t('accessibleTitle'))),
        floatingActionButton: FloatingActionButton.extended(
          icon: const Icon(Icons.add),
          label: Text(s.t('accessibleAdd')),
          onPressed: _add,
        ),
        body: ListView(
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(s.t('accessibleHint')),
            ),
            for (final app in apps)
              ListTile(
                title: Text(name(app)),
                subtitle: Text(
                  config.alwaysAllowed.contains(app)
                      ? s.t('accessibleAnyTime')
                      : s.t('accessibleInHours'),
                ),
                leading: Switch(
                  value: config.alwaysAllowed.contains(app),
                  onChanged: (v) => c.setAccessible(app, anyTime: v),
                ),
                trailing: IconButton(
                  tooltip: s.t('delete'),
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => c.removeAccessible(app),
                ),
              ),
          ],
        ),
      );
    },
  );
}
