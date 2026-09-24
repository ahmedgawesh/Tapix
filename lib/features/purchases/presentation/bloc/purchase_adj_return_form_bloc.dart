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
import '../../../../core/pricing/line_item_pricing_engine.dart';
import '../../../../core/pricing/pricing_snapshot.dart';
import '../../../../core/pricing/pricing_preview_fingerprint.dart';
import '../../../../core/services/business/branch_tax_policy_store.dart';
import '../../../../core/measurement/measurement.dart';
import '../../../../core/services/journal_entry_service.dart';
import '../../../../core/services/lan/lan_network_service.dart';

import '../../../settings/data/services/app_settings_service.dart';
import '../../../settings/domain/entities/app_settings.dart';
import '../../../../core/services/tax_calculation_service.dart';

// ==================== ENUMS ====================

/// Payment / refund method for adjustment returns.
/// Maps to the `refund_method` column (cash, card, credit, cheque).
/// `card` is routed to the Bank account (1010) by the accounting policy,
/// exactly like bank transfers — see `RefundChannelX.fromWire`.
enum AdjReturnPaymentMethod { cash, card, credit, cheque }

/// Mandatory reason code for unlinked (adjustment) returns.
/// Required by industry-standard practice (SAP, NetSuite, Odoo, QuickBooks)
/// to provide an audit trail and discourage fraudulent / careless issuance.
/// Persisted into the `notes` column with the prefix `[REASON:<name>] `.
enum AdjReturnReasonCode {
  damaged,
  defective,
  wrongItem,
  gift,
  goodwill,
  noReceipt,
  other,
}

/// Prefix used when serializing the reason code into the return's `notes`
/// column, so it remains readable and parseable later.
String buildAdjReturnNotes({
  required AdjReturnReasonCode reasonCode,
  String? userNotes,
}) {
  final tag = '[REASON:${reasonCode.name}]';
  final tail = (userNotes == null || userNotes.isEmpty) ? '' : ' $userNotes';
  return '$tag$tail';
}

/// Parsed result from a return's raw `notes` column.
class ParsedAdjReturnNotes {
  final AdjReturnReasonCode? reasonCode;
  final String? userNotes;
  const ParsedAdjReturnNotes({this.reasonCode, this.userNotes});
}

/// Inverse of [buildAdjReturnNotes]. Extracts the reason-code tag
/// (if present) and returns the user-visible notes without the tag.
ParsedAdjReturnNotes parseAdjReturnNotes(String? raw) {
  if (raw == null || raw.isEmpty) {
    return const ParsedAdjReturnNotes();
  }
  final match = RegExp(r'^\s*\[REASON:([a-zA-Z_]+)\]\s*').firstMatch(raw);
  if (match == null) {
    return ParsedAdjReturnNotes(
      userNotes: raw.trim().isEmpty ? null : raw.trim(),
    );
  }
  final name = match.group(1);
  AdjReturnReasonCode? code;
  if (name != null) {
    for (final v in AdjReturnReasonCode.values) {
      if (v.name == name) {
        code = v;
        break;
      }
    }
  }
  final rest = raw.substring(match.end).trim();
  return ParsedAdjReturnNotes(
    reasonCode: code,
    userNotes: rest.isEmpty ? null : rest,
  );
}

/// Localized label for a reason code. Returns empty string for null.
String adjReturnReasonLabel(AdjReturnReasonCode? r) {
  if (r == null) return '';
  return switch (r) {
    AdjReturnReasonCode.damaged => 'returns.reason_damaged'.tr(),
    AdjReturnReasonCode.defective => 'returns.reason_defective'.tr(),
    AdjReturnReasonCode.wrongItem => 'returns.reason_wrong_item'.tr(),
    AdjReturnReasonCode.gift => 'returns.reason_gift'.tr(),
    AdjReturnReasonCode.goodwill => 'returns.reason_goodwill'.tr(),
    AdjReturnReasonCode.noReceipt => 'returns.reason_no_receipt'.tr(),
    AdjReturnReasonCode.other => 'returns.reason_other'.tr(),
  };
}

// ==================== LINE ITEM ====================

class AdjReturnConsignmentSource extends Equatable {
  const AdjReturnConsignmentSource({
    required this.layerId,
    required this.supplierId,
    required this.supplierName,
    required this.receiptNumber,
    required this.receivedAt,
    required this.maximumReturnQuantity,
    required this.quantityScale,
    required this.measurementType,
    this.batchNumber,
    this.manufacturerLotNumber,
  });

  final String layerId;
  final int supplierId;
  final String supplierName;
  final String receiptNumber;
  final DateTime receivedAt;
  final int maximumReturnQuantity;
  final int quantityScale;
  final String measurementType;
  final String? batchNumber;
  final String? manufacturerLotNumber;

