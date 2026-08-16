import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:tapix/features/products/domain/entities/import_file_data.dart';
import 'package:tapix/features/products/domain/repositories/category_repository.dart';
import 'package:tapix/features/products/domain/repositories/product_repository.dart';
import 'package:tapix/features/products/domain/repositories/product_variant_repository.dart';
import 'package:tapix/features/products/services/product_import_service.dart';

class _MockProductRepository extends Mock implements ProductRepository {}

class _MockVariantRepository extends Mock implements ProductVariantRepository {}

class _MockCategoryRepository extends Mock implements CategoryRepository {}

void main() {
  late _MockProductRepository products;
  late _MockVariantRepository variants;
  late _MockCategoryRepository categories;
  late ProductImportService service;

  const mapping = ColumnMapping({'name': 0, 'price': 1, 'sku': 2});

  ImportFileData file(List<List<String>> rows) => ImportFileData(
    fileName: 'products.csv',
    fileType: ImportFileType.csv,
    headers: const ['name', 'price', 'sku'],
    rows: rows,
    totalRows: rows.length,
  );

  setUpAll(() {
    registerFallbackValue(Decimal.zero);
  });

  setUp(() {
    products = _MockProductRepository();
    variants = _MockVariantRepository();
    categories = _MockCategoryRepository();
    service = ProductImportService(products, variants, categories);

    when(() => categories.getAllCategories()).thenAnswer((_) async => []);
    when(() => variants.getAllColors()).thenAnswer((_) async => []);
    when(() => variants.getAllSizes()).thenAnswer((_) async => []);
    when(() => products.runInTransaction<void>(any())).thenAnswer((
      invocation,
    ) async {
      final action =
          invocation.positionalArguments.first as Future<void> Function();
      await action();
    });
    when(
      () => variants.ensureDefaultVariantForProduct(
        productId: any(named: 'productId'),
        costCents: any(named: 'costCents'),
        priceCents: any(named: 'priceCents'),
        stockQuantity: any(named: 'stockQuantity'),
      ),
    ).thenAnswer((_) async => 1);
    when(
      () => variants.getDefaultVariantByProduct(any()),
    ).thenAnswer((_) async => null);
  });

  test('a parse error prevents every database write', () async {
    final result = await service(
      fileData: file([
        ['Valid product', '10.00', 'VALID-1'],
        ['Broken product', '', 'BROKEN-1'],
      ]),
      columnMapping: mapping,
    );

    expect(result.successfulRows, 0);
    expect(result.failedRows, 2);
    expect(result.rowToProductId, isEmpty);
    verifyNever(() => products.runInTransaction<void>(any()));
    verifyNever(
      () => products.createProduct(
        name: any(named: 'name'),
        costCents: any(named: 'costCents'),
        priceCents: any(named: 'priceCents'),
        stockQuantity: any(named: 'stockQuantity'),
        minQuantity: any(named: 'minQuantity'),
      ),
    );
  });

  test(
    'a persistence failure reports zero committed rows after rollback',
    () async {
      var calls = 0;
      when(
        () => products.createProduct(
          name: any(named: 'name'),
          description: any(named: 'description'),
          sku: any(named: 'sku'),
          barcode: any(named: 'barcode'),
          costCents: any(named: 'costCents'),
          priceCents: any(named: 'priceCents'),
          wholesalePriceCents: any(named: 'wholesalePriceCents'),
          stockQuantity: any(named: 'stockQuantity'),
          minQuantity: any(named: 'minQuantity'),
          categoryId: any(named: 'categoryId'),
          hasVariants: any(named: 'hasVariants'),
          isTaxable: any(named: 'isTaxable'),
          isActive: any(named: 'isActive'),
          trackInventory: any(named: 'trackInventory'),
        ),
      ).thenAnswer((_) async {
        calls++;
        if (calls == 2) throw Exception('second product failed');
        return 101;
      });

      final result = await service(
        fileData: file([
          ['First product', '10.00', 'FIRST-1'],
          ['Second product', '20.00', 'SECOND-1'],
        ]),
        columnMapping: mapping,
      );

      expect(result.successfulRows, 0);
      expect(result.failedRows, 2);
      expect(result.rowToProductId, isEmpty);
      expect(result.errors.map((e) => e.rowIndex).toSet(), {0, 1});
      verify(() => products.runInTransaction<void>(any())).called(1);
    },
  );
}
