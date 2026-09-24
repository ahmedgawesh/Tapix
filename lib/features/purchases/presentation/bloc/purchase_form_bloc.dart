import 'package:decimal/decimal.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../../core/services/inventory/purchase_supplier_source_service.dart';
import '../../../../core/services/inventory/supplier_identity_rules.dart';
import '../../../../core/services/inventory/supplier_product_identity_service.dart';
import '../../../../core/services/inventory/supplier_purchase_source_policy.dart';

import '../../../../core/money/money.dart';
import '../../../../core/database/daos/pharmacy_dao.dart';
import '../../../../core/payments/checkout_settlement.dart';
import '../../../../core/pricing/discount.dart';
import '../../../../core/pricing/invoice_pricing_engine.dart';
import '../../../../core/pricing/line_item_pricing_engine.dart';
import '../../../../core/services/crashlytics_service.dart';
import '../../../../core/services/purchases/original_price_resolver.dart';
import '../../domain/repositories/purchase_repository.dart';
import '../../../products/domain/entities/product_entity.dart';
import '../../../products/domain/entities/product_variant_entity.dart';
import '../../../products/domain/repositories/product_repository.dart';
import '../../../products/domain/repositories/product_variant_repository.dart';

// ==================== ENUMS ====================

/// Discount mode: per-item discounts or a single invoice-level discount
enum DiscountMode { perItem, invoice }

/// Payment method for purchase invoice
enum PurchasePaymentMethod { cash, credit, card, cheque, purchaseOrder }

/// How to handle overpayment when paid amount exceeds invoice total
enum OverpaymentHandling {
  /// Return the excess as change to the party
  returnChange,

  /// Add the excess to the party's credit balance
  addToBalance,
}

// ==================== STATE ====================

class PurchaseFormState extends Equatable {
  final int? purchaseId;
  final String? purchaseNumber;
  final int? supplierId;
  final String? supplierName;
  final int currencyId;
  final List<PurchaseLineItem> items;
  final DiscountMode discountMode;
  final Decimal invoiceDiscountCents;
  final String? supplierInvoiceRef;
  final String? notes;
  final DateTime purchaseDate;
  final DateTime? dueDate;
  final PurchasePaymentMethod paymentMethod;
  final Decimal taxRatePercent;
  final Decimal paidAmountCents;
  final OverpaymentHandling overpaymentHandling;
  final bool isSubmitting;
  final String? error;
  final bool isSuccess;
  final bool hasUnsavedChanges;
  // Global tax settings
  final bool enableTaxCalculations;
  final int defaultPurchaseTaxRateBps;
  final bool taxInclusivePricing;
  // Editing posted purchase flag
  final bool isEditingPosted;
  final bool pharmacyFeaturesEnabled;
  final bool useSupplierProductCodes;
  final Map<String, SupplierIdentityPreview> supplierSourcePreviews;
  final Map<String, String> supplierSourceErrors;
  final bool isResolvingSupplierSources;

  PurchaseFormState({
    this.purchaseId,
    this.purchaseNumber,
    this.supplierId,
    this.supplierName,
    required this.currencyId,
    this.items = const [],
    this.discountMode = DiscountMode.perItem,
    Decimal? invoiceDiscountCents,
    this.supplierInvoiceRef,
    this.notes,
    required this.purchaseDate,
    this.dueDate,
    this.paymentMethod = PurchasePaymentMethod.cash,
    Decimal? taxRatePercent,
    Decimal? paidAmountCents,
    this.overpaymentHandling = OverpaymentHandling.returnChange,
    this.isSubmitting = false,
    this.error,
    this.isSuccess = false,
    this.hasUnsavedChanges = false,
    this.enableTaxCalculations = true,
    this.defaultPurchaseTaxRateBps = 0,
    this.taxInclusivePricing = false,
    this.isEditingPosted = false,
    this.pharmacyFeaturesEnabled = false,
    this.useSupplierProductCodes = false,
    this.supplierSourcePreviews = const {},
    this.supplierSourceErrors = const {},
    this.isResolvingSupplierSources = false,
  }) : invoiceDiscountCents = invoiceDiscountCents ?? Decimal.zero,
       taxRatePercent = taxRatePercent ?? Decimal.zero,
       paidAmountCents = paidAmountCents ?? Decimal.zero;

  // ── Engine-backed invoice math ─────────────────────────────────────────
  // Single source of truth: every `*Cents` getter that represents a
  // financial figure (subtotal, discount, tax, total) is derived from
  // exactly one call to [InvoicePricingEngine.compute]. Memoized once per
  // state instance so the cost is amortized across the many getter calls
  // the UI does per rebuild.
  //
  // The tender layer (paid / remaining / change) and pure quantity rollups
  // are intentionally NOT part of the engine — they belong to the bloc per
  // ADR `docs/adr/0002-engine-readiness-audit.md` §3.

  /// Lazy memoized engine result. Built on first access and reused for
  /// the lifetime of this immutable state instance.
  ///
  /// Phase-5 close-out: the Phase-3 dual-compute `kDebugMode` assertion
  /// has been removed after a full phase of green Phase-0 goldens and
  /// Phase-3 regression tests. The engine is now the unconditional SoT.
  late final InvoicePricingResult pricing = _computePricing();

  InvoicePricingResult _computePricing() {
    // Discount-mode bridge per ADR 0002 §G7:
    //   * `perItem`  → per-line discount preserved, overall = none.
    //   * `invoice`  → per-line discount suppressed (Q3 mode-exclusivity),
    //                  overall = invoice-level discount.
    // This matches the legacy `TaxCalculationService.calculateInvoiceTax`
    // contract used at submission time (which also zeros per-line
    // discounts in invoice mode) so the engine output stays identical to
    // what the bloc previously persisted.
    final inInvoiceMode = discountMode == DiscountMode.invoice;
    final lineInputs = items
        .map(
          (i) => i.toPricingInput(
            overrideDiscount: inInvoiceMode ? Discount.none : null,
          ),
        )
        .toList(growable: false);

    return InvoicePricingEngine.compute(
      InvoicePricingInput(
        lines: lineInputs,
        overallDiscount: inInvoiceMode
            ? _buildOverallDiscount()
            : Discount.none,
        enableTaxCalculations: enableTaxCalculations,
        defaultTaxRateBps: defaultPurchaseTaxRateBps,
        taxInclusivePricing: taxInclusivePricing,
      ),
    );
  }

  Discount _buildOverallDiscount() {
    // Single source of truth: the fixed-cents amount the user committed is
    // the authoritative invoice-level discount — matching `SaleFormState`.
    // The percentage shown in the UI is a pure display helper that is
    // converted to cents before reaching the bloc; it must NOT re-derive
    // the discount here, otherwise a fixed `405.00` input gets silently
    // rewritten to e.g. `5.01 %` → `405.31` (the rounding drift bug).
    if (invoiceDiscountCents > Decimal.zero) {
      return Discount.fixed(Money.fromDecimalCents(invoiceDiscountCents));
    }
    return Discount.none;
  }

  Decimal get subtotalCents => pricing.subtotal.decimalCents;

  /// Sum of user-entered per-line discounts as displayed in the UI.
  /// In `invoice` mode this is always zero because `_onDiscountModeChanged`
  /// (Phase-14) wipes every line's `discountCents` on mode switch, and the
  /// per-line discount input is gated to `perItem` mode. The engine also
  /// masks per-line discounts at compute time for defence-in-depth (per
  /// Q3 mode-exclusivity) — but state is the single SoT.
  Decimal get itemDiscountCents =>
      items.fold(Decimal.zero, (sum, item) => sum + item.discountCents);

  /// Invoice-level discount actually applied. The engine clamps both
  /// fixed and percent paths to `[0, subtotal]` so this value can never
  /// exceed subtotal — matching the IFRS-correct accounting behavior.
  Decimal get effectiveInvoiceDiscountCents {
    if (discountMode != DiscountMode.invoice) return invoiceDiscountCents;
    return pricing.overallDiscount.decimalCents;
  }

