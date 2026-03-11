import 'package:decimal/decimal.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/database/app_database.dart' show LoyaltySettings;
import '../../../../core/services/audit_log_service.dart';
import '../../../../core/services/below_cost_sale_service.dart';
import '../../../../core/services/crashlytics_service.dart';
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
  // Global inventory settings
  final bool allowNegativeStock;
  // Editing posted sale flag
  final bool isEditingPosted;

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
    this.allowNegativeStock = false,
    this.isEditingPosted = false,
  }) : invoiceDiscountCents = invoiceDiscountCents ?? Decimal.zero,
       taxRatePercent = taxRatePercent ?? Decimal.zero,
       paidAmountCents = paidAmountCents ?? Decimal.zero;

  Decimal get subtotalCents => items.fold(
        Decimal.zero,
        (sum, item) => sum + item.subtotalCents,
      );

  Decimal get itemDiscountCents => items.fold(
        Decimal.zero,
        (sum, item) => sum + item.discountCents,
      );

  Decimal get totalDiscountCents {
    if (discountMode == SaleDiscountMode.invoice) {
      return invoiceDiscountCents;
    }
    return itemDiscountCents;
  }

  Decimal get itemTaxCents => items.fold(
        Decimal.zero,
        (sum, item) => sum + item.taxCentsWithSettings(
          enableTaxCalculations: enableTaxCalculations,
          defaultTaxRateBps: defaultSalesTaxRateBps,
        ),
      );

  Decimal get taxCents => itemTaxCents;

  Decimal get totalBeforeLoyaltyCents {
    final net = subtotalCents - totalDiscountCents + taxCents;
    return net < Decimal.zero ? Decimal.zero : net;
  }

  Decimal get totalCents {
    final net = totalBeforeLoyaltyCents - Decimal.fromInt(loyaltyDiscountCents);
    return net < Decimal.zero ? Decimal.zero : net;
  }

  int get totalQuantity => items.fold(0, (sum, item) => sum + item.quantity);

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
    bool? allowNegativeStock,
    bool? isEditingPosted,
  }) {
    return SaleFormState(
      saleId: saleId ?? this.saleId,
      saleNumber: saleNumber ?? this.saleNumber,
      customerId: clearCustomer ? null : (customerId ?? this.customerId),
      customerName: clearCustomer ? null : (customerName ?? this.customerName),
      employeeId: clearCustomer ? this.employeeId : (employeeId ?? this.employeeId),
      employeeName: clearCustomer ? this.employeeName : (employeeName ?? this.employeeName),
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
      belowCostWarning: clearBelowCostWarning ? null : (belowCostWarning ?? this.belowCostWarning),
      belowCostOverrides: belowCostOverrides ?? this.belowCostOverrides,
      loyaltyPointsBalance: clearLoyalty ? 0 : (loyaltyPointsBalance ?? this.loyaltyPointsBalance),
      loyaltyPointsToRedeem: clearLoyalty ? 0 : (loyaltyPointsToRedeem ?? this.loyaltyPointsToRedeem),
      loyaltyDiscountCents: clearLoyalty ? 0 : (loyaltyDiscountCents ?? this.loyaltyDiscountCents),
      loyaltySettings: clearLoyalty ? null : (loyaltySettings ?? this.loyaltySettings),
      loyaltyRedemptionEnabled: clearLoyalty ? false : (loyaltyRedemptionEnabled ?? this.loyaltyRedemptionEnabled),
      enableTaxCalculations: enableTaxCalculations ?? this.enableTaxCalculations,
      defaultSalesTaxRateBps: defaultSalesTaxRateBps ?? this.defaultSalesTaxRateBps,
      allowNegativeStock: allowNegativeStock ?? this.allowNegativeStock,
      isEditingPosted: isEditingPosted ?? this.isEditingPosted,
    );
  }

  @override
  List<Object?> get props => [
        saleId, saleNumber, customerId, customerName, employeeId, employeeName, currencyId, items,
        discountMode, invoiceDiscountCents, notes, saleDate, dueDate,
        paymentMethod, taxRatePercent, salespersonMode, paidAmountCents, overpaymentHandling,
        isSubmitting, error, isSuccess, belowCostWarning, belowCostOverrides,
        loyaltyPointsBalance, loyaltyPointsToRedeem, loyaltyDiscountCents,
        loyaltySettings, loyaltyRedemptionEnabled,
        enableTaxCalculations, defaultSalesTaxRateBps, allowNegativeStock, isEditingPosted,
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
  List<Object?> get props => [tempId, productId, productName, costCents, sellingPriceCents, lossCents, reason];
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
  })  : discountCents = discountCents ?? Decimal.zero;

  Decimal get subtotalCents => unitPriceCents * Decimal.fromInt(quantity);
  Decimal get netCents => subtotalCents - discountCents;

  /// Tax is computed from the product's sales tax rate.
  /// Uses proper rounding (round half-up) instead of truncation.
  /// This getter uses product settings - use taxCentsWithSettings for global settings support.
  Decimal get taxCents => taxCentsWithSettings(enableTaxCalculations: true, defaultTaxRateBps: 0);

  /// Calculate tax respecting global settings.
  /// If enableTaxCalculations is false, returns zero.
  /// If product has its own tax rate (isTaxable && salesTaxRateBps > 0), uses that.
  /// Otherwise, uses the defaultTaxRateBps from global settings.
  Decimal taxCentsWithSettings({
    required bool enableTaxCalculations,
    required int defaultTaxRateBps,
  }) {
    if (!enableTaxCalculations) return Decimal.zero;
    
    final taxable = netCents;
    if (taxable <= Decimal.zero) return Decimal.zero;
    
    // Determine which tax rate to use
    int taxRateBps;
    if (product.isTaxable && product.salesTaxRateBps > 0) {
      // Product has its own tax rate - use it
      taxRateBps = product.salesTaxRateBps;
    } else if (defaultTaxRateBps > 0) {
      // Use global default tax rate
      taxRateBps = defaultTaxRateBps;
    } else {
      return Decimal.zero;
    }
    
    final raw = taxable * Decimal.fromInt(taxRateBps) / Decimal.fromInt(10000);
    return Decimal.fromBigInt(raw.round());
  }

  Decimal get totalCents => netCents + taxCents;

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
        tempId, product, variant, quantity,
        unitPriceCents, discountCents,
        colorName, colorHex, sizeName,
        employeeId, employeeName, itemNote,
      ];
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
  final bool allowNegativeStock;
  final bool isEditingPosted;
  const SaleFormInitialized({
    this.saleId,
    required this.currencyId,
    this.enableTaxCalculations = true,
    this.defaultSalesTaxRateBps = 0,
    this.allowNegativeStock = false,
    this.isEditingPosted = false,
  });

  @override
  List<Object?> get props => [saleId, currencyId, enableTaxCalculations, defaultSalesTaxRateBps, allowNegativeStock, isEditingPosted];
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

  const SaleLineItemAdded({
    required this.product,
    this.variant,
    required this.quantity,
    required this.unitPriceCents,
    this.discountCents,
  });

  @override
  List<Object?> get props => [product, variant, quantity, unitPriceCents, discountCents];
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
  List<Object?> get props => [tempId, quantity, unitPriceCents, discountCents, employeeId, employeeName, itemNote, clearEmployee];
}

