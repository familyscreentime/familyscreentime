/// The family's devices (parent mode): their last contact, removing one,
/// and adding a new one on the local network.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:screentime_engine/screentime_engine.dart' show dayOf;
import 'package:screentime_sync/screentime_sync.dart';

import '../controller.dart';
import '../store.dart';
import '../strings.dart';
import '../sync/bonsoir_directory.dart';
import '../sync/family_sync.dart';
import 'changes_screen.dart';
import 'join_screen.dart';
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
  bool _busy = false;

  /// The state shown changes on its own (contact, sync, receipts).
  Timer? _refresh;

  @override
  void initState() {
    super.initState();
    _load();
    // What it says of the relay is fresh, a few seconds later.
    if (widget.controller.settings.parentDevice) {
      unawaited(widget.controller.syncRelayNow());
    }
    _refresh = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!_busy) _load();
    });
    widget.controller.addListener(_onChange);
  }

  void _onChange() {
    if (!_busy) _load();
  }

  @override
  void dispose() {
    _refresh?.cancel();
    widget.controller.removeListener(_onChange);
    super.dispose();
  }

  /// The relay server's address and this device's last exchange with it.
  (String, RelayState)? _relay;
  bool _relayKey = true;

  /// Recent changes each device has not received yet.
  Map<String, int> _pending = const {};

  Future<void> _load() async {
    final c = widget.controller;
    final log = await c.sync;
    final peers = log == null ? const <String, PeerState>{} : await log.peers();
    final relay = await c.relayStatus();
    final relayKey = await c.hasRelayKey;
    final pending = await c.pendingChanges();
    if (!mounted) return;
    setState(() {
      _pending = pending;
      _log = log;
      _peers = peers;
      _relay = relay;
      _relayKey = relayKey;
      _loaded = true;
    });
  }

  Future<void> _setUpRelay() async {
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => _RelayDialog(controller: widget.controller),
    );
    if (done == true) await _load();
  }

  Future<void> _removeRelay() async {
    final c = widget.controller;
    if (!await confirm(
      context,
      c.s,
      c.s.t('relayRemoveConfirm'),
      action: c.s.t('relayRemove'),
    )) {
      return;
    }
    await c.removeRelay();
    await _load();
  }

  Future<void> _syncRelay() async {
    await widget.controller.syncRelayNow();
    // The monitor syncs on a child's device: its result a moment later.
    await Future<void>.delayed(const Duration(seconds: 3));
    if (mounted) await _load();
  }

  Widget _relayCard(BuildContext context, S s) {
    final relay = _relay;
    final theme = Theme.of(context);
    if (relay == null) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.cloud_outlined),
          title: Text(s.t('relayTitle')),
          subtitle: Text(s.t('relayOffText')),
          isThreeLine: true,
          trailing: FilledButton.tonal(
            onPressed: _setUpRelay,
            child: Text(s.t('relaySetUp')),
          ),
        ),
      );
    }
    final (url, state) = relay;
    final error = state.lastError;
    final now = DateTime.now();
    final lastOk = state.lastOk;
    final status = !_relayKey
        ? s.t('relayWaitingKey')
        : error != null
        ? [
            relayErrorText(s, error),
            // Not alarming when it worked a moment ago.
            if (lastOk != null)
              s.t('relayLastSync', {'time': contactTime(s, lastOk, now)}),
          ].join('\n')
        : state.lastOk == null
        ? s.t('relayFirstSync')
        : s.t('relayLastSync', {'time': contactTime(s, state.lastOk!, now)});
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: Icon(
              error == null ? Icons.cloud_done_outlined : Icons.cloud_off,
              color: error == null ? null : theme.colorScheme.error,
            ),
            title: Text(s.t('relayAt', {'host': Uri.parse(url).host})),
            subtitle: Text(
              status,
              style: error == null
                  ? null
                  : TextStyle(color: theme.colorScheme.error),
            ),
          ),
          OverflowBar(
            alignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _removeRelay,
                child: Text(s.t('relayRemove')),
              ),
              TextButton(
                onPressed: _relayKey ? _syncRelay : null,
                child: Text(s.t('relaySyncNow')),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Linked to at least one other device.
  bool get _linked => (_log?.devices.length ?? 0) > 1;

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

  Future<void> _rename(String id, String name) async {
    final c = widget.controller;
    final s = c.s;
    final field = TextEditingController(text: name);
    final next = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.t('deviceRename')),
        content: TextField(
          controller: field,
          autofocus: true,
          decoration: InputDecoration(labelText: s.t('pairDeviceName')),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(s.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, field.text),
            child: Text(s.t('save')),
          ),
        ],
      ),
    );
    field.dispose();
    final trimmed = next?.trim() ?? '';
    if (trimmed.isEmpty || trimmed == name) return;
    await c.renameDevice(id, trimmed);
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

  Future<void> _join() async {
    final joined = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => JoinScreen(
          controller: widget.controller,
          directory: widget.directory,
        ),
      ),
    );
    if (joined == true) await _load();
  }

  Future<void> _detach() async {
    final c = widget.controller;
    final child = c.family.child(c.settings.childId)?.name ?? '';
    if (!await confirm(
      context,
      c.s,
      c.s.t('detachConfirm', {'child': child}),
      action: c.s.t('detachAction'),
    )) {
      return;
    }
    setState(() => _busy = true);
    await c.detach();
    if (!mounted) return;
    setState(() => _busy = false);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final s = c.s;
    final log = _log;
    final now = DateTime.now();
    return Scaffold(
      appBar: AppBar(title: Text(s.t('devicesTitle'))),
      floatingActionButton: !_loaded || !_linked
          ? null
          : FloatingActionButton.extended(
              onPressed: _add,
              icon: const Icon(Icons.add_link),
              label: Text(s.t('addDevice')),
            ),
      body: !_loaded || _busy
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                if (!_linked) ...[
                  Text(s.t('devicesAlone')),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _add,
                    icon: const Icon(Icons.add_link),
                    label: Text(s.t('addDevice')),
                  ),
                  const SizedBox(height: 8),
                  if (!c.settings.parentDevice)
                    OutlinedButton.icon(
                      onPressed: _join,
                      icon: const Icon(Icons.login),
                      label: Text(s.t('joinDevices')),
                    ),
                ] else ...[
                  Text(s.t('devicesHint')),
                  const SizedBox(height: 8),
                  for (final e in log!.devices.entries)
                    _deviceTile(context, s, log, e.key, e.value, now),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.fact_check_outlined),
                      title: Text(s.t('changesTitle')),
                      subtitle: Text(s.t('changesSubtitle')),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => ChangesScreen(controller: c),
                          ),
                        );
                        await _load();
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  _relayCard(context, s),
                  if (!c.settings.parentDevice) ...[
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _detach,
                        icon: const Icon(Icons.link_off),
                        label: Text(s.t('detach')),
                      ),
                    ),
                  ],
                ],
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
    // The last contact on the network or through the relay.
    final viaRelay = _relay?.$2.seen[id];
    final last = [
      ?peer?.lastContact,
      ?viaRelay,
    ].fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);
    final status = here
        ? s.t('devicesThis')
        : peer?.connected ?? false
        ? s.t('deviceConnected')
        : last == null
        ? s.t('deviceNeverSeen')
        : s.t('deviceLastContact', {'time': contactTime(s, last, now)});
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
            if ((_pending[id] ?? 0) > 0)
              s.t('devicePending', {'n': '${_pending[id]}'}),
          ].join(' · '),
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (v) =>
              v == 'rename' ? _rename(id, name) : _remove(id, name),
          itemBuilder: (_) => [
            PopupMenuItem(value: 'rename', child: Text(s.t('deviceRename'))),
            if (!here)
              PopupMenuItem(value: 'remove', child: Text(s.t('deviceRemove'))),
          ],
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
    // A device working on its own starts sharing now.
    final linking = await c.startLinking();
    if (linking == null) {
      if (mounted) setState(() => _error = c.s.t('pairNoKey'));
      return;
    }
    final (log, key) = linking;
    _linkLog = log;
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

  /// The log the other device is welcomed into.
  FamilySync? _linkLog;

  Future<Map<String, Object?>?> _confirm(
    String code,
    Map<String, Object?> info,
  ) async {
    if (!mounted) return null;
    final c = widget.controller;
    c.touch();
    final child = info['child'];
    final registration = await showDialog<Map<String, Object?>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PairDialog(
        controller: c,
        code: code,
        name: info['name'] as String? ?? '',
        child: child is Map ? Map<String, Object?>.from(child) : null,
        // Every child, also from a child's device.
        children: _linkLog?.allChildren() ?? c.family.children,
      ),
    );
    if (registration == null) return null;
    // A child the linked devices did not know: they all learn of them.
    final newName = registration.remove(_newChildName) as String?;
    if (newName != null) {
      await c.updateFamily(
        c.family.copyWith(
          children: [
            ...c.family.children,
            Child(id: registration['childId'] as String, name: newName),
          ],
        ),
      );
    }
    return registration;
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

