import '../../../features/accounting/data/repositories/accounting_repository.dart';
import '../../../features/accounting/domain/exceptions/accounting_exception.dart';
import '../../../features/accounting/domain/models/journal_entry_data.dart';
import 'posted_return.dart';

/// **Single source of truth** for return-journal-entry shape.
///
/// `ReturnJournalPolicy` is a pure-ish translator from the unified
/// `PostedReturn` value object to a balanced `JournalEntryData`.
/// It is the *only* place in the codebase that decides which account codes
/// participate in a return — there are no per-flow special cases below.
///
/// Outputs are always:
/// - `entryType` = `'sale_return'` (sale side) or `'purchase_return'`
///   (purchase side). The legacy values `'saleReturn'`,
///   `'saleReturnAdjustment'`, `'purchaseReturn'`,
///   `'purchaseReturnAdjustment'` are **deprecated** going forward; the
///   policy collapses both linked and adjustment flows under the same type.
/// - `sourceTable`/`sourceId` mirror the actual return header (linked or
///   adjustment) so reports can still join back to the originating row.
/// - `description` = `'<Side> Return #<id>'` plus a refund-channel suffix.
///
/// ───────────────────────────────────────────────────────────────────────
/// **Sale Return (unified shape)**
///
///   Lines (financial):
///     Dr  5700 Sales Return Adjustment        netCents       (contra-revenue)
///     Dr  2100 VAT Payable                    taxCents       (if tax > 0)
///       Cr  routing-account                   totalCents
///         - cash                              → 1000 Cash
///         - bank / card / transfer            → 1010 Bank
///         - cheque                            → 1100 AR (pending refund)
///         - credit + linked invoice           → 1100 AR
///         - credit + unlinked + party present → 2400 Customer Credit Liab.
///         - credit + no party                 → REJECTED (defense-in-depth)
///
///   Lines (inventory; only when restockable cost > 0):
///     Dr  1200 Inventory                      restockableCost
///       Cr  5300 COGS                         restockableCost
///
///   Lines (inventory shrinkage; only when damaged/scrap cost > 0):
///     Dr  5800 Inventory Shrinkage            shrinkageCost
///       Cr  5300 COGS                         shrinkageCost
///
/// **Purchase Return (unified shape)**
///
///   Lines (financial):
///     Dr  routing-account                     totalCents
///       - cash                                → 1000 Cash
///       - bank / card / transfer              → 1010 Bank
///       - cheque                              → 2000 AP (pending collection)
///       - credit                              → 2000 Accounts Payable
///       Cr  1300 VAT Receivable               taxCents       (if tax > 0)
///       Cr  4100 Purchase Return Adjustment   netCents       (contra-COGS)
///
///   Lines (inventory; required for purchase returns):
///     Dr  4100 Purchase Return Adjustment     inventoryCost
///       Cr  1200 Inventory                    inventoryCost
///
/// In linked-purchase returns where `netCents == inventoryCost` the 4100
/// account nets to zero — that is intentional and correct (no price
/// variance recognised). In adjustment-purchase returns where
/// `netCents != inventoryCost`, 4100 carries the variance, which is the
/// IFRS-compliant treatment of a purchase price adjustment.
class ReturnJournalPolicy {
  final AccountingRepository _accountingRepo;

  ReturnJournalPolicy(this._accountingRepo);

  // ── Account-code constants ────────────────────────────────────────────
  // These mirror the seeded chart of accounts. Any change here MUST be
  // mirrored in `JournalRepositoryImpl.seedDefaultAccounts` and in the
  // header doc above.
  static const String _cashCode = '1000';
  static const String _bankCode = '1010';
  static const String _arCode = '1100';
  static const String _inventoryCode = '1200';
  static const String _returnsInTransitCode = '1290';
  static const String _vatReceivableCode = '1300';
  static const String _apCode = '2000';
  static const String _vatPayableCode = '2100';
  static const String _customerCreditLiabilityCode = '2400';
  static const String _purchaseReturnAdjCode = '4100';
  static const String _salesReturnAdjCode = '5700';
  static const String _cogsCode = '5300';
  static const String _shrinkageCode = '5800';

  static const String entryTypeSaleReturn = 'sale_return';
  static const String entryTypePurchaseReturn = 'purchase_return';

