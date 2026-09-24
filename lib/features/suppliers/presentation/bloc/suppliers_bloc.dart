import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart';
import '../../domain/repositories/supplier_repository.dart';

enum SupplierStatusFilter { active, inactive, all }

abstract class SuppliersEvent extends RealtimeEvent {
  const SuppliersEvent();
}

class SuppliersSearchRequested extends SuppliersEvent {
  final String query;
  const SuppliersSearchRequested(this.query);
}

class SuppliersStatusFilterChanged extends SuppliersEvent {
  final SupplierStatusFilter filter;
  const SuppliersStatusFilterChanged(this.filter);
}

class SupplierDeleteRequested extends SuppliersEvent {
  final int supplierId;
  const SupplierDeleteRequested(this.supplierId);
}

class SupplierToggleActiveRequested extends SuppliersEvent {
  final Supplier supplier;
  const SupplierToggleActiveRequested(this.supplier);
}

class SuppliersData {
  /// Suppliers visible under the current status + search filters.
  final List<Supplier> suppliers;
  final String? searchQuery;
  final bool isSearching;
  final SupplierStatusFilter statusFilter;

  /// Counts across the full list, independent of search.
  final int activeCount;
  final int inactiveCount;
  final int totalCount;

  const SuppliersData({
    required this.suppliers,
    this.searchQuery,
    this.isSearching = false,
    this.statusFilter = SupplierStatusFilter.active,
    this.activeCount = 0,
    this.inactiveCount = 0,
    this.totalCount = 0,
  });

  SuppliersData copyWith({
    List<Supplier>? suppliers,
    String? searchQuery,
    bool? isSearching,
    SupplierStatusFilter? statusFilter,
    int? activeCount,
    int? inactiveCount,
    int? totalCount,
  }) {
    return SuppliersData(
      suppliers: suppliers ?? this.suppliers,
      searchQuery: searchQuery ?? this.searchQuery,
      isSearching: isSearching ?? this.isSearching,
      statusFilter: statusFilter ?? this.statusFilter,
      activeCount: activeCount ?? this.activeCount,
      inactiveCount: inactiveCount ?? this.inactiveCount,
      totalCount: totalCount ?? this.totalCount,
    );
  }
}

/// Watch the complete supplier list once and apply status + search together.
/// Live DB emissions must not overwrite a search with an unfiltered list.
class SuppliersBloc extends RealtimeBloc<SuppliersData, SuppliersEvent> {
  final SupplierRepository _repository;
  String? _currentSearchQuery;
  SupplierStatusFilter _statusFilter = SupplierStatusFilter.active;
  List<Supplier> _allSuppliers = const [];
  bool _hasLoaded = false;

  SuppliersBloc(this._repository) : super(const RealtimeLoading());

  @override
  Stream<SuppliersData> get dataStream => _repository.watchAllSuppliers().map(
    (suppliers) => SuppliersData(suppliers: suppliers),
  );

  @override
  RealtimeState<SuppliersData> mapDataToState(SuppliersData data) {
    _allSuppliers = List<Supplier>.unmodifiable(data.suppliers);
    _hasLoaded = true;
    return RealtimeSuccess<SuppliersData>(data: _filteredData());
  }

  SuppliersData _filteredData() {
    final query = (_currentSearchQuery ?? '').toLowerCase();
    final visible = _allSuppliers
        .where((supplier) {
          final matchesStatus = switch (_statusFilter) {
            SupplierStatusFilter.active => supplier.isActive,
            SupplierStatusFilter.inactive => !supplier.isActive,
            SupplierStatusFilter.all => true,
          };
          return matchesStatus &&
              (query.isEmpty ||
                  supplier.name.toLowerCase().contains(query) ||
                  (supplier.productCode ?? '').toLowerCase().contains(query) ||
                  (supplier.phone ?? '').toLowerCase().contains(query) ||
                  (supplier.email ?? '').toLowerCase().contains(query));
        })
        .toList(growable: false);
    final active = _allSuppliers.where((s) => s.isActive).length;
    return SuppliersData(
      suppliers: visible,
      searchQuery: _currentSearchQuery,
      isSearching: query.isNotEmpty,
      statusFilter: _statusFilter,
      activeCount: active,
      inactiveCount: _allSuppliers.length - active,
      totalCount: _allSuppliers.length,
    );
  }

  @override
  void registerEventHandlers() {
    on<SuppliersSearchRequested>(_onSearchRequested);
    on<SuppliersStatusFilterChanged>(_onStatusFilterChanged);
    on<SupplierDeleteRequested>(_onDeleteRequested);
    on<SupplierToggleActiveRequested>(_onToggleActiveRequested);
  }

  void _onSearchRequested(
    SuppliersSearchRequested event,
    Emitter<RealtimeState<SuppliersData>> emit,
  ) {
    final query = event.query.trim();
    _currentSearchQuery = query.isEmpty ? null : query;
    if (_hasLoaded) {
      emit(RealtimeSuccess<SuppliersData>(data: _filteredData()));
    }
  }

  void _onStatusFilterChanged(
    SuppliersStatusFilterChanged event,
    Emitter<RealtimeState<SuppliersData>> emit,
  ) {
    _statusFilter = event.filter;
    if (_hasLoaded) {
      emit(RealtimeSuccess<SuppliersData>(data: _filteredData()));
    }
  }

  Future<void> _onDeleteRequested(
    SupplierDeleteRequested event,
    Emitter<RealtimeState<SuppliersData>> emit,
  ) async {
    try {
      await _repository.deleteSupplier(event.supplierId);
    } catch (error, stackTrace) {
      emit(
        RealtimeError<SuppliersData>(
          error: error,
          stackTrace: stackTrace,
          previousData: currentData,
        ),
      );
    }
  }

  Future<void> _onToggleActiveRequested(
    SupplierToggleActiveRequested event,
    Emitter<RealtimeState<SuppliersData>> emit,
  ) async {
    try {
      await _repository.setSupplierActive(
        event.supplier.id,
        !event.supplier.isActive,
      );
    } catch (error, stackTrace) {
      emit(
        RealtimeError<SuppliersData>(
          error: error,
          stackTrace: stackTrace,
          previousData: currentData,
        ),
      );
    }
  }
}
