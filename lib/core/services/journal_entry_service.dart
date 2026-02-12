import '../../features/accounting/data/repositories/accounting_repository.dart';
import '../../features/accounting/domain/models/journal_entry_data.dart';

/// Lightweight service that creates journal entries as a side-effect
/// after sales, purchases, returns, and expenses are saved.
///
/// This does NOT replace or modify the existing transaction flows.
/// It is called after the record is already persisted, so failures
/// here do not break the core business logic.
class JournalEntryService {
  final AccountingRepository _accountingRepo;

  JournalEntryService(this._accountingRepo);

  /// Create journal entries for a completed sale.
  /// Debit: Cash/Receivables, Credit: Revenue
  Future<void> recordSaleJournalEntry({
    required int saleId,
    required int totalCents,
    required int paidAmountCents,
    required int currencyId,
  }) async {
    try {
      final cashAccount = await _accountingRepo.getAccountByCode('1000');
      final receivablesAccount = await _accountingRepo.getAccountByCode('1100');
      final revenueAccount = await _accountingRepo.getAccountByCode('4000');

      if (cashAccount == null || revenueAccount == null) return;

      // Cash portion
      if (paidAmountCents > 0) {
        await _accountingRepo.createJournalEntry(
          entryData: JournalEntryData.simple(
            description: 'Sale #$saleId - Cash Revenue',
            debitAccountId: cashAccount.id,
            creditAccountId: revenueAccount.id,
            amountCents: paidAmountCents,
            currencyId: currencyId,
            entryType: 'sale',
            sourceTable: 'sales',
            sourceId: saleId,
            autoPost: true,
          ),
          userId: null,
        );
      }

      // Credit portion (unpaid)
      final unpaid = totalCents - paidAmountCents;
      if (unpaid > 0 && receivablesAccount != null) {
        await _accountingRepo.createJournalEntry(
          entryData: JournalEntryData.simple(
            description: 'Sale #$saleId - Credit Revenue',
            debitAccountId: receivablesAccount.id,
            creditAccountId: revenueAccount.id,
            amountCents: unpaid,
            currencyId: currencyId,
            entryType: 'sale',
            sourceTable: 'sales',
            sourceId: saleId,
            autoPost: true,
          ),
          userId: null,
        );
      }
    } catch (_) {
      // Journal entry creation is best-effort; don't break the sale flow
    }
  }

  /// Create journal entries for a completed purchase.
  /// Debit: Inventory, Credit: Cash/Payables
  Future<void> recordPurchaseJournalEntry({
    required int purchaseId,
    required int totalCents,
    required int paidAmountCents,
    required int currencyId,
  }) async {
    try {
      final cashAccount = await _accountingRepo.getAccountByCode('1000');
      final payablesAccount = await _accountingRepo.getAccountByCode('2000');
      final inventoryAccount = await _accountingRepo.getAccountByCode('1200');

      if (inventoryAccount == null) return;

      // Paid portion
      if (paidAmountCents > 0 && cashAccount != null) {
        await _accountingRepo.createJournalEntry(
          entryData: JournalEntryData.simple(
            description: 'Purchase #$purchaseId - Cash',
            debitAccountId: inventoryAccount.id,
            creditAccountId: cashAccount.id,
            amountCents: paidAmountCents,
            currencyId: currencyId,
            entryType: 'purchase',
            sourceTable: 'purchases',
            sourceId: purchaseId,
            autoPost: true,
          ),
          userId: null,
        );
      }

      // Unpaid portion
      final unpaid = totalCents - paidAmountCents;
      if (unpaid > 0 && payablesAccount != null) {
        await _accountingRepo.createJournalEntry(
          entryData: JournalEntryData.simple(
            description: 'Purchase #$purchaseId - Credit',
            debitAccountId: inventoryAccount.id,
            creditAccountId: payablesAccount.id,
            amountCents: unpaid,
            currencyId: currencyId,
            entryType: 'purchase',
            sourceTable: 'purchases',
            sourceId: purchaseId,
            autoPost: true,
          ),
          userId: null,
        );
      }
    } catch (_) {
      // Best-effort
    }
  }

  /// Create journal entries for a posted sale return.
  /// Debit: Revenue, Credit: Cash (refund)
  Future<void> recordSaleReturnJournalEntry({
    required int returnId,
    required int totalCents,
    required int currencyId,
  }) async {
    try {
      final cashAccount = await _accountingRepo.getAccountByCode('1000');
      final revenueAccount = await _accountingRepo.getAccountByCode('4000');

      if (cashAccount == null || revenueAccount == null) return;

      await _accountingRepo.createJournalEntry(
        entryData: JournalEntryData.simple(
          description: 'Sale Return #$returnId',
          debitAccountId: revenueAccount.id,
          creditAccountId: cashAccount.id,
          amountCents: totalCents,
          currencyId: currencyId,
          entryType: 'saleReturn',
          sourceTable: 'sale_returns',
          sourceId: returnId,
          autoPost: true,
        ),
        userId: null,
      );
    } catch (_) {
      // Best-effort
    }
  }

  /// Create journal entries for a posted purchase return.
  /// Debit: Cash, Credit: Inventory
  Future<void> recordPurchaseReturnJournalEntry({
    required int returnId,
    required int totalCents,
    required int currencyId,
  }) async {
    try {
      final cashAccount = await _accountingRepo.getAccountByCode('1000');
      final inventoryAccount = await _accountingRepo.getAccountByCode('1200');

      if (cashAccount == null || inventoryAccount == null) return;

      await _accountingRepo.createJournalEntry(
        entryData: JournalEntryData.simple(
          description: 'Purchase Return #$returnId',
          debitAccountId: cashAccount.id,
          creditAccountId: inventoryAccount.id,
          amountCents: totalCents,
          currencyId: currencyId,
          entryType: 'purchaseReturn',
          sourceTable: 'purchase_returns',
          sourceId: returnId,
          autoPost: true,
        ),
        userId: null,
      );
    } catch (_) {
      // Best-effort
    }
  }
}