/// Name of a new child in what the dialog returns (not registered).
const _newChildName = 'newChildName';

/// Dropdown value for a new child.
const _newChild = '';

/// The code to compare, the other device's name and its child: one the
/// linked devices know, or a new one (the other device's own, if it was
/// set up already).
class _PairDialog extends StatefulWidget {
  final AppController controller;
  final String code;
  final String name;

  /// The other device's child, if it was set up already: `id`, `name`.
  final Map<String, Object?>? child;

  /// The children the device may be given to.
  final List<Child> children;

  const _PairDialog({
    required this.children,
    required this.controller,
    required this.code,
    required this.name,
    this.child,
  });

  @override
  State<_PairDialog> createState() => _PairDialogState();
}

class _PairDialogState extends State<_PairDialog> {
  late final _name = TextEditingController(text: widget.name);
  late final _childName = TextEditingController(
    text: widget.child?['name'] as String? ?? '',
  );
  String? _childId;

  /// A parent's device rather than a child's.
  bool _parent = false;

  @override
  void initState() {
    super.initState();
    final children = widget.children;
    final theirs = (widget.child?['name'] as String? ?? '')
        .trim()
        .toLowerCase();
    final same = children
        .where((c) => c.name.trim().toLowerCase() == theirs)
        .firstOrNull;
    if (same != null) {
      _childId = same.id;
    } else if (widget.child != null) {
      _childId = _newChild;
    } else if (children.length == 1) {
      _childId = children.single.id;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _childName.dispose();
    super.dispose();
  }

  Map<String, Object?> _registration() {
    final reg = <String, Object?>{
      'name': _name.text.trim(),
      'role': _parent ? 'parent' : 'child',
    };
    if (_parent) return reg;
    if (_childId != _newChild) return {...reg, 'childId': _childId};
    // The other device's child keeps its id, unless it is taken.
    final known = {for (final c in widget.children) c.id};
    final theirs = widget.child?['id'] as String?;
    return {
      ...reg,
      'childId': theirs != null && !known.contains(theirs) ? theirs : newId(),
      'newChild': true,
      _newChildName: _childName.text.trim(),
    };
  }

  bool get _complete =>
      _name.text.trim().isNotEmpty &&
      (_parent ||
          (_childId != null &&
              (_childId != _newChild || _childName.text.trim().isNotEmpty)));

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
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(value: false, label: Text(s.t('pairRoleChild'))),
                ButtonSegment(value: true, label: Text(s.t('pairRoleParent'))),
              ],
              selected: {_parent},
              onSelectionChanged: (v) => setState(() => _parent = v.first),
            ),
            if (!_parent) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _childId,
                decoration: InputDecoration(labelText: s.t('pairChild')),
                items: [
                  for (final child in widget.children)
                    DropdownMenuItem(value: child.id, child: Text(child.name)),
                  DropdownMenuItem(
                    value: _newChild,
                    child: Text(s.t('pairNewChild')),
                  ),
                ],
                onChanged: (v) => setState(() => _childId = v),
              ),
              if (_childId == _newChild) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _childName,
                  decoration: InputDecoration(labelText: s.t('pairChildName')),
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(s.t('cancel')),
        ),
        FilledButton(
          onPressed: _complete
              ? () => Navigator.pop(context, _registration())
              : null,
          child: Text(s.t('pairConfirm')),
        ),
      ],
    );
  }
}

