import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tapix/core/bloc/realtime_bloc.dart';
import 'package:tapix/features/products/presentation/bloc/export_bloc.dart';
import 'package:tapix/features/products/presentation/bloc/export_event.dart';
import 'package:tapix/features/products/presentation/bloc/export_state.dart';
import 'package:tapix/features/products/services/export_service.dart';
import 'package:tapix/features/products/domain/entities/product_entity.dart';
import 'package:decimal/decimal.dart';
import 'dart:typed_data';

class MockExportService extends Mock implements ExportService {}

void main() {
  late ExportBloc exportBloc;
  late MockExportService mockExportService;

  setUp(() {
    mockExportService = MockExportService();
    when(
      () => mockExportService.watchProducts(
        categoryId: any(named: 'categoryId', that: anything),
        supplierId: any(named: 'supplierId', that: anything),
        activeOnly: any(named: 'activeOnly'),
      ),
    ).thenAnswer((_) => const Stream.empty());
    exportBloc = ExportBloc(mockExportService);
  });

  tearDown(() {
    exportBloc.close();
  });

  final testProducts = [
    Product(
      id: 1,
      name: 'Product 1',
      sku: 'SKU001',
      costCents: Decimal.parse('1000'),
      priceCents: Decimal.parse('1500'),
      stockQuantity: 100,
      minQuantity: 10,
      hasVariants: false,
      isTaxable: false,
      purchaseTaxRateBps: 0,
      salesTaxRateBps: 0,
      isActive: true,
      trackInventory: true,
    ),
  ];

  group('ExportBloc', () {
    test('initial state is RealtimeLoading', () {
      expect(exportBloc.state, isA<RealtimeLoading<ExportUiData>>());
    });

    blocTest<ExportBloc, RealtimeState<ExportUiData>>(
      'emits loading then success when LoadExportPreview subscribes',
      build: () {
        when(
          () => mockExportService.watchProducts(
            categoryId: any(named: 'categoryId', that: anything),
            supplierId: any(named: 'supplierId', that: anything),
            activeOnly: any(named: 'activeOnly'),
          ),
        ).thenAnswer((_) => Stream.value(testProducts));
        return ExportBloc(mockExportService);
      },
      act: (bloc) => bloc.add(const LoadExportPreview()),
      expect: () => [
        isA<RealtimeLoading<ExportUiData>>(),
        isA<RealtimeSuccess<ExportUiData>>().having(
          (s) => s.data.products,
          'products',
          testProducts,
        ),
      ],
    );

    blocTest<ExportBloc, RealtimeState<ExportUiData>>(
      'emits error when watchProducts stream errors',
      build: () {
        when(
          () => mockExportService.watchProducts(
            categoryId: any(named: 'categoryId', that: anything),
            supplierId: any(named: 'supplierId', that: anything),
            activeOnly: any(named: 'activeOnly'),
          ),
        ).thenAnswer((_) => Stream.error(Exception('Failed to load preview')));
        return ExportBloc(mockExportService);
      },
      act: (bloc) => bloc.add(const LoadExportPreview()),
      wait: const Duration(milliseconds: 50),
      expect: () => [
        isA<RealtimeLoading<ExportUiData>>(),
        isA<RealtimeError<ExportUiData>>(),
      ],
    );

    blocTest<ExportBloc, RealtimeState<ExportUiData>>(
      'emits success payload when ExportToCSV succeeds',
      build: () {
        when(
          () => mockExportService.exportToCSV(
            categoryId: any(named: 'categoryId', that: anything),
            supplierId: any(named: 'supplierId', that: anything),
            activeOnly: any(named: 'activeOnly'),
            selectedProductIds: any(named: 'selectedProductIds'),
          ),
        ).thenAnswer((_) async => 'id,name\n1,Product 1');
        when(
          () => mockExportService.watchProducts(
            categoryId: any(named: 'categoryId', that: anything),
            supplierId: any(named: 'supplierId', that: anything),
            activeOnly: any(named: 'activeOnly'),
          ),
        ).thenAnswer((_) => Stream.value(testProducts));
        return ExportBloc(mockExportService);
      },
      act: (bloc) async {
        bloc.add(const LoadExportPreview());
        await Future<void>.delayed(const Duration(milliseconds: 10));
        bloc.add(const ExportToCSV());
      },
      wait: const Duration(milliseconds: 50),
      expect: () => [
        isA<RealtimeLoading<ExportUiData>>(),
        isA<RealtimeSuccess<ExportUiData>>(),
        isA<RealtimeSuccess<ExportUiData>>(),
        isA<RealtimeSuccess<ExportUiData>>().having(
          (s) => s.data.lastExport,
          'lastExport',
          isNotNull,
        ),
      ],
    );

    blocTest<ExportBloc, RealtimeState<ExportUiData>>(
      'emits success payload when ExportToExcel succeeds',
      build: () {
        when(
          () => mockExportService.exportToExcel(
            categoryId: any(named: 'categoryId', that: anything),
            supplierId: any(named: 'supplierId', that: anything),
            activeOnly: any(named: 'activeOnly'),
            selectedProductIds: any(named: 'selectedProductIds'),
          ),
        ).thenAnswer((_) async => Uint8List.fromList([1, 2, 3]));
        when(
          () => mockExportService.watchProducts(
            categoryId: any(named: 'categoryId', that: anything),
            supplierId: any(named: 'supplierId', that: anything),
            activeOnly: any(named: 'activeOnly'),
          ),
        ).thenAnswer((_) => Stream.value(testProducts));
        return ExportBloc(mockExportService);
      },
      act: (bloc) async {
        bloc.add(const LoadExportPreview());
        await Future<void>.delayed(const Duration(milliseconds: 10));
        bloc.add(const ExportToExcel());
      },
      wait: const Duration(milliseconds: 50),
      expect: () => [
        isA<RealtimeLoading<ExportUiData>>(),
        isA<RealtimeSuccess<ExportUiData>>(),
        isA<RealtimeSuccess<ExportUiData>>(),
        isA<RealtimeSuccess<ExportUiData>>().having(
          (s) => s.data.lastExport,
          'lastExport',
          isNotNull,
        ),
      ],
    );

    blocTest<ExportBloc, RealtimeState<ExportUiData>>(
      'passes category filter through to exportToCSV',
      build: () {
        when(
          () => mockExportService.exportToCSV(
            categoryId: 5,
            supplierId: any(named: 'supplierId', that: anything),
            activeOnly: any(named: 'activeOnly'),
            selectedProductIds: any(named: 'selectedProductIds'),
          ),
        ).thenAnswer((_) async => 'id,name\n1,Product 1');
        when(
          () => mockExportService.watchProducts(
            categoryId: any(named: 'categoryId', that: anything),
            supplierId: any(named: 'supplierId', that: anything),
            activeOnly: any(named: 'activeOnly'),
          ),
        ).thenAnswer((_) => Stream.value(testProducts));
        return ExportBloc(mockExportService);
      },
      act: (bloc) async {
        bloc.add(const LoadExportPreview());
        await Future<void>.delayed(const Duration(milliseconds: 10));
        bloc.add(const ExportToCSV(categoryId: 5));
      },
      verify: (_) {
        verify(
          () => mockExportService.exportToCSV(
            categoryId: 5,
            supplierId: any(named: 'supplierId', that: anything),
            activeOnly: any(named: 'activeOnly'),
            selectedProductIds: any(named: 'selectedProductIds'),
          ),
        ).called(1);
      },
    );

    blocTest<ExportBloc, RealtimeState<ExportUiData>>(
      'updates format selection in ui data',
      build: () {
        when(
          () => mockExportService.watchProducts(
            categoryId: any(named: 'categoryId', that: anything),
            supplierId: any(named: 'supplierId', that: anything),
            activeOnly: any(named: 'activeOnly'),
          ),
        ).thenAnswer((_) => Stream.value(testProducts));
        return ExportBloc(mockExportService);
      },
      act: (bloc) => bloc.add(const UpdateExportFormat(ExportFormat.excel)),
      expect: () => [
        isA<RealtimeSuccess<ExportUiData>>().having(
          (s) => s.data.format,
          'format',
          ExportFormat.excel,
        ),
      ],
    );
  });
}
