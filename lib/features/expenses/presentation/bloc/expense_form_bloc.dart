import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart';
import '../../domain/repositories/expense_repository.dart';

/// Events for ExpenseFormBloc
abstract class ExpenseFormEvent extends RealtimeEvent {
  const ExpenseFormEvent();
}

class ExpenseFormLoadRequested extends ExpenseFormEvent {
  final int? expenseId;
  const ExpenseFormLoadRequested({this.expenseId});
}

class ExpenseFormSubmitRequested extends ExpenseFormEvent {
  final int categoryId;
  final String description;
  final Decimal amountCents;
  final int currencyId;
  final int? accountId;
  final DateTime expenseDate;
  final String? receiptPath;

  const ExpenseFormSubmitRequested({
    required this.categoryId,
    required this.description,
    required this.amountCents,
    required this.currencyId,
    this.accountId,
    required this.expenseDate,
    this.receiptPath,
  });
}

/// State data for expense form
class ExpenseFormData {
  final Expense? existingExpense;
  final bool isSubmitting;
  final bool isSubmitted;
  final String? errorMessage;

  const ExpenseFormData({
    this.existingExpense,
    this.isSubmitting = false,
    this.isSubmitted = false,
    this.errorMessage,
  });

  ExpenseFormData copyWith({
    Expense? existingExpense,
    bool? isSubmitting,
    bool? isSubmitted,
    String? errorMessage,
  }) {
    return ExpenseFormData(
      existingExpense: existingExpense ?? this.existingExpense,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      isSubmitted: isSubmitted ?? this.isSubmitted,
      errorMessage: errorMessage,
    );
  }
}

/// Bloc for managing expense form (create/edit)
class ExpenseFormBloc extends RealtimeBloc<ExpenseFormData, ExpenseFormEvent> {
  final ExpenseRepository _repository;
  int? _editingExpenseId;

  ExpenseFormBloc(this._repository)
    : super(RealtimeSuccess<ExpenseFormData>(data: const ExpenseFormData()));

  @override
  Stream<ExpenseFormData> get dataStream => const Stream.empty();

  @override
  void registerEventHandlers() {
    on<ExpenseFormLoadRequested>(_onLoadRequested);
    on<ExpenseFormSubmitRequested>(_onSubmitRequested);
  }

  Future<void> _onLoadRequested(
    ExpenseFormLoadRequested event,
    Emitter<RealtimeState<ExpenseFormData>> emit,
  ) async {
    if (event.expenseId == null) {
      emit(RealtimeSuccess<ExpenseFormData>(data: const ExpenseFormData()));
      return;
    }

    _editingExpenseId = event.expenseId;
    emit(const RealtimeLoading<ExpenseFormData>());

    try {
      final expense = await _repository.getExpense(event.expenseId!);
      if (expense != null) {
        emit(
          RealtimeSuccess<ExpenseFormData>(
            data: ExpenseFormData(existingExpense: expense),
          ),
        );
      } else {
        emit(RealtimeError<ExpenseFormData>(error: 'Expense not found'));
      }
    } catch (e, st) {
      emit(RealtimeError<ExpenseFormData>(error: e, stackTrace: st));
    }
  }

  Future<void> _onSubmitRequested(
    ExpenseFormSubmitRequested event,
    Emitter<RealtimeState<ExpenseFormData>> emit,
  ) async {
    final previousData = currentData;
    emit(
      RealtimeSuccess<ExpenseFormData>(
        data: (previousData ?? const ExpenseFormData()).copyWith(
          isSubmitting: true,
        ),
      ),
    );

    try {
      if (_editingExpenseId != null) {
        final existing = await _repository.getExpense(_editingExpenseId!);
        if (existing != null) {
          final updated = existing.copyWith(
            categoryId: event.categoryId,
            description: event.description,
            amountCents: event.amountCents,
            currencyId: event.currencyId,
            accountId: Value(event.accountId),
            expenseDate: event.expenseDate,
            receiptPath: Value(event.receiptPath),
            updatedAt: DateTime.now(),
          );
          await _repository.updateExpense(updated);
        }
      } else {
        await _repository.createExpense(
          categoryId: event.categoryId,
          description: event.description,
          amountCents: event.amountCents,
          currencyId: event.currencyId,
          accountId: event.accountId,
          expenseDate: event.expenseDate,
          receiptPath: event.receiptPath,
        );
      }

      emit(
        RealtimeSuccess<ExpenseFormData>(
          data: (previousData ?? const ExpenseFormData()).copyWith(
            isSubmitting: false,
            isSubmitted: true,
          ),
        ),
      );
    } catch (e) {
      emit(
        RealtimeSuccess<ExpenseFormData>(
          data: (previousData ?? const ExpenseFormData()).copyWith(
            isSubmitting: false,
            errorMessage: e.toString(),
          ),
        ),
      );
    }
  }
}
