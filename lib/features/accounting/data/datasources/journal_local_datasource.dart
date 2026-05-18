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
    // ── Phase 15.2 — Batch ledger is SoT only for FIFO/batch products ───
    //
    // Pre-Phase-15 this was `Σ(variant.stock × variant.cost_cents)` for
    // ALL products. Phase 15.0 then made `product_batches` authoritative
    // whenever ANY active batch existed for a variant. That was correct
    // for FIFO/batch products but wrong for WAC products: Phase 6.4
    // unified the write side and creates a `product_batches` row for
    // EVERY tracked purchase line — but only the FIFO consumption paths
    // (`BatchService.consumeFifo`, `_isFifoProduct(productId) == true`
    // in `PurchaseDao.postPurchaseReturn` / `SaleDao.postSaleReturn` /
    // `AdjustmentReturnDao`) decrement `remaining_quantity`. WAC return
    // paths only adjust `variant.stock_quantity` and post the
    // `1200 Inventory` GL leg — they NEVER touch the batch row.
    //
    // Result: a WAC product's batch rows are write-once / read-stale.
    // Reading them as authoritative valuation produced a phantom drift
    // exactly equal to `(returned_qty × unit_cost)` on every linked or
    // adjustment purchase return against a WAC product (field report
    // 2026-05-18, backup `tapix_backup_20260518_061018.db` — 9 900¢
    // drift after one 1-unit linked purchase return on a WAC variant).
    //
    // **Single rule**: the read predicate gating the batch branch must
    // mirror the write predicate `_isFifoProduct` (FIFO ⇔ batch ledger
    // is the SoT). Anything else is asymmetric and accumulates drift.
    //
    //   Branch 1 (batch ledger):   product is FIFO/batch + active batch
    //   Branch 2 (variant):        product is WAC ............ OR
    //                              product is FIFO but variant has no
    //                              active batch (pre-10044 legacy)
    //   Branch 3 (product):        same predicate as Branch 2 but for
    //                              products without variants
    //
    // The legacy fallback inside Branches 2/3 keeps pre-batch FIFO data
    // visible. Soft-deleted (`is_active = 0`) batches stay excluded so
    // a void cleanly removes a layer from the SoT.
    final row = await _accountingDao.customSelect(
      '''
      SELECT
        COALESCE((
          SELECT SUM(
            CAST(b.remaining_quantity AS INTEGER) *
            CAST(b.unit_cost_cents AS INTEGER)
          )
          FROM product_batches b
          INNER JOIN products p ON p.id = b.product_id
          WHERE b.is_active = 1
            AND (p.inventory_tracking_type IN ('batch', 'batch_expiry')
                 OR p.costing_method = 'fifo')
        ), 0)
        +
        COALESCE((
          SELECT SUM(
            CAST(v.stock_quantity AS INTEGER) *
            CAST(v.cost_cents AS INTEGER)
          )
          FROM product_variants v
          INNER JOIN products p ON p.id = v.product_id
          WHERE NOT (p.inventory_tracking_type IN ('batch', 'batch_expiry')
                     OR p.costing_method = 'fifo')
             OR NOT EXISTS (
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
          AND (
            NOT (p.inventory_tracking_type IN ('batch', 'batch_expiry')
                 OR p.costing_method = 'fifo')
            OR NOT EXISTS (
              SELECT 1 FROM product_batches b
              WHERE b.product_id = p.id AND b.is_active = 1
            )
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
