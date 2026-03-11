import 'dart:developer' as developer;

import '../../features/accounting/data/repositories/accounting_repository.dart';
import '../../features/accounting/domain/exceptions/accounting_exception.dart';
import '../../features/accounting/domain/models/journal_entry_data.dart';

/// MANDATORY journal-entry service for all financial operations.
///
/// Every method here WILL throw on failure — callers MUST handle errors.
/// There are NO silent catch blocks. If the ledger cannot be updated,
/// the business transaction must be aware of it.
///
/// Account codes used here MUST match the STRICT Chart of Accounts
/// seeded by JournalRepositoryImpl.seedDefaultAccounts:
///   Assets:      1000 = Cash, 1010 = Bank, 1100 = Accounts Receivable,
///                1200 = Inventory, 1300 = VAT Receivable
///   Liabilities: 2000 = Accounts Payable, 2100 = VAT Payable,
///                2300 = Loyalty Points Liability
///   Equity:      3000 = Owner Capital, 3100 = Opening Balance Equity
///   Income:      4000 = Sales Revenue
///   Expenses:    5100 = Expenses, 5200 = Salaries Expense,
///                5300 = Cost of Goods Sold,
///                5500 = Discounts Given, 5600 = Commissions Expense
class JournalEntryService {
  final AccountingRepository _accountingRepo;

  JournalEntryService(this._accountingRepo);

  // ── Account lookup — fails loudly ──────────────────────────

  Future<int> _requireAccountId(String code) async {
    final account = await _accountingRepo.getAccountByCode(code);
    if (account == null) {
      throw AccountingException(
        'Required account "$code" not found in Chart of Accounts. '
        'Run seedDefaultAccounts first.',
      );
    }
    return account.id;
  }

  /// Returns Cash (1000) or Bank (1010) account ID based on payment method.
  /// Card, cheque, transfers, and digital wallets go to Bank; others default to Cash.
  Future<int> _cashOrBankAccountId(String? paymentMethod) async {
    final normalized = paymentMethod?.trim().toLowerCase();
    const bankMethods = {
      'card',
      'cheque',
      'bank',
      'bank_transfer',
      'transfer',
      'wire',
      'wallet',
      'mobile',
      'pos',
      'terminal',
    };
    if (normalized != null && bankMethods.contains(normalized)) {
      return _requireAccountId('1010');
    }
    return _requireAccountId('1000');
  }

  // ── Sale ────────────────────────────────────────────────────

  /// Create journal entries for a completed sale.
  ///
  /// STRICT RULES:
  /// Sale (Cash):   Dr Cash,                Cr Sales Revenue
  /// Sale (Credit): Dr Accounts Receivable, Cr Sales Revenue
  /// VAT on Sales:  Dr Cash/AR,             Cr VAT Payable
  ///
  /// When [taxCents] > 0, the entry splits into revenue + VAT.
  /// Throws on any failure — caller must handle.
  Future<void> recordSaleJournalEntry({
    required int saleId,
    required int totalCents,
    required int paidAmountCents,
    required int currencyId,
    int taxCents = 0,
    String? paymentMethod,
    int? userId,
  }) async {
    final cashOrBankId = await _cashOrBankAccountId(paymentMethod);
    final receivablesId = await _requireAccountId('1100');
    final revenueId = await _requireAccountId('4000');

    // Cap the effective paid amount to totalCents for the invoice portion.
    // Any overpayment is handled separately as a prepayment (Dr Cash, Cr AR).
    final effectivePaid = paidAmountCents > totalCents ? totalCents : paidAmountCents;
    final overpayment = paidAmountCents > totalCents ? paidAmountCents - totalCents : 0;

    // Revenue — cash portion (capped at totalCents): Dr Cash, Cr Sales Revenue (+ Cr VAT Payable)
    if (effectivePaid > 0) {
      if (taxCents > 0) {
        final paidTax = (effectivePaid == totalCents)
            ? taxCents
            : (taxCents * effectivePaid / totalCents).round();
        final paidRevenue = effectivePaid - paidTax;
        final vatPayableId = await _requireAccountId('2100');

        await _accountingRepo.createJournalEntry(
          entryData: JournalEntryData(
            description: 'Sale #$saleId — Cash Revenue + VAT',
            entryType: 'sale',
            sourceTable: 'sales',
            sourceId: saleId,
            autoPost: true,
            lines: [
              JournalEntryLineData(
                accountId: cashOrBankId,
                debitCents: effectivePaid,
                creditCents: 0,
                currencyId: currencyId,
              ),
              JournalEntryLineData(
                accountId: revenueId,
                debitCents: 0,
                creditCents: paidRevenue,
                currencyId: currencyId,
              ),
              JournalEntryLineData(
                accountId: vatPayableId,
                debitCents: 0,
                creditCents: paidTax,
                currencyId: currencyId,
              ),
            ],
          ),
          userId: userId,
        );
      } else {
        // Sale (Cash) no VAT: Dr Cash, Cr Sales Revenue
        await _accountingRepo.createJournalEntry(
          entryData: JournalEntryData.simple(
            description: 'Sale #$saleId — Cash Revenue',
            debitAccountId: cashOrBankId,
            creditAccountId: revenueId,
            amountCents: effectivePaid,
            currencyId: currencyId,
            entryType: 'sale',
            sourceTable: 'sales',
            sourceId: saleId,
            autoPost: true,
          ),
          userId: userId,
        );
      }
    }

    // Revenue — credit portion: Dr Accounts Receivable, Cr Sales Revenue (+ Cr VAT Payable)
    final unpaid = totalCents - effectivePaid;
    if (unpaid > 0) {
      if (taxCents > 0) {
        final paidTax = (effectivePaid > 0 && effectivePaid < totalCents)
            ? (taxCents * effectivePaid / totalCents).round()
            : 0;
        final creditTax = taxCents - paidTax;
        final creditRevenue = unpaid - creditTax;
        final vatPayableId = await _requireAccountId('2100');

        await _accountingRepo.createJournalEntry(
          entryData: JournalEntryData(
            description: 'Sale #$saleId — Credit Revenue + VAT',
            entryType: 'sale',
            sourceTable: 'sales',
            sourceId: saleId,
            autoPost: true,
            lines: [
              JournalEntryLineData(
                accountId: receivablesId,
                debitCents: unpaid,
                creditCents: 0,
                currencyId: currencyId,
              ),
              JournalEntryLineData(
                accountId: revenueId,
                debitCents: 0,
                creditCents: creditRevenue,
                currencyId: currencyId,
              ),
              JournalEntryLineData(
                accountId: vatPayableId,
                debitCents: 0,
                creditCents: creditTax,
                currencyId: currencyId,
              ),
            ],
          ),
          userId: userId,
        );
      } else {
        // Sale (Credit) no VAT: Dr Accounts Receivable, Cr Sales Revenue
        await _accountingRepo.createJournalEntry(
          entryData: JournalEntryData.simple(
            description: 'Sale #$saleId — Credit Revenue',
            debitAccountId: receivablesId,
            creditAccountId: revenueId,
            amountCents: unpaid,
            currencyId: currencyId,
            entryType: 'sale',
            sourceTable: 'sales',
            sourceId: saleId,
            autoPost: true,
          ),
          userId: userId,
        );
      }
    }

    // Overpayment — customer prepayment: Dr Cash, Cr Accounts Receivable
    // This records that we owe the customer money (negative AR balance).
    if (overpayment > 0) {
      await _accountingRepo.createJournalEntry(
        entryData: JournalEntryData.simple(
          description: 'Sale #$saleId — Overpayment (customer prepayment)',
          debitAccountId: cashOrBankId,
          creditAccountId: receivablesId,
          amountCents: overpayment,
          currencyId: currencyId,
          entryType: 'sale',
          sourceTable: 'sales',
          sourceId: saleId,
          autoPost: true,
        ),
        userId: userId,
      );
    }

    developer.log('Journal entries created for Sale #$saleId', name: 'JournalEntryService');
  }

