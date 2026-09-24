import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart';
import '../../domain/repositories/expense_repository.dart';

/// Events for ExpenseCategoriesBloc
abstract class ExpenseCategoriesEvent extends RealtimeEvent {
  const ExpenseCategoriesEvent();
}

class ExpenseCategoryCreateRequested extends ExpenseCategoriesEvent {
  final String name;
  final String? description;
  const ExpenseCategoryCreateRequested({required this.name, this.description});
}

class ExpenseCategoryUpdateRequested extends ExpenseCategoriesEvent {
  final ExpenseCategory category;
  const ExpenseCategoryUpdateRequested(this.category);
}

class ExpenseCategoryDeleteRequested extends ExpenseCategoriesEvent {
  final int categoryId;
  const ExpenseCategoryDeleteRequested(this.categoryId);
}

class ExpenseCategoryToggleActiveRequested extends ExpenseCategoriesEvent {
  final ExpenseCategory category;
  const ExpenseCategoryToggleActiveRequested(this.category);
}

/// Bloc for managing expense categories with real-time updates
class ExpenseCategoriesBloc
    extends RealtimeBloc<List<ExpenseCategory>, ExpenseCategoriesEvent> {
  final ExpenseRepository _repository;

  ExpenseCategoriesBloc(this._repository) : super(const RealtimeLoading());

  @override
  Stream<List<ExpenseCategory>> get dataStream {
    return _repository.watchAllCategories(isActive: true);
  }

  @override
  void registerEventHandlers() {
    on<ExpenseCategoryCreateRequested>(_onCreateRequested);
    on<ExpenseCategoryUpdateRequested>(_onUpdateRequested);
    on<ExpenseCategoryDeleteRequested>(_onDeleteRequested);
    on<ExpenseCategoryToggleActiveRequested>(_onToggleActiveRequested);
  }

  Future<void> _onCreateRequested(
    ExpenseCategoryCreateRequested event,
    Emitter<RealtimeState<List<ExpenseCategory>>> emit,
  ) async {
    try {
      await _repository.createCategory(
        name: event.name,
        description: event.description,
      );
    } catch (e, st) {
      emit(
        RealtimeError<List<ExpenseCategory>>(
          error: e,
          stackTrace: st,
          previousData: currentData,
        ),
      );
    }
  }

  Future<void> _onUpdateRequested(
    ExpenseCategoryUpdateRequested event,
    Emitter<RealtimeState<List<ExpenseCategory>>> emit,
  ) async {
    try {
      await _repository.updateCategory(event.category);
    } catch (e, st) {
      emit(
        RealtimeError<List<ExpenseCategory>>(
          error: e,
          stackTrace: st,
          previousData: currentData,
        ),
      );
    }
  }

  Future<void> _onDeleteRequested(
    ExpenseCategoryDeleteRequested event,
    Emitter<RealtimeState<List<ExpenseCategory>>> emit,
  ) async {
    try {
      await _repository.deleteCategory(event.categoryId);
    } catch (e, st) {
      emit(
        RealtimeError<List<ExpenseCategory>>(
          error: e,
          stackTrace: st,
          previousData: currentData,
        ),
      );
    }
  }

  Future<void> _onToggleActiveRequested(
    ExpenseCategoryToggleActiveRequested event,
    Emitter<RealtimeState<List<ExpenseCategory>>> emit,
  ) async {
    try {
      final updated = event.category.copyWith(
        isActive: !event.category.isActive,
        updatedAt: DateTime.now(),
      );
      await _repository.updateCategory(updated);
    } catch (e, st) {
      emit(
        RealtimeError<List<ExpenseCategory>>(
          error: e,
          stackTrace: st,
          previousData: currentData,
        ),
      );
    }
  }
}
