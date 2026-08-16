import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import '../../../../core/database/app_database.dart';
import '../../domain/models/journal_entry_data.dart';
import '../../domain/models/trial_balance.dart';
import '../../domain/models/reconciliation_result.dart';
import '../../domain/repositories/journal_repository.dart';
import '../datasources/journal_local_datasource.dart';
import 'accounting_repository.dart';

/// Implementation of JournalRepository.
///
/// ──────────────────────────────────────────────────────────────────────
/// Phase 1 (scattered-calc migration) — 2026-05
/// ──────────────────────────────────────────────────────────────────────
/// This class is an **adapter** over [AccountingRepository]. All write paths
/// (create / post / void) and the trial-balance computation delegate to
/// [AccountingRepository] so that `accounts.balance_cents` has exactly one
/// writer in the codebase. Read-only watchers and CRUD for accounts /
/// periods remain routed through [JournalLocalDatasource].
///
/// Do NOT re-introduce balance math here. See docs/adr/0001-pricing-engines-as-sot.md.
/// ──────────────────────────────────────────────────────────────────────
class JournalRepositoryImpl implements JournalRepository {
  final JournalLocalDatasource _datasource;
  final AccountingRepository _accountingRepo;

  static const Set<String> _validAccountTypes = {
    'asset',
    'liability',
    'equity',
    'revenue',
    'expense',
  };

  JournalRepositoryImpl(this._datasource, this._accountingRepo);

  // ── Accounts ──────────────────────────────────────────────

  @override
  Stream<List<Account>> watchAllAccounts() => _datasource.watchAllAccounts();

  @override
  Stream<List<Account>> watchAccountsByType(String accountType) =>
      _datasource.watchAccountsByType(accountType);

  @override
  Stream<Account?> watchAccount(int id) => _datasource.watchAccount(id);

  @override
  Future<Account?> getAccount(int id) => _datasource.getAccount(id);

  @override
  Future<Account?> findAccountByCode(String code) =>
      _datasource.findByCode(code);

  @override
  Future<List<Account>> getChildAccounts(int parentId) =>
      _datasource.getChildAccounts(parentId);

  @override
  Future<int> createAccount({
    required String accountCode,
    required String accountName,
    required String accountType,
    required int currencyId,
    int? parentAccountId,
    bool isSystemAccount = false,
    int displayOrder = 0,
    String? description,
  }) {
    final normalizedType = _normalizeAccountType(accountType);
    _validateAccountType(normalizedType);
    final companion = AccountsCompanion(
      accountCode: Value(accountCode),
      accountName: Value(accountName),
      accountType: Value(normalizedType),
      currencyId: Value(currencyId),
      parentAccountId: Value(parentAccountId),
      isSystemAccount: Value(isSystemAccount),
      displayOrder: Value(displayOrder),
      description: Value(description),
      isActive: const Value(true),
      balanceCents: Value(Decimal.zero),
      createdAt: Value(DateTime.now()),
      updatedAt: Value(DateTime.now()),
    );
    return _datasource.createAccount(companion);
  }

  @override
  Future<bool> updateAccount(Account account) =>
      _datasource.updateAccount(account);

  @override
  Future<int> deleteAccount(int id) => _datasource.deleteAccount(id);

  @override
  Stream<int> watchAccountCount({bool? isActive}) =>
      _datasource.watchAccountCount(isActive: isActive);

  // ── Journal Entries ───────────────────────────────────────

  @override
  Stream<List<JournalEntry>> watchAllJournalEntries() =>
      _datasource.watchJournalEntries();

  @override
  Stream<List<JournalEntry>> watchJournalEntriesByDateRange(
    DateTime start,
    DateTime end,
  ) => _datasource.watchJournalEntriesByDateRange(start, end);

  @override
  Stream<List<JournalEntry>> watchJournalEntriesByType(String entryType) =>
      _datasource.watchJournalEntriesByType(entryType);

  @override
  Stream<List<JournalEntry>> watchJournalEntriesByStatus(String status) =>
      _datasource.watchJournalEntriesByStatus(status);

