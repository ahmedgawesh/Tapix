import 'package:bloc_test/bloc_test.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tapix/core/bloc/realtime_bloc.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/features/expenses/domain/repositories/expense_repository.dart';
import 'package:tapix/features/expenses/presentation/bloc/expenses_bloc.dart';

class MockExpenseRepository extends Mock implements ExpenseRepository {}

void main() {
  late MockExpenseRepository mockRepository;

  final tExpense1 = Expense(
    id: 1,
    categoryId: 1,
    description: 'Office supplies',
    amountCents: Decimal.fromInt(5000),
    currencyId: 1,
    expenseDate: DateTime(2026, 1, 15),
    createdAt: DateTime(2026, 1, 15),
    updatedAt: DateTime(2026, 1, 15),
  );

  final tExpense2 = Expense(
    id: 2,
    categoryId: 2,
    description: 'Internet bill',
    amountCents: Decimal.fromInt(15000),
    currencyId: 1,
    expenseDate: DateTime(2026, 1, 20),
    createdAt: DateTime(2026, 1, 20),
    updatedAt: DateTime(2026, 1, 20),
  );

  final tExpenses = [tExpense1, tExpense2];

  setUp(() {
    mockRepository = MockExpenseRepository();

    when(() => mockRepository.watchAllExpenses())
        .thenAnswer((_) => const Stream.empty());
  });

  group('ExpensesBloc', () {
    test('initial state is RealtimeLoading', () {
      final bloc = ExpensesBloc(mockRepository);
      addTearDown(bloc.close);

      expect(bloc.state, isA<RealtimeLoading<ExpensesData>>());
    });

    blocTest<ExpensesBloc, RealtimeState<ExpensesData>>(
      'emits expenses when stream emits data',
      build: () {
        when(() => mockRepository.watchAllExpenses())
            .thenAnswer((_) => Stream.value(tExpenses));
        return ExpensesBloc(mockRepository);
      },
      expect: () => [
        isA<RealtimeSuccess<ExpensesData>>()
            .having((s) => s.data.expenses.length, 'expenses count', 2),
      ],
    );

    blocTest<ExpensesBloc, RealtimeState<ExpensesData>>(
      'searches expenses when ExpensesSearchRequested is added',
      build: () {
        when(() => mockRepository.watchAllExpenses())
            .thenAnswer((_) => const Stream.empty());
        when(() => mockRepository.searchExpenses(any()))
            .thenAnswer((_) async => [tExpense1]);
        return ExpensesBloc(mockRepository);
      },
      act: (bloc) => bloc.add(const ExpensesSearchRequested('Office')),
      expect: () => [
        isA<RealtimeLoading<ExpensesData>>(),
        isA<RealtimeSuccess<ExpensesData>>()
            .having((s) => s.data.expenses.length, 'results count', 1)
            .having((s) => s.data.isSearching, 'isSearching', true),
      ],
      verify: (_) {
        verify(() => mockRepository.searchExpenses('Office')).called(1);
      },
    );

    blocTest<ExpensesBloc, RealtimeState<ExpensesData>>(
      'deletes expense when ExpenseDeleteRequested is added',
      build: () {
        when(() => mockRepository.watchAllExpenses())
            .thenAnswer((_) => Stream.value(tExpenses));
        when(() => mockRepository.deleteExpense(any()))
            .thenAnswer((_) async => 1);
        return ExpensesBloc(mockRepository);
      },
      act: (bloc) => bloc.add(const ExpenseDeleteRequested(1)),
      verify: (_) {
        verify(() => mockRepository.deleteExpense(1)).called(1);
      },
    );

    blocTest<ExpensesBloc, RealtimeState<ExpensesData>>(
      'filters by category when ExpensesFilterByCategoryRequested is added',
      build: () {
        when(() => mockRepository.watchAllExpenses())
            .thenAnswer((_) => Stream.value(tExpenses));
        return ExpensesBloc(mockRepository);
      },
      act: (bloc) => bloc.add(const ExpensesFilterByCategoryRequested(1)),
      expect: () => [
        // Initial stream data
        isA<RealtimeSuccess<ExpensesData>>(),
        // After filter + refresh
        isA<RealtimeLoading<ExpensesData>>(),
        isA<RealtimeSuccess<ExpensesData>>()
            .having((s) => s.data.filterCategoryId, 'filterCategoryId', 1),
      ],
    );

    blocTest<ExpensesBloc, RealtimeState<ExpensesData>>(
      'clears search when empty query is provided',
      build: () {
        when(() => mockRepository.watchAllExpenses())
            .thenAnswer((_) => Stream.value(tExpenses));
        return ExpensesBloc(mockRepository);
      },
      act: (bloc) => bloc.add(const ExpensesSearchRequested('')),
      expect: () => [
        // Initial stream data
        isA<RealtimeSuccess<ExpensesData>>(),
        // After refresh from empty search
        isA<RealtimeLoading<ExpensesData>>(),
        isA<RealtimeSuccess<ExpensesData>>()
            .having((s) => s.data.isSearching, 'isSearching', false),
      ],
    );
  });
}
