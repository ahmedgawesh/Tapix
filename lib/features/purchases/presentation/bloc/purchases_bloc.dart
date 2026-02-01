import 'package:decimal/decimal.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/bloc/realtime_bloc.dart';
import '../../domain/entities/purchase_entity.dart';
import '../../domain/repositories/purchase_repository.dart';

// Events
abstract class PurchasesEvent extends RealtimeEvent {
  const PurchasesEvent();
}

class PurchasesInitialized extends PurchasesEvent {
  const PurchasesInitialized();
}

class PurchasesByStatusRequested extends PurchasesEvent {
  final String status;
  const PurchasesByStatusRequested(this.status);
}

class PurchaseCreateRequested extends PurchasesEvent {
  final int supplierId;
  final int currencyId;
  final Decimal subtotalCents;
  final Decimal taxCents;
  final Decimal totalCents;
  final List<PurchaseItemInput> items;
  final DateTime? purchaseDate;

  const PurchaseCreateRequested({
    required this.supplierId,
    required this.currencyId,
    required this.subtotalCents,
    required this.taxCents,
    required this.totalCents,
    required this.items,
    this.purchaseDate,
  });
}

class PurchasePostRequested extends PurchasesEvent {
  final int purchaseId;
  const PurchasePostRequested(this.purchaseId);
}

class PurchaseDeleteRequested extends PurchasesEvent {
  final int purchaseId;
  const PurchaseDeleteRequested(this.purchaseId);
}

// Bloc
class PurchasesBloc extends RealtimeBloc<List<PurchaseEntity>, PurchasesEvent> {
  final PurchaseRepository _repository;
  String? _statusFilter;
  bool _initialized = false;

  PurchasesBloc(this._repository) : super(const RealtimeLoading()) {
    add(const PurchasesInitialized());
  }

  @override
  void registerEventHandlers() {
    on<PurchasesInitialized>(_onInitialized);
    on<PurchasesByStatusRequested>(_onStatusFilter);
    on<PurchaseCreateRequested>(_onCreatePurchase);
    on<PurchasePostRequested>(_onPostPurchase);
    on<PurchaseDeleteRequested>(_onDeletePurchase);
  }

  @override
  Stream<List<PurchaseEntity>> get dataStream {
    if (!_initialized) {
      return const Stream.empty();
    }
    if (_statusFilter != null) {
      return _repository.watchPurchasesByStatus(_statusFilter!);
    }
    return _repository.watchAllPurchases();
  }

  void _onInitialized(
    PurchasesInitialized event,
    Emitter<RealtimeState<List<PurchaseEntity>>> emit,
  ) {
    _initialized = true;
    refresh();
  }

  void _onStatusFilter(
    PurchasesByStatusRequested event,
    Emitter<RealtimeState<List<PurchaseEntity>>> emit,
  ) {
    _statusFilter = event.status;
    refresh();
  }

  Future<void> _onCreatePurchase(
    PurchaseCreateRequested event,
    Emitter<RealtimeState<List<PurchaseEntity>>> emit,
  ) async {
    try {
      await _repository.createPurchase(
        supplierId: event.supplierId,
        currencyId: event.currencyId,
        subtotalCents: event.subtotalCents,
        taxCents: event.taxCents,
        totalCents: event.totalCents,
        items: event.items,
        purchaseDate: event.purchaseDate,
      );
    } catch (e) {
      emit(RealtimeError(error: e, previousData: currentData));
    }
  }

  Future<void> _onPostPurchase(
    PurchasePostRequested event,
    Emitter<RealtimeState<List<PurchaseEntity>>> emit,
  ) async {
    try {
      await _repository.postPurchase(event.purchaseId);
    } catch (e) {
      emit(RealtimeError(error: e, previousData: currentData));
    }
  }

  Future<void> _onDeletePurchase(
    PurchaseDeleteRequested event,
    Emitter<RealtimeState<List<PurchaseEntity>>> emit,
  ) async {
    try {
      await _repository.deletePurchase(event.purchaseId);
    } catch (e) {
      emit(RealtimeError(error: e, previousData: currentData));
    }
  }
}
