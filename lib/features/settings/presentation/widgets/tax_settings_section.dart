import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../domain/entities/app_settings.dart';
import '../bloc/app_settings_bloc.dart';
import 'settings_widgets.dart';

class TaxSettingsSection extends StatelessWidget {
  const TaxSettingsSection({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AppSettingsBloc, AppSettingsState>(
      builder: (context, state) {
        final s = state.settings;
        return SettingsExpansionCard(
          title: 'app_settings.tax.title'.tr(),
          icon: LucideIcons.percent,
          children: [
            SwitchListTile(
              title: Text('app_settings.tax.enable'.tr()),
              subtitle: Text('app_settings.tax.enable_desc'.tr()),
              value: s.enableTaxCalculations,
              onChanged: (v) => _patch(context, (c) => c.copyWith(enableTaxCalculations: v)),
            ),
            SettingsSliderTile(
              title: 'app_settings.tax.purchase_rate'.tr(),
              value: s.defaultPurchaseTaxRate,
              min: 0,
              max: 30,
              divisions: 30,
              labelSuffix: '%',
              onChanged: (v) => _patch(context, (c) => c.copyWith(defaultPurchaseTaxRate: v)),
            ),
            SettingsSliderTile(
              title: 'app_settings.tax.sales_rate'.tr(),
              value: s.defaultSalesTaxRate,
              min: 0,
              max: 30,
              divisions: 30,
              labelSuffix: '%',
              onChanged: (v) => _patch(context, (c) => c.copyWith(defaultSalesTaxRate: v)),
            ),
            SettingsTextField(
              label: 'app_settings.tax.registration_number'.tr(),
              value: s.taxRegistrationNumber,
              hint: 'app_settings.tax.registration_hint'.tr(),
              onChanged: (v) => _patch(context, (c) => c.copyWith(taxRegistrationNumber: v)),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              title: Text('app_settings.tax.inclusive_pricing'.tr()),
              subtitle: Text('app_settings.tax.inclusive_pricing_desc'.tr()),
              value: s.taxInclusivePricing,
              onChanged: (v) => _patch(context, (c) => c.copyWith(taxInclusivePricing: v)),
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
