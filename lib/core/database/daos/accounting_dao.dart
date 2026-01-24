import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/accounting.dart';

part 'accounting_dao.g.dart';

@DriftAccessor(tables: [Accounts, JournalEntries, JournalEntryLines, AccountingPeriods, Expenses])
class AccountingDao extends DatabaseAccessor<AppDatabase> with _$AccountingDaoMixin {
  AccountingDao(super.db);

  Stream<List<Account>> watchAllAccounts() {
    return (select(accounts)
          ..where((a) => a.isActive.equals(true))
          ..orderBy([(a) => OrderingTerm(expression: a.accountCode)]))
        .watch();
  }

  Stream<Account?> watchAccount(int id) {
    return (select(accounts)..where((a) => a.id.equals(id))).watchSingleOrNull();
  }

  Future<Account?> findByCode(String code) {
    return (select(accounts)..where((a) => a.accountCode.equals(code))).getSingleOrNull();
  }

  Future<int> createAccount(AccountsCompanion account) {
    return into(accounts).insert(account);
  }

  Future<int> createJournalEntry(JournalEntriesCompanion entry) {
    return into(journalEntries).insert(entry);
  }

  Future<int> createJournalEntryLine(JournalEntryLinesCompanion line) {
    return into(journalEntryLines).insert(line);
  }

  Stream<List<JournalEntry>> watchJournalEntries() {
    return (select(journalEntries)..orderBy([(j) => OrderingTerm(expression: j.entryDate, mode: OrderingMode.desc)])).watch();
  }

  Stream<List<JournalEntryLine>> watchJournalEntryLines(int entryId) {
    return (select(journalEntryLines)..where((l) => l.journalEntryId.equals(entryId))).watch();
  }

  Future<int> createExpense(ExpensesCompanion expense) {
    return into(expenses).insert(expense);
  }

  Stream<List<Expense>> watchExpenses() {
    return (select(expenses)..orderBy([(e) => OrderingTerm(expression: e.expenseDate, mode: OrderingMode.desc)])).watch();
  }
}
