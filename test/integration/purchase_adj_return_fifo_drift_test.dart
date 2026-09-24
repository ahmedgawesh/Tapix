// Regression — FIFO purchase ADJUSTMENT (unlinked) return must NOT drift the
// Inventory (1200) GL away from Σ(batch.remaining × batch.unit_cost).
//
// Field-reported bug (June 2026):
//
//   A FIFO product was bought in two lots at different unit costs. The
//   product's *current* cost_cents (a DISPLAY value = latest paid cost) was
//   frozen onto the purchase-adjustment-return line. On post the goods left
//   the OLDEST (cheaper) batch via FIFO consumption, but the Inventory GL leg
//   was credited with the FROZEN product cost × qty instead of the ACTUAL
//   batch cost consumed. The difference (batch_cost − product_cost) × qty
//   silently drifted GL(1200) away from Σ(stock × cost) — exactly the
//   reconciliation mismatch the Health screen later reported.
//
// The fix: the 1200 leg is now sourced from the actual FIFO batch consumption
// (Σ batch_consumptions.totalCostCents), so the GL reduction equals the
// physical valuation reduction. The refund-vs-cost difference is a purchase
// price variance routed to 4100 / 5300.
import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/database/daos/accounting_dao.dart';
import 'package:tapix/core/database/daos/adjustment_return_dao.dart';
import 'package:tapix/core/services/journal_entry_service.dart';
import 'package:tapix/features/accounting/data/datasources/journal_local_datasource.dart';
import 'package:tapix/features/accounting/data/repositories/accounting_repository.dart';

