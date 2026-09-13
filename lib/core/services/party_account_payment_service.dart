import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';

import '../database/app_database.dart';
import 'audit_log_service.dart';

abstract final class PartyAccountPaymentStatus {
  static const open = 'open';
  static const partiallyApplied = 'partially_applied';
  static const applied = 'applied';
  static const reversed = 'reversed';
}

abstract final class PartyAccountPaymentDocumentType {
  static const sale = 'sale';
  static const purchase = 'purchase';
}

class PartyOutstandingDocument {
  final String documentType;
  final int documentId;
  final String documentNumber;
  final DateTime documentDate;
  final int outstandingCents;
  final int currencyId;

  const PartyOutstandingDocument({
    required this.documentType,
    required this.documentId,
    required this.documentNumber,
    required this.documentDate,
    required this.outstandingCents,
    required this.currencyId,
  });
}

class PartyAccountPaymentDetails {
  final PartyAccountPayment payment;
  final ChequeInstrument cheque;
  final String partyName;
  final String currencyCode;
  final String currencySymbol;

  const PartyAccountPaymentDetails({
    required this.payment,
    required this.cheque,
    required this.partyName,
    required this.currencyCode,
    required this.currencySymbol,
  });

  int get amountCents => payment.amountCents.toBigInt().toInt();
  int get appliedCents => payment.appliedCents.toBigInt().toInt();
  int get availableCents => amountCents - appliedCents;
}

class PartyAccountPaymentApplicationDetails {
  final PartyAccountPaymentApplication application;
  final String documentNumber;

  const PartyAccountPaymentApplicationDetails({
    required this.application,
    required this.documentNumber,
  });
}

class PartyUnappliedBalance {
  final int paymentId;
  final int chequeId;
  final String chequeNumber;
  final int amountCents;
  final int appliedCents;
  final String currencySymbol;
  final DateTime recognizedAt;

  const PartyUnappliedBalance({
    required this.paymentId,
    required this.chequeId,
    required this.chequeNumber,
    required this.amountCents,
    required this.appliedCents,
    required this.currencySymbol,
    required this.recognizedAt,
  });

  int get availableCents => amountCents - appliedCents;
}

/// Tracks and allocates cleared standalone party cheques.
///
/// Clearance remains the only event that changes cash, party balances and
/// the general ledger. Allocation merely creates an `account_credit` invoice
/// payment row so the invoice can be settled without recognizing cash twice.
class PartyAccountPaymentService {
  final AppDatabase _db;
  final AuditLogService _audit;

  PartyAccountPaymentService({
    required AppDatabase db,
    required AuditLogService auditLogService,
  }) : _db = db,
       _audit = auditLogService;

  Future<PartyAccountPayment?> getByChequeId(int chequeId) => (_db.select(
    _db.partyAccountPayments,
  )..where((row) => row.chequeInstrumentId.equals(chequeId))).getSingleOrNull();

  Future<PartyAccountPaymentDetails?> getDetailsByChequeId(int chequeId) async {
    final payment = await getByChequeId(chequeId);
    if (payment == null) return null;
    final cheque = await (_db.select(
      _db.chequeInstruments,
    )..where((row) => row.id.equals(chequeId))).getSingle();
    final partyName = payment.partyType == 'customer'
        ? (await (_db.select(
            _db.customers,
          )..where((row) => row.id.equals(payment.partyId))).getSingle()).name
        : (await (_db.select(
            _db.suppliers,
          )..where((row) => row.id.equals(payment.partyId))).getSingle()).name;
    final currency = await (_db.select(
      _db.currencies,
    )..where((row) => row.id.equals(payment.currencyId))).getSingle();
    return PartyAccountPaymentDetails(
      payment: payment,
      cheque: cheque,
      partyName: partyName,
      currencyCode: currency.code,
      currencySymbol: currency.symbol,
    );
  }

  Stream<List<PartyAccountPaymentApplication>> watchApplications(
    int accountPaymentId,
  ) =>
      (_db.select(_db.partyAccountPaymentApplications)
            ..where((row) => row.accountPaymentId.equals(accountPaymentId))
            ..orderBy([(row) => OrderingTerm.desc(row.appliedAt)]))
          .watch();

