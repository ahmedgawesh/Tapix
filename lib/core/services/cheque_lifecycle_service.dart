import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' show Value, Variable;

import '../database/app_database.dart';
import '../database/daos/cheque_confirmation_dao.dart';
import '../database/daos/cheque_instrument_dao.dart';
import '../payments/checkout_settlement.dart';
import '../payments/return_settlement_service.dart';
import '../../features/purchases/domain/repositories/purchase_repository.dart';
import '../../features/sales/domain/repositories/sale_repository.dart';
import 'audit_log_service.dart';
import 'balance_service.dart';
import 'document_number_service.dart';
import 'journal_entry_service.dart';
import 'party_account_payment_service.dart';

/// Outcome of a [`ChequeLifecycleService`] transition. Useful for the UI
/// to surface "settled $X" / "reversed $Y" snackbars.
class ChequeTransitionResult {
  /// New status persisted on `cheque_confirmations`.
  final String status;

  /// Outstanding amount (cents) that was settled by this transition.
  /// Non-null when clearing created a real invoice payment or return
  /// settlement.
  final int? settledAmountCents;

  /// Amount (cents) reversed by this transition. Non-null only on
  /// `cleared → bounced` or `cleared → cancelled` paths that found a
  /// previously-stamped `cleared_payment_id`.
  final int? reversedAmountCents;

  /// Settlement record created by this transition. For invoices this is a
  /// payment id; for returns it is the settlement journal id.
  final int? createdPaymentId;

  const ChequeTransitionResult({
    required this.status,
    this.settledAmountCents,
    this.reversedAmountCents,
    this.createdPaymentId,
  });
}

class ChequeResolutionResult {
  final String resolutionType;
  final int? journalEntryId;
  final int? replacementChequeId;

  const ChequeResolutionResult({
    required this.resolutionType,
    this.journalEntryId,
    this.replacementChequeId,
  });
}

/// Thrown when a transition is requested for an unknown / soft-deleted
/// source document. Lets the dashboard show a sane snackbar instead of
/// crashing.
class ChequeSourceNotFoundException implements Exception {
  final String sourceTable;
  final int sourceId;
  ChequeSourceNotFoundException(this.sourceTable, this.sourceId);

  @override
  String toString() =>
      'ChequeSourceNotFoundException: $sourceTable#$sourceId not found';
}

/// Single source of truth for physical-cheque lifecycle transitions.
///
/// Invoice and return cheques are recognized in 1020 (Cheques in Hand) or
/// 2020 (Cheques Issued) when received/issued; clearance then moves the value
/// to/from Bank 1010.
/// A bounced incoming cheque is reclassified to 1030 (Dishonoured Cheques)
/// while cancellation and failed outgoing cheques restore the original
/// obligation. This keeps a collectible bounced cheque visible as an asset
/// without treating it as cash in hand or bank.
/// Older unstamped instruments are recognized defensively on clearance.
/// Every transition, its accounting entry, payment link, party sub-ledger
/// movement and audit record is committed in one Drift transaction.
class ChequeLifecycleService {
  final AppDatabase _db;
  final ChequeConfirmationDao _confirmDao;
  final ChequeInstrumentDao _instrumentDao;
  final PurchaseRepository _purchaseRepo;
  final SaleRepository _saleRepo;
  final JournalEntryService _journalService;
  final AuditLogService _audit;
  final PartyAccountPaymentService _accountPayments;

  ChequeLifecycleService({
    required AppDatabase db,
    required ChequeConfirmationDao confirmationDao,
    required ChequeInstrumentDao instrumentDao,
    required PurchaseRepository purchaseRepository,
    required SaleRepository saleRepository,
    required JournalEntryService journalEntryService,
    required AuditLogService auditLogService,
    PartyAccountPaymentService? accountPaymentService,
  }) : _db = db,
       _confirmDao = confirmationDao,
       _instrumentDao = instrumentDao,
       _purchaseRepo = purchaseRepository,
       _saleRepo = saleRepository,
       _journalService = journalEntryService,
       _audit = auditLogService,
       _accountPayments =
           accountPaymentService ??
           PartyAccountPaymentService(db: db, auditLogService: auditLogService);
  // ── public API ────────────────────────────────────────────────────────

  Future<ChequeTransitionResult> markDeposited({
    required String sourceTable,
    required int sourceId,
    int? instrumentId,
    int? userId,
  }) {
    return _db.transaction(() async {
      final c = await _resolveInstrument(
        sourceTable,
        sourceId,
        userId,
        instrumentId,
      );
      if (c.direction != ChequeDirectionValue.incoming) {
        throw StateError('Only incoming cheques can be deposited');
      }
      if (ChequeInstrumentStatus.terminal.contains(c.status)) {
        throw StateError('A resolved cheque cannot be deposited');
      }
      if (c.status != ChequeInstrumentStatus.deposited) {
        await _instrumentDao.writeLifecycle(
          id: c.id,
          status: ChequeInstrumentStatus.deposited,
          userId: userId,
        );
        await _audit.log(
          entityType: 'cheque_instrument',
          entityId: c.id,
          action: 'deposit',
          oldValue: {'status': c.status},
          newValue: {'status': ChequeInstrumentStatus.deposited},
          userId: userId,
        );
      }
      return const ChequeTransitionResult(
        status: ChequeInstrumentStatus.deposited,
      );
    });
  }

