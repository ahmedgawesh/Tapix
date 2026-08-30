import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/measurement/measurement.dart';
import '../../../../core/measurement/measurement_localization.dart';
import '../../domain/entities/product_color_entity.dart';
import '../../domain/entities/product_entity.dart';
import '../../domain/entities/product_variant_entity.dart';
import '../../domain/entities/size_entity.dart';
import '../../domain/repositories/product_variant_repository.dart';
import '../../domain/repositories/product_repository.dart';
import '../bloc/product_variants_bloc.dart';
import '../bloc/colors_bloc.dart';
import '../bloc/sizes_bloc.dart';
import '../../../../core/widgets/inputs/select_all_on_focus.dart';
import 'money_input_widget.dart';
import 'inventory_adjustment_dialog.dart';

/// Reusable dialog for creating/editing a product variant.
/// Full-featured with: Attributes, Identity (SKU/Barcode), Pricing, Inventory, Status, Print, Delete.
class VariantEditDialog extends StatefulWidget {
  final int productId;
  final String? productName;
  final ProductVariant? variant;
  final ProductVariantsBloc? variantsBloc;
  final String measurementType;

  const VariantEditDialog({
    super.key,
    required this.productId,
    this.productName,
    this.variant,
    this.variantsBloc,
    this.measurementType = 'piece',
  });

  @override
  State<VariantEditDialog> createState() => _VariantEditDialogState();

  /// Shows the dialog with proper bloc providers using GetIt.
  static void show(
    BuildContext context, {
    required int productId,
    String? productName,
    ProductVariant? variant,
    ProductVariantsBloc? existingVariantsBloc,
    String measurementType = 'piece',
  }) {
    // Try to get blocs from context first, fallback to GetIt
    ColorsBloc? colorsBloc;
    SizesBloc? sizesBloc;
    ProductVariantsBloc? variantsBloc = existingVariantsBloc;

    try {
      colorsBloc = context.read<ColorsBloc>();
    } catch (_) {
      colorsBloc = sl<ColorsBloc>();
    }

    try {
      sizesBloc = context.read<SizesBloc>();
    } catch (_) {
      sizesBloc = sl<SizesBloc>();
    }

    if (variantsBloc == null) {
      try {
        variantsBloc = context.read<ProductVariantsBloc>();
      } catch (_) {
        variantsBloc = sl<ProductVariantsBloc>();
        variantsBloc.add(ProductVariantsInitialized(productId));
      }
    }

    final isMobile = MediaQuery.of(context).size.width < 600;

    if (isMobile) {
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (ctx) => MultiBlocProvider(
          providers: [
            BlocProvider.value(value: colorsBloc!),
            BlocProvider.value(value: sizesBloc!),
            BlocProvider.value(value: variantsBloc!),
          ],
          child: VariantEditDialog(
            productId: productId,
            productName: productName,
            variant: variant,
            variantsBloc: variantsBloc,
            measurementType: measurementType,
          ),
        ),
      );
    } else {
      showDialog<void>(
        context: context,
        builder: (ctx) => MultiBlocProvider(
          providers: [
            BlocProvider.value(value: colorsBloc!),
            BlocProvider.value(value: sizesBloc!),
            BlocProvider.value(value: variantsBloc!),
          ],
          child: Dialog(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680, maxHeight: 800),
              child: VariantEditDialog(
                productId: productId,
                productName: productName,
                variant: variant,
                variantsBloc: variantsBloc,
                measurementType: measurementType,
              ),
            ),
          ),
        ),
      );
    }
  }
}

class _VariantEditDialogState extends State<VariantEditDialog> {
  final _formKey = GlobalKey<FormState>();
  final _skuController = TextEditingController();
  final _barcodeController = TextEditingController();
  final _stockController = TextEditingController();

  int? _colorId;
  int? _sizeId;
  Decimal _costCents = Decimal.zero;
  Decimal _priceCents = Decimal.zero;
  Decimal? _wholesalePriceCents;
  bool _isActive = true;
  bool _isLoading = false;
  String? _errorMessage;
  String? _skuError;
  String? _barcodeError;
  String? _duplicateError;
  String? _baseSku;

  bool get _isEditing => widget.variant != null;
  int get _currentStock => widget.variant?.stockQuantity ?? 0;

