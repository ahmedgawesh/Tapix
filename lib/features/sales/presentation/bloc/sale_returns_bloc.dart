import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:decimal/decimal.dart';

import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/services/lan/lan_network_service.dart';
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
  final LanNetworkService? _lan;

  bool get _isRemoteClient =>
      _lan?.snapshot.mode == LanMode.client &&
      _lan?.hasRemoteUserSession == true;

  String _searchQuery = '';
  List<SaleReturnEntity> _allReturns = [];
  Map<String, List<String>> _productTerms = {};
  Set<String> _productMatchedReturnIds = {};
  StreamSubscription<Map<String, List<String>>>? _productTermsSub;

  static const int _maxResults = 20;

  SaleReturnsBloc(this._repository, {LanNetworkService? lan})
    : _lan = lan,
      super(const RealtimeLoading()) {
    if (!_isRemoteClient) {
      _productTermsSub = _repository.watchSaleReturnProductSearchTerms().listen(
        (terms) {
          _productTerms = terms;
          _refilter();
        },
      );
    }
  }

  @override
  void registerEventHandlers() {
    on<SaleReturnsSearchRequested>(_onSearch);
  }

  @override
  Stream<List<SaleReturnEntity>> get dataStream {
    if (!_isRemoteClient) return _repository.watchAllSaleReturns();
    return _watchRemoteReturns();
  }

  Stream<List<SaleReturnEntity>> _watchRemoteReturns() async* {
    while (true) {
      yield await _loadRemoteReturns();
      await Future<void>.delayed(const Duration(seconds: 3));
    }
  }

  Future<List<SaleReturnEntity>> _loadRemoteReturns() async {
    final page = await _lan!.fetchRemoteSaleReturns(limit: 200);
    return page.returns
        .map(
          (value) => SaleReturnEntity(
            id: value.id,
            saleId: value.saleId,
            saleInvoiceNumber: value.saleInvoiceNumber,
            customerName: value.customerName,
            customerPhone: value.customerPhone,
            customerId: value.customerId,
            returnNumber: value.returnNumber,
            subtotalCents: Decimal.fromInt(value.subtotalCents),
            discountCents: Decimal.fromInt(value.discountCents),
            taxCents: Decimal.fromInt(value.taxCents),
            totalCents: Decimal.fromInt(value.totalCents),
            currencyId: value.currencyId,
            status: value.status,
            dispositionType: value.dispositionType,
            refundMethod: value.refundMethod,
            reason: value.reason,
            returnDate: value.returnDate,
            createdAt: value.createdAt,
            isAdjustment: value.isAdjustment,
            unifiedId: value.unifiedId,
          ),
        )
        .toList(growable: false);
  }

  @override
  RealtimeState<List<SaleReturnEntity>> mapDataToState(
    List<SaleReturnEntity> data,
  ) {
    _allReturns = data;
    return RealtimeSuccess<List<SaleReturnEntity>>(data: _applyFilter(data));
  }

  void _onSearch(
    SaleReturnsSearchRequested event,
    Emitter<RealtimeState<List<SaleReturnEntity>>> emit,
  ) {
    _searchQuery = event.query;
    emit(RealtimeSuccess(data: _applyFilter(_allReturns)));
  }

  void _refilter() {
    if (_allReturns.isNotEmpty) {
      // ignore: invalid_use_of_visible_for_testing_member
      emit(RealtimeSuccess(data: _applyFilter(_allReturns)));
    }
  }

  List<SaleReturnEntity> _applyFilter(List<SaleReturnEntity> returns) {
    if (_searchQuery.isEmpty) {
      _productMatchedReturnIds = {};
      return returns.take(_maxResults).toList();
    }

    final q = _searchQuery.toLowerCase();
    final matched = <SaleReturnEntity>[];
    final productMatched = <String>{};

    for (final r in returns) {
      // 1. Return number
      if (r.returnNumber.toLowerCase().contains(q)) {
        matched.add(r);
        continue;
      }

      // 2. Invoice number (for linked returns)
      if (r.saleInvoiceNumber?.toLowerCase().contains(q) ?? false) {
        matched.add(r);
        continue;
      }

      // 3. Customer name
      if (r.customerName?.toLowerCase().contains(q) ?? false) {
        matched.add(r);
        continue;
      }

      // 4. Customer phone
      if (r.customerPhone?.toLowerCase().contains(q) ?? false) {
        matched.add(r);
        continue;
      }

      // 5. Product name / barcode / SKU
      final terms = _productTerms[r.unifiedId];
      if (terms != null && terms.any((t) => t.toLowerCase().contains(q))) {
        matched.add(r);
        productMatched.add(r.unifiedId);
        continue;
      }

      if (matched.length >= _maxResults) break;
    }

    _productMatchedReturnIds = productMatched;
    return matched.take(_maxResults).toList();
  }

  /// Returns true if this return was matched via product search
  bool isProductMatched(String unifiedId) =>
      _productMatchedReturnIds.contains(unifiedId);

  @override
  Future<void> close() {
    _productTermsSub?.cancel();
    return super.close();
  }
}
