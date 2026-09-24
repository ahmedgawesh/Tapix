import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/database/daos/adjustment_return_dao.dart';

/// ────────────────────────────────────────────────────────────────────────────
/// Phase 0.5 — Idempotency keys on returns.
///
/// All four returns tables (purchase_returns, sale_returns,
/// purchase_return_adjustments, sale_return_adjustments) carry a UNIQUE
/// `idempotency_key`. A duplicated submission (double-tap, retried network
/// call) MUST throw — never create a second ledger / stock movement / JE.
/// ────────────────────────────────────────────────────────────────────────────
void main() {
  late AppDatabase db;
  late AdjustmentReturnDao adjDao;

  setUp(() async {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    adjDao = AdjustmentReturnDao(db);
    await db.customSelect('SELECT 1').get();
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await db.customStatement(
      'INSERT OR IGNORE INTO users (id, username, password_hash, role, '
      'is_active, created_at, updated_at) '
      "VALUES (0, 'system', 'no-pin', 'owner', 1, $now, $now)",
    );
  });

  tearDown(() async => db.close());

  Future<({int currencyId, int customerId, int supplierId, int productId})>
  seed() async {
    final usd = await (db.select(
      db.currencies,
    )..where((c) => c.code.equals('USD'))).getSingle();
    final cid = await db
        .into(db.customers)
        .insert(
          CustomersCompanion.insert(
            name: 'Idem Customer',
            currencyId: usd.id,
            balanceCents: Value(Decimal.zero),
          ),
        );
    final sid = await db
        .into(db.suppliers)
        .insert(
          SuppliersCompanion.insert(
            name: 'Idem Supplier',
            currencyId: usd.id,
            balanceCents: Value(Decimal.zero),
          ),
        );
    final pid = await db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            sku: const Value<String?>('IDEM-1'),
            name: 'Idem Product',
            costCents: Decimal.fromInt(1000),
            priceCents: Decimal.fromInt(2000),
            currencyId: Value(usd.id),
            stockQuantity: const Value(100),
          ),
        );
    await db
        .into(db.productVariants)
        .insert(
          ProductVariantsCompanion.insert(
            productId: pid,
            stockQuantity: const Value(100),
            costCents: Decimal.fromInt(1000),
            priceCents: Decimal.fromInt(2000),
          ),
        );
    return (
      currencyId: usd.id,
      customerId: cid,
      supplierId: sid,
      productId: pid,
    );
  }

  test(
    'purchase adjustment return UNIQUE idempotency key blocks duplicate',
    () async {
      final s = await seed();
      const key = 'idem-par-001';

      final headerOk = PurchaseReturnAdjustmentsCompanion.insert(
        returnNumber: 'PAR-IDEM-1',
        supplierId: s.supplierId,
        currencyId: s.currencyId,
        totalCents: Decimal.fromInt(1000),
        idempotencyKey: const Value(key),
      );
      final items = [
        PurchaseReturnAdjustmentItemsCompanion.insert(
          returnId: 0,
          productId: s.productId,
          quantity: 1,
          unitPriceCents: Decimal.fromInt(1000),
          totalCents: Decimal.fromInt(1000),
        ),
      ];

      final firstId = await adjDao.createPurchaseAdjReturn(headerOk, items);
      expect(firstId, greaterThan(0));

      // Second submission with same key must throw a UNIQUE-constraint error.
      expect(
        () async => adjDao.createPurchaseAdjReturn(
          PurchaseReturnAdjustmentsCompanion.insert(
            returnNumber: 'PAR-IDEM-1-DUP',
            supplierId: s.supplierId,
            currencyId: s.currencyId,
            totalCents: Decimal.fromInt(1000),
            idempotencyKey: const Value(key),
          ),
          items,
        ),
        throwsA(isA<Exception>()),
      );

      // Verify exactly ONE row exists.
      final rows = await db
          .customSelect(
            'SELECT COUNT(*) AS c FROM purchase_return_adjustments '
            'WHERE idempotency_key = ?',
            variables: [Variable.withString(key)],
          )
          .getSingle();
      expect(rows.read<int>('c'), equals(1));
    },
  );

  test(
    'sale adjustment return UNIQUE idempotency key blocks duplicate',
    () async {
      final s = await seed();
      const key = 'idem-sar-001';

      final header = SaleReturnAdjustmentsCompanion.insert(
        returnNumber: 'SAR-IDEM-1',
        customerId: Value(s.customerId),
        currencyId: s.currencyId,
        totalCents: Decimal.fromInt(2000),
        refundMethod: const Value('cash'),
        idempotencyKey: const Value(key),
      );
      final items = [
        SaleReturnAdjustmentItemsCompanion.insert(
          sourceResolution: const Value('unverified'),
          sourceResolutionReason: const Value('test fixture'),
          returnId: 0,
          productId: s.productId,
          quantity: 1,
          unitPriceCents: Decimal.fromInt(2000),
          totalCents: Decimal.fromInt(2000),
        ),
      ];

      await adjDao.createSaleAdjReturn(header, items);

      expect(
        () async => adjDao.createSaleAdjReturn(
          SaleReturnAdjustmentsCompanion.insert(
            returnNumber: 'SAR-IDEM-1-DUP',
            customerId: Value(s.customerId),
            currencyId: s.currencyId,
            totalCents: Decimal.fromInt(2000),
            refundMethod: const Value('cash'),
            idempotencyKey: const Value(key),
          ),
          items,
        ),
        throwsA(isA<Exception>()),
      );

      final rows = await db
          .customSelect(
            'SELECT COUNT(*) AS c FROM sale_return_adjustments '
            'WHERE idempotency_key = ?',
            variables: [Variable.withString(key)],
          )
          .getSingle();
      expect(rows.read<int>('c'), equals(1));
    },
  );

  test('null idempotency key allows multiple inserts (back-compat)', () async {
    final s = await seed();

    final header1 = PurchaseReturnAdjustmentsCompanion.insert(
      returnNumber: 'PAR-NULL-1',
      supplierId: s.supplierId,
      currencyId: s.currencyId,
      totalCents: Decimal.fromInt(1000),
    );
    final header2 = PurchaseReturnAdjustmentsCompanion.insert(
      returnNumber: 'PAR-NULL-2',
      supplierId: s.supplierId,
      currencyId: s.currencyId,
      totalCents: Decimal.fromInt(1000),
    );
    final items = [
      PurchaseReturnAdjustmentItemsCompanion.insert(
        returnId: 0,
        productId: s.productId,
        quantity: 1,
        unitPriceCents: Decimal.fromInt(1000),
        totalCents: Decimal.fromInt(1000),
      ),
    ];

    final id1 = await adjDao.createPurchaseAdjReturn(header1, items);
    final id2 = await adjDao.createPurchaseAdjReturn(header2, items);
    expect(id1, isNot(equals(id2)));
  });
}
