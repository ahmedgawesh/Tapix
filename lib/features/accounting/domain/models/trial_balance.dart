/// Trial Balance report model
class TrialBalance {
  final DateTime asOfDate;
  final List<TrialBalanceItem> items;
  final int totalDebitCents;
  final int totalCreditCents;
  final bool isBalanced;

  TrialBalance({
    required this.asOfDate,
    required this.items,
    required this.totalDebitCents,
    required this.totalCreditCents,
    required this.isBalanced,
  });

  /// Get difference between debits and credits
  int get differenceCents => totalDebitCents - totalCreditCents;

  /// Get items with non-zero balances only
  List<TrialBalanceItem> get nonZeroItems =>
      items.where((item) => item.debitCents > 0 || item.creditCents > 0).toList();

  /// Get items by account type
  List<TrialBalanceItem> getItemsByType(String accountType) =>
      items.where((item) => item.accountType.toLowerCase() == accountType.toLowerCase()).toList();

  /// Get total for a specific account type
  int getTotalDebitsByType(String accountType) =>
      getItemsByType(accountType).fold(0, (sum, item) => sum + item.debitCents);

  int getTotalCreditsByType(String accountType) =>
      getItemsByType(accountType).fold(0, (sum, item) => sum + item.creditCents);

  /// Phase 7 — Reporting consolidation SoT.
  ///
  /// Returns the **natural (normal) balance total** for a given account type:
  ///   - Asset / Expense    → Σ(debit − credit)
  ///   - Liability / Equity / Revenue → Σ(credit − debit)
  ///
  /// This collapses the `fold((sum, i) => sum + i.creditCents - i.debitCents)`
  /// / `(sum + i.debitCents - i.creditCents)` patterns that were duplicated
  /// across P&L, balance-sheet, financial-management-hub and
  /// accounting-close-service. Sole owner of account-type signing for reports.
  int totalForType(String accountType) => getItemsByType(accountType)
      .fold(0, (sum, item) => sum + item.naturalBalanceCents);
}

/// Individual item in trial balance
class TrialBalanceItem {
  final int accountId;
  final String accountCode;
  final String accountName;
  final String accountType;
  final int debitCents;
  final int creditCents;

  TrialBalanceItem({
    required this.accountId,
    required this.accountCode,
    required this.accountName,
    required this.accountType,
    required this.debitCents,
    required this.creditCents,
  });

  /// Get net balance (debit - credit)
  int get netBalanceCents => debitCents - creditCents;

  /// Phase 7 — Returns the **natural (normal) balance** for this row:
  ///   - Asset / Expense    → debit − credit
  ///   - Liability / Equity / Revenue → credit − debit
  ///
  /// Unknown types fall back to `debit − credit` (safe default; matches
  /// `netBalanceCents`). Sole owner of per-row account-type signing.
  int get naturalBalanceCents {
    switch (accountType.toLowerCase()) {
      case 'liability':
      case 'equity':
      case 'revenue':
        return creditCents - debitCents;
      case 'asset':
      case 'expense':
      default:
        return debitCents - creditCents;
    }
  }

  /// Check if this is a debit balance
  bool get isDebitBalance => debitCents > creditCents;

  /// Check if this is a credit balance
  bool get isCreditBalance => creditCents > debitCents;

  /// Check if balance is zero
  bool get isZeroBalance => debitCents == 0 && creditCents == 0;
}