void main() {
  late AppDatabase db;
  late AdjustmentReturnDao adjDao;
  late JournalEntryService journalService;
  late JournalLocalDatasourceImpl valuationDs;

  setUp(() async {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    journalService = JournalEntryService(AccountingRepository(db));
    adjDao = AdjustmentReturnDao(db);
    valuationDs = JournalLocalDatasourceImpl(AccountingDao(db));

    await db.customSelect('SELECT 1').get(); // force schema + account seed
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await db.customStatement(
      'INSERT OR IGNORE INTO users (id, username, password_hash, role, '
      'is_active, created_at, updated_at) '
      "VALUES (0, 'system', 'no-pin', 'owner', 1, $now, $now)",
    );
  });

  tearDown(() async => db.close());

  Future<int> accountIdByCode(String code) async {
    final row = await db
        .customSelect(
          'SELECT id FROM accounts WHERE account_code = ?',
          variables: [Variable.withString(code)],
        )
        .getSingle();
    return row.read<int>('id');
  }

  /// Net credit posted to a given account by the JE of an adjustment return.
  Future<({int debit, int credit})> ledgerLineFor(
    String code,
    int returnId,
  ) async {
    final acctId = await accountIdByCode(code);
    final row = await db
        .customSelect(
          'SELECT COALESCE(SUM(jel.debit_cents),0) AS d, '
          '       COALESCE(SUM(jel.credit_cents),0) AS c '
          'FROM journal_entry_lines jel '
          'INNER JOIN journal_entries je ON je.id = jel.journal_entry_id '
          "WHERE je.source_table = 'purchase_return_adjustments' "
          '  AND je.source_id = ? AND je.status = ? AND jel.account_id = ?',
          variables: [
            Variable.withInt(returnId),
            Variable.withString('posted'),
            Variable.withInt(acctId),
          ],
        )
        .getSingle();
    return (debit: row.read<int>('d'), credit: row.read<int>('c'));
  }

  test('FIFO purchase adjustment return credits Inventory (1200) by the ACTUAL '
      'consumed batch cost, keeping GL == Σ(stock×cost)', () async {
    final usd = await (db.select(
      db.currencies,
    )..where((c) => c.code.equals('USD'))).getSingle();
    final currencyId = usd.id;

    final supplierId = await db
        .into(db.suppliers)
        .insert(
          SuppliersCompanion.insert(
            name: 'FIFO Drift Supplier',
            currencyId: currencyId,
            balanceCents: Value(Decimal.fromInt(100000)),
          ),
        );

    // FIFO product. cost_cents is a DISPLAY value = latest paid (5000),
    // deliberately DIFFERENT from the oldest batch (3000).
    final productId = await db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            name: 'FIFO Drift Product',
            costCents: Decimal.fromInt(5000),
            priceCents: Decimal.fromInt(8000),
            currencyId: Value(currencyId),
            costingMethod: const Value('fifo'),
            inventoryTrackingType: const Value('batch'),
            stockQuantity: const Value(15),
          ),
        );
    final variantId = await db
        .into(db.productVariants)
        .insert(
          ProductVariantsCompanion.insert(
            productId: productId,
            costCents: Decimal.fromInt(5000), // latest paid (display)
            priceCents: Decimal.fromInt(8000),
            stockQuantity: const Value(15),
          ),
        );

    // Two lots: oldest 10 @ 3000 (FIFO-first), newest 5 @ 5000.
    await db
        .into(db.productBatches)
        .insert(
          ProductBatchesCompanion.insert(
            productId: productId,
            variantId: Value(variantId),
            batchNumber: 'LOT-OLD',
            receivedQuantity: 10,
            remainingQuantity: 10,
            unitCostCents: Decimal.fromInt(3000),
            receivedDate: Value(DateTime(2026, 1, 1)),
          ),
        );
    await db
        .into(db.productBatches)
        .insert(
          ProductBatchesCompanion.insert(
            productId: productId,
            variantId: Value(variantId),
            batchNumber: 'LOT-NEW',
            receivedQuantity: 5,
            remainingQuantity: 5,
            unitCostCents: Decimal.fromInt(5000),
            receivedDate: Value(DateTime(2026, 2, 1)),
          ),
        );

    final valueBefore = await valuationDs.getTotalInventoryValueCents();
    expect(valueBefore, 10 * 3000 + 5 * 5000); // 55,000

    // Return 4 units → consumes 4 from the OLDEST lot @3000 = 12,000 actual.
    // The frozen line cost (product/variant current cost 5000) would WRONGLY
    // value this at 4 × 5000 = 20,000 — the 8,000 drift the bug produced.
    const returnQty = 4;
    final returnId = await adjDao.createAndPostPurchaseAdjReturn(
      PurchaseReturnAdjustmentsCompanion.insert(
        returnNumber: 'PAR-FIFO-DRIFT-1',
        supplierId: supplierId,
        currencyId: currencyId,
        totalCents: Decimal.fromInt(returnQty * 6000), // refund @ list 6000
        refundMethod: const Value('credit'),
        returnMode: const Value('adjustment'),
      ),
      [
        PurchaseReturnAdjustmentItemsCompanion.insert(
          returnId: 0,
          productId: productId,
          variantId: Value(variantId),
          quantity: returnQty,
          unitPriceCents: Decimal.fromInt(6000),
          unitCostCents: Value(
            Decimal.fromInt(5000),
          ), // FROZEN (wrong for FIFO)
          totalCents: Decimal.fromInt(returnQty * 6000),
          dispositionType: const Value('restock'),
        ),
      ],
      journalEntryService: journalService,
      allowOverHistory: true,
    );

    // ── Physical valuation dropped by the OLDEST-lot cost, not product cost.
    final valueAfter = await valuationDs.getTotalInventoryValueCents();
    expect(
      valueBefore - valueAfter,
      12000,
      reason: 'FIFO consumed 4 × 3000 from the oldest lot',
    );

    // ── The Inventory (1200) GL leg must equal that same 12,000 — NOT 20,000.
    final inv = await ledgerLineFor('1200', returnId);
    expect(
      inv.credit,
      12000,
      reason:
          'GL(1200) must be credited by the ACTUAL FIFO batch cost, '
          'never the frozen product cost (would be 20,000)',
    );

    // ── The core invariant: GL inventory movement == physical valuation move.
    expect(
      inv.credit,
      valueBefore - valueAfter,
      reason: 'no drift: 1200 reduction must equal Σ(stock×cost) reduction',
    );
  });
}
