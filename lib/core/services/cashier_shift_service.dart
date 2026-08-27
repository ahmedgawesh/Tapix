import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';

import '../database/app_database.dart';

class CashierShiftView {
  final CashierShift shift;
  final String cashierName;
  final String currencyCode;
  final String currencySymbol;

  const CashierShiftView({
    required this.shift,
    required this.cashierName,
    required this.currencyCode,
    required this.currencySymbol,
  });
}

class ShiftPaymentBreakdown {
  final String method;
  final int receivedCents;
  final int refundedCents;

  const ShiftPaymentBreakdown({
    required this.method,
    required this.receivedCents,
    required this.refundedCents,
  });

  int get netCents => receivedCents - refundedCents;
}

class CashierShiftSummary {
  final int salesCount;
  final int linkedReturnsCount;
  final int adjustmentReturnsCount;
  final int additionalPaymentsCount;
  final int grossSalesCents;
  final int returnsCents;
  final int additionalPaymentsCents;
  final int openingCashCents;
  final int cashReceivedCents;
  final int cashRefundedCents;
  final int expectedCashCents;
  final int? countedCashCents;
  final int? varianceCents;
  final int foreignCurrencyTransactions;
  final List<ShiftPaymentBreakdown> paymentBreakdown;

  const CashierShiftSummary({
    required this.salesCount,
    required this.linkedReturnsCount,
    required this.adjustmentReturnsCount,
    required this.additionalPaymentsCount,
    required this.grossSalesCents,
    required this.returnsCents,
    required this.additionalPaymentsCents,
    required this.openingCashCents,
    required this.cashReceivedCents,
    required this.cashRefundedCents,
    required this.expectedCashCents,
    required this.countedCashCents,
    required this.varianceCents,
    required this.foreignCurrencyTransactions,
    required this.paymentBreakdown,
  });

  int get netSalesCents => grossSalesCents - returnsCents;
  int get returnsCount => linkedReturnsCount + adjustmentReturnsCount;
}

enum ShiftTransactionKind { sale, linkedReturn, adjustmentReturn, payment }

class ShiftTransactionView {
  final ShiftTransactionKind kind;
  final int sourceId;
  final String documentNumber;
  final int amountCents;
  final int cashImpactCents;
  final String paymentMethod;
  final String currencyCode;
  final String currencySymbol;
  final DateTime occurredAt;
  final String status;

  const ShiftTransactionView({
    required this.kind,
    required this.sourceId,
    required this.documentNumber,
    required this.amountCents,
    required this.cashImpactCents,
    required this.paymentMethod,
    required this.currencyCode,
    required this.currencySymbol,
    required this.occurredAt,
    required this.status,
  });
}

/// Source of truth for cashier sessions and till reconciliation.
///
/// Documents are linked by a real FK at creation time. We never infer old
/// transactions from a date range because two cashiers may overlap and such
/// attribution would be unauditable.
class CashierShiftService {
  final AppDatabase db;

  const CashierShiftService(this.db);

  Future<int?> resolveOpenShiftId(int? userId) async {
    if (userId == null) return null;
    final row =
        await (db.select(db.cashierShifts)
              ..where(
                (s) => s.cashierUserId.equals(userId) & s.status.equals('open'),
              )
              ..limit(1))
            .getSingleOrNull();
    return row?.id;
  }

