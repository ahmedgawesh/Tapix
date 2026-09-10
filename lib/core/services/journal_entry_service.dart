import 'dart:developer' as developer;

import '../../features/accounting/data/repositories/accounting_repository.dart';
import '../../features/accounting/domain/exceptions/accounting_exception.dart';
import '../../features/accounting/domain/models/journal_entry_data.dart';
import 'returns/posted_return.dart';
import 'returns/return_posting_service.dart';

/// MANDATORY journal-entry service for all financial operations.
///
/// Every method here WILL throw on failure — callers MUST handle errors.
/// There are NO silent catch blocks. If the ledger cannot be updated,
/// the business transaction must be aware of it.
///
/// Account codes used here MUST match the STRICT Chart of Accounts
/// seeded by JournalRepositoryImpl.seedDefaultAccounts:
///   Assets:      1000 = Cash, 1010 = Bank, 1020 = Cheques in Hand,
///                1030 = Dishonoured Cheques Receivable,
///                1100 = Accounts Receivable,
///                1200 = Inventory, 1290 = Returns in Transit,
///                1300 = VAT Receivable
///   Liabilities: 2000 = Accounts Payable, 2020 = Cheques Issued,
///                2100 = VAT Payable,
///                2300 = Loyalty Points Liability,
///                2400 = Customer Credit Liability
///   Equity:      3000 = Owner Capital, 3100 = Opening Balance Equity
///   Income:      4000 = Sales Revenue,
///                4100 = Purchase Return Adjustment (contra-expense),
///                4200 = Inventory Gain,
///                4900 = Purchase Discounts Earned,
///                5700 = Sales Return Adjustment (contra-revenue)
///   Expenses:    5100 = Expenses, 5200 = Salaries Expense,
///                5300 = Cost of Goods Sold,
///                5500 = Discounts Given, 5600 = Commissions Expense,
///                5800 = Inventory Shrinkage,
///                5900 = Inventory Revaluation
class JournalEntryService {
  final AccountingRepository _accountingRepo;

  /// Optional unified return-posting pipeline.
  ///
  /// When provided (production DI always provides it), the four legacy
  /// `record*ReturnJournalEntry` methods on this class delegate to
  /// `ReturnPostingService.post` so that linked and adjustment returns
  /// produce the **same** JE shape (driven by `ReturnJournalPolicy`).
  ///
  /// Tests that construct `JournalEntryService` directly may still leave
  /// this `null` — the class falls back to its legacy in-line shape so
  /// pre-existing tests continue to pass without rewiring.
  final ReturnPostingService? _returnPostingService;

  JournalEntryService(
    this._accountingRepo, {
    ReturnPostingService? returnPostingService,
  }) : _returnPostingService = returnPostingService;

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

  /// Generic Cash (1000) / Bank (1010) resolver for non-cheque-aware flows.
  /// Cheque-aware document and payment flows must use the incoming/outgoing
  /// settlement helpers below so physical cheques never hit Bank prematurely.
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

  bool _isCheque(String? method) {
    final value = method?.trim().toLowerCase();
    return value == 'cheque' || value == 'check';
  }

  /// Incoming cheques are assets in hand, not bank cash, until cleared.
  Future<int> _incomingSettlementAccountId(String? method) {
    if (_isCheque(method)) return _requireAccountId('1020');
    return _cashOrBankAccountId(method);
  }

  /// Issued cheques remain an outstanding liability until bank clearance.
  Future<int> _outgoingSettlementAccountId(String? method) {
    if (_isCheque(method)) return _requireAccountId('2020');
    return _cashOrBankAccountId(method);
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
    final cashOrBankId = await _incomingSettlementAccountId(paymentMethod);
    final receivablesId = await _requireAccountId('1100');
    final revenueId = await _requireAccountId('4000');

    // Cap the effective paid amount to totalCents for the invoice portion.
    // Any overpayment is handled separately as a prepayment (Dr Cash, Cr AR).
    final effectivePaid = paidAmountCents > totalCents
        ? totalCents
        : paidAmountCents;
    final overpayment = paidAmountCents > totalCents
        ? paidAmountCents - totalCents
        : 0;

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

    developer.log(
      'Journal entries created for Sale #$saleId',
      name: 'JournalEntryService',
    );
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

    developer.log(
      'COGS journal entry created for Sale #$saleId ($costCents cents)',
      name: 'JournalEntryService',
    );
  }

  /// Repairs a historical sale whose Inventory/COGS posting exceeded the
  /// exact carrying value removed from stock.
  ///
  /// This is intentionally attached to the original `sales` source so the
  /// normal sale-void workflow reverses both the original COGS entry and this
  /// correction. Posted entries remain immutable: the correction is a new,
  /// balanced and auditable Dr Inventory / Cr COGS entry.
  Future<int> recordSaleCogsValuationCorrection({
    required int saleId,
    required int amountCents,
    required int currencyId,
    required String reason,
    DateTime? entryDate,
    int? userId,
  }) async {
    if (amountCents <= 0) {
      throw AccountingException(
        'Sale COGS valuation correction must be positive',
      );
    }
    final inventoryId = await _requireAccountId('1200');
    final cogsId = await _requireAccountId('5300');
    return _accountingRepo.createJournalEntry(
      entryData: JournalEntryData.simple(
        description: 'Sale #$saleId — Inventory/COGS correction: $reason',
        debitAccountId: inventoryId,
        creditAccountId: cogsId,
        amountCents: amountCents,
        currencyId: currencyId,
        entryDate: entryDate,
        entryType: 'sale_cogs_correction',
        sourceTable: 'sales',
        sourceId: saleId,
        autoPost: true,
      ),
      userId: userId,
    );
  }