/// What the relay's error [code] means for the parent.
String relayErrorText(S s, String code) {
  const known = {
    'unreachable',
    'not_a_relay',
    'not_installed',
    'bad_address',
    'bad_invitation',
    'invitation_needed',
    'unknown_device',
    'no_family',
    'clock',
    'no_key',
  };
  return known.contains(code)
      ? s.t('relayError_$code')
      : s.t('relayErrorOther', {'code': code});
}

/// The relay server's address and, the first time, an invitation.
class _RelayDialog extends StatefulWidget {
  final AppController controller;

  const _RelayDialog({required this.controller});

  @override
  State<_RelayDialog> createState() => _RelayDialogState();
}

class _RelayDialogState extends State<_RelayDialog> {
  final _address = TextEditingController();
  final _invitation = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _address.dispose();
    _invitation.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final c = widget.controller;
    c.touch();
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await c.setUpRelay(_address.text, _invitation.text);
    if (!mounted) return;
    if (error == null) {
      Navigator.pop(context, true);
      return;
    }
    setState(() {
      _busy = false;
      _error = relayErrorText(c.s, error);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.controller.s;
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(s.t('relayTitle')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.t('relayDialogText')),
            const SizedBox(height: 12),
            TextField(
              controller: _address,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: s.t('relayAddress'),
                hintText: 'https://exemple.org/fst',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _invitation,
              autocorrect: false,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: s.t('relayInvitation'),
                hintText: 'XXXX-XXXX-XXXX',
                helperText: s.t('relayInvitationHelp'),
                helperMaxLines: 3,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(s.t('cancel')),
        ),
        FilledButton(
          onPressed: _busy ? null : _connect,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(s.t('relayConnect')),
        ),
      ],
    );
  }
}
