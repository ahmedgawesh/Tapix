import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../domain/entities/app_settings.dart';
import '../bloc/app_settings_bloc.dart';
import 'settings_widgets.dart';

class ReportsSettingsSection extends StatelessWidget {
  const ReportsSettingsSection({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AppSettingsBloc, AppSettingsState>(
      builder: (context, state) {
        final s = state.settings;
        return SettingsExpansionCard(
          title: 'app_settings.reports.title'.tr(),
          icon: LucideIcons.barChart3,
          children: [
            SettingsOptionTile<String>(
              title: 'app_settings.reports.default_range'.tr(),
              value: s.defaultReportDateRange,
              options: {
                'today': 'app_settings.reports.range_today'.tr(),
                'week': 'app_settings.reports.range_week'.tr(),
                'month': 'app_settings.reports.range_month'.tr(),
              },
              onChanged: (v) => _patch(context, (c) => c.copyWith(defaultReportDateRange: v)),
            ),
            SettingsOptionTile<String>(
              title: 'app_settings.reports.export_format'.tr(),
              value: s.defaultExportFormat,
              options: const {
                'pdf': 'PDF',
                'excel': 'Excel',
                'csv': 'CSV',
              },
              onChanged: (v) => _patch(context, (c) => c.copyWith(defaultExportFormat: v)),
            ),
            SwitchListTile(
              title: Text('app_settings.reports.include_inactive'.tr()),
              subtitle: Text('app_settings.reports.include_inactive_desc'.tr()),
              value: s.includeInactiveInReports,
              onChanged: (v) => _patch(context, (c) => c.copyWith(includeInactiveInReports: v)),
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
