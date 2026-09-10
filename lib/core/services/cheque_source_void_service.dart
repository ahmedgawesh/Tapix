import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../database/daos/cheque_confirmation_dao.dart';
import '../database/daos/cheque_instrument_dao.dart';
import 'balance_service.dart';
import 'journal_entry_service.dart';

/// Reverses every cheque-lifecycle side effect when its source document is
/// voided. This is intentionally independent from the sale/purchase
/// repositories so linked and adjustment returns share exactly one policy.
class ChequeSourceVoidService {
  ChequeSourceVoidService._();

  static Future<void> voidForSource({
    required AppDatabase db,
    required JournalEntryService journalService,
    required String sourceTable,
    required int sourceId,
    required String reason,
    int? userId,
  }) async {
    if (!ChequeSourceTables.all.contains(sourceTable)) return;

    await db.transaction(() async {
      final dao = ChequeInstrumentDao(db);
      final instruments = await dao.getBySource(
        sourceTable: sourceTable,
        sourceId: sourceId,
      );

      for (final cheque in instruments) {
        await journalService.voidJournalEntriesForSource(
          sourceTable: 'cheque_instruments',
          sourceId: cheque.id,
          reason: reason,
          userId: userId,
        );

        if (_isReturnSource(sourceTable) &&
            cheque.settlementPaymentId != null) {
          await _reverseReturnSettlementSubledger(db, dao, cheque, sourceTable);
        }

        // A failed cheque may have reopened a customer/supplier obligation.
        // Voiding its source must remove that reopening from the sub-ledger as
        // well as reversing its GL journal entry.
        if (cheque.dishonourJournalEntryId != null) {
          await _reverseFailedPartySubledger(db, dao, cheque, sourceTable);
        }
        if (cheque.resolvedAt != null) {
          await _reverseResolutionPartySubledger(db, dao, cheque, sourceTable);
        }

        await dao.writeLifecycle(
          id: cheque.id,
          status: ChequeInstrumentStatus.cancelled,
          clearSettlementPaymentId: true,
          clearClearanceJournalEntryId: true,
          clearDishonourJournalEntryId: true,
          userId: userId,
        );
      }
    });
  }

  static bool _isReturnSource(String sourceTable) =>
      sourceTable == ChequeSourceTables.saleReturn ||
      sourceTable == ChequeSourceTables.purchaseReturn ||
      sourceTable == ChequeSourceTables.saleReturnAdjustment ||
      sourceTable == ChequeSourceTables.purchaseReturnAdjustment;

  static Future<void> _reverseReturnSettlementSubledger(
    AppDatabase db,
    ChequeInstrumentDao dao,
    ChequeInstrument cheque,
    String sourceTable,
  ) async {
    final partyId = cheque.partyId;
    if (partyId == null) return;
    final saleSide =
        sourceTable == ChequeSourceTables.saleReturn ||
        sourceTable == ChequeSourceTables.saleReturnAdjustment;
    final table = saleSide ? 'customer_transactions' : 'supplier_transactions';
    final partyColumn = saleSide ? 'customer_id' : 'supplier_id';
    final original = await db
        .customSelect(
          'SELECT COUNT(*) AS c FROM $table '
          'WHERE $partyColumn = ? AND reference_type = ? AND reference_id = ? '
          'AND transaction_type = ?',
          variables: [
            Variable.withInt(partyId),
            Variable.withString('cheque_instrument'),
            Variable.withInt(cheque.id),
            Variable.withString('cheque_return_settlement'),
          ],
        )
        .getSingle();
    if (original.read<int>('c') == 0) return;
    final existing = await db
        .customSelect(
          'SELECT COUNT(*) AS c FROM $table '
          'WHERE $partyColumn = ? AND reference_type = ? AND reference_id = ? '
          'AND transaction_type IN (?, ?)',
          variables: [
            Variable.withInt(partyId),
            Variable.withString('cheque_instrument'),
            Variable.withInt(cheque.id),
            Variable.withString('cheque_return_settlement_reversal'),
            Variable.withString('cheque_return_settlement_void'),
          ],
        )
        .getSingle();
    if (existing.read<int>('c') > 0) return;
    final amount = cheque.amountCents.toBigInt().toInt();
    if (saleSide) {
      await db
          .into(db.customerTransactions)
          .insert(
            CustomerTransactionsCompanion.insert(
              customerId: partyId,
              transactionType: 'cheque_return_settlement_void',
              amountCents: Decimal.fromInt(-amount),
              currencyId: cheque.currencyId,
              description: Value(
                'Voided return cheque #${cheque.id} settlement',
              ),
              referenceId: Value(cheque.id),
              referenceType: const Value('cheque_instrument'),
            ),
          );
      await BalanceService.adjustCustomerBalance(
        dao,
        customerId: partyId,
        deltaCents: -amount,
      );
      return;
    }
    await db
        .into(db.supplierTransactions)
        .insert(
          SupplierTransactionsCompanion.insert(
            supplierId: partyId,
            transactionType: 'cheque_return_settlement_void',
            amountCents: Decimal.fromInt(-amount),
            currencyId: cheque.currencyId,
            description: Value('Voided return cheque #${cheque.id} settlement'),
            referenceId: Value(cheque.id),
            referenceType: const Value('cheque_instrument'),
          ),
        );
    await BalanceService.adjustSupplierBalance(
      dao,
      supplierId: partyId,
      deltaCents: -amount,
    );
  }

