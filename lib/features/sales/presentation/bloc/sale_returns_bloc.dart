import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/bloc/realtime_bloc.dart';
import '../../domain/entities/sale_entity.dart';
import '../../domain/repositories/sale_repository.dart';

// ==================== EVENTS ====================

abstract class SaleReturnsEvent extends RealtimeEvent {
  const SaleReturnsEvent();
}

class SaleReturnsSearchRequested extends SaleReturnsEvent {
  final String query;
  const SaleReturnsSearchRequested(this.query);
}

// ==================== BLOC ====================

class SaleReturnsBloc
    extends RealtimeBloc<List<SaleReturnEntity>, SaleReturnsEvent> {
  final SaleRepository _repository;
  String? _searchQuery;

  SaleReturnsBloc(this._repository) : super(const RealtimeLoading());

  @override
  void registerEventHandlers() {
    on<SaleReturnsSearchRequested>(_onSearch);
  }

  @override
  Stream<List<SaleReturnEntity>> get dataStream {
    return _repository.watchAllSaleReturns();
  }

  void _onSearch(
    SaleReturnsSearchRequested event,
    Emitter<RealtimeState<List<SaleReturnEntity>>> emit,
  ) {
    _searchQuery = event.query.isEmpty ? null : event.query;
    final data = currentData;
    if (data != null) {
      final filtered = _applyFilter(data);
      emit(RealtimeSuccess(data: filtered));
    }
  }

  List<SaleReturnEntity> _applyFilter(List<SaleReturnEntity> returns) {
    if (_searchQuery == null || _searchQuery!.isEmpty) return returns;
    final q = _searchQuery!.toLowerCase();
    return returns.where((r) =>
        r.returnNumber.toLowerCase().contains(q) ||
        (r.saleInvoiceNumber?.toLowerCase().contains(q) ?? false) ||
        (r.customerName?.toLowerCase().contains(q) ?? false)).toList();
  }
}