  @override
  void initState() {
    super.initState();
    if (widget.variant != null) {
      final v = widget.variant!;
      _skuController.text = v.sku ?? '';
      _barcodeController.text = v.barcode ?? '';
      _stockController.text = MeasuredQuantity.majorValue(
        v.stockQuantity,
        MeasurementType.fromDb(widget.measurementType),
      );
      _colorId = v.colorId;
      _sizeId = v.sizeId;
      // Display the GROSS supplier reference price rather than the IAS-2
      // net cost basis (see product_form_bloc for the full rationale).
      // Fallback to costCents for legacy variants pre-migration 10055.
      _costCents = v.lastPurchasePriceCents ?? v.costCents;
      _priceCents = v.priceCents;
      _wholesalePriceCents = v.wholesalePriceCents;
      _isActive = v.isActive;
    } else {
      _stockController.text = '0';
      _loadDefaultsForNewVariant();
    }
  }

  Future<void> _loadDefaultsForNewVariant() async {
    try {
      final productRepo = sl<ProductRepository>();
      final product = await productRepo.watchProduct(widget.productId).first;
      if (!mounted || product == null) return;

      setState(() {
        _costCents = product.lastPurchasePriceCents ?? product.costCents;
        _priceCents = product.priceCents;
        _wholesalePriceCents = product.wholesalePriceCents;
        _baseSku = (product.sku ?? '').trim();

        if (_skuController.text.trim().isEmpty &&
            _baseSku != null &&
            _baseSku!.isNotEmpty) {
          // Pre-fill with base SKU (user must add a suffix).
          _skuController.text = '${_baseSku!}-';
        }
      });
    } catch (_) {
      // Ignore and keep defaults.
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
    final colorScheme = Theme.of(context).colorScheme;
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      backgroundColor: isMobile ? null : Colors.transparent,
      appBar: isMobile
          ? AppBar(
              title: Text(
                _isEditing
                    ? 'variant_dialog.edit_title'.tr()
                    : 'variant_dialog.add_title'.tr(),
              ),
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
              actions: _buildAppBarActions(),
            )
          : null,
      body: Column(
        children: [
          if (!isMobile) _buildDesktopHeader(colorScheme),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_errorMessage != null) _buildErrorBanner(colorScheme),
                    if (_duplicateError != null)
                      _buildDuplicateWarning(colorScheme),
                    _buildAttributesSection(colorScheme),
                    const SizedBox(height: 24),
                    _buildIdentitySection(colorScheme),
                    const SizedBox(height: 24),
                    _buildPricingSection(colorScheme),
                    const SizedBox(height: 24),
                    _buildInventorySection(colorScheme),
                    const SizedBox(height: 24),
                    _buildStatusSection(colorScheme),
                    if (_isEditing) ...[
                      const SizedBox(height: 24),
                      _buildDangerZone(colorScheme),
                    ],
                  ],
                ),
              ),
            ),
          ),
          _buildBottomActions(colorScheme, isMobile),
        ],
      ),
    );
  }

  List<Widget> _buildAppBarActions() {
    return [
      if (_isEditing)
        IconButton(
          icon: const Icon(LucideIcons.printer),
          onPressed: _printLabel,
          tooltip: 'variant_dialog.print_label'.tr(),
        ),
    ];
  }

  Widget _buildDesktopHeader(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _isEditing
                      ? 'variant_dialog.edit_title'.tr()
                      : 'variant_dialog.add_title'.tr(),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              if (_isEditing) ...[
                Chip(
                  label: Text('#${widget.variant!.id}'),
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 8),
                Chip(
                  label: Text(
                    _isActive
                        ? 'variant_dialog.active'.tr()
                        : 'variant_dialog.inactive'.tr(),
                  ),
                  backgroundColor: _isActive
                      ? colorScheme.primaryContainer
                      : colorScheme.errorContainer,
                  visualDensity: VisualDensity.compact,
                ),
              ],
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          if (widget.productName != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(LucideIcons.package, size: 16, color: colorScheme.outline),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.productName!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.outline,
                    ),
                  ),
                ),
                if (_isEditing)
                  TextButton.icon(
                    onPressed: _printLabel,
                    icon: const Icon(LucideIcons.printer, size: 16),
                    label: Text('variant_dialog.print_label'.tr()),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildErrorBanner(ColorScheme colorScheme) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.alertCircle, color: colorScheme.error),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _errorMessage!,
              style: TextStyle(color: colorScheme.onErrorContainer),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => setState(() => _errorMessage = null),
            iconSize: 18,
          ),
        ],
      ),
    );
  }

  Widget _buildDuplicateWarning(ColorScheme colorScheme) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.alertTriangle, color: colorScheme.tertiary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _duplicateError!,
              style: TextStyle(color: colorScheme.onTertiaryContainer),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(
    String title,
    IconData icon,
    ColorScheme colorScheme,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttributesSection(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(
          'variant_dialog.attributes'.tr(),
          LucideIcons.tags,
          colorScheme,
        ),
        Row(
          children: [
            Expanded(child: _buildColorSelector(colorScheme)),
            const SizedBox(width: 16),
            Expanded(child: _buildSizeSelector(colorScheme)),
          ],
        ),
      ],
    );
  }

  Widget _buildColorSelector(ColorScheme colorScheme) {
    return BlocBuilder<ColorsBloc, RealtimeState<List<ProductColor>>>(
      builder: (context, state) {
        final colors = state is RealtimeSuccess<List<ProductColor>>
            ? state.data
            : <ProductColor>[];
        final selectedColor = colors.where((c) => c.id == _colorId).firstOrNull;

        return InkWell(
          onTap: () => _showColorPicker(colors),
          borderRadius: BorderRadius.circular(8),
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: 'variant_dialog.color'.tr(),
              border: const OutlineInputBorder(),
              prefixIcon: selectedColor != null
                  ? Padding(
                      padding: const EdgeInsets.all(12),
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: _parseColor(selectedColor.hexCode),
                          shape: BoxShape.circle,
                          border: Border.all(color: colorScheme.outline),
                        ),
                      ),
                    )
                  : const Icon(LucideIcons.palette),
              suffixIcon: const Icon(Icons.arrow_drop_down),
            ),
            child: Text(
              selectedColor?.name ?? 'common.none'.tr(),
              style: selectedColor == null
                  ? TextStyle(color: colorScheme.outline)
                  : null,
            ),
          ),
        );
      },
    );
  }

  Widget _buildSizeSelector(ColorScheme colorScheme) {
    return BlocBuilder<SizesBloc, RealtimeState<List<Size>>>(
      builder: (context, state) {
        final sizes = state is RealtimeSuccess<List<Size>>
            ? state.data
            : <Size>[];
        final selectedSize = sizes.where((s) => s.id == _sizeId).firstOrNull;

        return InkWell(
          onTap: () => _showSizePicker(sizes),
          borderRadius: BorderRadius.circular(8),
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: 'variant_dialog.size'.tr(),
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(LucideIcons.ruler),
              suffixIcon: const Icon(Icons.arrow_drop_down),
            ),
            child: Text(
              selectedSize?.name ?? 'common.none'.tr(),
              style: selectedSize == null
                  ? TextStyle(color: colorScheme.outline)
                  : null,
            ),
          ),
        );
      },
    );
  }

  void _showColorPicker(List<ProductColor> colors) {
    final searchController = TextEditingController();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (ctx, scrollController) {
          return StatefulBuilder(
            builder: (ctx, setSheetState) {
              final query = searchController.text.toLowerCase();
              final filtered = colors
                  .where((c) => c.name.toLowerCase().contains(query))
                  .toList();

              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'variant_dialog.select_color'.tr(),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () => context.push('/products/colors'),
                          icon: const Icon(LucideIcons.settings, size: 16),
                          label: Text('variant_dialog.manage'.tr()),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      controller: searchController,
                      decoration: InputDecoration(
                        hintText: 'variant_dialog.search_color'.tr(),
                        prefixIcon: const Icon(LucideIcons.search),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (_) => setSheetState(() {}),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      children: [
                        ListTile(
                          leading: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.grey),
                            ),
                            child: const Icon(Icons.block, size: 16),
                          ),
                          title: Text('common.none'.tr()),
                          selected: _colorId == null,
                          onTap: () {
                            setState(() => _colorId = null);
                            _checkDuplicateCombination();
                            Navigator.pop(ctx);
                          },
                        ),
                        ...filtered.map(
                          (color) => ListTile(
                            leading: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: _parseColor(color.hexCode),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                            ),
                            title: Text(color.name),
                            selected: _colorId == color.id,
                            onTap: () {
                              setState(() => _colorId = color.id);
                              _checkDuplicateCombination();
                              Navigator.pop(ctx);
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  void _showSizePicker(List<Size> sizes) {
    final searchController = TextEditingController();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (ctx, scrollController) {
          return StatefulBuilder(
            builder: (ctx, setSheetState) {
              final query = searchController.text.toLowerCase();
              final filtered = sizes
                  .where((s) => s.name.toLowerCase().contains(query))
                  .toList();

              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'variant_dialog.select_size'.tr(),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () => context.push('/products/sizes'),
                          icon: const Icon(LucideIcons.settings, size: 16),
                          label: Text('variant_dialog.manage'.tr()),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      controller: searchController,
                      decoration: InputDecoration(
                        hintText: 'variant_dialog.search_size'.tr(),
                        prefixIcon: const Icon(LucideIcons.search),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (_) => setSheetState(() {}),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      children: [
                        ListTile(
                          leading: const Icon(Icons.block),
                          title: Text('common.none'.tr()),
                          selected: _sizeId == null,
                          onTap: () {
                            setState(() => _sizeId = null);
                            _checkDuplicateCombination();
                            Navigator.pop(ctx);
                          },
                        ),
                        ...filtered.map(
                          (size) => ListTile(
                            leading: const Icon(LucideIcons.ruler),
                            title: Text(size.name),
                            selected: _sizeId == size.id,
                            onTap: () {
                              setState(() => _sizeId = size.id);
                              _checkDuplicateCombination();
                              Navigator.pop(ctx);
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildIdentitySection(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(
          'variant_dialog.identity'.tr(),
          LucideIcons.fingerprint,
          colorScheme,
        ),
        TextFormField(
          controller: _skuController,
          decoration: InputDecoration(
            labelText: 'variant_dialog.sku'.tr(),
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(LucideIcons.hash),
            errorText: _skuError,
            suffixIcon: IconButton(
              icon: const Icon(LucideIcons.sparkles),
              onPressed: _generateSku,
              tooltip: 'variant_dialog.generate_sku'.tr(),
            ),
          ),
          onChanged: (_) => _validateSku(),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _barcodeController,
          decoration: InputDecoration(
            labelText: 'variant_dialog.barcode'.tr(),
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(LucideIcons.scan),
            errorText: _barcodeError,
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(LucideIcons.sparkles),
                  onPressed: _isEditing ? _generateBarcode : null,
                  tooltip: 'variant_dialog.generate_barcode'.tr(),
                ),
                IconButton(
                  icon: const Icon(LucideIcons.copy),
                  onPressed: _barcodeController.text.isNotEmpty
                      ? () => _copyToClipboard(_barcodeController.text)
                      : null,
                  tooltip: 'variant_dialog.copy_barcode'.tr(),
                ),
              ],
            ),
          ),
          onChanged: (_) => _validateBarcode(),
        ),
        if (!_isEditing)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'variant_dialog.barcode_auto_hint'.tr(),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colorScheme.outline),
            ),
          ),
      ],
    );
  }

  Widget _buildPricingSection(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(
          'variant_dialog.pricing'.tr(),
          LucideIcons.dollarSign,
          colorScheme,
        ),
        Row(
          children: [
            Expanded(
              child: MoneyInputWidget(
                value: _costCents,
                label: 'variant_dialog.cost'.tr(),
                // Cost is WAC-managed: updated only by purchases and by
                // Inventory Revaluation adjustments. Editable only when
                // creating a brand-new variant (no stock history yet).
                enabled: !_isEditing,
                hint: _isEditing ? 'products.cost_readonly_hint'.tr() : null,
                onChanged: (value) => setState(() => _costCents = value),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: MoneyInputWidget(
                value: _priceCents,
                label: 'variant_dialog.price'.tr(),
                onChanged: (value) => setState(() => _priceCents = value),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        MoneyInputWidget(
          value: _wholesalePriceCents ?? Decimal.zero,
          label: 'variant_dialog.wholesale_price'.tr(),
          onChanged: (value) => setState(() {
            _wholesalePriceCents = value == Decimal.zero ? null : value;
          }),
        ),
        if (_priceCents < _costCents && _priceCents > Decimal.zero)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                Icon(
                  LucideIcons.alertTriangle,
                  size: 16,
                  color: colorScheme.tertiary,
                ),
                const SizedBox(width: 8),
                Text(
                  'variant_dialog.price_below_cost'.tr(),
                  style: TextStyle(color: colorScheme.tertiary, fontSize: 12),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildInventorySection(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(
          'variant_dialog.inventory'.tr(),
          LucideIcons.package,
          colorScheme,
        ),
        if (_isEditing) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(LucideIcons.boxes, color: colorScheme.primary),
                const SizedBox(width: 12),
                Text(
                  'variant_dialog.current_stock'.tr(),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const Spacer(),
                Text(
                  localizedQuantity(_currentStock, widget.measurementType),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: _currentStock <= 0
                        ? colorScheme.error
                        : colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'products.stock_readonly_hint'.tr(),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _isLoading ? null : _openInventoryAdjustment,
            icon: const Icon(LucideIcons.warehouse, size: 16),
            label: Text('products.adjust_inventory'.tr()),
          ),
        ] else ...[
          TextFormField(
            controller: _stockController,
            decoration: InputDecoration(
              labelText: 'variant_dialog.initial_stock'.tr(),
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(LucideIcons.package),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            onTap: () => selectAllText(_stockController),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'common.required'.tr();
              }
              try {
                MeasuredQuantity.parseToStored(
                  value,
                  MeasurementType.fromDb(widget.measurementType).majorUnit,
                );
              } on FormatException {
                return 'variant_dialog.invalid_stock'.tr();
              }
              return null;
            },
          ),
        ],
      ],
    );
  }

  /// Launches the accounting-safe Inventory Adjustment dialog for the
  /// variant currently being edited. Any successful post is applied through
  /// `InventoryAdjustmentService`, which updates stock, posts a balanced
  /// journal entry, and records an `inventory_adjustments` audit row in
  /// one transaction. On success we close this dialog so the caller sees
  /// fresh data when it re-opens.
  Future<void> _openInventoryAdjustment() async {
    final v = widget.variant;
    if (v == null) return;
    final posted = await InventoryAdjustmentDialog.show(
      context,
      productId: v.productId,
      variantId: v.id,
      currentStock: v.stockQuantity,
      currentUnitCostCents: v.costCents.toBigInt().toInt(),
      subjectLabel: widget.productName,
    );
    if (posted == true && mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('inventory_adjustment.posted_success'.tr())),
      );
    }
  }

  Widget _buildStatusSection(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(
          'variant_dialog.status'.tr(),
          LucideIcons.toggleLeft,
          colorScheme,
        ),
        SwitchListTile(
          title: Text('variant_dialog.active'.tr()),
          subtitle: Text(
            (widget.variant?.stockQuantity ?? 0) != 0 && _isActive
                ? 'variant_dialog.active_stock_hint'.tr()
                : 'variant_dialog.active_hint'.tr(),
          ),
          value: _isActive,
          onChanged: (value) {
            if (!value && (widget.variant?.stockQuantity ?? 0) != 0) {
              _showStockBlock();
              return;
            }
            setState(() => _isActive = value);
          },
          contentPadding: EdgeInsets.zero,
        ),
      ],
    );
  }

  Widget _buildDangerZone(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(
          'variant_dialog.danger_zone'.tr(),
          LucideIcons.alertTriangle,
          colorScheme,
        ),
        OutlinedButton.icon(
          onPressed: _confirmDelete,
          icon: Icon(LucideIcons.trash2, color: colorScheme.error),
          label: Text(
            'variant_dialog.delete_variant'.tr(),
            style: TextStyle(color: colorScheme.error),
          ),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: colorScheme.error),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomActions(ColorScheme colorScheme, bool isMobile) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Row(
        children: [
          if (!isMobile)
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('common.cancel'.tr()),
            ),
          const Spacer(),
          if (_isEditing && !isMobile)
            OutlinedButton.icon(
              onPressed: _printLabel,
              icon: const Icon(LucideIcons.printer),
              label: Text('variant_dialog.print'.tr()),
            ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _isLoading ? null : _submit,
            icon: _isLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(LucideIcons.check),
            label: Text('common.save'.tr()),
          ),
        ],
      ),
    );
  }

  Color _parseColor(String? hexCode) {
    if (hexCode == null || hexCode.isEmpty) return Colors.grey;
    try {
      return Color(int.parse(hexCode.replaceFirst('#', '0xFF')));
    } catch (_) {
      return Colors.grey;
    }
  }

  void _generateSku() {
    final parts = <String>[];
    final base = (_baseSku ?? '').trim();
    parts.add(base.isNotEmpty ? base : 'P${widget.productId}');
    if (_colorId != null) parts.add('C$_colorId');
    if (_sizeId != null) parts.add('S$_sizeId');
    setState(() {
      _skuController.text = parts.join('-');
    });
    _validateSku();
  }

  Future<void> _ensureVariantSkuSuffix() async {
    if (_isEditing) return;
    final base = (_baseSku ?? '').trim();
    if (base.isEmpty) return;

    var sku = _skuController.text.trim();
    if (sku.isEmpty) sku = '$base-';

    final normalizedPrefix = '$base-';
    if (sku == base || sku == normalizedPrefix) {
      // User didn't provide a suffix -> auto-generate one.
      final repo = sl<ProductVariantRepository>();
      var i = 1;
      while (true) {
        final candidate = '$normalizedPrefix$i';
        final taken = await repo.isSkuTaken(candidate);
        if (!taken) {
          sku = candidate;
          break;
        }
        i++;
      }
    }

    setState(() {
      _skuController.text = sku;
    });
    await _validateSku();
  }

  void _generateBarcode() {
    if (!_isEditing || widget.variant == null) return;
    final id = widget.variant!.id.toString().padLeft(10, '0');
    setState(() {
      _barcodeController.text = '29$id';
    });
    _validateBarcode();
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('variant_dialog.copied'.tr())));
  }

  Future<void> _validateSku() async {
    final sku = _skuController.text.trim();
    if (sku.isEmpty) {
      setState(() => _skuError = null);
      return;
    }
    try {
      final repo = sl<ProductVariantRepository>();
      final exists = await repo.isSkuTaken(
        sku,
        excludeVariantId: widget.variant?.id,
      );
      setState(() {
        _skuError = exists ? 'variant_dialog.sku_taken'.tr() : null;
      });
    } catch (_) {
      setState(() => _skuError = null);
    }
  }

  Future<void> _validateBarcode() async {
    final barcode = _barcodeController.text.trim();
    if (barcode.isEmpty) {
      setState(() => _barcodeError = null);
      return;
    }
    try {
      final repo = sl<ProductVariantRepository>();
      final exists = await repo.isBarcodeTaken(
        barcode,
        excludeVariantId: widget.variant?.id,
      );
      setState(() {
        _barcodeError = exists ? 'variant_dialog.barcode_taken'.tr() : null;
      });
    } catch (_) {
      setState(() => _barcodeError = null);
    }
  }

  Future<void> _checkDuplicateCombination() async {
    try {
      final repo = sl<ProductVariantRepository>();
      final exists = await repo.variantExists(
        productId: widget.productId,
        colorId: _colorId,
        sizeId: _sizeId,
        excludeVariantId: widget.variant?.id,
      );
      setState(() {
        _duplicateError = exists
            ? 'variant_dialog.duplicate_combination'.tr()
            : null;
      });
    } catch (_) {
      setState(() => _duplicateError = null);
    }
  }

  void _printLabel() {
    if (widget.variant == null) return;
    final v = widget.variant!;

    // Build a Product object from the variant data for the barcode design screen
    final printProduct = Product(
      id: v.productId,
      name: widget.productName ?? '',
      sku: v.sku,
      barcode: v.barcode,
      costCents: v.costCents,
      priceCents: v.priceCents,
      wholesalePriceCents: v.wholesalePriceCents,
      stockQuantity: v.stockQuantity,
      minQuantity: 0,
      categoryId: null,
      supplierId: null,
      currencyId: null,
      imagePath: null,
      hasVariants: false,
      isTaxable: false,
      purchaseTaxRateBps: 0,
      salesTaxRateBps: 0,
      isActive: v.isActive,
      trackInventory: false,
    );

    // Build variant info string from color/size
    final parts = <String>[];
    if (v.colorId != null) parts.add('C#${v.colorId}');
    if (v.sizeId != null) parts.add('S#${v.sizeId}');
    final variantInfo = parts.isNotEmpty ? parts.join(' / ') : null;

    Navigator.pop(context);
    context.push(
      '/products/barcode-design',
      extra: {
        'products': [printProduct],
        if (variantInfo != null)
          'variantInfoByProductId': <int, String>{printProduct.id: variantInfo},
      },
    );
  }

  void _confirmDelete() {
    if ((widget.variant?.stockQuantity ?? 0) != 0) {
      _showStockBlock();
      return;
    }
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('variant_dialog.delete_title'.tr()),
        content: Text('variant_dialog.delete_confirm'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text('common.delete'.tr()),
          ),
        ],
      ),
    ).then((confirmed) {
      if (!mounted) return;
      if (confirmed == true && widget.variant != null) {
        context.read<ProductVariantsBloc>().add(
          VariantDeleteRequested(widget.variant!.id),
        );
        Navigator.pop(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('variant_dialog.deleted'.tr())));
      }
    });
  }

  void _showStockBlock() {
    final cs = Theme.of(context).colorScheme;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(LucideIcons.packageX, color: cs.error),
        title: Text('variant_dialog.stock_block_title'.tr()),
        content: Text('variant_dialog.stock_block_body'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(ctx).pop();
              _openInventoryAdjustment();
            },
            icon: const Icon(LucideIcons.warehouse),
            label: Text('variant_dialog.adjust_stock'.tr()),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    // Capture bloc reference before any async operations
    final bloc = widget.variantsBloc ?? context.read<ProductVariantsBloc>();

    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_duplicateError != null) {
      setState(() => _errorMessage = _duplicateError);
      return;
    }

    await _ensureVariantSkuSuffix();
    if (_skuError != null) {
      setState(() => _errorMessage = 'variant_dialog.fix_errors'.tr());
      return;
    }

    if (_skuError != null || _barcodeError != null) {
      setState(() => _errorMessage = 'variant_dialog.fix_errors'.tr());
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      if (_isEditing) {
        // NOTE: stockQuantity is NEVER written from this form. The
        // defense-in-depth guard in `VariantLocalDatasource.updateVariant`
        // forcibly preserves the stored on-hand value. Stock mutations go
        // exclusively through `InventoryAdjustmentService` via the
        // "Adjust Inventory" button above.
        //
        // Similarly, `costCents` is retained (WAC-managed by purchases /
        // revaluation adjustments). We still pass the current Decimal down
        // because the entity requires it; the guard ensures the DB value
        // cannot drift even if a malformed state gets through here.
        final updatedVariant = ProductVariant(
          id: widget.variant!.id,
          productId: widget.productId,
          sku: _skuController.text.isEmpty ? null : _skuController.text.trim(),
          barcode: _barcodeController.text.isEmpty
              ? null
              : _barcodeController.text.trim(),
          colorId: _colorId,
          sizeId: _sizeId,
          costCents: _costCents,
          priceCents: _priceCents,
          wholesalePriceCents: _wholesalePriceCents,
          priceAdjustmentCents: widget.variant!.priceAdjustmentCents,
          stockQuantity: widget.variant!.stockQuantity,
          isActive: _isActive,
        );
        bloc.add(VariantUpdateRequested(updatedVariant));
      } else {
        final stock = MeasuredQuantity.parseToStored(
          _stockController.text,
          MeasurementType.fromDb(widget.measurementType).majorUnit,
        );
        bloc.add(
          VariantCreateRequested(
            productId: widget.productId,
            sku: _skuController.text.isEmpty
                ? null
                : _skuController.text.trim(),
            barcode: _barcodeController.text.isEmpty
                ? null
                : _barcodeController.text.trim(),
            colorId: _colorId,
            sizeId: _sizeId,
            costCents: _costCents,
            priceCents: _priceCents,
            wholesalePriceCents: _wholesalePriceCents,
            stockQuantity: stock,
          ),
        );
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isEditing
                  ? 'variant_dialog.updated'.tr()
                  : 'variant_dialog.created'.tr(),
            ),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }
}
