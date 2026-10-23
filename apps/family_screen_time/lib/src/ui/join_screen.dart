/// A device joining devices linked already, at first launch or set up on
/// its own already (parent mode): find the device welcoming it on the
/// network, compare the code, enter their parent code, and, if this device
/// had rules for a child they know, choose what becomes of them.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:screentime_sync/screentime_sync.dart';

import '../controller.dart';
import '../sync/bonsoir_directory.dart';
import '../sync/family_sync.dart';

class JoinScreen extends StatefulWidget {
  final AppController controller;
  final LanDirectory Function() directory;

  const JoinScreen({
    super.key,
    required this.controller,
    this.directory = BonsoirDirectory.new,
  });

  @override
  State<JoinScreen> createState() => _JoinScreenState();
}

enum _Stage { searching, comparing, waiting, code, rules }

class _JoinScreenState extends State<JoinScreen> {
  final _hosts = <String, LanService>{};
  StreamSubscription<LanService>? _search;
  _Stage _stage = _Stage.searching;
  String? _code;
  Completer<bool>? _codeChecked;
  FamilySync? _joined;
  final _parentCode = TextEditingController();
  String? _error;
  bool _checking = false;

  /// Joined for good: the log is this device's.
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _startSearch();
  }

  void _startSearch() {
    _search = findPairingHosts(widget.directory()).listen(
      (s) {
        if (!mounted) return;
        setState(() {
          if (s.lost) {
            _hosts.remove(s.name);
          } else {
            _hosts[s.name] = s;
          }
        });
      },
      onError: (Object _) {
        if (!mounted) return;
        setState(() => _error = widget.controller.s.t('pairNetworkError'));
      },
    );
  }

  @override
  void dispose() {
    _search?.cancel();
    _parentCode.dispose();
    // Given up before the end: this device stays as it was.
    if (!_done) _joined?.close();
    super.dispose();
  }

  Future<void> _join(LanService host) async {
    final c = widget.controller;
    setState(() {
      _error = null;
      _stage = _Stage.comparing;
    });
    try {
      c.touch();
      final me = await DeviceIdentity.generate(c.settings.deviceId);
      final settings = c.settings;
      final child = settings.setupDone && !settings.parentDevice
          ? c.family.child(settings.childId)
          : null;
      final welcome = await joinThrough(
        host,
        me: me,
        info: {
          'name': await c.platform.deviceName(),
          'platform': 'android',
          // Set up already: the parent says who this child is there.
          if (child != null) 'child': {'id': child.id, 'name': child.name},
        },
        confirm: (code) {
          final checked = _codeChecked = Completer<bool>();
          if (mounted) setState(() => _code = code);
          return checked.future;
        },
      );
      final log = await FamilySync.join(
        store: c.store,
        identity: me,
        welcome: welcome,
      );
      if (!mounted) {
        await log.close();
        return;
      }
      setState(() {
        _joined = log;
        _stage = _Stage.code;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _error = c.s.t('joinRefused');
        _stage = _Stage.searching;
        _code = null;
      });
    }
  }

  void _answer(bool same) {
    _codeChecked?.complete(same);
    _codeChecked = null;
    setState(() => _stage = same ? _Stage.waiting : _Stage.searching);
  }

  Future<void> _checkParentCode() async {
    final c = widget.controller;
    final log = _joined!;
    setState(() {
      _checking = true;
      _error = null;
    });
    final key = await log.unlock(_parentCode.text);
    if (!mounted) return;
    if (key == null) {
      setState(() {
        _checking = false;
        _error = c.s.t('wrongPin');
      });
      return;
    }
    if (c.joinAsksForRules(log)) {
      c.touch();
      setState(() {
        _checking = false;
        _stage = _Stage.rules;
      });
      return;
    }
    await _complete(keepRules: false);
  }

  Future<void> _complete({required bool keepRules}) async {
    final c = widget.controller;
    setState(() => _checking = true);
    await c.completeJoin(_joined!, _parentCode.text, keepRules: keepRules);
    _done = true;
    if (mounted) Navigator.of(context).pop(true);
  }

  /// The child's name among the linked devices.
  String _childThere() {
    final id = _joined?.registration?['childId'];
    final child = _joined?.node.replica['child/$id'];
    return child?['name'] as String? ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.controller.s;
    final theme = Theme.of(context);
    final code = _code;
    return Scaffold(
      appBar: AppBar(title: Text(s.t('joinTitle'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ...switch (_stage) {
            _Stage.searching => [
              Text(s.t('joinText')),
              const SizedBox(height: 16),
              if (_hosts.isEmpty)
                Row(
                  children: [
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(s.t('joinSearching'))),
                  ],
                ),
              for (final h in _hosts.values)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.devices),
                    title: Text(h.attributes['n'] ?? h.name),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _join(h),
                  ),
                ),
            ],
            _Stage.comparing when code == null => [
              const Center(child: CircularProgressIndicator()),
            ],
            _Stage.comparing => [
              Text(s.t('joinCodeText')),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  '${code!.substring(0, 3)} ${code.substring(3)}',
                  style: theme.textTheme.displaySmall?.copyWith(
                    letterSpacing: 4,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => _answer(true),
                child: Text(s.t('pairConfirm')),
              ),
              TextButton(
                onPressed: () => _answer(false),
                child: Text(s.t('cancel')),
              ),
            ],
            _Stage.waiting => [
              Text(s.t('joinWaiting')),
              const SizedBox(height: 16),
              const Center(child: CircularProgressIndicator()),
            ],
            _Stage.code => [
              Text(s.t('joinCodeAsk')),
              const SizedBox(height: 12),
              TextField(
                controller: _parentCode,
                obscureText: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: s.t('pin'),
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: (_) => _checkParentCode(),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _checking ? null : _checkParentCode,
                child: Text(s.t('continue')),
              ),
            ],
            _Stage.rules => [
              Text(s.t('joinRulesText', {'child': _childThere()})),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _checking ? null : () => _complete(keepRules: false),
                child: Text(s.t('joinRulesDrop')),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _checking ? null : () => _complete(keepRules: true),
                child: Text(s.t('joinRulesKeep')),
              ),
            ],
          },
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
        ],
      ),
    );
  }
}
