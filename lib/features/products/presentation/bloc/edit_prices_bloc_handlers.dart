import 'package:decimal/decimal.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../domain/entities/product_entity.dart';
import 'edit_prices_event.dart';
import 'edit_prices_state.dart';

// Extension methods for EditPricesBloc handlers
extension EditPricesBlocHandlers on dynamic {
  void handleBulkAdjust(
    EditPricesBulkAdjustRequested event,
    Emitter<RealtimeState<EditPricesStateData>> emit,
    RealtimeState<EditPricesStateData> currentState,
    Map<int, Map<String, Decimal>> priceChanges,
    Function saveToUndoStack,
    Function refresh,
    Function clearRedoStack,
    Function setHasUnsavedChanges,
  ) {
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
    saveToUndoStack();

    // Apply adjustment to each product
    for (final product in targetProducts) {
      if (!priceChanges.containsKey(product.id)) {
        priceChanges[product.id] = {};
      }

      // Get current price (either from changes or original)
      final currentPrice = priceChanges[product.id]!.containsKey('priceCents')
          ? priceChanges[product.id]!['priceCents']!
          : product.priceCents;

      Decimal newPrice;

      switch (event.adjustmentType) {
        case 'percentage_increase':
          newPrice =
              currentPrice *
              (Decimal.one + (event.value / Decimal.fromInt(100)).toDecimal());
          break;
        case 'percentage_decrease':
          newPrice =
              currentPrice *
              (Decimal.one - (event.value / Decimal.fromInt(100)).toDecimal());
          break;
        case 'fixed_increase':
          newPrice = currentPrice + (event.value * Decimal.fromInt(100));
          break;
        case 'fixed_decrease':
          newPrice = currentPrice - (event.value * Decimal.fromInt(100));
          break;
        default:
          continue;
      }

      // Ensure price doesn't go negative
      if (newPrice < Decimal.zero) {
        newPrice = Decimal.zero;
      }

      priceChanges[product.id]!['priceCents'] = newPrice;
    }

    setHasUnsavedChanges();
    clearRedoStack();
    refresh();
  }

  void handleUndo(
    List<Map<int, Map<String, Decimal>>> undoStack,
    List<Map<int, Map<String, Decimal>>> redoStack,
    Map<int, Map<String, Decimal>> priceChanges,
    Function refresh,
    Function setHasUnsavedChanges,
  ) {
    if (undoStack.isEmpty) return;

    // Save current state to redo stack
    final currentSnapshot = <int, Map<String, Decimal>>{};
    for (final entry in priceChanges.entries) {
      currentSnapshot[entry.key] = Map.from(entry.value);
    }
    redoStack.add(currentSnapshot);

    // Restore previous state
    final previousState = undoStack.removeLast();
    priceChanges.clear();
    for (final entry in previousState.entries) {
      priceChanges[entry.key] = Map.from(entry.value);
    }

    setHasUnsavedChanges();
    refresh();
  }

  void handleRedo(
    List<Map<int, Map<String, Decimal>>> undoStack,
    List<Map<int, Map<String, Decimal>>> redoStack,
    Map<int, Map<String, Decimal>> priceChanges,
    Function saveToUndoStack,
    Function refresh,
    Function setHasUnsavedChanges,
  ) {
    if (redoStack.isEmpty) return;

    // Save current state to undo stack
    saveToUndoStack();

    // Restore redo state
    final redoState = redoStack.removeLast();
    priceChanges.clear();
    for (final entry in redoState.entries) {
      priceChanges[entry.key] = Map.from(entry.value);
    }

    setHasUnsavedChanges();
    refresh();
  }

  void handleDiscardChanges(
    Map<int, Map<String, Decimal>> priceChanges,
    List<Map<int, Map<String, Decimal>>> undoStack,
    List<Map<int, Map<String, Decimal>>> redoStack,
    Function clearHasUnsavedChanges,
    Function refresh,
  ) {
    priceChanges.clear();
    undoStack.clear();
    redoStack.clear();
    clearHasUnsavedChanges();
    refresh();
  }
}
