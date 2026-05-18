import 'dart:io';

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../domain/entities/expiry_summary.dart';
import '../../domain/entities/product_entity.dart';
import '../../domain/entities/product_variant_entity.dart';
import '../../domain/entities/product_color_entity.dart';
import '../../domain/entities/size_entity.dart';
import '../../domain/repositories/product_variant_repository.dart';
import '../../domain/repositories/product_color_repository.dart';
import '../../domain/repositories/size_repository.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/services/currency_service.dart';
import '../../../../core/widgets/marquee_text.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/bloc/currency_bloc.dart';
import '../../../../core/bloc/realtime_bloc.dart';

class ProductTileWidget extends StatelessWidget {
  final Product product;
  final void Function(Product)? onTap;
  final void Function(Product)? onLongPress;
  final void Function(Product)? onCheckboxChanged;
  final bool? isSelected;
  
  /// For products with variants: number of variants and total stock across all variants.
  /// If provided, these override the product's stockQuantity for display purposes.
  final int? variantCount;
  final int? totalVariantStock;

  /// For product cards: preview of one variant's attributes (size + color shade)
  /// Displayed next to SKU as: SKU (Size ●)
  final String? previewSizeName;
  final String? previewColorHex;

  /// Optional batch-expiry health summary supplied by the parent list. When
  /// non-null and its derived status is [ExpiryStatus.nearExpiry] or
  /// [ExpiryStatus.expired], a yellow / red pill is rendered next to the
  /// stock indicator. Tile is intentionally data-driven: it never queries
  /// the database itself — Phase E will reuse the same primitive for the
  /// dashboard alert widget.
  final ExpirySummary? expirySummary;

  const ProductTileWidget({
    super.key,
    required this.product,
    this.onTap,
    this.onLongPress,
    this.onCheckboxChanged,
    this.isSelected,
    this.variantCount,
    this.totalVariantStock,
    this.previewSizeName,
    this.previewColorHex,
    this.expirySummary,
  });

  Color? _tryParseHexColor(String? hex) {
    if (hex == null) return null;
    final cleaned = hex.trim().replaceFirst('#', '');
    if (cleaned.isEmpty) return null;
    final buffer = StringBuffer();
    if (cleaned.length == 6) buffer.write('ff');
    buffer.write(cleaned);
    try {
      return Color(int.parse(buffer.toString(), radix: 16));
    } catch (_) {
      return null;
    }
  }