  Future<List<PartyAccountPaymentApplicationDetails>> getApplications(
    int accountPaymentId,
  ) async {
    final rows = await _db
        .customSelect(
          '''
SELECT a.*,
       CASE a.document_type
         WHEN 'sale' THEN (SELECT invoice_number FROM sales WHERE id = a.document_id)
         ELSE (SELECT purchase_number FROM purchases WHERE id = a.document_id)
       END AS resolved_document_number
  FROM party_account_payment_applications a
 WHERE a.account_payment_id = ?
 ORDER BY a.applied_at DESC, a.id DESC
''',
          variables: [Variable.withInt(accountPaymentId)],
          readsFrom: {
            _db.partyAccountPaymentApplications,
            _db.sales,
            _db.purchases,
          },
        )
        .get();
    return rows
        .map(
          (row) => PartyAccountPaymentApplicationDetails(
            application: _db.partyAccountPaymentApplications.map(row.data),
            documentNumber:
                row.readNullable<String>('resolved_document_number') ??
                '#${row.read<int>('document_id')}',
          ),
        )
        .toList(growable: false);
  }

  Stream<List<PartyUnappliedBalance>> watchUnappliedForParty({
    required String partyType,
    required int partyId,
  }) {
    final query = _db.customSelect(
      '''
SELECT pap.id AS payment_id, pap.cheque_instrument_id AS cheque_id,
       COALESCE(ci.cheque_number, '#' || ci.id) AS cheque_number,
       pap.amount_cents, pap.applied_cents, c.symbol AS currency_symbol,
       pap.recognized_at
  FROM party_account_payments pap
  JOIN cheque_instruments ci ON ci.id = pap.cheque_instrument_id
  JOIN currencies c ON c.id = pap.currency_id
 WHERE pap.party_type = ? AND pap.party_id = ?
   AND pap.status IN ('open','partially_applied')
   AND pap.amount_cents > pap.applied_cents
 ORDER BY pap.recognized_at DESC, pap.id DESC
''',
      variables: [Variable.withString(partyType), Variable.withInt(partyId)],
      readsFrom: {
        _db.partyAccountPayments,
        _db.chequeInstruments,
        _db.currencies,
      },
    );
    return query.watch().map(
      (rows) => rows
          .map(
            (row) => PartyUnappliedBalance(
              paymentId: row.read<int>('payment_id'),
              chequeId: row.read<int>('cheque_id'),
              chequeNumber: row.read<String>('cheque_number'),
              amountCents: row.read<int>('amount_cents'),
              appliedCents: row.read<int>('applied_cents'),
              currencySymbol: row.read<String>('currency_symbol'),
              recognizedAt: row.read<DateTime>('recognized_at'),
            ),
          )
          .toList(growable: false),
    );
  }

  /// Idempotently exposes the cleared value for later invoice allocation.
  /// Refund-direction account cheques are deliberately excluded: they settle
  /// an existing credit and cannot be used as an advance against invoices.
  Future<int?> recognizeClearedCheque({
    required ChequeInstrument cheque,
    required int settlementTransactionId,
  }) async {
    if (!_isAllocatable(cheque)) return null;
    final now = DateTime.now();
    final existing = await getByChequeId(cheque.id);
    if (existing != null) {
      await (_db.update(
        _db.partyAccountPayments,
      )..where((row) => row.id.equals(existing.id))).write(
        PartyAccountPaymentsCompanion(
          amountCents: Value(cheque.amountCents),
          appliedCents: existing.status == PartyAccountPaymentStatus.reversed
              ? Value(Decimal.zero)
              : const Value.absent(),
          settlementTransactionId: Value(settlementTransactionId),
          status: existing.status == PartyAccountPaymentStatus.reversed
              ? const Value(PartyAccountPaymentStatus.open)
              : const Value.absent(),
          recognizedAt: Value(now),
          reversedAt: const Value(null),
          updatedAt: Value(now),
        ),
      );
      return existing.id;
    }
    return _db
        .into(_db.partyAccountPayments)
        .insert(
          PartyAccountPaymentsCompanion.insert(
            chequeInstrumentId: cheque.id,
            partyType: cheque.partyType!,
            partyId: cheque.partyId!,
            direction: cheque.direction,
            amountCents: cheque.amountCents,
            currencyId: cheque.currencyId,
            settlementTransactionId: Value(settlementTransactionId),
            recognizedAt: now,
          ),
        );
  }

