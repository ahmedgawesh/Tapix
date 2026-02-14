import '../../../../core/database/app_database.dart';
import '../../../../core/database/daos/accounting_dao.dart';

/// Local datasource for journal entry and account operations
abstract class JournalLocalDatasource {
  // Accounts
  Stream<List<Account>> watchAllAccounts();
  Stream<List<Account>> watchAccountsByType(String accountType);
  Stream<Account?> watchAccount(int id);
  Future<Account?> getAccount(int id);
  Future<Account?> findByCode(String code);
  Future<List<Account>> getChildAccounts(int parentId);
  Future<int> createAccount(AccountsCompanion account);
  Future<bool> updateAccount(Account account);
  Future<int> deleteAccount(int id);
  Stream<int> watchAccountCount({bool? isActive});

  // Journal Entries
  Stream<List<JournalEntry>> watchJournalEntries();
  Stream<List<JournalEntry>> watchJournalEntriesByDateRange(DateTime start, DateTime end);
  Stream<List<JournalEntry>> watchJournalEntriesByType(String entryType);
  Stream<List<JournalEntry>> watchJournalEntriesByStatus(String status);
  Future<JournalEntry?> getJournalEntry(int id);
  Future<JournalEntry?> findJournalEntryByNumber(String entryNumber);
  Future<JournalEntry?> findJournalEntryBySource(String sourceTable, int sourceId);
  Future<List<JournalEntry>> searchJournalEntries(String query);
  Future<int> createJournalEntry(JournalEntriesCompanion entry);
  Future<bool> updateJournalEntry(JournalEntry entry);
  Future<int> createJournalEntryLine(JournalEntryLinesCompanion line);
  Future<int> deleteJournalEntryLines(int entryId);
  Stream<int> watchJournalEntryCount({String? status});
  Future<String> generateNextEntryNumber();

  // Journal Entry Lines
  Stream<List<JournalEntryLine>> watchJournalEntryLines(int entryId);
  Future<List<JournalEntryLine>> getJournalEntryLines(int entryId);
  Stream<List<JournalEntryLine>> watchJournalLinesByAccount(int accountId);

  // Accounting Periods
  Stream<List<AccountingPeriod>> watchAccountingPeriods();
  Future<AccountingPeriod?> getActiveAccountingPeriod();
  Future<int> createAccountingPeriod(AccountingPeriodsCompanion period);
  Future<bool> updateAccountingPeriod(AccountingPeriod period);

  // Trial Balance & Reconciliation
  Future<List<Account>> getAllActiveAccounts();
  Future<List<JournalEntry>> getPostedJournalEntries();
  Future<bool> isDateInClosedPeriod(DateTime date);
  Future<int> getCustomerBalanceTotal();
  Future<int> getSupplierBalanceTotal();

  // Date-Range Queries
  Stream<List<JournalEntryLine>> watchPostedLinesByDateRange(
    DateTime startDate, DateTime endDate);
  Stream<List<JournalEntryLine>> watchPostedLinesByAccountAndDateRange(
    int accountId, DateTime startDate, DateTime endDate);
}

/// Implementation of JournalLocalDatasource using AccountingDao
class JournalLocalDatasourceImpl implements JournalLocalDatasource {
  final AccountingDao _accountingDao;

  JournalLocalDatasourceImpl(this._accountingDao);

  // ── Accounts ──────────────────────────────────────────────

  @override
  Stream<List<Account>> watchAllAccounts() => _accountingDao.watchAllAccounts();

  @override
  Stream<List<Account>> watchAccountsByType(String accountType) =>
      _accountingDao.watchAccountsByType(accountType);

  @override
  Stream<Account?> watchAccount(int id) => _accountingDao.watchAccount(id);

  @override
  Future<Account?> getAccount(int id) => _accountingDao.getAccount(id);

  @override
  Future<Account?> findByCode(String code) => _accountingDao.findByCode(code);

  @override
  Future<List<Account>> getChildAccounts(int parentId) =>
      _accountingDao.getChildAccounts(parentId);

  @override
  Future<int> createAccount(AccountsCompanion account) =>
      _accountingDao.createAccount(account);

  @override
  Future<bool> updateAccount(Account account) =>
      _accountingDao.updateAccount(account);

  @override
  Future<int> deleteAccount(int id) => _accountingDao.deleteAccount(id);

  @override
  Stream<int> watchAccountCount({bool? isActive}) =>
      _accountingDao.watchAccountCount(isActive: isActive);

  // ── Journal Entries ───────────────────────────────────────

  @override
  Stream<List<JournalEntry>> watchJournalEntries() =>
      _accountingDao.watchJournalEntries();

