import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/di/injection_container.dart';
import '../../domain/entities/product_color_entity.dart';
import '../../domain/entities/product_variant_entity.dart';
import '../../domain/entities/size_entity.dart';
import '../../domain/repositories/product_variant_repository.dart';
import '../../domain/repositories/product_repository.dart';
import '../bloc/product_variants_bloc.dart';
import '../bloc/colors_bloc.dart';
import '../bloc/sizes_bloc.dart';
import 'money_input_widget.dart';

/// Reusable dialog for creating/editing a product variant.
/// Full-featured with: Attributes, Identity (SKU/Barcode), Pricing, Inventory, Status, Print, Delete.
class VariantEditDialog extends StatefulWidget {
  final int productId;
  final String? productName;
  final ProductVariant? variant;
  final ProductVariantsBloc? variantsBloc;

  const VariantEditDialog({
    super.key,
    required this.productId,
    this.productName,
    this.variant,
    this.variantsBloc,
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
  final _adjustController = TextEditingController();

  
  int? _colorId;
  int? _sizeId;
  Decimal _costCents = Decimal.zero;
  Decimal _priceCents = Decimal.zero;
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
      _stockController.text = v.stockQuantity.toString();
      _colorId = v.colorId;
      _sizeId = v.sizeId;
      _costCents = v.costCents;
      _priceCents = v.priceCents;
      _isActive = v.isActive;
    } else {
      _stockController.text = '0';
      _loadDefaultsForNewVariant();
    }
    _adjustController.text = '0';
  }

  Future<void> _loadDefaultsForNewVariant() async {
    try {
      final productRepo = sl<ProductRepository>();
      final product = await productRepo.watchProduct(widget.productId).first;
      if (!mounted || product == null) return;

      setState(() {
        _costCents = product.costCents;
        _priceCents = product.priceCents;
        _baseSku = (product.sku ?? '').trim();

        if (_skuController.text.trim().isEmpty && _baseSku != null && _baseSku!.isNotEmpty) {
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
    _adjustController.dispose();
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
              title: Text(_isEditing
                  ? 'variant_dialog.edit_title'.tr()
                  : 'variant_dialog.add_title'.tr()),
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
                    if (_errorMessage != null)
                      _buildErrorBanner(colorScheme),
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
                    if (_isEditing) ...
                      [
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
              if (_isEditing) ...
                [
                  Chip(
                    label: Text('#${widget.variant!.id}'),
                    visualDensity: VisualDensity.compact,
                  ),
                  const SizedBox(width: 8),
                  Chip(
                    label: Text(_isActive
                        ? 'variant_dialog.active'.tr()
                        : 'variant_dialog.inactive'.tr()),
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
          if (widget.productName != null) ...
            [
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

  Widget _buildSectionTitle(String title, IconData icon, ColorScheme colorScheme) {
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
                        ...filtered.map((color) => ListTile(
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
                            )),
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
                        ...filtered.map((size) => ListTile(
                              leading: const Icon(LucideIcons.ruler),
                              title: Text(size.name),
                              selected: _sizeId == size.id,
                              onTap: () {
                                setState(() => _sizeId = size.id);
                                _checkDuplicateCombination();
                                Navigator.pop(ctx);
                              },
                            )),
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
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.outline,
                  ),
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
        if (_priceCents < _costCents && _priceCents > Decimal.zero)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                Icon(LucideIcons.alertTriangle,
                    size: 16, color: colorScheme.tertiary),
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
        if (_isEditing) ...
          [
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
                    _currentStock.toString(),
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
            const SizedBox(height: 16),
            Text(
              'variant_dialog.adjust_stock'.tr(),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.outline,
                  ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _buildQuickAdjustButton(-10, colorScheme),
                const SizedBox(width: 8),
                _buildQuickAdjustButton(-1, colorScheme),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: _adjustController,
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                        signed: true),
                  ),
                ),
                const SizedBox(width: 8),
                _buildQuickAdjustButton(1, colorScheme),
                const SizedBox(width: 8),
                _buildQuickAdjustButton(10, colorScheme),
              ],
            ),
            const SizedBox(height: 8),
            Builder(builder: (context) {
              final adj = int.tryParse(_adjustController.text) ?? 0;
              final newStock = _currentStock + adj;
              if (adj == 0) return const SizedBox.shrink();
              return Text(
                'variant_dialog.new_stock_preview'.tr(args: [newStock.toString()]),
                style: TextStyle(
                  color: newStock < 0 ? colorScheme.error : colorScheme.primary,
                  fontWeight: FontWeight.w500,
                ),
              );
            }),
          ]
        else ...
          [
            TextFormField(
              controller: _stockController,
              decoration: InputDecoration(
                labelText: 'variant_dialog.initial_stock'.tr(),
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(LucideIcons.package),
              ),
              keyboardType: TextInputType.number,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'common.required'.tr();
                }
                final n = int.tryParse(value);
                if (n == null || n < 0) {
                  return 'variant_dialog.invalid_stock'.tr();
                }
                return null;
              },
            ),
          ],
      ],
    );
  }

  Widget _buildQuickAdjustButton(int delta, ColorScheme colorScheme) {
    final isPositive = delta > 0;
    return Material(
      color: isPositive
          ? colorScheme.primaryContainer
          : colorScheme.errorContainer,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: () {
          final current = int.tryParse(_adjustController.text) ?? 0;
          setState(() {
            _adjustController.text = (current + delta).toString();
          });
        },
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            '${isPositive ? '+' : ''}$delta',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isPositive
                  ? colorScheme.onPrimaryContainer
                  : colorScheme.onErrorContainer,
            ),
          ),
        ),
      ),
    );
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
          subtitle: Text('variant_dialog.active_hint'.tr()),
          value: _isActive,
          onChanged: (value) => setState(() => _isActive = value),
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('variant_dialog.copied'.tr())),
    );
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
        _duplicateError = exists ? 'variant_dialog.duplicate_combination'.tr() : null;
      });
    } catch (_) {
      setState(() => _duplicateError = null);
    }
  }

  void _printLabel() {
    if (widget.variant == null) return;
    final v = widget.variant!;
    context.push(
      '/products/barcode-design',
      extra: {
        'variantId': v.id,
        'barcode': v.barcode,
        'productId': v.productId,
      },
    );
  }

  void _confirmDelete() {
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
        context
            .read<ProductVariantsBloc>()
            .add(VariantDeleteRequested(widget.variant!.id));
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('variant_dialog.deleted'.tr())),
        );
      }
    });
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
        final adj = int.tryParse(_adjustController.text) ?? 0;
        final newStock = _currentStock + adj;
        if (newStock < 0) {
          setState(() {
            _errorMessage = 'variant_dialog.stock_negative'.tr();
            _isLoading = false;
          });
          return;
        }

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
          priceAdjustmentCents: widget.variant!.priceAdjustmentCents,
          stockQuantity: newStock,
          isActive: _isActive,
        );
        bloc.add(VariantUpdateRequested(updatedVariant));
      } else {
        final stock = int.parse(_stockController.text);
        bloc.add(VariantCreateRequested(
          productId: widget.productId,
          sku: _skuController.text.isEmpty ? null : _skuController.text.trim(),
          barcode: _barcodeController.text.isEmpty
              ? null
              : _barcodeController.text.trim(),
          colorId: _colorId,
          sizeId: _sizeId,
          costCents: _costCents,
          priceCents: _priceCents,
          stockQuantity: stock,
        ));
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isEditing
                ? 'variant_dialog.updated'.tr()
                : 'variant_dialog.created'.tr()),
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
