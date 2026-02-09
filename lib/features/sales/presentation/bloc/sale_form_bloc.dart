import 'package:decimal/decimal.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';

import '../../domain/repositories/sale_repository.dart';
import '../../../products/domain/entities/product_entity.dart';
import '../../../products/domain/entities/product_variant_entity.dart';
import '../../../products/domain/repositories/product_variant_repository.dart';

// ==================== ENUMS ====================

/// Discount mode: per-item discounts or a single invoice-level discount
enum SaleDiscountMode { perItem, invoice }

/// Payment method for sale invoice
enum SalePaymentMethod { cash, credit, card, cheque }

/// Salesperson assignment mode: per-invoice or per-item
enum SalespersonMode { perInvoice, perItem }

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
  final bool isSubmitting;
  final String? error;
  final bool isSuccess;

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
    this.isSubmitting = false,
    this.error,
    this.isSuccess = false,
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

  Decimal get totalCents {
    final net = subtotalCents - totalDiscountCents + taxCents;
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
    bool? isSubmitting,
    String? error,
    bool? isSuccess,
    bool clearCustomer = false,
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
      isSubmitting: isSubmitting ?? this.isSubmitting,
      error: error,
      isSuccess: isSuccess ?? this.isSuccess,
    );
  }

  @override
  List<Object?> get props => [
        saleId, saleNumber, customerId, customerName, employeeId, employeeName, currencyId, items,
        discountMode, invoiceDiscountCents, notes, saleDate, dueDate,
        paymentMethod, taxRatePercent, salespersonMode, paidAmountCents,
        isSubmitting, error, isSuccess,
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
  final Decimal taxCents;
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
    Decimal? taxCents,
    this.colorName,
    this.colorHex,
    this.sizeName,
    this.employeeId,
    this.employeeName,
    this.itemNote,
  })  : discountCents = discountCents ?? Decimal.zero,
        taxCents = taxCents ?? Decimal.zero;

  Decimal get subtotalCents => unitPriceCents * Decimal.fromInt(quantity);
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

  SaleLineItem copyWith({
    String? tempId,
    Product? product,
    ProductVariant? variant,
    int? quantity,
    Decimal? unitPriceCents,
    Decimal? discountCents,
    Decimal? taxCents,
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
      taxCents: taxCents ?? this.taxCents,
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
        unitPriceCents, discountCents, taxCents,
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
  const SaleFormInitialized({this.saleId, required this.currencyId});

  @override
  List<Object?> get props => [saleId, currencyId];
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

// ==================== BLOC ====================

class SaleFormBloc extends Bloc<SaleFormEvent, SaleFormState> {
  final SaleRepository _repository;
  final ProductVariantRepository _variantRepository;
  int _lineCounter = 0;

  Map<int, String> _colorNames = {};
  Map<int, String?> _colorHexes = {};
  Map<int, String> _sizeNames = {};

  SaleFormBloc(this._repository, this._variantRepository)
      : super(SaleFormState(
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
    on<SaleDueDateChanged>(_onDueDateChanged);
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
        ));
      } catch (_) {
        emit(state.copyWith(currencyId: event.currencyId));
      }
      return;
    }

    emit(state.copyWith(
      saleId: event.saleId,
      currencyId: event.currencyId,
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
          costCents: Decimal.zero,
          priceCents: i.unitPriceCents,
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
          taxCents: i.taxCents,
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

  void _onCustomerChanged(
    SaleCustomerChanged event,
    Emitter<SaleFormState> emit,
  ) {
    if (event.customerId == null) {
      emit(state.copyWith(clearCustomer: true));
    } else {
      emit(state.copyWith(
        customerId: event.customerId,
        customerName: event.customerName,
      ));
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
    emit(state.copyWith(items: [...state.items, newItem]));
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

    // Cash validation: paid amount must be >= total
    if (state.paymentMethod == SalePaymentMethod.cash &&
        state.paidAmountCents < state.totalCents) {
      emit(state.copyWith(error: 'sales.cash_insufficient'));
      return;
    }

    emit(state.copyWith(isSubmitting: true, error: null));

    try {
      final items = state.items.map((item) => SaleItemInput(
            productId: item.product.id,
            variantId: item.variant?.id,
            quantity: item.quantity,
            unitPriceCents: item.unitPriceCents,
            subtotalCents: item.subtotalCents,
            discountCents: item.discountCents,
            taxCents: item.taxCents,
            totalCents: item.totalCents,
          )).toList();

      final paymentMethodStr = state.paymentMethod.name;

      // Determine effective paid amount:
      // - cash: user-entered paid amount
      // - card: auto-set to total (fully settled)
      // - credit/cheque: 0 (full amount goes to balance)
      final effectivePaidCents = switch (state.paymentMethod) {
        SalePaymentMethod.cash => state.paidAmountCents,
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
        );

        emit(state.copyWith(
          saleId: saleId,
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

        emit(state.copyWith(
          isSubmitting: false,
          isSuccess: true,
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

  void _onDueDateChanged(
    SaleDueDateChanged event,
    Emitter<SaleFormState> emit,
  ) {
    emit(state.copyWith(dueDate: event.date));
  }
}
