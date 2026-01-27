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

  /// Check if this is a debit balance
  bool get isDebitBalance => debitCents > creditCents;

  /// Check if this is a credit balance
  bool get isCreditBalance => creditCents > debitCents;

  /// Check if balance is zero
  bool get isZeroBalance => debitCents == 0 && creditCents == 0;
}