  Decimal get totalDiscountCents {
    if (discountMode == DiscountMode.invoice) {
      return effectiveInvoiceDiscountCents;
    }
    return itemDiscountCents;
  }

  Decimal get itemTaxCents => pricing.tax.decimalCents;

  Decimal get taxCents => itemTaxCents;

  Decimal get totalCents => pricing.total.decimalCents;

  // ── Tender layer (NOT part of the pricing engine by design) ────────────

  Decimal get remainingCents {
    final r = totalCents - paidAmountCents;
    return r < Decimal.zero ? Decimal.zero : r;
  }

  Decimal get changeCents {
    final change = paidAmountCents - totalCents;
    return change > Decimal.zero ? change : Decimal.zero;
  }

  int get totalQuantity => items.fold(0, (sum, item) => sum + item.quantity);

  bool get isDraft => purchaseId == null;

  PurchaseFormState copyWith({
    int? purchaseId,
    String? purchaseNumber,
    int? supplierId,
    String? supplierName,
    int? currencyId,
    List<PurchaseLineItem>? items,
    DiscountMode? discountMode,
    Decimal? invoiceDiscountCents,
    String? supplierInvoiceRef,
    String? notes,
    DateTime? purchaseDate,
    DateTime? dueDate,
    PurchasePaymentMethod? paymentMethod,
    Decimal? taxRatePercent,
    Decimal? paidAmountCents,
    OverpaymentHandling? overpaymentHandling,
    bool? isSubmitting,
    String? error,
    bool? isSuccess,
    bool clearDueDate = false,
    bool? hasUnsavedChanges,
    bool? enableTaxCalculations,
    int? defaultPurchaseTaxRateBps,
    bool? taxInclusivePricing,
    bool? isEditingPosted,
    bool? pharmacyFeaturesEnabled,
    bool? useSupplierProductCodes,
    Map<String, SupplierIdentityPreview>? supplierSourcePreviews,
    Map<String, String>? supplierSourceErrors,
    bool? isResolvingSupplierSources,
  }) {
    return PurchaseFormState(
      purchaseId: purchaseId ?? this.purchaseId,
      purchaseNumber: purchaseNumber ?? this.purchaseNumber,
      supplierId: supplierId ?? this.supplierId,
      supplierName: supplierName ?? this.supplierName,
      currencyId: currencyId ?? this.currencyId,
      items: items ?? this.items,
      discountMode: discountMode ?? this.discountMode,
      invoiceDiscountCents: invoiceDiscountCents ?? this.invoiceDiscountCents,
      supplierInvoiceRef: supplierInvoiceRef ?? this.supplierInvoiceRef,
      notes: notes ?? this.notes,
      purchaseDate: purchaseDate ?? this.purchaseDate,
      dueDate: clearDueDate ? null : (dueDate ?? this.dueDate),
      paymentMethod: paymentMethod ?? this.paymentMethod,
      taxRatePercent: taxRatePercent ?? this.taxRatePercent,
      paidAmountCents: paidAmountCents ?? this.paidAmountCents,
      overpaymentHandling: overpaymentHandling ?? this.overpaymentHandling,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      error: error,
      isSuccess: isSuccess ?? this.isSuccess,
      hasUnsavedChanges: hasUnsavedChanges ?? this.hasUnsavedChanges,
      enableTaxCalculations:
          enableTaxCalculations ?? this.enableTaxCalculations,
      defaultPurchaseTaxRateBps:
          defaultPurchaseTaxRateBps ?? this.defaultPurchaseTaxRateBps,
      taxInclusivePricing: taxInclusivePricing ?? this.taxInclusivePricing,
      isEditingPosted: isEditingPosted ?? this.isEditingPosted,
      useSupplierProductCodes:
          useSupplierProductCodes ?? this.useSupplierProductCodes,
      supplierSourcePreviews:
          supplierSourcePreviews ?? this.supplierSourcePreviews,
      supplierSourceErrors: supplierSourceErrors ?? this.supplierSourceErrors,
      isResolvingSupplierSources:
          isResolvingSupplierSources ?? this.isResolvingSupplierSources,
      pharmacyFeaturesEnabled:
          pharmacyFeaturesEnabled ?? this.pharmacyFeaturesEnabled,
    );
  }

  @override
  List<Object?> get props => [
    purchaseId,
    purchaseNumber,
    supplierId,
    supplierName,
    currencyId,
    items,
    discountMode,
    invoiceDiscountCents,
    supplierInvoiceRef,
    notes,
    purchaseDate,
    dueDate,
    paymentMethod,
    taxRatePercent,
    paidAmountCents,
    overpaymentHandling,
    isSubmitting,
    error,
    isSuccess,
    hasUnsavedChanges,
    enableTaxCalculations,
    defaultPurchaseTaxRateBps,
    taxInclusivePricing,
    isEditingPosted,
    pharmacyFeaturesEnabled,
    useSupplierProductCodes,
    supplierSourcePreviews,
    supplierSourceErrors,
    isResolvingSupplierSources,
  ];
}

/// A line item in the purchase form
class PurchaseLineItem extends Equatable {
  final String tempId;
  final Product product;
  final ProductVariant? variant;
  final int quantity;
  final Decimal unitCostCents;
  final Decimal discountCents;
  final DateTime? expiryDate;
  final String? manufacturerLotNumber;
  final bool isMedicine;
  final String? colorName;
  final String? colorHex;
  final String? sizeName;

  /// Display value for "old cost" in the bottom-sheet. Always populated via
  /// [OriginalPriceResolver]; never null even for brand-new variants.
  final int originalCostCents;

  /// Display value for "old sell price". See [originalCostCents].
  final int originalPriceCents;

  /// Display value for "old wholesale price". `null` means no wholesale
  /// price is configured (genuine absence, not default-init `0`).
  final int? originalWholesalePriceCents;

  /// Snapshot of cost to PERSIST as `original_cost_cents` on the purchase
  /// row. `null` when there is no real historical cost worth freezing
  /// (default-init variant whose live cost is still `0`). Persisting `null`
  /// instead of `0` lets a future re-load fall back through the
  /// [OriginalPriceResolver] chain rather than displaying `0.00`.
  final int? persistOriginalCostCents;

  /// Snapshot of retail price to PERSIST. See [persistOriginalCostCents].
  final int? persistOriginalPriceCents;

  /// Snapshot of wholesale price to PERSIST. See [persistOriginalCostCents].
  final int? persistOriginalWholesalePriceCents;

  final Decimal? newSellPriceCents;
  final Decimal? newWholesalePriceCents;

  PurchaseLineItem({
    required this.tempId,
    required this.product,
    this.variant,
    required this.quantity,
    required this.unitCostCents,
    Decimal? discountCents,
    this.expiryDate,
    this.manufacturerLotNumber,
    this.isMedicine = false,
    this.colorName,
    this.colorHex,
    this.sizeName,
    required this.originalCostCents,
    required this.originalPriceCents,
    this.originalWholesalePriceCents,
    this.persistOriginalCostCents,
    this.persistOriginalPriceCents,
    this.persistOriginalWholesalePriceCents,
    this.newSellPriceCents,
    this.newWholesalePriceCents,
  }) : discountCents = discountCents ?? Decimal.zero;

  // ── Engine-backed line math ────────────────────────────────────────────
  // Per-line totals flow through [LineItemPricingEngine] so there is
  // exactly one place where `subtotal → discount → net → tax → total`
  // is computed. Decimal return types are preserved for UI/PDF/repo
  // compatibility (consumers call `.toBigInt().toInt()` on the result).

