import 'package:decimal/decimal.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/bloc/currency_bloc.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/services/currency_service.dart';
import '../../../barcode/services/barcode_validation_service.dart';
import '../../domain/entities/product_color_entity.dart';
import '../../domain/entities/size_entity.dart';
import '../bloc/bulk_product_bloc.dart';
import '../bloc/colors_bloc.dart';
import '../bloc/sizes_bloc.dart';

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
  late TextEditingController _nameArController;
  late TextEditingController _nameFrController;
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
    _nameArController = TextEditingController(text: widget.rowData.nameAr ?? '');
    _nameFrController = TextEditingController(text: widget.rowData.nameFr ?? '');
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
    _nameArController.dispose();
    _nameFrController.dispose();
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
          // Row 1: Names
          Row(
            children: [
              Expanded(child: _buildNameField(context)),
              const SizedBox(width: 16),
              Expanded(child: _buildNameArField(context)),
              const SizedBox(width: 16),
              Expanded(child: _buildNameFrField(context)),
            ],
          ),
          const SizedBox(height: 16),
          // Row 2: SKU, Barcode, Category
          Row(
            children: [
              Expanded(child: _buildSkuField(context)),
              const SizedBox(width: 16),
              Expanded(child: _buildBarcodeField(context)),
              const SizedBox(width: 16),
              Expanded(child: _buildCategoryDropdown(context)),
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
              Expanded(child: _buildColorDropdown(context)),
              const SizedBox(width: 16),
              Expanded(child: _buildSizeDropdown(context)),
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
          // Row 1: Name
          _buildNameField(context),
          const SizedBox(height: 16),
          // Row 2: Names localized
          Row(
            children: [
              Expanded(child: _buildNameArField(context)),
              const SizedBox(width: 16),
              Expanded(child: _buildNameFrField(context)),
            ],
          ),
          const SizedBox(height: 16),
          // Row 3: SKU, Barcode
          Row(
            children: [
              Expanded(child: _buildSkuField(context)),
              const SizedBox(width: 16),
              Expanded(child: _buildBarcodeField(context)),
            ],
          ),
          const SizedBox(height: 16),
          // Row 4: Prices
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
          // Row 5: Stock and variants
          Row(
            children: [
              Expanded(child: _buildStockField(context)),
              const SizedBox(width: 16),
              Expanded(child: _buildMinStockField(context)),
            ],
          ),
          const SizedBox(height: 16),
          // Row 6: Color, Size
          Row(
            children: [
              Expanded(child: _buildColorDropdown(context)),
              const SizedBox(width: 16),
              Expanded(child: _buildSizeDropdown(context)),
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
          _buildNameArField(context),
          const SizedBox(height: 16),
          _buildNameFrField(context),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _buildSkuField(context)),
              const SizedBox(width: 16),
              Expanded(child: _buildBarcodeField(context)),
            ],
          ),
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
              Expanded(child: _buildColorDropdown(context)),
              const SizedBox(width: 16),
              Expanded(child: _buildSizeDropdown(context)),
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

  Widget _buildNameArField(BuildContext context) {
    return TextFormField(
      controller: _nameArController,
      decoration: InputDecoration(
        labelText: 'product_form.nameAr'.tr(),
        hintText: 'product_form.nameAr'.tr(),
        border: const OutlineInputBorder(),
      ),
      onChanged: (value) {
        widget.onUpdate({'nameAr': value});
      },
    );
  }

  Widget _buildNameFrField(BuildContext context) {
    return TextFormField(
      controller: _nameFrController,
      decoration: InputDecoration(
        labelText: 'product_form.nameFr'.tr(),
        hintText: 'product_form.nameFr'.tr(),
        border: const OutlineInputBorder(),
      ),
      onChanged: (value) {
        widget.onUpdate({'nameFr': value});
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

  Widget _buildCategoryDropdown(BuildContext context) {
    return DropdownButtonFormField<int?>(
      initialValue: widget.rowData.categoryId,
      decoration: InputDecoration(
        labelText: 'product_form.category'.tr(),
        border: const OutlineInputBorder(),
      ),
      items: [
        DropdownMenuItem<int?>(
          value: null,
          child: Text('common.none'.tr()),
        ),
      ],
      onChanged: (value) {
        widget.onUpdate({'categoryId': value});
      },
    );
  }

  Widget _buildColorDropdown(BuildContext context) {
    return BlocBuilder<ColorsBloc, RealtimeState<List<ProductColor>>>(
      builder: (context, state) {
        final colors = state is RealtimeSuccess<List<ProductColor>> 
            ? state.data 
            : <ProductColor>[];
        
        return DropdownButtonFormField<int?>(
          initialValue: widget.rowData.colorId,
          decoration: InputDecoration(
            labelText: 'product_form.variantColor'.tr(),
            border: const OutlineInputBorder(),
          ),
          items: [
            DropdownMenuItem<int?>(
              value: null,
              child: Text('common.none'.tr()),
            ),
            ...colors.map((color) => DropdownMenuItem<int?>(
              value: color.id,
              child: Row(
                children: [
                  if (color.hexCode != null)
                    Container(
                      width: 16,
                      height: 16,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: _parseHexColor(color.hexCode!),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                    ),
                  Text(color.name),
                ],
              ),
            )),
          ],
          onChanged: (value) {
            widget.onUpdate({'colorId': value});
          },
        );
      },
    );
  }

  Color _parseHexColor(String hexCode) {
    try {
      final hex = hexCode.replaceFirst('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return Colors.grey;
    }
  }

  Widget _buildSizeDropdown(BuildContext context) {
    return BlocBuilder<SizesBloc, RealtimeState<List<Size>>>(
      builder: (context, state) {
        final sizes = state is RealtimeSuccess<List<Size>> 
            ? state.data 
            : <Size>[];
        
        return DropdownButtonFormField<int?>(
          initialValue: widget.rowData.sizeId,
          decoration: InputDecoration(
            labelText: 'product_form.variantSize'.tr(),
            border: const OutlineInputBorder(),
          ),
          items: [
            DropdownMenuItem<int?>(
              value: null,
              child: Text('common.none'.tr()),
            ),
            ...sizes.map((size) => DropdownMenuItem<int?>(
              value: size.id,
              child: Text(size.name),
            )),
          ],
          onChanged: (value) {
            widget.onUpdate({'sizeId': value});
          },
        );
      },
    );
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