  Future<ChequeTransitionResult> markCleared({
    required String sourceTable,
    required int sourceId,
    int? instrumentId,
    int? userId,
    String? note,
  }) {
    return _db.transaction(() async {
      final c = await _resolveInstrument(
        sourceTable,
        sourceId,
        userId,
        instrumentId,
      );
      if (c.status == ChequeInstrumentStatus.cleared) {
        return ChequeTransitionResult(
          status: ChequeConfirmationStatus.cleared,
          createdPaymentId: c.settlementPaymentId,
        );
      }
      if (ChequeInstrumentStatus.terminal.contains(c.status)) {
        throw StateError('A resolved cheque cannot be cleared');
      }
      var paymentId = c.settlementPaymentId;
      int? settled;
      if (_isSettleable(sourceTable) &&
          paymentId == null &&
          !c.legacyDirectBank) {
        // The physical cheque is settled for its face value. Do not cap it
        // to the document's current outstanding balance: another payment
        // may have been recorded after accepting the cheque, in which case
        // the excess correctly becomes a customer/supplier credit.
        final settlementAmount = c.amountCents.toBigInt().toInt();
        paymentId = await _recordSettlement(
          sourceTable,
          sourceId,
          settlementAmount,
          c,
          note,
          userId,
        );
        settled = settlementAmount;
      }
      int? journalId;
      if (!c.legacyDirectBank) {
        journalId = await _journalService.recordChequeClearanceJournalEntry(
          chequeId: c.id,
          incoming: c.direction == ChequeDirectionValue.incoming,
          amountCents: c.amountCents.toBigInt().toInt(),
          currencyId: c.currencyId,
          userId: userId,
        );
      }
      await _instrumentDao.writeLifecycle(
        id: c.id,
        status: ChequeInstrumentStatus.cleared,
        settlementPaymentId: paymentId,
        clearanceJournalEntryId: journalId,
        userId: userId,
      );
      if (!_isAccountSource(sourceTable)) {
        await _confirmDao.confirm(
          sourceTable: sourceTable,
          sourceId: sourceId,
          status: ChequeConfirmationStatus.cleared,
          note: note,
          userId: userId,
          clearedPaymentId: paymentId,
        );
      }
      await _audit.log(
        entityType: 'cheque_instrument',
        entityId: c.id,
        action: 'clear',
        oldValue: {'status': c.status},
        newValue: {
          'status': ChequeInstrumentStatus.cleared,
          'paymentId': paymentId,
          'journalId': journalId,
        },
        userId: userId,
        severity: AuditSeverity.critical,
      );
      return ChequeTransitionResult(
        status: ChequeConfirmationStatus.cleared,
        settledAmountCents: settled,
        createdPaymentId: paymentId,
      );
    });
  }

  Future<ChequeTransitionResult> markBounced({
    required String sourceTable,
    required int sourceId,
    required String bounceReason,
    int? instrumentId,
    int? userId,
  }) {
    if (bounceReason.trim().isEmpty) {
      throw ArgumentError('bounceReason is required');
    }
    return _markFailed(
      sourceTable,
      sourceId,
      false,
      bounceReason.trim(),
      userId,
      instrumentId,
    );
  }

  Future<ChequeTransitionResult> markCancelled({
    required String sourceTable,
    required int sourceId,
    int? instrumentId,
    int? userId,
  }) => _markFailed(
    sourceTable,
    sourceId,
    true,
    'Cheque cancelled by user',
    userId,
    instrumentId,
  );

  /// Resolves one bounced cheque and records the selected business outcome.
  /// Incoming cheques close account 1030. Outgoing cheques use the existing
  /// supplier-payment / customer-return settlement paths because they never
  /// belong in 1030.
  Future<ChequeResolutionResult> resolveBounced({
    required int instrumentId,
    required String resolutionType,
    String? note,
    String? replacementChequeNumber,
    String? replacementBankName,
    DateTime? replacementIssueDate,
    DateTime? replacementDueDate,
    int? userId,
  }) {
    if (!ChequeResolutionType.all.contains(resolutionType)) {
      throw ArgumentError.value(resolutionType, 'resolutionType');
    }
    return _db.transaction(() async {
      final cheque = await _instrumentDao.getById(instrumentId);
      if (cheque == null) throw StateError('cheque_not_found');
      if (cheque.status != ChequeInstrumentStatus.bounced) {
        throw StateError('cheque_not_bounced');
      }
      if (cheque.resolvedAt != null || cheque.resolutionType != null) {
        throw StateError('cheque_already_resolved');
      }
      if (cheque.partyId == null || cheque.partyType == null) {
        throw StateError('cheque_party_required');
      }
      if (resolutionType == ChequeResolutionType.replacement) {
        if (replacementChequeNumber?.trim().isEmpty != false ||
            replacementDueDate == null) {
          throw ArgumentError('replacement_cheque_details_required');
        }
      }
      if (cheque.direction == ChequeDirectionValue.outgoing &&
          resolutionType == ChequeResolutionType.writeOff) {
        throw StateError('outgoing_cheque_cannot_be_written_off');
      }

      final result = cheque.direction == ChequeDirectionValue.incoming
          ? await _resolveIncomingDishonour(
              cheque: cheque,
              resolutionType: resolutionType,
              note: note,
              replacementChequeNumber: replacementChequeNumber,
              replacementBankName: replacementBankName,
              replacementIssueDate: replacementIssueDate,
              replacementDueDate: replacementDueDate,
              userId: userId,
            )
          : await _resolveOutgoingDishonour(
              cheque: cheque,
              resolutionType: resolutionType,
              note: note,
              replacementChequeNumber: replacementChequeNumber,
              replacementBankName: replacementBankName,
              replacementIssueDate: replacementIssueDate,
              replacementDueDate: replacementDueDate,
              userId: userId,
            );

      await _instrumentDao.writeResolution(
        id: cheque.id,
        resolutionType: resolutionType,
        resolutionJournalEntryId: result.journalEntryId,
        replacementChequeId: result.replacementChequeId,
        note: note,
        userId: userId,
      );
      await _audit.log(
        entityType: 'cheque_instrument',
        entityId: cheque.id,
        action: 'resolve_dishonoured',
        oldValue: {
          'status': cheque.status,
          'resolutionType': cheque.resolutionType,
        },
        newValue: {
          'resolutionType': resolutionType,
          'journalEntryId': result.journalEntryId,
          'replacementChequeId': result.replacementChequeId,
          'note': note,
        },
        userId: userId,
        severity: AuditSeverity.critical,
      );
      return result;
    });
  }