  /// Build the engine input for this line. [overrideDiscount] lets the
  /// owning state suppress the per-line discount when the invoice-level
  /// discount mode is active (ADR 0002 §G7 mode-exclusivity bridge).
  LineItemPricingInput toPricingInput({Discount? overrideDiscount}) {
    return LineItemPricingInput(
      unitPrice: Money.fromDecimalCents(unitCostCents),
      quantity: quantity,
      quantityScale: product.quantityScale,
      discount:
          overrideDiscount ??
          (discountCents > Decimal.zero
              ? Discount.fixed(Money.fromDecimalCents(discountCents))
              : Discount.none),
      isTaxable: product.isTaxable,
      productTaxRateBps: product.purchaseTaxRateBps,
    );
  }

  /// Local (line-scoped) engine result. Uses the same contract as the
  /// historical getters: tax always enabled, no global default rate, no
  /// tax-inclusive pricing. The state-level engine in [PurchaseFormState]
  /// is where global settings are honored.
  LineItemPricingResult _localCompute() => LineItemPricingEngine.compute(
    input: toPricingInput(),
    enableTaxCalculations: true,
    defaultTaxRateBps: 0,
    taxInclusivePricing: false,
  );

  Decimal get subtotalCents => _localCompute().subtotal.decimalCents;

  Decimal get netCents => _localCompute().net.decimalCents;

  /// Tax is computed from the product's purchase tax rate.
  /// This getter uses product settings — use [taxCentsWithSettings] for
  /// global-settings-aware computation.
  Decimal get taxCents => _localCompute().tax.decimalCents;

  /// Calculate tax respecting global settings.
  /// If [enableTaxCalculations] is false, returns zero.
  /// If product has its own tax rate (isTaxable && purchaseTaxRateBps > 0),
  /// uses that. Otherwise, falls back to [defaultTaxRateBps].
  Decimal taxCentsWithSettings({
    required bool enableTaxCalculations,
    required int defaultTaxRateBps,
    bool taxInclusivePricing = false,
  }) {
    return LineItemPricingEngine.compute(
      input: toPricingInput(),
      enableTaxCalculations: enableTaxCalculations,
      defaultTaxRateBps: defaultTaxRateBps,
      taxInclusivePricing: taxInclusivePricing,
    ).tax.decimalCents;
  }

  Decimal get totalCents => _localCompute().total.decimalCents;

  String get displayName {
    final parts = <String>[];
    if (colorName != null) parts.add(colorName!);
    if (sizeName != null) parts.add(sizeName!);
    if (parts.isEmpty && variant != null) {
      parts.add(variant!.sku ?? 'Variant ${variant!.id}');
    }
    if (parts.isNotEmpty) {
      return '${product.name} (${parts.join(' / ')})';
    }
    return product.name;
  }

  /// Manufacturer lot numbers are a medicine receiving requirement only.
  /// Ordinary products may still use batch tracking without being treated as
  /// medicines when pharmacy features are enabled for the business.
  bool get requiresManufacturerLot =>
      isMedicine &&
      product.trackInventory &&
      product.inventoryTrackingType != 'standard';

  PurchaseLineItem copyWith({
    String? tempId,
    Product? product,
    ProductVariant? variant,
    int? quantity,
    Decimal? unitCostCents,
    Decimal? discountCents,
    DateTime? expiryDate,
    bool clearExpiry = false,
    String? manufacturerLotNumber,
    bool clearManufacturerLotNumber = false,
    bool? isMedicine,
    String? colorName,
    String? colorHex,
    String? sizeName,
    int? originalCostCents,
    int? originalPriceCents,
    int? originalWholesalePriceCents,
    int? persistOriginalCostCents,
    int? persistOriginalPriceCents,
    int? persistOriginalWholesalePriceCents,
    Decimal? newSellPriceCents,
    Decimal? newWholesalePriceCents,
    bool clearNewSellPrice = false,
    bool clearNewWholesalePrice = false,
  }) {
    return PurchaseLineItem(
      tempId: tempId ?? this.tempId,
      product: product ?? this.product,
      variant: variant ?? this.variant,
      quantity: quantity ?? this.quantity,
      unitCostCents: unitCostCents ?? this.unitCostCents,
      discountCents: discountCents ?? this.discountCents,
      expiryDate: clearExpiry ? null : (expiryDate ?? this.expiryDate),
      manufacturerLotNumber: clearManufacturerLotNumber
          ? null
          : (manufacturerLotNumber ?? this.manufacturerLotNumber),
      isMedicine: isMedicine ?? this.isMedicine,
      colorName: colorName ?? this.colorName,
      colorHex: colorHex ?? this.colorHex,
      sizeName: sizeName ?? this.sizeName,
      originalCostCents: originalCostCents ?? this.originalCostCents,
      originalPriceCents: originalPriceCents ?? this.originalPriceCents,
      originalWholesalePriceCents:
          originalWholesalePriceCents ?? this.originalWholesalePriceCents,
      persistOriginalCostCents:
          persistOriginalCostCents ?? this.persistOriginalCostCents,
      persistOriginalPriceCents:
          persistOriginalPriceCents ?? this.persistOriginalPriceCents,
      persistOriginalWholesalePriceCents:
          persistOriginalWholesalePriceCents ??
          this.persistOriginalWholesalePriceCents,
      newSellPriceCents: clearNewSellPrice
          ? null
          : (newSellPriceCents ?? this.newSellPriceCents),
      newWholesalePriceCents: clearNewWholesalePrice
          ? null
          : (newWholesalePriceCents ?? this.newWholesalePriceCents),
    );
  }

  @override
  List<Object?> get props => [
    tempId,
    product,
    variant,
    quantity,
    unitCostCents,
    discountCents,
    expiryDate,
    manufacturerLotNumber,
    isMedicine,
    colorName,
    colorHex,
    sizeName,
    originalCostCents,
    originalPriceCents,
    originalWholesalePriceCents,
    persistOriginalCostCents,
    persistOriginalPriceCents,
    persistOriginalWholesalePriceCents,
    newSellPriceCents,
    newWholesalePriceCents,
  ];
}

// ==================== EVENTS ====================

abstract class PurchaseFormEvent extends Equatable {
  const PurchaseFormEvent();

  @override
  List<Object?> get props => [];
}

class PurchaseFormInitialized extends PurchaseFormEvent {
  final int? purchaseId;
  final int currencyId;
  final bool enableTaxCalculations;
  final int defaultPurchaseTaxRateBps;
  final bool taxInclusivePricing;
  final bool isEditingPosted;
  final bool pharmacyFeaturesEnabled;
  final bool useSupplierProductCodes;

  const PurchaseFormInitialized({
    this.purchaseId,
    required this.currencyId,
    this.enableTaxCalculations = true,
    this.defaultPurchaseTaxRateBps = 0,
    this.taxInclusivePricing = false,
    this.isEditingPosted = false,
    this.pharmacyFeaturesEnabled = false,
    this.useSupplierProductCodes = false,
  });

  @override
  List<Object?> get props => [
    purchaseId,
    currencyId,
    enableTaxCalculations,
    defaultPurchaseTaxRateBps,
    taxInclusivePricing,
    isEditingPosted,
    pharmacyFeaturesEnabled,
    useSupplierProductCodes,
  ];
}

class PurchaseTaxSettingsChanged extends PurchaseFormEvent {
  final bool enableTaxCalculations;
  final int defaultPurchaseTaxRateBps;
  final bool taxInclusivePricing;
  const PurchaseTaxSettingsChanged({
    required this.enableTaxCalculations,
    required this.defaultPurchaseTaxRateBps,
    this.taxInclusivePricing = false,
  });

  @override
  List<Object?> get props => [
    enableTaxCalculations,
    defaultPurchaseTaxRateBps,
    taxInclusivePricing,
  ];
}

class PurchaseSupplierChanged extends PurchaseFormEvent {
  final int supplierId;
  final String? supplierName;
  const PurchaseSupplierChanged(this.supplierId, {this.supplierName});

  @override
  List<Object?> get props => [supplierId, supplierName];
}

class PurchaseDateChanged extends PurchaseFormEvent {
  final DateTime date;
  const PurchaseDateChanged(this.date);

