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
  final Set<int> purchaseIdsWithReturns;
  final Map<int, List<String>> productSearchTerms;
  final Set<int> productMatchedPurchaseIds;

  static const int searchResultLimit = 20;

  const PurchasesHubData({
    required this.purchases,
    required this.stats,
    this.searchQuery,
    this.statusFilter,
    this.purchaseIdsWithReturns = const {},
    this.productSearchTerms = const {},
    this.productMatchedPurchaseIds = const {},
  });

  List<PurchaseEntity> get filteredPurchases {
    var list = purchases;
    if (statusFilter != null && statusFilter!.isNotEmpty) {
      list = list.where((p) => p.status == statusFilter).toList();
    }
    if (searchQuery != null && searchQuery!.isNotEmpty) {
      final q = searchQuery!.toLowerCase();
      list = list.where((p) {
        // Priority 1: purchase number
        if (p.purchaseNumber.toLowerCase().contains(q)) return true;
        // Priority 2: supplier name
        if (p.supplierName?.toLowerCase().contains(q) ?? false) return true;
        // Priority 2b: supplier phone
        if (p.supplierPhone?.contains(q) ?? false) return true;
        // Priority 3: product name / barcode / SKU
        final terms = productSearchTerms[p.id];
        if (terms != null) {
          for (final term in terms) {
            if (term.toLowerCase().contains(q)) return true;
          }
        }
        return false;
      }).toList();
    }
    // Limit results for performance
    if (list.length > searchResultLimit && searchQuery != null && searchQuery!.isNotEmpty) {
      list = list.sublist(0, searchResultLimit);
    }
    return list;
  }

  /// Compute which purchase IDs were matched via product search terms
  static Set<int> computeProductMatchedIds(
    List<PurchaseEntity> purchases,
    String? query,
    Map<int, List<String>> productTerms,
  ) {
    if (query == null || query.isEmpty) return const {};
    final q = query.toLowerCase();
    final matched = <int>{};
    for (final purchase in purchases) {
      // Only flag product match if the purchase did NOT match by number/supplier/phone
      final matchesNumber = purchase.purchaseNumber.toLowerCase().contains(q);
      final matchesSupplier = purchase.supplierName?.toLowerCase().contains(q) ?? false;
      final matchesPhone = purchase.supplierPhone?.contains(q) ?? false;
      if (!matchesNumber && !matchesSupplier && !matchesPhone) {
        final terms = productTerms[purchase.id];
        if (terms != null) {
          for (final term in terms) {
            if (term.toLowerCase().contains(q)) {
              matched.add(purchase.id);
              break;
            }
          }
        }
      }
    }
    return matched;
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

  // Keep latest values from all streams
  List<PurchaseEntity>? _latestPurchases;
  PurchaseDashboardStats? _latestStats;
  Set<int>? _returnPurchaseIds;
  Map<int, List<String>>? _productSearchTerms;
  StreamSubscription<PurchaseDashboardStats>? _statsSub;
  StreamSubscription<Set<int>>? _returnIdsSub;
  StreamSubscription<Map<int, List<String>>>? _productTermsSub;

  PurchasesBloc(this._repository) : super(const RealtimeLoading()) {
    _statsSub = _repository.watchDashboardStats().listen((stats) {
      _latestStats = stats;
      _emitCombined();
    });
    _returnIdsSub = _repository.watchPurchaseIdsWithReturns().listen((ids) {
      _returnPurchaseIds = ids;
      _emitCombined();
    });
    _productTermsSub = _repository.watchPurchaseProductSearchTerms().listen((terms) {
      _productSearchTerms = terms;
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
      final terms = _productSearchTerms ?? const {};
      return PurchasesHubData(
        purchases: purchases,
        stats: _latestStats ?? const PurchaseDashboardStats(
          totalCount: 0, draftCount: 0, postedCount: 0,
          totalPayableCents: 0, totalPaidCents: 0,
          overdueCount: 0, returnsCount: 0,
        ),
        searchQuery: _searchQuery,
        statusFilter: _statusFilter,
        purchaseIdsWithReturns: _returnPurchaseIds ?? const {},
        productSearchTerms: terms,
        productMatchedPurchaseIds: PurchasesHubData.computeProductMatchedIds(
          purchases, _searchQuery, terms,
        ),
      );
    });
  }

  void _emitCombined() {
    if (_latestPurchases != null && _latestStats != null) {
      final terms = _productSearchTerms ?? const {};
      // ignore: invalid_use_of_visible_for_testing_member
      emit(RealtimeSuccess(data: PurchasesHubData(
        purchases: _latestPurchases!,
        stats: _latestStats!,
        searchQuery: _searchQuery,
        statusFilter: _statusFilter,
        purchaseIdsWithReturns: _returnPurchaseIds ?? const {},
        productSearchTerms: terms,
        productMatchedPurchaseIds: PurchasesHubData.computeProductMatchedIds(
          _latestPurchases!, _searchQuery, terms,
        ),
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
      final terms = _productSearchTerms ?? const {};
      emit(RealtimeSuccess(data: PurchasesHubData(
        purchases: data.purchases,
        stats: data.stats,
        searchQuery: _searchQuery,
        statusFilter: _statusFilter,
        purchaseIdsWithReturns: data.purchaseIdsWithReturns,
        productSearchTerms: terms,
        productMatchedPurchaseIds: PurchasesHubData.computeProductMatchedIds(
          data.purchases, _searchQuery, terms,
        ),
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
      final terms = _productSearchTerms ?? const {};
      emit(RealtimeSuccess(data: PurchasesHubData(
        purchases: data.purchases,
        stats: data.stats,
        searchQuery: _searchQuery,
        statusFilter: _statusFilter,
        purchaseIdsWithReturns: data.purchaseIdsWithReturns,
        productSearchTerms: terms,
        productMatchedPurchaseIds: PurchasesHubData.computeProductMatchedIds(
          data.purchases, _searchQuery, terms,
        ),
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
    _returnIdsSub?.cancel();
    _productTermsSub?.cancel();
    return super.close();
  }
}
