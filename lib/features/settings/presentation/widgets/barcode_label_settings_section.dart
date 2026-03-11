import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../domain/entities/app_settings.dart';
import '../bloc/app_settings_bloc.dart';
import 'settings_widgets.dart';

class BarcodeLabelSettingsSection extends StatelessWidget {
  const BarcodeLabelSettingsSection({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AppSettingsBloc, AppSettingsState>(
      builder: (context, state) {
        final s = state.settings;
        return SettingsExpansionCard(
          title: 'app_settings.barcode.title'.tr(),
          icon: LucideIcons.scanLine,
          children: [
            SettingsOptionTile<String>(
              title: 'app_settings.barcode.label_size'.tr(),
              value: s.defaultLabelSize,
              options: {
                'small': 'app_settings.barcode.size_small'.tr(),
                'medium': 'app_settings.barcode.size_medium'.tr(),
                'large': 'app_settings.barcode.size_large'.tr(),
              },
              onChanged: (v) => _patch(context, (c) => c.copyWith(defaultLabelSize: v)),
            ),
            SettingsOptionTile<String>(
              title: 'app_settings.barcode.template'.tr(),
              value: s.labelTemplate,
              options: {
                'standard': 'app_settings.barcode.template_standard'.tr(),
                'compact': 'app_settings.barcode.template_compact'.tr(),
                'detailed': 'app_settings.barcode.template_detailed'.tr(),
              },
              onChanged: (v) => _patch(context, (c) => c.copyWith(labelTemplate: v)),
            ),
            SettingsOptionTile<String>(
              title: 'app_settings.barcode.printer_connection'.tr(),
              value: s.printerConnection,
              options: {
                'none': 'app_settings.barcode.conn_none'.tr(),
                'bluetooth': 'app_settings.barcode.conn_bluetooth'.tr(),
                'usb': 'app_settings.barcode.conn_usb'.tr(),
                'network': 'app_settings.barcode.conn_network'.tr(),
              },
              onChanged: (v) => _patch(context, (c) => c.copyWith(printerConnection: v)),
            ),
            SwitchListTile(
              title: Text('app_settings.barcode.include_price'.tr()),
              subtitle: Text('app_settings.barcode.include_price_desc'.tr()),
              value: s.includePriceOnLabel,
              onChanged: (v) => _patch(context, (c) => c.copyWith(includePriceOnLabel: v)),
            ),
            SwitchListTile(
              title: Text('app_settings.barcode.include_text'.tr()),
              subtitle: Text('app_settings.barcode.include_text_desc'.tr()),
              value: s.includeBarcodeText,
              onChanged: (v) => _patch(context, (c) => c.copyWith(includeBarcodeText: v)),
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