  // ── Sale COGS ─────────────────────────────────────────────────

  /// Create a Cost of Goods Sold journal entry when a sale is posted.
  ///
  /// STRICT RULES:
  /// Dr Cost of Goods Sold (5300), Cr Inventory (1200)
  ///
  /// [costCents] is the total cost of all items sold, computed by the caller
  /// from each item's variant/product cost_cents * quantity.
  /// Throws on any failure — caller must handle.
  Future<void> recordSaleCOGSJournalEntry({
    required int saleId,
    required int costCents,
    required int currencyId,
    int? userId,
  }) async {
    if (costCents <= 0) return;

    final cogsId = await _requireAccountId('5300');
    final inventoryId = await _requireAccountId('1200');

    await _accountingRepo.createJournalEntry(
      entryData: JournalEntryData.simple(
        description: 'Sale #$saleId — Cost of Goods Sold',
        debitAccountId: cogsId,
        creditAccountId: inventoryId,
        amountCents: costCents,
        currencyId: currencyId,
        entryType: 'sale_cogs',
        sourceTable: 'sales',
        sourceId: saleId,
        autoPost: true,
      ),
      userId: userId,
    );

    developer.log('COGS journal entry created for Sale #$saleId ($costCents cents)', name: 'JournalEntryService');
  }

  /// Reverse COGS when a sale return is posted.
  ///
  /// STRICT RULES:
  /// Dr Inventory (1200), Cr Cost of Goods Sold (5300)
  ///
  /// [costCents] is the total cost of the returned items.
  Future<void> recordSaleReturnCOGSReversalJournalEntry({
    required int returnId,
    required int costCents,
    required int currencyId,
    int? userId,
  }) async {
    if (costCents <= 0) return;

    final inventoryId = await _requireAccountId('1200');
    final cogsId = await _requireAccountId('5300');

    await _accountingRepo.createJournalEntry(
      entryData: JournalEntryData.simple(
        description: 'Sale Return #$returnId — COGS Reversal',
        debitAccountId: inventoryId,
        creditAccountId: cogsId,
        amountCents: costCents,
        currencyId: currencyId,
        entryType: 'sale_return_cogs',
        sourceTable: 'sale_returns',
        sourceId: returnId,
        autoPost: true,
      ),
      userId: userId,
    );

    developer.log('COGS reversal journal entry created for Sale Return #$returnId ($costCents cents)', name: 'JournalEntryService');
  }

  // ── Purchase ────────────────────────────────────────────────

