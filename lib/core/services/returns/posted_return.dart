// Unified value objects describing a posted return — the **single** input
// shape consumed by `ReturnJournalPolicy` and `ReturnPostingService`.
//
// These types deliberately collapse the distinction between *linked* returns
// (those tied to an original sale/purchase invoice) and *adjustment* returns
// (supplier-/customer-facing unlinked returns). The accounting policy is
// identical from this point onward: every return is a sequence of lines
// describing financial impact + (optional) inventory impact, and the policy
// produces one balanced compound `JournalEntryData` regardless of origin.
//
// Compatibility with the tri-modal inventory system (standard / batch /
// batch_expiry) is preserved because the policy never touches stock — it
// only consumes already-resolved cost/qty figures from the upstream caller.

/// Which side of the ledger this return belongs to.
enum ReturnSide {
  /// Customer returns goods → debit Sales R&A, credit Cash/AR/CustomerCredit.
  sale,

  /// Supplier takes goods back → debit AP/Cash, credit Inventory + VAT.
  purchase,
}

/// How the goods are treated physically after the return.
enum ReturnDisposition {
  /// Goods go back into resaleable stock — debit Inventory @ cost.
  restock,

  /// Goods are damaged / unfit for sale — debit Inventory Shrinkage (5800).
  /// Sale-side only; for purchases the supplier physically takes the goods,
  /// so this disposition is meaningless.
  damaged,

  /// Goods will be scrapped / written off — debit Inventory Shrinkage (5800).
  /// Sale-side only.
  scrap,

  /// Purchase-side: goods physically leave the premises but the supplier
  /// has not yet settled the credit. The inventory leg debits 1290 Returns
  /// in Transit instead of reducing 1200 directly. Clears later when the
  /// supplier issues the credit note. Ignored on sale returns.
  sendBack,
}

extension ReturnDispositionX on ReturnDisposition {
  /// Stable wire-format string for persisting into `disposition_type` columns.
  String get wireValue {
    switch (this) {
      case ReturnDisposition.restock:
        return 'restock';
      case ReturnDisposition.damaged:
        return 'damaged';
      case ReturnDisposition.scrap:
        return 'scrap';
      case ReturnDisposition.sendBack:
        return 'send_back';
    }
  }

  static ReturnDisposition fromWire(String? raw) {
    switch (raw?.trim().toLowerCase()) {
      case 'damaged':
      case 'write_off':
        return ReturnDisposition.damaged;
      case 'scrap':
        return ReturnDisposition.scrap;
      case 'send_back':
      case 'sendback':
      case 'return_to_supplier':
        return ReturnDisposition.sendBack;
      case 'restock':
      case 'exchange':
      case 'store_credit':
      case 'refund':
      case 'repair':
      case 'replace':
      default:
        return ReturnDisposition.restock;
    }
  }
}

/// How the cash leg of the return is settled.
enum RefundChannel {
  /// Physical cash drawer — debit/credit 1000 Cash.
  cash,

  /// Bank transfer / card / wire / cheque — debit/credit 1010 Bank.
  bank,

  /// Cheque (treated like bank for routing).
  cheque,

  /// On-account: customer/supplier balance.
  ///
  /// **Sale side**:
  /// - With `partyId` AND `linkedToInvoiceId` → 1100 AR (reduce existing AR).
  /// - With `partyId` AND no original invoice → 2400 Customer Credit Liability
  ///   (held until customer applies the credit on a future sale).
  /// - Without `partyId` → policy rejects (defense-in-depth).
  ///
  /// **Purchase side**: always → 2000 AP (reduce what we owe supplier).
  credit,
}

extension RefundChannelX on RefundChannel {
  /// Wire-format string for serialising into existing `refund_method`
  /// columns and audit logs. Stable; do not rename.
  String get wireValue {
    switch (this) {
      case RefundChannel.cash:
        return 'cash';
      case RefundChannel.bank:
        return 'bank';
      case RefundChannel.cheque:
        return 'cheque';
      case RefundChannel.credit:
        return 'credit';
    }
  }

  static RefundChannel fromWire(String? raw) {
    switch (raw?.trim().toLowerCase()) {
      case 'cash':
        return RefundChannel.cash;
      case 'bank':
      case 'bank_transfer':
      case 'transfer':
      case 'wire':
      case 'card':
      case 'wallet':
      case 'mobile':
      case 'pos':
      case 'terminal':
        return RefundChannel.bank;
      case 'cheque':
      case 'check':
        return RefundChannel.cheque;
      case 'credit':
      case 'on_account':
      case 'on-account':
        return RefundChannel.credit;
      default:
        return RefundChannel.cash;
    }
  }
}

/// Origin of the return — linked to a real invoice, or unlinked.
class ReturnLink {
  /// `null` => unlinked (adjustment) return.
  final int? sourceInvoiceId;

  /// `null` => unlinked (adjustment) return.
  final String? sourceTable;

  const ReturnLink._({this.sourceInvoiceId, this.sourceTable});

  /// Linked to an existing sale/purchase invoice.
  factory ReturnLink.linked({
    required int sourceInvoiceId,
    required String sourceTable,
  }) =>
      ReturnLink._(
        sourceInvoiceId: sourceInvoiceId,
        sourceTable: sourceTable,
      );