  String get sourceCode => 'C-$layerId';

  @override
  List<Object?> get props => [
    layerId,
    supplierId,
    supplierName,
    receiptNumber,
    receivedAt,
    maximumReturnQuantity,
    quantityScale,
    measurementType,
    batchNumber,
    manufacturerLotNumber,
  ];
}

class AdjReturnSupplierIdentitySource extends Equatable {
  const AdjReturnSupplierIdentitySource({
    required this.identityId,
    required this.supplierId,
    required this.supplierName,
    required this.sourceSku,
  });

  final int identityId;
  final int supplierId;
  final String supplierName;
  final String sourceSku;

  @override
  List<Object?> get props => [identityId, supplierId, supplierName, sourceSku];
}

enum AdjReturnSourceResolution {
  pending,
  supplierIdentity,
  consignment,
  unverified,
  notApplicable;

  String get wireValue => switch (this) {
    AdjReturnSourceResolution.pending => 'pending',
    AdjReturnSourceResolution.supplierIdentity => 'supplier_identity',
    AdjReturnSourceResolution.consignment => 'consignment',
    AdjReturnSourceResolution.unverified => 'unverified',
    AdjReturnSourceResolution.notApplicable => 'not_applicable',
  };
}

class AdjReturnLineItem extends Equatable {
  final int productId;
  final int? variantId;
  final String productName;
  final String? variantSku;
  final String? variantLabel;
  final int quantity;
  final int quantityScale;
  final String measurementType;
  final int unitPriceCents;
  final int unitCostCents;

  /// Reference retail (regular) selling price captured at pick time. Used to
  /// render the "retail" price-tier shortcut in the edit sheet so the user can
  /// snap back to it after switching to wholesale. Never mutated by edits.
  final int? retailPriceCents;

  /// Reference wholesale selling price captured at pick time (nullable when the
  /// product/variant has no wholesale price). Used to render the "wholesale"
  /// price-tier shortcut in the edit sheet.
  final int? wholesalePriceCents;
  final int discountCents;

  /// When > 0, the line discount is treated as a percentage (basis points,
  /// e.g. 100 = 1%) of the line subtotal, and [discountCents] is ignored
  /// in favour of [effectiveDiscountCents]. This lets a percent discount
  /// entered in the edit sheet stay correct after the quantity is changed
  /// from outside the sheet.
  final int discountPercentBps;

  /// Tax rate in basis points (e.g. 1500 = 15%).
  final int taxRateBps;
  final bool? isTaxable;
  final bool taxInclusivePricing;
  final String? reason;
  final bool trackInventory;
  final AdjReturnConsignmentSource? consignmentSource;
  final AdjReturnSupplierIdentitySource? supplierIdentitySource;
  final AdjReturnSourceResolution sourceResolution;
  final String? sourceResolutionReason;

  const AdjReturnLineItem({
    required this.productId,
    this.variantId,
    required this.productName,
    this.variantSku,
    this.variantLabel,
    required this.quantity,
    this.quantityScale = 1,
    this.measurementType = 'piece',
    required this.unitPriceCents,
    this.unitCostCents = 0,
    this.retailPriceCents,
    this.wholesalePriceCents,
    this.discountCents = 0,
    this.discountPercentBps = 0,
    this.taxRateBps = 0,
    this.isTaxable,
    this.taxInclusivePricing = false,
    this.reason,
    this.trackInventory = true,
    this.consignmentSource,
    this.supplierIdentitySource,
    AdjReturnSourceResolution? sourceResolution,
    this.sourceResolutionReason,
  }) : sourceResolution =
           sourceResolution ??
           (consignmentSource != null
               ? AdjReturnSourceResolution.consignment
               : supplierIdentitySource != null
               ? AdjReturnSourceResolution.supplierIdentity
               : trackInventory
               ? AdjReturnSourceResolution.pending
               : AdjReturnSourceResolution.notApplicable);

  // ── Engine-backed line math ────────────────────────────────────────────
  // All getters below delegate to [LineItemPricingEngine] so there is
  // exactly one place in the codebase where line totals are computed.
  // Returning `int cents` keeps the existing UI/UX contract unchanged.

  /// Build the engine input for this line.
  LineItemPricingInput toPricingInput() => LineItemPricingInput(
    unitPrice: Money.fromCents(unitPriceCents),
    quantity: quantity,
    quantityScale: quantityScale,
    discount: discountPercentBps > 0
        ? Discount.percent(discountPercentBps)
        : (discountCents > 0
              ? Discount.fixed(Money.fromCents(discountCents))
              : Discount.none),
    isTaxable: taxRateBps > 0,
    productTaxRateBps: taxRateBps,
  );

