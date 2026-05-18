// ─────────────────────────────────────────────────────────────────────────────
// ExpiryAlertService — Drift integration tests
//
// Phase E. The service powers BOTH the dashboard widget (top-N preview) and
// the full expiry report screen. They MUST share an identical view of the
// data, which is why all bucket math lives in this single class.
//
// Rules under test:
//   1. Only `inventory_tracking_type = 'batch_expiry'` products are surfaced.
//      `'batch'`-only and `'standard'` products never raise alerts.
//   2. Only `is_active = 1` products and `is_active = 1` batches are counted.
//   3. Batches with `remaining_quantity = 0` are excluded.
//   4. Batches with `expiry_date IS NULL` are excluded (defensive: the schema
//      allows NULL even on batch_expiry products, but the alert is undefined).
//   5. Batches beyond the 90-day horizon are excluded.
//   6. Bucket assignment:
//        diffDays <=  0 → expired
//        diffDays <= 30 → in30Days
//        diffDays <= 60 → in60Days
//        diffDays <= 90 → in90Days
//   7. `expiredCostCents = Σ remaining_quantity × unit_cost_cents` (the value
//      the business is about to write off).
//   8. Items are ordered by `expiry_date ASC` (FEFO surfacing).
// ─────────────────────────────────────────────────────────────────────────────

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/services/inventory/expiry_alert_service.dart';
import 'package:tapix/features/inventory/domain/entities/expiry_alert_item.dart';