  Future<List<PartyOutstandingDocument>> getOutstandingDocuments(
    int accountPaymentId,
  ) async {
    final payment = await (_db.select(
      _db.partyAccountPayments,
    )..where((row) => row.id.equals(accountPaymentId))).getSingleOrNull();
    if (payment == null) throw StateError('account_payment_not_found');
    if (payment.status == PartyAccountPaymentStatus.reversed) return const [];

    if (payment.partyType == 'customer' && payment.direction == 'incoming') {
      final rows = await _db
          .customSelect(
            '''
SELECT id, invoice_number AS document_number, sale_date AS document_date,
       currency_id, (total_cents - paid_amount_cents) AS outstanding_cents
  FROM sales
 WHERE customer_id = ? AND currency_id = ? AND status = 'completed'
   AND total_cents > paid_amount_cents
 ORDER BY sale_date, id
''',
            variables: [
              Variable.withInt(payment.partyId),
              Variable.withInt(payment.currencyId),
            ],
            readsFrom: {_db.sales},
          )
          .get();
      return rows
          .map(
            (row) => PartyOutstandingDocument(
              documentType: PartyAccountPaymentDocumentType.sale,
              documentId: row.read<int>('id'),
              documentNumber: row.read<String>('document_number'),
              documentDate: row.read<DateTime>('document_date'),
              outstandingCents: row.read<int>('outstanding_cents'),
              currencyId: row.read<int>('currency_id'),
            ),
          )
          .toList(growable: false);
    }
    if (payment.partyType == 'supplier' && payment.direction == 'outgoing') {
      final rows = await _db
          .customSelect(
            '''
SELECT id, purchase_number AS document_number,
       purchase_date AS document_date, currency_id,
       (total_cents - paid_amount_cents) AS outstanding_cents
  FROM purchases
 WHERE supplier_id = ? AND currency_id = ? AND status = 'posted'
   AND total_cents > paid_amount_cents
 ORDER BY purchase_date, id
''',
            variables: [
              Variable.withInt(payment.partyId),
              Variable.withInt(payment.currencyId),
            ],
            readsFrom: {_db.purchases},
          )
          .get();
      return rows
          .map(
            (row) => PartyOutstandingDocument(
              documentType: PartyAccountPaymentDocumentType.purchase,
              documentId: row.read<int>('id'),
              documentNumber: row.read<String>('document_number'),
              documentDate: row.read<DateTime>('document_date'),
              outstandingCents: row.read<int>('outstanding_cents'),
              currencyId: row.read<int>('currency_id'),
            ),
          )
          .toList(growable: false);
    }
    return const [];
  }

