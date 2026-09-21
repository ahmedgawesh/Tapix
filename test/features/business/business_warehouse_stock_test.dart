import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/database/migrations/business_document_locations.dart';
import 'package:tapix/core/database/migrations/business_warehouse_stock.dart';
import 'package:tapix/core/services/stock_service.dart';
import 'package:tapix/core/services/business/warehouse_operation_scope.dart';
import 'package:tapix/features/business/data/business_foundation_repository.dart';
import 'package:uuid/uuid.dart';

import 'business_foundation_test.dart' as fixtures;

void main() {
  late AppDatabase db;
  late int variant;
  late int product;
  late String warehouse;

  setUp(() async {
    db = fixtures.memoryDb();
    await fixtures.seedLegacyData(db);
    final row = await db
        .customSelect(
          'SELECT id, product_id FROM product_variants ORDER BY id LIMIT 1',
        )
        .getSingle();
    variant = row.read<int>('id');
    product = row.read<int>('product_id');
    warehouse = (await BusinessFoundationRepository(db).getScope()).warehouseId;
  });
  tearDown(() => db.close());

  Future<void> expectBalance(int quantity, int cost) async {
    final v = await db
        .customSelect(
          'SELECT stock_quantity, cost_cents FROM product_variants WHERE id = $variant',
        )
        .getSingle();
    final s = await db
        .customSelect(
          'SELECT quantity, unit_cost_cents FROM business_warehouse_stocks WHERE variant_id = $variant AND warehouse_id = ?',
          variables: [Variable.withString(warehouse)],
        )
        .getSingle();
    expect(v.read<int>('stock_quantity'), quantity);
    expect(s.read<int>('quantity'), quantity);
    expect(v.read<int>('cost_cents'), cost);
    expect(s.read<int>('unit_cost_cents'), cost);
  }

  Future<String> addWarehouse({bool foreignBranch = false}) async {
    final scope = await BusinessFoundationRepository(db).getScope();
    final id = const Uuid().v4();
    var branch = scope.branchId;
    if (foreignBranch) {
      branch = const Uuid().v4();
      await db
          .into(db.businessBranches)
          .insert(
            BusinessBranchesCompanion.insert(
              id: branch,
              organizationId: scope.organizationId,
              code: branch.substring(0, 8),
            ),
          );
    }
    await db
        .into(db.businessWarehouses)
        .insert(
          BusinessWarehousesCompanion.insert(
            id: id,
            organizationId: scope.organizationId,
            branchId: branch,
            code: id.substring(0, 8),
          ),
        );
    return id;
  }

  Future<void> insertStock(
    String id, {
    int quantity = 50,
  }) => db.customStatement(
    'INSERT INTO business_warehouse_stocks (warehouse_id, variant_id, quantity, unit_cost_cents) VALUES (?, ?, ?, 999)',
    [id, variant, quantity],
  );

  group('explicit warehouse quantity routing', () {
    Future<int> quantityAt(String id) async =>
        (await db
                .customSelect(
                  'SELECT quantity FROM business_warehouse_stocks WHERE warehouse_id = ? AND variant_id = ?',
                  variables: [
                    Variable.withString(id),
                    Variable.withInt(variant),
                  ],
                )
                .getSingle())
            .read<int>('quantity');

    for (final explicitVariant in [false, true]) {
      test(
        'secondary movement preserves primary mirrors: variant=$explicitVariant',
        () async {
          if (explicitVariant) {
            await (db.update(db.products)..where((p) => p.id.equals(product)))
                .write(const ProductsCompanion(hasVariants: Value(true)));
          }
          final other = await addWarehouse();
          await insertStock(other, quantity: 700);
          final scope = await WarehouseOperationScope.resolve(
            db,
            warehouseId: other,
          );
          final before = await fixtures.legacySnapshot(db);
          await StockService.adjustStock(
            db.productDao,
            productId: product,
            variantId: explicitVariant ? variant : null,
            quantity: 234,
            direction: StockDirection.decrease,
            scope: scope,
          );
          await StockService.syncProductStockFromVariants(
            db.productDao,
            productId: product,
            scope: scope,
          );
          expect(await quantityAt(other), 466);
          await expectBalance(1234, 701);
          expect(await fixtures.legacySnapshot(db), before);
          final cost = await db
              .customSelect(
                'SELECT unit_cost_cents FROM business_warehouse_stocks WHERE warehouse_id = ? AND variant_id = ?',
                variables: [
                  Variable.withString(other),
                  Variable.withInt(variant),
                ],
              )
              .getSingle();
          expect(cost.read<int>('unit_cost_cents'), 999);
        },
      );
    }

    test(
      'default scope keeps primary behavior and never selects other stock',
      () async {
        final other = await addWarehouse();
        await insertStock(other);
        final scope = await WarehouseOperationScope.resolve(db);
        expect(scope.isPrimary, isTrue);
        expect(scope.warehouseId, warehouse);
        await StockService.adjustStock(
          db.productDao,
          productId: product,
          quantity: 34,
          direction: StockDirection.increase,
        );
        await StockService.syncProductStockFromVariants(
          db.productDao,
          productId: product,
        );
        await expectBalance(1268, 701);
        expect(await quantityAt(other), 50);
      },
    );

    test(
      'foreign branch and missing warehouse cannot resolve a scope',
      () async {
        final foreign = await addWarehouse(foreignBranch: true);
        for (final id in [foreign, const Uuid().v4(), '']) {
          await expectLater(
            WarehouseOperationScope.resolve(db, warehouseId: id),
            throwsStateError,
          );
        }
      },
    );

    test(
      'deactivation after selection prevents writes and projection',
      () async {
        final other = await addWarehouse();
        await insertStock(other);
        final scope = await WarehouseOperationScope.resolve(
          db,
          warehouseId: other,
        );
        await (db.update(db.businessWarehouses)
              ..where((w) => w.id.equals(other)))
            .write(const BusinessWarehousesCompanion(isActive: Value(false)));
        await expectLater(
          StockService.adjustStock(
            db.productDao,
            productId: product,
            quantity: 10,
            direction: StockDirection.decrease,
            scope: scope,
          ),
          throwsStateError,
        );
        await expectLater(
          StockService.syncProductStockFromVariants(
            db.productDao,
            productId: product,
            scope: scope,
          ),
          throwsStateError,
        );
        expect(await quantityAt(other), 50);
        await expectBalance(1234, 701);
      },
    );

    test('scope cannot be reused on another database connection', () async {
      final scope = await WarehouseOperationScope.resolve(db);
      final another = fixtures.memoryDb();
      try {
        await expectLater(scope.validate(another), throwsStateError);
      } finally {
        await another.close();
      }
    });

    test('missing secondary balance never falls back to primary', () async {
      final other = await addWarehouse();
      final scope = await WarehouseOperationScope.resolve(
        db,
        warehouseId: other,
      );
      final before = await fixtures.legacySnapshot(db);
      await expectLater(
        StockService.adjustStock(
          db.productDao,
          productId: product,
          quantity: 10,
          direction: StockDirection.increase,
          scope: scope,
        ),
        throwsStateError,
      );
      expect(await fixtures.legacySnapshot(db), before);
      await expectBalance(1234, 701);
    });

    test('secondary write rejects a mismatched product and variant', () async {
      final other = await addWarehouse();
      await insertStock(other);
      final scope = await WarehouseOperationScope.resolve(
        db,
        warehouseId: other,
      );
      await expectLater(
        StockService.adjustStock(
          db.productDao,
          productId: product + 999,
          variantId: variant,
          quantity: 10,
          direction: StockDirection.increase,
          scope: scope,
        ),
        throwsStateError,
      );
      expect(await quantityAt(other), 50);
    });

    test('outer transaction failure rolls back secondary quantity', () async {
      final other = await addWarehouse();
      await insertStock(other);
      final scope = await WarehouseOperationScope.resolve(
        db,
        warehouseId: other,
      );
      await expectLater(
        db.transaction(() async {
          await StockService.adjustStock(
            db.productDao,
            productId: product,
            quantity: 10,
            direction: StockDirection.increase,
            scope: scope,
          );
          throw StateError('simulated posting failure');
        }),
        throwsStateError,
      );
      expect(await quantityAt(other), 50);
      await expectBalance(1234, 701);
    });

    test(
      'interleaved scopes never change the default database context',
      () async {
        final other = await addWarehouse();
        await insertStock(other);
        final primary = await WarehouseOperationScope.resolve(db);
        final secondary = await WarehouseOperationScope.resolve(
          db,
          warehouseId: other,
        );
        await Future.wait([
          StockService.adjustStock(
            db.productDao,
            productId: product,
            variantId: variant,
            quantity: 34,
            direction: StockDirection.decrease,
            scope: primary,
          ),
          StockService.adjustStock(
            db.productDao,
            productId: product,
            variantId: variant,
            quantity: 20,
            direction: StockDirection.increase,
            scope: secondary,
          ),
        ]);
        await expectBalance(1200, 701);
        expect(await quantityAt(other), 70);
        expect(
          (await BusinessFoundationRepository(db).getScope()).warehouseId,
          warehouse,
        );
      },
    );
  });

  test(
    'legacy writes and warehouse writes agree with recursive triggers on and off',
    () async {
      for (final recursive in [0, 1]) {
        await db.customStatement('PRAGMA recursive_triggers = $recursive');
        await db.customStatement(
          'UPDATE product_variants SET stock_quantity = -12, cost_cents = 703 WHERE id = $variant',
        );
        await expectBalance(-12, 703);
        await db.customStatement(
          'UPDATE business_warehouse_stocks SET quantity = 1234, unit_cost_cents = 701 WHERE variant_id = $variant',
        );
        await expectBalance(1234, 701);
      }
    },
  );

  test(
    'stock service validates ownership and preserves measured quantities',
    () async {
      await StockService.adjustStock(
        db.productDao,
        productId: product,
        variantId: variant,
        quantity: 234,
        direction: StockDirection.decrease,
      );
      await expectBalance(1000, 701);
      await expectLater(
        StockService.adjustStock(
          db.productDao,
          productId: product + 100,
          variantId: variant,
          quantity: 50,
          direction: StockDirection.increase,
        ),
        throwsStateError,
      );
      await expectLater(
        StockService.adjustStock(
          db.productDao,
          productId: product,
          variantId: variant,
          quantity: -1,
          direction: StockDirection.increase,
        ),
        throwsArgumentError,
      );
      await expectBalance(1000, 701);
    },
  );

  test(
    'failed projection rolls back warehouse and simple product writes',
    () async {
      await db.customStatement(
        '''CREATE TRIGGER fail_stock BEFORE UPDATE OF stock_quantity ON product_variants
      BEGIN SELECT RAISE(ABORT, 'injected failure'); END''',
      );
      final before = await fixtures.legacySnapshot(db);
      await expectLater(
        StockService.adjustStock(
          db.productDao,
          productId: product,
          quantity: 50,
          direction: StockDirection.decrease,
        ),
        throwsA(anything),
      );
      expect(await fixtures.legacySnapshot(db), before);
      await expectBalance(1234, 701);
    },
  );

  test('secondary warehouse stock is isolated and cannot be orphaned', () async {
    final second = await addWarehouse();
    await insertStock(second);
    await db.customStatement(
      'UPDATE business_warehouse_stocks SET quantity = 77 WHERE warehouse_id = ?',
      [second],
    );
    await expectBalance(1234, 701);
    await expectLater(
      db.customStatement('DELETE FROM product_variants WHERE id = $variant'),
      throwsA(anything),
    );
    for (final recursive in [0, 1]) {
      await db.customStatement('PRAGMA recursive_triggers = $recursive');
      await expectLater(
        db.customStatement(
          'INSERT OR REPLACE INTO product_variants (id, product_id, cost_cents, price_cents) VALUES (?, ?, 0, 0)',
          [variant, product],
        ),
        throwsA(anything),
      );
    }
    await expectLater(
      db.customStatement(
        'DELETE FROM business_warehouse_stocks WHERE warehouse_id = ?',
        [second],
      ),
      throwsA(anything),
    );
    await db.customStatement(
      'UPDATE business_warehouse_stocks SET quantity = 0 WHERE warehouse_id = ?',
      [second],
    );
    await db.customStatement(
      'DELETE FROM business_warehouse_stocks WHERE warehouse_id = ?',
      [second],
    );
    await expectBalance(1234, 701);
  });

  test(
    'foreign branch, key changes, replacement and primary deletion are rejected',
    () async {
      final foreign = await addWarehouse(foreignBranch: true);
      await expectLater(insertStock(foreign), throwsA(anything));
      await expectLater(
        db.customStatement(
          'UPDATE business_warehouse_stocks SET warehouse_id = ? WHERE variant_id = ?',
          [foreign, variant],
        ),
        throwsA(anything),
      );
      await expectLater(
        db.customStatement(
          'INSERT OR REPLACE INTO business_warehouse_stocks (warehouse_id, variant_id, quantity) VALUES (?, ?, 0)',
          [warehouse, variant],
        ),
        throwsA(anything),
      );
      await expectLater(
        db.customStatement(
          'DELETE FROM business_warehouse_stocks WHERE variant_id = $variant',
        ),
        throwsA(anything),
      );
      await expectBalance(1234, 701);
    },
  );

  test(
    'integer overflow and fractional storage fail without partial writes',
    () async {
      await expectLater(
        db.customStatement(
          'UPDATE business_warehouse_stocks SET quantity = 1.5 WHERE variant_id = $variant',
        ),
        throwsA(anything),
      );
      await expectLater(
        db.customStatement(
          'UPDATE product_variants SET stock_quantity = 9223372036854775807 + 1 WHERE id = $variant',
        ),
        throwsA(anything),
      );
      await expectBalance(1234, 701);
    },
  );

  test('stock context guards work independently of document guards', () async {
    await removeBusinessDocumentLocationTriggers(db);
    await expectLater(
      db.customStatement('DELETE FROM business_contexts'),
      throwsA(anything),
    );
    await expectLater(
      db.customStatement('UPDATE business_contexts SET database_id = ?', [
        const Uuid().v4(),
      ]),
      throwsA(anything),
    );
    await expectBalance(1234, 701);
  });

  test('variant watchers receive stock-service changes', () async {
    final values = <int>[];
    final initial = Completer<void>();
    final changed = Completer<void>();
    final subscription =
        (db.select(
          db.productVariants,
        )..where((v) => v.id.equals(variant))).watchSingle().listen((v) {
          values.add(v.stockQuantity);
          if (v.stockQuantity == 1234 && !initial.isCompleted) {
            initial.complete();
          }
          if (v.stockQuantity == 1230 && !changed.isCompleted) {
            changed.complete();
          }
        });
    try {
      await initial.future.timeout(const Duration(seconds: 5));
      await StockService.adjustStock(
        db.productDao,
        productId: product,
        variantId: variant,
        quantity: 4,
        direction: StockDirection.decrease,
      );
      await changed.future.timeout(const Duration(seconds: 5));
      expect(values, containsAllInOrder([1234, 1230]));
    } finally {
      await subscription.cancel();
    }
  });

  test('unused variant deletion removes its primary balance normally', () async {
    final unusedProduct = await db.customInsert(
      "INSERT INTO products (name, cost_cents, price_cents) VALUES ('Unused', 0, 0)",
    );
    final id = await db.customInsert(
      'INSERT INTO product_variants (product_id, cost_cents, price_cents) VALUES ($unusedProduct, 0, 0)',
    );
    await db.customStatement('DELETE FROM product_variants WHERE id = $id');
    expect(
      await db
          .customSelect(
            'SELECT 1 FROM business_warehouse_stocks WHERE variant_id = $id',
          )
          .get(),
      isEmpty,
    );
  });

  test('failed 10085 backfill rolls back table creation and can retry', () async {
    final dir = await Directory.systemTemp.createTemp(
      'warehouse_failed_upgrade_',
    );
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/legacy.sqlite');
    var disk = AppDatabase.connect(DatabaseConnection(NativeDatabase(file)));
    await fixtures.seedLegacyData(disk);
    await removeBusinessWarehouseStockTriggers(disk);
    await disk.customStatement('DROP TABLE business_warehouse_stocks');
    await disk.customStatement(
      'UPDATE product_variants SET stock_quantity = 1.5',
    );
    await disk.customStatement('PRAGMA user_version = 10085');
    await disk.close();
    disk = AppDatabase.connect(DatabaseConnection(NativeDatabase(file)));
    await expectLater(disk.customSelect('SELECT 1').get(), throwsA(anything));
    await disk.close();
    final raw = sqlite.sqlite3.open(file.path);
    try {
      expect(raw.userVersion, 10085);
      expect(
        raw.select(
          "SELECT name FROM sqlite_master WHERE name = 'business_warehouse_stocks'",
        ),
        isEmpty,
      );
      expect(
        raw
            .select('SELECT stock_quantity FROM product_variants')
            .every((r) => r['stock_quantity'] == 1.5),
        isTrue,
      );
      raw.execute('UPDATE product_variants SET stock_quantity = 1234');
    } finally {
      raw.close();
    }
    disk = AppDatabase.connect(DatabaseConnection(NativeDatabase(file)));
    try {
      expect(
        await disk.select(disk.businessWarehouseStocks).get(),
        hasLength(2),
      );
      expect(
        await disk.customSelect('PRAGMA foreign_key_check').get(),
        isEmpty,
      );
    } finally {
      await disk.close();
    }
  });

  test(
    '10085 upgrade preserves every legacy row, lots and scope; reopening is stable',
    () async {
      final dir = await Directory.systemTemp.createTemp('warehouse_upgrade_');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/legacy.sqlite');
      var disk = AppDatabase.connect(DatabaseConnection(NativeDatabase(file)));
      await fixtures.seedLegacyData(disk);
      await disk.customStatement(
        "UPDATE product_batches SET manufacturer_lot_number = 'LOT-10085'",
      );
      final before = await fixtures.legacySnapshot(disk);
      final scope = await BusinessFoundationRepository(disk).getScope();
      await removeBusinessWarehouseStockTriggers(disk);
      await disk.customStatement('DROP TABLE business_warehouse_stocks');
      await disk.customStatement('PRAGMA user_version = 10085');
      await disk.close();
      disk = AppDatabase.connect(DatabaseConnection(NativeDatabase(file)));
      try {
        expect(await fixtures.legacySnapshot(disk), before);
        expect(
          (await BusinessFoundationRepository(disk).getScope()).databaseId,
          scope.databaseId,
        );
        final stocks = await BusinessFoundationRepository(
          disk,
        ).getPrimaryWarehouseStock(scope.warehouseId);
        expect(stocks, hasLength(2));
        expect(
          stocks.every(
            (s) =>
                s.quantity == 1234 &&
                s.unitCostCents == 701 &&
                s.quantityScale == 1000,
          ),
          isTrue,
        );
        expect(
          await disk.customSelect('PRAGMA foreign_key_check').get(),
          isEmpty,
        );
      } finally {
        await disk.close();
      }
      disk = AppDatabase.connect(DatabaseConnection(NativeDatabase(file)));
      try {
        expect(await fixtures.legacySnapshot(disk), before);
        expect(
          await disk.select(disk.businessWarehouseStocks).get(),
          hasLength(2),
        );
      } finally {
        await disk.close();
      }
    },
  );
}
