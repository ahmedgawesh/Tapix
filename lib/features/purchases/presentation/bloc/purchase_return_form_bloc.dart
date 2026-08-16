import 'package:decimal/decimal.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/services/return_calculation_service.dart';
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
    originalItem,
    returnQuantity,
    subtotalCents,
    discountCents,
    taxCents,
    refundCents,
    reason,
  ];
}

/// ERP Golden Rule: Proportional reversal of original transaction.
/// Delegates to [ReturnCalculationService.computeProportionalReturn].
ReturnLineItem _computeProportionalReturn(
  PurchaseItemEntity original,
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
  return ReturnLineItem(
    originalItem: original,
    returnQuantity: returnQty,
    subtotalCents: Decimal.fromInt(result.subtotalCents),
    discountCents: Decimal.fromInt(result.discountCents),
    taxCents: Decimal.fromInt(result.taxCents),
    refundCents: Decimal.fromInt(result.refundCents),
  );
}

class PurchaseReturnFormState extends Equatable {
  final int? purchaseId;
  final PurchaseEntity? purchase;
  final List<PurchaseItemEntity> availableItems;
  final List<ReturnLineItem> returnItems;

  /// Map of purchaseItemId -> quantity already returned in previous returns
  final Map<int, int> alreadyReturnedQty;
  final Map<int, LinkedReturnHistory> linkedReturnHistory;
  final String? reason;

  /// restock, write_off, repair, replace, refund
  final String dispositionType;

  /// cash, credit, cheque
  final String refundMethod;

  /// Phase 14.0 — cheque due date. Required by `_onSubmitted` when
  /// [refundMethod] == 'cheque'. Ignored (persisted as NULL) otherwise.
  final DateTime? dueDate;
  final int currencyId;
  final bool isLoading;
  final bool isSubmitting;
  final String? error;
  final bool isSuccess;
  final bool hasUnsavedChanges;

  PurchaseReturnFormState({
    this.purchaseId,
    this.purchase,
    this.availableItems = const [],
    this.returnItems = const [],
    this.alreadyReturnedQty = const {},
    this.linkedReturnHistory = const {},
    this.reason,
    this.dispositionType = 'restock',
    this.refundMethod = 'credit',
    this.dueDate,
    this.currencyId = 1,
    this.isLoading = false,
    this.isSubmitting = false,
    this.error,
    this.isSuccess = false,
    this.hasUnsavedChanges = false,
  });

  /// Maximum allowed by BOTH:
  ///   1. invoice entitlement (purchased − linked/adjustment returns), and
  ///   2. current physical stock for the same product/variant.
  ///
  /// An unlinked purchase return can legitimately be FIFO-attributed to an
  /// older invoice, leaving this invoice's entitlement unchanged while total
  /// on-hand stock is lower. Showing entitlement alone lets the user select an
  /// impossible quantity that the DAO only rejects at posting time.
  int maxReturnableQty(PurchaseItemEntity item) {
    final alreadyReturned = alreadyReturnedQty[item.id] ?? 0;
    final invoiceRemaining = item.quantity - alreadyReturned;
    if (invoiceRemaining <= 0) return 0;
    if (!item.tracksInventory || item.currentStockQuantity == null) {
      return invoiceRemaining;
    }

    final reservedByOtherLines = returnItems
        .where(
          (line) =>
              line.originalItem.id != item.id &&
              line.originalItem.productId == item.productId &&
              line.originalItem.variantId == item.variantId,
        )
        .fold<int>(0, (sum, line) => sum + line.returnQuantity);
    final physicalRemaining = item.currentStockQuantity! - reservedByOtherLines;
    if (physicalRemaining <= 0) return 0;
    return invoiceRemaining < physicalRemaining
        ? invoiceRemaining
        : physicalRemaining;
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

  /// Phase 14.0 — same gate as the sale-side bloc.
  bool get isChequeMissingDueDate =>
      refundMethod == 'cheque' && dueDate == null;

  PurchaseReturnFormState copyWith({
    int? purchaseId,
    PurchaseEntity? purchase,
    List<PurchaseItemEntity>? availableItems,
    List<ReturnLineItem>? returnItems,
    Map<int, int>? alreadyReturnedQty,
    Map<int, LinkedReturnHistory>? linkedReturnHistory,
    String? reason,
    String? dispositionType,
    String? refundMethod,
    Object? dueDate = _sentinel,
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
      linkedReturnHistory: linkedReturnHistory ?? this.linkedReturnHistory,
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
      hasUnsavedChanges: hasUnsavedChanges ?? this.hasUnsavedChanges,
    );
  }

  @override
  List<Object?> get props => [
    purchaseId,
    purchase,
    availableItems,
    returnItems,
    alreadyReturnedQty,
    linkedReturnHistory,
    reason,
    dispositionType,
    refundMethod,
    dueDate,
    currencyId,
    isLoading,
    isSubmitting,
    error,
    isSuccess,
    hasUnsavedChanges,
  ];
}

/// Sentinel for `copyWith` to distinguish "don't touch" from "set to null".
const Object _sentinel = Object();

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

/// Phase 14.0 — cheque due date selection.
class PurchaseReturnDueDateChanged extends PurchaseReturnFormEvent {
  final DateTime? dueDate;
  const PurchaseReturnDueDateChanged(this.dueDate);