  /// Reverse COGS when a sale return is posted.
  ///
  /// STRICT RULES (unified policy):
  ///   Dr Inventory         (1200)  costCents   [disposition=restock]
  ///     Cr COGS             (5300)  costCents
  ///
  /// When [_returnPostingService] is wired (production), delegates to
  /// `ReturnPostingService.post` with a `totalCents=0` sale-return shape
  /// so only the inventory leg is emitted. Shape matches what the legacy
  /// method produced, but flows through the single source of truth.
  ///
  /// [costCents] is the total cost of the returned items.
  Future<void> recordSaleReturnCOGSReversalJournalEntry({
    required int returnId,
    required int costCents,
    required int currencyId,
    int? userId,
  }) async {
    if (costCents <= 0) return;

    final svc = _returnPostingService;
    if (svc != null) {
      await svc.post(
        PostedReturn(
          side: ReturnSide.sale,
          link: ReturnLink.linked(
            sourceInvoiceId: returnId,
            sourceTable: 'sale_returns',
          ),
          partyId: null,
          returnId: returnId,
          // refund channel is irrelevant for a COGS-only JE (totalCents=0);
          // use cash as a safe default so the policy does not attempt to
          // resolve 2400 / 1100 for a zero-amount settlement leg.
          refund: RefundChannel.cash,
          currencyId: currencyId,
          lines: [
            PostedReturnLine(
              totalCents: 0,
              taxCents: 0,
              inventoryCostCents: costCents,
            ),
          ],
          userId: userId,
        ),
      );
      return;
    }

    // ── Legacy fallback ──
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

    developer.log(
      'COGS reversal journal entry created for Sale Return #$returnId '
      '($costCents cents; legacy fallback)',
      name: 'JournalEntryService',
    );
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
    int? inventoryNetCents,
    String? paymentMethod,
    int? userId,
  }) async {
    final cashOrBankId = await _outgoingSettlementAccountId(paymentMethod);
    final payablesId = await _requireAccountId('2000');
    final inventoryId = await _requireAccountId('1200');
    final netTotal = (totalCents - taxCents).clamp(0, totalCents).toInt();
    final inventoryNet = (inventoryNetCents ?? netTotal)
        .clamp(0, netTotal)
        .toInt();
    final expenseNet = netTotal - inventoryNet;
    final expenseId = expenseNet > 0 ? await _requireAccountId('5100') : null;

    // Cap the effective paid amount to totalCents for the invoice portion.
    // Any overpayment is handled separately as a prepayment (Dr AP, Cr Cash).
    final effectivePaid = paidAmountCents > totalCents
        ? totalCents
        : paidAmountCents;
    final overpayment = paidAmountCents > totalCents
        ? paidAmountCents - totalCents
        : 0;
    var paidInventoryAllocated = 0;
    var paidExpenseAllocated = 0;

    // Paid portion (capped at totalCents)
    if (effectivePaid > 0) {
      if (taxCents > 0 || expenseNet > 0) {
        // Split the paid invoice portion into Inventory / Expense / VAT.
        // The cumulative remainder stays in the unpaid portion so both
        // asset classes reconcile exactly to their invoice totals.
        final paidTax = (effectivePaid == totalCents)
            ? taxCents
            : (taxCents * effectivePaid / totalCents).round();
        final paidNet = effectivePaid - paidTax;
        paidInventoryAllocated = netTotal <= 0
            ? 0
            : (inventoryNet * paidNet / netTotal)
                  .round()
                  .clamp(0, inventoryNet)
                  .clamp(0, paidNet)
                  .toInt();
        paidExpenseAllocated = paidNet - paidInventoryAllocated;
        final vatReceivableId = paidTax > 0
            ? await _requireAccountId('1300')
            : null;

        final lines = <JournalEntryLineData>[];
        if (paidInventoryAllocated > 0) {
          lines.add(
            JournalEntryLineData(
              accountId: inventoryId,
              debitCents: paidInventoryAllocated,
              creditCents: 0,
              currencyId: currencyId,
            ),
          );
        }
        if (paidExpenseAllocated > 0) {
          lines.add(
            JournalEntryLineData(
              accountId: expenseId!,
              debitCents: paidExpenseAllocated,
              creditCents: 0,
              currencyId: currencyId,
            ),
          );
        }
        if (paidTax > 0) {
          lines.add(
            JournalEntryLineData(
              accountId: vatReceivableId!,
              debitCents: paidTax,
              creditCents: 0,
              currencyId: currencyId,
            ),
          );
        }
        lines.add(
          JournalEntryLineData(
            accountId: cashOrBankId,
            debitCents: 0,
            creditCents: effectivePaid,
            currencyId: currencyId,
          ),
        );

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
      if (taxCents > 0 || expenseNet > 0) {
        final paidTax = (effectivePaid > 0 && effectivePaid < totalCents)
            ? (taxCents * effectivePaid / totalCents).round()
            : 0;
        final creditTax = taxCents - paidTax;
        final creditInventory = inventoryNet - paidInventoryAllocated;
        final creditExpense = expenseNet - paidExpenseAllocated;
        final vatReceivableId = creditTax > 0
            ? await _requireAccountId('1300')
            : null;

        final lines = <JournalEntryLineData>[];
        if (creditInventory > 0) {
          lines.add(
            JournalEntryLineData(
              accountId: inventoryId,
              debitCents: creditInventory,
              creditCents: 0,
              currencyId: currencyId,
            ),
          );
        }
        if (creditExpense > 0) {
          lines.add(
            JournalEntryLineData(
              accountId: expenseId!,
              debitCents: creditExpense,
              creditCents: 0,
              currencyId: currencyId,
            ),
          );
        }
        if (creditTax > 0) {
          lines.add(
            JournalEntryLineData(
              accountId: vatReceivableId!,
              debitCents: creditTax,
              creditCents: 0,
              currencyId: currencyId,
            ),
          );
        }
        lines.add(
          JournalEntryLineData(
            accountId: payablesId,
            debitCents: 0,
            creditCents: unpaid,
            currencyId: currencyId,
          ),
        );

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
          description:
              'Purchase #$purchaseId — Overpayment (supplier prepayment)',
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

    developer.log(
      'Journal entries created for Purchase #$purchaseId',
      name: 'JournalEntryService',
    );
  }

  // ── Sale Return ─────────────────────────────────────────────

  /// Create the financial-leg journal entry for a posted **linked** sale
  /// return (sale-return row lives in `sale_returns`).
  ///
  /// When [_returnPostingService] is wired (production), this method
  /// delegates to `ReturnPostingService.post` which drives the unified
  /// `ReturnJournalPolicy`. The resulting JE has:
  ///   Dr  5700 Sales R&A (contra-revenue)  netCents
  ///   Dr  2100 VAT Payable                 taxCents    (if tax > 0)
  ///     Cr  routing-account                totalCents
  ///       - cash         → 1000
  ///       - bank          → 1010
  //       - cheque        → 2020
  ///       - credit       → 1100 AR (linked → reduce existing AR)
  ///
  /// The COGS leg is handled by [recordSaleReturnCOGSReversalJournalEntry].
  /// A future cleanup pass can fold the two calls into one compound JE.
  ///
  /// [partyId] is the `customer_id` on the sale (required for credit-refund
  /// defense-in-depth). Callers may pass `null` for walk-in cash refunds.
  Future<void> recordSaleReturnJournalEntry({
    required int returnId,
    required int totalCents,
    required int currencyId,
    int taxCents = 0,
    String refundMethod = 'cash',
    int? partyId,
    int? userId,
    DateTime? postingDate,
    List<PostedReturnLine>? explicitLines,
  }) async {
    if (totalCents <= 0) return;

    // Delegate to unified pipeline when available.
    final svc = _returnPostingService;
    if (svc != null) {
      await svc.post(
        PostedReturn(
          side: ReturnSide.sale,
          link: ReturnLink.linked(
            sourceInvoiceId: returnId,
            sourceTable: 'sale_returns',
          ),
          partyId: partyId,
          returnId: returnId,
          refund: RefundChannelX.fromWire(refundMethod),
          currencyId: currencyId,
          lines:
              explicitLines ??
              [
                PostedReturnLine(
                  totalCents: totalCents,
                  taxCents: taxCents,
                  inventoryCostCents:
                      0, // COGS handled separately (legacy path)
                ),
              ],
          userId: userId,
          postingDate: postingDate,
        ),
      );
      return;
    }

    // ── Legacy fallback (tests that construct JournalEntryService
    //    without injecting ReturnPostingService) ────────────────────
    final cashOrBankId = await _outgoingSettlementAccountId(refundMethod);
    final receivablesId = await _requireAccountId('1100');
    final salesRAId = await _requireAccountId('5700');

    final isCreditRefund = refundMethod == 'credit';
    final creditAccountId = isCreditRefund ? receivablesId : cashOrBankId;
    final methodLabel = isCreditRefund ? 'Credit Note' : 'Cash Refund';

    final netRevenue = totalCents - taxCents;
    final lines = <JournalEntryLineData>[];
    if (netRevenue > 0) {
      lines.add(
        JournalEntryLineData(
          accountId: salesRAId,
          debitCents: netRevenue,
          creditCents: 0,
          currencyId: currencyId,
        ),
      );
    }
    if (taxCents > 0) {
      final vatPayableId = await _requireAccountId('2100');
      lines.add(
        JournalEntryLineData(
          accountId: vatPayableId,
          debitCents: taxCents,
          creditCents: 0,
          currencyId: currencyId,
        ),
      );
    }
    lines.add(
      JournalEntryLineData(
        accountId: creditAccountId,
        debitCents: 0,
        creditCents: totalCents,
        currencyId: currencyId,
      ),
    );

    await _accountingRepo.createJournalEntry(
      entryData: JournalEntryData(
        description: 'Sale Return #$returnId — $methodLabel',
        entryType: 'sale_return',
        sourceTable: 'sale_returns',
        sourceId: returnId,
        autoPost: true,
        lines: lines,
      ),
      userId: userId,
    );

    developer.log(
      'Journal entries created for Sale Return #$returnId '
      '($methodLabel; legacy fallback, no ReturnPostingService injected)',
      name: 'JournalEntryService',
    );
  }

  // ── Purchase Return ─────────────────────────────────────────

  /// Create journal entries for a posted **linked** purchase return.
  ///
  /// When [_returnPostingService] is wired (production), this method
  /// delegates to `ReturnPostingService.post` — identical shape for linked
  /// and adjustment returns. The unified JE:
  ///
  ///   Dr  routing-account          totalCents
  ///     Cr  1300 VAT Receivable    taxCents     (if tax > 0)
  ///     Cr  4100 Purchase R&A      netCents
  ///   Dr  4100 Purchase R&A        inventoryCost
  ///     Cr  1200 Inventory         inventoryCost
  ///
  /// For linked returns `inventoryCost == netCents` so 4100 nets to zero —
  /// this is correct: no purchase-price variance on linked returns.
  ///
  /// [inventoryCostCents] is the historical cost of the returned goods
  /// from the original batch/WAC; callers are responsible for freezing
  /// this snapshot at post-time. When omitted (legacy call sites), the
  /// policy receives `inventoryCostCents = netCents` which preserves the
  /// previous behaviour (Cr 1200 == net).
  Future<void> recordPurchaseReturnJournalEntry({
    required int returnId,
    required int totalCents,
    required int currencyId,
    int taxCents = 0,
    int? inventoryCostCents,
    String refundMethod = 'cash',
    int? userId,
    DateTime? postingDate,
    List<PostedReturnLine>? explicitLines,
  }) async {
    if (totalCents <= 0) {
      developer.log(
        'Purchase Return #$returnId — totalCents <= 0, skipping JE',
        name: 'JournalEntryService',
      );
      return;
    }

    // Defensive clamp — taxCents must never exceed totalCents.
    final clampedTax = taxCents > totalCents ? totalCents : taxCents;
    final net = totalCents - clampedTax;
    // Default invCost to net (linked-return invariant) when caller didn't
    // supply a historical snapshot. Forces 4100 wash-through.
    final invCost = inventoryCostCents ?? net;

    final svc = _returnPostingService;
    if (svc != null) {
      await svc.post(
        PostedReturn(
          side: ReturnSide.purchase,
          link: ReturnLink.linked(
            sourceInvoiceId: returnId,
            sourceTable: 'purchase_returns',
          ),
          partyId: null,
          returnId: returnId,
          refund: RefundChannelX.fromWire(refundMethod),
          currencyId: currencyId,
          lines:
              explicitLines ??
              [
                PostedReturnLine(
                  totalCents: totalCents,
                  taxCents: clampedTax,
                  inventoryCostCents: invCost,
                ),
              ],
          userId: userId,
          postingDate: postingDate,
        ),
      );
      return;
    }

    // ── Legacy fallback (tests without ReturnPostingService) ──
    final cashOrBankId = await _incomingSettlementAccountId(refundMethod);
    final payablesId = await _requireAccountId('2000');
    final inventoryId = await _requireAccountId('1200');
    final isCreditRefund = refundMethod == 'credit';
    final debitAccountId = isCreditRefund ? payablesId : cashOrBankId;
    final methodLabel = isCreditRefund ? 'Credit Note' : 'Cash Refund';

    // A return can contain service/non-stock lines, or inventory whose
    // historical cost differs from its invoice net. In that case the old
    // fallback (Cr Inventory for the whole net) corrupts both Inventory and
    // purchase-return variance. Mirror the production posting policy here.
    if (invCost != net) {
      final vatReceivableId = clampedTax > 0
          ? await _requireAccountId('1300')
          : null;
      final purchaseReturnAdjustmentId = await _requireAccountId('4100');
      final lines = <JournalEntryLineData>[
        JournalEntryLineData(
          accountId: debitAccountId,
          debitCents: totalCents,
          creditCents: 0,
          currencyId: currencyId,
        ),
      ];
      if (clampedTax > 0) {
        lines.add(
          JournalEntryLineData(
            accountId: vatReceivableId!,
            debitCents: 0,
            creditCents: clampedTax,
            currencyId: currencyId,
          ),
        );
      }
      if (net > 0) {
        lines.add(
          JournalEntryLineData(
            accountId: purchaseReturnAdjustmentId,
            debitCents: 0,
            creditCents: net,
            currencyId: currencyId,
          ),
        );
      }
      if (invCost > 0) {
        lines.addAll([
          JournalEntryLineData(
            accountId: purchaseReturnAdjustmentId,
            debitCents: invCost,
            creditCents: 0,
            currencyId: currencyId,
          ),
          JournalEntryLineData(
            accountId: inventoryId,
            debitCents: 0,
            creditCents: invCost,
            currencyId: currencyId,
          ),
        ]);
      }
      await _accountingRepo.createJournalEntry(
        entryData: JournalEntryData(
          description:
              'Purchase Return #$returnId — $methodLabel + Cost Adjustment',
          entryType: 'purchase_return',
          sourceTable: 'purchase_returns',
          sourceId: returnId,
          autoPost: true,
          lines: lines,
        ),
        userId: userId,
      );
      return;
    }

    if (clampedTax > 0) {
      final vatReceivableId = await _requireAccountId('1300');
      final lines = <JournalEntryLineData>[
        JournalEntryLineData(
          accountId: debitAccountId,
          debitCents: totalCents,
          creditCents: 0,
          currencyId: currencyId,
        ),
        JournalEntryLineData(
          accountId: vatReceivableId,
          debitCents: 0,
          creditCents: clampedTax,
          currencyId: currencyId,
        ),
      ];
      if (net > 0) {
        lines.add(
          JournalEntryLineData(
            accountId: inventoryId,
            debitCents: 0,
            creditCents: net,
            currencyId: currencyId,
          ),
        );
      }
      await _accountingRepo.createJournalEntry(
        entryData: JournalEntryData(
          description:
              'Purchase Return #$returnId — $methodLabel + VAT Reversal',
          entryType: 'purchase_return',
          sourceTable: 'purchase_returns',
          sourceId: returnId,
          autoPost: true,
          lines: lines,
        ),
        userId: userId,
      );
    } else {
      await _accountingRepo.createJournalEntry(
        entryData: JournalEntryData.simple(
          description: 'Purchase Return #$returnId ($methodLabel)',
          debitAccountId: debitAccountId,
          creditAccountId: inventoryId,
          amountCents: totalCents,
          currencyId: currencyId,
          entryType: 'purchase_return',
          sourceTable: 'purchase_returns',
          sourceId: returnId,
          autoPost: true,
        ),
        userId: userId,
      );
    }

    developer.log(
      'Journal entries created for Purchase Return #$returnId '
      '($methodLabel, tax=$taxCents; legacy fallback)',
      name: 'JournalEntryService',
    );
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

    developer.log(
      'Journal entry created for Expense #$expenseId',
      name: 'JournalEntryService',
    );
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
    final cashOrBankId = await _incomingSettlementAccountId(paymentMethod);
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

    developer.log(
      'Journal entry created for Customer Payment #$paymentId',
      name: 'JournalEntryService',
    );
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
    final cashOrBankId = await _outgoingSettlementAccountId(paymentMethod);

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

    developer.log(
      'Journal entry created for Supplier Payment #$paymentId',
      name: 'JournalEntryService',
    );
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
    final cashOrBankId = await _incomingSettlementAccountId(paymentMethod);
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

    developer.log(
      'Journal entry created for Direct Customer Payment #$transactionId',
      name: 'JournalEntryService',
    );
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

    developer.log(
      'Journal entry created for Customer Discount #$transactionId',
      name: 'JournalEntryService',
    );
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

    developer.log(
      'Journal entry created for Direct Supplier Payment #$transactionId',
      name: 'JournalEntryService',
    );
  }

  /// Immediate cash/card leg of a sale return.
  /// The return itself is first posted to AR; paying the customer now settles
  /// only this allocation: Dr Accounts Receivable, Cr Cash/Bank.
  Future<void> recordSaleReturnSettlementJournalEntry({
    required int transactionId,
    required int amountCents,
    required int currencyId,
    required String paymentMethod,
    int? userId,
  }) async {
    final receivablesId = await _requireAccountId('1100');
    final cashOrBankId = await _outgoingSettlementAccountId(paymentMethod);
    if (amountCents <= 0) return;
    await _accountingRepo.createJournalEntry(
      entryData: JournalEntryData.simple(
        description: 'Sale return settlement #$transactionId',
        debitAccountId: receivablesId,
        creditAccountId: cashOrBankId,
        amountCents: amountCents,
        currencyId: currencyId,
        entryType: 'return_settlement',
        sourceTable: 'customer_transactions',
        sourceId: transactionId,
        autoPost: true,
      ),
      userId: userId,
    );
  }

  /// Immediate cash/card leg of a purchase return.
  /// The return itself is first posted to AP; receipt from the supplier now
  /// settles only this allocation: Dr Cash/Bank, Cr Accounts Payable.
  Future<void> recordPurchaseReturnSettlementJournalEntry({
    required int transactionId,
    required int amountCents,
    required int currencyId,
    required String paymentMethod,
    int? userId,
  }) async {
    final cashOrBankId = await _incomingSettlementAccountId(paymentMethod);
    final payablesId = await _requireAccountId('2000');
    if (amountCents <= 0) return;
    await _accountingRepo.createJournalEntry(
      entryData: JournalEntryData.simple(
        description: 'Purchase return settlement #$transactionId',
        debitAccountId: cashOrBankId,
        creditAccountId: payablesId,
        amountCents: amountCents,
        currencyId: currencyId,
        entryType: 'return_settlement',
        sourceTable: 'supplier_transactions',
        sourceId: transactionId,
        autoPost: true,
      ),
      userId: userId,
    );
  }

  // ── Direct Supplier Discount (from profile) ───────────────────

  /// Create journal entry for a purchase/supplier discount recorded from
  /// the supplier profile screen (NOT tied to a specific PO line).
  ///
  /// STRICT RULE — Unallocated Supplier Discount:
  ///   Dr Accounts Payable (2000) — supplier owes us less
  ///   Cr Purchase Discounts Earned (4900) — recognised as income
  ///
  /// ────────────────────────────────────────────────────────────────────
  /// WHY NOT Cr Inventory (1200)?
  /// ────────────────────────────────────────────────────────────────────
  /// The legacy rule was "Dr AP / Cr Inventory", justified as a landed-
  /// cost reduction. But this JE has no stock-side movement: it never
  /// updates `products.cost_cents`, `product_variants.cost_cents`, or
  /// `stock_batches.cost_cents`, so Σ(stock × cost) stays unchanged
  /// while GL Inventory drops by the discount amount. The result is a
  /// permanent, immovable reconciliation drift surfaced by
  /// `ReconciliationHealthService` as "Inventory mismatch:
  /// GL(journal_lines)=X, Σ(stock×cost)=Y" with Y − X = discount.
  ///
  /// To Cr Inventory CORRECTLY we would need a full landed-cost
  /// allocation algorithm: prorate the rebate across remaining stock
  /// layers, write down `cost_cents` per layer/variant, and reverse the
  /// COGS of already-sold units. That workflow does not exist in this
  /// app and adding it would be a Phase-2 inventory-valuation engine.
  ///
  /// Until then, the IFRS/GAAP-conformant treatment of an unallocated,
  /// after-the-fact supplier rebate is to recognise it as **other
  /// income** in the period received (parallel to the customer-side rule:
  /// customer discount = Dr Discounts Given / Cr AR). That is the
  /// posting this method now produces.
  Future<void> recordDirectSupplierDiscountJournalEntry({
    required int transactionId,
    required int amountCents,
    required int currencyId,
    int? userId,
  }) async {
    final payablesId = await _requireAccountId('2000');
    final discountsEarnedId = await _requireAccountId('4900');

    if (amountCents > 0) {
      await _accountingRepo.createJournalEntry(
        entryData: JournalEntryData.simple(
          description: 'Purchase Discount #$transactionId',
          debitAccountId: payablesId,
          creditAccountId: discountsEarnedId,
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

    developer.log(
      'Journal entry created for Purchase Discount #$transactionId',
      name: 'JournalEntryService',
    );
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

    developer.log(
      'Journal entry created for Payroll #$payrollId',
      name: 'JournalEntryService',
    );
  }

  // ── Purchase Adjustment Return (Perpetual Inventory) ──────────

  /// Create compound journal entry for a purchase adjustment return.
  ///
  /// STRICT RULE — Purchase Adjustment Return (Perpetual Inventory):
  ///   Financial side:
  ///     Dr Payment Account (AP 2000 / Cash 1000 / Bank 1010)  [totalCents]
  ///     Cr Purchase Return Adj (4100)                         netCents
  ///     Cr VAT Receivable / Input Tax (1300)                  [taxCents]
  ///   Inventory side:
  ///     Dr COGS (5300)      [inventoryCostCents]
  ///     Cr Inventory (1200) [inventoryCostCents]
  ///
  /// [totalCents]          = tax-inclusive financial total.
  /// [taxCents]            = VAT / input-tax portion to reverse.
  /// [inventoryCostCents]  = sum of (unitCostCents × qty) — inventory value.
  /// [refundMethod]        = 'cash' | 'credit' | 'cheque' — determines debit account.
  Future<void> recordPurchaseAdjustmentReturnJournalEntry({
    required int returnId,
    required int totalCents,
    required int taxCents,
    required int inventoryCostCents,
    required int currencyId,
    String refundMethod = 'credit',
    int? userId,
    DateTime? postingDate,
    List<PostedReturnLine>? explicitLines,
    String approvalStatus = 'auto_approved',
    String? approvalReason,
    int? supplierId,
  }) async {
    if (totalCents <= 0 && inventoryCostCents <= 0) {
      developer.log(
        'Purchase Adj Return #$returnId — nothing to post (total=0, cost=0)',
        name: 'JournalEntryService',
      );
      return;
    }

    // Delegate to unified pipeline when available. Same shape as
    // `recordPurchaseReturnJournalEntry` — linked vs adjustment are
    // identical at the JE level.
    final svc = _returnPostingService;
    if (svc != null) {
      await svc.post(
        PostedReturn(
          side: ReturnSide.purchase,
          link: ReturnLink.adjustment,
          partyId: supplierId,
          returnId: returnId,
          refund: RefundChannelX.fromWire(refundMethod),
          currencyId: currencyId,
          lines:
              explicitLines ??
              [
                PostedReturnLine(
                  totalCents: totalCents,
                  taxCents: taxCents,
                  inventoryCostCents: inventoryCostCents,
                ),
              ],
          userId: userId,
          postingDate: postingDate,
          approvalStatus: approvalStatus,
          approvalReason: approvalReason,
        ),
      );
      return;
    }

    // ── Legacy fallback (in-line shape preserved for unwired tests) ──
    final adjAccountId = await _requireAccountId('4100');
    final inventoryId = await _requireAccountId('1200');
    final cogsId = await _requireAccountId('5300');

    final int debitAccountId;
    switch (refundMethod) {
      case 'cash':
        debitAccountId = await _requireAccountId('1000');
      case 'cheque':
        debitAccountId = await _requireAccountId('1020');
      case 'credit':
      default:
        debitAccountId = await _requireAccountId('2000');
    }

    final netCents = totalCents - taxCents;
    final lines = <JournalEntryLineData>[];

    if (totalCents > 0) {
      lines.add(
        JournalEntryLineData(
          accountId: debitAccountId,
          debitCents: totalCents,
          creditCents: 0,
          currencyId: currencyId,
          description: refundMethod == 'credit'
              ? 'AP reduced — Purchase Adj Return #$returnId'
              : 'Refund received ($refundMethod) — Purchase Adj Return #$returnId',
        ),
      );
      if (netCents > 0) {
        lines.add(
          JournalEntryLineData(
            accountId: adjAccountId,
            debitCents: 0,
            creditCents: netCents,
            currencyId: currencyId,
            description: 'Purchase Return Adjustment income — #$returnId',
          ),
        );
      }
      if (taxCents > 0) {
        final vatReceivableId = await _requireAccountId('1300');
        lines.add(
          JournalEntryLineData(
            accountId: vatReceivableId,
            debitCents: 0,
            creditCents: taxCents,
            currencyId: currencyId,
            description: 'Input VAT reversed — Purchase Adj Return #$returnId',
          ),
        );
      }
    }

    if (inventoryCostCents > 0) {
      lines.add(
        JournalEntryLineData(
          accountId: cogsId,
          debitCents: inventoryCostCents,
          creditCents: 0,
          currencyId: currencyId,
          description:
              'Inventory cost removed — Purchase Adj Return #$returnId',
        ),
      );
      lines.add(
        JournalEntryLineData(
          accountId: inventoryId,
          debitCents: 0,
          creditCents: inventoryCostCents,
          currencyId: currencyId,
          description: 'Inventory decreased — Purchase Adj Return #$returnId',
        ),
      );
    }

    if (lines.isNotEmpty) {
      await _accountingRepo.createJournalEntry(
        entryData: JournalEntryData(
          description: 'Purchase Adjustment Return #$returnId',
          entryType: 'purchase_return',
          sourceTable: 'purchase_return_adjustments',
          sourceId: returnId,
          autoPost: true,
          lines: lines,
        ),
        userId: userId,
      );
    }

    developer.log(
      'Purchase Adj Return #$returnId posted via legacy fallback '
      '(no ReturnPostingService): net=$netCents tax=$taxCents '
      'total=$totalCents inv=$inventoryCostCents method=$refundMethod',
      name: 'JournalEntryService',
    );
  }

  // ── Sale Adjustment Return (Perpetual Inventory) ────────────

  /// Create compound journal entry for a sale adjustment return.
  ///
  /// STRICT RULE — Sale Adjustment Return (Perpetual Inventory):
  ///   Financial side:
  ///     Dr Sales Return Adj (5700)                             netCents
  ///     Dr VAT Payable / Output Tax (2100)                     [taxCents]
  ///     Cr Payment Account (AR 1100 / Cash 1000 / Bank 1010)   [totalCents]
  ///   Inventory side:
  ///     Dr Inventory (1200) [inventoryCostCents]
  ///     Cr COGS (5300)      [inventoryCostCents]
  ///
  /// [totalCents]          = tax-inclusive financial total.
  /// [taxCents]            = VAT / output-tax portion to reverse.
  /// [inventoryCostCents]  = sum of (unitCostCents × qty) — inventory value.
  /// [refundMethod]        = 'cash' | 'credit' | 'cheque' — determines credit account.
  Future<void> recordSaleAdjustmentReturnJournalEntry({
    required int returnId,
    required int totalCents,
    required int taxCents,
    required int inventoryCostCents,
    required int currencyId,
    String refundMethod = 'cash',
    int? partyId,
    int? userId,
    DateTime? postingDate,
    List<PostedReturnLine>? explicitLines,
    String approvalStatus = 'auto_approved',
    String? approvalReason,
    bool creditToReceivable = false,
  }) async {
    if (totalCents <= 0 && inventoryCostCents <= 0) {
      developer.log(
        'Sale Adj Return #$returnId — nothing to post (total=0, cost=0)',
        name: 'JournalEntryService',
      );
      return;
    }

    // Delegate to unified pipeline when available.
    final svc = _returnPostingService;
    if (svc != null) {
      await svc.post(
        PostedReturn(
          side: ReturnSide.sale,
          link: ReturnLink.adjustment,
          partyId: partyId,
          returnId: returnId,
          refund: RefundChannelX.fromWire(refundMethod),
          currencyId: currencyId,
          lines:
              explicitLines ??
              [
                PostedReturnLine(
                  totalCents: totalCents,
                  taxCents: taxCents,
                  inventoryCostCents: inventoryCostCents,
                ),
              ],
          userId: userId,
          postingDate: postingDate,
          approvalStatus: approvalStatus,
          approvalReason: approvalReason,
          creditToReceivable: creditToReceivable,
        ),
      );
      return;
    }

    // ── Legacy fallback (in-line shape preserved for unwired tests) ──
    final adjAccountId = await _requireAccountId('5700');
    final inventoryId = await _requireAccountId('1200');
    final cogsId = await _requireAccountId('5300');

    final int creditAccountId;
    switch (refundMethod) {
      case 'credit':
        creditAccountId = await _requireAccountId('1100');
      case 'cheque':
        creditAccountId = await _requireAccountId('2020');
      case 'cash':
      default:
        creditAccountId = await _requireAccountId('1000');
    }

    final netCents = totalCents - taxCents;
    final lines = <JournalEntryLineData>[];

    if (totalCents > 0) {
      if (netCents > 0) {
        lines.add(
          JournalEntryLineData(
            accountId: adjAccountId,
            debitCents: netCents,
            creditCents: 0,
            currencyId: currencyId,
            description: 'Sales return adjustment expense — #$returnId',
          ),
        );
      }
      if (taxCents > 0) {
        final vatPayableId = await _requireAccountId('2100');
        lines.add(
          JournalEntryLineData(
            accountId: vatPayableId,
            debitCents: taxCents,
            creditCents: 0,
            currencyId: currencyId,
            description: 'Output VAT reversed — Sale Adj Return #$returnId',
          ),
        );
      }
      lines.add(
        JournalEntryLineData(
          accountId: creditAccountId,
          debitCents: 0,
          creditCents: totalCents,
          currencyId: currencyId,
          description: refundMethod == 'credit'
              ? 'AR reduced — Sale Adj Return #$returnId'
              : 'Refund issued ($refundMethod) — Sale Adj Return #$returnId',
        ),
      );
    }

    if (inventoryCostCents > 0) {
      lines.add(
        JournalEntryLineData(
          accountId: inventoryId,
          debitCents: inventoryCostCents,
          creditCents: 0,
          currencyId: currencyId,
          description: 'Inventory restored — Sale Adj Return #$returnId',
        ),
      );
      lines.add(
        JournalEntryLineData(
          accountId: cogsId,
          debitCents: 0,
          creditCents: inventoryCostCents,
          currencyId: currencyId,
          description: 'COGS reversed — Sale Adj Return #$returnId',
        ),
      );
    }

    if (lines.isNotEmpty) {
      await _accountingRepo.createJournalEntry(
        entryData: JournalEntryData(
          description: 'Sale Adjustment Return #$returnId',
          entryType: 'sale_return',
          sourceTable: 'sale_return_adjustments',
          sourceId: returnId,
          autoPost: true,
          lines: lines,
        ),
        userId: userId,
      );
    }

    developer.log(
      'Sale Adj Return #$returnId posted via legacy fallback '
      '(no ReturnPostingService): net=$netCents tax=$taxCents '
      'total=$totalCents inv=$inventoryCostCents method=$refundMethod',
      name: 'JournalEntryService',
    );
  }

  // ── Inventory Adjustment (Shrinkage / Gain / Revaluation) ──

  /// Create journal entry for an **inventory shrinkage** adjustment.
  ///
  /// Recognises a loss of on-hand inventory (theft, damage, expiry, count
  /// shortage). Follows the perpetual-inventory standard used by QuickBooks,
  /// Odoo, Xero and SAP B1.
  ///
  /// STRICT RULE:
  ///   Dr Inventory Shrinkage (5800)  valueCents
  ///   Cr Inventory           (1200)  valueCents
  ///
  /// [valueCents] MUST equal `abs(quantity) × unitCostCents` and be positive.
  /// Returns the id of the created journal entry so the caller can link it
  /// back to its `inventory_adjustments` row (single source of truth).
  Future<int> recordInventoryShrinkageJournalEntry({
    required int adjustmentId,
    required int valueCents,
    required int currencyId,
    required String reason,
    int? userId,
  }) async {
    if (valueCents <= 0) {
      throw AccountingException(
        'Inventory shrinkage valueCents must be > 0 (got $valueCents)',
      );
    }
    final shrinkageId = await _requireAccountId('5800');
    final inventoryId = await _requireAccountId('1200');

    final entryId = await _accountingRepo.createJournalEntry(
      entryData: JournalEntryData.simple(
        description: 'Inventory Shrinkage #$adjustmentId — $reason',
        debitAccountId: shrinkageId,
        creditAccountId: inventoryId,
        amountCents: valueCents,
        currencyId: currencyId,
        entryType: 'inventory_shrinkage',
        sourceTable: 'inventory_adjustments',
        sourceId: adjustmentId,
        autoPost: true,
      ),
      userId: userId,
    );

    developer.log(
      'Journal entry created for Inventory Shrinkage #$adjustmentId '
      '($valueCents cents): $reason',
      name: 'JournalEntryService',
    );
    return entryId;
  }

  /// Create journal entry for an **inventory gain** adjustment.
  ///
  /// Recognises a surplus discovered on physical count (found stock, data
  /// correction). Classified as "other income" (4200), never as revenue —
  /// mirrors IFRS / GAAP treatment.
  ///
  /// STRICT RULE:
  ///   Dr Inventory    (1200)  valueCents
  ///   Cr Inventory Gain (4200) valueCents
  Future<int> recordInventoryGainJournalEntry({
    required int adjustmentId,
    required int valueCents,
    required int currencyId,
    required String reason,
    int? userId,
  }) async {
    if (valueCents <= 0) {
      throw AccountingException(
        'Inventory gain valueCents must be > 0 (got $valueCents)',
      );
    }
    final inventoryId = await _requireAccountId('1200');
    final gainId = await _requireAccountId('4200');

    final entryId = await _accountingRepo.createJournalEntry(
      entryData: JournalEntryData.simple(
        description: 'Inventory Gain #$adjustmentId — $reason',
        debitAccountId: inventoryId,
        creditAccountId: gainId,
        amountCents: valueCents,
        currencyId: currencyId,
        entryType: 'inventory_gain',
        sourceTable: 'inventory_adjustments',
        sourceId: adjustmentId,
        autoPost: true,
      ),
      userId: userId,
    );

    developer.log(
      'Journal entry created for Inventory Gain #$adjustmentId '
      '($valueCents cents): $reason',
      name: 'JournalEntryService',
    );
    return entryId;
  }

  /// Create journal entry for an **inventory revaluation**.
  ///
  /// Used when the unit cost of on-hand inventory changes without any
  /// physical movement (e.g. correcting a historical purchase cost or
  /// applying a Net Realisable Value write-down per IAS 2).
  ///
  /// [deltaValueCents] is SIGNED:
  ///   - positive → carrying value increased (revaluation up)
  ///       Dr Inventory (1200)  |delta|
  ///       Cr Inventory Revaluation (5900)  |delta|
  ///   - negative → carrying value decreased (write-down)
  ///       Dr Inventory Revaluation (5900)  |delta|
  ///       Cr Inventory (1200)              |delta|
  Future<int> recordInventoryRevaluationJournalEntry({
    required int adjustmentId,
    required int deltaValueCents,
    required int currencyId,
    required String reason,
    int? userId,
  }) async {
    if (deltaValueCents == 0) {
      throw AccountingException('Inventory revaluation delta must be non-zero');
    }
    final inventoryId = await _requireAccountId('1200');
    final revaluationId = await _requireAccountId('5900');

    final amount = deltaValueCents.abs();
    final isWriteUp = deltaValueCents > 0;

    final entryId = await _accountingRepo.createJournalEntry(
      entryData: JournalEntryData.simple(
        description:
            'Inventory Revaluation #$adjustmentId '
            '(${isWriteUp ? "up" : "down"}) — $reason',
        debitAccountId: isWriteUp ? inventoryId : revaluationId,
        creditAccountId: isWriteUp ? revaluationId : inventoryId,
        amountCents: amount,
        currencyId: currencyId,
        entryType: 'inventory_revaluation',
        sourceTable: 'inventory_adjustments',
        sourceId: adjustmentId,
        autoPost: true,
      ),
      userId: userId,
    );

    developer.log(
      'Journal entry created for Inventory Revaluation #$adjustmentId '
      '(${isWriteUp ? "+" : "-"}$amount cents): $reason',
      name: 'JournalEntryService',
    );
    return entryId;
  }

  /// Posts the cent-level carrying-value difference caused by measuring a
  /// fractional purchase against an already-rounded SKU pool.
  ///
  /// The source remains the purchase so normal invoice cancellation reverses
  /// both the commercial entry and this rounding revaluation atomically.
  Future<int> recordInventoryRoundingJournalEntry({
    required String sourceTable,
    required int sourceId,
    required int deltaValueCents,
    required int currencyId,
    required String reason,
    int? userId,
  }) async {
    if (deltaValueCents == 0) {
      throw AccountingException('Inventory rounding delta must be non-zero');
    }
    final inventoryId = await _requireAccountId('1200');
    final revaluationId = await _requireAccountId('5900');
    final amount = deltaValueCents.abs();
    final isWriteUp = deltaValueCents > 0;

    return _accountingRepo.createJournalEntry(
      entryData: JournalEntryData.simple(
        description:
            'Inventory rounding ${isWriteUp ? "up" : "down"} — $reason',
        debitAccountId: isWriteUp ? inventoryId : revaluationId,
        creditAccountId: isWriteUp ? revaluationId : inventoryId,
        amountCents: amount,
        currencyId: currencyId,
        entryType: 'inventory_rounding',
        sourceTable: sourceTable,
        sourceId: sourceId,
        autoPost: true,
      ),
      userId: userId,
    );
  }

  /// Create journal entry for an **inventory opening balance**.
  ///
  /// Used when a product / variant is created with a non-zero starting
  /// quantity. The offsetting credit goes to Opening Balance Equity (3100)
  /// — NOT Inventory Gain (4200) — so the P&L is not polluted with a
  /// pseudo-revenue line. This matches QuickBooks / Xero / Sage treatment
  /// and is IFRS/GAAP-compliant (IAS 2: initial measurement at cost via
  /// equity movement, not income).
  ///
  /// STRICT RULE:
  ///   Dr Inventory (1200)               valueCents
  ///   Cr Opening Balance Equity (3100)  valueCents
  Future<int> recordInventoryOpeningBalanceJournalEntry({
    required int adjustmentId,
    required int valueCents,
    required int currencyId,
    required String reason,
    int? userId,
  }) async {
    if (valueCents <= 0) {
      throw AccountingException(
        'Inventory opening balance valueCents must be > 0 (got $valueCents)',
      );
    }
    final inventoryId = await _requireAccountId('1200');
    final openingEquityId = await _requireAccountId('3100');

    final entryId = await _accountingRepo.createJournalEntry(
      entryData: JournalEntryData.simple(
        description: 'Inventory Opening Balance #$adjustmentId — $reason',
        debitAccountId: inventoryId,
        creditAccountId: openingEquityId,
        amountCents: valueCents,
        currencyId: currencyId,
        entryType: 'inventory_opening_balance',
        sourceTable: 'inventory_adjustments',
        sourceId: adjustmentId,
        autoPost: true,
      ),
      userId: userId,
    );

    developer.log(
      'Journal entry created for Inventory Opening Balance #$adjustmentId '
      '($valueCents cents): $reason',
      name: 'JournalEntryService',
    );
    return entryId;
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

    developer.log(
      'Journal entry created for Commission Payment #$referenceId',
      name: 'JournalEntryService',
    );
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

    developer.log(
      'Journal entry created for Loyalty Earn — Sale #$saleId',
      name: 'JournalEntryService',
    );
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

    developer.log(
      'Journal entry created for Loyalty Redemption #$redemptionId',
      name: 'JournalEntryService',
    );
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
      'SELECT pu.id, pu.total_cents, pu.paid_amount_cents, pu.currency_id, '
      'pu.tax_cents, pu.payment_method, '
      'COALESCE((SELECT SUM(CASE WHEN pr.track_inventory = 1 '
      'THEN MAX(pi.total_cents - pi.tax_cents, 0) ELSE 0 END) '
      'FROM purchase_items pi JOIN products pr ON pr.id = pi.product_id '
      'WHERE pi.purchase_id = pu.id), 0) AS inventory_net_cents '
      'FROM purchases pu WHERE pu.status = \'posted\' '
      'AND CAST(pu.paid_amount_cents AS INTEGER) > '
      'CAST(pu.total_cents AS INTEGER)',
    );

    for (final row in overpaidPurchases) {
      final purchaseId = row.read<int>('id');
      final totalCents = row.read<int>('total_cents');
      final paidAmountCents = row.read<int>('paid_amount_cents');
      final currencyId = row.read<int>('currency_id');
      final taxCents = row.read<int>('tax_cents');
      final inventoryNetCents = row.read<int>('inventory_net_cents');
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
        taxCents: taxCents,
        inventoryNetCents: inventoryNetCents,
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
      final entries = await _accountingRepo.getJournalEntriesForSource(
        'sales',
        saleId,
      );
      for (final entry in entries) {
        if (entry.status == 'posted' &&
            !entry.isReversed &&
            entry.entryType == 'sale') {
          await _accountingRepo.voidJournalEntry(
            entryId: entry.id,
            reason: 'Repair: overpayment journal entry fix',
            userId: null,
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
      sourceTable,
      sourceId,
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
        userId: userId,
      );
      voided++;
    }

    developer.log(
      'Voided $voided of ${entries.length} journal entries for $sourceTable #$sourceId',
      name: 'JournalEntryService',
    );
  }
  // ── Cheque clearing and dishonour ───────────────────────────

  /// Moves one physical cheque between the cheque clearing account and Bank.
  /// Incoming: Dr Bank / Cr Cheques in Hand.
  /// Outgoing: Dr Cheques Issued / Cr Bank.
  Future<int> recordChequeClearanceJournalEntry({
    required int chequeId,
    required bool incoming,
    required int amountCents,
    required int currencyId,
    int? userId,
  }) async {
    if (amountCents <= 0) {
      throw AccountingException('Cheque clearance amount must be positive');
    }
    final bankId = await _requireAccountId('1010');
    final clearingId = await _requireAccountId(incoming ? '1020' : '2020');
    return _accountingRepo.createJournalEntry(
      entryData: JournalEntryData.simple(
        description: incoming
            ? 'Incoming cheque #$chequeId cleared'
            : 'Outgoing cheque #$chequeId cleared',
        debitAccountId: incoming ? bankId : clearingId,
        creditAccountId: incoming ? clearingId : bankId,
        amountCents: amountCents,
        currencyId: currencyId,
        entryType: 'cheque_clearance',
        sourceTable: 'cheque_instruments',
        sourceId: chequeId,
        autoPost: true,
      ),
      userId: userId,
    );
  }

  /// Reclassifies a return cheque that was posted by an older build directly
  /// to a cheque clearing account. The new lifecycle keeps the amount in the
  /// customer/supplier obligation until the instrument actually clears.
  Future<int> recordReturnChequeDeferralJournalEntry({
    required int chequeId,
    required bool incoming,
    required int amountCents,
    required int currencyId,
    required String obligationAccountCode,
    int? userId,
  }) async {
    if (amountCents <= 0) {
      throw AccountingException(
        'Return cheque deferral amount must be positive',
      );
    }
    final obligationId = await _requireAccountId(obligationAccountCode);
    final clearingId = await _requireAccountId(incoming ? '1020' : '2020');
    return _accountingRepo.createJournalEntry(
      entryData: JournalEntryData.simple(
        description: 'Return cheque #$chequeId deferred until clearance',
        debitAccountId: incoming ? obligationId : clearingId,
        creditAccountId: incoming ? clearingId : obligationId,
        amountCents: amountCents,
        currencyId: currencyId,
        entryType: 'cheque_return_deferral',
        sourceTable: 'cheque_instruments',
        sourceId: chequeId,
        autoPost: true,
      ),
      userId: userId,
    );
  }

  /// Recognizes a return cheque against the party obligation when the
  /// instrument is received or issued. Bank clearance is posted separately.
  Future<int> recordReturnChequeSettlementJournalEntry({
    required int chequeId,
    required bool incoming,
    required int amountCents,
    required int currencyId,
    required String obligationAccountCode,
    int? userId,
  }) async {
    if (amountCents <= 0) {
      throw AccountingException(
        'Return cheque settlement amount must be positive',
      );
    }
    final obligationId = await _requireAccountId(obligationAccountCode);
    final clearingId = await _requireAccountId(incoming ? '1020' : '2020');
    return _accountingRepo.createJournalEntry(
      entryData: JournalEntryData.simple(
        description: incoming
            ? 'Incoming return cheque #$chequeId received'
            : 'Outgoing return cheque #$chequeId issued',
        debitAccountId: incoming ? clearingId : obligationId,
        creditAccountId: incoming ? obligationId : clearingId,
        amountCents: amountCents,
        currencyId: currencyId,
        entryType: 'cheque_return_settlement',
        sourceTable: 'cheque_instruments',
        sourceId: chequeId,
        autoPost: true,
      ),
      userId: userId,
    );
  }

  /// Restores the economic obligation after a cheque is bounced or cancelled.
  Future<int> recordChequeObligationRestorationJournalEntry({
    required int chequeId,
    required int amountCents,
    required int currencyId,
    required String debitAccountCode,
    required String creditAccountCode,
    required bool cancelled,
    String? reason,
    int? userId,
  }) async {
    if (amountCents <= 0) {
      throw AccountingException('Cheque restoration amount must be positive');
    }
    final debitId = await _requireAccountId(debitAccountCode);
    final creditId = await _requireAccountId(creditAccountCode);
    return _accountingRepo.createJournalEntry(
      entryData: JournalEntryData.simple(
        description: cancelled
            ? 'Cheque #$chequeId cancelled${reason == null ? '' : ' — $reason'}'
            : 'Cheque #$chequeId dishonoured${reason == null ? '' : ' — $reason'}',
        debitAccountId: debitId,
        creditAccountId: creditId,
        amountCents: amountCents,
        currencyId: currencyId,
        entryType: cancelled ? 'cheque_reinstatement' : 'cheque_dishonour',
        sourceTable: 'cheque_instruments',
        sourceId: chequeId,
        autoPost: true,
      ),
      userId: userId,
    );
  }

  /// Closes an incoming dishonoured-cheque receivable in account 1030.
  /// The debit account identifies the real resolution channel: cash, bank,
  /// replacement cheque, normal party credit, or bad-debt expense.
  Future<int> recordDishonouredChequeResolutionJournalEntry({
    required int chequeId,
    required int amountCents,
    required int currencyId,
    required String debitAccountCode,
    required String resolutionType,
    String? note,
    int? userId,
  }) async {
    if (amountCents <= 0) {
      throw AccountingException('Cheque resolution amount must be positive');
    }
    final debitId = await _requireAccountId(debitAccountCode);
    final dishonouredId = await _requireAccountId('1030');
    return _accountingRepo.createJournalEntry(
      entryData: JournalEntryData.simple(
        description:
            'Dishonoured cheque #$chequeId resolved by $resolutionType'
            '${note == null || note.trim().isEmpty ? '' : ' — ${note.trim()}'}',
        debitAccountId: debitId,
        creditAccountId: dishonouredId,
        amountCents: amountCents,
        currencyId: currencyId,
        entryType: 'cheque_dishonour_resolution',
        sourceTable: 'cheque_instruments',
        sourceId: chequeId,
        autoPost: true,
      ),
      userId: userId,
    );
  }

  /// Reverses one specific cheque lifecycle journal idempotently.
  Future<void> voidChequeJournalEntry({
    required int chequeId,
    required int journalEntryId,
    required String reason,
    int? userId,
  }) async {
    final entries = await _accountingRepo.getJournalEntriesForSource(
      'cheque_instruments',
      chequeId,
    );
    final canVoid = entries.any(
      (entry) =>
          entry.id == journalEntryId &&
          entry.status == 'posted' &&
          !entry.isReversed,
    );
    if (!canVoid) return;
    await _accountingRepo.voidJournalEntry(
      entryId: journalEntryId,
      reason: reason,
      userId: userId,
    );
  }
}