  Future<int> applyToDocument({
    required int accountPaymentId,
    required String documentType,
    required int documentId,
    required int amountCents,
    int? userId,
  }) => _db.transaction(() async {
    if (amountCents <= 0) throw ArgumentError('account_payment_amount_invalid');
    final payment = await (_db.select(
      _db.partyAccountPayments,
    )..where((row) => row.id.equals(accountPaymentId))).getSingleOrNull();
    if (payment == null) throw StateError('account_payment_not_found');
    if (payment.status == PartyAccountPaymentStatus.reversed) {
      throw StateError('account_payment_reversed');
    }
    final available =
        _cents(payment.amountCents) - _cents(payment.appliedCents);
    if (amountCents > available) {
      throw StateError('account_payment_exceeds_available');
    }

    final now = DateTime.now();
    int? salePaymentId;
    int? purchasePaymentId;
    String documentNumber;
    int outstanding;
    if (documentType == PartyAccountPaymentDocumentType.sale) {
      if (payment.partyType != 'customer' || payment.direction != 'incoming') {
        throw StateError('account_payment_document_mismatch');
      }
      final sale = await (_db.select(
        _db.sales,
      )..where((row) => row.id.equals(documentId))).getSingleOrNull();
      if (sale == null || sale.status != 'completed') {
        throw StateError('account_payment_document_not_open');
      }
      if (sale.customerId != payment.partyId ||
          sale.currencyId != payment.currencyId) {
        throw StateError('account_payment_document_mismatch');
      }
      outstanding = _cents(sale.totalCents) - _cents(sale.paidAmountCents);
      documentNumber = sale.invoiceNumber;
      if (amountCents > outstanding) {
        throw StateError('account_payment_exceeds_document');
      }
      salePaymentId = await _db
          .into(_db.salePayments)
          .insert(
            SalePaymentsCompanion.insert(
              saleId: sale.id,
              amountCents: Decimal.fromInt(amountCents),
              currencyId: sale.currencyId,
              paymentMethod: 'account_credit',
              reference: Value('ACP-$accountPaymentId'),
              notes: const Value('Allocated from cleared account cheque'),
              paymentDate: Value(now),
            ),
          );
      await _refreshSalePaidAmount(sale.id);
    } else if (documentType == PartyAccountPaymentDocumentType.purchase) {
      if (payment.partyType != 'supplier' || payment.direction != 'outgoing') {
        throw StateError('account_payment_document_mismatch');
      }
      final purchase = await (_db.select(
        _db.purchases,
      )..where((row) => row.id.equals(documentId))).getSingleOrNull();
      if (purchase == null || purchase.status != 'posted') {
        throw StateError('account_payment_document_not_open');
      }
      if (purchase.supplierId != payment.partyId ||
          purchase.currencyId != payment.currencyId) {
        throw StateError('account_payment_document_mismatch');
      }
      outstanding =
          _cents(purchase.totalCents) - _cents(purchase.paidAmountCents);
      documentNumber = purchase.purchaseNumber;
      if (amountCents > outstanding) {
        throw StateError('account_payment_exceeds_document');
      }
      purchasePaymentId = await _db
          .into(_db.purchasePayments)
          .insert(
            PurchasePaymentsCompanion.insert(
              purchaseId: purchase.id,
              amountCents: Decimal.fromInt(amountCents),
              currencyId: purchase.currencyId,
              paymentMethod: 'account_credit',
              reference: Value('ACP-$accountPaymentId'),
              notes: const Value('Allocated from cleared account cheque'),
              paymentDate: Value(now),
            ),
          );
      await _refreshPurchasePaidAmount(purchase.id);
    } else {
      throw ArgumentError.value(documentType, 'documentType');
    }

    final applicationId = await _db
        .into(_db.partyAccountPaymentApplications)
        .insert(
          PartyAccountPaymentApplicationsCompanion.insert(
            accountPaymentId: accountPaymentId,
            documentType: documentType,
            documentId: documentId,
            amountCents: Decimal.fromInt(amountCents),
            salePaymentId: Value(salePaymentId),
            purchasePaymentId: Value(purchasePaymentId),
            appliedAt: now,
            createdBy: Value(userId),
          ),
        );
    await _syncPaymentTotals(accountPaymentId);
    await _audit.log(
      entityType: 'party_account_payment_application',
      entityId: applicationId,
      action: 'apply',
      newValue: {
        'accountPaymentId': accountPaymentId,
        'documentType': documentType,
        'documentId': documentId,
        'documentNumber': documentNumber,
        'amountCents': amountCents,
        'generalLedgerPosted': false,
      },
      userId: userId,
      severity: AuditSeverity.critical,
    );
    return applicationId;
  });

  Future<void> reverseApplication({
    required int applicationId,
    String? reason,
    int? userId,
  }) => _db.transaction(() async {
    final application = await (_db.select(
      _db.partyAccountPaymentApplications,
    )..where((row) => row.id.equals(applicationId))).getSingleOrNull();
    if (application == null) throw StateError('account_application_not_found');
    if (application.status == 'reversed') return;
    final now = DateTime.now();
    await (_db.update(
      _db.partyAccountPaymentApplications,
    )..where((row) => row.id.equals(applicationId))).write(
      PartyAccountPaymentApplicationsCompanion(
        status: const Value('reversed'),
        reversedAt: Value(now),
        updatedAt: Value(now),
      ),
    );
    if (application.salePaymentId != null) {
      await (_db.delete(
        _db.salePayments,
      )..where((row) => row.id.equals(application.salePaymentId!))).go();
      await _refreshSalePaidAmount(application.documentId);
    } else if (application.purchasePaymentId != null) {
      await (_db.delete(
        _db.purchasePayments,
      )..where((row) => row.id.equals(application.purchasePaymentId!))).go();
      await _refreshPurchasePaidAmount(application.documentId);
    }
    await _syncPaymentTotals(application.accountPaymentId);
    await _audit.log(
      entityType: 'party_account_payment_application',
      entityId: applicationId,
      action: 'reverse',
      oldValue: {'status': 'active'},
      newValue: {'status': 'reversed', 'reason': reason},
      userId: userId,
      severity: AuditSeverity.critical,
    );
  });

