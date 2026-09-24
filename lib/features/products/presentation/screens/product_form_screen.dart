import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../../../core/database/daos/product_dao.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/services/feature_gate_service.dart';
import '../../../../core/services/inventory/inventory_stock_source_service.dart';
import '../../../../core/services/lan/lan_network_service.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/widgets/theme_toggle_button.dart';
import '../../../../core/widgets/inputs/select_all_on_focus.dart';
import '../../../../core/measurement/measurement.dart';
import '../../../../core/measurement/measurement_localization.dart';
import '../../../subscription/presentation/widgets/upgrade_prompt.dart';
import '../../domain/entities/price_history_entity.dart';
import '../../domain/entities/product_entity.dart';
import '../../domain/entities/product_variant_entity.dart';
import '../../domain/entities/category_entity.dart';
import '../../domain/repositories/product_repository.dart';
import '../../domain/repositories/product_variant_repository.dart';
import '../bloc/product_form_bloc.dart';
import '../bloc/product_variants_bloc.dart';
import '../bloc/categories_bloc.dart';
import '../bloc/colors_bloc.dart';
import '../bloc/colors_event.dart';
import '../bloc/sizes_bloc.dart';
import '../bloc/sizes_event.dart';
import '../bloc/categories_event.dart';
import '../widgets/money_input_widget.dart';
import '../widgets/variant_management_widget.dart';
import '../widgets/inventory_adjustment_dialog.dart';
import '../widgets/medicine_alternatives_dialog.dart';
import '../widgets/medicine_profile_form_section.dart';
import '../../domain/entities/product_color_entity.dart';
import '../../domain/entities/size_entity.dart';
import '../../../settings/presentation/bloc/app_settings_bloc.dart';
import '../../../barcode/services/barcode_generation_service.dart';
import '../../../inventory/presentation/widgets/batches_section_widget.dart';

class ProductFormScreen extends StatelessWidget {
  final int? productId;
  final String? initialBarcode;

  const ProductFormScreen({super.key, this.productId, this.initialBarcode});

  @override
  Widget build(BuildContext context) {
    // Get inventory settings from AppSettingsBloc for new products
    final appSettingsState = context.read<AppSettingsBloc>().state;
    final settings = appSettingsState.settings;

    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (context) => sl<ProductFormBloc>()
            ..add(
              ProductFormInitialized(
                productId: productId,
                initialBarcode: initialBarcode,
                defaultTrackInventory: settings.defaultTrackInventory,
                // New products inherit the global `lowStockThreshold` from
                // settings as their initial per-product re-order point. The
                // user can still override the value per-product in the form
                // before saving. This restores the pre-Phase-B behaviour that
                // was inadvertently changed when inventory tracking types
                // were introduced — the global setting is the single source
                // of truth for the *default*, while `products.min_quantity`
                // remains the per-product authoritative value once saved.
                defaultMinQuantity: settings.lowStockThreshold,
                enablePharmacyFeatures: sl<FeatureGateService>().isEnabled(
                  AppFeature.pharmacy,
                  settingEnabled: settings.enablePharmacyFeatures,
                ),
              ),
            ),
        ),
        BlocProvider(
          create: (context) =>
              sl<CategoriesBloc>()..add(const LoadCategories()),
        ),
        BlocProvider(
          create: (context) => sl<ColorsBloc>()..add(const LoadColors()),
        ),
        BlocProvider(
          create: (context) => sl<SizesBloc>()..add(const LoadSizes()),
        ),
        if (productId != null) ...[
          BlocProvider(
            create: (context) =>
                sl<ProductVariantsBloc>()
                  ..add(ProductVariantsInitialized(productId!)),
          ),
        ],
      ],
      child: const _ProductFormView(),
    );
  }
}

class _ProductFormView extends StatefulWidget {
  const _ProductFormView();

  @override
  State<_ProductFormView> createState() => _ProductFormViewState();
}

