import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/services/batch_service.dart';

/// ────────────────────────────────────────────────────────────────────────────
/// Phase I2 — `BatchService.updateExpiryDate` + Invariant I7 (expiry-date
/// freeze after first consumption).
///
/// What we prove here:
///   1. Happy path — re-date a fresh batch (no consumption) succeeds and
///      persists the new value.
///   2. Setting `null` is allowed when no consumption exists (e.g. switch
///      a `batch_expiry` row back to `batch` after a tracking-type fix).
///   3. After the FIRST 'out' consumption, the batch's `expiry_date` is
///      FROZEN — `BatchExpiryLockedException(reason='has_consumptions')`.
///   4. The thrown exception leaves the row UNCHANGED (no partial mutation).
///   5. Restoring a consumption (sale return) still leaves the lock engaged
///      because the historical 'out' row is preserved — Invariant I7 is
///      about audit traceability, not about current stock.
///   6. Voided / inactive batches reject edits with reason='inactive'.
///   7. Unknown batchId raises `StateError`.
/// ────────────────────────────────────────────────────────────────────────────
void main() {
  late AppDatabase db;
  late int productId;
  late int variantId;

  Future<void> seedProduct() async {
    productId = await db.into(db.products).insert(
          ProductsCompanion.insert(
            sku: const Value('I7-EXPIRY'),
            name: 'I7 expiry-freeze test product',
            costCents: Decimal.fromInt(100),
            priceCents: Decimal.fromInt(200),
            stockQuantity: const Value(0),
            inventoryTrackingType: const Value('batch_expiry'),
          ),
        );
    variantId = await db.into(db.productVariants).insert(
          ProductVariantsCompanion.insert(
            productId: productId,
            stockQuantity: const Value(0),
            costCents: Decimal.fromInt(100),
            priceCents: Decimal.fromInt(200),
          ),
        );
  }

  Future<int> insertBatch({
    required int qty,
    DateTime? expiry,
  }) async {
    final id = await BatchService.createOpeningBatch(
      db.purchaseDao,
      productId: productId,
      variantId: variantId,
      quantity: qty,
      unitCostCents: 100,
      source: 'opening',
      receivedDate: DateTime(2026, 1, 1),
      expiryDate: expiry,
    );
    // Mirror variant stock so subsequent consumeFifo doesn't desync.
    await db.customStatement(
      'UPDATE product_variants SET stock_quantity = stock_quantity + ? '
      ' WHERE id = ?',
      [qty, variantId],
    );
    return id;
  }

  Future<DateTime?> readExpiry(int batchId) async {
    final row = await db
        .customSelect(
          'SELECT expiry_date FROM product_batches WHERE id = ?',
          variables: [Variable.withInt(batchId)],
        )
        .getSingle();
    final iso = row.readNullable<String>('expiry_date');
    return iso == null ? null : DateTime.parse(iso);
  }

  setUp(() async {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    await db.customSelect('SELECT 1').get();
    await seedProduct();
  });

  tearDown(() async {
    await db.close();
  });

  test('I7-1: re-date a fresh batch (no consumption) succeeds', () async {
    final batchId = await insertBatch(
      qty: 10,
      expiry: DateTime(2026, 6, 1),
    );

    final newExpiry = DateTime(2026, 9, 30);
    await BatchService.updateExpiryDate(
      db.purchaseDao,
      batchId: batchId,
      newExpiry: newExpiry,
    );

    expect(await readExpiry(batchId), equals(newExpiry));
  });

  test('I7-2: setting expiry to null is allowed when no consumption exists',
      () async {
    final batchId = await insertBatch(
      qty: 5,
      expiry: DateTime(2026, 6, 1),
    );

    await BatchService.updateExpiryDate(
      db.purchaseDao,
      batchId: batchId,
      newExpiry: null,
    );

    expect(await readExpiry(batchId), isNull);
  });

  test(
      'I7-3: after first OUT consumption, expiry edit throws '
      'BatchExpiryLockedException(reason=has_consumptions)', () async {
    final batchId = await insertBatch(
      qty: 10,
      expiry: DateTime(2026, 6, 1),
    );

    // Trigger one OUT row via consumeFifo.
    await BatchService.consumeFifo(
      db.purchaseDao,
      productId: productId,
      variantId: variantId,
      quantity: 3,
      consumptionType: 'sale',
    );
    // Mirror the variant stock so the system is otherwise consistent.
    await db.customStatement(
      'UPDATE product_variants SET stock_quantity = stock_quantity - 3 '
      ' WHERE id = ?',
      [variantId],
    );

    expect(
      () => BatchService.updateExpiryDate(
        db.purchaseDao,
        batchId: batchId,
        newExpiry: DateTime(2027, 1, 1),
      ),
      throwsA(isA<BatchExpiryLockedException>()
          .having((e) => e.reason, 'reason', 'has_consumptions')
          .having((e) => e.consumptionCount, 'consumptionCount', 1)
          .having((e) => e.batchId, 'batchId', batchId)),
    );
  });

  test('I7-4: rejected edit leaves expiry_date unchanged', () async {
    final original = DateTime(2026, 6, 1);
    final batchId = await insertBatch(qty: 10, expiry: original);

    await BatchService.consumeFifo(
      db.purchaseDao,
      productId: productId,
      variantId: variantId,
      quantity: 1,
      consumptionType: 'sale',
    );
    await db.customStatement(
      'UPDATE product_variants SET stock_quantity = stock_quantity - 1 '
      ' WHERE id = ?',
      [variantId],
    );

    try {
      await BatchService.updateExpiryDate(
        db.purchaseDao,
        batchId: batchId,
        newExpiry: DateTime(2099, 1, 1),
      );
      fail('expected BatchExpiryLockedException');
    } on BatchExpiryLockedException {
      // expected
    }

    expect(await readExpiry(batchId), equals(original));
  });

  test(
      'I7-5: lock persists even when an IN row mirrors the OUT (return) — '
      'the filter checks direction=\'out\' specifically', () async {
    final original = DateTime(2026, 6, 1);
    final batchId = await insertBatch(qty: 10, expiry: original);

    // Real OUT via the production write path.
    await BatchService.consumeFifo(
      db.purchaseDao,
      productId: productId,
      variantId: variantId,
      quantity: 4,
      consumptionType: 'sale',
    );
    await db.customStatement(
      'UPDATE product_variants SET stock_quantity = stock_quantity - 4 '
      ' WHERE id = ?',
      [variantId],
    );

    // Mirror IN row (as a return would create) — direction='in'. We skip
    // restoreConsumptions to avoid touching unrelated source FKs; the
    // structural shape (one OUT + one IN on the same batch) is what
    // matters for proving the COUNT filter uses direction='out' only.
    await db.customStatement(
      'INSERT INTO batch_consumptions '
      '(batch_id, consumption_type, direction, quantity, unit_cost_cents, '
      ' created_at) '
      'VALUES (?, \'sale_return_reverse\', \'in\', 4, 100, ?)',
      [batchId, DateTime.now().toIso8601String()],
    );
    await db.customStatement(
      'UPDATE product_batches SET remaining_quantity = remaining_quantity + 4 '
      ' WHERE id = ?',
      [batchId],
    );
    await db.customStatement(
      'UPDATE product_variants SET stock_quantity = stock_quantity + 4 '
      ' WHERE id = ?',
      [variantId],
    );

    // Edit must STILL be refused — the historical OUT row is what matters
    // for I7, not the current remaining_quantity.
    expect(
      () => BatchService.updateExpiryDate(
        db.purchaseDao,
        batchId: batchId,
        newExpiry: DateTime(2027, 1, 1),
      ),
      throwsA(isA<BatchExpiryLockedException>()
          .having((e) => e.reason, 'reason', 'has_consumptions')
          .having((e) => e.consumptionCount, 'consumptionCount', 1)),
    );
    expect(await readExpiry(batchId), equals(original));
  });

  test('I7-6: voided (is_active=0) batch rejects with reason=inactive',
      () async {
    final batchId = await insertBatch(qty: 5, expiry: DateTime(2026, 6, 1));

    // Simulate a void (matches PurchaseDao.voidPurchase soft-delete shape).
    await db.customStatement(
      'UPDATE product_batches SET is_active = 0, remaining_quantity = 0 '
      ' WHERE id = ?',
      [batchId],
    );
    await db.customStatement(
      'UPDATE product_variants SET stock_quantity = stock_quantity - 5 '
      ' WHERE id = ?',
      [variantId],
    );

    expect(
      () => BatchService.updateExpiryDate(
        db.purchaseDao,
        batchId: batchId,
        newExpiry: DateTime(2027, 1, 1),
      ),
      throwsA(isA<BatchExpiryLockedException>()
          .having((e) => e.reason, 'reason', 'inactive')
          .having((e) => e.batchId, 'batchId', batchId)),
    );
  });

  test('I7-7: unknown batchId raises StateError', () async {
    expect(
      () => BatchService.updateExpiryDate(
        db.purchaseDao,
        batchId: 999999,
        newExpiry: DateTime(2027, 1, 1),
      ),
      throwsA(isA<StateError>()),
    );
  });
}