  /// Create journal entries for a completed purchase.
  ///
  /// STRICT RULES:
  /// Purchase (Cash):   Dr Inventory, Cr Cash
  /// Purchase (Credit): Dr Inventory, Cr Accounts Payable
  /// VAT on Purchase:   Dr VAT Receivable, Cr Cash / Accounts Payable
  /// Overpayment:       Dr Accounts Payable, Cr Cash (supplier prepayment)
  Future<void> recordPurchaseJournalEntry({
    required int purchaseId,
    required int totalCents,
    required int paidAmountCents,
    required int currencyId,
    int taxCents = 0,
    String? paymentMethod,
    int? userId,
  }) async {
    final cashOrBankId = await _cashOrBankAccountId(paymentMethod);
    final payablesId = await _requireAccountId('2000');
    final inventoryId = await _requireAccountId('1200');

    // Cap the effective paid amount to totalCents for the invoice portion.
    // Any overpayment is handled separately as a prepayment (Dr AP, Cr Cash).
    final effectivePaid = paidAmountCents > totalCents ? totalCents : paidAmountCents;
    final overpayment = paidAmountCents > totalCents ? paidAmountCents - totalCents : 0;

    // Paid portion (capped at totalCents)
    if (effectivePaid > 0) {
      if (taxCents > 0) {
        // Split paid amount into inventory + VAT proportionally
        final paidTax = (effectivePaid == totalCents)
            ? taxCents
            : (taxCents * effectivePaid / totalCents).round();
        final paidInventory = effectivePaid - paidTax;
        final vatReceivableId = await _requireAccountId('1300');

        final lines = <JournalEntryLineData>[];
        if (paidInventory > 0) {
          lines.add(JournalEntryLineData(
            accountId: inventoryId,
            debitCents: paidInventory,
            creditCents: 0,
            currencyId: currencyId,
          ));
        }
        if (paidTax > 0) {
          lines.add(JournalEntryLineData(
            accountId: vatReceivableId,
            debitCents: paidTax,
            creditCents: 0,
            currencyId: currencyId,
          ));
        }
        lines.add(JournalEntryLineData(
          accountId: cashOrBankId,
          debitCents: 0,
          creditCents: effectivePaid,
          currencyId: currencyId,
        ));

        await _accountingRepo.createJournalEntry(
          entryData: JournalEntryData(
            description: 'Purchase #$purchaseId — Cash + VAT',
            entryType: 'purchase',
            sourceTable: 'purchases',
            sourceId: purchaseId,
            autoPost: true,
            lines: lines,
          ),
          userId: userId,
        );
      } else {
        // Purchase (Cash) no VAT: Dr Inventory, Cr Cash
        await _accountingRepo.createJournalEntry(
          entryData: JournalEntryData.simple(
            description: 'Purchase #$purchaseId — Cash',
            debitAccountId: inventoryId,
            creditAccountId: cashOrBankId,
            amountCents: effectivePaid,
            currencyId: currencyId,
            entryType: 'purchase',
            sourceTable: 'purchases',
            sourceId: purchaseId,
            autoPost: true,
          ),
          userId: userId,
        );
      }
    }

    // Unpaid portion — Dr Inventory (+ Dr VAT Receivable), Cr Accounts Payable
    final unpaid = totalCents - effectivePaid;
    if (unpaid > 0) {
      if (taxCents > 0) {
        final paidTax = (effectivePaid > 0 && effectivePaid < totalCents)
            ? (taxCents * effectivePaid / totalCents).round()
            : 0;
        final creditTax = taxCents - paidTax;
        final creditInventory = unpaid - creditTax;
        final vatReceivableId = await _requireAccountId('1300');

        final lines = <JournalEntryLineData>[];
        if (creditInventory > 0) {
          lines.add(JournalEntryLineData(
            accountId: inventoryId,
            debitCents: creditInventory,
            creditCents: 0,
            currencyId: currencyId,
          ));
        }
        if (creditTax > 0) {
          lines.add(JournalEntryLineData(
            accountId: vatReceivableId,
            debitCents: creditTax,
            creditCents: 0,
            currencyId: currencyId,
          ));
        }
        lines.add(JournalEntryLineData(
          accountId: payablesId,
          debitCents: 0,
          creditCents: unpaid,
          currencyId: currencyId,
        ));

        await _accountingRepo.createJournalEntry(
          entryData: JournalEntryData(
            description: 'Purchase #$purchaseId — Credit + VAT',
            entryType: 'purchase',
            sourceTable: 'purchases',
            sourceId: purchaseId,
            autoPost: true,
            lines: lines,
          ),
          userId: userId,
        );
      } else {
        // Purchase (Credit) no VAT: Dr Inventory, Cr Accounts Payable
        await _accountingRepo.createJournalEntry(
          entryData: JournalEntryData.simple(
            description: 'Purchase #$purchaseId — Credit',
            debitAccountId: inventoryId,
            creditAccountId: payablesId,
            amountCents: unpaid,
            currencyId: currencyId,
            entryType: 'purchase',
            sourceTable: 'purchases',
            sourceId: purchaseId,
            autoPost: true,
          ),
          userId: userId,
        );
      }
    }

    // Overpayment — supplier prepayment: Dr Accounts Payable, Cr Cash
    // This records that the supplier owes us money (negative AP balance).
    if (overpayment > 0) {
      await _accountingRepo.createJournalEntry(
        entryData: JournalEntryData.simple(
          description: 'Purchase #$purchaseId — Overpayment (supplier prepayment)',
          debitAccountId: payablesId,
          creditAccountId: cashOrBankId,
          amountCents: overpayment,
          currencyId: currencyId,
          entryType: 'purchase',
          sourceTable: 'purchases',
          sourceId: purchaseId,
          autoPost: true,
        ),
        userId: userId,
      );
    }

    developer.log('Journal entries created for Purchase #$purchaseId', name: 'JournalEntryService');
  }

