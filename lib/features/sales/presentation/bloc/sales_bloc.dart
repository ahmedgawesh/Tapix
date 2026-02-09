import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/bloc/realtime_bloc.dart';
import '../../domain/entities/sale_entity.dart';
import '../../domain/repositories/sale_repository.dart';

// ==================== STATE ====================

class SalesHubData {
  final List<SaleEntity> sales;
  final SaleDashboardStats stats;
  final String? searchQuery;
  final String? statusFilter;
  final Set<int> saleIdsWithReturns;

  const SalesHubData({
    required this.sales,
    required this.stats,
    this.searchQuery,
    this.statusFilter,
    this.saleIdsWithReturns = const {},
  });

  List<SaleEntity> get filteredSales {
    var list = sales;
    if (statusFilter != null && statusFilter!.isNotEmpty) {
      list = list.where((s) => s.status == statusFilter).toList();
    }
    if (searchQuery != null && searchQuery!.isNotEmpty) {
      final q = searchQuery!.toLowerCase();
      list = list.where((s) =>
          s.invoiceNumber.toLowerCase().contains(q) ||
          (s.customerName?.toLowerCase().contains(q) ?? false)).toList();
    }
    return list;
  }
}

// ==================== EVENTS ====================

abstract class SalesEvent extends RealtimeEvent {
  const SalesEvent();
}

class SalesSearchRequested extends SalesEvent {
  final String query;
  const SalesSearchRequested(this.query);
}

class SalesStatusFilterChanged extends SalesEvent {
  final String? status;
  const SalesStatusFilterChanged(this.status);
}

class SaleVoidRequested extends SalesEvent {
  final int saleId;
  const SaleVoidRequested(this.saleId);
}

class SaleDeleteRequested extends SalesEvent {
  final int saleId;
  const SaleDeleteRequested(this.saleId);
}

// ==================== BLOC ====================

class SalesBloc extends RealtimeBloc<SalesHubData, SalesEvent> {
  final SaleRepository _repository;
  String? _searchQuery;
  String? _statusFilter;

  List<SaleEntity>? _latestSales;
  SaleDashboardStats? _latestStats;
  Set<int>? _returnSaleIds;
  StreamSubscription<SaleDashboardStats>? _statsSub;
  StreamSubscription<Set<int>>? _returnIdsSub;

  SalesBloc(this._repository) : super(const RealtimeLoading()) {
    _statsSub = _repository.watchDashboardStats().listen((stats) {
      _latestStats = stats;
      _emitCombined();
    });
    _returnIdsSub = _repository.watchSaleIdsWithReturns().listen((ids) {
      _returnSaleIds = ids;
      _emitCombined();
    });
  }

  @override
  void registerEventHandlers() {
    on<SalesSearchRequested>(_onSearch);
    on<SalesStatusFilterChanged>(_onStatusFilter);
    on<SaleVoidRequested>(_onVoidSale);
    on<SaleDeleteRequested>(_onDeleteSale);
  }

  @override
  Stream<SalesHubData> get dataStream {
    return _repository.watchAllSales().map((sales) {
      _latestSales = sales;
      return SalesHubData(
        sales: sales,
        stats: _latestStats ?? const SaleDashboardStats(
          totalCount: 0, completedCount: 0, voidedCount: 0,
          totalSalesCents: 0, returnsCount: 0, totalReturnsCents: 0,
          todaySalesCents: 0, todayCount: 0,
        ),
        searchQuery: _searchQuery,
        statusFilter: _statusFilter,
        saleIdsWithReturns: _returnSaleIds ?? const {},
      );
    });
  }

  void _emitCombined() {
    if (_latestSales != null && _latestStats != null) {
      // ignore: invalid_use_of_visible_for_testing_member
      emit(RealtimeSuccess(data: SalesHubData(
        sales: _latestSales!,
        stats: _latestStats!,
        searchQuery: _searchQuery,
        statusFilter: _statusFilter,
        saleIdsWithReturns: _returnSaleIds ?? const {},
      )));
    }
  }

  void _onSearch(
    SalesSearchRequested event,
    Emitter<RealtimeState<SalesHubData>> emit,
  ) {
    _searchQuery = event.query.isEmpty ? null : event.query;
    final data = currentData;
    if (data != null) {
      emit(RealtimeSuccess(data: SalesHubData(
        sales: data.sales,
        stats: data.stats,
        searchQuery: _searchQuery,
        statusFilter: _statusFilter,
        saleIdsWithReturns: data.saleIdsWithReturns,
      )));
    }
  }

  void _onStatusFilter(
    SalesStatusFilterChanged event,
    Emitter<RealtimeState<SalesHubData>> emit,
  ) {
    _statusFilter = event.status;
    final data = currentData;
    if (data != null) {
      emit(RealtimeSuccess(data: SalesHubData(
        sales: data.sales,
        stats: data.stats,
        searchQuery: _searchQuery,
        statusFilter: _statusFilter,
        saleIdsWithReturns: data.saleIdsWithReturns,
      )));
    }
  }

  Future<void> _onVoidSale(
    SaleVoidRequested event,
    Emitter<RealtimeState<SalesHubData>> emit,
  ) async {
    try {
      await _repository.voidSale(event.saleId);
    } catch (e) {
      emit(RealtimeError(error: e, previousData: currentData));
    }
  }

  Future<void> _onDeleteSale(
    SaleDeleteRequested event,
    Emitter<RealtimeState<SalesHubData>> emit,
  ) async {
    try {
      await _repository.deleteSale(event.saleId);
    } catch (e) {
      emit(RealtimeError(error: e, previousData: currentData));
    }
  }

  @override
  Future<void> close() {
    _statsSub?.cancel();
    _returnIdsSub?.cancel();
    return super.close();
  }
}
