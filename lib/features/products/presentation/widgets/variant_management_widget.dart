import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../../../core/bloc/realtime_bloc.dart';
import '../../domain/entities/product_variant_entity.dart';
import '../bloc/product_variants_bloc.dart';
import '../bloc/colors_bloc.dart';
import '../bloc/sizes_bloc.dart';
import 'color_picker_widget.dart';
import 'size_selector_widget.dart';
import 'money_input_widget.dart';

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
    // Capture blocs from the current context before showing the dialog
    final colorsBloc = context.read<ColorsBloc>();
    final sizesBloc = context.read<SizesBloc>();
    final variantsBloc = context.read<ProductVariantsBloc>();

    showDialog<void>(
      context: context,
      builder: (context) => MultiBlocProvider(
        providers: [
          BlocProvider.value(value: colorsBloc),
          BlocProvider.value(value: sizesBloc),
          BlocProvider.value(value: variantsBloc),
        ],
        child: _VariantDialog(
          productId: productId,
          variant: variant,
        ),
      ),
    );
  }
}

class _VariantDialog extends StatefulWidget {
  final int productId;
  final ProductVariant? variant;

  const _VariantDialog({
    required this.productId,
    this.variant,
  });

  @override
  State<_VariantDialog> createState() => _VariantDialogState();
}

class _VariantDialogState extends State<_VariantDialog> {
  final _formKey = GlobalKey<FormState>();
  final _skuController = TextEditingController();
  final _barcodeController = TextEditingController();
  final _stockController = TextEditingController();
  
  int? _colorId;
  int? _sizeId;
  Decimal _costCents = Decimal.zero;
  Decimal _priceCents = Decimal.zero;

  @override
  void initState() {
    super.initState();
    if (widget.variant != null) {
      final v = widget.variant!;
      _skuController.text = v.sku ?? '';
      _barcodeController.text = v.barcode ?? '';
      _stockController.text = v.stockQuantity.toString();
      _colorId = v.colorId;
      _sizeId = v.sizeId;
      _costCents = v.costCents;
      _priceCents = v.priceCents;
    } else {
      _stockController.text = '0';
    }
  }

  @override
  void dispose() {
    _skuController.dispose();
    _barcodeController.dispose();
    _stockController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final dialogWidth = constraints.maxWidth >= 560 ? 560.0 : constraints.maxWidth;
        final isNarrow = dialogWidth < 480;

        return AlertDialog(
          title: Text(
            widget.variant == null ? 'product_form.addVariant'.tr() : 'product_form.editVariant'.tr(),
          ),
          content: SizedBox(
            width: dialogWidth,
            child: SingleChildScrollView(
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isNarrow)
                      Column(
                        children: [
                          ColorPickerWidget(
                            selectedColorId: _colorId,
                            onColorSelected: (id) => setState(() => _colorId = id),
                          ),
                          const SizedBox(height: 16),
                          SizeSelectorWidget(
                            selectedSizeId: _sizeId,
                            onSizeSelected: (id) => setState(() => _sizeId = id),
                          ),
                        ],
                      )
                    else
                      Row(
                        children: [
                          Expanded(
                            child: ColorPickerWidget(
                              selectedColorId: _colorId,
                              onColorSelected: (id) => setState(() => _colorId = id),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: SizeSelectorWidget(
                              selectedSizeId: _sizeId,
                              onSizeSelected: (id) => setState(() => _sizeId = id),
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _skuController,
                      decoration: InputDecoration(
                        labelText: 'product_form.variantSku'.tr(),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _barcodeController,
                      decoration: InputDecoration(
                        labelText: 'product_form.variantBarcode'.tr(),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        SizedBox(
                          width: isNarrow ? dialogWidth : (dialogWidth - 16) / 2,
                          child: MoneyInputWidget(
                            value: _costCents,
                            label: 'product_form.cost'.tr(),
                            onChanged: (value) => setState(() => _costCents = value),
                          ),
                        ),
                        SizedBox(
                          width: isNarrow ? dialogWidth : (dialogWidth - 16) / 2,
                          child: MoneyInputWidget(
                            value: _priceCents,
                            label: 'product_form.price'.tr(),
                            onChanged: (value) => setState(() => _priceCents = value),
                          ),
                        ),
                        SizedBox(
                          width: dialogWidth,
                          child: TextFormField(
                            controller: _stockController,
                            decoration: InputDecoration(
                              labelText: 'product_form.quantity'.tr(),
                              border: const OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'common.required'.tr();
                              }
                              if (int.tryParse(value) == null) {
                                return 'common.invalidNumber'.tr();
                              }
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('common.cancel'.tr()),
            ),
            FilledButton(
              onPressed: _submit,
              child: Text('common.save'.tr()),
            ),
          ],
        );
      },
    );
  }

  void _submit() {
    if (_formKey.currentState?.validate() ?? false) {
      final stock = int.parse(_stockController.text);
      
      if (widget.variant != null) {
        final updatedVariant = ProductVariant(
          id: widget.variant!.id,
          productId: widget.productId,
          sku: _skuController.text.isEmpty ? null : _skuController.text,
          barcode: _barcodeController.text.isEmpty ? null : _barcodeController.text,
          colorId: _colorId,
          sizeId: _sizeId,
          costCents: _costCents,
          priceCents: _priceCents,
          priceAdjustmentCents: widget.variant!.priceAdjustmentCents,
          stockQuantity: stock,
          isActive: widget.variant!.isActive,
        );
        context.read<ProductVariantsBloc>().add(VariantUpdateRequested(updatedVariant));
      } else {
        context.read<ProductVariantsBloc>().add(VariantCreateRequested(
          productId: widget.productId,
          sku: _skuController.text.isEmpty ? null : _skuController.text,
          barcode: _barcodeController.text.isEmpty ? null : _barcodeController.text,
          colorId: _colorId,
          sizeId: _sizeId,
          costCents: _costCents,
          priceCents: _priceCents,
          stockQuantity: stock,
        ));
      }
      Navigator.pop(context);
    }
  }
}
