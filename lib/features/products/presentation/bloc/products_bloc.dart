import 'package:decimal/decimal.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart';
import '../../data/repositories/product_repository.dart';

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
  final int currencyId;
  final bool trackInventory;
  final int stockQuantity;
  final int? reorderLevel;
  final bool hasVariants;

  const ProductCreateRequested({
    required this.sku,
    required this.name,
    this.description,
    this.categoryId,
    required this.costCents,
    required this.priceCents,
    required this.currencyId,
    this.trackInventory = true,
    this.stockQuantity = 0,
    this.reorderLevel,
    this.hasVariants = false,
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

/// Event to search products
class ProductSearchRequested extends ProductsEvent {
  final String query;

  const ProductSearchRequested(this.query);
}

/// Products Bloc that extends RealtimeBloc for automatic real-time updates
class ProductsBloc extends RealtimeBloc<List<Product>, ProductsEvent> {
  final ProductRepository _repository;
  String? _currentSearchQuery;

  ProductsBloc(this._repository) : super();

  @override
  Stream<List<Product>> get dataStream => _repository.watchAllProducts();

  @override
  void registerEventHandlers() {
    on<ProductCreateRequested>(_onProductCreate);
    on<ProductUpdateRequested>(_onProductUpdate);
    on<ProductDeleteRequested>(_onProductDelete);
    on<ProductSearchRequested>(_onProductSearch);
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
        currencyId: event.currencyId,
        trackInventory: event.trackInventory,
        stockQuantity: event.stockQuantity,
        reorderLevel: event.reorderLevel,
        hasVariants: event.hasVariants,
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

    await performOptimisticUpdate(
      operationId: 'delete_${event.productId}_${DateTime.now().millisecondsSinceEpoch}',
      optimisticData: optimisticProducts,
      operation: () => _repository.deleteProduct(event.productId),
    );
  }

  Future<void> _onProductSearch(
    ProductSearchRequested event,
    Emitter<RealtimeState<List<Product>>> emit,
  ) async {
    _currentSearchQuery = event.query.isEmpty ? null : event.query;

    if (_currentSearchQuery == null) {
      refresh();
      return;
    }

    emit(RealtimeLoading<List<Product>>(previousData: currentData));

    try {
      final results = await _repository.searchProducts(event.query);
      emit(RealtimeSuccess<List<Product>>(data: results));
    } catch (e, st) {
      add(RealtimeErrorOccurred(e, st));
    }
  }

  /// Get search query if active
  String? get currentSearchQuery => _currentSearchQuery;

  /// Clear search and return to full list
  void clearSearch() {
    _currentSearchQuery = null;
    refresh();
  }
}
