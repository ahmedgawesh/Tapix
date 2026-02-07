import 'package:decimal/decimal.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';

import '../../domain/entities/purchase_entity.dart';
import '../../domain/repositories/purchase_repository.dart';

// ==================== STATE ====================

class ReturnLineItem extends Equatable {
  final PurchaseItemEntity originalItem;
  final int returnQuantity;
  final Decimal refundCents;
  final String? reason;

  const ReturnLineItem({
    required this.originalItem,
    required this.returnQuantity,
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
    Decimal? refundCents,
    String? reason,
  }) {
    return ReturnLineItem(
      originalItem: originalItem,
      returnQuantity: returnQuantity ?? this.returnQuantity,
      refundCents: refundCents ?? this.refundCents,
      reason: reason ?? this.reason,
    );
  }

  @override
  List<Object?> get props => [originalItem, returnQuantity, refundCents, reason];
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
  final int currencyId;
  final bool isLoading;
  final bool isSubmitting;
  final String? error;
  final bool isSuccess;

  const PurchaseReturnFormState({
    this.purchaseId,
    this.purchase,
    this.availableItems = const [],
    this.returnItems = const [],
    this.alreadyReturnedQty = const {},
    this.reason,
    this.dispositionType = 'restock',
    this.currencyId = 1,
    this.isLoading = false,
    this.isSubmitting = false,
    this.error,
    this.isSuccess = false,
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
    int? currencyId,
    bool? isLoading,
    bool? isSubmitting,
    String? error,
    bool? isSuccess,
  }) {
    return PurchaseReturnFormState(
      purchaseId: purchaseId ?? this.purchaseId,
      purchase: purchase ?? this.purchase,
      availableItems: availableItems ?? this.availableItems,
      returnItems: returnItems ?? this.returnItems,
      alreadyReturnedQty: alreadyReturnedQty ?? this.alreadyReturnedQty,
      reason: reason ?? this.reason,
      dispositionType: dispositionType ?? this.dispositionType,
      currencyId: currencyId ?? this.currencyId,
      isLoading: isLoading ?? this.isLoading,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      error: error,
      isSuccess: isSuccess ?? this.isSuccess,
    );
  }

  @override
  List<Object?> get props => [
        purchaseId, purchase, availableItems, returnItems,
        alreadyReturnedQty, reason, dispositionType, currencyId,
        isLoading, isSubmitting, error, isSuccess,
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
      emit(state.copyWith(returnItems: updated));
    } else {
      // Add item with max returnable quantity
      final maxQty = state.maxReturnableQty(event.item.id, event.item.quantity);
      if (maxQty <= 0) return; // Fully returned already
      final origQty = event.item.quantity;
      final totalInt = event.item.totalCents.toBigInt().toInt();
      final refundInt = origQty > 0 ? (totalInt * maxQty) ~/ origQty : 0;
      final newItem = ReturnLineItem(
        originalItem: event.item,
        returnQuantity: maxQty,
        refundCents: Decimal.fromInt(refundInt),
      );
      emit(state.copyWith(returnItems: [...state.returnItems, newItem]));
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
        // Proportional refund: (totalCents * returnQty) / originalQty
        // Use integer math to avoid Decimal division returning Object
        final origQty = item.originalItem.quantity;
        final totalInt = item.originalItem.totalCents.toBigInt().toInt();
        final refundInt = origQty > 0 ? (totalInt * qty) ~/ origQty : 0;
        return item.copyWith(
          returnQuantity: qty,
          refundCents: Decimal.fromInt(refundInt),
        );
      }
      return item;
    }).toList();
    emit(state.copyWith(returnItems: updated));
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
                refundCents: item.refundCents,
                reason: item.reason,
              ))
          .toList();

      await _repository.createPurchaseReturn(
        purchaseId: state.purchaseId!,
        currencyId: state.currencyId,
        totalCents: state.totalRefundCents,
        items: items,
        dispositionType: state.dispositionType,
        reason: state.reason,
        returnDate: DateTime.now(),
      );

      emit(state.copyWith(isSubmitting: false, isSuccess: true));
    } catch (e) {
      emit(state.copyWith(isSubmitting: false, error: e.toString()));
    }
  }
}