  LineItemPricingResult _compute() => LineItemPricingEngine.compute(
    input: toPricingInput(),
    enableTaxCalculations: taxRateBps > 0,
    defaultTaxRateBps: 0,
    taxInclusivePricing: taxInclusivePricing,
  );

  int get subtotalCents => _compute().subtotal.cents;

  /// Resolved discount in cents. If a percent was supplied, the engine
  /// recomputes it against the *current* subtotal so quantity/price
  /// changes flow through automatically.
  int get effectiveDiscountCents => _compute().discount.cents;

  int get netCents => _compute().net.cents;
  int get taxCents => _compute().tax.cents;
  int get totalCents => _compute().total.cents;

  String get displayName {
    if (variantLabel != null && variantLabel!.isNotEmpty) {
      return '$productName ($variantLabel)';
    }
    if (variantSku != null && variantSku!.isNotEmpty) {
      return '$productName ($variantSku)';
    }
    return productName;
  }

  AdjReturnLineItem copyWith({
    int? quantity,
    int? unitPriceCents,
    int? discountCents,
    int? discountPercentBps,
    int? taxRateBps,
    bool? taxInclusivePricing,
    String? reason,
    bool? trackInventory,
    AdjReturnConsignmentSource? consignmentSource,
    bool clearConsignmentSource = false,
    AdjReturnSupplierIdentitySource? supplierIdentitySource,
    bool clearSupplierIdentitySource = false,
    AdjReturnSourceResolution? sourceResolution,
    String? sourceResolutionReason,
    bool clearSourceResolutionReason = false,
  }) {
    return AdjReturnLineItem(
      productId: productId,
      variantId: variantId,
      productName: productName,
      variantSku: variantSku,
      variantLabel: variantLabel,
      quantity: quantity ?? this.quantity,
      quantityScale: quantityScale,
      measurementType: measurementType,
      unitPriceCents: unitPriceCents ?? this.unitPriceCents,
      unitCostCents: unitCostCents,
      retailPriceCents: retailPriceCents,
      wholesalePriceCents: wholesalePriceCents,
      discountCents: discountCents ?? this.discountCents,
      discountPercentBps: discountPercentBps ?? this.discountPercentBps,
      taxRateBps: taxRateBps ?? this.taxRateBps,
      isTaxable: isTaxable,
      taxInclusivePricing: taxInclusivePricing ?? this.taxInclusivePricing,
      reason: reason ?? this.reason,
      trackInventory: trackInventory ?? this.trackInventory,
      consignmentSource: clearConsignmentSource
          ? null
          : (consignmentSource ?? this.consignmentSource),
      supplierIdentitySource: clearSupplierIdentitySource
          ? null
          : (supplierIdentitySource ?? this.supplierIdentitySource),
      sourceResolution: sourceResolution ?? this.sourceResolution,
      sourceResolutionReason: clearSourceResolutionReason
          ? null
          : (sourceResolutionReason ?? this.sourceResolutionReason),
    );
  }

  @override
  List<Object?> get props => [
    productId,
    variantId,
    productName,
    variantSku,
    variantLabel,
    quantity,
    quantityScale,
    measurementType,
    unitPriceCents,
    unitCostCents,
    retailPriceCents,
    wholesalePriceCents,
    discountCents,
    discountPercentBps,
    taxRateBps,
    isTaxable,
    taxInclusivePricing,
    reason,
    trackInventory,
    consignmentSource,
    supplierIdentitySource,
    sourceResolution,
    sourceResolutionReason,
  ];
}

// ==================== STATE ====================

class PurchaseAdjReturnFormState extends Equatable {
  final String? returnNumber;
  final int? supplierId;
  final String? supplierName;
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

  PurchaseAdjReturnFormState({
    this.returnNumber,
    this.supplierId,
    this.supplierName,
    this.items = const [],
    this.notes,
    this.currencyId = 1,
    DateTime? returnDate,
    this.discountPerItem = true,
    this.overallDiscountCents = 0,
    this.overallDiscountIsPercent = false,
    this.paymentMethod = AdjReturnPaymentMethod.credit,
    this.dueDate,
    this.reasonCode,
    this.isLoading = false,
    this.isSubmitting = false,
    this.error,
    this.isSuccess = false,
    this.hasUnsavedChanges = false,
    this.createdReturnId,
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
        // The state stores per-item taxRateBps directly, so the engine's
        // global tax toggle is always on; lines with rate 0 produce 0 tax.
        enableTaxCalculations: true,
        defaultTaxRateBps: 0,
        taxInclusivePricing: taxInclusivePricing,
      ),
    );
  }

  bool get taxInclusivePricing =>
      items.isNotEmpty && items.first.taxInclusivePricing;

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
  /// tax. This is the correct base for an invoice-level percent discount,
  /// matching the per-item percent semantics (1% of net, not 1% of net+tax).
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

  PurchaseAdjReturnFormState copyWith({
    String? returnNumber,
    int? supplierId,
    String? supplierName,
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
  }) {
    return PurchaseAdjReturnFormState(
      returnNumber: returnNumber ?? this.returnNumber,
      supplierId: supplierId ?? this.supplierId,
      supplierName: supplierName ?? this.supplierName,
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
    );
  }

  @override
  List<Object?> get props => [
    returnNumber,
    supplierId,
    supplierName,
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
  ];
}

