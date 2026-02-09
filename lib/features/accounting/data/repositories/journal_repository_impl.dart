import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import '../../../../core/database/app_database.dart';
import '../../domain/models/trial_balance.dart';
import '../../domain/models/reconciliation_result.dart';
import '../../domain/repositories/journal_repository.dart';
import '../datasources/journal_local_datasource.dart';

/// Implementation of JournalRepository
class JournalRepositoryImpl implements JournalRepository {
  final JournalLocalDatasource _datasource;

  JournalRepositoryImpl(this._datasource);

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
  Future<Account?> findAccountByCode(String code) => _datasource.findByCode(code);

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
    final companion = AccountsCompanion(
      accountCode: Value(accountCode),
      accountName: Value(accountName),
      accountType: Value(accountType),
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
  Future<bool> updateAccount(Account account) => _datasource.updateAccount(account);

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
  Stream<List<JournalEntry>> watchJournalEntriesByDateRange(DateTime start, DateTime end) =>
      _datasource.watchJournalEntriesByDateRange(start, end);

  @override
  Stream<List<JournalEntry>> watchJournalEntriesByType(String entryType) =>
      _datasource.watchJournalEntriesByType(entryType);

  @override
  Stream<List<JournalEntry>> watchJournalEntriesByStatus(String status) =>
      _datasource.watchJournalEntriesByStatus(status);

  @override
  Future<JournalEntry?> getJournalEntry(int id) => _datasource.getJournalEntry(id);

  @override
  Future<JournalEntry?> findJournalEntryByNumber(String entryNumber) =>
      _datasource.findJournalEntryByNumber(entryNumber);

  @override
  Future<JournalEntry?> findJournalEntryBySource(String sourceTable, int sourceId) =>
      _datasource.findJournalEntryBySource(sourceTable, sourceId);

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
    // Validate double-entry: total debits must equal total credits
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

    // Generate entry number
    final entryNumber = await _datasource.generateNextEntryNumber();

    // Create the journal entry header
    final entryId = await _datasource.createJournalEntry(
      JournalEntriesCompanion(
        entryNumber: Value(entryNumber),
        description: Value(description),
        entryDate: Value(entryDate),
        entryType: Value(entryType),
        status: const Value('draft'),
        sourceTable: Value(sourceTable),
        sourceId: Value(sourceId),
        totalDebitCents: Value(totalDebits),
        totalCreditCents: Value(totalCredits),
        createdBy: Value(createdBy),
        createdAt: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
      ),
    );

    // Create journal entry lines
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      await _datasource.createJournalEntryLine(
        JournalEntryLinesCompanion(
          journalEntryId: Value(entryId),
          accountId: Value(line.accountId),
          debitCents: Value(line.debitCents),
          creditCents: Value(line.creditCents),
          currencyId: Value(line.currencyId),
          lineNumber: Value(i + 1),
          description: Value(line.description),
          createdAt: Value(DateTime.now()),
        ),
      );
    }

