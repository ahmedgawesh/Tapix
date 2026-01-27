import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../../../core/bloc/realtime_bloc.dart';
import '../../domain/entities/product_variant_entity.dart';
import '../bloc/product_variants_bloc.dart';
import 'variant_edit_dialog.dart';

class VariantManagementWidget extends StatelessWidget {
  final int productId;

  const VariantManagementWidget({
    super.key,
    required this.productId,
  });

  @override
  Widget build(BuildContext context) {
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
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Text(
                        variant.sku?.isNotEmpty == true
                            ? variant.sku!
                            : 'product_form.variant_item_title'.tr(args: ['${variant.id}']),
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
  }

  void _confirmDelete(BuildContext context, ProductVariant variant) {
    final variantsBloc = context.read<ProductVariantsBloc>();
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('common.confirm'.tr()),
        content: Text('product_form.deleteVariantConfirm'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton(
            onPressed: () {
              variantsBloc.add(VariantDeleteRequested(variant.id));
              Navigator.pop(context);
            },
            child: Text('common.delete'.tr()),
          ),
        ],
      ),
    );
  }

  void _showVariantDialog(BuildContext context, {ProductVariant? variant}) {
    VariantEditDialog.show(
      context,
      productId: productId,
      variant: variant,
    );
  }
}
