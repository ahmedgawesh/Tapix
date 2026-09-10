import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';

import '../../features/purchases/domain/repositories/purchase_repository.dart';
import '../../features/sales/domain/repositories/sale_repository.dart';
import '../database/app_database.dart';
import '../database/daos/cheque_confirmation_dao.dart';
import '../database/daos/cheque_instrument_dao.dart';
import 'audit_log_service.dart';

class ChequeRegisterEntry {
  final ChequeInstrument instrument;
  final String referenceNumber;
  final String? partyName;
  final String currencyCode;
  final String currencySymbol;

  const ChequeRegisterEntry({
    required this.instrument,
    required this.referenceNumber,
    required this.currencyCode,
    required this.currencySymbol,
    this.partyName,
  });
}

class ChequeOutstandingDocument {
  final String sourceTable;
  final int sourceId;
  final String referenceNumber;
  final String? partyName;
  final int? partyId;
  final int currencyId;
  final String currencyCode;
  final String currencySymbol;
  final int outstandingCents;

  const ChequeOutstandingDocument({
    required this.sourceTable,
    required this.sourceId,
    required this.referenceNumber,
    required this.currencyId,
    required this.currencyCode,
    required this.currencySymbol,
    required this.outstandingCents,
    this.partyName,
    this.partyId,
  });

  String get direction => sourceTable == ChequeSourceTables.sale
      ? ChequeDirectionValue.incoming
      : ChequeDirectionValue.outgoing;
}

/// Application service behind the cheque register UI.
///
/// Receiving or issuing a cheque creates a pending instrument only. The
/// customer/supplier obligation remains open and no payment is created until
/// bank clearance is confirmed through the cheque lifecycle service.
class ChequeManagementService {
  final AppDatabase _db;
  final ChequeInstrumentDao _instrumentDao;
  final SaleRepository _saleRepository;
  final PurchaseRepository _purchaseRepository;
  final AuditLogService _audit;

  ChequeManagementService({
    required AppDatabase db,
    required ChequeInstrumentDao instrumentDao,
    required SaleRepository saleRepository,
    required PurchaseRepository purchaseRepository,
    required AuditLogService auditLogService,
  }) : _db = db,
       _instrumentDao = instrumentDao,
       _saleRepository = saleRepository,
       _purchaseRepository = purchaseRepository,
       _audit = auditLogService;

  Stream<List<ChequeRegisterEntry>> watchRegister() {
    final query = _db.customSelect(
      '''
      SELECT ci.*,
             c.code AS currency_code,
             c.symbol AS currency_symbol,
             CASE ci.source_table
               WHEN 'sale' THEN (SELECT invoice_number FROM sales WHERE id = ci.source_id)
               WHEN 'purchase' THEN (SELECT purchase_number FROM purchases WHERE id = ci.source_id)
               WHEN 'sale_return' THEN (SELECT return_number FROM sale_returns WHERE id = ci.source_id)
               WHEN 'purchase_return' THEN (SELECT return_number FROM purchase_returns WHERE id = ci.source_id)
               WHEN 'sale_return_adjustment' THEN (SELECT return_number FROM sale_return_adjustments WHERE id = ci.source_id)
               WHEN 'purchase_return_adjustment' THEN (SELECT return_number FROM purchase_return_adjustments WHERE id = ci.source_id)
             END AS reference_number,
             CASE ci.party_type
               WHEN 'customer' THEN (SELECT name FROM customers WHERE id = ci.party_id)
               WHEN 'supplier' THEN (SELECT name FROM suppliers WHERE id = ci.party_id)
             END AS party_name
        FROM cheque_instruments ci
        JOIN currencies c ON c.id = ci.currency_id
       ORDER BY ci.due_date ASC, ci.id ASC
      ''',
      readsFrom: {
        _db.chequeInstruments,
        _db.currencies,
        _db.sales,
        _db.purchases,
        _db.saleReturns,
        _db.purchaseReturns,
        _db.saleReturnAdjustments,
        _db.purchaseReturnAdjustments,
        _db.customers,
        _db.suppliers,
      },
    );
    return query.watch().map(
      (rows) => rows
          .map(
            (row) => ChequeRegisterEntry(
              instrument: _db.chequeInstruments.map(row.data),
              referenceNumber:
                  row.readNullable<String>('reference_number') ??
                  '#${row.read<int>('id')}',
              partyName: row.readNullable<String>('party_name'),
              currencyCode: row.read<String>('currency_code'),
              currencySymbol: row.read<String>('currency_symbol'),
            ),
          )
          .toList(growable: false),
    );
  }