  Future<ChequeResolutionResult> _resolveIncomingDishonour({
    required ChequeInstrument cheque,
    required String resolutionType,
    required String? note,
    required String? replacementChequeNumber,
    required String? replacementBankName,
    required DateTime? replacementIssueDate,
    required DateTime? replacementDueDate,
    required int? userId,
  }) async {
    final amount = cheque.amountCents.toBigInt().toInt();
    final balance = await _activeDishonouredBalance(cheque.id);
    if (balance != amount) {
      throw StateError('cheque_dishonoured_balance_mismatch');
    }
    final debitAccount = switch (resolutionType) {
      ChequeResolutionType.cash => '1000',
      ChequeResolutionType.bank || ChequeResolutionType.card => '1010',
      ChequeResolutionType.replacement =>
        cheque.partyType == 'supplier' ? '2000' : '1100',
      ChequeResolutionType.credit =>
        cheque.partyType == 'customer' ? '1100' : '2000',
      ChequeResolutionType.writeOff => '6200',
      _ => throw ArgumentError.value(resolutionType, 'resolutionType'),
    };
    final journalId = await _journalService
        .recordDishonouredChequeResolutionJournalEntry(
          chequeId: cheque.id,
          amountCents: amount,
          currencyId: cheque.currencyId,
          debitAccountCode: debitAccount,
          resolutionType: resolutionType,
          note: note,
          userId: userId,
        );

    int? replacementId;
    if (resolutionType == ChequeResolutionType.replacement) {
      replacementId = await _instrumentDao.create(
        direction: ChequeDirectionValue.incoming,
        sourceTable: cheque.sourceTable,
        sourceId: cheque.sourceId,
        amountCents: amount,
        currencyId: cheque.currencyId,
        dueDate: replacementDueDate!,
        issueDate: replacementIssueDate ?? DateTime.now(),
        partyType: cheque.partyType,
        partyId: cheque.partyId,
        chequeNumber: replacementChequeNumber,
        bankName: replacementBankName,
        drawerName: cheque.drawerName,
        note: note,
        userId: userId,
      );
    }

    if (resolutionType != ChequeResolutionType.credit &&
        resolutionType != ChequeResolutionType.replacement) {
      final transactionId = await _closeIncomingDishonourPartyBalance(
        cheque: cheque,
        resolutionType: resolutionType,
        note: note,
      );
      if (_isAccountSource(cheque.sourceTable)) {
        await _accountPayments.recognizeClearedCheque(
          cheque: cheque,
          settlementTransactionId: transactionId,
        );
      }
    }
    return ChequeResolutionResult(
      resolutionType: resolutionType,
      journalEntryId: journalId,
      replacementChequeId: replacementId,
    );
  }

  Future<ChequeResolutionResult> _resolveOutgoingDishonour({
    required ChequeInstrument cheque,
    required String resolutionType,
    required String? note,
    required String? replacementChequeNumber,
    required String? replacementBankName,
    required DateTime? replacementIssueDate,
    required DateTime? replacementDueDate,
    required int? userId,
  }) async {
    if (resolutionType == ChequeResolutionType.credit) {
      return ChequeResolutionResult(resolutionType: resolutionType);
    }
    final amount = cheque.amountCents.toBigInt().toInt();
    final paymentMethod = switch (resolutionType) {
      ChequeResolutionType.cash => 'cash',
      ChequeResolutionType.bank => 'bank_transfer',
      ChequeResolutionType.card => 'card',
      ChequeResolutionType.replacement => 'cheque',
      _ => throw ArgumentError.value(resolutionType, 'resolutionType'),
    };

    int? replacementId;
    if (_isAccountSource(cheque.sourceTable)) {
      if (resolutionType == ChequeResolutionType.replacement) {
        replacementId = await _instrumentDao.create(
          direction: ChequeDirectionValue.outgoing,
          sourceTable: cheque.sourceTable,
          sourceId: cheque.sourceId,
          amountCents: amount,
          currencyId: cheque.currencyId,
          dueDate: replacementDueDate!,
          issueDate: replacementIssueDate ?? DateTime.now(),
          partyType: cheque.partyType,
          partyId: cheque.partyId,
          chequeNumber: replacementChequeNumber,
          bankName: replacementBankName,
          drawerName: cheque.drawerName,
          note: note,
          userId: userId,
        );
        return ChequeResolutionResult(
          resolutionType: resolutionType,
          replacementChequeId: replacementId,
        );
      }
      final settlement = await _recordAccountPartySettlement(
        cheque: cheque,
        amount: amount,
        note: note,
        userId: userId,
        throughChequeClearing: false,
        paymentMethod: paymentMethod,
      );
      return ChequeResolutionResult(
        resolutionType: resolutionType,
        journalEntryId: settlement.journalEntryId,
      );
    }
    if (cheque.sourceTable == ChequeSourceTables.purchase) {
      if (resolutionType == ChequeResolutionType.replacement) {
        replacementId = await _instrumentDao.create(
          direction: ChequeDirectionValue.outgoing,
          sourceTable: cheque.sourceTable,
          sourceId: cheque.sourceId,
          amountCents: amount,
          currencyId: cheque.currencyId,
          dueDate: replacementDueDate!,
          issueDate: replacementIssueDate ?? DateTime.now(),
          partyType: cheque.partyType,
          partyId: cheque.partyId,
          chequeNumber: replacementChequeNumber,
          bankName: replacementBankName,
          drawerName: cheque.drawerName,
          note: note,
          userId: userId,
        );
        return ChequeResolutionResult(
          resolutionType: resolutionType,
          replacementChequeId: replacementId,
        );
      }
      await _purchaseRepo.recordPayment(
        purchaseId: cheque.sourceId,
        currencyId: cheque.currencyId,
        amountCents: Decimal.fromInt(amount),
        paymentMethod: paymentMethod,
        reference: replacementChequeNumber,
        notes: note ?? 'Bounced cheque #${cheque.id} resolution',
        paymentDate: replacementIssueDate ?? DateTime.now(),
      );
      return ChequeResolutionResult(
        resolutionType: resolutionType,
        replacementChequeId: replacementId,
      );
    }

    if (cheque.sourceTable == ChequeSourceTables.saleReturn ||
        cheque.sourceTable == ChequeSourceTables.saleReturnAdjustment) {
      await ReturnSettlementService.apply(
        db: _db,
        journalService: _journalService,
        side: ReturnSettlementSide.sale,
        sourceTable: cheque.sourceTable,
        sourceId: cheque.sourceId,
        partyId: cheque.partyId!,
        totalCents: amount,
        currencyId: cheque.currencyId,
        allocations: [
          CheckoutPaymentAllocation(
            method: paymentMethod,
            amountCents: amount,
            reference: replacementChequeNumber,
            bankName: replacementBankName,
            issueDate: replacementIssueDate ?? DateTime.now(),
            dueDate: resolutionType == ChequeResolutionType.replacement
                ? replacementDueDate
                : null,
            note: note,
          ),
        ],
        documentDate: replacementIssueDate ?? DateTime.now(),
        userId: userId,
      );
      if (resolutionType == ChequeResolutionType.replacement) {
        final row = await _db
            .customSelect(
              'SELECT id FROM cheque_instruments '
              'WHERE source_table = ? AND source_id = ? AND id <> ? '
              'ORDER BY id DESC LIMIT 1',
              variables: [
                Variable.withString(cheque.sourceTable),
                Variable.withInt(cheque.sourceId),
                Variable.withInt(cheque.id),
              ],
            )
            .getSingle();
        replacementId = row.read<int>('id');
      }
      return ChequeResolutionResult(
        resolutionType: resolutionType,
        replacementChequeId: replacementId,
      );
    }
    throw StateError('cheque_resolution_source_unsupported');
  }