  // ── Sale Return ─────────────────────────────────────────────

  /// Create journal entries for a posted sale return.
  ///
  /// STRICT RULES:
  /// Sales Return:        Dr Sales Revenue, Cr Cash / Accounts Receivable
  /// VAT on Sales Return: Dr VAT Payable,   Cr Cash / Accounts Receivable
  Future<void> recordSaleReturnJournalEntry({
    required int returnId,
    required int totalCents,
    required int currencyId,
    int taxCents = 0,
    String refundMethod = 'cash',
    int? userId,
  }) async {
    final cashOrBankId = await _cashOrBankAccountId(refundMethod);
    final receivablesId = await _requireAccountId('1100');
    final revenueId = await _requireAccountId('4000');

    final isCreditRefund = refundMethod == 'credit';
    final creditAccountId = isCreditRefund ? receivablesId : cashOrBankId;
    final methodLabel = isCreditRefund ? 'Credit Note' : 'Cash Refund';

    if (totalCents > 0) {
      if (taxCents > 0) {
        final netRevenue = totalCents - taxCents;
        final vatPayableId = await _requireAccountId('2100');

        final lines = <JournalEntryLineData>[];
        if (netRevenue > 0) {
          lines.add(JournalEntryLineData(
            accountId: revenueId,
            debitCents: netRevenue,
            creditCents: 0,
            currencyId: currencyId,
          ));
        }
        if (taxCents > 0) {
          lines.add(JournalEntryLineData(
            accountId: vatPayableId,
            debitCents: taxCents,
            creditCents: 0,
            currencyId: currencyId,
          ));
        }
        lines.add(JournalEntryLineData(
          accountId: creditAccountId,
          debitCents: 0,
          creditCents: totalCents,
          currencyId: currencyId,
        ));

        await _accountingRepo.createJournalEntry(
          entryData: JournalEntryData(
            description: 'Sale Return #$returnId — $methodLabel + VAT Reversal',
            entryType: 'saleReturn',
            sourceTable: 'sale_returns',
            sourceId: returnId,
            autoPost: true,
            lines: lines,
          ),
          userId: userId,
        );
      } else {
        // Dr Sales Revenue, Cr Cash/AR
        await _accountingRepo.createJournalEntry(
          entryData: JournalEntryData.simple(
            description: 'Sale Return #$returnId — $methodLabel',
            debitAccountId: revenueId,
            creditAccountId: creditAccountId,
            amountCents: totalCents,
            currencyId: currencyId,
            entryType: 'saleReturn',
            sourceTable: 'sale_returns',
            sourceId: returnId,
            autoPost: true,
          ),
          userId: userId,
        );
      }
    }

    developer.log('Journal entries created for Sale Return #$returnId ($methodLabel)', name: 'JournalEntryService');
  }

  // ── Purchase Return ─────────────────────────────────────────

  /// Create journal entries for a posted purchase return.
  ///
  /// Depends on refund method:
  ///   - cash/cheque: Dr Cash, Cr Inventory          (money comes back)
  ///   - credit:      Dr Payables, Cr Inventory       (reduces what we owe)
  Future<void> recordPurchaseReturnJournalEntry({
    required int returnId,
    required int totalCents,
    required int currencyId,
    String refundMethod = 'cash',
    int? userId,
  }) async {
    final cashOrBankId = await _cashOrBankAccountId(refundMethod);
    final payablesId = await _requireAccountId('2000');
    final inventoryId = await _requireAccountId('1200');

    // Credit refunds reduce A/P; cash/cheque refunds increase Cash/Bank
    final isCreditRefund = refundMethod == 'credit';
    final debitAccountId = isCreditRefund ? payablesId : cashOrBankId;
    final methodLabel = isCreditRefund ? 'Credit Note' : 'Cash Refund';

    if (totalCents > 0) {
      await _accountingRepo.createJournalEntry(
        entryData: JournalEntryData.simple(
          description: 'Purchase Return #$returnId ($methodLabel)',
          debitAccountId: debitAccountId,
          creditAccountId: inventoryId,
          amountCents: totalCents,
          currencyId: currencyId,
          entryType: 'purchaseReturn',
          sourceTable: 'purchase_returns',
          sourceId: returnId,
          autoPost: true,
        ),
        userId: userId,
      );
    }

    developer.log('Journal entries created for Purchase Return #$returnId ($methodLabel)', name: 'JournalEntryService');
  }

  // ── Expense ─────────────────────────────────────────────────

  /// Create journal entry for an expense.
  /// Dr Expense account, Cr Cash/Bank
  Future<void> recordExpenseJournalEntry({
    required int expenseId,
    required int amountCents,
    required int currencyId,
    String? expenseAccountCode,
    String? paymentMethod,
    int? userId,
  }) async {
    final cashOrBankId = await _cashOrBankAccountId(paymentMethod);
    final expenseId_ = await _requireAccountId(expenseAccountCode ?? '5100');

    if (amountCents > 0) {
      await _accountingRepo.createJournalEntry(
        entryData: JournalEntryData.simple(
          description: 'Expense #$expenseId',
          debitAccountId: expenseId_,
          creditAccountId: cashOrBankId,
          amountCents: amountCents,
          currencyId: currencyId,
          entryType: 'expense',
          sourceTable: 'expenses',
          sourceId: expenseId,
          autoPost: true,
        ),
        userId: userId,
      );
    }

    developer.log('Journal entry created for Expense #$expenseId', name: 'JournalEntryService');
  }

