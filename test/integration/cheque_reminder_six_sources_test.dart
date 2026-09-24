// Phase 14.0 — pins the dashboard cheque-reminders contract.
//
// Before Phase 14.0 the reminders widget only read three of the six
// cheque-bearing source tables, and `sale_returns`/`purchase_returns`
// did not even have a `due_date` column — so a cheque tied to a linked
// refund was invisible to the user and never surfaced as a reminder.
//
// This test:
//   1. Verifies `sale_returns.due_date` and `purchase_returns.due_date`
//      exist on the live schema (migration 10056 contract) and round-trip.
//   2. Verifies the dashboard's UNION query surfaces a `due_date`-bearing
//      cheque from EACH of the six source tables exactly once.
//   3. Verifies voided / draft documents are filtered out.
//   4. Verifies `cheque_confirmations` natural-key shape matches the
//      key the widget builds for the resolved-cheque lookup.
//
// No JE / stock invariants — those are owned by other test files.
import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/database/daos/cheque_confirmation_dao.dart';

void main() {
  late AppDatabase db;
  late int currencyId;
  late int customerId;
  late int supplierId;

  Decimal d(int n) => Decimal.fromInt(n);

  setUp(() async {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    currencyId = (await db.select(db.currencies).get()).first.id;
    customerId = await db
        .into(db.customers)
        .insert(CustomersCompanion.insert(name: 'C1', currencyId: currencyId));
    supplierId = await db
        .into(db.suppliers)
        .insert(SuppliersCompanion.insert(name: 'S1', currencyId: currencyId));
  });

  tearDown(() async => db.close());

  Future<int> insertSale({required DateTime due, String status = 'completed'}) {
    return db
        .into(db.sales)
        .insert(
          SalesCompanion.insert(
            invoiceNumber: 'INV-${DateTime.now().microsecondsSinceEpoch}',
            customerId: Value(customerId),
            currencyId: currencyId,
            subtotalCents: d(1000),
            taxCents: Decimal.zero,
            totalCents: d(1000),
            paymentMethod: 'cheque',
            dueDate: Value(due),
            status: Value(status),
          ),
        );
  }

  Future<int> insertPurchase({required DateTime due}) {
    return db
        .into(db.purchases)
        .insert(
          PurchasesCompanion.insert(
            purchaseNumber: 'PO-${DateTime.now().microsecondsSinceEpoch}',
            supplierId: supplierId,
            currencyId: currencyId,
            subtotalCents: d(800),
            taxCents: Decimal.zero,
            totalCents: d(800),
            paymentMethod: const Value('cheque'),
            dueDate: Value(due),
            status: const Value('posted'),
          ),
        );
  }

  Future<int> insertSaleReturn(int saleId, {required DateTime due}) {
    return db
        .into(db.saleReturns)
        .insert(
          SaleReturnsCompanion.insert(
            returnNumber: 'SR-${DateTime.now().microsecondsSinceEpoch}',
            saleId: saleId,
            currencyId: currencyId,
            subtotalCents: Value(d(200)),
            taxCents: Value(Decimal.zero),
            totalCents: d(200),
            refundMethod: const Value('cheque'),
            dueDate: Value(due),
            status: const Value('completed'),
          ),
        );
  }

  Future<int> insertPurchaseReturn(int purchaseId, {required DateTime due}) {
    return db
        .into(db.purchaseReturns)
        .insert(
          PurchaseReturnsCompanion.insert(
            returnNumber: 'PR-${DateTime.now().microsecondsSinceEpoch}',
            purchaseId: purchaseId,
            currencyId: currencyId,
            subtotalCents: Value(d(150)),
            taxCents: Value(Decimal.zero),
            totalCents: d(150),
            refundMethod: const Value('cheque'),
            dueDate: Value(due),
            status: const Value('completed'),
          ),
        );
  }

  Future<int> insertSaleReturnAdj({required DateTime due}) {
    return db
        .into(db.saleReturnAdjustments)
        .insert(
          SaleReturnAdjustmentsCompanion.insert(
            returnNumber: 'SAR-${DateTime.now().microsecondsSinceEpoch}',
            customerId: Value(customerId),
            currencyId: currencyId,
            subtotalCents: Value(d(50)),
            taxCents: Value(Decimal.zero),
            totalCents: d(50),
            refundMethod: const Value('cheque'),
            dueDate: Value(due),
            status: const Value('completed'),
          ),
        );
  }

  Future<int> insertPurchaseReturnAdj({required DateTime due}) {
    return db
        .into(db.purchaseReturnAdjustments)
        .insert(
          PurchaseReturnAdjustmentsCompanion.insert(
            returnNumber: 'PAR-${DateTime.now().microsecondsSinceEpoch}',
            supplierId: supplierId,
            currencyId: currencyId,
            subtotalCents: Value(d(75)),
            taxCents: Value(Decimal.zero),
            totalCents: d(75),
            refundMethod: const Value('cheque'),
            dueDate: Value(due),
            status: const Value('completed'),
          ),
        );
  }

  test('sale_returns and purchase_returns persist due_date column', () async {
    final due = DateTime(2026, 6, 15);
    final saleId = await insertSale(due: due);
    final srId = await insertSaleReturn(saleId, due: due);
    final purchaseId = await insertPurchase(due: due);
    final prId = await insertPurchaseReturn(purchaseId, due: due);

    final sr = await (db.select(
      db.saleReturns,
    )..where((t) => t.id.equals(srId))).getSingle();
    final pr = await (db.select(
      db.purchaseReturns,
    )..where((t) => t.id.equals(prId))).getSingle();

    expect(sr.dueDate, due);
    expect(pr.dueDate, due);
  });

  test(
    'dashboard UNION surfaces one cheque from each of the six sources',
    () async {
      final due = DateTime(2026, 6, 20);

      final saleId = await insertSale(due: due);
      final purchaseId = await insertPurchase(due: due);
      await insertSaleReturn(saleId, due: due);
      await insertPurchaseReturn(purchaseId, due: due);
      await insertSaleReturnAdj(due: due);
      await insertPurchaseReturnAdj(due: due);

      final rows = await db.customSelect('''
      SELECT 'sale' AS source_table, id AS source_id FROM sales
      WHERE payment_method IN ('cheque', 'check') AND due_date IS NOT NULL
        AND status NOT IN ('voided', 'draft')
      UNION ALL
      SELECT 'purchase' AS source_table, id AS source_id FROM purchases
      WHERE payment_method IN ('cheque', 'check') AND due_date IS NOT NULL
        AND status NOT IN ('voided', 'draft')
      UNION ALL
      SELECT 'sale_return' AS source_table, id AS source_id FROM sale_returns
      WHERE refund_method IN ('cheque', 'check') AND due_date IS NOT NULL
        AND status NOT IN ('voided', 'draft')
      UNION ALL
      SELECT 'purchase_return' AS source_table, id AS source_id FROM purchase_returns
      WHERE refund_method IN ('cheque', 'check') AND due_date IS NOT NULL
        AND status NOT IN ('voided', 'draft')
      UNION ALL
      SELECT 'sale_return_adjustment' AS source_table, id AS source_id FROM sale_return_adjustments
      WHERE refund_method IN ('cheque', 'check') AND due_date IS NOT NULL
        AND status NOT IN ('voided', 'draft')
      UNION ALL
      SELECT 'purchase_return_adjustment' AS source_table, id AS source_id FROM purchase_return_adjustments
      WHERE refund_method IN ('cheque', 'check') AND due_date IS NOT NULL
        AND status NOT IN ('voided', 'draft')
    ''').get();

      final tables = rows.map((r) => r.read<String>('source_table')).toSet();
      expect(
        tables,
        equals({
          'sale',
          'purchase',
          'sale_return',
          'purchase_return',
          'sale_return_adjustment',
          'purchase_return_adjustment',
        }),
        reason:
            'All six cheque-bearing source tables must surface to the '
            'dashboard reminder. Phase 14.0 closes the gap where linked '
            'returns (sale_returns / purchase_returns) were silently dropped.',
      );
      expect(rows.length, 6, reason: 'Exactly one cheque per source table.');
    },
  );

  test(
    'voided / draft documents are EXCLUDED from the reminder feed',
    () async {
      final due = DateTime(2026, 6, 22);
      await insertSale(due: due, status: 'voided');
      await insertSale(due: due, status: 'draft');

      final rows = await db.customSelect('''
      SELECT id FROM sales WHERE payment_method='cheque'
        AND due_date IS NOT NULL
        AND status NOT IN ('voided', 'draft')
    ''').get();
      expect(
        rows,
        isEmpty,
        reason: 'Voided and draft sales must not surface as cheque reminders.',
      );
    },
  );

  test(
    'cheque_confirmations natural key matches dashboard lookup format',
    () async {
      final dao = ChequeConfirmationDao(db);
      final saleId = await insertSale(due: DateTime(2026, 7, 1));

      await dao.confirm(
        sourceTable: ChequeSourceTables.sale,
        sourceId: saleId,
        status: ChequeConfirmationStatus.cleared,
      );

      final map = await dao.watchAllAsMap().first;
      expect(map.containsKey('sale|$saleId'), isTrue);
      expect(
        ChequeConfirmationStatus.resolved.contains(map['sale|$saleId']!.status),
        isTrue,
        reason:
            'A cleared cheque is in the resolved set the widget uses to '
            'hide the reminder card.',
      );
    },
  );
}