  Future<int> _activeDishonouredBalance(int chequeId) async {
    final row = await _db
        .customSelect(
          'SELECT COALESCE(SUM(jel.debit_cents - jel.credit_cents), 0) AS net '
          'FROM journal_entries je '
          'JOIN journal_entry_lines jel ON jel.journal_entry_id = je.id '
          'JOIN accounts a ON a.id = jel.account_id '
          "WHERE je.source_table = 'cheque_instruments' "
          'AND je.source_id = ? AND je.status = \'posted\' '
          "AND a.account_code = '1030'",
          variables: [Variable.withInt(chequeId)],
        )
        .getSingle();
    return row.read<int>('net');
  }

  Future<int> _closeIncomingDishonourPartyBalance({
    required ChequeInstrument cheque,
    required String resolutionType,
    required String? note,
  }) async {
    final amount = cheque.amountCents.toBigInt().toInt();
    final description =
        'Dishonoured cheque #${cheque.id} resolved by $resolutionType'
        '${note == null || note.trim().isEmpty ? '' : ' — ${note.trim()}'}';
    if (cheque.partyType == 'customer') {
      final transactionId = await _db
          .into(_db.customerTransactions)
          .insert(
            CustomerTransactionsCompanion.insert(
              customerId: cheque.partyId!,
              transactionType: 'cheque_dishonour_resolution',
              amountCents: Decimal.fromInt(-amount),
              currencyId: cheque.currencyId,
              description: Value(description),
              referenceId: Value(cheque.id),
              referenceType: const Value('cheque_instrument'),
            ),
          );
      await BalanceService.adjustCustomerBalance(
        _instrumentDao,
        customerId: cheque.partyId!,
        deltaCents: -amount,
      );
      return transactionId;
    }
    final transactionId = await _db
        .into(_db.supplierTransactions)
        .insert(
          SupplierTransactionsCompanion.insert(
            supplierId: cheque.partyId!,
            transactionType: 'cheque_dishonour_resolution',
            amountCents: Decimal.fromInt(amount),
            currencyId: cheque.currencyId,
            description: Value(description),
            referenceId: Value(cheque.id),
            referenceType: const Value('cheque_instrument'),
          ),
        );
    await BalanceService.adjustSupplierBalance(
      _instrumentDao,
      supplierId: cheque.partyId!,
      deltaCents: amount,
    );
    return transactionId;
  }

  Future<ChequeTransitionResult> _markFailed(
    String sourceTable,
    int sourceId,
    bool cancelled,
    String reason,
    int? userId,
    int? instrumentId,
  ) {
    return _db.transaction(() async {
      final c = await _resolveInstrument(
        sourceTable,
        sourceId,
        userId,
        instrumentId,
      );
      final target = cancelled
          ? ChequeInstrumentStatus.cancelled
          : ChequeInstrumentStatus.bounced;
      if (c.status == target) {
        return ChequeTransitionResult(
          status: cancelled
              ? ChequeConfirmationStatus.cancelled
              : ChequeConfirmationStatus.bounced,
        );
      }
      if (c.status == ChequeInstrumentStatus.bounced ||
          c.status == ChequeInstrumentStatus.cancelled ||
          c.status == ChequeInstrumentStatus.replaced) {
        throw StateError('A resolved cheque cannot be changed');
      }
      if (c.clearanceJournalEntryId != null) {
        await _journalService.voidChequeJournalEntry(
          chequeId: c.id,
          journalEntryId: c.clearanceJournalEntryId!,
          reason: reason,
          userId: userId,
        );
      }
      final paymentId = c.settlementPaymentId;
      final isReplacementInstrument = await _isReplacementInstrument(c.id);
      final recognitionWasBooked =
          paymentId != null ||
          c.legacyDirectBank ||
          (_isReturnSource(sourceTable) &&
              c.status == ChequeInstrumentStatus.cleared);
      if (_isAccountSource(sourceTable) && recognitionWasBooked) {
        await _accountPayments.reverseCheque(chequeId: c.id, userId: userId);
      }
      final isIncomingDishonour =
          !cancelled && c.direction == ChequeDirectionValue.incoming;
      var paymentHadJournal = false;
      int? reversed;
      int? restorationId;

      if (isIncomingDishonour) {
        reversed = c.amountCents.toBigInt().toInt();
        restorationId = await _journalService
            .recordChequeObligationRestorationJournalEntry(
              chequeId: c.id,
              amountCents: reversed,
              currencyId: c.currencyId,
              debitAccountCode: '1030',
              creditAccountCode: recognitionWasBooked
                  ? (c.legacyDirectBank ? '1010' : '1020')
                  : _incomingObligationAccount(sourceTable),
              cancelled: false,
              reason: reason,
              userId: userId,
            );
        if (recognitionWasBooked) {
          await _restorePartySubledger(
            sourceTable: sourceTable,
            cheque: c,
            reason: reason,
          );
        }
      } else if (cancelled &&
          c.direction == ChequeDirectionValue.incoming &&
          isReplacementInstrument &&
          recognitionWasBooked) {
        reversed = c.amountCents.toBigInt().toInt();
        final obligationAccount = c.partyType == 'supplier' ? '2000' : '1100';
        restorationId = await _journalService
            .recordChequeObligationRestorationJournalEntry(
              chequeId: c.id,
              amountCents: reversed,
              currencyId: c.currencyId,
              debitAccountCode: obligationAccount,
              creditAccountCode: '1020',
              cancelled: true,
              reason: reason,
              userId: userId,
            );
        await _restorePartySubledger(
          sourceTable: sourceTable,
          cheque: c,
          reason: reason,
        );
        paymentHadJournal = true;
      } else if (paymentId != null && _isInvoiceSource(sourceTable)) {
        paymentHadJournal = await _paymentHasJournal(sourceTable, paymentId);
        reversed = await _paymentAmount(sourceTable, paymentId);
        if (reversed != null) {
          if (sourceTable == ChequeSourceTables.purchase) {
            await _purchaseRepo.deletePayment(paymentId);
          } else {
            await _saleRepo.deletePayment(paymentId);
          }
        }
      } else if (paymentId != null && _isReturnSource(sourceTable)) {
        await _journalService.voidChequeJournalEntry(
          chequeId: c.id,
          journalEntryId: paymentId,
          reason: reason,
          userId: userId,
        );
        await _reverseReturnPartySettlement(
          sourceTable: sourceTable,
          cheque: c,
          reason: reason,
        );
        paymentHadJournal = true;
        reversed = c.amountCents.toBigInt().toInt();
      }
      if (!isIncomingDishonour && recognitionWasBooked && !paymentHadJournal) {
        final a = _restorationAccounts(sourceTable, c);
        restorationId = await _journalService
            .recordChequeObligationRestorationJournalEntry(
              chequeId: c.id,
              amountCents: c.amountCents.toBigInt().toInt(),
              currencyId: c.currencyId,
              debitAccountCode: a.debit,
              creditAccountCode: a.credit,
              cancelled: cancelled,
              reason: reason,
              userId: userId,
            );
      }
      if (!isIncomingDishonour &&
          restorationId != null &&
          (paymentId == null ||
              c.legacyDirectBank ||
              _isAccountSource(sourceTable))) {
        await _restorePartySubledger(
          sourceTable: sourceTable,
          cheque: c,
          reason: reason,
        );
      }
      await _instrumentDao.writeLifecycle(
        id: c.id,
        status: target,
        bounceReason: cancelled ? null : reason,
        dishonourJournalEntryId: restorationId,
        clearSettlementPaymentId: paymentId != null && !isIncomingDishonour,
        clearClearanceJournalEntryId: c.clearanceJournalEntryId != null,
        userId: userId,
      );
      if (!_isAccountSource(sourceTable)) {
        await _confirmDao.confirm(
          sourceTable: sourceTable,
          sourceId: sourceId,
          status: cancelled
              ? ChequeConfirmationStatus.cancelled
              : ChequeConfirmationStatus.bounced,
          bounceReason: cancelled ? null : reason,
          note: cancelled ? reason : null,
          userId: userId,
          clearClearedPaymentId: !isIncomingDishonour,
        );
      }
      await _audit.log(
        entityType: 'cheque_instrument',
        entityId: c.id,
        action: cancelled ? 'cancel' : 'bounce',
        oldValue: {'status': c.status},
        newValue: {
          'status': target,
          'reason': reason,
          'paymentId': paymentId,
          'journalId': restorationId,
        },
        userId: userId,
        severity: AuditSeverity.critical,
      );
      return ChequeTransitionResult(
        status: cancelled
            ? ChequeConfirmationStatus.cancelled
            : ChequeConfirmationStatus.bounced,
        reversedAmountCents:
            reversed ??
            (restorationId == null ? null : c.amountCents.toBigInt().toInt()),
      );
    });
  }

