import 'dart:developer' as developer;

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../domain/models/journal_entry_data.dart';
import '../../domain/models/trial_balance.dart';
import '../../domain/models/reconciliation_result.dart';
import '../../domain/exceptions/accounting_exception.dart';

/// AccountingRepository - SINGLE SOURCE OF TRUTH for all accounting operations
/// 
/// ALL accounting data access MUST go through this repository.
/// Direct database access to accounting tables is PROHIBITED.
/// 
/// This repository ensures:
/// - Double-entry bookkeeping integrity
/// - Immutable transaction pattern (void via reversal only)
/// - Atomic operations for all balance changes
/// - Complete audit trail
class AccountingRepository {
  final AppDatabase _db;

  static const Set<String> _validAccountTypes = {
    'asset',
    'liability',
    'equity',
    'revenue',
    'expense',
  };

  /// Control account codes that MUST NOT be touched by manual journal entries.
  /// Only system-generated entries (sale, purchase, payment, reversal, etc.)
  /// are allowed to modify these accounts.
  static const Set<String> _controlAccountCodes = {'1100', '2000'};

  /// Entry types that are allowed to touch control accounts.
  static const Set<String> _systemEntryTypes = {
    'sale',
    'purchase',
    'payment',
    'saleReturn',
    'purchaseReturn',
    'reversal',
    'customer_payment',
    'customer_discount',
    'supplier_payment',
    'supplier_discount',
    'closing',
  };

  AccountingRepository(this._db);

  // ============================================================
  // ACCOUNT OPERATIONS
  // ============================================================

  /// Watch all active accounts
  Stream<List<Account>> watchAllAccounts() {
    return (_db.select(_db.accounts)
          ..where((a) => a.isActive.equals(true))
          ..orderBy([(a) => OrderingTerm(expression: a.accountCode)]))
        .watch();
  }

  /// Watch a single account by ID
  Stream<Account?> watchAccount(int id) {
    return (_db.select(_db.accounts)..where((a) => a.id.equals(id)))
        .watchSingleOrNull();
  }

  /// Get account by code
  Future<Account?> getAccountByCode(String code) {
    return (_db.select(_db.accounts)..where((a) => a.accountCode.equals(code)))
        .getSingleOrNull();
  }

  /// Get account by ID
  Future<Account?> getAccountById(int id) {
    return (_db.select(_db.accounts)..where((a) => a.id.equals(id)))
        .getSingleOrNull();
  }

  /// Create a new account
  Future<int> createAccount({
    required String accountCode,
    required String accountName,
    required String accountType,
    required int currencyId,
    int? parentAccountId,
    String? description,
    bool isSystemAccount = false,
    int displayOrder = 0,
  }) async {
    final normalizedType = _normalizeAccountType(accountType);
    _validateAccountType(normalizedType);
    return await _db.into(_db.accounts).insert(
      AccountsCompanion.insert(
        accountCode: accountCode,
        accountName: accountName,
        accountType: normalizedType,
        currencyId: currencyId,
        parentAccountId: Value(parentAccountId),
        description: Value(description),
        isSystemAccount: Value(isSystemAccount),
        displayOrder: Value(displayOrder),
      ),
    );
  }

  /// Update account (non-balance fields only)
  /// Balance changes MUST go through journal entries
  Future<bool> updateAccount({
    required int id,
    String? accountName,
    String? description,
    bool? isActive,
    int? displayOrder,
  }) async {
    final account = await getAccountById(id);
    if (account == null) return false;
    
    // Prevent deactivating system accounts
    if (account.isSystemAccount && isActive == false) {
      throw AccountingException('Cannot deactivate system account');
    }

    final updated = await (_db.update(_db.accounts)..where((a) => a.id.equals(id)))
        .write(AccountsCompanion(
          accountName: accountName != null ? Value(accountName) : const Value.absent(),
          description: description != null ? Value(description) : const Value.absent(),
          isActive: isActive != null ? Value(isActive) : const Value.absent(),
          displayOrder: displayOrder != null ? Value(displayOrder) : const Value.absent(),
          updatedAt: Value(DateTime.now()),
        ));
    return updated > 0;
  }

  // ============================================================
  // JOURNAL ENTRY OPERATIONS
  // ============================================================

