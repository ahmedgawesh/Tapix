import 'package:decimal/decimal.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/services/currency_service.dart';
import '../../domain/entities/product_entity.dart';

class PriceEditRow extends StatefulWidget {
  final Product product;
  final CurrencyService currencyService;
  final void Function(Decimal newPrice, bool isWholesale) onPriceChanged;
  final bool isSelected;
  final void Function(bool? selected)? onSelectionChanged;

  const PriceEditRow({
    super.key,
    required this.product,
    required this.currencyService,
    required this.onPriceChanged,
    this.isSelected = false,
    this.onSelectionChanged,
  });

  @override
  State<PriceEditRow> createState() => _PriceEditRowState();
}

class _PriceEditRowState extends State<PriceEditRow> {
  late TextEditingController _costController;
  late TextEditingController _priceController;
  late TextEditingController _wholesaleController;

  @override
  void initState() {
    super.initState();
    _costController = TextEditingController(
      text: _formatCents(widget.product.costCents),
    );
    _priceController = TextEditingController(
      text: _formatCents(widget.product.priceCents),
    );
    _wholesaleController = TextEditingController(
      text: widget.product.wholesalePriceCents != null
          ? _formatCents(widget.product.wholesalePriceCents!)
          : '',
    );
  }

  @override
  void didUpdateWidget(PriceEditRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Update controllers when product data changes
    if (oldWidget.product.costCents != widget.product.costCents) {
      _costController.text = _formatCents(widget.product.costCents);
    }
    if (oldWidget.product.priceCents != widget.product.priceCents) {
      _priceController.text = _formatCents(widget.product.priceCents);
    }
    if (oldWidget.product.wholesalePriceCents != widget.product.wholesalePriceCents) {
      _wholesaleController.text = widget.product.wholesalePriceCents != null
          ? _formatCents(widget.product.wholesalePriceCents!)
          : '';
    }
  }

  @override
  void dispose() {
    _costController.dispose();
    _priceController.dispose();
    _wholesaleController.dispose();
    super.dispose();
  }

  String _formatCents(Decimal cents) {
    final value = (cents / Decimal.fromInt(100)).toDecimal(scaleOnInfinitePrecision: 2);
    return value.toStringAsFixed(2);
  }

  Decimal _parseToCents(String value) {
    if (value.isEmpty) return Decimal.zero;
    try {
      final parsed = Decimal.parse(value);
      return parsed * Decimal.fromInt(100);
    } catch (_) {
      return Decimal.zero;
    }
  }

  Decimal _calculateMargin() {
    final cost = _parseToCents(_costController.text);
    final price = _parseToCents(_priceController.text);
    if (price == Decimal.zero) return Decimal.zero;
    final ratio = ((price - cost) / price).toDecimal(scaleOnInfinitePrecision: 4);
    return ratio * Decimal.fromInt(100);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final margin = _calculateMargin();
    final marginColor = margin < Decimal.fromInt(15)
        ? colorScheme.error
        : margin < Decimal.fromInt(25)
            ? Colors.orange
            : colorScheme.primary;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Product name and SKU
            Row(
              children: [
                if (widget.onSelectionChanged != null) ...[
                  Checkbox(
                    value: widget.isSelected,
                    onChanged: widget.onSelectionChanged,
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.product.name,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (widget.product.sku != null)
                        Text(
                          'SKU: ${widget.product.sku}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colorScheme.outline,
                          ),
                        ),
                    ],
                  ),
                ),
                // Margin indicator
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: marginColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: marginColor.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    '${margin.toStringAsFixed(1)}%',
                    style: TextStyle(
                      color: marginColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Price fields
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 500;
                
                if (isWide) {
                  return Row(
                    children: [
                      Expanded(child: _buildCostField()),
                      const SizedBox(width: 12),
                      Expanded(child: _buildPriceField()),
                      const SizedBox(width: 12),
                      Expanded(child: _buildWholesaleField()),
                    ],
                  );
                }
                
                return Column(
                  children: [
                    Row(
                      children: [
                        Expanded(child: _buildCostField()),
                        const SizedBox(width: 12),
                        Expanded(child: _buildPriceField()),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildWholesaleField(),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCostField() {
    return TextFormField(
      controller: _costController,
      decoration: InputDecoration(
        labelText: 'edit_prices.cost'.tr(),
        prefixText: widget.currencyService.currencySymbol,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
      ],
      onTap: () {
        if (_costController.text == '0.00') {
          _costController.clear();
        }
      },
      onChanged: (_) {
        setState(() {});
        widget.onPriceChanged(_parseToCents(_costController.text), false);
      },
    );
  }

  Widget _buildPriceField() {
    return TextFormField(
      controller: _priceController,
      decoration: InputDecoration(
        labelText: 'edit_prices.selling_price'.tr(),
        prefixText: widget.currencyService.currencySymbol,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
      ],
      onTap: () {
        if (_priceController.text == '0.00') {
          _priceController.clear();
        }
      },
      onChanged: (_) {
        setState(() {});
        widget.onPriceChanged(_parseToCents(_priceController.text), false);
      },
    );
  }

  Widget _buildWholesaleField() {
    return TextFormField(
      controller: _wholesaleController,
      decoration: InputDecoration(
        labelText: 'edit_prices.wholesale_price'.tr(),
        prefixText: widget.currencyService.currencySymbol,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
      ],
      onTap: () {
        if (_wholesaleController.text == '0.00') {
          _wholesaleController.clear();
        }
      },
      onChanged: (_) {
        widget.onPriceChanged(_parseToCents(_wholesaleController.text), true);
      },
    );
  }
}
