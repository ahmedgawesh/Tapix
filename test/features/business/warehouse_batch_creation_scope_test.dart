import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/database/migrations/business_document_locations.dart';
import 'package:tapix/core/services/batch_service.dart';
import 'package:tapix/core/services/business/warehouse_operation_scope.dart';
import 'package:uuid/uuid.dart';
import 'business_foundation_test.dart' as fixtures;

void main() {
  late AppDatabase db;
  late int product, variant;
  late WarehouseOperationScope selected;
  setUp(() async {
    db = fixtures.memoryDb();
    await fixtures.seedLegacyData(db);
    final row = await db
        .customSelect('SELECT product_id, variant_id FROM product_batches')
        .getSingle();
    product = row.read<int>('product_id');
    variant = row.read<int>('variant_id');
    final primary = await WarehouseOperationScope.resolve(db);
    final other = const Uuid().v4();
    await db
        .into(db.businessWarehouses)
        .insert(
          BusinessWarehousesCompanion.insert(
            id: other,
            organizationId: primary.organizationId,
            branchId: primary.branchId,
            code: 'CREATION',
          ),
        );
    selected = await WarehouseOperationScope.resolve(db, warehouseId: other);
  });
  tearDown(() => db.close());
  Future<int> create({WarehouseOperationScope? scope}) =>
      BatchService.createOpeningBatch(
        db.purchaseDao,
        productId: product,
        variantId: variant,
        quantity: 10,
        unitCostCents: 321,
        source: 'opening',
        scope: scope,
      );

  test(
    'creation assigns secondary location atomically without changing default context',
    () async {
      final primary = await WarehouseOperationScope.resolve(db);
      final id = await create(scope: selected);
      final batch = await (db.select(
        db.productBatches,
      )..where((b) => b.id.equals(id))).getSingle();
      final location =
          await (db.select(db.businessDocumentLocations)..where(
                (l) =>
                    l.sourceTable.equals('product_batches') &
                    l.sourceId.equals(id),
              ))
              .getSingle();
      expect(batch.warehouseId, selected.warehouseId);
      expect(location.warehouseId, selected.warehouseId);
      expect(location.branchId, selected.branchId);
      expect(
        (await WarehouseOperationScope.resolve(db)).warehouseId,
        primary.warehouseId,
      );
      final consumed = await BatchService.consumeFifo(
        db.saleDao,
        productId: product,
        variantId: variant,
        quantity: 5,
        consumptionType: 'sale',
        scope: selected,
      );
      expect(consumed.single.batchId, id);
      expect(consumed.single.unitCostCents, 321);
    },
  );

  test('creation without scope keeps primary routing', () async {
    final id = await create();
    final primary = await WarehouseOperationScope.resolve(db);
    final location =
        await (db.select(db.businessDocumentLocations)..where(
              (l) =>
                  l.sourceTable.equals('product_batches') &
                  l.sourceId.equals(id),
            ))
            .getSingle();
    expect(location.warehouseId, primary.warehouseId);
  });

  test('neither batch route nor historical location can be reassigned', () async {
    final id = await create(scope: selected);
    final primary = await WarehouseOperationScope.resolve(db);
    await expectLater(
      db.customStatement(
        'UPDATE product_batches SET warehouse_id = ? WHERE id = ?',
        [primary.warehouseId, id],
      ),
      throwsA(anything),
    );
    await expectLater(
      db.customStatement(
        'UPDATE product_batches SET warehouse_id = NULL WHERE id = ?',
        [id],
      ),
      throwsA(anything),
    );
    await expectLater(
      db.customStatement(
        "UPDATE business_document_locations SET warehouse_id = ? WHERE source_table = 'product_batches' AND source_id = ?",
        [primary.warehouseId, id],
      ),
      throwsA(anything),
    );
  });

  test('location insertion failure leaves neither batch nor metadata', () async {
    final before = await db.select(db.productBatches).get();
    final locations = await db.select(db.businessDocumentLocations).get();
    await db.customStatement(
      "CREATE TRIGGER fail_batch_location BEFORE INSERT ON business_document_locations WHEN NEW.source_table = 'product_batches' BEGIN SELECT RAISE(ABORT, 'injected'); END",
    );
    await expectLater(create(scope: selected), throwsA(anything));
    expect(await db.select(db.productBatches).get(), before);
    expect(await db.select(db.businessDocumentLocations).get(), locations);
  });

  test(
    'raw creation rejects inactive warehouse and rolls back source row',
    () async {
      await (db.update(db.businessWarehouses)
            ..where((w) => w.id.equals(selected.warehouseId)))
          .write(const BusinessWarehousesCompanion(isActive: Value(false)));
      final before = await db.select(db.productBatches).get();
      await expectLater(
        db.customStatement(
          "INSERT INTO product_batches (warehouse_id,product_id,variant_id,batch_number,source,received_date,received_quantity,remaining_quantity,unit_cost_cents) VALUES (?,?,?,'BAD','opening','2026-09-21',1,1,100)",
          [selected.warehouseId, product, variant],
        ),
        throwsA(anything),
      );
      expect(await db.select(db.productBatches).get(), before);
    },
  );

  test('secondary purchase batch rejects purchase source from primary', () async {
    final purchase = (await db.select(db.purchases).get()).single;
    final item = await db.customInsert(
      'INSERT INTO purchase_items (purchase_id, product_id, variant_id, quantity, unit_cost_cents, subtotal_cents, total_cents) VALUES (?, ?, ?, 10, 100, 1000, 1000)',
      variables: [
        Variable.withInt(purchase.id),
        Variable.withInt(product),
        Variable.withInt(variant),
      ],
    );
    final before = await db.select(db.productBatches).get();
    await expectLater(
      BatchService.createBatchFromPurchase(
        db.purchaseDao,
        productId: product,
        variantId: variant,
        purchaseItemId: item,
        quantity: 10,
        unitCostCents: 100,
        scope: selected,
      ),
      throwsStateError,
    );
    expect(await db.select(db.productBatches).get(), before);
  });

  test(
    '10087 file upgrade preserves old locations, quantities and costs',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'tapix-batch-route-',
      );
      final file = File('${directory.path}/legacy.db');
      final original = AppDatabase.connect(
        DatabaseConnection(NativeDatabase(file)),
      );
      try {
        await fixtures.seedLegacyData(original);
        final before =
            (await original
                    .customSelect(
                      'SELECT id, remaining_quantity, unit_cost_cents FROM product_batches',
                    )
                    .get())
                .map((r) => r.data)
                .toList();
        final locations = await original
            .select(original.businessDocumentLocations)
            .get();
        await removeBusinessDocumentLocationTriggers(original);
        await original.customStatement(
          'ALTER TABLE product_batches DROP COLUMN warehouse_id',
        );
        await original.close();
        final raw = sqlite.sqlite3.open(file.path);
        raw.execute('PRAGMA user_version = 10087');
        raw.execute('DROP INDEX business_locations_by_warehouse');
        raw.execute('CREATE VIEW business_locations_by_warehouse AS SELECT 1');
        raw.close();
        final failed = AppDatabase.connect(
          DatabaseConnection(NativeDatabase(file)),
        );
        try {
          await expectLater(
            failed.customSelect('SELECT 1').get(),
            throwsA(anything),
          );
        } finally {
          await failed.close();
        }
        final check = sqlite.sqlite3.open(file.path);
        try {
          expect(
            check.select('PRAGMA user_version').single['user_version'],
            10087,
          );
          expect(
            check
                .select('PRAGMA table_info(product_batches)')
                .any((r) => r['name'] == 'warehouse_id'),
            isFalse,
          );
          check.execute('DROP VIEW business_locations_by_warehouse');
        } finally {
          check.close();
        }
        final upgraded = AppDatabase.connect(
          DatabaseConnection(NativeDatabase(file)),
        );
        try {
          expect(
            (await upgraded
                    .customSelect(
                      'SELECT id, remaining_quantity, unit_cost_cents FROM product_batches',
                    )
                    .get())
                .map((r) => r.data)
                .toList(),
            before,
          );
          expect(
            await upgraded.select(upgraded.businessDocumentLocations).get(),
            locations,
          );
          expect(
            (await upgraded.customSelect('PRAGMA user_version').getSingle())
                .read<int>('user_version'),
            10091,
          );
          expect(
            await upgraded.customSelect('PRAGMA foreign_key_check').get(),
            isEmpty,
          );
          expect(
            (await upgraded.select(upgraded.productBatches).get()).every(
              (b) => b.warehouseId == null,
            ),
            isTrue,
          );
        } finally {
          await upgraded.close();
        }
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );
  test('10088 file upgrade preserves old locations, quantities and costs', () async {
    final directory = await Directory.systemTemp.createTemp(
      'tapix-adjust-route-',
    );
    final file = File('${directory.path}/legacy.db');
    final original = AppDatabase.connect(
      DatabaseConnection(NativeDatabase(file)),
    );
    try {
      await fixtures.seedLegacyData(original);

      await original.customStatement(
        'INSERT INTO inventory_adjustments '
        '(adjustment_number, product_id, adjustment_type, quantity_delta, '
        'unit_cost_cents, total_value_cents, reason, currency_id) '
        "SELECT 'LEGACY-ADJ', id, 'gain', 10, 701, 7, 'Historical fixture', currency_id "
        'FROM products ORDER BY id LIMIT 1',
      );
      final oldAdjustments =
          (await original
                  .customSelect(
                    'SELECT id, product_id, currency_id, quantity_delta, unit_cost_cents, total_value_cents FROM inventory_adjustments',
                  )
                  .get())
              .map((r) => r.data)
              .toList();
      final before =
          (await original
                  .customSelect(
                    'SELECT id, remaining_quantity, unit_cost_cents FROM product_batches',
                  )
                  .get())
              .map((r) => r.data)
              .toList();
      final locations = await original
          .select(original.businessDocumentLocations)
          .get();
      await removeBusinessDocumentLocationTriggers(original);
      await original.customStatement(
        'ALTER TABLE inventory_adjustments DROP COLUMN warehouse_id',
      );
      await original.close();
      final raw = sqlite.sqlite3.open(file.path);
      raw.execute('PRAGMA user_version = 10088');
      raw.execute('DROP INDEX business_locations_by_warehouse');
      raw.execute('CREATE VIEW business_locations_by_warehouse AS SELECT 1');
      raw.close();
      final failed = AppDatabase.connect(
        DatabaseConnection(NativeDatabase(file)),
      );
      try {
        await expectLater(
          failed.customSelect('SELECT 1').get(),
          throwsA(anything),
        );
      } finally {
        await failed.close();
      }
      final check = sqlite.sqlite3.open(file.path);
      try {
        expect(
          check.select('PRAGMA user_version').single['user_version'],
          10088,
        );
        expect(
          check
              .select('PRAGMA table_info(inventory_adjustments)')
              .any((r) => r['name'] == 'warehouse_id'),
          isFalse,
        );
        check.execute('DROP VIEW business_locations_by_warehouse');
      } finally {
        check.close();
      }
      final upgraded = AppDatabase.connect(
        DatabaseConnection(NativeDatabase(file)),
      );
      try {
        expect(
          (await upgraded
                  .customSelect(
                    'SELECT id, product_id, currency_id, quantity_delta, unit_cost_cents, total_value_cents FROM inventory_adjustments',
                  )
                  .get())
              .map((r) => r.data)
              .toList(),
          oldAdjustments,
        );
        expect(
          (await upgraded
                  .customSelect(
                    'SELECT id, remaining_quantity, unit_cost_cents FROM product_batches',
                  )
                  .get())
              .map((r) => r.data)
              .toList(),
          before,
        );
        expect(
          await upgraded.select(upgraded.businessDocumentLocations).get(),
          locations,
        );
        expect(
          (await upgraded.customSelect('PRAGMA user_version').getSingle())
              .read<int>('user_version'),
          10091,
        );
        expect(
          await upgraded.customSelect('PRAGMA foreign_key_check').get(),
          isEmpty,
        );
        expect(
          (await upgraded.select(upgraded.inventoryAdjustments).get()).every(
            (b) => b.warehouseId == null,
          ),
          isTrue,
        );
      } finally {
        await upgraded.close();
      }
    } finally {
      await directory.delete(recursive: true);
    }
  });
}
