import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart';
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

  group('Database Migration', () {
    test('creates all tables successfully', () async {
      final tables = await database.customSelect("SELECT name FROM sqlite_master WHERE type = 'table'").get();
      final tableNames = tables.map((row) => row.read<String>('name')).toList();
      
      expect(tableNames, contains('currencies'));
      expect(tableNames, contains('products'));
      expect(tableNames, contains('customers'));
      expect(tableNames, contains('sales'));
      expect(tableNames, contains('accounts'));
      expect(tableNames, contains('journal_entries'));
    });

    test('creates indexes successfully', () async {
      final indexes = await database.customSelect("SELECT name FROM sqlite_master WHERE type = 'index'").get();
      final indexNames = indexes.map((row) => row.read<String>('name')).toList();
      
      expect(indexNames, contains('idx_sales_customer_date'));
      expect(indexNames, contains('idx_products_active'));
      expect(indexNames, contains('idx_sale_items_sale'));
      expect(indexNames, contains('idx_journal_entry_date'));
      expect(indexNames, contains('idx_audit_table_record'));
    });

    test('seeds initial currencies', () async {
      final currencies = await database.select(database.currencies).get();
      
      expect(currencies.length, greaterThanOrEqualTo(3));
      expect(currencies.any((c) => c.code == 'USD'), isTrue);
      expect(currencies.any((c) => c.code == 'EUR'), isTrue);
      expect(currencies.any((c) => c.code == 'DZD'), isTrue);
      
      final baseCurrency = currencies.firstWhere((c) => c.isBase);
      expect(baseCurrency.code, equals('USD'));
    });

    test('seeds initial accounts', () async {
      final accounts = await database.select(database.accounts).get();
      
      expect(accounts.length, greaterThanOrEqualTo(6));
      expect(accounts.any((a) => a.accountCode == '1000'), isTrue);
      expect(accounts.any((a) => a.accountCode == '4000'), isTrue);
    });

    test('seeds initial settings', () async {
      final settings = await database.select(database.appSettings).get();
      
      expect(settings.length, greaterThanOrEqualTo(2));
      expect(settings.any((s) => s.key == 'app_version'), isTrue);
      expect(settings.any((s) => s.key == 'default_currency_id'), isTrue);
    });
  });

  group('Idempotency', () {
    test('seeding can be safely re-run without creating duplicates', () async {
      await database.seedInitialDataForTest();

      final currencies1 = await database.select(database.currencies).get();
      final accounts1 = await database.select(database.accounts).get();
      final settings1 = await database.select(database.appSettings).get();

      await database.seedInitialDataForTest();

      final currencies2 = await database.select(database.currencies).get();
      final accounts2 = await database.select(database.accounts).get();
      final settings2 = await database.select(database.appSettings).get();

      expect(currencies2.length, equals(currencies1.length));
      expect(accounts2.length, equals(accounts1.length));
      expect(settings2.length, equals(settings1.length));
    });

    test('index creation can be safely re-run', () async {
      await database.createIndexesForTest();
      await database.createIndexesForTest();

      final indexes = await database.customSelect("SELECT name FROM sqlite_master WHERE type = 'index'").get();
      final indexNames = indexes.map((row) => row.read<String>('name')).toList();

      expect(indexNames, contains('idx_sales_customer_date'));
      expect(indexNames, contains('idx_products_active'));
    });
  });

  group('Foreign Key Constraints', () {
    test('enforces CASCADE on sale items when sale is deleted', () async {
      final currencyId = await database.into(database.currencies).insert(
        CurrenciesCompanion.insert(
          code: 'TST',
          name: 'Test Currency',
          symbol: 'T',
          exchangeRate: Decimal.fromInt(1),
        ),
      );

      final productId = await database.into(database.products).insert(
        ProductsCompanion.insert(
          sku: const Value<String?>('TEST-001'),
          name: 'Test Product',
          costCents: Decimal.fromInt(10),
          priceCents: Decimal.fromInt(20),
          currencyId: Value(currencyId),
        ),
      );

      final saleId = await database.into(database.sales).insert(
        SalesCompanion.insert(
          invoiceNumber: 'INV-001',
          subtotalCents: Decimal.fromInt(20),
          taxCents: Decimal.zero,
          totalCents: Decimal.fromInt(20),
          currencyId: currencyId,
          paymentMethod: 'cash',
        ),
      );

      await database.into(database.saleItems).insert(
        SaleItemsCompanion.insert(
          saleId: saleId,
          productId: productId,
          quantity: 1,
          unitPriceCents: Decimal.fromInt(20),
          subtotalCents: Decimal.fromInt(20),
          totalCents: Decimal.fromInt(20),
        ),
      );

      await (database.delete(database.sales)..where((s) => s.id.equals(saleId))).go();

      final remainingItems = await (database.select(database.saleItems)
            ..where((i) => i.saleId.equals(saleId)))
          .get();
      
      expect(remainingItems, isEmpty);
    });

    test('enforces RESTRICT on products when referenced by sale items', () async {
      final currencyId = await database.into(database.currencies).insert(
        CurrenciesCompanion.insert(
          code: 'TST',
          name: 'Test Currency',
          symbol: 'T',
          exchangeRate: Decimal.fromInt(1),
        ),
      );

      final productId = await database.into(database.products).insert(
        ProductsCompanion.insert(
          sku: const Value<String?>('TEST-002'),
          name: 'Test Product 2',
          costCents: Decimal.fromInt(10),
          priceCents: Decimal.fromInt(20),
          currencyId: Value(currencyId),
        ),
      );

      final saleId = await database.into(database.sales).insert(
        SalesCompanion.insert(
          invoiceNumber: 'INV-002',
          subtotalCents: Decimal.fromInt(20),
          taxCents: Decimal.zero,
          totalCents: Decimal.fromInt(20),
          currencyId: currencyId,
          paymentMethod: 'cash',
        ),
      );

      await database.into(database.saleItems).insert(
        SaleItemsCompanion.insert(
          saleId: saleId,
          productId: productId,
          quantity: 1,
          unitPriceCents: Decimal.fromInt(20),
          subtotalCents: Decimal.fromInt(20),
          totalCents: Decimal.fromInt(20),
        ),
      );

      expect(
        () => (database.delete(database.products)..where((p) => p.id.equals(productId))).go(),
        throwsA(isA<SqliteException>()),
      );
    });
  });

  group('Money Math Precision', () {
    test('stores and retrieves money values accurately', () async {
      final currencyId = await database.into(database.currencies).insert(
        CurrenciesCompanion.insert(
          code: 'TST',
          name: 'Test Currency',
          symbol: 'T',
          exchangeRate: Decimal.fromInt(1),
        ),
      );

      final testAmount = Decimal.fromInt(12345);
      final productId = await database.into(database.products).insert(
        ProductsCompanion.insert(
          sku: const Value<String?>('TEST-003'),
          name: 'Test Product 3',
          costCents: testAmount,
          priceCents: testAmount,
          currencyId: Value(currencyId),
        ),
      );

      final product = await (database.select(database.products)
            ..where((p) => p.id.equals(productId)))
          .getSingle();

      expect(product.costCents, equals(testAmount));
      expect(product.priceCents, equals(testAmount));
    });

    test('handles complex money calculations without precision loss', () async {
      final priceCents = 1999;
      const quantity = 3;
      const taxRateBps = 1900;

      final subtotalCents = priceCents * quantity;
      final taxCents = (subtotalCents * taxRateBps) ~/ 10000;
      final totalCents = subtotalCents + taxCents;

      expect(subtotalCents, equals(5997));
      expect(taxCents, equals(1139));
      expect(totalCents, equals(7136));
    });
  });

  group('Performance Benchmarks', () {
    test('product lookup completes in under 50ms', () async {
      final currencyId = await database.into(database.currencies).insert(
        CurrenciesCompanion.insert(
          code: 'TST',
          name: 'Test Currency',
          symbol: 'T',
          exchangeRate: Decimal.fromInt(1),
        ),
      );

      for (int i = 0; i < 100; i++) {
        await database.into(database.products).insert(
          ProductsCompanion.insert(
            sku: Value<String?>('SKU-$i'),
            name: 'Product $i',
            costCents: Decimal.fromInt(10),
            priceCents: Decimal.fromInt(20),
            currencyId: Value(currencyId),
          ),
        );
      }

      final stopwatch = Stopwatch()..start();
      await (database.select(database.products)
            ..where((p) => p.sku.equals('SKU-50')))
          .getSingle();
      stopwatch.stop();

      expect(stopwatch.elapsedMilliseconds, lessThan(50));
    });

    test('sale insertion completes in under 100ms', () async {
      final currencyId = await database.into(database.currencies).insert(
        CurrenciesCompanion.insert(
          code: 'TST',
          name: 'Test Currency',
          symbol: 'T',
          exchangeRate: Decimal.fromInt(1),
        ),
      );

      final productId = await database.into(database.products).insert(
        ProductsCompanion.insert(
          sku: const Value<String?>('PERF-001'),
          name: 'Performance Test Product',
          costCents: Decimal.fromInt(10),
          priceCents: Decimal.fromInt(20),
          currencyId: Value(currencyId),
        ),
      );

      final stopwatch = Stopwatch()..start();
      
      final saleId = await database.into(database.sales).insert(
        SalesCompanion.insert(
          invoiceNumber: 'PERF-INV-001',
          subtotalCents: Decimal.fromInt(20),
          taxCents: Decimal.zero,
          totalCents: Decimal.fromInt(20),
          currencyId: currencyId,
          paymentMethod: 'cash',
        ),
      );

      await database.into(database.saleItems).insert(
        SaleItemsCompanion.insert(
          saleId: saleId,
          productId: productId,
          quantity: 1,
          unitPriceCents: Decimal.fromInt(20),
          subtotalCents: Decimal.fromInt(20),
          totalCents: Decimal.fromInt(20),
        ),
      );

      stopwatch.stop();

      expect(stopwatch.elapsedMilliseconds, lessThan(100));
    });
  });
}
