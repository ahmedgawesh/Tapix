import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/services/currency_service.dart';
import '../../../../core/di/injection_container.dart';
import '../../../products/domain/entities/product_entity.dart';
import '../../domain/entities/scanner_result.dart';

class ProductResultCard extends StatelessWidget {
  final Product product;
  final ScannerResult? scanResult;
  final VoidCallback? onViewProduct;

  const ProductResultCard({
    super.key,
    required this.product,
    this.scanResult,
    this.onViewProduct,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final currencyService = sl<CurrencyService>();

    return Card(
      color: colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with success icon
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    LucideIcons.check,
                    color: colorScheme.onPrimary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'barcode.product_found'.tr(),
                        style: TextStyle(
                          color: colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (scanResult != null)
                        Text(
                          scanResult!.barcode,
                          style: TextStyle(
                            color: colorScheme.onPrimaryContainer.withValues(alpha: 0.7),
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
                if (onViewProduct != null)
                  IconButton(
                    onPressed: onViewProduct,
                    icon: const Icon(LucideIcons.externalLink),
                    tooltip: 'barcode.view_product'.tr(),
                  ),
              ],
            ),
            const Divider(height: 24),
            // Product details
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Product name
                    Text(
                      product.name,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // SKU
                    if (product.sku != null) ...[
                      _buildInfoRow(
                        context,
                        icon: LucideIcons.hash,
                        label: 'products.sku'.tr(),
                        value: product.sku!,
                      ),
                      const SizedBox(height: 4),
                    ],
                    // Price
                    _buildInfoRow(
                      context,
                      icon: LucideIcons.dollarSign,
                      label: 'products.price'.tr(),
                      value: currencyService.format(product.priceCents.toBigInt().toInt()),
                      valueStyle: TextStyle(
                        color: colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Stock
                    _buildInfoRow(
                      context,
                      icon: LucideIcons.package,
                      label: 'products.stock'.tr(),
                      value: '${product.stockQuantity}',
                      valueStyle: TextStyle(
                        color: product.stockQuantity <= product.minQuantity
                            ? colorScheme.error
                            : colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    TextStyle? valueStyle,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Icon(
          icon,
          size: 16,
          color: colorScheme.onPrimaryContainer.withValues(alpha: 0.7),
        ),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: TextStyle(
            color: colorScheme.onPrimaryContainer.withValues(alpha: 0.7),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: valueStyle ??
                TextStyle(
                  color: colorScheme.onPrimaryContainer,
                ),
          ),
        ),
      ],
    );
  }
}
