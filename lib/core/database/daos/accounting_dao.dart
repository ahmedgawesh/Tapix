import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/accounting.dart';
import '../tables/settings.dart';

part 'accounting_dao.g.dart';

@DriftAccessor(
  tables: [
    Accounts,
    JournalEntries,
    JournalEntryLines,
    AccountingPeriods,
    Expenses,
    ExpenseCategories,
  ],
)
class AccountingDao extends DatabaseAccessor<AppDatabase>
    with _$AccountingDaoMixin {
  AccountingDao(super.db);

  // ── Accounts ──────────────────────────────────────────────

  Stream<List<Account>> watchAllAccounts() {
    return (select(accounts)
          ..where((a) => a.isActive.equals(true))
          ..orderBy([(a) => OrderingTerm(expression: a.accountCode)]))
        .watch();
  }

  Stream<Account?> watchAccount(int id) {
    return (select(
      accounts,
    )..where((a) => a.id.equals(id))).watchSingleOrNull();
  }

  Future<Account?> findByCode(String code) {
    return (select(
      accounts,
    )..where((a) => a.accountCode.equals(code))).getSingleOrNull();
  }

  Future<int> createAccount(AccountsCompanion account) {
    return into(accounts).insert(account);
  }

  Future<bool> updateAccount(Account account) async {
    final existing = await getAccount(account.id);
    if (existing?.isSystemAccount ?? false) {
      throw StateError(
        'System posting accounts cannot be edited through account CRUD.',
      );
    }
    return update(accounts).replace(account);
  }

  Future<int> deleteAccount(int id) async {
    final existing = await getAccount(id);
    if (existing?.isSystemAccount ?? false) {
      throw StateError('System posting accounts cannot be deleted.');
    }
    return (delete(accounts)..where((a) => a.id.equals(id))).go();
  }

  Stream<List<Account>> watchAccountsByType(String accountType) {
    return (select(accounts)
          ..where(
            (a) => a.accountType.equals(accountType) & a.isActive.equals(true),
          )
          ..orderBy([(a) => OrderingTerm(expression: a.accountCode)]))
        .watch();
  }

  Future<List<Account>> getChildAccounts(int parentId) {
    return (select(
      accounts,
    )..where((a) => a.parentAccountId.equals(parentId))).get();
  }

  Future<Account?> getAccount(int id) {
    return (select(accounts)..where((a) => a.id.equals(id))).getSingleOrNull();
  }

  Stream<int> watchAccountCount({bool? isActive}) {
    final countExp = accounts.id.count();
    final query = selectOnly(accounts)..addColumns([countExp]);
    if (isActive != null) {
      query.where(accounts.isActive.equals(isActive));
    }
    return query.map((row) => row.read(countExp) ?? 0).watchSingle();
  }

  // ── Journal Entries ───────────────────────────────────────

  Future<int> createJournalEntry(JournalEntriesCompanion entry) {
    return into(journalEntries).insert(entry);
  }

  Future<bool> updateJournalEntry(JournalEntry entry) {
    return update(journalEntries).replace(entry);
  }

  Future<int> createJournalEntryLine(JournalEntryLinesCompanion line) {
    return into(journalEntryLines).insert(line);
  }

  Future<int> deleteJournalEntryLines(int entryId) {
    return (delete(
      journalEntryLines,
    )..where((l) => l.journalEntryId.equals(entryId))).go();
  }

  Stream<List<JournalEntry>> watchJournalEntries() {
    return (select(journalEntries)..orderBy([
          (j) => OrderingTerm(expression: j.entryDate, mode: OrderingMode.desc),
        ]))
        .watch();
  }

  Stream<List<JournalEntry>> watchJournalEntriesByDateRange(
    DateTime start,
    DateTime end,
  ) {
    return (select(journalEntries)
          ..where(
            (j) =>
                j.entryDate.isBiggerOrEqualValue(start) &
                j.entryDate.isSmallerOrEqualValue(end),
          )
          ..orderBy([
            (j) =>
                OrderingTerm(expression: j.entryDate, mode: OrderingMode.desc),
          ]))
        .watch();
  }

  Stream<List<JournalEntry>> watchJournalEntriesByType(String entryType) {
    return (select(journalEntries)
          ..where((j) => j.entryType.equals(entryType))
          ..orderBy([
            (j) =>
                OrderingTerm(expression: j.entryDate, mode: OrderingMode.desc),
          ]))
        .watch();
  }

  Stream<List<JournalEntry>> watchJournalEntriesByStatus(String status) {
    return (select(journalEntries)
          ..where((j) => j.status.equals(status))
          ..orderBy([
            (j) =>
                OrderingTerm(expression: j.entryDate, mode: OrderingMode.desc),
          ]))
        .watch();
  }

  Future<JournalEntry?> getJournalEntry(int id) {
    return (select(
      journalEntries,
    )..where((j) => j.id.equals(id))).getSingleOrNull();
  }

  Future<JournalEntry?> findJournalEntryByNumber(String entryNumber) {
    return (select(
      journalEntries,
    )..where((j) => j.entryNumber.equals(entryNumber))).getSingleOrNull();
  }

  Future<JournalEntry?> findJournalEntryBySource(
    String sourceTable,
    int sourceId,
  ) {
    return (select(journalEntries)..where(
          (j) =>
              j.sourceTable.equals(sourceTable) & j.sourceId.equals(sourceId),
        ))
        .getSingleOrNull();
  }

  Stream<List<JournalEntryLine>> watchJournalEntryLines(int entryId) {
    return (select(journalEntryLines)
          ..where((l) => l.journalEntryId.equals(entryId))
          ..orderBy([(l) => OrderingTerm(expression: l.lineNumber)]))
        .watch();
  }

  Future<List<JournalEntryLine>> getJournalEntryLines(int entryId) {
    return (select(journalEntryLines)
          ..where((l) => l.journalEntryId.equals(entryId))
          ..orderBy([(l) => OrderingTerm(expression: l.lineNumber)]))
        .get();
  }

  Stream<List<JournalEntryLine>> watchJournalLinesByAccount(int accountId) {
    final query = select(journalEntryLines).join([
      innerJoin(
        journalEntries,
        journalEntries.id.equalsExp(journalEntryLines.journalEntryId),
      ),
    ]);
    query.where(
      journalEntryLines.accountId.equals(accountId) &
          journalEntries.status.equals('posted'),
    );
    query.orderBy([
      OrderingTerm(
        expression: journalEntries.entryDate,
        mode: OrderingMode.desc,
      ),
      OrderingTerm(
        expression: journalEntryLines.lineNumber,
        mode: OrderingMode.asc,
      ),
    ]);
    return query.map((row) => row.readTable(journalEntryLines)).watch();
  }

  Future<List<JournalEntry>> searchJournalEntries(String query) {
    return (select(journalEntries)
          ..where(
            (j) =>
                j.description.like('%$query%') | j.entryNumber.like('%$query%'),
          )
          ..orderBy([
            (j) =>
                OrderingTerm(expression: j.entryDate, mode: OrderingMode.desc),
          ]))
        .get();
  }

  Stream<int> watchJournalEntryCount({String? status}) {
    final countExp = journalEntries.id.count();
    final query = selectOnly(journalEntries)..addColumns([countExp]);
    if (status != null) {
      query.where(journalEntries.status.equals(status));
    }
    return query.map((row) => row.read(countExp) ?? 0).watchSingle();
  }

  Future<String> generateNextEntryNumber() async {
    final maxNum = journalEntries.id.max();
    final query = selectOnly(journalEntries)..addColumns([maxNum]);
    final result = await query.getSingle();
    final nextId = (result.read(maxNum) ?? 0) + 1;
    return 'JE-${nextId.toString().padLeft(6, '0')}';
  }

  // ── Accounting Periods ──────────────────────────────────

  Stream<List<AccountingPeriod>> watchAccountingPeriods() {
    return (select(accountingPeriods)..orderBy([
          (p) => OrderingTerm(expression: p.startDate, mode: OrderingMode.desc),
        ]))
        .watch();
  }

  Future<AccountingPeriod?> getActiveAccountingPeriod() {
    return (select(accountingPeriods)
          ..where((p) => p.isClosed.equals(false))
          ..orderBy([
            (p) =>
                OrderingTerm(expression: p.startDate, mode: OrderingMode.desc),
          ]))
        .getSingleOrNull();
  }

  Future<int> createAccountingPeriod(AccountingPeriodsCompanion period) {
    return into(accountingPeriods).insert(period);
  }

  Future<bool> updateAccountingPeriod(AccountingPeriod period) {
    return update(accountingPeriods).replace(period);
  }

  // ── Date-Range Queries ──────────────────────────────────

  /// Watch posted journal entry lines within a date range.
  /// Joins journal_entry_lines with journal_entries to filter by entry_date and status='posted'.
  Stream<List<JournalEntryLine>> watchPostedLinesByDateRange(
    DateTime startDate,
    DateTime endDate,
  ) {
    final query = select(journalEntryLines).join([
      innerJoin(
        journalEntries,
        journalEntries.id.equalsExp(journalEntryLines.journalEntryId),
      ),
    ]);
    query.where(
      journalEntries.status.equals('posted') &
          journalEntries.entryDate.isBiggerOrEqualValue(startDate) &
          journalEntries.entryDate.isSmallerOrEqualValue(endDate),
    );
    query.orderBy([OrderingTerm(expression: journalEntries.entryDate)]);
    return query.watch().map(
      (rows) => rows.map((row) => row.readTable(journalEntryLines)).toList(),
    );
  }

  /// Watch posted journal entry lines for a specific account within a date range.
  Stream<List<JournalEntryLine>> watchPostedLinesByAccountAndDateRange(
    int accountId,
    DateTime startDate,
    DateTime endDate,
  ) {
    final query = select(journalEntryLines).join([
      innerJoin(
        journalEntries,
        journalEntries.id.equalsExp(journalEntryLines.journalEntryId),
      ),
    ]);
    query.where(
      journalEntryLines.accountId.equals(accountId) &
          journalEntries.status.equals('posted') &
          journalEntries.entryDate.isBiggerOrEqualValue(startDate) &
          journalEntries.entryDate.isSmallerOrEqualValue(endDate),
    );
    query.orderBy([OrderingTerm(expression: journalEntries.entryDate)]);
    return query.watch().map(
      (rows) => rows.map((row) => row.readTable(journalEntryLines)).toList(),
    );
  }

  // ── Trial Balance & Reconciliation ───────────────────────

  Future<List<Account>> getAllActiveAccounts() {
    return (select(accounts)
          ..where((a) => a.isActive.equals(true))
          ..orderBy([(a) => OrderingTerm(expression: a.accountCode)]))
        .get();
  }

  Future<List<JournalEntry>> getPostedJournalEntries() {
    return (select(
      journalEntries,
    )..where((e) => e.status.equals('posted'))).get();
  }

  Future<bool> isDateInClosedPeriod(DateTime date) async {
    final closedPeriods =
        await (select(accountingPeriods)
              ..where((p) => p.isClosed.equals(true))
              ..where((p) => p.startDate.isSmallerOrEqualValue(date))
              ..where((p) => p.endDate.isBiggerOrEqualValue(date)))
            .get();
    return closedPeriods.isNotEmpty;
  }

  // ── Expense Categories ────────────────────────────────────

  Stream<List<ExpenseCategory>> watchAllExpenseCategories({bool? isActive}) {
    final query = select(expenseCategories);
    if (isActive != null) {
      query.where((c) => c.isActive.equals(isActive));
    }
    query.orderBy([(c) => OrderingTerm(expression: c.name)]);
    return query.watch();
  }

  Future<ExpenseCategory?> getExpenseCategory(int id) {
    return (select(
      expenseCategories,
    )..where((c) => c.id.equals(id))).getSingleOrNull();
  }

  Future<ExpenseCategory?> findExpenseCategoryByName(String name) {
    return (select(
      expenseCategories,
    )..where((c) => c.name.equals(name))).getSingleOrNull();
  }

  Future<int> createExpenseCategory(ExpenseCategoriesCompanion category) {
    return into(expenseCategories).insert(category);
  }

  Future<bool> updateExpenseCategory(ExpenseCategory category) {
    return update(expenseCategories).replace(category);
  }

  Future<int> deleteExpenseCategory(int id) {
    return (delete(expenseCategories)..where((c) => c.id.equals(id))).go();
  }

  Stream<int> watchExpenseCategoryCount({bool? isActive}) {
    final countExp = expenseCategories.id.count();
    final query = selectOnly(expenseCategories)..addColumns([countExp]);
    if (isActive != null) {
      query.where(expenseCategories.isActive.equals(isActive));
    }
    return query.map((row) => row.read(countExp) ?? 0).watchSingle();
  }

  // ── Expenses ──────────────────────────────────────────────

  Future<int> createExpense(ExpensesCompanion expense) {
    return into(expenses).insert(expense);
  }

  Future<bool> updateExpense(Expense expense) {
    return update(expenses).replace(expense);
  }

  Future<int> deleteExpense(int id) {
    return (delete(expenses)..where((e) => e.id.equals(id))).go();
  }

  Future<Expense?> getExpense(int id) {
    return (select(expenses)..where((e) => e.id.equals(id))).getSingleOrNull();
  }

  Stream<List<Expense>> watchExpenses() {
    return (select(expenses)..orderBy([
          (e) =>
              OrderingTerm(expression: e.expenseDate, mode: OrderingMode.desc),
        ]))
        .watch();
  }

  Stream<List<Expense>> watchExpensesByCategory(int categoryId) {
    return (select(expenses)
          ..where((e) => e.categoryId.equals(categoryId))
          ..orderBy([
            (e) => OrderingTerm(
              expression: e.expenseDate,
              mode: OrderingMode.desc,
            ),
          ]))
        .watch();
  }

  Stream<List<Expense>> watchExpensesByDateRange(DateTime start, DateTime end) {
    return (select(expenses)
          ..where(
            (e) =>
                e.expenseDate.isBiggerOrEqualValue(start) &
                e.expenseDate.isSmallerOrEqualValue(end),
          )
          ..orderBy([
            (e) => OrderingTerm(
              expression: e.expenseDate,
              mode: OrderingMode.desc,
            ),
          ]))
        .watch();
  }

  Future<List<Expense>> searchExpenses(String query) {
    return (select(expenses)
          ..where((e) => e.description.like('%$query%'))
          ..orderBy([
            (e) => OrderingTerm(
              expression: e.expenseDate,
              mode: OrderingMode.desc,
            ),
          ]))
        .get();
  }

  Stream<int> watchExpenseCount() {
    final countExp = expenses.id.count();
    final query = selectOnly(expenses)..addColumns([countExp]);
    return query.map((row) => row.read(countExp) ?? 0).watchSingle();
  }

  Stream<int> watchTotalExpenseCents() {
    final sumExp = expenses.amountCents.sum();
    final query = selectOnly(expenses)..addColumns([sumExp]);
    return query.map((row) => row.read(sumExp) ?? 0).watchSingle();
  }
}
