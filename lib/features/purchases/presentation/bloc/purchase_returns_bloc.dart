import 'dart:async';
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

  String _searchQuery = '';
  List<PurchaseReturnEntity> _allReturns = [];
  Map<String, List<String>> _productTerms = {};
  Set<String> _productMatchedReturnIds = {};
  StreamSubscription<Map<String, List<String>>>? _productTermsSub;

  static const int _maxResults = 20;

  PurchaseReturnsBloc(this._repository) : super(const RealtimeLoading()) {
    _productTermsSub = _repository
        .watchPurchaseReturnProductSearchTerms()
        .listen((terms) {
          _productTerms = terms;
          _refilter();
        });
  }

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
    List<PurchaseReturnEntity> data,
  ) {
    _allReturns = data;
    return RealtimeSuccess<List<PurchaseReturnEntity>>(
      data: _applyFilter(data),
    );
  }

  void _onSearch(
    PurchaseReturnsSearchRequested event,
    Emitter<RealtimeState<List<PurchaseReturnEntity>>> emit,
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

  List<PurchaseReturnEntity> _applyFilter(List<PurchaseReturnEntity> returns) {
    if (_searchQuery.isEmpty) {
      _productMatchedReturnIds = {};
      return returns.take(_maxResults).toList();
    }

    final q = _searchQuery.toLowerCase();
    final matched = <PurchaseReturnEntity>[];
    final productMatched = <String>{};

    for (final r in returns) {
      // 1. Return number
      if (r.returnNumber.toLowerCase().contains(q)) {
        matched.add(r);
        continue;
      }

      // 2. Supplier name
      if (r.supplierName?.toLowerCase().contains(q) ?? false) {
        matched.add(r);
        continue;
      }

      // 3. Supplier phone
      if (r.supplierPhone?.toLowerCase().contains(q) ?? false) {
        matched.add(r);
        continue;
      }

      // 4. Product name / barcode / SKU
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
