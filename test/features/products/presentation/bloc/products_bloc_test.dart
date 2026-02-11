import 'package:bloc_test/bloc_test.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tapix/core/bloc/realtime_bloc.dart';
import 'package:tapix/features/products/domain/entities/product_entity.dart';
import 'package:tapix/features/products/domain/repositories/product_repository.dart';
import 'package:tapix/features/products/presentation/bloc/products_bloc.dart';

class MockProductRepository extends Mock implements ProductRepository {}

class MockProduct extends Mock implements Product {}

void main() {
  late ProductRepository mockRepository;
  late ProductsBloc bloc;
  final testProducts = <Product>[];

  setUpAll(() {
    registerFallbackValue(Decimal.zero);
  });

  setUp(() {
    mockRepository = MockProductRepository();
    // Stub watchAllProducts since it's called immediately in constructor
    // Use Stream.empty() to prevent automatic state changes during tests
    when(() => mockRepository.watchAllProducts())
        .thenAnswer((_) => const Stream.empty());
    bloc = ProductsBloc(mockRepository);
  });

  tearDown(() {
    bloc.close();
  });

  group('ProductsBloc', () {
    test('initial state is RealtimeLoading', () {
      expect(bloc.state, isA<RealtimeLoading<List<Product>>>());
    });

    group('ProductSearchRequested', () {
      blocTest<ProductsBloc, RealtimeState<List<Product>>>(
        'emits loading then success with search results',
        build: () {
          when(() => mockRepository.watchAllProducts())
              .thenAnswer((_) => const Stream.empty());
          when(() => mockRepository.searchProducts(any()))
              .thenAnswer((_) async => testProducts);
          return ProductsBloc(mockRepository);
        },
        act: (bloc) => bloc.add(const ProductSearchRequested('test')),
        expect: () => [
          isA<RealtimeLoading<List<Product>>>(),
          isA<RealtimeSuccess<List<Product>>>(),
        ],
        verify: (_) {
          verify(() => mockRepository.searchProducts('test')).called(1);
        },
      );

      blocTest<ProductsBloc, RealtimeState<List<Product>>>(
        'clears search when query is empty',
        build: () {
          when(() => mockRepository.watchAllProducts())
              .thenAnswer((_) => Stream.value(testProducts));
          return ProductsBloc(mockRepository);
        },
        act: (bloc) => bloc.add(const ProductSearchRequested('')),
        verify: (_) {
          verify(() => mockRepository.watchAllProducts()).called(greaterThan(0));
        },
      );
    });

    group('ProductFilterRequested', () {
      blocTest<ProductsBloc, RealtimeState<List<Product>>>(
        'emits loading then success with filtered results',
        build: () {
          when(() => mockRepository.watchAllProducts())
              .thenAnswer((_) => const Stream.empty());
          when(() => mockRepository.filterProducts(
                categoryId: any(named: 'categoryId'),
                stockStatus: any(named: 'stockStatus'),
                limit: any(named: 'limit'),
                offset: any(named: 'offset'),
              )).thenAnswer((_) async => testProducts);
          return ProductsBloc(mockRepository);
        },
        act: (bloc) => bloc.add(const ProductFilterRequested(
          categoryId: 1,
          stockStatus: 'low_stock',
        )),
        expect: () => [
          isA<RealtimeLoading<List<Product>>>(),
          isA<RealtimeSuccess<List<Product>>>(),
        ],
        verify: (bloc) {
          expect(bloc.activeFiltersCount, 2);
          expect(bloc.currentCategoryFilter, 1);
          expect(bloc.currentStockStatusFilter, 'low_stock');
        },
      );
    });

    group('ProductFilterCleared', () {
      blocTest<ProductsBloc, RealtimeState<List<Product>>>(
        'clears all filters and refreshes',
        build: () {
          when(() => mockRepository.watchAllProducts())
              .thenAnswer((_) => Stream.value(testProducts));
          return ProductsBloc(mockRepository);
        },
        seed: () {
          final bloc = ProductsBloc(mockRepository);
          bloc.add(const ProductFilterRequested(categoryId: 1));
          return bloc.state;
        },
        act: (bloc) => bloc.add(const ProductFilterCleared()),
        verify: (bloc) {
          expect(bloc.activeFiltersCount, 0);
          expect(bloc.currentCategoryFilter, null);
          expect(bloc.currentStockStatusFilter, null);
        },
      );
    });

    group('ProductBarcodeScanned', () {
      final testProduct = MockProduct();

      blocTest<ProductsBloc, RealtimeState<List<Product>>>(
        'emits loading then success with scanned product',
        build: () {
          when(() => mockRepository.watchAllProducts())
              .thenAnswer((_) => const Stream.empty());
          when(() => mockRepository.findByBarcode(any()))
              .thenAnswer((_) async => testProduct);
          return ProductsBloc(mockRepository);
        },
        act: (bloc) => bloc.add(const ProductBarcodeScanned('123456')),
        expect: () => [
          isA<RealtimeLoading<List<Product>>>(),
          isA<RealtimeSuccess<List<Product>>>(),
        ],
        verify: (_) {
          verify(() => mockRepository.findByBarcode('123456')).called(1);
        },
      );

      blocTest<ProductsBloc, RealtimeState<List<Product>>>(
        'emits empty list when barcode not found',
        build: () {
          when(() => mockRepository.watchAllProducts())
              .thenAnswer((_) => const Stream.empty());
          when(() => mockRepository.findByBarcode(any()))
              .thenAnswer((_) async => null);
          return ProductsBloc(mockRepository);
        },
        act: (bloc) => bloc.add(const ProductBarcodeScanned('999999')),
        expect: () => [
          isA<RealtimeLoading<List<Product>>>(),
          predicate<RealtimeSuccess<List<Product>>>(
            (state) => state.data.isEmpty,
          ),
        ],
      );
    });

    group('ProductLoadMoreRequested', () {
      blocTest<ProductsBloc, RealtimeState<List<Product>>>(
        'loads more products and appends to list',
        build: () {
          when(() => mockRepository.watchAllProducts())
              .thenAnswer((_) => const Stream.empty());
          // Return enough products to trigger hasMoreData = true (>= pageSize)
          final manyProducts = List.generate(50, (i) => MockProduct());
          when(() => mockRepository.filterProducts(
                categoryId: any(named: 'categoryId'),
                stockStatus: any(named: 'stockStatus'),
                limit: any(named: 'limit'),
                offset: any(named: 'offset'),
              )).thenAnswer((_) async => manyProducts);
          return ProductsBloc(mockRepository);
        },
        act: (bloc) async {
          // First trigger a filter to set hasMoreData = true
          bloc.add(const ProductFilterRequested(categoryId: 1));
          await Future<void>.delayed(const Duration(milliseconds: 50));
          // Then request more
          bloc.add(const ProductLoadMoreRequested());
        },
        expect: () => [
          isA<RealtimeLoading<List<Product>>>(),
          isA<RealtimeSuccess<List<Product>>>(),
          isA<RealtimeSuccess<List<Product>>>(),
        ],
      );

      blocTest<ProductsBloc, RealtimeState<List<Product>>>(
        'does not load more when hasMoreData is false',
        build: () {
          when(() => mockRepository.watchAllProducts())
              .thenAnswer((_) => const Stream.empty());
          when(() => mockRepository.filterProducts(
                categoryId: any(named: 'categoryId'),
                stockStatus: any(named: 'stockStatus'),
                limit: any(named: 'limit'),
                offset: any(named: 'offset'),
              )).thenAnswer((_) async => []);
          final bloc = ProductsBloc(mockRepository);
          bloc.add(const ProductLoadMoreRequested());
          return bloc;
        },
        act: (bloc) => bloc.add(const ProductLoadMoreRequested()),
        verify: (bloc) {
          expect(bloc.hasMoreData, false);
        },
      );
    });

    group('ProductCreateRequested', () {
      blocTest<ProductsBloc, RealtimeState<List<Product>>>(
        'creates product successfully',
        build: () {
          when(() => mockRepository.watchAllProducts())
              .thenAnswer((_) => const Stream.empty());
          when(() => mockRepository.createProduct(
                name: any(named: 'name'),
                nameAr: any(named: 'nameAr'),
                nameFr: any(named: 'nameFr'),
                description: any(named: 'description'),
                sku: any(named: 'sku'),
                barcode: any(named: 'barcode'),
                costCents: any(named: 'costCents'),
                priceCents: any(named: 'priceCents'),
                wholesalePriceCents: any(named: 'wholesalePriceCents'),
                stockQuantity: any(named: 'stockQuantity'),
                minQuantity: any(named: 'minQuantity'),
                categoryId: any(named: 'categoryId'),
                supplierId: any(named: 'supplierId'),
                currencyId: any(named: 'currencyId'),
                imagePath: any(named: 'imagePath'),
                hasVariants: any(named: 'hasVariants'),
                isTaxable: any(named: 'isTaxable'),
                purchaseTaxRateBps: any(named: 'purchaseTaxRateBps'),
                salesTaxRateBps: any(named: 'salesTaxRateBps'),
                isActive: any(named: 'isActive'),
                trackInventory: any(named: 'trackInventory'),
              )).thenAnswer((_) async => 1);
          return ProductsBloc(mockRepository);
        },
        act: (bloc) => bloc.add(ProductCreateRequested(
          sku: 'TEST-001',
          name: 'Test Product',
          costCents: Decimal.fromInt(1000),
          priceCents: Decimal.fromInt(1500),
          currencyId: 1,
        )),
        verify: (_) {
          verify(() => mockRepository.createProduct(
                name: 'Test Product',
                nameAr: any(named: 'nameAr'),
                nameFr: any(named: 'nameFr'),
                description: any(named: 'description'),
                sku: 'TEST-001',
                barcode: any(named: 'barcode'),
                costCents: Decimal.fromInt(1000),
                priceCents: Decimal.fromInt(1500),
                wholesalePriceCents: any(named: 'wholesalePriceCents'),
                stockQuantity: any(named: 'stockQuantity'),
                minQuantity: any(named: 'minQuantity'),
                categoryId: any(named: 'categoryId'),
                supplierId: any(named: 'supplierId'),
                currencyId: 1,
                imagePath: any(named: 'imagePath'),
                hasVariants: any(named: 'hasVariants'),
                isTaxable: any(named: 'isTaxable'),
                purchaseTaxRateBps: any(named: 'purchaseTaxRateBps'),
                salesTaxRateBps: any(named: 'salesTaxRateBps'),
                isActive: any(named: 'isActive'),
                trackInventory: any(named: 'trackInventory'),
              )).called(1);
        },
      );
    });
  });
}