  bool _isInvoiceSource(String source) =>
      source == ChequeSourceTables.sale ||
      source == ChequeSourceTables.purchase;

  bool _isReturnSource(String source) =>
      source == ChequeSourceTables.saleReturn ||
      source == ChequeSourceTables.purchaseReturn ||
      source == ChequeSourceTables.saleReturnAdjustment ||
      source == ChequeSourceTables.purchaseReturnAdjustment;

  bool _isAccountSource(String source) =>
      ChequeSourceTables.isAccountSource(source);

  bool _isSettleable(String source) =>
      _isInvoiceSource(source) ||
      _isReturnSource(source) ||
      _isAccountSource(source);

  Future<bool> _isReplacementInstrument(int chequeId) async {
    final row = await _db
        .customSelect(
          'SELECT 1 AS found FROM cheque_instruments '
          'WHERE replacement_cheque_id = ? LIMIT 1',
          variables: [Variable.withInt(chequeId)],
        )
        .getSingleOrNull();
    return row != null;
  }

  Future<int> _recordSettlement(
    String source,
    int id,
    int amount,
    ChequeInstrument cheque,
    String? note,
    int? userId,
  ) async {
    if (_isAccountSource(source)) {
      final settlement = await _recordAccountPartySettlement(
        cheque: cheque,
        amount: amount,
        note: note,
        userId: userId,
      );
      return settlement.transactionId;
    }
    if (source == ChequeSourceTables.purchase) {
      final p = await _purchaseRepo.getPurchaseById(id);
      if (p == null) throw ChequeSourceNotFoundException(source, id);
      return _purchaseRepo.recordPayment(
        purchaseId: id,
        currencyId: p.currencyId,
        amountCents: Decimal.fromInt(amount),
        paymentMethod: 'cheque',
        reference: cheque.chequeNumber,
        notes: note ?? 'Cleared issued cheque',
        paymentDate: DateTime.now(),
      );
    }
    if (source == ChequeSourceTables.sale) {
      final s = await _saleRepo.getSaleById(id);
      if (s == null) throw ChequeSourceNotFoundException(source, id);
      return _saleRepo.recordPayment(
        saleId: id,
        amountCents: Decimal.fromInt(amount),
        currencyId: s.currencyId,
        paymentMethod: 'cheque',
        reference: cheque.chequeNumber,
        notes: note ?? 'Cleared incoming cheque',
        paymentDate: DateTime.now(),
      );
    }
    if (_isReturnSource(source)) {
      if (cheque.partyId == null) {
        throw StateError(
          'A return cheque must be linked to a customer or supplier before '
          'it can be cleared',
        );
      }
      final settlementJournalId = await _journalService
          .recordReturnChequeSettlementJournalEntry(
            chequeId: cheque.id,
            incoming: cheque.direction == ChequeDirectionValue.incoming,
            amountCents: amount,
            currencyId: cheque.currencyId,
            obligationAccountCode: _returnObligationAccount(source),
            userId: userId,
          );
      await _recordReturnPartySettlement(
        sourceTable: source,
        cheque: cheque,
        note: note,
      );
      return settlementJournalId;
    }
    throw ChequeSourceNotFoundException(source, id);
  }