  /// Create a journal entry with lines - ATOMIC OPERATION
  /// 
  /// This is the ONLY way to change account balances.
  /// Validates double-entry before committing.
  Future<int> createJournalEntry({
    required JournalEntryData entryData,
    required int? userId,
  }) async {
    // Validate double-entry balance
    int totalDebits = 0;
    int totalCredits = 0;
    
    for (final line in entryData.lines) {
      totalDebits += line.debitCents;
      totalCredits += line.creditCents;
      
      // Validate each line has debit OR credit, not both
      if (line.debitCents > 0 && line.creditCents > 0) {
        throw AccountingException(
          'Journal line cannot have both debit and credit'
        );
      }
      if (line.debitCents == 0 && line.creditCents == 0) {
        throw AccountingException(
          'Journal line must have either debit or credit'
        );
      }
    }
    
    if (totalDebits != totalCredits) {
      throw AccountingException(
        'Journal entry unbalanced: Debits=$totalDebits, Credits=$totalCredits'
      );
    }
    
    if (entryData.lines.length < 2) {
      throw AccountingException(
        'Journal entry must have at least 2 lines'
      );
    }

    // Enforce control account protection: manual entries cannot touch AR/AP
    final entryType = entryData.entryType ?? 'manual';
    if (!_systemEntryTypes.contains(entryType)) {
      for (final line in entryData.lines) {
        final account = await getAccountById(line.accountId);
        if (account != null && _controlAccountCodes.contains(account.accountCode)) {
          throw AccountingException(
            'Cannot modify control account "${account.accountName}" (${account.accountCode}) '
            'via manual journal entry. Use the appropriate business transaction '
            '(sale, purchase, payment) instead.',
          );
        }
      }
    }

    // Enforce closed period lock
    final entryDate = entryData.entryDate ?? DateTime.now();
    if (await isDateInClosedPeriod(entryDate)) {
      throw AccountingException(
        'Cannot post journal entry: date ${entryDate.toIso8601String().substring(0, 10)} falls in a closed accounting period'
      );
    }

    // Execute in atomic transaction
    return await _db.transaction(() async {
      // Generate entry number
      final entryNumber = await _generateEntryNumber();
      
      // Create journal entry header
      final entryId = await _db.into(_db.journalEntries).insert(
        JournalEntriesCompanion.insert(
          entryNumber: entryNumber,
          description: entryData.description,
          entryDate: Value(entryData.entryDate ?? DateTime.now()),
          accountingPeriodId: Value(entryData.accountingPeriodId),
          status: Value(entryData.autoPost ? 'posted' : 'draft'),
          entryType: Value(entryData.entryType ?? 'manual'),
          sourceTable: Value(entryData.sourceTable),
          sourceId: Value(entryData.sourceId),
          reversedEntryId: Value(entryData.reversedEntryId),
          totalDebitCents: Value(Decimal.fromInt(totalDebits)),
          totalCreditCents: Value(Decimal.fromInt(totalCredits)),
          createdBy: Value(userId),
          postedBy: entryData.autoPost ? Value(userId) : const Value.absent(),
          postedAt: entryData.autoPost ? Value(DateTime.now()) : const Value.absent(),
        ),
      );
      
      // Create journal entry lines
      int lineNumber = 1;
      for (final line in entryData.lines) {
        await _db.into(_db.journalEntryLines).insert(
          JournalEntryLinesCompanion.insert(
            journalEntryId: entryId,
            accountId: line.accountId,
            debitCents: Value(Decimal.fromInt(line.debitCents)),
            creditCents: Value(Decimal.fromInt(line.creditCents)),
            currencyId: line.currencyId,
            lineNumber: Value(lineNumber++),
            description: Value(line.description),
          ),
        );
        
        // Update account balance if entry is posted
        if (entryData.autoPost) {
          await _updateAccountBalance(
            accountId: line.accountId,
            debitCents: line.debitCents,
            creditCents: line.creditCents,
          );
        }
      }
      
      return entryId;
    });
  }

