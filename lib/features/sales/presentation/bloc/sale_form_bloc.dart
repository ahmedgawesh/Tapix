import 'package:decimal/decimal.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/app_database.dart' show LoyaltySettings;
import '../../../../core/money/money.dart';
import '../../../../core/payments/checkout_settlement.dart';
import '../../../../core/pricing/discount.dart';
import '../../../../core/pricing/invoice_pricing_engine.dart';
import '../../../../core/pricing/line_item_pricing_engine.dart';
import '../../../../core/promotions/promotion_engine.dart';
import '../../../../core/promotions/promotion_margin_policy.dart';
import '../../../../core/promotions/promotion_repository.dart';
import '../../../../core/services/audit_log_service.dart';
import '../../../../core/services/below_cost_sale_service.dart';
import '../../../../core/services/crashlytics_service.dart';
import '../../../../core/services/free_quota_service.dart';
import '../../../../core/services/lan/lan_network_service.dart';
import '../../domain/repositories/sale_repository.dart';
import '../../../auth/domain/entities/user_entity.dart';
import '../../../customers/domain/repositories/loyalty_repository.dart';
import '../../../products/domain/entities/product_entity.dart';
import '../../../products/domain/entities/product_variant_entity.dart';
import '../../../products/domain/repositories/product_repository.dart';
import '../../../products/domain/repositories/product_variant_repository.dart';

// ==================== ENUMS ====================

/// Discount mode: per-item discounts or a single invoice-level discount
enum SaleDiscountMode { perItem, invoice }

/// Payment method for sale invoice
enum SalePaymentMethod { cash, credit, card, cheque }

/// Salesperson assignment mode: per-invoice or per-item
enum SalespersonMode { perInvoice, perItem }

/// How to handle overpayment when paid amount exceeds invoice total
enum SaleOverpaymentHandling {
  /// Return the excess as change to the customer
  returnChange,

  /// Add the excess to the customer's credit balance
  addToBalance,
}

// ==================== STATE ====================

class SaleFormState extends Equatable {
  final int? saleId;
  final String? saleNumber;
  final int? customerId;
  final String? customerName;
  final int? employeeId;
  final String? employeeName;
  final int currencyId;
  final List<SaleLineItem> items;
  final SaleDiscountMode discountMode;
  final Decimal invoiceDiscountCents;
  final String? notes;
  final DateTime saleDate;
  final DateTime? dueDate;
  final SalePaymentMethod paymentMethod;
  final Decimal taxRatePercent;
  final SalespersonMode salespersonMode;
  final Decimal paidAmountCents;
  final SaleOverpaymentHandling overpaymentHandling;
  final bool isSubmitting;
  final String? error;
  final bool isSuccess;
  final BelowCostCheckResult? belowCostWarning;
  final List<BelowCostOverride> belowCostOverrides;
  // Loyalty points redemption
  final int loyaltyPointsBalance;
  final int loyaltyPointsToRedeem;
  final int loyaltyDiscountCents;
  final LoyaltySettings? loyaltySettings;
  final bool loyaltyRedemptionEnabled;
  // Global tax settings
  final bool enableTaxCalculations;
  final int defaultSalesTaxRateBps;
  final bool taxInclusivePricing;
  // Global inventory settings
  final bool allowNegativeStock;
  // Global sales settings
  final bool allowPartialPayments;
  final bool allowDiscounts;
  final double maxDiscountPercent;
  final bool allowBelowCostSales;
  // Null on local sales; populated from the master for LAN cashier PDFs.
  final String? masterReceiptHeaderText;
  final String? masterReceiptFooterText;
  final bool requireCustomerForSales;
  final bool enableLoyaltyPoints;
  final bool enablePromotions;
  final List<PromotionRule> promotionRules;
  // Editing posted sale flag
  final bool isEditingPosted;
  // Tracks if user has made unsaved changes
  final bool hasUnsavedChanges;

  SaleFormState({
    this.saleId,
    this.saleNumber,
    this.customerId,
    this.customerName,
    this.employeeId,
    this.employeeName,
    required this.currencyId,
    this.items = const [],
    this.discountMode = SaleDiscountMode.perItem,
    Decimal? invoiceDiscountCents,
    this.notes,
    required this.saleDate,
    this.dueDate,
    this.paymentMethod = SalePaymentMethod.cash,
    Decimal? taxRatePercent,
    this.salespersonMode = SalespersonMode.perInvoice,
    Decimal? paidAmountCents,
    this.overpaymentHandling = SaleOverpaymentHandling.returnChange,
    this.isSubmitting = false,
    this.error,
    this.isSuccess = false,
    this.belowCostWarning,
    this.belowCostOverrides = const [],
    this.loyaltyPointsBalance = 0,
    this.loyaltyPointsToRedeem = 0,
    this.loyaltyDiscountCents = 0,
    this.loyaltySettings,
    this.loyaltyRedemptionEnabled = false,
    this.enableTaxCalculations = true,
    this.defaultSalesTaxRateBps = 0,
    this.taxInclusivePricing = false,
    this.allowNegativeStock = false,
    this.allowPartialPayments = false,
    this.allowDiscounts = true,
    this.maxDiscountPercent = 100.0,
    this.allowBelowCostSales = false,
    this.masterReceiptHeaderText,
    this.masterReceiptFooterText,
    this.requireCustomerForSales = false,
    this.enableLoyaltyPoints = false,
    this.enablePromotions = false,
    this.promotionRules = const [],
    this.isEditingPosted = false,
    this.hasUnsavedChanges = false,
  }) : invoiceDiscountCents = invoiceDiscountCents ?? Decimal.zero,
       taxRatePercent = taxRatePercent ?? Decimal.zero,
       paidAmountCents = paidAmountCents ?? Decimal.zero;

  // ── Engine-backed pricing layer (single source of truth) ───────────────
  //
  // Every monetary getter that represents an invoice-level pricing figure
  // (subtotal, item-discount, overall-discount, tax, pre-loyalty total)
  // is derived from exactly one call to [InvoicePricingEngine.compute].
  // Memoized once per immutable state instance so the UI's many rebuilds
  // amortize the cost.
  //
  // The TENDER layer (loyalty redemption, paid, remaining, change) is
  // intentionally NOT part of the engine — see ADR
  // `docs/adr/0002-engine-readiness-audit.md` §4 Q2: loyalty redemption is
  // a contra-AR settlement (GAAP/IFRS-15), NOT a reduction of taxable
  // revenue. The engine's `pricing.total` IS the pre-loyalty figure; the
  // bloc's `totalCents` subtracts the loyalty deduction afterwards.

  /// Lazy memoized engine result. Built on first access and reused for
  /// the lifetime of this immutable state instance.
  ///
  /// Phase-5 close-out: the Phase-4 dual-compute `kDebugMode` assertion
  /// has been removed after a full phase of green Phase-0 goldens and
  /// Phase-4 regression tests. The engine is now the unconditional SoT
  /// for every pricing figure; the tender layer below remains bloc-owned.
  late final InvoicePricingResult manualPricing = _computePricing(
    includePromotions: false,
  );

  late final PromotionEvaluationResult promotionEvaluation =
      _computePromotionEvaluation();

  late final InvoicePricingResult pricing = _computePricing(
    includePromotions: true,
  );

  InvoicePricingResult _computePricing({required bool includePromotions}) {
    // Discount-mode bridge (ADR 0002 §G7):
    //   * `perItem`  → per-line discount preserved, overall = none.
    //   * `invoice`  → per-line discount suppressed (Q3 mode-exclusivity),
    //                  overall = invoice-level discount.
    // This matches the long-standing `TaxCalculationService.calculateInvoiceTax`
    // submission contract (which also zeroed per-line discounts in invoice
    // mode), so engine output stays identical to what the bloc previously
    // persisted — see Phase-0 goldens.
    final inInvoiceMode = discountMode == SaleDiscountMode.invoice;
    final promotionByLine = includePromotions
        ? promotionEvaluation.discountByLine
        : const <String, Money>{};
    final lineInputs = items
        .map((item) {
          final manual = inInvoiceMode
              ? Money.zero
              : Money.fromDecimalCents(item.discountCents);
          final promotion = promotionByLine[item.tempId] ?? Money.zero;
          final combined = manual + promotion;
          return item.toPricingInput(
            overrideDiscount: combined.isPositive
                ? Discount.fixed(combined)
                : Discount.none,
          );
        })
        .toList(growable: false);

    return InvoicePricingEngine.compute(
      InvoicePricingInput(
        lines: lineInputs,
        overallDiscount: inInvoiceMode
            ? _buildOverallDiscount()
            : Discount.none,
        enableTaxCalculations: enableTaxCalculations,
        defaultTaxRateBps: defaultSalesTaxRateBps,
        taxInclusivePricing: taxInclusivePricing,
      ),
    );
  }

