import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/widgets/theme_toggle_button.dart';
import '../../domain/entities/product_entity.dart';
import '../../domain/repositories/product_repository.dart';
import '../bloc/products_bloc.dart';
import '../bloc/variant_summaries_bloc.dart';
import '../bloc/product_variant_previews_bloc.dart';
import '../widgets/product_tile_widget.dart';
import '../widgets/product_search_widget.dart';
import '../widgets/product_filter_widget.dart';

class ProductListScreen extends StatelessWidget {
  const ProductListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (context) => sl<ProductsBloc>()),
        BlocProvider(create: (context) => sl<VariantSummariesBloc>()),
        BlocProvider(create: (context) => sl<ProductVariantPreviewsBloc>()),
      ],
      child: const _ProductListView(),
    );
  }
}

class _ProductListView extends StatefulWidget {
  const _ProductListView();

  @override
  State<_ProductListView> createState() => _ProductListViewState();
}

class _ProductListViewState extends State<_ProductListView> {
  final ScrollController _scrollController = ScrollController();
  final Set<int> _selectedProductIds = {};
  bool _isSelectionMode = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_isBottom) {
      final bloc = context.read<ProductsBloc>();
      if (bloc.hasMoreData) {
        bloc.add(const ProductLoadMoreRequested());
      }
    }
  }

  bool get _isBottom {
    if (!_scrollController.hasClients) return false;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.offset;
    return currentScroll >= (maxScroll * 0.9);
  }

  Widget _buildPrintLabelsBar(BuildContext context) {
    return BlocBuilder<ProductsBloc, RealtimeState<List<Product>>>(
      builder: (context, state) {
        List<Product>? products;
        if (state is RealtimeSuccess<List<Product>>) {
          products = state.data;
        } else if (state is RealtimeOptimistic<List<Product>>) {
          products = state.optimisticData;
        }

        final productCount = products?.length ?? 0;
        final allSelected = productCount > 0 && _selectedProductIds.length == productCount;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            border: Border(
              bottom: BorderSide(
                color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
              ),
            ),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isSmallScreen = constraints.maxWidth <= 380;
              final isVerySmallScreen = constraints.maxWidth < 320;
              
              if (isVerySmallScreen) {
                // For very small screens, stack vertically
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        // Select all checkbox
                        Checkbox(
                          value: allSelected,
                          tristate: true,
                          onChanged: (value) {
                            setState(() {
                              if (value == true && products != null) {
                                _isSelectionMode = true;
                                _selectedProductIds.clear();
                                _selectedProductIds.addAll(products.map((p) => p.id));
                              } else {
                                _selectedProductIds.clear();
                                if (_selectedProductIds.isEmpty) {
                                  _isSelectionMode = false;
                                }
                              }
                            });
                          },
                        ),
                        Expanded(
                          child: Text(
                            _selectedProductIds.isEmpty
                                ? 'products.select_for_print'.tr()
                                : 'products.selected_count'.tr(args: [_selectedProductIds.length.toString()]),
                            style: Theme.of(context).textTheme.bodyMedium,
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Print labels button - full width
                    FilledButton.tonalIcon(
                      onPressed: _selectedProductIds.isEmpty
                          ? null
                          : () => _printSelectedLabels(context),
                      icon: const Icon(LucideIcons.printer, size: 18),
                      label: Text('barcode.print_labels'.tr()),
                    ),
                    const SizedBox(height: 8),
                    FilledButton.tonalIcon(
                      onPressed: _selectedProductIds.isEmpty
                          ? null
                          : () => _deleteSelectedProducts(context),
                      icon: const Icon(LucideIcons.trash, size: 18),
                      label: Text('common.delete'.tr()),
                    ),
                  ],
                );
              }
              
              final content = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Select all checkbox
                  Checkbox(
                    value: allSelected,
                    tristate: true,
                    onChanged: (value) {
                      setState(() {
                        if (value == true && products != null) {
                          _isSelectionMode = true;
                          _selectedProductIds.clear();
                          _selectedProductIds.addAll(products.map((p) => p.id));
                        } else {
                          _selectedProductIds.clear();
                          if (_selectedProductIds.isEmpty) {
                            _isSelectionMode = false;
                          }
                        }
                      });
                    },
                  ),
                  ConstrainedBox(
                    constraints: BoxConstraints(minWidth: isSmallScreen ? 180 : 0),
                    child: Text(
                      _selectedProductIds.isEmpty
                          ? 'products.select_for_print'.tr()
                          : 'products.selected_count'.tr(args: [_selectedProductIds.length.toString()]),
                      style: Theme.of(context).textTheme.bodyMedium,
                      overflow: TextOverflow.ellipsis,
                      maxLines: isSmallScreen ? 1 : 2,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (isSmallScreen)
                    IconButton(
                      onPressed: _selectedProductIds.isEmpty
                          ? null
                          : () => _printSelectedLabels(context),
                      icon: const Icon(LucideIcons.printer),
                      tooltip: 'barcode.print_labels'.tr(),
                    )
                  else
                    FilledButton.tonalIcon(
                      onPressed: _selectedProductIds.isEmpty
                          ? null
                          : () => _printSelectedLabels(context),
                      icon: const Icon(LucideIcons.printer, size: 18),
                      label: Text('barcode.print_labels'.tr()),
                    ),
                  if (isSmallScreen)
                    IconButton(
                      onPressed: _selectedProductIds.isEmpty
                          ? null
                          : () => _deleteSelectedProducts(context),
                      icon: const Icon(LucideIcons.trash2),
                      tooltip: 'common.delete'.tr(),
                    )
                  else
                    Padding(
                      padding: const EdgeInsetsDirectional.only(start: 8),
                      child: FilledButton.tonalIcon(
                        onPressed: _selectedProductIds.isEmpty
                            ? null
                            : () => _deleteSelectedProducts(context),
                        icon: const Icon(LucideIcons.trash, size: 18),
                        label: Text('common.delete'.tr()),
                      ),
                    ),
                ],
              );

              return ClipRect(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: content,
                ),
              );
            },
          ),
        );
      },
    );
  }

  void _printSelectedLabels(BuildContext context) async {
    final bloc = context.read<ProductsBloc>();
    final state = bloc.state;
    
    List<Product>? allProducts;
    if (state is RealtimeSuccess<List<Product>>) {
      allProducts = state.data;
    } else if (state is RealtimeOptimistic<List<Product>>) {
      allProducts = state.optimisticData;
    }
    
    if (allProducts == null) return;
    
    final selectedProducts = allProducts
        .where((p) => _selectedProductIds.contains(p.id))
        .toList();
    
    if (selectedProducts.isEmpty) return;
    
    // Navigate to barcode design screen
    await context.push('/products/barcode-design', extra: {'products': selectedProducts});
    
    // Clear selection after printing
    setState(() {
      _isSelectionMode = false;
      _selectedProductIds.clear();
    });
  }

  Future<void> _deleteSelectedProducts(BuildContext context) async {
    final bloc = context.read<ProductsBloc>();
    final state = bloc.state;

    List<Product>? allProducts;
    if (state is RealtimeSuccess<List<Product>>) {
      allProducts = state.data;
    } else if (state is RealtimeOptimistic<List<Product>>) {
      allProducts = state.optimisticData;
    }

    if (allProducts == null) return;

    final selectedProducts = allProducts
        .where((p) => _selectedProductIds.contains(p.id))
        .toList();
    if (selectedProducts.isEmpty) return;

    final hasStock = selectedProducts.any((p) => p.stockQuantity > 0);
    if (hasStock) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('products.delete_blocked_stock'.tr()),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    final repository = sl<ProductRepository>();
    final referencedIds = await repository.findProductIdsReferencedByOpenPurchases(
      _selectedProductIds.toList(),
    );
    if (referencedIds.isNotEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('products.delete_blocked_open_purchase'.tr()),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    if (!context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('products.delete_title'.tr()),
          content: Text(
            'products.delete_confirm'.tr(args: [selectedProducts.length.toString()]),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('common.cancel'.tr()),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text('common.delete'.tr()),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      await repository.bulkDeleteProducts(_selectedProductIds.toList());
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('products.delete_blocked_linked_records'.tr()),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('products.delete_success'.tr()),
      ),
    );

    setState(() {
      _isSelectionMode = false;
      _selectedProductIds.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _isSelectionMode
            ? Text('products.selected_count'.tr(args: [_selectedProductIds.length.toString()]))
            : Text('dashboard.products'.tr()),
        centerTitle: true,
        leading: _isSelectionMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {
                  setState(() {
                    _isSelectionMode = false;
                    _selectedProductIds.clear();
                  });
                },
                tooltip: 'common.cancel'.tr(),
              )
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go('/dashboard');
                  }
                },
                tooltip: 'common.back'.tr(),
              ),
        actions: _isSelectionMode
            ? [
                IconButton(
                  icon: const Icon(LucideIcons.printer),
                  onPressed: _selectedProductIds.isEmpty
                      ? null
                      : () => _printSelectedLabels(context),
                  tooltip: 'barcode.print_labels'.tr(),
                ),
                IconButton(
                  icon: const Icon(LucideIcons.trash),
                  onPressed: _selectedProductIds.isEmpty
                      ? null
                      : () => _deleteSelectedProducts(context),
                  tooltip: 'common.delete'.tr(),
                ),
              ]
            : [
          IconButton(
            icon: const Icon(LucideIcons.layers),
            onPressed: () async {
              await context.push('/products/variants');
              if (!context.mounted) return;
              context.read<ProductsBloc>().refresh();
              context.read<VariantSummariesBloc>().refresh();
            },
            tooltip: 'variants.title'.tr(),
          ),
          PopupMenuButton<String>(
            icon: const Icon(LucideIcons.moreVertical),
            onSelected: (value) {
              switch (value) {
                case 'bulk':
                  context.push('/products/bulk');
                  break;
                case 'edit_prices':
                  context.push('/products/edit-prices');
                  break;
                case 'import':
                  context.push('/products/import');
                  break;
                case 'export':
                  context.push('/products/export');
                  break;
                case 'variants':
                  context.push('/products/variants');
                  break;
                case 'categories':
                  context.push('/products/categories');
                  break;
                case 'colors':
                  context.push('/products/colors');
                  break;
                case 'sizes':
                  context.push('/products/sizes');
                  break;
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'bulk',
                child: Row(
                  children: [
                    const Icon(LucideIcons.layers),
                    const SizedBox(width: 12),
                    Text('bulk_product.title'.tr()),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'edit_prices',
                child: Row(
                  children: [
                    const Icon(LucideIcons.dollarSign),
                    const SizedBox(width: 12),
                    Text('edit_prices.title'.tr()),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'import',
                child: Row(
                  children: [
                    const Icon(LucideIcons.upload),
                    const SizedBox(width: 12),
                    Text('import_products.title'.tr()),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'export',
                child: Row(
                  children: [
                    const Icon(LucideIcons.download),
                    const SizedBox(width: 12),
                    Text('export_products.title'.tr()),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'variants',
                child: Row(
                  children: [
                    const Icon(LucideIcons.layers),
                    const SizedBox(width: 12),
                    Text('variants.title'.tr()),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'categories',
                child: Row(
                  children: [
                    const Icon(LucideIcons.folder),
                    const SizedBox(width: 12),
                    Text('categories.title'.tr()),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'colors',
                child: Row(
                  children: [
                    const Icon(LucideIcons.palette),
                    const SizedBox(width: 12),
                    Text('colors.title'.tr()),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'sizes',
                child: Row(
                  children: [
                    const Icon(LucideIcons.ruler),
                    const SizedBox(width: 12),
                    Text('sizes.title'.tr()),
                  ],
                ),
              ),
            ],
          ),
          const ThemeToggleButton(),
          IconButton(
            icon: const Icon(LucideIcons.settings),
            onPressed: () {
              context.push('/settings');
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await context.push('/products/new');
          if (!context.mounted) return;
          context.read<ProductsBloc>().refresh();
          context.read<VariantSummariesBloc>().refresh();
        },
        icon: const Icon(LucideIcons.plus),
        label: Text('common.add'.tr()),
      ),
      body: Column(
        children: [
          ProductSearchWidget(
            onChanged: (query) {
              context.read<ProductsBloc>().add(ProductSearchRequested(query));
            },
            onScanBarcode: () async {
              final bloc = context.read<ProductsBloc>();
              final barcode = await context.push<String>(
                '/barcode-scanner',
                extra: {'returnOnScan': true},
              );
              
              if (barcode != null && barcode.isNotEmpty) {
                if (mounted) {
                  bloc.add(ProductBarcodeScanned(barcode));
                }
              }
            },
          ),
          // Print Labels action bar
          _buildPrintLabelsBar(context),
          BlocBuilder<ProductsBloc, RealtimeState<List<Product>>>(
            builder: (context, state) {
              final bloc = context.read<ProductsBloc>();
              return ProductFilterWidget(
                onClearAll: () {
                  bloc.add(const ProductFilterCleared());
                },
                activeFiltersCount: bloc.activeFiltersCount,
                selectedCategoryId: bloc.currentCategoryFilter,
                selectedStockStatus: bloc.currentStockStatusFilter,
                selectedIsActive: bloc.currentIsActiveFilter,
              );
            },
          ),
          const SizedBox(height: 8),
          Expanded(
            child: BlocBuilder<ProductsBloc, RealtimeState<List<Product>>>(
              builder: (context, state) {
                List<Product>? products;
                final bloc = context.read<ProductsBloc>();

                if (state is RealtimeSuccess<List<Product>>) {
                  products = state.data;
                } else if (state is RealtimeLoading<List<Product>>) {
                  products = state.previousData;
                } else if (state is RealtimeError<List<Product>>) {
                  products = state.previousData;
                } else if (state is RealtimeOptimistic<List<Product>>) {
                  products = state.optimisticData;
                }

                if (kDebugMode) {
                  debugPrint(
                    'ProductListScreen.builder state=${state.runtimeType} products=${products?.length ?? -1} hasMore=${bloc.hasMoreData} search=${bloc.currentSearchQuery}',
                  );
                }

                if (state is RealtimeLoading && products == null) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (state is RealtimeError && products == null) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(LucideIcons.alertTriangle, size: 48, color: Colors.red),
                        const SizedBox(height: 16),
                        Text('products.error_loading'.tr(args: [(state as RealtimeError).error.toString()])),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: () {
                            context.read<ProductsBloc>().refresh();
                          },
                          child: Text('common.retry'.tr()),
                        ),
                      ],
                    ),
                  );
                }

                final displayProducts = products ?? [];

                if (displayProducts.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(LucideIcons.packageOpen, size: 64, color: Colors.grey),
                        const SizedBox(height: 16),
                        Text('products.no_results'.tr()),
                      ],
                    ),
                  );
                }

                return BlocBuilder<VariantSummariesBloc, RealtimeState<Map<int, VariantSummary>>>(
                  builder: (context, summariesState) {
                    Map<int, VariantSummary> summaries = const {};
                    if (summariesState is RealtimeSuccess<Map<int, VariantSummary>>) {
                      summaries = summariesState.data;
                    } else if (summariesState is RealtimeLoading<Map<int, VariantSummary>>) {
                      summaries = summariesState.previousData ?? const {};
                    }

                    return BlocBuilder<ProductVariantPreviewsBloc, RealtimeState<Map<int, VariantPreview>>>(
                      builder: (context, previewsState) {
                        Map<int, VariantPreview> previews = const {};
                        if (previewsState is RealtimeSuccess<Map<int, VariantPreview>>) {
                          previews = previewsState.data;
                        } else if (previewsState is RealtimeLoading<Map<int, VariantPreview>>) {
                          previews = previewsState.previousData ?? const {};
                        }

                        return ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.only(bottom: 80),
                          itemCount: displayProducts.length + (bloc.isLoadingMore ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index >= displayProducts.length) {
                              return const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(16.0),
                                  child: CircularProgressIndicator(),
                                ),
                              );
                            }

                            final product = displayProducts[index];
                            final isSelected = _selectedProductIds.contains(product.id);
                            final summary = product.hasVariants ? summaries[product.id] : null;
                            final preview = previews[product.id];

                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                              child: ProductTileWidget(
                                product: product,
                                isSelected: _isSelectionMode ? isSelected : null,
                                variantCount: summary?.count,
                                totalVariantStock: summary?.totalStock,
                                previewSizeName: preview?.sizeName,
                                previewColorHex: preview?.colorHex,
                                onTap: (p) {
                                  if (_isSelectionMode) {
                                    setState(() {
                                      if (isSelected) {
                                        _selectedProductIds.remove(p.id);
                                      } else {
                                        _selectedProductIds.add(p.id);
                                      }
                                    });
                                  } else {
                                    () async {
                                      await context.push('/products/${p.id}/edit');
                                      if (!context.mounted) return;
                                      context.read<ProductsBloc>().refresh();
                                      context.read<VariantSummariesBloc>().refresh();
                                      context.read<ProductVariantPreviewsBloc>().refresh();
                                    }();
                                  }
                                },
                                onLongPress: (p) {
                                  if (!_isSelectionMode) {
                                    setState(() {
                                      _isSelectionMode = true;
                                      _selectedProductIds.add(p.id);
                                    });
                                  }
                                },
                              ),
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

}
