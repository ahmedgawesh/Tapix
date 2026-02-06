import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart';
import '../../domain/repositories/supplier_repository.dart';

/// Events for SuppliersBloc
abstract class SuppliersEvent extends RealtimeEvent {
  const SuppliersEvent();
}

class SuppliersSearchRequested extends SuppliersEvent {
  final String query;
  const SuppliersSearchRequested(this.query);
}

class SupplierDeleteRequested extends SuppliersEvent {
  final int supplierId;
  const SupplierDeleteRequested(this.supplierId);
}

class SupplierToggleActiveRequested extends SuppliersEvent {
  final Supplier supplier;
  const SupplierToggleActiveRequested(this.supplier);
}

/// State data for suppliers list
class SuppliersData {
  final List<Supplier> suppliers;
  final String? searchQuery;
  final bool isSearching;

  const SuppliersData({
    required this.suppliers,
    this.searchQuery,
    this.isSearching = false,
  });

  SuppliersData copyWith({
    List<Supplier>? suppliers,
    String? searchQuery,
    bool? isSearching,
  }) {
    return SuppliersData(
      suppliers: suppliers ?? this.suppliers,
      searchQuery: searchQuery ?? this.searchQuery,
      isSearching: isSearching ?? this.isSearching,
    );
  }
}

/// Bloc for managing suppliers list with real-time updates
class SuppliersBloc extends RealtimeBloc<SuppliersData, SuppliersEvent> {
  final SupplierRepository _repository;
  String? _currentSearchQuery;

  SuppliersBloc(this._repository) : super(const RealtimeLoading());

  @override
  Stream<SuppliersData> get dataStream {
    return _repository.watchAllSuppliers(isActive: true).map(
      (suppliers) => SuppliersData(
        suppliers: suppliers,
        searchQuery: _currentSearchQuery,
        isSearching: _currentSearchQuery != null && _currentSearchQuery!.isNotEmpty,
      ),
    );
  }

  @override
  void registerEventHandlers() {
    on<SuppliersSearchRequested>(_onSearchRequested);
    on<SupplierDeleteRequested>(_onDeleteRequested);
    on<SupplierToggleActiveRequested>(_onToggleActiveRequested);
  }

  Future<void> _onSearchRequested(
    SuppliersSearchRequested event,
    Emitter<RealtimeState<SuppliersData>> emit,
  ) async {
    _currentSearchQuery = event.query.isEmpty ? null : event.query;

    if (event.query.isEmpty) {
      refresh();
      return;
    }

    final previousData = currentData;
    emit(RealtimeLoading<SuppliersData>(previousData: previousData));

    try {
      final results = await _repository.searchSuppliers(event.query, isActive: true);
      emit(RealtimeSuccess<SuppliersData>(
        data: SuppliersData(
          suppliers: results,
          searchQuery: event.query,
          isSearching: true,
        ),
      ));
    } catch (e, st) {
      emit(RealtimeError<SuppliersData>(error: e, stackTrace: st, previousData: previousData));
    }
  }

  Future<void> _onDeleteRequested(
    SupplierDeleteRequested event,
    Emitter<RealtimeState<SuppliersData>> emit,
  ) async {
    try {
      await _repository.deleteSupplier(event.supplierId);
    } catch (e, st) {
      emit(RealtimeError<SuppliersData>(error: e, stackTrace: st, previousData: currentData));
    }
  }

  Future<void> _onToggleActiveRequested(
    SupplierToggleActiveRequested event,
    Emitter<RealtimeState<SuppliersData>> emit,
  ) async {
    try {
      final updatedSupplier = event.supplier.copyWith(
        isActive: !event.supplier.isActive,
        updatedAt: DateTime.now(),
      );
      await _repository.updateSupplier(updatedSupplier);
    } catch (e, st) {
      emit(RealtimeError<SuppliersData>(error: e, stackTrace: st, previousData: currentData));
    }
  }
}