  Stream<List<ChequeOutstandingDocument>> watchOutstandingDocuments() {
    final query = _db.customSelect(
      '''
      SELECT 'sale' AS source_table, s.id AS source_id,
             s.invoice_number AS reference_number, s.customer_id AS party_id,
             cu.name AS party_name, s.currency_id,
             c.code AS currency_code, c.symbol AS currency_symbol,
             (s.total_cents - s.paid_amount_cents - COALESCE((
               SELECT SUM(ci.amount_cents) FROM cheque_instruments ci
                WHERE ci.source_table = 'sale' AND ci.source_id = s.id
                  AND ci.status IN ('received','issued','deposited')
                  AND ci.settlement_payment_id IS NULL
             ), 0)) AS outstanding_cents
        FROM sales s
        JOIN currencies c ON c.id = s.currency_id
        LEFT JOIN customers cu ON cu.id = s.customer_id
       WHERE s.status = 'completed'
         AND (s.total_cents - s.paid_amount_cents - COALESCE((
               SELECT SUM(ci.amount_cents) FROM cheque_instruments ci
                WHERE ci.source_table = 'sale' AND ci.source_id = s.id
                  AND ci.status IN ('received','issued','deposited')
                  AND ci.settlement_payment_id IS NULL
             ), 0)) > 0
      UNION ALL
      SELECT 'purchase', p.id, p.purchase_number, p.supplier_id,
             sp.name, p.currency_id, c.code, c.symbol,
             (p.total_cents - p.paid_amount_cents - COALESCE((
               SELECT SUM(ci.amount_cents) FROM cheque_instruments ci
                WHERE ci.source_table = 'purchase' AND ci.source_id = p.id
                  AND ci.status IN ('received','issued','deposited')
                  AND ci.settlement_payment_id IS NULL
             ), 0))
        FROM purchases p
        JOIN currencies c ON c.id = p.currency_id
        LEFT JOIN suppliers sp ON sp.id = p.supplier_id
       WHERE p.status = 'posted'
         AND (p.total_cents - p.paid_amount_cents - COALESCE((
               SELECT SUM(ci.amount_cents) FROM cheque_instruments ci
                WHERE ci.source_table = 'purchase' AND ci.source_id = p.id
                  AND ci.status IN ('received','issued','deposited')
                  AND ci.settlement_payment_id IS NULL
             ), 0)) > 0
       ORDER BY reference_number
      ''',
      readsFrom: {
        _db.sales,
        _db.purchases,
        _db.currencies,
        _db.customers,
        _db.suppliers,
        _db.chequeInstruments,
      },
    );
    return query.watch().map(
      (rows) => rows
          .map(
            (row) => ChequeOutstandingDocument(
              sourceTable: row.read<String>('source_table'),
              sourceId: row.read<int>('source_id'),
              referenceNumber: row.read<String>('reference_number'),
              partyId: row.readNullable<int>('party_id'),
              partyName: row.readNullable<String>('party_name'),
              currencyId: row.read<int>('currency_id'),
              currencyCode: row.read<String>('currency_code'),
              currencySymbol: row.read<String>('currency_symbol'),
              outstandingCents: row.read<int>('outstanding_cents'),
            ),
          )
          .toList(growable: false),
    );
  }

  Future<int> createPartialCheque({
    required ChequeOutstandingDocument document,
    required int amountCents,
    required String chequeNumber,
    required DateTime issueDate,
    required DateTime dueDate,
    String? bankName,
    String? branchName,
    String? accountNumber,
    String? drawerName,
    String? note,
    int? userId,
  }) async {
    final number = chequeNumber.trim();
    if (number.isEmpty) throw ArgumentError('cheque_number_required');
    if (amountCents <= 0) throw ArgumentError('cheque_amount_invalid');
    if (document.partyId == null) {
      throw ArgumentError('cheque_party_required');
    }
    if (dueDate.isBefore(
      DateTime(issueDate.year, issueDate.month, issueDate.day),
    )) {
      throw ArgumentError('cheque_due_before_issue');
    }

    return _db.transaction(() async {
      final outstanding = await _currentUnallocatedOutstanding(
        document.sourceTable,
        document.sourceId,
      );
      if (amountCents > outstanding) {
        throw StateError('cheque_amount_exceeds_outstanding');
      }
      await _ensureNumberAvailable(
        direction: document.direction,
        chequeNumber: number,
        bankName: bankName,
        accountNumber: accountNumber,
      );

      final id = await _instrumentDao.create(
        direction: document.direction,
        sourceTable: document.sourceTable,
        sourceId: document.sourceId,
        amountCents: amountCents,
        currencyId: document.currencyId,
        dueDate: dueDate,
        issueDate: issueDate,
        partyType: document.sourceTable == ChequeSourceTables.sale
            ? 'customer'
            : 'supplier',
        partyId: document.partyId,
        chequeNumber: number,
        bankName: bankName,
        branchName: branchName,
        accountNumber: accountNumber,
        drawerName: drawerName,
        note: note,
        userId: userId,
      );
      await _audit.log(
        entityType: 'cheque_instrument',
        entityId: id,
        action: 'create_partial',
        newValue: {
          'sourceTable': document.sourceTable,
          'sourceId': document.sourceId,
          'amountCents': amountCents,
          'settlementPaymentId': null,
          'deferredUntilClearance': true,
          'chequeNumber': number,
        },
        userId: userId,
        severity: AuditSeverity.critical,
      );
      return id;
    });
  }

