import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapix/core/database/app_database.dart';

/// ────────────────────────────────────────────────────────────────────────────
/// Phase I3 — `product_batches` DB-level integrity triggers.
///
/// Verifies that the BEFORE INSERT / BEFORE UPDATE triggers installed by
/// `_installProductBatchesIntegrityTriggers()` reject any row whose
/// `remaining_quantity` is negative or exceeds `received_quantity`.
///
/// These triggers are a defense-in-depth safety net layered *below*
/// `BatchService`: they catch any future write path (raw SQL, new DAO, bug
/// regression) that bypasses the service and would otherwise corrupt
/// inventory state silently.
///
/// Each test follows the same shape:
///   1. Insert one product (parent FK).
///   2. Either INSERT a violating row, or INSERT a valid row then UPDATE it
///      into a violating state.
///   3. Expect a SQLite `Exception` whose message contains the documented
///      RAISE(ABORT, ...) text.
///
/// Triggers covered:
///   • trg_product_batches_remaining_nonneg_insert          → I-DB-1 (insert)
///   • trg_product_batches_remaining_nonneg_update          → I-DB-1 (update)
///   • trg_product_batches_remaining_le_received_insert     → I-DB-2 (insert)
///   • trg_product_batches_remaining_le_received_update     → I-DB-2 (update)
/// ────────────────────────────────────────────────────────────────────────────
void main() {
  late AppDatabase db;
  late int productId;

  setUp(() async {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));

    // _seedInitialData() already creates a base currency. Pick the first
    // available one for the FK; we don't care which.
    final currencyRow = await db
        .customSelect('SELECT id FROM currencies ORDER BY id LIMIT 1')
        .getSingle();
    final currencyId = currencyRow.data['id'] as int;

    productId = await db.into(db.products).insert(
          ProductsCompanion.insert(
            sku: const Value('SKU-I3'),
            name: 'I3 Test Product',
            costCents: Decimal.fromInt(100),
            priceCents: Decimal.fromInt(200),
            currencyId: Value(currencyId),
            stockQuantity: const Value(0),
            inventoryTrackingType: const Value('batch'),
          ),
        );
  });

  tearDown(() async => db.close());

  // ──────────────────────────────────────────────────────────────────────────
  // Helpers
  // ──────────────────────────────────────────────────────────────────────────

  /// Insert raw row via SQL to bypass Drift companions (which would otherwise
  /// short-circuit on the int column type). The trigger has to fire on the DB
  /// layer regardless of source.
  Future<void> insertBatchRaw({
    required String batchNumber,
    required int received,
    required int remaining,
  }) async {
    await db.customStatement(
      '''
      INSERT INTO product_batches
        (product_id, batch_number, source, received_date,
         received_quantity, remaining_quantity, unit_cost_cents, is_active,
         created_at, updated_at)
      VALUES (?, ?, 'purchase', '2026-01-01T00:00:00.000', ?, ?, 100, 1,
              '2026-01-01T00:00:00.000', '2026-01-01T00:00:00.000')
      ''',
      [productId, batchNumber, received, remaining],
    );
  }

  Future<int> insertValidBatch({
    required String batchNumber,
    required int received,
    int? remaining,
  }) async {
    await insertBatchRaw(
      batchNumber: batchNumber,
      received: received,
      remaining: remaining ?? received,
    );
    final row = await db.customSelect(
      'SELECT id FROM product_batches WHERE batch_number = ?',
      variables: [Variable.withString(batchNumber)],
    ).getSingle();
    return row.data['id'] as int;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // I-DB-1: remaining_quantity >= 0
  // ──────────────────────────────────────────────────────────────────────────

  test(
    'I-DB-1 INSERT: rejects remaining_quantity < 0 with RAISE(ABORT)',
    () async {
      await expectLater(
        () => insertBatchRaw(
          batchNumber: 'B-NEG-INSERT',
          received: 10,
          remaining: -1,
        ),
        throwsA(predicate(
          (e) => e.toString().contains('remaining_quantity must be >= 0'),
          'message contains "remaining_quantity must be >= 0"',
        )),
      );

      // Verify the row was NOT inserted (BEFORE INSERT trigger short-circuits).
      final count = await db.customSelect(
        'SELECT COUNT(*) AS c FROM product_batches WHERE batch_number = ?',
        variables: [Variable.withString('B-NEG-INSERT')],
      ).getSingle();
      expect(count.data['c'], equals(0));
    },
  );

  test(
    'I-DB-1 UPDATE: rejects remaining_quantity going below zero',
    () async {
      final batchId = await insertValidBatch(
        batchNumber: 'B-NEG-UPDATE',
        received: 10,
        remaining: 5,
      );

      await expectLater(
        () => db.customStatement(
          'UPDATE product_batches SET remaining_quantity = -3 WHERE id = ?',
          [batchId],
        ),
        throwsA(predicate(
          (e) => e.toString().contains('remaining_quantity must be >= 0'),
        )),
      );

      // Original value is preserved.
      final row = await db.customSelect(
        'SELECT remaining_quantity AS r FROM product_batches WHERE id = ?',
        variables: [Variable.withInt(batchId)],
      ).getSingle();
      expect(row.data['r'], equals(5));
    },
  );

  // ──────────────────────────────────────────────────────────────────────────
  // I-DB-2: remaining_quantity <= received_quantity
  // ──────────────────────────────────────────────────────────────────────────

  test(
    'I-DB-2 INSERT: rejects remaining_quantity > received_quantity',
    () async {
      await expectLater(
        () => insertBatchRaw(
          batchNumber: 'B-OVER-INSERT',
          received: 10,
          remaining: 11,
        ),
        throwsA(predicate(
          (e) => e
              .toString()
              .contains('remaining_quantity must be <= received_quantity'),
          'message contains "remaining_quantity must be <= received_quantity"',
        )),
      );
    },
  );

  test(
    'I-DB-2 UPDATE: rejects remaining_quantity climbing above received_quantity '
    '(catches return-overflow bugs)',
    () async {
      final batchId = await insertValidBatch(
        batchNumber: 'B-OVER-UPDATE',
        received: 10,
        remaining: 5,
      );

      // Simulate a buggy "return restoration" path that double-restores.
      await expectLater(
        () => db.customStatement(
          'UPDATE product_batches SET remaining_quantity = 12 WHERE id = ?',
          [batchId],
        ),
        throwsA(predicate(
          (e) => e
              .toString()
              .contains('remaining_quantity must be <= received_quantity'),
        )),
      );

      final row = await db.customSelect(
        'SELECT remaining_quantity AS r FROM product_batches WHERE id = ?',
        variables: [Variable.withInt(batchId)],
      ).getSingle();
      expect(row.data['r'], equals(5));
    },
  );

  // ──────────────────────────────────────────────────────────────────────────
  // Positive cases — valid mutations must still pass through unchanged.
  // ──────────────────────────────────────────────────────────────────────────

  test(
    'valid INSERT (0 <= remaining <= received) succeeds',
    () async {
      await insertBatchRaw(
        batchNumber: 'B-VALID-FULL',
        received: 10,
        remaining: 10,
      );
      await insertBatchRaw(
        batchNumber: 'B-VALID-PARTIAL',
        received: 10,
        remaining: 3,
      );
      await insertBatchRaw(
        batchNumber: 'B-VALID-EMPTY',
        received: 10,
        remaining: 0,
      );

      final count = await db.customSelect(
        "SELECT COUNT(*) AS c FROM product_batches WHERE batch_number LIKE 'B-VALID-%'",
      ).getSingle();
      expect(count.data['c'], equals(3));
    },
  );

  test(
    'valid UPDATE (consume down to zero, restore back up) succeeds',
    () async {
      final batchId = await insertValidBatch(
        batchNumber: 'B-CYCLE',
        received: 10,
        remaining: 10,
      );

      // Simulate FIFO consumption to zero.
      await db.customStatement(
        'UPDATE product_batches SET remaining_quantity = 0 WHERE id = ?',
        [batchId],
      );

      // Simulate sale-return restoring back up to (but not exceeding) received.
      await db.customStatement(
        'UPDATE product_batches SET remaining_quantity = 10 WHERE id = ?',
        [batchId],
      );

      final row = await db.customSelect(
        'SELECT remaining_quantity AS r FROM product_batches WHERE id = ?',
        variables: [Variable.withInt(batchId)],
      ).getSingle();
      expect(row.data['r'], equals(10));
    },
  );

  // ──────────────────────────────────────────────────────────────────────────
  // Trigger introspection — proves all four triggers were actually installed.
  // ──────────────────────────────────────────────────────────────────────────

  test(
    'all four integrity triggers are present in sqlite_master',
    () async {
      final rows = await db.customSelect(
        "SELECT name FROM sqlite_master WHERE type = 'trigger' AND name LIKE 'trg_product_batches_%' ORDER BY name",
      ).get();
      final names = rows.map((r) => r.data['name'] as String).toList();
      expect(
        names,
        containsAll(<String>[
          'trg_product_batches_remaining_le_received_insert',
          'trg_product_batches_remaining_le_received_update',
          'trg_product_batches_remaining_nonneg_insert',
          'trg_product_batches_remaining_nonneg_update',
        ]),
      );
    },
  );

  test(
    'installProductBatchesIntegrityTriggersForTest is idempotent '
    '(safe to call repeatedly)',
    () async {
      // Already installed via onCreate. Calling again must not throw.
      await db.installProductBatchesIntegrityTriggersForTest();
      await db.installProductBatchesIntegrityTriggersForTest();

      // Behavior must remain identical: invariant still enforced.
      await expectLater(
        () => insertBatchRaw(
          batchNumber: 'B-IDEMPOTENT',
          received: 5,
          remaining: -1,
        ),
        throwsA(predicate(
          (e) => e.toString().contains('remaining_quantity must be >= 0'),
        )),
      );
    },
  );
}
