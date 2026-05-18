import 'package:drift/drift.dart';

import 'users.dart';

/// ChequeConfirmations — Phase 14.0 minimal-risk SoT for cheque lifecycle.
///
/// This is a **dismissal / status sidecar** for cheque-bearing documents.
/// It does NOT replace the source document's `payment_method` / `refund_method`
/// or its `due_date`; those remain the canonical economic record.
///
/// Pre-Phase-14 the dashboard reminder dismissal was stored in
/// `SharedPreferences` under the key `confirmed_cheques_list` — surviving
/// neither device migration nor app reinstall, and producing zero audit
/// trail. This table moves that state into the DB without altering any
/// existing journal-entry policy (deferred to a future full phase).
///
/// One row per (source_table, source_id) — the natural key of every
/// cheque-bearing document in the system. The six allowed source tables:
///   • sales                              (incoming cheque)
///   • purchases                          (outgoing cheque)
///   • sale_returns                       (outgoing cheque)
///   • purchase_returns                   (incoming cheque)
///   • sale_return_adjustments            (outgoing cheque)
///   • purchase_return_adjustments        (incoming cheque)
///
/// `status` lifecycle (kept minimal — no JE changes yet):
///   • `pending`    — default; cheque still in motion. Surfaced as a
///                    reminder card on the dashboard.
///   • `cleared`    — user confirmed the cheque cleared (cash hit/left
///                    the bank). Hides the reminder.
///   • `bounced`    — user confirmed the cheque bounced. Hides the
///                    standard reminder; keeps an audit record. A future
///                    phase will wire a JE reversal here.
///   • `cancelled`  — user voided / stopped the cheque. Hides reminder.
@DataClassName('ChequeConfirmation')
class ChequeConfirmations extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// One of: `sale`, `purchase`, `sale_return`, `purchase_return`,
  /// `sale_return_adjustment`, `purchase_return_adjustment`.
  /// Kept as TEXT (no FK) because the row spans six different parent
  /// tables — same pattern as `audit_logs.entity_type`.
  TextColumn get sourceTable => text()();

  /// PK of the source row in `sourceTable`.
  IntColumn get sourceId => integer()();

  /// `pending` | `cleared` | `bounced` | `cancelled`.
  TextColumn get status =>
      text().withDefault(const Constant('pending'))();

  /// Set when status transitions away from `pending`.
  DateTimeColumn get confirmedAt => dateTime().nullable()();

  @ReferenceName('chequeConfirmedBy')
  IntColumn get confirmedBy =>
      integer().nullable().references(Users, #id, onDelete: KeyAction.setNull)();

  /// Free-text note (e.g. "deposited at branch", "represented Friday").
  TextColumn get note => text().nullable()();

  /// Required when status = `bounced`. Free-text (NSF, stop-pay, etc.).
  TextColumn get bounceReason => text().nullable()();

  /// **Phase 15.0 — Cheque lifecycle JE wiring.**
  ///
  /// When status transitions `pending → cleared` for `source_table ∈
  /// {sale, purchase}`, the [`ChequeLifecycleService`] also calls
  /// `SaleRepository.recordPayment` / `PurchaseRepository.recordPayment`
  /// for the outstanding `(total − paid)` amount. The resulting
  /// `sale_payments.id` / `purchase_payments.id` is stamped here so that
  /// a later `cleared → bounced` (or `cleared → cancelled`) transition
  /// can deterministically reverse the matching payment row via the
  /// existing `deletePayment` SoT (which itself voids the JE and restores
  /// the party balance).
  ///
  /// Nullable because:
  ///   - returns (the 4 non-sale/non-purchase source_table values) never
  ///     record a settlement payment — their original return JE already
  ///     debited/credited the cash leg at posting time;
  ///   - a `pending → cleared` on a fully-paid sale/purchase
  ///     (`outstanding == 0`) is a no-op payment-wise.
  ///
  /// The polymorphic interpretation (purchase_payments vs sale_payments)
  /// is driven by [`sourceTable`] — no separate column needed. See
  /// `docs/ACCOUNTING_INTEGRITY_GUIDELINES.md` §Phase-15.
  IntColumn get clearedPaymentId => integer().nullable()();

  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();

  /// Natural key — at most one confirmation row per cheque-bearing
  /// document. Upsert on (source_table, source_id) is the only write path.
  @override
  List<Set<Column>> get uniqueKeys => [
        {sourceTable, sourceId},
      ];
}