  @override
  List<Object?> get props => [date];
}

class PurchaseDueDateChanged extends PurchaseFormEvent {
  final DateTime? dueDate;
  const PurchaseDueDateChanged(this.dueDate);

  @override
  List<Object?> get props => [dueDate];
}

class PurchaseNotesChanged extends PurchaseFormEvent {
  final String notes;
  const PurchaseNotesChanged(this.notes);

  @override
  List<Object?> get props => [notes];
}

class PurchaseSupplierRefChanged extends PurchaseFormEvent {
  final String ref;
  const PurchaseSupplierRefChanged(this.ref);

  @override
  List<Object?> get props => [ref];
}

class PurchaseDiscountModeChanged extends PurchaseFormEvent {
  final DiscountMode mode;
  const PurchaseDiscountModeChanged(this.mode);

  @override
  List<Object?> get props => [mode];
}

class PurchaseInvoiceDiscountChanged extends PurchaseFormEvent {
  final Decimal discountCents;
  const PurchaseInvoiceDiscountChanged(this.discountCents);

  @override
  List<Object?> get props => [discountCents];
}

class PurchaseLineItemAdded extends PurchaseFormEvent {
  final Product product;
  final ProductVariant? variant;
  final int quantity;
  final Decimal unitCostCents;
  final Decimal? discountCents;
  final DateTime? expiryDate;
  final String? manufacturerLotNumber;

  const PurchaseLineItemAdded({
    required this.product,
    this.variant,
    required this.quantity,
    required this.unitCostCents,
    this.discountCents,
    this.expiryDate,
    this.manufacturerLotNumber,
  });

  @override
  List<Object?> get props => [
    product,
    variant,
    quantity,
    unitCostCents,
    discountCents,
    expiryDate,
    manufacturerLotNumber,
  ];
}

class PurchaseLineItemUpdated extends PurchaseFormEvent {
  final String tempId;
  final int? quantity;
  final Decimal? unitCostCents;
  final Decimal? discountCents;
  final DateTime? expiryDate;
  final bool clearExpiry;
  final String? manufacturerLotNumber;
  final bool clearManufacturerLotNumber;
  final Decimal? newSellPriceCents;
  final Decimal? newWholesalePriceCents;

  const PurchaseLineItemUpdated({
    required this.tempId,
    this.quantity,
    this.unitCostCents,
    this.discountCents,
    this.expiryDate,
    this.clearExpiry = false,
    this.manufacturerLotNumber,
    this.clearManufacturerLotNumber = false,
    this.newSellPriceCents,
    this.newWholesalePriceCents,
  });

  @override
  List<Object?> get props => [
    tempId,
    quantity,
    unitCostCents,
    discountCents,
    expiryDate,
    clearExpiry,
    manufacturerLotNumber,
    clearManufacturerLotNumber,
    newSellPriceCents,
    newWholesalePriceCents,
  ];
}

class PurchaseLineItemRemoved extends PurchaseFormEvent {
  final String tempId;
  const PurchaseLineItemRemoved(this.tempId);

  @override
  List<Object?> get props => [tempId];
}

class PurchaseFormSubmitted extends PurchaseFormEvent {
  final CheckoutSettlement? settlement;

  const PurchaseFormSubmitted({this.settlement});

  @override
  List<Object?> get props => [settlement];
}

class PurchaseFormPosted extends PurchaseFormEvent {
  const PurchaseFormPosted();
}

class PurchasePaymentMethodChanged extends PurchaseFormEvent {
  final PurchasePaymentMethod method;
  const PurchasePaymentMethodChanged(this.method);

  @override
  List<Object?> get props => [method];
}

class PurchaseTaxRateChanged extends PurchaseFormEvent {
  final Decimal taxRatePercent;
  const PurchaseTaxRateChanged(this.taxRatePercent);

  @override
  List<Object?> get props => [taxRatePercent];
}

class PurchasePaidAmountChanged extends PurchaseFormEvent {
  final Decimal paidAmountCents;
  const PurchasePaidAmountChanged(this.paidAmountCents);

  @override
  List<Object?> get props => [paidAmountCents];
}

class PurchaseOverpaymentHandlingChanged extends PurchaseFormEvent {
  final OverpaymentHandling handling;
  const PurchaseOverpaymentHandlingChanged(this.handling);

  @override
  List<Object?> get props => [handling];
}

// ==================== BLOC ====================

class PurchaseFormBloc extends Bloc<PurchaseFormEvent, PurchaseFormState> {
  final PurchaseRepository _repository;
  final ProductVariantRepository _variantRepository;
  final ProductRepository _productRepository;
  final PharmacyDao? _pharmacyDao;
  final PurchaseSupplierSourcePreviewer? _supplierSourcePreviewer;
  int _sourcePreviewGeneration = 0;
  int _lineCounter = 0;
  Set<int> _medicineProductIds = const {};

  // Cached color/size lookup maps
  Map<int, String> _colorNames = {};
  Map<int, String?> _colorHexes = {};
  Map<int, String> _sizeNames = {};

  PurchaseFormBloc(
    this._repository,
    this._variantRepository,
    this._productRepository, {
    PharmacyDao? pharmacyDao,
    PurchaseSupplierSourcePreviewer? supplierSourcePreviewer,
  }) : _pharmacyDao = pharmacyDao,
       _supplierSourcePreviewer = supplierSourcePreviewer,
       super(PurchaseFormState(currencyId: 1, purchaseDate: DateTime.now())) {
    on<PurchaseFormInitialized>(_onInitialized);
    on<PurchaseSupplierChanged>(_onSupplierChanged);
    on<PurchaseDateChanged>(_onDateChanged);
    on<PurchaseDueDateChanged>(_onDueDateChanged);
    on<PurchaseNotesChanged>(_onNotesChanged);
    on<PurchaseSupplierRefChanged>(_onSupplierRefChanged);
    on<PurchaseDiscountModeChanged>(_onDiscountModeChanged);
    on<PurchaseInvoiceDiscountChanged>(_onInvoiceDiscountChanged);
    on<PurchaseLineItemAdded>(_onLineItemAdded);
    on<PurchaseLineItemUpdated>(_onLineItemUpdated);
    on<PurchaseLineItemRemoved>(_onLineItemRemoved);
    on<PurchaseFormSubmitted>(_onSubmitted);
    on<PurchaseFormPosted>(_onPosted);
    on<PurchasePaymentMethodChanged>(_onPaymentMethodChanged);
    on<PurchaseTaxRateChanged>(_onTaxRateChanged);
    on<PurchasePaidAmountChanged>(_onPaidAmountChanged);
    on<PurchaseOverpaymentHandlingChanged>(_onOverpaymentHandlingChanged);
    on<PurchaseTaxSettingsChanged>(_onTaxSettingsChanged);
  }

  Future<void> _loadColorSizeLookups() async {
    if (_colorNames.isNotEmpty) return;
    try {
      final colors = await _variantRepository.getAllColors();
      _colorNames = {for (final c in colors) c.id: c.name};
      _colorHexes = {for (final c in colors) c.id: c.hexCode};
      final sizes = await _variantRepository.getAllSizes();
      _sizeNames = {for (final s in sizes) s.id: s.name};
    } catch (_) {}
  }

  Future<void> _loadMedicineProductIds(bool pharmacyFeaturesEnabled) async {
    if (!pharmacyFeaturesEnabled || _pharmacyDao == null) {
      _medicineProductIds = const {};
      return;
    }
    try {
      _medicineProductIds = await _pharmacyDao.getMedicineProductIds();
    } catch (_) {
      // Do not block receiving if an old/corrupt pharmacy profile cannot be
      // read. The submit path still validates every medicine we did resolve.
      _medicineProductIds = const {};
    }
  }

  String? _resolveColorName(int? colorId) =>
      colorId != null ? _colorNames[colorId] : null;
  String? _resolveColorHex(int? colorId) =>
      colorId != null ? _colorHexes[colorId] : null;
  String? _resolveSizeName(int? sizeId) =>
      sizeId != null ? _sizeNames[sizeId] : null;

