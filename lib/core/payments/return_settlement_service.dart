import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../database/daos/cheque_confirmation_dao.dart';
import '../database/daos/cheque_instrument_dao.dart';
import '../services/balance_service.dart';
import '../services/journal_entry_service.dart';
import 'checkout_settlement.dart';

enum ReturnSettlementSide { sale, purchase }

/// Posts and reverses structured return settlements.
///
/// A return cheque remains a pending instrument and leaves the matching party
/// obligation open. It is recognized as a payment only when bank clearance is
/// confirmed by ChequeLifecycleService.
class ReturnSettlementService {
  ReturnSettlementService._();

  static const _immediatePrefix = 'return_settlement_';

  static Future<void> apply({
    required AppDatabase db,
    required JournalEntryService journalService,
    required ReturnSettlementSide side,
    required String sourceTable,
    required int sourceId,
    required int partyId,
    required int totalCents,
    required int currencyId,
    required List<CheckoutPaymentAllocation> allocations,
    required DateTime documentDate,
    int? userId,
  }) async {
    final settlement = CheckoutSettlement(allocations);
    settlement.validate(invoiceTotalCents: totalCents);
    _validateSource(side, sourceTable);
    // Validate every immediate channel before the first insert. Although all
    // production callers wrap this service in a transaction, this keeps the
    // service itself fail-fast and prevents partial writes for future callers.
    for (final allocation in allocations) {
      if (!allocation.isCheque) _normalizeImmediateMethod(allocation.method);
    }
    final accessor = ChequeInstrumentDao(db);

    for (final allocation in allocations) {
      if (allocation.isCheque) {
        await accessor.create(
          direction: side == ReturnSettlementSide.sale
              ? ChequeDirectionValue.outgoing
              : ChequeDirectionValue.incoming,
          sourceTable: sourceTable,
          sourceId: sourceId,
          amountCents: allocation.amountCents,
          currencyId: currencyId,
          dueDate: allocation.dueDate!,
          partyType: side == ReturnSettlementSide.sale
              ? 'customer'
              : 'supplier',
          partyId: partyId,
          chequeNumber: allocation.reference,
          bankName: allocation.bankName,
          issueDate: allocation.issueDate ?? documentDate,
          note: allocation.note,
          userId: userId,
        );
        continue;
      }

      final method = _normalizeImmediateMethod(allocation.method);
      final description = _description(
        side: side,
        sourceTable: sourceTable,
        sourceId: sourceId,
        method: method,
        bankName: allocation.bankName,
        note: allocation.note,
      );
      if (side == ReturnSettlementSide.sale) {
        final transactionId = await db
            .into(db.customerTransactions)
            .insert(
              CustomerTransactionsCompanion.insert(
                customerId: partyId,
                transactionType: '$_immediatePrefix$method',
                transactionNumber: Value(_blankToNull(allocation.reference)),
                amountCents: Decimal.fromInt(allocation.amountCents),
                currencyId: currencyId,
                description: Value(description),
                referenceId: Value(sourceId),
                referenceType: Value(sourceTable),
                transactionDate: Value(allocation.issueDate ?? documentDate),
              ),
            );
        await BalanceService.adjustCustomerBalance(
          accessor,
          customerId: partyId,
          deltaCents: allocation.amountCents,
        );
        await journalService.recordSaleReturnSettlementJournalEntry(
          transactionId: transactionId,
          amountCents: allocation.amountCents,
          currencyId: currencyId,
          paymentMethod: method,
          userId: userId,
        );
      } else {
        final transactionId = await db
            .into(db.supplierTransactions)
            .insert(
              SupplierTransactionsCompanion.insert(
                supplierId: partyId,
                transactionType: '$_immediatePrefix$method',
                transactionNumber: Value(_blankToNull(allocation.reference)),
                amountCents: Decimal.fromInt(allocation.amountCents),
                currencyId: currencyId,
                description: Value(description),
                referenceId: Value(sourceId),
                referenceType: Value(sourceTable),
                transactionDate: Value(allocation.issueDate ?? documentDate),
              ),
            );
        await BalanceService.adjustSupplierBalance(
          accessor,
          supplierId: partyId,
          deltaCents: allocation.amountCents,
        );
        await journalService.recordPurchaseReturnSettlementJournalEntry(
          transactionId: transactionId,
          amountCents: allocation.amountCents,
          currencyId: currencyId,
          paymentMethod: method,
          userId: userId,
        );
      }
    }
  }

