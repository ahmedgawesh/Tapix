// ─────────────────────────────────────────────────────────────────────────────
// ProductDao.watchExpirySummaries — Drift integration tests
//
// The query is a hot path on the product list (one stream subscription, runs
// over `products ⨯ product_batches`), so the rules it encodes are easy to
// regress silently. This file asserts each rule with a minimal seeded DB so
// any future change to the SQL (or a schema rename) trips a test.
//
// Rules under test:
//   1. Only `inventory_tracking_type = 'batch_expiry'` products appear.
//   2. Only `is_active = 1` batches with `remaining_quantity > 0` are counted.
//   3. `expired_qty` sums remaining qty across batches with `expiry_date < today`.
//   4. `next_expiry_iso` = MIN(expiry_date) over batches with `expiry_date >= today`.
//   5. Products whose only remaining stock is already expired return
//      `expired_qty > 0` AND `next_expiry_iso == null` (still emitted).
//   6. Products with no expiry-tracked stock are entirely absent from the map.
//   7. Healthy products (only future expiries) emit a single nearest date.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/database/app_database.dart';

void main() {
  late AppDatabase database;
  late int currencyId;

  setUp(() async {
    database = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    final currencies = await database.select(database.currencies).get();
    currencyId = currencies.first.id;
  });

  tearDown(() async {
    await database.close();
  });

  // ── helpers ────────────────────────────────────────────────────────────────

  Future<int> insertProduct({
    required String sku,
    required String trackingType,
  }) {
    return database.into(database.products).insert(
          ProductsCompanion.insert(
            sku: Value<String?>(sku),
            name: 'P-$sku',
            costCents: Decimal.fromInt(100),
            priceCents: Decimal.fromInt(200),
            currencyId: Value(currencyId),
            inventoryTrackingType: Value(trackingType),
          ),
        );
  }

  Future<void> insertBatch({
    required int productId,
    required String batchNumber,
    required int remaining,
    required DateTime? expiry,
    int received = 100,
    bool isActive = true,
  }) async {
    await database.into(database.productBatches).insert(
          ProductBatchesCompanion.insert(
            productId: productId,
            batchNumber: batchNumber,
            receivedQuantity: received,
            remainingQuantity: remaining,
            unitCostCents: Decimal.fromInt(1000),
            expiryDate: Value(expiry),
            isActive: Value(isActive),
          ),
        );
  }

  // Today, normalised to start-of-day, mirroring the DAO. We compute test
  // expiry dates relative to *now* so the test is timezone-independent.
  DateTime startOfToday() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  group('ProductDao.watchExpirySummaries', () {
    test('returns empty map when no batch_expiry products exist', () async {
      // Standard + plain-batch products are filtered out by the WHERE clause.
      final standardId = await insertProduct(
        sku: 'STD-1',
        trackingType: 'standard',
      );
      final batchId = await insertProduct(
        sku: 'BAT-1',
        trackingType: 'batch',
      );
      // Even with batches, neither should appear.
      await insertBatch(
        productId: standardId,
        batchNumber: 'B-STD',
        remaining: 10,
        expiry: startOfToday().add(const Duration(days: 5)),
      );
      await insertBatch(
        productId: batchId,
        batchNumber: 'B-BAT',
        remaining: 10,
        expiry: startOfToday().add(const Duration(days: 5)),
      );

      final result = await database.productDao.watchExpirySummaries().first;
      expect(result, isEmpty);
    });

    test('emits a row only for the batch_expiry product (rule #1)', () async {
      final standardId = await insertProduct(
        sku: 'STD-2',
        trackingType: 'standard',
      );
      final pharmId = await insertProduct(
        sku: 'PHARM-1',
        trackingType: 'batch_expiry',
      );

      await insertBatch(
        productId: standardId,
        batchNumber: 'B-STD-2',
        remaining: 5,
        expiry: startOfToday().add(const Duration(days: 1)),
      );
      await insertBatch(
        productId: pharmId,
        batchNumber: 'B-PH-1',
        remaining: 7,
        expiry: startOfToday().add(const Duration(days: 10)),
      );

      final result = await database.productDao.watchExpirySummaries().first;
      expect(result.keys, [pharmId]);
      expect(result[pharmId]!.expiredQty, 0);
      expect(result[pharmId]!.nextExpiry, isNotNull);
    });

    test('skips inactive batches and zero-remaining batches (rule #2)',
        () async {
      final pharmId = await insertProduct(
        sku: 'PHARM-2',
        trackingType: 'batch_expiry',
      );

      // Inactive batch — must be ignored entirely.
      await insertBatch(
        productId: pharmId,
        batchNumber: 'B-INACT',
        remaining: 50,
        expiry: startOfToday().add(const Duration(days: 3)),
        isActive: false,
      );
      // Active but fully consumed — must be ignored.
      await insertBatch(
        productId: pharmId,
        batchNumber: 'B-EMPTY',
        remaining: 0,
        expiry: startOfToday().add(const Duration(days: 3)),
      );
      // The only batch that should drive the summary.
      await insertBatch(
        productId: pharmId,
        batchNumber: 'B-LIVE',
        remaining: 4,
        expiry: startOfToday().add(const Duration(days: 20)),
      );

      final result = await database.productDao.watchExpirySummaries().first;
      expect(result[pharmId]!.expiredQty, 0,
          reason: 'inactive/empty batches must not contribute');
      expect(
        result[pharmId]!.nextExpiry!.difference(startOfToday()).inDays,
        20,
        reason: 'nearest expiry must be the only live batch',
      );
    });

    test(
        'expired_qty sums remaining over expired batches; '
        'next_expiry_iso reflects MIN(future) (rules #3 + #4)', () async {
      final pharmId = await insertProduct(
        sku: 'PHARM-3',
        trackingType: 'batch_expiry',
      );

      // Two expired-with-stock batches: total expiredQty = 6+9 = 15.
      await insertBatch(
        productId: pharmId,
        batchNumber: 'B-EXP-A',
        remaining: 6,
        expiry: startOfToday().subtract(const Duration(days: 2)),
      );
      await insertBatch(
        productId: pharmId,
        batchNumber: 'B-EXP-B',
        remaining: 9,
        expiry: startOfToday().subtract(const Duration(days: 30)),
      );
      // Two future batches: nearest = +5 days (not +40).
      await insertBatch(
        productId: pharmId,
        batchNumber: 'B-FUT-A',
        remaining: 12,
        expiry: startOfToday().add(const Duration(days: 40)),
      );
      await insertBatch(
        productId: pharmId,
        batchNumber: 'B-FUT-B',
        remaining: 3,
        expiry: startOfToday().add(const Duration(days: 5)),
      );

      final result = await database.productDao.watchExpirySummaries().first;
      expect(result[pharmId]!.expiredQty, 15);
      expect(
        result[pharmId]!.nextExpiry!.difference(startOfToday()).inDays,
        5,
      );
    });

    test('product with only expired stock emits expiredQty>0 + nextExpiry=null '
        '(rule #5)', () async {
      final pharmId = await insertProduct(
        sku: 'PHARM-4',
        trackingType: 'batch_expiry',
      );
      await insertBatch(
        productId: pharmId,
        batchNumber: 'B-ONLY-EXP',
        remaining: 4,
        expiry: startOfToday().subtract(const Duration(days: 1)),
      );

      final result = await database.productDao.watchExpirySummaries().first;
      expect(result[pharmId]!.expiredQty, 4);
      expect(result[pharmId]!.nextExpiry, isNull,
          reason: 'no future batches → nearestExpiry must be null');
    });

    test('product with NULL expiry_date is excluded (rule #6 — guarded by SQL)',
        () async {
      // Guard: even though the form blocks this in Phase C, defensive SQL
      // filters `expiry_date IS NOT NULL` so legacy / migration-imported rows
      // never produce a phantom badge.
      final pharmId = await insertProduct(
        sku: 'PHARM-5',
        trackingType: 'batch_expiry',
      );
      await insertBatch(
        productId: pharmId,
        batchNumber: 'B-NULL-EXP',
        remaining: 10,
        expiry: null,
      );

      final result = await database.productDao.watchExpirySummaries().first;
      expect(result, isEmpty);
    });

    test('healthy product with only future expiries reports nearest only '
        '(rule #7)', () async {
      final pharmId = await insertProduct(
        sku: 'PHARM-6',
        trackingType: 'batch_expiry',
      );
      await insertBatch(
        productId: pharmId,
        batchNumber: 'B-FAR-1',
        remaining: 100,
        expiry: startOfToday().add(const Duration(days: 180)),
      );
      await insertBatch(
        productId: pharmId,
        batchNumber: 'B-FAR-2',
        remaining: 100,
        expiry: startOfToday().add(const Duration(days: 365)),
      );

      final result = await database.productDao.watchExpirySummaries().first;
      expect(result[pharmId]!.expiredQty, 0);
      expect(
        result[pharmId]!.nextExpiry!.difference(startOfToday()).inDays,
        180,
      );
    });

    test('multiple batch_expiry products are emitted independently', () async {
      final aId =
          await insertProduct(sku: 'PHARM-A', trackingType: 'batch_expiry');
      final bId =
          await insertProduct(sku: 'PHARM-B', trackingType: 'batch_expiry');
      await insertBatch(
        productId: aId,
        batchNumber: 'BA-1',
        remaining: 2,
        expiry: startOfToday().subtract(const Duration(days: 1)),
      );
      await insertBatch(
        productId: bId,
        batchNumber: 'BB-1',
        remaining: 8,
        expiry: startOfToday().add(const Duration(days: 7)),
      );

      final result = await database.productDao.watchExpirySummaries().first;
      expect(result.length, 2);
      expect(result[aId]!.expiredQty, 2);
      expect(result[aId]!.nextExpiry, isNull);
      expect(result[bId]!.expiredQty, 0);
      expect(
        result[bId]!.nextExpiry!.difference(startOfToday()).inDays,
        7,
      );
    });
  });
}
