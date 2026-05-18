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

  /// Σ(stock_quantity × cost_cents) across the whole stock ledger — the
  /// physical book value of inventory in cents. Used by the reconciliation
  /// engine to verify that account 1200 Inventory in the GL stays aligned
  /// with the on-hand × cost product of every SKU on the books, regardless
  /// of whether the SKU is currently active. Soft-deleted variants (and
  /// orphan products without variants) MUST be included because their
  /// previous purchase / opening-balance journal entries still sit on the
  /// 1200 ledger, so excluding them would falsely report a mismatch.
  Future<int> getTotalInventoryValueCents();

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

  @override
  Future<int> getTotalInventoryValueCents() async {
    final db = _accountingDao.attachedDatabase;
    // ── Phase 15.0 — Batch-ledger-authoritative formula ─────────────────
    //
    // Pre-Phase-15 this was `Σ(variant.stock × variant.cost_cents)` for
    // ALL products. That formula is correct ONLY for products whose
    // `costing_method = 'wac'` (cost_cents is the moving-average cost
    // basis on every layer). For products configured as `'fifo'` /
    // `'last'`, `cost_cents` is a DISPLAY value — it always holds the
    // most-recent paid unit cost — so the per-layer cost basis lives in
    // `product_batches.unit_cost_cents` and `Σ(stock × cost_cents)`
    // systematically under- or over-reports valuation as soon as two
    // purchase lines for the same SKU carry different effective unit
    // costs (e.g. a trade-discounted re-stock).
    //
    // Field-reported manifestation (May 2026): a `fifo` / `batch_expiry`
    // product was bought at 9,900¢/unit (qty 10) and re-bought at 9,801¢
    // /unit (qty 3, after 99¢/unit discount). GL(1200 Inventory) =
    // 99,000 + 29,403 = 128,403. `variant.cost_cents` = 9,801 (last).
    // 13 × 9,801 = 127,413 → reconciliation engine reported a 990¢
    // false drift. The books were correct; the formula was wrong.
    //
    // New formula: **prefer the batch ledger** when active batch rows
    // exist for the variant (FIFO products always have batches; WAC
    // products also get a batch row per purchase line because Phase 6.4
    // unified the ledger). Fall back to `variant.stock × variant.cost`
    // ONLY for variants that genuinely have no batch coverage
    // (extremely rare — legacy data, or non-batched WAC products that
    // pre-date 10044). Same dual-fallback for products without variants.
    //
    // The variant/product fallback keeps the WAC happy path identical
    // for pre-batch DBs and preserves the inactive-variant inclusion
    // that prevents soft-delete from triggering a false mismatch
    // (variants stay in the SUM via the batch ledger as long as the
    // batches are still `is_active = 1`).
    final row = await _accountingDao.customSelect(
      '''
      SELECT
        COALESCE((
          SELECT SUM(
            CAST(b.remaining_quantity AS INTEGER) *
            CAST(b.unit_cost_cents AS INTEGER)
          )
          FROM product_batches b
          WHERE b.is_active = 1
        ), 0)
        +
        COALESCE((
          SELECT SUM(
            CAST(v.stock_quantity AS INTEGER) *
            CAST(v.cost_cents AS INTEGER)
          )
          FROM product_variants v
          WHERE NOT EXISTS (
            SELECT 1 FROM product_batches b
            WHERE b.variant_id = v.id AND b.is_active = 1
          )
        ), 0)
        +
        COALESCE((
          SELECT SUM(
            CAST(p.stock_quantity AS INTEGER) *
            CAST(p.cost_cents AS INTEGER)
          )
          FROM products p
          WHERE NOT EXISTS (
            SELECT 1 FROM product_variants v WHERE v.product_id = p.id
          )
          AND NOT EXISTS (
            SELECT 1 FROM product_batches b
            WHERE b.product_id = p.id AND b.is_active = 1
          )
        ), 0)
        AS total
      ''',
      readsFrom: {
        db.products,
        db.productVariants,
        db.productBatches,
      },
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