  /// Translate a [PostedReturn] into a balanced compound [JournalEntryData].
  ///
  /// Throws [AccountingException] if any required account is missing from
  /// the chart of accounts, or if a defense-in-depth invariant is violated
  /// (e.g. `refund=credit` on a sale return without a customer).
  Future<JournalEntryData> toJournalEntry(PostedReturn ret) async {
    if (ret.lines.isEmpty) {
      throw AccountingException(
        'Cannot build JE for return #${ret.returnId}: no lines provided.',
      );
    }
    if (ret.totalCents < 0) {
      throw AccountingException(
        'Cannot build JE for return #${ret.returnId}: '
        'totalCents must be ≥ 0 (was ${ret.totalCents}).',
      );
    }

    switch (ret.side) {
      case ReturnSide.sale:
        return _buildSaleReturn(ret);
      case ReturnSide.purchase:
        return _buildPurchaseReturn(ret);
    }
  }

  // ── Sale-side ─────────────────────────────────────────────────────────

  Future<JournalEntryData> _buildSaleReturn(PostedReturn ret) async {
    // Defense-in-depth: a deferred sale return MUST have a customer.
    // Without a party we have no way to track who is owed (1100 AR or 2400
    // Customer Credit Liability would become an orphaned balance).
    if ((ret.refund == RefundChannel.credit ||
            ret.refund == RefundChannel.cheque) &&
        ret.partyId == null) {
      throw AccountingException(
        'Sale Return #${ret.returnId}: deferred refund requires a customer; '
        'no partyId was provided.',
      );
    }

    final salesRACode = await _requireAccountId(_salesReturnAdjCode);
    final cogsId = await _requireAccountId(_cogsCode);

    final settlementId = await _resolveSaleSettlementAccount(ret);

    final lines = <JournalEntryLineData>[];

    // ── Financial leg ──
    if (ret.totalCents > 0) {
      final net = ret.netCents;
      final tax = ret.taxCents;

      if (net > 0) {
        lines.add(
          JournalEntryLineData(
            accountId: salesRACode,
            debitCents: net,
            creditCents: 0,
            currencyId: ret.currencyId,
            description:
                'Sales return (contra-revenue) — Sale Return #${ret.returnId}',
          ),
        );
      }

      if (tax > 0) {
        final vatPayableId = await _requireAccountId(_vatPayableCode);
        lines.add(
          JournalEntryLineData(
            accountId: vatPayableId,
            debitCents: tax,
            creditCents: 0,
            currencyId: ret.currencyId,
            description: 'Output VAT reversed — Sale Return #${ret.returnId}',
          ),
        );
      }

      lines.add(
        JournalEntryLineData(
          accountId: settlementId,
          debitCents: 0,
          creditCents: ret.totalCents,
          currencyId: ret.currencyId,
          description: _saleSettlementDescription(ret),
        ),
      );
    }

    // ── Inventory leg: restock → 1200 ──
    final restockCost = ret.restockableInventoryCostCents;
    if (restockCost > 0) {
      final inventoryId = await _requireAccountId(_inventoryCode);
      lines.add(
        JournalEntryLineData(
          accountId: inventoryId,
          debitCents: restockCost,
          creditCents: 0,
          currencyId: ret.currencyId,
          description: 'Inventory restored — Sale Return #${ret.returnId}',
        ),
      );
      lines.add(
        JournalEntryLineData(
          accountId: cogsId,
          debitCents: 0,
          creditCents: restockCost,
          currencyId: ret.currencyId,
          description: 'COGS reversed — Sale Return #${ret.returnId}',
        ),
      );
    }

    // ── Inventory leg: shrinkage → 5800 ──
    final shrinkageCost = ret.shrinkageInventoryCostCents;
    if (shrinkageCost > 0) {
      final shrinkageId = await _requireAccountId(_shrinkageCode);
      lines.add(
        JournalEntryLineData(
          accountId: shrinkageId,
          debitCents: shrinkageCost,
          creditCents: 0,
          currencyId: ret.currencyId,
          description:
              'Inventory shrinkage (damaged/scrap) — Sale Return #${ret.returnId}',
        ),
      );
      lines.add(
        JournalEntryLineData(
          accountId: cogsId,
          debitCents: 0,
          creditCents: shrinkageCost,
          currencyId: ret.currencyId,
          description:
              'COGS reversed (write-off) — Sale Return #${ret.returnId}',
        ),
      );
    }

    return JournalEntryData(
      description: _saleDescription(ret),
      entryType: entryTypeSaleReturn,
      sourceTable: ret.link.sourceTable ?? 'sale_return_adjustments',
      sourceId: ret.returnId,
      autoPost: true,
      lines: lines,
    );
  }

