// ════════════════════════════════════════════════════════════════════════════
// EmployeeDao.getEmployeeSalesStats — single-source-of-truth regression suite.
// ════════════════════════════════════════════════════════════════════════════
//
// Why this exists
// ---------------
// The salesperson summary on the employee detail screen (and the target
// bonus calculation in `EmployeeDetailBloc._onSettleAccount`) both consume
// `EmployeeDao.getEmployeeSalesStats`. After the dual-return refactor and
// the per-item salesperson mode rollout, that one query had to fan-out
// across FIVE contribution sources or the screen would silently show
// `Sales Count = 0` / `Sales Total = $0.00` even when commissions were
// being correctly accrued (because commission attribution and stats
// attribution lived in two places).
//
// This file pins the contract by exercising every one of those paths in
// an in-memory Drift database, plus the negative cases (voided rows,
// out-of-range dates, cross-employee non-leakage).
//
// Bug repro
// ---------
// A salesperson assigned per-item on 6 line items (header
// `sales.employee_id IS NULL`) had `$6.83` commission posted but their
// detail screen showed `Sales Count 0`, `Sales Total $0.00`,
// `Returns Count 0`, `Returns Total $0.00`. The query was only matching
// the header path. This suite locks the union-fan-out fix in place.
// ════════════════════════════════════════════════════════════════════════════

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/database/app_database.dart';

