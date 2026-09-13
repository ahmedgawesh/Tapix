import 'package:drift/drift.dart';

import '../converters/money_converter.dart';
import 'settings.dart';
import 'transactions.dart';
import 'users.dart';

/// A real negotiable cheque instrument.
///
/// Unlike [ChequeConfirmations] (the legacy one-row-per-document sidecar),
/// this table stores one row per physical cheque. Consequently a document
/// can be settled by several partial cheques and every cheque keeps its own
/// number, bank data, amount and lifecycle/accounting links.
@DataClassName('ChequeInstrument')
class ChequeInstruments extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get direction => text()();
  TextColumn get sourceTable => text()();
  IntColumn get sourceId => integer()();
  TextColumn get partyType => text().nullable()();
  IntColumn get partyId => integer().nullable()();
  IntColumn get amountCents => integer().map(const MoneyConverter())();
  IntColumn get currencyId =>
      integer().references(Currencies, #id, onDelete: KeyAction.restrict)();
  TextColumn get chequeNumber => text().nullable()();
  TextColumn get bankName => text().nullable()();
  TextColumn get branchName => text().nullable()();
  TextColumn get accountNumber => text().nullable()();
  TextColumn get drawerName => text().nullable()();
  DateTimeColumn get issueDate => dateTime().nullable()();
  DateTimeColumn get dueDate => dateTime()();
  TextColumn get status => text()();
  DateTimeColumn get depositedAt => dateTime().nullable()();
  DateTimeColumn get clearedAt => dateTime().nullable()();
  DateTimeColumn get bouncedAt => dateTime().nullable()();
  DateTimeColumn get cancelledAt => dateTime().nullable()();
  TextColumn get bounceReason => text().nullable()();
  TextColumn get note => text().nullable()();

  /// Invoice payment id, or return-settlement journal id, which moved the
  /// party obligation into the appropriate cheque clearing account.
  IntColumn get settlementPaymentId => integer().nullable()();

  /// Journal which moved the clearing account to Bank.
  IntColumn get clearanceJournalEntryId => integer().nullable()();

  /// Journal which restored the party obligation after dishonour/cancel.
  IntColumn get dishonourJournalEntryId => integer().nullable()();

  /// How a bounced cheque was finally resolved: cash, bank, card,
  /// replacement, credit, or write_off. A bounced cheque with no value here
  /// remains an actionable alert in the cheque register and party profile.
  TextColumn get resolutionType => text().nullable()();
  IntColumn get resolutionJournalEntryId => integer().nullable()();
  DateTimeColumn get resolvedAt => dateTime().nullable()();
  TextColumn get resolutionNote => text().nullable()();
  IntColumn get replacementChequeId => integer().nullable()();

  /// Old documents may already have posted directly to Bank.
  BoolColumn get legacyDirectBank =>
      boolean().withDefault(const Constant(false))();

  @ReferenceName('chequeCreatedBy')
  IntColumn get createdBy => integer().nullable().references(
    Users,
    #id,
    onDelete: KeyAction.setNull,
  )();
  @ReferenceName('chequeUpdatedBy')
  IntColumn get updatedBy => integer().nullable().references(
    Users,
    #id,
    onDelete: KeyAction.setNull,
  )();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<String> get customConstraints => [
    "CHECK (direction IN ('incoming','outgoing'))",
    'CHECK (amount_cents > 0)',
    "CHECK (status IN ('received','issued','deposited','cleared','bounced','cancelled','replaced'))",
    "CHECK (party_type IS NULL OR party_type IN ('customer','supplier'))",
  ];
}

