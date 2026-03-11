import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../domain/entities/app_settings.dart';
import '../bloc/app_settings_bloc.dart';
import 'settings_widgets.dart';

class InventorySettingsSection extends StatelessWidget {
  const InventorySettingsSection({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AppSettingsBloc, AppSettingsState>(
      builder: (context, state) {
        final s = state.settings;
        return SettingsExpansionCard(
          title: 'app_settings.inventory.title'.tr(),
          icon: LucideIcons.warehouse,
          children: [
            SettingsSliderTile(
              title: 'app_settings.inventory.low_stock_threshold'.tr(),
              value: s.lowStockThreshold.toDouble(),
              min: 1,
              max: 50,
              divisions: 49,
              onChanged: (v) => _patch(context, (c) => c.copyWith(lowStockThreshold: v.round())),
            ),
            SwitchListTile(
              title: Text('app_settings.inventory.stock_alerts'.tr()),
              subtitle: Text('app_settings.inventory.stock_alerts_desc'.tr()),
              value: s.enableStockAlerts,
              onChanged: (v) => _patch(context, (c) => c.copyWith(enableStockAlerts: v)),
            ),
            SwitchListTile(
              title: Text('app_settings.inventory.negative_stock'.tr()),
              subtitle: Text('app_settings.inventory.negative_stock_desc'.tr()),
              value: s.allowNegativeStock,
              onChanged: (v) => _patch(context, (c) => c.copyWith(allowNegativeStock: v)),
            ),
            SwitchListTile(
              title: Text('app_settings.inventory.auto_sku'.tr()),
              subtitle: Text('app_settings.inventory.auto_sku_desc'.tr()),
              value: s.autoGenerateSku,
              onChanged: (v) => _patch(context, (c) => c.copyWith(autoGenerateSku: v)),
            ),
            if (s.autoGenerateSku)
              SettingsTextField(
                label: 'app_settings.inventory.sku_format'.tr(),
                value: s.skuFormat,
                hint: 'PRD-{0000}',
                onChanged: (v) => _patch(context, (c) => c.copyWith(skuFormat: v)),
              ),
            SwitchListTile(
              title: Text('app_settings.inventory.auto_barcode'.tr()),
              subtitle: Text('app_settings.inventory.auto_barcode_desc'.tr()),
              value: s.autoGenerateBarcode,
              onChanged: (v) => _patch(context, (c) => c.copyWith(autoGenerateBarcode: v)),
            ),
            SwitchListTile(
              title: Text('app_settings.inventory.track_inventory'.tr()),
              subtitle: Text('app_settings.inventory.track_inventory_desc'.tr()),
              value: s.defaultTrackInventory,
              onChanged: (v) => _patch(context, (c) => c.copyWith(defaultTrackInventory: v)),
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