  /// Reverses allocations before a cleared account cheque is dishonoured.
  /// The lifecycle service then performs the one accounting restoration.
  Future<void> reverseCheque({required int chequeId, int? userId}) =>
      _db.transaction(() async {
        final payment = await getByChequeId(chequeId);
        if (payment == null ||
            payment.status == PartyAccountPaymentStatus.reversed) {
          return;
        }
        final applications =
            await (_db.select(_db.partyAccountPaymentApplications)..where(
                  (row) =>
                      row.accountPaymentId.equals(payment.id) &
                      row.status.equals('active'),
                ))
                .get();
        for (final application in applications) {
          await reverseApplication(
            applicationId: application.id,
            reason: 'Source cheque dishonoured or cancelled',
            userId: userId,
          );
        }
        await (_db.update(
          _db.partyAccountPayments,
        )..where((row) => row.id.equals(payment.id))).write(
          PartyAccountPaymentsCompanion(
            appliedCents: Value(Decimal.zero),
            status: const Value(PartyAccountPaymentStatus.reversed),
            reversedAt: Value(DateTime.now()),
            updatedAt: Value(DateTime.now()),
          ),
        );
      });

  Future<void> _refreshSalePaidAmount(int saleId) async {
    await _db.customStatement(
      'UPDATE sales SET paid_amount_cents = COALESCE((SELECT SUM(amount_cents) '
      'FROM sale_payments WHERE sale_id = ?), 0), updated_at = CURRENT_TIMESTAMP '
      'WHERE id = ?',
      [saleId, saleId],
    );
  }

  Future<void> _refreshPurchasePaidAmount(int purchaseId) async {
    await _db.customStatement(
      'UPDATE purchases SET paid_amount_cents = COALESCE((SELECT SUM(amount_cents) '
      'FROM purchase_payments WHERE purchase_id = ?), 0), '
      'updated_at = CURRENT_TIMESTAMP WHERE id = ?',
      [purchaseId, purchaseId],
    );
  }

  Future<void> _syncPaymentTotals(int paymentId) async {
    final row = await _db
        .customSelect(
          'SELECT amount_cents, COALESCE((SELECT SUM(amount_cents) FROM '
          'party_account_payment_applications WHERE account_payment_id = ? '
          "AND status = 'active'), 0) AS applied_cents "
          'FROM party_account_payments WHERE id = ?',
          variables: [Variable.withInt(paymentId), Variable.withInt(paymentId)],
          readsFrom: {
            _db.partyAccountPayments,
            _db.partyAccountPaymentApplications,
          },
        )
        .getSingle();
    final amount = row.read<int>('amount_cents');
    final applied = row.read<int>('applied_cents');
    final current = await (_db.select(
      _db.partyAccountPayments,
    )..where((item) => item.id.equals(paymentId))).getSingle();
    final status = current.status == PartyAccountPaymentStatus.reversed
        ? PartyAccountPaymentStatus.reversed
        : applied == 0
        ? PartyAccountPaymentStatus.open
        : applied >= amount
        ? PartyAccountPaymentStatus.applied
        : PartyAccountPaymentStatus.partiallyApplied;
    await (_db.update(
      _db.partyAccountPayments,
    )..where((item) => item.id.equals(paymentId))).write(
      PartyAccountPaymentsCompanion(
        appliedCents: Value(Decimal.fromInt(applied)),
        status: Value(status),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  bool _isAllocatable(ChequeInstrument cheque) =>
      cheque.partyId != null &&
      ((cheque.sourceTable == 'customer_account' &&
              cheque.partyType == 'customer' &&
              cheque.direction == 'incoming') ||
          (cheque.sourceTable == 'supplier_account' &&
              cheque.partyType == 'supplier' &&
              cheque.direction == 'outgoing'));

  int _cents(Decimal value) => value.toBigInt().toInt();
}
