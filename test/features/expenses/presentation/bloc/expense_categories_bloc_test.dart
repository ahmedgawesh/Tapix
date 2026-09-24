import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tapix/core/bloc/realtime_bloc.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/features/expenses/domain/repositories/expense_repository.dart';
import 'package:tapix/features/expenses/presentation/bloc/expense_categories_bloc.dart';

class MockExpenseRepository extends Mock implements ExpenseRepository {}

void main() {
  late MockExpenseRepository mockRepository;

  final tCategory1 = ExpenseCategory(
    id: 1,
    name: 'Office',
    description: 'Office expenses',
    isActive: true,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );

  final tCategory2 = ExpenseCategory(
    id: 2,
    name: 'Utilities',
    description: 'Utility bills',
    isActive: true,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );

  final tCategories = [tCategory1, tCategory2];

  setUpAll(() {
    registerFallbackValue(tCategory1);
  });

  setUp(() {
    mockRepository = MockExpenseRepository();

    when(
      () => mockRepository.watchAllCategories(isActive: any(named: 'isActive')),
    ).thenAnswer((_) => const Stream.empty());
  });

  group('ExpenseCategoriesBloc', () {
    test('initial state is RealtimeLoading', () {
      final bloc = ExpenseCategoriesBloc(mockRepository);
      addTearDown(bloc.close);

      expect(bloc.state, isA<RealtimeLoading<List<ExpenseCategory>>>());
    });

    blocTest<ExpenseCategoriesBloc, RealtimeState<List<ExpenseCategory>>>(
      'emits categories when stream emits data',
      build: () {
        when(
          () => mockRepository.watchAllCategories(isActive: true),
        ).thenAnswer((_) => Stream.value(tCategories));
        return ExpenseCategoriesBloc(mockRepository);
      },
      expect: () => [
        isA<RealtimeSuccess<List<ExpenseCategory>>>().having(
          (s) => s.data.length,
          'count',
          2,
        ),
      ],
    );

    blocTest<ExpenseCategoriesBloc, RealtimeState<List<ExpenseCategory>>>(
      'creates category when ExpenseCategoryCreateRequested is added',
      build: () {
        when(
          () => mockRepository.watchAllCategories(isActive: true),
        ).thenAnswer((_) => Stream.value(tCategories));
        when(
          () => mockRepository.createCategory(
            name: any(named: 'name'),
            description: any(named: 'description'),
          ),
        ).thenAnswer((_) async => 3);
        return ExpenseCategoriesBloc(mockRepository);
      },
      act: (bloc) => bloc.add(
        const ExpenseCategoryCreateRequested(
          name: 'Travel',
          description: 'Travel expenses',
        ),
      ),
      verify: (_) {
        verify(
          () => mockRepository.createCategory(
            name: 'Travel',
            description: 'Travel expenses',
          ),
        ).called(1);
      },
    );

    blocTest<ExpenseCategoriesBloc, RealtimeState<List<ExpenseCategory>>>(
      'updates category when ExpenseCategoryUpdateRequested is added',
      build: () {
        when(
          () => mockRepository.watchAllCategories(isActive: true),
        ).thenAnswer((_) => Stream.value(tCategories));
        when(
          () => mockRepository.updateCategory(any()),
        ).thenAnswer((_) async => true);
        return ExpenseCategoriesBloc(mockRepository);
      },
      act: (bloc) => bloc.add(ExpenseCategoryUpdateRequested(tCategory1)),
      verify: (_) {
        verify(() => mockRepository.updateCategory(tCategory1)).called(1);
      },
    );

    blocTest<ExpenseCategoriesBloc, RealtimeState<List<ExpenseCategory>>>(
      'deletes category when ExpenseCategoryDeleteRequested is added',
      build: () {
        when(
          () => mockRepository.watchAllCategories(isActive: true),
        ).thenAnswer((_) => Stream.value(tCategories));
        when(
          () => mockRepository.deleteCategory(any()),
        ).thenAnswer((_) async => 1);
        return ExpenseCategoriesBloc(mockRepository);
      },
      act: (bloc) => bloc.add(const ExpenseCategoryDeleteRequested(1)),
      verify: (_) {
        verify(() => mockRepository.deleteCategory(1)).called(1);
      },
    );

    blocTest<ExpenseCategoriesBloc, RealtimeState<List<ExpenseCategory>>>(
      'toggles active status when ExpenseCategoryToggleActiveRequested is added',
      build: () {
        when(
          () => mockRepository.watchAllCategories(isActive: true),
        ).thenAnswer((_) => Stream.value(tCategories));
        when(
          () => mockRepository.updateCategory(any()),
        ).thenAnswer((_) async => true);
        return ExpenseCategoriesBloc(mockRepository);
      },
      act: (bloc) => bloc.add(ExpenseCategoryToggleActiveRequested(tCategory1)),
      verify: (_) {
        verify(
          () => mockRepository.updateCategory(
            any(
              that: isA<ExpenseCategory>().having(
                (c) => c.isActive,
                'isActive',
                false,
              ),
            ),
          ),
        ).called(1);
      },
    );
  });
}