class SaleLineItemRemoved extends SaleFormEvent {
  final String tempId;
  const SaleLineItemRemoved(this.tempId);

  @override
  List<Object?> get props => [tempId];
}

class SaleFormSubmitted extends SaleFormEvent {
  const SaleFormSubmitted();
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
  const SaleLoyaltyRedemptionChanged({required this.enabled, required this.pointsToRedeem});

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
  UserRole currentUserRole;
  int? currentUserId;
  int _lineCounter = 0;

  Map<int, String> _colorNames = {};
  Map<int, String?> _colorHexes = {};
  Map<int, String> _sizeNames = {};

  SaleFormBloc(this._repository, this._variantRepository, this._productRepository, this._auditService, {
    BelowCostSaleService? belowCostService,
    LoyaltyRepository? loyaltyRepository,
    UserRole userRole = UserRole.cashier,
    int? userId,
  })  : _belowCostService = belowCostService ?? const BelowCostSaleService(),
        _loyaltyRepository = loyaltyRepository,
        currentUserId = userId,
        currentUserRole = userRole,
        super(SaleFormState(
          currencyId: 1,
          saleDate: DateTime.now(),
        )) {
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
    if (_colorNames.isNotEmpty) return;
    try {
      final colors = await _variantRepository.getAllColors();
      _colorNames = {for (final c in colors) c.id: c.name};
      _colorHexes = {for (final c in colors) c.id: c.hexCode};
      final sizes = await _variantRepository.getAllSizes();
      _sizeNames = {for (final s in sizes) s.id: s.name};
    } catch (_) {}
  }

