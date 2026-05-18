import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/cheques.dart';

part 'cheque_confirmation_dao.g.dart';

/// Allowed values for `cheque_confirmations.source_table`.
///
/// Kept as a plain Dart const set (not an enum stored in DB) so the
/// reminder widget's UNION query and this DAO share the same vocabulary
/// without forcing schema churn on every new cheque source.
class ChequeSourceTables {
  ChequeSourceTables._();

  static const String sale = 'sale';
  static const String purchase = 'purchase';
  static const String saleReturn = 'sale_return';
  static const String purchaseReturn = 'purchase_return';
  static const String saleReturnAdjustment = 'sale_return_adjustment';
  static const String purchaseReturnAdjustment = 'purchase_return_adjustment';

  static const Set<String> all = {
    sale,
    purchase,
    saleReturn,
    purchaseReturn,
    saleReturnAdjustment,
    purchaseReturnAdjustment,
  };
}

/// Allowed `cheque_confirmations.status` values.
class ChequeConfirmationStatus {
  ChequeConfirmationStatus._();

  static const String pending = 'pending';
  static const String cleared = 'cleared';
  static const String bounced = 'bounced';
  static const String cancelled = 'cancelled';

  static const Set<String> all = {pending, cleared, bounced, cancelled};
  static const Set<String> resolved = {cleared, bounced, cancelled};
}