// ==================== EVENTS ====================

abstract class PurchaseAdjReturnFormEvent extends Equatable {
  const PurchaseAdjReturnFormEvent();
  @override
  List<Object?> get props => [];
}

class PurchaseAdjReturnSupplierSelected extends PurchaseAdjReturnFormEvent {
  final int supplierId;
  final String supplierName;
  const PurchaseAdjReturnSupplierSelected(this.supplierId, this.supplierName);
  @override
  List<Object?> get props => [supplierId, supplierName];
}

class PurchaseAdjReturnItemAdded extends PurchaseAdjReturnFormEvent {
  final AdjReturnLineItem item;
  const PurchaseAdjReturnItemAdded(this.item);
  @override
  List<Object?> get props => [item];
}

class PurchaseAdjReturnItemRemoved extends PurchaseAdjReturnFormEvent {
  final int index;
  const PurchaseAdjReturnItemRemoved(this.index);
  @override
  List<Object?> get props => [index];
}

class PurchaseAdjReturnItemQuantityChanged extends PurchaseAdjReturnFormEvent {
  final int index;
  final int quantity;
  const PurchaseAdjReturnItemQuantityChanged(this.index, this.quantity);
  @override
  List<Object?> get props => [index, quantity];
}

class PurchaseAdjReturnItemPriceChanged extends PurchaseAdjReturnFormEvent {
  final int index;
  final int unitPriceCents;
  const PurchaseAdjReturnItemPriceChanged(this.index, this.unitPriceCents);
  @override
  List<Object?> get props => [index, unitPriceCents];
}

class PurchaseAdjReturnItemDiscountChanged extends PurchaseAdjReturnFormEvent {
  final int index;
  final int discountCents;

  /// Percent discount in basis points (100 = 1%). When > 0 the discount is
  /// stored as a percent and recomputed live against the line subtotal.
  final int discountPercentBps;
  const PurchaseAdjReturnItemDiscountChanged(
    this.index,
    this.discountCents, {
    this.discountPercentBps = 0,
  });
  @override
  List<Object?> get props => [index, discountCents, discountPercentBps];
}

class PurchaseAdjReturnNotesChanged extends PurchaseAdjReturnFormEvent {
  final String notes;
  const PurchaseAdjReturnNotesChanged(this.notes);
  @override
  List<Object?> get props => [notes];
}

class PurchaseAdjReturnDateChanged extends PurchaseAdjReturnFormEvent {
  final DateTime date;
  const PurchaseAdjReturnDateChanged(this.date);
  @override
  List<Object?> get props => [date];
}

class PurchaseAdjReturnOverallDiscountChanged
    extends PurchaseAdjReturnFormEvent {
  final int cents;
  final bool isPercent;
  const PurchaseAdjReturnOverallDiscountChanged(this.cents, this.isPercent);
  @override
  List<Object?> get props => [cents, isPercent];
}

class PurchaseAdjReturnDiscountModeChanged extends PurchaseAdjReturnFormEvent {
  final bool perItem;
  const PurchaseAdjReturnDiscountModeChanged(this.perItem);
  @override
  List<Object?> get props => [perItem];
}

class PurchaseAdjReturnPaymentMethodChanged extends PurchaseAdjReturnFormEvent {
  final AdjReturnPaymentMethod method;
  const PurchaseAdjReturnPaymentMethodChanged(this.method);
  @override
  List<Object?> get props => [method];
}

class PurchaseAdjReturnDueDateChanged extends PurchaseAdjReturnFormEvent {
  final DateTime? date;
  const PurchaseAdjReturnDueDateChanged(this.date);
  @override
  List<Object?> get props => [date];
}

class PurchaseAdjReturnReasonChanged extends PurchaseAdjReturnFormEvent {
  final AdjReturnReasonCode reasonCode;
  const PurchaseAdjReturnReasonChanged(this.reasonCode);
  @override
  List<Object?> get props => [reasonCode];
}

class PurchaseAdjReturnSubmitted extends PurchaseAdjReturnFormEvent {
  /// Carries the current inventory policy from the UI layer so the bloc
  /// doesn't need a direct dependency on the app settings bloc.
  final bool allowNegativeStock;
  final List<CheckoutPaymentAllocation> settlementAllocations;

