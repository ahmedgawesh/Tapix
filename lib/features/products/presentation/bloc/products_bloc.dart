import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/di/injection_container.dart';
import '../../../settings/presentation/bloc/app_settings_bloc.dart';
import '../../domain/entities/product_entity.dart';
import '../../domain/repositories/product_repository.dart';

/// Events specific to products management
abstract class ProductsEvent extends RealtimeEvent {
  const ProductsEvent();
}

/// Event to create a new product
class ProductCreateRequested extends ProductsEvent {
  final String sku;
  final String name;
  final String? description;
  final int? categoryId;
  final Decimal costCents;
  final Decimal priceCents;
  final Decimal? wholesalePriceCents;
  final int currencyId;
  final bool trackInventory;
  final int stockQuantity;
  final int minQuantity;
  final bool hasVariants;
  final bool isTaxable;
  final int purchaseTaxRateBps;
  final int salesTaxRateBps;
  final String? imagePath;

  const ProductCreateRequested({
    required this.sku,
    required this.name,
    this.description,
    this.categoryId,
    required this.costCents,
    required this.priceCents,
    this.wholesalePriceCents,
    required this.currencyId,
    this.trackInventory = true,
    this.stockQuantity = 0,
    this.minQuantity = 0,
    this.hasVariants = false,
    this.isTaxable = false,
    this.purchaseTaxRateBps = 0,
    this.salesTaxRateBps = 0,
    this.imagePath,
  });
}

/// Event to update an existing product
class ProductUpdateRequested extends ProductsEvent {
  final Product product;

  const ProductUpdateRequested(this.product);
}

/// Event to delete a product
class ProductDeleteRequested extends ProductsEvent {
  final int productId;

  const ProductDeleteRequested(this.productId);
}

/// Stock-aware delete: posts a balanced Shrinkage adjustment for every
/// variant carrying on-hand stock (Dr 5800 / Cr 1200) BEFORE running smart
/// delete, so the 1200 Inventory ledger always equals Σ(stock × cost).
class ProductWriteOffAndDeleteRequested extends ProductsEvent {
  final int productId;
  final String reason;

  const ProductWriteOffAndDeleteRequested({
    required this.productId,
    required this.reason,
  });
}

/// Event to search products
class ProductSearchRequested extends ProductsEvent {
  final String query;

  const ProductSearchRequested(this.query);
}

/// Event to filter products
class ProductFilterRequested extends ProductsEvent {
  final int? categoryId;
  final String? stockStatus;
  final bool? isActive;

  const ProductFilterRequested({
    this.categoryId,
    this.stockStatus,
    this.isActive,
  });
}

/// Event to clear all filters
class ProductFilterCleared extends ProductsEvent {
  const ProductFilterCleared();
}

/// Event to scan barcode
class ProductBarcodeScanned extends ProductsEvent {
  final String barcode;

  const ProductBarcodeScanned(this.barcode);
}

/// Event to load more products (pagination)
class ProductLoadMoreRequested extends ProductsEvent {
  const ProductLoadMoreRequested();
}

/// Products Bloc that extends RealtimeBloc for automatic real-time updates
class ProductsBloc extends RealtimeBloc<List<Product>, ProductsEvent> {
  final ProductRepository _repository;
  String? _currentSearchQuery;
  int? _currentCategoryFilter;
  String? _currentStockStatusFilter;
  bool? _currentIsActiveFilter = true;
  int _currentPage = 0;
  static const int _pageSize = 50;
  bool _hasMoreData = false;
  bool _isLoadingMore = false;

  ProductsBloc(this._repository) : super();

  @override
  Stream<List<Product>> get dataStream {
    // For filter-based views, use DB streams so UI updates instantly
    // (especially for stock status which depends on variants).
    final hasDbFilters = _currentCategoryFilter != null || _currentStockStatusFilter != null;
    if (hasDbFilters) {
      // Get global lowStockThreshold from settings (default 5 if not available)
      final threshold = _getLowStockThreshold();
      return _repository.watchFilteredProducts(
        categoryId: _currentCategoryFilter,
        stockStatus: _currentStockStatusFilter,
        isActive: _currentIsActiveFilter,
        lowStockThreshold: threshold,
      );
    }

    return _repository.watchAllProducts(
      isActive: _currentIsActiveFilter,
    );
  }

  int _getLowStockThreshold() {
    try {
      final settingsBloc = sl<AppSettingsBloc>();
      return settingsBloc.state.settings.lowStockThreshold;
    } catch (e) {
      return 5; // Default fallback
    }
  }

  @override
  void registerEventHandlers() {
    on<ProductCreateRequested>(_onProductCreate);
    on<ProductUpdateRequested>(_onProductUpdate);
    on<ProductDeleteRequested>(_onProductDelete);
    on<ProductWriteOffAndDeleteRequested>(_onProductWriteOffAndDelete);
    on<ProductSearchRequested>(_onProductSearch);
    on<ProductFilterRequested>(_onProductFilter);
    on<ProductFilterCleared>(_onFilterCleared);
    on<ProductBarcodeScanned>(_onBarcodeScanned);
    on<ProductLoadMoreRequested>(_onLoadMore);
  }