  /// Post a draft journal entry
  Future<bool> postJournalEntry({
    required int entryId,
    required int userId,
  }) async {
    final entry = await (_db.select(_db.journalEntries)
          ..where((e) => e.id.equals(entryId)))
        .getSingleOrNull();
    
    if (entry == null) {
      throw AccountingException('Journal entry not found');
    }
    
    if (entry.status != 'draft') {
      throw AccountingException('Only draft entries can be posted');
    }

    // Enforce closed period lock
    if (await isDateInClosedPeriod(entry.entryDate)) {
      throw AccountingException(
        'Cannot post journal entry: date ${entry.entryDate.toIso8601String().substring(0, 10)} falls in a closed accounting period'
      );
    }
    
    return await _db.transaction(() async {
      // Update entry status
      await (_db.update(_db.journalEntries)..where((e) => e.id.equals(entryId)))
          .write(JournalEntriesCompanion(
            status: const Value('posted'),
            postedBy: Value(userId),
            postedAt: Value(DateTime.now()),
            updatedAt: Value(DateTime.now()),
          ));
      
      // Update account balances
      final lines = await (_db.select(_db.journalEntryLines)
            ..where((l) => l.journalEntryId.equals(entryId)))
          .get();
      
      for (final line in lines) {
        await _updateAccountBalance(
          accountId: line.accountId,
          debitCents: line.debitCents.toBigInt().toInt(),
          creditCents: line.creditCents.toBigInt().toInt(),
        );
      }
      
      return true;
    });
  }

  /// Void a posted journal entry by creating a reversal entry
  /// 
  /// Posted entries are NEVER modified - only reversed.
  Future<int> voidJournalEntry({
    required int entryId,
    required String reason,
    required int userId,
  }) async {
    final entry = await (_db.select(_db.journalEntries)
          ..where((e) => e.id.equals(entryId)))
        .getSingleOrNull();
    
    if (entry == null) {
      throw AccountingException('Journal entry not found');
    }
    
    if (entry.status != 'posted') {
      throw AccountingException('Only posted entries can be voided');
    }
    
    if (entry.isReversed) {
      throw AccountingException('Entry has already been voided');
    }
    
    // Get original lines
    final originalLines = await (_db.select(_db.journalEntryLines)
          ..where((l) => l.journalEntryId.equals(entryId)))
        .get();
    
    // Create reversal entry with opposite amounts
    final reversalLines = originalLines.map((line) => JournalEntryLineData(
      accountId: line.accountId,
      debitCents: line.creditCents.toBigInt().toInt(), // Swap debit/credit
      creditCents: line.debitCents.toBigInt().toInt(),
      currencyId: line.currencyId,
      description: 'REVERSAL: ${line.description ?? ""}',
    )).toList();
    
    return await _db.transaction(() async {
      // Create reversal entry
      final reversalId = await createJournalEntry(
        entryData: JournalEntryData(
          description: 'VOID: ${entry.description} - $reason',
          entryDate: DateTime.now(),
          entryType: 'reversal',
          reversedEntryId: entryId,
          lines: reversalLines,
          autoPost: true,
        ),
        userId: userId,
      );
      
      // Mark original entry as reversed
      await (_db.update(_db.journalEntries)..where((e) => e.id.equals(entryId)))
          .write(JournalEntriesCompanion(
            status: const Value('voided'),
            isReversed: const Value(true),
            updatedAt: Value(DateTime.now()),
          ));
      
      return reversalId;
    });
  }

  /// Watch journal entries
  Stream<List<JournalEntry>> watchJournalEntries({
    String? status,
    DateTime? fromDate,
    DateTime? toDate,
  }) {
    var query = _db.select(_db.journalEntries);
    
    if (status != null) {
      query = query..where((e) => e.status.equals(status));
    }
    if (fromDate != null) {
      query = query..where((e) => e.entryDate.isBiggerOrEqualValue(fromDate));
    }
    if (toDate != null) {
      query = query..where((e) => e.entryDate.isSmallerOrEqualValue(toDate));
    }
    
    return (query..orderBy([(e) => OrderingTerm(expression: e.entryDate, mode: OrderingMode.desc)]))
        .watch();
  }

  /// Get journal entry lines for an entry
  Future<List<JournalEntryLine>> getJournalEntryLines(int entryId) {
    return (_db.select(_db.journalEntryLines)
          ..where((l) => l.journalEntryId.equals(entryId))
          ..orderBy([(l) => OrderingTerm(expression: l.lineNumber)]))
        .get();
  }