  String _generateTempId() {
    _lineCounter++;
    return 'line_$_lineCounter';
  }

  PurchasePaymentMethod _parsePaymentMethod(String? raw) {
    switch (raw) {
      case 'cash':
        return PurchasePaymentMethod.cash;
      case 'credit':
        return PurchasePaymentMethod.credit;
      case 'card':
        return PurchasePaymentMethod.card;
      case 'cheque':
        return PurchasePaymentMethod.cheque;
      case 'purchaseOrder':
        return PurchasePaymentMethod.purchaseOrder;
      default:
        return PurchasePaymentMethod.cash;
    }
  }

  Future<void> _onInitialized(
    PurchaseFormInitialized event,
    Emitter<PurchaseFormState> emit,
  ) async {
    await _loadColorSizeLookups();
    await _loadMedicineProductIds(event.pharmacyFeaturesEnabled);

    if (event.purchaseId == null) {
      // New purchase: generate next invoice number
      try {
        final nextNumber = await _repository.generatePurchaseNumber();
        emit(
          state.copyWith(
            currencyId: event.currencyId,
            useSupplierProductCodes: SupplierPurchaseSourcePolicy.enabled(
              event.useSupplierProductCodes,
            ),
            purchaseNumber: nextNumber,
            enableTaxCalculations: event.enableTaxCalculations,
            defaultPurchaseTaxRateBps: event.defaultPurchaseTaxRateBps,
            taxInclusivePricing: event.taxInclusivePricing,
            pharmacyFeaturesEnabled: event.pharmacyFeaturesEnabled,
          ),
        );
      } catch (_) {
        emit(
          state.copyWith(
            currencyId: event.currencyId,
            useSupplierProductCodes: SupplierPurchaseSourcePolicy.enabled(
              event.useSupplierProductCodes,
            ),
            enableTaxCalculations: event.enableTaxCalculations,
            defaultPurchaseTaxRateBps: event.defaultPurchaseTaxRateBps,
            taxInclusivePricing: event.taxInclusivePricing,
            pharmacyFeaturesEnabled: event.pharmacyFeaturesEnabled,
          ),
        );
      }
      return;
    }

    emit(
      state.copyWith(
        purchaseId: event.purchaseId,
        currencyId: event.currencyId,
        enableTaxCalculations: event.enableTaxCalculations,
        defaultPurchaseTaxRateBps: event.defaultPurchaseTaxRateBps,
        taxInclusivePricing: event.taxInclusivePricing,
        isEditingPosted: event.isEditingPosted,
        pharmacyFeaturesEnabled: event.pharmacyFeaturesEnabled,
      ),
    );

    try {
      final purchase = await _repository.getPurchaseById(event.purchaseId!);
      if (purchase == null) {
        emit(state.copyWith(error: 'purchases.not_found'));
        return;
      }

      final items = await _repository.getPurchaseItems(event.purchaseId!);
      _lineCounter = items.length;

      // Fetch real variant data for color/size resolution
      final variantFutures = <int, Future<ProductVariant?>>{};
      final defaultVariantFutures = <int, Future<ProductVariant?>>{};
      final productIds = <int>{};
      for (final i in items) {
        productIds.add(i.productId);
        if (i.variantId != null && !variantFutures.containsKey(i.variantId)) {
          variantFutures[i.variantId!] = _variantRepository.getVariantById(
            i.variantId!,
          );
        }
        if (i.variantId == null &&
            !defaultVariantFutures.containsKey(i.productId)) {
          defaultVariantFutures[i.productId] = _variantRepository
              .getDefaultVariantByProduct(i.productId);
        }
      }
      final resolvedVariants = <int, ProductVariant?>{};
      for (final entry in variantFutures.entries) {
        resolvedVariants[entry.key] = await entry.value;
      }

      final resolvedDefaultVariants = <int, ProductVariant?>{};
      for (final entry in defaultVariantFutures.entries) {
        resolvedDefaultVariants[entry.key] = await entry.value;
      }

      // Fetch real product data for tax info
      final resolvedProducts = <int, Product?>{};
      for (final pid in productIds) {
        final stream = _productRepository.watchProduct(pid);
        resolvedProducts[pid] = await stream.first;
      }

      final mappedItems = items.map((i) {
        final realProduct = resolvedProducts[i.productId];
        final product = Product(
          id: i.productId,
          name: i.productName ?? realProduct?.name ?? 'Product #${i.productId}',
          costCents: i.unitCostCents,
          priceCents: realProduct?.priceCents ?? Decimal.zero,
          wholesalePriceCents: realProduct?.wholesalePriceCents,
          stockQuantity: realProduct?.stockQuantity ?? 0,
          minQuantity: realProduct?.minQuantity ?? 0,
          hasVariants: i.variantId != null,
          isTaxable: realProduct?.isTaxable ?? false,
          purchaseTaxRateBps: realProduct?.purchaseTaxRateBps ?? 0,
          salesTaxRateBps: realProduct?.salesTaxRateBps ?? 0,
          isActive: realProduct?.isActive ?? true,
          trackInventory: realProduct?.trackInventory ?? true,
          inventoryTrackingType:
              realProduct?.inventoryTrackingType ?? 'standard',
          measurementType: i.measurementType,
        );

        final realVariant = i.variantId != null
            ? resolvedVariants[i.variantId!]
            : null;
        final defaultVariant = i.variantId == null
            ? resolvedDefaultVariants[i.productId]
            : null;
        final variant =
            realVariant ??
            defaultVariant ??
            (i.variantId == null
                ? null
                : ProductVariant(
                    id: i.variantId!,
                    productId: i.productId,
                    sku: i.variantSku,
                    barcode: null,
                    colorId: null,
                    sizeId: null,
                    costCents: i.unitCostCents,
                    priceCents: Decimal.zero,
                    wholesalePriceCents: null,
                    priceAdjustmentCents: Decimal.zero,
                    stockQuantity: 0,
                    isActive: true,
                  ));

        // Resolve "original" (pre-purchase) prices through the centralized
        // [OriginalPriceResolver]. This is the SINGLE source of truth for
        // the chain saved → variant.previous → variant.current → product.*
        // and for the "saved 0 == legacy default-init" rule. See
        // `lib/core/services/purchases/original_price_resolver.dart`.
        final snapshot = OriginalPriceResolver.resolveForEdit(
          product: product,
          variant: variant,
          savedCostCents: i.originalCostCents?.toBigInt().toInt(),
          savedPriceCents: i.originalPriceCents?.toBigInt().toInt(),
          savedWholesalePriceCents: i.originalWholesalePriceCents
              ?.toBigInt()
              .toInt(),
        );

        return PurchaseLineItem(
          tempId: _generateTempId(),
          product: product,
          variant: variant,
          quantity: i.quantity,
          unitCostCents: i.unitCostCents,
          discountCents: i.discountCents,
          expiryDate: i.expiryDate,
          manufacturerLotNumber: i.manufacturerLotNumber,
          isMedicine:
              event.pharmacyFeaturesEnabled &&
              _medicineProductIds.contains(i.productId),
          colorName: _resolveColorName(variant?.colorId),
          colorHex: _resolveColorHex(variant?.colorId),
          sizeName: _resolveSizeName(variant?.sizeId),
          originalCostCents: snapshot.costCents,
          originalPriceCents: snapshot.priceCents,
          originalWholesalePriceCents: snapshot.wholesalePriceCents,
          persistOriginalCostCents: snapshot.persistCostCents,
          persistOriginalPriceCents: snapshot.persistPriceCents,
          persistOriginalWholesalePriceCents:
              snapshot.persistWholesalePriceCents,
          newSellPriceCents: i.newSellPriceCents,
          newWholesalePriceCents: i.newWholesalePriceCents,
        );
      }).toList();

      final itemDiscountCents = mappedItems.fold<Decimal>(
        Decimal.zero,
        (sum, item) => sum + item.discountCents,
      );
      final hasAnyItemDiscount = itemDiscountCents > Decimal.zero;
      final hasInvoiceDiscount = purchase.discountCents > Decimal.zero;
      final resolvedDiscountMode = (!hasAnyItemDiscount && hasInvoiceDiscount)
          ? DiscountMode.invoice
          : DiscountMode.perItem;
      final resolvedInvoiceDiscountCents =
          resolvedDiscountMode == DiscountMode.invoice
          ? purchase.discountCents
          : Decimal.zero;

      final hasAnyItemTax = mappedItems.any((i) => i.taxCents > Decimal.zero);
      Decimal resolvedTaxRatePercent = Decimal.zero;
      if (!hasAnyItemTax && purchase.taxCents > Decimal.zero) {
        final taxable = purchase.subtotalCents - purchase.discountCents;
        if (taxable > Decimal.zero) {
          final rawPct = (purchase.taxCents * Decimal.fromInt(100)) / taxable;
          final rawPctDouble = double.tryParse(rawPct.toString()) ?? 0;
          resolvedTaxRatePercent = Decimal.parse(
            rawPctDouble.toStringAsFixed(2),
          );
        }
      }

      emit(
        state.copyWith(
          purchaseId: purchase.id,
          purchaseNumber: purchase.purchaseNumber,
          supplierId: purchase.supplierId,
          supplierName: purchase.supplierName,
          currencyId: purchase.currencyId,
          purchaseDate: purchase.purchaseDate,
          dueDate: purchase.dueDate,
          supplierInvoiceRef: purchase.supplierInvoiceRef,
          notes: purchase.notes,
          items: mappedItems,
          // Do not silently enable/disable source attribution on an old draft
          // when the app preference changed after it was saved.
          useSupplierProductCodes: items.any(
            (i) => i.supplierIdentityRequested,
          ),
          discountMode: resolvedDiscountMode,
          invoiceDiscountCents: resolvedInvoiceDiscountCents,
          paymentMethod: _parsePaymentMethod(purchase.paymentMethod),
          paidAmountCents: purchase.paidAmountCents,
          taxRatePercent: resolvedTaxRatePercent,
        ),
      );
      await _refreshSupplierSourcePreviews(emit);
    } catch (e) {
      emit(state.copyWith(error: e.toString()));
    }
  }

