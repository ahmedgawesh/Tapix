import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../domain/entities/app_settings.dart';
import '../bloc/app_settings_bloc.dart';
import 'settings_widgets.dart';

class SecuritySettingsSection extends StatelessWidget {
  const SecuritySettingsSection({super.key});

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
              subtitle: Text('app_settings.security.enable_session_timeout_desc'.tr()),
              value: s.enableSessionTimeout,
              onChanged: (v) => _patch(context, (c) => c.copyWith(enableSessionTimeout: v)),
            ),
            if (s.enableSessionTimeout)
              SettingsSliderTile(
                title: 'app_settings.security.session_timeout'.tr(),
                value: s.sessionTimeoutMinutes.toDouble(),
                min: 5,
                max: 120,
                divisions: 23,
                labelSuffix: ' min',
                onChanged: (v) => _patch(context, (c) => c.copyWith(sessionTimeoutMinutes: v.round())),
              ),
            SwitchListTile(
              title: Text('app_settings.security.pin_void_refund'.tr()),
              subtitle: Text('app_settings.security.pin_void_refund_desc'.tr()),
              value: s.requirePinForVoidRefund,
              onChanged: (v) => _patch(context, (c) => c.copyWith(requirePinForVoidRefund: v)),
            ),
            SwitchListTile(
              title: Text('app_settings.security.biometric'.tr()),
              subtitle: Text('app_settings.security.biometric_desc'.tr()),
              value: s.enableBiometricLogin,
              onChanged: (v) => _patch(context, (c) => c.copyWith(enableBiometricLogin: v)),
            ),
            SwitchListTile(
              title: Text('app_settings.security.encryption'.tr()),
              subtitle: Text('app_settings.security.encryption_desc'.tr()),
              value: s.enableDatabaseEncryption,
              onChanged: (v) => _patch(context, (c) => c.copyWith(enableDatabaseEncryption: v)),
            ),
          ],
        );
      },
    );
  }

  void _patch(BuildContext context, AppSettings Function(AppSettings) fn) {
    context.read<AppSettingsBloc>().add(AppSettingsPatched(fn));
  }
}