  /// Adjustment / unlinked return (no original invoice).
  static const ReturnLink adjustment = ReturnLink._();

  bool get isLinked => sourceInvoiceId != null;
}

/// One line of a posted return — collapsed from sale_return_items,
/// sale_return_adjustment_items, purchase_return_items, and
/// purchase_return_adjustment_items.
///
/// All amounts are integer cents in the return's currency. Tax & cost are
/// pre-computed by the caller (frozen snapshots from history when linked,
/// computed at post-time when adjustment).
class PostedReturnLine {
  /// Total monetary impact of this line *including* tax. Drives Cash/AR/AP.
  final int totalCents;

  /// Tax portion within `totalCents`. Drives 2100 / 1300.
  final int taxCents;

  /// Inventory cost being moved (sum of unit_cost × qty). Drives 1200/5300/5800.
  ///
  /// May be `0` for service items (`track_inventory=false`) or for
  /// price-only adjustment returns where no physical goods move.
  final int inventoryCostCents;

  /// What happens to the goods physically. Sale-side only;
  /// purchase-side is forced to `restock` (the supplier takes them).
  final ReturnDisposition disposition;

  /// Optional product / variant pointers used for line descriptions.
  /// Not used by the policy — purely informational.
  final int? productId;
  final int? variantId;
  final int qty;

  const PostedReturnLine({
    required this.totalCents,
    required this.taxCents,
    required this.inventoryCostCents,
    this.disposition = ReturnDisposition.restock,
    this.productId,
    this.variantId,
    this.qty = 0,
  });

  /// Net (pre-tax) portion = total − tax.
  int get netCents => totalCents - taxCents;
}

/// A fully resolved, ready-to-post return. The single input shape for
/// `ReturnJournalPolicy.toJournalEntry` — produced by callers (DAOs /
/// repositories) after they have already snapshotted prices and costs.
class PostedReturn {
  final ReturnSide side;
  final ReturnLink link;

  /// `customer_id` for sales, `supplier_id` for purchases.
  /// Required when `refund == credit` for sale-side returns; absence
  /// triggers a defense-in-depth assertion in the policy.
  final int? partyId;

  /// Database row id of the return header (sale_returns / purchase_returns
  /// / sale_return_adjustments / purchase_return_adjustments).
  final int returnId;

  final RefundChannel refund;
  final int currencyId;
  final List<PostedReturnLine> lines;

  /// Optional human-readable label for the JE (`'SR-202611-0042'`, etc.).
  /// Defaults to `'<Side> Return #<returnId>'`.
  final String? referenceCode;

  /// User performing the post (audit trail).
  final int? userId;

  /// Effective accounting date of this return. Used by the fiscal-period
  /// service to block posts landing in a closed period. When `null` the
  /// pipeline falls back to `DateTime.now()`.
  final DateTime? postingDate;

  /// Phase 3 — persisted `approval_status` of the return header (one of
  /// `auto_approved` | `pending` | `approved` | `rejected`). The
  /// `ReturnPostingService` rejects any post whose status is not in
  /// `ApprovalStatus.postable`. Defaults to `auto_approved` so legacy
  /// callers that have not yet wired the approval pipeline keep working.
  final String approvalStatus;

  /// Comma-joined approval reason codes (informational; surfaced in the
  /// thrown `ReturnApprovalRequiredException` for the UI).
  final String? approvalReason;

  const PostedReturn({
    required this.side,
    required this.link,
    required this.partyId,
    required this.returnId,
    required this.refund,
    required this.currencyId,
    required this.lines,
    this.referenceCode,
    this.userId,
    this.postingDate,
    this.approvalStatus = 'auto_approved',
    this.approvalReason,
  });

  /// Convenience: total monetary impact (sum of all lines).
  int get totalCents =>
      lines.fold(0, (sum, l) => sum + l.totalCents);

  /// Convenience: aggregate tax across all lines.
  int get taxCents =>
      lines.fold(0, (sum, l) => sum + l.taxCents);

  /// Convenience: aggregate net (pre-tax) revenue/cost across all lines.
  int get netCents => totalCents - taxCents;

  /// Convenience: aggregate inventory cost — used by the policy to size
  /// the COGS / Inventory leg.
  int get totalInventoryCostCents =>
      lines.fold(0, (sum, l) => sum + l.inventoryCostCents);

  /// Inventory cost going back to **resaleable** stock (1200).
  int get restockableInventoryCostCents =>
      lines
          .where((l) => l.disposition == ReturnDisposition.restock)
          .fold(0, (sum, l) => sum + l.inventoryCostCents);

  /// Inventory cost going to **shrinkage** (5800) — sale-side only.
  int get shrinkageInventoryCostCents =>
      lines
          .where((l) =>
              l.disposition == ReturnDisposition.damaged ||
              l.disposition == ReturnDisposition.scrap)
          .fold(0, (sum, l) => sum + l.inventoryCostCents);

  /// Inventory cost parked in **Returns in Transit** (1290) — purchase-side
  /// only. Used when the supplier has not yet settled the credit note so
  /// 1200 must not yet be reduced.
  int get sendBackInventoryCostCents =>
      lines
          .where((l) => l.disposition == ReturnDisposition.sendBack)
          .fold(0, (sum, l) => sum + l.inventoryCostCents);
}
