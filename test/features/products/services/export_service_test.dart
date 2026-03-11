import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tapix/features/products/services/export_service.dart';
import 'package:tapix/features/products/domain/repositories/product_repository.dart';
import 'package:tapix/features/products/domain/repositories/product_variant_repository.dart';
import 'package:tapix/features/products/domain/repositories/category_repository.dart';
import 'package:tapix/features/products/domain/entities/product_entity.dart';
import 'package:tapix/features/products/domain/entities/product_color_entity.dart';
import 'package:tapix/features/products/domain/entities/size_entity.dart';
import 'package:decimal/decimal.dart';

class MockProductRepository extends Mock implements ProductRepository {}

class MockProductVariantRepository extends Mock implements ProductVariantRepository {}

class MockCategoryRepository extends Mock implements CategoryRepository {}

void main() {
  late ExportService exportService;
  late MockProductRepository mockProductRepository;
  late MockProductVariantRepository mockVariantRepository;
  late MockCategoryRepository mockCategoryRepository;

  setUp(() {
    mockProductRepository = MockProductRepository();
    mockVariantRepository = MockProductVariantRepository();
    mockCategoryRepository = MockCategoryRepository();

    when(() => mockVariantRepository.getAllColors()).thenAnswer((_) async => <ProductColor>[]);
    when(() => mockVariantRepository.getAllSizes()).thenAnswer((_) async => <Size>[]);
    when(() => mockVariantRepository.getVariantsByProduct(any())).thenAnswer((_) async => []);
    when(() => mockVariantRepository.getDefaultVariantByProduct(any())).thenAnswer((_) async => null);
    when(() => mockCategoryRepository.getAllCategories()).thenAnswer((_) async => []);

    exportService = ExportServiceImpl(mockProductRepository, mockVariantRepository, mockCategoryRepository);
  });

  group('ExportService', () {
    final testProducts = [
      Product(
        id: 1,
        name: 'Product 1',
        sku: 'SKU001',
        barcode: 'BAR001',
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
      Product(
        id: 2,
        name: 'Product 2',
        sku: 'SKU002',
        barcode: 'BAR002',
        costCents: Decimal.parse('2000'),
        priceCents: Decimal.parse('3000'),
        stockQuantity: 50,
        minQuantity: 5,
        hasVariants: false,
        isTaxable: false,
        purchaseTaxRateBps: 0,
        salesTaxRateBps: 0,
        isActive: true,
        trackInventory: true,
      ),
    ];

    group('exportToCSV', () {
      test('generates CSV with all product fields in cents', () async {
        when(() => mockProductRepository.fetchProductsForExport(
              categoryId: any(named: 'categoryId'),
              supplierId: any(named: 'supplierId'),
              activeOnly: any(named: 'activeOnly'),
              limit: any(named: 'limit'),
              offset: any(named: 'offset'),
            )).thenAnswer((_) async => testProducts);

        final result = await exportService.exportToCSV();

        expect(result, isNotNull);
        expect(result, contains('product_id,name,description,category,sku,barcode,color,size'));
        expect(result, contains('Product 1'));
        expect(result, contains('1000')); // cost in cents
        expect(result, contains('1500')); // price in cents
        expect(result, contains('100')); // stock quantity
      });

      test('handles empty product list', () async {
        when(() => mockProductRepository.fetchProductsForExport(
              categoryId: any(named: 'categoryId'),
              supplierId: any(named: 'supplierId'),
              activeOnly: any(named: 'activeOnly'),
              limit: any(named: 'limit'),
              offset: any(named: 'offset'),
            )).thenAnswer((_) async => []);

        final result = await exportService.exportToCSV();

        expect(result, isNotNull);
        expect(result, contains('product_id,name,description,category,sku,barcode,color,size')); // Header only
      });

      test('respects category filter', () async {
        when(() => mockProductRepository.fetchProductsForExport(
              categoryId: 5,
              supplierId: any(named: 'supplierId'),
              activeOnly: any(named: 'activeOnly'),
              limit: any(named: 'limit'),
              offset: any(named: 'offset'),
            )).thenAnswer((_) async => [testProducts.first]);

        final result = await exportService.exportToCSV(categoryId: 5);

        expect(result, isNotNull);
        verify(() => mockProductRepository.fetchProductsForExport(
              categoryId: 5,
              supplierId: any(named: 'supplierId'),
              activeOnly: any(named: 'activeOnly'),
              limit: any(named: 'limit'),
              offset: any(named: 'offset'),
            )).called(1);
      });
    });

    group('exportToExcel', () {
      test('generates Excel file bytes', () async {
        when(() => mockProductRepository.fetchProductsForExport(
              categoryId: any(named: 'categoryId'),
              supplierId: any(named: 'supplierId'),
              activeOnly: any(named: 'activeOnly'),
              limit: any(named: 'limit'),
              offset: any(named: 'offset'),
            )).thenAnswer((_) async => testProducts);

        final result = await exportService.exportToExcel();

        expect(result, isNotNull);
        expect(result.length, greaterThan(0));
      });

      test('handles large datasets efficiently', () async {
        final largeDataset = List.generate(
          1000,
          (i) => Product(
            id: i,
            name: 'Product $i',
            sku: 'SKU$i',
            costCents: Decimal.parse('${i * 100}'),
            priceCents: Decimal.parse('${i * 150}'),
            stockQuantity: i,
            minQuantity: i ~/ 10,
            hasVariants: false,
            isTaxable: false,
            purchaseTaxRateBps: 0,
            salesTaxRateBps: 0,
            isActive: true,
            trackInventory: true,
          ),
        );

        when(() => mockProductRepository.fetchProductsForExport(
              categoryId: any(named: 'categoryId'),
              supplierId: any(named: 'supplierId'),
              activeOnly: any(named: 'activeOnly'),
              limit: any(named: 'limit'),
              offset: any(named: 'offset'),
            )).thenAnswer((_) async => largeDataset);

        final stopwatch = Stopwatch()..start();
        final result = await exportService.exportToExcel();
        stopwatch.stop();

        expect(result, isNotNull);
        expect(result.length, greaterThan(0));
        expect(stopwatch.elapsedMilliseconds, lessThan(5000)); // < 5 seconds for 1k products
      });
    });

    group('getExportPreview', () {
      test('returns first 10 products', () async {
        final products = List.generate(
          50,
          (i) => Product(
            id: i,
            name: 'Product $i',
            sku: 'SKU$i',
            costCents: Decimal.parse('${i * 100}'),
            priceCents: Decimal.parse('${i * 150}'),
            stockQuantity: i,
            minQuantity: i ~/ 10,
            hasVariants: false,
            isTaxable: false,
            purchaseTaxRateBps: 0,
            salesTaxRateBps: 0,
            isActive: true,
            trackInventory: true,
          ),
        );

        when(() => mockProductRepository.fetchProductsForExport(
              categoryId: any(named: 'categoryId'),
              supplierId: any(named: 'supplierId'),
              activeOnly: any(named: 'activeOnly'),
              limit: 10,
              offset: 0,
            )).thenAnswer((_) async => products.take(10).toList());

        final result = await exportService.getExportPreview();

        expect(result.length, equals(10));
        verify(() => mockProductRepository.fetchProductsForExport(
              categoryId: any(named: 'categoryId'),
              supplierId: any(named: 'supplierId'),
              activeOnly: any(named: 'activeOnly'),
              limit: 10,
              offset: 0,
            )).called(1);
      });
    });
  });
}
