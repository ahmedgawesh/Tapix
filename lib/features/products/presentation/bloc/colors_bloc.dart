import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../domain/entities/product_color_entity.dart';
import '../../domain/repositories/product_color_repository.dart';
import '../../data/models/product_color_model.dart';
import 'colors_event.dart';

class ColorsBloc extends RealtimeBloc<List<ProductColor>, ColorsEvent> {
  final ProductColorRepository _repository;
  String _currentSearchQuery = '';

  ProductColorRepository get repository => _repository;

  ColorsBloc(this._repository) : super(const RealtimeLoading()) {
    on<LoadColors>(_onLoadColors);
    on<SearchColors>(_onSearchColors);
    on<CreateColor>(_onCreateColor);
    on<UpdateColor>(_onUpdateColor);
    on<DeleteColor>(_onDeleteColor);
  }

  @override
  Stream<List<ProductColor>> get dataStream {
    if (_currentSearchQuery.isEmpty) {
      return _repository.watchAllColors();
    } else {
      return _repository.watchColorsBySearch(_currentSearchQuery);
    }
  }

  @override
  void registerEventHandlers() {}

  Future<void> _onLoadColors(
    LoadColors event,
    Emitter<RealtimeState<List<ProductColor>>> emit,
  ) async {
    _currentSearchQuery = '';
    add(const RealtimeRefreshRequested());
  }

  Future<void> _onSearchColors(
    SearchColors event,
    Emitter<RealtimeState<List<ProductColor>>> emit,
  ) async {
    _currentSearchQuery = event.query;
    add(const RealtimeRefreshRequested());
  }

  Future<void> _onCreateColor(
    CreateColor event,
    Emitter<RealtimeState<List<ProductColor>>> emit,
  ) async {
    try {
      final color = ProductColorModel(
        id: 0,
        name: event.name,
        hexCode: event.hexCode,
        isActive: true,
      );

      await _repository.createColor(color);
    } catch (e) {
      emit(RealtimeError(error: 'Failed to create color: ${e.toString()}'));
    }
  }

  Future<void> _onUpdateColor(
    UpdateColor event,
    Emitter<RealtimeState<List<ProductColor>>> emit,
  ) async {
    try {
      final success = await _repository.updateColor(event.color);
      if (!success) {
        emit(RealtimeError(error: 'Failed to update color'));
      }
    } catch (e) {
      emit(RealtimeError(error: 'Failed to update color: ${e.toString()}'));
    }
  }

  Future<void> _onDeleteColor(
    DeleteColor event,
    Emitter<RealtimeState<List<ProductColor>>> emit,
  ) async {
    try {
      final hasProducts = await _repository.hasProducts(event.colorId);
      if (hasProducts) {
        emit(
          RealtimeError(error: 'Cannot delete color with assigned products'),
        );
        return;
      }

      await _repository.deleteColor(event.colorId);
    } catch (e) {
      emit(RealtimeError(error: 'Failed to delete color: ${e.toString()}'));
    }
  }

  Future<Map<int, int>> getProductCounts(List<ProductColor> colors) async {
    final counts = <int, int>{};
    for (final color in colors) {
      counts[color.id] = await _repository.getProductCountByColor(color.id);
    }
    return counts;
  }
}
