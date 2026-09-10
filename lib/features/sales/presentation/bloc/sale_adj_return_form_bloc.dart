import 'dart:developer' as developer;

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/daos/adjustment_return_dao.dart';
import '../../../../core/money/money.dart';
import '../../../../core/payments/checkout_settlement.dart';
import '../../../../core/pricing/discount.dart';
import '../../../../core/pricing/invoice_pricing_engine.dart';
import '../../../../core/pricing/pricing_snapshot.dart';
import '../../../../core/services/journal_entry_service.dart';
import '../../../../core/services/lan/lan_network_service.dart';
import '../../../../core/services/commissions/commission_service.dart';
import '../../../../core/services/loyalty/loyalty_points_service.dart';
import '../../../auth/data/services/session_service.dart';
import '../../../purchases/presentation/bloc/purchase_adj_return_form_bloc.dart';

// Re-use AdjReturnLineItem from purchase_adj_return_form_bloc.dart

// ==================== STATE ====================

class SaleAdjReturnFormState extends Equatable {
  final String? returnNumber;
  final int? customerId;
  final String? customerName;
  final int? employeeId;
  final String? employeeName;
  final List<AdjReturnLineItem> items;
  final String? notes;
  final int currencyId;
  final DateTime returnDate;
  final bool discountPerItem;
  final int overallDiscountCents;
  final bool overallDiscountIsPercent;
  final AdjReturnPaymentMethod paymentMethod;
  final DateTime? dueDate;
  final AdjReturnReasonCode? reasonCode;
  final bool isLoading;
  final bool isSubmitting;
  final String? error;
  final bool isSuccess;
  final bool hasUnsavedChanges;
  final int? createdReturnId;

  /// ── Loyalty deduction preview (req 3 + 4) ──
  /// Whether the loyalty program is enabled (drives UI visibility).
  final bool loyaltyEnabled;

  /// Points that WILL be deducted on submit for a credit return with a
  /// selected customer (already capped at the customer's balance).
  final int loyaltyPointsToDeduct;

  /// Value of ONE point in cents, from loyalty settings.
  final int loyaltyPointValueCents;

  SaleAdjReturnFormState({
    this.returnNumber,
    this.customerId,
    this.customerName,
    this.employeeId,
    this.employeeName,
    this.items = const [],
    this.notes,
    this.currencyId = 1,
    DateTime? returnDate,
    this.discountPerItem = true,
    this.overallDiscountCents = 0,
    this.overallDiscountIsPercent = false,
    this.paymentMethod = AdjReturnPaymentMethod.cash,
    this.dueDate,
    this.reasonCode,
    this.isLoading = false,
    this.isSubmitting = false,
    this.error,
    this.isSuccess = false,
    this.hasUnsavedChanges = false,
    this.createdReturnId,
    this.loyaltyEnabled = false,
    this.loyaltyPointsToDeduct = 0,
    this.loyaltyPointValueCents = 0,
  }) : returnDate = returnDate ?? DateTime.now();

  // ── Engine-backed invoice math ─────────────────────────────────────────
  // Single source of truth: every total/derived field below is computed
  // exactly once by [InvoicePricingEngine]. Memoized so that the cost is
  // amortized across the many getter calls the UI does per rebuild.

  /// Lazy memoized engine result. Built on first access and reused
  /// for the lifetime of this immutable state instance.
  late final InvoicePricingResult pricing = _computePricing();

  InvoicePricingResult _computePricing() {
    return InvoicePricingEngine.compute(
      InvoicePricingInput(
        lines: items.map((i) => i.toPricingInput()).toList(growable: false),
        overallDiscount: overallDiscountIsPercent
            ? Discount.percent(overallDiscountCents)
            : (overallDiscountCents > 0
                  ? Discount.fixed(Money.fromCents(overallDiscountCents))
                  : Discount.none),
        enableTaxCalculations: true,
        defaultTaxRateBps: 0,
        taxInclusivePricing: false,
      ),
    );
  }

