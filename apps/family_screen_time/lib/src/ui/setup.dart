/// First launch: language, parent code, child, permissions.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controller.dart';
import '../pin.dart';
import '../strings.dart';
import 'permissions.dart';

class SetupFlow extends StatefulWidget {
  final AppController controller;

  const SetupFlow({super.key, required this.controller});

  @override
  State<SetupFlow> createState() => _SetupFlowState();
}

class _SetupFlowState extends State<SetupFlow> {
  int _step = 0;
  final _pin = TextEditingController();
  final _pinConfirm = TextEditingController();
  final _name = TextEditingController();
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _pin.dispose();
    _pinConfirm.dispose();
    _name.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // Setup interrupted after the child was created: resume at permissions.
    if (widget.controller.settings.childId != null) _step = 3;
  }

  S get s => widget.controller.s;

  void _next() {
    setState(() => _error = null);
    switch (_step) {
      case 1:
        if (_pin.text.length < minPinLength) {
          setState(() => _error = s.t('pinTooShort'));
          return;
        }
        if (_pin.text != _pinConfirm.text) {
          setState(() => _error = s.t('pinMismatch'));
          return;
        }
      case 2:
        if (_name.text.trim().isEmpty) {
          setState(() => _error = s.t('childNameMissing'));
          return;
        }
        _finish();
        return;
    }
    setState(() => _step++);
  }

  Future<void> _finish() async {
    setState(() => _saving = true);
    // Setup is saved before the permissions step, so the monitor can start
    // as soon as the first permission is granted.
    await widget.controller.completeSetup(
      pin: _pin.text,
      childName: _name.text.trim(),
    );
    if (mounted) setState(() => _step = 3);
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final title = [
      'welcomeTitle',
      'pinCreateTitle',
      'childTitle',
      'permissionsTitle',
    ][_step];
    return Scaffold(
      appBar: AppBar(title: Text(s.t(title))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ...switch (_step) {
              0 => [
                Text(s.t('welcomeText')),
                const SizedBox(height: 24),
                Text(
                  s.t('language'),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: [
                    for (final l in supportedLanguages)
                      ButtonSegment(
                        value: l,
                        label: Text(S(l).t('languageName')),
                      ),
                  ],
                  selected: {controller.settings.language},
                  onSelectionChanged: (v) => controller.updateSettings(
                    controller.settings.copyWith(language: v.first),
                  ),
                ),
              ],
              1 => [
                Text(s.t('pinCreateText')),
                const SizedBox(height: 16),
                _pinField(_pin, s.t('pin')),
                const SizedBox(height: 12),
                _pinField(_pinConfirm, s.t('pinConfirm')),
              ],
              2 => [
                Text(s.t('childText')),
                const SizedBox(height: 16),
                TextField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: s.t('childName'),
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
              _ => [
                Text(s.t('permissionsText')),
                const SizedBox(height: 12),
                PermissionsView(controller: controller),
              ],
            },
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 24),
            if (_step < 3)
              FilledButton(
                onPressed: _saving ? null : _next,
                child: Text(s.t('continue')),
              ),
            if (_step == 3)
              FilledButton(
                // Leaves setup: the home screen replaces this flow.
                onPressed: () => controller.updateSettings(
                  controller.settings.copyWith(setupDone: true),
                ),
                child: Text(s.t('done')),
              ),
          ],
        ),
      ),
    );
  }

  Widget _pinField(TextEditingController c, String label) => TextField(
    controller: c,
    obscureText: true,
    keyboardType: TextInputType.number,
    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
    ),
  );
}