  Future<({int transactionId, int journalEntryId})>
  _recordAccountPartySettlement({
    required ChequeInstrument cheque,
    required int amount,
    required String? note,
    required int? userId,
    bool throughChequeClearing = true,
    String? paymentMethod,
  }) async {
    final partyId = cheque.partyId;
    final partyType = cheque.partyType;
    if (partyId == null ||
        (partyType != 'customer' && partyType != 'supplier')) {
      throw StateError('account_cheque_party_required');
    }
    final expectedSource = partyType == 'customer'
        ? ChequeSourceTables.customerAccount
        : ChequeSourceTables.supplierAccount;
    if (cheque.sourceTable != expectedSource || cheque.sourceId != partyId) {
      throw StateError('account_cheque_party_mismatch');
    }

    final incoming = cheque.direction == ChequeDirectionValue.incoming;
    final delta = partyType == 'customer'
        ? (incoming ? -amount : amount)
        : (incoming ? amount : -amount);
    final transactionType =
        (partyType == 'customer' && incoming) ||
            (partyType == 'supplier' && !incoming)
        ? 'payment'
        : 'refund';
    final numberService = DocumentNumberService(_db);
    final transactionNumber = partyType == 'customer'
        ? await numberService.nextCustomerTransaction(
            transactionType == 'payment' ? 'CAP' : 'CAR',
          )
        : await numberService.nextSupplierTransaction(
            transactionType == 'payment' ? 'SAP' : 'SAR',
          );
    final description =
        '${incoming ? 'Incoming' : 'Outgoing'} account cheque '
        '${cheque.chequeNumber ?? '#${cheque.id}'}'
        '${note == null || note.trim().isEmpty ? '' : ' — ${note.trim()}'}';

    final int transactionId;
    if (partyType == 'customer') {
      transactionId = await _db
          .into(_db.customerTransactions)
          .insert(
            CustomerTransactionsCompanion.insert(
              customerId: partyId,
              transactionType: transactionType,
              transactionNumber: Value(transactionNumber),
              amountCents: Decimal.fromInt(delta),
              currencyId: cheque.currencyId,
              description: Value(description),
              referenceId: Value(cheque.id),
              referenceType: const Value('cheque_instrument'),
            ),
          );
    } else {
      transactionId = await _db
          .into(_db.supplierTransactions)
          .insert(
            SupplierTransactionsCompanion.insert(
              supplierId: partyId,
              transactionType: transactionType,
              transactionNumber: Value(transactionNumber),
              amountCents: Decimal.fromInt(delta),
              currencyId: cheque.currencyId,
              description: Value(description),
              referenceId: Value(cheque.id),
              referenceType: const Value('cheque_instrument'),
            ),
          );
    }

    final journalEntryId = await _journalService
        .recordAccountChequeSettlementJournalEntry(
          chequeId: cheque.id,
          transactionId: transactionId,
          partyType: partyType!,
          incoming: incoming,
          amountCents: amount,
          currencyId: cheque.currencyId,
          paymentMethod: paymentMethod,
          throughChequeClearing: throughChequeClearing,
          userId: userId,
        );
    if (partyType == 'customer') {
      await BalanceService.adjustCustomerBalance(
        _instrumentDao,
        customerId: partyId,
        deltaCents: delta,
      );
    } else {
      await BalanceService.adjustSupplierBalance(
        _instrumentDao,
        supplierId: partyId,
        deltaCents: delta,
      );
    }
    await _accountPayments.recognizeClearedCheque(
      cheque: cheque,
      settlementTransactionId: transactionId,
    );
    return (transactionId: transactionId, journalEntryId: journalEntryId);
  }

  String _returnObligationAccount(String source) {
    if (source == ChequeSourceTables.saleReturn ||
        source == ChequeSourceTables.saleReturnAdjustment) {
      return '1100';
    }
    if (source == ChequeSourceTables.purchaseReturn ||
        source == ChequeSourceTables.purchaseReturnAdjustment) {
      return '2000';
    }
    throw ArgumentError.value(source, 'sourceTable');
  }

  String _incomingObligationAccount(String source) {
    if (source == ChequeSourceTables.sale) return '1100';
    if (source == ChequeSourceTables.customerAccount) return '1100';
    if (source == ChequeSourceTables.supplierAccount) return '2000';
    if (source == ChequeSourceTables.purchaseReturn ||
        source == ChequeSourceTables.purchaseReturnAdjustment) {
      return '2000';
    }
    throw ArgumentError.value(source, 'sourceTable');
  }

  Future<void> _recordReturnPartySettlement({
    required String sourceTable,
    required ChequeInstrument cheque,
    String? note,
  }) async {
    final partyId = cheque.partyId;
    if (partyId == null) {
      throw StateError(
        'A return cheque settlement requires a linked customer or supplier',
      );
    }
    final amount = cheque.amountCents.toBigInt().toInt();
    final saleSide =
        sourceTable == ChequeSourceTables.saleReturn ||
        sourceTable == ChequeSourceTables.saleReturnAdjustment;
    final description =
        '${saleSide ? 'Outgoing' : 'Incoming'} return cheque '
        '${cheque.chequeNumber ?? '#${cheque.id}'} cleared'
        '${note == null || note.trim().isEmpty ? '' : ' — ${note.trim()}'}';
    if (saleSide) {
      await _db
          .into(_db.customerTransactions)
          .insert(
            CustomerTransactionsCompanion.insert(
              customerId: partyId,
              transactionType: 'cheque_return_settlement',
              amountCents: Decimal.fromInt(amount),
              currencyId: cheque.currencyId,
              description: Value(description),
              referenceId: Value(cheque.id),
              referenceType: const Value('cheque_instrument'),
            ),
          );
      await BalanceService.adjustCustomerBalance(
        _instrumentDao,
        customerId: partyId,
        deltaCents: amount,
      );
      return;
    }
    await _db
        .into(_db.supplierTransactions)
        .insert(
          SupplierTransactionsCompanion.insert(
            supplierId: partyId,
            transactionType: 'cheque_return_settlement',
            amountCents: Decimal.fromInt(amount),
            currencyId: cheque.currencyId,
            description: Value(description),
            referenceId: Value(cheque.id),
            referenceType: const Value('cheque_instrument'),
          ),
        );
    await BalanceService.adjustSupplierBalance(
      _instrumentDao,
      supplierId: partyId,
      deltaCents: amount,
    );
  }