  PromotionEvaluationResult _computePromotionEvaluation() {
    if (!enablePromotions || promotionRules.isEmpty || items.isEmpty) {
      return const PromotionEvaluationResult(applications: []);
    }
    final cartLines = <PromotionCartLine>[];
    for (var index = 0; index < items.length; index++) {
      final item = items[index];
      cartLines.add(
        PromotionCartLine(
          lineId: item.tempId,
          productId: item.product.id,
          variantId: item.variant?.id,
          categoryId: item.product.categoryId,
          measurementType: item.product.measurementType,
          priceMode:
              (item.variant?.wholesalePriceCents ??
                          item.product.wholesalePriceCents) !=
                      null &&
                  item.unitPriceCents ==
                      (item.variant?.wholesalePriceCents ??
                          item.product.wholesalePriceCents)
              ? 'wholesale'
              : 'retail',
          quantity: item.quantity,
          quantityScale: item.product.quantityScale,
          unitPrice: Money.fromDecimalCents(item.unitPriceCents),
          existingDiscount: manualPricing.lines[index].totalLineDiscount,
        ),
      );
    }
    return PromotionEngine.evaluate(
      cart: PromotionCart(
        currencyId: currencyId,
        evaluatedAt: saleDate,
        lines: cartLines,
      ),
      promotions: promotionRules,
    );
  }

  Discount _buildOverallDiscount() {
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

  /// Invoice-level discount actually applied. The engine clamps to
  /// `[0, subtotal]` so this value can never exceed subtotal.
  Decimal get effectiveInvoiceDiscountCents {
    if (discountMode != SaleDiscountMode.invoice) return invoiceDiscountCents;
    return pricing.overallDiscount.decimalCents;
  }

  Decimal get totalDiscountCents => pricing.totalDiscount.decimalCents;

  int get promotionDiscountCents => promotionEvaluation.totalDiscount.cents;

  Decimal get itemTaxCents => pricing.tax.decimalCents;

  Decimal get taxCents => itemTaxCents;

  /// Pre-loyalty invoice total — IS the engine's `total`.
  ///
  /// This is the figure that posts to `sales.total_cents` and feeds revenue
  /// recognition. Loyalty redemption does NOT reduce it (GAAP/IFRS-15:
  /// revenue = gross transaction price; redemption = contra-AR settlement).
  Decimal get totalBeforeLoyaltyCents => pricing.total.decimalCents;

  // ── Tender layer (NOT part of the pricing engine by design) ────────────
  //
  // Loyalty redemption, paid amount, remaining, and change all live here.
  // They consume `pricing.total` but never feed back into it.

  /// Net amount the customer owes/pays at the till.
  ///
  /// `max(0, pricing.total − loyaltyDiscountCents)`. The journal-entry
  /// pipeline already knows to debit the contra-AR loyalty account by
  /// `loyaltyDiscountCents` and credit Sales Revenue by the full
  /// `pricing.total`.
  Decimal get totalCents {
    final net =
        pricing.total.decimalCents - Decimal.fromInt(loyaltyDiscountCents);
    return net < Decimal.zero ? Decimal.zero : net;
  }

  int get totalQuantity => items.fold(0, (sum, item) => sum + item.quantity);

  /// Checkout eligibility has one authoritative source: loyalty settings.
  /// The legacy sales-screen feature flag is intentionally not consulted;
  /// requiring both flags made an eligible customer's redemption card vanish
  /// even though the loyalty settings screen showed the program as enabled.
  bool get canOfferLoyaltyRedemption {
    final settings = loyaltySettings;
    return customerId != null &&
        settings != null &&
        settings.isEnabled &&
        settings.allowPointsRedemption &&
        settings.pointValueCents > 0 &&
        loyaltyPointsBalance > 0 &&
        loyaltyPointsBalance >= settings.minRedemptionPoints;
  }

  Decimal get remainingCents {
    final remaining = totalCents - paidAmountCents;
    return remaining < Decimal.zero ? Decimal.zero : remaining;
  }

  Decimal get changeCents {
    final change = paidAmountCents - totalCents;
    return change > Decimal.zero ? change : Decimal.zero;
  }

  SaleFormState copyWith({
    int? saleId,
    String? saleNumber,
    int? customerId,
    String? customerName,
    int? employeeId,
    String? employeeName,
    int? currencyId,
    List<SaleLineItem>? items,
    SaleDiscountMode? discountMode,
    Decimal? invoiceDiscountCents,
    String? notes,
    DateTime? saleDate,
    DateTime? dueDate,
    SalePaymentMethod? paymentMethod,
    Decimal? taxRatePercent,
    SalespersonMode? salespersonMode,
    Decimal? paidAmountCents,
    SaleOverpaymentHandling? overpaymentHandling,
    bool? isSubmitting,
    String? error,
    bool? isSuccess,
    bool clearCustomer = false,
    BelowCostCheckResult? belowCostWarning,
    bool clearBelowCostWarning = false,
    List<BelowCostOverride>? belowCostOverrides,
    int? loyaltyPointsBalance,
    int? loyaltyPointsToRedeem,
    int? loyaltyDiscountCents,
    LoyaltySettings? loyaltySettings,
    bool? loyaltyRedemptionEnabled,
    bool clearLoyalty = false,
    bool? enableTaxCalculations,
    int? defaultSalesTaxRateBps,
    bool? taxInclusivePricing,
    bool? allowNegativeStock,
    bool? allowPartialPayments,
    bool? allowDiscounts,
    double? maxDiscountPercent,
    bool? allowBelowCostSales,
    String? masterReceiptHeaderText,
    String? masterReceiptFooterText,
    bool? requireCustomerForSales,
    bool? enableLoyaltyPoints,
    bool? enablePromotions,
    List<PromotionRule>? promotionRules,
    bool? isEditingPosted,
    bool? hasUnsavedChanges,
  }) {
    return SaleFormState(
      saleId: saleId ?? this.saleId,
      saleNumber: saleNumber ?? this.saleNumber,
      customerId: clearCustomer ? null : (customerId ?? this.customerId),
      customerName: clearCustomer ? null : (customerName ?? this.customerName),
      employeeId: clearCustomer
          ? this.employeeId
          : (employeeId ?? this.employeeId),
      employeeName: clearCustomer
          ? this.employeeName
          : (employeeName ?? this.employeeName),
      currencyId: currencyId ?? this.currencyId,
      items: items ?? this.items,
      discountMode: discountMode ?? this.discountMode,
      invoiceDiscountCents: invoiceDiscountCents ?? this.invoiceDiscountCents,
      notes: notes ?? this.notes,
      saleDate: saleDate ?? this.saleDate,
      dueDate: dueDate ?? this.dueDate,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      taxRatePercent: taxRatePercent ?? this.taxRatePercent,
      salespersonMode: salespersonMode ?? this.salespersonMode,
      paidAmountCents: paidAmountCents ?? this.paidAmountCents,
      overpaymentHandling: overpaymentHandling ?? this.overpaymentHandling,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      error: error,
      isSuccess: isSuccess ?? this.isSuccess,
      belowCostWarning: clearBelowCostWarning
          ? null
          : (belowCostWarning ?? this.belowCostWarning),
      belowCostOverrides: belowCostOverrides ?? this.belowCostOverrides,
      loyaltyPointsBalance: clearLoyalty
          ? 0
          : (loyaltyPointsBalance ?? this.loyaltyPointsBalance),
      loyaltyPointsToRedeem: clearLoyalty
          ? 0
          : (loyaltyPointsToRedeem ?? this.loyaltyPointsToRedeem),
      loyaltyDiscountCents: clearLoyalty
          ? 0
          : (loyaltyDiscountCents ?? this.loyaltyDiscountCents),
      loyaltySettings: clearLoyalty
          ? null
          : (loyaltySettings ?? this.loyaltySettings),
      loyaltyRedemptionEnabled: clearLoyalty
          ? false
          : (loyaltyRedemptionEnabled ?? this.loyaltyRedemptionEnabled),
      enableTaxCalculations:
          enableTaxCalculations ?? this.enableTaxCalculations,
      defaultSalesTaxRateBps:
          defaultSalesTaxRateBps ?? this.defaultSalesTaxRateBps,
      allowNegativeStock: allowNegativeStock ?? this.allowNegativeStock,
      allowPartialPayments: allowPartialPayments ?? this.allowPartialPayments,
      allowDiscounts: allowDiscounts ?? this.allowDiscounts,
      maxDiscountPercent: maxDiscountPercent ?? this.maxDiscountPercent,
      allowBelowCostSales: allowBelowCostSales ?? this.allowBelowCostSales,
      masterReceiptHeaderText:
          masterReceiptHeaderText ?? this.masterReceiptHeaderText,
      masterReceiptFooterText:
          masterReceiptFooterText ?? this.masterReceiptFooterText,
      requireCustomerForSales:
          requireCustomerForSales ?? this.requireCustomerForSales,
      enableLoyaltyPoints: enableLoyaltyPoints ?? this.enableLoyaltyPoints,
      enablePromotions: enablePromotions ?? this.enablePromotions,
      promotionRules: promotionRules ?? this.promotionRules,
      isEditingPosted: isEditingPosted ?? this.isEditingPosted,
      hasUnsavedChanges: hasUnsavedChanges ?? this.hasUnsavedChanges,
    );
  }

  @override
  List<Object?> get props => [
    saleId,
    saleNumber,
    customerId,
    customerName,
    employeeId,
    employeeName,
    currencyId,
    items,
    discountMode,
    invoiceDiscountCents,
    notes,
    saleDate,
    dueDate,
    paymentMethod,
    taxRatePercent,
    salespersonMode,
    paidAmountCents,
    overpaymentHandling,
    isSubmitting,
    error,
    isSuccess,
    belowCostWarning,
    belowCostOverrides,
    loyaltyPointsBalance,
    loyaltyPointsToRedeem,
    loyaltyDiscountCents,
    loyaltySettings,
    loyaltyRedemptionEnabled,
    enableTaxCalculations,
    defaultSalesTaxRateBps,
    allowNegativeStock,
    allowPartialPayments,
    allowDiscounts,
    maxDiscountPercent,
    allowBelowCostSales,
    masterReceiptHeaderText,
    masterReceiptFooterText,
    requireCustomerForSales,
    enableLoyaltyPoints,
    enablePromotions,
    promotionRules,
    isEditingPosted,
    hasUnsavedChanges,
  ];
}

/// Tracks a below-cost override that was approved by a Manager/Owner.
class BelowCostOverride extends Equatable {
  final String tempId;
  final int productId;
  final String productName;
  final Decimal costCents;
  final Decimal sellingPriceCents;
  final Decimal lossCents;
  final String reason;