    return entryId;
  }

  @override
  Future<void> postJournalEntry(int entryId, {int? postedBy}) async {
    final entry = await _datasource.getJournalEntry(entryId);
    if (entry == null) throw ArgumentError('Journal entry not found: $entryId');
    if (entry.status != 'draft') {
      throw StateError('Only draft entries can be posted. Current status: ${entry.status}');
    }

    // Update entry status to posted
    final updated = entry.copyWith(
      status: 'posted',
      postedBy: Value(postedBy),
      postedAt: Value(DateTime.now()),
      updatedAt: DateTime.now(),
    );
    await _datasource.updateJournalEntry(updated);

    // Update account balances
    final lines = await _datasource.getJournalEntryLines(entryId);
    for (final line in lines) {
      final account = await _datasource.getAccount(line.accountId);
      if (account == null) continue;

      final isDebitNormal = account.accountType == 'asset' || account.accountType == 'expense';
      final balanceChange = isDebitNormal
          ? (line.debitCents - line.creditCents)
          : (line.creditCents - line.debitCents);

      final newBalance = account.balanceCents + balanceChange;
      final updatedAccount = account.copyWith(
        balanceCents: newBalance,
        updatedAt: DateTime.now(),
      );
      await _datasource.updateAccount(updatedAccount);
    }
  }

  @override
  Future<int> voidJournalEntry(int entryId, {required String reason, int? createdBy}) async {
    final entry = await _datasource.getJournalEntry(entryId);
    if (entry == null) throw ArgumentError('Journal entry not found: $entryId');
    if (entry.status != 'posted') {
      throw StateError('Only posted entries can be voided. Current status: ${entry.status}');
    }

    // Mark original entry as reversed
    final updatedOriginal = entry.copyWith(
      isReversed: true,
      updatedAt: DateTime.now(),
    );
    await _datasource.updateJournalEntry(updatedOriginal);

    // Create reversal entry with swapped debits/credits
    final originalLines = await _datasource.getJournalEntryLines(entryId);
    final reversalLines = originalLines.map((line) => JournalLineInput(
      accountId: line.accountId,
      debitCents: line.creditCents,
      creditCents: line.debitCents,
      currencyId: line.currencyId,
      description: 'Reversal: ${line.description ?? ''}',
    )).toList();

    final reversalId = await createJournalEntryWithLines(
      description: 'VOID: $reason (reversal of ${entry.entryNumber})',
      entryDate: DateTime.now(),
      entryType: 'reversal',
      lines: reversalLines,
      createdBy: createdBy,
    );

    // Post the reversal immediately
    await postJournalEntry(reversalId, postedBy: createdBy);

    // Update the reversal entry to reference the original
    final reversalEntry = await _datasource.getJournalEntry(reversalId);
    if (reversalEntry != null) {
      final updatedReversal = reversalEntry.copyWith(
        reversedEntryId: Value(entryId),
        updatedAt: DateTime.now(),
      );
      await _datasource.updateJournalEntry(updatedReversal);
    }

    // Mark original as voided
    final voidedOriginal = updatedOriginal.copyWith(
      status: 'voided',
      updatedAt: DateTime.now(),
    );
    await _datasource.updateJournalEntry(voidedOriginal);

    return reversalId;
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

  @override
  Future<TrialBalance> getTrialBalance({DateTime? asOfDate}) async {
    final accounts = await _datasource.getAllActiveAccounts();

    int totalDebits = 0;
    int totalCredits = 0;
    final items = <TrialBalanceItem>[];

    for (final account in accounts) {
      final balance = account.balanceCents.toBigInt().toInt();

      int debit = 0;
      int credit = 0;

      final type = account.accountType.toLowerCase();
      if (type == 'asset' || type == 'expense') {
        if (balance >= 0) {
          debit = balance;
        } else {
          credit = -balance;
        }
      } else {
        if (balance >= 0) {
          credit = balance;
        } else {
          debit = -balance;
        }
      }

      totalDebits += debit;
      totalCredits += credit;

      items.add(TrialBalanceItem(
        accountId: account.id,
        accountCode: account.accountCode,
        accountName: account.accountName,
        accountType: account.accountType,
        debitCents: debit,
        creditCents: credit,
      ));
    }

    return TrialBalance(
      asOfDate: asOfDate ?? DateTime.now(),
      items: items,
      totalDebitCents: totalDebits,
      totalCreditCents: totalCredits,
      isBalanced: totalDebits == totalCredits,
    );
  }

  @override
  Future<ReconciliationResult> reconcileBalances() async {
    final issues = <String>[];

    // Check 1: Trial balance
    final trialBalance = await getTrialBalance();
    if (!trialBalance.isBalanced) {
      issues.add(
        'Trial balance mismatch: Debits=${trialBalance.totalDebitCents}, '
        'Credits=${trialBalance.totalCreditCents}',
      );
    }

    // Check 2: All posted entries are balanced
    final entries = await _datasource.getPostedJournalEntries();
    for (final entry in entries) {
      if (entry.totalDebitCents != entry.totalCreditCents) {
        issues.add('Unbalanced posted entry: ${entry.entryNumber}');
      }
    }

    return ReconciliationResult(
      isHealthy: issues.isEmpty,
      issues: issues,
      timestamp: DateTime.now(),
    );
  }

  // ── Seeding ───────────────────────────────────────────────

  @override
  Future<void> seedDefaultAccounts(int currencyId) async {
    // Check if accounts already exist (idempotent)
    final existing = await _datasource.findByCode('10000');
    if (existing != null) return;

    final now = DateTime.now();

    // Default Chart of Accounts
    final defaultAccounts = <Map<String, dynamic>>[
      // Assets (1xxxx)
      {'code': '10000', 'name': 'Assets', 'type': 'asset', 'system': true, 'order': 1},
      {'code': '10100', 'name': 'Cash', 'type': 'asset', 'parent': '10000', 'system': true, 'order': 2},
      {'code': '10200', 'name': 'Bank', 'type': 'asset', 'parent': '10000', 'system': true, 'order': 3},
      {'code': '10300', 'name': 'Accounts Receivable', 'type': 'asset', 'parent': '10000', 'system': true, 'order': 4},
      {'code': '10400', 'name': 'Inventory', 'type': 'asset', 'parent': '10000', 'system': true, 'order': 5},
      // Liabilities (2xxxx)
      {'code': '20000', 'name': 'Liabilities', 'type': 'liability', 'system': true, 'order': 10},
      {'code': '20100', 'name': 'Accounts Payable', 'type': 'liability', 'parent': '20000', 'system': true, 'order': 11},
      {'code': '20200', 'name': 'Tax Payable', 'type': 'liability', 'parent': '20000', 'system': true, 'order': 12},
      // Equity (3xxxx)
      {'code': '30000', 'name': 'Equity', 'type': 'equity', 'system': true, 'order': 20},
      {'code': '30100', 'name': 'Owner Equity', 'type': 'equity', 'parent': '30000', 'system': true, 'order': 21},
      {'code': '30200', 'name': 'Retained Earnings', 'type': 'equity', 'parent': '30000', 'system': true, 'order': 22},
      // Revenue (4xxxx)
      {'code': '40000', 'name': 'Revenue', 'type': 'revenue', 'system': true, 'order': 30},
      {'code': '40100', 'name': 'Sales Revenue', 'type': 'revenue', 'parent': '40000', 'system': true, 'order': 31},
      {'code': '40200', 'name': 'Service Revenue', 'type': 'revenue', 'parent': '40000', 'system': true, 'order': 32},
      {'code': '40300', 'name': 'Other Income', 'type': 'revenue', 'parent': '40000', 'system': true, 'order': 33},
      // Expenses (5xxxx)
      {'code': '50000', 'name': 'Expenses', 'type': 'expense', 'system': true, 'order': 40},
      {'code': '50100', 'name': 'Cost of Goods Sold', 'type': 'expense', 'parent': '50000', 'system': true, 'order': 41},
      {'code': '50200', 'name': 'Operating Expenses', 'type': 'expense', 'parent': '50000', 'system': true, 'order': 42},
      {'code': '50300', 'name': 'Salaries & Wages', 'type': 'expense', 'parent': '50000', 'system': true, 'order': 43},
      {'code': '50400', 'name': 'Rent Expense', 'type': 'expense', 'parent': '50000', 'system': true, 'order': 44},
      {'code': '50500', 'name': 'Utilities Expense', 'type': 'expense', 'parent': '50000', 'system': true, 'order': 45},
    ];

    // First pass: create all accounts without parent references
    final codeToId = <String, int>{};
    for (final acct in defaultAccounts) {
      final id = await _datasource.createAccount(
        AccountsCompanion(
          accountCode: Value(acct['code'] as String),
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
      codeToId[acct['code'] as String] = id;
    }

    // Second pass: update parent references
    for (final acct in defaultAccounts) {
      if (acct.containsKey('parent')) {
        final parentCode = acct['parent'] as String;
        final parentId = codeToId[parentCode];
        final childId = codeToId[acct['code'] as String];
        if (parentId != null && childId != null) {
          final child = await _datasource.getAccount(childId);
          if (child != null) {
            final updated = child.copyWith(
              parentAccountId: Value(parentId),
              updatedAt: now,
            );
            await _datasource.updateAccount(updated);
          }
        }
      }
    }
  }

  // ── Date-Range Queries ──────────────────────────────────

  @override
  Stream<List<JournalEntryLine>> watchPostedLinesByDateRange(
    DateTime startDate, DateTime endDate) =>
      _datasource.watchPostedLinesByDateRange(startDate, endDate);

  @override
  Stream<List<JournalEntryLine>> watchPostedLinesByAccountAndDateRange(
    int accountId, DateTime startDate, DateTime endDate) =>
      _datasource.watchPostedLinesByAccountAndDateRange(accountId, startDate, endDate);
}
