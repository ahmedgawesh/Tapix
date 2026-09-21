import 'dart:async';
import 'package:csv/csv.dart';
import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/database/daos/inventory_adjustment_dao.dart';
import 'package:tapix/core/database/migrations/business_warehouse_stock.dart';
import 'package:tapix/core/services/business/warehouse_catalog_scope.dart';
import 'package:tapix/core/services/audit_log_service.dart';
import 'package:tapix/core/services/inventory/inventory_adjustment_service.dart';
import 'package:tapix/core/services/journal_entry_service.dart';
import 'package:tapix/features/accounting/data/repositories/accounting_repository.dart';
import 'package:tapix/features/auth/data/services/session_service.dart';
import 'package:tapix/features/products/data/datasources/product_local_datasource.dart';
import 'package:tapix/features/products/data/datasources/variant_local_datasource.dart';
import 'package:tapix/features/products/data/repositories/product_repository_impl.dart';
import 'package:tapix/features/products/data/repositories/product_variant_repository_impl.dart';
import 'package:tapix/features/products/data/repositories/category_repository_impl.dart';
import 'package:tapix/features/products/services/export_service.dart';
import 'package:tapix/features/products/services/export_stock_reader.dart';
import 'business_foundation_test.dart' as fixtures;

void main() {
  late AppDatabase db;
  late ExportServiceImpl exporter;
  late int simple, multiple, simpleVariant, extraVariant;
  late String primary;
  setUp(() async {
    db = fixtures.memoryDb();
    await fixtures.seedLegacyData(db);
    final products = await (db.select(
      db.products,
    )..orderBy([(p) => OrderingTerm.asc(p.id)])).get();
    simple = products.first.id;
    multiple = products.last.id;
    simpleVariant = (await db.productVariantDao.getVariantsByProduct(
      simple,
    )).single.id;
    final size = await db.customInsert(
      "INSERT INTO sizes(name) VALUES ('Optional dimension')",
    );
    await db.customStatement(
      'UPDATE product_variants SET size_id = ? WHERE id = ?',
      [size, simpleVariant],
    );
    await db.customStatement(
      'UPDATE products SET has_variants = 1 WHERE id = ?',
      [multiple],
    );
    extraVariant = await db
        .into(db.productVariants)
        .insert(
          ProductVariantsCompanion.insert(
            productId: multiple,
            sizeId: Value(size),
            costCents: Decimal.fromInt(900),
            priceCents: Decimal.fromInt(1500),
            stockQuantity: const Value(200),
          ),
        );
    final context = await db.select(db.businessContexts).getSingle();
    primary = context.warehouseId;
    const remote = '00000000-0000-4000-8000-000000000088';
    await db
        .into(db.businessWarehouses)
        .insert(
          BusinessWarehousesCompanion.insert(
            id: remote,
            organizationId: context.organizationId,
            branchId: context.branchId,
            code: 'REMOTE',
          ),
        );
    for (final variant in await db.select(db.productVariants).get()) {
      await db
          .into(db.businessWarehouseStocks)
          .insert(
            BusinessWarehouseStocksCompanion.insert(
              warehouseId: remote,
              variantId: variant.id,
              quantity: const Value(9000),
              unitCostCents: const Value(9900),
            ),
          );
    }
    // Deliberately stale compatibility mirrors: reads must still use warehouse rows.
    await removeBusinessWarehouseStockTriggers(db);
    await db.customStatement(
      'UPDATE products SET stock_quantity = 9999, cost_cents = 8888',
    );
    await db.customStatement(
      'UPDATE product_variants SET stock_quantity = 7777, cost_cents = 6666',
    );
    final journal = JournalEntryService(AccountingRepository(db));
    exporter = ExportServiceImpl(
      ProductRepositoryImpl(
        ProductLocalDatasourceImpl(db.productDao),
        AuditLogService(db),
        SessionService(),
      ),
      ProductVariantRepositoryImpl(
        VariantLocalDatasourceImpl(
          db.productVariantDao,
          db.productColorDao,
          db.sizeDao,
        ),
        InventoryAdjustmentService(
          db: db,
          dao: InventoryAdjustmentDao(db),
          journal: journal,
        ),
      ),
      CategoryRepositoryImpl(db),
      WarehouseExportStockReader(db),
    );
  });
  tearDown(() => db.close());

  test(
    'catalog projects simple optional variant and variant aggregates without changing mirrors',
    () async {
      final before = await fixtures.legacySnapshot(db);
      final rows = await WarehouseCatalogScope.readProducts(db, [
        simple,
        multiple,
      ]);
      expect(rows.singleWhere((p) => p.id == simple).stockQuantity, 1234);
      expect(
        rows.singleWhere((p) => p.id == simple).costCents,
        Decimal.fromInt(701),
      );
      expect(rows.singleWhere((p) => p.id == multiple).stockQuantity, 1434);
      expect(
        rows.singleWhere((p) => p.id == multiple).costCents,
        Decimal.fromInt(729),
      );
      expect(await fixtures.legacySnapshot(db), before);
    },
  );
  test(
    'CSV exports primary balances and carrying cost for every row',
    () async {
      final rows = const CsvDecoder().convert(await exporter.exportToCSV());
      final header = rows.first;
      final id = header.indexOf('product_id');
      final qty = header.indexOf('stock_quantity');
      final cost = header.indexOf('cost_cents');
      expect(rows.length, 4);
      final simpleRow = rows
          .skip(1)
          .singleWhere((r) => r[id].toString() == '$simple');
      expect(simpleRow[qty].toString(), '1234');
      expect(simpleRow[cost].toString(), '701');
      final others = rows.skip(1).where((r) => r[id].toString() == '$multiple');
      expect(
        others.map((r) => r[qty].toString()),
        unorderedEquals(['1234', '200']),
      );
      expect(
        others.map((r) => r[cost].toString()),
        unorderedEquals(['701', '900']),
      );
    },
  );
  test('Excel matches CSV warehouse quantities and costs', () async {
    final workbook = Excel.decodeBytes(await exporter.exportToExcel());
    final rows = workbook.tables.values.firstWhere((t) => t.maxRows > 0).rows;
    expect(rows.length, 4);
    expect(
      rows.skip(1).map((r) => (r[11]!.value as IntCellValue).value),
      unorderedEquals([1234, 1234, 200]),
    );
    expect(
      rows.skip(1).map((r) => (r[8]!.value as IntCellValue).value),
      unorderedEquals([701, 701, 900]),
    );
  });
  test(
    'preview and realtime export list update on warehouse-only changes',
    () async {
      expect(
        (await exporter.getExportPreview())
            .singleWhere((p) => p.id == simple)
            .stockQuantity,
        1234,
      );
      final stream = StreamIterator(exporter.watchProducts());
      addTearDown(stream.cancel);
      await stream.moveNext();
      await (db.update(db.businessWarehouseStocks)..where(
            (s) =>
                s.warehouseId.equals(primary) &
                s.variantId.equals(simpleVariant),
          ))
          .write(const BusinessWarehouseStocksCompanion(quantity: Value(42)));
      expect(
        await stream.moveNext().timeout(const Duration(seconds: 5)),
        isTrue,
      );
      expect(
        stream.current.singleWhere((p) => p.id == simple).stockQuantity,
        42,
      );
    },
  );
  test('disabled warehouse keeps export history', () async {
    await (db.update(db.businessWarehouses)..where((w) => w.id.equals(primary)))
        .write(const BusinessWarehousesCompanion(isActive: Value(false)));
    expect(
      (await exporter.getExportPreview())
          .singleWhere((p) => p.id == simple)
          .stockQuantity,
      1234,
    );
  });
  test('missing primary balance refuses catalog and both file formats', () async {
    await db.customStatement(
      'DELETE FROM business_warehouse_stocks WHERE warehouse_id = ? AND variant_id = ?',
      [primary, simpleVariant],
    );
    await expectLater(
      WarehouseCatalogScope.readProducts(db, [simple]),
      throwsStateError,
    );
    await expectLater(exporter.exportToCSV(), throwsStateError);
    await expectLater(exporter.exportToExcel(), throwsStateError);
  });
  test(
    'multiple active variants on a simple product are not guessed',
    () async {
      await db.customStatement(
        'UPDATE products SET has_variants = 0 WHERE id = ?',
        [multiple],
      );
      await expectLater(exporter.exportToCSV(), throwsStateError);
      await expectLater(exporter.exportToExcel(), throwsStateError);
    },
  );
  test(
    'inactive variant export still reads its own warehouse balance',
    () async {
      await db.customStatement(
        'UPDATE product_variants SET is_active = 0 WHERE id = ?',
        [extraVariant],
      );
      final rows = await WarehouseCatalogScope.readVariants(db, [extraVariant]);
      expect(rows.single.stockQuantity, 200);
      expect(rows.single.costCents, Decimal.fromInt(900));
      expect(
        (await WarehouseCatalogScope.readProducts(db, [
          multiple,
        ])).single.stockQuantity,
        1234,
      );
    },
  );
  test(
    'legacy product without any operational variant retains explicit fallback',
    () async {
      final id = await db.customInsert(
        "INSERT INTO products(name, cost_cents, price_cents, stock_quantity) VALUES ('Legacy no variant', 321, 500, 7)",
      );
      final row = (await WarehouseCatalogScope.readProducts(db, [id])).single;
      expect(row.stockQuantity, 7);
      expect(row.costCents, Decimal.fromInt(321));
    },
  );
}