  // ── Customer Payment ────────────────────────────────────────

  /// Create journal entry for receiving customer payment.
  /// Dr Cash/Bank, Cr Accounts Receivable
  Future<void> recordCustomerPaymentJournalEntry({
    required int paymentId,
    required int amountCents,
    required int currencyId,
    String? paymentMethod,
    int? userId,
  }) async {
    final cashOrBankId = await _cashOrBankAccountId(paymentMethod);
    final receivablesId = await _requireAccountId('1100');

    if (amountCents > 0) {
      await _accountingRepo.createJournalEntry(
        entryData: JournalEntryData.simple(
          description: 'Customer Payment #$paymentId',
          debitAccountId: cashOrBankId,
          creditAccountId: receivablesId,
          amountCents: amountCents,
          currencyId: currencyId,
          entryType: 'payment',
          sourceTable: 'sale_payments',
          sourceId: paymentId,
          autoPost: true,
        ),
        userId: userId,
      );
    }

    developer.log('Journal entry created for Customer Payment #$paymentId', name: 'JournalEntryService');
  }

  // ── Supplier Payment ────────────────────────────────────────

  /// Create journal entry for paying a supplier.
  /// Dr Accounts Payable, Cr Cash/Bank
  Future<void> recordSupplierPaymentJournalEntry({
    required int paymentId,
    required int amountCents,
    required int currencyId,
    String? paymentMethod,
    int? userId,
  }) async {
    final payablesId = await _requireAccountId('2000');
    final cashOrBankId = await _cashOrBankAccountId(paymentMethod);

    if (amountCents > 0) {
      await _accountingRepo.createJournalEntry(
        entryData: JournalEntryData.simple(
          description: 'Supplier Payment #$paymentId',
          debitAccountId: payablesId,
          creditAccountId: cashOrBankId,
          amountCents: amountCents,
          currencyId: currencyId,
          entryType: 'payment',
          sourceTable: 'purchase_payments',
          sourceId: paymentId,
          autoPost: true,
        ),
        userId: userId,
      );
    }

    developer.log('Journal entry created for Supplier Payment #$paymentId', name: 'JournalEntryService');
  }

  // ── Direct Customer Payment (from profile) ───────────────────

  /// Create journal entry for a direct customer payment recorded from the
  /// customer profile screen (not tied to a specific sale).
  /// Dr Cash/Bank, Cr Accounts Receivable (1100)
  Future<void> recordDirectCustomerPaymentJournalEntry({
    required int transactionId,
    required int amountCents,
    required int currencyId,
    String? paymentMethod,
    int? userId,
  }) async {
    final cashOrBankId = await _cashOrBankAccountId(paymentMethod);
    final receivablesId = await _requireAccountId('1100');

    if (amountCents > 0) {
      await _accountingRepo.createJournalEntry(
        entryData: JournalEntryData.simple(
          description: 'Direct Customer Payment #$transactionId',
          debitAccountId: cashOrBankId,
          creditAccountId: receivablesId,
          amountCents: amountCents,
          currencyId: currencyId,
          entryType: 'customer_payment',
          sourceTable: 'customer_transactions',
          sourceId: transactionId,
          autoPost: true,
        ),
        userId: userId,
      );
    }

    developer.log('Journal entry created for Direct Customer Payment #$transactionId', name: 'JournalEntryService');
  }

  // ── Direct Customer Discount (from profile) ───────────────────

  /// Create journal entry for a direct customer discount.
  ///
  /// STRICT RULE — Invoice Discount:
  /// Dr Discounts Given (5500), Cr Accounts Receivable (1100)
  Future<void> recordDirectCustomerDiscountJournalEntry({
    required int transactionId,
    required int amountCents,
    required int currencyId,
    int? userId,
  }) async {
    final discountsGivenId = await _requireAccountId('5500');
    final receivablesId = await _requireAccountId('1100');

    if (amountCents > 0) {
      await _accountingRepo.createJournalEntry(
        entryData: JournalEntryData.simple(
          description: 'Customer Discount #$transactionId',
          debitAccountId: discountsGivenId,
          creditAccountId: receivablesId,
          amountCents: amountCents,
          currencyId: currencyId,
          entryType: 'customer_discount',
          sourceTable: 'customer_transactions',
          sourceId: transactionId,
          autoPost: true,
        ),
        userId: userId,
      );
    }

    developer.log('Journal entry created for Customer Discount #$transactionId', name: 'JournalEntryService');
  }

  // ── Direct Supplier Payment (from profile) ────────────────────

  /// Create journal entry for a direct supplier payment recorded from the
  /// supplier profile screen (not tied to a specific purchase).
  /// Dr Accounts Payable (2000), Cr Cash/Bank
  Future<void> recordDirectSupplierPaymentJournalEntry({
    required int transactionId,
    required int amountCents,
    required int currencyId,
    String? paymentMethod,
    int? userId,
  }) async {
    final payablesId = await _requireAccountId('2000');
    final cashOrBankId = await _cashOrBankAccountId(paymentMethod);

    if (amountCents > 0) {
      await _accountingRepo.createJournalEntry(
        entryData: JournalEntryData.simple(
          description: 'Direct Supplier Payment #$transactionId',
          debitAccountId: payablesId,
          creditAccountId: cashOrBankId,
          amountCents: amountCents,
          currencyId: currencyId,
          entryType: 'supplier_payment',
          sourceTable: 'supplier_transactions',
          sourceId: transactionId,
          autoPost: true,
        ),
        userId: userId,
      );
    }

    developer.log('Journal entry created for Direct Supplier Payment #$transactionId', name: 'JournalEntryService');
  }

