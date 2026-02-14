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
///   Equity:      3000 = Owner Capital
///   Income:      4000 = Sales Revenue
///   Expenses:    5100 = Expenses, 5200 = Salaries Expense,
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

    // Revenue — cash portion: Dr Cash, Cr Sales Revenue (+ Cr VAT Payable)
    if (paidAmountCents > 0) {
      if (taxCents > 0) {
        final paidTax = (paidAmountCents == totalCents)
            ? taxCents
            : (taxCents * paidAmountCents / totalCents).round();
        final paidRevenue = paidAmountCents - paidTax;
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
                debitCents: paidAmountCents,
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
            amountCents: paidAmountCents,
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
    final unpaid = totalCents - paidAmountCents;
    if (unpaid > 0) {
      if (taxCents > 0) {
        final paidTax = (paidAmountCents > 0 && paidAmountCents < totalCents)
            ? (taxCents * paidAmountCents / totalCents).round()
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

    developer.log('Journal entries created for Sale #$saleId', name: 'JournalEntryService');
  }

  // ── Purchase ────────────────────────────────────────────────

  /// Create journal entries for a completed purchase.
  ///
  /// STRICT RULES:
  /// Purchase (Cash):   Dr Inventory, Cr Cash
  /// Purchase (Credit): Dr Inventory, Cr Accounts Payable
  /// VAT on Purchase:   Dr VAT Receivable, Cr Cash / Accounts Payable
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

    // Paid portion
    if (paidAmountCents > 0) {
      if (taxCents > 0) {
        // Split paid amount into inventory + VAT proportionally
        final paidTax = (paidAmountCents == totalCents)
            ? taxCents
            : (taxCents * paidAmountCents / totalCents).round();
        final paidInventory = paidAmountCents - paidTax;
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
          creditCents: paidAmountCents,
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
            amountCents: paidAmountCents,
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
    final unpaid = totalCents - paidAmountCents;
    if (unpaid > 0) {
      if (taxCents > 0) {
        final paidTax = (paidAmountCents > 0 && paidAmountCents < totalCents)
            ? (taxCents * paidAmountCents / totalCents).round()
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