  const BelowCostOverride({
    required this.tempId,
    required this.productId,
    required this.productName,
    required this.costCents,
    required this.sellingPriceCents,
    required this.lossCents,
    required this.reason,
  });

  @override
  List<Object?> get props => [
    tempId,
    productId,
    productName,
    costCents,
    sellingPriceCents,
    lossCents,
    reason,
  ];
}

/// A line item in the sale form
class SaleLineItem extends Equatable {
  final String tempId;
  final Product product;
  final ProductVariant? variant;
  final int quantity;
  final Decimal unitPriceCents;
  final Decimal discountCents;
  final String? colorName;
  final String? colorHex;
  final String? sizeName;
  final int? employeeId;
  final String? employeeName;
  final String? itemNote;

  SaleLineItem({
    required this.tempId,
    required this.product,
    this.variant,
    required this.quantity,
    required this.unitPriceCents,
    Decimal? discountCents,
    this.colorName,
    this.colorHex,
    this.sizeName,
    this.employeeId,
    this.employeeName,
    this.itemNote,
  }) : discountCents = discountCents ?? Decimal.zero;

  // ── Engine-backed line math ────────────────────────────────────────────
  // Per-line totals flow through [LineItemPricingEngine] so there is
  // exactly one place where `subtotal → discount → net → tax → total`
  // is computed. Decimal return types are preserved for UI/PDF/repo
  // compatibility (consumers call `.toBigInt().toInt()` on the result).

  /// Build the engine input for this line. [overrideDiscount] lets the
  /// owning state suppress the per-line discount when invoice-level
  /// discount mode is active (ADR 0002 §G7 mode-exclusivity bridge).
  LineItemPricingInput toPricingInput({Discount? overrideDiscount}) {
    return LineItemPricingInput(
      unitPrice: Money.fromDecimalCents(unitPriceCents),
      quantity: quantity,
      quantityScale: product.quantityScale,
      discount:
          overrideDiscount ??
          (discountCents > Decimal.zero
              ? Discount.fixed(Money.fromDecimalCents(discountCents))
              : Discount.none),
      isTaxable: product.isTaxable,
      productTaxRateBps: product.salesTaxRateBps,
    );
  }

  /// Local (line-scoped) engine result. Uses the same contract as the
  /// historical getters: tax always enabled, no global default rate, no
  /// tax-inclusive pricing. The state-level engine in [SaleFormState] is
  /// where global settings are honored.
  LineItemPricingResult _localCompute() => LineItemPricingEngine.compute(
    input: toPricingInput(),
    enableTaxCalculations: true,
    defaultTaxRateBps: 0,
    taxInclusivePricing: false,
  );

  Decimal get subtotalCents => _localCompute().subtotal.decimalCents;

  Decimal get netCents => _localCompute().net.decimalCents;

  /// Tax computed from the product's sales tax rate (engine-resolved).
  /// This getter intentionally hard-codes `enableTaxCalculations=true,
  /// defaultTaxRateBps=0` to preserve the historical line-level contract
  /// (the invoice-level state respects global settings via `pricing`).
  Decimal get taxCents => _localCompute().tax.decimalCents;

  /// Calculate tax respecting global settings (engine-resolved).
  /// If [enableTaxCalculations] is false, returns zero.
  /// If product has its own rate (isTaxable && salesTaxRateBps > 0), uses
  /// that. Otherwise, falls back to [defaultTaxRateBps].
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

  SaleLineItem copyWith({
    String? tempId,
    Product? product,
    ProductVariant? variant,
    int? quantity,
    Decimal? unitPriceCents,
    Decimal? discountCents,
    String? colorName,
    String? colorHex,
    String? sizeName,
    int? employeeId,
    String? employeeName,
    String? itemNote,
    bool clearEmployee = false,
  }) {
    return SaleLineItem(
      tempId: tempId ?? this.tempId,
      product: product ?? this.product,
      variant: variant ?? this.variant,
      quantity: quantity ?? this.quantity,
      unitPriceCents: unitPriceCents ?? this.unitPriceCents,
      discountCents: discountCents ?? this.discountCents,
      colorName: colorName ?? this.colorName,
      colorHex: colorHex ?? this.colorHex,
      sizeName: sizeName ?? this.sizeName,
      employeeId: clearEmployee ? null : (employeeId ?? this.employeeId),
      employeeName: clearEmployee ? null : (employeeName ?? this.employeeName),
      itemNote: itemNote ?? this.itemNote,
    );
  }

  @override
  List<Object?> get props => [
    tempId,
    product,
    variant,
    quantity,
    unitPriceCents,
    discountCents,
    colorName,
    colorHex,
    sizeName,
    employeeId,
    employeeName,
    itemNote,
  ];

  Decimal get netCentsWithInvoiceDiscount =>
      netCents; // Will be handled by Bloc for invoice-level rounding
}

// ==================== EVENTS ====================

abstract class SaleFormEvent extends Equatable {
  const SaleFormEvent();

  @override
  List<Object?> get props => [];
}

class SaleFormInitialized extends SaleFormEvent {
  final int? saleId;
  final int currencyId;
  final bool enableTaxCalculations;
  final int defaultSalesTaxRateBps;
  final bool taxInclusivePricing;
  final bool allowNegativeStock;
  final bool allowPartialPayments;
  final bool allowDiscounts;
  final double maxDiscountPercent;
  final bool allowBelowCostSales;
  final bool requireCustomerForSales;
  final bool enableLoyaltyPoints;
  final bool enablePromotions;
  final String defaultPaymentMethodStr;
  final bool isEditingPosted;
  const SaleFormInitialized({
    this.saleId,
    required this.currencyId,
    this.enableTaxCalculations = true,
    this.defaultSalesTaxRateBps = 0,
    this.taxInclusivePricing = false,
    this.allowNegativeStock = false,
    this.allowPartialPayments = false,
    this.allowDiscounts = true,
    this.maxDiscountPercent = 100.0,
    this.allowBelowCostSales = false,
    this.requireCustomerForSales = false,
    this.enableLoyaltyPoints = false,
    this.enablePromotions = false,
    this.defaultPaymentMethodStr = 'cash',
    this.isEditingPosted = false,
  });

  @override
  List<Object?> get props => [
    saleId,
    currencyId,
    enableTaxCalculations,
    defaultSalesTaxRateBps,
    allowNegativeStock,
    allowPartialPayments,
    allowDiscounts,
    maxDiscountPercent,
    allowBelowCostSales,
    requireCustomerForSales,
    enableLoyaltyPoints,
    enablePromotions,
    defaultPaymentMethodStr,
    isEditingPosted,
  ];
}

class SaleTaxSettingsChanged extends SaleFormEvent {
  final bool enableTaxCalculations;
  final int defaultSalesTaxRateBps;
  const SaleTaxSettingsChanged({
    required this.enableTaxCalculations,
    required this.defaultSalesTaxRateBps,
  });

  @override
  List<Object?> get props => [enableTaxCalculations, defaultSalesTaxRateBps];
}

class SaleCustomerChanged extends SaleFormEvent {
  final int? customerId;
  final String? customerName;
  const SaleCustomerChanged({this.customerId, this.customerName});

  @override
  List<Object?> get props => [customerId, customerName];
}

class SaleDateChanged extends SaleFormEvent {
  final DateTime date;
  const SaleDateChanged(this.date);

  @override
  List<Object?> get props => [date];
}

class SaleDueDateChanged extends SaleFormEvent {
  final DateTime date;
  const SaleDueDateChanged(this.date);

  @override
  List<Object?> get props => [date];
}

class SaleEmployeeChanged extends SaleFormEvent {
  final int? employeeId;
  final String? employeeName;
  const SaleEmployeeChanged({this.employeeId, this.employeeName});

  @override
  List<Object?> get props => [employeeId, employeeName];
}

class SaleNotesChanged extends SaleFormEvent {
  final String notes;
  const SaleNotesChanged(this.notes);

  @override
  List<Object?> get props => [notes];
}

class SaleDiscountModeChanged extends SaleFormEvent {
  final SaleDiscountMode mode;
  const SaleDiscountModeChanged(this.mode);

