import 'package:decimal/decimal.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/bloc/currency_bloc.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/services/currency_service.dart';
import '../../../barcode/services/barcode_validation_service.dart';
import '../../domain/entities/category_entity.dart';
import '../../domain/entities/product_color_entity.dart';
import '../../domain/entities/size_entity.dart';
import '../bloc/bulk_product_bloc.dart';
import '../bloc/categories_bloc.dart';
import '../bloc/categories_event.dart';
import '../bloc/colors_bloc.dart';
import '../bloc/colors_event.dart';
import '../bloc/sizes_bloc.dart';
import '../bloc/sizes_event.dart';

class BulkProductRow extends StatefulWidget {
  final BulkProductRowData rowData;
  final List<String>? errors;
  final bool isDesktop;
  final bool isTablet;
  final bool canRemove;
  final void Function(Map<String, dynamic> updates) onUpdate;
  final VoidCallback onRemove;

  const BulkProductRow({
    super.key,
    required this.rowData,
    this.errors,
    required this.isDesktop,
    required this.isTablet,
    required this.canRemove,
    required this.onUpdate,
    required this.onRemove,
  });

  @override
  State<BulkProductRow> createState() => _BulkProductRowState();
}

class _BulkProductRowState extends State<BulkProductRow> {
  late TextEditingController _nameController;
  late TextEditingController _skuController;
  late TextEditingController _barcodeController;
  late TextEditingController _costController;
  late TextEditingController _priceController;
  late TextEditingController _wholesalePriceController;
  late TextEditingController _stockController;
  late TextEditingController _minStockController;