  // ── Purchase-side ─────────────────────────────────────────────────────

  Future<JournalEntryData> _buildPurchaseReturn(PostedReturn ret) async {
    final purchaseRAId = await _requireAccountId(_purchaseReturnAdjCode);
    final inventoryId = await _requireAccountId(_inventoryCode);

    final settlementId = await _resolvePurchaseSettlementAccount(ret);

    final lines = <JournalEntryLineData>[];

    // ── Financial leg ──
    if (ret.totalCents > 0) {
      final net = ret.netCents;
      final tax = ret.taxCents;

      lines.add(
        JournalEntryLineData(
          accountId: settlementId,
          debitCents: ret.totalCents,
          creditCents: 0,
          currencyId: ret.currencyId,
          description: _purchaseSettlementDescription(ret),
        ),
      );

      if (tax > 0) {
        final vatReceivableId = await _requireAccountId(_vatReceivableCode);
        lines.add(
          JournalEntryLineData(
            accountId: vatReceivableId,
            debitCents: 0,
            creditCents: tax,
            currencyId: ret.currencyId,
            description:
                'Input VAT reversed — Purchase Return #${ret.returnId}',
          ),
        );
      }

      if (net > 0) {
        lines.add(
          JournalEntryLineData(
            accountId: purchaseRAId,
            debitCents: 0,
            creditCents: net,
            currencyId: ret.currencyId,
            description:
                'Purchase return (contra-COGS) — Purchase Return #${ret.returnId}',
          ),
        );
      }
    }

    // ── Inventory leg (perpetual) — split by disposition ──
    //
    // restock   → Dr 4100 / Cr 1200   — supplier physically took the goods
    //                                   AND settled (or will settle) the
    //                                   credit. Inventory leaves on-hand
    //                                   and the 4100 contra-COGS offsets
    //                                   the credit to AP so the net-on-4100
    //                                   carries only the price variance.
    // sendBack  → Dr 1290 / Cr 1200   — goods physically left but the
    //                                   supplier credit memo has NOT yet
    //                                   arrived. We DO NOT touch 4100 on
    //                                   the inventory leg: the full credit
    //                                   stays posted to 4100 on the
    //                                   financial side above, and a future
    //                                   credit-memo reconciliation posts
    //                                   Dr 4100 / Cr 1290 to clear both
    //                                   accounts. Keeping 1290 strictly
    //                                   debit-balance preserves its
    //                                   asset-nature (pending-credit claim
    //                                   against the supplier).
    //
    // Net effect on 4100 (restock only) = net − cost = price variance:
    //   linked       → cost == net → 4100 nets to 0 (no variance)
    //   adjustment   → cost may differ → 4100 carries variance (IFRS price-adj)
    final restockCost = ret.lines
        .where((l) => l.disposition != ReturnDisposition.sendBack)
        .fold(0, (sum, l) => sum + l.inventoryCostCents);
    final sendBackCost = ret.sendBackInventoryCostCents;

    if (restockCost > 0) {
      lines.add(
        JournalEntryLineData(
          accountId: purchaseRAId,
          debitCents: restockCost,
          creditCents: 0,
          currencyId: ret.currencyId,
          description:
              'Inventory cost removed (offsets purchase return) — '
              'Purchase Return #${ret.returnId}',
        ),
      );
      lines.add(
        JournalEntryLineData(
          accountId: inventoryId,
          debitCents: 0,
          creditCents: restockCost,
          currencyId: ret.currencyId,
          description: 'Inventory decreased — Purchase Return #${ret.returnId}',
        ),
      );
    }

    if (sendBackCost > 0) {
      final ritId = await _requireAccountId(_returnsInTransitCode);
      lines.add(
        JournalEntryLineData(
          accountId: ritId,
          debitCents: sendBackCost,
          creditCents: 0,
          currencyId: ret.currencyId,
          description:
              'Goods in transit (supplier has not yet issued credit) — '
              'Purchase Return #${ret.returnId}',
        ),
      );
      lines.add(
        JournalEntryLineData(
          accountId: inventoryId,
          debitCents: 0,
          creditCents: sendBackCost,
          currencyId: ret.currencyId,
          description:
              'Inventory decreased (goods left premises) — '
              'Purchase Return #${ret.returnId}',
        ),
      );
    }

    return JournalEntryData(
      description: _purchaseDescription(ret),
      entryType: entryTypePurchaseReturn,
      sourceTable: ret.link.sourceTable ?? 'purchase_return_adjustments',
      sourceId: ret.returnId,
      autoPost: true,
      lines: lines,
    );
  }