  int get totalSubtotalCents => pricing.subtotal.cents;
  int get totalItemDiscountCents => pricing.itemDiscountTotal.cents;

  /// Sum of per-line tax **before** invoice-level discount allocation.
  /// Kept for back-compat with the legacy UI; reports should prefer
  /// [totalAdjustedTaxCents] which is what is actually posted.
  int get totalTaxCents => items.fold(0, (sum, i) => sum + i.taxCents);

  /// Sum of per-line totals **before** the invoice-level discount.
  /// Kept for back-compat with the legacy UI.
  int get totalBeforeOverallDiscount =>
      items.fold(0, (sum, i) => sum + i.totalCents);

  /// Net amount across all items *before* the overall discount and *before*
  /// tax. Correct base for an invoice-level percent discount so it matches
  /// the per-item percent semantics (1% of net, not 1% of net+tax).
  int get totalNetBeforeOverallDiscountCents =>
      items.fold(0, (sum, i) => sum + i.netCents);

  int get effectiveOverallDiscountCents => pricing.overallDiscount.cents;

  /// Net amount after ALL discounts (item-level + overall), before tax.
  int get totalNetCents =>
      (pricing.subtotal - pricing.totalDiscount).clampNonNegative().cents;

  /// Tax computed by the engine on the post-overall-discount base.
  /// Matches SAP / QuickBooks / Xero behavior.
  int get totalAdjustedTaxCents => pricing.tax.cents;

  /// Final total: net (after all discounts) + adjusted tax.
  int get totalCents => pricing.total.cents;
  int get totalQuantity => items.fold(0, (sum, i) => sum + i.quantity);

  SaleAdjReturnFormState copyWith({
    String? returnNumber,
    int? customerId,
    bool clearCustomer = false,
    String? customerName,
    int? employeeId,
    String? employeeName,
    bool clearEmployee = false,
    List<AdjReturnLineItem>? items,
    String? notes,
    int? currencyId,
    DateTime? returnDate,
    bool? discountPerItem,
    int? overallDiscountCents,
    bool? overallDiscountIsPercent,
    AdjReturnPaymentMethod? paymentMethod,
    DateTime? dueDate,
    bool clearDueDate = false,
    AdjReturnReasonCode? reasonCode,
    bool? isLoading,
    bool? isSubmitting,
    String? error,
    bool? isSuccess,
    bool? hasUnsavedChanges,
    int? createdReturnId,
    bool? loyaltyEnabled,
    int? loyaltyPointsToDeduct,
    int? loyaltyPointValueCents,
  }) {
    return SaleAdjReturnFormState(
      returnNumber: returnNumber ?? this.returnNumber,
      customerId: clearCustomer ? null : (customerId ?? this.customerId),
      customerName: clearCustomer ? null : (customerName ?? this.customerName),
      employeeId: clearEmployee ? null : (employeeId ?? this.employeeId),
      employeeName: clearEmployee ? null : (employeeName ?? this.employeeName),
      items: items ?? this.items,
      notes: notes ?? this.notes,
      currencyId: currencyId ?? this.currencyId,
      returnDate: returnDate ?? this.returnDate,
      discountPerItem: discountPerItem ?? this.discountPerItem,
      overallDiscountCents: overallDiscountCents ?? this.overallDiscountCents,
      overallDiscountIsPercent:
          overallDiscountIsPercent ?? this.overallDiscountIsPercent,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      dueDate: clearDueDate ? null : (dueDate ?? this.dueDate),
      reasonCode: reasonCode ?? this.reasonCode,
      isLoading: isLoading ?? this.isLoading,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      error: error,
      isSuccess: isSuccess ?? this.isSuccess,
      hasUnsavedChanges: hasUnsavedChanges ?? this.hasUnsavedChanges,
      createdReturnId: createdReturnId ?? this.createdReturnId,
      loyaltyEnabled: loyaltyEnabled ?? this.loyaltyEnabled,
      loyaltyPointsToDeduct:
          loyaltyPointsToDeduct ?? this.loyaltyPointsToDeduct,
      loyaltyPointValueCents:
          loyaltyPointValueCents ?? this.loyaltyPointValueCents,
    );
  }