  Future<void> _onSupplierChanged(
    PurchaseSupplierChanged event,
    Emitter<PurchaseFormState> emit,
  ) async {
    if (state.isSubmitting) return;
    emit(
      state.copyWith(
        supplierId: event.supplierId,
        supplierName: event.supplierName,
        hasUnsavedChanges: true,
        supplierSourcePreviews: const {},
        supplierSourceErrors: const {},
      ),
    );
    await _refreshSupplierSourcePreviews(emit);
  }

  Future<void> _refreshSupplierSourcePreviews(
    Emitter<PurchaseFormState> emit,
  ) async {
    final generation = ++_sourcePreviewGeneration;
    final snapshot = state;
    if (!snapshot.useSupplierProductCodes || snapshot.supplierId == null) {
      emit(
        state.copyWith(
          supplierSourcePreviews: const {},
          supplierSourceErrors: const {},
          isResolvingSupplierSources: false,
        ),
      );
      return;
    }
    emit(
      state.copyWith(
        supplierSourcePreviews: const {},
        supplierSourceErrors: const {},
        isResolvingSupplierSources: true,
      ),
    );
    final previews = <String, SupplierIdentityPreview>{};
    final errors = <String, String>{};
    // Cache per variant within this preview only; different lots still render
    // separate invoice lines with the same immutable supplier identity.
    final cache = <String, Future<SupplierIdentityPreview>>{};
    for (final line in snapshot.items.where((i) => i.product.trackInventory)) {
      try {
        final previewer = _supplierSourcePreviewer;
        if (previewer == null) {
          throw const SupplierIdentityException(
            'supplier_purchase.unavailable',
          );
        }
        final key = '${line.product.id}:${line.variant?.id}';
        previews[line.tempId] = await cache.putIfAbsent(
          key,
          () => previewer.preview(
            supplierId: snapshot.supplierId!,
            productId: line.product.id,
            variantId: line.variant?.id,
          ),
        );
      } catch (error) {
        errors[line.tempId] =
            SupplierIdentityException.fromError(error)?.messageKey ??
            'supplier_purchase.preview_failed';
      }
    }
    // A slower N preview must not overwrite a newer A selection. No DB writes
    // occur here, and an old event handler must not emit after it is done.
    if (generation != _sourcePreviewGeneration || emit.isDone) return;
    emit(
      state.copyWith(
        supplierSourcePreviews: Map.unmodifiable(previews),
        supplierSourceErrors: Map.unmodifiable(errors),
        isResolvingSupplierSources: false,
      ),
    );
  }

  void _onDateChanged(
    PurchaseDateChanged event,
    Emitter<PurchaseFormState> emit,
  ) {
    emit(state.copyWith(purchaseDate: event.date));
  }

  void _onDueDateChanged(
    PurchaseDueDateChanged event,
    Emitter<PurchaseFormState> emit,
  ) {
    if (event.dueDate == null) {
      emit(state.copyWith(clearDueDate: true));
    } else {
      emit(state.copyWith(dueDate: event.dueDate));
    }
  }

  void _onNotesChanged(
    PurchaseNotesChanged event,
    Emitter<PurchaseFormState> emit,
  ) {
    emit(state.copyWith(notes: event.notes));
  }

  void _onSupplierRefChanged(
    PurchaseSupplierRefChanged event,
    Emitter<PurchaseFormState> emit,
  ) {
    emit(state.copyWith(supplierInvoiceRef: event.ref));
  }

  void _onDiscountModeChanged(
    PurchaseDiscountModeChanged event,
    Emitter<PurchaseFormState> emit,
  ) {
    // Phase-14 mode-exclusivity (state-level): when the user toggles the
    // discount mode, clear the OTHER mode's discount inputs so the two
    // paths are mathematically and visually equivalent. The pricing
    // engine already masks this at compute time (see `_computePricing`
    // overrideDiscount), but stale per-line discounts in `state.items`
    // would silently re-activate on a back-toggle to `perItem`, causing
    // a "double-discount the user can't notice" — exactly the bug class
    // already documented in `SaleAdjReturnFormBloc._onDiscountModeChanged`.
    //
    // Switching INTO `invoice` mode -> wipe per-line `discountCents`.
    // Switching INTO `perItem`  mode -> wipe invoice-level discount
    //                                    (already done; kept for symmetry).
    final isInvoice = event.mode == DiscountMode.invoice;
    final clearedItems = isInvoice
        ? state.items
              .map((i) => i.copyWith(discountCents: Decimal.zero))
              .toList()
        : state.items;
    emit(
      state.copyWith(
        discountMode: event.mode,
        items: clearedItems,
        invoiceDiscountCents: Decimal.zero,
        hasUnsavedChanges: true,
      ),
    );
  }

  void _onInvoiceDiscountChanged(
    PurchaseInvoiceDiscountChanged event,
    Emitter<PurchaseFormState> emit,
  ) {
    emit(state.copyWith(invoiceDiscountCents: event.discountCents));
  }

