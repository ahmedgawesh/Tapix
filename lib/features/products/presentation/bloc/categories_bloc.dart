import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../domain/entities/category_entity.dart';
import '../../domain/repositories/category_repository.dart';
import '../../data/models/category_model.dart';
import 'categories_event.dart';

class CategoriesBloc extends RealtimeBloc<List<Category>, RealtimeEvent> {
  final CategoryRepository _repository;
  String _currentSearchQuery = '';

  CategoriesBloc(this._repository) : super(const RealtimeLoading()) {
    on<LoadCategories>(_onLoadCategories);
    on<SearchCategories>(_onSearchCategories);
    on<CreateCategory>(_onCreateCategory);
    on<UpdateCategory>(_onUpdateCategory);
    on<DeleteCategory>(_onDeleteCategory);
  }

  @override
  Stream<List<Category>> get dataStream {
    if (_currentSearchQuery.isEmpty) {
      return _repository.watchAllCategories();
    } else {
      return _repository.watchCategoriesBySearch(_currentSearchQuery);
    }
  }

  @override
  void registerEventHandlers() {
  }

  Future<void> _onLoadCategories(
    LoadCategories event,
    Emitter<RealtimeState<List<Category>>> emit,
  ) async {
    _currentSearchQuery = '';
  }

  Future<void> _onSearchCategories(
    SearchCategories event,
    Emitter<RealtimeState<List<Category>>> emit,
  ) async {
    _currentSearchQuery = event.query;
  }

  Future<void> _onCreateCategory(
    CreateCategory event,
    Emitter<RealtimeState<List<Category>>> emit,
  ) async {
    try {
      if (event.parentId != null) {
        final hasCircular = await _repository.hasCircularReference(0, event.parentId);
        if (hasCircular) {
          emit(RealtimeError(error: 'Circular reference detected. Cannot set parent category.'));
          return;
        }
      }

      final category = CategoryModel(
        id: 0,
        name: event.name,
        description: event.description,
        parentId: event.parentId,
        isActive: true,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await _repository.createCategory(category);
    } catch (e) {
      emit(RealtimeError(error: 'Failed to create category: ${e.toString()}'));
    }
  }

  Future<void> _onUpdateCategory(
    UpdateCategory event,
    Emitter<RealtimeState<List<Category>>> emit,
  ) async {
    try {
      if (event.category.parentId != null) {
        final hasCircular = await _repository.hasCircularReference(
          event.category.id,
          event.category.parentId,
        );
        if (hasCircular) {
          emit(RealtimeError(error: 'Circular reference detected. Cannot set parent category.'));
          return;
        }
      }

      final success = await _repository.updateCategory(event.category);
      if (!success) {
        emit(RealtimeError(error: 'Failed to update category'));
      }
    } catch (e) {
      emit(RealtimeError(error: 'Failed to update category: ${e.toString()}'));
    }
  }

  Future<void> _onDeleteCategory(
    DeleteCategory event,
    Emitter<RealtimeState<List<Category>>> emit,
  ) async {
    try {
      final hasProducts = await _repository.hasProducts(event.categoryId);
      if (hasProducts) {
        emit(RealtimeError(error: 'Cannot delete category with assigned products'));
        return;
      }

      await _repository.deleteCategory(event.categoryId);
    } catch (e) {
      emit(RealtimeError(error: 'Failed to delete category: ${e.toString()}'));
    }
  }

  Future<Map<int, int>> getProductCounts(List<Category> categories) async {
    final counts = <int, int>{};
    for (final category in categories) {
      counts[category.id] = await _repository.getProductCountByCategory(category.id);
    }
    return counts;
  }
}
