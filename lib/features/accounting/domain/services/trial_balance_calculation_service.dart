import '../../../../core/database/app_database.dart';
import '../models/trial_balance.dart';

/// Pure trial-balance classifier shared by repository and period reports.
class TrialBalanceCalculationService {
  const TrialBalanceCalculationService._();

  static TrialBalance calculate({
    required List<Account> accounts,
    required Iterable<JournalEntryLine> lines,
    required DateTime asOfDate,
  }) {
    final balanceByAccountId = <int, int>{};

    for (final line in lines) {
      final debit = line.debitCents.toBigInt().toInt();
      final credit = line.creditCents.toBigInt().toInt();
      balanceByAccountId.update(
        line.accountId,
        (value) => value + debit - credit,
        ifAbsent: () => debit - credit,
      );
    }

    var totalDebits = 0;
    var totalCredits = 0;
    final items = <TrialBalanceItem>[];

    for (final account in accounts) {
      final rawBalance = balanceByAccountId[account.id] ?? 0;
      var debit = 0;
      var credit = 0;
      final type = account.accountType.toLowerCase();

      if (type == 'asset' || type == 'expense') {
        if (rawBalance >= 0) {
          debit = rawBalance;
        } else {
          credit = -rawBalance;
        }
      } else {
        final naturalBalance = -rawBalance;
        if (naturalBalance >= 0) {
          credit = naturalBalance;
        } else {
          debit = -naturalBalance;
        }
      }

      totalDebits += debit;
      totalCredits += credit;
      items.add(
        TrialBalanceItem(
          accountId: account.id,
          accountCode: account.accountCode,
          accountName: account.accountName,
          accountType: account.accountType,
          debitCents: debit,
          creditCents: credit,
        ),
      );
    }

    return TrialBalance(
      asOfDate: asOfDate,
      items: items,
      totalDebitCents: totalDebits,
      totalCreditCents: totalCredits,
      isBalanced: totalDebits == totalCredits,
    );
  }
}