/// Single source of truth for cheque-confirmation state.
///
/// Pre-Phase-14 the dashboard reminder dismissal lived in
/// `SharedPreferences` only. This DAO moves that state into the database
/// and exposes it via a strict (source_table, source_id) natural key.
///
/// **What this DAO does NOT do:**
/// - It does not change journal entries.
/// - It does not enforce that `source_table`/`source_id` references a
///   real row (the six parent tables span six different feature
///   boundaries; FK fanout is deliberately avoided here).
/// - It does not auto-clear on `due_date` \u2014 the user explicitly
///   confirms every transition (matches real-world banking).
@DriftAccessor(tables: [ChequeConfirmations])
class ChequeConfirmationDao extends DatabaseAccessor<AppDatabase>
    with _$ChequeConfirmationDaoMixin {
  ChequeConfirmationDao(AppDatabase db) : super(db);

  /// Fetch a single confirmation row by its natural key.
  /// Returns `null` if no confirmation has been recorded yet (i.e. the
  /// cheque is implicitly `pending`).
  Future<ChequeConfirmation?> getBySource({
    required String sourceTable,
    required int sourceId,
  }) {
    _assertValidSourceTable(sourceTable);
    return (select(chequeConfirmations)
          ..where((c) =>
              c.sourceTable.equals(sourceTable) &
              c.sourceId.equals(sourceId)))
        .getSingleOrNull();
  }

  /// Watch a single confirmation row for reactive UI badges.
  Stream<ChequeConfirmation?> watchBySource({
    required String sourceTable,
    required int sourceId,
  }) {
    _assertValidSourceTable(sourceTable);
    return (select(chequeConfirmations)
          ..where((c) =>
              c.sourceTable.equals(sourceTable) &
              c.sourceId.equals(sourceId)))
        .watchSingleOrNull();
  }

  /// Get all confirmations as a map keyed by `'$table|$id'`. Used by the
  /// dashboard reminder to efficiently filter out resolved cheques.
  Stream<Map<String, ChequeConfirmation>> watchAllAsMap() {
    return select(chequeConfirmations).watch().map((rows) {
      final m = <String, ChequeConfirmation>{};
      for (final r in rows) {
        m['${r.sourceTable}|${r.sourceId}'] = r;
      }
      return m;
    });
  }

  /// Upsert idempotently. Calling this with the same `(source, status)`
  /// twice is a no-op; calling it with a new status updates the existing
  /// row and bumps `updated_at`.
  ///
  /// **Phase 15.0** — added [`clearedPaymentId`] (nullable). Set by the
  /// `ChequeLifecycleService` when transitioning `pending → cleared` for
  /// a `sale`/`purchase` source that had an outstanding balance. Cleared
  /// (set to `null` explicitly) when transitioning out of `cleared` —
  /// pass [`clearClearedPaymentId`]`= true` to opt-in.
  ///
  /// Returns the `id` of the affected row.
  Future<int> confirm({
    required String sourceTable,
    required int sourceId,
    required String status,
    String? note,
    String? bounceReason,
    int? userId,
    DateTime? confirmedAt,
    int? clearedPaymentId,
    bool clearClearedPaymentId = false,
  }) async {
    _assertValidSourceTable(sourceTable);
    if (!ChequeConfirmationStatus.all.contains(status)) {
      throw ArgumentError.value(
        status,
        'status',
        'Must be one of ${ChequeConfirmationStatus.all}',
      );
    }
    if (status == ChequeConfirmationStatus.bounced &&
        (bounceReason == null || bounceReason.trim().isEmpty)) {
      throw ArgumentError(
        'bounceReason is required when status = bounced',
      );
    }
    if (clearedPaymentId != null && clearClearedPaymentId) {
      throw ArgumentError(
        'clearedPaymentId and clearClearedPaymentId are mutually exclusive',
      );
    }

    final now = DateTime.now();
    final effectiveConfirmedAt = status == ChequeConfirmationStatus.pending
        ? null
        : (confirmedAt ?? now);

    // Translate the nullable+flag pair into a Drift `Value<int?>`.
    // - `clearClearedPaymentId == true` → write SQL NULL explicitly.
    // - `clearedPaymentId != null`      → write the int.
    // - otherwise                       → absent (preserve existing value).
    final Value<int?> clearedPaymentIdValue;
    if (clearClearedPaymentId) {
      clearedPaymentIdValue = const Value<int?>(null);
    } else if (clearedPaymentId != null) {
      clearedPaymentIdValue = Value(clearedPaymentId);
    } else {
      clearedPaymentIdValue = const Value.absent();
    }

    return transaction(() async {
      final existing = await (select(chequeConfirmations)
            ..where((c) =>
                c.sourceTable.equals(sourceTable) &
                c.sourceId.equals(sourceId)))
          .getSingleOrNull();

      if (existing == null) {
        return into(chequeConfirmations).insert(
          ChequeConfirmationsCompanion.insert(
            sourceTable: sourceTable,
            sourceId: sourceId,
            status: Value(status),
            confirmedAt: Value(effectiveConfirmedAt),
            confirmedBy: Value(userId),
            note: Value(note),
            bounceReason: Value(bounceReason),
            clearedPaymentId: clearedPaymentIdValue,
          ),
        );
      }

      // Idempotency — same status, same note, same bounce reason, and no
      // payment-id mutation requested ⇒ no write.
      final paymentIdNoOp = !clearedPaymentIdValue.present;
      if (existing.status == status &&
          existing.note == note &&
          existing.bounceReason == bounceReason &&
          paymentIdNoOp) {
        return existing.id;
      }

      await (update(chequeConfirmations)
            ..where((c) => c.id.equals(existing.id)))
          .write(
        ChequeConfirmationsCompanion(
          status: Value(status),
          confirmedAt: Value(effectiveConfirmedAt),
          confirmedBy: Value(userId),
          note: Value(note),
          bounceReason: Value(bounceReason),
          clearedPaymentId: clearedPaymentIdValue,
          updatedAt: Value(now),
        ),
      );
      return existing.id;
    });
  }

  /// Re-open a resolved cheque (e.g. user clicked "Undo Cleared").
  /// Sets status back to `pending` and clears `confirmed_at` /
  /// `confirmed_by` / `bounce_reason`.
  Future<void> reopenToPending({
    required String sourceTable,
    required int sourceId,
  }) async {
    _assertValidSourceTable(sourceTable);
    await (update(chequeConfirmations)
          ..where((c) =>
              c.sourceTable.equals(sourceTable) &
              c.sourceId.equals(sourceId)))
        .write(
      ChequeConfirmationsCompanion(
        status: const Value(ChequeConfirmationStatus.pending),
        confirmedAt: const Value(null),
        confirmedBy: const Value(null),
        bounceReason: const Value(null),
        // Phase 15.0 — drop the payment linkage when re-opening to pending.
        // (If a payment row was created during a previous cleared, the
        // caller MUST reverse it before re-opening; we just clear the
        // pointer here so a stale FK can't confuse future transitions.)
        clearedPaymentId: const Value<int?>(null),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// One-time helper used by the SharedPreferences\u2192DB migration.
  /// Inserts a `cleared` row only if no row already exists for the
  /// natural key. Never overwrites.
  Future<bool> backfillClearedIfAbsent({
    required String sourceTable,
    required int sourceId,
  }) async {
    _assertValidSourceTable(sourceTable);
    final existing = await getBySource(
      sourceTable: sourceTable,
      sourceId: sourceId,
    );
    if (existing != null) return false;
    await into(chequeConfirmations).insert(
      ChequeConfirmationsCompanion.insert(
        sourceTable: sourceTable,
        sourceId: sourceId,
        status: const Value(ChequeConfirmationStatus.cleared),
        confirmedAt: Value(DateTime.now()),
        note: const Value('backfilled from local dismissal'),
      ),
    );
    return true;
  }

  void _assertValidSourceTable(String sourceTable) {
    if (!ChequeSourceTables.all.contains(sourceTable)) {
      throw ArgumentError.value(
        sourceTable,
        'sourceTable',
        'Must be one of ${ChequeSourceTables.all}',
      );
    }
  }
}
