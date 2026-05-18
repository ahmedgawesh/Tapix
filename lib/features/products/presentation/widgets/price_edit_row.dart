import 'package:decimal/decimal.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/services/currency_service.dart';
import '../../../../core/widgets/inputs/select_all_on_focus.dart';
import '../../domain/entities/product_entity.dart';
import '../../domain/entities/product_variant_entity.dart';

class PriceEditRow extends StatefulWidget {
  final Product product;
  final CurrencyService currencyService;
  final void Function(Decimal newPrice, bool isWholesale) onPriceChanged;
  final bool isSelected;
  final void Function(bool? selected)? onSelectionChanged;
  /// Called when user expands variants for the first time; return variants list.
  final Future<List<ProductVariant>> Function(int productId)? onVariantsRequested;
  /// Called when a variant price is changed inline.
  final void Function(ProductVariant updatedVariant)? onVariantPriceChanged;
  /// Currently selected variant IDs for bulk operations.
  final Set<int> selectedVariantIds;
  /// Called when a variant checkbox is toggled.
  final void Function(int variantId, bool isSelected)? onVariantSelectionChanged;
  /// Optimistic changes for variants from the bloc state
  final Map<int, Map<String, Decimal>> variantPriceChanges;

  const PriceEditRow({
    super.key,
    required this.product,
    required this.currencyService,
    required this.onPriceChanged,
    this.isSelected = false,
    this.onSelectionChanged,
    this.onVariantsRequested,
    this.onVariantPriceChanged,
    this.selectedVariantIds = const {},
    this.onVariantSelectionChanged,
    this.variantPriceChanges = const {},
  });

  @override
  State<PriceEditRow> createState() => _PriceEditRowState();
}

class _PriceEditRowState extends State<PriceEditRow> {
  late TextEditingController _costController;
  late TextEditingController _priceController;
  late TextEditingController _wholesaleController;

