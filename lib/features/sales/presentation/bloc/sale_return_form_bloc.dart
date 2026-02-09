import 'package:decimal/decimal.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';

import '../../domain/entities/sale_entity.dart';
import '../../domain/repositories/sale_repository.dart';

// ==================== STATE ====================

class SaleReturnLineItem extends Equatable {
  final SaleItemEntity originalItem;
  final int returnQuantity;
  final Decimal refundCents;
  final String? reason;

  const SaleReturnLineItem({
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

  SaleReturnLineItem copyWith({
    int? returnQuantity,
    Decimal? refundCents,
    String? reason,
  }) {
    return SaleReturnLineItem(
      originalItem: originalItem,
      returnQuantity: returnQuantity ?? this.returnQuantity,
      refundCents: refundCents ?? this.refundCents,
      reason: reason ?? this.reason,
    );
  }

  @override
  List<Object?> get props => [originalItem, returnQuantity, refundCents, reason];
}

class SaleReturnFormState extends Equatable {
  final int? saleId;
  final SaleEntity? sale;
  final List<SaleItemEntity> availableItems;
  final List<SaleReturnLineItem> returnItems;
  final String? reason;
  final String dispositionType;
  final String refundMethod;
  final int currencyId;
  final bool isLoading;
  final bool isSubmitting;
  final String? error;
  final bool isSuccess;
  final Map<int, int> alreadyReturnedQty;

  const SaleReturnFormState({
    this.saleId,
    this.sale,
    this.availableItems = const [],
    this.returnItems = const [],
    this.reason,
    this.dispositionType = 'restock',
    this.refundMethod = 'cash',
    this.currencyId = 1,
    this.isLoading = false,
    this.isSubmitting = false,
    this.error,
    this.isSuccess = false,
    this.alreadyReturnedQty = const {},
  });

  bool get hasUnsavedChanges => returnItems.isNotEmpty;

  int maxReturnableQty(int itemId, int originalQty) {
    final alreadyReturned = alreadyReturnedQty[itemId] ?? 0;
    return (originalQty - alreadyReturned).clamp(0, originalQty);
  }

  Decimal get totalRefundCents => returnItems.fold(
        Decimal.zero,
        (sum, item) => sum + item.refundCents,
      );

  int get totalReturnQuantity =>
      returnItems.fold(0, (sum, item) => sum + item.returnQuantity);

  SaleReturnFormState copyWith({
    int? saleId,
    SaleEntity? sale,
    List<SaleItemEntity>? availableItems,
    List<SaleReturnLineItem>? returnItems,
    String? reason,
    String? dispositionType,
    String? refundMethod,
    int? currencyId,
    bool? isLoading,
    bool? isSubmitting,
    String? error,
    bool? isSuccess,
    Map<int, int>? alreadyReturnedQty,
  }) {
    return SaleReturnFormState(
      saleId: saleId ?? this.saleId,
      sale: sale ?? this.sale,
      availableItems: availableItems ?? this.availableItems,
      returnItems: returnItems ?? this.returnItems,
      reason: reason ?? this.reason,
      dispositionType: dispositionType ?? this.dispositionType,
      refundMethod: refundMethod ?? this.refundMethod,
      currencyId: currencyId ?? this.currencyId,
      isLoading: isLoading ?? this.isLoading,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      error: error,
      isSuccess: isSuccess ?? this.isSuccess,
      alreadyReturnedQty: alreadyReturnedQty ?? this.alreadyReturnedQty,
    );
  }

  @override
  List<Object?> get props => [
        saleId, sale, availableItems, returnItems,
        reason, dispositionType, refundMethod, currencyId,
        isLoading, isSubmitting, error, isSuccess, alreadyReturnedQty,
      ];
}

// ==================== EVENTS ====================

abstract class SaleReturnFormEvent extends Equatable {
  const SaleReturnFormEvent();

  @override
  List<Object?> get props => [];
}

class SaleReturnFormInitialized extends SaleReturnFormEvent {
  final int saleId;
  const SaleReturnFormInitialized(this.saleId);

  @override
  List<Object?> get props => [saleId];
}

class SaleReturnItemToggled extends SaleReturnFormEvent {
  final SaleItemEntity item;
  const SaleReturnItemToggled(this.item);

  @override
  List<Object?> get props => [item];
}

class SaleReturnItemQuantityChanged extends SaleReturnFormEvent {
  final int saleItemId;
  final int quantity;
  const SaleReturnItemQuantityChanged(this.saleItemId, this.quantity);

  @override
  List<Object?> get props => [saleItemId, quantity];
}

class SaleReturnItemReasonChanged extends SaleReturnFormEvent {
  final int saleItemId;
  final String reason;
  const SaleReturnItemReasonChanged(this.saleItemId, this.reason);

  @override
  List<Object?> get props => [saleItemId, reason];
}

class SaleReturnReasonChanged extends SaleReturnFormEvent {
  final String reason;
  const SaleReturnReasonChanged(this.reason);

  @override
  List<Object?> get props => [reason];
}

class SaleReturnDispositionChanged extends SaleReturnFormEvent {
  final String dispositionType;
  const SaleReturnDispositionChanged(this.dispositionType);

  @override
  List<Object?> get props => [dispositionType];
}

class SaleReturnRefundMethodChanged extends SaleReturnFormEvent {
  final String refundMethod;
  const SaleReturnRefundMethodChanged(this.refundMethod);

  @override
  List<Object?> get props => [refundMethod];
}

class SaleReturnFormSubmitted extends SaleReturnFormEvent {
  const SaleReturnFormSubmitted();
}

// ==================== BLOC ====================

class SaleReturnFormBloc
    extends Bloc<SaleReturnFormEvent, SaleReturnFormState> {
  final SaleRepository _repository;

  SaleReturnFormBloc(this._repository)
      : super(const SaleReturnFormState()) {
    on<SaleReturnFormInitialized>(_onInitialized);
    on<SaleReturnItemToggled>(_onItemToggled);
    on<SaleReturnItemQuantityChanged>(_onQuantityChanged);
    on<SaleReturnItemReasonChanged>(_onItemReasonChanged);
    on<SaleReturnReasonChanged>(_onReasonChanged);
    on<SaleReturnDispositionChanged>(_onDispositionChanged);
    on<SaleReturnRefundMethodChanged>(_onRefundMethodChanged);
    on<SaleReturnFormSubmitted>(_onSubmitted);
  }

  Future<void> _onInitialized(
    SaleReturnFormInitialized event,
    Emitter<SaleReturnFormState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, saleId: event.saleId));

    try {
      final sale = await _repository.getSaleById(event.saleId);
      final items = await _repository.getSaleItems(event.saleId);

      // Fetch already-returned quantities for each item
      final alreadyReturned = <int, int>{};
      for (final item in items) {
        final qty = await _repository.getReturnedQuantity(item.id);
        if (qty > 0) alreadyReturned[item.id] = qty;
      }

      emit(state.copyWith(
        sale: sale,
        availableItems: items,
        currencyId: sale?.currencyId ?? 1,
        isLoading: false,
        alreadyReturnedQty: alreadyReturned,
      ));
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: e.toString()));
    }
  }

  void _onItemToggled(
    SaleReturnItemToggled event,
    Emitter<SaleReturnFormState> emit,
  ) {
    final existing = state.returnItems
        .where((r) => r.originalItem.id == event.item.id)
        .toList();

    if (existing.isNotEmpty) {
      final updated = state.returnItems
          .where((r) => r.originalItem.id != event.item.id)
          .toList();
      emit(state.copyWith(returnItems: updated));
    } else {
      final maxQty = state.maxReturnableQty(event.item.id, event.item.quantity);
      if (maxQty <= 0) return; // fully returned already
      final origQty = event.item.quantity;
      final totalInt = event.item.totalCents.toBigInt().toInt();
      final refundInt = origQty > 0 ? (totalInt * maxQty) ~/ origQty : 0;
      final newItem = SaleReturnLineItem(
        originalItem: event.item,
        returnQuantity: maxQty,
        refundCents: Decimal.fromInt(refundInt),
      );
      emit(state.copyWith(returnItems: [...state.returnItems, newItem]));
    }
  }

  void _onQuantityChanged(
    SaleReturnItemQuantityChanged event,
    Emitter<SaleReturnFormState> emit,
  ) {
    final updated = state.returnItems.map((item) {
      if (item.originalItem.id == event.saleItemId) {
        final maxQty = state.maxReturnableQty(item.originalItem.id, item.originalItem.quantity);
        final qty = event.quantity.clamp(1, maxQty > 0 ? maxQty : 1);
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
    SaleReturnItemReasonChanged event,
    Emitter<SaleReturnFormState> emit,
  ) {
    final updated = state.returnItems.map((item) {
      if (item.originalItem.id == event.saleItemId) {
        return item.copyWith(reason: event.reason);
      }
      return item;
    }).toList();
    emit(state.copyWith(returnItems: updated));
  }

  void _onReasonChanged(
    SaleReturnReasonChanged event,
    Emitter<SaleReturnFormState> emit,
  ) {
    emit(state.copyWith(reason: event.reason));
  }

  void _onDispositionChanged(
    SaleReturnDispositionChanged event,
    Emitter<SaleReturnFormState> emit,
  ) {
    emit(state.copyWith(dispositionType: event.dispositionType));
  }

  void _onRefundMethodChanged(
    SaleReturnRefundMethodChanged event,
    Emitter<SaleReturnFormState> emit,
  ) {
    emit(state.copyWith(refundMethod: event.refundMethod));
  }

  Future<void> _onSubmitted(
    SaleReturnFormSubmitted event,
    Emitter<SaleReturnFormState> emit,
  ) async {
    if (state.saleId == null) {
      emit(state.copyWith(error: 'No sale selected'));
      return;
    }
    if (state.returnItems.isEmpty) {
      emit(state.copyWith(error: 'Please select at least one item to return'));
      return;
    }

    emit(state.copyWith(isSubmitting: true, error: null));

    try {
      final items = state.returnItems
          .map((item) => SaleReturnItemInput(
                saleItemId: item.originalItem.id,
                quantity: item.returnQuantity,
                refundCents: item.refundCents,
                reason: item.reason,
              ))
          .toList();

      await _repository.createSaleReturn(
        saleId: state.saleId!,
        currencyId: state.currencyId,
        totalCents: state.totalRefundCents,
        items: items,
        reason: state.reason,
        dispositionType: state.dispositionType,
        refundMethod: state.refundMethod,
        returnDate: DateTime.now(),
      );

      emit(state.copyWith(isSubmitting: false, isSuccess: true));
    } catch (e) {
      emit(state.copyWith(isSubmitting: false, error: e.toString()));
    }
  }
}
