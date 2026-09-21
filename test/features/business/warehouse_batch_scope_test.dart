import 'dart:async';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/database/daos/accounting_dao.dart';
import 'package:tapix/core/database/daos/batch_audit_dao.dart';
import 'package:tapix/core/services/batch_service.dart';
import 'package:tapix/core/services/business/warehouse_operation_scope.dart';
import 'package:tapix/core/services/stock_service.dart';
import 'package:tapix/features/accounting/data/datasources/journal_local_datasource.dart';
import 'package:tapix/features/business/data/business_foundation_repository.dart';
import 'package:uuid/uuid.dart';

import 'business_foundation_test.dart' as fixtures;

void main() {
  late AppDatabase db;
  late int product;
  late int variant;
  late int batch;

  setUp(() async {
    db = fixtures.memoryDb();
    await fixtures.seedLegacyData(db);
    final row = await db
        .customSelect('SELECT id, product_id, variant_id FROM product_batches')
        .getSingle();
    product = row.read<int>('product_id');
    variant = row.read<int>('variant_id');
    batch = row.read<int>('id');
  });
  tearDown(() => db.close());

  Future<int> opening({int quantity = 100}) => BatchService.createOpeningBatch(
    db.purchaseDao,
    productId: product,
    variantId: variant,
    quantity: quantity,
    unitCostCents: 9999,
    source: 'opening',
    receivedDate: DateTime(2024),
    expiryDate: DateTime(2025),
  );

  Future<String> moveToSecondary(int batchId) async {
    final scope = await BusinessFoundationRepository(db).getScope();
    final second = const Uuid().v4();
    await db
        .into(db.businessWarehouses)
        .insert(
          BusinessWarehousesCompanion.insert(
            id: second,
            organizationId: scope.organizationId,
            branchId: scope.branchId,
            code: second.substring(0, 8),
          ),
        );
    // Simulate a future imported location. Production still forbids reassignment.
    await db.customStatement(
      'DROP TRIGGER IF EXISTS business_location_immutable',
    );
    await db.customStatement(
      "UPDATE business_document_locations SET warehouse_id = ? WHERE source_table = 'product_batches' AND source_id = ?",
      [second, batchId],
    );
    return second;
  }

  Future<List<BatchConsumptionResult>> consume(
    int quantity, {
    int? saleItemId,
  }) => BatchService.consumeFifo(
    db.saleDao,
    productId: product,
    variantId: variant,
    quantity: quantity,
    consumptionType: 'sale',
    saleItemId: saleItemId,
  );

  Future<int> remaining(int id) async =>
      (await db
              .customSelect(
                'SELECT remaining_quantity FROM product_batches WHERE id = $id',
              )
              .getSingle())
          .read<int>('remaining_quantity');

  group('selected warehouse batches', () {
    late int remoteBatch;
    late WarehouseOperationScope selected;
    setUp(() async {
      remoteBatch = await opening();
      final warehouse = await moveToSecondary(remoteBatch);
      selected = await WarehouseOperationScope.resolve(
        db,
        warehouseId: warehouse,
      );
      await db
          .into(db.businessWarehouseStocks)
          .insert(
            BusinessWarehouseStocksCompanion.insert(
              warehouseId: warehouse,
              variantId: variant,
              quantity: const Value(100),
              unitCostCents: const Value(9999),
            ),
          );
    });

    Future<List<BatchConsumptionResult>> take(int quantity, {int? item}) =>
        BatchService.consumeFifo(
          db.saleDao,
          productId: product,
          variantId: variant,
          quantity: quantity,
          consumptionType: 'sale',
          saleItemId: item,
          scope: selected,
        );

    test(
      'consumption and invariant use selected layers and quantity only',
      () async {
        await db.transaction(() async {
          final result = await take(30);
          expect(result.single.batchId, remoteBatch);
          expect(result.single.unitCostCents, 9999);
          await StockService.adjustStock(
            db.saleDao,
            productId: product,
            variantId: variant,
            quantity: 30,
            direction: StockDirection.decrease,
            scope: selected,
          );
          await BatchService.assertInvariantForProduct(
            db.saleDao,
            productId: product,
            scope: selected,
          );
        });
        expect(await remaining(remoteBatch), 70);
        expect(await remaining(batch), 1234);
        await BatchService.assertInvariant(
          db.saleDao,
          productId: product,
          variantId: variant,
        );
      },
    );

    test('shortage never borrows layers from the primary warehouse', () async {
      await expectLater(
        take(101),
        throwsA(isA<BatchInsufficientStockException>()),
      );
      expect(await remaining(remoteBatch), 100);
      expect(await remaining(batch), 1234);
      expect(await db.select(db.batchConsumptions).get(), isEmpty);
    });

    test('reversal restores captured batch cost in selected warehouse', () async {
      final sale = (await db.select(db.sales).get()).single;
      final item = await db.customInsert(
        'INSERT INTO sale_items (sale_id, product_id, variant_id, quantity, unit_price_cents, subtotal_cents, total_cents) VALUES (?, ?, ?, 30, 1, 30, 30)',
        variables: [
          Variable.withInt(sale.id),
          Variable.withInt(product),
          Variable.withInt(variant),
        ],
      );
      await take(30, item: item);
      await expectLater(
        BatchService.restoreConsumptions(
          db.saleDao,
          reverseConsumptionType: 'sale_return',
          saleItemId: item,
        ),
        throwsStateError,
      );
      expect(await remaining(remoteBatch), 70);
      expect(
        await BatchService.restoreConsumptions(
          db.saleDao,
          reverseConsumptionType: 'sale_return',
          saleItemId: item,
          scope: selected,
        ),
        30,
      );
      expect(await remaining(remoteBatch), 100);
      expect(await remaining(batch), 1234);
      final restored = await (db.select(
        db.batchConsumptions,
      )..where((c) => c.direction.equals('in'))).getSingle();
      expect(restored.unitCostCents.toBigInt().toInt(), 9999);
      expect(restored.batchId, remoteBatch);
    });

    test(
      'expiry edit is confined to selected warehouse and locks after consumption',
      () async {
        await BatchService.updateExpiryDate(
          db.purchaseDao,
          batchId: remoteBatch,
          newExpiry: DateTime(2030),
          scope: selected,
        );
        await expectLater(
          BatchService.updateExpiryDate(
            db.purchaseDao,
            batchId: batch,
            newExpiry: DateTime(2030),
            scope: selected,
          ),
          throwsStateError,
        );
        await take(1);
        await expectLater(
          BatchService.updateExpiryDate(
            db.purchaseDao,
            batchId: remoteBatch,
            newExpiry: DateTime(2031),
            scope: selected,
          ),
          throwsA(isA<BatchExpiryLockedException>()),
        );
      },
    );

    test('deactivated selected warehouse rejects consumption', () async {
      await (db.update(db.businessWarehouses)
            ..where((w) => w.id.equals(selected.warehouseId)))
          .write(const BusinessWarehousesCompanion(isActive: Value(false)));
      await expectLater(take(1), throwsStateError);
      expect(await remaining(remoteBatch), 100);
    });

    test('ledger failure rolls back selected consumption', () async {
      await db.customStatement(
        "CREATE TRIGGER fail_selected_consumption BEFORE INSERT ON batch_consumptions BEGIN SELECT RAISE(ABORT, 'injected'); END",
      );
      await expectLater(take(10), throwsA(anything));
      expect(await remaining(remoteBatch), 100);
      expect(await remaining(batch), 1234);
    });

    test(
      'selected invariant detects drift even when primary balances match',
      () async {
        await take(1);
        await expectLater(
          BatchService.assertInvariant(
            db.saleDao,
            productId: product,
            variantId: variant,
            scope: selected,
          ),
          throwsStateError,
        );
        await BatchService.assertInvariant(
          db.saleDao,
          productId: product,
          variantId: variant,
        );
      },
    );
  });

  test(
    'shortage rolls back all batches without requiring an outer transaction',
    () async {
      await expectLater(
        consume(1235),
        throwsA(isA<BatchInsufficientStockException>()),
      );
      expect(await remaining(batch), 1234);
      expect(await db.select(db.batchConsumptions).get(), isEmpty);
    },
  );

  test('failure to insert ledger entry rolls back quantity', () async {
    await db.customStatement(
      "CREATE TRIGGER fail_consumption BEFORE INSERT ON batch_consumptions BEGIN SELECT RAISE(ABORT, 'injected'); END",
    );
    await expectLater(consume(5), throwsA(anything));
    expect(await remaining(batch), 1234);
    expect(await db.select(db.batchConsumptions).get(), isEmpty);
  });

  test(
    'earlier foreign batch cannot enter FEFO, audit or accounting valuation',
    () async {
      final valuation = JournalLocalDatasourceImpl(AccountingDao(db));
      final before = await valuation.getTotalInventoryValueCents();
      final other = await opening();
      await moveToSecondary(other);
      expect(await valuation.getTotalInventoryValueCents(), before);
      final listed = await BatchAuditDao(
        db,
      ).getBatchesForProduct(productId: product);
      expect(listed.map((b) => b.batchId), [batch]);
      final result = await consume(5);
      expect(result.single.batchId, batch);
      expect(result.single.unitCostCents, 701);
      expect(result.single.quantityScale, 1000);
      expect(await remaining(other), 100);
      await expectLater(
        BatchService.updateExpiryDate(
          db.purchaseDao,
          batchId: other,
          newExpiry: DateTime(2030),
        ),
        throwsStateError,
      );
    },
  );

  test(
    'batch invariant compares only local layers with the local warehouse balance',
    () async {
      final other = await opening();
      await moveToSecondary(other);
      await BatchService.assertInvariant(
        db.saleDao,
        productId: product,
        variantId: variant,
      );
    },
  );

  test(
    'wrong variant ownership and invalid quantities fail before writing',
    () async {
      final before = await db.select(db.productBatches).get();
      await expectLater(
        BatchService.createOpeningBatch(
          db.purchaseDao,
          productId: product + 1000,
          variantId: variant,
          quantity: 1,
          unitCostCents: 10,
          source: 'opening',
        ),
        throwsStateError,
      );
      await expectLater(opening(quantity: 0), throwsArgumentError);
      await expectLater(consume(-1), throwsArgumentError);
      expect(await db.select(db.productBatches).get(), before);
    },
  );

  test(
    'restoration rejects a foreign batch and rolls back earlier restored rows',
    () async {
      final sale = (await db.select(db.sales).get()).single;
      final item = await db.customInsert(
        'INSERT INTO sale_items (sale_id, product_id, variant_id, quantity, unit_price_cents, subtotal_cents, total_cents) VALUES (?, ?, ?, 1300, 1, 1300, 1300)',
        variables: [
          Variable.withInt(sale.id),
          Variable.withInt(product),
          Variable.withInt(variant),
        ],
      );
      await consume(1234, saleItemId: item);
      final other = await opening();
      await consume(10, saleItemId: item);
      await moveToSecondary(other);
      await expectLater(
        BatchService.restoreConsumptions(
          db.saleDao,
          reverseConsumptionType: 'sale_return',
          saleItemId: item,
        ),
        throwsStateError,
      );
      expect(await remaining(batch), 0);
      expect(await remaining(other), 90);
      expect(
        await db
            .customSelect(
              "SELECT id FROM batch_consumptions WHERE direction = 'in'",
            )
            .get(),
        isEmpty,
      );
    },
  );

  test(
    'disabled warehouse remains in audit and valuation but rejects writes',
    () async {
      final first = Completer<void>();
      final disabled = Completer<void>();
      var disabling = false;
      // FIFO's display cost may differ from the frozen cost of its layers.
      // Disabling a warehouse must never switch valuation to that display cost.
      await db.customStatement(
        'UPDATE product_variants SET cost_cents = 1900 WHERE id = ?',
        [variant],
      );
      final valuation = JournalLocalDatasourceImpl(AccountingDao(db));
      final before = await valuation.getTotalInventoryValueCents();
      final subscription = BatchAuditDao(db)
          .watchBatchesForProduct(productId: product)
          .listen((rows) {
            if (rows.isNotEmpty && !first.isCompleted) first.complete();
            if (disabling && rows.isNotEmpty && !disabled.isCompleted) {
              disabled.complete();
            }
          });
      try {
        await first.future.timeout(const Duration(seconds: 5));
        disabling = true;
        await db
            .update(db.businessWarehouses)
            .write(const BusinessWarehousesCompanion(isActive: Value(false)));
        await disabled.future.timeout(const Duration(seconds: 5));
        expect(await valuation.getTotalInventoryValueCents(), before);
        await expectLater(
          BatchService.updateExpiryDate(
            db.purchaseDao,
            batchId: batch,
            newExpiry: DateTime(2030),
          ),
          throwsStateError,
        );
        await expectLater(consume(1), throwsStateError);
        await expectLater(opening(), throwsStateError);
        expect(await remaining(batch), 1234);
      } finally {
        await subscription.cancel();
      }
    },
  );
}