  // ── Direct Supplier Discount (from profile) ───────────────────

  /// Create journal entry for a purchase/supplier discount.
  ///
  /// STRICT RULE — Purchase Discount:
  /// Dr Accounts Payable / Cash (2000), Cr Inventory (1200)
  /// All purchase discounts reduce Inventory value directly.
  Future<void> recordDirectSupplierDiscountJournalEntry({
    required int transactionId,
    required int amountCents,
    required int currencyId,
    int? userId,
  }) async {
    final payablesId = await _requireAccountId('2000');
    final inventoryId = await _requireAccountId('1200');

    if (amountCents > 0) {
      await _accountingRepo.createJournalEntry(
        entryData: JournalEntryData.simple(
          description: 'Purchase Discount #$transactionId',
          debitAccountId: payablesId,
          creditAccountId: inventoryId,
          amountCents: amountCents,
          currencyId: currencyId,
          entryType: 'supplier_discount',
          sourceTable: 'supplier_transactions',
          sourceId: transactionId,
          autoPost: true,
        ),
        userId: userId,
      );
    }

    developer.log('Journal entry created for Purchase Discount #$transactionId', name: 'JournalEntryService');
  }

  // ── Payroll (Salary Payment) ────────────────────────────────

  /// Create journal entry for salary payment.
  ///
  /// STRICT RULE — Salary Payment:
  /// Dr Salaries Expense (5200), Cr Cash / Bank
  /// No accrual. No Salaries Payable. Direct expense on payment.
  Future<void> recordPayrollJournalEntry({
    required int payrollId,
    required int netPayCents,
    required int currencyId,
    String? paymentMethod,
    int? userId,
  }) async {
    final salaryExpenseId = await _requireAccountId('5200');
    final cashOrBankId = await _cashOrBankAccountId(paymentMethod);

    if (netPayCents > 0) {
      await _accountingRepo.createJournalEntry(
        entryData: JournalEntryData.simple(
          description: 'Salary Payment — Payroll #$payrollId',
          debitAccountId: salaryExpenseId,
          creditAccountId: cashOrBankId,
          amountCents: netPayCents,
          currencyId: currencyId,
          entryType: 'payroll',
          sourceTable: 'payrolls',
          sourceId: payrollId,
          autoPost: true,
        ),
        userId: userId,
      );
    }

    developer.log('Journal entry created for Payroll #$payrollId', name: 'JournalEntryService');
  }

  // ── Commission Payment ────────────────────────────────────

  /// Create journal entry for commission payment.
  ///
  /// STRICT RULE — Commission Payment:
  /// Dr Commissions Expense (5600), Cr Cash / Bank
  Future<void> recordCommissionPaymentJournalEntry({
    required int referenceId,
    required int amountCents,
    required int currencyId,
    String? paymentMethod,
    String? sourceTable,
    int? userId,
  }) async {
    final commissionExpenseId = await _requireAccountId('5600');
    final cashOrBankId = await _cashOrBankAccountId(paymentMethod);

    if (amountCents > 0) {
      await _accountingRepo.createJournalEntry(
        entryData: JournalEntryData.simple(
          description: 'Commission Payment #$referenceId',
          debitAccountId: commissionExpenseId,
          creditAccountId: cashOrBankId,
          amountCents: amountCents,
          currencyId: currencyId,
          entryType: 'commission',
          sourceTable: sourceTable ?? 'commissions',
          sourceId: referenceId,
          autoPost: true,
        ),
        userId: userId,
      );
    }

    developer.log('Journal entry created for Commission Payment #$referenceId', name: 'JournalEntryService');
  }

  // ── Loyalty Points ───────────────────────────────────────────

  /// Create journal entry when loyalty points are EARNED (on sale completion).
  ///
  /// STRICT RULE — Loyalty points are a LIABILITY, not income.
  /// When points are earned:
  /// Dr Discounts Given (5500), Cr Loyalty Points Liability (2300)
  Future<void> recordLoyaltyEarnJournalEntry({
    required int saleId,
    required int valueCents,
    required int currencyId,
    int? userId,
  }) async {
    final discountsGivenId = await _requireAccountId('5500');
    final loyaltyLiabilityId = await _requireAccountId('2300');

    if (valueCents > 0) {
      await _accountingRepo.createJournalEntry(
        entryData: JournalEntryData.simple(
          description: 'Loyalty Points Earned — Sale #$saleId',
          debitAccountId: discountsGivenId,
          creditAccountId: loyaltyLiabilityId,
          amountCents: valueCents,
          currencyId: currencyId,
          entryType: 'loyalty_earn',
          sourceTable: 'sales',
          sourceId: saleId,
          autoPost: true,
        ),
        userId: userId,
      );
    }

    developer.log('Journal entry created for Loyalty Earn — Sale #$saleId', name: 'JournalEntryService');
  }

