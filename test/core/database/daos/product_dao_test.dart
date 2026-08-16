import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:decimal/decimal.dart';
import 'package:tapix/core/database/app_database.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
  });

  tearDown(() async {
    await database.close();
  });

  group('ProductDao', () {
    test('watchAllProducts returns only active products', () async {
      final currencies = await database.select(database.currencies).get();
      final currencyId = currencies.first.id;

      await database
          .into(database.products)
          .insert(
            ProductsCompanion.insert(
              sku: const Value<String?>('ACTIVE-001'),
              name: 'Active Product',
              costCents: Decimal.fromInt(10),
              priceCents: Decimal.fromInt(20),
              currencyId: Value(currencyId),
              isActive: const Value(true),
            ),
          );

      await database
          .into(database.products)
          .insert(
            ProductsCompanion.insert(
              sku: const Value<String?>('INACTIVE-001'),
              name: 'Inactive Product',
              costCents: Decimal.fromInt(10),
              priceCents: Decimal.fromInt(20),
              currencyId: Value(currencyId),
              isActive: const Value(false),
            ),
          );

      final products = await database.productDao.watchAllProducts().first;

      expect(products.length, equals(1));
      expect(products.first.sku, equals('ACTIVE-001'));
    });

    test('searchProducts finds products by name or SKU', () async {
      final currencies = await database.select(database.currencies).get();
      final currencyId = currencies.first.id;

      await database
          .into(database.products)
          .insert(
            ProductsCompanion.insert(
              sku: const Value<String?>('SEARCH-001'),
              name: 'Laptop Computer',
              costCents: Decimal.fromInt(500),
              priceCents: Decimal.fromInt(1000),
              currencyId: Value(currencyId),
            ),
          );

      await database
          .into(database.products)
          .insert(
            ProductsCompanion.insert(
              sku: const Value<String?>('SEARCH-002'),
              name: 'Desktop Computer',
              costCents: Decimal.fromInt(600),
              priceCents: Decimal.fromInt(1200),
              currencyId: Value(currencyId),
            ),
          );

      final resultsByName = await database.productDao.searchProducts(
        'Computer',
      );
      expect(resultsByName.length, equals(2));

      final resultsBySku = await database.productDao.searchProducts(
        'SEARCH-001',
      );
      expect(resultsBySku.length, equals(1));
      expect(resultsBySku.first.name, equals('Laptop Computer'));
    });

    test('findBySku returns correct product', () async {
      final currencies = await database.select(database.currencies).get();
      final currencyId = currencies.first.id;

      await database
          .into(database.products)
          .insert(
            ProductsCompanion.insert(
              sku: const Value<String?>('UNIQUE-SKU'),
              name: 'Unique Product',
              costCents: Decimal.fromInt(10),
              priceCents: Decimal.fromInt(20),
              currencyId: Value(currencyId),
            ),
          );

      final product = await database.productDao.findBySku('UNIQUE-SKU');

      expect(product, isNotNull);
      expect(product!.name, equals('Unique Product'));
    });

    test('createProduct inserts new product', () async {
      final currencies = await database.select(database.currencies).get();
      final currencyId = currencies.first.id;

      final productId = await database.productDao.createProduct(
        ProductsCompanion.insert(
          sku: const Value<String?>('NEW-PRODUCT'),
          name: 'New Product',
          costCents: Decimal.fromInt(15),
          priceCents: Decimal.fromInt(30),
          currencyId: Value(currencyId),
        ),
      );

      expect(productId, greaterThan(0));

      final product = await database.productDao.watchProduct(productId).first;
      expect(product, isNotNull);
      expect(product!.sku, equals('NEW-PRODUCT'));
    });

    test('watchProductVariants returns variants for product', () async {
      final currencies = await database.select(database.currencies).get();
      final currencyId = currencies.first.id;

      // Create two sizes so each variant has a distinct (product_id, color_id, size_id) tuple
      final sizeId1 = await database
          .into(database.sizes)
          .insert(
            SizesCompanion.insert(name: 'Small', sortOrder: const Value(1)),
          );
      final sizeId2 = await database
          .into(database.sizes)
          .insert(
            SizesCompanion.insert(name: 'Medium', sortOrder: const Value(2)),
          );

      final productId = await database
          .into(database.products)
          .insert(
            ProductsCompanion.insert(
              sku: const Value<String?>('VAR-PRODUCT'),
              name: 'Product with Variants',
              costCents: Decimal.fromInt(10),
              priceCents: Decimal.fromInt(20),
              currencyId: Value(currencyId),
              hasVariants: const Value(true),
            ),
          );

      await database
          .into(database.productVariants)
          .insert(
            ProductVariantsCompanion.insert(
              productId: productId,
              sku: const Value<String?>('VAR-001'),
              sizeId: Value(sizeId1),
              costCents: Decimal.fromInt(0),
              priceCents: Decimal.fromInt(0),
            ),
          );

      await database
          .into(database.productVariants)
          .insert(
            ProductVariantsCompanion.insert(
              productId: productId,
              sku: const Value<String?>('VAR-002'),
              sizeId: Value(sizeId2),
              costCents: Decimal.fromInt(0),
              priceCents: Decimal.fromInt(0),
            ),
          );

      final variants = await database.productDao
          .watchProductVariants(productId)
          .first;

      expect(variants.length, equals(2));
    });

    test(
      'inventory lock detects negative stock on inactive variants',
      () async {
        final productId = await database
            .into(database.products)
            .insert(
              ProductsCompanion.insert(
                name: 'Negative legacy stock',
                costCents: Decimal.fromInt(10),
                priceCents: Decimal.fromInt(20),
                hasVariants: const Value(true),
              ),
            );
        await database
            .into(database.productVariants)
            .insert(
              ProductVariantsCompanion.insert(
                productId: productId,
                costCents: Decimal.fromInt(10),
                priceCents: Decimal.fromInt(20),
                stockQuantity: const Value(-1000),
                isActive: const Value(false),
              ),
            );

        expect(
          await database.productDao.getCostingMethodLockReason(productId),
          'has_stock',
        );
      },
    );

    test(
      'unit and tracking stay locked after stock history is at zero',
      () async {
        final currencyId =
            (await database.select(database.currencies).get()).first.id;
        final productId = await database
            .into(database.products)
            .insert(
              ProductsCompanion.insert(
                name: 'Historical product',
                costCents: Decimal.fromInt(10),
                priceCents: Decimal.fromInt(20),
              ),
            );
        await database.customStatement(
          'INSERT INTO inventory_adjustments '
          '(adjustment_number, product_id, adjustment_type, quantity_delta, '
          'unit_cost_cents, total_value_cents, reason, currency_id) '
          "VALUES ('LOCK-1', ?, 'revaluation', 0, 10, 0, 'history', ?)",
          [productId, currencyId],
        );

        expect(
          await database.productDao.getCostingMethodLockReason(productId),
          'has_transactions',
        );
        expect(
          await database.productDao.setMeasurementType(
            productId: productId,
            measurementType: 'weight',
          ),
          'has_transactions',
        );
        expect(
          await database.productDao.setTrackInventory(
            productId: productId,
            trackInventory: false,
          ),
          'has_transactions',
        );

        final persisted = await database.productDao.getProductById(productId);
        expect(persisted!.measurementType, 'piece');
        expect(persisted.trackInventory, isTrue);
      },
    );
  });
}
