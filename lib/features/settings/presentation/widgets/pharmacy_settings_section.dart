import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/database/daos/settings_dao.dart';
import '../../../../core/di/injection_container.dart';
import '../bloc/app_settings_bloc.dart';
import 'settings_widgets.dart';

class PharmacySettingsSection extends StatelessWidget {
  const PharmacySettingsSection({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AppSettingsBloc, AppSettingsState>(
      builder: (context, state) {
        return SettingsExpansionCard(
          title: 'pharmacy.settings.title'.tr(),
          icon: LucideIcons.pill,
          children: [
            SwitchListTile(
              title: Text('pharmacy.settings.enable'.tr()),
              subtitle: Text('pharmacy.settings.enable_desc'.tr()),
              value: state.settings.enablePharmacyFeatures,
              onChanged: (enabled) {
                context.read<AppSettingsBloc>().add(
                  AppSettingsPatched(
                    (current) =>
                        current.copyWith(enablePharmacyFeatures: enabled),
                  ),
                );
                // Keep the database-backed flag in sync so backups and the
                // future online/LAN settings source retain the same choice.
                unawaited(_mirrorFeatureFlag(enabled));
              },
            ),
            if (state.settings.enablePharmacyFeatures)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  'pharmacy.settings.safety_note'.tr(),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _mirrorFeatureFlag(bool enabled) async {
    try {
      await sl<SettingsDao>().saveSetting(
        'pharmacy_features_enabled',
        enabled ? '1' : '0',
      );
    } catch (_) {
      // SharedPreferences remains the authoritative UI setting. The DB mirror
      // is best-effort metadata for backup and future LAN/cloud propagation.
    }
  }
}
