import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/services/lan/lan_network_service.dart';
import '../../domain/entities/sale_entity.dart';
import '../../domain/repositories/sale_repository.dart';

// ==================== STATE ====================

class SalesHubData {
  final List<SaleEntity> sales;
  final SaleDashboardStats stats;
  final String? searchQuery;
  final String? statusFilter;
  final Set<int> saleIdsWithReturns;
  final Map<int, List<String>> productSearchTerms;
  final Set<int> productMatchedSaleIds;
  final String? currencyCode;
  final String? currencySymbol;
  final int? currencyDecimalDigits;
  final bool currencySymbolAfter;

  static const int searchResultLimit = 20;

  const SalesHubData({
    required this.sales,
    required this.stats,
    this.searchQuery,
    this.statusFilter,
    this.saleIdsWithReturns = const {},
    this.productSearchTerms = const {},
    this.productMatchedSaleIds = const {},
    this.currencyCode,
    this.currencySymbol,
    this.currencyDecimalDigits,
    this.currencySymbolAfter = false,
  });

  List<SaleEntity> get filteredSales {
    var list = sales;
    if (statusFilter != null && statusFilter!.isNotEmpty) {
      list = list.where((s) => s.status == statusFilter).toList();
    }
    if (searchQuery != null && searchQuery!.isNotEmpty) {
      final q = searchQuery!.toLowerCase();
      list = list.where((s) {
        // Priority 1: invoice number
        if (s.invoiceNumber.toLowerCase().contains(q)) return true;
        // Priority 2: customer name
        if (s.customerName?.toLowerCase().contains(q) ?? false) return true;
        // Priority 2b: customer phone
        if (s.customerPhone?.contains(q) ?? false) return true;
        // Priority 3: product name / barcode / SKU
        final terms = productSearchTerms[s.id];
        if (terms != null) {
          for (final term in terms) {
            if (term.toLowerCase().contains(q)) return true;
          }
        }
        return false;
      }).toList();
    }
    // Limit results for performance
    if (list.length > searchResultLimit &&
        searchQuery != null &&
        searchQuery!.isNotEmpty) {
      list = list.sublist(0, searchResultLimit);
    }
    return list;
  }

