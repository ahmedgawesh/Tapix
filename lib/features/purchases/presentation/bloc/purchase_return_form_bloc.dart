import 'package:decimal/decimal.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';

import '../../domain/entities/purchase_entity.dart';
import '../../domain/repositories/purchase_repository.dart';

// ==================== STATE ====================

class ReturnLineItem extends Equatable {
  final PurchaseItemEntity originalItem;
  final int returnQuantity;
  final Decimal subtotalCents;
  final Decimal discountCents;
  final Decimal taxCents;
  final Decimal refundCents;
  final String? reason;

  const ReturnLineItem({
    required this.originalItem,
    required this.returnQuantity,
    required this.subtotalCents,
    required this.discountCents,
    required this.taxCents,
    required this.refundCents,
    this.reason,
  });

  String get displayName {
    if (originalItem.variantSku != null) {
      return '${originalItem.productName ?? 'Product'} (${originalItem.variantSku})';
    }
    return originalItem.productName ?? 'Product #${originalItem.productId}';
  }

  ReturnLineItem copyWith({
    int? returnQuantity,
    Decimal? subtotalCents,
    Decimal? discountCents,
    Decimal? taxCents,
    Decimal? refundCents,
    String? reason,
  }) {
    return ReturnLineItem(
      originalItem: originalItem,
      returnQuantity: returnQuantity ?? this.returnQuantity,
      subtotalCents: subtotalCents ?? this.subtotalCents,
      discountCents: discountCents ?? this.discountCents,
      taxCents: taxCents ?? this.taxCents,
      refundCents: refundCents ?? this.refundCents,
      reason: reason ?? this.reason,
    );
  }

  @override
  List<Object?> get props => [
        originalItem, returnQuantity,
        subtotalCents, discountCents, taxCents, refundCents, reason,
      ];
}

/// ERP Golden Rule: Proportional reversal of original transaction.
/// ReturnRatio = returnQty / originalQty
/// Each component is reversed proportionally using integer math.
ReturnLineItem _computeProportionalReturn(
    PurchaseItemEntity original, int returnQty) {
  final origQty = original.quantity;
  if (origQty <= 0) {
    return ReturnLineItem(
      originalItem: original,
      returnQuantity: returnQty,
      subtotalCents: Decimal.zero,
      discountCents: Decimal.zero,
      taxCents: Decimal.zero,
      refundCents: Decimal.zero,
    );
  }
  final subtotalInt = (original.subtotalCents.toBigInt().toInt() * returnQty) ~/ origQty;
  final discountInt = (original.discountCents.toBigInt().toInt() * returnQty) ~/ origQty;
  final taxInt = (original.taxCents.toBigInt().toInt() * returnQty) ~/ origQty;
  // refund = subtotal - discount + tax  (net value + tax)
  final refundInt = subtotalInt - discountInt + taxInt;
  return ReturnLineItem(
    originalItem: original,
    returnQuantity: returnQty,
    subtotalCents: Decimal.fromInt(subtotalInt),
    discountCents: Decimal.fromInt(discountInt),
    taxCents: Decimal.fromInt(taxInt),
    refundCents: Decimal.fromInt(refundInt),
  );
}

class PurchaseReturnFormState extends Equatable {
  final int? purchaseId;
  final PurchaseEntity? purchase;
  final List<PurchaseItemEntity> availableItems;
  final List<ReturnLineItem> returnItems;
  /// Map of purchaseItemId -> quantity already returned in previous returns
  final Map<int, int> alreadyReturnedQty;
  final String? reason;
  /// restock, write_off, repair, replace, refund
  final String dispositionType;
  /// cash, credit, cheque
  final String refundMethod;
  final int currencyId;
  final bool isLoading;
  final bool isSubmitting;
  final String? error;
  final bool isSuccess;
  final bool hasUnsavedChanges;

  const PurchaseReturnFormState({
    this.purchaseId,
    this.purchase,
    this.availableItems = const [],
    this.returnItems = const [],
    this.alreadyReturnedQty = const {},
    this.reason,
    this.dispositionType = 'restock',
    this.refundMethod = 'credit',
    this.currencyId = 1,
    this.isLoading = false,
    this.isSubmitting = false,
    this.error,
    this.isSuccess = false,
    this.hasUnsavedChanges = false,
  });

  /// Max returnable quantity for a given purchase item
  int maxReturnableQty(int purchaseItemId, int originalQty) {
    final alreadyReturned = alreadyReturnedQty[purchaseItemId] ?? 0;
    final remaining = originalQty - alreadyReturned;
    return remaining < 0 ? 0 : remaining;
  }

  Decimal get totalRefundCents => returnItems.fold(
        Decimal.zero,
        (sum, item) => sum + item.refundCents,
      );

  Decimal get totalSubtotalCents => returnItems.fold(
        Decimal.zero,
        (sum, item) => sum + item.subtotalCents,
      );