  /// Total monetary value of [loyaltyPointsToDeduct] in cents.
  int get loyaltyDeductionValueCents =>
      loyaltyPointsToDeduct * loyaltyPointValueCents;

  @override
  List<Object?> get props => [
    returnNumber,
    customerId,
    customerName,
    employeeId,
    employeeName,
    items,
    notes,
    currencyId,
    returnDate,
    discountPerItem,
    overallDiscountCents,
    overallDiscountIsPercent,
    paymentMethod,
    dueDate,
    reasonCode,
    isLoading,
    isSubmitting,
    error,
    isSuccess,
    hasUnsavedChanges,
    createdReturnId,
    loyaltyEnabled,
    loyaltyPointsToDeduct,
    loyaltyPointValueCents,
  ];
}

// ==================== EVENTS ====================

abstract class SaleAdjReturnFormEvent extends Equatable {
  const SaleAdjReturnFormEvent();
  @override
  List<Object?> get props => [];
}

class SaleAdjReturnCustomerSelected extends SaleAdjReturnFormEvent {
  final int? customerId;
  final String? customerName;
  const SaleAdjReturnCustomerSelected([this.customerId, this.customerName]);
  @override
  List<Object?> get props => [customerId, customerName];
}

class SaleAdjReturnItemAdded extends SaleAdjReturnFormEvent {
  final AdjReturnLineItem item;
  const SaleAdjReturnItemAdded(this.item);
  @override
  List<Object?> get props => [item];
}

class SaleAdjReturnItemRemoved extends SaleAdjReturnFormEvent {
  final int index;
  const SaleAdjReturnItemRemoved(this.index);
  @override
  List<Object?> get props => [index];
}

class SaleAdjReturnItemQuantityChanged extends SaleAdjReturnFormEvent {
  final int index;
  final int quantity;
  const SaleAdjReturnItemQuantityChanged(this.index, this.quantity);
  @override
  List<Object?> get props => [index, quantity];
}

class SaleAdjReturnItemPriceChanged extends SaleAdjReturnFormEvent {
  final int index;
  final int unitPriceCents;
  const SaleAdjReturnItemPriceChanged(this.index, this.unitPriceCents);
  @override
  List<Object?> get props => [index, unitPriceCents];
}

class SaleAdjReturnItemDiscountChanged extends SaleAdjReturnFormEvent {
  final int index;
  final int discountCents;

  /// Percent discount in basis points (100 = 1%). When > 0 the discount is
  /// stored as a percent and recomputed live against the line subtotal.
  final int discountPercentBps;
  const SaleAdjReturnItemDiscountChanged(
    this.index,
    this.discountCents, {
    this.discountPercentBps = 0,
  });
  @override
  List<Object?> get props => [index, discountCents, discountPercentBps];
}

class SaleAdjReturnNotesChanged extends SaleAdjReturnFormEvent {
  final String notes;
  const SaleAdjReturnNotesChanged(this.notes);
  @override
  List<Object?> get props => [notes];
}

class SaleAdjReturnDateChanged extends SaleAdjReturnFormEvent {
  final DateTime date;
  const SaleAdjReturnDateChanged(this.date);
  @override
  List<Object?> get props => [date];
}

class SaleAdjReturnOverallDiscountChanged extends SaleAdjReturnFormEvent {
  final int cents;
  final bool isPercent;
  const SaleAdjReturnOverallDiscountChanged(this.cents, this.isPercent);
  @override
  List<Object?> get props => [cents, isPercent];
}

class SaleAdjReturnDiscountModeChanged extends SaleAdjReturnFormEvent {
  final bool perItem;
  const SaleAdjReturnDiscountModeChanged(this.perItem);
  @override
  List<Object?> get props => [perItem];
}

