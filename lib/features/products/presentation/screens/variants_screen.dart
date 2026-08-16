import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/measurement/measurement_localization.dart';
import '../../../../core/services/currency_service.dart';
import '../../../auth/data/services/permission_service.dart';
import '../../../auth/domain/entities/permission_constants.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../settings/presentation/bloc/app_settings_bloc.dart';
import '../../domain/entities/product_variant_entity.dart';
import '../../domain/entities/product_color_entity.dart';
import '../../domain/entities/size_entity.dart';
import '../../domain/entities/product_entity.dart';
import '../../domain/entities/category_entity.dart';
import '../bloc/product_variants_bloc.dart';
import '../bloc/products_bloc.dart';
import '../bloc/colors_bloc.dart';
import '../bloc/colors_event.dart';
import '../bloc/sizes_bloc.dart';
import '../bloc/sizes_event.dart';
import '../bloc/categories_bloc.dart';
import '../bloc/categories_event.dart';
import '../widgets/variant_edit_dialog.dart';
import '../widgets/inventory_adjustment_dialog.dart';

enum StockFilter { all, inStock, lowStock, outOfStock }

enum SortOption { barcode, sku, stock, recent }

class VariantsScreen extends StatelessWidget {
  const VariantsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (context) =>
              sl<ProductVariantsBloc>()..add(const AllVariantsInitialized()),
        ),
        BlocProvider(create: (context) => sl<ProductsBloc>()),
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
      ],
      child: const _VariantsView(),
    );
  }
}

class _VariantsView extends StatefulWidget {
  const _VariantsView();

  @override
  State<_VariantsView> createState() => _VariantsViewState();
}

class _VariantsViewState extends State<_VariantsView> {
  final TextEditingController _searchController = TextEditingController();
  final Set<int> _selectedVariantIds = {};

  int? _productFilter;
  int? _colorFilter;
  int? _sizeFilter;
  StockFilter _stockFilter = StockFilter.all;
  bool? _activeFilter;
  SortOption _sortOption = SortOption.recent;
  ProductVariant? _selectedVariant;

  bool _hasPermission(String permission) {
    final authState = context.read<AuthBloc>().state;
    final user = authState is AuthAuthenticated ? authState.user : null;
    return sl<PermissionService>().hasPermission(user, permission);
  }

  bool get _canViewProductCost => _hasPermission(Permissions.viewProductCost);
  bool get _canManageProducts => _hasPermission(Permissions.editProducts);
  bool get _canAdjustStock => _hasPermission(Permissions.adjustStock);

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width >= 1024;
    final currencyService = sl<CurrencyService>();

