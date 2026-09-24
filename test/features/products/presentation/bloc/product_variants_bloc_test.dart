import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tapix/core/bloc/realtime_bloc.dart';
import 'package:tapix/features/products/domain/entities/product_variant_entity.dart';
import 'package:tapix/features/products/domain/repositories/product_variant_repository.dart';
import 'package:tapix/features/products/presentation/bloc/product_variants_bloc.dart';

class MockProductVariantRepository extends Mock
    implements ProductVariantRepository {}

class FakeProductVariant extends Fake implements ProductVariant {}

class FakeDecimal extends Fake implements Decimal {}

void main() {
  setUpAll(() {
    registerFallbackValue(FakeProductVariant());
    registerFallbackValue(FakeDecimal());
  });

  group('ProductVariantsBloc', () {
    late MockProductVariantRepository repository;
    late ProductVariantsBloc bloc;

    setUp(() {
      repository = MockProductVariantRepository();
      bloc = ProductVariantsBloc(repository);
    });

    tearDown(() {
      bloc.close();
    });

    test('initial state is RealtimeLoading', () {
      expect(bloc.state, isA<RealtimeLoading<List<ProductVariant>>>());
    });

    group('ProductVariantsInitialized', () {
      test('subscribes to variants stream', () async {
        final List<ProductVariant> variants = [
          ProductVariant(
            id: 1,
            productId: 1,
            costCents: Decimal.zero,
            priceCents: Decimal.zero,
            priceAdjustmentCents: Decimal.zero,
            stockQuantity: 10,
            isActive: true,
          ),
        ];

        when(
          () => repository.watchVariantsByProduct(1),
        ).thenAnswer((_) => Stream.value(variants));

        bloc.add(const ProductVariantsInitialized(1));

        await expectLater(
          bloc.stream,
          emitsInOrder([
            isA<RealtimeLoading<List<ProductVariant>>>(),
            isA<RealtimeSuccess<List<ProductVariant>>>().having(
              (s) => s.data,
              'data',
              variants,
            ),
          ]),
        );
      });
    });

    group('VariantCreateRequested', () {
      test('calls createVariant on repository', () async {
        when(
          () => repository.createVariant(
            productId: any(named: 'productId'),
            costCents: any(named: 'costCents'),
            priceCents: any(named: 'priceCents'),
            stockQuantity: any(named: 'stockQuantity'),
            sku: any(named: 'sku'),
            barcode: any(named: 'barcode'),
            colorId: any(named: 'colorId'),
            sizeId: any(named: 'sizeId'),
          ),
        ).thenAnswer((_) async => 1);

        bloc.add(
          VariantCreateRequested(
            productId: 1,
            costCents: Decimal.fromInt(500),
            priceCents: Decimal.fromInt(1000),
            stockQuantity: 5,
            sku: 'VAR-001',
          ),
        );

        // Wait for async operation
        await Future<void>.delayed(const Duration(milliseconds: 100));

        verify(
          () => repository.createVariant(
            productId: 1,
            costCents: Decimal.fromInt(500),
            priceCents: Decimal.fromInt(1000),
            stockQuantity: 5,
            sku: 'VAR-001',
          ),
        ).called(1);
      });
    });

    group('VariantUpdateRequested', () {
      test('updates variant optimistically', () async {
        final List<ProductVariant> variants = [
          ProductVariant(
            id: 1,
            productId: 1,
            costCents: Decimal.zero,
            priceCents: Decimal.zero,
            priceAdjustmentCents: Decimal.zero,
            stockQuantity: 10,
            isActive: true,
          ),
        ];

        // Setup initial data
        when(
          () => repository.watchVariantsByProduct(1),
        ).thenAnswer((_) => Stream.value(variants));
        bloc.add(const ProductVariantsInitialized(1));

        // Wait for initial data load
        await bloc.stream.firstWhere((state) => state is RealtimeSuccess);

        final updatedVariant = variants[0].copyWith(stockQuantity: 20);
        when(
          () => repository.updateVariant(updatedVariant),
        ).thenAnswer((_) async => true);

        bloc.add(VariantUpdateRequested(updatedVariant));

        await expectLater(
          bloc.stream,
          emits(
            isA<RealtimeOptimistic<List<ProductVariant>>>().having(
              (s) => s.optimisticData.first.stockQuantity,
              'stockQuantity',
              20,
            ),
          ),
        );

        verify(() => repository.updateVariant(updatedVariant)).called(1);
      });
    });

    group('VariantDeleteRequested', () {
      test('deletes variant optimistically', () async {
        final List<ProductVariant> variants = [
          ProductVariant(
            id: 1,
            productId: 1,
            costCents: Decimal.zero,
            priceCents: Decimal.zero,
            priceAdjustmentCents: Decimal.zero,
            stockQuantity: 10,
            isActive: true,
          ),
        ];

        // Setup initial data
        when(
          () => repository.watchVariantsByProduct(1),
        ).thenAnswer((_) => Stream.value(variants));
        bloc.add(const ProductVariantsInitialized(1));

        // Wait for initial data load
        await bloc.stream.firstWhere((state) => state is RealtimeSuccess);

        // The bloc routes deletes through smartDeleteVariant so referenced
        // variants get deactivated rather than FK-failing. Cf. audit issue #16.
        when(() => repository.smartDeleteVariant(1)).thenAnswer(
          (_) async =>
              const VariantDeletionResult(wasDeleted: true, referenceCount: 0),
        );

        bloc.add(const VariantDeleteRequested(1));

        await expectLater(
          bloc.stream,
          emits(
            isA<RealtimeOptimistic<List<ProductVariant>>>().having(
              (s) => s.optimisticData,
              'optimisticData',
              isEmpty,
            ),
          ),
        );

        verify(() => repository.smartDeleteVariant(1)).called(1);
        verifyNever(() => repository.deleteVariant(1));
      });
    });
  });
}