  String? _resolveColorName(int? colorId) => colorId != null ? _colorNames[colorId] : null;
  String? _resolveColorHex(int? colorId) => colorId != null ? _colorHexes[colorId] : null;
  String? _resolveSizeName(int? sizeId) => sizeId != null ? _sizeNames[sizeId] : null;

  String _generateTempId() {
    _lineCounter++;
    return 'line_$_lineCounter';
  }

  Future<void> _onInitialized(
    SaleFormInitialized event,
    Emitter<SaleFormState> emit,
  ) async {
    await _loadColorSizeLookups();

    if (event.saleId == null) {
      // New sale: generate next invoice number
      try {
        final nextNumber = await _repository.generateInvoiceNumber();
        emit(state.copyWith(
          currencyId: event.currencyId,
          saleNumber: nextNumber,
          enableTaxCalculations: event.enableTaxCalculations,
          defaultSalesTaxRateBps: event.defaultSalesTaxRateBps,
          allowNegativeStock: event.allowNegativeStock,
        ));
      } catch (_) {
        emit(state.copyWith(
          currencyId: event.currencyId,
          enableTaxCalculations: event.enableTaxCalculations,
          defaultSalesTaxRateBps: event.defaultSalesTaxRateBps,
          allowNegativeStock: event.allowNegativeStock,
        ));
      }
      return;
    }

    emit(state.copyWith(
      saleId: event.saleId,
      currencyId: event.currencyId,
      enableTaxCalculations: event.enableTaxCalculations,
      defaultSalesTaxRateBps: event.defaultSalesTaxRateBps,
      allowNegativeStock: event.allowNegativeStock,
      isEditingPosted: event.isEditingPosted,
    ));

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
          variantFutures[i.variantId!] = _variantRepository.getVariantById(i.variantId!);
        }
        if (i.variantId == null && !defaultVariantFutures.containsKey(i.productId)) {
          defaultVariantFutures[i.productId] =
              _variantRepository.getDefaultVariantByProduct(i.productId);
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
        );

        final realVariant = i.variantId != null ? resolvedVariants[i.variantId!] : null;
        final defaultVariant = i.variantId == null ? resolvedDefaultVariants[i.productId] : null;
        final variant = realVariant ?? defaultVariant ?? (i.variantId == null
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

      emit(state.copyWith(
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
      ));
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
      emit(state.copyWith(
        customerId: event.customerId,
        customerName: event.customerName,
      ));
      // Auto-load loyalty data for the selected customer
      if (_loyaltyRepository != null) {
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
      emit(state.copyWith(
        employeeId: event.employeeId,
        employeeName: event.employeeName,
      ));
    }
  }

  void _onDateChanged(
    SaleDateChanged event,
    Emitter<SaleFormState> emit,
  ) {
    emit(state.copyWith(saleDate: event.date));
  }

  void _onNotesChanged(
    SaleNotesChanged event,
    Emitter<SaleFormState> emit,
  ) {
    emit(state.copyWith(notes: event.notes));
  }

  void _onDiscountModeChanged(
    SaleDiscountModeChanged event,
    Emitter<SaleFormState> emit,
  ) {
    emit(state.copyWith(
      discountMode: event.mode,
      invoiceDiscountCents: Decimal.zero,
    ));
  }

  void _onInvoiceDiscountChanged(
    SaleInvoiceDiscountChanged event,
    Emitter<SaleFormState> emit,
  ) {
    emit(state.copyWith(invoiceDiscountCents: event.discountCents));
  }

