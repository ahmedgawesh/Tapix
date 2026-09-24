import 'dart:developer' as developer;

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';

import '../../database/app_database.dart';
import '../../../features/accounting/data/repositories/accounting_repository.dart';
import '../../../features/accounting/domain/exceptions/accounting_exception.dart';
import '../../../features/accounting/domain/models/journal_entry_data.dart';

// ── Decimal ↔ int helpers ─────────────────────────────────────────────
// The money columns use `MoneyConverter` which makes the Dart type `Decimal`.
// The service API operates in integer cents — single source of truth for
// the arithmetic. These two helpers keep the Decimal plumbing at the edges.
Decimal _toD(int cents) => Decimal.fromInt(cents);
int _toI(Decimal d) => d.toBigInt().toInt();

/// Thrown when an apply operation would exceed the note's open balance.
class CreditNoteInsufficientBalanceException extends AccountingException {
  final int creditNoteId;
  final int requestedCents;
  final int availableCents;

  CreditNoteInsufficientBalanceException({
    required this.creditNoteId,
    required this.requestedCents,
    required this.availableCents,
  }) : super(
         'Customer credit note #$creditNoteId: requested $requestedCents '
         'cents but only $availableCents cents available.',
       );
}

/// **Single source of truth** for the customer credit-note sub-ledger.
///
/// Reconciliation contract (must always hold):
///   Σ(`customer_credit_notes.balance_cents` WHERE status ∈ {'open',
///   'partially_applied'}) == GL balance of 2400 Customer Credit Liability.
///
/// Lifecycle:
///
///   ┌──────────┐    issue()     ┌────────────────┐   apply(partial)
///   │ (absent) │ ─────────────► │      open      │ ──────────────────┐
///   └──────────┘                └────────────────┘                   │
///                                      │                             ▼
///                                      │                   ┌────────────────┐
///                                      │ apply(full)       │ partially_     │
///                                      │ ─────────────────►│  applied       │
///                                      │                   └────────────────┘
///                                      ▼                             │
///                               ┌────────────────┐                   │
///                               │ fully_applied  │ ◄─────────────────┘
///                               └────────────────┘
///
///   voidNote() from `open` only → status='voided' (and a reversing JE
///   posts Dr 2400 / Cr `<original settlement account>`).
///
/// JE topology:
///   • Issue  (triggered upstream by `ReturnPostingService` when a sale
///             return routes its settlement to 2400):
///       Dr Sales Return Adj (5700)   netCents
///       Dr VAT Payable (2100)        taxCents
///         Cr 2400 Customer Credit Liab totalCents
///     The issuing JE id is stored on the credit-note row
///     (`issue_journal_entry_id`) for audit.
///   • Apply  (when the customer redeems credit on a future sale):
///       Dr 2400 Customer Credit Liab amount
///         Cr 1100 Accounts Receivable amount
///     The application JE id is stored on the application row.
class CustomerCreditNoteService {
  final AppDatabase _db;
  final AccountingRepository _accountingRepo;

  CustomerCreditNoteService({
    required AppDatabase db,
    required AccountingRepository accountingRepo,
  }) : _db = db,
       _accountingRepo = accountingRepo;

  // ── Account codes (mirror JournalRepositoryImpl.seedDefaultAccounts) ─
  static const String _customerCreditLiabilityCode = '2400';
  static const String _arCode = '1100';

  /// Generate `'CCN-YYYYMM-NNNN'` for the current month.
  Future<String> _generateNoteNumber() async {
    final now = DateTime.now();
    final prefix = 'CCN-${now.year}${now.month.toString().padLeft(2, '0')}';
    final last =
        await (_db.select(_db.customerCreditNotes)
              ..where((n) => n.noteNumber.like('$prefix%'))
              ..orderBy([(n) => OrderingTerm.desc(n.noteNumber)])
              ..limit(1))
            .getSingleOrNull();
    int next = 1;
    if (last != null) {
      final tail = int.tryParse(last.noteNumber.split('-').last) ?? 0;
      next = tail + 1;
    }
    return '$prefix-${next.toString().padLeft(4, '0')}';
  }

