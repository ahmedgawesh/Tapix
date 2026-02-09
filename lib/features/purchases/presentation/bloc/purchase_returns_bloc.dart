import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/bloc/realtime_bloc.dart';
import '../../domain/entities/purchase_entity.dart';
import '../../domain/repositories/purchase_repository.dart';

// ==================== EVENTS ====================

abstract class PurchaseReturnsEvent extends RealtimeEvent {
  const PurchaseReturnsEvent();
}

class PurchaseReturnsSearchRequested extends PurchaseReturnsEvent {
  final String query;
  const PurchaseReturnsSearchRequested(this.query);
}

// ==================== BLOC ====================

class PurchaseReturnsBloc
    extends RealtimeBloc<List<PurchaseReturnEntity>, PurchaseReturnsEvent> {
  final PurchaseRepository _repository;
  String? _searchQuery;
  List<PurchaseReturnEntity>? _latestStreamData;

  PurchaseReturnsBloc(this._repository) : super(const RealtimeLoading());

  @override
  void registerEventHandlers() {
    on<PurchaseReturnsSearchRequested>(_onSearch);
  }

  @override
  Stream<List<PurchaseReturnEntity>> get dataStream {
    return _repository.watchAllPurchaseReturns();
  }

  @override
  RealtimeState<List<PurchaseReturnEntity>> mapDataToState(
      List<PurchaseReturnEntity> data) {
    _latestStreamData = data;
    return RealtimeSuccess<List<PurchaseReturnEntity>>(data: _applyFilter(data));
  }

  void _onSearch(
    PurchaseReturnsSearchRequested event,
    Emitter<RealtimeState<List<PurchaseReturnEntity>>> emit,
  ) {
    _searchQuery = event.query.isEmpty ? null : event.query;

    final base = _latestStreamData ?? currentData;
    if (base != null) {
      emit(RealtimeSuccess(data: _applyFilter(base)));
    }
  }

  List<PurchaseReturnEntity> _applyFilter(List<PurchaseReturnEntity> returns) {
    if (_searchQuery == null || _searchQuery!.isEmpty) return returns;
    final q = _searchQuery!.toLowerCase();
    return returns.where((r) =>
        r.returnNumber.toLowerCase().contains(q) ||
        (r.supplierName?.toLowerCase().contains(q) ?? false)).toList();
  }
}
