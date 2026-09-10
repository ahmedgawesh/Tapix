import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Small, reusable confirmation used for irreversible one-tap actions.
Future<bool> showActionConfirmationDialog(
  BuildContext context, {
  required String title,
  required String message,
  String? confirmLabel,
  IconData icon = Icons.warning_amber_rounded,
  bool destructive = false,
}) async {
  final scheme = Theme.of(context).colorScheme;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: Icon(icon, color: destructive ? scheme.error : scheme.primary),
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text('common.cancel'.tr()),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: scheme.error,
                  foregroundColor: scheme.onError,
                )
              : null,
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(confirmLabel ?? 'common.confirm'.tr()),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

Future<bool> confirmInvoiceLineRemoval(
  BuildContext context, {
  String? itemName,
}) {
  final normalizedName = itemName?.trim();
  return showActionConfirmationDialog(
    context,
    title: 'common.remove_invoice_item_title'.tr(),
    message: normalizedName == null || normalizedName.isEmpty
        ? 'common.remove_invoice_item_message'.tr()
        : 'common.remove_invoice_item_named_message'.tr(
            namedArgs: {'name': normalizedName},
          ),
    confirmLabel: 'common.remove'.tr(),
    icon: Icons.delete_outline_rounded,
    destructive: true,
  );
}
