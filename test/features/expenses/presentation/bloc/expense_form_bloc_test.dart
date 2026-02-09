import 'package:bloc_test/bloc_test.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tapix/core/bloc/realtime_bloc.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/features/expenses/domain/repositories/expense_repository.dart';
import 'package:tapix/features/expenses/presentation/bloc/expense_form_bloc.dart';

class MockExpenseRepository extends Mock implements ExpenseRepository {}

void main() {
  late MockExpenseRepository mockRepository;

  final tExpense = Expense(
    id: 1,
    categoryId: 1,
    description: 'Office supplies',
    amountCents: Decimal.fromInt(5000),
    currencyId: 1,
    expenseDate: DateTime(2026, 1, 15),
    createdAt: DateTime(2026, 1, 15),
    updatedAt: DateTime(2026, 1, 15),
  );

  setUpAll(() {
    registerFallbackValue(Decimal.zero);
    registerFallbackValue(tExpense);
  });

  setUp(() {
    mockRepository = MockExpenseRepository();
  });

  group('ExpenseFormBloc', () {
    test('initial state is RealtimeSuccess with empty form data', () {
      final bloc = ExpenseFormBloc(mockRepository);
      addTearDown(bloc.close);

      expect(bloc.state, isA<RealtimeSuccess<ExpenseFormData>>());
      final state = bloc.state as RealtimeSuccess<ExpenseFormData>;
      expect(state.data.existingExpense, isNull);
      expect(state.data.isSubmitting, false);
      expect(state.data.isSubmitted, false);
    });

    blocTest<ExpenseFormBloc, RealtimeState<ExpenseFormData>>(
      'loads existing expense when ExpenseFormLoadRequested is added',
      build: () {
        when(() => mockRepository.getExpense(1))
            .thenAnswer((_) async => tExpense);
        return ExpenseFormBloc(mockRepository);
      },
      act: (bloc) => bloc.add(const ExpenseFormLoadRequested(expenseId: 1)),
      expect: () => [
        isA<RealtimeLoading<ExpenseFormData>>(),
        isA<RealtimeSuccess<ExpenseFormData>>()
            .having((s) => s.data.existingExpense, 'expense', isNotNull)
            .having((s) => s.data.existingExpense?.id, 'expense id', 1),
      ],
    );

    blocTest<ExpenseFormBloc, RealtimeState<ExpenseFormData>>(
      'emits error when expense not found',
      build: () {
        when(() => mockRepository.getExpense(999))
            .thenAnswer((_) async => null);
        return ExpenseFormBloc(mockRepository);
      },
      act: (bloc) => bloc.add(const ExpenseFormLoadRequested(expenseId: 999)),
      expect: () => [
        isA<RealtimeLoading<ExpenseFormData>>(),
        isA<RealtimeError<ExpenseFormData>>(),
      ],
    );

    blocTest<ExpenseFormBloc, RealtimeState<ExpenseFormData>>(
      'creates new expense when ExpenseFormSubmitRequested is added (no edit id)',
      build: () {
        when(() => mockRepository.createExpense(
              categoryId: any(named: 'categoryId'),
              description: any(named: 'description'),
              amountCents: any(named: 'amountCents'),
              currencyId: any(named: 'currencyId'),
              accountId: any(named: 'accountId'),
              expenseDate: any(named: 'expenseDate'),
              receiptPath: any(named: 'receiptPath'),
            )).thenAnswer((_) async => 1);
        return ExpenseFormBloc(mockRepository);
      },
      act: (bloc) => bloc.add(ExpenseFormSubmitRequested(
        categoryId: 1,
        description: 'New expense',
        amountCents: Decimal.fromInt(3000),
        currencyId: 1,
        expenseDate: DateTime(2026, 2, 1),
      )),
      expect: () => [
        // isSubmitting = true
        isA<RealtimeSuccess<ExpenseFormData>>()
            .having((s) => s.data.isSubmitting, 'isSubmitting', true),
        // isSubmitted = true
        isA<RealtimeSuccess<ExpenseFormData>>()
            .having((s) => s.data.isSubmitted, 'isSubmitted', true)
            .having((s) => s.data.isSubmitting, 'isSubmitting', false),
      ],
      verify: (_) {
        verify(() => mockRepository.createExpense(
              categoryId: 1,
              description: 'New expense',
              amountCents: Decimal.fromInt(3000),
              currencyId: 1,
              expenseDate: DateTime(2026, 2, 1),
            )).called(1);
      },
    );

    blocTest<ExpenseFormBloc, RealtimeState<ExpenseFormData>>(
      'emits error message when create fails',
      build: () {
        when(() => mockRepository.createExpense(
              categoryId: any(named: 'categoryId'),
              description: any(named: 'description'),
              amountCents: any(named: 'amountCents'),
              currencyId: any(named: 'currencyId'),
              accountId: any(named: 'accountId'),
              expenseDate: any(named: 'expenseDate'),
              receiptPath: any(named: 'receiptPath'),
            )).thenThrow(Exception('DB error'));
        return ExpenseFormBloc(mockRepository);
      },
      act: (bloc) => bloc.add(ExpenseFormSubmitRequested(
        categoryId: 1,
        description: 'Failing expense',
        amountCents: Decimal.fromInt(1000),
        currencyId: 1,
        expenseDate: DateTime(2026, 2, 1),
      )),
      expect: () => [
        isA<RealtimeSuccess<ExpenseFormData>>()
            .having((s) => s.data.isSubmitting, 'isSubmitting', true),
        isA<RealtimeSuccess<ExpenseFormData>>()
            .having((s) => s.data.isSubmitting, 'isSubmitting', false)
            .having((s) => s.data.errorMessage, 'errorMessage', isNotNull),
      ],
    );

    blocTest<ExpenseFormBloc, RealtimeState<ExpenseFormData>>(
      'emits empty form data when load requested with null id',
      build: () => ExpenseFormBloc(mockRepository),
      act: (bloc) => bloc.add(const ExpenseFormLoadRequested()),
      expect: () => [
        isA<RealtimeSuccess<ExpenseFormData>>()
            .having((s) => s.data.existingExpense, 'expense', isNull),
      ],
    );
  });
}