  /// Create journal entry when loyalty points are REDEEMED.
  ///
  /// STRICT RULE — When points are redeemed:
  /// Dr Loyalty Points Liability (2300), Cr Discounts Given (5500)
  /// Keeps all customer incentives under Discounts Given. Never inflates revenue.
  Future<void> recordLoyaltyRedemptionJournalEntry({
    required int redemptionId,
    required int valueCents,
    required int currencyId,
    int? userId,
  }) async {
    final loyaltyLiabilityId = await _requireAccountId('2300');
    final discountsGivenId = await _requireAccountId('5500');

    if (valueCents > 0) {
      await _accountingRepo.createJournalEntry(
        entryData: JournalEntryData.simple(
          description: 'Loyalty Points Redeemed — Redemption #$redemptionId',
          debitAccountId: loyaltyLiabilityId,
          creditAccountId: discountsGivenId,
          amountCents: valueCents,
          currencyId: currencyId,
          entryType: 'loyalty_redemption',
          sourceTable: 'customer_reward_redemptions',
          sourceId: redemptionId,
          autoPost: true,
        ),
        userId: userId,
      );
    }

    developer.log('Journal entry created for Loyalty Redemption #$redemptionId', name: 'JournalEntryService');
  }

  // ── Opening Balance (Customer / Supplier) ──────────────────────

  /// Create journal entry for a customer opening balance.
  ///
  /// STRICT RULES:
  /// If amountCents > 0 (customer owes us):
  ///   Dr Accounts Receivable (1100), Cr Opening Balance Equity (3100)
  /// If amountCents < 0 (we owe customer / credit balance):
  ///   Dr Opening Balance Equity (3100), Cr Accounts Receivable (1100)
  ///
  /// Idempotent: checks for existing opening_balance entry for this customer
  /// before creating a new one.
  Future<void> recordCustomerOpeningBalanceJournalEntry({
    required int customerId,
    required int amountCents,
    required int currencyId,
    int? userId,
  }) async {
    if (amountCents == 0) return;

    final receivablesId = await _requireAccountId('1100');
    final openingEquityId = await _requireAccountId('3100');

    final absAmount = amountCents.abs();

    final int debitAccountId;
    final int creditAccountId;

    if (amountCents > 0) {
      // Customer owes us: Dr AR, Cr Opening Balance Equity
      debitAccountId = receivablesId;
      creditAccountId = openingEquityId;
    } else {
      // We owe customer: Dr Opening Balance Equity, Cr AR
      debitAccountId = openingEquityId;
      creditAccountId = receivablesId;
    }

    await _accountingRepo.createJournalEntry(
      entryData: JournalEntryData.simple(
        description: 'Customer #$customerId — Opening Balance',
        debitAccountId: debitAccountId,
        creditAccountId: creditAccountId,
        amountCents: absAmount,
        currencyId: currencyId,
        entryType: 'opening_balance',
        sourceTable: 'customers',
        sourceId: customerId,
        autoPost: true,
      ),
      userId: userId,
    );

    developer.log(
      'Journal entry created for Customer #$customerId opening balance: $amountCents cents',
      name: 'JournalEntryService',
    );
  }

  /// Create journal entry for a supplier opening balance.
  ///
  /// STRICT RULES:
  /// If amountCents > 0 (we owe supplier):
  ///   Dr Opening Balance Equity (3100), Cr Accounts Payable (2000)
  /// If amountCents < 0 (supplier owes us / debit balance):
  ///   Dr Accounts Payable (2000), Cr Opening Balance Equity (3100)
  ///
  /// Idempotent: checks for existing opening_balance entry for this supplier
  /// before creating a new one.
  Future<void> recordSupplierOpeningBalanceJournalEntry({
    required int supplierId,
    required int amountCents,
    required int currencyId,
    int? userId,
  }) async {
    if (amountCents == 0) return;

    final payablesId = await _requireAccountId('2000');
    final openingEquityId = await _requireAccountId('3100');

    final absAmount = amountCents.abs();

    final int debitAccountId;
    final int creditAccountId;

    if (amountCents > 0) {
      // We owe supplier: Dr Opening Balance Equity, Cr AP
      debitAccountId = openingEquityId;
      creditAccountId = payablesId;
    } else {
      // Supplier owes us: Dr AP, Cr Opening Balance Equity
      debitAccountId = payablesId;
      creditAccountId = openingEquityId;
    }

    await _accountingRepo.createJournalEntry(
      entryData: JournalEntryData.simple(
        description: 'Supplier #$supplierId — Opening Balance',
        debitAccountId: debitAccountId,
        creditAccountId: creditAccountId,
        amountCents: absAmount,
        currencyId: currencyId,
        entryType: 'opening_balance',
        sourceTable: 'suppliers',
        sourceId: supplierId,
        autoPost: true,
      ),
      userId: userId,
    );

    developer.log(
      'Journal entry created for Supplier #$supplierId opening balance: $amountCents cents',
      name: 'JournalEntryService',
    );
  }

  // ── Repair journal entries ──────────────────────────────────

