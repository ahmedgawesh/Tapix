import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../../core/services/revenuecat_service.dart';
import '../screens/custom_paywall_screen.dart';

/// Shows a dialog telling the user they hit the free-tier quota and offering an
/// upgrade. Returns when the dialog is dismissed.
///
/// [isProducts] picks the products vs sales copy; [limit] is the free cap.
Future<void> showQuotaExceededDialog(
  BuildContext context, {
  required bool isProducts,
  required int limit,
}) async {
  final messageKey = isProducts
      ? 'subscription.quota_products_reached'
      : 'subscription.quota_sales_reached';

  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.workspace_premium, color: Colors.amber, size: 40),
      title: Text('subscription.feature_locked_title'.tr()),
      content: Text(
        messageKey.tr(namedArgs: {'limit': '$limit'}),
        textAlign: TextAlign.center,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text('subscription.back_to_home'.tr()),
        ),
        ElevatedButton.icon(
          onPressed: () {
            Navigator.of(ctx).pop();
            if (RevenueCatConfig.isSupported &&
                RevenueCatService.instance.isInitialized) {
              CustomPaywallScreen.show(context);
            }
          },
          icon: const Icon(Icons.star),
          label: Text('subscription.upgrade_to_pro'.tr()),
        ),
      ],
    ),
  );
}

/// Parses a bloc/state error string of the form `quota_exceeded:<kind>:<limit>`.
/// Returns `null` when [error] is not a quota error.
({bool isProducts, int limit})? parseQuotaError(String? error) {
  if (error == null || !error.startsWith('quota_exceeded:')) return null;
  final parts = error.split(':');
  if (parts.length < 3) return null;
  final isProducts = parts[1] == 'products';
  final limit = int.tryParse(parts[2]) ?? 0;
  return (isProducts: isProducts, limit: limit);
}
