import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart';
import '../../domain/repositories/expense_repository.dart';

/// Events for ExpensesBloc
abstract class ExpensesEvent extends RealtimeEvent {
  const ExpensesEvent();
}

class ExpensesSearchRequested extends ExpensesEvent {
  final String query;
  const ExpensesSearchRequested(this.query);
}

class ExpenseDeleteRequested extends ExpensesEvent {
  final int expenseId;
  const ExpenseDeleteRequested(this.expenseId);
}

class ExpensesFilterByCategoryRequested extends ExpensesEvent {
  final int? categoryId;
  const ExpensesFilterByCategoryRequested(this.categoryId);
}

class ExpensesFilterByDateRangeRequested extends ExpensesEvent {
  final DateTime? startDate;
  final DateTime? endDate;
  const ExpensesFilterByDateRangeRequested({this.startDate, this.endDate});
}

/// State data for expenses list
class ExpensesData {
  final List<Expense> expenses;
  final String? searchQuery;
  final int? filterCategoryId;
  final bool isSearching;

  const ExpensesData({
    required this.expenses,
    this.searchQuery,
    this.filterCategoryId,
    this.isSearching = false,
  });

  ExpensesData copyWith({
    List<Expense>? expenses,
    String? searchQuery,
    int? filterCategoryId,
    bool? isSearching,
  }) {
    return ExpensesData(
      expenses: expenses ?? this.expenses,
      searchQuery: searchQuery ?? this.searchQuery,
      filterCategoryId: filterCategoryId ?? this.filterCategoryId,
      isSearching: isSearching ?? this.isSearching,
    );
  }
}

/// Bloc for managing expenses list with real-time updates
class ExpensesBloc extends RealtimeBloc<ExpensesData, ExpensesEvent> {
  final ExpenseRepository _repository;
  String? _currentSearchQuery;
  int? _currentCategoryFilter;

  ExpensesBloc(this._repository) : super(const RealtimeLoading());

  @override
  Stream<ExpensesData> get dataStream {
    return _repository.watchAllExpenses().map(
      (expenses) => ExpensesData(
        expenses: _applyLocalFilters(expenses),
        searchQuery: _currentSearchQuery,
        filterCategoryId: _currentCategoryFilter,
        isSearching: _currentSearchQuery != null && _currentSearchQuery!.isNotEmpty,
      ),
    );
  }

  @override
  void registerEventHandlers() {
    on<ExpensesSearchRequested>(_onSearchRequested);
    on<ExpenseDeleteRequested>(_onDeleteRequested);
    on<ExpensesFilterByCategoryRequested>(_onFilterByCategory);
    on<ExpensesFilterByDateRangeRequested>(_onFilterByDateRange);
  }

  List<Expense> _applyLocalFilters(List<Expense> expenses) {
    var filtered = expenses;
    if (_currentCategoryFilter != null) {
      filtered = filtered.where((e) => e.categoryId == _currentCategoryFilter).toList();
    }
    return filtered;
  }

  Future<void> _onSearchRequested(
    ExpensesSearchRequested event,
    Emitter<RealtimeState<ExpensesData>> emit,
  ) async {
    _currentSearchQuery = event.query.isEmpty ? null : event.query;

    if (event.query.isEmpty) {
      refresh();
      return;
    }

    final previousData = currentData;
    emit(RealtimeLoading<ExpensesData>(previousData: previousData));

    try {
      final results = await _repository.searchExpenses(event.query);
      emit(RealtimeSuccess<ExpensesData>(
        data: ExpensesData(
          expenses: results,
          searchQuery: event.query,
          filterCategoryId: _currentCategoryFilter,
          isSearching: true,
        ),
      ));
    } catch (e, st) {
      emit(RealtimeError<ExpensesData>(error: e, stackTrace: st, previousData: previousData));
    }
  }

  Future<void> _onDeleteRequested(
    ExpenseDeleteRequested event,
    Emitter<RealtimeState<ExpensesData>> emit,
  ) async {
    try {
      await _repository.deleteExpense(event.expenseId);
    } catch (e, st) {
      emit(RealtimeError<ExpensesData>(error: e, stackTrace: st, previousData: currentData));
    }
  }

  Future<void> _onFilterByCategory(
    ExpensesFilterByCategoryRequested event,
    Emitter<RealtimeState<ExpensesData>> emit,
  ) async {
    _currentCategoryFilter = event.categoryId;
    refresh();
  }

  Future<void> _onFilterByDateRange(
    ExpensesFilterByDateRangeRequested event,
    Emitter<RealtimeState<ExpensesData>> emit,
  ) async {
    if (event.startDate == null || event.endDate == null) {
      refresh();
      return;
    }

    final previousData = currentData;
    emit(RealtimeLoading<ExpensesData>(previousData: previousData));

    try {
      // Use the stream-based date range filter - it will emit via dataStream
      // For now, just refresh to pick up the latest data
      refresh();
    } catch (e, st) {
      emit(RealtimeError<ExpensesData>(error: e, stackTrace: st, previousData: previousData));
    }
  }
}