  Future<void> _onProductCreate(
    ProductCreateRequested event,
    Emitter<RealtimeState<List<Product>>> emit,
  ) async {
    try {
      await _repository.createProduct(
        sku: event.sku,
        name: event.name,
        description: event.description,
        categoryId: event.categoryId,
        costCents: event.costCents,
        priceCents: event.priceCents,
        wholesalePriceCents: event.wholesalePriceCents,
        currencyId: event.currencyId,
        trackInventory: event.trackInventory,
        stockQuantity: event.stockQuantity,
        minQuantity: event.minQuantity,
        hasVariants: event.hasVariants,
        isTaxable: event.isTaxable,
        purchaseTaxRateBps: event.purchaseTaxRateBps,
        salesTaxRateBps: event.salesTaxRateBps,
        imagePath: event.imagePath,
      );
    } catch (e, st) {
      add(RealtimeErrorOccurred(e, st));
    }
  }

  Future<void> _onProductUpdate(
    ProductUpdateRequested event,
    Emitter<RealtimeState<List<Product>>> emit,
  ) async {
    final currentProducts = currentData;
    if (currentProducts == null) return;

    final optimisticProducts = currentProducts.map((p) {
      if (p.id == event.product.id) {
        return event.product;
      }
      return p;
    }).toList();

    await performOptimisticUpdate(
      operationId: 'update_${event.product.id}_${DateTime.now().millisecondsSinceEpoch}',
      optimisticData: optimisticProducts,
      operation: () => _repository.updateProduct(event.product),
    );
  }

  Future<void> _onProductDelete(
    ProductDeleteRequested event,
    Emitter<RealtimeState<List<Product>>> emit,
  ) async {
    final currentProducts = currentData;
    if (currentProducts == null) return;

    final optimisticProducts = currentProducts
        .where((p) => p.id != event.productId)
        .toList();

    // Route through smart-delete so referenced products are deactivated
     // (soft-delete) rather than triggering a SQL FK restrict failure. This
     // matches the UI flow in `product_form_screen._handleSmartDelete` and
     // mirrors QuickBooks/Xero/Odoo: history-bearing rows must never be
     // hard-deleted because audit trail and journal entries depend on them.
    await performOptimisticUpdate(
      operationId: 'delete_${event.productId}_${DateTime.now().millisecondsSinceEpoch}',
      optimisticData: optimisticProducts,
      operation: () => _repository.smartDeleteProduct(event.productId),
    );
  }

  Future<void> _onProductWriteOffAndDelete(
    ProductWriteOffAndDeleteRequested event,
    Emitter<RealtimeState<List<Product>>> emit,
  ) async {
    final currentProducts = currentData;
    if (currentProducts == null) {
      try {
        await _repository.writeOffAndDeleteProduct(
          productId: event.productId,
          reason: event.reason,
        );
      } catch (e, st) {
        add(RealtimeErrorOccurred(e, st));
      }
      return;
    }

    final optimisticProducts = currentProducts
        .where((p) => p.id != event.productId)
        .toList();

    await performOptimisticUpdate(
      operationId:
          'writeoff_${event.productId}_${DateTime.now().millisecondsSinceEpoch}',
      optimisticData: optimisticProducts,
      operation: () => _repository.writeOffAndDeleteProduct(
        productId: event.productId,
        reason: event.reason,
      ),
    );
  }

  Future<void> _onProductSearch(
    ProductSearchRequested event,
    Emitter<RealtimeState<List<Product>>> emit,
  ) async {
    debugPrint(
      'ProductsBloc.search query="${event.query}" currentData=${currentData?.length ?? 0}',
    );
    _currentSearchQuery = event.query.isEmpty ? null : event.query;

    // Search results are not paginated in the current implementation.
    // Disable pagination loader while a search is active.
    _currentPage = 0;
    _hasMoreData = false;
    _isLoadingMore = false;

    if (_currentSearchQuery == null) {
      _hasMoreData = true;
      _isLoadingMore = false;
      debugPrint('ProductsBloc.search cleared -> refresh (hasMoreData=$_hasMoreData)');
      refresh();
      return;
    }

    debugPrint('ProductsBloc.search active -> disable pagination (hasMoreData=$_hasMoreData)');
    emit(RealtimeLoading<List<Product>>(previousData: currentData));

    try {
      final results = await _repository.searchProducts(
        event.query,
        isActive: _currentIsActiveFilter,
      );
      debugPrint(
        'ProductsBloc.search results=${results.length} -> emit success (hasMoreData=$_hasMoreData)',
      );
      emit(RealtimeSuccess<List<Product>>(data: results));
    } catch (e, st) {
      add(RealtimeErrorOccurred(e, st));
    }
  }