  Future<void> _onLineItemAdded(
    PurchaseLineItemAdded event,
    Emitter<PurchaseFormState> emit,
  ) async {
    if (state.isSubmitting) return;
    await _loadColorSizeLookups();

    ProductVariant? resolvedVariant = event.variant;
    if (resolvedVariant == null) {
      try {
        resolvedVariant = await _variantRepository.getDefaultVariantByProduct(
          event.product.id,
        );
      } catch (_) {}
    }

    // Capture "original" (pre-purchase) prices through the centralized
    // [OriginalPriceResolver]. Same chain as the read path in
    // `_onInitialized`, ensuring the bottom-sheet displays consistent
    // values whether the line is freshly added or loaded from a saved
    // purchase. See `lib/core/services/purchases/original_price_resolver.dart`.
    final snapshot = OriginalPriceResolver.captureForNewLine(
      product: event.product,
      variant: resolvedVariant,
    );

    final newItem = PurchaseLineItem(
      tempId: _generateTempId(),
      product: event.product,
      variant: resolvedVariant,
      quantity: event.quantity,
      unitCostCents: event.unitCostCents,
      discountCents: event.discountCents,
      expiryDate: event.expiryDate,
      manufacturerLotNumber: event.manufacturerLotNumber,
      isMedicine:
          state.pharmacyFeaturesEnabled &&
          _medicineProductIds.contains(event.product.id),
      colorName: _resolveColorName(resolvedVariant?.colorId),
      colorHex: _resolveColorHex(resolvedVariant?.colorId),
      sizeName: _resolveSizeName(resolvedVariant?.sizeId),
      originalCostCents: snapshot.costCents,
      originalPriceCents: snapshot.priceCents,
      originalWholesalePriceCents: snapshot.wholesalePriceCents,
      persistOriginalCostCents: snapshot.persistCostCents,
      persistOriginalPriceCents: snapshot.persistPriceCents,
      persistOriginalWholesalePriceCents: snapshot.persistWholesalePriceCents,
    );
    if (state.isSubmitting || emit.isDone) return;
    emit(
      state.copyWith(items: [...state.items, newItem], hasUnsavedChanges: true),
    );
    await _refreshSupplierSourcePreviews(emit);
  }

  void _onLineItemUpdated(
    PurchaseLineItemUpdated event,
    Emitter<PurchaseFormState> emit,
  ) {
    if (state.isSubmitting) return;
    final updatedItems = state.items.map((item) {
      if (item.tempId == event.tempId) {
        return item.copyWith(
          quantity: event.quantity,
          unitCostCents: event.unitCostCents,
          discountCents: event.discountCents,
          expiryDate: event.expiryDate,
          clearExpiry: event.clearExpiry,
          manufacturerLotNumber: event.manufacturerLotNumber,
          clearManufacturerLotNumber: event.clearManufacturerLotNumber,
          newSellPriceCents: event.newSellPriceCents,
          newWholesalePriceCents: event.newWholesalePriceCents,
        );
      }
      return item;
    }).toList();
    emit(state.copyWith(items: updatedItems, hasUnsavedChanges: true));
  }

  Future<void> _onLineItemRemoved(
    PurchaseLineItemRemoved event,
    Emitter<PurchaseFormState> emit,
  ) async {
    if (state.isSubmitting) return;
    final updatedItems = state.items
        .where((item) => item.tempId != event.tempId)
        .toList();
    emit(state.copyWith(items: updatedItems, hasUnsavedChanges: true));
    await _refreshSupplierSourcePreviews(emit);
  }

