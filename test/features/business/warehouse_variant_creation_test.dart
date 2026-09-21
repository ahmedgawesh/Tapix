import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/database/daos/inventory_adjustment_dao.dart';
import 'package:tapix/core/services/inventory/inventory_adjustment_service.dart';
import 'package:tapix/core/services/journal_entry_service.dart';
import 'package:tapix/features/accounting/data/repositories/accounting_repository.dart';
import 'package:tapix/features/products/data/datasources/variant_local_datasource.dart';
import 'package:tapix/features/products/data/repositories/product_variant_repository_impl.dart';

import 'business_foundation_test.dart' as fixtures;

void main() {
  late AppDatabase db;
  late ProductVariantRepositoryImpl repo;
  late int product;
  setUp(() async {
    db = fixtures.memoryDb();
    await db.customSelect('SELECT 1').get();
    await db.customStatement(
      "INSERT INTO users (id, username, password_hash, role, is_active, created_at, updated_at) VALUES (0, 'system', 'no-pin', 'owner', 1, 0, 0)",
    );
    product = await db.customInsert(
      "INSERT INTO products (name, cost_cents, price_cents) VALUES ('Opening', 500, 1000)",
    );
    repo = ProductVariantRepositoryImpl(
      VariantLocalDatasourceImpl(
        db.productVariantDao,
        db.productColorDao,
        db.sizeDao,
      ),
      InventoryAdjustmentService(
        db: db,
        dao: InventoryAdjustmentDao(db),
        journal: JournalEntryService(AccountingRepository(db)),
      ),
    );
  });
  tearDown(() => db.close());

  Future<int> create({int quantity = 4, bool ensure = false, int? size}) =>
      ensure
      ? repo.ensureDefaultVariantForProduct(
          productId: product,
          costCents: Decimal.fromInt(500),
          priceCents: Decimal.fromInt(1000),
          stockQuantity: quantity,
        )
      : repo.createVariant(
          productId: product,
          sizeId: size,
          costCents: Decimal.fromInt(500),
          priceCents: Decimal.fromInt(1000),
          stockQuantity: quantity,
        );

  Future<List<Map<String, Object?>>> balances() async =>
      (await db.customSelect('SELECT * FROM business_warehouse_stocks').get())
          .map((r) => r.data)
          .toList();

  for (final ensure in [false, true]) {
    for (final failure in ['barcode', 'journal']) {
      test('$ensure rolls back complete creation on $failure failure', () async {
        final size = await db.customInsert(
          "INSERT INTO sizes (name) VALUES ('Large')",
        );
        final before = await fixtures.legacySnapshot(db);
        final stockBefore = await balances();
        final target = failure == 'barcode'
            ? 'BEFORE UPDATE OF barcode ON product_variants'
            : 'BEFORE INSERT ON journal_entry_lines';
        await db.customStatement(
          "CREATE TRIGGER reject_creation $target BEGIN SELECT RAISE(ABORT, 'injected failure'); END",
        );
        await expectLater(
          create(ensure: ensure, size: size),
          throwsA(anything),
        );
        expect(await fixtures.legacySnapshot(db), before);
        expect(await balances(), stockBefore);
        expect((await db.select(db.businessDocumentLocations).get()), isEmpty);
      });
    }
    test('$ensure rejects negative opening stock before writes', () async {
      final before = await fixtures.legacySnapshot(db);
      await expectLater(
        create(quantity: -1, ensure: ensure),
        throwsArgumentError,
      );
      expect(await fixtures.legacySnapshot(db), before);
    });
  }

  test('opening stock and balanced inventory journal commit once', () async {
    final id = await create(ensure: true);
    expect(await create(ensure: true), id);
    final stock = await db.select(db.businessWarehouseStocks).getSingle();
    expect(stock.quantity, 4);
    expect(stock.unitCostCents, 500);
    final row = await db
        .customSelect(
          'SELECT SUM(debit_cents) AS dr, SUM(credit_cents) AS cr FROM journal_entry_lines',
        )
        .getSingle();
    expect(row.read<int>('dr'), 2000);
    expect(row.read<int>('cr'), 2000);
    expect(await db.select(db.inventoryAdjustments).get(), hasLength(1));
  });

  test('zero opening stock creates a usable barcode without journal', () async {
    final id = await create(quantity: 0);
    final variant = await repo.getVariantById(id);
    expect(variant!.barcode, hasLength(13));
    expect(variant.stockQuantity, 0);
    expect(await db.select(db.journalEntries).get(), isEmpty);
  });

  test(
    'outer transaction still rolls back successful nested creation',
    () async {
      final before = await fixtures.legacySnapshot(db);
      await expectLater(
        db.transaction(() async {
          await create();
          throw StateError('outer failure');
        }),
        throwsStateError,
      );
      expect(await fixtures.legacySnapshot(db), before);
      expect(await balances(), isEmpty);
    },
  );
}