  Future<void> _onProductFilter(
    ProductFilterRequested event,
    Emitter<RealtimeState<List<Product>>> emit,
  ) async {
    debugPrint(
      'ProductsBloc.filter categoryId=${event.categoryId} stockStatus=${event.stockStatus} currentData=${currentData?.length ?? 0}',
    );
    if (event.categoryId != null || (event.categoryId == null && _currentCategoryFilter != null)) {
      _currentCategoryFilter = event.categoryId;
    }
    if (event.stockStatus != null || (event.stockStatus == null && _currentStockStatusFilter != null)) {
      _currentStockStatusFilter = event.stockStatus;
    }
    if (event.isActive != null || (event.isActive == null && _currentIsActiveFilter != null)) {
      _currentIsActiveFilter = event.isActive;
    }
    _currentPage = 0;
    _hasMoreData = true;
    _isLoadingMore = false;

    debugPrint('ProductsBloc.filter -> emit loading (hasMoreData=$_hasMoreData page=$_currentPage)');
    // With DB streams, refresh will re-subscribe and emit latest data.
    // Pagination is handled only in the unfiltered list.
    emit(RealtimeLoading<List<Product>>(previousData: currentData));
    refresh();
  }

  Future<void> _onFilterCleared(
    ProductFilterCleared event,
    Emitter<RealtimeState<List<Product>>> emit,
  ) async {
    debugPrint('ProductsBloc.clearFilters -> refresh');
    _currentCategoryFilter = null;
    _currentStockStatusFilter = null;
    _currentSearchQuery = null;
    _currentIsActiveFilter = true;
    _currentPage = 0;
    _hasMoreData = true;
    _isLoadingMore = false;
    refresh();
  }

  Future<void> _onBarcodeScanned(
    ProductBarcodeScanned event,
    Emitter<RealtimeState<List<Product>>> emit,
  ) async {
    debugPrint('ProductsBloc.barcodeScanned barcode=${event.barcode}');
    // Barcode scan returns a single result (or empty), so pagination is not applicable.
    _currentSearchQuery = null;
    _currentPage = 0;
    _hasMoreData = false;
    _isLoadingMore = false;
    emit(RealtimeLoading<List<Product>>(previousData: currentData));

    try {
      final product = await _repository.findByBarcode(event.barcode);
      debugPrint('ProductsBloc.barcodeScanned found=${product != null}');
      if (product != null) {
        emit(RealtimeSuccess<List<Product>>(data: [product]));
      } else {
        emit(RealtimeSuccess<List<Product>>(data: []));
      }
    } catch (e, st) {
      add(RealtimeErrorOccurred(e, st));
    }
  }

  Future<void> _onLoadMore(
    ProductLoadMoreRequested event,
    Emitter<RealtimeState<List<Product>>> emit,
  ) async {
    if (!_hasMoreData) return;
    if (_isLoadingMore) return;

    final currentProducts = currentData ?? [];
    _currentPage++;

    _isLoadingMore = true;

    debugPrint(
      'ProductsBloc.loadMore page=$_currentPage current=${currentProducts.length} hasMoreData=$_hasMoreData',
    );

    try {
      final threshold = _getLowStockThreshold();
      final newProducts = await _repository.filterProducts(
        categoryId: _currentCategoryFilter,
        stockStatus: _currentStockStatusFilter,
        limit: _pageSize,
        offset: _currentPage * _pageSize,
        isActive: _currentIsActiveFilter,
        lowStockThreshold: threshold,
      );

      _hasMoreData = newProducts.length >= _pageSize;
      debugPrint(
        'ProductsBloc.loadMore fetched=${newProducts.length} hasMoreData=$_hasMoreData',
      );
      final allProducts = [...currentProducts, ...newProducts];
      emit(RealtimeSuccess<List<Product>>(data: allProducts));
    } catch (e, st) {
      add(RealtimeErrorOccurred(e, st));
    } finally {
      _isLoadingMore = false;
    }
  }

  /// Get search query if active
  String? get currentSearchQuery => _currentSearchQuery;

  /// Get active filters count
  int get activeFiltersCount {
    int count = 0;
    if (_currentCategoryFilter != null) count++;
    if (_currentStockStatusFilter != null) count++;
    return count;
  }

  /// Get current category filter
  int? get currentCategoryFilter => _currentCategoryFilter;

  /// Get current stock status filter
  String? get currentStockStatusFilter => _currentStockStatusFilter;

  /// Get current active status filter
  bool? get currentIsActiveFilter => _currentIsActiveFilter;

  /// Check if has more data for pagination
  bool get hasMoreData => _hasMoreData;

  /// True only while a load-more request is actively fetching the next page.
  bool get isLoadingMore => _isLoadingMore;

  /// Clear search and return to full list
  void clearSearch() {
    _currentSearchQuery = null;
    refresh();
  }
}