  Future<void> _reverseReturnPartySettlement({
    required String sourceTable,
    required ChequeInstrument cheque,
    required String reason,
  }) async {
    final partyId = cheque.partyId;
    if (partyId == null) return;
    final amount = cheque.amountCents.toBigInt().toInt();
    final saleSide =
        sourceTable == ChequeSourceTables.saleReturn ||
        sourceTable == ChequeSourceTables.saleReturnAdjustment;
    if (saleSide) {
      await _db
          .into(_db.customerTransactions)
          .insert(
            CustomerTransactionsCompanion.insert(
              customerId: partyId,
              transactionType: 'cheque_return_settlement_reversal',
              amountCents: Decimal.fromInt(-amount),
              currencyId: cheque.currencyId,
              description: Value(
                'Return cheque #${cheque.id} settlement reversed — $reason',
              ),
              referenceId: Value(cheque.id),
              referenceType: const Value('cheque_instrument'),
            ),
          );
      await BalanceService.adjustCustomerBalance(
        _instrumentDao,
        customerId: partyId,
        deltaCents: -amount,
      );
      return;
    }
    await _db
        .into(_db.supplierTransactions)
        .insert(
          SupplierTransactionsCompanion.insert(
            supplierId: partyId,
            transactionType: 'cheque_return_settlement_reversal',
            amountCents: Decimal.fromInt(-amount),
            currencyId: cheque.currencyId,
            description: Value(
              'Return cheque #${cheque.id} settlement reversed — $reason',
            ),
            referenceId: Value(cheque.id),
            referenceType: const Value('cheque_instrument'),
          ),
        );
    await BalanceService.adjustSupplierBalance(
      _instrumentDao,
      supplierId: partyId,
      deltaCents: -amount,
    );
  }

  Future<ChequeInstrument> _ensureInstrument(
    String source,
    int id,
    int? userId,
  ) async {
    final rows = await _instrumentDao.getBySource(
      sourceTable: source,
      sourceId: id,
    );
    if (rows.isNotEmpty) return rows.first;
    final s = await _sourceSnapshot(source, id);
    final newId = await _instrumentDao.create(
      direction: s.direction,
      sourceTable: source,
      sourceId: id,
      amountCents: s.amount,
      currencyId: s.currency,
      dueDate: s.due,
      issueDate: s.issue,
      partyType: s.partyType,
      partyId: s.partyId,
      settlementPaymentId: s.paymentId,
      userId: userId,
    );
    final created = await _instrumentDao.getById(newId);
    if (created == null) throw StateError('Cheque instrument was not created');
    return created;
  }

  /// Resolves one physical cheque. Legacy callers omit [instrumentId] and
  /// keep the original one-cheque-per-document behaviour. The management
  /// screen always supplies it, preventing an action on one partial cheque
  /// from accidentally changing another cheque for the same invoice.
  Future<ChequeInstrument> _resolveInstrument(
    String source,
    int sourceId,
    int? userId,
    int? instrumentId,
  ) async {
    if (instrumentId == null) {
      if (_isAccountSource(source)) {
        throw StateError('account_cheque_instrument_required');
      }
      return _ensureInstrument(source, sourceId, userId);
    }
    final instrument = await _instrumentDao.getById(instrumentId);
    if (instrument == null ||
        instrument.sourceTable != source ||
        instrument.sourceId != sourceId) {
      throw ChequeSourceNotFoundException(source, sourceId);
    }
    return instrument;
  }

  Future<
    ({
      String direction,
      int amount,
      int currency,
      DateTime due,
      DateTime issue,
      String? partyType,
      int? partyId,
      int? paymentId,
    })
  >
  _sourceSnapshot(String source, int id) async {
    if (source == ChequeSourceTables.sale) {
      final r = await (_db.select(
        _db.sales,
      )..where((x) => x.id.equals(id))).getSingleOrNull();
      if (r == null || r.dueDate == null) {
        throw ChequeSourceNotFoundException(source, id);
      }
      return (
        direction: ChequeDirectionValue.incoming,
        amount: r.totalCents.toBigInt().toInt(),
        currency: r.currencyId,
        due: r.dueDate!,
        issue: r.saleDate,
        partyType: r.customerId == null ? null : 'customer',
        partyId: r.customerId,
        paymentId: await _firstPayment(source, id),
      );
    }
    if (source == ChequeSourceTables.purchase) {
      final r = await (_db.select(
        _db.purchases,
      )..where((x) => x.id.equals(id))).getSingleOrNull();
      if (r == null || r.dueDate == null) {
        throw ChequeSourceNotFoundException(source, id);
      }
      return (
        direction: ChequeDirectionValue.outgoing,
        amount: r.totalCents.toBigInt().toInt(),
        currency: r.currencyId,
        due: r.dueDate!,
        issue: r.purchaseDate,
        partyType: 'supplier',
        partyId: r.supplierId,
        paymentId: await _firstPayment(source, id),
      );
    }
    if (source == ChequeSourceTables.saleReturn) {
      final r = await (_db.select(
        _db.saleReturns,
      )..where((x) => x.id.equals(id))).getSingleOrNull();
      if (r == null || r.dueDate == null) {
        throw ChequeSourceNotFoundException(source, id);
      }
      final sale = await (_db.select(
        _db.sales,
      )..where((x) => x.id.equals(r.saleId))).getSingleOrNull();
      return (
        direction: ChequeDirectionValue.outgoing,
        amount: r.totalCents.toBigInt().toInt(),
        currency: r.currencyId,
        due: r.dueDate!,
        issue: r.returnDate,
        partyType: sale?.customerId == null ? null : 'customer',
        partyId: sale?.customerId,
        paymentId: null,
      );
    }
    if (source == ChequeSourceTables.purchaseReturn) {
      final r = await (_db.select(
        _db.purchaseReturns,
      )..where((x) => x.id.equals(id))).getSingleOrNull();
      if (r == null || r.dueDate == null) {
        throw ChequeSourceNotFoundException(source, id);
      }
      final purchase = await (_db.select(
        _db.purchases,
      )..where((x) => x.id.equals(r.purchaseId))).getSingleOrNull();
      return (
        direction: ChequeDirectionValue.incoming,
        amount: r.totalCents.toBigInt().toInt(),
        currency: r.currencyId,
        due: r.dueDate!,
        issue: r.returnDate,
        partyType: 'supplier',
        partyId: purchase?.supplierId,
        paymentId: null,
      );
    }
    if (source == ChequeSourceTables.saleReturnAdjustment) {
      final r = await (_db.select(
        _db.saleReturnAdjustments,
      )..where((x) => x.id.equals(id))).getSingleOrNull();
      if (r == null || r.dueDate == null) {
        throw ChequeSourceNotFoundException(source, id);
      }
      return (
        direction: ChequeDirectionValue.outgoing,
        amount: r.totalCents.toBigInt().toInt(),
        currency: r.currencyId,
        due: r.dueDate!,
        issue: r.returnDate,
        partyType: r.customerId == null ? null : 'customer',
        partyId: r.customerId,
        paymentId: null,
      );
    }
    if (source == ChequeSourceTables.purchaseReturnAdjustment) {
      final r = await (_db.select(
        _db.purchaseReturnAdjustments,
      )..where((x) => x.id.equals(id))).getSingleOrNull();
      if (r == null || r.dueDate == null) {
        throw ChequeSourceNotFoundException(source, id);
      }
      return (
        direction: ChequeDirectionValue.incoming,
        amount: r.totalCents.toBigInt().toInt(),
        currency: r.currencyId,
        due: r.dueDate!,
        issue: r.returnDate,
        partyType: 'supplier',
        partyId: r.supplierId,
        paymentId: null,
      );
    }
    throw ArgumentError.value(source, 'sourceTable');
  }

