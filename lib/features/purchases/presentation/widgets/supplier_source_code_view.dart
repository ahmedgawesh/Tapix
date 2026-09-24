import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'dart:ui' as ui;

class SupplierSourceCodeView extends StatelessWidget {
  const SupplierSourceCodeView({
    super.key,
    this.code,
    this.errorKey,
    this.pending = false,
  });
  final String? code;
  final String? errorKey;
  final bool pending;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'supplier_purchase.code_label'.tr(),
            style: theme.textTheme.labelSmall,
          ),
          if (code != null)
            Text(
              code!,
              textDirection: ui.TextDirection.ltr,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            )
          else
            Text(
              (errorKey ??
                      (pending
                          ? 'supplier_purchase.loading'
                          : 'supplier_purchase.select_supplier'))
                  .tr(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: errorKey == null
                    ? theme.colorScheme.onSurfaceVariant
                    : theme.colorScheme.error,
              ),
            ),
        ],
      ),
    );
  }
}
