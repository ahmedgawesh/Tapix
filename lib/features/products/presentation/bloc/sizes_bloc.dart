import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../domain/entities/size_entity.dart';
import '../../domain/repositories/size_repository.dart';
import '../../data/models/size_model.dart';
import 'sizes_event.dart';

class SizesBloc extends RealtimeBloc<List<Size>, SizesEvent> {
  final SizeRepository _repository;
  String _currentSearchQuery = '';

  SizeRepository get repository => _repository;

  SizesBloc(this._repository) : super(const RealtimeLoading());

  @override
  Stream<List<Size>> get dataStream {
    if (_currentSearchQuery.isEmpty) {
      return _repository.watchAllSizes();
    } else {
      return _repository.watchSizesBySearch(_currentSearchQuery);
    }
  }

  @override
  void registerEventHandlers() {
    on<LoadSizes>(_onLoadSizes);
    on<SearchSizes>(_onSearchSizes);
    on<CreateSize>(_onCreateSize);
    on<UpdateSize>(_onUpdateSize);
    on<DeleteSize>(_onDeleteSize);
  }

  Future<void> _onLoadSizes(
    LoadSizes event,
    Emitter<RealtimeState<List<Size>>> emit,
  ) async {
    _currentSearchQuery = '';
    add(const RealtimeRefreshRequested());
  }

  Future<void> _onSearchSizes(
    SearchSizes event,
    Emitter<RealtimeState<List<Size>>> emit,
  ) async {
    _currentSearchQuery = event.query;
    add(const RealtimeRefreshRequested());
  }

  Future<void> _onCreateSize(
    CreateSize event,
    Emitter<RealtimeState<List<Size>>> emit,
  ) async {
    try {
      final size = SizeModel(
        id: 0,
        name: event.name,
        description: event.description,
        sortOrder: event.sortOrder,
        isActive: true,
      );

      await _repository.createSize(size);
    } catch (e) {
      emit(RealtimeError(error: 'Failed to create size: ${e.toString()}'));
    }
  }

  Future<void> _onUpdateSize(
    UpdateSize event,
    Emitter<RealtimeState<List<Size>>> emit,
  ) async {
    try {
      final success = await _repository.updateSize(event.size);
      if (!success) {
        emit(RealtimeError(error: 'Failed to update size'));
      }
    } catch (e) {
      emit(RealtimeError(error: 'Failed to update size: ${e.toString()}'));
    }
  }

  Future<void> _onDeleteSize(
    DeleteSize event,
    Emitter<RealtimeState<List<Size>>> emit,
  ) async {
    try {
      final hasProducts = await _repository.hasProducts(event.sizeId);
      if (hasProducts) {
        emit(RealtimeError(error: 'Cannot delete size with assigned products'));
        return;
      }

      await _repository.deleteSize(event.sizeId);
    } catch (e) {
      emit(RealtimeError(error: 'Failed to delete size: ${e.toString()}'));
    }
  }

  Future<Map<int, int>> getProductCounts(List<Size> sizes) async {
    final counts = <int, int>{};
    for (final size in sizes) {
      counts[size.id] = await _repository.getProductCountBySize(size.id);
    }
    return counts;
  }
}
