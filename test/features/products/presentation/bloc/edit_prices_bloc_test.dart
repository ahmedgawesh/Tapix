import 'package:bloc_test/bloc_test.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:tapix/core/bloc/realtime_bloc.dart';
import 'package:tapix/features/products/domain/repositories/product_repository.dart';
import 'package:tapix/features/products/domain/repositories/product_variant_repository.dart';
import 'package:tapix/features/products/presentation/bloc/edit_prices_bloc.dart';
import 'package:tapix/features/products/presentation/bloc/edit_prices_event.dart';
import 'package:tapix/features/products/presentation/bloc/edit_prices_state.dart';
import 'package:tapix/features/products/domain/entities/product_entity.dart';

import 'edit_prices_bloc_test.mocks.dart';

@GenerateMocks([ProductRepository, ProductVariantRepository])
void main() {
  late MockProductRepository mockRepository;
  late MockProductVariantRepository mockVariantRepository;

  final tProduct = Product(
    id: 1,
    name: 'Test Product',
    costCents: Decimal.parse('1000'),
    priceCents: Decimal.parse('2000'),
    stockQuantity: 10,
    minQuantity: 5,
    isActive: true,
    trackInventory: true,
    hasVariants: false,
    isTaxable: false,
    purchaseTaxRateBps: 0,
    salesTaxRateBps: 0,
  );

  setUp(() {
    mockRepository = MockProductRepository();
    mockVariantRepository = MockProductVariantRepository();
    // Default stub for watchAllProducts
    when(
      mockRepository.watchAllProducts(),
    ).thenAnswer((_) => Stream.value([tProduct]));
    when(
      mockRepository.watchFilteredProducts(
        categoryId: anyNamed('categoryId'),
        stockStatus: anyNamed('stockStatus'),
      ),
    ).thenAnswer((_) => Stream.value([tProduct]));
  });

  group('EditPricesBloc', () {
    test('initial state is RealtimeLoading', () {
      final bloc = EditPricesBloc(mockRepository, mockVariantRepository);
      expect(bloc.state, isA<RealtimeLoading<EditPricesStateData>>());
      bloc.close();
    });

    blocTest<EditPricesBloc, RealtimeState<EditPricesStateData>>(
      'emits RealtimeSuccess when stream emits data',
      build: () => EditPricesBloc(mockRepository, mockVariantRepository),
      wait: const Duration(milliseconds: 100),
      expect: () => [isA<RealtimeSuccess<EditPricesStateData>>()],
    );

    blocTest<EditPricesBloc, RealtimeState<EditPricesStateData>>(
      'emits RealtimeLoading then RealtimeSuccess when LoadProducts is added',
      build: () => EditPricesBloc(mockRepository, mockVariantRepository),
      act: (bloc) => bloc.add(const EditPricesLoadProducts()),
      wait: const Duration(milliseconds: 100),
      expect: () => [
        isA<RealtimeSuccess<EditPricesStateData>>(),
        isA<RealtimeLoading<EditPricesStateData>>(),
        isA<RealtimeSuccess<EditPricesStateData>>(),
      ],
    );

    blocTest<EditPricesBloc, RealtimeState<EditPricesStateData>>(
      'updates price optimistically when EditPricesPriceUpdated is added',
      build: () => EditPricesBloc(mockRepository, mockVariantRepository),
      act: (bloc) async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        bloc.add(
          EditPricesPriceUpdated(
            productId: 1,
            newPrice: Decimal.parse('2500'),
            isWholesale: false,
          ),
        );
      },
      wait: const Duration(milliseconds: 100),
      verify: (bloc) {
        expect(bloc.hasUnsavedChanges, true);
      },
    );

    blocTest<EditPricesBloc, RealtimeState<EditPricesStateData>>(
      'performs bulk price adjustment with percentage increase',
      build: () => EditPricesBloc(mockRepository, mockVariantRepository),
      act: (bloc) async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        bloc.add(
          EditPricesBulkAdjustRequested(
            adjustmentType: 'percentage_increase',
            value: Decimal.fromInt(10),
            applyToAll: true,
          ),
        );
      },
      wait: const Duration(milliseconds: 100),
      verify: (bloc) {
        expect(bloc.hasUnsavedChanges, true);
      },
    );

    blocTest<EditPricesBloc, RealtimeState<EditPricesStateData>>(
      'supports undo after price change',
      build: () => EditPricesBloc(mockRepository, mockVariantRepository),
      act: (bloc) async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        bloc.add(
          EditPricesPriceUpdated(
            productId: 1,
            newPrice: Decimal.parse('2500'),
            isWholesale: false,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
        bloc.add(const EditPricesUndoRequested());
      },
      wait: const Duration(milliseconds: 100),
      verify: (bloc) {
        expect(bloc.canRedo, true);
      },
    );

    blocTest<EditPricesBloc, RealtimeState<EditPricesStateData>>(
      'supports redo after undo',
      build: () => EditPricesBloc(mockRepository, mockVariantRepository),
      act: (bloc) async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        bloc.add(
          EditPricesPriceUpdated(
            productId: 1,
            newPrice: Decimal.parse('2500'),
            isWholesale: false,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
        bloc.add(const EditPricesUndoRequested());
        await Future<void>.delayed(const Duration(milliseconds: 50));
        bloc.add(const EditPricesRedoRequested());
      },
      wait: const Duration(milliseconds: 150),
      verify: (bloc) {
        expect(bloc.hasUnsavedChanges, true);
      },
    );

    blocTest<EditPricesBloc, RealtimeState<EditPricesStateData>>(
      'clears unsaved changes when discard is requested',
      build: () => EditPricesBloc(mockRepository, mockVariantRepository),
      act: (bloc) async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        bloc.add(
          EditPricesPriceUpdated(
            productId: 1,
            newPrice: Decimal.parse('2500'),
            isWholesale: false,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
        bloc.add(const EditPricesDiscardChanges());
      },
      wait: const Duration(milliseconds: 100),
      verify: (bloc) {
        expect(bloc.hasUnsavedChanges, false);
        expect(bloc.canUndo, false);
        expect(bloc.canRedo, false);
      },
    );

    blocTest<EditPricesBloc, RealtimeState<EditPricesStateData>>(
      'saves price changes to repository',
      build: () {
        when(mockRepository.updateProduct(any)).thenAnswer((_) async => true);
        return EditPricesBloc(mockRepository, mockVariantRepository);
      },
      act: (bloc) async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        bloc.add(
          EditPricesPriceUpdated(
            productId: 1,
            newPrice: Decimal.parse('2500'),
            isWholesale: false,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
        bloc.add(const EditPricesSaveChanges());
      },
      wait: const Duration(milliseconds: 150),
      verify: (bloc) {
        verify(mockRepository.updateProduct(any)).called(1);
      },
    );

    blocTest<EditPricesBloc, RealtimeState<EditPricesStateData>>(
      'filters products by category',
      build: () => EditPricesBloc(mockRepository, mockVariantRepository),
      act: (bloc) {
        bloc.add(const EditPricesFilterChanged(categoryId: 1));
      },
      wait: const Duration(milliseconds: 100),
      verify: (bloc) {
        verify(
          mockRepository.watchFilteredProducts(
            categoryId: 1,
            stockStatus: null,
          ),
        ).called(greaterThan(0));
      },
    );

    blocTest<EditPricesBloc, RealtimeState<EditPricesStateData>>(
      'filters products by stock status',
      build: () => EditPricesBloc(mockRepository, mockVariantRepository),
      act: (bloc) {
        bloc.add(const EditPricesFilterChanged(stockStatus: 'low_stock'));
      },
      wait: const Duration(milliseconds: 100),
      verify: (bloc) {
        verify(
          mockRepository.watchFilteredProducts(
            categoryId: null,
            stockStatus: 'low_stock',
          ),
        ).called(greaterThan(0));
      },
    );
  });
}