  @override
  Stream<List<JournalEntry>> watchJournalEntriesByDateRange(DateTime start, DateTime end) =>
      _accountingDao.watchJournalEntriesByDateRange(start, end);

  @override
  Stream<List<JournalEntry>> watchJournalEntriesByType(String entryType) =>
      _accountingDao.watchJournalEntriesByType(entryType);

  @override
  Stream<List<JournalEntry>> watchJournalEntriesByStatus(String status) =>
      _accountingDao.watchJournalEntriesByStatus(status);

  @override
  Future<JournalEntry?> getJournalEntry(int id) =>
      _accountingDao.getJournalEntry(id);

  @override
  Future<JournalEntry?> findJournalEntryByNumber(String entryNumber) =>
      _accountingDao.findJournalEntryByNumber(entryNumber);

  @override
  Future<JournalEntry?> findJournalEntryBySource(String sourceTable, int sourceId) =>
      _accountingDao.findJournalEntryBySource(sourceTable, sourceId);

  @override
  Future<List<JournalEntry>> searchJournalEntries(String query) =>
      _accountingDao.searchJournalEntries(query);

  @override
  Future<int> createJournalEntry(JournalEntriesCompanion entry) =>
      _accountingDao.createJournalEntry(entry);

  @override
  Future<bool> updateJournalEntry(JournalEntry entry) =>
      _accountingDao.updateJournalEntry(entry);

  @override
  Future<int> createJournalEntryLine(JournalEntryLinesCompanion line) =>
      _accountingDao.createJournalEntryLine(line);

  @override
  Future<int> deleteJournalEntryLines(int entryId) =>
      _accountingDao.deleteJournalEntryLines(entryId);

  @override
  Stream<int> watchJournalEntryCount({String? status}) =>
      _accountingDao.watchJournalEntryCount(status: status);

  @override
  Future<String> generateNextEntryNumber() =>
      _accountingDao.generateNextEntryNumber();

  // ── Journal Entry Lines ───────────────────────────────────

  @override
  Stream<List<JournalEntryLine>> watchJournalEntryLines(int entryId) =>
      _accountingDao.watchJournalEntryLines(entryId);

  @override
  Future<List<JournalEntryLine>> getJournalEntryLines(int entryId) =>
      _accountingDao.getJournalEntryLines(entryId);

  @override
  Stream<List<JournalEntryLine>> watchJournalLinesByAccount(int accountId) =>
      _accountingDao.watchJournalLinesByAccount(accountId);

  // ── Accounting Periods ────────────────────────────────────

  @override
  Stream<List<AccountingPeriod>> watchAccountingPeriods() =>
      _accountingDao.watchAccountingPeriods();

  @override
  Future<AccountingPeriod?> getActiveAccountingPeriod() =>
      _accountingDao.getActiveAccountingPeriod();

  @override
  Future<int> createAccountingPeriod(AccountingPeriodsCompanion period) =>
      _accountingDao.createAccountingPeriod(period);

  @override
  Future<bool> updateAccountingPeriod(AccountingPeriod period) =>
      _accountingDao.updateAccountingPeriod(period);

  // ── Trial Balance & Reconciliation ─────────────────────

  @override
  Future<List<Account>> getAllActiveAccounts() =>
      _accountingDao.getAllActiveAccounts();

  @override
  Future<List<JournalEntry>> getPostedJournalEntries() =>
      _accountingDao.getPostedJournalEntries();

  @override
  Future<bool> isDateInClosedPeriod(DateTime date) =>
      _accountingDao.isDateInClosedPeriod(date);

  @override
  Future<int> getCustomerBalanceTotal() async {
    final db = _accountingDao.attachedDatabase;
    final row = await _accountingDao.customSelect(
      'SELECT COALESCE(SUM(balance_cents), 0) AS total FROM customers',
      readsFrom: {db.customers},
    ).getSingle();
    return row.read<int>('total');
  }

  @override
  Future<int> getSupplierBalanceTotal() async {
    final db = _accountingDao.attachedDatabase;
    final row = await _accountingDao.customSelect(
      'SELECT COALESCE(SUM(balance_cents), 0) AS total FROM suppliers',
      readsFrom: {db.suppliers},
    ).getSingle();
    return row.read<int>('total');
  }

  // ── Date-Range Queries ──────────────────────────────────

  @override
  Stream<List<JournalEntryLine>> watchPostedLinesByDateRange(
    DateTime startDate, DateTime endDate) =>
      _accountingDao.watchPostedLinesByDateRange(startDate, endDate);

  @override
  Stream<List<JournalEntryLine>> watchPostedLinesByAccountAndDateRange(
    int accountId, DateTime startDate, DateTime endDate) =>
      _accountingDao.watchPostedLinesByAccountAndDateRange(accountId, startDate, endDate);
}
