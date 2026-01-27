import 'dart:async';
import 'package:decimal/decimal.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../domain/entities/product_entity.dart';
import '../../domain/repositories/product_repository.dart';
import 'edit_prices_event.dart';
import 'edit_prices_state.dart';

class EditPricesBloc extends RealtimeBloc<EditPricesStateData, EditPricesEvent> {
  final ProductRepository _repository;

  int? _categoryId;
  int? _supplierId;
  String? _stockStatus;
  String? _searchQuery;
  
  // Track price changes that haven't been saved yet
  final Map<int, Map<String, Decimal>> _priceChanges = {};
  bool _hasUnsavedChanges = false;
  
  // Track selected products for bulk operations
  final Set<int> _selectedProductIds = {};
  
  // Undo/Redo stacks
  final List<Map<int, Map<String, Decimal>>> _undoStack = [];
  final List<Map<int, Map<String, Decimal>>> _redoStack = [];
  final int _maxUndoStackSize = 50;

  EditPricesBloc(this._repository) : super(const RealtimeLoading());

  @override
  Stream<EditPricesStateData> get dataStream {
    Stream<List<Product>> sourceStream;
    
    // Use the appropriate repository method based on filters
    if (_categoryId != null || _stockStatus != null) {
      sourceStream = _repository.watchFilteredProducts(
        categoryId: _categoryId,
        stockStatus: _stockStatus,
      );
    } else {
      sourceStream = _repository.watchAllProducts();
    }

    return sourceStream.map((products) {
      // Apply memory filters for things not supported by DB stream yet (like search query)
      var filtered = products;
      
      if (_searchQuery != null && _searchQuery!.isNotEmpty) {
        final query = _searchQuery!.toLowerCase();
        filtered = products.where((p) => 
          p.name.toLowerCase().contains(query) || 
          (p.sku != null && p.sku!.toLowerCase().contains(query))
        ).toList();
      }
      
      // Note: supplierId filter is not yet supported in repository stream, 
      // so we would filter here if we had supplierId on Product entity.
      // Assuming Product entity has supplierId (it does).
      if (_supplierId != null) {
        filtered = products.where((p) => p.supplierId == _supplierId).toList();
      }

      // Apply optimistic price changes
      final productsWithChanges = filtered.map((product) {
        final changes = _priceChanges[product.id];
        if (changes != null) {
          var updatedProduct = product;
          if (changes.containsKey('costCents')) {
            updatedProduct = updatedProduct.copyWith(costCents: changes['costCents']!);
          }
          if (changes.containsKey('priceCents')) {
            updatedProduct = updatedProduct.copyWith(priceCents: changes['priceCents']!);
          }
          if (changes.containsKey('wholesalePriceCents')) {
            updatedProduct = updatedProduct.copyWith(wholesalePriceCents: changes['wholesalePriceCents']!);
          }
          return updatedProduct;
        }
        return product;
      }).toList();

      return EditPricesStateData(
        products: productsWithChanges,
        categoryId: _categoryId,
        supplierId: _supplierId,
        stockStatus: _stockStatus,
        searchQuery: _searchQuery,
        hasUnsavedChanges: _hasUnsavedChanges,
        selectedProductIds: _selectedProductIds,
      );
    });
  }

  @override
  void registerEventHandlers() {
    on<EditPricesLoadProducts>(_onLoadProducts);
    on<EditPricesFilterChanged>(_onFilterChanged);
    on<EditPricesPriceUpdated>(_onPriceUpdated);
    on<EditPricesSaveChanges>(_onSaveChanges);
    on<EditPricesBulkAdjustRequested>(_onBulkAdjust);
    on<EditPricesUndoRequested>(_onUndo);
    on<EditPricesRedoRequested>(_onRedo);
    on<EditPricesDiscardChanges>(_onDiscardChanges);
    on<EditPricesProductSelectionToggled>(_onProductSelectionToggled);
    on<EditPricesSelectAllToggled>(_onSelectAllToggled);
  }

  Future<void> _onLoadProducts(
    EditPricesLoadProducts event,
    Emitter<RealtimeState<EditPricesStateData>> emit,
  ) async {
    refresh();
  }

