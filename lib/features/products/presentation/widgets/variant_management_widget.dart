import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/di/injection_container.dart';
import '../../domain/entities/product_variant_entity.dart';
import '../../domain/entities/product_color_entity.dart';
import '../../domain/entities/size_entity.dart';
import '../../domain/repositories/product_variant_repository.dart';
import '../bloc/product_variants_bloc.dart';
import '../bloc/colors_bloc.dart';
import '../bloc/sizes_bloc.dart';
import 'variant_edit_dialog.dart';

class VariantManagementWidget extends StatelessWidget {
  final int productId;

  const VariantManagementWidget({
    super.key,
    required this.productId,
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

  Widget _buildSkuWithAttributes({
    required String skuText,
    required String? sizeName,
    required String? colorHex,
    required ColorScheme colorScheme,
    TextStyle? style,
  }) {
    final showSize = sizeName != null && sizeName.trim().isNotEmpty;
    final shade = _tryParseHexColor(colorHex);
    final showShade = shade != null;

    if (!showSize && !showShade) {
      return Text(
        skuText,
        style: style,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            skuText,
            style: style,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 6),
        Text('(', style: style),
        if (showSize)
          Flexible(
            child: Text(
              sizeName,
              style: style,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        if (showSize && showShade) const SizedBox(width: 6),
        if (showShade)
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: shade,
              shape: BoxShape.circle,
              border: Border.all(color: colorScheme.outline),
            ),
          ),
        Text(')', style: style),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textStyle = Theme.of(context).textTheme.titleSmall;

    return BlocBuilder<ColorsBloc, RealtimeState<List<ProductColor>>>(
      builder: (context, colorsState) {
        final colors = colorsState is RealtimeSuccess<List<ProductColor>>
            ? colorsState.data
            : colorsState is RealtimeLoading<List<ProductColor>>
                ? colorsState.previousData ?? const <ProductColor>[]
                : const <ProductColor>[];
        final colorById = {for (final c in colors) c.id: c};

        return BlocBuilder<SizesBloc, RealtimeState<List<Size>>>(
          builder: (context, sizesState) {
            final sizes = sizesState is RealtimeSuccess<List<Size>>
                ? sizesState.data
                : sizesState is RealtimeLoading<List<Size>>
                    ? sizesState.previousData ?? const <Size>[]
                    : const <Size>[];
            final sizeNameById = {for (final s in sizes) s.id: s.name};

            return BlocBuilder<ProductVariantsBloc, RealtimeState<List<ProductVariant>>>(
              builder: (context, state) {
                List<ProductVariant>? variants;
                if (state is RealtimeSuccess<List<ProductVariant>>) {
                  variants = state.data;
                } else if (state is RealtimeLoading<List<ProductVariant>>) {
                  variants = state.previousData;
                } else if (state is RealtimeError<List<ProductVariant>>) {
                  variants = state.previousData;
                } else if (state is RealtimeOptimistic<List<ProductVariant>>) {
                  variants = state.optimisticData;
                }

                if (state is RealtimeLoading<List<ProductVariant>> && variants == null) {
                  return const Center(child: CircularProgressIndicator());
                }

                final displayVariants = variants ?? <ProductVariant>[];

                return Column(
                  children: [
                    if (displayVariants.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        child: Column(
                          children: [
                            const Icon(LucideIcons.layers, size: 48, color: Colors.grey),
                            const SizedBox(height: 8),
                            Text('product_form.noVariants'.tr()),
                            const SizedBox(height: 16),
                          ],
                        ),
                      )
                    else
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: displayVariants.length,
                        itemBuilder: (context, index) {
                          final variant = displayVariants[index];
                          final sizeName = variant.sizeId == null ? null : sizeNameById[variant.sizeId!];
                          final colorHex = variant.colorId == null ? null : colorById[variant.colorId!]?.hexCode;
                          final skuText = variant.sku?.isNotEmpty == true
                              ? variant.sku!
                              : 'product_form.variant_item_title'.tr(args: ['${variant.id}']);

                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              title: _buildSkuWithAttributes(
                                skuText: skuText,
                                sizeName: sizeName,
                                colorHex: colorHex,
                                colorScheme: colorScheme,
                                style: textStyle,
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'product_form.variant_item_stock'.tr(args: ['${variant.stockQuantity}']),
                                  ),
                                  if (variant.barcode?.isNotEmpty == true)
                                    Text(
                                      'product_form.variant_item_barcode'.tr(args: [variant.barcode!]),
                                    ),
                                ],
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(LucideIcons.edit),
                                    onPressed: () => _showVariantDialog(context, variant: variant),
                                  ),
                                  IconButton(
                                    icon: const Icon(LucideIcons.trash2),
                                    onPressed: () => _confirmDelete(context, variant),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () => _showVariantDialog(context),
                      icon: const Icon(LucideIcons.plus),
                      label: Text('product_form.addVariant'.tr()),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  /// Smart-delete entry point for a single variant. The dialog branches on
  /// two orthogonal axes — stock-on-hand and historical references — so the
  /// outcome stays consistent with QuickBooks/Xero/Odoo and never lets the
  /// 1200 Inventory ledger drift away from Σ(stock × cost):
  ///
  ///   refCount=0, stock=0 → hard delete (no GL impact)
  ///   refCount>0, stock=0 → deactivate     (preserve audit trail)
  ///   stock>0             → write-off + delete: post a Shrinkage entry
  ///                         (Dr 5800 / Cr 1200) for the on-hand value,
  ///                         then hard-delete or deactivate based on refs.
  Future<void> _confirmDelete(BuildContext context, ProductVariant variant) async {
    final variantsBloc = context.read<ProductVariantsBloc>();
    final repo = sl<ProductVariantRepository>();
    final colorScheme = Theme.of(context).colorScheme;

    int refCount;
    try {
      refCount = await repo.countVariantReferences(variant.id);
    } catch (_) {
      // If the count fails for any reason, fall through with refCount = -1
      // which we treat as "may have refs" so we never hard-delete by mistake.
      refCount = -1;
    }
    if (!context.mounted) return;

    final stock = variant.stockQuantity;
    final hasStock = stock > 0;
    final willDeactivate = refCount != 0; // 0 = safe; >0 or -1 (unknown) = soft

    // Branch 1: stock>0 → mandatory shrinkage write-off before delete.
    if (hasStock) {
      final body = willDeactivate
          ? (refCount > 0
              ? 'product_form.variant_writeoff_deactivate_body'
                  .tr(args: [stock.toString(), refCount.toString()])
              : 'product_form.variant_writeoff_deactivate_body_unknown'
                  .tr(args: [stock.toString()]))
          : 'product_form.variant_writeoff_delete_body'
              .tr(args: [stock.toString()]);
      final actionLabel = 'product_form.variant_writeoff_action'.tr();

      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: Icon(LucideIcons.alertTriangle, color: colorScheme.error),
          title: Text('product_form.variant_writeoff_title'.tr()),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('common.cancel'.tr()),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: colorScheme.error,
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(actionLabel),
            ),
          ],
        ),
      );
      if (ok != true || !context.mounted) return;
      variantsBloc.add(VariantWriteOffAndDeleteRequested(
        variantId: variant.id,
        reason: 'product_form.variant_writeoff_reason'.tr(),
      ));
      return;
    }

    // Branch 2: stock=0 → original smart-delete flow.
    final title = willDeactivate
        ? 'product_form.variant_deactivate_title'.tr()
        : 'product_form.variant_delete_title'.tr();
    final body = willDeactivate
        ? (refCount > 0
            ? 'product_form.variant_deactivate_body'.tr(args: [refCount.toString()])
            : 'product_form.variant_deactivate_body_unknown'.tr())
        : 'product_form.variant_delete_body'.tr();
    final actionLabel = willDeactivate
        ? 'product_form.variant_deactivate_action'.tr()
        : 'common.delete'.tr();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(
          willDeactivate ? LucideIcons.archive : LucideIcons.trash2,
          color: willDeactivate ? colorScheme.tertiary : colorScheme.error,
        ),
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor:
                  willDeactivate ? colorScheme.tertiary : colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(actionLabel),
          ),
        ],
      ),
    );

    if (ok != true || !context.mounted) return;
    variantsBloc.add(VariantDeleteRequested(variant.id));
  }

  void _showVariantDialog(BuildContext context, {ProductVariant? variant}) {
    VariantEditDialog.show(
      context,
      productId: productId,
      variant: variant,
    );
  }
}