  bool _isExpanded = false;
  bool _isLoadingVariants = false;
  List<ProductVariant> _variants = [];

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
    if (oldWidget.product.costCents != widget.product.costCents) {
      final newVal = _formatCents(widget.product.costCents);
      if (_costController.text != newVal && _parseToCents(_costController.text) != widget.product.costCents) {
        _costController.text = newVal;
      }
    }
    if (oldWidget.product.priceCents != widget.product.priceCents) {
      final newVal = _formatCents(widget.product.priceCents);
      if (_priceController.text != newVal && _parseToCents(_priceController.text) != widget.product.priceCents) {
        _priceController.text = newVal;
      }
    }
    if (oldWidget.product.wholesalePriceCents != widget.product.wholesalePriceCents) {
      final newVal = widget.product.wholesalePriceCents != null ? _formatCents(widget.product.wholesalePriceCents!) : '';
      if (_wholesaleController.text != newVal && _parseToCents(_wholesaleController.text) != (widget.product.wholesalePriceCents ?? Decimal.zero)) {
        _wholesaleController.text = newVal;
      }
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

  Future<void> _toggleVariants() async {
    if (_isExpanded) {
      setState(() => _isExpanded = false);
      return;
    }

    if (_variants.isEmpty && widget.onVariantsRequested != null) {
      setState(() => _isLoadingVariants = true);
      try {
        final variants = await widget.onVariantsRequested!(widget.product.id);
        if (!mounted) return;
        setState(() {
          _variants = variants;
          _isExpanded = true;
          _isLoadingVariants = false;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() => _isLoadingVariants = false);
      }
    } else {
      setState(() => _isExpanded = true);
    }
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
            // Expand variants button (only for products with variants)
            if (widget.product.hasVariants && widget.onVariantsRequested != null) ...[
              const SizedBox(height: 12),
              _buildVariantsToggle(colorScheme),
            ],
            // Expanded variant rows
            if (_isExpanded && _variants.isNotEmpty) ...[
              const SizedBox(height: 8),
              _buildVariantsList(colorScheme),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildVariantsToggle(ColorScheme colorScheme) {
    return InkWell(
      onTap: _isLoadingVariants ? null : _toggleVariants,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: colorScheme.primaryContainer.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colorScheme.primary.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isLoadingVariants)
              const SizedBox(
                width: 16, height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(
                _isExpanded ? Icons.expand_less : Icons.expand_more,
                size: 20,
                color: colorScheme.primary,
              ),
            const SizedBox(width: 6),
            Text(
              _isExpanded
                  ? 'edit_prices.hide_variants'.tr()
                  : 'edit_prices.show_variants'.tr(),
              style: TextStyle(
                color: colorScheme.primary,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            if (!_isExpanded && _variants.isNotEmpty) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${_variants.length}',
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildVariantsList(ColorScheme colorScheme) {
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: _variants.map((variant) {
          final isVariantSelected = widget.selectedVariantIds.contains(variant.id);
          
          // Apply optimistic variant price changes
          ProductVariant displayVariant = variant;
          final changes = widget.variantPriceChanges[variant.id];
          if (changes != null) {
            if (changes.containsKey('costCents')) {
              displayVariant = displayVariant.copyWith(costCents: changes['costCents']!);
            }
            if (changes.containsKey('priceCents')) {
              displayVariant = displayVariant.copyWith(priceCents: changes['priceCents']!);
            }
            if (changes.containsKey('wholesalePriceCents')) {
              displayVariant = displayVariant.copyWith(wholesalePriceCents: changes['wholesalePriceCents']!);
            }
          }

          return _VariantPriceRow(
            key: ValueKey('variant_${variant.id}'),
            variant: displayVariant,
            currencyService: widget.currencyService,
            isSelected: isVariantSelected,
            onSelectionChanged: (selected) {
              widget.onVariantSelectionChanged?.call(variant.id, selected ?? false);
            },
            onChanged: (updated) {
              widget.onVariantPriceChanged?.call(updated);
              setState(() {
                final index = _variants.indexWhere((v) => v.id == updated.id);
                if (index >= 0) _variants[index] = updated;
              });
            },
          );
        }).toList(),
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
      onTap: () => selectAllText(_costController),
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
      onTap: () => selectAllText(_priceController),
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
      onTap: () => selectAllText(_wholesaleController),
      onChanged: (_) {
        widget.onPriceChanged(_parseToCents(_wholesaleController.text), true);
      },
    );
  }
}

/// A sub-row for an individual variant's prices within the expanded section.
class _VariantPriceRow extends StatefulWidget {
  final ProductVariant variant;
  final CurrencyService currencyService;
  final void Function(ProductVariant updated) onChanged;
  final bool isSelected;
  final void Function(bool? selected)? onSelectionChanged;

  const _VariantPriceRow({
    super.key,
    required this.variant,
    required this.currencyService,
    required this.onChanged,
    this.isSelected = false,
    this.onSelectionChanged,
  });

  @override
  State<_VariantPriceRow> createState() => _VariantPriceRowState();
}

class _VariantPriceRowState extends State<_VariantPriceRow> {
  late TextEditingController _costCtrl;
  late TextEditingController _priceCtrl;
  late TextEditingController _wholesaleCtrl;

  @override
  void initState() {
    super.initState();
    _costCtrl = TextEditingController(text: _fmt(widget.variant.costCents));
    _priceCtrl = TextEditingController(text: _fmt(widget.variant.priceCents));
    _wholesaleCtrl = TextEditingController(
      text: widget.variant.wholesalePriceCents != null
          ? _fmt(widget.variant.wholesalePriceCents!)
          : '',
    );
  }

  @override
  void didUpdateWidget(_VariantPriceRow old) {
    super.didUpdateWidget(old);
    if (old.variant.costCents != widget.variant.costCents) {
      final newVal = _fmt(widget.variant.costCents);
      if (_costCtrl.text != newVal && _toCents(_costCtrl.text) != widget.variant.costCents) {
        _costCtrl.text = newVal;
      }
    }
    if (old.variant.priceCents != widget.variant.priceCents) {
      final newVal = _fmt(widget.variant.priceCents);
      if (_priceCtrl.text != newVal && _toCents(_priceCtrl.text) != widget.variant.priceCents) {
        _priceCtrl.text = newVal;
      }
    }
    if (old.variant.wholesalePriceCents != widget.variant.wholesalePriceCents) {
      final newVal = widget.variant.wholesalePriceCents != null ? _fmt(widget.variant.wholesalePriceCents!) : '';
      if (_wholesaleCtrl.text != newVal && _toCents(_wholesaleCtrl.text) != (widget.variant.wholesalePriceCents ?? Decimal.zero)) {
        _wholesaleCtrl.text = newVal;
      }
    }
  }

  @override
  void dispose() {
    _costCtrl.dispose();
    _priceCtrl.dispose();
    _wholesaleCtrl.dispose();
    super.dispose();
  }

  String _fmt(Decimal cents) =>
      (cents / Decimal.fromInt(100)).toDecimal(scaleOnInfinitePrecision: 2).toStringAsFixed(2);

  Decimal _toCents(String v) {
    if (v.isEmpty) return Decimal.zero;
    try {
      return Decimal.parse(v) * Decimal.fromInt(100);
    } catch (_) {
      return Decimal.zero;
    }
  }

  void _emitUpdate() {
    final costCents = _toCents(_costCtrl.text);
    final priceCents = _toCents(_priceCtrl.text);
    final wholesaleText = _wholesaleCtrl.text.trim();
    final wholesaleCents = wholesaleText.isEmpty ? null : _toCents(wholesaleText);

    widget.onChanged(widget.variant.copyWith(
      costCents: costCents,
      priceCents: priceCents,
      wholesalePriceCents: wholesaleCents,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final variant = widget.variant;

    // Build variant label
    String label = variant.sku ?? 'ID: ${variant.id}';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 32,
                height: 32,
                child: Checkbox(
                  value: widget.isSelected,
                  onChanged: widget.onSelectionChanged,
                  visualDensity: VisualDensity.compact,
                ),
              ),
              Icon(Icons.subdirectory_arrow_right, size: 16, color: colorScheme.outline),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: _buildField(_costCtrl, 'edit_prices.cost'.tr()),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildField(_priceCtrl, 'edit_prices.selling_price'.tr()),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildField(_wholesaleCtrl, 'edit_prices.wholesale_price'.tr()),
              ),
            ],
          ),
          const Divider(height: 1),
        ],
      ),
    );
  }

  Widget _buildField(TextEditingController ctrl, String label) {
    return TextFormField(
      controller: ctrl,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 11),
        prefixText: widget.currencyService.currencySymbol,
        prefixStyle: const TextStyle(fontSize: 13),
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        isDense: true,
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
      ],
      onTap: () => selectAllText(ctrl),
      onChanged: (_) => _emitUpdate(),
    );
  }
}