  @override
  Future<JournalEntry?> getJournalEntry(int id) =>
      _datasource.getJournalEntry(id);

  @override
  Future<JournalEntry?> findJournalEntryByNumber(String entryNumber) =>
      _datasource.findJournalEntryByNumber(entryNumber);

  @override
  Future<JournalEntry?> findJournalEntryBySource(
    String sourceTable,
    int sourceId,
  ) => _datasource.findJournalEntryBySource(sourceTable, sourceId);

  @override
  Future<List<JournalEntry>> searchJournalEntries(String query) =>
      _datasource.searchJournalEntries(query);

  @override
  Future<int> createJournalEntryWithLines({
    required String description,
    required DateTime entryDate,
    required String entryType,
    required List<JournalLineInput> lines,
    String? sourceTable,
    int? sourceId,
    int? createdBy,
  }) async {
    // DELEGATION — this method used to duplicate the double-entry validation,
    // closed-period lock, control-account protection, and raw table writes
    // found in AccountingRepository.createJournalEntry. To guarantee a
    // single writer for `accounts.balance_cents` and a single rule set for
    // JE validation, the work is funnelled to AccountingRepository.
    //
    // Minimal pre-check kept here: ArgumentError on imbalance / empty /
    // <2-line entries, to preserve the existing public contract of this
    // interface (its callers — journal_entry_form_bloc etc. — catch
    // ArgumentError / StateError). AccountingRepository throws
    // `AccountingException` for the same conditions.
    Decimal totalDebits = Decimal.zero;
    Decimal totalCredits = Decimal.zero;
    for (final line in lines) {
      totalDebits += line.debitCents;
      totalCredits += line.creditCents;
    }
    if (totalDebits != totalCredits) {
      throw ArgumentError(
        'Journal entry is not balanced: debits=$totalDebits, credits=$totalCredits',
      );
    }
    if (totalDebits == Decimal.zero) {
      throw ArgumentError('Journal entry must have non-zero amounts');
    }
    if (lines.length < 2) {
      throw ArgumentError('Journal entry must have at least 2 lines');
    }

    final entryData = JournalEntryData(
      description: description,
      entryDate: entryDate,
      entryType: entryType,
      sourceTable: sourceTable,
      sourceId: sourceId,
      autoPost: false,
      lines: [
        for (final line in lines)
          JournalEntryLineData(
            accountId: line.accountId,
            debitCents: line.debitCents.toBigInt().toInt(),
            creditCents: line.creditCents.toBigInt().toInt(),
            currencyId: line.currencyId,
            description: line.description,
          ),
      ],
    );

    return _accountingRepo.createJournalEntry(
      entryData: entryData,
      userId: createdBy,
    );
  }

  @override
  Future<void> postJournalEntry(int entryId, {int? postedBy}) async {
    // DELEGATION — previously this method contained inline
    // `accounts.balance_cents` update logic in parallel to
    // AccountingRepository._updateAccountBalance. Now a single writer.
    //
    // Preserve the public contract: ArgumentError when entry not found,
    // StateError when already posted. AccountingRepository throws
    // AccountingException for both; translate for callers that match on
    // the legacy error types.
    final entry = await _datasource.getJournalEntry(entryId);
    if (entry == null) throw ArgumentError('Journal entry not found: $entryId');
    if (entry.status != 'draft') {
      throw StateError(
        'Only draft entries can be posted. Current status: ${entry.status}',
      );
    }

    await _accountingRepo.postJournalEntry(entryId: entryId, userId: postedBy);
  }

  @override
  Future<int> voidJournalEntry(
    int entryId, {
    required String reason,
    int? createdBy,
  }) async {
    // DELEGATION — void-via-reversal is produced by AccountingRepository.
    // The AccountingRepository variant also atomically links the reversal
    // entry to the original via `reversedEntryId` at creation time (this
    // implementation previously did a follow-up update, creating a brief
    // window where the reversal existed without the back-reference).
    final entry = await _datasource.getJournalEntry(entryId);
    if (entry == null) throw ArgumentError('Journal entry not found: $entryId');
    if (entry.status != 'posted') {
      throw StateError(
        'Only posted entries can be voided. Current status: ${entry.status}',
      );
    }

    return _accountingRepo.voidJournalEntry(
      entryId: entryId,
      reason: reason,
      userId: createdBy,
    );
  }