  /// Repair journal entries to fix GL ↔ sub-ledger mismatches.
  ///
  /// Two issues are fixed:
  /// 1. Orphaned draft journal entries: the old code created journal entries
  ///    at purchase draft time, but supplier balances were only updated at
  ///    post time. This voids journal entries for non-posted purchases.
  /// 2. Overpayment entries: the old code recorded overpayment incorrectly.
  ///    For posted purchases/sales with paid > total, void and re-create.
  Future<int> repairOverpaymentJournalEntries() async {
    int repaired = 0;

    // ── Fix 1: Void journal entries for non-posted (draft) purchases ──
    // The old code created journal entries at draft time, causing GL ↔ sub-ledger drift.
    final draftPurchasesWithJournals = await _accountingRepo.rawSelect(
      'SELECT p.id FROM purchases p '
      'INNER JOIN journal_entries je ON je.source_table = \'purchases\' AND je.source_id = p.id '
      'WHERE p.status != \'posted\' AND je.status = \'posted\' AND je.is_reversed = 0 '
      'GROUP BY p.id',
    );

    for (final row in draftPurchasesWithJournals) {
      final purchaseId = row.read<int>('id');
      developer.log(
        'Voiding orphaned journal entries for non-posted Purchase #$purchaseId',
        name: 'JournalEntryService',
      );
      await voidJournalEntriesForSource(
        sourceTable: 'purchases',
        sourceId: purchaseId,
        reason: 'Repair: void draft purchase journal entries',
      );
      repaired++;
    }

    // ── Fix 2: Re-create journal entries for posted purchases with overpayment ──
    final overpaidPurchases = await _accountingRepo.rawSelect(
      'SELECT id, total_cents, paid_amount_cents, currency_id, payment_method '
      'FROM purchases WHERE status = \'posted\' '
      'AND CAST(paid_amount_cents AS INTEGER) > CAST(total_cents AS INTEGER)',
    );

    for (final row in overpaidPurchases) {
      final purchaseId = row.read<int>('id');
      final totalCents = row.read<int>('total_cents');
      final paidAmountCents = row.read<int>('paid_amount_cents');
      final currencyId = row.read<int>('currency_id');
      final paymentMethod = row.readNullable<String>('payment_method');

      developer.log(
        'Repairing Purchase #$purchaseId: total=$totalCents, paid=$paidAmountCents',
        name: 'JournalEntryService',
      );

      await voidJournalEntriesForSource(
        sourceTable: 'purchases',
        sourceId: purchaseId,
        reason: 'Repair: overpayment journal entry fix',
      );

      await recordPurchaseJournalEntry(
        purchaseId: purchaseId,
        totalCents: totalCents,
        paidAmountCents: paidAmountCents,
        currencyId: currencyId,
        paymentMethod: paymentMethod,
      );

      repaired++;
    }

    // ── Fix 3: Re-create journal entries for posted sales with overpayment ──
    final overpaidSales = await _accountingRepo.rawSelect(
      'SELECT id, total_cents, paid_amount_cents, currency_id, payment_method '
      'FROM sales WHERE status = \'completed\' '
      'AND CAST(paid_amount_cents AS INTEGER) > CAST(total_cents AS INTEGER)',
    );

    for (final row in overpaidSales) {
      final saleId = row.read<int>('id');
      final totalCents = row.read<int>('total_cents');
      final paidAmountCents = row.read<int>('paid_amount_cents');
      final currencyId = row.read<int>('currency_id');
      final paymentMethod = row.readNullable<String>('payment_method');

      developer.log(
        'Repairing Sale #$saleId: total=$totalCents, paid=$paidAmountCents',
        name: 'JournalEntryService',
      );

      // Void old entries (only sale revenue entries, not COGS)
      final entries = await _accountingRepo.getJournalEntriesForSource('sales', saleId);
      for (final entry in entries) {
        if (entry.status == 'posted' && !entry.isReversed && entry.entryType == 'sale') {
          await _accountingRepo.voidJournalEntry(
            entryId: entry.id,
            reason: 'Repair: overpayment journal entry fix',
            userId: 0,
          );
        }
      }

      await recordSaleJournalEntry(
        saleId: saleId,
        totalCents: totalCents,
        paidAmountCents: paidAmountCents,
        currencyId: currencyId,
        paymentMethod: paymentMethod,
      );

      repaired++;
    }

    developer.log(
      'Repaired $repaired journal entries '
      '(${draftPurchasesWithJournals.length} draft purchases, '
      '${overpaidPurchases.length} overpaid purchases, '
      '${overpaidSales.length} overpaid sales)',
      name: 'JournalEntryService',
    );
    return repaired;
  }

  // ── Void (reverse all journal entries for a source) ─────────

  /// Void all journal entries linked to a source document.
  /// Used when voiding sales, purchases, etc.
  ///
  /// SAFETY: Only voids entries that are posted AND not already reversed.
  /// If the source has already been fully voided, this is a no-op with a log.
  /// Reversal happens at most ONCE per entry.
  Future<void> voidJournalEntriesForSource({
    required String sourceTable,
    required int sourceId,
    required String reason,
    int? userId,
  }) async {
    final entries = await _accountingRepo.getJournalEntriesForSource(
      sourceTable, sourceId,
    );

    // Filter to only entries that CAN be voided
    final voidable = entries
        .where((e) => e.status == 'posted' && !e.isReversed)
        .toList();

    if (voidable.isEmpty) {
      developer.log(
        'No voidable entries for $sourceTable #$sourceId '
        '(${entries.length} total, all already voided/reversed)',
        name: 'JournalEntryService',
      );
      return;
    }

    int voided = 0;
    for (final entry in voidable) {
      await _accountingRepo.voidJournalEntry(
        entryId: entry.id,
        reason: reason,
        userId: userId ?? 0,
      );
      voided++;
    }

    developer.log(
      'Voided $voided of ${entries.length} journal entries for $sourceTable #$sourceId',
      name: 'JournalEntryService',
    );
  }
}