class SaleAdjReturnPaymentMethodChanged extends SaleAdjReturnFormEvent {
  final AdjReturnPaymentMethod method;
  const SaleAdjReturnPaymentMethodChanged(this.method);
  @override
  List<Object?> get props => [method];
}

class SaleAdjReturnDueDateChanged extends SaleAdjReturnFormEvent {
  final DateTime? date;
  const SaleAdjReturnDueDateChanged(this.date);
  @override
  List<Object?> get props => [date];
}

class SaleAdjReturnEmployeeChanged extends SaleAdjReturnFormEvent {
  final int? employeeId;
  final String? employeeName;
  const SaleAdjReturnEmployeeChanged({this.employeeId, this.employeeName});
  @override
  List<Object?> get props => [employeeId, employeeName];
}

class SaleAdjReturnReasonChanged extends SaleAdjReturnFormEvent {
  final AdjReturnReasonCode reasonCode;
  const SaleAdjReturnReasonChanged(this.reasonCode);
  @override
  List<Object?> get props => [reasonCode];
}

class SaleAdjReturnSubmitted extends SaleAdjReturnFormEvent {
  final List<CheckoutPaymentAllocation> settlementAllocations;

  const SaleAdjReturnSubmitted({this.settlementAllocations = const []});

  @override
  List<Object?> get props => [settlementAllocations];
}

// ==================== BLOC ====================

class _SaleAdjReturnInitialized extends SaleAdjReturnFormEvent {
  const _SaleAdjReturnInitialized();
}

/// Internal event: recompute the loyalty deduction preview whenever the
/// customer, totals, or refund method changes. Fired by the mutating
/// handlers so the sync UI handlers stay sync while the async loyalty
/// lookup runs on its own turn.
class _SaleAdjReturnRecomputeLoyalty extends SaleAdjReturnFormEvent {
  const _SaleAdjReturnRecomputeLoyalty();
}