void main() {
  late AppDatabase db;
  late int currencyId;
  late int customerId;
  late int productId;
  late int variantId;
  late int empAId; // the employee we measure
  late int empBId; // a different employee, used for non-leak tests

  // Stats are queried over May 2026. Use mid-month for in-range and
  // a different month for out-of-range checks.
  final periodStart = DateTime(2026, 5, 1);
  final periodEnd = DateTime(2026, 5, 31, 23, 59, 59);
  final inRange = DateTime(2026, 5, 15, 10);
  final outOfRange = DateTime(2026, 4, 15, 10);

  setUp(() async {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    // Force migration to run so seed rows exist.
    await db.customSelect('SELECT 1').get();
    // Disable FK enforcement: these stats tests insert synthetic sales /
    // returns directly; we are not exercising the full posting pipeline.
    await db.customStatement('PRAGMA foreign_keys = OFF');

    currencyId = (await db.select(db.currencies).get()).first.id;

    customerId = await db.into(db.customers).insert(
          CustomersCompanion.insert(name: 'Acme Co', currencyId: currencyId),
        );

    productId = await db.into(db.products).insert(
          ProductsCompanion.insert(
            name: 'Widget',
            costCents: Decimal.fromInt(500),
            priceCents: Decimal.fromInt(1000),
            currencyId: Value(currencyId),
          ),
        );
    variantId = await db.into(db.productVariants).insert(
          ProductVariantsCompanion.insert(
            productId: productId,
            costCents: Decimal.fromInt(500),
            priceCents: Decimal.fromInt(1000),
          ),
        );

    empAId = await db.into(db.employees).insert(
          EmployeesCompanion.insert(name: 'bero', currencyId: currencyId),
        );
    empBId = await db.into(db.employees).insert(
          EmployeesCompanion.insert(name: 'other', currencyId: currencyId),
        );
  });

  tearDown(() async => db.close());

  // ─── helpers ──────────────────────────────────────────────────────────

  /// Insert one sale with N items. Each item can have its own employee.
  /// If [headerEmployeeId] is non-null the sale uses per-invoice mode and
  /// per-item employee assignment is ignored by the commission/stats path
  /// (matches the production attribution rule).
  Future<int> insertSale({
    required String invoice,
    required DateTime date,
    int? headerEmployeeId,
    required List<({int? itemEmployeeId, int totalCents})> items,
    String status = 'completed',
  }) async {
    final totalCents =
        items.fold<int>(0, (sum, i) => sum + i.totalCents);
    final saleId = await db.into(db.sales).insert(
          SalesCompanion.insert(
            invoiceNumber: invoice,
            customerId: Value(customerId),
            employeeId: Value(headerEmployeeId),
            currencyId: currencyId,
            subtotalCents: Decimal.fromInt(totalCents),
            taxCents: Decimal.zero,
            totalCents: Decimal.fromInt(totalCents),
            paymentMethod: 'cash',
            saleDate: Value(date),
            status: Value(status),
          ),
        );
    for (final item in items) {
      await db.into(db.saleItems).insert(
            SaleItemsCompanion.insert(
              saleId: saleId,
              productId: productId,
              variantId: Value(variantId),
              employeeId: Value(item.itemEmployeeId),
              quantity: 1,
              unitPriceCents: Decimal.fromInt(item.totalCents),
              subtotalCents: Decimal.fromInt(item.totalCents),
              totalCents: Decimal.fromInt(item.totalCents),
            ),
          );
    }
    return saleId;
  }

  /// Insert a linked sale return referencing an existing sale's items.
  /// One return row, one line per supplied sale_item_id + refund cents.
  Future<int> insertLinkedReturn({
    required String returnNumber,
    required int saleId,
    required DateTime date,
    required List<({int saleItemId, int refundCents})> lines,
    String status = 'posted',
  }) async {
    final total = lines.fold<int>(0, (s, l) => s + l.refundCents);
    final returnId = await db.into(db.saleReturns).insert(
          SaleReturnsCompanion.insert(
            returnNumber: returnNumber,
            saleId: saleId,
            subtotalCents: Value(Decimal.fromInt(total)),
            totalCents: Decimal.fromInt(total),
            currencyId: currencyId,
            status: Value(status),
            returnDate: Value(date),
            refundMethod: const Value('cash'),
          ),
        );
    for (final line in lines) {
      await db.into(db.saleReturnItems).insert(
            SaleReturnItemsCompanion.insert(
              returnId: returnId,
              saleItemId: line.saleItemId,
              quantity: 1,
              subtotalCents: Value(Decimal.fromInt(line.refundCents)),
              refundCents: Decimal.fromInt(line.refundCents),
            ),
          );
    }
    return returnId;
  }

  /// Insert an unlinked (adjustment) sale return for the given employee.
  Future<int> insertAdjReturn({
    required String returnNumber,
    required int? employeeId,
    required DateTime date,
    required int totalCents,
    String status = 'posted',
  }) async {
    final returnId = await db.into(db.saleReturnAdjustments).insert(
          SaleReturnAdjustmentsCompanion.insert(
            returnNumber: returnNumber,
            customerId: Value(customerId),
            employeeId: Value(employeeId),
            currencyId: currencyId,
            totalCents: Decimal.fromInt(totalCents),
            subtotalCents: Value(Decimal.fromInt(totalCents)),
            refundMethod: const Value('cash'),
            status: Value(status),
            returnDate: Value(date),
          ),
        );
    await db.into(db.saleReturnAdjustmentItems).insert(
          SaleReturnAdjustmentItemsCompanion.insert(
            returnId: returnId,
            productId: productId,
            variantId: Value(variantId),
            quantity: 1,
            unitPriceCents: Decimal.fromInt(totalCents),
            totalCents: Decimal.fromInt(totalCents),
          ),
        );
    return returnId;
  }

  // ─── sales attribution ────────────────────────────────────────────────

  group('sales attribution', () {
    test('per-invoice mode: full sale total is credited to header employee',
        () async {
      await insertSale(
        invoice: 'INV-1',
        date: inRange,
        headerEmployeeId: empAId,
        items: [
          (itemEmployeeId: null, totalCents: 1500),
          (itemEmployeeId: null, totalCents: 2500),
        ],
      );
      final stats = await db.employeeDao
          .getEmployeeSalesStats(empAId, periodStart, periodEnd);
      expect(stats['salesCount'], 1);
      expect(stats['salesTotalCents'], 4000);
      expect(stats['returnsCount'], 0);
      expect(stats['returnsTotalCents'], 0);
    });

    test(
        'per-item mode: header NULL + per-item employees → sum only this '
        "employee's line items (the screenshot bug)", () async {
      await insertSale(
        invoice: 'INV-2',
        date: inRange,
        headerEmployeeId: null, // per-item mode
        items: [
          (itemEmployeeId: empAId, totalCents: 1000),
          (itemEmployeeId: empAId, totalCents: 2000),
          (itemEmployeeId: empBId, totalCents: 999), // not ours
        ],
      );
      final statsA = await db.employeeDao
          .getEmployeeSalesStats(empAId, periodStart, periodEnd);
      expect(statsA['salesCount'], 1);
      expect(statsA['salesTotalCents'], 3000);

      final statsB = await db.employeeDao
          .getEmployeeSalesStats(empBId, periodStart, periodEnd);
      expect(statsB['salesCount'], 1);
      expect(statsB['salesTotalCents'], 999);
    });

    test(
        'per-item mode without a single matching item returns zero — no '
        'cross-employee leak', () async {
      await insertSale(
        invoice: 'INV-3',
        date: inRange,
        headerEmployeeId: null,
        items: [
          (itemEmployeeId: empBId, totalCents: 5000),
        ],
      );
      final stats = await db.employeeDao
          .getEmployeeSalesStats(empAId, periodStart, periodEnd);
      expect(stats['salesCount'], 0);
      expect(stats['salesTotalCents'], 0);
    });

    test(
        'per-invoice mode never double-counts when items also carry an '
        'employee_id (defence-in-depth)', () async {
      // Production code branches IF/ELSE on `sales.employee_id`, so items
      // assigned in addition to a header must NOT cause double-credit.
      await insertSale(
        invoice: 'INV-4',
        date: inRange,
        headerEmployeeId: empAId,
        items: [
          (itemEmployeeId: empAId, totalCents: 1000), // would inflate
          (itemEmployeeId: empAId, totalCents: 2000),
        ],
      );
      final stats = await db.employeeDao
          .getEmployeeSalesStats(empAId, periodStart, periodEnd);
      expect(stats['salesCount'], 1);
      expect(stats['salesTotalCents'], 3000); // header total, not 6000
    });

    test('voided sale is excluded across both attribution modes', () async {
      await insertSale(
        invoice: 'INV-V-INV',
        date: inRange,
        headerEmployeeId: empAId,
        items: [(itemEmployeeId: null, totalCents: 1000)],
        status: 'voided',
      );
      await insertSale(
        invoice: 'INV-V-ITEM',
        date: inRange,
        headerEmployeeId: null,
        items: [(itemEmployeeId: empAId, totalCents: 2000)],
        status: 'voided',
      );
      final stats = await db.employeeDao
          .getEmployeeSalesStats(empAId, periodStart, periodEnd);
      expect(stats['salesCount'], 0);
      expect(stats['salesTotalCents'], 0);
    });

    test('sales outside the period are excluded', () async {
      await insertSale(
        invoice: 'INV-PAST',
        date: outOfRange,
        headerEmployeeId: empAId,
        items: [(itemEmployeeId: null, totalCents: 9999)],
      );
      await insertSale(
        invoice: 'INV-PAST-ITEM',
        date: outOfRange,
        headerEmployeeId: null,
        items: [(itemEmployeeId: empAId, totalCents: 9999)],
      );
      final stats = await db.employeeDao
          .getEmployeeSalesStats(empAId, periodStart, periodEnd);
      expect(stats['salesCount'], 0);
      expect(stats['salesTotalCents'], 0);
    });
  });

  // ─── returns attribution ──────────────────────────────────────────────

  group('returns attribution', () {
    test('linked return on per-invoice mode sale → full return total',
        () async {
      final saleId = await insertSale(
        invoice: 'INV-L1',
        date: inRange,
        headerEmployeeId: empAId,
        items: [(itemEmployeeId: null, totalCents: 5000)],
      );
      final saleItem = await (db.select(db.saleItems)
            ..where((i) => i.saleId.equals(saleId)))
          .getSingle();
      await insertLinkedReturn(
        returnNumber: 'SR-L1',
        saleId: saleId,
        date: inRange,
        lines: [(saleItemId: saleItem.id, refundCents: 1500)],
      );
      final stats = await db.employeeDao
          .getEmployeeSalesStats(empAId, periodStart, periodEnd);
      expect(stats['returnsCount'], 1);
      // Per-invoice-mode rule: whole sr.total_cents is the employee's slice.
      expect(stats['returnsTotalCents'], 1500);
    });

    test(
        "linked return on per-item mode sale → only this employee's return "
        'lines are summed', () async {
      final saleId = await insertSale(
        invoice: 'INV-L2',
        date: inRange,
        headerEmployeeId: null,
        items: [
          (itemEmployeeId: empAId, totalCents: 3000),
          (itemEmployeeId: empBId, totalCents: 2000),
        ],
      );
      final items = await (db.select(db.saleItems)
            ..where((i) => i.saleId.equals(saleId)))
          .get();
      final aItem = items.firstWhere((i) => i.employeeId == empAId);
      final bItem = items.firstWhere((i) => i.employeeId == empBId);

      // Both items are returned. Empire's share is just A's refund line.
      await insertLinkedReturn(
        returnNumber: 'SR-L2',
        saleId: saleId,
        date: inRange,
        lines: [
          (saleItemId: aItem.id, refundCents: 3000),
          (saleItemId: bItem.id, refundCents: 2000),
        ],
      );

      final statsA = await db.employeeDao
          .getEmployeeSalesStats(empAId, periodStart, periodEnd);
      expect(statsA['returnsCount'], 1);
      expect(statsA['returnsTotalCents'], 3000); // only A's line

      final statsB = await db.employeeDao
          .getEmployeeSalesStats(empBId, periodStart, periodEnd);
      expect(statsB['returnsCount'], 1);
      expect(statsB['returnsTotalCents'], 2000); // only B's line
    });

    test('adjustment (unlinked) return on header employee_id → full total',
        () async {
      await insertAdjReturn(
        returnNumber: 'SAR-1',
        employeeId: empAId,
        date: inRange,
        totalCents: 4200,
      );
      final stats = await db.employeeDao
          .getEmployeeSalesStats(empAId, periodStart, periodEnd);
      expect(stats['returnsCount'], 1);
      expect(stats['returnsTotalCents'], 4200);
    });

    test('voided returns are excluded across all three paths', () async {
      // A) linked, per-invoice
      final saleA = await insertSale(
        invoice: 'INV-V-RA',
        date: inRange,
        headerEmployeeId: empAId,
        items: [(itemEmployeeId: null, totalCents: 1000)],
      );
      final aItem = await (db.select(db.saleItems)
            ..where((i) => i.saleId.equals(saleA)))
          .getSingle();
      await insertLinkedReturn(
        returnNumber: 'SR-V-A',
        saleId: saleA,
        date: inRange,
        lines: [(saleItemId: aItem.id, refundCents: 1000)],
        status: 'voided',
      );

      // B) linked, per-item
      final saleB = await insertSale(
        invoice: 'INV-V-RB',
        date: inRange,
        headerEmployeeId: null,
        items: [(itemEmployeeId: empAId, totalCents: 2000)],
      );
      final bItem = await (db.select(db.saleItems)
            ..where((i) => i.saleId.equals(saleB)))
          .getSingle();
      await insertLinkedReturn(
        returnNumber: 'SR-V-B',
        saleId: saleB,
        date: inRange,
        lines: [(saleItemId: bItem.id, refundCents: 2000)],
        status: 'voided',
      );

      // C) adjustment
      await insertAdjReturn(
        returnNumber: 'SAR-V',
        employeeId: empAId,
        date: inRange,
        totalCents: 3000,
        status: 'voided',
      );

      final stats = await db.employeeDao
          .getEmployeeSalesStats(empAId, periodStart, periodEnd);
      // The two underlying sales themselves still count (status=completed).
      expect(stats['salesCount'], 2);
      expect(stats['salesTotalCents'], 3000);
      // But every return is voided.
      expect(stats['returnsCount'], 0);
      expect(stats['returnsTotalCents'], 0);
    });

    test('returns outside the period are excluded', () async {
      await insertAdjReturn(
        returnNumber: 'SAR-PAST',
        employeeId: empAId,
        date: outOfRange,
        totalCents: 9999,
      );
      final stats = await db.employeeDao
          .getEmployeeSalesStats(empAId, periodStart, periodEnd);
      expect(stats['returnsCount'], 0);
      expect(stats['returnsTotalCents'], 0);
    });
  });

  // ─── end-to-end mixed scenario ────────────────────────────────────────

  group('end-to-end mixed scenario', () {
    test(
        '5 contribution paths sum correctly in one query — reproduction of '
        'the field bug and its fix', () async {
      // 1. Per-invoice mode sale credited to empA: 5000
      await insertSale(
        invoice: 'MIX-1',
        date: inRange,
        headerEmployeeId: empAId,
        items: [(itemEmployeeId: null, totalCents: 5000)],
      );

      // 2. Per-item mode sale: empA gets 2 items totalling 3000; empB gets 1
      final perItemSaleId = await insertSale(
        invoice: 'MIX-2',
        date: inRange,
        headerEmployeeId: null,
        items: [
          (itemEmployeeId: empAId, totalCents: 1000),
          (itemEmployeeId: empAId, totalCents: 2000),
          (itemEmployeeId: empBId, totalCents: 1500),
        ],
      );

      // 3. Linked return on the per-invoice sale: empA loses 1000
      final invoiceSale = await (db.select(db.sales)
            ..where((s) => s.invoiceNumber.equals('MIX-1')))
          .getSingle();
      final invoiceSaleItem = await (db.select(db.saleItems)
            ..where((i) => i.saleId.equals(invoiceSale.id)))
          .getSingle();
      await insertLinkedReturn(
        returnNumber: 'SR-MIX-A',
        saleId: invoiceSale.id,
        date: inRange,
        lines: [(saleItemId: invoiceSaleItem.id, refundCents: 1000)],
      );

      // 4. Linked return on the per-item sale: empA loses one item (1000)
      final perItemItems = await (db.select(db.saleItems)
            ..where((i) => i.saleId.equals(perItemSaleId)))
          .get();
      final aItemToReturn =
          perItemItems.firstWhere((i) => i.employeeId == empAId);
      await insertLinkedReturn(
        returnNumber: 'SR-MIX-B',
        saleId: perItemSaleId,
        date: inRange,
        lines: [(saleItemId: aItemToReturn.id, refundCents: 1000)],
      );

      // 5. Adjustment return on empA: 500
      await insertAdjReturn(
        returnNumber: 'SAR-MIX',
        employeeId: empAId,
        date: inRange,
        totalCents: 500,
      );

      final stats = await db.employeeDao
          .getEmployeeSalesStats(empAId, periodStart, periodEnd);

      // Sales: 1 per-invoice + 1 per-item, totals 5000 + 3000.
      expect(stats['salesCount'], 2);
      expect(stats['salesTotalCents'], 8000);

      // Returns: linked-per-invoice + linked-per-item + adjustment.
      expect(stats['returnsCount'], 3);
      expect(stats['returnsTotalCents'], 2500); // 1000 + 1000 + 500
    });
  });
}
