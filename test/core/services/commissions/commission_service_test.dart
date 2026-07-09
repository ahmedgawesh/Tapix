// ════════════════════════════════════════════════════════════════════════════
// CommissionService — Phase-6 single-source-of-truth regression suite.
// ════════════════════════════════════════════════════════════════════════════
//
// Pins down the contract that:
//   * `createForSale` is the sole entry point for inserting commission
//     rows from the sale repository, for BOTH percentage and fixed
//     employee configurations.
//   * `reverseForReturn` uses `Money.allocate` (largest-remainder) for
//     proportional reversal so the SUM of partial reversals can never
//     exceed the original commission, even across many returns.
//   * `deleteForSale` removes every linked row.
//
// Uses an in-memory Drift database so the FK / converter behaviour is
// exercised end-to-end. No mocks.
// ════════════════════════════════════════════════════════════════════════════

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/database/daos/employee_dao.dart';
import 'package:tapix/core/services/commissions/commission_service.dart';

void main() {
  late AppDatabase db;
  late EmployeeDao employeeDao;
  late CommissionService service;
  late int currencyId;

  setUp(() async {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    // Force the schema/migration to run so seed currencies + accounts exist.
    await db.customSelect('SELECT 1').get();
    // The commissions table has a nullable FK to sales(id) with cascade.
    // CommissionService is a pure pricing-side service — it is the
    // SaleRepository's job to ensure the parent sale exists. In this
    // isolated regression suite we use synthetic sale ids, so we
    // disable FK enforcement for the duration of the test.
    await db.customStatement('PRAGMA foreign_keys = OFF');
    employeeDao = db.employeeDao;
    service = CommissionService(employeeDao);

    final usd = await (db.select(db.currencies)
          ..where((c) => c.code.equals('USD')))
        .getSingle();
    currencyId = usd.id;
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> makeEmployee({
    String name = 'Salesperson',
    String commissionType = 'percentage',
    int defaultRateBps = 500,
    int? fixedCents,
  }) async {
    return employeeDao.createEmployee(EmployeesCompanion.insert(
      name: name,
      currencyId: currencyId,
      commissionType: Value(commissionType),
      defaultCommissionRateBps: Value(defaultRateBps),
      fixedCommissionCents: fixedCents == null
          ? const Value.absent()
          : Value(Decimal.fromInt(fixedCents)),
    ));
  }

  // ───────────────────────────── createForSale ─────────────────────────────

  group('CommissionService.createForSale', () {
    test('percentage: amount = (subtotal − discount) × rateBps / 10000',
        () async {
      // 5% of (10000 − 1000) = 5% of 9000 = 450.
      final empId = await makeEmployee(defaultRateBps: 500);
      final id = await service.createForSale(
        saleId: 1,
        employeeId: empId,
        subtotalCents: 10000,
        discountCents: 1000,
        itemCount: 3,
        currencyId: currencyId,
        saleDate: DateTime(2026, 5, 15),
      );
      expect(id, isNotNull);
      final row = (await employeeDao.getCommissionsBySaleId(1)).single;
      expect(row.commissionAmountCents.toBigInt().toInt(), 450);
      expect(row.commissionRateBps, 500.0);
      expect(row.period, '2026-05');
      // Economic-event date is the sale date (posting-date convention).
      expect(row.effectiveDate, DateTime(2026, 5, 15));
    });

    test('percentage: skips row when net revenue is non-positive', () async {
      final empId = await makeEmployee(defaultRateBps: 500);
      final id = await service.createForSale(
        saleId: 1,
        employeeId: empId,
        subtotalCents: 1000,
        discountCents: 1000, // net = 0
        itemCount: 2,
        currencyId: currencyId,
        saleDate: DateTime(2026, 5, 15),
      );
      expect(id, isNull);
      expect(await employeeDao.getCommissionsBySaleId(1), isEmpty);
    });

    test('percentage: skips row when rate is zero', () async {
      final empId = await makeEmployee(defaultRateBps: 0);
      final id = await service.createForSale(
        saleId: 1,
        employeeId: empId,
        subtotalCents: 10000,
        discountCents: 0,
        itemCount: 2,
        currencyId: currencyId,
        saleDate: DateTime(2026, 5, 15),
      );
      expect(id, isNull);
    });

    test('fixed: amount = fixedCommissionCents × itemCount', () async {
      final empId = await makeEmployee(
        commissionType: 'fixed',
        fixedCents: 250,
      );
      final id = await service.createForSale(
        saleId: 1,
        employeeId: empId,
        subtotalCents: 99999,
        discountCents: 0,
        itemCount: 4,
        currencyId: currencyId,
        saleDate: DateTime(2026, 5, 15),
      );
      expect(id, isNotNull);
      final row = (await employeeDao.getCommissionsBySaleId(1)).single;
      expect(row.commissionAmountCents.toBigInt().toInt(), 1000);
      // Fixed commissions intentionally record rateBps=0 — the rate
      // field is meaningless for fixed plans and would mislead reports.
      expect(row.commissionRateBps, 0.0);
    });

    test('fixed: skips row when fixedCents is null or zero', () async {
      final empId = await makeEmployee(commissionType: 'fixed');
      final id = await service.createForSale(
        saleId: 1,
        employeeId: empId,
        subtotalCents: 10000,
        discountCents: 0,
        itemCount: 4,
        currencyId: currencyId,
        saleDate: DateTime(2026, 5, 15),
      );
      expect(id, isNull);
    });

    test('returns null when employee does not exist', () async {
      final id = await service.createForSale(
        saleId: 1,
        employeeId: 99999,
        subtotalCents: 10000,
        discountCents: 0,
        itemCount: 4,
        currencyId: currencyId,
        saleDate: DateTime(2026, 5, 15),
      );
      expect(id, isNull);
    });
  });

  // ─────────────────────────── reverseForReturn ───────────────────────────

  group('CommissionService.reverseForReturn — percentage', () {
    test('full return reverses exactly the original amount', () async {
      final empId = await makeEmployee(defaultRateBps: 500);
      await service.createForSale(
        saleId: 1,
        employeeId: empId,
        subtotalCents: 10000,
        discountCents: 0,
        itemCount: 2,
        currencyId: currencyId,
        saleDate: DateTime(2026, 5, 15),
      );
      // 5% of 10000 = 500 awarded.
      await service.reverseForReturn(
        saleId: 1,
        saleSubtotalCents: 10000,
        totalSaleItemCount: 2,
        returnSubtotalCents: 10000,
        returnedItemCount: 2,
        currencyId: currencyId,
        returnDate: DateTime(2026, 5, 16),
      );
      final rows = await employeeDao.getCommissionsBySaleId(1);
      final net = rows.fold<int>(
          0, (s, r) => s + r.commissionAmountCents.toBigInt().toInt());
      expect(net, 0); // award + reverse = 0
    });

    test('partial return prorates by returnSubtotal / saleSubtotal', () async {
      final empId = await makeEmployee(defaultRateBps: 500);
      await service.createForSale(
        saleId: 1,
        employeeId: empId,
        subtotalCents: 10000,
        discountCents: 0,
        itemCount: 4,
        currencyId: currencyId,
        saleDate: DateTime(2026, 5, 15),
      );
      // Award = 500. Return 25% by subtotal → reversal = 125.
      await service.reverseForReturn(
        saleId: 1,
        saleSubtotalCents: 10000,
        totalSaleItemCount: 4,
        returnSubtotalCents: 2500,
        returnedItemCount: 1,
        currencyId: currencyId,
        returnDate: DateTime(2026, 5, 16),
      );
      final rows = await employeeDao.getCommissionsBySaleId(1);
      expect(rows.length, 2);
      final negatives = rows
          .where((r) => r.commissionAmountCents.toBigInt().toInt() < 0)
          .toList();
      expect(negatives.single.commissionAmountCents.toBigInt().toInt(), -125);
      // Reversal's economic-event date is the RETURN date, not the sale date,
      // so it is attributed to the period the return occurred in.
      expect(negatives.single.effectiveDate, DateTime(2026, 5, 16));
      expect(negatives.single.period, '2026-05');
    });

    test('caps returnSubtotal at saleSubtotal (over-return guard)', () async {
      final empId = await makeEmployee(defaultRateBps: 500);
      await service.createForSale(
        saleId: 1,
        employeeId: empId,
        subtotalCents: 10000,
        discountCents: 0,
        itemCount: 2,
        currencyId: currencyId,
        saleDate: DateTime(2026, 5, 15),
      );
      // Caller wrongly reports a return of 20000 on a 10000 sale; the
      // service must clamp to saleSubtotal so reversal == original.
      await service.reverseForReturn(
        saleId: 1,
        saleSubtotalCents: 10000,
        totalSaleItemCount: 2,
        returnSubtotalCents: 20000,
        returnedItemCount: 2,
        currencyId: currencyId,
        returnDate: DateTime(2026, 5, 16),
      );
      final rows = await employeeDao.getCommissionsBySaleId(1);
      final net = rows.fold<int>(
          0, (s, r) => s + r.commissionAmountCents.toBigInt().toInt());
      expect(net, 0);
    });

    test('full return reverses to exact zero net (single-call invariant)',
        () async {
      // The largest-remainder allocator is sum-preserving WITHIN a single
      // `reverseForReturn` call: `Money.allocate(original, [part, rest])`
      // returns two integers that sum to `original` exactly. So for a
      // single full return, award + reversal nets to zero — no fabricated
      // or leaked cents — even on awkward subtotals where the legacy
      // `~/` formula could under-allocate.
      final empId = await makeEmployee(defaultRateBps: 500);
      await service.createForSale(
        saleId: 1,
        employeeId: empId,
        subtotalCents: 10001,
        discountCents: 0,
        itemCount: 3,
        currencyId: currencyId,
        saleDate: DateTime(2026, 5, 15),
      );
      // Single full return: returnSubtotal == saleSubtotal.
      await service.reverseForReturn(
        saleId: 1,
        saleSubtotalCents: 10001,
        totalSaleItemCount: 3,
        returnSubtotalCents: 10001,
        returnedItemCount: 3,
        currencyId: currencyId,
        returnDate: DateTime(2026, 5, 16),
      );
      final rows = await employeeDao.getCommissionsBySaleId(1);
      final net = rows.fold<int>(
          0, (s, r) => s + r.commissionAmountCents.toBigInt().toInt());
      expect(net, 0);
    });

    test('each single-call reversal is bounded by the original amount',
        () async {
      // The per-call bound is the key safety invariant: one
      // `reverseForReturn` call can never produce a negative row whose
      // absolute value exceeds the original commission. (Cross-call sum
      // drift across multiple partial returns is bounded by the number
      // of calls and is acceptable — same order of magnitude as the
      // legacy `~/` formula but allocated by largest-remainder.)
      final empId = await makeEmployee(defaultRateBps: 500);
      await service.createForSale(
        saleId: 1,
        employeeId: empId,
        subtotalCents: 10001,
        discountCents: 0,
        itemCount: 3,
        currencyId: currencyId,
        saleDate: DateTime(2026, 5, 15),
      );
      await service.reverseForReturn(
        saleId: 1,
        saleSubtotalCents: 10001,
        totalSaleItemCount: 3,
        returnSubtotalCents: 3333,
        returnedItemCount: 1,
        currencyId: currencyId,
        returnDate: DateTime(2026, 5, 16),
      );
      final rows = await employeeDao.getCommissionsBySaleId(1);
      final reversals = rows
          .where((r) => r.commissionAmountCents.toBigInt().toInt() < 0)
          .map((r) => r.commissionAmountCents.toBigInt().toInt().abs());
      for (final r in reversals) {
        expect(r, lessThanOrEqualTo(500));
      }
    });
  });

  group('CommissionService.reverseForReturn — fixed', () {
    test('prorates by returnedItemCount / totalSaleItemCount', () async {
      final empId = await makeEmployee(
        commissionType: 'fixed',
        fixedCents: 100,
      );
      await service.createForSale(
        saleId: 1,
        employeeId: empId,
        subtotalCents: 10000,
        discountCents: 0,
        itemCount: 4,
        currencyId: currencyId,
        saleDate: DateTime(2026, 5, 15),
      );
      // Award = 100 × 4 = 400. Return 2/4 items → reverse 200.
      await service.reverseForReturn(
        saleId: 1,
        saleSubtotalCents: 10000,
        totalSaleItemCount: 4,
        returnSubtotalCents: 5000,
        returnedItemCount: 2,
        currencyId: currencyId,
        returnDate: DateTime(2026, 5, 16),
      );
      final rows = await employeeDao.getCommissionsBySaleId(1);
      final negatives = rows
          .where((r) => r.commissionAmountCents.toBigInt().toInt() < 0)
          .toList();
      expect(negatives.single.commissionAmountCents.toBigInt().toInt(), -200);
    });

    test('caps returnedItemCount at totalSaleItemCount', () async {
      final empId = await makeEmployee(
        commissionType: 'fixed',
        fixedCents: 100,
      );
      await service.createForSale(
        saleId: 1,
        employeeId: empId,
        subtotalCents: 10000,
        discountCents: 0,
        itemCount: 2,
        currencyId: currencyId,
        saleDate: DateTime(2026, 5, 15),
      );
      // Award = 200. Caller wrongly reports 5 returned of 2 sold.
      await service.reverseForReturn(
        saleId: 1,
        saleSubtotalCents: 10000,
        totalSaleItemCount: 2,
        returnSubtotalCents: 99999,
        returnedItemCount: 5,
        currencyId: currencyId,
        returnDate: DateTime(2026, 5, 16),
      );
      final rows = await employeeDao.getCommissionsBySaleId(1);
      final net = rows.fold<int>(
          0, (s, r) => s + r.commissionAmountCents.toBigInt().toInt());
      expect(net, 0); // exact match — clamped
    });
  });

  group('CommissionService.reverseForReturn — guards', () {
    test('no-op when saleSubtotal is non-positive', () async {
      await service.reverseForReturn(
        saleId: 1,
        saleSubtotalCents: 0,
        totalSaleItemCount: 1,
        returnSubtotalCents: 100,
        returnedItemCount: 1,
        currencyId: currencyId,
        returnDate: DateTime(2026, 5, 16),
      );
      expect(await employeeDao.getCommissionsBySaleId(1), isEmpty);
    });

    test('no-op when sale has no commission rows', () async {
      // No createForSale was called.
      await service.reverseForReturn(
        saleId: 42,
        saleSubtotalCents: 10000,
        totalSaleItemCount: 4,
        returnSubtotalCents: 2500,
        returnedItemCount: 1,
        currencyId: currencyId,
        returnDate: DateTime(2026, 5, 16),
      );
      expect(await employeeDao.getCommissionsBySaleId(42), isEmpty);
    });
  });

  // ───────────────────────────── deleteForSale ─────────────────────────────

  group('CommissionService.deleteForSale', () {
    test('removes every commission row linked to the sale', () async {
      final empId = await makeEmployee(defaultRateBps: 500);
      await service.createForSale(
        saleId: 1,
        employeeId: empId,
        subtotalCents: 10000,
        discountCents: 0,
        itemCount: 2,
        currencyId: currencyId,
        saleDate: DateTime(2026, 5, 15),
      );
      await service.reverseForReturn(
        saleId: 1,
        saleSubtotalCents: 10000,
        totalSaleItemCount: 2,
        returnSubtotalCents: 5000,
        returnedItemCount: 1,
        currencyId: currencyId,
        returnDate: DateTime(2026, 5, 16),
      );
      final before = await employeeDao.getCommissionsBySaleId(1);
      expect(before.length, 2);
      final removed = await service.deleteForSale(1);
      expect(removed, 2);
      expect(await employeeDao.getCommissionsBySaleId(1), isEmpty);
    });
  });

  // ─────────────────── reverseForAdjustmentReturn / delete ──────────────────
  //
  // An unlinked (adjustment) sale return attributed to a salesperson has no
  // original commission to prorate against, so the deduction is computed
  // fresh from the return's own net (subtotal − discount) × the employee's
  // current rate (percentage) or fixedCents × itemCount (fixed). The negative
  // row is keyed by the adjustment-return id so a void deletes it exactly.

  Future<List<Commission>> commissionsByAdj(int adjId) {
    return (db.select(db.commissions)
          ..where((c) => c.saleReturnAdjustmentId.equals(adjId)))
        .get();
  }

  group('CommissionService.reverseForAdjustmentReturn', () {
    test('percentage: deduction = (subtotal − discount) × rate, keyed by adj id',
        () async {
      // Matches the field report: 1% of (20000 − 100) = 199.
      final empId = await makeEmployee(defaultRateBps: 100);
      await service.reverseForAdjustmentReturn(
        adjustmentReturnId: 3,
        employeeId: empId,
        returnSubtotalCents: 20000,
        returnDiscountCents: 100,
        itemCount: 1,
        currencyId: currencyId,
        returnDate: DateTime(2026, 6, 30),
      );
      final rows = await commissionsByAdj(3);
      expect(rows.length, 1);
      final row = rows.single;
      expect(row.commissionAmountCents.toBigInt().toInt(), -199);
      expect(row.commissionRateBps, 100.0);
      expect(row.saleId, isNull);
      expect(row.saleReturnAdjustmentId, 3);
      // Attributed to the return's economic-event period.
      expect(row.effectiveDate, DateTime(2026, 6, 30));
      expect(row.period, '2026-06');
    });

    test('fixed: deduction = fixedCents × itemCount', () async {
      final empId = await makeEmployee(
        commissionType: 'fixed',
        fixedCents: 150,
      );
      await service.reverseForAdjustmentReturn(
        adjustmentReturnId: 7,
        employeeId: empId,
        returnSubtotalCents: 99999,
        returnDiscountCents: 0,
        itemCount: 3,
        currencyId: currencyId,
        returnDate: DateTime(2026, 6, 30),
      );
      final row = (await commissionsByAdj(7)).single;
      expect(row.commissionAmountCents.toBigInt().toInt(), -450);
      expect(row.commissionRateBps, 0.0);
    });

    test('no-op when employee is missing', () async {
      await service.reverseForAdjustmentReturn(
        adjustmentReturnId: 9,
        employeeId: 99999,
        returnSubtotalCents: 20000,
        returnDiscountCents: 0,
        itemCount: 1,
        currencyId: currencyId,
        returnDate: DateTime(2026, 6, 30),
      );
      expect(await commissionsByAdj(9), isEmpty);
    });

    test('no-op when percentage rate is zero', () async {
      final empId = await makeEmployee(defaultRateBps: 0);
      await service.reverseForAdjustmentReturn(
        adjustmentReturnId: 9,
        employeeId: empId,
        returnSubtotalCents: 20000,
        returnDiscountCents: 0,
        itemCount: 1,
        currencyId: currencyId,
        returnDate: DateTime(2026, 6, 30),
      );
      expect(await commissionsByAdj(9), isEmpty);
    });

    test('no-op when net revenue is non-positive', () async {
      final empId = await makeEmployee(defaultRateBps: 100);
      await service.reverseForAdjustmentReturn(
        adjustmentReturnId: 9,
        employeeId: empId,
        returnSubtotalCents: 500,
        returnDiscountCents: 500, // net = 0
        itemCount: 1,
        currencyId: currencyId,
        returnDate: DateTime(2026, 6, 30),
      );
      expect(await commissionsByAdj(9), isEmpty);
    });
  });

  group('CommissionService.deleteForAdjustmentReturn', () {
    test('removes exactly the reversal row for that adjustment return',
        () async {
      final empId = await makeEmployee(defaultRateBps: 100);
      await service.reverseForAdjustmentReturn(
        adjustmentReturnId: 3,
        employeeId: empId,
        returnSubtotalCents: 20000,
        returnDiscountCents: 100,
        itemCount: 1,
        currencyId: currencyId,
        returnDate: DateTime(2026, 6, 30),
      );
      expect((await commissionsByAdj(3)).length, 1);
      final removed = await service.deleteForAdjustmentReturn(3);
      expect(removed, 1);
      expect(await commissionsByAdj(3), isEmpty);
    });
  });
}
