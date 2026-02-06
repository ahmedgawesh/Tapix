import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/bloc/realtime_bloc.dart';
import '../../domain/entities/purchase_entity.dart';
import '../../domain/repositories/purchase_repository.dart';

// ==================== STATE ====================

class PurchasesHubData {
  final List<PurchaseEntity> purchases;
  final PurchaseDashboardStats stats;
  final String? searchQuery;
  final String? statusFilter;

  const PurchasesHubData({
    required this.purchases,
    required this.stats,
    this.searchQuery,
    this.statusFilter,
  });

  List<PurchaseEntity> get filteredPurchases {
    var list = purchases;
    if (statusFilter != null && statusFilter!.isNotEmpty) {
      list = list.where((p) => p.status == statusFilter).toList();
    }
    if (searchQuery != null && searchQuery!.isNotEmpty) {
      final q = searchQuery!.toLowerCase();
      list = list.where((p) =>
          p.purchaseNumber.toLowerCase().contains(q) ||
          (p.supplierName?.toLowerCase().contains(q) ?? false)).toList();
    }
    return list;
  }
}

// ==================== EVENTS ====================

abstract class PurchasesEvent extends RealtimeEvent {
  const PurchasesEvent();
}

class PurchasesSearchRequested extends PurchasesEvent {
  final String query;
  const PurchasesSearchRequested(this.query);
}

class PurchasesStatusFilterChanged extends PurchasesEvent {
  final String? status;
  const PurchasesStatusFilterChanged(this.status);
}

class PurchasePostRequested extends PurchasesEvent {
  final int purchaseId;
  const PurchasePostRequested(this.purchaseId);
}

class PurchaseVoidRequested extends PurchasesEvent {
  final int purchaseId;
  const PurchaseVoidRequested(this.purchaseId);
}

class PurchaseDeleteRequested extends PurchasesEvent {
  final int purchaseId;
  const PurchaseDeleteRequested(this.purchaseId);
}

// ==================== BLOC ====================

class PurchasesBloc extends RealtimeBloc<PurchasesHubData, PurchasesEvent> {
  final PurchaseRepository _repository;
  String? _searchQuery;
  String? _statusFilter;

  // Keep latest values from both streams
  List<PurchaseEntity>? _latestPurchases;
  PurchaseDashboardStats? _latestStats;
  StreamSubscription<PurchaseDashboardStats>? _statsSub;

  PurchasesBloc(this._repository) : super(const RealtimeLoading()) {
    // Subscribe to stats stream separately
    _statsSub = _repository.watchDashboardStats().listen((stats) {
      _latestStats = stats;
      _emitCombined();
    });
  }

  @override
  void registerEventHandlers() {
    on<PurchasesSearchRequested>(_onSearch);
    on<PurchasesStatusFilterChanged>(_onStatusFilter);
    on<PurchasePostRequested>(_onPostPurchase);
    on<PurchaseVoidRequested>(_onVoidPurchase);
    on<PurchaseDeleteRequested>(_onDeletePurchase);
  }

  @override
  Stream<PurchasesHubData> get dataStream {
    return _repository.watchAllPurchases().map((purchases) {
      _latestPurchases = purchases;
      return PurchasesHubData(
        purchases: purchases,
        stats: _latestStats ?? const PurchaseDashboardStats(
          totalCount: 0, draftCount: 0, postedCount: 0,
          totalPayableCents: 0, returnsCount: 0,
        ),
        searchQuery: _searchQuery,
        statusFilter: _statusFilter,
      );
    });
  }

  void _emitCombined() {
    if (_latestPurchases != null && _latestStats != null) {
      // ignore: invalid_use_of_visible_for_testing_member
      emit(RealtimeSuccess(data: PurchasesHubData(
        purchases: _latestPurchases!,
        stats: _latestStats!,
        searchQuery: _searchQuery,
        statusFilter: _statusFilter,
      )));
    }
  }

  void _onSearch(
    PurchasesSearchRequested event,
    Emitter<RealtimeState<PurchasesHubData>> emit,
  ) {
    _searchQuery = event.query.isEmpty ? null : event.query;
    final data = currentData;
    if (data != null) {
      emit(RealtimeSuccess(data: PurchasesHubData(
        purchases: data.purchases,
        stats: data.stats,
        searchQuery: _searchQuery,
        statusFilter: _statusFilter,
      )));
    }
  }

  void _onStatusFilter(
    PurchasesStatusFilterChanged event,
    Emitter<RealtimeState<PurchasesHubData>> emit,
  ) {
    _statusFilter = event.status;
    final data = currentData;
    if (data != null) {
      emit(RealtimeSuccess(data: PurchasesHubData(
        purchases: data.purchases,
        stats: data.stats,
        searchQuery: _searchQuery,
        statusFilter: _statusFilter,
      )));
    }
  }

  Future<void> _onPostPurchase(
    PurchasePostRequested event,
    Emitter<RealtimeState<PurchasesHubData>> emit,
  ) async {
    try {
      await _repository.postPurchase(event.purchaseId);
    } catch (e) {
      emit(RealtimeError(error: e, previousData: currentData));
    }
  }

  Future<void> _onVoidPurchase(
    PurchaseVoidRequested event,
    Emitter<RealtimeState<PurchasesHubData>> emit,
  ) async {
    try {
      await _repository.voidPurchase(event.purchaseId);
    } catch (e) {
      emit(RealtimeError(error: e, previousData: currentData));
    }
  }

  Future<void> _onDeletePurchase(
    PurchaseDeleteRequested event,
    Emitter<RealtimeState<PurchasesHubData>> emit,
  ) async {
    try {
      await _repository.deletePurchase(event.purchaseId);
    } catch (e) {
      emit(RealtimeError(error: e, previousData: currentData));
    }
  }

  @override
  Future<void> close() {
    _statsSub?.cancel();
    return super.close();
  }
}