  Decimal get totalDiscountCents => returnItems.fold(
        Decimal.zero,
        (sum, item) => sum + item.discountCents,
      );

  Decimal get totalTaxCents => returnItems.fold(
        Decimal.zero,
        (sum, item) => sum + item.taxCents,
      );

  int get totalReturnQuantity =>
      returnItems.fold(0, (sum, item) => sum + item.returnQuantity);

  PurchaseReturnFormState copyWith({
    int? purchaseId,
    PurchaseEntity? purchase,
    List<PurchaseItemEntity>? availableItems,
    List<ReturnLineItem>? returnItems,
    Map<int, int>? alreadyReturnedQty,
    String? reason,
    String? dispositionType,
    String? refundMethod,
    int? currencyId,
    bool? isLoading,
    bool? isSubmitting,
    String? error,
    bool? isSuccess,
    bool? hasUnsavedChanges,
  }) {
    return PurchaseReturnFormState(
      purchaseId: purchaseId ?? this.purchaseId,
      purchase: purchase ?? this.purchase,
      availableItems: availableItems ?? this.availableItems,
      returnItems: returnItems ?? this.returnItems,
      alreadyReturnedQty: alreadyReturnedQty ?? this.alreadyReturnedQty,
      reason: reason ?? this.reason,
      dispositionType: dispositionType ?? this.dispositionType,
      refundMethod: refundMethod ?? this.refundMethod,
      currencyId: currencyId ?? this.currencyId,
      isLoading: isLoading ?? this.isLoading,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      error: error,
      isSuccess: isSuccess ?? this.isSuccess,
      hasUnsavedChanges: hasUnsavedChanges ?? this.hasUnsavedChanges,
    );
  }

  @override
  List<Object?> get props => [
        purchaseId, purchase, availableItems, returnItems,
        alreadyReturnedQty, reason, dispositionType, refundMethod, currencyId,
        isLoading, isSubmitting, error, isSuccess, hasUnsavedChanges,
      ];
}

// ==================== EVENTS ====================

abstract class PurchaseReturnFormEvent extends Equatable {
  const PurchaseReturnFormEvent();

  @override
  List<Object?> get props => [];
}

class PurchaseReturnFormInitialized extends PurchaseReturnFormEvent {
  final int purchaseId;
  const PurchaseReturnFormInitialized(this.purchaseId);

  @override
  List<Object?> get props => [purchaseId];
}

class ReturnItemToggled extends PurchaseReturnFormEvent {
  final PurchaseItemEntity item;
  const ReturnItemToggled(this.item);

  @override
  List<Object?> get props => [item];
}

class ReturnItemQuantityChanged extends PurchaseReturnFormEvent {
  final int purchaseItemId;
  final int quantity;
  const ReturnItemQuantityChanged(this.purchaseItemId, this.quantity);

  @override
  List<Object?> get props => [purchaseItemId, quantity];
}

class ReturnItemReasonChanged extends PurchaseReturnFormEvent {
  final int purchaseItemId;
  final String reason;
  const ReturnItemReasonChanged(this.purchaseItemId, this.reason);

  @override
  List<Object?> get props => [purchaseItemId, reason];
}

class ReturnReasonChanged extends PurchaseReturnFormEvent {
  final String reason;
  const ReturnReasonChanged(this.reason);

  @override
  List<Object?> get props => [reason];
}

class ReturnDispositionChanged extends PurchaseReturnFormEvent {
  final String dispositionType;
  const ReturnDispositionChanged(this.dispositionType);

  @override
  List<Object?> get props => [dispositionType];
}

class ReturnRefundMethodChanged extends PurchaseReturnFormEvent {
  final String refundMethod;
  const ReturnRefundMethodChanged(this.refundMethod);

  @override
  List<Object?> get props => [refundMethod];
}

class PurchaseReturnFormSubmitted extends PurchaseReturnFormEvent {
  const PurchaseReturnFormSubmitted();
}

// ==================== BLOC ====================