    return Scaffold(
      appBar: _buildAppBar(context, isDesktop),
      body: SafeArea(
        child: Column(
          children: [
            _buildSearchBar(context, isDesktop),
            _buildFiltersBar(context),
            if (_selectedVariantIds.isNotEmpty) _buildBulkActionsBar(context),
            Expanded(
              child: _buildVariantsContent(context, isDesktop, currencyService),
            ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context, bool isDesktop) {
    return AppBar(
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
      title: Text('variants.title'.tr()),
      centerTitle: !isDesktop,
      actions: [
        IconButton(
          icon: const Icon(LucideIcons.printer),
          tooltip: 'variants.print_labels'.tr(),
          onPressed: _selectedVariantIds.isEmpty
              ? null
              : () => _printSelectedLabels(context),
        ),
        if (_canManageProducts)
          IconButton(
            icon: const Icon(LucideIcons.plus),
            tooltip: 'variants.add_variant'.tr(),
            onPressed: () => _showAddVariantDialog(context),
          ),
      ],
    );
  }

  Widget _buildSearchBar(BuildContext context, bool isDesktop) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isDesktop ? 24.0 : 16.0,
        vertical: 12.0,
      ),
      child: TextField(
        controller: _searchController,
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _handleBarcodeSearch(),
        decoration: InputDecoration(
          hintText: 'variants.search_hint'.tr(),
          prefixIcon: const Icon(LucideIcons.search),
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_searchController.text.isNotEmpty)
                IconButton(
                  icon: const Icon(LucideIcons.x),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {});
                  },
                ),
              IconButton(
                icon: const Icon(LucideIcons.scanLine),
                tooltip: 'variants.scan_barcode'.tr(),
                onPressed: () => _openBarcodeScanner(context),
              ),
            ],
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  Widget _buildFiltersBar(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return BlocBuilder<ProductsBloc, RealtimeState<List<Product>>>(
      builder: (context, productsState) {
        return BlocBuilder<ColorsBloc, RealtimeState<List<ProductColor>>>(
          builder: (context, colorsState) {
            return BlocBuilder<SizesBloc, RealtimeState<List<Size>>>(
              builder: (context, sizesState) {
                final products = productsState is RealtimeSuccess<List<Product>>
                    ? productsState.data
                    : <Product>[];
                final colors =
                    colorsState is RealtimeSuccess<List<ProductColor>>
                    ? colorsState.data
                    : <ProductColor>[];
                final sizes = sizesState is RealtimeSuccess<List<Size>>
                    ? sizesState.data
                    : <Size>[];

                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerLow,
                    border: Border(
                      bottom: BorderSide(color: colorScheme.outlineVariant),
                    ),
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildFilterChip(
                          context,
                          label: _productFilter == null
                              ? 'variants.all_products'.tr()
                              : products
                                        .where((p) => p.id == _productFilter)
                                        .firstOrNull
                                        ?.name ??
                                    'variants.all_products'.tr(),
                          icon: LucideIcons.package,
                          isSelected: _productFilter != null,
                          onTap: () =>
                              _showProductFilterDialog(context, products),
                        ),
                        const SizedBox(width: 8),
                        _buildFilterChip(
                          context,
                          label: _colorFilter == null
                              ? 'variants.all_colors'.tr()
                              : colors
                                        .where((c) => c.id == _colorFilter)
                                        .firstOrNull
                                        ?.name ??
                                    'variants.all_colors'.tr(),
                          icon: LucideIcons.palette,
                          isSelected: _colorFilter != null,
                          onTap: () => _showColorFilterDialog(context, colors),
                        ),
                        const SizedBox(width: 8),
                        _buildFilterChip(
                          context,
                          label: _sizeFilter == null
                              ? 'variants.all_sizes'.tr()
                              : sizes
                                        .where((s) => s.id == _sizeFilter)
                                        .firstOrNull
                                        ?.name ??
                                    'variants.all_sizes'.tr(),
                          icon: LucideIcons.ruler,
                          isSelected: _sizeFilter != null,
                          onTap: () => _showSizeFilterDialog(context, sizes),
                        ),
                        const SizedBox(width: 8),
                        _buildFilterChip(
                          context,
                          label: _getStockFilterLabel(),
                          icon: LucideIcons.warehouse,
                          isSelected: _stockFilter != StockFilter.all,
                          onTap: () => _showStockFilterDialog(context),
                        ),
                        const SizedBox(width: 8),
                        _buildFilterChip(
                          context,
                          label: _getActiveFilterLabel(),
                          icon: LucideIcons.toggleLeft,
                          isSelected: _activeFilter != null,
                          onTap: () => _showActiveFilterDialog(context),
                        ),
                        const SizedBox(width: 16),
                        const VerticalDivider(width: 1),
                        const SizedBox(width: 16),
                        _buildFilterChip(
                          context,
                          label: _getSortLabel(),
                          icon: LucideIcons.arrowUpDown,
                          isSelected: false,
                          onTap: () => _showSortDialog(context),
                        ),
                        if (_hasActiveFilters()) ...[
                          const SizedBox(width: 16),
                          TextButton.icon(
                            onPressed: _clearAllFilters,
                            icon: const Icon(LucideIcons.x, size: 16),
                            label: Text('variants.clear_filters'.tr()),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildFilterChip(
    BuildContext context, {
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return ActionChip(
      avatar: Icon(icon, size: 16),
      label: Text(label),
      backgroundColor: isSelected ? colorScheme.primaryContainer : null,
      onPressed: onTap,
    );
  }

  Widget _buildBulkActionsBar(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isSmall = MediaQuery.of(context).size.width < 420;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: colorScheme.primaryContainer,
      child: isSmall
          ? SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'variants.selected_count'.tr(
                      args: ['${_selectedVariantIds.length}'],
                    ),
                    style: TextStyle(
                      color: colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 12),
                  TextButton.icon(
                    onPressed: () => _printSelectedLabels(context),
                    icon: const Icon(LucideIcons.printer, size: 18),
                    label: Text('variants.print'.tr()),
                  ),
                  const SizedBox(width: 8),
                  if (_canManageProducts)
                    TextButton.icon(
                      onPressed: () => _bulkSetActive(context, true),
                      icon: const Icon(LucideIcons.toggleRight, size: 18),
                      label: Text('variants.activate'.tr()),
                    ),
                  const SizedBox(width: 8),
                  if (_canManageProducts)
                    TextButton.icon(
                      onPressed: () => _bulkSetActive(context, false),
                      icon: const Icon(LucideIcons.toggleLeft, size: 18),
                      label: Text('variants.deactivate'.tr()),
                    ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: () =>
                        setState(() => _selectedVariantIds.clear()),
                    icon: const Icon(LucideIcons.x, size: 18),
                    label: Text('common.cancel'.tr()),
                  ),
                ],
              ),
            )
          : Row(
              children: [
                Text(
                  'variants.selected_count'.tr(
                    args: ['${_selectedVariantIds.length}'],
                  ),
                  style: TextStyle(
                    color: colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _printSelectedLabels(context),
                  icon: const Icon(LucideIcons.printer, size: 18),
                  label: Text('variants.print'.tr()),
                ),
                const SizedBox(width: 8),
                if (_canManageProducts)
                  TextButton.icon(
                    onPressed: () => _bulkSetActive(context, true),
                    icon: const Icon(LucideIcons.toggleRight, size: 18),
                    label: Text('variants.activate'.tr()),
                  ),
                const SizedBox(width: 8),
                if (_canManageProducts)
                  TextButton.icon(
                    onPressed: () => _bulkSetActive(context, false),
                    icon: const Icon(LucideIcons.toggleLeft, size: 18),
                    label: Text('variants.deactivate'.tr()),
                  ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () => setState(() => _selectedVariantIds.clear()),
                  icon: const Icon(LucideIcons.x, size: 18),
                  label: Text('common.cancel'.tr()),
                ),
              ],
            ),
    );
  }

  Widget _buildVariantsContent(
    BuildContext context,
    bool isDesktop,
    CurrencyService currencyService,
  ) {
    final colorScheme = Theme.of(context).colorScheme;

    return BlocBuilder<
      ProductVariantsBloc,
      RealtimeState<List<ProductVariant>>
    >(
      builder: (context, variantsState) {
        return BlocBuilder<ProductsBloc, RealtimeState<List<Product>>>(
          builder: (context, productsState) {
            return BlocBuilder<ColorsBloc, RealtimeState<List<ProductColor>>>(
              builder: (context, colorsState) {
                return BlocBuilder<SizesBloc, RealtimeState<List<Size>>>(
                  builder: (context, sizesState) {
                    List<ProductVariant>? variants;
                    if (variantsState
                        is RealtimeSuccess<List<ProductVariant>>) {
                      variants = variantsState.data;
                    } else if (variantsState
                        is RealtimeLoading<List<ProductVariant>>) {
                      variants = variantsState.previousData;
                    } else if (variantsState
                        is RealtimeError<List<ProductVariant>>) {
                      variants = variantsState.previousData;
                    } else if (variantsState
                        is RealtimeOptimistic<List<ProductVariant>>) {
                      variants = variantsState.optimisticData;
                    }

                    if (variantsState
                            is RealtimeLoading<List<ProductVariant>> &&
                        variants == null) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final products =
                        productsState is RealtimeSuccess<List<Product>>
                        ? productsState.data
                        : <Product>[];
                    final colors =
                        colorsState is RealtimeSuccess<List<ProductColor>>
                        ? colorsState.data
                        : <ProductColor>[];
                    final sizes = sizesState is RealtimeSuccess<List<Size>>
                        ? sizesState.data
                        : <Size>[];

                    final productNameById = {
                      for (final p in products) p.id: p.name,
                    };
                    final productById = {for (final p in products) p.id: p};
                    final measurementTypeByProductId = {
                      for (final p in products) p.id: p.measurementType,
                    };
                    final colorById = {for (final c in colors) c.id: c};
                    final sizeNameById = {for (final s in sizes) s.id: s.name};

                    final filteredItems = _applyFilters(
                      variants ?? [],
                      productById,
                      colorById,
                      sizeNameById,
                    );
                    final sortedItems = _applySorting(filteredItems);

                    if (sortedItems.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              LucideIcons.layers,
                              size: 64,
                              color: colorScheme.onSurface.withValues(
                                alpha: 0.3,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _searchController.text.isEmpty &&
                                      !_hasActiveFilters()
                                  ? 'variants.empty'.tr()
                                  : 'variants.no_results'.tr(),
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    color: colorScheme.onSurface.withValues(
                                      alpha: 0.7,
                                    ),
                                  ),
                            ),
                          ],
                        ),
                      );
                    }

                    if (isDesktop) {
                      return _buildSplitView(
                        sortedItems,
                        productNameById: productNameById,
                        measurementTypeByProductId: measurementTypeByProductId,
                        colorById: colorById,
                        sizeNameById: sizeNameById,
                        currencyService: currencyService,
                      );
                    }

                    return _buildDenseList(
                      sortedItems,
                      productNameById: productNameById,
                      measurementTypeByProductId: measurementTypeByProductId,
                      colorById: colorById,
                      sizeNameById: sizeNameById,
                      currencyService: currencyService,
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  List<ProductVariant> _applyFilters(
    List<ProductVariant> variants,
    Map<int, Product> productById,
    Map<int, ProductColor> colorById,
    Map<int, String> sizeNameById,
  ) {
    final query = _searchController.text.trim().toLowerCase();
    // Get global low stock threshold from settings
    final globalThreshold = _getLowStockThreshold();

    return variants.where((v) {
      if (query.isNotEmpty) {
        final barcode = (v.barcode ?? '').toLowerCase();
        final sku = (v.sku ?? '').toLowerCase();
        final color = v.colorId == null
            ? ''
            : (colorById[v.colorId!]?.name ?? '').toLowerCase();
        final size = v.sizeId == null
            ? ''
            : (sizeNameById[v.sizeId!] ?? '').toLowerCase();
        if (!barcode.contains(query) &&
            !sku.contains(query) &&
            !color.contains(query) &&
            !size.contains(query)) {
          return false;
        }
      }
      if (_productFilter != null && v.productId != _productFilter) return false;
      if (_colorFilter != null && v.colorId != _colorFilter) return false;
      if (_sizeFilter != null && v.sizeId != _sizeFilter) return false;

      // Get product-specific minQuantity or use global threshold
      final product = productById[v.productId];
      final threshold =
          (product?.minQuantity != null && product!.minQuantity > 0)
          ? product.minQuantity
          : globalThreshold;

      switch (_stockFilter) {
        case StockFilter.inStock:
          if (v.stockQuantity <= 0) return false;
          break;
        case StockFilter.lowStock:
          if (v.stockQuantity <= 0 || v.stockQuantity > threshold) return false;
          break;
        case StockFilter.outOfStock:
          if (v.stockQuantity > 0) return false;
          break;
        case StockFilter.all:
          break;
      }
      if (_activeFilter != null && v.isActive != _activeFilter) return false;
      return true;
    }).toList();
  }

  int _getLowStockThreshold() {
    try {
      final settingsBloc = sl<AppSettingsBloc>();
      return settingsBloc.state.settings.lowStockThreshold;
    } catch (e) {
      return 5; // Default fallback
    }
  }

  List<ProductVariant> _applySorting(List<ProductVariant> variants) {
    final sorted = List<ProductVariant>.from(variants);
    switch (_sortOption) {
      case SortOption.barcode:
        sorted.sort((a, b) => (a.barcode ?? '').compareTo(b.barcode ?? ''));
        break;
      case SortOption.sku:
        sorted.sort((a, b) => (a.sku ?? '').compareTo(b.sku ?? ''));
        break;
      case SortOption.stock:
        sorted.sort((a, b) => a.stockQuantity.compareTo(b.stockQuantity));
        break;
      case SortOption.recent:
        sorted.sort((a, b) => b.id.compareTo(a.id));
        break;
    }
    return sorted;
  }

  Widget _buildSplitView(
    List<ProductVariant> variants, {
    required Map<int, String> productNameById,
    required Map<int, String> measurementTypeByProductId,
    required Map<int, ProductColor> colorById,
    required Map<int, String> sizeNameById,
    required CurrencyService currencyService,
  }) {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: _buildDenseList(
            variants,
            productNameById: productNameById,
            measurementTypeByProductId: measurementTypeByProductId,
            colorById: colorById,
            sizeNameById: sizeNameById,
            currencyService: currencyService,
          ),
        ),
        if (_selectedVariant != null)
          Expanded(
            flex: 1,
            child: _buildDetailPanel(
              _selectedVariant!,
              productNameById: productNameById,
              measurementTypeByProductId: measurementTypeByProductId,
              colorById: colorById,
              sizeNameById: sizeNameById,
              currencyService: currencyService,
            ),
          ),
      ],
    );
  }

  Widget _buildDenseList(
    List<ProductVariant> variants, {
    required Map<int, String> productNameById,
    required Map<int, String> measurementTypeByProductId,
    required Map<int, ProductColor> colorById,
    required Map<int, String> sizeNameById,
    required CurrencyService currencyService,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isSmall = MediaQuery.of(context).size.width < 420;

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      itemCount: variants.length,
      itemBuilder: (context, index) {
        final v = variants[index];
        final productName = productNameById[v.productId] ?? '';
        final measurementType =
            measurementTypeByProductId[v.productId] ?? 'piece';
        final color = v.colorId == null ? null : colorById[v.colorId!];
        final sizeName = v.sizeId == null ? null : sizeNameById[v.sizeId!];
        final isSelected = _selectedVariantIds.contains(v.id);
        final isDetailSelected = _selectedVariant?.id == v.id;

        Color stockColor;
        if (v.stockQuantity <= 0) {
          stockColor = colorScheme.error;
        } else if (v.stockQuantity <= 10) {
          stockColor = Colors.orange;
        } else {
          stockColor = colorScheme.primary;
        }

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
          color: isDetailSelected
              ? colorScheme.primaryContainer.withValues(alpha: 0.3)
              : null,
          child: InkWell(
            onTap: () => setState(() => _selectedVariant = v),
            onLongPress: () => setState(() {
              if (isSelected) {
                _selectedVariantIds.remove(v.id);
              } else {
                _selectedVariantIds.add(v.id);
              }
            }),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: isSmall
                  ? SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: IntrinsicHeight(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Checkbox(
                              value: isSelected,
                              onChanged: (val) => setState(() {
                                if (val == true) {
                                  _selectedVariantIds.add(v.id);
                                } else {
                                  _selectedVariantIds.remove(v.id);
                                }
                              }),
                            ),
                            SizedBox(
                              width: 140,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    v.sku?.isNotEmpty == true
                                        ? v.sku!
                                        : '#${v.id}',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (v.barcode?.isNotEmpty == true)
                                    Text(
                                      v.barcode!,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: colorScheme.onSurfaceVariant,
                                          ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 140,
                              child: Text(
                                productName,
                                style: theme.textTheme.bodySmall,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (color != null || sizeName != null)
                              SizedBox(
                                width: 160,
                                child: Wrap(
                                  spacing: 4,
                                  children: [
                                    if (color != null)
                                      Chip(
                                        avatar: color.hexCode != null
                                            ? Container(
                                                width: 12,
                                                height: 12,
                                                decoration: BoxDecoration(
                                                  color: _parseHexColor(
                                                    color.hexCode!,
                                                  ),
                                                  shape: BoxShape.circle,
                                                  border: Border.all(
                                                    color: colorScheme.outline,
                                                  ),
                                                ),
                                              )
                                            : null,
                                        label: Text(
                                          color.name,
                                          style: const TextStyle(fontSize: 11),
                                        ),
                                        padding: EdgeInsets.zero,
                                        visualDensity: VisualDensity.compact,
                                      ),
                                    if (sizeName != null)
                                      Chip(
                                        label: Text(
                                          sizeName,
                                          style: const TextStyle(fontSize: 11),
                                        ),
                                        padding: EdgeInsets.zero,
                                        visualDensity: VisualDensity.compact,
                                      ),
                                  ],
                                ),
                              )
                            else
                              const SizedBox(width: 160),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 80,
                              child: Text(
                                currencyService.format(
                                  v.priceCents.toBigInt().toInt(),
                                ),
                                style: theme.textTheme.bodyMedium,
                                textAlign: TextAlign.end,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              width: 50,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: stockColor.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                localizedQuantity(
                                  v.stockQuantity,
                                  measurementType,
                                ),
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: stockColor,
                                  fontWeight: FontWeight.w600,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            const SizedBox(width: 4),
                            if (_canAdjustStock)
                              IconButton(
                                icon: const Icon(
                                  LucideIcons.warehouse,
                                  size: 16,
                                ),
                                tooltip: 'products.adjust_inventory'.tr(),
                                onPressed: () =>
                                    _openInventoryAdjustment(context, v),
                                visualDensity: VisualDensity.compact,
                                constraints: const BoxConstraints(
                                  minWidth: 32,
                                  minHeight: 32,
                                ),
                              ),
                            if (_canManageProducts)
                              IconButton(
                                icon: const Icon(LucideIcons.edit, size: 16),
                                tooltip: 'common.edit'.tr(),
                                onPressed: () => _showEditDialog(context, v),
                                visualDensity: VisualDensity.compact,
                                constraints: const BoxConstraints(
                                  minWidth: 32,
                                  minHeight: 32,
                                ),
                              ),
                            if (_canManageProducts)
                              IconButton(
                                icon: Icon(
                                  v.isActive
                                      ? LucideIcons.toggleRight
                                      : LucideIcons.toggleLeft,
                                  size: 16,
                                  color: v.isActive
                                      ? colorScheme.primary
                                      : colorScheme.outline,
                                ),
                                tooltip: v.isActive
                                    ? 'variants.deactivate'.tr()
                                    : 'variants.activate'.tr(),
                                onPressed: () => _toggleActive(context, v),
                                visualDensity: VisualDensity.compact,
                                constraints: const BoxConstraints(
                                  minWidth: 32,
                                  minHeight: 32,
                                ),
                              ),
                          ],
                        ),
                      ),
                    )
                  : Row(
                      children: [
                        Checkbox(
                          value: isSelected,
                          onChanged: (val) => setState(() {
                            if (val == true) {
                              _selectedVariantIds.add(v.id);
                            } else {
                              _selectedVariantIds.remove(v.id);
                            }
                          }),
                        ),
                        Expanded(
                          flex: 2,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                v.sku?.isNotEmpty == true ? v.sku! : '#${v.id}',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (v.barcode?.isNotEmpty == true)
                                Text(
                                  v.barcode!,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: Text(
                            productName,
                            style: theme.textTheme.bodySmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (color != null || sizeName != null)
                          Expanded(
                            flex: 2,
                            child: Wrap(
                              spacing: 4,
                              children: [
                                if (color != null)
                                  Chip(
                                    avatar: color.hexCode != null
                                        ? Container(
                                            width: 12,
                                            height: 12,
                                            decoration: BoxDecoration(
                                              color: _parseHexColor(
                                                color.hexCode!,
                                              ),
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: colorScheme.outline,
                                              ),
                                            ),
                                          )
                                        : null,
                                    label: Text(
                                      color.name,
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                    padding: EdgeInsets.zero,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                if (sizeName != null)
                                  Chip(
                                    label: Text(
                                      sizeName,
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                    padding: EdgeInsets.zero,
                                    visualDensity: VisualDensity.compact,
                                  ),
                              ],
                            ),
                          )
                        else
                          const Expanded(flex: 2, child: SizedBox()),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 60,
                          child: Text(
                            currencyService.format(
                              v.priceCents.toBigInt().toInt(),
                            ),
                            style: theme.textTheme.bodyMedium,
                            textAlign: TextAlign.end,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          width: 50,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: stockColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            localizedQuantity(v.stockQuantity, measurementType),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: stockColor,
                              fontWeight: FontWeight.w600,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(width: 4),
                        if (_canAdjustStock)
                          IconButton(
                            icon: const Icon(LucideIcons.warehouse, size: 16),
                            tooltip: 'products.adjust_inventory'.tr(),
                            onPressed: () =>
                                _openInventoryAdjustment(context, v),
                            visualDensity: VisualDensity.compact,
                            constraints: const BoxConstraints(
                              minWidth: 32,
                              minHeight: 32,
                            ),
                          ),
                        if (_canManageProducts) const SizedBox(width: 4),
                        if (_canManageProducts)
                          IconButton(
                            icon: const Icon(LucideIcons.edit, size: 16),
                            tooltip: 'common.edit'.tr(),
                            onPressed: () => _showEditDialog(context, v),
                            visualDensity: VisualDensity.compact,
                            constraints: const BoxConstraints(
                              minWidth: 32,
                              minHeight: 32,
                            ),
                          ),
                        if (_canManageProducts)
                          IconButton(
                            icon: Icon(
                              v.isActive
                                  ? LucideIcons.toggleRight
                                  : LucideIcons.toggleLeft,
                              size: 16,
                              color: v.isActive
                                  ? colorScheme.primary
                                  : colorScheme.outline,
                            ),
                            tooltip: v.isActive
                                ? 'variants.deactivate'.tr()
                                : 'variants.activate'.tr(),
                            onPressed: () => _toggleActive(context, v),
                            visualDensity: VisualDensity.compact,
                            constraints: const BoxConstraints(
                              minWidth: 32,
                              minHeight: 32,
                            ),
                          ),
                      ],
                    ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDetailPanel(
    ProductVariant variant, {
    required Map<int, String> productNameById,
    required Map<int, String> measurementTypeByProductId,
    required Map<int, ProductColor> colorById,
    required Map<int, String> sizeNameById,
    required CurrencyService currencyService,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final productName = productNameById[variant.productId] ?? '';
    final measurementType =
        measurementTypeByProductId[variant.productId] ?? 'piece';
    final color = variant.colorId == null ? null : colorById[variant.colorId!];
    final sizeName = variant.sizeId == null
        ? null
        : sizeNameById[variant.sizeId!];

    return Container(
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: colorScheme.outlineVariant)),
        color: colorScheme.surfaceContainerLow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: colorScheme.outlineVariant),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'variants.details'.tr(),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(LucideIcons.x),
                  onPressed: () => setState(() => _selectedVariant = null),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDetailRow('variants.product'.tr(), productName),
                  _buildDetailRow('variants.sku'.tr(), variant.sku ?? '—'),
                  _buildDetailRow(
                    'variants.barcode'.tr(),
                    variant.barcode ?? '—',
                  ),
                  if (color != null)
                    _buildDetailRow(
                      'variants.color'.tr(),
                      color.name,
                      colorHex: color.hexCode,
                    ),
                  if (sizeName != null)
                    _buildDetailRow('variants.size'.tr(), sizeName),
                  if (_canViewProductCost)
                    _buildDetailRow(
                      'variants.cost'.tr(),
                      currencyService.format(
                        (variant.lastPurchasePriceCents ?? variant.costCents)
                            .toBigInt()
                            .toInt(),
                      ),
                    ),
                  _buildDetailRow(
                    'variants.price'.tr(),
                    currencyService.format(
                      variant.priceCents.toBigInt().toInt(),
                    ),
                  ),
                  _buildDetailRow(
                    'variants.stock'.tr(),
                    localizedQuantity(variant.stockQuantity, measurementType),
                  ),
                  _buildDetailRow(
                    'variants.status'.tr(),
                    variant.isActive
                        ? 'variants.active'.tr()
                        : 'variants.inactive'.tr(),
                  ),
                  const SizedBox(height: 24),
                  if (_canAdjustStock) ...[
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () =>
                                _openInventoryAdjustment(context, variant),
                            icon: const Icon(LucideIcons.warehouse),
                            label: Text('products.adjust_inventory'.tr()),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _printVariantLabel(context, variant),
                          icon: const Icon(LucideIcons.printer),
                          label: Text('variants.print'.tr()),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_canManageProducts) ...[
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () => _showEditDialog(context, variant),
                            icon: const Icon(LucideIcons.edit),
                            label: Text('common.edit'.tr()),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: TextButton.icon(
                          onPressed: () =>
                              context.push('/products/${variant.productId}'),
                          icon: const Icon(LucideIcons.externalLink),
                          label: Text('variants.open_product'.tr()),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {String? colorHex}) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Row(
              children: [
                if (colorHex != null) ...[
                  Container(
                    width: 16,
                    height: 16,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: _parseHexColor(colorHex),
                      shape: BoxShape.circle,
                      border: Border.all(color: colorScheme.outline),
                    ),
                  ),
                ],
                Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _parseHexColor(String hex) {
    final buffer = StringBuffer();
    if (hex.length == 6 || hex.length == 7) buffer.write('ff');
    buffer.write(hex.replaceFirst('#', ''));
    return Color(int.parse(buffer.toString(), radix: 16));
  }

  // Filter helpers
  String _getStockFilterLabel() {
    switch (_stockFilter) {
      case StockFilter.all:
        return 'variants.stock_all'.tr();
      case StockFilter.inStock:
        return 'variants.stock_in_stock'.tr();
      case StockFilter.lowStock:
        return 'variants.stock_low'.tr();
      case StockFilter.outOfStock:
        return 'variants.stock_out'.tr();
    }
  }

  String _getActiveFilterLabel() {
    if (_activeFilter == null) return 'variants.status_all'.tr();
    return _activeFilter! ? 'variants.active'.tr() : 'variants.inactive'.tr();
  }

  String _getSortLabel() {
    switch (_sortOption) {
      case SortOption.barcode:
        return 'variants.sort_barcode'.tr();
      case SortOption.sku:
        return 'variants.sort_sku'.tr();
      case SortOption.stock:
        return 'variants.sort_stock'.tr();
      case SortOption.recent:
        return 'variants.sort_recent'.tr();
    }
  }

  bool _hasActiveFilters() =>
      _productFilter != null ||
      _colorFilter != null ||
      _sizeFilter != null ||
      _stockFilter != StockFilter.all ||
      _activeFilter != null;

  void _clearAllFilters() => setState(() {
    _productFilter = null;
    _colorFilter = null;
    _sizeFilter = null;
    _stockFilter = StockFilter.all;
    _activeFilter = null;
  });

  // Filter dialogs
  void _showProductFilterDialog(BuildContext context, List<Product> products) {
    showDialog<void>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('variants.filter_by_product'.tr()),
        children: [
          SimpleDialogOption(
            onPressed: () {
              setState(() => _productFilter = null);
              Navigator.pop(ctx);
            },
            child: Text('variants.all_products'.tr()),
          ),
          ...products.map(
            (p) => SimpleDialogOption(
              onPressed: () {
                setState(() => _productFilter = p.id);
                Navigator.pop(ctx);
              },
              child: Text(p.name),
            ),
          ),
        ],
      ),
    );
  }

  void _showColorFilterDialog(BuildContext context, List<ProductColor> colors) {
    showDialog<void>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('variants.filter_by_color'.tr()),
        children: [
          SimpleDialogOption(
            onPressed: () {
              setState(() => _colorFilter = null);
              Navigator.pop(ctx);
            },
            child: Text('variants.all_colors'.tr()),
          ),
          ...colors.map(
            (c) => SimpleDialogOption(
              onPressed: () {
                setState(() => _colorFilter = c.id);
                Navigator.pop(ctx);
              },
              child: Row(
                children: [
                  if (c.hexCode != null)
                    Container(
                      width: 16,
                      height: 16,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: _parseHexColor(c.hexCode!),
                        shape: BoxShape.circle,
                      ),
                    ),
                  Text(c.name),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showSizeFilterDialog(BuildContext context, List<Size> sizes) {
    showDialog<void>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('variants.filter_by_size'.tr()),
        children: [
          SimpleDialogOption(
            onPressed: () {
              setState(() => _sizeFilter = null);
              Navigator.pop(ctx);
            },
            child: Text('variants.all_sizes'.tr()),
          ),
          ...sizes.map(
            (s) => SimpleDialogOption(
              onPressed: () {
                setState(() => _sizeFilter = s.id);
                Navigator.pop(ctx);
              },
              child: Text(s.name),
            ),
          ),
        ],
      ),
    );
  }

  void _showStockFilterDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('variants.filter_by_stock'.tr()),
        children: StockFilter.values
            .map(
              (f) => SimpleDialogOption(
                onPressed: () {
                  setState(() => _stockFilter = f);
                  Navigator.pop(ctx);
                },
                child: Text(_getStockFilterLabelFor(f)),
              ),
            )
            .toList(),
      ),
    );
  }

  String _getStockFilterLabelFor(StockFilter filter) {
    switch (filter) {
      case StockFilter.all:
        return 'variants.stock_all'.tr();
      case StockFilter.inStock:
        return 'variants.stock_in_stock'.tr();
      case StockFilter.lowStock:
        return 'variants.stock_low'.tr();
      case StockFilter.outOfStock:
        return 'variants.stock_out'.tr();
    }
  }

  void _showActiveFilterDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('variants.filter_by_status'.tr()),
        children: [
          SimpleDialogOption(
            onPressed: () {
              setState(() => _activeFilter = null);
              Navigator.pop(ctx);
            },
            child: Text('variants.status_all'.tr()),
          ),
          SimpleDialogOption(
            onPressed: () {
              setState(() => _activeFilter = true);
              Navigator.pop(ctx);
            },
            child: Text('variants.active'.tr()),
          ),
          SimpleDialogOption(
            onPressed: () {
              setState(() => _activeFilter = false);
              Navigator.pop(ctx);
            },
            child: Text('variants.inactive'.tr()),
          ),
        ],
      ),
    );
  }

  void _showSortDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('variants.sort_by'.tr()),
        children: SortOption.values
            .map(
              (s) => SimpleDialogOption(
                onPressed: () {
                  setState(() => _sortOption = s);
                  Navigator.pop(ctx);
                },
                child: Text(_getSortLabelFor(s)),
              ),
            )
            .toList(),
      ),
    );
  }

  String _getSortLabelFor(SortOption option) {
    switch (option) {
      case SortOption.barcode:
        return 'variants.sort_barcode'.tr();
      case SortOption.sku:
        return 'variants.sort_sku'.tr();
      case SortOption.stock:
        return 'variants.sort_stock'.tr();
      case SortOption.recent:
        return 'variants.sort_recent'.tr();
    }
  }

  // Actions
  void _handleBarcodeSearch() {
    // Auto-select if exact barcode match
  }

  void _openBarcodeScanner(BuildContext context) {
    context.push('/barcode-scanner');
  }

  void _showAddVariantDialog(BuildContext context) {
    // Show product selection first, then variant dialog
    final productsBloc = context.read<ProductsBloc>();
    final categoriesBloc = context.read<CategoriesBloc>();

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return MultiBlocProvider(
          providers: [
            BlocProvider.value(value: productsBloc),
            BlocProvider.value(value: categoriesBloc),
          ],
          child: _ProductPickerDialog(
            onSelected: (p) {
              Navigator.pop(ctx);
              VariantEditDialog.show(
                context,
                productId: p.id,
                measurementType: p.measurementType,
              );
            },
          ),
        );
      },
    );
  }

  void _showEditDialog(BuildContext context, ProductVariant variant) {
    final products = _getProductsFromBloc(context);
    final measurementType = products
        .where((product) => product.id == variant.productId)
        .map((product) => product.measurementType)
        .firstOrNull;
    VariantEditDialog.show(
      context,
      productId: variant.productId,
      variant: variant,
      measurementType: measurementType ?? 'piece',
    );
  }

  /// Opens the accounting-safe Inventory Adjustment dialog. This is the
  /// ONLY path that may change on-hand stock or unit cost outside of
  /// purchase / sale / return documents. Every post goes through
  /// `InventoryAdjustmentService`, which writes a balanced journal entry
  /// and an `inventory_adjustments` audit row atomically.
  Future<void> _openInventoryAdjustment(
    BuildContext context,
    ProductVariant variant,
  ) async {
    final products = _getProductsFromBloc(context);
    final colors = _getColorsFromBloc(context);
    final sizes = _getSizesFromBloc(context);
    final parent = products
        .where((p) => p.id == variant.productId)
        .cast<Product?>()
        .firstOrNull;
    final colorName = variant.colorId == null
        ? null
        : colors
              .where((c) => c.id == variant.colorId)
              .map((c) => c.name)
              .cast<String?>()
              .firstOrNull;
    final sizeName = variant.sizeId == null
        ? null
        : sizes
              .where((s) => s.id == variant.sizeId)
              .map((s) => s.name)
              .cast<String?>()
              .firstOrNull;
    final label = [
      parent?.name,
      [colorName, sizeName].whereType<String>().join(' / '),
    ].whereType<String>().where((s) => s.isNotEmpty).join(' — ');

    final posted = await InventoryAdjustmentDialog.show(
      context,
      productId: variant.productId,
      variantId: variant.id,
      currentStock: variant.stockQuantity,
      currentUnitCostCents: variant.costCents.toBigInt().toInt(),
      subjectLabel: label.isEmpty ? null : label,
    );
    if (posted == true && context.mounted) {
      context.read<ProductVariantsBloc>().add(const AllVariantsInitialized());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('inventory_adjustment.posted_success'.tr())),
      );
    }
  }

  void _toggleActive(BuildContext context, ProductVariant variant) {
    final updated = ProductVariant(
      id: variant.id,
      productId: variant.productId,
      sku: variant.sku,
      barcode: variant.barcode,
      colorId: variant.colorId,
      sizeId: variant.sizeId,
      costCents: variant.costCents,
      priceCents: variant.priceCents,
      priceAdjustmentCents: variant.priceAdjustmentCents,
      stockQuantity: variant.stockQuantity,
      isActive: !variant.isActive,
    );
    context.read<ProductVariantsBloc>().add(VariantUpdateRequested(updated));
  }

  void _printVariantLabel(BuildContext context, ProductVariant variant) {
    final products = _getProductsFromBloc(context);
    final colors = _getColorsFromBloc(context);
    final sizes = _getSizesFromBloc(context);
    final parentProduct = products
        .where((p) => p.id == variant.productId)
        .cast<Product?>()
        .firstOrNull;

    final colorName = variant.colorId == null
        ? null
        : colors
              .where((c) => c.id == variant.colorId)
              .map((c) => c.name)
              .cast<String?>()
              .firstOrNull;
    final sizeName = variant.sizeId == null
        ? null
        : sizes
              .where((s) => s.id == variant.sizeId)
              .map((s) => s.name)
              .cast<String?>()
              .firstOrNull;
    final info = [
      sizeName,
      colorName,
    ].whereType<String>().where((v) => v.trim().isNotEmpty).join(' / ');

    // Keep the parent product identity for print history, and explicitly
    // restrict the barcode designer to this one variant.
    final printProduct =
        parentProduct ??
        Product(
          id: variant.productId,
          name: '',
          nameAr: null,
          nameFr: null,
          description: null,
          sku: variant.sku,
          barcode: variant.barcode,
          costCents: variant.costCents,
          priceCents: variant.priceCents,
          wholesalePriceCents: variant.wholesalePriceCents,
          stockQuantity: variant.stockQuantity,
          minQuantity: 0,
          categoryId: null,
          supplierId: null,
          currencyId: null,
          imagePath: null,
          hasVariants: false,
          isTaxable: false,
          purchaseTaxRateBps: 0,
          salesTaxRateBps: 0,
          isActive: true,
          trackInventory: false,
        );
    context.push(
      '/products/barcode-design',
      extra: {
        'products': [printProduct],
        'variantInfoByProductId': {printProduct.id: info},
        if (parentProduct != null) 'selectedVariantIds': <int>{variant.id},
      },
    );
  }

  void _printSelectedLabels(BuildContext context) {
    final products = _getProductsFromBloc(context);
    final variants = _getVariantsFromBloc(context);
    final selectedVariants = variants
        .where((v) => _selectedVariantIds.contains(v.id) && v.isActive)
        .toList();
    final selectedProductIds = selectedVariants.map((v) => v.productId).toSet();

    final selectedProducts = products
        .where((p) => selectedProductIds.contains(p.id))
        .toList();

    if (selectedProducts.isEmpty || selectedVariants.isEmpty) return;

    context.push(
      '/products/barcode-design',
      extra: {
        'products': selectedProducts,
        'selectedVariantIds': selectedVariants.map((v) => v.id).toSet(),
      },
    );
  }

  List<Product> _getProductsFromBloc(BuildContext context) {
    final state = context.read<ProductsBloc>().state;
    if (state is RealtimeSuccess<List<Product>>) {
      return state.data;
    }
    if (state is RealtimeLoading<List<Product>>) {
      return state.previousData ?? const <Product>[];
    }
    if (state is RealtimeError<List<Product>>) {
      return state.previousData ?? const <Product>[];
    }
    return const <Product>[];
  }

  List<ProductVariant> _getVariantsFromBloc(BuildContext context) {
    final state = context.read<ProductVariantsBloc>().state;
    if (state is RealtimeSuccess<List<ProductVariant>>) {
      return state.data;
    }
    if (state is RealtimeLoading<List<ProductVariant>>) {
      return state.previousData ?? const <ProductVariant>[];
    }
    if (state is RealtimeError<List<ProductVariant>>) {
      return state.previousData ?? const <ProductVariant>[];
    }
    return const <ProductVariant>[];
  }

  List<ProductColor> _getColorsFromBloc(BuildContext context) {
    final state = context.read<ColorsBloc>().state;
    if (state is RealtimeSuccess<List<ProductColor>>) {
      return state.data;
    }
    if (state is RealtimeLoading<List<ProductColor>>) {
      return state.previousData ?? const <ProductColor>[];
    }
    if (state is RealtimeError<List<ProductColor>>) {
      return state.previousData ?? const <ProductColor>[];
    }
    return const <ProductColor>[];
  }

  List<Size> _getSizesFromBloc(BuildContext context) {
    final state = context.read<SizesBloc>().state;
    if (state is RealtimeSuccess<List<Size>>) {
      return state.data;
    }
    if (state is RealtimeLoading<List<Size>>) {
      return state.previousData ?? const <Size>[];
    }
    if (state is RealtimeError<List<Size>>) {
      return state.previousData ?? const <Size>[];
    }
    return const <Size>[];
  }

  void _bulkSetActive(BuildContext context, bool active) {
    final variants = _getVariantsFromBloc(context);

    final selected = variants
        .where((v) => _selectedVariantIds.contains(v.id))
        .toList();
    if (selected.isEmpty) return;

    for (final v in selected) {
      if (v.isActive == active) continue;
      final updated = ProductVariant(
        id: v.id,
        productId: v.productId,
        sku: v.sku,
        barcode: v.barcode,
        colorId: v.colorId,
        sizeId: v.sizeId,
        costCents: v.costCents,
        priceCents: v.priceCents,
        priceAdjustmentCents: v.priceAdjustmentCents,
        stockQuantity: v.stockQuantity,
        isActive: active,
      );
      context.read<ProductVariantsBloc>().add(VariantUpdateRequested(updated));
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          active
              ? 'variants.bulk_activated'.tr()
              : 'variants.bulk_deactivated'.tr(),
        ),
      ),
    );
    setState(() => _selectedVariantIds.clear());
  }
}

class _ProductPickerDialog extends StatefulWidget {
  final ValueChanged<Product> onSelected;

  const _ProductPickerDialog({required this.onSelected});

  @override
  State<_ProductPickerDialog> createState() => _ProductPickerDialogState();
}

class _ProductPickerDialogState extends State<_ProductPickerDialog> {
  final TextEditingController _searchController = TextEditingController();
  int? _categoryId;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _matches(Product p, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;

    final fields = <String?>[p.name, p.nameAr, p.nameFr, p.sku, p.barcode];

    for (final f in fields) {
      final v = f?.toLowerCase();
      if (v != null && v.contains(q)) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('variants.select_product'.tr()),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'variants.product_search_hint'.tr(),
                prefixIcon: const Icon(LucideIcons.search),
                suffixIcon: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _searchController,
                  builder: (context, value, _) {
                    if (value.text.isEmpty) return const SizedBox.shrink();
                    return IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {});
                      },
                    );
                  },
                ),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            BlocBuilder<CategoriesBloc, RealtimeState<List<Category>>>(
              builder: (context, state) {
                final categories = state is RealtimeSuccess<List<Category>>
                    ? state.data
                    : <Category>[];

                final activeCategories = categories
                    .where((c) => c.isActive)
                    .toList();
                activeCategories.sort(
                  (a, b) =>
                      a.name.toLowerCase().compareTo(b.name.toLowerCase()),
                );

                return DropdownButtonFormField<int?>(
                  initialValue: _categoryId,
                  decoration: InputDecoration(
                    labelText: 'variants.category_filter'.tr(),
                    border: const OutlineInputBorder(),
                    isDense: true,
                    prefixIcon: const Icon(LucideIcons.folderTree),
                  ),
                  items: [
                    DropdownMenuItem<int?>(
                      value: null,
                      child: Text('variants.all_categories'.tr()),
                    ),
                    ...activeCategories.map(
                      (c) => DropdownMenuItem<int?>(
                        value: c.id,
                        child: Text(c.name),
                      ),
                    ),
                  ],
                  onChanged: (v) => setState(() => _categoryId = v),
                );
              },
            ),
            const SizedBox(height: 12),
            Flexible(
              child: BlocBuilder<ProductsBloc, RealtimeState<List<Product>>>(
                builder: (context, state) {
                  final products = state is RealtimeSuccess<List<Product>>
                      ? state.data
                      : <Product>[];
                  final query = _searchController.text;

                  final filtered = products.where((p) {
                    if (_categoryId != null && p.categoryId != _categoryId) {
                      return false;
                    }
                    return _matches(p, query);
                  }).toList();

                  filtered.sort(
                    (a, b) =>
                        a.name.toLowerCase().compareTo(b.name.toLowerCase()),
                  );

                  if (filtered.isEmpty) {
                    return Center(child: Text('variants.no_results'.tr()));
                  }

                  final skuLabel = 'variants.sku'.tr();
                  final barcodeLabel = 'variants.barcode'.tr();

                  return ListView.separated(
                    shrinkWrap: true,
                    itemCount: filtered.length,
                    separatorBuilder: (_, dividerIndex) =>
                        const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final p = filtered[index];
                      final subtitleParts = <String>[];
                      if (p.sku != null && p.sku!.trim().isNotEmpty) {
                        subtitleParts.add('$skuLabel: ${p.sku}');
                      }
                      if (p.barcode != null && p.barcode!.trim().isNotEmpty) {
                        subtitleParts.add('$barcodeLabel: ${p.barcode}');
                      }

                      return ListTile(
                        title: Text(p.name),
                        subtitle: subtitleParts.isEmpty
                            ? null
                            : Text(
                                subtitleParts.join(' • '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                        onTap: () => widget.onSelected(p),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('common.cancel'.tr()),
        ),
      ],
    );
  }
}
