import 'package:decimal/decimal.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/services/return_calculation_service.dart';
import '../../domain/entities/sale_entity.dart';
import '../../domain/repositories/sale_repository.dart';

// ==================== STATE ====================

class SaleReturnLineItem extends Equatable {
  final SaleItemEntity originalItem;
  final int returnQuantity;
  final Decimal subtotalCents;
  final Decimal discountCents;
  final Decimal taxCents;
  final Decimal refundCents;
  final String? reason;

  const SaleReturnLineItem({
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

  SaleReturnLineItem copyWith({
    int? returnQuantity,
    Decimal? subtotalCents,
    Decimal? discountCents,
    Decimal? taxCents,
    Decimal? refundCents,
    String? reason,
  }) {
    return SaleReturnLineItem(
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
    originalItem,
    returnQuantity,
    subtotalCents,
    discountCents,
    taxCents,
    refundCents,
    reason,
  ];
}

/// ERP Golden Rule: Proportional reversal of original sale transaction.
/// Delegates to [ReturnCalculationService.computeProportionalReturn].
SaleReturnLineItem _computeProportionalSaleReturn(
  SaleItemEntity original,
  int returnQty, {
  LinkedReturnHistory previousLinkedHistory = LinkedReturnHistory.zero,
  bool taxInclusivePricing = false,
}) {
  final result = ReturnCalculationService.computeProportionalReturn(
    originalQuantity: original.quantity,
    returnQuantity: returnQty,
    originalSubtotalCents: original.subtotalCents.toBigInt().toInt(),
    originalDiscountCents: original.discountCents.toBigInt().toInt(),
    originalTaxCents: original.taxCents.toBigInt().toInt(),
    previousLinkedHistory: previousLinkedHistory,
    taxInclusivePricing: taxInclusivePricing,
  );
  return SaleReturnLineItem(
    originalItem: original,
    returnQuantity: returnQty,
    subtotalCents: Decimal.fromInt(result.subtotalCents),
    discountCents: Decimal.fromInt(result.discountCents),
    taxCents: Decimal.fromInt(result.taxCents),
    refundCents: Decimal.fromInt(result.refundCents),
  );
}

class SaleReturnFormState extends Equatable {
  final int? saleId;
  final SaleEntity? sale;
  final List<SaleItemEntity> availableItems;
  final List<SaleReturnLineItem> returnItems;
  final String? reason;
  final String dispositionType;
  final String refundMethod;

  /// Phase 14.0 — cheque due date. Required by `_onSubmitted` when
  /// [refundMethod] == 'cheque'. Ignored (persisted as NULL) otherwise.
  final DateTime? dueDate;
  final int currencyId;
  final bool isLoading;
  final bool isSubmitting;
  final String? error;
  final bool isSuccess;
  final Map<int, int> alreadyReturnedQty;
  final Map<int, LinkedReturnHistory> linkedReturnHistory;

  SaleReturnFormState({
    this.saleId,
    this.sale,
    this.availableItems = const [],
    this.returnItems = const [],
    this.reason,
    this.dispositionType = 'restock',
    this.refundMethod = 'cash',
    this.dueDate,
    this.currencyId = 1,
    this.isLoading = false,
    this.isSubmitting = false,
    this.error,
    this.isSuccess = false,
    this.alreadyReturnedQty = const {},
    this.linkedReturnHistory = const {},
  });

  /// True when refund-method = cheque but the operator has not yet picked
  /// a due date. The form's confirm button reads this directly.
  bool get isChequeMissingDueDate =>
      refundMethod == 'cheque' && dueDate == null;

  bool get hasUnsavedChanges => returnItems.isNotEmpty;

  int maxReturnableQty(int itemId, int originalQty) {
    final alreadyReturned = alreadyReturnedQty[itemId] ?? 0;
    return (originalQty - alreadyReturned).clamp(0, originalQty);
  }

  // ── Rollup layer (single source of truth) ──────────────────────────────
  //
  // Phase-5 of the scattered-calculation migration (see
  // `docs/adr/0001-pricing-engines-as-sot.md`) collapses the four parallel
  // `fold(Decimal.zero, +)` loops into a single call to
  // `ReturnCalculationService.aggregate`. Memoized once per immutable
  // state instance; every `total*Cents` / `totalReturnQuantity` getter
  // reads from the same rollup so they can never disagree.
  late final ReturnRollup _rollup = ReturnCalculationService.aggregate(
    returnItems.map(
      (i) => (
        subtotalCents: i.subtotalCents.toBigInt().toInt(),
        discountCents: i.discountCents.toBigInt().toInt(),
        taxCents: i.taxCents.toBigInt().toInt(),
        refundCents: i.refundCents.toBigInt().toInt(),
        quantity: i.returnQuantity,
      ),
    ),
  );

  Decimal get totalRefundCents => Decimal.fromInt(_rollup.refundCents);

  Decimal get totalSubtotalCents => Decimal.fromInt(_rollup.subtotalCents);

  Decimal get totalDiscountCents => Decimal.fromInt(_rollup.discountCents);

  Decimal get totalTaxCents => Decimal.fromInt(_rollup.taxCents);

  int get totalReturnQuantity => _rollup.totalQuantity;

  SaleReturnFormState copyWith({
    int? saleId,
    SaleEntity? sale,
    List<SaleItemEntity>? availableItems,
    List<SaleReturnLineItem>? returnItems,
    String? reason,
    String? dispositionType,
    String? refundMethod,
    Object? dueDate = _sentinel,
    int? currencyId,
    bool? isLoading,
    bool? isSubmitting,
    String? error,
    bool? isSuccess,
    Map<int, int>? alreadyReturnedQty,
    Map<int, LinkedReturnHistory>? linkedReturnHistory,
  }) {
    return SaleReturnFormState(
      saleId: saleId ?? this.saleId,
      sale: sale ?? this.sale,
      availableItems: availableItems ?? this.availableItems,
      returnItems: returnItems ?? this.returnItems,
      reason: reason ?? this.reason,
      dispositionType: dispositionType ?? this.dispositionType,
      refundMethod: refundMethod ?? this.refundMethod,
      dueDate: identical(dueDate, _sentinel)
          ? this.dueDate
          : dueDate as DateTime?,
      currencyId: currencyId ?? this.currencyId,
      isLoading: isLoading ?? this.isLoading,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      error: error,
      isSuccess: isSuccess ?? this.isSuccess,
      alreadyReturnedQty: alreadyReturnedQty ?? this.alreadyReturnedQty,
      linkedReturnHistory: linkedReturnHistory ?? this.linkedReturnHistory,
    );
  }

  @override
  List<Object?> get props => [
    saleId,
    sale,
    availableItems,
    returnItems,
    reason,
    dispositionType,
    refundMethod,
    dueDate,
    currencyId,
    isLoading,
    isSubmitting,
    error,
    isSuccess,
    alreadyReturnedQty,
    linkedReturnHistory,
  ];
}

/// Sentinel for `copyWith` to distinguish "don't touch" from "set to null".
const Object _sentinel = Object();

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

/// Phase 14.0 — cheque due date selection.
class SaleReturnDueDateChanged extends SaleReturnFormEvent {
  final DateTime? dueDate;
  const SaleReturnDueDateChanged(this.dueDate);

  @override
  List<Object?> get props => [dueDate];
}

class SaleReturnFormSubmitted extends SaleReturnFormEvent {
  const SaleReturnFormSubmitted();
}

// ==================== BLOC ====================

class SaleReturnFormBloc
    extends Bloc<SaleReturnFormEvent, SaleReturnFormState> {
  final SaleRepository _repository;

  SaleReturnFormBloc(this._repository) : super(SaleReturnFormState()) {
    on<SaleReturnFormInitialized>(_onInitialized);
    on<SaleReturnItemToggled>(_onItemToggled);
    on<SaleReturnItemQuantityChanged>(_onQuantityChanged);
    on<SaleReturnItemReasonChanged>(_onItemReasonChanged);
    on<SaleReturnReasonChanged>(_onReasonChanged);
    on<SaleReturnDispositionChanged>(_onDispositionChanged);
    on<SaleReturnRefundMethodChanged>(_onRefundMethodChanged);
    on<SaleReturnDueDateChanged>(_onDueDateChanged);
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
      final linkedHistory = <int, LinkedReturnHistory>{};
      for (final item in items) {
        final qty = await _repository.getReturnedQuantity(item.id);
        if (qty > 0) alreadyReturned[item.id] = qty;
        final history = await _repository.getLinkedReturnHistory(item.id);
        if (history.quantity > 0) linkedHistory[item.id] = history;
      }

      // Filter out items that are fully returned
      final availableItems = items.where((item) {
        final returned = alreadyReturned[item.id] ?? 0;
        return returned < item.quantity;
      }).toList();

      emit(
        state.copyWith(
          sale: sale,
          availableItems: availableItems,
          currencyId: sale?.currencyId ?? 1,
          isLoading: false,
          alreadyReturnedQty: alreadyReturned,
          linkedReturnHistory: linkedHistory,
        ),
      );
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
      final newItem = _computeProportionalSaleReturn(
        event.item,
        maxQty,
        previousLinkedHistory:
            state.linkedReturnHistory[event.item.id] ??
            LinkedReturnHistory.zero,
        taxInclusivePricing: state.sale?.taxInclusiveAtPost ?? false,
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
        final maxQty = state.maxReturnableQty(
          item.originalItem.id,
          item.originalItem.quantity,
        );
        final qty = event.quantity.clamp(1, maxQty > 0 ? maxQty : 1);
        final computed = _computeProportionalSaleReturn(
          item.originalItem,
          qty,
          previousLinkedHistory:
              state.linkedReturnHistory[item.originalItem.id] ??
              LinkedReturnHistory.zero,
          taxInclusivePricing: state.sale?.taxInclusiveAtPost ?? false,
        );
        return computed.copyWith(reason: item.reason);
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
    // When switching away from cheque, clear the due date so a stale
    // value cannot be persisted.
    final clearDueDate = event.refundMethod != 'cheque';
    emit(
      state.copyWith(
        refundMethod: event.refundMethod,
        dueDate: clearDueDate ? null : state.dueDate,
      ),
    );
  }

  void _onDueDateChanged(
    SaleReturnDueDateChanged event,
    Emitter<SaleReturnFormState> emit,
  ) {
    emit(state.copyWith(dueDate: event.dueDate));
  }

  Future<void> _onSubmitted(
    SaleReturnFormSubmitted event,
    Emitter<SaleReturnFormState> emit,
  ) async {
    if (state.isSuccess) return; // Prevent double-submission
    if (state.saleId == null) {
      emit(state.copyWith(error: 'No sale selected'));
      return;
    }
    if (state.returnItems.isEmpty) {
      emit(state.copyWith(error: 'Please select at least one item to return'));
      return;
    }
    // Phase 14.0 — cheque must always carry a due date so it surfaces
    // on the dashboard reminder. Caught here defensively even though
    // the UI also disables the confirm button.
    if (state.isChequeMissingDueDate) {
      emit(
        state.copyWith(
          error: 'Please select a due date for the cheque refund.',
        ),
      );
      return;
    }

    emit(state.copyWith(isSubmitting: true, error: null));

    try {
      final items = state.returnItems
          .map(
            (item) => SaleReturnItemInput(
              saleItemId: item.originalItem.id,
              quantity: item.returnQuantity,
              quantityScale: item.originalItem.quantityScale,
              measurementType: item.originalItem.measurementType,
              subtotalCents: item.subtotalCents,
              discountCents: item.discountCents,
              taxCents: item.taxCents,
              refundCents: item.refundCents,
              reason: item.reason,
            ),
          )
          .toList();

      // Idempotency token: caught by UNIQUE on sale_returns.idempotency_key
      // so a duplicate insert (double-tap, retried call) cannot reach
      // post / JE / commission / loyalty side effects.
      final idempotencyKey = const Uuid().v4();

      await _repository.createSaleReturn(
        saleId: state.saleId!,
        currencyId: state.currencyId,
        subtotalCents: state.totalSubtotalCents,
        discountCents: state.totalDiscountCents,
        taxCents: state.totalTaxCents,
        totalCents: state.totalRefundCents,
        items: items,
        reason: state.reason,
        dispositionType: state.dispositionType,
        refundMethod: state.refundMethod,
        returnDate: DateTime.now(),
        dueDate: state.dueDate,
        idempotencyKey: idempotencyKey,
        taxInclusiveAtPost: state.sale?.taxInclusiveAtPost ?? false,
      );

      emit(state.copyWith(isSubmitting: false, isSuccess: true));
    } catch (e) {
      emit(state.copyWith(isSubmitting: false, error: e.toString()));
    }
  }
}
