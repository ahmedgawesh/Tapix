import 'package:decimal/decimal.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';

import '../../domain/repositories/purchase_repository.dart';
import '../../../products/domain/entities/product_entity.dart';
import '../../../products/domain/entities/product_variant_entity.dart';

// ==================== STATE ====================

class PurchaseFormState extends Equatable {
  final int? purchaseId;
  final int? supplierId;
  final String? supplierName;
  final int currencyId;
  final List<PurchaseLineItem> items;
  final Decimal invoiceDiscountCents;
  final String? notes;
  final DateTime purchaseDate;
  final bool isSubmitting;
  final String? error;
  final bool isSuccess;

  PurchaseFormState({
    this.purchaseId,
    this.supplierId,
    this.supplierName,
    required this.currencyId,
    this.items = const [],
    Decimal? invoiceDiscountCents,
    this.notes,
    required this.purchaseDate,
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

  Decimal get totalDiscountCents => itemDiscountCents + invoiceDiscountCents;

  Decimal get taxCents => items.fold(
        Decimal.zero,
        (sum, item) => sum + item.taxCents,
      );

  Decimal get totalCents => subtotalCents - totalDiscountCents + taxCents;

  int get totalQuantity => items.fold(0, (sum, item) => sum + item.quantity);

  PurchaseFormState copyWith({
    int? purchaseId,
    int? supplierId,
    String? supplierName,
    int? currencyId,
    List<PurchaseLineItem>? items,
    Decimal? invoiceDiscountCents,
    String? notes,
    DateTime? purchaseDate,
    bool? isSubmitting,
    String? error,
    bool? isSuccess,
  }) {
    return PurchaseFormState(
      purchaseId: purchaseId ?? this.purchaseId,
      supplierId: supplierId ?? this.supplierId,
      supplierName: supplierName ?? this.supplierName,
      currencyId: currencyId ?? this.currencyId,
      items: items ?? this.items,
      invoiceDiscountCents: invoiceDiscountCents ?? this.invoiceDiscountCents,
      notes: notes ?? this.notes,
      purchaseDate: purchaseDate ?? this.purchaseDate,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      error: error,
      isSuccess: isSuccess ?? this.isSuccess,
    );
  }

  @override
  List<Object?> get props => [
        purchaseId, supplierId, supplierName, currencyId, items,
        invoiceDiscountCents, notes, purchaseDate,
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
  }) {
    return PurchaseLineItem(
      tempId: tempId ?? this.tempId,
      product: product ?? this.product,
      variant: variant ?? this.variant,
      quantity: quantity ?? this.quantity,
      unitCostCents: unitCostCents ?? this.unitCostCents,
      discountCents: discountCents ?? this.discountCents,
      taxCents: taxCents ?? this.taxCents,
      expiryDate: expiryDate ?? this.expiryDate,
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

class PurchaseNotesChanged extends PurchaseFormEvent {
  final String notes;
  const PurchaseNotesChanged(this.notes);

  @override
  List<Object?> get props => [notes];
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

  const PurchaseLineItemUpdated({
    required this.tempId,
    this.quantity,
    this.unitCostCents,
    this.discountCents,
    this.expiryDate,
  });

  @override
  List<Object?> get props => [tempId, quantity, unitCostCents, discountCents, expiryDate];
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
    on<PurchaseNotesChanged>(_onNotesChanged);
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

  void _onNotesChanged(
    PurchaseNotesChanged event,
    Emitter<PurchaseFormState> emit,
  ) {
    emit(state.copyWith(notes: event.notes));
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