  Future<void> _onLineItemAdded(
    SaleLineItemAdded event,
    Emitter<SaleFormState> emit,
  ) async {
    await _loadColorSizeLookups();

    ProductVariant? resolvedVariant = event.variant;
    if (resolvedVariant == null) {
      try {
        resolvedVariant = await _variantRepository.getDefaultVariantByProduct(event.product.id);
      } catch (_) {}
    }

    final newItem = SaleLineItem(
      tempId: _generateTempId(),
      product: event.product,
      variant: resolvedVariant,
      quantity: event.quantity,
      unitPriceCents: event.unitPriceCents,
      discountCents: event.discountCents,
      colorName: _resolveColorName(resolvedVariant?.colorId),
      colorHex: _resolveColorHex(resolvedVariant?.colorId),
      sizeName: _resolveSizeName(resolvedVariant?.sizeId),
    );

    // Below-cost check: use variant cost if available, else product cost
    final costCents = resolvedVariant?.costCents ?? event.product.costCents;
    final check = _belowCostService.check(
      costCents: costCents,
      sellingPriceCents: event.unitPriceCents,
      productName: newItem.displayName,
      productId: event.product.id,
      userRole: currentUserRole,
    );

    if (check.isBelowCost) {
      // Add item but show warning
      emit(state.copyWith(
        items: [...state.items, newItem],
        belowCostWarning: check,
      ));
    } else {
      emit(state.copyWith(items: [...state.items, newItem]));
    }
  }

  void _onLineItemUpdated(
    SaleLineItemUpdated event,
    Emitter<SaleFormState> emit,
  ) {
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
    emit(state.copyWith(items: updatedItems));

    // Re-check below-cost if price was changed
    if (event.unitPriceCents != null) {
      final item = updatedItems.firstWhere((i) => i.tempId == event.tempId);
      // Remove any previous override for this item since price changed
      final filteredOverrides = state.belowCostOverrides
          .where((o) => o.tempId != event.tempId)
          .toList();

      final costCents = item.variant?.costCents ?? item.product.costCents;
      final check = _belowCostService.check(
        costCents: costCents,
        sellingPriceCents: event.unitPriceCents!,
        productName: item.displayName,
        productId: item.product.id,
        userRole: currentUserRole,
      );

      if (check.isBelowCost) {
        emit(state.copyWith(
          belowCostWarning: check,
          belowCostOverrides: filteredOverrides,
        ));
      } else {
        // Price is now above cost, clear any warning
        emit(state.copyWith(
          clearBelowCostWarning: true,
          belowCostOverrides: filteredOverrides,
        ));
      }
    }
  }

  void _onLineItemRemoved(
    SaleLineItemRemoved event,
    Emitter<SaleFormState> emit,
  ) {
    final updatedItems = state.items.where((item) => item.tempId != event.tempId).toList();
    emit(state.copyWith(items: updatedItems));
  }

  Future<void> _onSubmitted(
    SaleFormSubmitted event,
    Emitter<SaleFormState> emit,
  ) async {
    if (state.items.isEmpty) {
      emit(state.copyWith(error: 'Please add at least one item'));
      return;
    }

    // Below-cost final gate: check all items for unresolved below-cost violations
    final overriddenTempIds = state.belowCostOverrides.map((o) => o.tempId).toSet();
    for (final item in state.items) {
      final costCents = item.variant?.costCents ?? item.product.costCents;
      if (costCents > Decimal.zero && item.unitPriceCents < costCents) {
        if (!overriddenTempIds.contains(item.tempId)) {
          // This item is below cost and has no override — re-trigger warning
          final check = _belowCostService.check(
            costCents: costCents,
            sellingPriceCents: item.unitPriceCents,
            productName: item.displayName,
            productId: item.product.id,
            userRole: currentUserRole,
          );
          emit(state.copyWith(belowCostWarning: check));
          return;
        }
      }
    }

    // Cash validation: paid amount must be >= total
    if (state.paymentMethod == SalePaymentMethod.cash &&
        state.paidAmountCents < state.totalCents) {
      emit(state.copyWith(error: 'sales.cash_insufficient'));
      return;
    }

    emit(state.copyWith(isSubmitting: true, error: null));

    try {
      // Distribute invoice-level discount and tax proportionally to each line
      // so that each item in the DB carries its correct share (needed for returns).
      final invoiceDiscount = state.discountMode == SaleDiscountMode.invoice
          ? state.invoiceDiscountCents.toBigInt().toInt()
          : 0;
      final invoiceTax = state.taxRatePercent > Decimal.zero
          ? state.taxCents.toBigInt().toInt()
          : 0;
      final totalSubtotal = state.subtotalCents.toBigInt().toInt();

      final lineItems = state.items;
      final distributedDiscounts = _distributeProportionally(
        invoiceDiscount, lineItems.map((i) => i.subtotalCents.toBigInt().toInt()).toList(), totalSubtotal,
      );
      final distributedTaxes = _distributeProportionally(
        invoiceTax, lineItems.map((i) => i.subtotalCents.toBigInt().toInt()).toList(), totalSubtotal,
      );

      final items = <SaleItemInput>[];
      for (int idx = 0; idx < lineItems.length; idx++) {
        final item = lineItems[idx];
        final effectiveDiscount = invoiceDiscount > 0
            ? Decimal.fromInt(distributedDiscounts[idx])
            : item.discountCents;
        final effectiveTax = invoiceTax > 0
            ? Decimal.fromInt(distributedTaxes[idx])
            : item.taxCents;
        final effectiveTotal = item.subtotalCents - effectiveDiscount + effectiveTax;
        items.add(SaleItemInput(
          productId: item.product.id,
          variantId: item.variant?.id,
          quantity: item.quantity,
          unitPriceCents: item.unitPriceCents,
          subtotalCents: item.subtotalCents,
          discountCents: effectiveDiscount,
          taxCents: effectiveTax,
          totalCents: effectiveTotal,
          employeeId: item.employeeId,
          employeeName: item.employeeName,
        ));
      }

      final paymentMethodStr = state.paymentMethod.name;

      // Determine effective paid amount:
      // - cash: depends on overpayment handling
      //   - returnChange: cap at totalCents (excess is returned as cash change)
      //   - addToBalance: use full paidAmountCents (excess goes to customer credit)
      // - card: auto-set to total (fully settled)
      // - credit/cheque: 0 (full amount goes to balance)
      final effectivePaidCents = switch (state.paymentMethod) {
        SalePaymentMethod.cash => () {
          // If overpaying and user chose to return change, cap at total
          if (state.paidAmountCents > state.totalCents &&
              state.overpaymentHandling == SaleOverpaymentHandling.returnChange) {
            return state.totalCents;
          }
          // Otherwise use full paid amount (either exact payment or add to balance)
          return state.paidAmountCents;
        }(),
        SalePaymentMethod.card => state.totalCents,
        SalePaymentMethod.credit => Decimal.zero,
        SalePaymentMethod.cheque => Decimal.zero,
      };

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
        );

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
        emit(state.copyWith(
          saleId: saleId,
          isSubmitting: false,
          isSuccess: true,
        ));
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
        );

