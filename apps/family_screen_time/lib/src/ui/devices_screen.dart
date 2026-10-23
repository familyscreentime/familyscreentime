/// The family's devices (parent mode): their last contact, removing one,
/// and adding a new one on the local network.
library;

import 'package:flutter/material.dart';
import 'package:screentime_engine/screentime_engine.dart' show dayOf;
import 'package:screentime_sync/screentime_sync.dart';

import '../controller.dart';
import '../strings.dart';
import '../sync/bonsoir_directory.dart';
import '../sync/family_sync.dart';
import 'widgets.dart';

/// "Today 14:05", or the date and time for an older contact.
String contactTime(S s, DateTime t, DateTime now) =>
    dayOf(t) == dayOf(now) ? s.time(t) : '${s.date(t)} ${s.time(t)}';

class DevicesScreen extends StatefulWidget {
  final AppController controller;

  /// Finds devices on the network (DNS-SD by default; a fake in tests).
  final LanDirectory Function() directory;

  const DevicesScreen({
    super.key,
    required this.controller,
    this.directory = BonsoirDirectory.new,
  });

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  FamilySync? _log;
  Map<String, PeerState> _peers = const {};
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final log = await widget.controller.sync;
    final peers = log == null ? const <String, PeerState>{} : await log.peers();
    if (!mounted) return;
    setState(() {
      _log = log;
      _peers = peers;
      _loaded = true;
    });
  }

  Future<void> _remove(String id, String name) async {
    final c = widget.controller;
    if (!await confirm(
      context,
      c.s,
      c.s.t('deviceRemoveConfirm', {'name': name}),
      action: c.s.t('deviceRemove'),
    )) {
      return;
    }
    await c.removeDevice(id);
    await _load();
  }

  Future<void> _add() async {
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AddDeviceScreen(
          controller: widget.controller,
          directory: widget.directory,
        ),
      ),
    );
    if (added == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final s = c.s;
    final log = _log;
    final now = DateTime.now();
    return Scaffold(
      appBar: AppBar(title: Text(s.t('devicesTitle'))),
      floatingActionButton: log == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _add,
              icon: const Icon(Icons.add),
              label: Text(s.t('addDevice')),
            ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                Text(s.t(log == null ? 'devicesNoFamily' : 'devicesHint')),
                const SizedBox(height: 8),
                if (log != null)
                  for (final e in log.devices.entries)
                    _deviceTile(context, s, log, e.key, e.value, now),
              ],
            ),
    );
  }

  Widget _deviceTile(
    BuildContext context,
    S s,
    FamilySync log,
    String id,
    Map<String, Object?> d,
    DateTime now,
  ) {
    final c = widget.controller;
    final name = d['name'] as String? ?? id;
    final child = c.family.child(d['childId'] as String?);
    final here = id == log.deviceId;
    final peer = _peers[id];
    final status = here
        ? s.t('devicesThis')
        : peer == null
        ? s.t('deviceNeverSeen')
        : peer.connected
        ? s.t('deviceConnected')
        : s.t('deviceLastContact', {
            'time': contactTime(s, peer.lastContact, now),
          });
    return Card(
      child: ListTile(
        leading: Icon(
          d['role'] == 'parent' ? Icons.phone_android : Icons.tablet_android,
        ),
        title: Text(name),
        subtitle: Text(
          [
            if (child != null)
              s.t('deviceOfChild', {'child': child.name})
            else if (d['role'] == 'parent')
              s.t('deviceParent'),
            status,
          ].join(' · '),
        ),
        trailing: here
            ? null
            : IconButton(
                tooltip: s.t('deviceRemove'),
                icon: const Icon(Icons.link_off),
                onPressed: () => _remove(id, name),
              ),
      ),
    );
  }
}

/// Waits for a new device on the network, then checks the code with the
/// parent and registers it.
class AddDeviceScreen extends StatefulWidget {
  final AppController controller;
  final LanDirectory Function() directory;

  const AddDeviceScreen({
    super.key,
    required this.controller,
    this.directory = BonsoirDirectory.new,
  });

  @override
  State<AddDeviceScreen> createState() => _AddDeviceScreenState();
}

class _AddDeviceScreenState extends State<AddDeviceScreen> {
  PairingHost? _host;
  String? _error;
  String _name = '';

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final c = widget.controller;
    final log = await c.sync;
    final key = await c.parentKey;
    if (log == null || key == null) {
      if (mounted) setState(() => _error = c.s.t('pairNoKey'));
      return;
    }
    _name = log.registration?['name'] as String? ?? '';
    final host = _host = PairingHost(
      node: log.node,
      parentKey: key,
      directory: widget.directory(),
      name: _name,
      confirm: _confirm,
      onWelcomed: _welcomed,
    );
    try {
      await host.start();
      if (mounted) setState(() {});
    } on Object {
      if (mounted) setState(() => _error = c.s.t('pairNetworkError'));
    }
  }

  Future<Map<String, Object?>?> _confirm(
    String code,
    Map<String, Object?> info,
  ) async {
    if (!mounted) return null;
    widget.controller.touch();
    return showDialog<Map<String, Object?>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PairDialog(
        controller: widget.controller,
        code: code,
        name: info['name'] as String? ?? '',
      ),
    );
  }

  Future<void> _welcomed(String id) async {
    await widget.controller.deviceWelcomed();
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  void dispose() {
    _host?.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.controller.s;
    return Scaffold(
      appBar: AppBar(title: Text(s.t('addDevice'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            )
          else ...[
            Text(s.t('addDeviceText', {'name': _name})),
            const SizedBox(height: 24),
            Row(
              children: [
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(s.t('addDeviceWaiting'))),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// The code to compare, the new device's name and its child.
class _PairDialog extends StatefulWidget {
  final AppController controller;
  final String code;
  final String name;

  const _PairDialog({
    required this.controller,
    required this.code,
    required this.name,
  });

  @override
  State<_PairDialog> createState() => _PairDialogState();
}

class _PairDialogState extends State<_PairDialog> {
  late final _name = TextEditingController(text: widget.name);
  String? _childId;

  @override
  void initState() {
    super.initState();
    final children = widget.controller.family.children;
    if (children.length == 1) _childId = children.single.id;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final s = c.s;
    final theme = Theme.of(context);
    final code = widget.code;
    return AlertDialog(
      title: Text(s.t('pairCodeTitle')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.t('pairCodeHost')),
            const SizedBox(height: 12),
            Center(
              child: Text(
                '${code.substring(0, 3)} ${code.substring(3)}',
                style: theme.textTheme.displaySmall?.copyWith(
                  letterSpacing: 4,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              decoration: InputDecoration(labelText: s.t('pairDeviceName')),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _childId,
              decoration: InputDecoration(labelText: s.t('pairChild')),
              items: [
                for (final child in c.family.children)
                  DropdownMenuItem(value: child.id, child: Text(child.name)),
              ],
              onChanged: (v) => setState(() => _childId = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(s.t('cancel')),
        ),
        FilledButton(
          onPressed: _childId == null || _name.text.trim().isEmpty
              ? null
              : () => Navigator.pop(context, {
                  'name': _name.text.trim(),
                  'role': 'child',
                  'childId': _childId,
                }),
          child: Text(s.t('pairConfirm')),
        ),
      ],
    );
  }
}