class SaleAdjReturnFormBloc
    extends Bloc<SaleAdjReturnFormEvent, SaleAdjReturnFormState> {
  final AdjustmentReturnDao _dao;
  final JournalEntryService _journalEntryService;
  final CommissionService _commissionService;
  final LoyaltyPointsService _loyaltyPointsService;
  final SessionService _sessionService;
  final LanNetworkService? _lan;

  bool get _isRemoteClient =>
      _lan?.snapshot.mode == LanMode.client &&
      _lan?.hasRemoteUserSession == true;

  SaleAdjReturnFormBloc(
    this._dao,
    this._journalEntryService,
    this._commissionService,
    this._loyaltyPointsService,
    this._sessionService, {
    LanNetworkService? lan,
  }) : _lan = lan,
       super(SaleAdjReturnFormState()) {
    on<_SaleAdjReturnInitialized>(_onInitialized);
    on<_SaleAdjReturnRecomputeLoyalty>(_onRecomputeLoyalty);
    on<SaleAdjReturnCustomerSelected>(_onCustomerSelected);
    add(const _SaleAdjReturnInitialized());
    on<SaleAdjReturnItemAdded>(_onItemAdded);
    on<SaleAdjReturnItemRemoved>(_onItemRemoved);
    on<SaleAdjReturnItemQuantityChanged>(_onQuantityChanged);
    on<SaleAdjReturnItemPriceChanged>(_onPriceChanged);
    on<SaleAdjReturnItemDiscountChanged>(_onDiscountChanged);
    on<SaleAdjReturnNotesChanged>(_onNotesChanged);
    on<SaleAdjReturnDateChanged>(_onDateChanged);
    on<SaleAdjReturnOverallDiscountChanged>(_onOverallDiscountChanged);
    on<SaleAdjReturnDiscountModeChanged>(_onDiscountModeChanged);
    on<SaleAdjReturnPaymentMethodChanged>(_onPaymentMethodChanged);
    on<SaleAdjReturnDueDateChanged>(_onDueDateChanged);
    on<SaleAdjReturnEmployeeChanged>(_onEmployeeChanged);
    on<SaleAdjReturnReasonChanged>(_onReasonChanged);
    on<SaleAdjReturnSubmitted>(_onSubmitted);
  }

  Future<void> _onInitialized(
    _SaleAdjReturnInitialized event,
    Emitter<SaleAdjReturnFormState> emit,
  ) async {
    if (_isRemoteClient) {
      emit(state.copyWith(returnNumber: 'SRS'));
      return;
    }
    try {
      final number = await _dao.generateSaleAdjReturnNumber();
      emit(state.copyWith(returnNumber: number));
    } catch (_) {}
  }

  /// Recompute the loyalty-point deduction preview. Only meaningful for a
  /// credit return with a selected customer; otherwise clears the preview.
  Future<void> _onRecomputeLoyalty(
    _SaleAdjReturnRecomputeLoyalty event,
    Emitter<SaleAdjReturnFormState> emit,
  ) async {
    if (_isRemoteClient) {
      if (state.loyaltyEnabled || state.loyaltyPointsToDeduct != 0) {
        emit(
          state.copyWith(
            loyaltyEnabled: false,
            loyaltyPointsToDeduct: 0,
            loyaltyPointValueCents: 0,
          ),
        );
      }
      return;
    }
    final isCredit = state.paymentMethod == AdjReturnPaymentMethod.credit;
    if (!isCredit || state.customerId == null || state.totalCents <= 0) {
      if (state.loyaltyPointsToDeduct != 0 || state.loyaltyEnabled) {
        emit(
          state.copyWith(
            loyaltyEnabled: false,
            loyaltyPointsToDeduct: 0,
            loyaltyPointValueCents: 0,
          ),
        );
      }
      return;
    }
    final preview = await _loyaltyPointsService
        .previewAdjustmentReturnDeduction(
          customerId: state.customerId!,
          returnTotalCents: state.totalCents,
        );
    emit(
      state.copyWith(
        loyaltyEnabled: preview.enabled,
        loyaltyPointsToDeduct: preview.pointsToDeduct,
        loyaltyPointValueCents: preview.pointValueCents,
      ),
    );
  }

  void _onCustomerSelected(
    SaleAdjReturnCustomerSelected event,
    Emitter<SaleAdjReturnFormState> emit,
  ) {
    if (event.customerId == null) {
      emit(state.copyWith(clearCustomer: true, hasUnsavedChanges: true));
    } else {
      emit(
        state.copyWith(
          customerId: event.customerId,
          customerName: event.customerName,
          hasUnsavedChanges: true,
        ),
      );
    }
    add(const _SaleAdjReturnRecomputeLoyalty());
  }

  void _onItemAdded(
    SaleAdjReturnItemAdded event,
    Emitter<SaleAdjReturnFormState> emit,
  ) {
    emit(
      state.copyWith(
        items: [...state.items, event.item],
        hasUnsavedChanges: true,
      ),
    );
    add(const _SaleAdjReturnRecomputeLoyalty());
  }

  void _onItemRemoved(
    SaleAdjReturnItemRemoved event,
    Emitter<SaleAdjReturnFormState> emit,
  ) {
    final updated = List<AdjReturnLineItem>.from(state.items)
      ..removeAt(event.index);
    emit(state.copyWith(items: updated, hasUnsavedChanges: true));
    add(const _SaleAdjReturnRecomputeLoyalty());
  }

  void _onQuantityChanged(
    SaleAdjReturnItemQuantityChanged event,
    Emitter<SaleAdjReturnFormState> emit,
  ) {
    final updated = List<AdjReturnLineItem>.from(state.items);
    if (event.index < updated.length) {
      final qty = event.quantity < 1 ? 1 : event.quantity;
      updated[event.index] = updated[event.index].copyWith(quantity: qty);
      emit(state.copyWith(items: updated, hasUnsavedChanges: true));
    }
    add(const _SaleAdjReturnRecomputeLoyalty());
  }

  void _onPriceChanged(
    SaleAdjReturnItemPriceChanged event,
    Emitter<SaleAdjReturnFormState> emit,
  ) {
    final updated = List<AdjReturnLineItem>.from(state.items);
    if (event.index < updated.length) {
      updated[event.index] = updated[event.index].copyWith(
        unitPriceCents: event.unitPriceCents,
      );
      emit(state.copyWith(items: updated, hasUnsavedChanges: true));
    }
    add(const _SaleAdjReturnRecomputeLoyalty());
  }

  void _onDiscountChanged(
    SaleAdjReturnItemDiscountChanged event,
    Emitter<SaleAdjReturnFormState> emit,
  ) {
    final updated = List<AdjReturnLineItem>.from(state.items);
    if (event.index < updated.length) {
      updated[event.index] = updated[event.index].copyWith(
        discountCents: event.discountCents,
        discountPercentBps: event.discountPercentBps,
      );
      emit(state.copyWith(items: updated, hasUnsavedChanges: true));
    }
    add(const _SaleAdjReturnRecomputeLoyalty());
  }

  void _onNotesChanged(
    SaleAdjReturnNotesChanged event,
    Emitter<SaleAdjReturnFormState> emit,
  ) {
    emit(state.copyWith(notes: event.notes, hasUnsavedChanges: true));
  }

  void _onDateChanged(
    SaleAdjReturnDateChanged event,
    Emitter<SaleAdjReturnFormState> emit,
  ) {
    emit(state.copyWith(returnDate: event.date, hasUnsavedChanges: true));
  }

  void _onOverallDiscountChanged(
    SaleAdjReturnOverallDiscountChanged event,
    Emitter<SaleAdjReturnFormState> emit,
  ) {
    emit(
      state.copyWith(
        overallDiscountCents: event.cents,
        overallDiscountIsPercent: event.isPercent,
        hasUnsavedChanges: true,
      ),
    );
    add(const _SaleAdjReturnRecomputeLoyalty());
  }

  void _onDiscountModeChanged(
    SaleAdjReturnDiscountModeChanged event,
    Emitter<SaleAdjReturnFormState> emit,
  ) {
    // When switching modes, clear the OTHER mode's discount so the two
    // paths are mathematically equivalent. Without this, item-level
    // discounts would silently stack with a freshly-entered overall
    // discount (or vice-versa), causing a "double-discount" bug where
    // the same nominal 1% produces two different totals depending on
    // which entry path was used.
    final clearedItems = event.perItem
        ? state.items
        : state.items
              .map((i) => i.copyWith(discountCents: 0, discountPercentBps: 0))
              .toList();
    emit(
      state.copyWith(
        discountPerItem: event.perItem,
        items: clearedItems,
        overallDiscountCents: 0,
        overallDiscountIsPercent: false,
        hasUnsavedChanges: true,
      ),
    );
    add(const _SaleAdjReturnRecomputeLoyalty());
  }

  void _onPaymentMethodChanged(
    SaleAdjReturnPaymentMethodChanged event,
    Emitter<SaleAdjReturnFormState> emit,
  ) {
    emit(state.copyWith(paymentMethod: event.method, hasUnsavedChanges: true));
    add(const _SaleAdjReturnRecomputeLoyalty());
  }

  void _onDueDateChanged(
    SaleAdjReturnDueDateChanged event,
    Emitter<SaleAdjReturnFormState> emit,
  ) {
    if (event.date == null) {
      emit(state.copyWith(clearDueDate: true, hasUnsavedChanges: true));
    } else {
      emit(state.copyWith(dueDate: event.date, hasUnsavedChanges: true));
    }
  }

  void _onReasonChanged(
    SaleAdjReturnReasonChanged event,
    Emitter<SaleAdjReturnFormState> emit,
  ) {
    emit(state.copyWith(reasonCode: event.reasonCode, hasUnsavedChanges: true));
  }

  void _onEmployeeChanged(
    SaleAdjReturnEmployeeChanged event,
    Emitter<SaleAdjReturnFormState> emit,
  ) {
    if (event.employeeId == null) {
      emit(state.copyWith(clearEmployee: true, hasUnsavedChanges: true));
    } else {
      emit(
        state.copyWith(
          employeeId: event.employeeId,
          employeeName: event.employeeName,
          hasUnsavedChanges: true,
        ),
      );
    }
  }

  Future<void> _submitRemote(
    SaleAdjReturnSubmitted event,
    Emitter<SaleAdjReturnFormState> emit,
  ) async {
    try {
      final result = await _lan!.submitRemoteSaleAdjustmentReturn(
        LanSaleAdjustmentReturnRequest(
          idempotencyKey: const Uuid().v4(),
          customerId: state.customerId,
          employeeId: state.employeeId,
          refundMethod: state.paymentMethod.name,
          dueDate: state.dueDate,
          returnDate: state.returnDate,
          reasonCode: state.reasonCode!.name,
          notes: state.notes,
          overallDiscountCents: state.overallDiscountCents,
          overallDiscountIsPercent: state.overallDiscountIsPercent,
          payments: event.settlementAllocations
              .map(
                (payment) => LanCheckoutPaymentRequest(
                  method: payment.method,
                  amountCents: payment.amountCents,
                  reference: payment.reference,
                  bankName: payment.bankName,
                  issueDate: payment.issueDate,
                  dueDate: payment.dueDate,
                  note: payment.note,
                ),
              )
              .toList(growable: false),
          lines: state.items
              .map(
                (item) => LanSaleAdjustmentReturnLineRequest(
                  productId: item.productId,
                  variantId: item.variantId,
                  quantity: item.quantity,
                  unitPriceCents: item.unitPriceCents,
                  discountCents: item.discountCents,
                  discountPercentBps: item.discountPercentBps,
                  reason: item.reason,
                ),
              )
              .toList(growable: false),
        ),
      );
      emit(
        state.copyWith(
          returnNumber: result.returnNumber,
          isSubmitting: false,
          isSuccess: true,
          hasUnsavedChanges: false,
          createdReturnId: result.returnId,
        ),
      );
    } on LanBusinessException catch (error) {
      emit(state.copyWith(isSubmitting: false, error: error.message));
    } catch (error, stackTrace) {
      developer.log(
        'Remote sale adjustment return submission failed: $error',
        name: 'SaleAdjReturnFormBloc',
        error: error,
        stackTrace: stackTrace,
      );
      emit(
        state.copyWith(
          isSubmitting: false,
          error: 'returns.return_failed'.tr(),
        ),
      );
    }
  }

  Future<void> _onSubmitted(
    SaleAdjReturnSubmitted event,
    Emitter<SaleAdjReturnFormState> emit,
  ) async {
    if (state.isSuccess) return;
    // Customer required for credit/cheque only
    if ((state.paymentMethod == AdjReturnPaymentMethod.credit ||
            state.paymentMethod == AdjReturnPaymentMethod.cheque) &&
        state.customerId == null) {
      emit(state.copyWith(error: 'sales.customer_required_for_credit'.tr()));
      return;
    }
    // Cheque requires due date
    if (state.paymentMethod == AdjReturnPaymentMethod.cheque &&
        state.dueDate == null) {
      emit(state.copyWith(error: 'sales.cheque_due_date_required'.tr()));
      return;
    }
    if (state.items.isEmpty) {
      emit(state.copyWith(error: 'returns.items_required'.tr()));
      return;
    }
    if (state.reasonCode == null) {
      emit(state.copyWith(error: 'returns.reason_required'.tr()));
      return;
    }

    emit(state.copyWith(isSubmitting: true, error: null));

    if (_isRemoteClient) {
      await _submitRemote(event, emit);
      return;
    }

    try {
      // Idempotency: per-submission UUID. The UNIQUE constraint on
      // sale_return_adjustments.idempotency_key catches a duplicate insert
      // before any stock / GL side effect fires (defence-in-depth in
      // addition to `state.isSubmitting`).
      final idempotencyKey = const Uuid().v4();

      // Return number is generated atomically by the DAO inside the transaction
      // Phase 11.2 — stamp pricing-engine snapshot. The state's engine call
      // hardcodes `taxInclusivePricing: false`, so the snapshot must mirror
      // that exact flag.
      final returnData = SaleReturnAdjustmentsCompanion.insert(
        returnNumber: '', // Overridden by DAO inside transaction
        customerId: Value(state.customerId),
        employeeId: Value(state.employeeId),
        currencyId: state.currencyId,
        subtotalCents: Value(Decimal.fromInt(state.totalSubtotalCents)),
        discountCents: Value(
          Decimal.fromInt(
            state.totalItemDiscountCents + state.effectiveOverallDiscountCents,
          ),
        ),
        taxCents: Value(Decimal.fromInt(state.totalAdjustedTaxCents)),
        totalCents: Decimal.fromInt(state.totalCents),
        notes: Value(
          buildAdjReturnNotes(
            reasonCode: state.reasonCode!,
            userNotes: state.notes,
          ),
        ),
        returnDate: Value(state.returnDate),
        refundMethod: Value(
          event.settlementAllocations.isEmpty
              ? state.paymentMethod.name
              : 'mixed',
        ),
        dueDate: Value(
          event.settlementAllocations.isEmpty ? state.dueDate : null,
        ),
        idempotencyKey: Value(idempotencyKey),
      ).withPricingSnapshot(taxInclusive: false);

      // The engine has already done all the hard work: per-line subtotal,
      // per-line item discount, the proportional share of the invoice-
      // level discount, the post-allocation net, and the tax computed on
      // that net. We just persist what the engine produced — there is no
      // second arithmetic path here, which is the whole point of Phase 1.
      final pricing = state.pricing;
      final itemCompanions = <SaleReturnAdjustmentItemsCompanion>[];
      for (int idx = 0; idx < state.items.length; idx++) {
        final item = state.items[idx];
        final line = pricing.lines[idx];
        itemCompanions.add(
          SaleReturnAdjustmentItemsCompanion.insert(
            returnId: 0, // Will be set by DAO
            productId: item.productId,
            variantId: Value(item.variantId),
            quantity: item.quantity,
            quantityScale: Value(item.quantityScale),
            measurementType: Value(item.measurementType),
            unitPriceCents: Decimal.fromInt(item.unitPriceCents),
            // Total discount on this item = per-line discount + share of overall
            discountCents: Value(Decimal.fromInt(line.totalLineDiscount.cents)),
            taxCents: Value(Decimal.fromInt(line.tax.cents)),
            totalCents: Decimal.fromInt(line.total.cents),
            reason: Value(item.reason),
          ),
        );
      }

      final createdId = await _dao.createAndPostSaleAdjReturn(
        returnData,
        itemCompanions,
        journalEntryService: _journalEntryService,
        userId: await _sessionService.getCurrentUserId(),
        commissionService: _commissionService,
        loyaltyPointsService: _loyaltyPointsService,
        settlementAllocations: event.settlementAllocations,
      );

      emit(
        state.copyWith(
          isSubmitting: false,
          isSuccess: true,
          hasUnsavedChanges: false,
          createdReturnId: createdId,
        ),
      );
    } on StockInsufficientException catch (e) {
      emit(
        state.copyWith(
          isSubmitting: false,
          error: 'returns.stock_insufficient'.tr(
            namedArgs: {
              'stock': '${e.currentStock}',
              'quantity': '${e.requestedQuantity}',
            },
          ),
        ),
      );
    } catch (e, st) {
      developer.log(
        'Sale adjustment return submission failed: $e',
        name: 'SaleAdjReturnFormBloc',
        error: e,
        stackTrace: st,
      );
      emit(
        state.copyWith(
          isSubmitting: false,
          error: 'returns.return_failed'.tr(),
        ),
      );
    }
  }
}
