import 'package:bloc_test/bloc_test.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tapix/features/products/domain/entities/product_entity.dart';
import 'package:tapix/features/products/domain/entities/product_variant_entity.dart';
import 'package:tapix/features/products/domain/repositories/product_repository.dart';
import 'package:tapix/features/products/domain/repositories/product_variant_repository.dart';
import 'package:tapix/features/products/presentation/bloc/bulk_product_bloc.dart';

class MockProductRepository extends Mock implements ProductRepository {}

class MockProductVariantRepository extends Mock implements ProductVariantRepository {}

class FakeBulkProductData extends Fake implements BulkProductData {}

class FakeProductVariant extends Fake implements ProductVariant {}

void main() {
  late MockProductRepository mockRepository;
  late MockProductVariantRepository mockVariantRepository;

  setUpAll(() {
    registerFallbackValue(Decimal.zero);
    registerFallbackValue(<BulkProductData>[]);
    registerFallbackValue(FakeBulkProductData());
    registerFallbackValue(FakeProductVariant());
  });

  setUp(() {
    mockRepository = MockProductRepository();
    mockVariantRepository = MockProductVariantRepository();

    when(() => mockVariantRepository.createVariant(
          productId: any(named: 'productId'),
          sku: any(named: 'sku'),
          barcode: any(named: 'barcode'),
          colorId: any(named: 'colorId'),
          sizeId: any(named: 'sizeId'),
          costCents: any(named: 'costCents'),
          priceCents: any(named: 'priceCents'),
          stockQuantity: any(named: 'stockQuantity'),
          isActive: any(named: 'isActive'),
        )).thenAnswer((_) async => 1);
    
    // Default stubs for variant repository methods called after bulkCreateProducts
    when(() => mockVariantRepository.ensureDefaultVariantForProduct(
          productId: any(named: 'productId'),
          costCents: any(named: 'costCents'),
          priceCents: any(named: 'priceCents'),
          stockQuantity: any(named: 'stockQuantity'),
        )).thenAnswer((_) async => 1);
    when(() => mockVariantRepository.getDefaultVariantByProduct(any()))
        .thenAnswer((invocation) async => ProductVariant(
          id: 1,
          productId: invocation.positionalArguments[0] as int,
          costCents: Decimal.fromInt(500),
          priceCents: Decimal.fromInt(1000),
          priceAdjustmentCents: Decimal.zero,
          stockQuantity: 10,
          isActive: true,
        ));
    when(() => mockVariantRepository.updateVariant(any()))
        .thenAnswer((_) async => true);
  });

  group('BulkProductBloc', () {
    test('initial state is BulkProductInitial', () {
      final bloc = BulkProductBloc(mockRepository, mockVariantRepository);
      expect(bloc.state, isA<BulkProductInitial>());
      bloc.close();
    });

    blocTest<BulkProductBloc, BulkProductState>(
      'emits state with new row when BulkProductRowAdded is added',
      build: () => BulkProductBloc(mockRepository, mockVariantRepository),
      act: (bloc) => bloc.add(const BulkProductRowAdded()),
      expect: () => [
        isA<BulkProductEditing>().having(
          (s) => s.rows.length,
          'rows length',
          2, // Initial row + added row
        ),
      ],
    );

    blocTest<BulkProductBloc, BulkProductState>(
      'emits state with removed row when BulkProductRowRemoved is added',
      build: () => BulkProductBloc(mockRepository, mockVariantRepository),
      seed: () => BulkProductEditing(
        rows: [
          BulkProductRowData.empty(0),
          BulkProductRowData.empty(1),
        ],
        validationErrors: const {},
      ),
      act: (bloc) => bloc.add(const BulkProductRowRemoved(0)),
      expect: () => [
        isA<BulkProductEditing>().having(
          (s) => s.rows.length,
          'rows length',
          1,
        ),
      ],
    );

    blocTest<BulkProductBloc, BulkProductState>(
      'emits state with updated row when BulkProductRowUpdated is added',
      build: () => BulkProductBloc(mockRepository, mockVariantRepository),
      seed: () => BulkProductEditing(
        rows: [BulkProductRowData.empty(0)],
        validationErrors: const {},
      ),
      act: (bloc) => bloc.add(
        const BulkProductRowUpdated(
          rowIndex: 0,
          name: 'Test Product',
          sku: 'TEST-001',
        ),
      ),
      expect: () => [
        isA<BulkProductEditing>().having(
          (s) => s.rows[0].name,
          'row name',
          'Test Product',
        ),
      ],
    );

    blocTest<BulkProductBloc, BulkProductState>(
      'emits validation error for empty required fields',
      build: () {
        when(() => mockRepository.findBySku(any())).thenAnswer((_) async => null);
        return BulkProductBloc(mockRepository, mockVariantRepository);
      },
      seed: () => BulkProductEditing(
        rows: [
          BulkProductRowData(
            rowIndex: 0,
            name: '',
            sku: 'TEST-001',
            costCents: Decimal.zero,
            priceCents: Decimal.fromInt(1000),
            stockQuantity: 0,
          ),
        ],
        validationErrors: const {},
      ),
      act: (bloc) => bloc.add(const BulkProductValidationRequested()),
      expect: () => [
        isA<BulkProductEditing>().having(
          (s) => s.validationErrors.containsKey(0),
          'has validation error for row 0',
          true,
        ),
      ],
    );

    blocTest<BulkProductBloc, BulkProductState>(
      'emits BulkProductSubmitting then BulkProductSuccess on successful submission',
      build: () {
        when(() => mockRepository.findBySku(any())).thenAnswer((_) async => null);
        when(() => mockRepository.bulkCreateProducts(any()))
            .thenAnswer((_) async => {0: 1});
        return BulkProductBloc(mockRepository, mockVariantRepository);
      },
      seed: () => BulkProductEditing(
        rows: [
          BulkProductRowData(
            rowIndex: 0,
            name: 'Test Product',
            sku: 'TEST-001',
            costCents: Decimal.fromInt(500),
            priceCents: Decimal.fromInt(1000),
            stockQuantity: 10,
          ),
        ],
        validationErrors: const {},
      ),
      act: (bloc) => bloc.add(const BulkProductSubmitRequested()),
      wait: const Duration(milliseconds: 200),
      expect: () => [
        isA<BulkProductSubmitting>(),
        isA<BulkProductSuccess>().having(
          (s) => s.successCount,
          'success count',
          1,
        ),
      ],
    );

    blocTest<BulkProductBloc, BulkProductState>(
      'emits BulkProductError on submission failure',
      build: () {
        when(() => mockRepository.findBySku(any())).thenAnswer((_) async => null);
        when(() => mockRepository.bulkCreateProducts(any()))
            .thenThrow(Exception('Database error'));
        return BulkProductBloc(mockRepository, mockVariantRepository);
      },
      seed: () => BulkProductEditing(
        rows: [
          BulkProductRowData(
            rowIndex: 0,
            name: 'Test Product',
            sku: 'TEST-001',
            costCents: Decimal.fromInt(500),
            priceCents: Decimal.fromInt(1000),
            stockQuantity: 10,
          ),
        ],
        validationErrors: const {},
      ),
      act: (bloc) => bloc.add(const BulkProductSubmitRequested()),
      wait: const Duration(milliseconds: 200),
      expect: () => [
        isA<BulkProductSubmitting>(),
        isA<BulkProductError>(),
      ],
    );

    blocTest<BulkProductBloc, BulkProductState>(
      'detects SKU exists in database during validation',
      build: () {
        when(() => mockRepository.findBySku('EXISTING-SKU'))
            .thenAnswer((_) async => Product(
              id: 999,
              name: 'Existing Product',
              sku: 'EXISTING-SKU',
              barcode: null,
              costCents: Decimal.fromInt(500),
              priceCents: Decimal.fromInt(1000),
              wholesalePriceCents: null,
              stockQuantity: 10,
              minQuantity: 0,
              categoryId: null,
              supplierId: null,
              currencyId: 1,
              imagePath: null,
              hasVariants: false,
              isTaxable: false,
              purchaseTaxRateBps: 0,
              salesTaxRateBps: 0,
              isActive: true,
              trackInventory: true,
            ));
        return BulkProductBloc(mockRepository, mockVariantRepository);
      },
      seed: () => BulkProductEditing(
        rows: [
          BulkProductRowData(
            rowIndex: 0,
            name: 'Test Product',
            sku: 'EXISTING-SKU',
            costCents: Decimal.fromInt(500),
            priceCents: Decimal.fromInt(1000),
            stockQuantity: 10,
          ),
        ],
        validationErrors: const {},
      ),
      act: (bloc) => bloc.add(const BulkProductValidationRequested()),
      expect: () => [
        isA<BulkProductEditing>().having(
          (s) => s.validationErrors[0]?.contains('sku_exists_in_database'),
          'has SKU exists error',
          true,
        ),
      ],
    );

    blocTest<BulkProductBloc, BulkProductState>(
      'handles 100+ products efficiently',
      build: () {
        when(() => mockRepository.findBySku(any())).thenAnswer((_) async => null);
        when(() => mockRepository.bulkCreateProducts(any()))
            .thenAnswer((_) async => Map.fromEntries(
              List.generate(100, (i) => MapEntry(i, i + 1)),
            ));
        return BulkProductBloc(mockRepository, mockVariantRepository);
      },
      seed: () => BulkProductEditing(
        rows: List.generate(
          100,
          (i) => BulkProductRowData(
            rowIndex: i,
            name: 'Product $i',
            sku: 'SKU-$i',
            costCents: Decimal.fromInt(500),
            priceCents: Decimal.fromInt(1000),
            stockQuantity: 10,
          ),
        ),
        validationErrors: const {},
      ),
      act: (bloc) => bloc.add(const BulkProductSubmitRequested()),
      wait: const Duration(seconds: 2),
      expect: () => [
        isA<BulkProductSubmitting>(),
        isA<BulkProductSuccess>().having(
          (s) => s.successCount,
          'success count',
          100,
        ),
      ],
      verify: (_) {
        verify(() => mockRepository.bulkCreateProducts(any())).called(1);
      },
    );
  });
}