  void _onFilterChanged(
    EditPricesFilterChanged event,
    Emitter<RealtimeState<EditPricesStateData>> emit,
  ) {
    if (event.categoryId != null) _categoryId = event.categoryId;
    if (event.supplierId != null) _supplierId = event.supplierId;
    if (event.stockStatus != null) _stockStatus = event.stockStatus;
    if (event.searchQuery != null) _searchQuery = event.searchQuery;
    
    // Refresh to update the stream with new filters
    refresh();
  }

  void _onPriceUpdated(
    EditPricesPriceUpdated event,
    Emitter<RealtimeState<EditPricesStateData>> emit,
  ) {
    // Save current state to undo stack
    _saveToUndoStack();
    
    // Track the price change for optimistic update
    if (!_priceChanges.containsKey(event.productId)) {
      _priceChanges[event.productId] = {};
    }
    
    if (event.isWholesale) {
      _priceChanges[event.productId]!['wholesalePriceCents'] = event.newPrice;
    } else {
      _priceChanges[event.productId]!['priceCents'] = event.newPrice;
    }
    
    _hasUnsavedChanges = true;
    
    // Clear redo stack when new change is made
    _redoStack.clear();
    
    // Trigger refresh to apply optimistic changes
    refresh();
  }
  
  void _saveToUndoStack() {
    // Deep copy current state
    final snapshot = <int, Map<String, Decimal>>{};
    for (final entry in _priceChanges.entries) {
      snapshot[entry.key] = Map.from(entry.value);
    }
    
    _undoStack.add(snapshot);
    
    // Limit stack size
    if (_undoStack.length > _maxUndoStackSize) {
      _undoStack.removeAt(0);
    }
  }

  Future<void> _onSaveChanges(
    EditPricesSaveChanges event,
    Emitter<RealtimeState<EditPricesStateData>> emit,
  ) async {
    if (_priceChanges.isEmpty) return;
    
    try {
      // Get current products from state
      final currentState = state;
      if (currentState is! RealtimeSuccess<EditPricesStateData>) return;
      
      final products = currentState.data.products;
      
      // Update each product with price changes
      for (final entry in _priceChanges.entries) {
        final productId = entry.key;
        final changes = entry.value;
        
        // Find the product in current list
        final product = products.firstWhere(
          (p) => p.id == productId,
          orElse: () => throw Exception('Product $productId not found'),
        );
        
        // Apply changes
        var updatedProduct = product;
        if (changes.containsKey('costCents')) {
          updatedProduct = updatedProduct.copyWith(costCents: changes['costCents']!);
        }
        if (changes.containsKey('priceCents')) {
          updatedProduct = updatedProduct.copyWith(priceCents: changes['priceCents']!);
        }
        if (changes.containsKey('wholesalePriceCents')) {
          updatedProduct = updatedProduct.copyWith(wholesalePriceCents: changes['wholesalePriceCents']!);
        }
        
        // Save to database
        await _repository.updateProduct(updatedProduct);
      }
      
      // Clear changes after successful save
      _priceChanges.clear();
      _hasUnsavedChanges = false;
      
      // Refresh to get updated data from database
      refresh();
    } catch (e, st) {
      add(RealtimeErrorOccurred(e, st));
    }
  }
  