  @override
  List<Object?> get props => [mode];
}

class SaleInvoiceDiscountChanged extends SaleFormEvent {
  final Decimal discountCents;
  const SaleInvoiceDiscountChanged(this.discountCents);

  @override
  List<Object?> get props => [discountCents];
}

class SaleLineItemAdded extends SaleFormEvent {
  final Product product;
  final ProductVariant? variant;
  final int quantity;
  final Decimal unitPriceCents;
  final Decimal? discountCents;
  final String? colorName;
  final String? sizeName;

  const SaleLineItemAdded({
    required this.product,
    this.variant,
    required this.quantity,
    required this.unitPriceCents,
    this.discountCents,
    this.colorName,
    this.sizeName,
  });

  @override
  List<Object?> get props => [
    product,
    variant,
    quantity,
    unitPriceCents,
    discountCents,
    colorName,
    sizeName,
  ];
}

class SaleLineItemUpdated extends SaleFormEvent {
  final String tempId;
  final int? quantity;
  final Decimal? unitPriceCents;
  final Decimal? discountCents;
  final int? employeeId;
  final String? employeeName;
  final String? itemNote;
  final bool clearEmployee;

  const SaleLineItemUpdated({
    required this.tempId,
    this.quantity,
    this.unitPriceCents,
    this.discountCents,
    this.employeeId,
    this.employeeName,
    this.itemNote,
    this.clearEmployee = false,
  });

  @override
  List<Object?> get props => [
    tempId,
    quantity,
    unitPriceCents,
    discountCents,
    employeeId,
    employeeName,
    itemNote,
    clearEmployee,
  ];
}

class SaleLineItemRemoved extends SaleFormEvent {
  final String tempId;
  const SaleLineItemRemoved(this.tempId);

  @override
  List<Object?> get props => [tempId];
}

class SaleFormSubmitted extends SaleFormEvent {
  final CheckoutSettlement? settlement;

  const SaleFormSubmitted({this.settlement});

  @override
  List<Object?> get props => [settlement];
}

class SalePaymentMethodChanged extends SaleFormEvent {
  final SalePaymentMethod method;
  const SalePaymentMethodChanged(this.method);

  @override
  List<Object?> get props => [method];
}

class SaleTaxRateChanged extends SaleFormEvent {
  final Decimal taxRatePercent;
  const SaleTaxRateChanged(this.taxRatePercent);

  @override
  List<Object?> get props => [taxRatePercent];
}

class SaleSalespersonModeChanged extends SaleFormEvent {
  final SalespersonMode mode;
  const SaleSalespersonModeChanged(this.mode);

  @override
  List<Object?> get props => [mode];
}

class SalePaidAmountChanged extends SaleFormEvent {
  final Decimal paidAmountCents;
  const SalePaidAmountChanged(this.paidAmountCents);

  @override
  List<Object?> get props => [paidAmountCents];
}

class SaleBelowCostOverrideApproved extends SaleFormEvent {
  final String reason;
  const SaleBelowCostOverrideApproved(this.reason);

  @override
  List<Object?> get props => [reason];
}

class SaleBelowCostWarningDismissed extends SaleFormEvent {
  const SaleBelowCostWarningDismissed();
}

/// Fired when customer changes to load their loyalty data
class SaleLoyaltyDataRequested extends SaleFormEvent {
  final int customerId;
  const SaleLoyaltyDataRequested(this.customerId);

  @override
  List<Object?> get props => [customerId];
}

/// Fired when user toggles loyalty redemption or changes points to redeem
class SaleLoyaltyRedemptionChanged extends SaleFormEvent {
  final bool enabled;
  final int pointsToRedeem;
  const SaleLoyaltyRedemptionChanged({
    required this.enabled,
    required this.pointsToRedeem,
  });

  @override
  List<Object?> get props => [enabled, pointsToRedeem];
}

class SaleOverpaymentHandlingChanged extends SaleFormEvent {
  final SaleOverpaymentHandling handling;
  const SaleOverpaymentHandlingChanged(this.handling);

  @override
  List<Object?> get props => [handling];
}

// ==================== BLOC ====================

class SaleFormBloc extends Bloc<SaleFormEvent, SaleFormState> {
  final SaleRepository _repository;
  final ProductVariantRepository _variantRepository;
  final ProductRepository _productRepository;
  final BelowCostSaleService _belowCostService;
  final AuditLogService _auditService;
  final LoyaltyRepository? _loyaltyRepository;
  final PromotionRepository? _promotionRepository;
  final LanNetworkService? _lan;
  UserRole currentUserRole;
  int? currentUserId;
  int _lineCounter = 0;
  final String _remoteIdempotencyKey = const Uuid().v4();

  bool get _isRemoteClient =>
      _lan?.snapshot.mode == LanMode.client &&
      _lan?.hasRemoteUserSession == true;

  Map<int, String> _colorNames = {};
  Map<int, String?> _colorHexes = {};
  Map<int, String> _sizeNames = {};

  SaleFormBloc(
    this._repository,
    this._variantRepository,
    this._productRepository,
    this._auditService, {
    BelowCostSaleService? belowCostService,
    LoyaltyRepository? loyaltyRepository,
    PromotionRepository? promotionRepository,
    LanNetworkService? lan,
    UserRole userRole = UserRole.cashier,
    int? userId,
  }) : _belowCostService = belowCostService ?? const BelowCostSaleService(),
       _loyaltyRepository = loyaltyRepository,
       _promotionRepository = promotionRepository,
       _lan = lan,
       currentUserId = userId,
       currentUserRole = userRole,
       super(SaleFormState(currencyId: 1, saleDate: DateTime.now())) {
    on<SaleFormInitialized>(_onInitialized);
    on<SaleCustomerChanged>(_onCustomerChanged);
    on<SaleEmployeeChanged>(_onEmployeeChanged);
    on<SaleDateChanged>(_onDateChanged);
    on<SaleNotesChanged>(_onNotesChanged);
    on<SaleDiscountModeChanged>(_onDiscountModeChanged);
    on<SaleInvoiceDiscountChanged>(_onInvoiceDiscountChanged);
    on<SaleLineItemAdded>(_onLineItemAdded);
    on<SaleLineItemUpdated>(_onLineItemUpdated);
    on<SaleLineItemRemoved>(_onLineItemRemoved);
    on<SaleFormSubmitted>(_onSubmitted);
    on<SalePaymentMethodChanged>(_onPaymentMethodChanged);
    on<SaleTaxRateChanged>(_onTaxRateChanged);
    on<SaleSalespersonModeChanged>(_onSalespersonModeChanged);
    on<SalePaidAmountChanged>(_onPaidAmountChanged);
    on<SaleOverpaymentHandlingChanged>(_onOverpaymentHandlingChanged);
    on<SaleDueDateChanged>(_onDueDateChanged);
    on<SaleBelowCostOverrideApproved>(_onBelowCostOverrideApproved);
    on<SaleBelowCostWarningDismissed>(_onBelowCostWarningDismissed);
    on<SaleLoyaltyDataRequested>(_onLoyaltyDataRequested);
    on<SaleLoyaltyRedemptionChanged>(_onLoyaltyRedemptionChanged);
    on<SaleTaxSettingsChanged>(_onTaxSettingsChanged);
  }