  Future<void> updateDetails({
    required ChequeRegisterEntry entry,
    required String chequeNumber,
    required DateTime issueDate,
    required DateTime dueDate,
    String? bankName,
    String? branchName,
    String? accountNumber,
    String? drawerName,
    String? note,
    int? userId,
  }) async {
    final number = chequeNumber.trim();
    if (number.isEmpty) throw ArgumentError('cheque_number_required');
    if (dueDate.isBefore(
      DateTime(issueDate.year, issueDate.month, issueDate.day),
    )) {
      throw ArgumentError('cheque_due_before_issue');
    }
    await _db.transaction(() async {
      await _ensureNumberAvailable(
        direction: entry.instrument.direction,
        chequeNumber: number,
        bankName: bankName,
        accountNumber: accountNumber,
        excludingId: entry.instrument.id,
      );
      await _instrumentDao.updateDetails(
        id: entry.instrument.id,
        chequeNumber: number,
        bankName: bankName,
        branchName: branchName,
        accountNumber: accountNumber,
        drawerName: drawerName,
        issueDate: issueDate,
        dueDate: dueDate,
        note: note,
        userId: userId,
      );
      await _audit.log(
        entityType: 'cheque_instrument',
        entityId: entry.instrument.id,
        action: 'update_details',
        oldValue: {
          'chequeNumber': entry.instrument.chequeNumber,
          'dueDate': entry.instrument.dueDate.toIso8601String(),
        },
        newValue: {
          'chequeNumber': number,
          'bankName': bankName,
          'dueDate': dueDate.toIso8601String(),
        },
        userId: userId,
      );
    });
  }

  Future<int> _currentOutstanding(String sourceTable, int sourceId) async {
    if (sourceTable == ChequeSourceTables.sale) {
      final sale = await _saleRepository.getSaleById(sourceId);
      if (sale == null) throw StateError('cheque_source_not_found');
      final value = sale.totalCents - sale.paidAmountCents;
      return value <= Decimal.zero ? 0 : value.toBigInt().toInt();
    }
    if (sourceTable == ChequeSourceTables.purchase) {
      final purchase = await _purchaseRepository.getPurchaseById(sourceId);
      if (purchase == null) throw StateError('cheque_source_not_found');
      final value = purchase.totalCents - purchase.paidAmountCents;
      return value <= Decimal.zero ? 0 : value.toBigInt().toInt();
    }
    throw ArgumentError.value(sourceTable, 'sourceTable');
  }

  Future<int> _currentUnallocatedOutstanding(
    String sourceTable,
    int sourceId,
  ) async {
    final outstanding = await _currentOutstanding(sourceTable, sourceId);
    // Linked instruments are already represented by invoice paid_amount. Only
    // legacy/open instruments without a payment link still reserve capacity.
    final row = await _db
        .customSelect(
          '''
      SELECT COALESCE(SUM(amount_cents), 0) AS allocated_cents
        FROM cheque_instruments
       WHERE source_table = ? AND source_id = ?
         AND status IN ('received','issued','deposited')
         AND settlement_payment_id IS NULL
      ''',
          variables: [
            Variable.withString(sourceTable),
            Variable.withInt(sourceId),
          ],
          readsFrom: {_db.chequeInstruments},
        )
        .getSingle();
    final available = outstanding - row.read<int>('allocated_cents');
    return available < 0 ? 0 : available;
  }

  Future<void> _ensureNumberAvailable({
    required String direction,
    required String chequeNumber,
    String? bankName,
    String? accountNumber,
    int? excludingId,
  }) async {
    final row = await _db
        .customSelect(
          '''
      SELECT id FROM cheque_instruments
       WHERE direction = ?
         AND lower(trim(cheque_number)) = lower(trim(?))
         AND lower(trim(COALESCE(bank_name, ''))) = lower(trim(?))
         AND lower(trim(COALESCE(account_number, ''))) = lower(trim(?))
         AND (? IS NULL OR id <> ?)
       LIMIT 1
      ''',
          variables: [
            Variable.withString(direction),
            Variable.withString(chequeNumber),
            Variable.withString(bankName ?? ''),
            Variable.withString(accountNumber ?? ''),
            excludingId == null
                ? const Variable<int>(null)
                : Variable.withInt(excludingId),
            excludingId == null
                ? const Variable<int>(null)
                : Variable.withInt(excludingId),
          ],
          readsFrom: {_db.chequeInstruments},
        )
        .getSingleOrNull();
    if (row != null) throw StateError('cheque_number_duplicate');
  }
}