  const PurchaseAdjReturnSubmitted({
    this.allowNegativeStock = false,
    this.settlementAllocations = const [],
  });

  @override
  List<Object?> get props => [allowNegativeStock, settlementAllocations];
}

// ==================== BLOC ====================

class _PurchaseAdjReturnInitialized extends PurchaseAdjReturnFormEvent {
  const _PurchaseAdjReturnInitialized();
}

class _LocalPurchaseReturnPricingChanged implements Exception {
  const _LocalPurchaseReturnPricingChanged(this.preview);
  final PurchaseAdjReturnFormState preview;
}

class PurchaseAdjReturnFormBloc
    extends Bloc<PurchaseAdjReturnFormEvent, PurchaseAdjReturnFormState> {
  final AdjustmentReturnDao _dao;
  final JournalEntryService _journalEntryService;
  final LanNetworkService? _lan;
  final AppSettingsService? _settings;
  Future<AppSettings>? _taxPolicy;

  PurchaseAdjReturnFormBloc(
    this._dao,
    this._journalEntryService, {
    LanNetworkService? lan,
    AppSettingsService? settings,
  }) : _lan = lan,
       _settings = settings,
       super(PurchaseAdjReturnFormState()) {
    on<_PurchaseAdjReturnInitialized>(_onInitialized);
    on<PurchaseAdjReturnSupplierSelected>(_onSupplierSelected);
    add(const _PurchaseAdjReturnInitialized());
    on<PurchaseAdjReturnItemAdded>(_onItemAdded);
    on<PurchaseAdjReturnItemRemoved>(_onItemRemoved);
    on<PurchaseAdjReturnItemQuantityChanged>(_onQuantityChanged);
    on<PurchaseAdjReturnItemPriceChanged>(_onPriceChanged);
    on<PurchaseAdjReturnItemDiscountChanged>(_onDiscountChanged);
    on<PurchaseAdjReturnNotesChanged>(_onNotesChanged);
    on<PurchaseAdjReturnDateChanged>(_onDateChanged);
    on<PurchaseAdjReturnOverallDiscountChanged>(_onOverallDiscountChanged);
    on<PurchaseAdjReturnDiscountModeChanged>(_onDiscountModeChanged);
    on<PurchaseAdjReturnPaymentMethodChanged>(_onPaymentMethodChanged);
    on<PurchaseAdjReturnDueDateChanged>(_onDueDateChanged);
    on<PurchaseAdjReturnReasonChanged>(_onReasonChanged);
    on<PurchaseAdjReturnSubmitted>(_onSubmitted);
  }

  bool get _isRemoteClient =>
      _lan?.snapshot.mode == LanMode.client &&
      _lan?.hasRemoteUserSession == true;

  Future<void> _onInitialized(
    _PurchaseAdjReturnInitialized event,
    Emitter<PurchaseAdjReturnFormState> emit,
  ) async {
    if (_isRemoteClient) {
      emit(state.copyWith(returnNumber: '—'));
      return;
    }
    try {
      final number = await _dao.generatePurchaseAdjReturnNumber();
      emit(state.copyWith(returnNumber: number));
    } catch (_) {}
  }

  void _onSupplierSelected(
    PurchaseAdjReturnSupplierSelected event,
    Emitter<PurchaseAdjReturnFormState> emit,
  ) {
    emit(
      state.copyWith(
        supplierId: event.supplierId,
        supplierName: event.supplierName,
        hasUnsavedChanges: true,
      ),
    );
  }

  Future<AppSettings> _loadTaxPolicy() async {
    if (_isRemoteClient) {
      final page = await _lan!.fetchRemoteCatalog(limit: 1, management: true);
      // Older masters use product-only, exclusive purchase-return pricing.
      final purchaseRate = page.defaultPurchaseTaxRateBps;
      if (purchaseRate == null) return const AppSettings();
      return AppSettings(
        enableTaxCalculations: page.enableTaxCalculations,
        defaultPurchaseTaxRate: purchaseRate / 100,
        taxInclusivePricing: page.taxInclusivePricing,
      );
    }
    final stored = await BranchTaxPolicyStore(_dao.attachedDatabase).read();
    if (stored == null && (_settings?.requiresPersistedTaxPolicy ?? false)) {
      throw StateError('Branch tax policy is missing.');
    }
    final current = _settings?.current ?? const AppSettings();
    return stored?.policy.applyTo(current) ?? current;
  }

  /// Read and price within the caller's posting transaction. Never persist the
  /// form's cached tax values without comparing with current product rules.
  Future<PurchaseAdjReturnFormState> _refreshLocalPricing(
    PurchaseAdjReturnFormState submitted,
  ) async {
    final policy = await _loadTaxPolicy();
    final ids = submitted.items.map((i) => i.productId).toSet();
    final products = await (_dao.select(
      _dao.products,
    )..where((p) => p.id.isIn(ids))).get();
    final byId = {for (final p in products) p.id: p};
    final refreshed = <AdjReturnLineItem>[];
    for (final item in submitted.items) {
      final product = byId[item.productId];
      if (product == null ||
          !product.isActive ||
          product.measurementType != item.measurementType ||
          MeasurementType.fromDb(product.measurementType).quantityScale !=
              item.quantityScale) {
        throw StateError('Return product or measurement is unavailable.');
      }
      refreshed.add(
        item.copyWith(
          taxRateBps: policy.enableTaxCalculations
              ? TaxCalculationService.resolveLineItemTaxRateBps(
                  isTaxable: product.isTaxable,
                  productTaxRateBps: product.purchaseTaxRateBps,
                  defaultTaxRateBps: (policy.defaultPurchaseTaxRate * 100)
                      .round(),
                )
              : 0,
          taxInclusivePricing: policy.taxInclusivePricing,
        ),
      );
    }
    return submitted.copyWith(items: refreshed);
  }

  Future<void> _onItemAdded(
    PurchaseAdjReturnItemAdded event,
    Emitter<PurchaseAdjReturnFormState> emit,
  ) async {
    try {
      var item = event.item;
      if (_settings != null || _isRemoteClient) {
        final policy = await (_taxPolicy ??= _loadTaxPolicy());
        var taxable = item.isTaxable ?? (item.taxRateBps > 0);
        var rate = item.taxRateBps;
        if (_isRemoteClient && item.isTaxable == null) {
          final page = await _lan!.fetchRemoteCatalog(
            query: item.productName,
            limit: 200,
            management: true,
          );
          final product = page.products.firstWhere(
            (p) => p.id == item.productId,
          );
          taxable = product.isTaxable;
          rate = product.purchaseTaxRateBps;
        }
        if (!_isRemoteClient) {
          final product = await (_dao.select(
            _dao.products,
          )..where((p) => p.id.equals(item.productId))).getSingle();
          taxable = product.isTaxable;
          rate = product.purchaseTaxRateBps;
        }
        item = item.copyWith(
          taxRateBps: policy.enableTaxCalculations
              ? TaxCalculationService.resolveLineItemTaxRateBps(
                  isTaxable: taxable,
                  productTaxRateBps: rate,
                  defaultTaxRateBps: (policy.defaultPurchaseTaxRate * 100)
                      .round(),
                )
              : 0,
          taxInclusivePricing: policy.taxInclusivePricing,
        );
      }
      emit(
        state.copyWith(items: [...state.items, item], hasUnsavedChanges: true),
      );
    } catch (error) {
      _taxPolicy = null;
      emit(state.copyWith(error: error.toString()));
    }
  }

  void _onItemRemoved(
    PurchaseAdjReturnItemRemoved event,
    Emitter<PurchaseAdjReturnFormState> emit,
  ) {
    final updated = List<AdjReturnLineItem>.from(state.items)
      ..removeAt(event.index);
    emit(state.copyWith(items: updated, hasUnsavedChanges: true));
  }

  void _onQuantityChanged(
    PurchaseAdjReturnItemQuantityChanged event,
    Emitter<PurchaseAdjReturnFormState> emit,
  ) {
    final updated = List<AdjReturnLineItem>.from(state.items);
    if (event.index < updated.length) {
      final qty = event.quantity < 1 ? 1 : event.quantity;
      updated[event.index] = updated[event.index].copyWith(quantity: qty);
      emit(state.copyWith(items: updated, hasUnsavedChanges: true));
    }
  }

  void _onPriceChanged(
    PurchaseAdjReturnItemPriceChanged event,
    Emitter<PurchaseAdjReturnFormState> emit,
  ) {
    final updated = List<AdjReturnLineItem>.from(state.items);
    if (event.index < updated.length) {
      updated[event.index] = updated[event.index].copyWith(
        unitPriceCents: event.unitPriceCents,
      );
      emit(state.copyWith(items: updated, hasUnsavedChanges: true));
    }
  }

  void _onDiscountChanged(
    PurchaseAdjReturnItemDiscountChanged event,
    Emitter<PurchaseAdjReturnFormState> emit,
  ) {
    final updated = List<AdjReturnLineItem>.from(state.items);
    if (event.index < updated.length) {
      updated[event.index] = updated[event.index].copyWith(
        discountCents: event.discountCents,
        discountPercentBps: event.discountPercentBps,
      );
      emit(state.copyWith(items: updated, hasUnsavedChanges: true));
    }
  }

  void _onNotesChanged(
    PurchaseAdjReturnNotesChanged event,
    Emitter<PurchaseAdjReturnFormState> emit,
  ) {
    emit(state.copyWith(notes: event.notes, hasUnsavedChanges: true));
  }

  void _onDateChanged(
    PurchaseAdjReturnDateChanged event,
    Emitter<PurchaseAdjReturnFormState> emit,
  ) {
    emit(state.copyWith(returnDate: event.date, hasUnsavedChanges: true));
  }

  void _onOverallDiscountChanged(
    PurchaseAdjReturnOverallDiscountChanged event,
    Emitter<PurchaseAdjReturnFormState> emit,
  ) {
    emit(
      state.copyWith(
        overallDiscountCents: event.cents,
        overallDiscountIsPercent: event.isPercent,
        hasUnsavedChanges: true,
      ),
    );
  }

  void _onDiscountModeChanged(
    PurchaseAdjReturnDiscountModeChanged event,
    Emitter<PurchaseAdjReturnFormState> emit,
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
  }

  void _onPaymentMethodChanged(
    PurchaseAdjReturnPaymentMethodChanged event,
    Emitter<PurchaseAdjReturnFormState> emit,
  ) {
    emit(state.copyWith(paymentMethod: event.method, hasUnsavedChanges: true));
  }

  void _onDueDateChanged(
    PurchaseAdjReturnDueDateChanged event,
    Emitter<PurchaseAdjReturnFormState> emit,
  ) {
    if (event.date == null) {
      emit(state.copyWith(clearDueDate: true, hasUnsavedChanges: true));
    } else {
      emit(state.copyWith(dueDate: event.date, hasUnsavedChanges: true));
    }
  }

  void _onReasonChanged(
    PurchaseAdjReturnReasonChanged event,
    Emitter<PurchaseAdjReturnFormState> emit,
  ) {
    emit(state.copyWith(reasonCode: event.reasonCode, hasUnsavedChanges: true));
  }

  Future<void> _onSubmitted(
    PurchaseAdjReturnSubmitted event,
    Emitter<PurchaseAdjReturnFormState> emit,
  ) async {
    if (state.isSuccess || state.isSubmitting) return;
    if (state.supplierId == null) {
      emit(state.copyWith(error: 'returns.supplier_required'.tr()));
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
    // Cheque requires due date
    if (state.paymentMethod == AdjReturnPaymentMethod.cheque &&
        state.dueDate == null) {
      emit(state.copyWith(error: 'purchases.cheque_due_date_required'.tr()));
      return;
    }

    emit(state.copyWith(isSubmitting: true, error: null));

    try {
      // Idempotency: generate a per-submission UUID so that if the same
      // companion is replayed (double-tap that beats `isSubmitting`, retried
      // network call, OS-level rebuild) the UNIQUE constraint on
      // purchase_return_adjustments.idempotency_key rejects the duplicate
      // before any stock / GL side effects fire.
      final idempotencyKey = const Uuid().v4();

      if (_isRemoteClient) {
        final result = await _lan!.submitRemotePurchaseAdjustmentReturn(
          LanPurchaseAdjustmentReturnRequest(
            idempotencyKey: idempotencyKey,
            expectedPricingFingerprint: pricingPreviewFingerprint(
              state.pricing,
              taxInclusive: state.taxInclusivePricing,
            ),
            supplierId: state.supplierId!,
            refundMethod: state.paymentMethod.name,
            dueDate: state.dueDate,
            returnDate: state.returnDate,
            reasonCode: state.reasonCode!.name,
            notes: state.notes,
            overallDiscountCents: state.overallDiscountCents,
            overallDiscountIsPercent: state.overallDiscountIsPercent,
            lines: state.items
                .map(
                  (item) => LanPurchaseAdjustmentReturnLineRequest(
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
          ),
        );
        emit(
          state.copyWith(
            isSubmitting: false,
            isSuccess: true,
            hasUnsavedChanges: false,
            createdReturnId: result.returnId,
          ),
        );
        return;
      }

      final submitted = state;
      final createdId = await _dao.transaction(() async {
        final refreshed = await _refreshLocalPricing(submitted);
        if (pricingPreviewFingerprint(
              submitted.pricing,
              taxInclusive: submitted.taxInclusivePricing,
            ) !=
            pricingPreviewFingerprint(
              refreshed.pricing,
              taxInclusive: refreshed.taxInclusivePricing,
            )) {
          throw _LocalPurchaseReturnPricingChanged(refreshed);
        }
        // Return number is generated atomically by the DAO inside the transaction
        // Preserve the pricing mode used by the form.
        final returnData = PurchaseReturnAdjustmentsCompanion.insert(
          returnNumber: '', // Overridden by DAO inside transaction
          supplierId: submitted.supplierId!,
          currencyId: submitted.currencyId,
          subtotalCents: Value(Decimal.fromInt(submitted.totalSubtotalCents)),
          discountCents: Value(
            Decimal.fromInt(
              submitted.totalItemDiscountCents +
                  submitted.effectiveOverallDiscountCents,
            ),
          ),
          taxCents: Value(Decimal.fromInt(submitted.totalAdjustedTaxCents)),
          totalCents: Decimal.fromInt(submitted.totalCents),
          notes: Value(
            buildAdjReturnNotes(
              reasonCode: submitted.reasonCode!,
              userNotes: submitted.notes,
            ),
          ),
          returnDate: Value(submitted.returnDate),
          refundMethod: Value(
            event.settlementAllocations.isEmpty
                ? submitted.paymentMethod.name
                : 'mixed',
          ),
          dueDate: Value(
            event.settlementAllocations.isEmpty ? submitted.dueDate : null,
          ),
          idempotencyKey: Value(idempotencyKey),
        ).withPricingSnapshot(taxInclusive: submitted.taxInclusivePricing);

        // The engine has already done all the hard work: per-line subtotal,
        // per-line item discount, the proportional share of the invoice-
        // level discount, the post-allocation net, and the tax computed on
        // that net. We just persist what the engine produced — there is no
        // second arithmetic path here, which is the whole point of Phase 1.
        final pricing = submitted.pricing;
        final itemCompanions = <PurchaseReturnAdjustmentItemsCompanion>[];
        for (int idx = 0; idx < submitted.items.length; idx++) {
          final item = submitted.items[idx];
          final line = pricing.lines[idx];
          itemCompanions.add(
            PurchaseReturnAdjustmentItemsCompanion.insert(
              returnId: 0, // Will be set by DAO
              productId: item.productId,
              variantId: Value(item.variantId),
              quantity: item.quantity,
              quantityScale: Value(item.quantityScale),
              measurementType: Value(item.measurementType),
              unitPriceCents: Decimal.fromInt(item.unitPriceCents),
              // Total discount on this item = per-line discount + share of overall
              discountCents: Value(
                Decimal.fromInt(line.totalLineDiscount.cents),
              ),
              taxCents: Value(Decimal.fromInt(line.tax.cents)),
              totalCents: Decimal.fromInt(line.total.cents),
              reason: Value(item.reason),
            ),
          );
        }

        return _dao.createAndPostPurchaseAdjReturn(
          returnData,
          itemCompanions,
          journalEntryService: _journalEntryService,
          allowNegativeStock: event.allowNegativeStock,
          settlementAllocations: event.settlementAllocations,
        );
      });

      emit(
        state.copyWith(
          isSubmitting: false,
          isSuccess: true,
          hasUnsavedChanges: false,
          createdReturnId: createdId,
        ),
      );
    } on _LocalPurchaseReturnPricingChanged catch (e) {
      _taxPolicy = null;
      emit(
        state.copyWith(
          items: e.preview.items,
          isSubmitting: false,
          error: 'returns.pricing_preview_updated'.tr(),
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
    } on LanBusinessException catch (e) {
      if (e.code == 'pricing_preview_changed') {
        try {
          _taxPolicy = null;
          final policy = await (_taxPolicy = _loadTaxPolicy());
          final refreshed = <AdjReturnLineItem>[];
          for (final item in state.items) {
            final page = await _lan!.fetchRemoteCatalog(
              query: item.productName,
              limit: 200,
              management: true,
            );
            final product = page.products.firstWhere(
              (p) => p.id == item.productId,
            );
            refreshed.add(
              item.copyWith(
                taxRateBps: policy.enableTaxCalculations
                    ? TaxCalculationService.resolveLineItemTaxRateBps(
                        isTaxable: product.isTaxable,
                        productTaxRateBps: product.purchaseTaxRateBps,
                        defaultTaxRateBps: (policy.defaultPurchaseTaxRate * 100)
                            .round(),
                      )
                    : 0,
                taxInclusivePricing: policy.taxInclusivePricing,
              ),
            );
          }
          emit(
            state.copyWith(
              items: refreshed,
              isSubmitting: false,
              error: 'returns.pricing_preview_updated'.tr(),
            ),
          );
        } catch (_) {
          _taxPolicy = null;
          emit(
            state.copyWith(
              isSubmitting: false,
              error: 'returns.pricing_preview_refresh_failed'.tr(),
            ),
          );
        }
      } else {
        emit(
          state.copyWith(
            isSubmitting: false,
            error: 'returns.return_failed'.tr(),
          ),
        );
      }
    } catch (e, st) {
      developer.log(
        'Purchase adjustment return submission failed: $e',
        name: 'PurchaseAdjReturnFormBloc',
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