class PurchaseReturnFormBloc
    extends Bloc<PurchaseReturnFormEvent, PurchaseReturnFormState> {
  final PurchaseRepository _repository;

  PurchaseReturnFormBloc(this._repository)
      : super(const PurchaseReturnFormState()) {
    on<PurchaseReturnFormInitialized>(_onInitialized);
    on<ReturnItemToggled>(_onItemToggled);
    on<ReturnItemQuantityChanged>(_onQuantityChanged);
    on<ReturnItemReasonChanged>(_onItemReasonChanged);
    on<ReturnReasonChanged>(_onReasonChanged);
    on<ReturnDispositionChanged>(_onDispositionChanged);
    on<ReturnRefundMethodChanged>(_onRefundMethodChanged);
    on<PurchaseReturnFormSubmitted>(_onSubmitted);
  }

  Future<void> _onInitialized(
    PurchaseReturnFormInitialized event,
    Emitter<PurchaseReturnFormState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, purchaseId: event.purchaseId));

    try {
      final purchase = await _repository.getPurchaseById(event.purchaseId);
      final items = await _repository.getPurchaseItems(event.purchaseId);

      // Load already-returned quantities for each item
      final returnedQtyMap = <int, int>{};
      for (final item in items) {
        final returnedQty = await _repository.getReturnedQuantity(item.id);
        if (returnedQty > 0) {
          returnedQtyMap[item.id] = returnedQty;
        }
      }

      // Filter out items that are fully returned
      final availableItems = items.where((item) {
        final returned = returnedQtyMap[item.id] ?? 0;
        return returned < item.quantity;
      }).toList();

      emit(state.copyWith(
        purchase: purchase,
        availableItems: availableItems,
        alreadyReturnedQty: returnedQtyMap,
        currencyId: purchase?.currencyId ?? 1,
        isLoading: false,
      ));
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: e.toString()));
    }
  }

  void _onItemToggled(
    ReturnItemToggled event,
    Emitter<PurchaseReturnFormState> emit,
  ) {
    final existing = state.returnItems
        .where((r) => r.originalItem.id == event.item.id)
        .toList();

    if (existing.isNotEmpty) {
      // Remove item
      final updated = state.returnItems
          .where((r) => r.originalItem.id != event.item.id)
          .toList();
      emit(state.copyWith(returnItems: updated, hasUnsavedChanges: true));
    } else {
      // Add item with max returnable quantity
      final maxQty = state.maxReturnableQty(event.item.id, event.item.quantity);
      if (maxQty <= 0) return; // Fully returned already
      final newItem = _computeProportionalReturn(event.item, maxQty);
      emit(state.copyWith(returnItems: [...state.returnItems, newItem], hasUnsavedChanges: true));
    }
  }

  void _onQuantityChanged(
    ReturnItemQuantityChanged event,
    Emitter<PurchaseReturnFormState> emit,
  ) {
    final updated = state.returnItems.map((item) {
      if (item.originalItem.id == event.purchaseItemId) {
        final maxQty = state.maxReturnableQty(item.originalItem.id, item.originalItem.quantity);
        final qty = event.quantity.clamp(1, maxQty);
        final computed = _computeProportionalReturn(item.originalItem, qty);
        return computed.copyWith(reason: item.reason);
      }
      return item;
    }).toList();
    emit(state.copyWith(returnItems: updated, hasUnsavedChanges: true));
  }

  void _onItemReasonChanged(
    ReturnItemReasonChanged event,
    Emitter<PurchaseReturnFormState> emit,
  ) {
    final updated = state.returnItems.map((item) {
      if (item.originalItem.id == event.purchaseItemId) {
        return item.copyWith(reason: event.reason);
      }
      return item;
    }).toList();
    emit(state.copyWith(returnItems: updated));
  }

  void _onReasonChanged(
    ReturnReasonChanged event,
    Emitter<PurchaseReturnFormState> emit,
  ) {
    emit(state.copyWith(reason: event.reason));
  }

  void _onDispositionChanged(
    ReturnDispositionChanged event,
    Emitter<PurchaseReturnFormState> emit,
  ) {
    emit(state.copyWith(dispositionType: event.dispositionType));
  }

  void _onRefundMethodChanged(
    ReturnRefundMethodChanged event,
    Emitter<PurchaseReturnFormState> emit,
  ) {
    emit(state.copyWith(refundMethod: event.refundMethod));
  }

  Future<void> _onSubmitted(
    PurchaseReturnFormSubmitted event,
    Emitter<PurchaseReturnFormState> emit,
  ) async {
    if (state.purchaseId == null) {
      emit(state.copyWith(error: 'No purchase selected'));
      return;
    }
    if (state.returnItems.isEmpty) {
      emit(state.copyWith(error: 'Please select at least one item to return'));
      return;
    }

    emit(state.copyWith(isSubmitting: true, error: null));

    try {
      final items = state.returnItems
          .map((item) => PurchaseReturnItemInput(
                purchaseItemId: item.originalItem.id,
                quantity: item.returnQuantity,
                subtotalCents: item.subtotalCents,
                discountCents: item.discountCents,
                taxCents: item.taxCents,
                refundCents: item.refundCents,
                reason: item.reason,
              ))
          .toList();

      await _repository.createPurchaseReturn(
        purchaseId: state.purchaseId!,
        currencyId: state.currencyId,
        subtotalCents: state.totalSubtotalCents,
        discountCents: state.totalDiscountCents,
        taxCents: state.totalTaxCents,
        totalCents: state.totalRefundCents,
        items: items,
        dispositionType: state.dispositionType,
        refundMethod: state.refundMethod,
        reason: state.reason,
        returnDate: DateTime.now(),
      );

      emit(state.copyWith(isSubmitting: false, isSuccess: true, hasUnsavedChanges: false));
    } catch (e) {
      emit(state.copyWith(isSubmitting: false, error: e.toString()));
    }
  }
}