  /// Get all journal entries linked to a source document
  Future<List<JournalEntry>> getJournalEntriesForSource(
    String sourceTable, int sourceId,
  ) {
    return (_db.select(_db.journalEntries)
          ..where((e) => e.sourceTable.equals(sourceTable))
          ..where((e) => e.sourceId.equals(sourceId)))
        .get();
  }

  // ============================================================
  // TRIAL BALANCE & REPORTS
  // ============================================================

  /// Trial Balance — SINGLE SOURCE OF TRUTH: journal_lines table.
  /// Never uses cached balanceCents. Always aggregates from posted journal lines.
  Future<TrialBalance> getTrialBalance({DateTime? asOfDate}) async {
    final accounts = await (_db.select(_db.accounts)
          ..where((a) => a.isActive.equals(true))
          ..orderBy([(a) => OrderingTerm(expression: a.accountCode)]))
        .get();

    final effectiveDate = asOfDate ?? DateTime.now();

    // ALWAYS compute from journal_lines — the only source of truth
    final query = _db.select(_db.journalEntryLines).join([
      innerJoin(
        _db.journalEntries,
        _db.journalEntries.id.equalsExp(_db.journalEntryLines.journalEntryId),
      ),
    ]);
    query.where(
      _db.journalEntries.status.equals('posted') &
          _db.journalEntries.entryDate.isSmallerOrEqualValue(effectiveDate),
    );

    final rows = await query.get();
    final balanceByAccountId = <int, int>{};
    int rawTotalDebits = 0;
    int rawTotalCredits = 0;
    for (final row in rows) {
      final line = row.readTable(_db.journalEntryLines);
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
      'DIAGNOSTIC [AccountingRepo]: journal_lines raw totals — '
      'Debits=$rawTotalDebits, Credits=$rawTotalCredits, '
      'Diff=${rawTotalDebits - rawTotalCredits}, Lines=${rows.length}',
      name: 'TrialBalance',
    );

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
        'WARNING [AccountingRepo]: Trial Balance unbalanced! '
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

  /// Reconcile all balances - verify data integrity
  Future<ReconciliationResult> reconcileBalances() async {
    final issues = <String>[];

    final trialBalance = await getTrialBalance();
    if (!trialBalance.isBalanced) {
      issues.add(
        'Trial balance mismatch: Debits=${trialBalance.totalDebitCents}, '
        'Credits=${trialBalance.totalCreditCents}',
      );
    }

    final entries = await (_db.select(_db.journalEntries)
          ..where((e) => e.status.equals('posted')))
        .get();
    for (final entry in entries) {
      if (entry.totalDebitCents != entry.totalCreditCents) {
        issues.add('Unbalanced posted entry: ${entry.entryNumber}');
      }
    }

    final accounts = await (_db.select(_db.accounts)
          ..where((a) => a.isActive.equals(true)))
        .get();
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
    final arAccount = await getAccountByCode('1100');
    if (arAccount != null) {
      final arItem = trialBalance.items.where((i) => i.accountId == arAccount.id).firstOrNull;
      final arBalance = arItem != null ? (arItem.debitCents - arItem.creditCents) : 0;
      final row = await _db.customSelect(
        'SELECT COALESCE(SUM(balance_cents), 0) AS total FROM customers',
        readsFrom: {_db.customers},
      ).getSingle();
      final customerTotal = row.read<int>('total');
      if (arBalance != customerTotal) {
        issues.add(
          'Accounts receivable mismatch: GL(journal_lines)=$arBalance, Customers=$customerTotal',
        );
      }
    }

    final apAccount = await getAccountByCode('2000');
    if (apAccount != null) {
      final apItem = trialBalance.items.where((i) => i.accountId == apAccount.id).firstOrNull;
      // AP is liability — credit balance is positive, so net = credit - debit
      final apBalance = apItem != null ? (apItem.creditCents - apItem.debitCents) : 0;
      final row = await _db.customSelect(
        'SELECT COALESCE(SUM(balance_cents), 0) AS total FROM suppliers',
        readsFrom: {_db.suppliers},
      ).getSingle();
      final supplierTotal = row.read<int>('total');
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
      throw AccountingException('Invalid account type: $accountType');
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

  // ============================================================
  // ACCOUNTING PERIOD OPERATIONS
  // ============================================================

  /// Get current open accounting period
  Future<AccountingPeriod?> getCurrentPeriod() {
    return (_db.select(_db.accountingPeriods)
          ..where((p) => p.isClosed.equals(false))
          ..orderBy([(p) => OrderingTerm(expression: p.startDate, mode: OrderingMode.desc)]))
        .getSingleOrNull();
  }

  /// Create accounting period
  Future<int> createAccountingPeriod({
    required String periodName,
    required DateTime startDate,
    required DateTime endDate,
  }) {
    return _db.into(_db.accountingPeriods).insert(
      AccountingPeriodsCompanion.insert(
        periodName: periodName,
        startDate: startDate,
        endDate: endDate,
      ),
    );
  }

  /// Mark an accounting period as closed.
  ///
  /// Marks the period as closed. No closing journal entries are created.
  /// Revenue and expense accounts accumulate continuously.
  Future<bool> closeAccountingPeriod({
    required int periodId,
    required int userId,
  }) async {
    // Validate trial balance is balanced before allowing close
    final trialBalance = await getTrialBalance();
    if (!trialBalance.isBalanced) {
      throw AccountingException(
        'Cannot close period: Trial balance is not balanced. '
        'Debits=${trialBalance.totalDebitCents}, Credits=${trialBalance.totalCreditCents}. '
        'Fix all imbalances before closing.',
      );
    }

    // Mark period as closed
    final updated = await (_db.update(_db.accountingPeriods)
          ..where((p) => p.id.equals(periodId)))
        .write(AccountingPeriodsCompanion(
          isClosed: const Value(true),
          closedAt: Value(DateTime.now()),
          closedBy: Value(userId),
          updatedAt: Value(DateTime.now()),
        ));
    return updated > 0;
  }

  /// Check if a date falls within a closed accounting period.
  /// Returns true if the date is in a closed period (transaction should be blocked).
  Future<bool> isDateInClosedPeriod(DateTime date) async {
    final closedPeriods = await (_db.select(_db.accountingPeriods)
          ..where((p) => p.isClosed.equals(true))
          ..where((p) => p.startDate.isSmallerOrEqualValue(date))
          ..where((p) => p.endDate.isBiggerOrEqualValue(date)))
        .get();
    return closedPeriods.isNotEmpty;
  }

  // ============================================================
  // PRIVATE HELPER METHODS
  // ============================================================

  /// Update account balance based on debit/credit and account type
  Future<void> _updateAccountBalance({
    required int accountId,
    required int debitCents,
    required int creditCents,
  }) async {
    final account = await getAccountById(accountId);
    if (account == null) {
      throw AccountingException('Account not found: $accountId');
    }
    
    int balanceChange = 0;
    final type = account.accountType.toLowerCase();
    
    // Calculate balance change based on account type
    if (type == 'asset' || type == 'expense') {
      // Debit increases, Credit decreases
      balanceChange = debitCents - creditCents;
    } else {
      // Liability, Equity, Revenue: Credit increases, Debit decreases
      balanceChange = creditCents - debitCents;
    }
    
    final currentBalance = account.balanceCents.toBigInt().toInt();
    final newBalance = currentBalance + balanceChange;
    
    await (_db.update(_db.accounts)..where((a) => a.id.equals(accountId)))
        .write(AccountsCompanion(
          balanceCents: Value(Decimal.fromInt(newBalance)),
          updatedAt: Value(DateTime.now()),
        ));
  }

  /// Generate unique entry number
  Future<String> _generateEntryNumber() async {
    final now = DateTime.now();
    final prefix = 'JE${now.year}${now.month.toString().padLeft(2, '0')}';
    
    final lastEntry = await (_db.select(_db.journalEntries)
          ..where((e) => e.entryNumber.like('$prefix%'))
          ..orderBy([(e) => OrderingTerm(expression: e.id, mode: OrderingMode.desc)])
          ..limit(1))
        .getSingleOrNull();
    
    int sequence = 1;
    if (lastEntry != null) {
      final lastNumber = lastEntry.entryNumber.replaceAll(prefix, '');
      sequence = (int.tryParse(lastNumber) ?? 0) + 1;
    }
    
    return '$prefix${sequence.toString().padLeft(5, '0')}';
  }
}

