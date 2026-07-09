// ════════════════════════════════════════════════════════════════════════════
// CommissionService — single source of truth for sales commission math.
// ════════════════════════════════════════════════════════════════════════════
//
// Extracted from `sale_repository_impl.dart` during Phase 6 of the
// scattered-calculation-logic migration (May 2026).
//
// CONTRACT
// --------
//  * `createForSale`        — record a commission row for a posted sale.
//    Supports both percentage commissions (computed on post-discount,
//    pre-tax net revenue — the SAP / Salesforce / QuickBooks convention)
//    and fixed-per-item commissions.
//  * `reverseForReturn`     — issue a NEGATIVE commission row proportional
//    to the share of the original sale being returned. Uses
//    `Money.allocate` (largest-remainder method) so the SUM of the
//    reversed pieces never deviates from the original commission amount
//    by even a single cent — even across multiple partial returns. This
//    is the IFRS-correct allocation rule and replaces the legacy
//    `~/` (integer floor) formula that could silently lose / fabricate
//    cents at the rounding boundary.
//  * `deleteForSale`        — purge all commission rows for a sale
//    (used by `voidSale` and `editPostedSale`).
//
// CALLERS
// -------
// Only the sales repository (`SaleRepositoryImpl`) should call this
// service. No DAO writes the `commissions` table outside of it.
// ════════════════════════════════════════════════════════════════════════════

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';

import '../../database/app_database.dart' as db;
import '../../database/daos/employee_dao.dart';
import '../../money/money.dart';

class CommissionService {
  final EmployeeDao _employeeDao;

  CommissionService(this._employeeDao);

  /// Create a commission record for the assigned salesperson on a sale.
  ///
  /// Supports two commission types (declared on the employee row):
  /// - **percentage**: amount = `(subtotal - discount) * rateBps / 10000`.
  ///   Computed on post-discount, pre-tax net revenue. This prevents
  ///   inflating commission via large discounts and avoids paying
  ///   commission on VAT that belongs to the tax authority.
  /// - **fixed**:  amount = `fixedCommissionCents * itemCount` (per item).
  ///
  /// Returns the inserted commission `id`, or `null` when no row was
  /// created (employee not found, rate ≤ 0, net revenue ≤ 0, etc.).
  Future<int?> createForSale({
    required int saleId,
    required int employeeId,
    required int subtotalCents,
    required int discountCents,
    required int itemCount,
    required int currencyId,
    required DateTime saleDate,
  }) async {
    final employee = await _employeeDao.getEmployee(employeeId);
    if (employee == null) return null;

    int commissionAmountCents;
    int rateBps;

    if (employee.commissionType == 'fixed') {
      final fixedCents = employee.fixedCommissionCents?.toBigInt().toInt() ?? 0;
      if (fixedCents <= 0) return null;
      commissionAmountCents = fixedCents * itemCount;
      rateBps = 0;
    } else {
      rateBps = employee.defaultCommissionRateBps;
      if (rateBps <= 0) return null;
      final netRevenueCents = subtotalCents - discountCents;
      if (netRevenueCents <= 0) return null;
      commissionAmountCents = (netRevenueCents * rateBps) ~/ 10000;
      if (commissionAmountCents <= 0) return null;
    }

    final period =
        '${saleDate.year}-${saleDate.month.toString().padLeft(2, '0')}';

    final companion = db.CommissionsCompanion(
      employeeId: Value(employeeId),
      saleId: Value(saleId),
      commissionRateBps: Value(rateBps.toDouble()),
      commissionAmountCents: Value(Decimal.fromInt(commissionAmountCents)),
      currencyId: Value(currencyId),
      period: Value(period),
      status: const Value('pending'),
      effectiveDate: Value(saleDate),
      createdAt: Value(DateTime.now()),
    );

    return _employeeDao.createCommission(companion);
  }

