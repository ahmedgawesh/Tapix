import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../domain/entities/app_settings.dart';
import '../bloc/app_settings_bloc.dart';
import 'settings_widgets.dart';

class NotificationSettingsSection extends StatelessWidget {
  const NotificationSettingsSection({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AppSettingsBloc, AppSettingsState>(
      builder: (context, state) {
        final s = state.settings;
        return SettingsExpansionCard(
          title: 'app_settings.notifications.title'.tr(),
          icon: LucideIcons.bell,
          children: [
            SwitchListTile(
              title: Text('app_settings.notifications.low_stock'.tr()),
              subtitle: Text('app_settings.notifications.low_stock_desc'.tr()),
              value: s.lowStockNotifications,
              onChanged: (v) =>
                  _patch(context, (c) => c.copyWith(lowStockNotifications: v)),
            ),
            SwitchListTile(
              title: Text('app_settings.notifications.daily_summary'.tr()),
              subtitle: Text(
                'app_settings.notifications.daily_summary_desc'.tr(),
              ),
              value: s.dailySalesSummary,
              onChanged: (v) =>
                  _patch(context, (c) => c.copyWith(dailySalesSummary: v)),
            ),
            SwitchListTile(
              title: Text('app_settings.notifications.payment_reminders'.tr()),
              subtitle: Text(
                'app_settings.notifications.payment_reminders_desc'.tr(),
              ),
              value: s.paymentReminders,
              onChanged: (v) =>
                  _patch(context, (c) => c.copyWith(paymentReminders: v)),
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
