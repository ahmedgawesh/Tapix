/// Purchase returns remove goods and reverse the supplier invoice. A
/// replacement is credited on account; its incoming goods need a new purchase.
/// Keep `restock` as the historic wire value for returning goods to the vendor.
abstract final class PurchaseReturnDispositionPolicy {
  static const supported = {'restock', 'replace', 'write_off'};

  static String? validate({
    required String disposition,
    required String refundMethod,
    String? reason,
    bool hasSettlementAllocations = false,
  }) {
    if (!supported.contains(disposition)) {
      return 'invalid_disposition';
    }
    if (disposition == 'replace' &&
        (refundMethod != 'credit' || hasSettlementAllocations)) {
      return 'replacement_requires_credit';
    }
    if (disposition == 'write_off' && (reason?.trim().isEmpty ?? true)) {
      return 'supplier_write_off_reason_required';
    }
    return null;
  }
}
