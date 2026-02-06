import 'package:decimal/decimal.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';

import '../../domain/repositories/purchase_repository.dart';
import '../../../products/domain/entities/product_entity.dart';
import '../../../products/domain/entities/product_variant_entity.dart';

// ==================== ENUMS ====================

/// Discount mode: per-item discounts or a single invoice-level discount
enum DiscountMode { perItem, invoice }

// ==================== STATE ====================

class PurchaseFormState extends Equatable {
  final int? purchaseId;
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
  final bool isSubmitting;
  final String? error;
  final bool isSuccess;

  PurchaseFormState({
    this.purchaseId,
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
    this.isSubmitting = false,
    this.error,
    this.isSuccess = false,
  }) : invoiceDiscountCents = invoiceDiscountCents ?? Decimal.zero;

  Decimal get subtotalCents => items.fold(
        Decimal.zero,
        (sum, item) => sum + item.subtotalCents,
      );

  Decimal get itemDiscountCents => items.fold(
        Decimal.zero,
        (sum, item) => sum + item.discountCents,
      );

  Decimal get totalDiscountCents {
    if (discountMode == DiscountMode.invoice) {
      return invoiceDiscountCents;
    }
    return itemDiscountCents;
  }

  Decimal get taxCents => items.fold(
        Decimal.zero,
        (sum, item) => sum + item.taxCents,
      );

  Decimal get totalCents {
    final net = subtotalCents - totalDiscountCents + taxCents;
    return net < Decimal.zero ? Decimal.zero : net;
  }

  int get totalQuantity => items.fold(0, (sum, item) => sum + item.quantity);

  bool get isDraft => purchaseId == null;

  PurchaseFormState copyWith({
    int? purchaseId,
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
    bool? isSubmitting,
    String? error,
    bool? isSuccess,
    bool clearDueDate = false,
  }) {
    return PurchaseFormState(
      purchaseId: purchaseId ?? this.purchaseId,
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
      isSubmitting: isSubmitting ?? this.isSubmitting,
      error: error,
      isSuccess: isSuccess ?? this.isSuccess,
    );
  }

  @override
  List<Object?> get props => [
        purchaseId, supplierId, supplierName, currencyId, items,
        discountMode, invoiceDiscountCents, supplierInvoiceRef,
        notes, purchaseDate, dueDate,
        isSubmitting, error, isSuccess,
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

  PurchaseLineItem({
    required this.tempId,
    required this.product,
    this.variant,
    required this.quantity,
    required this.unitCostCents,
    Decimal? discountCents,
    Decimal? taxCents,
    this.expiryDate,
  })  : discountCents = discountCents ?? Decimal.zero,
        taxCents = taxCents ?? Decimal.zero;

  Decimal get subtotalCents => unitCostCents * Decimal.fromInt(quantity);
  Decimal get netCents => subtotalCents - discountCents;
  Decimal get totalCents => netCents + taxCents;

  String get displayName {
    if (variant != null && (variant!.colorId != null || variant!.sizeId != null)) {
      return '${product.name} (${variant!.sku ?? 'Variant ${variant!.id}'})';
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
    );
  }

  @override
  List<Object?> get props => [
        tempId, product, variant, quantity,
        unitCostCents, discountCents, taxCents, expiryDate,
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

// ==================== BLOC ====================

class PurchaseFormBloc extends Bloc<PurchaseFormEvent, PurchaseFormState> {
  final PurchaseRepository _repository;
  int _lineCounter = 0;

  PurchaseFormBloc(this._repository)
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
  }

  String _generateTempId() {
    _lineCounter++;
    return 'line_$_lineCounter';
  }

  void _onInitialized(
    PurchaseFormInitialized event,
    Emitter<PurchaseFormState> emit,
  ) {
    emit(state.copyWith(
      purchaseId: event.purchaseId,
      currencyId: event.currencyId,
    ));
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
    ));
  }

  void _onInvoiceDiscountChanged(
    PurchaseInvoiceDiscountChanged event,
    Emitter<PurchaseFormState> emit,
  ) {
    emit(state.copyWith(invoiceDiscountCents: event.discountCents));
  }

  void _onLineItemAdded(
    PurchaseLineItemAdded event,
    Emitter<PurchaseFormState> emit,
  ) {
    final newItem = PurchaseLineItem(
      tempId: _generateTempId(),
      product: event.product,
      variant: event.variant,
      quantity: event.quantity,
      unitCostCents: event.unitCostCents,
      discountCents: event.discountCents,
      expiryDate: event.expiryDate,
    );
    emit(state.copyWith(items: [...state.items, newItem]));
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
    emit(state.copyWith(items: updatedItems));
  }

  void _onLineItemRemoved(
    PurchaseLineItemRemoved event,
    Emitter<PurchaseFormState> emit,
  ) {
    final updatedItems = state.items.where((item) => item.tempId != event.tempId).toList();
    emit(state.copyWith(items: updatedItems));
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

      final purchaseId = await _repository.createPurchase(
        supplierId: state.supplierId!,
        currencyId: state.currencyId,
        subtotalCents: state.subtotalCents,
        discountCents: state.totalDiscountCents,
        taxCents: state.taxCents,
        totalCents: state.totalCents,
        items: items,
        notes: state.notes,
        purchaseDate: state.purchaseDate,
      );

      emit(state.copyWith(
        purchaseId: purchaseId,
        isSubmitting: false,
        isSuccess: true,
      ));
    } catch (e) {
      emit(state.copyWith(
        isSubmitting: false,
        error: e.toString(),
      ));
    }
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