        CrashlyticsService.instance.logAction('sale_edited_posted', {
          'sale_id': newSaleId.toString(),
          'original_sale_id': state.saleId.toString(),
        });
        emit(state.copyWith(
          saleId: newSaleId,
          isSubmitting: false,
          isSuccess: true,
        ));
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
        );

        if (!ok) throw Exception('Failed to update sale');

        CrashlyticsService.instance.logAction('sale_updated', {
          'sale_id': state.saleId.toString(),
        });
        emit(state.copyWith(
          isSubmitting: false,
          isSuccess: true,
        ));
      }
    } catch (e, st) {
      CrashlyticsService.instance.recordError(
        e,
        stackTrace: st,
        reason: 'SaleFormBloc._onSubmitted failed',
      );
      emit(state.copyWith(
        isSubmitting: false,
        error: e.toString(),
      ));
    }
  }

  void _onPaymentMethodChanged(
    SalePaymentMethodChanged event,
    Emitter<SaleFormState> emit,
  ) {
    // Reset paid amount when switching payment methods
    emit(state.copyWith(
      paymentMethod: event.method,
      paidAmountCents: Decimal.zero,
    ));
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

  Future<void> _onBelowCostOverrideApproved(
    SaleBelowCostOverrideApproved event,
    Emitter<SaleFormState> emit,
  ) async {
    final warning = state.belowCostWarning;
    if (warning == null || !warning.isBelowCost) return;

    // Find the last added item that matches the warning product
    final matchingItem = state.items.lastWhere(
      (item) => item.product.id == warning.productId,
      orElse: () => state.items.last,
    );

    final override = BelowCostOverride(
      tempId: matchingItem.tempId,
      productId: warning.productId,
      productName: warning.productName,
      costCents: warning.costCents,
      sellingPriceCents: warning.sellingPriceCents,
      lossCents: warning.lossCents,
      reason: event.reason,
    );

    // Write audit log immediately
    try {
      await _auditService.logBelowCostOverride(
        productId: warning.productId,
        productName: warning.productName,
        costCents: warning.costCents.toBigInt().toInt(),
        sellingPriceCents: warning.sellingPriceCents.toBigInt().toInt(),
        lossCents: warning.lossCents.toBigInt().toInt(),
        reason: event.reason,
        userId: currentUserId,
        userRole: currentUserRole.name,
      );
    } catch (_) {
      // Audit failure should not block the sale
    }

    emit(state.copyWith(
      clearBelowCostWarning: true,
      belowCostOverrides: [...state.belowCostOverrides, override],
    ));
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
      final idx = updatedItems.lastIndexWhere(
        (item) => item.product.id == warning.productId,
      );
      if (idx >= 0) updatedItems.removeAt(idx);
      emit(state.copyWith(
        items: updatedItems,
        clearBelowCostWarning: true,
      ));
    } else {
      // Manager/Owner dismissed without override: remove the item
      final updatedItems = List<SaleLineItem>.from(state.items);
      final idx = updatedItems.lastIndexWhere(
        (item) => item.product.id == warning.productId,
      );
      if (idx >= 0) updatedItems.removeAt(idx);
      emit(state.copyWith(
        items: updatedItems,
        clearBelowCostWarning: true,
      ));
    }
  }

  Future<void> _onLoyaltyDataRequested(
    SaleLoyaltyDataRequested event,
    Emitter<SaleFormState> emit,
  ) async {
    if (_loyaltyRepository == null) return;

    try {
      final settings = await _loyaltyRepository.getLoyaltySettings();
      if (settings == null || !settings.isEnabled || !settings.allowPointsRedemption) {
        emit(state.copyWith(clearLoyalty: true));
        return;
      }

      final summary = await _loyaltyRepository.getCustomerLoyaltySummary(event.customerId);
      if (summary == null) {
        emit(state.copyWith(clearLoyalty: true));
        return;
      }

      emit(state.copyWith(
        loyaltyPointsBalance: summary.pointsBalance,
        loyaltySettings: settings,
        loyaltyPointsToRedeem: 0,
        loyaltyDiscountCents: 0,
        loyaltyRedemptionEnabled: false,
      ));
    } catch (_) {
      emit(state.copyWith(clearLoyalty: true));
    }
  }

  void _onLoyaltyRedemptionChanged(
    SaleLoyaltyRedemptionChanged event,
    Emitter<SaleFormState> emit,
  ) {
    final settings = state.loyaltySettings;
    if (settings == null) return;

    if (!event.enabled) {
      emit(state.copyWith(
        loyaltyRedemptionEnabled: false,
        loyaltyPointsToRedeem: 0,
        loyaltyDiscountCents: 0,
      ));
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
    final maxDiscount = [maxDiscountFromPercent, maxDiscountFromPoints, invoiceTotal]
        .reduce((a, b) => a < b ? a : b);

    // Max redeemable points = maxDiscount / pointValueCents
    final maxRedeemablePoints = pointValueCents > 0 ? maxDiscount ~/ pointValueCents : 0;

    // Clamp requested points to valid range
    final pointsToRedeem = event.pointsToRedeem.clamp(0, maxRedeemablePoints);
    final discountCents = pointsToRedeem * pointValueCents;

    emit(state.copyWith(
      loyaltyRedemptionEnabled: true,
      loyaltyPointsToRedeem: pointsToRedeem,
      loyaltyDiscountCents: discountCents,
    ));
  }

  /// Distribute [total] proportionally across items based on [weights].
  /// Uses largest-remainder method so the distributed values sum exactly to [total].
  List<int> _distributeProportionally(int total, List<int> weights, int weightSum) {
    if (weights.isEmpty || weightSum <= 0 || total == 0) {
      return List.filled(weights.length, 0);
    }
    final result = List<int>.filled(weights.length, 0);
    int allocated = 0;
    final remainders = <int, double>{};
    for (int i = 0; i < weights.length; i++) {
      final exact = (total * weights[i]) / weightSum;
      result[i] = exact.floor();
      remainders[i] = exact - result[i];
      allocated += result[i];
    }
    // Distribute the remainder (total - allocated) to items with largest fractional parts
    var remaining = total - allocated;
    final sorted = remainders.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    for (final entry in sorted) {
      if (remaining <= 0) break;
      result[entry.key]++;
      remaining--;
    }
    return result;
  }

  void _onTaxSettingsChanged(
    SaleTaxSettingsChanged event,
    Emitter<SaleFormState> emit,
  ) {
    emit(state.copyWith(
      enableTaxCalculations: event.enableTaxCalculations,
      defaultSalesTaxRateBps: event.defaultSalesTaxRateBps,
    ));
  }
}