  Future<int?> _firstPayment(String source, int id) async {
    final table = source == ChequeSourceTables.purchase
        ? 'purchase_payments'
        : 'sale_payments';
    final fk = source == ChequeSourceTables.purchase
        ? 'purchase_id'
        : 'sale_id';
    final row = await _db
        .customSelect(
          'SELECT id FROM $table WHERE $fk = ? AND payment_method IN (\'cheque\',\'check\') ORDER BY id LIMIT 1',
          variables: [Variable.withInt(id)],
        )
        .getSingleOrNull();
    return row?.read<int>('id');
  }

  Future<bool> _paymentHasJournal(String source, int paymentId) async {
    final table = source == ChequeSourceTables.purchase
        ? 'purchase_payments'
        : 'sale_payments';
    final row = await _db
        .customSelect(
          'SELECT COUNT(*) AS c FROM journal_entries WHERE source_table = ? AND source_id = ? AND status = \'posted\' AND is_reversed = 0',
          variables: [Variable.withString(table), Variable.withInt(paymentId)],
        )
        .getSingle();
    return row.read<int>('c') > 0;
  }

  Future<int?> _paymentAmount(String source, int paymentId) async {
    final table = source == ChequeSourceTables.purchase
        ? 'purchase_payments'
        : 'sale_payments';
    final row = await _db
        .customSelect(
          'SELECT amount_cents FROM $table WHERE id = ?',
          variables: [Variable.withInt(paymentId)],
        )
        .getSingleOrNull();
    return row?.read<int>('amount_cents');
  }

  Future<void> _restorePartySubledger({
    required String sourceTable,
    required ChequeInstrument cheque,
    required String reason,
  }) async {
    final partyId = cheque.partyId;
    if (partyId == null) return;
    final amount = cheque.amountCents.toBigInt().toInt();
    final isAccountSource = _isAccountSource(sourceTable);
    final isSaleSide =
        sourceTable == ChequeSourceTables.sale ||
        sourceTable == ChequeSourceTables.saleReturn ||
        sourceTable == ChequeSourceTables.saleReturnAdjustment ||
        sourceTable == ChequeSourceTables.customerAccount;
    final isInvoice =
        sourceTable == ChequeSourceTables.sale ||
        sourceTable == ChequeSourceTables.purchase;
    final delta = isAccountSource
        ? (cheque.partyType == 'customer'
              ? (cheque.direction == ChequeDirectionValue.incoming
                    ? amount
                    : -amount)
              : (cheque.direction == ChequeDirectionValue.incoming
                    ? -amount
                    : amount))
        : (isInvoice ? amount : -amount);
    final description = 'Cheque #${cheque.id} failed — $reason';

    if (isSaleSide) {
      await _db
          .into(_db.customerTransactions)
          .insert(
            CustomerTransactionsCompanion.insert(
              customerId: partyId,
              transactionType: 'cheque_dishonour',
              amountCents: Decimal.fromInt(delta),
              currencyId: cheque.currencyId,
              description: Value(description),
              referenceId: Value(cheque.id),
              referenceType: const Value('cheque_instrument'),
            ),
          );
      await BalanceService.adjustCustomerBalance(
        _instrumentDao,
        customerId: partyId,
        deltaCents: delta,
      );
      return;
    }

    await _db
        .into(_db.supplierTransactions)
        .insert(
          SupplierTransactionsCompanion.insert(
            supplierId: partyId,
            transactionType: 'cheque_dishonour',
            amountCents: Decimal.fromInt(delta),
            currencyId: cheque.currencyId,
            description: Value(description),
            referenceId: Value(cheque.id),
            referenceType: const Value('cheque_instrument'),
          ),
        );
    await BalanceService.adjustSupplierBalance(
      _instrumentDao,
      supplierId: partyId,
      deltaCents: delta,
    );
  }

  ({String debit, String credit}) _restorationAccounts(
    String source,
    ChequeInstrument c,
  ) {
    final clearing = c.legacyDirectBank
        ? '1010'
        : (c.direction == ChequeDirectionValue.incoming ? '1020' : '2020');
    switch (source) {
      case ChequeSourceTables.sale:
        return (debit: c.partyId == null ? '1030' : '1100', credit: clearing);
      case ChequeSourceTables.purchase:
        return (debit: clearing, credit: '2000');
      case ChequeSourceTables.saleReturn:
      case ChequeSourceTables.saleReturnAdjustment:
        return (debit: clearing, credit: '2400');
      case ChequeSourceTables.purchaseReturn:
      case ChequeSourceTables.purchaseReturnAdjustment:
        return (debit: '2000', credit: clearing);
      case ChequeSourceTables.customerAccount:
        return c.direction == ChequeDirectionValue.incoming
            ? (debit: '1100', credit: clearing)
            : (debit: clearing, credit: '1100');
      case ChequeSourceTables.supplierAccount:
        return c.direction == ChequeDirectionValue.incoming
            ? (debit: '2000', credit: clearing)
            : (debit: clearing, credit: '2000');
      default:
        throw ArgumentError.value(source, 'sourceTable');
    }
  }
}
