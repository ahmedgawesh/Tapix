import 'dart:developer' as developer;

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import '../../../../core/database/app_database.dart';
import '../../domain/models/trial_balance.dart';
import '../../domain/models/reconciliation_result.dart';
import '../../domain/repositories/journal_repository.dart';
import '../datasources/journal_local_datasource.dart';
import 'accounting_repository.dart';

/// Implementation of JournalRepository
class JournalRepositoryImpl implements JournalRepository {
  final JournalLocalDatasource _datasource;
  // ignore: unused_field
  final AccountingRepository _accountingRepo;

  static const Set<String> _validAccountTypes = {
    'asset',
    'liability',
    'equity',
    'revenue',
    'expense',
  };

  /// Control account codes that MUST NOT be touched by manual journal entries.
  static const Set<String> _controlAccountCodes = {'1100', '2000'};

  /// Entry types that are allowed to touch control accounts.
  static const Set<String> _systemEntryTypes = {
    'sale', 'purchase', 'payment', 'saleReturn', 'purchaseReturn',
    'reversal', 'customer_payment', 'customer_discount',
    'supplier_payment', 'supplier_discount', 'closing',
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

    if (await _datasource.isDateInClosedPeriod(entryDate)) {
      throw StateError(
        'Cannot create journal entry: date ${entryDate.toIso8601String().substring(0, 10)} '
        'falls in a closed accounting period',
      );
    }

    // Enforce control account protection: manual entries cannot touch AR/AP
    if (!_systemEntryTypes.contains(entryType)) {
      for (final line in lines) {
        final account = await _datasource.getAccount(line.accountId);
        if (account != null && _controlAccountCodes.contains(account.accountCode)) {
          throw ArgumentError(
            'Cannot modify control account "${account.accountName}" (${account.accountCode}) '
            'via manual journal entry. Use the appropriate business transaction '
            '(sale, purchase, payment) instead.',
          );
        }
      }
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

    if (await _datasource.isDateInClosedPeriod(entry.entryDate)) {
      throw StateError(
        'Cannot post journal entry: date ${entry.entryDate.toIso8601String().substring(0, 10)} '
        'falls in a closed accounting period',
      );
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

    // Original stays 'posted' with isReversed=true so original + reversal
    // cancel to net zero in GL. Do NOT set status='voided' — that would
    // exclude the original from GL while the reversal subtracts again.

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

  /// Trial Balance — SINGLE SOURCE OF TRUTH: journal_lines table.
  /// Never uses cached balanceCents. Always aggregates from posted journal lines.
  @override
  Future<TrialBalance> getTrialBalance({DateTime? asOfDate}) async {
    final accounts = await _datasource.getAllActiveAccounts();
    final effectiveDate = asOfDate ?? DateTime.now();

    // ALWAYS compute from journal_lines — the only source of truth
    final lines = await _datasource
        .watchPostedLinesByDateRange(DateTime.fromMillisecondsSinceEpoch(0), effectiveDate)
        .first;

    final balanceByAccountId = <int, int>{};
    int rawTotalDebits = 0;
    int rawTotalCredits = 0;
    for (final line in lines) {
      final debit = line.debitCents.toBigInt().toInt();
      final credit = line.creditCents.toBigInt().toInt();
      rawTotalDebits += debit;
      rawTotalCredits += credit;
      balanceByAccountId.update(
        line.accountId,
        (value) => value + debit - credit,
        ifAbsent: () => debit - credit,
      );
    }

    // Diagnostic: raw journal_lines totals
    developer.log(
      'DIAGNOSTIC: journal_lines raw totals — '
      'Debits=$rawTotalDebits, Credits=$rawTotalCredits, '
      'Diff=${rawTotalDebits - rawTotalCredits}, Lines=${lines.length}',
      name: 'TrialBalance',
    );

    if (rawTotalDebits != rawTotalCredits) {
      developer.log(
        'WARNING: Raw journal line totals unbalanced! '
        'Debits=$rawTotalDebits, Credits=$rawTotalCredits, '
        'Diff=${rawTotalDebits - rawTotalCredits}',
        name: 'TrialBalance',
      );
    }

    int totalDebits = 0;
    int totalCredits = 0;
    final items = <TrialBalanceItem>[];

    for (final account in accounts) {
      // rawBalance = SUM(debit) - SUM(credit) for this account
      final rawBalance = balanceByAccountId[account.id] ?? 0;

      int debit = 0;
      int credit = 0;

      final type = account.accountType.toLowerCase();
      if (type == 'asset' || type == 'expense') {
        // Normal debit balance: positive rawBalance → debit column
        if (rawBalance >= 0) {
          debit = rawBalance;
        } else {
          credit = -rawBalance;
        }
      } else {
        // Liability/Equity/Revenue: normal credit balance.
        // rawBalance is (debit - credit), so negate to get natural balance.
        // Positive natural balance → credit column (normal).
        // Negative natural balance → debit column (abnormal).
        final naturalBalance = -rawBalance;
        if (naturalBalance >= 0) {
          credit = naturalBalance;
        } else {
          debit = -naturalBalance;
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

    // Diagnostic: if trial balance doesn't match, print per-account deltas
    if (totalDebits != totalCredits) {
      developer.log(
        'WARNING: Trial Balance unbalanced after classification! '
        'Debits=$totalDebits, Credits=$totalCredits, Diff=${totalDebits - totalCredits}',
        name: 'TrialBalance',
      );
      for (final item in items) {
        if (item.debitCents != 0 || item.creditCents != 0) {
          developer.log(
            '  Account ${item.accountCode} (${item.accountName}, ${item.accountType}): '
            'Dr=${item.debitCents}, Cr=${item.creditCents}, '
            'RawBalance=${balanceByAccountId[item.accountId] ?? 0}',
            name: 'TrialBalance',
          );
        }
      }
    }

    return TrialBalance(
      asOfDate: effectiveDate,
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

    final accounts = await _datasource.getAllActiveAccounts();
    for (final account in accounts) {
      final normalizedType = _normalizeAccountType(account.accountType);
      if (!_validAccountTypes.contains(normalizedType)) {
        issues.add(
          'Invalid account type for ${account.accountCode} (${account.accountName}): '
          '${account.accountType}',
        );
        continue;
      }

      final expectedType = _expectedTypeForCode(account.accountCode);
      if (expectedType != null && expectedType != normalizedType) {
        issues.add(
          'Account type mismatch for ${account.accountCode} (${account.accountName}): '
          'expected $expectedType, found ${account.accountType}',
        );
      }
    }

    // AR/AP checks: derive GL balance from journal_lines, not cached balanceCents
    final arAccount = await _datasource.findByCode('1100');
    if (arAccount != null) {
      final arItem = trialBalance.items.where((i) => i.accountId == arAccount.id).firstOrNull;
      final arBalance = arItem != null ? (arItem.debitCents - arItem.creditCents) : 0;
      final customerTotal = await _datasource.getCustomerBalanceTotal();
      if (arBalance != customerTotal) {
        issues.add(
          'Accounts receivable mismatch: GL(journal_lines)=$arBalance, Customers=$customerTotal',
        );
      }
    }

    final apAccount = await _datasource.findByCode('2000');
    if (apAccount != null) {
      final apItem = trialBalance.items.where((i) => i.accountId == apAccount.id).firstOrNull;
      // AP is liability — credit balance is positive, so net = credit - debit
      final apBalance = apItem != null ? (apItem.creditCents - apItem.debitCents) : 0;
      final supplierTotal = await _datasource.getSupplierBalanceTotal();
      if (apBalance != supplierTotal) {
        issues.add(
          'Accounts payable mismatch: GL(journal_lines)=$apBalance, Suppliers=$supplierTotal',
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

  String? _expectedTypeForCode(String accountCode) {
    final trimmed = accountCode.trim();
    if (trimmed.isEmpty) return null;
    switch (trimmed[0]) {
      case '1':
        return 'asset';
      case '2':
        return 'liability';
      case '3':
        return 'equity';
      case '4':
        return 'revenue';
      case '5':
        return 'expense';
      default:
        return null;
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
      {'code': '1000', 'name': 'Cash', 'type': 'asset', 'system': true, 'order': 1},              // الصندوق
      {'code': '1010', 'name': 'Bank', 'type': 'asset', 'system': true, 'order': 2},
      {'code': '1100', 'name': 'Accounts Receivable', 'type': 'asset', 'system': true, 'order': 3}, // Customers
      {'code': '1200', 'name': 'Inventory', 'type': 'asset', 'system': true, 'order': 4},
      {'code': '1300', 'name': 'VAT Receivable', 'type': 'asset', 'system': true, 'order': 5},      // Purchase Tax
      // ── Liabilities (2xxx) ──
      {'code': '2000', 'name': 'Accounts Payable', 'type': 'liability', 'system': true, 'order': 10}, // Suppliers
      {'code': '2100', 'name': 'VAT Payable', 'type': 'liability', 'system': true, 'order': 11},      // Sales Tax
      {'code': '2300', 'name': 'Loyalty Points Liability', 'type': 'liability', 'system': true, 'order': 12},
      // ── Equity (3xxx) ──
      {'code': '3000', 'name': 'Owner Capital', 'type': 'equity', 'system': true, 'order': 20},
      {'code': '3100', 'name': 'Opening Balance Equity', 'type': 'equity', 'system': true, 'order': 21},
      // ── Income (4xxx) ──
      {'code': '4000', 'name': 'Sales Revenue', 'type': 'revenue', 'system': true, 'order': 30},
      // ── Expenses (5xxx) ──
      {'code': '5100', 'name': 'Expenses', 'type': 'expense', 'system': true, 'order': 41},
      {'code': '5200', 'name': 'Salaries Expense', 'type': 'expense', 'system': true, 'order': 42},
      {'code': '5300', 'name': 'Cost of Goods Sold', 'type': 'expense', 'system': true, 'order': 43},
      {'code': '5500', 'name': 'Discounts Given', 'type': 'expense', 'system': true, 'order': 44},
      {'code': '5600', 'name': 'Commissions Expense', 'type': 'expense', 'system': true, 'order': 45},
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
    DateTime startDate, DateTime endDate) =>
      _datasource.watchPostedLinesByDateRange(startDate, endDate);

  @override
  Stream<List<JournalEntryLine>> watchPostedLinesByAccountAndDateRange(
    int accountId, DateTime startDate, DateTime endDate) =>
      _datasource.watchPostedLinesByAccountAndDateRange(accountId, startDate, endDate);
}