/// Legacy one-row-per-document compatibility sidecar.
///
/// This is a **dismissal / status sidecar** for cheque-bearing documents.
/// It does NOT replace the source document's `payment_method` / `refund_method`
/// or its `due_date`; those remain the canonical economic record.
///
/// Before this table the dashboard reminder dismissal was stored in
/// `SharedPreferences` under the key `confirmed_cheques_list` — surviving
/// neither device migration nor app reinstall, and producing zero audit
/// trail. This table moves that state into the DB without altering any
/// existing documents. New operational code uses [ChequeInstruments], where
/// each physical cheque has its own amount, identity and accounting links.
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
/// `status` mirrors the physical-instrument lifecycle for legacy consumers:
///   • `pending`    — default; cheque still in motion. Surfaced as a
///                    reminder card on the dashboard.
///   • `cleared`    — user confirmed the cheque cleared (cash hit/left
///                    the bank). Hides the reminder.
///   • `bounced`    — user confirmed the cheque bounced and the lifecycle
///                    service restored the obligation where applicable.
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
  TextColumn get status => text().withDefault(const Constant('pending'))();

  /// Set when status transitions away from `pending`.
  DateTimeColumn get confirmedAt => dateTime().nullable()();

  @ReferenceName('chequeConfirmedBy')
  IntColumn get confirmedBy => integer().nullable().references(
    Users,
    #id,
    onDelete: KeyAction.setNull,
  )();

  /// Free-text note (e.g. "deposited at branch", "represented Friday").
  TextColumn get note => text().nullable()();

  /// Required when status = `bounced`. Free-text (NSF, stop-pay, etc.).
  TextColumn get bounceReason => text().nullable()();

  /// **Phase 15.0 — Cheque lifecycle JE wiring.**
  ///
  /// When status transitions `pending → cleared` for an invoice source, the
  /// [`ChequeLifecycleService`] calls
  /// `SaleRepository.recordPayment` / `PurchaseRepository.recordPayment`
  /// for the outstanding `(total − paid)` amount. The resulting
  /// `sale_payments.id` / `purchase_payments.id` is stamped here so that
  /// a later `cleared → bounced` (or `cleared → cancelled`) transition
  /// can deterministically reverse the matching payment row via the
  /// existing `deletePayment` SoT (which itself voids the JE and restores
  /// the party balance).
  ///
  /// For return sources this field stores the return-settlement journal id;
  /// the party obligation is not settled until the cheque actually clears.
  /// It remains nullable while the physical cheque is pending.
  ///
  /// The polymorphic interpretation (purchase payment, sale payment, or
  /// return settlement journal) is driven by [`sourceTable`]. See
  /// `docs/ACCOUNTING_INTEGRITY_GUIDELINES.md` §Phase-15.
  IntColumn get clearedPaymentId => integer().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  /// Natural key — at most one confirmation row per cheque-bearing
  /// document. Upsert on (source_table, source_id) is the only write path.
  @override
  List<Set<Column>> get uniqueKeys => [
    {sourceTable, sourceId},
  ];
}

/// The accounting value recognized when a standalone party cheque clears.
///
/// This is a sub-ledger only: the cheque clearance has already posted the
/// customer/supplier balance and bank journals. Applying this value to an
/// invoice later is settlement matching and must not post cash or GL again.
@DataClassName('PartyAccountPayment')
class PartyAccountPayments extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get chequeInstrumentId => integer().references(
    ChequeInstruments,
    #id,
    onDelete: KeyAction.restrict,
  )();
  TextColumn get partyType => text()();
  IntColumn get partyId => integer()();
  TextColumn get direction => text()();
  IntColumn get amountCents => integer().map(const MoneyConverter())();
  IntColumn get appliedCents =>
      integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  IntColumn get currencyId =>
      integer().references(Currencies, #id, onDelete: KeyAction.restrict)();
  TextColumn get status => text().withDefault(const Constant('open'))();

  /// Customer/supplier transaction written when the cheque was cleared.
  /// This is deliberately polymorphic and therefore has no SQL foreign key.
  IntColumn get settlementTransactionId => integer().nullable()();
  DateTimeColumn get recognizedAt => dateTime()();
  DateTimeColumn get reversedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<Set<Column>> get uniqueKeys => [
    {chequeInstrumentId},
  ];

  @override
  List<String> get customConstraints => [
    "CHECK (party_type IN ('customer','supplier'))",
    "CHECK (direction IN ('incoming','outgoing'))",
    'CHECK (amount_cents > 0)',
    'CHECK (applied_cents >= 0 AND applied_cents <= amount_cents)',
    "CHECK (status IN ('open','partially_applied','applied','reversed'))",
  ];
}

/// One reversible allocation of a cleared account cheque to an invoice.
@DataClassName('PartyAccountPaymentApplication')
class PartyAccountPaymentApplications extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get accountPaymentId => integer().references(
    PartyAccountPayments,
    #id,
    onDelete: KeyAction.restrict,
  )();
  TextColumn get documentType => text()();
  IntColumn get documentId => integer()();
  IntColumn get amountCents => integer().map(const MoneyConverter())();
  IntColumn get salePaymentId => integer().nullable().references(
    SalePayments,
    #id,
    onDelete: KeyAction.setNull,
  )();
  IntColumn get purchasePaymentId => integer().nullable().references(
    PurchasePayments,
    #id,
    onDelete: KeyAction.setNull,
  )();
  TextColumn get status => text().withDefault(const Constant('active'))();
  DateTimeColumn get appliedAt => dateTime()();
  DateTimeColumn get reversedAt => dateTime().nullable()();
  @ReferenceName('accountPaymentApplicationCreatedBy')
  IntColumn get createdBy => integer().nullable().references(
    Users,
    #id,
    onDelete: KeyAction.setNull,
  )();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<String> get customConstraints => [
    "CHECK (document_type IN ('sale','purchase'))",
    'CHECK (amount_cents > 0)',
    "CHECK (status IN ('active','reversed'))",
    "CHECK ((document_type = 'sale' AND purchase_payment_id IS NULL) OR (document_type = 'purchase' AND sale_payment_id IS NULL))",
  ];
}