  /// Reverses immediate settlement legs. Physical cheque legs are reversed by
  /// ChequeSourceVoidService, so each lifecycle has one authoritative owner.
  static Future<void> voidImmediate({
    required AppDatabase db,
    required JournalEntryService journalService,
    required ReturnSettlementSide side,
    required String sourceTable,
    required int sourceId,
    required String reason,
    int? userId,
  }) async {
    _validateSource(side, sourceTable);
    final partyTable = side == ReturnSettlementSide.sale
        ? 'customer_transactions'
        : 'supplier_transactions';
    final partyColumn = side == ReturnSettlementSide.sale
        ? 'customer_id'
        : 'supplier_id';
    final rows = await db
        .customSelect(
          'SELECT id, $partyColumn AS party_id, amount_cents, currency_id '
          'FROM $partyTable '
          'WHERE reference_type = ? AND reference_id = ? '
          "AND transaction_type LIKE 'return_settlement_%'",
          variables: [
            Variable.withString(sourceTable),
            Variable.withInt(sourceId),
          ],
        )
        .get();
    final accessor = ChequeInstrumentDao(db);
    for (final row in rows) {
      final transactionId = row.read<int>('id');
      final partyId = row.read<int>('party_id');
      final amount = row.read<int>('amount_cents');
      final currencyId = row.read<int>('currency_id');
      final alreadyReversed = await db
          .customSelect(
            'SELECT COUNT(*) AS c FROM $partyTable '
            "WHERE transaction_type = 'return_settlement_void' "
            "AND reference_type = 'return_settlement_transaction' "
            'AND reference_id = ?',
            variables: [Variable.withInt(transactionId)],
          )
          .getSingle();
      if (alreadyReversed.read<int>('c') > 0) continue;

      if (side == ReturnSettlementSide.sale) {
        await db
            .into(db.customerTransactions)
            .insert(
              CustomerTransactionsCompanion.insert(
                customerId: partyId,
                transactionType: 'return_settlement_void',
                amountCents: Decimal.fromInt(-amount),
                currencyId: currencyId,
                description: Value(reason),
                referenceId: Value(transactionId),
                referenceType: const Value('return_settlement_transaction'),
              ),
            );
        await BalanceService.adjustCustomerBalance(
          accessor,
          customerId: partyId,
          deltaCents: -amount,
        );
      } else {
        await db
            .into(db.supplierTransactions)
            .insert(
              SupplierTransactionsCompanion.insert(
                supplierId: partyId,
                transactionType: 'return_settlement_void',
                amountCents: Decimal.fromInt(-amount),
                currencyId: currencyId,
                description: Value(reason),
                referenceId: Value(transactionId),
                referenceType: const Value('return_settlement_transaction'),
              ),
            );
        await BalanceService.adjustSupplierBalance(
          accessor,
          supplierId: partyId,
          deltaCents: -amount,
        );
      }
      await journalService.voidJournalEntriesForSource(
        sourceTable: partyTable,
        sourceId: transactionId,
        reason: reason,
        userId: userId,
      );
    }
  }

  static String _normalizeImmediateMethod(String raw) {
    final value = raw.trim().toLowerCase();
    if (value == 'cash' ||
        value == 'card' ||
        value == 'bank_transfer' ||
        value == 'bank' ||
        value == 'mobile') {
      return value == 'bank' ? 'bank_transfer' : value;
    }
    throw ArgumentError.value(raw, 'paymentMethod', 'Unsupported method');
  }

  static void _validateSource(ReturnSettlementSide side, String source) {
    final valid = side == ReturnSettlementSide.sale
        ? source == ChequeSourceTables.saleReturn ||
              source == ChequeSourceTables.saleReturnAdjustment
        : source == ChequeSourceTables.purchaseReturn ||
              source == ChequeSourceTables.purchaseReturnAdjustment;
    if (!valid) throw ArgumentError.value(source, 'sourceTable');
  }

  static String _description({
    required ReturnSettlementSide side,
    required String sourceTable,
    required int sourceId,
    required String method,
    String? bankName,
    String? note,
  }) {
    final parts = <String>[
      '${side.name} return settlement ($method) for $sourceTable#$sourceId',
      if (_blankToNull(bankName) case final bank?) 'bank=$bank',
      ?_blankToNull(note),
    ];
    return parts.join(' · ');
  }

  static String? _blankToNull(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}
