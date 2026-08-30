import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/database/database_encryption.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/services/biometric_service.dart';
import '../../../../core/services/pin_service.dart';
import '../../../auth/auth.dart';
import '../../domain/entities/app_settings.dart';
import '../bloc/app_settings_bloc.dart';
import 'settings_widgets.dart';

class SecuritySettingsSection extends StatefulWidget {
  const SecuritySettingsSection({super.key});

  @override
  State<SecuritySettingsSection> createState() =>
      _SecuritySettingsSectionState();
}

class _SecuritySettingsSectionState extends State<SecuritySettingsSection> {
  bool _isPinSet = false;

  @override
  void initState() {
    super.initState();
    _checkPinStatus();
  }

  Future<void> _checkPinStatus() async {
    final pinSet = await sl<PinService>().isPinSet();
    if (mounted) setState(() => _isPinSet = pinSet);
  }

  bool get _isOwner {
    final authState = context.read<AuthBloc>().state;
    return authState is AuthAuthenticated && authState.user.isOwner;
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AppSettingsBloc, AppSettingsState>(
      builder: (context, state) {
        final s = state.settings;
        return SettingsExpansionCard(
          title: 'app_settings.security.title'.tr(),
          icon: LucideIcons.shield,
          children: [
            SwitchListTile(
              title: Text('app_settings.security.enable_session_timeout'.tr()),
              subtitle: Text(
                'app_settings.security.enable_session_timeout_desc'.tr(),
              ),
              value: s.enableSessionTimeout,
              onChanged: (v) =>
                  _patch(context, (c) => c.copyWith(enableSessionTimeout: v)),
            ),
            if (s.enableSessionTimeout)
              SettingsSliderTile(
                title: 'app_settings.security.session_timeout'.tr(),
                value: s.sessionTimeoutMinutes.toDouble(),
                min: 5,
                max: 120,
                divisions: 23,
                labelSuffix: ' min',
                onChanged: (v) => _patch(
                  context,
                  (c) => c.copyWith(sessionTimeoutMinutes: v.round()),
                ),
              ),
            ListTile(
              title: Text('app_settings.security.remember_me_duration'.tr()),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'app_settings.security.remember_me_duration_desc'.tr(),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  Slider(
                    value: s.rememberMeDurationHours.toDouble().clamp(1, 168),
                    min: 1,
                    max: 168,
                    divisions: 167,
                    label: _formatDuration(s.rememberMeDurationHours),
                    onChanged: (v) => _patch(
                      context,
                      (c) => c.copyWith(rememberMeDurationHours: v.round()),
                    ),
                  ),
                ],
              ),
              trailing: Text(
                _formatDuration(s.rememberMeDurationHours),
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            SwitchListTile(
              title: Text('app_settings.security.pin_void_refund'.tr()),
              subtitle: Text('app_settings.security.pin_void_refund_desc'.tr()),
              value: s.requirePinForVoidRefund,
              onChanged: (v) => _togglePinRequirement(context, v),
            ),
            // PIN setup/change - owner only
            if (s.requirePinForVoidRefund && _isOwner)
              ListTile(
                leading: Icon(
                  _isPinSet ? LucideIcons.keyRound : LucideIcons.keyRound,
                  color: _isPinSet
                      ? Colors.green
                      : Theme.of(context).colorScheme.error,
                ),
                title: Text(
                  _isPinSet
                      ? 'app_settings.security.change_pin'.tr()
                      : 'app_settings.security.set_pin'.tr(),
                ),
                subtitle: Text(
                  _isPinSet
                      ? 'app_settings.security.pin_is_set'.tr()
                      : 'app_settings.security.pin_not_set'.tr(),
                ),
                trailing: const Icon(LucideIcons.chevronRight),
                onTap: () => _showSetPinDialog(context),
              ),
            SwitchListTile(
              title: Text('app_settings.security.biometric'.tr()),
              subtitle: Text('app_settings.security.biometric_desc'.tr()),
              value: s.enableBiometricLogin,
              onChanged: (v) => _toggleBiometricLogin(context, v),
            ),
            SwitchListTile(
              title: Text('app_settings.security.encryption'.tr()),
              subtitle: Text(
                s.enableDatabaseEncryption
                    ? 'app_settings.security.encryption_enabled_note'.tr()
                    : 'app_settings.security.encryption_desc'.tr(),
              ),
              value: s.enableDatabaseEncryption,
              onChanged: (v) => _toggleEncryption(context, v),
            ),
          ],
        );
      },
    );
  }

