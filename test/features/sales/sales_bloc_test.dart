import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tapix/core/bloc/realtime_bloc.dart';
import 'package:tapix/features/sales/domain/entities/sale_entity.dart';
import 'package:tapix/features/sales/domain/repositories/sale_repository.dart';
import 'package:tapix/features/sales/presentation/bloc/sales_bloc.dart';

class MockSaleRepository extends Mock implements SaleRepository {}

void main() {
  late MockSaleRepository mockRepository;
  late StreamController<List<SaleEntity>> salesStreamController;
  late StreamController<SaleDashboardStats> statsStreamController;
  late StreamController<Set<int>> returnIdsStreamController;

  final testSales = [
    SaleEntity(
      id: 1,
      invoiceNumber: 'INV-202601-0001',
      customerId: 1,
      customerName: 'Test Customer',
      subtotalCents: Decimal.fromInt(10000),
      taxCents: Decimal.fromInt(1500),
      discountCents: Decimal.zero,
      totalCents: Decimal.fromInt(11500),
      paidAmountCents: Decimal.fromInt(11500),
      currencyId: 1,
      paymentMethod: 'cash',
      status: 'completed',
      saleDate: DateTime(2026, 1, 15),
      createdAt: DateTime(2026, 1, 15),
      updatedAt: DateTime(2026, 1, 15),
    ),
    SaleEntity(
      id: 2,
      invoiceNumber: 'INV-202601-0002',
      customerId: 2,
      customerName: 'Another Customer',
      subtotalCents: Decimal.fromInt(20000),
      taxCents: Decimal.fromInt(3000),
      discountCents: Decimal.fromInt(1000),
      totalCents: Decimal.fromInt(22000),
      paidAmountCents: Decimal.fromInt(10000),
      currencyId: 1,
      paymentMethod: 'credit',
      status: 'pending',
      saleDate: DateTime(2026, 1, 16),
      createdAt: DateTime(2026, 1, 16),
      updatedAt: DateTime(2026, 1, 16),
    ),
    SaleEntity(
      id: 3,
      invoiceNumber: 'INV-202601-0003',
      subtotalCents: Decimal.fromInt(5000),
      taxCents: Decimal.zero,
      discountCents: Decimal.zero,
      totalCents: Decimal.fromInt(5000),
      paidAmountCents: Decimal.fromInt(5000),
      currencyId: 1,
      paymentMethod: 'cash',
      status: 'voided',
      saleDate: DateTime(2026, 1, 17),
      createdAt: DateTime(2026, 1, 17),
      updatedAt: DateTime(2026, 1, 17),
    ),
  ];

  const testStats = SaleDashboardStats(
    totalCount: 3,
    completedCount: 1,
    voidedCount: 1,
    totalSalesCents: 38500,
    returnsCount: 0,
    totalReturnsCents: 0,
    todaySalesCents: 0,
    todayCount: 0,
  );

  setUp(() {
    mockRepository = MockSaleRepository();
    salesStreamController = StreamController<List<SaleEntity>>.broadcast();
    statsStreamController = StreamController<SaleDashboardStats>.broadcast();
    returnIdsStreamController = StreamController<Set<int>>.broadcast();

    when(() => mockRepository.watchAllSales())
        .thenAnswer((_) => salesStreamController.stream);
    when(() => mockRepository.watchDashboardStats())
        .thenAnswer((_) => statsStreamController.stream);
    when(() => mockRepository.watchSaleIdsWithReturns())
        .thenAnswer((_) => returnIdsStreamController.stream);
    when(() => mockRepository.watchSaleProductSearchTerms())
        .thenAnswer((_) => Stream<Map<int, List<String>>>.value(const {}));
  });

  tearDown(() {
    salesStreamController.close();
    statsStreamController.close();
    returnIdsStreamController.close();
  });

  group('SalesBloc', () {
    test('initial state is RealtimeLoading', () {
      final bloc = SalesBloc(mockRepository);
      expect(bloc.state, isA<RealtimeLoading<SalesHubData>>());
      bloc.close();
    });

    blocTest<SalesBloc, RealtimeState<SalesHubData>>(
      'emits RealtimeSuccess when sales stream emits data',
      build: () => SalesBloc(mockRepository),
      act: (bloc) {
        statsStreamController.add(testStats);
        salesStreamController.add(testSales);
        returnIdsStreamController.add({1});
      },
      wait: const Duration(milliseconds: 100),
      verify: (bloc) {
        // Verify final state has correct data
        final state = bloc.state;
        expect(state, isA<RealtimeSuccess<SalesHubData>>());
        final successState = state as RealtimeSuccess<SalesHubData>;
        expect(successState.data.sales.length, equals(3));
        expect(successState.data.stats.totalCount, equals(3));
      },
    );

    blocTest<SalesBloc, RealtimeState<SalesHubData>>(
      'filters sales by search query',
      build: () => SalesBloc(mockRepository),
      seed: () => RealtimeSuccess(
        data: SalesHubData(
          sales: testSales,
          stats: testStats,
          saleIdsWithReturns: const {},
        ),
      ),
      act: (bloc) => bloc.add(const SalesSearchRequested('Test Customer')),
      expect: () => [
        isA<RealtimeSuccess<SalesHubData>>()
            .having((s) => s.data.searchQuery, 'search query', 'Test Customer')
            .having((s) => s.data.filteredSales.length, 'filtered count', 1),
      ],
    );

    blocTest<SalesBloc, RealtimeState<SalesHubData>>(
      'filters sales by status',
      build: () => SalesBloc(mockRepository),
      seed: () => RealtimeSuccess(
        data: SalesHubData(
          sales: testSales,
          stats: testStats,
          saleIdsWithReturns: const {},
        ),
      ),
      act: (bloc) => bloc.add(const SalesStatusFilterChanged('completed')),
      expect: () => [
        isA<RealtimeSuccess<SalesHubData>>()
            .having((s) => s.data.statusFilter, 'status filter', 'completed')
            .having((s) => s.data.filteredSales.length, 'filtered count', 1),
      ],
    );

    blocTest<SalesBloc, RealtimeState<SalesHubData>>(
      'clears search query when empty string provided',
      build: () => SalesBloc(mockRepository),
      seed: () => RealtimeSuccess(
        data: SalesHubData(
          sales: testSales,
          stats: testStats,
          searchQuery: 'Test',
          saleIdsWithReturns: const {},
        ),
      ),
      act: (bloc) => bloc.add(const SalesSearchRequested('')),
      expect: () => [
        isA<RealtimeSuccess<SalesHubData>>()
            .having((s) => s.data.searchQuery, 'search query', isNull),
      ],
    );

    blocTest<SalesBloc, RealtimeState<SalesHubData>>(
      'voids sale successfully',
      build: () {
        when(() => mockRepository.voidSale(any())).thenAnswer((_) async {});
        return SalesBloc(mockRepository);
      },
      seed: () => RealtimeSuccess(
        data: SalesHubData(
          sales: testSales,
          stats: testStats,
          saleIdsWithReturns: const {},
        ),
      ),
      act: (bloc) => bloc.add(const SaleVoidRequested(1)),
      verify: (_) {
        verify(() => mockRepository.voidSale(1)).called(1);
      },
    );

    blocTest<SalesBloc, RealtimeState<SalesHubData>>(
      'emits error state when void sale fails',
      build: () {
        when(() => mockRepository.voidSale(any()))
            .thenThrow(Exception('Void failed'));
        return SalesBloc(mockRepository);
      },
      seed: () => RealtimeSuccess(
        data: SalesHubData(
          sales: testSales,
          stats: testStats,
          saleIdsWithReturns: const {},
        ),
      ),
      act: (bloc) => bloc.add(const SaleVoidRequested(1)),
      expect: () => [
        isA<RealtimeError<SalesHubData>>()
            .having((s) => s.previousData, 'has previous data', isNotNull),
      ],
    );

    blocTest<SalesBloc, RealtimeState<SalesHubData>>(
      'deletes sale successfully',
      build: () {
        when(() => mockRepository.deleteSale(any())).thenAnswer((_) async {});
        return SalesBloc(mockRepository);
      },
      seed: () => RealtimeSuccess(
        data: SalesHubData(
          sales: testSales,
          stats: testStats,
          saleIdsWithReturns: const {},
        ),
      ),
      act: (bloc) => bloc.add(const SaleDeleteRequested(2)),
      verify: (_) {
        verify(() => mockRepository.deleteSale(2)).called(1);
      },
    );

    blocTest<SalesBloc, RealtimeState<SalesHubData>>(
      'emits error state when delete sale fails',
      build: () {
        when(() => mockRepository.deleteSale(any()))
            .thenThrow(Exception('Delete failed'));
        return SalesBloc(mockRepository);
      },
      seed: () => RealtimeSuccess(
        data: SalesHubData(
          sales: testSales,
          stats: testStats,
          saleIdsWithReturns: const {},
        ),
      ),
      act: (bloc) => bloc.add(const SaleDeleteRequested(2)),
      expect: () => [
        isA<RealtimeError<SalesHubData>>()
            .having((s) => s.previousData, 'has previous data', isNotNull),
      ],
    );
  });

  group('SalesHubData', () {
    test('filteredSales returns all sales when no filters applied', () {
      final data = SalesHubData(
        sales: testSales,
        stats: testStats,
        saleIdsWithReturns: const {},
      );
      expect(data.filteredSales.length, equals(3));
    });

    test('filteredSales filters by status', () {
      final data = SalesHubData(
        sales: testSales,
        stats: testStats,
        statusFilter: 'completed',
        saleIdsWithReturns: const {},
      );
      expect(data.filteredSales.length, equals(1));
      expect(data.filteredSales.first.status, equals('completed'));
    });

    test('filteredSales filters by search query on invoice number', () {
      final data = SalesHubData(
        sales: testSales,
        stats: testStats,
        searchQuery: '0002',
        saleIdsWithReturns: const {},
      );
      expect(data.filteredSales.length, equals(1));
      expect(data.filteredSales.first.invoiceNumber, contains('0002'));
    });

    test('filteredSales filters by search query on customer name', () {
      final data = SalesHubData(
        sales: testSales,
        stats: testStats,
        searchQuery: 'Another',
        saleIdsWithReturns: const {},
      );
      expect(data.filteredSales.length, equals(1));
      expect(data.filteredSales.first.customerName, contains('Another'));
    });

    test('filteredSales combines status and search filters', () {
      final data = SalesHubData(
        sales: testSales,
        stats: testStats,
        statusFilter: 'pending',
        searchQuery: 'Another',
        saleIdsWithReturns: const {},
      );
      expect(data.filteredSales.length, equals(1));
      expect(data.filteredSales.first.id, equals(2));
    });
  });

  group('SaleEntity', () {
    test('isCompleted returns true for completed status', () {
      expect(testSales[0].isCompleted, isTrue);
      expect(testSales[1].isCompleted, isFalse);
    });

    test('isVoided returns true for voided status', () {
      expect(testSales[2].isVoided, isTrue);
      expect(testSales[0].isVoided, isFalse);
    });

    test('isPending returns true for pending status', () {
      expect(testSales[1].isPending, isTrue);
      expect(testSales[0].isPending, isFalse);
    });

    test('remainingCents calculates correctly', () {
      // Sale 2: total 22000, paid 10000, remaining 12000
      expect(testSales[1].remainingCents, equals(Decimal.fromInt(12000)));
    });

    test('isFullyPaid returns true when paid >= total', () {
      expect(testSales[0].isFullyPaid, isTrue);
      expect(testSales[1].isFullyPaid, isFalse);
    });
  });
}