  /// Compute which sale IDs were matched via product search terms
  static Set<int> computeProductMatchedIds(
    List<SaleEntity> sales,
    String? query,
    Map<int, List<String>> productTerms,
  ) {
    if (query == null || query.isEmpty) return const {};
    final q = query.toLowerCase();
    final matched = <int>{};
    for (final sale in sales) {
      // Only flag product match if the sale did NOT match by invoice/customer/phone
      final matchesInvoice = sale.invoiceNumber.toLowerCase().contains(q);
      final matchesCustomer =
          sale.customerName?.toLowerCase().contains(q) ?? false;
      final matchesPhone = sale.customerPhone?.contains(q) ?? false;
      if (!matchesInvoice && !matchesCustomer && !matchesPhone) {
        final terms = productTerms[sale.id];
        if (terms != null) {
          for (final term in terms) {
            if (term.toLowerCase().contains(q)) {
              matched.add(sale.id);
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
  final LanNetworkService? _lan;
  String? _searchQuery;
  String? _statusFilter;

  List<SaleEntity>? _latestSales;
  SaleDashboardStats? _latestStats;
  Set<int>? _returnSaleIds;
  Map<int, List<String>>? _productSearchTerms;
  StreamSubscription<SaleDashboardStats>? _statsSub;
  StreamSubscription<Set<int>>? _returnIdsSub;
  StreamSubscription<Map<int, List<String>>>? _productTermsSub;

  SalesBloc(this._repository, {LanNetworkService? lan})
    : _lan = lan,
      super(const RealtimeLoading()) {
    if (_isRemoteClient) return;
    _statsSub = _repository.watchDashboardStats().listen((stats) {
      _latestStats = stats;
      _emitCombined();
    });
    _returnIdsSub = _repository.watchSaleIdsWithReturns().listen((ids) {
      _returnSaleIds = ids;
      _emitCombined();
    });
    _productTermsSub = _repository.watchSaleProductSearchTerms().listen((
      terms,
    ) {
      _productSearchTerms = terms;
      _emitCombined();
    });
  }

  bool get _isRemoteClient => _lan?.snapshot.mode == LanMode.client;

  @override
  void registerEventHandlers() {
    on<SalesSearchRequested>(_onSearch);
    on<SalesStatusFilterChanged>(_onStatusFilter);
    on<SaleVoidRequested>(_onVoidSale);
    on<SaleDeleteRequested>(_onDeleteSale);
  }

  @override
  Stream<SalesHubData> get dataStream {
    if (_isRemoteClient) {
      return Stream.fromFuture(_lan!.fetchRemoteSales()).map(_remotePageToData);
    }
    return _repository.watchAllSales().map((sales) {
      _latestSales = sales;
      final terms = _productSearchTerms ?? const {};
      return SalesHubData(
        sales: sales,
        stats:
            _latestStats ??
            const SaleDashboardStats(
              totalCount: 0,
              completedCount: 0,
              voidedCount: 0,
              totalSalesCents: 0,
              returnsCount: 0,
              totalReturnsCents: 0,
              todaySalesCents: 0,
              todayCount: 0,
            ),
        searchQuery: _searchQuery,
        statusFilter: _statusFilter,
        saleIdsWithReturns: _returnSaleIds ?? const {},
        productSearchTerms: terms,
        productMatchedSaleIds: SalesHubData.computeProductMatchedIds(
          sales,
          _searchQuery,
          terms,
        ),
      );
    });
  }

  SalesHubData _remotePageToData(LanSalesPage page) {
    final sales = page.sales
        .map(
          (sale) => SaleEntity(
            id: sale.id,
            invoiceNumber: sale.invoiceNumber,
            customerId: sale.customerId,
            customerName: sale.customerName,
            customerPhone: sale.customerPhone,
            employeeId: sale.employeeId,
            employeeName: sale.employeeName,
            subtotalCents: Decimal.fromInt(sale.subtotalCents),
            taxCents: Decimal.fromInt(sale.taxCents),
            discountCents: Decimal.fromInt(sale.discountCents),
            totalCents: Decimal.fromInt(sale.totalCents),
            paidAmountCents: Decimal.fromInt(sale.paidAmountCents),
            currencyId: sale.currencyId,
            paymentMethod: sale.paymentMethod,
            status: sale.status,
            notes: sale.notes,
            saleDate: sale.saleDate,
            dueDate: sale.dueDate,
            taxInclusiveAtPost: sale.taxInclusiveAtPost,
            createdAt: sale.createdAt,
            updatedAt: sale.updatedAt,
          ),
        )
        .toList(growable: false);
    final remoteStats = page.stats;
    final stats = SaleDashboardStats(
      totalCount: remoteStats.totalCount,
      completedCount: remoteStats.completedCount,
      voidedCount: remoteStats.voidedCount,
      totalSalesCents: remoteStats.totalSalesCents,
      totalPaidCents: remoteStats.totalPaidCents,
      overdueCount: remoteStats.overdueCount,
      returnsCount: remoteStats.returnsCount,
      totalReturnsCents: remoteStats.totalReturnsCents,
      todaySalesCents: remoteStats.todaySalesCents,
      todayCount: remoteStats.todayCount,
    );
    _latestSales = sales;
    _latestStats = stats;
    _returnSaleIds = page.saleIdsWithReturns;
    _productSearchTerms = page.productSearchTerms;
    return SalesHubData(
      sales: sales,
      stats: stats,
      searchQuery: _searchQuery,
      statusFilter: _statusFilter,
      saleIdsWithReturns: page.saleIdsWithReturns,
      productSearchTerms: page.productSearchTerms,
      currencyCode: page.currencyCode,
      currencySymbol: page.currencySymbol,
      currencyDecimalDigits: page.currencyDecimalDigits,
      currencySymbolAfter: page.currencySymbolAfter,
      productMatchedSaleIds: SalesHubData.computeProductMatchedIds(
        sales,
        _searchQuery,
        page.productSearchTerms,
      ),
    );
  }

  void _emitCombined() {
    if (_latestSales != null && _latestStats != null) {
      final terms = _productSearchTerms ?? const {};
      // ignore: invalid_use_of_visible_for_testing_member
      emit(
        RealtimeSuccess(
          data: SalesHubData(
            sales: _latestSales!,
            stats: _latestStats!,
            searchQuery: _searchQuery,
            statusFilter: _statusFilter,
            saleIdsWithReturns: _returnSaleIds ?? const {},
            productSearchTerms: terms,
            productMatchedSaleIds: SalesHubData.computeProductMatchedIds(
              _latestSales!,
              _searchQuery,
              terms,
            ),
          ),
        ),
      );
    }
  }

  void _onSearch(
    SalesSearchRequested event,
    Emitter<RealtimeState<SalesHubData>> emit,
  ) {
    _searchQuery = event.query.isEmpty ? null : event.query;
    final data = currentData;
    if (data != null) {
      final terms = _productSearchTerms ?? const {};
      emit(
        RealtimeSuccess(
          data: SalesHubData(
            sales: data.sales,
            stats: data.stats,
            searchQuery: _searchQuery,
            statusFilter: _statusFilter,
            saleIdsWithReturns: data.saleIdsWithReturns,
            productSearchTerms: terms,
            currencyCode: data.currencyCode,
            currencySymbol: data.currencySymbol,
            currencyDecimalDigits: data.currencyDecimalDigits,
            currencySymbolAfter: data.currencySymbolAfter,
            productMatchedSaleIds: SalesHubData.computeProductMatchedIds(
              data.sales,
              _searchQuery,
              terms,
            ),
          ),
        ),
      );
    }
  }

  void _onStatusFilter(
    SalesStatusFilterChanged event,
    Emitter<RealtimeState<SalesHubData>> emit,
  ) {
    _statusFilter = event.status;
    final data = currentData;
    if (data != null) {
      final terms = _productSearchTerms ?? const {};
      emit(
        RealtimeSuccess(
          data: SalesHubData(
            sales: data.sales,
            stats: data.stats,
            searchQuery: _searchQuery,
            statusFilter: _statusFilter,
            saleIdsWithReturns: data.saleIdsWithReturns,
            productSearchTerms: terms,
            currencyCode: data.currencyCode,
            currencySymbol: data.currencySymbol,
            currencyDecimalDigits: data.currencyDecimalDigits,
            currencySymbolAfter: data.currencySymbolAfter,
            productMatchedSaleIds: SalesHubData.computeProductMatchedIds(
              data.sales,
              _searchQuery,
              terms,
            ),
          ),
        ),
      );
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
    _productTermsSub?.cancel();
    return super.close();
  }
}