  Future<void> _onSubmitted(
    PurchaseFormSubmitted event,
    Emitter<PurchaseFormState> emit,
  ) async {
    if (state.isSubmitting) return;
    final submittedState = state;
    if (submittedState.supplierId == null) {
      emit(state.copyWith(error: 'Please select a supplier'));
      return;
    }
    if (submittedState.items.isEmpty) {
      emit(state.copyWith(error: 'Please add at least one item'));
      return;
    }

    // Phase C — two-layer inventory architecture: every line whose product
    // is tracked as `batch_expiry` MUST carry an expiry date. The UI gates
    // this at edit time (Save button disabled until a date is picked); this
    // is the server-authoritative back-stop in case a stale or programmatic
    // payload bypasses the UI guard.
    final missingExpiry = submittedState.items
        .where(
          (it) =>
              it.product.inventoryTrackingType == 'batch_expiry' &&
              it.expiryDate == null,
        )
        .toList();
    if (missingExpiry.isNotEmpty) {
      emit(state.copyWith(error: 'purchases.expiry_required_submit_blocked'));
      return;
    }

    // GS1 AI (10): only medicines in pharmacy mode require the manufacturer's
    // lot/batch number. Ordinary stock (bags, paper, etc.) must not inherit a
    // medicine-only requirement even if it uses generic batch tracking.
    final missingManufacturerLot =
        submittedState.pharmacyFeaturesEnabled &&
        submittedState.items.any(
          (it) =>
              it.requiresManufacturerLot &&
              (it.manufacturerLotNumber?.trim().isEmpty ?? true),
        );
    if (missingManufacturerLot) {
      emit(state.copyWith(error: 'pharmacy.batch.lot_required_submit_blocked'));
      return;
    }

    if (event.settlement == null &&
        submittedState.paymentMethod == PurchasePaymentMethod.cheque &&
        submittedState.dueDate == null) {
      emit(state.copyWith(error: 'purchases.cheque_due_date_required'));
      return;
    }

    // Cash validation: paid amount must be >= total
    if (submittedState.paymentMethod == PurchasePaymentMethod.cash &&
        submittedState.paidAmountCents < submittedState.totalCents) {
      emit(state.copyWith(error: 'purchases.cash_insufficient'));
      return;
    }

    // Invalidate any preview still in flight: it must not emit a second
    // success state (and navigate again) after this submit has completed.
    _sourcePreviewGeneration++;
    emit(
      state.copyWith(
        isSubmitting: true,
        error: null,
        isResolvingSupplierSources: false,
      ),
    );

    try {
      if (submittedState.useSupplierProductCodes) {
        if (!SupplierPurchaseSourcePolicy.buildAllowsWrites ||
            _supplierSourcePreviewer == null) {
          throw const SupplierIdentityException(
            'supplier_purchase.unavailable',
          );
        }
        // Preflight before creating any invoice. Save validates again inside
        // the DB transaction, so a race/collision cannot commit a partial bill.
        for (final line in submittedState.items.where(
          (i) => i.product.trackInventory,
        )) {
          await _supplierSourcePreviewer.preview(
            supplierId: submittedState.supplierId!,
            productId: line.product.id,
            variantId: line.variant?.id,
          );
        }
      }
      final settlement = event.settlement;
      settlement?.validate(
        invoiceTotalCents: submittedState.totalCents.toBigInt().toInt(),
      );
      // SoT for the per-line breakdown is the state-level pricing engine
      // result: it has already done subtotal → discount → net → invoice-
      // discount allocation (largest-remainder) → tax-on-adjusted-net.
      // No parallel arithmetic path lives here, by design.
      final lineItems = submittedState.items;
      final pricing = submittedState.pricing;

      final items = <PurchaseItemInput>[];
      for (int idx = 0; idx < lineItems.length; idx++) {
        final item = lineItems[idx];
        final line = pricing.lines[idx];
        items.add(
          PurchaseItemInput(
            productId: item.product.id,
            supplierIdentityRequested:
                submittedState.useSupplierProductCodes &&
                item.product.trackInventory,
            variantId: item.variant?.id,
            quantity: item.quantity,
            quantityScale: item.product.quantityScale,
            measurementType: item.product.measurementType,
            unitCostCents: item.unitCostCents,
            // Total per-line discount = entered line discount + share of
            // the invoice-level discount (zero in `perItem` mode).
            discountCents: Decimal.fromInt(line.totalLineDiscount.cents),
            subtotalCents: Decimal.fromInt(line.subtotal.cents),
            taxCents: Decimal.fromInt(line.tax.cents),
            totalCents: Decimal.fromInt(line.total.cents),
            expiryDate: item.expiryDate,
            manufacturerLotNumber: item.manufacturerLotNumber?.trim(),
            // Persist the snapshot fields, NOT the display fields. When the
            // resolver determined there is no real historical value (live cost
            // is still 0 from default-init), persist `null` rather than `0` —
            // a future re-load will then fall back through the resolver chain
            // and render meaningful prices instead of `0.00`.
            originalCostCents: item.persistOriginalCostCents != null
                ? Decimal.fromInt(item.persistOriginalCostCents!)
                : null,
            originalPriceCents: item.persistOriginalPriceCents != null
                ? Decimal.fromInt(item.persistOriginalPriceCents!)
                : null,
            originalWholesalePriceCents:
                item.persistOriginalWholesalePriceCents != null
                ? Decimal.fromInt(item.persistOriginalWholesalePriceCents!)
                : null,
            newSellPriceCents: item.newSellPriceCents,
            newWholesalePriceCents: item.newWholesalePriceCents,
          ),
        );
      }

      // Determine effective paid amount:
      // - cash: depends on overpayment handling
      //   - returnChange: cap at totalCents (excess is returned as cash change)
      //   - addToBalance: use full paidAmountCents (excess goes to supplier credit)
      // - card: auto-set to total (fully settled)
      // - credit: 0 (full amount goes to supplier balance)
      // - cheque: 0 until bank clearance confirms the payment
      // - purchaseOrder: auto-set to total (no balance impact, just a reminder)
      final effectivePaidCents = settlement != null
          ? Decimal.fromInt(settlement.totalSettledCents)
          : switch (submittedState.paymentMethod) {
              PurchasePaymentMethod.cash => () {
                if (submittedState.paidAmountCents >
                        submittedState.totalCents &&
                    submittedState.overpaymentHandling ==
                        OverpaymentHandling.returnChange) {
                  return submittedState.totalCents;
                }
                return submittedState.paidAmountCents;
              }(),
              PurchasePaymentMethod.card => submittedState.totalCents,
              PurchasePaymentMethod.credit => Decimal.zero,
              PurchasePaymentMethod.cheque => Decimal.zero,
              PurchasePaymentMethod.purchaseOrder => submittedState.totalCents,
            };

      if (submittedState.purchaseId == null) {
        final purchaseId = await _repository.createPurchase(
          supplierId: submittedState.supplierId!,
          currencyId: submittedState.currencyId,
          subtotalCents: submittedState.subtotalCents,
          discountCents: submittedState.totalDiscountCents,
          taxCents: submittedState.taxCents,
          totalCents: submittedState.totalCents,
          paidAmountCents: effectivePaidCents,
          items: items,
          paymentMethod:
              settlement?.headerPaymentMethod ??
              submittedState.paymentMethod.name,
          supplierInvoiceRef: submittedState.supplierInvoiceRef,
          notes: submittedState.notes,
          purchaseDate: submittedState.purchaseDate,
          dueDate: submittedState.dueDate,
          taxInclusiveAtPost: submittedState.taxInclusivePricing,
          initialPayments: settlement?.payments ?? const [],
        );

        CrashlyticsService.instance.logAction('purchase_created', {
          'purchase_id': purchaseId.toString(),
          'total_cents': submittedState.totalCents.toString(),
          'items_count': submittedState.items.length.toString(),
        });
        emit(
          state.copyWith(
            purchaseId: purchaseId,
            isSubmitting: false,
            isSuccess: true,
            hasUnsavedChanges: false,
          ),
        );
      } else if (submittedState.isEditingPosted) {
        // Editing a posted purchase: void original and create new
        final newPurchaseId = await _repository.editPostedPurchase(
          originalPurchaseId: submittedState.purchaseId!,
          supplierId: submittedState.supplierId!,
          currencyId: submittedState.currencyId,
          subtotalCents: submittedState.subtotalCents,
          discountCents: submittedState.totalDiscountCents,
          taxCents: submittedState.taxCents,
          totalCents: submittedState.totalCents,
          paidAmountCents: effectivePaidCents,
          items: items,
          paymentMethod: submittedState.paymentMethod.name,
          supplierInvoiceRef: submittedState.supplierInvoiceRef,
          notes: submittedState.notes,
          purchaseDate: submittedState.purchaseDate,
          dueDate: submittedState.dueDate,
          taxInclusiveAtPost: submittedState.taxInclusivePricing,
        );

        CrashlyticsService.instance.logAction('purchase_edited_posted', {
          'purchase_id': newPurchaseId.toString(),
          'original_purchase_id': submittedState.purchaseId.toString(),
        });
        emit(
          state.copyWith(
            purchaseId: newPurchaseId,
            isSubmitting: false,
            isSuccess: true,
            hasUnsavedChanges: false,
          ),
        );
      } else {
        final ok = await _repository.updatePurchase(
          purchaseId: submittedState.purchaseId!,
          supplierId: submittedState.supplierId!,
          currencyId: submittedState.currencyId,
          subtotalCents: submittedState.subtotalCents,
          discountCents: submittedState.totalDiscountCents,
          taxCents: submittedState.taxCents,
          totalCents: submittedState.totalCents,
          paidAmountCents: effectivePaidCents,
          items: items,
          paymentMethod: submittedState.paymentMethod.name,
          supplierInvoiceRef: submittedState.supplierInvoiceRef,
          notes: submittedState.notes,
          purchaseDate: submittedState.purchaseDate,
          dueDate: submittedState.dueDate,
          taxInclusiveAtPost: submittedState.taxInclusivePricing,
        );

        if (!ok) {
          throw Exception('Failed to update purchase');
        }

        CrashlyticsService.instance.logAction('purchase_updated', {
          'purchase_id': submittedState.purchaseId.toString(),
        });
        emit(
          state.copyWith(
            isSubmitting: false,
            isSuccess: true,
            hasUnsavedChanges: false,
          ),
        );
      }
    } catch (e, st) {
      CrashlyticsService.instance.recordError(
        e,
        stackTrace: st,
        reason: 'PurchaseFormBloc._onSubmitted failed',
      );
      emit(
        state.copyWith(
          isSubmitting: false,
          error:
              SupplierIdentityException.fromError(e)?.messageKey ??
              e.toString(),
        ),
      );
    }
  }

  void _onPaymentMethodChanged(
    PurchasePaymentMethodChanged event,
    Emitter<PurchaseFormState> emit,
  ) {
    // Reset paid amount when switching payment methods
    emit(
      state.copyWith(
        paymentMethod: event.method,
        paidAmountCents: Decimal.zero,
      ),
    );
  }

  void _onTaxRateChanged(
    PurchaseTaxRateChanged event,
    Emitter<PurchaseFormState> emit,
  ) {
    emit(state.copyWith(taxRatePercent: event.taxRatePercent));
  }

  void _onPaidAmountChanged(
    PurchasePaidAmountChanged event,
    Emitter<PurchaseFormState> emit,
  ) {
    emit(state.copyWith(paidAmountCents: event.paidAmountCents));
  }

  void _onOverpaymentHandlingChanged(
    PurchaseOverpaymentHandlingChanged event,
    Emitter<PurchaseFormState> emit,
  ) {
    emit(state.copyWith(overpaymentHandling: event.handling));
  }

  // _distributeProportionally removed — use TaxCalculationService.distributeProportionally()

  Future<void> _onPosted(
    PurchaseFormPosted event,
    Emitter<PurchaseFormState> emit,
  ) async {
    if (state.purchaseId == null) {
      emit(state.copyWith(error: 'Purchase must be saved first'));
      return;
    }

    emit(state.copyWith(isSubmitting: true, error: null));

    try {
      await _repository.postPurchase(state.purchaseId!);
      emit(state.copyWith(isSubmitting: false, isSuccess: true));
    } catch (e) {
      emit(
        state.copyWith(
          isSubmitting: false,
          error:
              SupplierIdentityException.fromError(e)?.messageKey ??
              e.toString(),
        ),
      );
    }
  }

  void _onTaxSettingsChanged(
    PurchaseTaxSettingsChanged event,
    Emitter<PurchaseFormState> emit,
  ) {
    emit(
      state.copyWith(
        enableTaxCalculations: event.enableTaxCalculations,
        defaultPurchaseTaxRateBps: event.defaultPurchaseTaxRateBps,
        taxInclusivePricing: event.taxInclusivePricing,
      ),
    );
  }
}
