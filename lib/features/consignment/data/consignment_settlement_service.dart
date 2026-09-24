import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/services/balance_service.dart';
import '../../../core/services/document_number_service.dart';
import '../../../core/services/journal_entry_service.dart';
import 'consignment_module_service.dart';

/// Converts immutable consignment obligation events into reviewed supplier AP.
/// This is deliberately separate from ordinary purchases and supplier invoices.
class ConsignmentSettlementService {
  ConsignmentSettlementService(this._db, this._module, this._journal);

  final AppDatabase _db;
  final ConsignmentModuleService _module;
  final JournalEntryService _journal;

  static const _paymentMethods = {'cash', 'card', 'bank_transfer'};
  static const _maxSafeInteger = 9007199254740991;

  Future<ConsignmentSettlementStatement> createDraft({
    required String requestKey,
    required String agreementId,
    required DateTime periodStart,
    required DateTime periodEnd,
    String notes = '',
  }) => _db.transaction(() async {
    final access = await _module.requireHistoricalManageAccess();
    _validateUuid(requestKey, 'requestKey');
    final start = periodStart.toUtc();
    final end = periodEnd.toUtc();
    final cleanNotes = notes.trim();
    if (end.isBefore(start)) {
      throw ArgumentError('Settlement period end precedes its start.');
    }
    if (cleanNotes.length > 2000) {
      throw ArgumentError('Settlement notes are too long.');
    }

    final agreement =
        await (_db.select(_db.consignmentAgreements)..where(
              (a) =>
                  a.id.equals(agreementId) &
                  a.organizationId.equals(access.scope.organizationId) &
                  a.branchId.equals(access.scope.branchId) &
                  a.databaseId.equals(access.scope.databaseId) &
                  a.status.isIn(const ['active', 'superseded', 'closed']),
            ))
            .getSingleOrNull();
    if (agreement == null) {
      throw StateError('The agreement is unavailable in the local branch.');
    }
    final prior = await (_db.select(
      _db.consignmentSettlementStatements,
    )..where((s) => s.requestKey.equals(requestKey))).getSingleOrNull();
    if (prior != null) {
      if (prior.agreementId != agreement.id ||
          prior.periodStart.toUtc() != start ||
          prior.periodEnd.toUtc() != end ||
          prior.notes != cleanNotes) {
        throw StateError(
          'Settlement request key was reused with different data.',
        );
      }
      return prior;
    }

    final events = await _unassignedEvents(
      agreement: agreement,
      start: start,
      end: end,
    );
    if (events.isEmpty) {
      throw const ConsignmentUserException('consignment.no_unsettled_events');
    }
    if (events.length > 10000) {
      throw StateError('Split this settlement into periods of 10,000 lines.');
    }

    final requestHash = _hash({
      'agreementId': agreement.id,
      'supplierId': agreement.supplierId,
      'currencyId': agreement.currencyId,
      'periodStart': start.toIso8601String(),
      'periodEnd': end.toIso8601String(),
      'notes': cleanNotes,
      'events': events.map((e) => e.toJson()).toList(growable: false),
    });
    final subtotal = events.fold<int>(
      0,
      (sum, event) => _checkedAdd(sum, event.signedAmountCents),
    );
    final tax = _calculateSignedTax(
      subtotal,
      agreement.settlementTaxRateBps,
      inclusive: agreement.settlementTaxInclusive,
    );
    final total = agreement.settlementTaxInclusive
        ? subtotal
        : _checkedAdd(subtotal, tax);
    final now = DateTime.now().toUtc();
    final statementId = await _nextId('consignment_settlement_statements');
    await _db
        .into(_db.consignmentSettlementStatements)
        .insert(
          ConsignmentSettlementStatementsCompanion.insert(
            id: Value(statementId),
            organizationId: access.scope.organizationId,
            branchId: access.scope.branchId,
            databaseId: access.scope.databaseId,
            supplierId: agreement.supplierId,
            agreementId: agreement.id,
            currencyId: agreement.currencyId,
            statementNumber: _statementNumber(statementId, now),
            periodStart: start,
            periodEnd: end,
            taxRateBps: Value(agreement.settlementTaxRateBps),
            taxInclusive: Value(agreement.settlementTaxInclusive),
            obligationSubtotalCents: subtotal,
            taxCents: Value(tax),
            totalCents: total,
            lineCount: events.length,
            dueDate: end.add(Duration(days: agreement.paymentTermsDays)),
            requestKey: requestKey,
            requestHash: requestHash,
            notes: Value(cleanNotes),
            createdBy: access.actorId,
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
    for (final event in events) {
      await _db
          .into(_db.consignmentSettlementItems)
          .insert(
            ConsignmentSettlementItemsCompanion.insert(
              statementId: statementId,
              sourceLedger: event.ledger,
              eventId: event.eventId,
              signedQuantity: event.signedQuantity,
              signedAmountCents: event.signedAmountCents,
              occurredAt: event.occurredAt,
            ),
          );
      await _setEventAssignment(event, 'assigned');
    }
    return _requireStatement(statementId);
  });

  Future<ConsignmentSettlementStatement> review(int statementId) =>
      _db.transaction(() async {
        final access = await _module.requireHistoricalManageAccess();
        final statement = await _requireLocalStatement(
          statementId,
          organizationId: access.scope.organizationId,
          branchId: access.scope.branchId,
          databaseId: access.scope.databaseId,
        );
        if (statement.status == 'reviewed') return statement;
        if (statement.status != 'draft') {
          throw StateError('Only a draft statement can be reviewed.');
        }
        await _verifyFrozenStatement(statement);
        final now = DateTime.now().toUtc();
        await (_db.update(
          _db.consignmentSettlementStatements,
        )..where((s) => s.id.equals(statementId))).write(
          ConsignmentSettlementStatementsCompanion(
            status: const Value('reviewed'),
            reviewedBy: Value(access.actorId),
            reviewedAt: Value(now),
            updatedAt: Value(now),
          ),
        );
        return _requireStatement(statementId);
      });

  Future<ConsignmentSettlementStatement> post(int statementId) =>
      _db.transaction(() async {
        final access = await _module.requireHistoricalManageAccess();
        final statement = await _requireLocalStatement(
          statementId,
          organizationId: access.scope.organizationId,
          branchId: access.scope.branchId,
          databaseId: access.scope.databaseId,
        );
        if ({'posted', 'partially_paid', 'paid'}.contains(statement.status)) {
          return statement;
        }
        if (statement.status != 'reviewed') {
          throw StateError('The statement must be reviewed before posting.');
        }
        await _verifyFrozenStatement(statement);
        final now = DateTime.now().toUtc();
        int? transactionId;
        int? journalId;
        if (statement.totalCents != 0) {
          transactionId = await _insertSupplierTransaction(
            supplierId: statement.supplierId,
            currencyId: statement.currencyId,
            amountCents: statement.totalCents,
            prefix: 'CST',
            type: 'consignment_settlement',
            description: 'Consignment settlement ${statement.statementNumber}',
            referenceId: statement.id,
            referenceType: 'consignment_settlement_statement',
            at: now,
          );
          await BalanceService.adjustSupplierBalance(
            _db.supplierDao,
            supplierId: statement.supplierId,
            deltaCents: statement.totalCents,
          );
          journalId = await _journal.recordConsignmentSettlementJournalEntry(
            statementId: statement.id,
            obligationSubtotalCents: statement.obligationSubtotalCents,
            taxCents: statement.taxCents,
            totalCents: statement.totalCents,
            taxInclusive: statement.taxInclusive,
            currencyId: statement.currencyId,
            entryDate: now,
            userId: access.actorId,
          );
        }
        await (_db.update(
          _db.consignmentSettlementStatements,
        )..where((s) => s.id.equals(statement.id))).write(
          ConsignmentSettlementStatementsCompanion(
            status: Value(statement.totalCents == 0 ? 'paid' : 'posted'),
            supplierTransactionId: Value(transactionId),
            journalEntryId: Value(journalId),
            postedBy: Value(access.actorId),
            postedAt: Value(now),
            updatedAt: Value(now),
          ),
        );
        return _requireStatement(statement.id);
      });

  Future<ConsignmentSettlementPayment> recordPayment({
    required int statementId,
    required int amountCents,
    required String paymentMethod,
    required String requestKey,
    String reference = '',
    DateTime? paidAt,
  }) => _db.transaction(() async {
    final access = await _module.requireHistoricalManageAccess();
    _validateUuid(requestKey, 'requestKey');
    final method = paymentMethod.trim().toLowerCase();
    final cleanReference = reference.trim();
    if (!_paymentMethods.contains(method)) {
      throw ArgumentError('Unsupported consignment payment method.');
    }
    if (amountCents <= 0 || amountCents > _maxSafeInteger) {
      throw ArgumentError('Payment amount is outside the safe range.');
    }
    if (cleanReference.length > 200) {
      throw ArgumentError('Payment reference is too long.');
    }
    final prior = await (_db.select(
      _db.consignmentSettlementPayments,
    )..where((p) => p.requestKey.equals(requestKey))).getSingleOrNull();
    if (prior != null) {
      if (prior.statementId != statementId ||
          prior.amountCents != amountCents ||
          prior.paymentMethod != method ||
          prior.reference != cleanReference) {
        throw StateError('Payment request key was reused with different data.');
      }
      return prior;
    }
    final statement = await _requireLocalStatement(
      statementId,
      organizationId: access.scope.organizationId,
      branchId: access.scope.branchId,
      databaseId: access.scope.databaseId,
    );
    if (!{'posted', 'partially_paid'}.contains(statement.status) ||
        statement.totalCents <= 0) {
      throw StateError('This statement cannot accept a payment.');
    }
    final outstanding = statement.totalCents - statement.paidCents;
    if (amountCents > outstanding) {
      throw StateError('Payment exceeds the statement outstanding balance.');
    }
    final timestamp = (paidAt ?? DateTime.now()).toUtc();
    final paymentId = await _nextId('consignment_settlement_payments');
    final transactionId = await _insertSupplierTransaction(
      supplierId: statement.supplierId,
      currencyId: statement.currencyId,
      amountCents: -amountCents,
      prefix: 'CSP',
      type: 'consignment_payment',
      description:
          'Payment for consignment settlement ${statement.statementNumber}',
      referenceId: statement.id,
      referenceType: 'consignment_settlement_statement',
      at: timestamp,
    );
    await BalanceService.adjustSupplierBalance(
      _db.supplierDao,
      supplierId: statement.supplierId,
      deltaCents: -amountCents,
    );
    final journalId = await _journal
        .recordConsignmentSettlementPaymentJournalEntry(
          paymentId: paymentId,
          amountCents: amountCents,
          currencyId: statement.currencyId,
          paymentMethod: method,
          entryDate: timestamp,
          userId: access.actorId,
        );
    await _db
        .into(_db.consignmentSettlementPayments)
        .insert(
          ConsignmentSettlementPaymentsCompanion.insert(
            id: Value(paymentId),
            statementId: statement.id,
            amountCents: amountCents,
            paymentMethod: method,
            reference: Value(cleanReference),
            requestKey: requestKey,
            supplierTransactionId: transactionId,
            journalEntryId: journalId,
            paidAt: timestamp,
            createdBy: access.actorId,
          ),
        );
    final paid = _checkedAdd(statement.paidCents, amountCents);
    await (_db.update(
      _db.consignmentSettlementStatements,
    )..where((s) => s.id.equals(statement.id))).write(
      ConsignmentSettlementStatementsCompanion(
        paidCents: Value(paid),
        status: Value(paid == statement.totalCents ? 'paid' : 'partially_paid'),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
    return (_db.select(
      _db.consignmentSettlementPayments,
    )..where((p) => p.id.equals(paymentId))).getSingle();
  });

  Future<ConsignmentSettlementPayment> reversePayment({
    required int paymentId,
    required String reason,
  }) => _db.transaction(() async {
    final access = await _module.requireHistoricalManageAccess();
    final cleanReason = reason.trim();
    if (cleanReason.isEmpty || cleanReason.length > 500) {
      throw ArgumentError('A concise reversal reason is required.');
    }
    final payment = await (_db.select(
      _db.consignmentSettlementPayments,
    )..where((p) => p.id.equals(paymentId))).getSingleOrNull();
    if (payment == null) throw StateError('Settlement payment was not found.');
    final statement = await _requireLocalStatement(
      payment.statementId,
      organizationId: access.scope.organizationId,
      branchId: access.scope.branchId,
      databaseId: access.scope.databaseId,
    );
    if (payment.status == 'reversed') return payment;
    if (payment.status != 'posted' ||
        !{'partially_paid', 'paid'}.contains(statement.status)) {
      throw StateError('This settlement payment cannot be reversed.');
    }
    final now = DateTime.now().toUtc();
    final transactionId = await _insertSupplierTransaction(
      supplierId: statement.supplierId,
      currencyId: statement.currencyId,
      amountCents: payment.amountCents,
      prefix: 'CSR',
      type: 'consignment_payment_reversal',
      description: 'Reverse consignment payment #${payment.id}: $cleanReason',
      referenceId: payment.id,
      referenceType: 'consignment_settlement_payment',
      at: now,
    );
    await BalanceService.adjustSupplierBalance(
      _db.supplierDao,
      supplierId: statement.supplierId,
      deltaCents: payment.amountCents,
    );
    final journalId = await _journal
        .recordConsignmentSettlementPaymentJournalEntry(
          paymentId: payment.id,
          amountCents: payment.amountCents,
          currencyId: statement.currencyId,
          paymentMethod: payment.paymentMethod,
          entryDate: now,
          userId: access.actorId,
          reversal: true,
        );
    await (_db.update(
      _db.consignmentSettlementPayments,
    )..where((p) => p.id.equals(payment.id))).write(
      ConsignmentSettlementPaymentsCompanion(
        status: const Value('reversed'),
        reversalSupplierTransactionId: Value(transactionId),
        reversalJournalEntryId: Value(journalId),
        reversedAt: Value(now),
        reversedBy: Value(access.actorId),
        reversalReason: Value(cleanReason),
      ),
    );
    final paid = statement.paidCents - payment.amountCents;
    if (paid < 0) throw StateError('Settlement paid balance is corrupted.');
    await (_db.update(
      _db.consignmentSettlementStatements,
    )..where((s) => s.id.equals(statement.id))).write(
      ConsignmentSettlementStatementsCompanion(
        paidCents: Value(paid),
        status: Value(paid == 0 ? 'posted' : 'partially_paid'),
        updatedAt: Value(now),
      ),
    );
    return (_db.select(
      _db.consignmentSettlementPayments,
    )..where((p) => p.id.equals(payment.id))).getSingle();
  });

  Future<ConsignmentSettlementStatement> voidStatement({
    required int statementId,
    required String reason,
  }) => _db.transaction(() async {
    final access = await _module.requireHistoricalManageAccess();
    final cleanReason = reason.trim();
    if (cleanReason.isEmpty || cleanReason.length > 500) {
      throw ArgumentError('A concise void reason is required.');
    }
    final statement = await _requireLocalStatement(
      statementId,
      organizationId: access.scope.organizationId,
      branchId: access.scope.branchId,
      databaseId: access.scope.databaseId,
    );
    if (statement.status == 'voided') return statement;
    final posted = {
      'posted',
      'partially_paid',
      'paid',
    }.contains(statement.status);
    if (!posted && !{'draft', 'reviewed'}.contains(statement.status)) {
      throw StateError('This settlement cannot be voided.');
    }
    if (posted && statement.paidCents != 0) {
      throw StateError('Reverse all settlement payments before voiding.');
    }
    final now = DateTime.now().toUtc();
    int? transactionId;
    int? journalId;
    if (posted && statement.totalCents != 0) {
      transactionId = await _insertSupplierTransaction(
        supplierId: statement.supplierId,
        currencyId: statement.currencyId,
        amountCents: -statement.totalCents,
        prefix: 'CSV',
        type: 'consignment_settlement_void',
        description:
            'Void consignment settlement ${statement.statementNumber}: '
            '$cleanReason',
        referenceId: statement.id,
        referenceType: 'consignment_settlement_statement',
        at: now,
      );
      await BalanceService.adjustSupplierBalance(
        _db.supplierDao,
        supplierId: statement.supplierId,
        deltaCents: -statement.totalCents,
      );
      journalId = await _journal.recordConsignmentSettlementJournalEntry(
        statementId: statement.id,
        obligationSubtotalCents: statement.obligationSubtotalCents,
        taxCents: statement.taxCents,
        totalCents: statement.totalCents,
        taxInclusive: statement.taxInclusive,
        currencyId: statement.currencyId,
        entryDate: now,
        userId: access.actorId,
        reversal: true,
      );
    }
    await (_db.update(
      _db.consignmentSettlementStatements,
    )..where((s) => s.id.equals(statement.id))).write(
      ConsignmentSettlementStatementsCompanion(
        status: const Value('voided'),
        voidSupplierTransactionId: Value(transactionId),
        voidJournalEntryId: Value(journalId),
        voidedBy: Value(access.actorId),
        voidedAt: Value(now),
        voidReason: Value(cleanReason),
        updatedAt: Value(now),
      ),
    );
    final items = await getStatementItems(statement.id);
    for (final item in items) {
      await _setEventAssignment(
        _SettlementSource(
          ledger: item.sourceLedger,
          eventId: item.eventId,
          signedQuantity: item.signedQuantity,
          signedAmountCents: item.signedAmountCents,
          occurredAt: item.occurredAt,
        ),
        'unassigned',
      );
    }
    return _requireStatement(statement.id);
  });

  Stream<List<ConsignmentSettlementStatement>> watchStatements({
    int? supplierId,
  }) async* {
    final access = await _module.requireViewAccess();
    final query = _db.select(_db.consignmentSettlementStatements)
      ..where(
        (s) =>
            s.organizationId.equals(access.scope.organizationId) &
            s.branchId.equals(access.scope.branchId) &
            s.databaseId.equals(access.scope.databaseId),
      )
      ..orderBy([
        (s) => OrderingTerm.desc(s.periodEnd),
        (s) => OrderingTerm.desc(s.id),
      ]);
    if (supplierId != null) query.where((s) => s.supplierId.equals(supplierId));
    yield* query.watch();
  }

  Future<List<ConsignmentSettlementItem>> getStatementItems(int statementId) =>
      (_db.select(_db.consignmentSettlementItems)
            ..where((i) => i.statementId.equals(statementId))
            ..orderBy([
              (i) => OrderingTerm.asc(i.occurredAt),
              (i) => OrderingTerm.asc(i.id),
            ]))
          .get();

  Future<List<ConsignmentSettlementPayment>> getStatementPayments(
    int statementId,
  ) =>
      (_db.select(_db.consignmentSettlementPayments)
            ..where((p) => p.statementId.equals(statementId))
            ..orderBy([(p) => OrderingTerm.asc(p.paidAt)]))
          .get();

  Future<List<_SettlementSource>> _unassignedEvents({
    required ConsignmentAgreement agreement,
    required DateTime start,
    required DateTime end,
  }) async {
    final result = <_SettlementSource>[];
    final obligationIds = await _unassignedEventIds(
      'consignment_obligation_events',
      agreement: agreement,
      start: start,
      end: end,
    );
    final obligations = obligationIds.isEmpty
        ? <ConsignmentObligationEvent>[]
        : await (_db.select(
            _db.consignmentObligationEvents,
          )..where((e) => e.id.isIn(obligationIds))).get();
    for (final event in obligations) {
      if (event.signedAmountCents != 0 && event.journalEntryId == null) {
        throw StateError('An obligation event is missing its posted journal.');
      }
      result.add(
        _SettlementSource(
          ledger: 'sale_obligation',
          eventId: event.id,
          signedQuantity: event.signedQuantity,
          signedAmountCents: event.signedAmountCents,
          occurredAt: event.occurredAt,
        ),
      );
    }
    final adjustmentIds = await _unassignedEventIds(
      'consignment_adjustment_return_events',
      agreement: agreement,
      start: start,
      end: end,
    );
    final adjustments = adjustmentIds.isEmpty
        ? <ConsignmentAdjustmentReturnEvent>[]
        : await (_db.select(
            _db.consignmentAdjustmentReturnEvents,
          )..where((e) => e.id.isIn(adjustmentIds))).get();
    for (final event in adjustments) {
      if (event.signedAmountCents != 0 && event.journalEntryId == null) {
        throw StateError('An adjustment event is missing its posted journal.');
      }
      result.add(
        _SettlementSource(
          ledger: 'adjustment_return',
          eventId: event.id,
          signedQuantity: event.signedQuantity,
          signedAmountCents: event.signedAmountCents,
          occurredAt: event.occurredAt,
        ),
      );
    }
    final custodyIds = await _unassignedEventIds(
      'consignment_custody_events',
      agreement: agreement,
      start: start,
      end: end,
    );
    final custodyEvents = custodyIds.isEmpty
        ? <ConsignmentCustodyEvent>[]
        : await (_db.select(
            _db.consignmentCustodyEvents,
          )..where((e) => e.id.isIn(custodyIds))).get();
    for (final event in custodyEvents) {
      if (event.signedAmountCents == 0 || event.journalEntryId == null) {
        throw StateError(
          'A custody-liability event is missing its posted journal.',
        );
      }
      result.add(
        _SettlementSource(
          ledger: 'custody_loss',
          eventId: event.id,
          signedQuantity: event.signedQuantity,
          signedAmountCents: event.signedAmountCents,
          occurredAt: event.occurredAt,
        ),
      );
    }
    result.sort((a, b) {
      final date = a.occurredAt.compareTo(b.occurredAt);
      if (date != 0) return date;
      final ledger = a.ledger.compareTo(b.ledger);
      return ledger != 0 ? ledger : a.eventId.compareTo(b.eventId);
    });
    return result;
  }

  Future<List<int>> _unassignedEventIds(
    String table, {
    required ConsignmentAgreement agreement,
    required DateTime start,
    required DateTime end,
  }) async {
    if (table != 'consignment_obligation_events' &&
        table != 'consignment_adjustment_return_events' &&
        table != 'consignment_custody_events') {
      throw ArgumentError.value(table, 'table');
    }
    final rows = await _db
        .customSelect(
          'SELECT id FROM $table WHERE supplier_id=? AND agreement_id=? '
          "AND currency_id=? AND settlement_status='unassigned' "
          'AND occurred_at>=? AND occurred_at<=? ORDER BY occurred_at,id '
          'LIMIT 10001',
          variables: [
            Variable.withInt(agreement.supplierId),
            Variable.withString(agreement.id),
            Variable.withInt(agreement.currencyId),
            Variable.withString(start.toUtc().toIso8601String()),
            Variable.withString(end.toUtc().toIso8601String()),
          ],
        )
        .get();
    return rows.map((row) => row.read<int>('id')).toList(growable: false);
  }

  Future<void> _verifyFrozenStatement(
    ConsignmentSettlementStatement statement,
  ) async {
    final items = await getStatementItems(statement.id);
    if (items.length != statement.lineCount || items.isEmpty) {
      throw StateError('Settlement line count failed integrity validation.');
    }
    final subtotal = items.fold<int>(
      0,
      (sum, item) => _checkedAdd(sum, item.signedAmountCents),
    );
    final tax = _calculateSignedTax(
      subtotal,
      statement.taxRateBps,
      inclusive: statement.taxInclusive,
    );
    final total = statement.taxInclusive
        ? subtotal
        : _checkedAdd(subtotal, tax);
    if (subtotal != statement.obligationSubtotalCents ||
        tax != statement.taxCents ||
        total != statement.totalCents) {
      throw StateError('Settlement totals failed integrity validation.');
    }
    for (final item in items) {
      final Object? exists;
      switch (item.sourceLedger) {
        case 'sale_obligation':
          exists =
              await (_db.select(_db.consignmentObligationEvents)..where(
                    (e) =>
                        e.id.equals(item.eventId) &
                        e.supplierId.equals(statement.supplierId) &
                        e.agreementId.equals(statement.agreementId) &
                        e.currencyId.equals(statement.currencyId) &
                        e.signedQuantity.equals(item.signedQuantity) &
                        e.signedAmountCents.equals(item.signedAmountCents) &
                        e.settlementStatus.equals('assigned'),
                  ))
                  .getSingleOrNull();
        case 'adjustment_return':
          exists =
              await (_db.select(_db.consignmentAdjustmentReturnEvents)..where(
                    (e) =>
                        e.id.equals(item.eventId) &
                        e.supplierId.equals(statement.supplierId) &
                        e.agreementId.equals(statement.agreementId) &
                        e.currencyId.equals(statement.currencyId) &
                        e.signedQuantity.equals(item.signedQuantity) &
                        e.signedAmountCents.equals(item.signedAmountCents) &
                        e.settlementStatus.equals('assigned'),
                  ))
                  .getSingleOrNull();
        case 'custody_loss':
          exists =
              await (_db.select(_db.consignmentCustodyEvents)..where(
                    (e) =>
                        e.id.equals(item.eventId) &
                        e.supplierId.equals(statement.supplierId) &
                        e.agreementId.equals(statement.agreementId) &
                        e.currencyId.equals(statement.currencyId) &
                        e.signedQuantity.equals(item.signedQuantity) &
                        e.signedAmountCents.equals(item.signedAmountCents) &
                        e.settlementStatus.equals('assigned'),
                  ))
                  .getSingleOrNull();
        default:
          exists = null;
      }
      if (exists == null) {
        throw StateError('A settlement source failed integrity validation.');
      }
    }
  }

  Future<void> _setEventAssignment(
    _SettlementSource source,
    String status,
  ) async {
    final int affected;
    switch (source.ledger) {
      case 'sale_obligation':
        affected =
            await (_db.update(
              _db.consignmentObligationEvents,
            )..where((e) => e.id.equals(source.eventId))).write(
              ConsignmentObligationEventsCompanion(
                settlementStatus: Value(status),
              ),
            );
      case 'adjustment_return':
        affected =
            await (_db.update(
              _db.consignmentAdjustmentReturnEvents,
            )..where((e) => e.id.equals(source.eventId))).write(
              ConsignmentAdjustmentReturnEventsCompanion(
                settlementStatus: Value(status),
              ),
            );
      case 'custody_loss':
        affected =
            await (_db.update(
              _db.consignmentCustodyEvents,
            )..where((e) => e.id.equals(source.eventId))).write(
              ConsignmentCustodyEventsCompanion(
                settlementStatus: Value(status),
              ),
            );
      default:
        throw StateError('Unknown consignment settlement source.');
    }
    if (affected != 1) throw StateError('Settlement source was not found.');
  }

  Future<int> _insertSupplierTransaction({
    required int supplierId,
    required int currencyId,
    required int amountCents,
    required String prefix,
    required String type,
    required String description,
    required int referenceId,
    required String referenceType,
    required DateTime at,
  }) async {
    final number = await DocumentNumberService(
      _db,
    ).nextSupplierTransaction(prefix);
    return _db
        .into(_db.supplierTransactions)
        .insert(
          SupplierTransactionsCompanion.insert(
            supplierId: supplierId,
            transactionNumber: Value(number),
            transactionType: type,
            amountCents: Decimal.fromInt(amountCents),
            currencyId: currencyId,
            description: Value(description),
            referenceId: Value(referenceId),
            referenceType: Value(referenceType),
            transactionDate: Value(at),
          ),
        );
  }

  Future<ConsignmentSettlementStatement> _requireLocalStatement(
    int statementId, {
    required String organizationId,
    required String branchId,
    required String databaseId,
  }) async {
    final statement = await _requireStatement(statementId);
    if (statement.organizationId != organizationId ||
        statement.branchId != branchId ||
        statement.databaseId != databaseId) {
      throw const ConsignmentAccessDenied();
    }
    return statement;
  }

  Future<ConsignmentSettlementStatement> _requireStatement(int id) async {
    final statement = await (_db.select(
      _db.consignmentSettlementStatements,
    )..where((s) => s.id.equals(id))).getSingleOrNull();
    if (statement == null) throw StateError('Settlement was not found.');
    return statement;
  }

  Future<int> _nextId(String table) async {
    if (table != 'consignment_settlement_statements' &&
        table != 'consignment_settlement_payments') {
      throw ArgumentError.value(table, 'table');
    }
    final row = await _db
        .customSelect('SELECT COALESCE(MAX(id),0)+1 AS next_id FROM $table')
        .getSingle();
    return row.read<int>('next_id');
  }

  String _statementNumber(int id, DateTime now) =>
      'CST-${now.year.toString().padLeft(4, '0')}'
      '${now.month.toString().padLeft(2, '0')}-${id.toString().padLeft(6, '0')}';

  int _calculateSignedTax(int amount, int rateBps, {required bool inclusive}) {
    if (amount == 0 || rateBps == 0) return 0;
    final sign = amount < 0 ? -1 : 1;
    final absolute = amount.abs();
    final denominator = inclusive ? 10000 + rateBps : 10000;
    final tax = ((absolute * rateBps) + (denominator ~/ 2)) ~/ denominator;
    return sign * tax;
  }

  int _checkedAdd(int left, int right) {
    final result = left + right;
    if (result.abs() > _maxSafeInteger) {
      throw StateError('Settlement total exceeds the supported safe range.');
    }
    return result;
  }

  void _validateUuid(String value, String name) {
    if (!RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
    ).hasMatch(value)) {
      throw ArgumentError.value(value, name, 'A UUID is required.');
    }
  }

  String _hash(Object value) =>
      sha256.convert(utf8.encode(jsonEncode(value))).toString();
}

class _SettlementSource {
  const _SettlementSource({
    required this.ledger,
    required this.eventId,
    required this.signedQuantity,
    required this.signedAmountCents,
    required this.occurredAt,
  });

  final String ledger;
  final int eventId;
  final int signedQuantity;
  final int signedAmountCents;
  final DateTime occurredAt;

  Map<String, Object> toJson() => {
    'ledger': ledger,
    'eventId': eventId,
    'signedQuantity': signedQuantity,
    'signedAmountCents': signedAmountCents,
    'occurredAt': occurredAt.toUtc().toIso8601String(),
  };
}
