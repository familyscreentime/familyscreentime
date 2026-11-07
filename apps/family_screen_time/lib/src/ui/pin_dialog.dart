/// Parent code prompt.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controller.dart';
import '../pin.dart';
import '../platform.dart' show BiometricStatus;

/// Asks for the parent code; true when it is right. On a parent's device,
/// the fingerprint or face is asked first when it was turned on, and
/// offered once after the code is typed ([offerBiometric]).
Future<bool> askParentPin(
  BuildContext context,
  AppController controller, {
  bool offerBiometric = true,
}) async {
  final code = await showDialog<String>(
    context: context,
    builder: (_) => _PinDialog(controller: controller),
  );
  if (code == null) return false;
  final c = controller;
  if (offerBiometric &&
      code.isNotEmpty &&
      c.settings.parentDevice &&
      !c.settings.biometricOffered &&
      !c.biometricOn &&
      context.mounted &&
      await c.biometricAvailable() &&
      context.mounted) {
    await _offerBiometric(context, c, code);
  }
  return true;
}

/// Offers, once, to open parent mode with the fingerprint or face.
Future<void> _offerBiometric(
  BuildContext context,
  AppController c,
  String code,
) async {
  final s = c.s;
  final yes = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.fingerprint),
      title: Text(s.t('biometricOfferTitle')),
      content: Text(s.t('biometricOfferText')),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(s.t('biometricOfferNo')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(s.t('biometricOfferYes')),
        ),
      ],
    ),
  );
  if (yes == true) {
    await c.enableBiometric(code);
  } else {
    await c.updateSettings(c.settings.copyWith(biometricOffered: true));
  }
}

/// Pops with the code typed, or an empty string when the fingerprint or
/// face opened.
class _PinDialog extends StatefulWidget {
  final AppController controller;

  const _PinDialog({required this.controller});

  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  final _pin = TextEditingController();
  final _focus = FocusNode();
  String? _error;
  bool _checking = false;
  bool _biometric = false;

  @override
  void initState() {
    super.initState();
    _biometric = widget.controller.biometricOn;
    if (_biometric) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _useBiometric());
    }
  }

  @override
  void dispose() {
    _pin.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _useBiometric() async {
    final c = widget.controller;
    if (_checking || !mounted) return;
    setState(() => _checking = true);
    final status = await c.biometricUnlock();
    if (!mounted) return;
    if (status == BiometricStatus.ok) {
      Navigator.of(context).pop('');
      return;
    }
    setState(() {
      _checking = false;
      _biometric = c.biometricOn;
      _error = switch (status) {
        BiometricStatus.invalidated => c.s.t('biometricChanged'),
        BiometricStatus.lockout => c.s.t('biometricLockout'),
        BiometricStatus.cancelled => null,
        _ => c.s.t('biometricFailed'),
      };
    });
    _focus.requestFocus();
  }

  Future<void> _submit() async {
    final c = widget.controller;
    setState(() => _checking = true);
    final code = _pin.text;
    final result = await c.checkParentCode(code);
    if (!mounted) return;
    if (result.ok) {
      Navigator.of(context).pop(code);
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
        focusNode: _focus,
        // The fingerprint or face comes first: no keyboard over its prompt.
        autofocus: !_biometric,
        obscureText: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onSubmitted: (_) => _checking ? null : _submit(),
        decoration: InputDecoration(
          errorText: _error,
          errorMaxLines: 3,
          suffixIcon: _biometric
              ? IconButton(
                  icon: const Icon(Icons.fingerprint),
                  tooltip: s.t('biometricTitle'),
                  onPressed: _checking ? null : _useBiometric,
                )
              : null,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
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
