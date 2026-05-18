import 'package:equatable/equatable.dart';
import 'package:decimal/decimal.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../domain/entities/product_variant_entity.dart';

abstract class EditPricesEvent extends RealtimeEvent with EquatableMixin {
  const EditPricesEvent();

  @override
  List<Object?> get props => [];
}

class EditPricesLoadProducts extends EditPricesEvent {
  const EditPricesLoadProducts();
}

class EditPricesFilterChanged extends EditPricesEvent {
  final int? categoryId;
  final int? supplierId;
  final String? stockStatus;
  final String? searchQuery;

  const EditPricesFilterChanged({
    this.categoryId,
    this.supplierId,
    this.stockStatus,
    this.searchQuery,
  });

  @override
  List<Object?> get props => [categoryId, supplierId, stockStatus, searchQuery];
}

class EditPricesPriceUpdated extends EditPricesEvent {
  final int productId;
  final Decimal newPrice;
  final bool isWholesale;

  const EditPricesPriceUpdated({
    required this.productId,
    required this.newPrice,
    this.isWholesale = false,
  });

  @override
  List<Object?> get props => [productId, newPrice, isWholesale];
}

class EditPricesVariantPriceUpdated extends EditPricesEvent {
  final ProductVariant updatedVariant;

  const EditPricesVariantPriceUpdated(this.updatedVariant);

  @override
  List<Object?> get props => [updatedVariant];
}

class EditPricesSaveChanges extends EditPricesEvent {
  const EditPricesSaveChanges();
}

// Bulk adjustment events
class EditPricesBulkAdjustRequested extends EditPricesEvent {
  final String adjustmentType; // 'percentage_increase', 'percentage_decrease', 'fixed_increase', 'fixed_decrease'
  final Decimal value;
  final String priceType; // 'cost', 'selling', 'wholesale'
  final bool applyToAll; // true = all products, false = selected only
  final List<int>? selectedProductIds; // null when applyToAll is true
  final List<int>? selectedVariantIds;

  const EditPricesBulkAdjustRequested({
    required this.adjustmentType,
    required this.value,
    this.priceType = 'selling',
    this.applyToAll = false,
    this.selectedProductIds,
    this.selectedVariantIds,
  });

  @override
  List<Object?> get props => [adjustmentType, value, priceType, applyToAll, selectedProductIds, selectedVariantIds];
}

class EditPricesUndoRequested extends EditPricesEvent {
  const EditPricesUndoRequested();
}

class EditPricesRedoRequested extends EditPricesEvent {
  const EditPricesRedoRequested();
}

class EditPricesDiscardChanges extends EditPricesEvent {
  const EditPricesDiscardChanges();
}

class EditPricesProductSelectionToggled extends EditPricesEvent {
  final int productId;
  final bool isSelected;

  const EditPricesProductSelectionToggled({
    required this.productId,
    required this.isSelected,
  });

  @override
  List<Object?> get props => [productId, isSelected];
}

class EditPricesVariantSelectionToggled extends EditPricesEvent {
  final int variantId;
  final bool isSelected;

  const EditPricesVariantSelectionToggled({
    required this.variantId,
    required this.isSelected,
  });

  @override
  List<Object?> get props => [variantId, isSelected];
}

class EditPricesSelectAllToggled extends EditPricesEvent {
  final bool selectAll;

  const EditPricesSelectAllToggled({required this.selectAll});

  @override
  List<Object?> get props => [selectAll];
}
