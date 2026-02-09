import 'package:decimal/decimal.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';

import '../../domain/repositories/purchase_repository.dart';
import '../../../products/domain/entities/product_entity.dart';
import '../../../products/domain/entities/product_variant_entity.dart';
import '../../../products/domain/repositories/product_variant_repository.dart';

// ==================== ENUMS ====================

/// Discount mode: per-item discounts or a single invoice-level discount
enum DiscountMode { perItem, invoice }

/// Payment method for purchase invoice
enum PurchasePaymentMethod { cash, credit, card, cheque, purchaseOrder }

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
  final Decimal invoiceDiscountPercent;
  final String? supplierInvoiceRef;
  final String? notes;
  final DateTime purchaseDate;
  final DateTime? dueDate;
  final PurchasePaymentMethod paymentMethod;
  final Decimal taxRatePercent;
  final Decimal paidAmountCents;
  final bool isSubmitting;
  final String? error;
  final bool isSuccess;
  final bool hasUnsavedChanges;

  PurchaseFormState({
    this.purchaseId,
    this.purchaseNumber,
    this.supplierId,
    this.supplierName,
    required this.currencyId,
    this.items = const [],
    this.discountMode = DiscountMode.perItem,
    Decimal? invoiceDiscountCents,
    Decimal? invoiceDiscountPercent,
    this.supplierInvoiceRef,
    this.notes,
    required this.purchaseDate,
    this.dueDate,
    this.paymentMethod = PurchasePaymentMethod.cash,
    Decimal? taxRatePercent,
    Decimal? paidAmountCents,
    this.isSubmitting = false,
    this.error,
    this.isSuccess = false,
    this.hasUnsavedChanges = false,
  }) : invoiceDiscountCents = invoiceDiscountCents ?? Decimal.zero,
       invoiceDiscountPercent = invoiceDiscountPercent ?? Decimal.zero,
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

  Decimal get effectiveInvoiceDiscountCents {
    if (invoiceDiscountPercent > Decimal.zero) {
      final raw = subtotalCents * invoiceDiscountPercent / Decimal.fromInt(100);
      final computed = Decimal.fromBigInt(raw.round());
      return computed > subtotalCents ? subtotalCents : computed;
    }
    return invoiceDiscountCents;
  }

  Decimal get totalDiscountCents {
    if (discountMode == DiscountMode.invoice) {
      return effectiveInvoiceDiscountCents;
    }
    return itemDiscountCents;
  }

  Decimal get itemTaxCents => items.fold(
        Decimal.zero,
        (sum, item) => sum + item.taxCents,
      );

  Decimal get taxCents {
    if (taxRatePercent > Decimal.zero) {
      final taxable = subtotalCents - totalDiscountCents;
      final raw = taxable * taxRatePercent / Decimal.fromInt(100);
      return Decimal.fromBigInt(raw.round());
    }
    return itemTaxCents;
  }

  Decimal get remainingCents {
    final r = totalCents - paidAmountCents;
    return r < Decimal.zero ? Decimal.zero : r;
  }

  Decimal get changeCents {
    final change = paidAmountCents - totalCents;
    return change > Decimal.zero ? change : Decimal.zero;
  }

  Decimal get totalCents {
    final net = subtotalCents - totalDiscountCents + taxCents;
    return net < Decimal.zero ? Decimal.zero : net;
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
    Decimal? invoiceDiscountPercent,
    String? supplierInvoiceRef,
    String? notes,
    DateTime? purchaseDate,
    DateTime? dueDate,
    PurchasePaymentMethod? paymentMethod,
    Decimal? taxRatePercent,
    Decimal? paidAmountCents,
    bool? isSubmitting,
    String? error,
    bool? isSuccess,
    bool clearDueDate = false,
    bool? hasUnsavedChanges,
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
      invoiceDiscountPercent: invoiceDiscountPercent ?? this.invoiceDiscountPercent,
      supplierInvoiceRef: supplierInvoiceRef ?? this.supplierInvoiceRef,
      notes: notes ?? this.notes,
      purchaseDate: purchaseDate ?? this.purchaseDate,
      dueDate: clearDueDate ? null : (dueDate ?? this.dueDate),
      paymentMethod: paymentMethod ?? this.paymentMethod,
      taxRatePercent: taxRatePercent ?? this.taxRatePercent,
      paidAmountCents: paidAmountCents ?? this.paidAmountCents,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      error: error,
      isSuccess: isSuccess ?? this.isSuccess,
      hasUnsavedChanges: hasUnsavedChanges ?? this.hasUnsavedChanges,
    );
  }

  @override
  List<Object?> get props => [
        purchaseId, purchaseNumber, supplierId, supplierName, currencyId, items,
        discountMode, invoiceDiscountCents, invoiceDiscountPercent, supplierInvoiceRef,
        notes, purchaseDate, dueDate,
        paymentMethod, taxRatePercent, paidAmountCents,
        isSubmitting, error, isSuccess, hasUnsavedChanges,
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
  final Decimal taxCents;
  final DateTime? expiryDate;
  final String? colorName;
  final String? colorHex;
  final String? sizeName;

  PurchaseLineItem({
    required this.tempId,
    required this.product,
    this.variant,
    required this.quantity,
    required this.unitCostCents,
    Decimal? discountCents,
    Decimal? taxCents,
    this.expiryDate,
    this.colorName,
    this.colorHex,
    this.sizeName,
  })  : discountCents = discountCents ?? Decimal.zero,
        taxCents = taxCents ?? Decimal.zero;

  Decimal get subtotalCents => unitCostCents * Decimal.fromInt(quantity);
  Decimal get netCents => subtotalCents - discountCents;
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

  PurchaseLineItem copyWith({
    String? tempId,
    Product? product,
    ProductVariant? variant,
    int? quantity,
    Decimal? unitCostCents,
    Decimal? discountCents,
    Decimal? taxCents,
    DateTime? expiryDate,
    bool clearExpiry = false,
    String? colorName,
    String? colorHex,
    String? sizeName,
  }) {
    return PurchaseLineItem(
      tempId: tempId ?? this.tempId,
      product: product ?? this.product,
      variant: variant ?? this.variant,
      quantity: quantity ?? this.quantity,
      unitCostCents: unitCostCents ?? this.unitCostCents,
      discountCents: discountCents ?? this.discountCents,
      taxCents: taxCents ?? this.taxCents,
      expiryDate: clearExpiry ? null : (expiryDate ?? this.expiryDate),
      colorName: colorName ?? this.colorName,
      colorHex: colorHex ?? this.colorHex,
      sizeName: sizeName ?? this.sizeName,
    );
  }

  @override
  List<Object?> get props => [
        tempId, product, variant, quantity,
        unitCostCents, discountCents, taxCents, expiryDate,
        colorName, colorHex, sizeName,
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

  const PurchaseFormInitialized({this.purchaseId, required this.currencyId});

  @override
  List<Object?> get props => [purchaseId, currencyId];
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
  final Decimal discountPercent;
  PurchaseInvoiceDiscountChanged(this.discountCents, {Decimal? discountPercent})
      : discountPercent = discountPercent ?? Decimal.zero;

  @override
  List<Object?> get props => [discountCents, discountPercent];
}

class PurchaseLineItemAdded extends PurchaseFormEvent {
  final Product product;
  final ProductVariant? variant;
  final int quantity;
  final Decimal unitCostCents;
  final Decimal? discountCents;
  final DateTime? expiryDate;

  const PurchaseLineItemAdded({
    required this.product,
    this.variant,
    required this.quantity,
    required this.unitCostCents,
    this.discountCents,
    this.expiryDate,
  });

  @override
  List<Object?> get props => [product, variant, quantity, unitCostCents, discountCents, expiryDate];
}

class PurchaseLineItemUpdated extends PurchaseFormEvent {
  final String tempId;
  final int? quantity;
  final Decimal? unitCostCents;
  final Decimal? discountCents;
  final DateTime? expiryDate;
  final bool clearExpiry;

  const PurchaseLineItemUpdated({
    required this.tempId,
    this.quantity,
    this.unitCostCents,
    this.discountCents,
    this.expiryDate,
    this.clearExpiry = false,
  });

  @override
  List<Object?> get props => [tempId, quantity, unitCostCents, discountCents, expiryDate, clearExpiry];
}

class PurchaseLineItemRemoved extends PurchaseFormEvent {
  final String tempId;
  const PurchaseLineItemRemoved(this.tempId);

  @override
  List<Object?> get props => [tempId];
}

class PurchaseFormSubmitted extends PurchaseFormEvent {
  const PurchaseFormSubmitted();
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

// ==================== BLOC ====================

class PurchaseFormBloc extends Bloc<PurchaseFormEvent, PurchaseFormState> {
  final PurchaseRepository _repository;
  final ProductVariantRepository _variantRepository;
  int _lineCounter = 0;

  // Cached color/size lookup maps
  Map<int, String> _colorNames = {};
  Map<int, String?> _colorHexes = {};
  Map<int, String> _sizeNames = {};

  PurchaseFormBloc(this._repository, this._variantRepository)
      : super(PurchaseFormState(
          currencyId: 1,
          purchaseDate: DateTime.now(),
        )) {
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

    if (event.purchaseId == null) {
      // New purchase: generate next invoice number
      try {
        final nextNumber = await _repository.generatePurchaseNumber();
        emit(state.copyWith(
          currencyId: event.currencyId,
          purchaseNumber: nextNumber,
        ));
      } catch (_) {
        emit(state.copyWith(currencyId: event.currencyId));
      }
      return;
    }

    emit(state.copyWith(
      purchaseId: event.purchaseId,
      currencyId: event.currencyId,
    ));

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
      for (final i in items) {
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

      final mappedItems = items.map((i) {
        final product = Product(
          id: i.productId,
          name: i.productName ?? 'Product #${i.productId}',
          costCents: i.unitCostCents,
          priceCents: Decimal.zero,
          stockQuantity: 0,
          minQuantity: 0,
          hasVariants: i.variantId != null,
          isTaxable: false,
          taxRateBps: 0,
          isActive: true,
          trackInventory: true,
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
                costCents: i.unitCostCents,
                priceCents: Decimal.zero,
                wholesalePriceCents: null,
                priceAdjustmentCents: Decimal.zero,
                stockQuantity: 0,
                isActive: true,
              ));

        return PurchaseLineItem(
          tempId: _generateTempId(),
          product: product,
          variant: variant,
          quantity: i.quantity,
          unitCostCents: i.unitCostCents,
          discountCents: i.discountCents,
          taxCents: i.taxCents,
          expiryDate: i.expiryDate,
          colorName: _resolveColorName(variant?.colorId),
          colorHex: _resolveColorHex(variant?.colorId),
          sizeName: _resolveSizeName(variant?.sizeId),
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
          resolvedDiscountMode == DiscountMode.invoice ? purchase.discountCents : Decimal.zero;

      final hasAnyItemTax = mappedItems.any((i) => i.taxCents > Decimal.zero);
      Decimal resolvedTaxRatePercent = Decimal.zero;
      if (!hasAnyItemTax && purchase.taxCents > Decimal.zero) {
        final taxable = purchase.subtotalCents - purchase.discountCents;
        if (taxable > Decimal.zero) {
          final rawPct = (purchase.taxCents * Decimal.fromInt(100)) / taxable;
          final rawPctDouble = double.tryParse(rawPct.toString()) ?? 0;
          resolvedTaxRatePercent = Decimal.parse(rawPctDouble.toStringAsFixed(2));
        }
      }

      emit(state.copyWith(
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
        discountMode: resolvedDiscountMode,
        invoiceDiscountCents: resolvedInvoiceDiscountCents,
        paymentMethod: _parsePaymentMethod(purchase.paymentMethod),
        paidAmountCents: purchase.paidAmountCents,
        taxRatePercent: resolvedTaxRatePercent,
      ));
    } catch (e) {
      emit(state.copyWith(error: e.toString()));
    }
  }

  void _onSupplierChanged(
    PurchaseSupplierChanged event,
    Emitter<PurchaseFormState> emit,
  ) {
    emit(state.copyWith(
      supplierId: event.supplierId,
      supplierName: event.supplierName,
    ));
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
    emit(state.copyWith(
      discountMode: event.mode,
      invoiceDiscountCents: Decimal.zero,
      invoiceDiscountPercent: Decimal.zero,
    ));
  }

  void _onInvoiceDiscountChanged(
    PurchaseInvoiceDiscountChanged event,
    Emitter<PurchaseFormState> emit,
  ) {
    emit(state.copyWith(
      invoiceDiscountCents: event.discountCents,
      invoiceDiscountPercent: event.discountPercent,
    ));
  }

  Future<void> _onLineItemAdded(
    PurchaseLineItemAdded event,
    Emitter<PurchaseFormState> emit,
  ) async {
    await _loadColorSizeLookups();

    ProductVariant? resolvedVariant = event.variant;
    if (resolvedVariant == null) {
      try {
        resolvedVariant = await _variantRepository.getDefaultVariantByProduct(event.product.id);
      } catch (_) {}
    }

    final newItem = PurchaseLineItem(
      tempId: _generateTempId(),
      product: event.product,
      variant: resolvedVariant,
      quantity: event.quantity,
      unitCostCents: event.unitCostCents,
      discountCents: event.discountCents,
      expiryDate: event.expiryDate,
      colorName: _resolveColorName(resolvedVariant?.colorId),
      colorHex: _resolveColorHex(resolvedVariant?.colorId),
      sizeName: _resolveSizeName(resolvedVariant?.sizeId),
    );
    emit(state.copyWith(items: [...state.items, newItem], hasUnsavedChanges: true));
  }

  void _onLineItemUpdated(
    PurchaseLineItemUpdated event,
    Emitter<PurchaseFormState> emit,
  ) {
    final updatedItems = state.items.map((item) {
      if (item.tempId == event.tempId) {
        return item.copyWith(
          quantity: event.quantity,
          unitCostCents: event.unitCostCents,
          discountCents: event.discountCents,
          expiryDate: event.expiryDate,
          clearExpiry: event.clearExpiry,
        );
      }
      return item;
    }).toList();
    emit(state.copyWith(items: updatedItems, hasUnsavedChanges: true));
  }

  void _onLineItemRemoved(
    PurchaseLineItemRemoved event,
    Emitter<PurchaseFormState> emit,
  ) {
    final updatedItems = state.items.where((item) => item.tempId != event.tempId).toList();
    emit(state.copyWith(items: updatedItems, hasUnsavedChanges: true));
  }

  Future<void> _onSubmitted(
    PurchaseFormSubmitted event,
    Emitter<PurchaseFormState> emit,
  ) async {
    if (state.supplierId == null) {
      emit(state.copyWith(error: 'Please select a supplier'));
      return;
    }
    if (state.items.isEmpty) {
      emit(state.copyWith(error: 'Please add at least one item'));
      return;
    }

    // Cash validation: paid amount must be >= total
    if (state.paymentMethod == PurchasePaymentMethod.cash &&
        state.paidAmountCents < state.totalCents) {
      emit(state.copyWith(error: 'purchases.cash_insufficient'));
      return;
    }

    emit(state.copyWith(isSubmitting: true, error: null));

    try {
      final items = state.items.map((item) => PurchaseItemInput(
            productId: item.product.id,
            variantId: item.variant?.id,
            quantity: item.quantity,
            unitCostCents: item.unitCostCents,
            discountCents: item.discountCents,
            subtotalCents: item.subtotalCents,
            taxCents: item.taxCents,
            totalCents: item.totalCents,
            expiryDate: item.expiryDate,
          )).toList();

      // Determine effective paid amount:
      // - cash: user-entered paid amount
      // - card: auto-set to total (fully settled)
      // - credit/cheque: 0 (full amount goes to supplier balance)
      // - purchaseOrder: auto-set to total (no balance impact, just a reminder)
      final effectivePaidCents = switch (state.paymentMethod) {
        PurchasePaymentMethod.cash => state.paidAmountCents,
        PurchasePaymentMethod.card => state.totalCents,
        PurchasePaymentMethod.credit => Decimal.zero,
        PurchasePaymentMethod.cheque => Decimal.zero,
        PurchasePaymentMethod.purchaseOrder => state.totalCents,
      };

      if (state.purchaseId == null) {
        final purchaseId = await _repository.createPurchase(
          supplierId: state.supplierId!,
          currencyId: state.currencyId,
          subtotalCents: state.subtotalCents,
          discountCents: state.totalDiscountCents,
          taxCents: state.taxCents,
          totalCents: state.totalCents,
          paidAmountCents: effectivePaidCents,
          items: items,
          paymentMethod: state.paymentMethod.name,
          supplierInvoiceRef: state.supplierInvoiceRef,
          notes: state.notes,
          purchaseDate: state.purchaseDate,
          dueDate: state.dueDate,
        );

        emit(state.copyWith(
          purchaseId: purchaseId,
          isSubmitting: false,
          isSuccess: true,
          hasUnsavedChanges: false,
        ));
      } else {
        final ok = await _repository.updatePurchase(
          purchaseId: state.purchaseId!,
          supplierId: state.supplierId!,
          currencyId: state.currencyId,
          subtotalCents: state.subtotalCents,
          discountCents: state.totalDiscountCents,
          taxCents: state.taxCents,
          totalCents: state.totalCents,
          paidAmountCents: effectivePaidCents,
          items: items,
          paymentMethod: state.paymentMethod.name,
          supplierInvoiceRef: state.supplierInvoiceRef,
          notes: state.notes,
          purchaseDate: state.purchaseDate,
          dueDate: state.dueDate,
        );

        if (!ok) {
          throw Exception('Failed to update purchase');
        }

        emit(state.copyWith(
          isSubmitting: false,
          isSuccess: true,
          hasUnsavedChanges: false,
        ));
      }
    } catch (e) {
      emit(state.copyWith(
        isSubmitting: false,
        error: e.toString(),
      ));
    }
  }

  void _onPaymentMethodChanged(
    PurchasePaymentMethodChanged event,
    Emitter<PurchaseFormState> emit,
  ) {
    // Reset paid amount when switching payment methods
    emit(state.copyWith(
      paymentMethod: event.method,
      paidAmountCents: Decimal.zero,
    ));
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
      emit(state.copyWith(
        isSubmitting: false,
        error: e.toString(),
      ));
    }
  }
}
