import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/services/business/branch_currency_policy_store.dart';
import 'package:tapix/core/services/business/warehouse_operation_scope.dart';
import 'package:tapix/core/services/business/warehouse_transfer_preflight.dart';
import 'business_foundation_test.dart' as fixtures;

void main() {
  late AppDatabase db;
  late WarehouseOperationScope source, destination;
  late WarehouseTransferPreflight service;
  late int product, variant, currency;
  var permitted = true;
  setUp(() async {
    db = fixtures.memoryDb();
    source = await WarehouseOperationScope.resolve(db);
    permitted = true;
    currency = (await (db.select(
      db.currencies,
    )..where((c) => c.code.equals('USD'))).getSingle()).id;
    product = await db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            name: 'Transfer',
            currencyId: Value(currency),
            costCents: Decimal.fromInt(1000),
            priceCents: Decimal.fromInt(2000),
          ),
        );
    variant = await db
        .into(db.productVariants)
        .insert(
          ProductVariantsCompanion.insert(
            productId: product,
            costCents: Decimal.fromInt(1000),
            priceCents: Decimal.fromInt(2000),
            stockQuantity: const Value(5),
          ),
        );
    await db
        .into(db.businessWarehouses)
        .insert(
          BusinessWarehousesCompanion.insert(
            id: '66666666-6666-4666-8666-666666666666',
            organizationId: source.organizationId,
            branchId: source.branchId,
            code: 'TARGET',
          ),
        );
    await db
        .into(db.businessWarehouseStocks)
        .insert(
          BusinessWarehouseStocksCompanion.insert(
            warehouseId: '66666666-6666-4666-8666-666666666666',
            variantId: variant,
            unitCostCents: const Value(3000),
          ),
        );
    destination = await WarehouseOperationScope.resolve(
      db,
      warehouseId: '66666666-6666-4666-8666-666666666666',
    );
    await BranchCurrencyPolicyStore(db).bind('USD');
    service = WarehouseTransferPreflight(
      db,
      authorizeWarehouse: (_) async {
        if (!permitted) throw StateError('denied');
      },
    );
  });
  tearDown(() async => db.close());
  Future<WarehouseTransferPreview> preview({int qty = 2}) => service.preview(
    source: source,
    destination: destination,
    lines: [WarehouseTransferRequestLine(productId: product, quantity: qty)],
  );
  test(
    'WAC preview uses source cost, does not move stock and detects subsequent change',
    () async {
      final before = await fixtures.legacySnapshot(db);
      final stocks = await db.select(db.businessWarehouseStocks).get();
      final result = await preview();
      expect(result.valueCents, 2000);
      expect(result.lines.single.sourceAvailable, 5);
      expect(result.lines.single.destinationAvailable, 0);
      await service.validateUnchanged(result);
      expect(await fixtures.legacySnapshot(db), before);
      expect(await db.select(db.businessWarehouseStocks).get(), stocks);
      await db.customStatement(
        'UPDATE business_warehouse_stocks SET unit_cost_cents=1500 WHERE warehouse_id=?',
        [source.warehouseId],
      );
      await expectLater(service.validateUnchanged(result), throwsStateError);
    },
  );
  test(
    'same location, insufficient quantity and duplicate lines are rejected',
    () async {
      await expectLater(
        service.preview(
          source: source,
          destination: source,
          lines: [
            WarehouseTransferRequestLine(productId: product, quantity: 1),
          ],
        ),
        throwsStateError,
      );
      await expectLater(preview(qty: 6), throwsStateError);
      await expectLater(preview(qty: 0), throwsArgumentError);
      await expectLater(
        service.preview(
          source: source,
          destination: destination,
          lines: [
            WarehouseTransferRequestLine(productId: product, quantity: 1),
            WarehouseTransferRequestLine(
              productId: product,
              variantId: variant,
              quantity: 1,
            ),
          ],
        ),
        throwsArgumentError,
      );
    },
  );
  test(
    'revoked permission and disabled warehouse invalidate captured preview',
    () async {
      final result = await preview();
      permitted = false;
      await expectLater(service.validateUnchanged(result), throwsStateError);
      permitted = true;
      await db.customStatement(
        "UPDATE business_warehouses SET is_active=0 WHERE id='66666666-6666-4666-8666-666666666666'",
      );
      await expectLater(service.validateUnchanged(result), throwsStateError);
    },
  );
  test(
    'FIFO preview preserves per-layer cost and detects source metadata changes',
    () async {
      await db.customStatement(
        "UPDATE products SET costing_method='fifo' WHERE id=?",
        [product],
      );
      for (final record in [(1, 1000, 'B1'), (4, 2000, 'B2')]) {
        await db
            .into(db.productBatches)
            .insert(
              ProductBatchesCompanion.insert(
                productId: product,
                variantId: Value(variant),
                batchNumber: record.$3,
                receivedQuantity: record.$1,
                remainingQuantity: record.$1,
                unitCostCents: Decimal.fromInt(record.$2),
                source: const Value('opening'),
              ),
            );
      }
      final result = await preview();
      expect(result.valueCents, 3000);
      expect(result.lines.single.layers.map((l) => l.quantity), [1, 1]);
      await db.customStatement(
        "UPDATE product_batches SET manufacturer_lot_number='changed' WHERE batch_number='B1'",
      );
      await expectLater(service.validateUnchanged(result), throwsStateError);
    },
  );
  test('measured WAC preserves rounded inventory pool value', () async {
    await db.customStatement(
      "UPDATE products SET measurement_type='weight' WHERE id=?",
      [product],
    );
    await db.customStatement(
      'UPDATE business_warehouse_stocks SET quantity=1500,unit_cost_cents=333 WHERE warehouse_id=?',
      [source.warehouseId],
    );
    final result = await preview(qty: 500);
    expect(result.lines.single.quantityScale, 1000);
    expect(result.valueCents, 167);
  });
}
