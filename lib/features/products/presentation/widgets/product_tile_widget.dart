import 'dart:io';

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../domain/entities/product_entity.dart';
import '../../../../core/services/currency_service.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class ProductTileWidget extends StatelessWidget {
  final Product product;
  final void Function(Product)? onTap;
  final void Function(Product)? onLongPress;
  final bool? isSelected;

  const ProductTileWidget({
    super.key,
    required this.product,
    this.onTap,
    this.onLongPress,
    this.isSelected,
  });

  bool get _isOutOfStock => product.stockQuantity <= 0;

  bool get _isLowStock {
    final minQuantity = product.minQuantity;
    return product.stockQuantity > 0 && product.stockQuantity <= minQuantity;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final currencyService = context.read<CurrencyService>();
    final inSelectionMode = isSelected != null;
    final selected = isSelected ?? false;
    
    return Card(
      clipBehavior: Clip.antiAlias,
      color: selected ? colorScheme.primaryContainer.withValues(alpha: 0.3) : null,
      child: InkWell(
        onTap: onTap != null ? () => onTap!(product) : null,
        onLongPress: onLongPress != null ? () => onLongPress!(product) : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              if (inSelectionMode)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Checkbox(
                    value: selected,
                    onChanged: (_) => onTap?.call(product),
                  ),
                ),
              _buildProductImage(colorScheme),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      product.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    if (product.sku != null && product.sku!.isNotEmpty)
                      Text(
                        'SKU: ${product.sku!}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(
                          currencyService.format(product.priceCents.toBigInt().toInt()),
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        product.hasVariants
                            ? _buildVariantsIndicator(context)
                            : _buildStockIndicator(context),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVariantsIndicator(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            LucideIcons.layers,
            size: 14,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          Text(
            'products.variants_badge'.tr(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductImage(ColorScheme colorScheme) {
    final hasImage = product.imagePath != null && product.imagePath!.isNotEmpty;
    
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        image: hasImage
            ? DecorationImage(
                image: FileImage(File(product.imagePath!)),
                fit: BoxFit.cover,
                onError: (exception, stackTrace) {
                  // Fallback if image load fails
                },
              )
            : null,
      ),
      child: !hasImage
          ? Icon(
              LucideIcons.package,
              size: 32,
              color: colorScheme.onSurfaceVariant,
            )
          : null,
    );
  }

  Widget _buildStockIndicator(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (_isOutOfStock) {
      return Container(
        key: const Key('out_of_stock_indicator'),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.alertCircle,
              size: 14,
              color: colorScheme.onErrorContainer,
            ),
            const SizedBox(width: 4),
            Text(
              '0',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.onErrorContainer,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }

    if (_isLowStock) {
      return Container(
        key: const Key('low_stock_indicator'),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: colorScheme.tertiaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.alertTriangle,
              size: 14,
              color: colorScheme.onTertiaryContainer,
            ),
            const SizedBox(width: 4),
            Text(
              '${product.stockQuantity}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.onTertiaryContainer,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      key: const Key('normal_stock_indicator'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            LucideIcons.package,
            size: 14,
            color: colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: 4),
          Text(
            '${product.stockQuantity}',
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.onSecondaryContainer,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
