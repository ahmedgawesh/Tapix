import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/database/daos/settings_dao.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/services/feature_gate_service.dart';
import '../bloc/app_settings_bloc.dart';
import 'settings_widgets.dart';

class PromotionsSettingsSection extends StatelessWidget {
  const PromotionsSettingsSection({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AppSettingsBloc, AppSettingsState>(
      builder: (context, state) {
        final gate = sl<FeatureGateService>();
        return ListenableBuilder(
          listenable: gate,
          builder: (context, _) {
            final isPro = gate.canAccess(AppFeature.promotions).granted;
            final enabled = gate.isEnabled(
              AppFeature.promotions,
              settingEnabled: state.settings.enablePromotions,
            );
            return SettingsExpansionCard(
              title: 'promotions.settings.title'.tr(),
              icon: LucideIcons.badgePercent,
              children: [
                SwitchListTile(
                  title: Text('promotions.settings.enable'.tr()),
                  subtitle: Text('promotions.settings.enable_desc'.tr()),
                  value: enabled,
                  onChanged: (value) {
                    if (!isPro) {
                      context.push('/upgrade?from=%2Fsettings');
                      return;
                    }
                    context.read<AppSettingsBloc>().add(
                      AppSettingsPatched(
                        (current) => current.copyWith(enablePromotions: value),
                      ),
                    );
                    unawaited(_mirrorFeatureFlag(value));
                  },
                ),
                if (!isPro)
                  ListTile(
                    leading: const Icon(LucideIcons.lockKeyhole),
                    title: Text('subscription.feature_locked_title'.tr()),
                    subtitle: Text('subscription.feature_locked_message'.tr()),
                    trailing: TextButton(
                      onPressed: () =>
                          context.push('/upgrade?from=%2Fsettings'),
                      child: Text('subscription.upgrade_to_pro'.tr()),
                    ),
                  ),
                if (enabled) ...[
                  ListTile(
                    leading: const Icon(LucideIcons.tags),
                    title: Text('promotions.settings.manage'.tr()),
                    subtitle: Text('promotions.settings.manage_desc'.tr()),
                    trailing: const Icon(LucideIcons.chevronRight),
                    onTap: () => context.push('/promotions'),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Text(
                      'promotions.settings.safety_note'.tr(),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _mirrorFeatureFlag(bool enabled) async {
    try {
      await sl<SettingsDao>().saveSetting(
        'promotions_enabled',
        enabled ? '1' : '0',
        description: 'Enables promotion management and automatic evaluation.',
      );
    } catch (_) {
      // SharedPreferences remains authoritative for the current device. The
      // database mirror is retained in backups and future online sync.
    }
  }
}
