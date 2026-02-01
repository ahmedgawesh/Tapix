import 'package:decimal/decimal.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';

import '../../domain/repositories/purchase_repository.dart';
import '../../../products/domain/entities/product_entity.dart';
import '../../../products/domain/entities/product_variant_entity.dart';

// State
class PurchaseFormState extends Equatable {
  final int? purchaseId;
  final int? supplierId;
  final int currencyId;
  final List<PurchaseLineItem> items;
  final DateTime purchaseDate;
  final bool isSubmitting;
  final String? error;
  final bool isSuccess;

  const PurchaseFormState({
    this.purchaseId,
    this.supplierId,
    required this.currencyId,
    this.items = const [],
    required this.purchaseDate,
    this.isSubmitting = false,
    this.error,
    this.isSuccess = false,
  });

  Decimal get subtotalCents => items.fold(
        Decimal.zero,
        (sum, item) => sum + item.subtotalCents,
      );

  Decimal get taxCents => items.fold(
        Decimal.zero,
        (sum, item) => sum + item.taxCents,
      );

  Decimal get totalCents => subtotalCents + taxCents;

  int get totalQuantity => items.fold(0, (sum, item) => sum + item.quantity);

  PurchaseFormState copyWith({
    int? purchaseId,
    int? supplierId,
    int? currencyId,
    List<PurchaseLineItem>? items,
    DateTime? purchaseDate,
    bool? isSubmitting,
    String? error,
    bool? isSuccess,
  }) {
    return PurchaseFormState(
      purchaseId: purchaseId ?? this.purchaseId,
      supplierId: supplierId ?? this.supplierId,
      currencyId: currencyId ?? this.currencyId,
      items: items ?? this.items,
      purchaseDate: purchaseDate ?? this.purchaseDate,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      error: error,
      isSuccess: isSuccess ?? this.isSuccess,
    );
  }

  @override
  List<Object?> get props => [
        purchaseId,
        supplierId,
        currencyId,
        items,
        purchaseDate,
        isSubmitting,
        error,
        isSuccess,
      ];
}

/// A line item in the purchase form
class PurchaseLineItem extends Equatable {
  final String tempId;
  final Product product;
  final ProductVariant? variant;
  final int quantity;
  final Decimal unitCostCents;
  final Decimal taxCents;

  PurchaseLineItem({
    required this.tempId,
    required this.product,
    this.variant,
    required this.quantity,
    required this.unitCostCents,
    Decimal? taxCents,
  }) : taxCents = taxCents ?? Decimal.zero;

  Decimal get subtotalCents => unitCostCents * Decimal.fromInt(quantity);
  Decimal get totalCents => subtotalCents + taxCents;

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
    Decimal? taxCents,
  }) {
    return PurchaseLineItem(
      tempId: tempId ?? this.tempId,
      product: product ?? this.product,
      variant: variant ?? this.variant,
      quantity: quantity ?? this.quantity,
      unitCostCents: unitCostCents ?? this.unitCostCents,
      taxCents: taxCents ?? this.taxCents,
    );
  }

  @override
  List<Object?> get props => [tempId, product, variant, quantity, unitCostCents, taxCents];
}

// Events
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
  const PurchaseSupplierChanged(this.supplierId);

  @override
  List<Object?> get props => [supplierId];
}

class PurchaseDateChanged extends PurchaseFormEvent {
  final DateTime date;
  const PurchaseDateChanged(this.date);

  @override
  List<Object?> get props => [date];
}

class PurchaseLineItemAdded extends PurchaseFormEvent {
  final Product product;
  final ProductVariant? variant;
  final int quantity;
  final Decimal unitCostCents;

  const PurchaseLineItemAdded({
    required this.product,
    this.variant,
    required this.quantity,
    required this.unitCostCents,
  });

  @override
  List<Object?> get props => [product, variant, quantity, unitCostCents];
}

class PurchaseLineItemUpdated extends PurchaseFormEvent {
  final String tempId;
  final int? quantity;
  final Decimal? unitCostCents;

  const PurchaseLineItemUpdated({
    required this.tempId,
    this.quantity,
    this.unitCostCents,
  });

  @override
  List<Object?> get props => [tempId, quantity, unitCostCents];
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

// Bloc
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
      supplierId: state.supplierId ?? 1,
    ));
  }

  void _onSupplierChanged(
    PurchaseSupplierChanged event,
    Emitter<PurchaseFormState> emit,
  ) {
    emit(state.copyWith(supplierId: event.supplierId));
  }

  void _onDateChanged(
    PurchaseDateChanged event,
    Emitter<PurchaseFormState> emit,
  ) {
    emit(state.copyWith(purchaseDate: event.date));
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
            subtotalCents: item.subtotalCents,
            taxCents: item.taxCents,
            totalCents: item.totalCents,
          )).toList();

      final purchaseId = await _repository.createPurchase(
        supplierId: state.supplierId!,
        currencyId: state.currencyId,
        subtotalCents: state.subtotalCents,
        taxCents: state.taxCents,
        totalCents: state.totalCents,
        items: items,
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