  static Future<void> _reverseFailedPartySubledger(
    AppDatabase db,
    ChequeInstrumentDao dao,
    ChequeInstrument cheque,
    String sourceTable,
  ) async {
    final partyId = cheque.partyId;
    if (partyId == null) return;
    final saleSide =
        sourceTable == ChequeSourceTables.sale ||
        sourceTable == ChequeSourceTables.saleReturn ||
        sourceTable == ChequeSourceTables.saleReturnAdjustment;
    final table = saleSide ? 'customer_transactions' : 'supplier_transactions';
    final partyColumn = saleSide ? 'customer_id' : 'supplier_id';
    final row = await db
        .customSelect(
          'SELECT COALESCE(SUM(amount_cents), 0) AS total FROM $table WHERE $partyColumn = ? AND transaction_type = ? AND reference_type = ? AND reference_id = ?',
          variables: [
            Variable.withInt(partyId),
            Variable.withString('cheque_dishonour'),
            Variable.withString('cheque_instrument'),
            Variable.withInt(cheque.id),
          ],
        )
        .getSingle();
    final originalDelta = row.read<int>('total');
    if (originalDelta == 0) return;
    final reversalDelta = -originalDelta;

    if (saleSide) {
      await db
          .into(db.customerTransactions)
          .insert(
            CustomerTransactionsCompanion.insert(
              customerId: partyId,
              transactionType: 'cheque_dishonour_reversal',
              amountCents: Decimal.fromInt(reversalDelta),
              currencyId: cheque.currencyId,
              description: Value('Voided cheque #${cheque.id}'),
              referenceId: Value(cheque.id),
              referenceType: const Value('cheque_instrument'),
            ),
          );
      await BalanceService.adjustCustomerBalance(
        dao,
        customerId: partyId,
        deltaCents: reversalDelta,
      );
      return;
    }

    await db
        .into(db.supplierTransactions)
        .insert(
          SupplierTransactionsCompanion.insert(
            supplierId: partyId,
            transactionType: 'cheque_dishonour_reversal',
            amountCents: Decimal.fromInt(reversalDelta),
            currencyId: cheque.currencyId,
            description: Value('Voided cheque #${cheque.id}'),
            referenceId: Value(cheque.id),
            referenceType: const Value('cheque_instrument'),
          ),
        );
    await BalanceService.adjustSupplierBalance(
      dao,
      supplierId: partyId,
      deltaCents: reversalDelta,
    );
  }

  static Future<void> _reverseResolutionPartySubledger(
    AppDatabase db,
    ChequeInstrumentDao dao,
    ChequeInstrument cheque,
    String sourceTable,
  ) async {
    final partyId = cheque.partyId;
    if (partyId == null) return;
    final saleSide =
        sourceTable == ChequeSourceTables.sale ||
        sourceTable == ChequeSourceTables.saleReturn ||
        sourceTable == ChequeSourceTables.saleReturnAdjustment;
    final table = saleSide ? 'customer_transactions' : 'supplier_transactions';
    final partyColumn = saleSide ? 'customer_id' : 'supplier_id';
    final row = await db
        .customSelect(
          'SELECT COALESCE(SUM(amount_cents), 0) AS total FROM $table '
          'WHERE $partyColumn = ? AND transaction_type = ? '
          'AND reference_type = ? AND reference_id = ?',
          variables: [
            Variable.withInt(partyId),
            Variable.withString('cheque_dishonour_resolution'),
            Variable.withString('cheque_instrument'),
            Variable.withInt(cheque.id),
          ],
        )
        .getSingle();
    final originalDelta = row.read<int>('total');
    if (originalDelta == 0) return;
    final alreadyReversed = await db
        .customSelect(
          'SELECT COUNT(*) AS c FROM $table WHERE $partyColumn = ? '
          'AND transaction_type = ? AND reference_type = ? AND reference_id = ?',
          variables: [
            Variable.withInt(partyId),
            Variable.withString('cheque_dishonour_resolution_reversal'),
            Variable.withString('cheque_instrument'),
            Variable.withInt(cheque.id),
          ],
        )
        .getSingle();
    if (alreadyReversed.read<int>('c') > 0) return;
    final reversalDelta = -originalDelta;
    if (saleSide) {
      await db
          .into(db.customerTransactions)
          .insert(
            CustomerTransactionsCompanion.insert(
              customerId: partyId,
              transactionType: 'cheque_dishonour_resolution_reversal',
              amountCents: Decimal.fromInt(reversalDelta),
              currencyId: cheque.currencyId,
              description: Value('Voided cheque #${cheque.id} resolution'),
              referenceId: Value(cheque.id),
              referenceType: const Value('cheque_instrument'),
            ),
          );
      await BalanceService.adjustCustomerBalance(
        dao,
        customerId: partyId,
        deltaCents: reversalDelta,
      );
      return;
    }
    await db
        .into(db.supplierTransactions)
        .insert(
          SupplierTransactionsCompanion.insert(
            supplierId: partyId,
            transactionType: 'cheque_dishonour_resolution_reversal',
            amountCents: Decimal.fromInt(reversalDelta),
            currencyId: cheque.currencyId,
            description: Value('Voided cheque #${cheque.id} resolution'),
            referenceId: Value(cheque.id),
            referenceType: const Value('cheque_instrument'),
          ),
        );
    await BalanceService.adjustSupplierBalance(
      dao,
      supplierId: partyId,
      deltaCents: reversalDelta,
    );
  }
}
