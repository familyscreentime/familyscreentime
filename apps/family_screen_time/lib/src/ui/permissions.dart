/// List of the permissions the monitor needs, with a button for each.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../controller.dart';
import '../platform.dart';
import 'widgets.dart';

const _titles = {
  'accessibility': 'permAccessibility',
  'usageAccess': 'permUsageAccess',
  'overlay': 'permOverlay',
  'notifications': 'permNotifications',
  'battery': 'permBattery',
  'deviceAdmin': 'permDeviceAdmin',
};

const _texts = {
  'accessibility': 'permAccessibilityText',
  'usageAccess': 'permUsageAccessText',
  'overlay': 'permOverlayText',
  'notifications': 'permNotificationsText',
  'battery': 'permBatteryText',
  'deviceAdmin': 'permDeviceAdminText',
};

/// Explanations shown before a sensitive permission is turned on.
const _disclosures = {
  'accessibility': 'disclosureAccessibility',
  'usageAccess': 'disclosureUsageAccess',
};

class PermissionsView extends StatefulWidget {
  final AppController controller;

  const PermissionsView({super.key, required this.controller});

  @override
  State<PermissionsView> createState() => _PermissionsViewState();
}

class _PermissionsViewState extends State<PermissionsView>
    with WidgetsBindingObserver {
  Map<String, bool> _status = const {};
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    // Settings screens change the status while the app is in the background.
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final status = await widget.controller.platform.permissionStatus();
    if (mounted) setState(() => _status = status);
  }

  /// Says what a sensitive permission is used for, and asks for consent,
  /// before opening its settings (as Google Play requires).
  Future<void> _enable(BuildContext context, String kind) async {
    final c = widget.controller;
    final s = c.s;
    final text = _disclosures[kind];
    if (text != null) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(s.t(_titles[kind]!)),
          content: SingleChildScrollView(child: Text(s.t(text))),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(s.t('disclosureDecline')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(s.t('disclosureAccept')),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    await c.platform.openPermissionSettings(kind);
  }

  Future<void> _disableProtection(BuildContext context) async {
    final c = widget.controller;
    if (!await confirm(
      context,
      c.s,
      c.s.t('disableAdminConfirm'),
      action: c.s.t('disable'),
    )) {
      return;
    }
    await c.platform.disableDeviceAdmin();
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.controller.s;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final kind in permissionKinds)
          Card(
            child: ListTile(
              leading: Icon(
                _status[kind] == true
                    ? Icons.check_circle
                    : Icons.radio_button_unchecked,
                color: _status[kind] == true
                    ? Colors.green
                    : requiredPermissions.contains(kind)
                    ? Theme.of(context).colorScheme.error
                    : null,
              ),
              title: Text(s.t(_titles[kind]!)),
              subtitle: Text(s.t(_texts[kind]!)),
              isThreeLine: true,
              trailing: _status[kind] == true && kind == 'deviceAdmin'
                  // Turned off here, behind the parent code: the Android
                  // settings for it are closed to the child.
                  ? TextButton(
                      onPressed: () => _disableProtection(context),
                      child: Text(s.t('disable')),
                    )
                  : _status[kind] == true
                  ? Text(s.t('enabled'))
                  : FilledButton.tonal(
                      onPressed: () => _enable(context, kind),
                      child: Text(s.t('enable')),
                    ),
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.info_outline),
            label: Text(s.t('permAppDetails')),
            onPressed: () =>
                widget.controller.platform.openPermissionSettings('appDetails'),
          ),
        ),
      ],
    );
  }
}

/// True when a permission needed to enforce limits is missing.
Future<bool> missingRequiredPermission(AppController c) async {
  final status = await c.platform.permissionStatus();
  return requiredPermissions.any((k) => status[k] != true);
}