  @override
  Stream<int> watchJournalEntryCount({String? status}) =>
      _datasource.watchJournalEntryCount(status: status);

  // ── Journal Entry Lines ───────────────────────────────────

  @override
  Stream<List<JournalEntryLine>> watchJournalEntryLines(int entryId) =>
      _datasource.watchJournalEntryLines(entryId);

  @override
  Future<List<JournalEntryLine>> getJournalEntryLines(int entryId) =>
      _datasource.getJournalEntryLines(entryId);

  @override
  Stream<List<JournalEntryLine>> watchJournalLinesByAccount(int accountId) =>
      _datasource.watchJournalLinesByAccount(accountId);

  // ── Accounting Periods ────────────────────────────────────

  @override
  Stream<List<AccountingPeriod>> watchAccountingPeriods() =>
      _datasource.watchAccountingPeriods();

  @override
  Future<AccountingPeriod?> getActiveAccountingPeriod() =>
      _datasource.getActiveAccountingPeriod();

  // ── Trial Balance & Reconciliation ───────────────────────

  /// Trial Balance — delegates to [AccountingRepository.getTrialBalance].
  ///
  /// Pre-Phase-1 this method contained a second, parallel implementation of
  /// the trial-balance classification logic. Both versions aggregated from
  /// `journal_entry_lines` but the duplication risked drift over time.
  /// See docs/adr/0001-pricing-engines-as-sot.md § Phase 1.
  @override
  Future<TrialBalance> getTrialBalance({DateTime? asOfDate}) {
    return _accountingRepo.getTrialBalance(asOfDate: asOfDate);
  }

  @override
  Future<ReconciliationResult> reconcileBalances() async {
    // AccountingRepository owns the shared GL, entry, account-type and AR/AP
    // checks. This adapter only appends the physical inventory valuation check.
    final base = await _accountingRepo.reconcileBalances();
    final issues = List<String>.from(base.issues);
    final trialBalance = await getTrialBalance();

    final invAccount = await _datasource.findByCode('1200');
    if (invAccount != null) {
      final invItem = trialBalance.items
          .where((i) => i.accountId == invAccount.id)
          .firstOrNull;
      final glBalance = invItem?.naturalBalanceCents ?? 0;
      final stockValue = await _datasource.getTotalInventoryValueCents();
      if (glBalance != stockValue) {
        issues.add(
          'Inventory mismatch: GL(journal_lines)=$glBalance, '
          'Σ(stock×cost)=$stockValue',
        );
      }
    }

    return ReconciliationResult(
      isHealthy: issues.isEmpty,
      issues: issues,
      timestamp: DateTime.now(),
    );
  }

  String _normalizeAccountType(String accountType) =>
      accountType.trim().toLowerCase();

  void _validateAccountType(String accountType) {
    if (!_validAccountTypes.contains(accountType)) {
      throw ArgumentError('Invalid account type: $accountType');
    }
  }

  // ── Seeding ───────────────────────────────────────────────