  void _onBulkAdjust(
    EditPricesBulkAdjustRequested event,
    Emitter<RealtimeState<EditPricesStateData>> emit,
  ) {
    final currentState = state;
    if (currentState is! RealtimeSuccess<EditPricesStateData>) return;
    
    final products = currentState.data.products;
    List<Product> targetProducts;
    
    if (event.applyToAll) {
      targetProducts = products;
    } else if (event.selectedProductIds != null) {
      targetProducts = products
          .where((p) => event.selectedProductIds!.contains(p.id))
          .toList();
    } else {
      return;
    }
    
    // Save current state to undo stack
    _saveToUndoStack();
    
    // Determine which price field to update based on priceType
    String priceField;
    switch (event.priceType) {
      case 'cost':
        priceField = 'costCents';
        break;
      case 'wholesale':
        priceField = 'wholesalePriceCents';
        break;
      case 'selling':
      default:
        priceField = 'priceCents';
        break;
    }
    
    // Apply adjustment to each product
    for (final product in targetProducts) {
      if (!_priceChanges.containsKey(product.id)) {
        _priceChanges[product.id] = {};
      }
      
      // Get current price based on price type
      Decimal currentPrice;
      if (_priceChanges[product.id]!.containsKey(priceField)) {
        currentPrice = _priceChanges[product.id]![priceField]!;
      } else {
        // Get original price from product
        switch (event.priceType) {
          case 'cost':
            currentPrice = product.costCents;
            break;
          case 'wholesale':
            currentPrice = product.wholesalePriceCents ?? Decimal.zero;
            break;
          case 'selling':
          default:
            currentPrice = product.priceCents;
            break;
        }
      }
      
      Decimal newPrice;
      
      switch (event.adjustmentType) {
        case 'percentage_increase':
          // Calculate: currentPrice * (1 + percentage/100)
          final increase = ((currentPrice * event.value) / Decimal.fromInt(100)).toDecimal();
          newPrice = currentPrice + increase;
          break;
        case 'percentage_decrease':
          // Calculate: currentPrice * (1 - percentage/100)
          final decrease = ((currentPrice * event.value) / Decimal.fromInt(100)).toDecimal();
          newPrice = currentPrice - decrease;
          break;
        case 'fixed_increase':
          newPrice = currentPrice + event.value;
          break;
        case 'fixed_decrease':
          newPrice = currentPrice - event.value;
          break;
        default:
          continue;
      }
      
      // Ensure price doesn't go negative
      if (newPrice < Decimal.zero) {
        newPrice = Decimal.zero;
      }
      
      _priceChanges[product.id]![priceField] = newPrice;
    }
    
    _hasUnsavedChanges = true;
    _redoStack.clear();
    refresh();
  }
  
  void _onUndo(
    EditPricesUndoRequested event,
    Emitter<RealtimeState<EditPricesStateData>> emit,
  ) {
    if (_undoStack.isEmpty) return;
    
    // Save current state to redo stack
    final currentSnapshot = <int, Map<String, Decimal>>{};
    for (final entry in _priceChanges.entries) {
      currentSnapshot[entry.key] = Map.from(entry.value);
    }
    _redoStack.add(currentSnapshot);
    
    // Restore previous state
    final previousState = _undoStack.removeLast();
    _priceChanges.clear();
    for (final entry in previousState.entries) {
      _priceChanges[entry.key] = Map.from(entry.value);
    }
    
    _hasUnsavedChanges = _priceChanges.isNotEmpty;
    refresh();
  }
  
  void _onRedo(
    EditPricesRedoRequested event,
    Emitter<RealtimeState<EditPricesStateData>> emit,
  ) {
    if (_redoStack.isEmpty) return;
    
    // Save current state to undo stack
    _saveToUndoStack();
    
    // Restore redo state
    final redoState = _redoStack.removeLast();
    _priceChanges.clear();
    for (final entry in redoState.entries) {
      _priceChanges[entry.key] = Map.from(entry.value);
    }
    
    _hasUnsavedChanges = _priceChanges.isNotEmpty;
    refresh();
  }
  
  void _onDiscardChanges(
    EditPricesDiscardChanges event,
    Emitter<RealtimeState<EditPricesStateData>> emit,
  ) {
    _priceChanges.clear();
    _undoStack.clear();
    _redoStack.clear();
    _hasUnsavedChanges = false;
    refresh();
  }
  
  void _onProductSelectionToggled(
    EditPricesProductSelectionToggled event,
    Emitter<RealtimeState<EditPricesStateData>> emit,
  ) {
    if (event.isSelected) {
      _selectedProductIds.add(event.productId);
    } else {
      _selectedProductIds.remove(event.productId);
    }
    refresh();
  }
  
  void _onSelectAllToggled(
    EditPricesSelectAllToggled event,
    Emitter<RealtimeState<EditPricesStateData>> emit,
  ) {
    final currentState = state;
    if (currentState is! RealtimeSuccess<EditPricesStateData>) return;
    
    if (event.selectAll) {
      _selectedProductIds.addAll(
        currentState.data.products.map((p) => p.id),
      );
    } else {
      _selectedProductIds.clear();
    }
    refresh();
  }
  
  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;
  bool get hasUnsavedChanges => _hasUnsavedChanges;
}
