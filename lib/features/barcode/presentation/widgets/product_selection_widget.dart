import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/di/injection_container.dart';
import '../../../../core/database/daos/product_variant_dao.dart';
import '../../../../core/database/app_database.dart' show ProductVariant;
import '../../../../core/services/currency_service.dart';
import '../../../products/domain/entities/product_entity.dart';

class ProductSelectionWidget extends StatelessWidget {
  final List<Product> selectedProducts;
  final ValueChanged<int> onRemove;
  final VoidCallback onClear;

  const ProductSelectionWidget({
    super.key,
    required this.selectedProducts,
    required this.onRemove,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final currencyService = sl<CurrencyService>();

    if (selectedProducts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              LucideIcons.packageOpen,
              size: 48,
              color: colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'barcode.no_products_selected'.tr(),
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: colorScheme.outline,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'barcode.add_products_hint'.tr(),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.outline,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Header with count and clear button
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Text(
                'barcode.products_count'.tr(args: [selectedProducts.length.toString()]),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: onClear,
                icon: const Icon(LucideIcons.trash2, size: 16),
                label: Text('common.clear_all'.tr()),
                style: TextButton.styleFrom(
                  foregroundColor: colorScheme.error,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // Product list
        Expanded(
          child: ListView.builder(
            itemCount: selectedProducts.length,
            itemBuilder: (context, index) {
              final product = selectedProducts[index];
              return _ProductListItem(
                product: product,
                currencyService: currencyService,
                onRemove: () => onRemove(product.id),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ProductListItem extends StatelessWidget {
  final Product product;
  final CurrencyService currencyService;
  final VoidCallback onRemove;

  const _ProductListItem({
    required this.product,
    required this.currencyService,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final variantDao = sl<ProductVariantDao>();

    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Icon(
            LucideIcons.package,
            size: 20,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ),
      title: Text(
        product.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (product.barcode != null && product.barcode!.isNotEmpty)
            Text(
              product.barcode!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                  ),
            ),
          Text(
            currencyService.format(product.priceCents.toBigInt().toInt()),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.primary,
                ),
          ),
          const SizedBox(height: 4),
          StreamBuilder<List<ProductVariant>>(
            stream: variantDao.watchVariantsByProduct(product.id),
            builder: (context, snapshot) {
              final variants = snapshot.data ?? const <ProductVariant>[];
              if (variants.isEmpty) {
                return const SizedBox.shrink();
              }

              final totalStock = variants.fold<int>(0, (sum, v) => sum + v.stockQuantity);
              final lines = variants.take(3).map((v) {
                final parts = <String>[];
                if (v.sizeId != null) parts.add('S#${v.sizeId}');
                if (v.colorId != null) parts.add('C#${v.colorId}');
                final name = parts.isEmpty ? 'Variant #${v.id}' : parts.join(' ');
                return '$name: ${v.stockQuantity}';
              }).join(' | ');

              return Text(
                '${'variants.new_stock'.tr()}: $totalStock  •  $lines',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.outline,
                    ),
              );
            },
          ),
        ],
      ),
      trailing: IconButton(
        icon: Icon(LucideIcons.x, color: colorScheme.error),
        onPressed: onRemove,
        tooltip: 'common.remove'.tr(),
      ),
      isThreeLine: product.barcode != null && product.barcode!.isNotEmpty,
    );
  }
}