  Future<void> _togglePinRequirement(BuildContext context, bool enable) async {
    if (!enable) {
      _patch(context, (c) => c.copyWith(requirePinForVoidRefund: false));
      return;
    }

    var pinReady = _isPinSet;
    if (!pinReady && _isOwner) {
      pinReady = await _showSetPinDialog(context);
    }
    if (!context.mounted) return;

    if (!pinReady) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('security.pin_not_set_message'.tr()),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    _patch(context, (c) => c.copyWith(requirePinForVoidRefund: true));
  }

  Future<void> _toggleBiometricLogin(BuildContext context, bool enable) async {
    if (!enable) {
      _patch(context, (c) => c.copyWith(enableBiometricLogin: false));
      return;
    }

    final biometricService = sl<BiometricService>();
    final available = await biometricService.isBiometricAvailable();
    if (!context.mounted) return;
    if (!available) {
      _showSecurityMessage(
        context,
        'app_settings.security.biometric_unavailable',
      );
      return;
    }

    final authenticated = await biometricService.authenticate(
      localizedReason: 'app_settings.security.biometric_enable_reason'.tr(),
    );
    if (!context.mounted) return;
    if (!authenticated) {
      _showSecurityMessage(
        context,
        'app_settings.security.biometric_verification_failed',
      );
      return;
    }

    _patch(context, (c) => c.copyWith(enableBiometricLogin: true));
    _showSecurityMessage(context, 'app_settings.security.biometric_enabled');
  }

  void _showSecurityMessage(BuildContext context, String key) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(key.tr()), behavior: SnackBarBehavior.floating),
    );
  }

  Future<bool> _showSetPinDialog(BuildContext context) async {
    final pinController = TextEditingController();
    final confirmController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: Icon(
          LucideIcons.keyRound,
          color: Theme.of(ctx).colorScheme.primary,
          size: 32,
        ),
        title: Text(
          _isPinSet
              ? 'app_settings.security.change_pin'.tr()
              : 'app_settings.security.set_pin'.tr(),
        ),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('app_settings.security.set_pin_desc'.tr()),
              const SizedBox(height: 16),
              TextFormField(
                controller: pinController,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: 'app_settings.security.new_pin'.tr(),
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.pin_outlined),
                  counterText: '',
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) {
                    return 'security.pin_required'.tr();
                  }
                  if (v.length < 4) {
                    return 'app_settings.security.pin_min_length'.tr();
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: confirmController,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: 'app_settings.security.confirm_pin'.tr(),
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.pin_outlined),
                  counterText: '',
                ),
                validator: (v) {
                  if (v != pinController.text) {
                    return 'app_settings.security.pin_mismatch'.tr();
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(ctx, true);
              }
            },
            child: Text('common.save'.tr()),
          ),
        ],
      ),
    );

    var saved = false;
    if (result == true) {
      await sl<PinService>().setPin(pinController.text);
      await _checkPinStatus();
      saved = true;
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('app_settings.security.pin_saved'.tr()),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }

    pinController.dispose();
    confirmController.dispose();
    return saved;
  }

  Future<void> _toggleEncryption(BuildContext context, bool enable) async {
    final keyManager = DatabaseEncryptionKeyManager();

    if (enable) {
      // Warn user: encryption requires app restart
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: Icon(
            LucideIcons.shieldCheck,
            color: Theme.of(ctx).colorScheme.primary,
            size: 32,
          ),
          title: Text('app_settings.security.encryption'.tr()),
          content: Text('app_settings.security.encryption_enable_warning'.tr()),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('common.cancel'.tr()),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('common.confirm'.tr()),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      await keyManager.enableEncryption();
    } else {
      // Warn user: disabling encryption requires restart too
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: Icon(
            LucideIcons.shieldOff,
            color: Theme.of(ctx).colorScheme.error,
            size: 32,
          ),
          title: Text('app_settings.security.encryption'.tr()),
          content: Text(
            'app_settings.security.encryption_disable_warning'.tr(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('common.cancel'.tr()),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('common.confirm'.tr()),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      await keyManager.disableEncryption();
    }

    if (!context.mounted) return;
    _patch(context, (c) => c.copyWith(enableDatabaseEncryption: enable));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('app_settings.security.encryption_restart_required'.tr()),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  String _formatDuration(int hours) {
    if (hours >= 24 && hours % 24 == 0) {
      final days = hours ~/ 24;
      return '$days d';
    }
    if (hours >= 24) {
      final days = hours ~/ 24;
      final remainingHours = hours % 24;
      return '${days}d ${remainingHours}h';
    }
    return '$hours h';
  }

  void _patch(BuildContext context, AppSettings Function(AppSettings) fn) {
    context.read<AppSettingsBloc>().add(AppSettingsPatched(fn));
  }
}