  /// Reverse (deduct) commission when a sale return is created.
  ///
  /// Inserts NEGATIVE commission rows proportional to the share of the
  /// original sale being returned. Rate-change safe — reversal is derived
  /// from the ORIGINAL commission amount, never the current employee
  /// settings (which may have been edited after the sale).
  ///
  /// Proration weights:
  /// - **Percentage commissions** — `returnSubtotal / saleSubtotal`.
  /// - **Fixed commissions** — `returnedItemCount / totalSaleItemCount`.
  ///
  /// Allocation uses `Money.allocate` (largest-remainder method). The two
  /// slots are `[deducted, retained]`; we take slot 0 as the reversal
  /// amount. This guarantees that across multiple partial returns the
  /// sum of all reversals can never exceed the original commission
  /// (sum-preservation invariant).
  Future<void> reverseForReturn({
    required int saleId,
    required int saleSubtotalCents,
    required int totalSaleItemCount,
    required int returnSubtotalCents,
    required int returnedItemCount,
    required int currencyId,
    required DateTime returnDate,
  }) async {
    if (saleSubtotalCents <= 0) return;

    final commissions = await _employeeDao.getCommissionsBySaleId(saleId);
    if (commissions.isEmpty) return;

    final period =
        '${returnDate.year}-${returnDate.month.toString().padLeft(2, '0')}';

    for (final c in commissions) {
      final originalAmount = c.commissionAmountCents.toBigInt().toInt();
      if (originalAmount <= 0) continue; // skip already-reversed entries

      final employee = await _employeeDao.getEmployee(c.employeeId);

      int deduction;
      if (employee != null && employee.commissionType == 'fixed') {
        if (totalSaleItemCount <= 0) continue;
        final capped = returnedItemCount > totalSaleItemCount
            ? totalSaleItemCount
            : returnedItemCount;
        if (capped <= 0) continue;
        deduction = _allocateFirst(
          originalAmount,
          capped,
          totalSaleItemCount - capped,
        );
      } else {
        if (returnSubtotalCents <= 0) continue;
        final capped = returnSubtotalCents > saleSubtotalCents
            ? saleSubtotalCents
            : returnSubtotalCents;
        if (capped <= 0) continue;
        deduction = _allocateFirst(
          originalAmount,
          capped,
          saleSubtotalCents - capped,
        );
      }

      if (deduction <= 0) continue;

      final companion = db.CommissionsCompanion(
        employeeId: Value(c.employeeId),
        saleId: Value(saleId),
        commissionRateBps: Value(c.commissionRateBps),
        commissionAmountCents: Value(Decimal.fromInt(-deduction)),
        currencyId: Value(currencyId),
        period: Value(period),
        status: const Value('pending'),
        effectiveDate: Value(returnDate),
        createdAt: Value(DateTime.now()),
      );

      await _employeeDao.createCommission(companion);
    }
  }

  /// Reverse (deduct) commission for an UNLINKED (adjustment) sale return.
  ///
  /// An adjustment return has no originating invoice, so — unlike
  /// [reverseForReturn] — there is no ORIGINAL commission row to prorate
  /// against. The deduction is therefore computed fresh with the SAME
  /// formula as [createForSale], using the employee's CURRENT commission
  /// settings:
  /// - **percentage**: `(returnSubtotal - returnDiscount) * rateBps / 10000`
  ///   (post-discount, pre-tax net — matches how earning is computed).
  /// - **fixed**: `fixedCommissionCents * itemCount` (per returned unit).
  ///
  /// The negative row is keyed by [adjustmentReturnId] (not `saleId`) so a
  /// void of the adjustment return can delete exactly this reversal via
  /// [deleteForAdjustmentReturn] — no recomputation, rate-change safe.
  ///
  /// No-op (nothing inserted) when the employee is missing, the rate/fixed
  /// amount is ≤ 0, or the computed deduction rounds to 0.
  Future<void> reverseForAdjustmentReturn({
    required int adjustmentReturnId,
    required int employeeId,
    required int returnSubtotalCents,
    required int returnDiscountCents,
    required int itemCount,
    required int currencyId,
    required DateTime returnDate,
  }) async {
    final employee = await _employeeDao.getEmployee(employeeId);
    if (employee == null) return;

    int deduction;
    int rateBps;
    if (employee.commissionType == 'fixed') {
      final fixedCents = employee.fixedCommissionCents?.toBigInt().toInt() ?? 0;
      if (fixedCents <= 0 || itemCount <= 0) return;
      deduction = fixedCents * itemCount;
      rateBps = 0;
    } else {
      rateBps = employee.defaultCommissionRateBps;
      if (rateBps <= 0) return;
      final netRevenueCents = returnSubtotalCents - returnDiscountCents;
      if (netRevenueCents <= 0) return;
      deduction = (netRevenueCents * rateBps) ~/ 10000;
    }

    if (deduction <= 0) return;

    final period =
        '${returnDate.year}-${returnDate.month.toString().padLeft(2, '0')}';

    final companion = db.CommissionsCompanion(
      employeeId: Value(employeeId),
      saleReturnAdjustmentId: Value(adjustmentReturnId),
      commissionRateBps: Value(rateBps.toDouble()),
      commissionAmountCents: Value(Decimal.fromInt(-deduction)),
      currencyId: Value(currencyId),
      period: Value(period),
      status: const Value('pending'),
      effectiveDate: Value(returnDate),
      createdAt: Value(DateTime.now()),
    );

    await _employeeDao.createCommission(companion);
  }

  /// Delete every commission row created for an adjustment sale return
  /// (used by `voidSaleAdjReturn`). Returns the number of rows removed.
  Future<int> deleteForAdjustmentReturn(int adjustmentReturnId) =>
      _employeeDao.deleteCommissionsByAdjustmentReturnId(adjustmentReturnId);

  /// Delete every commission row linked to a sale (used by `voidSale` /
  /// `editPostedSale`). Returns the number of rows removed.
  Future<int> deleteForSale(int saleId) =>
      _employeeDao.deleteCommissionsBySaleId(saleId);

  /// Largest-remainder split of [amount] across `[part, rest]`,
  /// returning slot 0. Pure helper used to guarantee that the sum of
  /// reversals can never exceed the original commission.
  static int _allocateFirst(int amount, int part, int rest) {
    final parts = Money.fromCents(amount).allocate([part, rest]);
    return parts[0].cents;
  }
}