  @override
  Future<void> seedDefaultAccounts(int currencyId) async {
    final now = DateTime.now();

    // STRICT Chart of Accounts — NO MORE THAN THESE.
    // Every account code here MUST match what JournalEntryService
    // and AccountingRepository reference via getAccountByCode().
    //
    // DO NOT add temporary, clearing, suspense, or smart accounts.
    final defaultAccounts = <Map<String, dynamic>>[
      // ── Assets (1xxx) ──
      {
        'code': '1000',
        'name': 'Cash',
        'type': 'asset',
        'system': true,
        'order': 1,
      }, // الصندوق
      {
        'code': '1010',
        'name': 'Bank',
        'type': 'asset',
        'system': true,
        'order': 2,
      },
      {
        'code': '1100',
        'name': 'Accounts Receivable',
        'type': 'asset',
        'system': true,
        'order': 3,
      }, // Customers
      {
        'code': '1200',
        'name': 'Inventory',
        'type': 'asset',
        'system': true,
        'order': 4,
      },
      // 1290 (Returns in Transit) is an INVENTORY-class clearing account
      // used for the `send_back` disposition on purchase returns: when the
      // supplier physically leaves the premises with defective goods but
      // has not yet issued the credit note / refund, the goods sit here
      // instead of Inventory (1200) or Shrinkage (5800). Clears to AP /
      // Cash / 4100 when the supplier finally settles. This keeps 1200
      // reconciliable to on-hand stock count even mid-return.
      {
        'code': '1290',
        'name': 'Returns in Transit',
        'type': 'asset',
        'system': true,
        'order': 6,
      },
      {
        'code': '1300',
        'name': 'VAT Receivable',
        'type': 'asset',
        'system': true,
        'order': 7,
      }, // Purchase Tax
      {
        'code': '1500',
        'name': 'Fixed Assets',
        'type': 'asset',
        'system': true,
        'order': 8,
      },
      {
        'code': '1510',
        'name': 'Furniture and Fixtures',
        'type': 'asset',
        'system': true,
        'order': 9,
      },
      {
        'code': '1520',
        'name': 'Equipment and Air Conditioners',
        'type': 'asset',
        'system': true,
        'order': 10,
      },
      {
        'code': '1590',
        'name': 'Accumulated Depreciation',
        'type': 'asset',
        'system': true,
        'order': 11,
      },
      // ── Liabilities (2xxx) ──
      {
        'code': '2000',
        'name': 'Accounts Payable',
        'type': 'liability',
        'system': true,
        'order': 10,
      }, // Suppliers
      {
        'code': '2100',
        'name': 'VAT Payable',
        'type': 'liability',
        'system': true,
        'order': 11,
      }, // Sales Tax
      {
        'code': '2200',
        'name': 'Owner Loan Payable',
        'type': 'liability',
        'system': true,
        'order': 12,
      },
      {
        'code': '2300',
        'name': 'Loyalty Points Liability',
        'type': 'liability',
        'system': true,
        'order': 12,
      },
      // 2400 (Customer Credit Liability) holds refunds we owe customers but
      // have not yet settled in cash, when the return is **unlinked** to any
      // sale invoice. Routing on-account refunds here (instead of into 1100
      // AR) keeps the AR sub-ledger anchored to real invoices and prevents
      // orphaned negative-AR balances. When the customer later applies the
      // credit to a future sale, that sale's JE clears 2400. This is the
      // IFRS/ZATCA Phase-2-friendly treatment of "credit notes without
      // original invoice".
      {
        'code': '2400',
        'name': 'Customer Credit Liability',
        'type': 'liability',
        'system': true,
        'order': 13,
      },
      // ── Equity (3xxx) ──
      {
        'code': '3000',
        'name': 'Owner Capital',
        'type': 'equity',
        'system': true,
        'order': 20,
      },
      {
        'code': '3100',
        'name': 'Opening Balance Equity',
        'type': 'equity',
        'system': true,
        'order': 21,
      },
      {
        'code': '3200',
        'name': 'Owner Drawings',
        'type': 'equity',
        'system': true,
        'order': 22,
      },
      // ── Income (4xxx) ──
      {
        'code': '4000',
        'name': 'Sales Revenue',
        'type': 'revenue',
        'system': true,
        'order': 30,
      },
      // 5700 (Sales Return Adjustment) is a CONTRA-REVENUE account: it carries
      // a debit balance and is presented as a deduction from gross revenue on
      // the income statement to yield Net Sales (IFRS/GAAP). Classifying it
      // as `revenue` makes the P&L revenue total = Σ(Cr − Dr) automatically
      // subtract sale-return debit balances — no special-case logic needed.
      {
        'code': '5700',
        'name': 'Sales Return Adjustment',
        'type': 'revenue',
        'system': true,
        'order': 33,
      },
      {
        'code': '4200',
        'name': 'Inventory Gain',
        'type': 'revenue',
        'system': true,
        'order': 32,
      },
      // 4900 (Purchase Discounts Earned) is an "other income" account that
      // captures after-the-fact, unallocated supplier discounts recorded
      // directly from the supplier profile screen (supplier_transactions
      // with transaction_type='discount'). Routing the credit here — rather
      // than to Inventory (1200) as a phantom landed-cost adjustment —
      // keeps the GL Inventory balance equal to the on-hand carrying value
      // Σ(stock × cost), eliminating a class of permanent reconciliation
      // drift. See `JournalEntryService.recordDirectSupplierDiscount…`.
      {
        'code': '4900',
        'name': 'Purchase Discounts Earned',
        'type': 'revenue',
        'system': true,
        'order': 34,
      },
      // ── Expenses (5xxx) ──
      // 4100 (Purchase Return Adjustment) is a CONTRA-EXPENSE account: it
      // carries a credit balance and is presented as a deduction from COGS
      // on the income statement to yield Net Cost of Sales. Classifying it
      // as `expense` makes Σ(Dr − Cr) automatically deduct purchase-return
      // credit balances from gross COGS — IFRS/GAAP presentation.
      {
        'code': '4100',
        'name': 'Purchase Return Adjustment',
        'type': 'expense',
        'system': true,
        'order': 40,
      },
      {
        'code': '5100',
        'name': 'Expenses',
        'type': 'expense',
        'system': true,
        'order': 41,
      },
      {
        'code': '5200',
        'name': 'Salaries Expense',
        'type': 'expense',
        'system': true,
        'order': 42,
      },
      {
        'code': '5300',
        'name': 'Cost of Goods Sold',
        'type': 'expense',
        'system': true,
        'order': 43,
      },
      {
        'code': '5500',
        'name': 'Discounts Given',
        'type': 'expense',
        'system': true,
        'order': 44,
      },
      {
        'code': '5600',
        'name': 'Commissions Expense',
        'type': 'expense',
        'system': true,
        'order': 45,
      },
      {
        'code': '5800',
        'name': 'Inventory Shrinkage',
        'type': 'expense',
        'system': true,
        'order': 47,
      },
      {
        'code': '5900',
        'name': 'Inventory Revaluation',
        'type': 'expense',
        'system': true,
        'order': 48,
      },
      {
        'code': '6100',
        'name': 'Depreciation Expense',
        'type': 'expense',
        'system': true,
        'order': 49,
      },
    ];

    // Idempotent: skip accounts that already exist, create only missing ones
    for (final acct in defaultAccounts) {
      final code = acct['code'] as String;
      final existing = await _datasource.findByCode(code);
      if (existing != null) continue;

      await _datasource.createAccount(
        AccountsCompanion(
          accountCode: Value(code),
          accountName: Value(acct['name'] as String),
          accountType: Value(acct['type'] as String),
          currencyId: Value(currencyId),
          isSystemAccount: Value(acct['system'] as bool),
          displayOrder: Value(acct['order'] as int),
          isActive: const Value(true),
          balanceCents: Value(Decimal.zero),
          createdAt: Value(now),
          updatedAt: Value(now),
        ),
      );
    }
  }

  // ── Date-Range Queries ──────────────────────────────────

  @override
  Stream<List<JournalEntryLine>> watchPostedLinesByDateRange(
    DateTime startDate,
    DateTime endDate,
  ) => _datasource.watchPostedLinesByDateRange(startDate, endDate);

  @override
  Stream<List<JournalEntryLine>> watchPostedLinesByAccountAndDateRange(
    int accountId,
    DateTime startDate,
    DateTime endDate,
  ) => _datasource.watchPostedLinesByAccountAndDateRange(
    accountId,
    startDate,
    endDate,
  );
}
