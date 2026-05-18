import 'package:drift/drift.dart';
import '../converters/money_converter.dart';
import 'parties.dart';
import 'settings.dart';

// ════════════════════════════════════════════════════════════════════════════
// Phase 2 — Compliance & period management
// ════════════════════════════════════════════════════════════════════════════
//
// Three new tables introduced in schema v10051:
//
//   • `fiscal_periods`              — month-level open/closed buckets used to
//                                     block post/void in closed periods.
//   • `customer_credit_notes`       — issued credit notes (refund=credit on
//                                     unlinked sale returns); the open balance
//                                     reconciles 1:1 with 2400 Customer Credit
//                                     Liability in the GL.
//   • `customer_credit_note_apps`   — applications of a credit note to a
//                                     subsequent sale (Dr 2400, Cr 1100 AR).
//
// Each table is fully self-contained — no FK to return tables to keep the
// audit trail intact even if a return is later voided.

/// One row per (year, month). Closed periods reject any post/void whose
/// effective date falls inside their bounds. Closing a period is an
/// administrative act recorded with `closed_by` + `closed_at` + `notes`.
///
/// Naming follows the international standard for accounting periods: the
/// `period_key` is `YYYY-MM` and is unique. Year-end is just December
/// closing; full-year close is therefore implicit.
@DataClassName('FiscalPeriod')
class FiscalPeriods extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// `'YYYY-MM'` — unique key for fast lookups.
  TextColumn get periodKey => text().unique()();

  /// Inclusive start of the period (00:00:00 of the first day).
  DateTimeColumn get startDate => dateTime()();

  /// Inclusive end of the period (23:59:59 of the last day).
  DateTimeColumn get endDate => dateTime()();

  /// `'open'` | `'closed'` — only `'closed'` blocks new posts.
  TextColumn get status => text().withDefault(const Constant('open'))();

  /// User id that closed the period (audit; nullable while open).
  IntColumn get closedByUserId => integer().nullable()();
  DateTimeColumn get closedAt => dateTime().nullable()();
  TextColumn get notes => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

/// A customer credit note issued when a sale return is settled with
/// `refund=credit` AND no original invoice is referenced. This is the
/// sub-ledger backing 2400 Customer Credit Liability in the chart of
/// accounts: Σ(open balances) here MUST equal the 2400 GL balance.
///
/// Lifecycle:
///   1. Issued by `CustomerCreditNoteService.issue` when the policy routes
///      a sale return to 2400 (Cr 2400 in the JE).
///   2. Applied to a future sale via
///      `CustomerCreditNoteService.apply` (Dr 2400, Cr 1100 AR).
///   3. Optionally voided (status=`voided`) — only allowed when no
///      applications exist.
///
/// Why a separate ledger:
///   AR (1100) per-customer balances would otherwise turn negative when an
///   adjustment-return refund=credit is issued without a matching invoice.
///   Aging reports cannot reconcile that. By holding the liability in
///   2400 and tracking the per-customer balance here, AR stays clean.
@DataClassName('CustomerCreditNote')
class CustomerCreditNotes extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// `'CCN-YYYYMM-NNNN'` (or similar) — unique human-readable id.
  TextColumn get noteNumber => text().unique()();

  IntColumn get customerId =>
      integer().references(Customers, #id, onDelete: KeyAction.restrict)();

  IntColumn get currencyId =>
      integer().references(Currencies, #id, onDelete: KeyAction.restrict)();

  /// Original face value of the credit note (cents).
  IntColumn get originalAmountCents =>
      integer().map(const MoneyConverter())();

  /// Open balance remaining for application (cents). Decreases as the
  /// note is applied to subsequent sales. `0` once fully consumed.
  IntColumn get balanceCents => integer().map(const MoneyConverter())();

  /// `'open'` | `'partially_applied'` | `'fully_applied'` | `'voided'`.
  TextColumn get status => text().withDefault(const Constant('open'))();

  /// Source-of-issue pointer — which return generated this note.
  /// Soft pointer (no FK) so a later void of the return does not lose
  /// the audit link.
  TextColumn get sourceTable => text()();
  IntColumn get sourceId => integer()();

  /// Linked journal-entry id for the issuance leg (Cr 2400).
  IntColumn get issueJournalEntryId => integer().nullable()();

  /// Optional expiry. NULL = never expires.
  DateTimeColumn get expiresAt => dateTime().nullable()();

  TextColumn get notes => text().nullable()();

  DateTimeColumn get issuedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

/// One row per application of a credit note to a subsequent sale.
/// Multiple applications per note are allowed; together they MUST sum
/// to `original_amount_cents − current_balance_cents`.
///
/// Each application generates its own JE (Dr 2400, Cr 1100 AR) recorded
/// via `journal_entry_id`.
@DataClassName('CustomerCreditNoteApplication')
class CustomerCreditNoteApplications extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get creditNoteId => integer().references(
        CustomerCreditNotes,
        #id,
        onDelete: KeyAction.restrict,
      )();

  /// The sale this application is being credited against. Soft pointer
  /// (no FK) so the application audit trail survives a sale void.
  IntColumn get saleId => integer().nullable()();

  /// Amount applied in this row (cents).
  IntColumn get amountCents => integer().map(const MoneyConverter())();

  /// Linked JE id for the application leg.
  IntColumn get journalEntryId => integer().nullable()();

  TextColumn get notes => text().nullable()();

  DateTimeColumn get appliedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