  /// Issue a new credit note for [customerId] tied to [sourceTable]/[sourceId]
  /// (typically a `sale_return_adjustments` row whose settlement was routed
  /// to 2400 by `ReturnJournalPolicy`). Returns the created credit-note id.
  ///
  /// **Does NOT create a journal entry** — the JE is created by the
  /// ReturnPostingService pipeline using the policy. This method stores
  /// the `issueJournalEntryId` supplied by the caller so the sub-ledger
  /// row is linked to the GL.
  Future<int> issueForReturn({
    required int customerId,
    required int currencyId,
    required int amountCents,
    required String sourceTable,
    required int sourceId,
    required int issueJournalEntryId,
    DateTime? issuedAt,
    String? notes,
  }) async {
    if (amountCents <= 0) {
      throw AccountingException(
        'CustomerCreditNoteService.issueForReturn: amountCents must be > 0 '
        '(got $amountCents).',
      );
    }

    // Idempotency: if a note has already been issued for this
    // (sourceTable, sourceId) pair, return the existing id. This makes
    // the service safe to call from a retried ReturnPostingService.post.
    final existing =
        await (_db.select(_db.customerCreditNotes)
              ..where(
                (n) =>
                    n.sourceTable.equals(sourceTable) &
                    n.sourceId.equals(sourceId) &
                    n.status.isNotValue('voided'),
              )
              ..limit(1))
            .getSingleOrNull();
    if (existing != null) {
      developer.log(
        'CustomerCreditNoteService: idempotent hit — '
        'existing note #${existing.id} for $sourceTable#$sourceId',
        name: 'CustomerCreditNoteService',
      );
      return existing.id;
    }

    final now = DateTime.now();
    final noteNumber = await _generateNoteNumber();
    final id = await _db
        .into(_db.customerCreditNotes)
        .insert(
          CustomerCreditNotesCompanion.insert(
            noteNumber: noteNumber,
            customerId: customerId,
            currencyId: currencyId,
            originalAmountCents: _toD(amountCents),
            balanceCents: _toD(amountCents),
            status: const Value('open'),
            sourceTable: sourceTable,
            sourceId: sourceId,
            issueJournalEntryId: Value(issueJournalEntryId),
            issuedAt: Value(issuedAt ?? now),
            notes: Value(notes),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
    developer.log(
      'CustomerCreditNoteService: issued $noteNumber (#$id) for '
      'customer=$customerId amount=$amountCents '
      'source=$sourceTable#$sourceId je=$issueJournalEntryId',
      name: 'CustomerCreditNoteService',
    );
    return id;
  }

  /// Apply [amountCents] of credit-note [creditNoteId] against [saleId].
  /// Posts `Dr 2400 / Cr 1100` JE and records the application row.
  ///
  /// Throws [CreditNoteInsufficientBalanceException] if the amount
  /// exceeds the open balance.
  Future<int> apply({
    required int creditNoteId,
    required int? saleId,
    required int amountCents,
    int? userId,
    DateTime? appliedAt,
    String? notes,
  }) async {
    if (amountCents <= 0) {
      throw AccountingException(
        'CustomerCreditNoteService.apply: amountCents must be > 0.',
      );
    }

    return _db.transaction(() async {
      final note = await (_db.select(
        _db.customerCreditNotes,
      )..where((n) => n.id.equals(creditNoteId))).getSingleOrNull();
      if (note == null) {
        throw AccountingException(
          'CustomerCreditNoteService.apply: credit note #$creditNoteId not found.',
        );
      }
      if (note.status == 'voided') {
        throw AccountingException(
          'CustomerCreditNoteService.apply: credit note #$creditNoteId is voided.',
        );
      }
      final balanceCentsInt = _toI(note.balanceCents);
      if (balanceCentsInt < amountCents) {
        throw CreditNoteInsufficientBalanceException(
          creditNoteId: creditNoteId,
          requestedCents: amountCents,
          availableCents: balanceCentsInt,
        );
      }

      // Post the application JE: Dr 2400 / Cr 1100.
      final liabId = await _accountingRepo.getAccountByCode(
        _customerCreditLiabilityCode,
      );
      final arId = await _accountingRepo.getAccountByCode(_arCode);
      if (liabId == null || arId == null) {
        throw AccountingException(
          'CustomerCreditNoteService.apply: chart of accounts missing '
          '2400 or 1100.',
        );
      }

      final jeId = await _accountingRepo.createJournalEntry(
        entryData: JournalEntryData.simple(
          description:
              'Credit Note ${note.noteNumber} applied'
              '${saleId != null ? " to Sale #$saleId" : ""}',
          debitAccountId: liabId.id,
          creditAccountId: arId.id,
          amountCents: amountCents,
          currencyId: note.currencyId,
          entryType: 'credit_note_application',
          sourceTable: 'customer_credit_note_applications',
          sourceId: 0, // filled after insert below
          autoPost: true,
        ),
        userId: userId,
      );

      final now = DateTime.now();
      final appId = await _db
          .into(_db.customerCreditNoteApplications)
          .insert(
            CustomerCreditNoteApplicationsCompanion.insert(
              creditNoteId: creditNoteId,
              saleId: Value(saleId),
              amountCents: _toD(amountCents),
              journalEntryId: Value(jeId),
              appliedAt: Value(appliedAt ?? now),
              notes: Value(notes),
              createdAt: Value(now),
            ),
          );

      final newBalance = balanceCentsInt - amountCents;
      final newStatus = newBalance == 0 ? 'fully_applied' : 'partially_applied';
      await (_db.update(
        _db.customerCreditNotes,
      )..where((n) => n.id.equals(creditNoteId))).write(
        CustomerCreditNotesCompanion(
          balanceCents: Value(_toD(newBalance)),
          status: Value(newStatus),
          updatedAt: Value(now),
        ),
      );

      developer.log(
        'CustomerCreditNoteService: applied $amountCents from '
        '${note.noteNumber} → sale=$saleId (balance $newBalance, '
        'status=$newStatus) je=$jeId',
        name: 'CustomerCreditNoteService',
      );
      return appId;
    });
  }

  /// Void an issued credit note. Only allowed when no applications exist.
  /// Posts a reversing JE `Dr 2400 / Cr 5700` (mirror of issuance).
  Future<void> voidNote({
    required int creditNoteId,
    int? userId,
    String? reason,
  }) async {
    await _db.transaction(() async {
      final note = await (_db.select(
        _db.customerCreditNotes,
      )..where((n) => n.id.equals(creditNoteId))).getSingleOrNull();
      if (note == null) {
        throw AccountingException('Credit note #$creditNoteId not found.');
      }
      if (note.status == 'voided') return; // idempotent
      final apps =
          await (_db.select(_db.customerCreditNoteApplications)
                ..where((a) => a.creditNoteId.equals(creditNoteId))
                ..limit(1))
              .getSingleOrNull();
      if (apps != null) {
        throw AccountingException(
          'Credit note #$creditNoteId has applications; cannot void.',
        );
      }

      final liab = await _accountingRepo.getAccountByCode(
        _customerCreditLiabilityCode,
      );
      // Use 5700 Sales Return Adj as the reversing debit counterpart,
      // because issuing posted Dr 5700 / Cr 2400 net of the return; void
      // should unwind that. We skip the VAT leg intentionally — caller
      // should void the underlying return (which reverses the full JE).
      final salesRA = await _accountingRepo.getAccountByCode('5700');
      if (liab == null || salesRA == null) {
        throw AccountingException('Chart of accounts missing 2400 or 5700.');
      }

      await _accountingRepo.createJournalEntry(
        entryData: JournalEntryData.simple(
          description:
              'Void Credit Note ${note.noteNumber}${reason != null ? " — $reason" : ""}',
          debitAccountId: liab.id,
          creditAccountId: salesRA.id,
          amountCents: _toI(note.balanceCents),
          currencyId: note.currencyId,
          entryType: 'credit_note_void',
          sourceTable: 'customer_credit_notes',
          sourceId: creditNoteId,
          autoPost: true,
        ),
        userId: userId,
      );

      final now = DateTime.now();
      await (_db.update(
        _db.customerCreditNotes,
      )..where((n) => n.id.equals(creditNoteId))).write(
        CustomerCreditNotesCompanion(
          status: const Value('voided'),
          balanceCents: Value(Decimal.zero),
          updatedAt: Value(now),
          notes: Value(reason ?? note.notes),
        ),
      );
      developer.log(
        'CustomerCreditNoteService: voided ${note.noteNumber} '
        '(reason="${reason ?? ""}") by user=$userId',
        name: 'CustomerCreditNoteService',
      );
    });
  }

  /// Open balance available for apply operations for [customerId] in
  /// the given [currencyId]. Used by the Apply-Credit UI.
  Future<int> getOpenBalance({
    required int customerId,
    required int currencyId,
  }) async {
    final rows =
        await (_db.select(_db.customerCreditNotes)..where(
              (n) =>
                  n.customerId.equals(customerId) &
                  n.currencyId.equals(currencyId) &
                  n.status.isNotValue('voided') &
                  n.status.isNotValue('fully_applied'),
            ))
            .get();
    return rows.fold<int>(0, (sum, r) => sum + _toI(r.balanceCents));
  }

  /// List open / partially-applied notes for a customer — oldest first so
  /// applications follow FIFO (standard accounting practice).
  Future<List<CustomerCreditNote>> listOpenForCustomer({
    required int customerId,
    required int currencyId,
  }) {
    return (_db.select(_db.customerCreditNotes)
          ..where(
            (n) =>
                n.customerId.equals(customerId) &
                n.currencyId.equals(currencyId) &
                n.status.isIn(const ['open', 'partially_applied']),
          )
          ..orderBy([(n) => OrderingTerm.asc(n.issuedAt)]))
        .get();
  }

  /// Reactively watch every non-voided credit note for [customerId]
  /// (newest first). Powers the customer-profile "Store Credit" section so
  /// adjustment-return credit notes — which settle to 2400 and therefore
  /// never touch `customer_transactions` — are still visible to the user.
  Stream<List<CustomerCreditNote>> watchForCustomer(int customerId) {
    return (_db.select(_db.customerCreditNotes)
          ..where(
            (n) =>
                n.customerId.equals(customerId) & n.status.isNotValue('voided'),
          )
          ..orderBy([(n) => OrderingTerm.desc(n.issuedAt)]))
        .watch();
  }

  /// Fetch a single note (for UI / audit).
  Future<CustomerCreditNote?> getById(int id) {
    return (_db.select(
      _db.customerCreditNotes,
    )..where((n) => n.id.equals(id))).getSingleOrNull();
  }

  /// Fetch the note (if any) originally issued for the given return row.
  /// Used by void-return flows to automatically clean up the note.
  Future<CustomerCreditNote?> findBySource({
    required String sourceTable,
    required int sourceId,
  }) {
    return (_db.select(_db.customerCreditNotes)..where(
          (n) =>
              n.sourceTable.equals(sourceTable) &
              n.sourceId.equals(sourceId) &
              n.status.isNotValue('voided'),
        ))
        .getSingleOrNull();
  }
}