  Future<CashierShiftView?> getOpenShiftForUser(int userId) async {
    final rows = await _shiftViews(userId: userId, openOnly: true, limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<List<CashierShiftView>> getOpenShifts({int limit = 100}) {
    return _shiftViews(openOnly: true, limit: limit);
  }

  Future<CashierShiftView?> getShift(int shiftId) async {
    final rows = await _shiftViews(shiftId: shiftId, limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  /// Returns the exact cashier shift frozen on a sale document.
  ///
  /// This deliberately does not infer a cashier from the document date or
  /// from the currently logged-in user: overlapping shifts make either
  /// inference unauditable.
  Future<CashierShiftView?> getSaleShift(int saleId) async {
    final sale =
        await (db.select(db.sales)
              ..where((s) => s.id.equals(saleId))
              ..limit(1))
            .getSingleOrNull();
    final shiftId = sale?.cashierShiftId;
    return shiftId == null ? null : getShift(shiftId);
  }

  /// Returns the cashier who actually processed a linked sale return, not
  /// the cashier who created the original invoice.
  Future<CashierShiftView?> getSaleReturnShift(int returnId) async {
    final saleReturn =
        await (db.select(db.saleReturns)
              ..where((r) => r.id.equals(returnId))
              ..limit(1))
            .getSingleOrNull();
    final shiftId = saleReturn?.cashierShiftId;
    return shiftId == null ? null : getShift(shiftId);
  }

  /// Returns the cashier who posted an unlinked/adjustment sale return.
  Future<CashierShiftView?> getSaleAdjustmentReturnShift(int returnId) async {
    final saleReturn =
        await (db.select(db.saleReturnAdjustments)
              ..where((r) => r.id.equals(returnId))
              ..limit(1))
            .getSingleOrNull();
    final shiftId = saleReturn?.cashierShiftId;
    return shiftId == null ? null : getShift(shiftId);
  }

  Future<List<CashierShiftView>> getShiftHistory({
    int? userId,
    int limit = 100,
  }) => _shiftViews(userId: userId, limit: limit);

  Stream<void> watchChanges() => db.cashierShifts.select().watch().map((_) {});

  Future<List<CashierShiftView>> _shiftViews({
    int? shiftId,
    int? userId,
    bool openOnly = false,
    int limit = 100,
  }) async {
    final query = db.select(db.cashierShifts).join([
      innerJoin(
        db.users,
        db.users.id.equalsExp(db.cashierShifts.cashierUserId),
      ),
      innerJoin(
        db.currencies,
        db.currencies.id.equalsExp(db.cashierShifts.currencyId),
      ),
      leftOuterJoin(
        db.employees,
        db.employees.id.equalsExp(db.users.employeeId),
      ),
    ]);
    if (shiftId != null) {
      query.where(db.cashierShifts.id.equals(shiftId));
    }
    if (userId != null) {
      query.where(db.cashierShifts.cashierUserId.equals(userId));
    }
    if (openOnly) query.where(db.cashierShifts.status.equals('open'));
    query
      ..orderBy([OrderingTerm.desc(db.cashierShifts.openedAt)])
      ..limit(limit);
    final rows = await query.get();
    return rows
        .map(
          (row) => CashierShiftView(
            shift: row.readTable(db.cashierShifts),
            cashierName:
                row.readTableOrNull(db.employees)?.name ??
                row.readTable(db.users).username,
            currencyCode: row.readTable(db.currencies).code,
            currencySymbol: row.readTable(db.currencies).symbol,
          ),
        )
        .toList(growable: false);
  }

  Future<CashierShiftView> openShift({
    required int userId,
    required int openingCashCents,
    String? currencyCode,
    String? notes,
    DateTime? openedAt,
  }) async {
    if (openingCashCents < 0) {
      throw ArgumentError.value(
        openingCashCents,
        'openingCashCents',
        'Opening cash cannot be negative',
      );
    }
    final now = openedAt ?? DateTime.now();
    final id = await db.transaction(() async {
      final existing = await resolveOpenShiftId(userId);
      if (existing != null) {
        throw StateError('cashier_shift_already_open');
      }
      final selectedCurrency = currencyCode == null
          ? null
          : await (db.select(db.currencies)
                  ..where(
                    (c) =>
                        c.code.equals(currencyCode) & c.isActive.equals(true),
                  )
                  ..limit(1))
                .getSingleOrNull();
      final currency =
          selectedCurrency ??
          await (db.select(db.currencies)
                ..where((c) => c.isBase.equals(true) & c.isActive.equals(true))
                ..limit(1))
              .getSingleOrNull();
      final fallback =
          currency ??
          await (db.select(db.currencies)
                ..where((c) => c.isActive.equals(true))
                ..orderBy([(c) => OrderingTerm.asc(c.id)])
                ..limit(1))
              .getSingleOrNull();
      if (fallback == null) throw StateError('cashier_shift_no_currency');

      final stamp = now.microsecondsSinceEpoch.toString();
      final number =
          'SH-${_compactDate(now)}-$userId-'
          '${stamp.substring(stamp.length - 6)}';
      return db
          .into(db.cashierShifts)
          .insert(
            CashierShiftsCompanion.insert(
              shiftNumber: number,
              cashierUserId: userId,
              currencyId: fallback.id,
              openingCashCents: Value(Decimal.fromInt(openingCashCents)),
              openingNotes: Value(
                notes?.trim().isEmpty == true ? null : notes?.trim(),
              ),
              openedAt: Value(now),
            ),
          );
    });
    return (await getShift(id))!;
  }

  Future<CashierShiftSummary> closeShift({
    required int shiftId,
    required int closedByUserId,
    required int countedClosingCashCents,
    String? notes,
    DateTime? closedAt,
  }) async {
    if (countedClosingCashCents < 0) {
      throw ArgumentError.value(
        countedClosingCashCents,
        'countedClosingCashCents',
        'Counted cash cannot be negative',
      );
    }
    return db.transaction(() async {
      final shift = await (db.select(
        db.cashierShifts,
      )..where((s) => s.id.equals(shiftId))).getSingleOrNull();
      if (shift == null) throw StateError('cashier_shift_not_found');
      if (shift.status != 'open') throw StateError('cashier_shift_closed');
      final summary = await getSummary(shiftId);
      final variance = countedClosingCashCents - summary.expectedCashCents;
      await (db.update(
        db.cashierShifts,
      )..where((s) => s.id.equals(shiftId))).write(
        CashierShiftsCompanion(
          status: const Value('closed'),
          expectedClosingCashCents: Value(
            Decimal.fromInt(summary.expectedCashCents),
          ),
          countedClosingCashCents: Value(
            Decimal.fromInt(countedClosingCashCents),
          ),
          cashVarianceCents: Value(Decimal.fromInt(variance)),
          closingNotes: Value(
            notes?.trim().isEmpty == true ? null : notes?.trim(),
          ),
          closedAt: Value(closedAt ?? DateTime.now()),
          closedBy: Value(closedByUserId),
          updatedAt: Value(DateTime.now()),
        ),
      );
      return CashierShiftSummary(
        salesCount: summary.salesCount,
        linkedReturnsCount: summary.linkedReturnsCount,
        adjustmentReturnsCount: summary.adjustmentReturnsCount,
        additionalPaymentsCount: summary.additionalPaymentsCount,
        grossSalesCents: summary.grossSalesCents,
        returnsCents: summary.returnsCents,
        additionalPaymentsCents: summary.additionalPaymentsCents,
        openingCashCents: summary.openingCashCents,
        cashReceivedCents: summary.cashReceivedCents,
        cashRefundedCents: summary.cashRefundedCents,
        expectedCashCents: summary.expectedCashCents,
        countedCashCents: countedClosingCashCents,
        varianceCents: variance,
        foreignCurrencyTransactions: summary.foreignCurrencyTransactions,
        paymentBreakdown: summary.paymentBreakdown,
      );
    });
  }

  Future<CashierShiftSummary> getSummary(int shiftId) async {
    final shift = await (db.select(
      db.cashierShifts,
    )..where((s) => s.id.equals(shiftId))).getSingleOrNull();
    if (shift == null) throw StateError('cashier_shift_not_found');
    final currencyId = shift.currencyId;

    final sales =
        await (db.select(db.sales)..where(
              (s) =>
                  s.cashierShiftId.equals(shiftId) &
                  s.status.equals('completed'),
            ))
            .get();
    final linkedReturns =
        await (db.select(db.saleReturns)..where(
              (r) =>
                  r.cashierShiftId.equals(shiftId) & r.status.equals('posted'),
            ))
            .get();
    final adjustmentReturns =
        await (db.select(db.saleReturnAdjustments)..where(
              (r) =>
                  r.cashierShiftId.equals(shiftId) & r.status.equals('posted'),
            ))
            .get();
    final payments = await (db.select(
      db.salePayments,
    )..where((p) => p.cashierShiftId.equals(shiftId))).get();

    final localSales = sales.where((e) => e.currencyId == currencyId).toList();
    final localLinked = linkedReturns
        .where((e) => e.currencyId == currencyId)
        .toList();
    final localAdjustments = adjustmentReturns
        .where((e) => e.currencyId == currencyId)
        .toList();
    final localPayments = payments
        .where((e) => e.currencyId == currencyId)
        .toList();

    int amount(Decimal value) => value.toBigInt().toInt();
    final receivedByMethod = <String, int>{};
    final refundedByMethod = <String, int>{};
    for (final sale in localSales) {
      final paid = amount(sale.paidAmountCents);
      if (paid > 0) {
        receivedByMethod.update(
          sale.paymentMethod,
          (v) => v + paid,
          ifAbsent: () => paid,
        );
      }
    }
    for (final payment in localPayments) {
      final paid = amount(payment.amountCents);
      receivedByMethod.update(
        payment.paymentMethod,
        (v) => v + paid,
        ifAbsent: () => paid,
      );
    }
    for (final ret in localLinked) {
      final refund = amount(ret.totalCents);
      refundedByMethod.update(
        ret.refundMethod,
        (v) => v + refund,
        ifAbsent: () => refund,
      );
    }
    for (final ret in localAdjustments) {
      final refund = amount(ret.totalCents);
      refundedByMethod.update(
        ret.refundMethod,
        (v) => v + refund,
        ifAbsent: () => refund,
      );
    }
    final methods = {
      ...receivedByMethod.keys,
      ...refundedByMethod.keys,
    }.toList()..sort();
    final breakdown = methods
        .map(
          (method) => ShiftPaymentBreakdown(
            method: method,
            receivedCents: receivedByMethod[method] ?? 0,
            refundedCents: refundedByMethod[method] ?? 0,
          ),
        )
        .toList(growable: false);

    final grossSales = localSales.fold<int>(
      0,
      (sum, row) => sum + amount(row.totalCents),
    );
    final returns =
        localLinked.fold<int>(0, (sum, row) => sum + amount(row.totalCents)) +
        localAdjustments.fold<int>(
          0,
          (sum, row) => sum + amount(row.totalCents),
        );
    final additionalPayments = localPayments.fold<int>(
      0,
      (sum, row) => sum + amount(row.amountCents),
    );
    final cashReceived = receivedByMethod['cash'] ?? 0;
    final cashRefunded = refundedByMethod['cash'] ?? 0;
    final opening = amount(shift.openingCashCents);
    final expected = opening + cashReceived - cashRefunded;
    final counted = shift.countedClosingCashCents == null
        ? null
        : amount(shift.countedClosingCashCents!);
    final variance = shift.cashVarianceCents == null
        ? null
        : amount(shift.cashVarianceCents!);

    return CashierShiftSummary(
      salesCount: sales.length,
      linkedReturnsCount: linkedReturns.length,
      adjustmentReturnsCount: adjustmentReturns.length,
      additionalPaymentsCount: payments.length,
      grossSalesCents: grossSales,
      returnsCents: returns,
      additionalPaymentsCents: additionalPayments,
      openingCashCents: opening,
      cashReceivedCents: cashReceived,
      cashRefundedCents: cashRefunded,
      expectedCashCents: expected,
      countedCashCents: counted,
      varianceCents: variance,
      foreignCurrencyTransactions:
          (sales.length - localSales.length) +
          (linkedReturns.length - localLinked.length) +
          (adjustmentReturns.length - localAdjustments.length) +
          (payments.length - localPayments.length),
      paymentBreakdown: breakdown,
    );
  }

  Future<List<ShiftTransactionView>> getTransactions(int shiftId) async {
    final currencies = await db.select(db.currencies).get();
    final currencyById = {for (final c in currencies) c.id: c};
    final rows = <ShiftTransactionView>[];
    final sales = await (db.select(
      db.sales,
    )..where((s) => s.cashierShiftId.equals(shiftId))).get();
    final saleById = {for (final sale in sales) sale.id: sale};
    for (final sale in sales) {
      final c = currencyById[sale.currencyId];
      final paid = sale.paidAmountCents.toBigInt().toInt();
      rows.add(
        ShiftTransactionView(
          kind: ShiftTransactionKind.sale,
          sourceId: sale.id,
          documentNumber: sale.invoiceNumber,
          amountCents: sale.totalCents.toBigInt().toInt(),
          cashImpactCents: sale.paymentMethod == 'cash' ? paid : 0,
          paymentMethod: sale.paymentMethod,
          currencyCode: c?.code ?? '',
          currencySymbol: c?.symbol ?? '',
          occurredAt: sale.saleDate,
          status: sale.status,
        ),
      );
    }
    final linkedReturns = await (db.select(
      db.saleReturns,
    )..where((r) => r.cashierShiftId.equals(shiftId))).get();
    for (final ret in linkedReturns) {
      final c = currencyById[ret.currencyId];
      final value = ret.totalCents.toBigInt().toInt();
      rows.add(
        ShiftTransactionView(
          kind: ShiftTransactionKind.linkedReturn,
          sourceId: ret.id,
          documentNumber: ret.returnNumber,
          amountCents: value,
          cashImpactCents: ret.refundMethod == 'cash' ? -value : 0,
          paymentMethod: ret.refundMethod,
          currencyCode: c?.code ?? '',
          currencySymbol: c?.symbol ?? '',
          occurredAt: ret.returnDate,
          status: ret.status,
        ),
      );
    }
    final adjustments = await (db.select(
      db.saleReturnAdjustments,
    )..where((r) => r.cashierShiftId.equals(shiftId))).get();
    for (final ret in adjustments) {
      final c = currencyById[ret.currencyId];
      final value = ret.totalCents.toBigInt().toInt();
      rows.add(
        ShiftTransactionView(
          kind: ShiftTransactionKind.adjustmentReturn,
          sourceId: ret.id,
          documentNumber: ret.returnNumber,
          amountCents: value,
          cashImpactCents: ret.refundMethod == 'cash' ? -value : 0,
          paymentMethod: ret.refundMethod,
          currencyCode: c?.code ?? '',
          currencySymbol: c?.symbol ?? '',
          occurredAt: ret.returnDate,
          status: ret.status,
        ),
      );
    }
    final payments = await (db.select(
      db.salePayments,
    )..where((p) => p.cashierShiftId.equals(shiftId))).get();
    for (final payment in payments) {
      final c = currencyById[payment.currencyId];
      final parent =
          saleById[payment.saleId] ??
          await (db.select(
            db.sales,
          )..where((s) => s.id.equals(payment.saleId))).getSingleOrNull();
      final value = payment.amountCents.toBigInt().toInt();
      rows.add(
        ShiftTransactionView(
          kind: ShiftTransactionKind.payment,
          sourceId: payment.id,
          documentNumber: parent?.invoiceNumber ?? '#${payment.saleId}',
          amountCents: value,
          cashImpactCents: payment.paymentMethod == 'cash' ? value : 0,
          paymentMethod: payment.paymentMethod,
          currencyCode: c?.code ?? '',
          currencySymbol: c?.symbol ?? '',
          occurredAt: payment.paymentDate,
          status: 'posted',
        ),
      );
    }
    rows.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    return rows;
  }

  static String _compactDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}'
      '${date.month.toString().padLeft(2, '0')}'
      '${date.day.toString().padLeft(2, '0')}';
}
