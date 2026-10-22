/// Parent code prompt.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controller.dart';
import '../pin.dart';

/// Asks for the parent code; true when it is right.
Future<bool> askParentPin(
  BuildContext context,
  AppController controller,
) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => _PinDialog(controller: controller),
  );
  return ok ?? false;
}

class _PinDialog extends StatefulWidget {
  final AppController controller;

  const _PinDialog({required this.controller});

  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  final _pin = TextEditingController();
  String? _error;
  bool _checking = false;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final c = widget.controller;
    setState(() => _checking = true);
    final result = await checkPin(c.settings, _pin.text);
    await c.updateSettings(result.settings);
    if (!mounted) return;
    if (result.ok) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _checking = false;
      _pin.clear();
      _error = result.lockedFor == null
          ? c.s.t('wrongPin')
          : c.s.t('pinLocked', {'time': c.s.duration(result.lockedFor!)});
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.controller.s;
    return AlertDialog(
      title: Text(s.t('enterPin')),
      content: TextField(
        controller: _pin,
        autofocus: true,
        obscureText: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onSubmitted: (_) => _checking ? null : _submit(),
        decoration: InputDecoration(errorText: _error),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(s.t('cancel')),
        ),
        FilledButton(
          onPressed: _checking ? null : _submit,
          child: _checking
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(s.t('ok')),
        ),
      ],
    );
  }
}

/// Asks for a new parent code twice; returns it, or null if cancelled.
Future<String?> askNewPin(BuildContext context, AppController controller) =>
    showDialog<String>(
      context: context,
      builder: (_) => _NewPinDialog(controller: controller),
    );

class _NewPinDialog extends StatefulWidget {
  final AppController controller;

  const _NewPinDialog({required this.controller});

  @override
  State<_NewPinDialog> createState() => _NewPinDialogState();
}

class _NewPinDialogState extends State<_NewPinDialog> {
  final _pin = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _pin.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _submit() {
    final s = widget.controller.s;
    if (_pin.text.length < minPinLength) {
      setState(() => _error = s.t('pinTooShort'));
    } else if (_pin.text != _confirm.text) {
      setState(() => _error = s.t('pinMismatch'));
    } else {
      Navigator.of(context).pop(_pin.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.controller.s;
    InputDecoration deco(String label) => InputDecoration(labelText: label);
    return AlertDialog(
      title: Text(s.t('changePin')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _pin,
            obscureText: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: deco(s.t('pin')),
          ),
          TextField(
            controller: _confirm,
            obscureText: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: deco(s.t('pinConfirm')).copyWith(errorText: _error),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(s.t('cancel')),
        ),
        FilledButton(onPressed: _submit, child: Text(s.t('save'))),
      ],
    );
  }
}
