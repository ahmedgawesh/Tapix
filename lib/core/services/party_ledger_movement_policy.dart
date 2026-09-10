/// Defines which audit rows change customer/supplier sub-ledger balances.
///
/// Immediate cash refunds are recorded as `refund` rows for traceability and
/// are audit-only. Return-cheque obligation and recognition rows use their own
/// transaction types and follow the normal balance rule.
class PartyLedgerMovementPolicy {
  const PartyLedgerMovementPolicy._();

  static bool affectsBalance(String transactionType) =>
      transactionType != 'refund' && transactionType != 'refund_reversal';
}
