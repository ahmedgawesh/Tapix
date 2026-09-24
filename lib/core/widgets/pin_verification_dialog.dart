import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/di/injection_container.dart';
import '../../core/services/pin_service.dart';

/// Shows a PIN verification dialog. Returns true if the PIN is correct, false otherwise.
/// If no PIN is set, shows a warning and returns false.
Future<bool> showPinVerificationDialog(BuildContext context) async {
  final pinService = sl<PinService>();
  final isPinSet = await pinService.isPinSet();

  if (!isPinSet) {
    // No PIN configured — show info dialog and block the action
    if (!context.mounted) return false;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(
          Icons.info_outline,
          color: Theme.of(ctx).colorScheme.primary,
          size: 32,
        ),
        title: Text('security.pin_not_set_title'.tr()),
        content: Text('security.pin_not_set_message'.tr()),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('common.ok'.tr()),
          ),
        ],
      ),
    );
    return false;
  }

  if (!context.mounted) return false;

  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _PinVerificationDialogContent(pinService: pinService),
  );

  return result == true;
}

class _PinVerificationDialogContent extends StatefulWidget {
  final PinService pinService;

  const _PinVerificationDialogContent({required this.pinService});

  @override
  State<_PinVerificationDialogContent> createState() =>
      _PinVerificationDialogContentState();
}

class _PinVerificationDialogContentState
    extends State<_PinVerificationDialogContent> {
  final _pinController = TextEditingController();
  final _focusNode = FocusNode();
  bool _obscure = true;
  String? _errorText;
  bool _verifying = false;
  int _attempts = 0;
  static const int _maxAttempts = 5;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _pinController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final pin = _pinController.text.trim();
    if (pin.isEmpty) {
      setState(() => _errorText = 'security.pin_required'.tr());
      return;
    }

    setState(() {
      _verifying = true;
      _errorText = null;
    });

    final isValid = await widget.pinService.verifyPin(pin);

    if (!mounted) return;

    if (isValid) {
      Navigator.pop(context, true);
    } else {
      _attempts++;
      if (_attempts >= _maxAttempts) {
        Navigator.pop(context, false);
        return;
      }
      setState(() {
        _verifying = false;
        _errorText = 'security.pin_incorrect'.tr();
        _pinController.clear();
      });
      _focusNode.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AlertDialog(
      icon: Icon(Icons.lock_outline, color: colorScheme.primary, size: 32),
      title: Text('security.enter_pin_title'.tr()),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('security.enter_pin_message'.tr()),
          const SizedBox(height: 16),
          TextField(
            controller: _pinController,
            focusNode: _focusNode,
            obscureText: _obscure,
            keyboardType: TextInputType.number,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: 'PIN',
              errorText: _errorText,
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.pin_outlined),
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
              counterText: '',
            ),
            onSubmitted: (_) => _verify(),
          ),
          if (_attempts > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'security.pin_attempts_remaining'.tr(
                  args: ['${_maxAttempts - _attempts}'],
                ),
                style: TextStyle(color: colorScheme.error, fontSize: 12),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _verifying ? null : () => Navigator.pop(context, false),
          child: Text('common.cancel'.tr()),
        ),
        FilledButton(
          onPressed: _verifying ? null : _verify,
          child: _verifying
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text('security.verify_pin'.tr()),
        ),
      ],
    );
  }
}
