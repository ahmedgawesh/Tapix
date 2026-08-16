/// Defines which audit rows change customer/supplier sub-ledger balances.
///
/// Cash/cheque returns are recorded as `refund` rows for traceability, but
/// their settlement is against cash/bank rather than receivables/payables.
/// Their reversals are therefore audit-only as well.
class PartyLedgerMovementPolicy {
  const PartyLedgerMovementPolicy._();

  static bool affectsBalance(String transactionType) =>
      transactionType != 'refund' && transactionType != 'refund_reversal';
}