  @override
  List<Object?> get props => [dueDate];
}

class PurchaseReturnFormSubmitted extends PurchaseReturnFormEvent {
  /// Carries the current inventory policy from the UI layer so the bloc
  /// doesn't need a direct dependency on the app settings bloc.
  final bool allowNegativeStock;
  const PurchaseReturnFormSubmitted({this.allowNegativeStock = false});

  @override
  List<Object?> get props => [allowNegativeStock];
}

// ==================== BLOC ====================

class PurchaseReturnFormBloc
    extends Bloc<PurchaseReturnFormEvent, PurchaseReturnFormState> {
  final PurchaseRepository _repository;

  PurchaseReturnFormBloc(this._repository) : super(PurchaseReturnFormState()) {
    on<PurchaseReturnFormInitialized>(_onInitialized);
    on<ReturnItemToggled>(_onItemToggled);
    on<ReturnItemQuantityChanged>(_onQuantityChanged);
    on<ReturnItemReasonChanged>(_onItemReasonChanged);
    on<ReturnReasonChanged>(_onReasonChanged);
    on<ReturnDispositionChanged>(_onDispositionChanged);
    on<ReturnRefundMethodChanged>(_onRefundMethodChanged);
    on<PurchaseReturnDueDateChanged>(_onDueDateChanged);
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
      final linkedHistory = <int, LinkedReturnHistory>{};
      for (final item in items) {
        final returnedQty = await _repository.getReturnedQuantity(item.id);
        if (returnedQty > 0) {
          returnedQtyMap[item.id] = returnedQty;
        }
        final history = await _repository.getLinkedReturnHistory(item.id);
        if (history.quantity > 0) linkedHistory[item.id] = history;
      }

      // Filter out items that are fully returned
      final availableItems = items.where((item) {
        final returned = returnedQtyMap[item.id] ?? 0;
        return returned < item.quantity;
      }).toList();

      emit(
        state.copyWith(
          purchase: purchase,
          availableItems: availableItems,
          alreadyReturnedQty: returnedQtyMap,
          linkedReturnHistory: linkedHistory,
          currencyId: purchase?.currencyId ?? 1,
          isLoading: false,
        ),
      );
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
      final maxQty = state.maxReturnableQty(event.item);
      if (maxQty <= 0) return; // Fully returned already
      final newItem = _computeProportionalReturn(
        event.item,
        maxQty,
        previousLinkedHistory:
            state.linkedReturnHistory[event.item.id] ??
            LinkedReturnHistory.zero,
        taxInclusivePricing: state.purchase?.taxInclusiveAtPost ?? false,
      );
      emit(
        state.copyWith(
          returnItems: [...state.returnItems, newItem],
          hasUnsavedChanges: true,
        ),
      );
    }
  }

  void _onQuantityChanged(
    ReturnItemQuantityChanged event,
    Emitter<PurchaseReturnFormState> emit,
  ) {
    final updated = state.returnItems.map((item) {
      if (item.originalItem.id == event.purchaseItemId) {
        final maxQty = state.maxReturnableQty(item.originalItem);
        final qty = event.quantity.clamp(1, maxQty);
        final computed = _computeProportionalReturn(
          item.originalItem,
          qty,
          previousLinkedHistory:
              state.linkedReturnHistory[item.originalItem.id] ??
              LinkedReturnHistory.zero,
          taxInclusivePricing: state.purchase?.taxInclusiveAtPost ?? false,
        );
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
    final clearDueDate = event.refundMethod != 'cheque';
    emit(
      state.copyWith(
        refundMethod: event.refundMethod,
        dueDate: clearDueDate ? null : state.dueDate,
      ),
    );
  }

  void _onDueDateChanged(
    PurchaseReturnDueDateChanged event,
    Emitter<PurchaseReturnFormState> emit,
  ) {
    emit(state.copyWith(dueDate: event.dueDate));
  }

  Future<void> _onSubmitted(
    PurchaseReturnFormSubmitted event,
    Emitter<PurchaseReturnFormState> emit,
  ) async {
    if (state.isSuccess) return; // Prevent double-submission
    if (state.purchaseId == null) {
      emit(state.copyWith(error: 'No purchase selected'));
      return;
    }
    if (state.returnItems.isEmpty) {
      emit(state.copyWith(error: 'Please select at least one item to return'));
      return;
    }
    // Phase 14.0 — cheque must always carry a due date.
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
            (item) => PurchaseReturnItemInput(
              purchaseItemId: item.originalItem.id,
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

      // Idempotency token: caught by UNIQUE on purchase_returns.idempotency_key
      // so a duplicate insert (double-tap, retried call) cannot reach
      // post / JE / VAT-reversal side effects.
      final idempotencyKey = const Uuid().v4();

      await _repository.createPurchaseReturn(
        purchaseId: state.purchaseId!,
        currencyId: state.currencyId,
        dueDate: state.dueDate,
        subtotalCents: state.totalSubtotalCents,
        discountCents: state.totalDiscountCents,
        taxCents: state.totalTaxCents,
        totalCents: state.totalRefundCents,
        items: items,
        dispositionType: state.dispositionType,
        refundMethod: state.refundMethod,
        reason: state.reason,
        returnDate: DateTime.now(),
        allowNegativeStock: event.allowNegativeStock,
        idempotencyKey: idempotencyKey,
        taxInclusiveAtPost: state.purchase?.taxInclusiveAtPost ?? false,
      );

      emit(
        state.copyWith(
          isSubmitting: false,
          isSuccess: true,
          hasUnsavedChanges: false,
        ),
      );
    } catch (e) {
      emit(state.copyWith(isSubmitting: false, error: e.toString()));
    }
  }
}
