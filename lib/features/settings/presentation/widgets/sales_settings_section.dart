import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../domain/entities/app_settings.dart';
import '../bloc/app_settings_bloc.dart';
import 'settings_widgets.dart';

class SalesSettingsSection extends StatelessWidget {
  const SalesSettingsSection({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AppSettingsBloc, AppSettingsState>(
      builder: (context, state) {
        final s = state.settings;
        return SettingsExpansionCard(
          title: 'app_settings.sales.title'.tr(),
          icon: LucideIcons.shoppingCart,
          children: [
            SettingsOptionTile<String>(
              title: 'app_settings.sales.default_payment'.tr(),
              value: s.defaultPaymentMethod,
              options: {
                'cash': 'app_settings.sales.payment_cash'.tr(),
                'card': 'app_settings.sales.payment_card'.tr(),
                'bank_transfer': 'app_settings.sales.payment_bank'.tr(),
              },
              onChanged: (v) => _patch(context, (c) => c.copyWith(defaultPaymentMethod: v)),
            ),
            SwitchListTile(
              title: Text('app_settings.sales.partial_payments'.tr()),
              subtitle: Text('app_settings.sales.partial_payments_desc'.tr()),
              value: s.allowPartialPayments,
              onChanged: (v) => _patch(context, (c) => c.copyWith(allowPartialPayments: v)),
            ),
            SwitchListTile(
              title: Text('app_settings.sales.allow_discounts'.tr()),
              subtitle: Text('app_settings.sales.allow_discounts_desc'.tr()),
              value: s.allowDiscounts,
              onChanged: (v) => _patch(context, (c) => c.copyWith(allowDiscounts: v)),
            ),
            if (s.allowDiscounts)
              SettingsSliderTile(
                title: 'app_settings.sales.max_discount'.tr(),
                value: s.maxDiscountPercent,
                min: 1,
                max: 100,
                divisions: 99,
                labelSuffix: '%',
                onChanged: (v) => _patch(context, (c) => c.copyWith(maxDiscountPercent: v)),
              ),
            SwitchListTile(
              title: Text('app_settings.sales.require_customer'.tr()),
              subtitle: Text('app_settings.sales.require_customer_desc'.tr()),
              value: s.requireCustomerForSales,
              onChanged: (v) => _patch(context, (c) => c.copyWith(requireCustomerForSales: v)),
            ),
            SwitchListTile(
              title: Text('app_settings.sales.loyalty_points'.tr()),
              subtitle: Text('app_settings.sales.loyalty_points_desc'.tr()),
              value: s.enableLoyaltyPoints,
              onChanged: (v) => _patch(context, (c) => c.copyWith(enableLoyaltyPoints: v)),
            ),
            if (s.enableLoyaltyPoints)
              SettingsSliderTile(
                title: 'app_settings.sales.points_per_unit'.tr(),
                value: s.pointsPerCurrencyUnit.toDouble(),
                min: 1,
                max: 10,
                divisions: 9,
                onChanged: (v) => _patch(context, (c) => c.copyWith(pointsPerCurrencyUnit: v.round())),
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
