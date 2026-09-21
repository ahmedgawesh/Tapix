import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/services/inventory/inventory_valuation_delta_service.dart';
import 'package:tapix/features/business/data/business_foundation_repository.dart';
import 'package:uuid/uuid.dart';

import 'business_foundation_test.dart' as fixtures;

void main() {
  late AppDatabase db;
  late int product, variant;
  late String warehouse;
  setUp(() async {
    db = fixtures.memoryDb();
    await fixtures.seedLegacyData(db);
    final row = await db
        .customSelect(
          'SELECT id, product_id FROM product_variants ORDER BY id LIMIT 1',
        )
        .getSingle();
    product = row.read<int>('product_id');
    variant = row.read<int>('id');
    warehouse = (await BusinessFoundationRepository(db).getScope()).warehouseId;
  });
  tearDown(() => db.close());

  Future<InventoryValuationSnapshot?> capture({int? id}) =>
      InventoryValuationDeltaService.capture(
        db.productDao,
        productId: product,
        variantId: id,
      );
  Future<int> delta(InventoryValuationSnapshot before) =>
      InventoryValuationDeltaService.signedDeltaAfter(db.productDao, before);
  Future<void> balance(int quantity, int cost) async {
    await (db.update(db.businessWarehouseStocks)..where(
          (s) => s.variantId.equals(variant) & s.warehouseId.equals(warehouse),
        ))
        .write(
          BusinessWarehouseStocksCompanion(
            quantity: Value(quantity),
            unitCostCents: Value(cost),
          ),
        );
  }

  test(
    'capture and delta use warehouse values despite stale legacy projection',
    () async {
      // Deliberately disable mirroring only in this corruption fixture.
      await db.customStatement('DROP TRIGGER business_stock_primary_update');
      await balance(1000, 501);
      final before = (await capture())!;
      expect(before.warehouseId, warehouse);
      expect(before.quantity, 1000);
      expect(before.unitCostCents, 501);
      await balance(999, 501);
      expect(await delta(before), -1);
      final legacy = await db
          .customSelect(
            'SELECT stock_quantity FROM product_variants WHERE id = $variant',
          )
          .getSingle();
      expect(legacy.read<int>('stock_quantity'), 1234);
    },
  );

  test('fractional movements telescope to original rounded pool', () async {
    await balance(3, 500);
    final before = (await capture())!;
    expect(before.valueCents, 2);
    await balance(2, 500);
    expect(await delta(before), -1);
    final second = (await capture())!;
    await balance(1, 500);
    expect(await delta(second), 0);
    final third = (await capture())!;
    await balance(0, 500);
    expect(await delta(third), -1);
    expect(await delta(before), -2);
  });

  test('quantity and cost changes both contribute to signed delta', () async {
    await balance(1000, 500);
    final before = (await capture(id: variant))!;
    await balance(2000, 600);
    expect(await delta(before), 700);
  });

  test('foreign variant is rejected even when its balance exists', () async {
    final foreign =
        (await db
                .customSelect(
                  'SELECT id FROM product_variants WHERE product_id != $product LIMIT 1',
                )
                .getSingle())
            .read<int>('id');
    await expectLater(capture(id: foreign), throwsStateError);
  });

  test(
    'optional size resolves the single simple operational variant',
    () async {
      final size = await db.customInsert(
        "INSERT INTO sizes (name) VALUES ('Optional')",
      );
      await db.customStatement(
        'UPDATE product_variants SET size_id = ? WHERE id = ?',
        [size, variant],
      );
      expect((await capture())!.variantId, variant);
    },
  );

  test('ambiguous simple product refuses to guess first variant', () async {
    final size = await db.customInsert(
      "INSERT INTO sizes (name) VALUES ('Extra')",
    );
    await db.customStatement(
      'INSERT INTO product_variants (product_id, size_id, cost_cents, price_cents) VALUES (?, ?, 100, 200)',
      [product, size],
    );
    await expectLater(capture(), throwsStateError);
    expect((await capture(id: variant))!.variantId, variant);
  });

  test('multi-variant product requires explicit variant', () async {
    await db.customStatement(
      'UPDATE products SET has_variants = 1 WHERE id = ?',
      [product],
    );
    await expectLater(capture(), throwsStateError);
    expect((await capture(id: variant))!.variantId, variant);
  });

  test('missing warehouse balance fails before and after snapshot', () async {
    final before = (await capture())!;
    await db.customStatement('DROP TRIGGER business_stock_retain');
    await db.customStatement(
      'DELETE FROM business_warehouse_stocks WHERE variant_id = ?',
      [variant],
    );
    await expectLater(capture(), throwsStateError);
    await expectLater(delta(before), throwsStateError);
  });

  for (final table in ['business_warehouses', 'business_branches']) {
    test('inactive $table rejects both valuation boundaries', () async {
      final before = (await capture())!;
      await db.customStatement('UPDATE $table SET is_active = 0');
      await expectLater(capture(), throwsStateError);
      await expectLater(delta(before), throwsStateError);
    });
  }

  test(
    'secondary warehouse cannot affect delta and foreign snapshot is rejected',
    () async {
      final scope = await BusinessFoundationRepository(db).getScope();
      final other = const Uuid().v4();
      await db
          .into(db.businessWarehouses)
          .insert(
            BusinessWarehousesCompanion.insert(
              id: other,
              organizationId: scope.organizationId,
              branchId: scope.branchId,
              code: 'OTHER',
            ),
          );
      final before = (await capture())!;
      await db
          .into(db.businessWarehouseStocks)
          .insert(
            BusinessWarehouseStocksCompanion.insert(
              warehouseId: other,
              variantId: variant,
              quantity: const Value(999999),
              unitCostCents: const Value(99999),
            ),
          );
      expect(await delta(before), 0);
      await expectLater(
        delta(
          InventoryValuationSnapshot(
            warehouseId: other,
            productId: product,
            variantId: variant,
            quantity: before.quantity,
            unitCostCents: before.unitCostCents,
            quantityScale: before.quantityScale,
          ),
        ),
        throwsStateError,
      );
    },
  );

  test('legacy simple product without variants retains parent valuation', () async {
    product = await db.customInsert(
      "INSERT INTO products (name, cost_cents, price_cents, stock_quantity) VALUES ('Legacy', 501, 1000, 3)",
    );
    final before = (await capture())!;
    expect(before.variantId, isNull);
    expect(before.valueCents, 1503);
    await db.customStatement(
      'UPDATE products SET stock_quantity = 2 WHERE id = ?',
      [product],
    );
    expect(await delta(before), -501);
    await db.customStatement(
      'INSERT INTO product_variants (product_id, cost_cents, price_cents) VALUES (?, 501, 1000)',
      [product],
    );
    await expectLater(delta(before), throwsStateError);
  });

  for (final policy in [
    "costing_method = 'fifo'",
    "inventory_tracking_type = 'batch'",
    "inventory_tracking_type = 'batch_expiry'",
    'track_inventory = 0',
  ]) {
    test('$policy remains excluded from standard valuation delta', () async {
      await db.customStatement('UPDATE products SET $policy WHERE id = ?', [
        product,
      ]);
      expect(await capture(), isNull);
    });
  }
}