  Future<void> _loadColorSizeLookups() async {
    if (_isRemoteClient || _colorNames.isNotEmpty) return;
    try {
      final colors = await _variantRepository.getAllColors();
      _colorNames = {for (final c in colors) c.id: c.name};
      _colorHexes = {for (final c in colors) c.id: c.hexCode};
      final sizes = await _variantRepository.getAllSizes();
      _sizeNames = {for (final s in sizes) s.id: s.name};
    } catch (_) {}
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

  Future<void> _onInitialized(
    SaleFormInitialized event,
    Emitter<SaleFormState> emit,
  ) async {
    await _loadColorSizeLookups();

    SalePaymentMethod parseMethod(String m) {
      if (m == 'card') return SalePaymentMethod.card;
      if (m == 'bank_transfer') return SalePaymentMethod.cheque;
      return SalePaymentMethod.cash;
    }

    final initialPaymentMethod = parseMethod(event.defaultPaymentMethodStr);

    if (_isRemoteClient) {
      if (event.saleId != null) {
        emit(state.copyWith(error: 'sales.remote_edit_not_supported'));
        return;
      }
      try {
        final catalog = await _lan!.fetchRemoteCatalog(limit: 1);
        final remoteRules = catalog.enablePromotions
            ? catalog.promotionRules
                  .map(PromotionRule.fromTransportMap)
                  .where((rule) => rule.validate().isEmpty)
                  .toList(growable: false)
            : const <PromotionRule>[];
        emit(
          state.copyWith(
            currencyId: catalog.currencyId,
            saleNumber: '—',
            enableTaxCalculations: catalog.enableTaxCalculations,
            defaultSalesTaxRateBps: catalog.defaultSalesTaxRateBps,
            taxInclusivePricing: catalog.taxInclusivePricing,
            allowNegativeStock: catalog.allowNegativeStock,
            allowPartialPayments: catalog.allowPartialPayments,
            allowDiscounts: catalog.allowDiscounts,
            maxDiscountPercent: catalog.maxDiscountPercent,
            allowBelowCostSales: catalog.allowBelowCostSales,
            masterReceiptHeaderText: catalog.receiptHeaderText,
            masterReceiptFooterText: catalog.receiptFooterText,
            requireCustomerForSales: catalog.requireCustomerForSales,
            enableLoyaltyPoints: false,
            enablePromotions: catalog.enablePromotions,
            promotionRules: remoteRules,
            paymentMethod: initialPaymentMethod,
          ),
        );
      } on LanBusinessException catch (error) {
        emit(state.copyWith(error: error.message));
      } catch (error) {
        emit(state.copyWith(error: error.toString()));
      }
      return;
    }

    if (event.saleId == null) {
      // New sale: generate next invoice number
      final promotionRules = event.enablePromotions
          ? await _promotionRepository?.loadActiveRules() ??
                const <PromotionRule>[]
          : const <PromotionRule>[];
      try {
        final nextNumber = await _repository.generateInvoiceNumber();
        emit(
          state.copyWith(
            currencyId: event.currencyId,
            saleNumber: nextNumber,
            enableTaxCalculations: event.enableTaxCalculations,
            defaultSalesTaxRateBps: event.defaultSalesTaxRateBps,
            allowNegativeStock: event.allowNegativeStock,
            allowPartialPayments: event.allowPartialPayments,
            allowDiscounts: event.allowDiscounts,
            maxDiscountPercent: event.maxDiscountPercent,
            allowBelowCostSales: event.allowBelowCostSales,
            requireCustomerForSales: event.requireCustomerForSales,
            enableLoyaltyPoints: event.enableLoyaltyPoints,
            enablePromotions: event.enablePromotions,
            promotionRules: promotionRules,
            paymentMethod: initialPaymentMethod,
          ),
        );
      } catch (_) {
        emit(
          state.copyWith(
            currencyId: event.currencyId,
            enableTaxCalculations: event.enableTaxCalculations,
            defaultSalesTaxRateBps: event.defaultSalesTaxRateBps,
            taxInclusivePricing: event.taxInclusivePricing,
            allowNegativeStock: event.allowNegativeStock,
            allowPartialPayments: event.allowPartialPayments,
            allowDiscounts: event.allowDiscounts,
            maxDiscountPercent: event.maxDiscountPercent,
            allowBelowCostSales: event.allowBelowCostSales,
            requireCustomerForSales: event.requireCustomerForSales,
            enableLoyaltyPoints: event.enableLoyaltyPoints,
            enablePromotions: event.enablePromotions,
            promotionRules: promotionRules,
            paymentMethod: initialPaymentMethod,
          ),
        );
      }
      return;
    }

    emit(
      state.copyWith(
        saleId: event.saleId,
        currencyId: event.currencyId,
        enableTaxCalculations: event.enableTaxCalculations,
        defaultSalesTaxRateBps: event.defaultSalesTaxRateBps,
        taxInclusivePricing: event.taxInclusivePricing,
        allowNegativeStock: event.allowNegativeStock,
        allowPartialPayments: event.allowPartialPayments,
        allowDiscounts: event.allowDiscounts,
        maxDiscountPercent: event.maxDiscountPercent,
        allowBelowCostSales: event.allowBelowCostSales,
        requireCustomerForSales: event.requireCustomerForSales,
        isEditingPosted: event.isEditingPosted,
        paymentMethod: initialPaymentMethod,
      ),
    );

    try {
      final sale = await _repository.getSaleById(event.saleId!);
      if (sale == null) {
        emit(state.copyWith(error: 'sales.not_found'));
        return;
      }

      final items = await _repository.getSaleItems(event.saleId!);
      _lineCounter = items.length;

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
          costCents: realProduct?.costCents ?? Decimal.zero,
          priceCents: i.unitPriceCents,
          wholesalePriceCents: realProduct?.wholesalePriceCents,
          stockQuantity: realProduct?.stockQuantity ?? 0,
          minQuantity: realProduct?.minQuantity ?? 0,
          hasVariants: i.variantId != null,
          isTaxable: realProduct?.isTaxable ?? false,
          purchaseTaxRateBps: realProduct?.purchaseTaxRateBps ?? 0,
          salesTaxRateBps: realProduct?.salesTaxRateBps ?? 0,
          isActive: realProduct?.isActive ?? true,
          trackInventory: realProduct?.trackInventory ?? true,
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
                    costCents: Decimal.zero,
                    priceCents: i.unitPriceCents,
                    wholesalePriceCents: null,
                    priceAdjustmentCents: Decimal.zero,
                    stockQuantity: 0,
                    isActive: true,
                  ));

        return SaleLineItem(
          tempId: _generateTempId(),
          product: product,
          variant: variant,
          quantity: i.quantity,
          unitPriceCents: i.unitPriceCents,
          discountCents: i.discountCents,
          colorName: _resolveColorName(variant?.colorId),
          colorHex: _resolveColorHex(variant?.colorId),
          sizeName: _resolveSizeName(variant?.sizeId),
        );
      }).toList();