void main() {
  late AppDatabase database;
  late int currencyId;
  late DateTime fixedNow;
  late ExpiryAlertService service;

  setUp(() async {
    database = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    final currencies = await database.select(database.currencies).get();
    currencyId = currencies.first.id;

    // Anchor the service to a fixed midday so we never straddle midnight in CI.
    fixedNow = DateTime(2026, 6, 15, 12);
    service = ExpiryAlertService(database, now: () => fixedNow);
  });

  tearDown(() async {
    await database.close();
  });

  // ── helpers ────────────────────────────────────────────────────────────────

  DateTime startOfFixedToday() =>
      DateTime(fixedNow.year, fixedNow.month, fixedNow.day);

  Future<int> insertProduct({
    required String sku,
    required String trackingType,
    bool isActive = true,
  }) {
    return database.into(database.products).insert(
          ProductsCompanion.insert(
            sku: Value<String?>(sku),
            name: 'P-$sku',
            costCents: Decimal.fromInt(100),
            priceCents: Decimal.fromInt(200),
            currencyId: Value(currencyId),
            inventoryTrackingType: Value(trackingType),
            isActive: Value(isActive),
          ),
        );
  }

  Future<int> insertBatch({
    required int productId,
    required String batchNumber,
    required int remaining,
    required DateTime? expiry,
    int unitCostCents = 1000,
    int received = 100,
    bool isActive = true,
  }) async {
    return database.into(database.productBatches).insert(
          ProductBatchesCompanion.insert(
            productId: productId,
            batchNumber: batchNumber,
            receivedQuantity: received,
            remainingQuantity: remaining,
            unitCostCents: Decimal.fromInt(unitCostCents),
            expiryDate: Value(expiry),
            isActive: Value(isActive),
          ),
        );
  }

  group('ExpiryAlertService.fetchAlerts', () {
    test('empty DB returns ExpiryAlertSnapshot.empty', () async {
      final snap = await service.fetchAlerts();
      expect(snap.items, isEmpty);
      expect(snap.summary.totalAlertCount, 0);
      expect(snap.summary.expiredCostCents, 0);
    });

    test('ignores standard and batch-only tracking types', () async {
      final stdId =
          await insertProduct(sku: 'STD-1', trackingType: 'standard');
      final batchId = await insertProduct(sku: 'BCH-1', trackingType: 'batch');
      // Even with imminent expiries, neither product should appear.
      await insertBatch(
        productId: stdId,
        batchNumber: 'B-STD',
        remaining: 5,
        expiry: startOfFixedToday().add(const Duration(days: 3)),
      );
      await insertBatch(
        productId: batchId,
        batchNumber: 'B-BCH',
        remaining: 5,
        expiry: startOfFixedToday().add(const Duration(days: 3)),
      );

      final snap = await service.fetchAlerts();
      expect(snap.items, isEmpty);
    });

    test('ignores inactive products and inactive batches', () async {
      final inactiveProd = await insertProduct(
        sku: 'EXP-1',
        trackingType: 'batch_expiry',
        isActive: false,
      );
      await insertBatch(
        productId: inactiveProd,
        batchNumber: 'B1',
        remaining: 10,
        expiry: startOfFixedToday().add(const Duration(days: 5)),
      );

      final activeProd =
          await insertProduct(sku: 'EXP-2', trackingType: 'batch_expiry');
      await insertBatch(
        productId: activeProd,
        batchNumber: 'B2',
        remaining: 10,
        expiry: startOfFixedToday().add(const Duration(days: 5)),
        isActive: false, // batch is inactive
      );

      final snap = await service.fetchAlerts();
      expect(snap.items, isEmpty);
    });

    test('ignores batches with remaining_quantity = 0 or NULL expiry',
        () async {
      final pid =
          await insertProduct(sku: 'EXP-3', trackingType: 'batch_expiry');
      await insertBatch(
        productId: pid,
        batchNumber: 'B-Z',
        remaining: 0, // depleted
        expiry: startOfFixedToday().add(const Duration(days: 5)),
      );
      await insertBatch(
        productId: pid,
        batchNumber: 'B-NULL',
        remaining: 10,
        expiry: null, // missing expiry on a batch_expiry product
      );

      final snap = await service.fetchAlerts();
      expect(snap.items, isEmpty);
    });

    test('ignores batches beyond the 90-day horizon', () async {
      final pid =
          await insertProduct(sku: 'EXP-4', trackingType: 'batch_expiry');
      await insertBatch(
        productId: pid,
        batchNumber: 'FAR',
        remaining: 10,
        expiry: startOfFixedToday().add(const Duration(days: 100)),
      );

      final snap = await service.fetchAlerts();
      expect(snap.items, isEmpty);
    });

    test('classifies into the 4 buckets at the correct boundaries', () async {
      final pid =
          await insertProduct(sku: 'EXP-5', trackingType: 'batch_expiry');
      final today = startOfFixedToday();

      await insertBatch(
        productId: pid,
        batchNumber: 'EXP',
        remaining: 1,
        expiry: today.subtract(const Duration(days: 2)), // expired
      );
      await insertBatch(
        productId: pid,
        batchNumber: 'D30',
        remaining: 1,
        expiry: today.add(const Duration(days: 30)), // bucket boundary in30
      );
      await insertBatch(
        productId: pid,
        batchNumber: 'D45',
        remaining: 1,
        expiry: today.add(const Duration(days: 45)), // in60
      );
      await insertBatch(
        productId: pid,
        batchNumber: 'D75',
        remaining: 1,
        expiry: today.add(const Duration(days: 75)), // in90
      );
      await insertBatch(
        productId: pid,
        batchNumber: 'D90',
        remaining: 1,
        expiry: today.add(const Duration(days: 90)), // bucket boundary in90
      );

      final snap = await service.fetchAlerts();
      expect(snap.items, hasLength(5));

      ExpiryBucket bucketOf(String batchNumber) =>
          snap.items.firstWhere((i) => i.batchNumber == batchNumber).bucket;

      expect(bucketOf('EXP'), ExpiryBucket.expired);
      expect(bucketOf('D30'), ExpiryBucket.in30Days);
      expect(bucketOf('D45'), ExpiryBucket.in60Days);
      expect(bucketOf('D75'), ExpiryBucket.in90Days);
      expect(bucketOf('D90'), ExpiryBucket.in90Days);

      expect(snap.summary.expiredCount, 1);
      expect(snap.summary.in30DaysCount, 1);
      expect(snap.summary.in60DaysCount, 1);
      expect(snap.summary.in90DaysCount, 2);
      expect(snap.summary.totalAlertCount, 5);
    });

    test('today (diffDays == 0) is bucketed as expired', () async {
      final pid =
          await insertProduct(sku: 'TDY', trackingType: 'batch_expiry');
      // Expires later today (8pm) — same calendar day as fixedNow.
      await insertBatch(
        productId: pid,
        batchNumber: 'T-NOW',
        remaining: 3,
        expiry: DateTime(fixedNow.year, fixedNow.month, fixedNow.day, 20),
      );
      final snap = await service.fetchAlerts();
      expect(snap.items, hasLength(1));
      expect(snap.items.single.bucket, ExpiryBucket.expired);
      expect(snap.items.single.daysUntilExpiry, 0);
    });

    test(
        'expiredCostCents sums remaining_quantity × unit_cost_cents over '
        'expired batches only', () async {
      final pid =
          await insertProduct(sku: 'WO', trackingType: 'batch_expiry');
      final today = startOfFixedToday();

      // Two expired batches → contribute to expiredCostCents.
      await insertBatch(
        productId: pid,
        batchNumber: 'E1',
        remaining: 4,
        unitCostCents: 250, // 4 × 250 = 1000
        expiry: today.subtract(const Duration(days: 1)),
      );
      await insertBatch(
        productId: pid,
        batchNumber: 'E2',
        remaining: 6,
        unitCostCents: 500, // 6 × 500 = 3000
        expiry: today.subtract(const Duration(days: 5)),
      );
      // Near-expiry batch — must NOT contribute.
      await insertBatch(
        productId: pid,
        batchNumber: 'NEAR',
        remaining: 100,
        unitCostCents: 999,
        expiry: today.add(const Duration(days: 10)),
      );

      final snap = await service.fetchAlerts();
      expect(snap.summary.expiredCount, 2);
      expect(snap.summary.expiredCostCents, 4000);
    });

    test('items are ordered by expiry_date ascending (FEFO)', () async {
      final pid =
          await insertProduct(sku: 'FEFO', trackingType: 'batch_expiry');
      final today = startOfFixedToday();
      // Insert in non-FEFO order on purpose.
      await insertBatch(
        productId: pid,
        batchNumber: 'D60',
        remaining: 1,
        expiry: today.add(const Duration(days: 60)),
      );
      await insertBatch(
        productId: pid,
        batchNumber: 'D5',
        remaining: 1,
        expiry: today.add(const Duration(days: 5)),
      );
      await insertBatch(
        productId: pid,
        batchNumber: 'D25',
        remaining: 1,
        expiry: today.add(const Duration(days: 25)),
      );
      final snap = await service.fetchAlerts();
      expect(
        snap.items.map((i) => i.batchNumber).toList(),
        ['D5', 'D25', 'D60'],
      );
    });
  });

  group('ExpiryAlertService.watchAlerts', () {
    test('emits an initial snapshot then re-emits on insert', () async {
      final pid =
          await insertProduct(sku: 'STR', trackingType: 'batch_expiry');
      // Seed one row before subscribing.
      await insertBatch(
        productId: pid,
        batchNumber: 'A',
        remaining: 1,
        expiry: startOfFixedToday().add(const Duration(days: 10)),
      );

      final emissions = <int>[];
      final sub = service.watchAlerts().listen((s) {
        emissions.add(s.items.length);
      });

      // Wait for the initial emission.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await insertBatch(
        productId: pid,
        batchNumber: 'B',
        remaining: 1,
        expiry: startOfFixedToday().add(const Duration(days: 20)),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await sub.cancel();
      // First emission saw 1 row, follow-up emission saw 2.
      expect(emissions.first, 1);
      expect(emissions.last, 2);
    });
  });
}
