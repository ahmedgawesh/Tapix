import 'dart:developer' as developer;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/di/injection_container.dart';
import '../../../../core/services/audit_log_service.dart';
import '../../../../core/widgets/pin_verification_dialog.dart';
import '../../../auth/domain/entities/user_entity.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
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
              onChanged: (v) =>
                  _patch(context, (c) => c.copyWith(defaultPaymentMethod: v)),
            ),
            SwitchListTile(
              title: Text('app_settings.sales.partial_payments'.tr()),
              subtitle: Text('app_settings.sales.partial_payments_desc'.tr()),
              value: s.allowPartialPayments,
              onChanged: (v) =>
                  _patch(context, (c) => c.copyWith(allowPartialPayments: v)),
            ),
            SwitchListTile(
              title: Text('app_settings.sales.allow_discounts'.tr()),
              subtitle: Text('app_settings.sales.allow_discounts_desc'.tr()),
              value: s.allowDiscounts,
              onChanged: (v) =>
                  _patch(context, (c) => c.copyWith(allowDiscounts: v)),
            ),
            if (s.allowDiscounts)
              SettingsSliderTile(
                title: 'app_settings.sales.max_discount'.tr(),
                value: s.maxDiscountPercent,
                min: 1,
                max: 100,
                divisions: 99,
                labelSuffix: '%',
                onChanged: (v) =>
                    _patch(context, (c) => c.copyWith(maxDiscountPercent: v)),
              ),
            SwitchListTile(
              secondary: const Icon(LucideIcons.shieldCheck),
              title: Text('app_settings.sales.allow_below_cost_sales'.tr()),
              subtitle: Text(
                'app_settings.sales.allow_below_cost_sales_desc'.tr(),
              ),
              value: s.allowBelowCostSales,
              onChanged: (value) => _setAllowBelowCostSales(context, value),
            ),
            SwitchListTile(
              title: Text('app_settings.sales.require_customer'.tr()),
              subtitle: Text('app_settings.sales.require_customer_desc'.tr()),
              value: s.requireCustomerForSales,
              onChanged: (v) => _patch(
                context,
                (c) => c.copyWith(requireCustomerForSales: v),
              ),
            ),
            SwitchListTile(
              title: Text('app_settings.sales.loyalty_points'.tr()),
              subtitle: Text('app_settings.sales.loyalty_points_desc'.tr()),
              value: s.enableLoyaltyPoints,
              onChanged: (v) =>
                  _patch(context, (c) => c.copyWith(enableLoyaltyPoints: v)),
            ),
            if (s.enableLoyaltyPoints)
              SettingsSliderTile(
                title: 'app_settings.sales.points_per_unit'.tr(),
                value: s.pointsPerCurrencyUnit.toDouble(),
                min: 1,
                max: 10,
                divisions: 9,
                onChanged: (v) => _patch(
                  context,
                  (c) => c.copyWith(pointsPerCurrencyUnit: v.round()),
                ),
              ),
          ],
        );
      },
    );
  }

  void _patch(BuildContext context, AppSettings Function(AppSettings) fn) {
    context.read<AppSettingsBloc>().add(AppSettingsPatched(fn));
  }

  Future<void> _setAllowBelowCostSales(BuildContext context, bool value) async {
    final authState = context.read<AuthBloc>().state;
    final user = authState is AuthAuthenticated ? authState.user : null;
    if (user == null || user.role != UserRole.owner) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('app_settings.sales.below_cost_owner_only'.tr()),
        ),
      );
      return;
    }

    final verified = await showPinVerificationDialog(context);
    if (!verified || !context.mounted) return;

    final previous = context
        .read<AppSettingsBloc>()
        .state
        .settings
        .allowBelowCostSales;
    if (previous == value) return;

    _patch(context, (current) => current.copyWith(allowBelowCostSales: value));
    try {
      await sl<AuditLogService>().log(
        entityType: 'settings',
        entityId: 0,
        action: 'below_cost_sales_policy_changed',
        oldValue: {'allowBelowCostSales': previous},
        newValue: {'allowBelowCostSales': value},
        userId: user.id,
        userRole: user.role.name,
        severity: AuditSeverity.critical,
      );
    } catch (error, stackTrace) {
      // The persisted setting remains authoritative, but a missing audit row
      // must remain visible in local diagnostics.
      developer.log(
        'Could not audit the below-cost sales policy change.',
        name: 'SalesSettingsSection',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