  // ── Settlement-account routing ────────────────────────────────────────

  Future<int> _resolveSaleSettlementAccount(PostedReturn ret) async {
    switch (ret.refund) {
      case RefundChannel.cash:
        return _requireAccountId(_cashCode);
      case RefundChannel.bank:
        return _requireAccountId(_bankCode);
      case RefundChannel.cheque:
        // Build the base return against AR. Registering the physical cheque
        // immediately reclassifies that obligation to 2020.
        return _requireAccountId(_arCode);
      case RefundChannel.credit:
        // Linked → reduce existing AR. Unlinked → by default park in 2400
        // Customer Credit Liability so AR isn't created out of thin air
        // (store-credit sub-ledger). When the caller opts into
        // `creditToReceivable` (sale adjustment returns), reduce 1100 AR
        // directly instead — the DAO mirrors this on `customers.balance_cents`
        // so the AR sub-ledger stays reconciled with GL 1100.
        if (ret.link.isLinked || ret.creditToReceivable) {
          return _requireAccountId(_arCode);
        }
        return _requireAccountId(_customerCreditLiabilityCode);
    }
  }

  Future<int> _resolvePurchaseSettlementAccount(PostedReturn ret) async {
    switch (ret.refund) {
      case RefundChannel.cash:
        return _requireAccountId(_cashCode);
      case RefundChannel.bank:
        return _requireAccountId(_bankCode);
      case RefundChannel.cheque:
        // Keep the supplier refund receivable in AP until collection.
        return _requireAccountId(_apCode);
      case RefundChannel.credit:
        return _requireAccountId(_apCode);
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────

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

  String _saleDescription(PostedReturn ret) {
    final base = ret.referenceCode ?? 'Sale Return #${ret.returnId}';
    final method = _refundMethodLabel(
      ret.refund,
      ReturnSide.sale,
      ret.link,
      ret.creditToReceivable,
    );
    return '$base — $method';
  }

  String _purchaseDescription(PostedReturn ret) {
    final base = ret.referenceCode ?? 'Purchase Return #${ret.returnId}';
    final method = _refundMethodLabel(
      ret.refund,
      ReturnSide.purchase,
      ret.link,
      ret.creditToReceivable,
    );
    return '$base — $method';
  }

  String _saleSettlementDescription(PostedReturn ret) {
    switch (ret.refund) {
      case RefundChannel.cash:
        return 'Cash refund — Sale Return #${ret.returnId}';
      case RefundChannel.bank:
        return 'Bank refund — Sale Return #${ret.returnId}';
      case RefundChannel.cheque:
        return 'Pending outgoing cheque — Sale Return #${ret.returnId}';
      case RefundChannel.credit:
        if (ret.link.isLinked || ret.creditToReceivable) {
          return 'AR reduced — Sale Return #${ret.returnId}';
        }
        return 'Customer credit issued — Sale Return #${ret.returnId}';
    }
  }

  String _purchaseSettlementDescription(PostedReturn ret) {
    switch (ret.refund) {
      case RefundChannel.cash:
        return 'Cash refund received — Purchase Return #${ret.returnId}';
      case RefundChannel.bank:
        return 'Bank refund received — Purchase Return #${ret.returnId}';
      case RefundChannel.cheque:
        return 'Pending incoming cheque — Purchase Return #${ret.returnId}';
      case RefundChannel.credit:
        return 'AP reduced — Purchase Return #${ret.returnId}';
    }
  }

  String _refundMethodLabel(
    RefundChannel ch,
    ReturnSide side,
    ReturnLink link,
    bool creditToReceivable,
  ) {
    switch (ch) {
      case RefundChannel.cash:
        return 'Cash';
      case RefundChannel.bank:
        return 'Bank';
      case RefundChannel.cheque:
        return 'Cheque';
      case RefundChannel.credit:
        if (side == ReturnSide.sale && !link.isLinked && !creditToReceivable) {
          return 'Customer Credit';
        }
        return 'Credit';
    }
  }
}
