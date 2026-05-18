import 'dart:developer' as developer;

import 'package:drift/drift.dart';

import '../../database/app_database.dart';
import '../../../features/accounting/domain/exceptions/accounting_exception.dart';

/// Thrown when a post / void is attempted against a date that falls
/// inside a **closed** fiscal period.
///
/// This is a **compliance invariant** — IFRS / IAS 8 and every mature
/// accounting system (QB, Odoo, NetSuite, SAP B1) enforce it. Closed
/// periods are frozen; altering them retroactively invalidates already-
/// issued statements.
class FiscalPeriodClosedException extends AccountingException {
  final String periodKey;
  final DateTime attemptedDate;

  FiscalPeriodClosedException({
    required this.periodKey,
    required this.attemptedDate,
  }) : super(
          'Fiscal period $periodKey is closed — cannot post or void '
          'a transaction with effective date $attemptedDate.',
        );
}

/// **Single source of truth** for fiscal-period management.
///
/// Every code path that creates or voids a journal entry (directly or
/// transitively) MUST funnel its effective date through
/// [assertOpen] before persisting. `ReturnPostingService.post` does
/// this automatically; other services (sales, purchases, payroll JEs,
/// etc.) should follow the same pattern when Phase 4 wires them in.
///
/// Design notes:
///   • Periods are month-level (`'YYYY-MM'`). Finer granularity (weekly,
///     daily) is not supported — no real-world ERP we target needs it,
///     and month is the standard reporting bucket.
///   • [ensurePeriod] is idempotent: calling it repeatedly for the same
///     month always returns the same row.
///   • Closing a period is a one-way op from the service's POV; reopening
///     requires an explicit admin call ([reopenPeriod]) that is logged.
class FiscalPeriodService {
  final AppDatabase _db;

  FiscalPeriodService(this._db);

  /// Format a date as the canonical period key `'YYYY-MM'`.
  static String keyFor(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    return '$y-$m';
  }

  /// Compute the inclusive start/end bounds of the month containing [date].
  /// Start = first of month 00:00:00; End = last of month 23:59:59.
  static ({DateTime start, DateTime end}) monthBounds(DateTime date) {
    final start = DateTime(date.year, date.month, 1);
    // Last day of month: first of next month minus one microsecond.
    final nextMonth = (date.month == 12)
        ? DateTime(date.year + 1, 1, 1)
        : DateTime(date.year, date.month + 1, 1);
    final end = nextMonth.subtract(const Duration(microseconds: 1));
    return (start: start, end: end);
  }

  /// Ensure a period row exists for the month of [date]. Returns the row.
  Future<FiscalPeriod> ensurePeriod(DateTime date) async {
    final key = keyFor(date);
    final existing = await (_db.select(_db.fiscalPeriods)
          ..where((p) => p.periodKey.equals(key)))
        .getSingleOrNull();
    if (existing != null) return existing;

    final bounds = monthBounds(date);
    final now = DateTime.now();
    final id = await _db.into(_db.fiscalPeriods).insert(
          FiscalPeriodsCompanion.insert(
            periodKey: key,
            startDate: bounds.start,
            endDate: bounds.end,
            status: const Value('open'),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
    final inserted = await (_db.select(_db.fiscalPeriods)
          ..where((p) => p.id.equals(id)))
        .getSingle();
    developer.log(
      'FiscalPeriodService: created new period $key '
      '(${bounds.start} .. ${bounds.end}) status=open',
      name: 'FiscalPeriodService',
    );
    return inserted;
  }

  /// Throws [FiscalPeriodClosedException] when the period for [date] is
  /// closed. Auto-creates the period row if missing (default status=open).
  Future<void> assertOpen(DateTime date) async {
    final period = await ensurePeriod(date);
    if (period.status == 'closed') {
      throw FiscalPeriodClosedException(
        periodKey: period.periodKey,
        attemptedDate: date,
      );
    }
  }

  /// Close the period identified by [periodKey]. No-op if already closed.
  ///
  /// Records the closer's user id + timestamp + optional notes. The
  /// caller is responsible for validating permission (admin-only) before
  /// invoking this method — the service does not check roles.
  Future<void> closePeriod({
    required String periodKey,
    int? userId,
    String? notes,
  }) async {
    final now = DateTime.now();
    final count = await (_db.update(_db.fiscalPeriods)
          ..where((p) => p.periodKey.equals(periodKey)))
        .write(FiscalPeriodsCompanion(
      status: const Value('closed'),
      closedByUserId: Value(userId),
      closedAt: Value(now),
      notes: Value(notes),
      updatedAt: Value(now),
    ));
    if (count == 0) {
      throw AccountingException(
        'FiscalPeriodService.closePeriod: no period found with key "$periodKey".',
      );
    }
    developer.log(
      'FiscalPeriodService: closed $periodKey by user=$userId '
      '(notes="${notes ?? ""}")',
      name: 'FiscalPeriodService',
    );
  }

  /// Reopen a previously closed period. Admin-only; logs the event.
  Future<void> reopenPeriod({
    required String periodKey,
    int? userId,
    String? notes,
  }) async {
    final now = DateTime.now();
    final count = await (_db.update(_db.fiscalPeriods)
          ..where((p) => p.periodKey.equals(periodKey)))
        .write(FiscalPeriodsCompanion(
      status: const Value('open'),
      closedByUserId: const Value(null),
      closedAt: const Value(null),
      notes: Value(notes),
      updatedAt: Value(now),
    ));
    if (count == 0) {
      throw AccountingException(
        'FiscalPeriodService.reopenPeriod: no period found with key "$periodKey".',
      );
    }
    developer.log(
      'FiscalPeriodService: reopened $periodKey by user=$userId',
      name: 'FiscalPeriodService',
    );
  }

  /// List all periods ordered most-recent first. Used by the admin screen.
  Future<List<FiscalPeriod>> listAll({int? limit}) {
    final q = _db.select(_db.fiscalPeriods)
      ..orderBy([(p) => OrderingTerm.desc(p.startDate)]);
    if (limit != null) q.limit(limit);
    return q.get();
  }

  Stream<List<FiscalPeriod>> watchAll() {
    return (_db.select(_db.fiscalPeriods)
          ..orderBy([(p) => OrderingTerm.desc(p.startDate)]))
        .watch();
  }

  Future<FiscalPeriod?> getByKey(String periodKey) {
    return (_db.select(_db.fiscalPeriods)
          ..where((p) => p.periodKey.equals(periodKey)))
        .getSingleOrNull();
  }
}