      emit(
        state.copyWith(
          saleId: sale.id,
          saleNumber: sale.invoiceNumber,
          customerId: sale.customerId,
          customerName: sale.customerName,
          employeeId: sale.employeeId,
          employeeName: sale.employeeName,
          currencyId: sale.currencyId,
          saleDate: sale.saleDate,
          items: mappedItems,
          discountMode: SaleDiscountMode.perItem,
          invoiceDiscountCents: Decimal.zero,
        ),
      );
    } catch (e) {
      emit(state.copyWith(error: e.toString()));
    }
  }

  Future<void> _onCustomerChanged(
    SaleCustomerChanged event,
    Emitter<SaleFormState> emit,
  ) async {
    if (event.customerId == null) {
      emit(state.copyWith(clearCustomer: true, clearLoyalty: true));
    } else {
      emit(
        state.copyWith(
          customerId: event.customerId,
          customerName: event.customerName,
          clearLoyalty: true,
        ),
      );
      // Auto-load loyalty data for the selected customer
      if (!_isRemoteClient && _loyaltyRepository != null) {
        add(SaleLoyaltyDataRequested(event.customerId!));
      }
    }
  }

  void _onEmployeeChanged(
    SaleEmployeeChanged event,
    Emitter<SaleFormState> emit,
  ) {
    if (event.employeeId == null) {
      emit(state.copyWith(employeeId: 0, employeeName: ''));
    } else {
      emit(
        state.copyWith(
          employeeId: event.employeeId,
          employeeName: event.employeeName,
        ),
      );
    }
  }

  void _onDateChanged(SaleDateChanged event, Emitter<SaleFormState> emit) {
    emit(state.copyWith(saleDate: event.date));
  }

  void _onNotesChanged(SaleNotesChanged event, Emitter<SaleFormState> emit) {
    emit(state.copyWith(notes: event.notes));
  }

  void _onDiscountModeChanged(
    SaleDiscountModeChanged event,
    Emitter<SaleFormState> emit,
  ) {
    // Phase-14 mode-exclusivity (state-level): mirror the purchase-side
    // fix in `PurchaseFormBloc._onDiscountModeChanged` and the original
    // `SaleAdjReturnFormBloc._onDiscountModeChanged` reference. The
    // engine already masks the unused mode at compute time, but stale
    // per-line `discountCents` on `state.items` would silently re-activate
    // on a back-toggle to `perItem`, causing a "double-discount the user
    // can't notice" — exactly the symmetry bug the user reported on
    // purchases and asked us to verify on sales.
    //
    // Switching INTO `invoice` mode -> wipe per-line `discountCents`.
    // Switching INTO `perItem`  mode -> wipe invoice-level discount
    //                                    (already done; kept for symmetry).
    final isInvoice = event.mode == SaleDiscountMode.invoice;
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
        belowCostOverrides: const [],
        hasUnsavedChanges: true,
      ),
    );
  }

  void _onInvoiceDiscountChanged(
    SaleInvoiceDiscountChanged event,
    Emitter<SaleFormState> emit,
  ) {
    emit(
      state.copyWith(
        invoiceDiscountCents: event.discountCents,
        belowCostOverrides: const [],
        clearBelowCostWarning: true,
      ),
    );
  }

  Future<void> _onLineItemAdded(
    SaleLineItemAdded event,
    Emitter<SaleFormState> emit,
  ) async {
    await _loadColorSizeLookups();

    ProductVariant? resolvedVariant = event.variant;
    if (!_isRemoteClient && resolvedVariant == null) {
      try {
        resolvedVariant = await _variantRepository.getDefaultVariantByProduct(
          event.product.id,
        );
      } catch (_) {}
    }

    final newItem = SaleLineItem(
      tempId: _generateTempId(),
      product: event.product,
      variant: resolvedVariant,
      quantity: event.quantity,
      unitPriceCents: event.unitPriceCents,
      discountCents: event.discountCents,
      colorName: event.colorName ?? _resolveColorName(resolvedVariant?.colorId),
      colorHex: _resolveColorHex(resolvedVariant?.colorId),
      sizeName: event.sizeName ?? _resolveSizeName(resolvedVariant?.sizeId),
    );

    // Below-cost check: use variant cost if available, else product cost
    final costCents = resolvedVariant?.costCents ?? event.product.costCents;
    final check = _belowCostService.check(
      costCents: costCents,
      sellingPriceCents: event.unitPriceCents,
      productName: newItem.displayName,
      productId: event.product.id,
      lineTempId: newItem.tempId,
      userRole: currentUserRole,
      allowOverride: state.allowBelowCostSales,
    );

    if (check.isBelowCost) {
      // Add item but show warning
      emit(
        state.copyWith(
          items: [...state.items, newItem],
          belowCostWarning: check,
          hasUnsavedChanges: true,
        ),
      );
    } else {
      emit(
        state.copyWith(
          items: [...state.items, newItem],
          hasUnsavedChanges: true,
        ),
      );
    }
  }

  void _onLineItemUpdated(
    SaleLineItemUpdated event,
    Emitter<SaleFormState> emit,
  ) {
    final pricingChanged =
        event.quantity != null ||
        event.unitPriceCents != null ||
        event.discountCents != null;
    final updatedItems = state.items.map((item) {
      if (item.tempId == event.tempId) {
        return item.copyWith(
          quantity: event.quantity,
          unitPriceCents: event.unitPriceCents,
          discountCents: event.discountCents,
          employeeId: event.employeeId,
          employeeName: event.employeeName,
          itemNote: event.itemNote,
          clearEmployee: event.clearEmployee,
        );
      }
      return item;
    }).toList();
    final filteredOverrides = pricingChanged
        ? state.belowCostOverrides
              .where((value) => value.tempId != event.tempId)
              .toList()
        : state.belowCostOverrides;
    final nextState = state.copyWith(
      items: updatedItems,
      belowCostOverrides: filteredOverrides,
      clearBelowCostWarning: pricingChanged,
      hasUnsavedChanges: true,
    );
    emit(nextState);

    if (!pricingChanged) return;
    final lineIndex = updatedItems.indexWhere(
      (item) => item.tempId == event.tempId,
    );
    if (lineIndex < 0) return;
    final item = updatedItems[lineIndex];
    final costCents = item.variant?.costCents ?? item.product.costCents;
    if (costCents <= Decimal.zero || item.quantity <= 0) return;

    final lineNet = nextState.pricing.lines[lineIndex].adjustedNet;
    final totalCost = Money.fromDecimalCents(
      costCents,
    ).multiplyRatio(item.quantity, item.product.quantityScale).round();
    if (lineNet.cents >= totalCost.cents) return;

    final effectiveUnitNet = lineNet
        .multiplyRatio(item.product.quantityScale, item.quantity)
        .decimalCents;
    final check = _belowCostService.check(
      costCents: costCents,
      sellingPriceCents: effectiveUnitNet,
      productName: item.displayName,
      productId: item.product.id,
      lineTempId: item.tempId,
      userRole: currentUserRole,
      allowOverride: state.allowBelowCostSales,
    );
    emit(
      state.copyWith(
        belowCostWarning: check,
        belowCostOverrides: filteredOverrides,
      ),
    );
  }

  void _onLineItemRemoved(
    SaleLineItemRemoved event,
    Emitter<SaleFormState> emit,
  ) {
    final updatedItems = state.items
        .where((item) => item.tempId != event.tempId)
        .toList();
    emit(state.copyWith(items: updatedItems, hasUnsavedChanges: true));
  }

  Future<void> _onSubmitted(
    SaleFormSubmitted event,
    Emitter<SaleFormState> emit,
  ) async {
    if (!_isRemoteClient &&
        state.saleId == null &&
        state.enablePromotions &&
        _promotionRepository != null) {
      final before = state.promotionEvaluation;
      final freshRules = await _promotionRepository.loadActiveRules();
      final refreshed = state.copyWith(promotionRules: freshRules);
      String signature(PromotionEvaluationResult value) {
        final rows =
            value.applications
                .map(
                  (row) =>
                      '${row.promotionId}:${row.version}:${row.totalDiscount.cents}',
                )
                .toList()
              ..sort();
        return rows.join('|');
      }

      if (signature(before) != signature(refreshed.promotionEvaluation)) {
        emit(
          refreshed.copyWith(
            error: 'promotions.errors.rules_updated',
            isSubmitting: false,
          ),
        );
        return;
      }
      emit(refreshed);
    }

    if (state.items.isEmpty) {
      emit(state.copyWith(error: 'Please add at least one item'));
      return;
    }

    // 1. Require Customer Validation
    if (state.requireCustomerForSales && state.customerId == null) {
      emit(state.copyWith(error: 'sales.customer_required'));
      return;
    }

    // 2. Discount Validations
    if (state.totalDiscountCents > Decimal.zero) {
      if (!state.allowDiscounts) {
        emit(state.copyWith(error: 'sales.discounts_disabled'));
        return;
      }
      if (state.maxDiscountPercent < 100 &&
          state.subtotalCents > Decimal.zero) {
        final currentDiscountPercent =
            (state.totalDiscountCents.toDouble() /
                state.subtotalCents.toDouble()) *
            100;
        if (currentDiscountPercent > state.maxDiscountPercent) {
          emit(state.copyWith(error: 'sales.discount_exceeds_max'));
          return;
        }
      }
    }

    // 3. Below-cost final gate. Compare the final pre-tax net after all
    // item/invoice discounts against the scaled cost of the sold quantity.
    final overriddenTempIds = state.belowCostOverrides
        .map((o) => o.tempId)
        .toSet();
    final profitableFreeBundleLineIds =
        PromotionMarginPolicy.profitableFreeBundleLineIds(
          evaluation: state.promotionEvaluation,
          lines: [
            for (var index = 0; index < state.items.length; index++)
              PromotionMarginLine(
                lineId: state.items[index].tempId,
                quantity: state.items[index].quantity,
                quantityScale: state.items[index].product.quantityScale,
                unitCost: Money.fromDecimalCents(
                  state.items[index].variant?.costCents ??
                      state.items[index].product.costCents,
                ),
                netBeforePromotions:
                    state.manualPricing.lines[index].adjustedNet,
              ),
          ],
        );
    for (var index = 0; index < state.items.length; index++) {
      final item = state.items[index];
      final costCents = item.variant?.costCents ?? item.product.costCents;
      if (costCents <= Decimal.zero || item.quantity <= 0) continue;

      final lineNet = state.pricing.lines[index].adjustedNet;
      final totalCost = Money.fromDecimalCents(
        costCents,
      ).multiplyRatio(item.quantity, item.product.quantityScale).round();
      if (lineNet.cents >= totalCost.cents ||
          overriddenTempIds.contains(item.tempId) ||
          profitableFreeBundleLineIds.contains(item.tempId)) {
        continue;
      }

      final effectiveUnitNet = lineNet
          .multiplyRatio(item.product.quantityScale, item.quantity)
          .decimalCents;
      final check = _belowCostService.check(
        costCents: costCents,
        sellingPriceCents: effectiveUnitNet,
        productName: item.displayName,
        productId: item.product.id,
        lineTempId: item.tempId,
        userRole: currentUserRole,
        allowOverride: state.allowBelowCostSales,
      );
      emit(state.copyWith(belowCostWarning: check));
      return;
    }

    // 4. Payment / Partial Payment Validation
    // A physical cheque must have a due date before it can enter the register.
    if (event.settlement == null &&
        state.paymentMethod == SalePaymentMethod.cheque &&
        state.dueDate == null) {
      emit(state.copyWith(error: 'sales.cheque_due_date_required'));
      return;
    }

    // Card and cheque are settled in full; cheque uses the clearing account
    // until bank clearance. Only cash needs the insufficient-funds check.
    if (state.remainingCents > Decimal.zero &&
        state.paymentMethod == SalePaymentMethod.cash) {
      if (!state.allowPartialPayments) {
        emit(state.copyWith(error: 'sales.cash_insufficient'));
        return;
      }
    }

    emit(state.copyWith(isSubmitting: true, error: null));

    try {
      final settlement = event.settlement;
      settlement?.validate(
        invoiceTotalCents: state.totalCents.toBigInt().toInt(),
      );
      // SoT for the per-line breakdown is the state-level pricing engine
      // result: it has already done subtotal → discount → net → invoice-
      // discount allocation (largest-remainder) → tax-on-adjusted-net.
      // No parallel arithmetic path lives here, by design (ADR 0002 §2).
      final lineItems = state.items;
      final pricing = state.pricing;

      final items = <SaleItemInput>[];
      for (int idx = 0; idx < lineItems.length; idx++) {
        final item = lineItems[idx];
        final line = pricing.lines[idx];
        items.add(
          SaleItemInput(
            lineId: item.tempId,
            productId: item.product.id,
            variantId: item.variant?.id,
            quantity: item.quantity,
            quantityScale: item.product.quantityScale,
            measurementType: item.product.measurementType,
            unitPriceCents: item.unitPriceCents,
            subtotalCents: Decimal.fromInt(line.subtotal.cents),
            // Total per-line discount = entered line discount + share of
            // the invoice-level discount (zero in `perItem` mode).
            discountCents: Decimal.fromInt(line.totalLineDiscount.cents),
            taxCents: Decimal.fromInt(line.tax.cents),
            totalCents: Decimal.fromInt(line.total.cents),
            employeeId: item.employeeId,
            employeeName: item.employeeName,
          ),
        );
      }

      final paymentMethodStr =
          settlement?.headerPaymentMethod ?? state.paymentMethod.name;

      // Determine effective paid amount:
      // - cash: depends on overpayment handling
      //   - returnChange: cap at totalCents (excess is returned as cash change)
      //   - addToBalance: use full paidAmountCents (excess goes to customer credit)
      // - card: auto-set to total (fully settled)
      // - credit: 0 (full amount goes to customer balance)
      // - cheque: 0 until bank clearance confirms the payment
      final effectivePaidCents = settlement != null
          ? Decimal.fromInt(settlement.totalSettledCents)
          : switch (state.paymentMethod) {
              SalePaymentMethod.cash => () {
                // If overpaying and user chose to return change, cap at total
                if (state.paidAmountCents > state.totalCents &&
                    state.overpaymentHandling ==
                        SaleOverpaymentHandling.returnChange) {
                  return state.totalCents;
                }
                // Otherwise use full paid amount (either exact payment or add to balance)
                return state.paidAmountCents;
              }(),
              SalePaymentMethod.card => state.totalCents,
              SalePaymentMethod.credit => Decimal.zero,
              SalePaymentMethod.cheque => Decimal.zero,
            };

      if (_isRemoteClient) {
        if (state.saleId != null) {
          throw const LanBusinessException(
            'remote_edit_not_supported',
            'Editing an existing sale over the network is not available yet.',
            statusCode: 409,
          );
        }
        final remoteLines = <LanSaleLineRequest>[];
        for (var index = 0; index < state.items.length; index++) {
          final item = state.items[index];
          final retail = item.variant?.priceCents ?? item.product.priceCents;
          final wholesale =
              item.variant?.wholesalePriceCents ??
              item.product.wholesalePriceCents;
          final String priceTier;
          if (wholesale != null && item.unitPriceCents == wholesale) {
            priceTier = 'wholesale';
          } else if (item.unitPriceCents == retail) {
            priceTier = 'retail';
          } else {
            throw const LanBusinessException(
              'remote_price_override_not_supported',
              'Choose the configured retail or wholesale price.',
              statusCode: 409,
            );
          }
          remoteLines.add(
            LanSaleLineRequest(
              productId: item.product.id,
              variantId: item.variant?.id,
              quantity: item.quantity,
              priceTier: priceTier,
              salespersonId: item.employeeId,
              discountType:
                  state.manualPricing.lines[index].totalLineDiscount.cents == 0
                  ? 'none'
                  : 'fixed',
              discountValue:
                  state.manualPricing.lines[index].totalLineDiscount.cents,
            ),
          );
        }
        final result = await _lan!.submitRemoteSale(
          LanSaleRequest(
            idempotencyKey: _remoteIdempotencyKey,
            customerId: state.customerId,
            salespersonId: state.employeeId,
            paymentMethod: paymentMethodStr,
            paidAmountCents: effectivePaidCents.toBigInt().toInt(),
            notes: state.notes,
            belowCostOverrideReason: state.belowCostOverrides.isEmpty
                ? null
                : state.belowCostOverrides
                      .map((override) => override.reason)
                      .join(' | '),
            lines: remoteLines,
            payments: settlement == null
                ? const []
                : settlement.payments
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
            saleId: result.saleId,
            saleNumber: result.invoiceNumber,
            masterReceiptHeaderText: result.receiptHeaderText,
            masterReceiptFooterText: result.receiptFooterText,
            isSubmitting: false,
            isSuccess: true,
            hasUnsavedChanges: false,
          ),
        );
        return;
      }

      if (state.saleId == null) {
        final saleId = await _repository.createSale(
          customerId: state.customerId,
          employeeId: state.employeeId,
          currencyId: state.currencyId,
          subtotalCents: state.subtotalCents,
          discountCents: state.totalDiscountCents,
          taxCents: state.taxCents,
          totalCents: state.totalCents,
          paidAmountCents: effectivePaidCents,
          paymentMethod: paymentMethodStr,
          items: items,
          notes: state.notes,
          saleDate: state.saleDate,
          dueDate: state.dueDate,
          allowNegativeStock: state.allowNegativeStock,
          taxInclusiveAtPost: state.taxInclusivePricing,
          appliedPromotions: state.promotionEvaluation.applications,
          initialPayments: settlement?.payments ?? const [],
        );

        await _logBelowCostOverrides(saleId);

        // Redeem loyalty points if applicable (non-critical, outside transaction)
        if (state.loyaltyRedemptionEnabled &&
            state.loyaltyPointsToRedeem > 0 &&
            state.customerId != null &&
            _loyaltyRepository != null) {
          try {
            await _loyaltyRepository.redeemPoints(
              customerId: state.customerId!,
              points: state.loyaltyPointsToRedeem,
              reason: 'Points redeemed at checkout for sale #$saleId',
              referenceId: saleId,
              referenceType: 'sale_redemption',
            );
          } catch (_) {
            // Loyalty redemption failure should not block the sale
          }
        }

        CrashlyticsService.instance.logAction('sale_created', {
          'sale_id': saleId.toString(),
          'total_cents': state.totalCents.toString(),
          'items_count': state.items.length.toString(),
        });
        emit(
          state.copyWith(
            saleId: saleId,
            isSubmitting: false,
            isSuccess: true,
            hasUnsavedChanges: false,
          ),
        );
      } else if (state.isEditingPosted) {
        // Editing a posted sale: void original and create new
        final newSaleId = await _repository.editPostedSale(
          originalSaleId: state.saleId!,
          customerId: state.customerId,
          employeeId: state.employeeId,
          currencyId: state.currencyId,
          subtotalCents: state.subtotalCents,
          discountCents: state.totalDiscountCents,
          taxCents: state.taxCents,
          totalCents: state.totalCents,
          paidAmountCents: effectivePaidCents,
          paymentMethod: paymentMethodStr,
          items: items,
          notes: state.notes,
          saleDate: state.saleDate,
          dueDate: state.dueDate,
          allowNegativeStock: state.allowNegativeStock,
          taxInclusiveAtPost: state.taxInclusivePricing,
        );

        CrashlyticsService.instance.logAction('sale_edited_posted', {
          'sale_id': newSaleId.toString(),
          'original_sale_id': state.saleId.toString(),
        });
        await _logBelowCostOverrides(newSaleId);
        emit(
          state.copyWith(
            saleId: newSaleId,
            isSubmitting: false,
            isSuccess: true,
            hasUnsavedChanges: false,
          ),
        );
      } else {
        final ok = await _repository.updateSale(
          saleId: state.saleId!,
          customerId: state.customerId,
          employeeId: state.employeeId,
          currencyId: state.currencyId,
          subtotalCents: state.subtotalCents,
          discountCents: state.totalDiscountCents,
          taxCents: state.taxCents,
          totalCents: state.totalCents,
          paidAmountCents: effectivePaidCents,
          paymentMethod: paymentMethodStr,
          items: items,
          notes: state.notes,
          saleDate: state.saleDate,
          dueDate: state.dueDate,
          taxInclusiveAtPost: state.taxInclusivePricing,
        );

        if (!ok) throw Exception('Failed to update sale');

        CrashlyticsService.instance.logAction('sale_updated', {
          'sale_id': state.saleId.toString(),
        });
        await _logBelowCostOverrides(state.saleId!);
        emit(
          state.copyWith(
            isSubmitting: false,
            isSuccess: true,
            hasUnsavedChanges: false,
          ),
        );
      }
    } on FreeQuotaExceededException catch (e) {
      // Free-tier cumulative cap reached. Surface a recognizable code so the
      // screen can present the paywall instead of a generic error.
      emit(
        state.copyWith(
          isSubmitting: false,
          error: 'quota_exceeded:sales:${e.limit}',
        ),
      );
    } on LanBusinessException catch (e, st) {
      CrashlyticsService.instance.recordError(
        e,
        stackTrace: st,
        reason: 'SaleFormBloc._onSubmitted LAN request rejected',
      );
      final warning = _belowCostWarningFromRemoteError(e);
      if (warning != null) {
        emit(
          state.copyWith(
            isSubmitting: false,
            error: null,
            belowCostWarning: warning,
          ),
        );
        return;
      }
      final errorKey = switch (e.code) {
        'sale_below_cost' => 'settings.network.sale.below_cost_rejected',
        'sale_below_cost_reason_required' =>
          'settings.network.sale.below_cost_reason_required',
        'discount_exceeds_max' => 'settings.network.sale.discount_exceeds_max',
        _ => e.message,
      };
      emit(state.copyWith(isSubmitting: false, error: errorKey));
    } catch (e, st) {
      CrashlyticsService.instance.recordError(
        e,
        stackTrace: st,
        reason: 'SaleFormBloc._onSubmitted failed',
      );
      emit(state.copyWith(isSubmitting: false, error: e.toString()));
    }
  }

  BelowCostCheckResult? _belowCostWarningFromRemoteError(
    LanBusinessException error,
  ) {
    if (!_isRemoteClient ||
        (error.code != 'sale_below_cost' &&
            error.code != 'sale_below_cost_reason_required')) {
      return null;
    }

    final details = error.details;
    final rawLineIndex = details['lineIndex'];
    final lineIndex = rawLineIndex is num
        ? rawLineIndex.toInt()
        : int.tryParse(rawLineIndex?.toString() ?? '');
    SaleLineItem? item;
    if (lineIndex != null && lineIndex >= 0 && lineIndex < state.items.length) {
      item = state.items[lineIndex];
    } else {
      final rawProductId = details['productId'];
      final productId = rawProductId is num
          ? rawProductId.toInt()
          : int.tryParse(rawProductId?.toString() ?? '');
      if (productId != null) {
        final index = state.items.indexWhere(
          (candidate) => candidate.product.id == productId,
        );
        if (index >= 0) item = state.items[index];
      }
    }
    // Older masters do not send structured warning details. Keep their
    // localized snackbar fallback instead of guessing and removing a line.
    if (item == null) return null;

    int amount(String key) {
      final value = details[key];
      return value is num ? value.toInt() : int.tryParse('$value') ?? 0;
    }

    final costCents = amount('costCents');
    final sellingPriceCents = amount('sellingPriceCents');
    final lossCents = amount('lossCents');
    final rawLossPercent = details['lossPercent'];
    final lossPercent = rawLossPercent is num
        ? rawLossPercent.toDouble()
        : double.tryParse(rawLossPercent?.toString() ?? '') ?? 0;
    final serverAllowsOverride = details['canOverride'] == true;

    return BelowCostCheckResult(
      isBelowCost: true,
      costCents: Decimal.fromInt(costCents),
      sellingPriceCents: Decimal.fromInt(sellingPriceCents),
      lossCents: Decimal.fromInt(lossCents),
      productName: details['productName']?.toString().trim().isNotEmpty == true
          ? details['productName'].toString().trim()
          : item.displayName,
      productId: item.product.id,
      lineTempId: item.tempId,
      canOverride:
          serverAllowsOverride &&
          BelowCostSaleService.canRoleOverride(currentUserRole),
      exceedsThreshold: details['exceedsThreshold'] == true,
      lossPercent: lossPercent,
    );
  }

  void _onPaymentMethodChanged(
    SalePaymentMethodChanged event,
    Emitter<SaleFormState> emit,
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
    SaleTaxRateChanged event,
    Emitter<SaleFormState> emit,
  ) {
    emit(state.copyWith(taxRatePercent: event.taxRatePercent));
  }

  void _onSalespersonModeChanged(
    SaleSalespersonModeChanged event,
    Emitter<SaleFormState> emit,
  ) {
    emit(state.copyWith(salespersonMode: event.mode));
  }

  void _onPaidAmountChanged(
    SalePaidAmountChanged event,
    Emitter<SaleFormState> emit,
  ) {
    emit(state.copyWith(paidAmountCents: event.paidAmountCents));
  }

  void _onOverpaymentHandlingChanged(
    SaleOverpaymentHandlingChanged event,
    Emitter<SaleFormState> emit,
  ) {
    emit(state.copyWith(overpaymentHandling: event.handling));
  }

  void _onDueDateChanged(
    SaleDueDateChanged event,
    Emitter<SaleFormState> emit,
  ) {
    emit(state.copyWith(dueDate: event.date));
  }

  void _onBelowCostOverrideApproved(
    SaleBelowCostOverrideApproved event,
    Emitter<SaleFormState> emit,
  ) {
    final warning = state.belowCostWarning;
    if (warning == null || !warning.isBelowCost) return;

    final matchingIndex = state.items.indexWhere(
      (item) => item.tempId == warning.lineTempId,
    );
    if (matchingIndex < 0) {
      emit(state.copyWith(clearBelowCostWarning: true));
      return;
    }
    final matchingItem = state.items[matchingIndex];

    final override = BelowCostOverride(
      tempId: matchingItem.tempId,
      productId: warning.productId,
      productName: warning.productName,
      costCents: warning.costCents,
      sellingPriceCents: warning.sellingPriceCents,
      lossCents: warning.lossCents,
      reason: event.reason,
    );

    emit(
      state.copyWith(
        clearBelowCostWarning: true,
        belowCostOverrides: [...state.belowCostOverrides, override],
      ),
    );
  }

  Future<void> _logBelowCostOverrides(int saleId) async {
    for (final override in state.belowCostOverrides) {
      try {
        await _auditService.logBelowCostOverride(
          saleId: saleId,
          productId: override.productId,
          productName: override.productName,
          costCents: override.costCents.toBigInt().toInt(),
          sellingPriceCents: override.sellingPriceCents.toBigInt().toInt(),
          lossCents: override.lossCents.toBigInt().toInt(),
          reason: override.reason,
          userId: currentUserId,
          userRole: currentUserRole.name,
        );
      } catch (_) {
        // The sale and its balanced journals remain authoritative even if
        // the secondary audit sink is temporarily unavailable.
      }
    }
  }

  void _onBelowCostWarningDismissed(
    SaleBelowCostWarningDismissed event,
    Emitter<SaleFormState> emit,
  ) {
    final warning = state.belowCostWarning;
    if (warning == null) return;

    if (!warning.canOverride) {
      // Cashier/Salesperson: remove the last item that triggered the warning
      final updatedItems = List<SaleLineItem>.from(state.items);
      final idx = updatedItems.indexWhere(
        (item) => item.tempId == warning.lineTempId,
      );
      if (idx >= 0) updatedItems.removeAt(idx);
      emit(state.copyWith(items: updatedItems, clearBelowCostWarning: true));
    } else {
      // Manager/Owner dismissed without override: remove the item
      final updatedItems = List<SaleLineItem>.from(state.items);
      final idx = updatedItems.indexWhere(
        (item) => item.tempId == warning.lineTempId,
      );
      if (idx >= 0) updatedItems.removeAt(idx);
      emit(state.copyWith(items: updatedItems, clearBelowCostWarning: true));
    }
  }

  Future<void> _onLoyaltyDataRequested(
    SaleLoyaltyDataRequested event,
    Emitter<SaleFormState> emit,
  ) async {
    if (_isRemoteClient || _loyaltyRepository == null) return;
    try {
      final settings = await _loyaltyRepository.getLoyaltySettings();
      if (state.customerId != event.customerId) return;
      if (settings == null ||
          !settings.isEnabled ||
          !settings.allowPointsRedemption) {
        emit(state.copyWith(clearLoyalty: true));
        return;
      }

      final summary = await _loyaltyRepository.getCustomerLoyaltySummary(
        event.customerId,
      );
      if (state.customerId != event.customerId) return;
      if (summary == null) {
        emit(state.copyWith(clearLoyalty: true));
        return;
      }

      emit(
        state.copyWith(
          loyaltyPointsBalance: summary.pointsBalance,
          loyaltySettings: settings,
          loyaltyPointsToRedeem: 0,
          loyaltyDiscountCents: 0,
          loyaltyRedemptionEnabled: false,
        ),
      );
    } catch (_) {
      if (state.customerId == event.customerId) {
        emit(state.copyWith(clearLoyalty: true));
      }
    }
  }

  void _onLoyaltyRedemptionChanged(
    SaleLoyaltyRedemptionChanged event,
    Emitter<SaleFormState> emit,
  ) {
    final settings = state.loyaltySettings;
    if (settings == null) return;

    if (!event.enabled) {
      emit(
        state.copyWith(
          loyaltyRedemptionEnabled: false,
          loyaltyPointsToRedeem: 0,
          loyaltyDiscountCents: 0,
        ),
      );
      return;
    }

    // Calculate max redeemable points based on settings constraints
    final pointValueCents = settings.pointValueCents;
    final maxPercentBps = settings.maxRedemptionPercentBps;
    final invoiceTotal = state.totalBeforeLoyaltyCents.toBigInt().toInt();

    // Max discount from percentage cap: (invoiceTotal * maxPercentBps) / 10000
    final maxDiscountFromPercent = (invoiceTotal * maxPercentBps) ~/ 10000;

    // Max discount from available points: pointsBalance * pointValueCents
    final maxDiscountFromPoints = state.loyaltyPointsBalance * pointValueCents;

    // The actual max discount is the minimum of both caps and the invoice total
    final maxDiscount = [
      maxDiscountFromPercent,
      maxDiscountFromPoints,
      invoiceTotal,
    ].reduce((a, b) => a < b ? a : b);

    // Max redeemable points = maxDiscount / pointValueCents
    final maxRedeemablePoints = pointValueCents > 0
        ? maxDiscount ~/ pointValueCents
        : 0;

    // Clamp requested points to valid range
    final pointsToRedeem = event.pointsToRedeem.clamp(0, maxRedeemablePoints);
    final discountCents = pointsToRedeem * pointValueCents;

    emit(
      state.copyWith(
        loyaltyRedemptionEnabled: true,
        loyaltyPointsToRedeem: pointsToRedeem,
        loyaltyDiscountCents: discountCents,
      ),
    );
  }

  // _distributeProportionally removed — use TaxCalculationService.distributeProportionally()

  void _onTaxSettingsChanged(
    SaleTaxSettingsChanged event,
    Emitter<SaleFormState> emit,
  ) {
    emit(
      state.copyWith(
        enableTaxCalculations: event.enableTaxCalculations,
        defaultSalesTaxRateBps: event.defaultSalesTaxRateBps,
      ),
    );
  }
}