  Future<void> _showVariantsOverviewDialog(BuildContext context) async {
    final colorScheme = Theme.of(context).colorScheme;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: colorScheme.surface,
          title: Text(product.name),
          content: SizedBox(
            width: 520,
            child: FutureBuilder<({
              List<ProductVariant> variants,
              List<ProductColor> colors,
              List<Size> sizes,
            })>(
              future: () async {
                final variantRepo = sl<ProductVariantRepository>();
                final colorRepo = sl<ProductColorRepository>();
                final sizeRepo = sl<SizeRepository>();

                final results = await Future.wait([
                  variantRepo.getVariantsByProduct(product.id),
                  colorRepo.getAllColors(),
                  sizeRepo.getAllSizes(),
                ]);

                return (
                  variants: results[0] as List<ProductVariant>,
                  colors: results[1] as List<ProductColor>,
                  sizes: results[2] as List<Size>,
                );
              }(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const SizedBox(
                    height: 120,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                final variants = snapshot.data!.variants;
                final colorsById = {for (final c in snapshot.data!.colors) c.id: c};
                final sizesById = {for (final s in snapshot.data!.sizes) s.id: s};

                final distinctColorHexes = <String>{};
                final distinctSizeNames = <String>{};

                for (final v in variants.where((x) => x.isActive)) {
                  final colorHex = v.colorId == null ? null : colorsById[v.colorId!]?.hexCode;
                  if (colorHex != null && colorHex.trim().isNotEmpty) {
                    distinctColorHexes.add(colorHex.trim());
                  }
                  final sizeName = v.sizeId == null ? null : sizesById[v.sizeId!]?.name;
                  if (sizeName != null && sizeName.trim().isNotEmpty) {
                    distinctSizeNames.add(sizeName.trim());
                  }
                }

                final colorDots = distinctColorHexes
                    .map(_tryParseHexColor)
                    .whereType<Color>()
                    .toList();
                final sizeList = distinctSizeNames.toList()..sort();

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (variantCount != null)
                          Text(
                            '${'products.variants_badge'.tr()}: $variantCount',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        if (totalVariantStock != null) ...[
                          const SizedBox(width: 12),
                          Text(
                            '${'variants.stock'.tr()}: $totalVariantStock',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 12),

                    if (colorDots.isNotEmpty) ...[
                      Text(
                        'colors.title'.tr(),
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final c in colorDots)
                            Container(
                              width: 14,
                              height: 14,
                              decoration: BoxDecoration(
                                color: c,
                                shape: BoxShape.circle,
                                border: Border.all(color: colorScheme.outline),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],

                    if (sizeList.isNotEmpty) ...[
                      Text(
                        'sizes.title'.tr(),
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final s in sizeList)
                            Chip(
                              label: Text(
                                s,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],

                    Text(
                      'variants.title'.tr(),
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 220,
                      child: ListView.separated(
                        itemCount: variants.length,
                        separatorBuilder: (context, index) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final v = variants[index];
                          final sizeName = v.sizeId == null ? null : sizesById[v.sizeId!]?.name;
                          final colorHex = v.colorId == null ? null : colorsById[v.colorId!]?.hexCode;
                          final shade = _tryParseHexColor(colorHex);

                          final title = v.sku?.isNotEmpty == true
                              ? v.sku!
                              : 'product_form.variant_item_title'.tr(args: ['${v.id}']);

                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (sizeName != null && sizeName.trim().isNotEmpty)
                                  Text(sizeName, maxLines: 1, overflow: TextOverflow.ellipsis),
                                if (sizeName != null && sizeName.trim().isNotEmpty && shade != null)
                                  const SizedBox(width: 8),
                                if (shade != null)
                                  Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      color: shade,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: colorScheme.outline),
                                    ),
                                  ),
                                const Spacer(),
                                Text(
                                  '${'variants.stock'.tr()}: ${v.stockQuantity}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('common.close'.tr()),
            ),
          ],
        );
      },
    );
  }

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
    final previewShade = _tryParseHexColor(previewColorHex);
    final showVariantsButton = product.hasVariants;
    
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
                    onChanged: (_) => (onCheckboxChanged ?? onTap)?.call(product),
                  ),
                ),
              _buildProductImage(colorScheme),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            product.name,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (showVariantsButton)
                          IconButton(
                            icon: const Icon(LucideIcons.info, size: 18),
                            tooltip: 'variants.title'.tr(),
                            onPressed: () => _showVariantsOverviewDialog(context),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    if (product.sku != null && product.sku!.isNotEmpty)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              'SKU: ${product.sku!}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (!product.hasVariants &&
                              ((previewSizeName != null && previewSizeName!.trim().isNotEmpty) ||
                                  previewShade != null)) ...[
                            const SizedBox(width: 6),
                            Text(
                              '(',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            if (previewSizeName != null && previewSizeName!.trim().isNotEmpty)
                              Flexible(
                                child: Text(
                                  previewSizeName!.trim(),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            if (previewSizeName != null && previewSizeName!.trim().isNotEmpty && previewShade != null)
                              const SizedBox(width: 6),
                            if (previewShade != null)
                              Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: previewShade,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: colorScheme.outline),
                                ),
                              ),
                            Text(
                              ')',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        BlocBuilder<CurrencyBloc, RealtimeState<Currency>>(
                          builder: (context, state) {
                            return Text(
                              currencyService.format(product.priceCents.toBigInt().toInt()),
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: colorScheme.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            );
                          },
                        ),
                        const SizedBox(width: 8),
                        if (expirySummary != null) ...[
                          Flexible(
                            fit: FlexFit.loose,
                            child: _buildExpiryBadge(context),
                          ),
                          const SizedBox(width: 6),
                        ] else
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

    // Build display text: show variant count and/or total stock if available
    String displayText;
    if (variantCount != null && totalVariantStock != null) {
      displayText = '$variantCount × $totalVariantStock';
    } else if (variantCount != null) {
      displayText = '×$variantCount';
    } else {
      displayText = 'products.variants_badge'.tr();
    }

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
            displayText,
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

  /// Compact expiry pill rendered next to the stock indicator. Returns an
  /// empty `SizedBox` when the derived [ExpiryStatus] is `healthy` so the
  /// badge is essentially free for non-urgent rows.
  ///
  /// Visual semantics (matches Material's red/amber tonal slots so the badge
  /// reads correctly against both light and dark surfaces):
  ///   * `expired`    → `errorContainer` background, `alert-octagon` icon.
  ///   * `nearExpiry` → `tertiaryContainer` background (amber tone),
  ///                    `alert-triangle` icon, label = "X days left" or
  ///                    "Expires today".
  ///
  /// The full label is in the tooltip so the pill stays narrow on small
  /// screens — this is the same trade-off Odoo and Cin7 take in their list
  /// views.
  Widget _buildExpiryBadge(BuildContext context) {
    final summary = expirySummary;
    if (summary == null) return const SizedBox.shrink();
    final status = summary.statusFor();
    if (status == ExpiryStatus.healthy) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final isExpired = status == ExpiryStatus.expired;
    final bg =
        isExpired ? colorScheme.errorContainer : colorScheme.tertiaryContainer;
    final fg = isExpired
        ? colorScheme.onErrorContainer
        : colorScheme.onTertiaryContainer;
    final icon =
        isExpired ? LucideIcons.alertOctagon : LucideIcons.alertTriangle;

    final String shortLabel;
    final String tooltip;
    if (isExpired) {
      shortLabel = 'products.expiry_badge_expired_label'.tr();
      tooltip = 'products.expiry_badge_expired_qty'
          .tr(args: ['${summary.expiredQuantity}']);
    } else {
      final days = summary.daysUntilNearestExpiry ?? 0;
      if (days == 0) {
        shortLabel = 'products.expiry_badge_today'.tr();
      } else if (days == 1) {
        shortLabel = 'products.expiry_badge_days_left_one'.tr();
      } else {
        shortLabel =
            'products.expiry_badge_days_left_other'.tr(args: ['$days']);
      }
      tooltip = 'products.expiry_badge_near_label'.tr();
    }

    return Tooltip(
      message: tooltip,
      child: Container(
        key: Key(
          isExpired ? 'expiry_badge_expired' : 'expiry_badge_near',
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 4),
            Flexible(
              child: MarqueeText(
                text: shortLabel,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
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