class _ProductFormViewState extends State<_ProductFormView>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _skuController = TextEditingController();
  final _barcodeController = TextEditingController();
  final _stockController = TextEditingController();
  final _minStockController = TextEditingController();
  final _purchaseTaxRateController = TextEditingController();
  final _salesTaxRateController = TextEditingController();

  final _stockFocusNode = FocusNode();
  final _minStockFocusNode = FocusNode();

  Future<ProductStockSourceSnapshot>? _stockSourcesFuture;
  int? _stockSourcesProductId;

  @override
  void initState() {
    super.initState();
    _stockFocusNode.addListener(
      () => _selectAllOnFocus(_stockFocusNode, _stockController),
    );
    _minStockFocusNode.addListener(
      () => _selectAllOnFocus(_minStockFocusNode, _minStockController),
    );
  }

  void _selectAllOnFocus(
    FocusNode focusNode,
    TextEditingController controller,
  ) {
    if (focusNode.hasFocus) {
      controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: controller.text.length,
      );
    }
  }

  /// Delegates EAN-13 generation to the shared [BarcodeGenerationService] so
  /// every generation path produces a valid checksum (scanner-compatible).
  String _generateBarcode() =>
      sl<BarcodeGenerationService>().generateRandomEan13();

  Future<ProductStockSourceSnapshot> _loadStockSources(int productId) async {
    final lan = sl<LanNetworkService>();
    if (lan.snapshot.mode == LanMode.client && lan.hasRemoteUserSession) {
      final remote = await lan.fetchRemoteInventoryStockSources(
        productId: productId,
      );
      return ProductStockSourceSnapshot(
        productId: remote.productId,
        warehouseId: remote.warehouseId,
        physicalQuantity: remote.physicalQuantity,
        enterpriseQuantity: remote.enterpriseQuantity,
        consignmentQuantity: remote.consignmentQuantity,
        quantityScale: remote.quantityScale,
        measurementType: remote.measurementType,
        reconciled: remote.reconciled,
        sources: remote.sources
            .map(
              (source) => InventoryStockSourceBalance(
                productId: source.productId,
                variantId: source.variantId,
                quantity: source.quantity,
                quantityScale: source.quantityScale,
                measurementType: source.measurementType,
                ownership: InventoryStockOwnership.values.firstWhere(
                  (value) => value.name == source.ownership,
                  orElse: () => InventoryStockOwnership.unverified,
                ),
                variantLabel: source.variantLabel,
                supplierId: source.supplierId,
                supplierName: source.supplierName,
                supplierIdentityId: source.supplierIdentityId,
                consignmentLayerId: source.consignmentLayerId,
                sourceCode: source.sourceCode,
                receiptNumber: source.receiptNumber,
                batchNumber: source.batchNumber,
              ),
            )
            .toList(growable: false),
      );
    }
    return InventoryStockSourceService(sl()).loadProduct(productId);
  }

  Future<ProductStockSourceSnapshot> _stockSources(int productId) {
    if (_stockSourcesFuture == null || _stockSourcesProductId != productId) {
      _stockSourcesProductId = productId;
      _stockSourcesFuture = _loadStockSources(productId);
    }
    return _stockSourcesFuture!;
  }

  void _refreshStockSources(int productId) {
    setState(() {
      _stockSourcesProductId = productId;
      _stockSourcesFuture = _loadStockSources(productId);
    });
  }

  Product _sourceLabelProduct(
    ProductFormState state,
    InventoryStockSourceBalance source,
  ) {
    final supplier = source.supplierName?.trim();
    final ownership = source.isConsignment
        ? 'stock_sources.consignment'.tr()
        : 'stock_sources.enterprise_owned'.tr();
    final variant = source.variantLabel.trim();
    return Product(
      id: state.productId!,
      name: [
        state.name,
        if (variant.isNotEmpty) variant,
        if (supplier?.isNotEmpty == true) supplier!,
        ownership,
      ].join(' / '),
      nameAr: state.nameAr,
      nameFr: state.nameFr,
      description: state.description,
      sku: source.sourceCode,
      barcode: source.sourceCode,
      costCents: state.costCents,
      priceCents: state.priceCents,
      wholesalePriceCents: state.wholesalePriceCents,
      stockQuantity: source.quantity,
      minQuantity: state.minQuantity,
      categoryId: state.categoryId,
      supplierId: source.supplierId,
      currencyId: state.currencyId ?? 1,
      imagePath: state.imagePath,
      hasVariants: false,
      isTaxable: state.isTaxable,
      purchaseTaxRateBps: state.purchaseTaxRateBps,
      salesTaxRateBps: state.salesTaxRateBps,
      isActive: state.isActive,
      trackInventory: state.trackInventory,
      measurementType: state.measurementType,
      costingMethod: state.inventoryTrackingType == 'standard' ? 'wac' : 'fifo',
      inventoryTrackingType: state.inventoryTrackingType,
    );
  }

  void _showPrintModeChoice(BuildContext context, Product product) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'barcode.choose_print_mode'.tr(),
                  style: textTheme.titleLarge,
                ),
                const SizedBox(height: 20),
                _PrintModeOptionCard(
                  icon: LucideIcons.tag,
                  title: 'barcode.thermal_label_title'.tr(),
                  subtitle: 'barcode.thermal_label_desc'.tr(),
                  colorScheme: colorScheme,
                  onTap: () {
                    Navigator.pop(ctx);
                    context.push('/barcode-designer', extra: product);
                  },
                ),
                const SizedBox(height: 12),
                _PrintModeOptionCard(
                  icon: LucideIcons.layoutGrid,
                  title: 'barcode.a4_sheet_title'.tr(),
                  subtitle: 'barcode.a4_sheet_desc'.tr(),
                  colorScheme: colorScheme,
                  onTap: () {
                    Navigator.pop(ctx);
                    context.push(
                      '/products/barcode-design',
                      extra: {
                        'products': [product],
                      },
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _skuController.dispose();
    _barcodeController.dispose();
    _stockController.dispose();
    _minStockController.dispose();
    _purchaseTaxRateController.dispose();
    _salesTaxRateController.dispose();
    _stockFocusNode.dispose();
    _minStockFocusNode.dispose();
    super.dispose();
  }

  void _initControllers(ProductFormState state) {
    if (_nameController.text.isEmpty && state.name.isNotEmpty) {
      _nameController.text = state.name;
    }
    if (_descriptionController.text.isEmpty && state.description != null) {
      _descriptionController.text = state.description!;
    }
    if (_skuController.text.isEmpty && state.sku != null) {
      _skuController.text = state.sku!;
    }
    if (_barcodeController.text.isEmpty && state.barcode != null) {
      _barcodeController.text = state.barcode!;
    }
    if (!_stockFocusNode.hasFocus) {
      _stockController.text = MeasuredQuantity.majorValue(
        state.stockQuantity,
        MeasurementType.fromDb(state.measurementType),
      );
    }
    if (!_minStockFocusNode.hasFocus) {
      _minStockController.text = MeasuredQuantity.majorValue(
        state.minQuantity,
        MeasurementType.fromDb(state.measurementType),
      );
    }
    if (_purchaseTaxRateController.text.isEmpty &&
        state.purchaseTaxRateBps > 0) {
      _purchaseTaxRateController.text = (state.purchaseTaxRateBps / 100)
          .toString();
    }
    if (_salesTaxRateController.text.isEmpty && state.salesTaxRateBps > 0) {
      _salesTaxRateController.text = (state.salesTaxRateBps / 100).toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          context.pop();
        },
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
          context.read<ProductFormBloc>().add(const ProductFormSubmitted());
        },
      },
      child: Focus(
        autofocus: true,
        child: BlocConsumer<ProductFormBloc, ProductFormState>(
          listener: (context, state) {
            if (state.isSuccess) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    state.isEditing
                        ? 'product_updated'.tr()
                        : 'product_created'.tr(),
                  ),
                  backgroundColor: colorScheme.primary,
                ),
              );
              Navigator.of(context).pop(true);
            }

            if (state.error != null) {
              final quota = parseQuotaError(state.error);
              if (quota != null) {
                showQuotaExceededDialog(
                  context,
                  isProducts: quota.isProducts,
                  limit: quota.limit,
                );
              } else if (state.error!.startsWith('variant_stock_conflict:')) {
                final count = int.tryParse(state.error!.split(':').last) ?? 1;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'product_form.hasVariants_stock_blocked'.tr(
                        args: [count.toString()],
                      ),
                    ),
                    backgroundColor: colorScheme.error,
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('product_form.error_saving'.tr()),
                    backgroundColor: colorScheme.error,
                  ),
                );
              }
            }

            _initControllers(state);
          },
          builder: (context, state) {
            if (state.isLoading) {
              return Scaffold(
                appBar: AppBar(
                  leading: IconButton(
                    icon: const Icon(LucideIcons.arrowLeft),
                    onPressed: () => context.pop(),
                    tooltip: 'common.back'.tr(),
                  ),
                  title: Text('product_form.title'.tr()),
                  centerTitle: true,
                ),
                body: const Center(child: CircularProgressIndicator()),
              );
            }

            return Scaffold(
              appBar: AppBar(
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () {
                    if (context.canPop()) {
                      context.pop();
                    } else {
                      context.go('/products');
                    }
                  },
                  tooltip: 'common.back'.tr(),
                ),
                title: Text(
                  state.isEditing
                      ? 'product_form.edit'.tr()
                      : 'product_form.create'.tr(),
                ),
                centerTitle: true,
                actions: [
                  const ThemeToggleButton(),
                  if (state.isEditing) ...[
                    IconButton(
                      icon: const Icon(LucideIcons.printer),
                      onPressed: () {
                        if (state.productId == null) return;

                        final product = Product(
                          id: state.productId!,
                          name: state.name,
                          nameAr: state.nameAr,
                          nameFr: state.nameFr,
                          description: state.description,
                          sku: state.sku,
                          barcode: state.barcode,
                          costCents: state.costCents,
                          priceCents: state.priceCents,
                          wholesalePriceCents: state.wholesalePriceCents,
                          stockQuantity: state.stockQuantity,
                          minQuantity: state.minQuantity,
                          categoryId: state.categoryId,
                          supplierId: state.supplierId,
                          currencyId:
                              state.currencyId ?? 1, // Default if not set
                          imagePath: state.imagePath,
                          hasVariants: state.hasVariants,
                          isTaxable: state.isTaxable,
                          purchaseTaxRateBps: state.purchaseTaxRateBps,
                          salesTaxRateBps: state.salesTaxRateBps,
                          isActive: state.isActive,
                          trackInventory: state.trackInventory,
                          measurementType: state.measurementType,
                        );
                        _showPrintModeChoice(context, product);
                      },
                      tooltip: 'edit_prices.print_label'.tr(),
                    ),
                    IconButton(
                      icon: const Icon(LucideIcons.trash2),
                      onPressed: state.isSubmitting
                          ? null
                          : () => _handleSmartDelete(context, state),
                      tooltip: 'common.delete'.tr(),
                    ),
                  ],
                  if (state.isSubmitting)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else
                    IconButton(
                      icon: const Icon(LucideIcons.save),
                      onPressed: () {
                        context.read<ProductFormBloc>().add(
                          const ProductFormSubmitted(),
                        );
                      },
                      tooltip: 'common.save'.tr(),
                    ),
                ],
              ),
              body: LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth > 800;

                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Form(
                      key: _formKey,
                      child: isWide
                          ? _buildWideLayout(context, state)
                          : _buildNarrowLayout(context, state),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildWideLayout(BuildContext context, ProductFormState state) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 2,
          child: Column(
            children: [
              _buildBasicInfoSection(context, state),
              const SizedBox(height: 24),
              _buildPricingSection(context, state),
              const SizedBox(height: 24),
              _buildInventorySection(context, state),
              if (state.pharmacyEditorEnabled) ...[
                const SizedBox(height: 24),
                MedicineProfileFormSection(
                  state: state,
                  onShowAlternatives: state.productId == null
                      ? null
                      : () => MedicineAlternativesDialog.show(
                          context,
                          productId: state.productId!,
                        ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 24),
        Expanded(
          child: Column(
            children: [
              _buildTaxSection(context, state),
              const SizedBox(height: 24),
              _buildOptionsSection(context, state),
              AnimatedSize(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                alignment: Alignment.topCenter,
                child: state.hasVariants
                    ? Padding(
                        padding: const EdgeInsets.only(top: 24),
                        child: _buildVariantsSection(context, state),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNarrowLayout(BuildContext context, ProductFormState state) {
    return Column(
      children: [
        _buildBasicInfoSection(context, state),
        const SizedBox(height: 24),
        _buildPricingSection(context, state),
        const SizedBox(height: 24),
        _buildInventorySection(context, state),
        if (state.pharmacyEditorEnabled) ...[
          const SizedBox(height: 24),
          MedicineProfileFormSection(
            state: state,
            onShowAlternatives: state.productId == null
                ? null
                : () => MedicineAlternativesDialog.show(
                    context,
                    productId: state.productId!,
                  ),
          ),
        ],
        const SizedBox(height: 24),
        _buildTaxSection(context, state),
        const SizedBox(height: 24),
        _buildOptionsSection(context, state),
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: state.hasVariants
              ? Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: _buildVariantsSection(context, state),
                )
              : const SizedBox.shrink(),
        ),
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);

    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      alignment: Alignment.topCenter,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 20, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ...children,
            ],
          ),
        ),
      ),
    );
  }

  /// Displays an informational warning (non-blocking) beneath a form field.
  /// Used for soft validations like price-below-cost or zero-cost/price, in
  /// the spirit of QuickBooks/Xero/Odoo which warn but do not reject.
  Widget _buildWarningHint(BuildContext context, String translationKey) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 6, left: 4, right: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            LucideIcons.alertTriangle,
            size: 14,
            color: theme.colorScheme.tertiary,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              translationKey.tr(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.tertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Opens the accounting-safe Inventory Adjustment dialog for the default
  /// variant of a simple (non-variant) product. Looks up the default
  /// variant so the adjustment is booked against the correct SKU (cost
  /// and stock live on the variant row, not the product row).
  ///
  /// Falls back to product-level values if the default variant cannot be
  /// resolved — in that case the dialog still posts correctly because
  /// the service reads on-hand / cost from the DB itself.
  Future<void> _openInventoryAdjustmentForDefaultVariant(
    BuildContext context, {
    required int productId,
    required int fallbackStock,
    required int fallbackCostCents,
  }) async {
    final variantRepo = sl<ProductVariantRepository>();
    // Use the repository helper which (a) prefers the strict default variant
    // (color_id IS NULL AND size_id IS NULL) and (b) falls back to ANY
    // variant of the product. Passing variantId=null to the adjustment
    // service while no strict-default variant exists causes StockService to
    // silently update zero variant rows, after which
    // syncProductStockFromVariants rewrites products.stock_quantity back to
    // its pre-adjustment value — producing a posted journal entry with no
    // matching stock movement (accounting ↔ inventory desync).
    final defaultVariant = await variantRepo.getDefaultVariantByProduct(
      productId,
    );
    if (!context.mounted) return;

    final posted = await InventoryAdjustmentDialog.show(
      context,
      productId: productId,
      variantId: defaultVariant?.id,
      currentStock: defaultVariant?.stockQuantity ?? fallbackStock,
      currentUnitCostCents:
          defaultVariant?.costCents.toBigInt().toInt() ?? fallbackCostCents,
    );
    if (posted == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('inventory_adjustment.posted_success'.tr())),
      );
    }
  }

  Future<void> _pickImage(ProductFormBloc bloc) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      bloc.add(
        ProductFormFieldChanged(field: 'imagePath', value: pickedFile.path),
      );
    }
  }

  Widget _buildBasicInfoSection(BuildContext context, ProductFormState state) {
    final bloc = context.read<ProductFormBloc>();

    return _buildSectionCard(
      title: 'product_form_basicInfo'.tr(),
      icon: LucideIcons.package,
      children: [
        Center(
          child: GestureDetector(
            onTap: () => _pickImage(bloc),
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
                image: state.imagePath != null
                    ? DecorationImage(
                        image: FileImage(File(state.imagePath!)),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: state.imagePath == null
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          LucideIcons.imagePlus,
                          size: 32,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'product_form_tap_to_add_image'.tr(),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    )
                  : null,
            ),
          ),
        ),
        const SizedBox(height: 24),
        TextFormField(
          controller: _nameController,
          decoration: InputDecoration(
            labelText: 'product_form_name'.tr(),
            errorText: state.fieldErrors['name']?.tr(),
            border: const OutlineInputBorder(),
          ),
          onChanged: (value) {
            bloc.add(ProductFormFieldChanged(field: 'name', value: value));
          },
        ),
        const SizedBox(height: 16),
        if (!state.hasVariants)
          _ColorSizePickerRow(
            selectedColorId: state.selectedColorId,
            selectedSizeId: state.selectedSizeId,
            onColorSelected: (id) => bloc.add(
              ProductFormFieldChanged(field: 'selectedColorId', value: id),
            ),
            onSizeSelected: (id) => bloc.add(
              ProductFormFieldChanged(field: 'selectedSizeId', value: id),
            ),
          )
        else
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Theme.of(
                  context,
                ).colorScheme.outline.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  LucideIcons.layers,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'product_form.color_size_disabled_when_has_variants'.tr(),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 16),
        _buildCategoryPicker(context, state),
        const SizedBox(height: 16),
        TextFormField(
          controller: _descriptionController,
          decoration: InputDecoration(
            labelText: 'product_form_description'.tr(),
            border: const OutlineInputBorder(),
          ),
          maxLines: 3,
          onChanged: (value) {
            bloc.add(
              ProductFormFieldChanged(field: 'description', value: value),
            );
          },
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _skuController,
                decoration: InputDecoration(
                  labelText: 'product_form_sku'.tr(),
                  errorText: state.fieldErrors['sku']?.tr(
                    args: [state.sku ?? ''],
                  ),
                  border: const OutlineInputBorder(),
                ),
                onChanged: (value) {
                  bloc.add(ProductFormFieldChanged(field: 'sku', value: value));
                },
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TextFormField(
                controller: _barcodeController,
                decoration: InputDecoration(
                  labelText: 'product_form_barcode'.tr(),
                  errorText: state.fieldErrors['barcode']?.tr(
                    args: [state.barcode ?? ''],
                  ),
                  border: const OutlineInputBorder(),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(LucideIcons.sparkles),
                        tooltip: 'barcode.auto_generate'.tr(),
                        onPressed: () {
                          final barcode = _generateBarcode();
                          _barcodeController.text = barcode;
                          bloc.add(
                            ProductFormFieldChanged(
                              field: 'barcode',
                              value: barcode,
                            ),
                          );
                        },
                      ),
                      IconButton(
                        icon: const Icon(LucideIcons.scanLine),
                        tooltip: 'barcode.scan'.tr(),
                        onPressed: () async {
                          final result = await context.push<String>(
                            '/barcode-scanner',
                          );
                          if (result != null && result.isNotEmpty && mounted) {
                            _barcodeController.text = result;
                            bloc.add(
                              ProductFormFieldChanged(
                                field: 'barcode',
                                value: result,
                              ),
                            );
                          }
                        },
                      ),
                    ],
                  ),
                ),
                onChanged: (value) {
                  bloc.add(
                    ProductFormFieldChanged(field: 'barcode', value: value),
                  );
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCategoryPicker(BuildContext context, ProductFormState state) {
    return BlocBuilder<CategoriesBloc, RealtimeState<List<Category>>>(
      builder: (context, categoriesState) {
        final categories = categoriesState is RealtimeSuccess<List<Category>>
            ? categoriesState.data
            : <Category>[];
        final selected = state.categoryId == null
            ? null
            : categories.cast<Category?>().firstWhere(
                (c) => c?.id == state.categoryId,
                orElse: () => null,
              );

        return InkWell(
          onTap: () =>
              _showCategoryPickerBottomSheet(context, state.categoryId),
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: 'product_form.category'.tr(),
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(LucideIcons.tags),
            ),
            child: Text(selected?.name ?? 'common.none'.tr()),
          ),
        );
      },
    );
  }

  Future<void> _showCategoryPickerBottomSheet(
    BuildContext context,
    int? currentId,
  ) async {
    final categoriesBloc = context.read<CategoriesBloc>();
    final bloc = context.read<ProductFormBloc>();

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
                      prefixIcon: const Icon(LucideIcons.search),
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (v) => categoriesBloc.add(SearchCategories(v)),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      onPressed: () =>
                          sheetContext.push('/products/categories'),
                      icon: const Icon(LucideIcons.settings),
                      label: Text('categories.title'.tr()),
                    ),
                  ),
                  Flexible(
                    child:
                        BlocBuilder<
                          CategoriesBloc,
                          RealtimeState<List<Category>>
                        >(
                          bloc: categoriesBloc,
                          builder: (context, state) {
                            final categories =
                                state is RealtimeSuccess<List<Category>>
                                ? state.data
                                : <Category>[];
                            return ListView.builder(
                              shrinkWrap: true,
                              itemCount: categories.length + 1,
                              itemBuilder: (context, index) {
                                if (index == 0) {
                                  return ListTile(
                                    title: Text('common.none'.tr()),
                                    onTap: () =>
                                        Navigator.of(context).pop(null),
                                  );
                                }
                                final cat = categories[index - 1];
                                return ListTile(
                                  title: Text(cat.name),
                                  onTap: () =>
                                      Navigator.of(context).pop(cat.id),
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
    if (selectedId != null || currentId != null) {
      bloc.add(ProductFormFieldChanged(field: 'categoryId', value: selectedId));
    }
  }

  Widget _buildPricingSection(BuildContext context, ProductFormState state) {
    final bloc = context.read<ProductFormBloc>();

    return _buildSectionCard(
      title: 'product_form_pricing'.tr(),
      icon: LucideIcons.dollarSign,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MoneyInputWidget(
                    value: state.costCents,
                    label: 'product_form_cost'.tr(),
                    errorText: state.fieldErrors['costCents']?.tr(),
                    // Cost is WAC-managed once the product exists: updated
                    // only through purchases (moving average) and manual
                    // Inventory Revaluation adjustments. Matches
                    // QuickBooks / Xero / Odoo behaviour.
                    enabled: !state.isEditing,
                    hint: state.isEditing
                        ? 'products.cost_readonly_hint'.tr()
                        : null,
                    onChanged: (value) {
                      bloc.add(
                        ProductFormFieldChanged(
                          field: 'costCents',
                          value: value,
                        ),
                      );
                    },
                  ),
                  if (state.fieldErrors['costCents'] == null &&
                      state.fieldWarnings['costCents'] != null)
                    _buildWarningHint(
                      context,
                      state.fieldWarnings['costCents']!,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MoneyInputWidget(
                    value: state.priceCents,
                    label: 'product_form_price'.tr(),
                    errorText: state.fieldErrors['priceCents']?.tr(),
                    onChanged: (value) {
                      bloc.add(
                        ProductFormFieldChanged(
                          field: 'priceCents',
                          value: value,
                        ),
                      );
                    },
                  ),
                  if (state.fieldErrors['priceCents'] == null &&
                      state.fieldWarnings['priceCents'] != null)
                    _buildWarningHint(
                      context,
                      state.fieldWarnings['priceCents']!,
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: MoneyInputWidget(
                value: state.wholesalePriceCents ?? Decimal.zero,
                label: 'product_form_wholesalePrice'.tr(),
                onChanged: (value) {
                  bloc.add(
                    ProductFormFieldChanged(
                      field: 'wholesalePriceCents',
                      value: value == Decimal.zero ? null : value,
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Card(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'product_form_margin'.tr(),
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      const SizedBox(height: 8),
                      MarginDisplayWidget(
                        costCents: state.costCents,
                        priceCents: state.priceCents,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        // Price & cost *range* card + "Apply to all variants" button — for
        // editing products with variants. Product-level cost/price act as a
        // bulk template that the user can push down to every variant, while
        // the actual ground-truth prices are shown as min–max ranges derived
        // from the variants themselves (Shopify / WooCommerce behaviour).
        if (state.hasVariants &&
            state.isEditing &&
            state.productId != null) ...[
          const SizedBox(height: 16),
          _VariantPriceRangeCard(productId: state.productId!),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _applyPriceToAllVariants(context, state),
              icon: const Icon(LucideIcons.layers, size: 18),
              label: Text('product_form_apply_to_variants'.tr()),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
        if (state.isEditing && state.productId != null) ...[
          const SizedBox(height: 16),
          _PriceHistoryWidget(productId: state.productId!),
        ],
      ],
    );
  }

  /// Smart-delete entry point. Pre-counts historical references and current
  /// on-hand stock, then presents a dialog whose body and action change with
  /// the four possible (refs, stock) combinations:
  ///
  ///   refs=0, stock=0 → hard delete         (no GL impact)
  ///   refs>0, stock=0 → deactivate          (preserve audit trail)
  ///   stock>0         → write-off + delete  (post Shrinkage Dr 5800 / Cr 1200)
  ///
  /// The write-off branch keeps the 1200 Inventory ledger in sync with
  /// Σ(stock × cost), matching IFRS/GAAP expectations.
  Future<void> _handleSmartDelete(
    BuildContext context,
    ProductFormState state,
  ) async {
    final id = state.productId;
    if (id == null) return;
    final repo = sl<ProductRepository>();
    final colorScheme = Theme.of(context).colorScheme;

    int refCount;
    try {
      refCount = await repo.countProductReferences(id);
    } catch (_) {
      refCount = -1; // unknown -> treat as "may have refs", proceed cautiously
    }

    // Always read stock fresh from DB so the dialog never lies based on
    // stale form state (the form may have been opened before a recent
    // purchase / sale changed on-hand).
    int stockQty;
    try {
      final fresh = await repo.getProductById(id);
      stockQty = fresh?.stockQuantity ?? 0;
    } catch (_) {
      stockQty = state.stockQuantity;
    }
    if (!context.mounted) return;

    final willDeactivate = refCount != 0;
    final hasStock = stockQty > 0;
    final displayedStock = localizedQuantity(stockQty, state.measurementType);

    // Branch 1: stock>0 → mandatory shrinkage write-off path.
    if (hasStock) {
      final body = willDeactivate
          ? (refCount > 0
                ? 'product_form.writeoff_deactivate_body'.tr(
                    args: [displayedStock, refCount.toString()],
                  )
                : 'product_form.writeoff_deactivate_body_unknown'.tr(
                    args: [displayedStock],
                  ))
          : 'product_form.writeoff_delete_body'.tr(args: [displayedStock]);

      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: Icon(LucideIcons.alertTriangle, color: colorScheme.error),
          title: Text('product_form.writeoff_title'.tr()),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('common.cancel'.tr()),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: colorScheme.error),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text('product_form.writeoff_action'.tr()),
            ),
          ],
        ),
      );
      if (ok != true || !context.mounted) return;

      try {
        final result = await repo.writeOffAndDeleteProduct(
          productId: id,
          reason: 'product_form.writeoff_reason'.tr(),
        );
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.wasDeleted
                  ? 'product_form.writeoff_deleted_success'.tr()
                  : 'product_form.writeoff_deactivated_success'.tr(
                      args: [result.referenceCount.toString()],
                    ),
            ),
            backgroundColor: result.wasDeleted
                ? colorScheme.primary
                : colorScheme.tertiary,
          ),
        );
        context.go('/products');
      } catch (_) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('product_form.error_saving'.tr()),
            backgroundColor: colorScheme.error,
          ),
        );
      }
      return;
    }

    // Branch 2: stock=0 → original smart-delete flow.
    final title = willDeactivate
        ? 'product_form.deactivate_title'.tr()
        : 'product_form.delete_title'.tr();
    final body = willDeactivate
        ? 'product_form.deactivate_body'.tr(args: [refCount.toString()])
        : 'product_form.delete_body'.tr();
    final actionLabel = willDeactivate
        ? 'product_form.deactivate_action'.tr()
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
              backgroundColor: willDeactivate
                  ? colorScheme.tertiary
                  : colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(actionLabel),
          ),
        ],
      ),
    );

    if (ok != true || !context.mounted) return;

    try {
      final result = await repo.smartDeleteProduct(id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.wasDeleted
                ? 'product_form.deleted_success'.tr()
                : 'product_form.deactivated_success'.tr(
                    args: [result.referenceCount.toString()],
                  ),
          ),
          backgroundColor: result.wasDeleted
              ? colorScheme.primary
              : colorScheme.tertiary,
        ),
      );
      context.go('/products');
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('product_form.error_saving'.tr()),
          backgroundColor: colorScheme.error,
        ),
      );
    }
  }

  /// Confirmation dialog shown before turning "Has Variants" off while active
  /// dimensional variants still exist. Displays the exact count so the user
  /// understands the soft-delete scope.
  Future<bool> _confirmDisableVariants(BuildContext context, int count) async {
    final cs = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(LucideIcons.alertTriangle, color: cs.tertiary),
        title: Text('product_form.hasVariants_disable_title'.tr()),
        content: Text(
          'product_form.hasVariants_disable_body'.tr(args: [count.toString()]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: cs.tertiary),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('product_form.hasVariants_disable_action'.tr()),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _showVariantStockBlock(BuildContext context, int count) {
    final cs = Theme.of(context).colorScheme;
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(LucideIcons.packageX, color: cs.error),
        title: Text('product_form.hasVariants_stock_title'.tr()),
        content: Text(
          'product_form.hasVariants_stock_blocked'.tr(args: [count.toString()]),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('common.ok'.tr()),
          ),
        ],
      ),
    );
  }

  Future<void> _applyPriceToAllVariants(
    BuildContext context,
    ProductFormState state,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('edit_prices.apply_to_all_variants'.tr()),
        content: Text('edit_prices.apply_to_variants_confirm'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('common.apply'.tr()),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    try {
      final variantRepo = sl<ProductVariantRepository>();
      final variants = await variantRepo.getVariantsByProduct(state.productId!);

      // IMPORTANT: only sale and wholesale prices propagate to variants.
      // `costCents` is intentionally NOT applied here because changing a
      // variant's cost without an inventory revaluation journal entry would
      // break the GL ↔ stock invariant (the defense-in-depth layer in
      // `VariantLocalDatasource.updateVariant` would silently revert it
      // anyway). To change cost, the user must run an Inventory Revaluation
      // adjustment which posts the proper Dr/Cr against 1200 / 5900.
      for (final variant in variants) {
        if (!variant.isActive) continue;
        await variantRepo.updateVariant(
          variant.copyWith(
            priceCents: state.priceCents,
            wholesalePriceCents: state.wholesalePriceCents,
          ),
        );
      }

      if (!context.mounted) return;
      final cs = Theme.of(context).colorScheme;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 5),
          backgroundColor: cs.primary,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('product_form_variants_price_updated'.tr()),
              const SizedBox(height: 4),
              Text(
                'product_form.apply_to_variants_cost_note'.tr(),
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onPrimary.withValues(alpha: 0.85),
                ),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('edit_prices.save_error'.tr()),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Widget _buildStockSourcesCard(BuildContext context, ProductFormState state) {
    final cs = Theme.of(context).colorScheme;
    return FutureBuilder<ProductStockSourceSnapshot>(
      future: _stockSources(state.productId!),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: const Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.errorContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'stock_sources.load_failed'.tr(),
                  style: TextStyle(
                    color: cs.onErrorContainer,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => _refreshStockSources(state.productId!),
                  icon: const Icon(LucideIcons.refreshCw),
                  label: Text('common.retry'.tr()),
                ),
              ],
            ),
          );
        }
        final data = snapshot.data!;
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(LucideIcons.layers3, color: cs.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'stock_sources.title'.tr(),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => _refreshStockSources(state.productId!),
                    icon: const Icon(LucideIcons.refreshCw),
                    tooltip: 'common.refresh'.tr(),
                  ),
                ],
              ),
              Text(
                'stock_sources.help'.tr(),
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _sourceSummaryChip(
                    'stock_sources.physical'.tr(),
                    localizedQuantity(
                      data.physicalQuantity,
                      data.measurementType,
                    ),
                  ),
                  _sourceSummaryChip(
                    'stock_sources.enterprise_owned'.tr(),
                    localizedQuantity(
                      data.enterpriseQuantity,
                      data.measurementType,
                    ),
                  ),
                  _sourceSummaryChip(
                    'stock_sources.consignment'.tr(),
                    localizedQuantity(
                      data.consignmentQuantity,
                      data.measurementType,
                    ),
                  ),
                ],
              ),
              if (!data.reconciled) ...[
                const SizedBox(height: 10),
                Text(
                  'stock_sources.legacy_unverified_note'.tr(),
                  style: TextStyle(color: cs.tertiary),
                ),
              ],
              const SizedBox(height: 12),
              if (data.sources.isEmpty)
                Text(
                  'stock_sources.empty'.tr(),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.onSurfaceVariant),
                )
              else
                ...data.sources.map(
                  (source) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _stockSourceTile(context, state, source),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _sourceSummaryChip(String label, String value) {
    return Chip(
      visualDensity: VisualDensity.compact,
      label: Text('$label: $value'),
    );
  }

  Widget _stockSourceTile(
    BuildContext context,
    ProductFormState state,
    InventoryStockSourceBalance source,
  ) {
    final cs = Theme.of(context).colorScheme;
    final isConsignment = source.isConsignment;
    final title = source.supplierName?.trim().isNotEmpty == true
        ? source.supplierName!.trim()
        : 'stock_sources.unverified'.tr();
    final code = source.sourceCode?.trim();
    return Material(
      color: isConsignment
          ? cs.tertiaryContainer.withValues(alpha: 0.45)
          : cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 8, 10),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: isConsignment
                  ? cs.tertiaryContainer
                  : cs.primaryContainer,
              child: Icon(
                isConsignment ? LucideIcons.handshake : LucideIcons.building2,
                color: isConsignment
                    ? cs.onTertiaryContainer
                    : cs.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  if (source.variantLabel.trim().isNotEmpty)
                    Text(
                      source.variantLabel,
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      Text(
                        '${'stock_sources.quantity'.tr()}: '
                        '${localizedQuantity(source.quantity, source.measurementType)}',
                      ),
                      Text(
                        isConsignment
                            ? 'stock_sources.consignment'.tr()
                            : source.ownership ==
                                  InventoryStockOwnership.unverified
                            ? 'stock_sources.unverified'.tr()
                            : 'stock_sources.enterprise_owned'.tr(),
                      ),
                      if (source.receiptNumber?.isNotEmpty == true)
                        Text(
                          '${'stock_sources.receipt'.tr()}: '
                          '${source.receiptNumber}',
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    code?.isNotEmpty == true
                        ? '${'stock_sources.code'.tr()}: $code'
                        : 'stock_sources.no_code'.tr(),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: code?.isNotEmpty == true
                          ? cs.primary
                          : cs.onSurfaceVariant,
                      fontWeight: code?.isNotEmpty == true
                          ? FontWeight.w600
                          : null,
                    ),
                  ),
                ],
              ),
            ),
            if (code?.isNotEmpty == true)
              IconButton(
                onPressed: () => _showPrintModeChoice(
                  context,
                  _sourceLabelProduct(state, source),
                ),
                icon: const Icon(LucideIcons.printer),
                tooltip: 'stock_sources.print_source'.tr(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInventorySection(BuildContext context, ProductFormState state) {
    final bloc = context.read<ProductFormBloc>();
    final productId = state.productId;

    return _buildSectionCard(
      title: 'product_form_inventory'.tr(),
      icon: LucideIcons.warehouse,
      children: [
        _buildMeasurementTypeSelector(context, state),
        const SizedBox(height: 16),
        if (state.hasVariants)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Theme.of(
                  context,
                ).colorScheme.outline.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  LucideIcons.layers,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'product_form.stock_is_sum_of_variants'.tr(),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        if (state.hasVariants) const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: state.hasVariants && productId != null
                  ? BlocBuilder<
                      ProductVariantsBloc,
                      RealtimeState<List<ProductVariant>>
                    >(
                      builder: (context, variantsState) {
                        List<ProductVariant> variants = const [];
                        if (variantsState
                            is RealtimeSuccess<List<ProductVariant>>) {
                          variants = variantsState.data;
                        } else if (variantsState
                            is RealtimeLoading<List<ProductVariant>>) {
                          variants = variantsState.previousData ?? const [];
                        } else if (variantsState
                            is RealtimeError<List<ProductVariant>>) {
                          variants = variantsState.previousData ?? const [];
                        } else if (variantsState
                            is RealtimeOptimistic<List<ProductVariant>>) {
                          variants = variantsState.optimisticData;
                        }

                        final totalStock = variants.fold<int>(
                          0,
                          (sum, v) => sum + v.stockQuantity,
                        );

                        return TextFormField(
                          key: ValueKey('total_stock_$totalStock'),
                          initialValue: localizedQuantity(
                            totalStock,
                            state.measurementType,
                          ),
                          decoration: InputDecoration(
                            labelText: 'product_form.totalStock'.tr(),
                            border: const OutlineInputBorder(),
                            suffixIcon: const Icon(LucideIcons.lock),
                          ),
                          enabled: false,
                        );
                      },
                    )
                  : TextFormField(
                      controller: _stockController,
                      focusNode: _stockFocusNode,
                      decoration: InputDecoration(
                        labelText: state.isEditing
                            ? 'product_form_quantity'.tr()
                            : 'product_form_quantity'.tr(),
                        helperText: state.isEditing && state.trackInventory
                            ? 'products.stock_readonly_hint'.tr()
                            : null,
                        helperMaxLines: 3,
                        errorText: state.fieldErrors['stockQuantity']?.tr(),
                        border: const OutlineInputBorder(),
                        suffixIcon: state.isEditing && state.trackInventory
                            ? const Icon(LucideIcons.lock)
                            : null,
                      ),
                      // Stock is a derived quantity once the product exists:
                      // it may be changed only by purchases, sales, returns
                      // and Inventory Adjustments — but ONLY when inventory
                      // tracking is enabled. Non-tracked products (services,
                      // labor, etc.) carry no inventory ledger so direct
                      // editing is allowed.
                      enabled: !state.isEditing || !state.trackInventory,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                      ],
                      onTap: () => selectAllText(_stockController),
                      onChanged: (value) {
                        bloc.add(
                          ProductFormFieldChanged(
                            field: 'stockQuantity',
                            value: _parseMajorQuantity(
                              value,
                              MeasurementType.fromDb(state.measurementType),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TextFormField(
                controller: _minStockController,
                focusNode: _minStockFocusNode,
                decoration: InputDecoration(
                  labelText: 'product_form_minQuantity'.tr(),
                  errorText: state.fieldErrors['minQuantity']?.tr(),
                  border: const OutlineInputBorder(),
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                onTap: () => selectAllText(_minStockController),
                onChanged: (value) {
                  bloc.add(
                    ProductFormFieldChanged(
                      field: 'minQuantity',
                      value: _parseMajorQuantity(
                        value,
                        MeasurementType.fromDb(state.measurementType),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        if (state.isEditing &&
            state.productId != null &&
            state.trackInventory) ...[
          const SizedBox(height: 16),
          _buildStockSourcesCard(context, state),
        ],
        if (state.isEditing &&
            !state.hasVariants &&
            state.productId != null &&
            state.trackInventory) ...[
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: OutlinedButton.icon(
              onPressed: () => _openInventoryAdjustmentForDefaultVariant(
                context,
                productId: state.productId!,
                fallbackStock: state.stockQuantity,
                fallbackCostCents: state.costCents.toBigInt().toInt(),
              ),
              icon: const Icon(LucideIcons.warehouse, size: 16),
              label: Text('products.adjust_inventory'.tr()),
            ),
          ),
        ],
        const SizedBox(height: 16),
        SwitchListTile(
          title: Text('product_form_trackInventory'.tr()),
          value: state.trackInventory,
          subtitle: state.isEditing && state.costingMethodLockReason != null
              ? Text('measurement.locked_after_activity'.tr())
              : null,
          onChanged: state.isEditing && state.costingMethodLockReason != null
              ? null
              : (value) {
                  bloc.add(
                    ProductFormFieldChanged(
                      field: 'trackInventory',
                      value: value,
                    ),
                  );
                },
        ),
        const SizedBox(height: 16),
        _buildInventoryTrackingSelector(context, state),
        if (productId != null) ...[
          const SizedBox(height: 16),
          _ExpiryInfoWidget(productId: productId),
          const SizedBox(height: 16),
          BatchesSectionWidget(productId: productId),
        ],
      ],
    );
  }

  int _parseMajorQuantity(String raw, MeasurementType type) {
    try {
      return MeasuredQuantity.parseToStored(raw, type.majorUnit);
    } on FormatException {
      return 0;
    }
  }

  Widget _buildMeasurementTypeSelector(
    BuildContext context,
    ProductFormState state,
  ) {
    final settings = context.watch<AppSettingsBloc>().state.settings;
    final current = MeasurementType.fromDb(state.measurementType);
    final enabled = <MeasurementType>{MeasurementType.piece};
    if (settings.enableMeasuredProducts) {
      if (settings.enableLengthUnits) enabled.add(MeasurementType.length);
      if (settings.enableWeightUnits) enabled.add(MeasurementType.weight);
      if (settings.enableVolumeUnits) enabled.add(MeasurementType.volume);
    }
    // Existing measured products remain usable even if their settings switch
    // is later disabled. The switch controls creation choices, not history.
    enabled.add(current);
    final locked = state.isEditing && state.costingMethodLockReason != null;

    return DropdownButtonFormField<MeasurementType>(
      initialValue: current,
      decoration: InputDecoration(
        labelText: 'measurement.product_type'.tr(),
        helperText: locked
            ? 'measurement.locked_after_activity'.tr()
            : 'measurement.price_per_major_unit'.tr(
                namedArgs: {
                  'unit': 'measurement.units.${current.majorUnit.dbValue}'.tr(),
                },
              ),
        helperMaxLines: 2,
        border: const OutlineInputBorder(),
        prefixIcon: const Icon(LucideIcons.ruler),
      ),
      items: enabled
          .map(
            (type) => DropdownMenuItem(
              value: type,
              child: Text('measurement.types.${type.dbValue}'.tr()),
            ),
          )
          .toList(),
      onChanged: locked
          ? null
          : (type) {
              if (type == null || type == current) return;
              context.read<ProductFormBloc>().add(
                ProductFormFieldChanged(
                  field: 'measurementType',
                  value: type.dbValue,
                ),
              );
              _stockController.text = '0';
              _minStockController.text = '0';
            },
    );
  }

  /// Per-product inventory tracking selector — Layer 2 of the two-layer
  /// inventory architecture (Standard / Batch / Batch + Expiry).
  ///
  /// Replaces the legacy WAC/FIFO selector. The valuation method itself is
  /// now a global setting (`InventoryValuationService`); per product, the
  /// only meaningful question is *whether we track this item as discrete
  /// batches with expiry dates*. Mirrors what Odoo, SAP B1, NetSuite and
  /// Cin7 expose at the product level.
  ///
  /// Lock semantics are identical to the previous selector — once stock or
  /// batch consumptions exist, the tracking type is frozen because flipping
  /// it would leave existing batches and journal entries inconsistent.
  Widget _buildInventoryTrackingSelector(
    BuildContext context,
    ProductFormState state,
  ) {
    final bloc = context.read<ProductFormBloc>();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isLocked = state.costingMethodLockReason != null;

    String lockMessage() {
      switch (state.costingMethodLockReason) {
        case 'has_stock':
          return 'products.tracking_locked_stock'.tr();
        case 'has_consumptions':
          return 'products.tracking_locked_consumptions'.tr();
        case 'has_transactions':
          return 'products.tracking_locked_transactions'.tr();
        default:
          return '';
      }
    }

    String helpText() {
      switch (state.inventoryTrackingType) {
        case 'batch':
          return 'products.tracking_batch_help'.tr();
        case 'batch_expiry':
          return 'products.tracking_batch_expiry_help'.tr();
        case 'standard':
        default:
          return 'products.tracking_standard_help'.tr();
      }
    }

    final fieldError =
        state.fieldErrors['inventoryTrackingType'] ??
        state.fieldErrors['costingMethod'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(LucideIcons.boxes, size: 16, color: cs.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(
              'products.inventory_tracking'.tr(),
              style: theme.textTheme.titleSmall,
            ),
            if (isLocked) ...[
              const SizedBox(width: 6),
              Icon(LucideIcons.lock, size: 14, color: cs.onSurfaceVariant),
            ],
          ],
        ),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: [
            ButtonSegment<String>(
              value: 'standard',
              label: Text('products.tracking_standard'.tr()),
              icon: const Icon(LucideIcons.package, size: 16),
            ),
            ButtonSegment<String>(
              value: 'batch',
              label: Text('products.tracking_batch'.tr()),
              icon: const Icon(LucideIcons.layers, size: 16),
            ),
            ButtonSegment<String>(
              value: 'batch_expiry',
              label: Text('products.tracking_batch_expiry'.tr()),
              icon: const Icon(LucideIcons.calendarClock, size: 16),
            ),
          ],
          selected: {state.inventoryTrackingType},
          onSelectionChanged: isLocked
              ? null
              : (set) => bloc.add(
                  ProductFormFieldChanged(
                    field: 'inventoryTrackingType',
                    value: set.first,
                  ),
                ),
          showSelectedIcon: false,
        ),
        const SizedBox(height: 6),
        Text(
          helpText(),
          style: theme.textTheme.bodySmall?.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
        if (isLocked) ...[
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(LucideIcons.info, size: 14, color: cs.tertiary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  lockMessage(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.tertiary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ],
        if (fieldError != null) ...[
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(LucideIcons.alertTriangle, size: 14, color: cs.error),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  fieldError.tr(),
                  style: theme.textTheme.bodySmall?.copyWith(color: cs.error),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildTaxSection(BuildContext context, ProductFormState state) {
    final bloc = context.read<ProductFormBloc>();

    return _buildSectionCard(
      title: 'product_form_tax'.tr(),
      icon: LucideIcons.percent,
      children: [
        SwitchListTile(
          title: Text('product_form_isTaxable'.tr()),
          value: state.isTaxable,
          onChanged: (value) {
            bloc.add(ProductFormFieldChanged(field: 'isTaxable', value: value));
          },
        ),
        if (state.isTaxable) ...[
          const SizedBox(height: 16),
          TextFormField(
            controller: _purchaseTaxRateController,
            decoration: InputDecoration(
              labelText: 'product_form_purchaseTaxRate'.tr(),
              errorText: state.fieldErrors['purchaseTaxRateBps']?.tr(),
              border: const OutlineInputBorder(),
              suffixText: '%',
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onTap: () => selectAllText(_purchaseTaxRateController),
            onChanged: (value) {
              final rate = double.tryParse(value) ?? 0;
              bloc.add(
                ProductFormFieldChanged(
                  field: 'purchaseTaxRateBps',
                  value: (rate * 100).toInt(),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _salesTaxRateController,
            decoration: InputDecoration(
              labelText: 'product_form_salesTaxRate'.tr(),
              errorText: state.fieldErrors['salesTaxRateBps']?.tr(),
              border: const OutlineInputBorder(),
              suffixText: '%',
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onTap: () => selectAllText(_salesTaxRateController),
            onChanged: (value) {
              final rate = double.tryParse(value) ?? 0;
              bloc.add(
                ProductFormFieldChanged(
                  field: 'salesTaxRateBps',
                  value: (rate * 100).toInt(),
                ),
              );
            },
          ),
        ],
      ],
    );
  }

  Widget _buildOptionsSection(BuildContext context, ProductFormState state) {
    final bloc = context.read<ProductFormBloc>();

    return _buildSectionCard(
      title: 'product_form_options'.tr(),
      icon: LucideIcons.settings,
      children: [
        SwitchListTile(
          title: Text('product_form_hasVariants'.tr()),
          subtitle: Text('product_form_hasVariants_hint'.tr()),
          value: state.hasVariants,
          onChanged: (value) async {
            // Turning variants OFF on an editing product is destructive:
            // dimensional variants will be deactivated. Confirm with the
            // exact count (Shopify / WooCommerce style) before applying.
            if (!value &&
                state.hasVariants &&
                state.isEditing &&
                state.productId != null) {
              final repository = sl<ProductVariantRepository>();
              final stockBearingCount = await repository
                  .countActiveDimensionalVariantsWithStock(state.productId!);
              if (!context.mounted) return;
              if (stockBearingCount > 0) {
                await _showVariantStockBlock(context, stockBearingCount);
                return;
              }
              final count = await repository.countActiveDimensionalVariants(
                state.productId!,
              );
              if (!context.mounted) return;
              if (count > 0) {
                final confirmed = await _confirmDisableVariants(context, count);
                if (!confirmed) return;
              }
            }
            bloc.add(
              ProductFormFieldChanged(field: 'hasVariants', value: value),
            );
          },
        ),
        SwitchListTile(
          title: Text('product_form_isActive'.tr()),
          value: state.isActive,
          onChanged: (value) {
            bloc.add(ProductFormFieldChanged(field: 'isActive', value: value));
          },
        ),
      ],
    );
  }

  Widget _buildVariantsSection(BuildContext context, ProductFormState state) {
    final productId = state.productId;

    // For new products, show a message that variants can be added after saving
    if (productId == null) {
      return _buildSectionCard(
        title: 'product_form.variants'.tr(),
        icon: LucideIcons.layers,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  LucideIcons.info,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'product_form.variants_save_first'.tr(),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return _buildSectionCard(
      title: 'product_form.variants'.tr(),
      icon: LucideIcons.layers,
      children: [
        VariantManagementWidget(
          productId: productId,
          measurementType: state.measurementType,
        ),
      ],
    );
  }
}

class _ColorSizePickerRow extends StatelessWidget {
  final int? selectedColorId;
  final int? selectedSizeId;
  final ValueChanged<int?> onColorSelected;
  final ValueChanged<int?> onSizeSelected;

  const _ColorSizePickerRow({
    required this.selectedColorId,
    required this.selectedSizeId,
    required this.onColorSelected,
    required this.onSizeSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ColorPickerField(
            selectedColorId: selectedColorId,
            onSelected: onColorSelected,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _SizePickerField(
            selectedSizeId: selectedSizeId,
            onSelected: onSizeSelected,
          ),
        ),
      ],
    );
  }
}

class _ColorPickerField extends StatelessWidget {
  final int? selectedColorId;
  final ValueChanged<int?> onSelected;

  const _ColorPickerField({
    required this.selectedColorId,
    required this.onSelected,
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

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ColorsBloc, RealtimeState<List<ProductColor>>>(
      builder: (context, state) {
        final colors = state is RealtimeSuccess<List<ProductColor>>
            ? state.data
            : <ProductColor>[];
        final selected = selectedColorId == null
            ? null
            : colors.cast<ProductColor?>().firstWhere(
                (c) => c?.id == selectedColorId,
                orElse: () => null,
              );

        return InkWell(
          onTap: () => _showColorPickerBottomSheet(context, colors),
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: 'product_form_variantColor'.tr(),
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(LucideIcons.palette),
            ),
            child: selected == null
                ? Text('common.none'.tr())
                : Row(
                    children: [
                      Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color:
                              _tryParseHexColor(selected.hexCode) ??
                              Colors.grey,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Theme.of(context).colorScheme.outline,
                          ),
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

  Future<void> _showColorPickerBottomSheet(
    BuildContext context,
    List<ProductColor> colors,
  ) async {
    final colorsBloc = context.read<ColorsBloc>();
    final selected = await showModalBottomSheet<int?>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        String query = '';
        return BlocProvider.value(
          value: colorsBloc,
          child: StatefulBuilder(
            builder: (context, setState) {
              return BlocBuilder<ColorsBloc, RealtimeState<List<ProductColor>>>(
                builder: (context, state) {
                  final allColors = state is RealtimeSuccess<List<ProductColor>>
                      ? state.data
                      : colors;
                  final filtered = query.isEmpty
                      ? allColors
                      : allColors
                            .where(
                              (c) => c.name.toLowerCase().contains(
                                query.toLowerCase(),
                              ),
                            )
                            .toList();

                  return SafeArea(
                    child: Padding(
                      padding: EdgeInsets.only(
                        left: 16,
                        right: 16,
                        top: 12,
                        bottom: MediaQuery.of(context).viewInsets.bottom + 12,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextField(
                            decoration: InputDecoration(
                              hintText: 'colors.search_hint'.tr(),
                              prefixIcon: const Icon(LucideIcons.search),
                              border: const OutlineInputBorder(),
                            ),
                            onChanged: (v) => setState(() => query = v),
                          ),
                          const SizedBox(height: 12),
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: TextButton.icon(
                              onPressed: () => context.push('/products/colors'),
                              icon: const Icon(LucideIcons.settings),
                              label: Text('manage_colors'.tr()),
                            ),
                          ),
                          Flexible(
                            child: ListView.builder(
                              shrinkWrap: true,
                              itemCount: filtered.length + 1,
                              itemBuilder: (context, index) {
                                if (index == 0) {
                                  return ListTile(
                                    title: Text('common.none'.tr()),
                                    onTap: () =>
                                        Navigator.of(context).pop(null),
                                  );
                                }
                                final color = filtered[index - 1];
                                return ListTile(
                                  leading: Container(
                                    width: 18,
                                    height: 18,
                                    decoration: BoxDecoration(
                                      color:
                                          _tryParseHexColor(color.hexCode) ??
                                          Colors.grey,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.outline,
                                      ),
                                    ),
                                  ),
                                  title: Text(color.name),
                                  onTap: () =>
                                      Navigator.of(context).pop(color.id),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );

    if (selected != null || selectedColorId != null) {
      onSelected(selected);
    }
  }
}

class _SizePickerField extends StatelessWidget {
  final int? selectedSizeId;
  final ValueChanged<int?> onSelected;

  const _SizePickerField({
    required this.selectedSizeId,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SizesBloc, RealtimeState<List<Size>>>(
      builder: (context, state) {
        final sizes = state is RealtimeSuccess<List<Size>>
            ? state.data
            : <Size>[];
        final selected = selectedSizeId == null
            ? null
            : sizes.cast<Size?>().firstWhere(
                (s) => s?.id == selectedSizeId,
                orElse: () => null,
              );

        return InkWell(
          onTap: () => _showSizePickerBottomSheet(context, sizes),
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: 'product_form_variantSize'.tr(),
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(LucideIcons.ruler),
            ),
            child: Text(selected?.name ?? 'common.none'.tr()),
          ),
        );
      },
    );
  }

  Future<void> _showSizePickerBottomSheet(
    BuildContext context,
    List<Size> sizes,
  ) async {
    final sizesBloc = context.read<SizesBloc>();
    final selected = await showModalBottomSheet<int?>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        String query = '';
        return BlocProvider.value(
          value: sizesBloc,
          child: StatefulBuilder(
            builder: (context, setState) {
              return BlocBuilder<SizesBloc, RealtimeState<List<Size>>>(
                builder: (context, state) {
                  final allSizes = state is RealtimeSuccess<List<Size>>
                      ? state.data
                      : sizes;
                  final filtered = query.isEmpty
                      ? allSizes
                      : allSizes
                            .where(
                              (s) => s.name.toLowerCase().contains(
                                query.toLowerCase(),
                              ),
                            )
                            .toList();

                  return SafeArea(
                    child: Padding(
                      padding: EdgeInsets.only(
                        left: 16,
                        right: 16,
                        top: 12,
                        bottom: MediaQuery.of(context).viewInsets.bottom + 12,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextField(
                            decoration: InputDecoration(
                              hintText: 'sizes.search_hint'.tr(),
                              prefixIcon: const Icon(LucideIcons.search),
                              border: const OutlineInputBorder(),
                            ),
                            onChanged: (v) => setState(() => query = v),
                          ),
                          const SizedBox(height: 12),
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: TextButton.icon(
                              onPressed: () => context.push('/products/sizes'),
                              icon: const Icon(LucideIcons.settings),
                              label: Text('manage_sizes'.tr()),
                            ),
                          ),
                          Flexible(
                            child: ListView.builder(
                              shrinkWrap: true,
                              itemCount: filtered.length + 1,
                              itemBuilder: (context, index) {
                                if (index == 0) {
                                  return ListTile(
                                    title: Text('common.none'.tr()),
                                    onTap: () =>
                                        Navigator.of(context).pop(null),
                                  );
                                }
                                final size = filtered[index - 1];
                                return ListTile(
                                  title: Text(size.name),
                                  onTap: () =>
                                      Navigator.of(context).pop(size.id),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );

    if (selected != null || selectedSizeId != null) {
      onSelected(selected);
    }
  }
}

class _ExpiryInfoWidget extends StatelessWidget {
  final int productId;
  const _ExpiryInfoWidget({required this.productId});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final productDao = sl<ProductDao>();

    // FIFO-aware: read remaining_quantity from product_batches, not the
    // original purchase line. Otherwise a 100-unit lot sold down to 12 would
    // still be displayed as "100 expiring on …", which silently misrepresents
    // shrinkage exposure. See ProductDao.getProductRemainingExpiryInfo.
    return FutureBuilder<List<({int quantity, DateTime expiryDate})>>(
      future: productDao.getProductRemainingExpiryInfo(productId),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const SizedBox.shrink();
        }

        final items = snapshot.data!;
        final now = DateTime.now();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final item in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: item.expiryDate.isBefore(now)
                        ? cs.errorContainer.withValues(alpha: 0.3)
                        : item.expiryDate.isBefore(
                            now.add(const Duration(days: 30)),
                          )
                        ? Colors.orange.withValues(alpha: 0.15)
                        : cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: item.expiryDate.isBefore(now)
                          ? cs.error.withValues(alpha: 0.5)
                          : item.expiryDate.isBefore(
                              now.add(const Duration(days: 30)),
                            )
                          ? Colors.orange.withValues(alpha: 0.5)
                          : cs.outline.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        LucideIcons.calendarClock,
                        size: 16,
                        color: item.expiryDate.isBefore(now)
                            ? cs.error
                            : item.expiryDate.isBefore(
                                now.add(const Duration(days: 30)),
                              )
                            ? Colors.orange
                            : cs.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'product_form.expiry_info'.tr(
                            args: [
                              '${item.quantity}',
                              DateFormat('dd/MM/yyyy').format(item.expiryDate),
                            ],
                          ),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: item.expiryDate.isBefore(now)
                                ? cs.error
                                : item.expiryDate.isBefore(
                                    now.add(const Duration(days: 30)),
                                  )
                                ? Colors.orange.shade800
                                : cs.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Shows the min–max cost and price derived from the product's active
/// variants. Data is streamed so POS-driven stock / price edits reflect here
/// in real time. The product-level cost/price inputs above keep acting as a
/// bulk template ("Apply to all variants" button pushes them down).
class _VariantPriceRangeCard extends StatelessWidget {
  final int productId;
  const _VariantPriceRangeCard({required this.productId});

  String _fmt(Decimal cents) => (cents / Decimal.fromInt(100))
      .toDecimal(scaleOnInfinitePrecision: 2)
      .toStringAsFixed(2);

  String _range(Decimal min, Decimal max) {
    if (min == max) return _fmt(min);
    return '${_fmt(min)} – ${_fmt(max)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return StreamBuilder<List<ProductVariant>>(
      stream: sl<ProductVariantRepository>().watchVariantsByProduct(productId),
      builder: (context, snapshot) {
        final variants = (snapshot.data ?? const <ProductVariant>[])
            .where((v) => v.isActive)
            .toList();
        if (variants.isEmpty) return const SizedBox.shrink();

        final costs = variants.map((v) => v.costCents).toList()..sort();
        final prices = variants.map((v) => v.priceCents).toList()..sort();
        final costMin = costs.first;
        final costMax = costs.last;
        final priceMin = prices.first;
        final priceMax = prices.last;

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(LucideIcons.layers, size: 16, color: cs.primary),
                  const SizedBox(width: 8),
                  Text(
                    'product_form.price_range_badge'.tr(),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${variants.length}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _rangeCell(
                      theme,
                      label: 'product_form_cost'.tr(),
                      value: _range(costMin, costMax),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _rangeCell(
                      theme,
                      label: 'product_form_price'.tr(),
                      value: _range(priceMin, priceMax),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _rangeCell(
    ThemeData theme, {
    required String label,
    required String value,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _PrintModeOptionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final ColorScheme colorScheme;
  final VoidCallback onTap;

  const _PrintModeOptionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.colorScheme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: colorScheme.onPrimaryContainer,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

/// Displays the most recent cost / retail / wholesale changes recorded for a
/// product. Mirrors the audit trail shown in QuickBooks / Xero / Odoo: each
/// row shows old → new amount and the timestamp.
///
/// Cost changes are now included because every sanctioned cost-mutating call
/// site (purchase post → WAC/FIFO/last-cost, inventory revaluation, manual
/// product-form save on first creation) funnels through
/// `PriceHistoryService` — the SINGLE writer for `product_price_histories`.
/// The bottom sheet shown inside purchase/sale invoices is a per-line
/// snapshot, NOT a separate history; the corresponding row appears here as
/// soon as the document is posted.
///
/// For products with dimensional variants, each row carries a
/// color/size/SKU chip so the user can attribute the change to the right
/// variant. Product-level rows (no variant id) render without a chip.
class _PriceHistoryWidget extends StatelessWidget {
  final int productId;
  const _PriceHistoryWidget({required this.productId});

  String _fmtCents(int cents) {
    final d = Decimal.fromInt(cents) / Decimal.fromInt(100);
    return d.toDecimal(scaleOnInfinitePrecision: 2).toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return FutureBuilder<_PriceHistoryViewModel>(
      future: _load(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 48,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        final vm = snapshot.data ?? const _PriceHistoryViewModel.empty();
        final entries = vm.entries;
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(LucideIcons.history, size: 16, color: cs.primary),
                  const SizedBox(width: 8),
                  Text(
                    'product_form.price_history_title'.tr(),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${entries.length}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (entries.isEmpty)
                Text(
                  'product_form.price_history_empty'.tr(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                )
              else
                ...entries.take(10).map((h) {
                  final costChanged = h.oldCostCents != h.newCostCents;
                  final priceChanged = h.oldPriceCents != h.newPriceCents;
                  final wholesaleChanged =
                      h.oldWholesalePriceCents != h.newWholesalePriceCents;
                  final variantLabel = h.variantId == null
                      ? null
                      : (vm.variantLabels[h.variantId!] ??
                            'Variant #${h.variantId}');
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              DateFormat(
                                'dd/MM/yyyy',
                              ).add_Hm().format(h.createdAt),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            if (variantLabel != null) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: cs.primaryContainer.withValues(
                                    alpha: 0.6,
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  variantLabel,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: cs.onPrimaryContainer,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (costChanged)
                          _PriceHistoryRow(
                            label: 'product_form_cost'.tr(),
                            from: _fmtCents(h.oldCostCents),
                            to: _fmtCents(h.newCostCents),
                            isIncrease: h.newCostCents > h.oldCostCents,
                          ),
                        if (priceChanged)
                          _PriceHistoryRow(
                            label: 'product_form_price'.tr(),
                            from: _fmtCents(h.oldPriceCents),
                            to: _fmtCents(h.newPriceCents),
                            isIncrease: h.newPriceCents > h.oldPriceCents,
                          ),
                        if (wholesaleChanged)
                          _PriceHistoryRow(
                            label: 'product_form_wholesalePrice'.tr(),
                            from: _fmtCents(h.oldWholesalePriceCents ?? 0),
                            to: _fmtCents(h.newWholesalePriceCents ?? 0),
                            isIncrease:
                                (h.newWholesalePriceCents ?? 0) >
                                (h.oldWholesalePriceCents ?? 0),
                          ),
                        const Divider(height: 12),
                      ],
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
  }

  Future<_PriceHistoryViewModel> _load() async {
    final entries = await sl<ProductRepository>().getPriceHistory(productId);
    // Resolve variant labels for the chip. Best-effort: SKU first, else
    // "Variant #id". Skipped entirely when no variant-scoped rows exist.
    final variantIds = entries.map((e) => e.variantId).whereType<int>().toSet();
    final labels = <int, String>{};
    if (variantIds.isNotEmpty) {
      final variants = await sl<ProductVariantRepository>()
          .getVariantsByProduct(productId);
      for (final v in variants) {
        if (variantIds.contains(v.id)) {
          labels[v.id] = (v.sku?.trim().isNotEmpty ?? false)
              ? v.sku!.trim()
              : 'Variant #${v.id}';
        }
      }
    }
    return _PriceHistoryViewModel(entries: entries, variantLabels: labels);
  }
}

class _PriceHistoryViewModel {
  final List<PriceHistory> entries;
  final Map<int, String> variantLabels;
  const _PriceHistoryViewModel({
    required this.entries,
    required this.variantLabels,
  });
  const _PriceHistoryViewModel.empty()
    : entries = const <PriceHistory>[],
      variantLabels = const <int, String>{};
}

class _PriceHistoryRow extends StatelessWidget {
  final String label;
  final String from;
  final String to;
  final bool isIncrease;
  const _PriceHistoryRow({
    required this.label,
    required this.from,
    required this.to,
    required this.isIncrease,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final color = isIncrease ? Colors.green.shade700 : cs.error;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Text(
            from,
            style: theme.textTheme.bodySmall?.copyWith(
              decoration: TextDecoration.lineThrough,
              color: cs.onSurfaceVariant,
            ),
          ),
          Icon(
            isIncrease ? LucideIcons.arrowUpRight : LucideIcons.arrowDownRight,
            size: 14,
            color: color,
          ),
          Text(
            to,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