  bool _isExpanded = true;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.rowData.name);
    _skuController = TextEditingController(text: widget.rowData.sku ?? '');
    _barcodeController = TextEditingController(text: widget.rowData.barcode ?? '');
    _costController = TextEditingController(
      text: widget.rowData.costCents == Decimal.zero 
          ? '' 
          : _formatDecimal(widget.rowData.costCents),
    );
    _priceController = TextEditingController(
      text: widget.rowData.priceCents == Decimal.zero 
          ? '' 
          : _formatDecimal(widget.rowData.priceCents),
    );
    _wholesalePriceController = TextEditingController(
      text: widget.rowData.wholesalePriceCents == null 
          ? '' 
          : _formatDecimal(widget.rowData.wholesalePriceCents!),
    );
    _stockController = TextEditingController(
      text: widget.rowData.stockQuantity.toString(),
    );
    _minStockController = TextEditingController(
      text: widget.rowData.minQuantity.toString(),
    );
  }

  String _formatDecimal(Decimal value) {
    final result = value / Decimal.fromInt(100);
    return result.toDecimal().toStringAsFixed(2);
  }

  Decimal _parseDecimal(String value) {
    if (value.isEmpty) return Decimal.zero;
    try {
      final parsed = Decimal.parse(value);
      return parsed * Decimal.fromInt(100);
    } catch (_) {
      return Decimal.zero;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _skuController.dispose();
    _barcodeController.dispose();
    _costController.dispose();
    _priceController.dispose();
    _wholesalePriceController.dispose();
    _stockController.dispose();
    _minStockController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasErrors = widget.errors != null && widget.errors!.isNotEmpty;

    return Card(
      elevation: hasErrors ? 2 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: hasErrors ? colorScheme.error : colorScheme.outlineVariant,
          width: hasErrors ? 2 : 1,
        ),
      ),
      child: Column(
        children: [
          _buildHeader(context, hasErrors),
          if (_isExpanded) _buildContent(context),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, bool hasErrors) {
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: () {
        setState(() {
          _isExpanded = !_isExpanded;
        });
      },
      borderRadius: BorderRadius.vertical(
        top: const Radius.circular(12),
        bottom: _isExpanded ? Radius.zero : const Radius.circular(12),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: hasErrors 
              ? colorScheme.errorContainer.withValues(alpha: 0.3) 
              : colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.vertical(
            top: const Radius.circular(12),
            bottom: _isExpanded ? Radius.zero : const Radius.circular(12),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: hasErrors ? colorScheme.error : colorScheme.primary,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  '${widget.rowData.rowIndex + 1}',
                  style: TextStyle(
                    color: hasErrors 
                        ? colorScheme.onError 
                        : colorScheme.onPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.rowData.name.isEmpty
                        ? 'bulk_product.new_product'.tr()
                        : widget.rowData.name,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (widget.rowData.sku != null && widget.rowData.sku!.isNotEmpty)
                    Text(
                      widget.rowData.sku!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                    ),
                ],
              ),
            ),
            if (hasErrors)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Icon(
                  Icons.error_outline,
                  color: colorScheme.error,
                  size: 20,
                ),
              ),
            if (widget.canRemove)
              IconButton(
                icon: Icon(Icons.delete_outline, color: colorScheme.error),
                onPressed: widget.onRemove,
                tooltip: 'common.delete'.tr(),
              ),
            Icon(
              _isExpanded ? Icons.expand_less : Icons.expand_more,
              color: colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (widget.isDesktop) {
      return _buildDesktopContent(context);
    } else if (widget.isTablet) {
      return _buildTabletContent(context);
    } else {
      return _buildMobileContent(context);
    }
  }

  Widget _buildDesktopContent(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildNameField(context),
          const SizedBox(height: 16),
          // Row 2: SKU, Barcode, Category
          Row(
            children: [
              Expanded(child: _buildSkuField(context)),
              const SizedBox(width: 16),
              Expanded(child: _buildBarcodeField(context)),
              const SizedBox(width: 16),
              Expanded(child: _buildCategoryPicker(context)),
            ],
          ),
          const SizedBox(height: 16),
          // Row 3: Prices
          Row(
            children: [
              Expanded(child: _buildCostField(context)),
              const SizedBox(width: 16),
              Expanded(child: _buildPriceField(context)),
              const SizedBox(width: 16),
              Expanded(child: _buildWholesalePriceField(context)),
            ],
          ),
          const SizedBox(height: 16),
          // Row 4: Stock
          Row(
            children: [
              Expanded(child: _buildStockField(context)),
              const SizedBox(width: 16),
              Expanded(child: _buildMinStockField(context)),
              const SizedBox(width: 16),
              Expanded(child: _buildColorPicker(context)),
              const SizedBox(width: 16),
              Expanded(child: _buildSizePicker(context)),
            ],
          ),
          if (widget.errors != null && widget.errors!.isNotEmpty)
            _buildErrorMessages(context),
        ],
      ),
    );
  }

  Widget _buildTabletContent(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildNameField(context),
          const SizedBox(height: 16),
          // Row 2: SKU, Barcode
          Row(
            children: [
              Expanded(child: _buildSkuField(context)),
              const SizedBox(width: 16),
              Expanded(child: _buildBarcodeField(context)),
            ],
          ),
          const SizedBox(height: 16),
          _buildCategoryPicker(context),
          const SizedBox(height: 16),
          // Row 3: Prices
          Row(
            children: [
              Expanded(child: _buildCostField(context)),
              const SizedBox(width: 16),
              Expanded(child: _buildPriceField(context)),
              const SizedBox(width: 16),
              Expanded(child: _buildWholesalePriceField(context)),
            ],
          ),
          const SizedBox(height: 16),
          // Row 4: Stock and variants
          Row(
            children: [
              Expanded(child: _buildStockField(context)),
              const SizedBox(width: 16),
              Expanded(child: _buildMinStockField(context)),
            ],
          ),
          const SizedBox(height: 16),
          // Row 5: Color, Size
          Row(
            children: [
              Expanded(child: _buildColorPicker(context)),
              const SizedBox(width: 16),
              Expanded(child: _buildSizePicker(context)),
            ],
          ),
          if (widget.errors != null && widget.errors!.isNotEmpty)
            _buildErrorMessages(context),
        ],
      ),
    );
  }

  Widget _buildMobileContent(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildNameField(context),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _buildSkuField(context)),
              const SizedBox(width: 16),
              Expanded(child: _buildBarcodeField(context)),
            ],
          ),
          const SizedBox(height: 16),
          _buildCategoryPicker(context),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _buildCostField(context)),
              const SizedBox(width: 16),
              Expanded(child: _buildPriceField(context)),
            ],
          ),
          const SizedBox(height: 16),
          _buildWholesalePriceField(context),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _buildStockField(context)),
              const SizedBox(width: 16),
              Expanded(child: _buildMinStockField(context)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _buildColorPicker(context)),
              const SizedBox(width: 16),
              Expanded(child: _buildSizePicker(context)),
            ],
          ),
          if (widget.errors != null && widget.errors!.isNotEmpty)
            _buildErrorMessages(context),
        ],
      ),
    );
  }

  Widget _buildNameField(BuildContext context) {
    final hasError = widget.errors?.contains('name_required') ?? false;
    return TextFormField(
      controller: _nameController,
      decoration: InputDecoration(
        labelText: 'product_form.name'.tr(),
        hintText: 'product_form.name'.tr(),
        errorText: hasError ? 'product_form.required'.tr() : null,
        border: const OutlineInputBorder(),
      ),
      onChanged: (value) {
        widget.onUpdate({'name': value});
      },
    );
  }

  Widget _buildSkuField(BuildContext context) {
    final hasError = widget.errors?.contains('sku_duplicate') ?? false;
    return TextFormField(
      controller: _skuController,
      decoration: InputDecoration(
        labelText: 'product_form.sku'.tr(),
        hintText: 'product_form.sku'.tr(),
        errorText: hasError ? 'bulk_product.sku_duplicate'.tr() : null,
        border: const OutlineInputBorder(),
      ),
      onChanged: (value) {
        widget.onUpdate({'sku': value});
      },
    );
  }

  Widget _buildBarcodeField(BuildContext context) {
    return TextFormField(
      controller: _barcodeController,
      decoration: InputDecoration(
        labelText: 'product_form.barcode'.tr(),
        hintText: 'product_form.barcode'.tr(),
        border: const OutlineInputBorder(),
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.auto_awesome),
              onPressed: _generateBarcode,
              tooltip: 'barcode.auto_generate'.tr(),
            ),
          ],
        ),
      ),
      onChanged: (value) {
        widget.onUpdate({'barcode': value});
      },
    );
  }

  void _generateBarcode() {
    // Generate EAN-13 barcode with valid checksum
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final rowIndex = widget.rowData.rowIndex;
    
    // Create a 12-digit base (EAN-13 without checksum)
    // Format: 200 (internal use prefix) + timestamp last 6 digits + row index padded + random
    final base = '200${(timestamp % 1000000).toString().padLeft(6, '0')}${(rowIndex % 1000).toString().padLeft(3, '0')}';
    
    // Calculate EAN-13 checksum
    final barcodeService = BarcodeValidationService();
    final checksum = barcodeService.calculateEan13Checksum(base);
    final barcode = '$base$checksum';
    
    _barcodeController.text = barcode;
    widget.onUpdate({'barcode': barcode});
  }

  Widget _buildCostField(BuildContext context) {
    final hasError = widget.errors?.contains('cost_invalid') ?? false;
    return TextFormField(
      controller: _costController,
      decoration: InputDecoration(
        labelText: 'product_form.cost'.tr(),
        hintText: '0.00',
        errorText: hasError ? 'product_form.invalidNumber'.tr() : null,
        border: const OutlineInputBorder(),
        prefixText: _getCurrencySymbol(context),
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
      ],
      onTap: () {
        if (_costController.text == '0.00' || _costController.text == '0') {
          _costController.clear();
        }
      },
      onChanged: (value) {
        widget.onUpdate({'costCents': _parseDecimal(value)});
      },
    );
  }

  Widget _buildPriceField(BuildContext context) {
    final hasError = widget.errors?.contains('price_required') ?? false;
    return TextFormField(
      controller: _priceController,
      decoration: InputDecoration(
        labelText: 'product_form.price'.tr(),
        hintText: '0.00',
        errorText: hasError ? 'product_form.required'.tr() : null,
        border: const OutlineInputBorder(),
        prefixText: _getCurrencySymbol(context),
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
      ],
      onTap: () {
        if (_priceController.text == '0.00' || _priceController.text == '0') {
          _priceController.clear();
        }
      },
      onChanged: (value) {
        widget.onUpdate({'priceCents': _parseDecimal(value)});
      },
    );
  }

  Widget _buildWholesalePriceField(BuildContext context) {
    return TextFormField(
      controller: _wholesalePriceController,
      decoration: InputDecoration(
        labelText: 'product_form.wholesalePrice'.tr(),
        hintText: '0.00',
        border: const OutlineInputBorder(),
        prefixText: _getCurrencySymbol(context),
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
      ],
      onTap: () {
        if (_wholesalePriceController.text == '0.00' || 
            _wholesalePriceController.text == '0') {
          _wholesalePriceController.clear();
        }
      },
      onChanged: (value) {
        widget.onUpdate({'wholesalePriceCents': _parseDecimal(value)});
      },
    );
  }

  Widget _buildStockField(BuildContext context) {
    return TextFormField(
      controller: _stockController,
      decoration: InputDecoration(
        labelText: 'product_form.quantity'.tr(),
        hintText: '0',
        border: const OutlineInputBorder(),
      ),
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
      ],
      onTap: () {
        if (_stockController.text == '0') {
          _stockController.clear();
        }
      },
      onChanged: (value) {
        widget.onUpdate({'stockQuantity': int.tryParse(value) ?? 0});
      },
    );
  }

  Widget _buildMinStockField(BuildContext context) {
    return TextFormField(
      controller: _minStockController,
      decoration: InputDecoration(
        labelText: 'product_form.minQuantity'.tr(),
        hintText: '0',
        border: const OutlineInputBorder(),
      ),
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
      ],
      onTap: () {
        if (_minStockController.text == '0') {
          _minStockController.clear();
        }
      },
      onChanged: (value) {
        widget.onUpdate({'minQuantity': int.tryParse(value) ?? 0});
      },
    );
  }

  Widget _buildCategoryPicker(BuildContext context) {
    return BlocBuilder<CategoriesBloc, RealtimeState<List<Category>>>(
      builder: (context, state) {
        final categories = state is RealtimeSuccess<List<Category>> ? state.data : <Category>[];
        final selected = widget.rowData.categoryId == null
            ? null
            : categories.cast<Category?>().firstWhere(
                  (c) => c?.id == widget.rowData.categoryId,
                  orElse: () => null,
                );

        return InkWell(
          onTap: () => _showCategoryPickerBottomSheet(context),
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: 'product_form.category'.tr(),
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.category_outlined),
            ),
            child: Text(selected?.name ?? 'common.none'.tr()),
          ),
        );
      },
    );
  }

  Future<void> _showCategoryPickerBottomSheet(BuildContext context) async {
    final categoriesBloc = context.read<CategoriesBloc>();
    final selectedId = await showModalBottomSheet<int?>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: false,
      builder: (sheetContext) {
        return BlocProvider.value(
          value: categoriesBloc,
          child: SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 12,
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 12,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    decoration: InputDecoration(
                      hintText: 'categories.search_hint'.tr(),
                      prefixIcon: const Icon(Icons.search),
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (v) => categoriesBloc.add(SearchCategories(v)),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      onPressed: () => sheetContext.push('/products/categories'),
                      icon: const Icon(Icons.settings),
                      label: Text('categories.title'.tr()),
                    ),
                  ),
                  Flexible(
                    child: BlocBuilder<CategoriesBloc, RealtimeState<List<Category>>>(
                      bloc: categoriesBloc,
                      builder: (context, state) {
                        final categories = state is RealtimeSuccess<List<Category>> ? state.data : <Category>[];
                        return ListView.builder(
                          shrinkWrap: true,
                          itemCount: categories.length + 1,
                          itemBuilder: (context, index) {
                            if (index == 0) {
                              return ListTile(
                                title: Text('common.none'.tr()),
                                onTap: () => Navigator.of(context).pop(null),
                              );
                            }
                            final cat = categories[index - 1];
                            return ListTile(
                              title: Text(cat.name),
                              onTap: () => Navigator.of(context).pop(cat.id),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (!mounted) return;

    categoriesBloc.add(const LoadCategories());
    if (selectedId != null || widget.rowData.categoryId != null) {
      widget.onUpdate({'categoryId': selectedId});
    }
  }

  Widget _buildColorPicker(BuildContext context) {
    return BlocBuilder<ColorsBloc, RealtimeState<List<ProductColor>>>(
      builder: (context, state) {
        final colors = state is RealtimeSuccess<List<ProductColor>> ? state.data : <ProductColor>[];
        final selected = widget.rowData.colorId == null
            ? null
            : colors.cast<ProductColor?>().firstWhere(
                  (c) => c?.id == widget.rowData.colorId,
                  orElse: () => null,
                );

        return InkWell(
          onTap: () => _showColorPickerBottomSheet(context),
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: 'product_form.variantColor'.tr(),
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.palette_outlined),
            ),
            child: selected == null
                ? Text('common.none'.tr())
                : Row(
                    children: [
                      Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: _tryParseHexColor(selected.hexCode) ?? Colors.grey,
                          shape: BoxShape.circle,
                          border: Border.all(color: Theme.of(context).colorScheme.outline),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(selected.name)),
                    ],
                  ),
          ),
        );
      },
    );
  }

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

  Future<void> _showColorPickerBottomSheet(BuildContext context) async {
    final colorsBloc = context.read<ColorsBloc>();
    final selectedId = await showModalBottomSheet<int?>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: false,
      builder: (sheetContext) {
        return BlocProvider.value(
          value: colorsBloc,
          child: SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 12,
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 12,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    decoration: InputDecoration(
                      hintText: 'colors.search_hint'.tr(),
                      prefixIcon: const Icon(Icons.search),
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (v) => colorsBloc.add(SearchColors(v)),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      onPressed: () => sheetContext.push('/products/colors'),
                      icon: const Icon(Icons.settings),
                      label: Text('manage_colors'.tr()),
                    ),
                  ),
                  Flexible(
                    child: BlocBuilder<ColorsBloc, RealtimeState<List<ProductColor>>>(
                      bloc: colorsBloc,
                      builder: (context, state) {
                        final colors = state is RealtimeSuccess<List<ProductColor>> ? state.data : <ProductColor>[];
                        return ListView.builder(
                          shrinkWrap: true,
                          itemCount: colors.length + 1,
                          itemBuilder: (context, index) {
                            if (index == 0) {
                              return ListTile(
                                title: Text('common.none'.tr()),
                                onTap: () => Navigator.of(context).pop(null),
                              );
                            }
                            final color = colors[index - 1];
                            return ListTile(
                              leading: Container(
                                width: 18,
                                height: 18,
                                decoration: BoxDecoration(
                                  color: _tryParseHexColor(color.hexCode) ?? Colors.grey,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Theme.of(context).colorScheme.outline),
                                ),
                              ),
                              title: Text(color.name),
                              onTap: () => Navigator.of(context).pop(color.id),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (!mounted) return;

    colorsBloc.add(const LoadColors());
    if (selectedId != null || widget.rowData.colorId != null) {
      widget.onUpdate({'colorId': selectedId});
    }
  }

  Widget _buildSizePicker(BuildContext context) {
    return BlocBuilder<SizesBloc, RealtimeState<List<Size>>>(
      builder: (context, state) {
        final sizes = state is RealtimeSuccess<List<Size>> ? state.data : <Size>[];
        final selected = widget.rowData.sizeId == null
            ? null
            : sizes.cast<Size?>().firstWhere(
                  (s) => s?.id == widget.rowData.sizeId,
                  orElse: () => null,
                );

        return InkWell(
          onTap: () => _showSizePickerBottomSheet(context),
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: 'product_form.variantSize'.tr(),
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.straighten_outlined),
            ),
            child: Text(selected?.name ?? 'common.none'.tr()),
          ),
        );
      },
    );
  }

  Future<void> _showSizePickerBottomSheet(BuildContext context) async {
    final sizesBloc = context.read<SizesBloc>();
    final selectedId = await showModalBottomSheet<int?>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: false,
      builder: (sheetContext) {
        return BlocProvider.value(
          value: sizesBloc,
          child: SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 12,
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 12,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    decoration: InputDecoration(
                      hintText: 'sizes.search_hint'.tr(),
                      prefixIcon: const Icon(Icons.search),
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (v) => sizesBloc.add(SearchSizes(v)),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      onPressed: () => sheetContext.push('/products/sizes'),
                      icon: const Icon(Icons.settings),
                      label: Text('manage_sizes'.tr()),
                    ),
                  ),
                  Flexible(
                    child: BlocBuilder<SizesBloc, RealtimeState<List<Size>>>(
                      bloc: sizesBloc,
                      builder: (context, state) {
                        final sizes = state is RealtimeSuccess<List<Size>> ? state.data : <Size>[];
                        return ListView.builder(
                          shrinkWrap: true,
                          itemCount: sizes.length + 1,
                          itemBuilder: (context, index) {
                            if (index == 0) {
                              return ListTile(
                                title: Text('common.none'.tr()),
                                onTap: () => Navigator.of(context).pop(null),
                              );
                            }
                            final size = sizes[index - 1];
                            return ListTile(
                              title: Text(size.name),
                              onTap: () => Navigator.of(context).pop(size.id),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (!mounted) return;

    sizesBloc.add(const LoadSizes());
    if (selectedId != null || widget.rowData.sizeId != null) {
      widget.onUpdate({'sizeId': selectedId});
    }
  }

  Widget _buildErrorMessages(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colorScheme.errorContainer.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colorScheme.error.withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: colorScheme.error, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.errors!.map((e) => _getErrorMessage(e)).join(', '),
                style: TextStyle(color: colorScheme.error),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getErrorMessage(String errorCode) {
    switch (errorCode) {
      case 'name_required':
        return 'bulk_product.error_name_required'.tr();
      case 'price_required':
        return 'bulk_product.error_price_required'.tr();
      case 'cost_invalid':
        return 'bulk_product.error_cost_invalid'.tr();
      case 'sku_duplicate':
        return 'bulk_product.sku_duplicate'.tr();
      default:
        return errorCode;
    }
  }

  String _getCurrencySymbol(BuildContext context) {
    try {
      final currencyState = context.watch<CurrencyBloc>().state;
      if (currencyState is RealtimeSuccess<Currency>) {
        return '${currencyState.data.symbol} ';
      }
    } catch (e) {
      debugPrint('CurrencyBloc not available in context: $e');
    }
    // Return empty string if CurrencyBloc not available - prefix will be hidden
    return '';
  }
}
