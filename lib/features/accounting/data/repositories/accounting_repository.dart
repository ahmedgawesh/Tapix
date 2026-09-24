import 'dart:developer' as developer;

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/services/compliance/fiscal_period_service.dart';
import '../../../../core/services/party_control_account_balance_service.dart';
import '../../domain/models/journal_entry_data.dart';
import '../../domain/models/trial_balance.dart';
import '../../domain/models/reconciliation_result.dart';
import '../../domain/exceptions/accounting_exception.dart';
import '../../domain/services/trial_balance_calculation_service.dart';

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

  /// Optional Phase-11 fiscal-period guard. When non-null, every
  /// [createJournalEntry] / [postJournalEntry] / [voidJournalEntry] call
  /// asserts the effective date falls inside an open fiscal-period row
  /// (`fiscal_periods` table) BEFORE the JE is written.
  ///
  /// This complements the legacy `accounting_periods` lock (which remains
  /// enforced via [isDateInClosedPeriod]). The two systems are independent
  /// and either one can block a post — closing a period in either table
  /// freezes the GL for that date range.
  ///
  /// Optional so the existing `AccountingRepository(db)` constructor used
  /// throughout the test suite continues to work unchanged. DI wires the
  /// service via the named constructor in production.
  final FiscalPeriodService? _fiscalPeriodService;

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
  ///
  /// `sale_return` / `purchase_return` are the **unified** Phase-1 types
  /// produced by `ReturnJournalPolicy`. The legacy camel-case variants
  /// (`saleReturn`, `purchaseReturn`, `saleReturnAdjustment`,
  /// `purchaseReturnAdjustment`) and the historical `sale_return_cogs`
  /// remain whitelisted so historical entries written by the deprecated
  /// pipeline continue to validate.
  static const Set<String> _systemEntryTypes = {
    'sale',
    'purchase',
    'payment',
    'sale_return',
    'purchase_return',
    'return_settlement',
    'sale_return_cogs',
    'saleReturn',
    'purchaseReturn',
    'purchaseReturnAdjustment',
    'saleReturnAdjustment',
    'reversal',
    'customer_payment',
    'customer_discount',
    'supplier_payment',
    'supplier_discount',
    'consignment_ownership_conversion',
    'consignment_ownership_conversion_void',
    'warehouse_transfer_dispatch',
    'warehouse_transfer_receipt',
    'warehouse_transfer_recall',
    'consignment_settlement',
    'consignment_settlement_void',
    'consignment_settlement_payment',
    'consignment_settlement_payment_reversal',
    'closing',
    'opening_balance',
    'owner_contribution',
    'owner_withdrawal',
    'owner_loan_received',
    'owner_loan_repayment',
    'fixed_asset_acquisition',
    'fixed_asset_depreciation',
    // Phase 2.3 — customer credit-note sub-ledger. Issued, applied, and
    // voided exclusively by `CustomerCreditNoteService` (no UI path),
    // so they qualify as system entries that may legally touch 1100 AR.
    'credit_note_issuance',
    'credit_note_application',
    'credit_note_void',
    'cheque_clearance',
    'cheque_return_deferral',
    'cheque_return_settlement',
    'account_cheque_settlement',
    'cheque_dishonour',
    'cheque_dishonour_resolution',
    'cheque_reinstatement',
  };

  AccountingRepository(this._db) : _fiscalPeriodService = null;

  /// DI-wired constructor — Phase 11.1. Adds the fiscal-period guard.
  AccountingRepository.withFiscalPeriodGuard(
    this._db, {
    required FiscalPeriodService fiscalPeriodService,
  }) : _fiscalPeriodService = fiscalPeriodService;

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
    return (_db.select(
      _db.accounts,
    )..where((a) => a.id.equals(id))).watchSingleOrNull();
  }

  /// Get account by code
  Future<Account?> getAccountByCode(String code) {
    return (_db.select(
      _db.accounts,
    )..where((a) => a.accountCode.equals(code))).getSingleOrNull();
  }

  /// Get account by ID
  Future<Account?> getAccountById(int id) {
    return (_db.select(
      _db.accounts,
    )..where((a) => a.id.equals(id))).getSingleOrNull();
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
    return await _db
        .into(_db.accounts)
        .insert(
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

    final updated =
        await (_db.update(_db.accounts)..where((a) => a.id.equals(id))).write(
          AccountsCompanion(
            accountName: accountName != null
                ? Value(accountName)
                : const Value.absent(),
            description: description != null
                ? Value(description)
                : const Value.absent(),
            isActive: isActive != null ? Value(isActive) : const Value.absent(),
            displayOrder: displayOrder != null
                ? Value(displayOrder)
                : const Value.absent(),
            updatedAt: Value(DateTime.now()),
          ),
        );
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
      if (line.debitCents < 0 || line.creditCents < 0) {
        throw AccountingException('Journal amounts cannot be negative');
      }
      totalDebits += line.debitCents;
      totalCredits += line.creditCents;

      // Validate each line has debit OR credit, not both
      if (line.debitCents > 0 && line.creditCents > 0) {
        throw AccountingException(
          'Journal line cannot have both debit and credit',
        );
      }
      if (line.debitCents == 0 && line.creditCents == 0) {
        throw AccountingException(
          'Journal line must have either debit or credit',
        );
      }
    }

    if (totalDebits != totalCredits) {
      throw AccountingException(
        'Journal entry unbalanced: Debits=$totalDebits, Credits=$totalCredits',
      );
    }

    if (entryData.lines.length < 2) {
      throw AccountingException('Journal entry must have at least 2 lines');
    }

    // Phase 11.3a — single-currency invariant.
    // Every line of one JE MUST share the same currencyId. Cross-currency
    // postings demand FX conversion + realised/unrealised gain-or-loss
    // accounts which the current chart does not model; rather than silently
    // accept a mathematically balanced but economically meaningless entry,
    // we reject it at the canonical writer. Mixed currencies require two
    // separate journal entries (one per currency) bridged by an explicit
    // FX-conversion JE.
    final currencyIds = entryData.lines.map((l) => l.currencyId).toSet();
    if (currencyIds.length > 1) {
      throw AccountingException(
        'Journal entry mixes currencies (${currencyIds.toList()..sort()}). '
        'Cross-currency postings require an explicit FX-conversion entry; '
        'split the transaction into one journal entry per currency.',
      );
    }

    // Enforce control account protection: manual entries cannot touch AR/AP
    final entryType = entryData.entryType ?? 'manual';
    if (!_systemEntryTypes.contains(entryType)) {
      for (final line in entryData.lines) {
        final account = await getAccountById(line.accountId);
        if (account != null &&
            _controlAccountCodes.contains(account.accountCode)) {
          throw AccountingException(
            'Cannot modify control account "${account.accountName}" (${account.accountCode}) '
            'via manual journal entry. Use the appropriate business transaction '
            '(sale, purchase, payment) instead.',
          );
        }
      }
    }

    // Enforce closed period lock (legacy `accounting_periods` table).
    final entryDate = entryData.entryDate ?? DateTime.now();
    if (await isDateInClosedPeriod(entryDate)) {
      throw AccountingException(
        'Cannot post journal entry: date ${entryDate.toIso8601String().substring(0, 10)} falls in a closed accounting period',
      );
    }

    // Phase 11.1 — fiscal-period guard (newer `fiscal_periods` table).
    // Throws FiscalPeriodClosedException if the month is closed. Both
    // period systems are checked independently; closing in either one
    // freezes the GL for that date range.
    await _fiscalPeriodService?.assertOpen(entryDate);

    // Execute in atomic transaction
    return await _db.transaction(() async {
      // Generate entry number
      final entryNumber = await _generateEntryNumber();

      // Create journal entry header
      final entryId = await _db
          .into(_db.journalEntries)
          .insert(
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
              postedBy: entryData.autoPost
                  ? Value(userId)
                  : const Value.absent(),
              postedAt: entryData.autoPost
                  ? Value(DateTime.now())
                  : const Value.absent(),
            ),
          );

      // Create journal entry lines
      int lineNumber = 1;
      for (final line in entryData.lines) {
        await _db
            .into(_db.journalEntryLines)
            .insert(
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
  ///
  /// `userId` is nullable to mirror `voidJournalEntry` and to allow
  /// non-interactive callers (e.g. `JournalRepositoryImpl` delegation from
  /// UI blocs where the current user may not be resolved). Drift's
  /// `postedBy` column is nullable in the schema.
  Future<bool> postJournalEntry({
    required int entryId,
    required int? userId,
  }) async {
    return _db.transaction(() async {
      final entry = await (_db.select(
        _db.journalEntries,
      )..where((e) => e.id.equals(entryId))).getSingleOrNull();

      if (entry == null) {
        throw AccountingException('Journal entry not found');
      }

      if (entry.status != 'draft') {
        throw AccountingException('Only draft entries can be posted');
      }

      // Enforce closed period lock (legacy `accounting_periods` table).
      if (await isDateInClosedPeriod(entry.entryDate)) {
        throw AccountingException(
          'Cannot post journal entry: date ${entry.entryDate.toIso8601String().substring(0, 10)} falls in a closed accounting period',
        );
      }

      // Phase 11.1 — fiscal-period guard (newer `fiscal_periods` table).
      await _fiscalPeriodService?.assertOpen(entry.entryDate);

      final draftLines = await (_db.select(
        _db.journalEntryLines,
      )..where((l) => l.journalEntryId.equals(entryId))).get();
      final data = JournalEntryData(
        description: entry.description,
        lines: draftLines
            .map(
              (line) => JournalEntryLineData(
                accountId: line.accountId,
                debitCents: line.debitCents.toBigInt().toInt(),
                creditCents: line.creditCents.toBigInt().toInt(),
                currencyId: line.currencyId,
              ),
            )
            .toList(),
      );
      if (!data.isValid ||
          data.lines.map((l) => l.currencyId).toSet().length != 1 ||
          entry.totalDebitCents.toBigInt().toInt() != data.totalDebitCents ||
          entry.totalCreditCents.toBigInt().toInt() != data.totalCreditCents) {
        throw AccountingException('Invalid draft journal entry');
      }
      // Update entry status
      await (_db.update(
        _db.journalEntries,
      )..where((e) => e.id.equals(entryId))).write(
        JournalEntriesCompanion(
          status: const Value('posted'),
          postedBy: Value(userId),
          postedAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
        ),
      );

      // Update account balances
      final lines = await (_db.select(
        _db.journalEntryLines,
      )..where((l) => l.journalEntryId.equals(entryId))).get();

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
    required int? userId,
  }) async {
    final entry = await (_db.select(
      _db.journalEntries,
    )..where((e) => e.id.equals(entryId))).getSingleOrNull();

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
    final originalLines = await (_db.select(
      _db.journalEntryLines,
    )..where((l) => l.journalEntryId.equals(entryId))).get();

    // Create reversal entry with opposite amounts
    final reversalLines = originalLines
        .map(
          (line) => JournalEntryLineData(
            accountId: line.accountId,
            debitCents: line.creditCents
                .toBigInt()
                .toInt(), // Swap debit/credit
            creditCents: line.debitCents.toBigInt().toInt(),
            currencyId: line.currencyId,
            description: 'REVERSAL: ${line.description ?? ""}',
          ),
        )
        .toList();

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

      // Mark original entry as reversed but keep status='posted'
      // so the original + reversal cancel each other out in the GL.
      // Changing status to 'voided' would EXCLUDE the original from GL
      // while the reversal (also posted) subtracts again — double removal.
      await (_db.update(
        _db.journalEntries,
      )..where((e) => e.id.equals(entryId))).write(
        JournalEntriesCompanion(
          isReversed: const Value(true),
          updatedAt: Value(DateTime.now()),
        ),
      );

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

    return (query..orderBy([
          (e) => OrderingTerm(expression: e.entryDate, mode: OrderingMode.desc),
        ]))
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
    String sourceTable,
    int sourceId,
  ) {
    return (_db.select(_db.journalEntries)
          ..where((e) => e.sourceTable.equals(sourceTable))
          ..where((e) => e.sourceId.equals(sourceId)))
        .get();
  }

  // ============================================================
  // TRIAL BALANCE & REPORTS
  // ============================================================

  /// Rebuilds the denormalized account-balance cache from posted journal
  /// lines. Journal lines remain the source of truth; this method exists for
  /// repair migrations that correct historical journal amounts.
  ///
  /// Keep this writer in [AccountingRepository] so every change to
  /// `accounts.balance_cents` continues to pass through the accounting
  /// boundary instead of being issued as raw SQL by a migration.
  Future<void> rebuildCachedAccountBalancesFromPostedLedger() async {
    final accountRows = await _db.select(_db.accounts).get();
    final joinedRows = await (_db.select(_db.journalEntryLines).join([
      innerJoin(
        _db.journalEntries,
        _db.journalEntries.id.equalsExp(_db.journalEntryLines.journalEntryId),
      ),
    ])..where(_db.journalEntries.status.equals('posted'))).get();

    final debitByAccount = <int, int>{};
    final creditByAccount = <int, int>{};
    for (final row in joinedRows) {
      final line = row.readTable(_db.journalEntryLines);
      debitByAccount.update(
        line.accountId,
        (value) => value + line.debitCents.toBigInt().toInt(),
        ifAbsent: () => line.debitCents.toBigInt().toInt(),
      );
      creditByAccount.update(
        line.accountId,
        (value) => value + line.creditCents.toBigInt().toInt(),
        ifAbsent: () => line.creditCents.toBigInt().toInt(),
      );
    }

    final now = DateTime.now();
    for (final account in accountRows) {
      final debit = debitByAccount[account.id] ?? 0;
      final credit = creditByAccount[account.id] ?? 0;
      final type = account.accountType.toLowerCase();
      final balance = type == 'asset' || type == 'expense'
          ? debit - credit
          : credit - debit;
      await (_db.update(
        _db.accounts,
      )..where((a) => a.id.equals(account.id))).write(
        AccountsCompanion(
          balanceCents: Value(Decimal.fromInt(balance)),
          updatedAt: Value(now),
        ),
      );
    }
  }

  /// Trial Balance — SINGLE SOURCE OF TRUTH: journal_lines table.
  /// Never uses cached balanceCents. Always aggregates from posted journal lines.
  Future<TrialBalance> getTrialBalance({DateTime? asOfDate}) async {
    final accounts =
        await (_db.select(_db.accounts)
              ..where((a) => a.isActive.equals(true))
              ..orderBy([(a) => OrderingTerm(expression: a.accountCode)]))
            .get();
    final effectiveDate = asOfDate ?? DateTime.now();

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
    final lines = rows
        .map((row) => row.readTable(_db.journalEntryLines))
        .toList(growable: false);
    final trialBalance = TrialBalanceCalculationService.calculate(
      accounts: accounts,
      lines: lines,
      asOfDate: effectiveDate,
    );

    if (!trialBalance.isBalanced) {
      developer.log(
        'WARNING [AccountingRepo]: Trial Balance unbalanced! '
        'Debits=${trialBalance.totalDebitCents}, '
        'Credits=${trialBalance.totalCreditCents}, '
        'Diff=${trialBalance.differenceCents}',
        name: 'TrialBalance',
      );
    }
    return trialBalance;
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

    final entries = await (_db.select(
      _db.journalEntries,
    )..where((e) => e.status.equals('posted'))).get();
    for (final entry in entries) {
      if (entry.totalDebitCents != entry.totalCreditCents) {
        issues.add('Unbalanced posted entry: ${entry.entryNumber}');
      }
    }

    final accounts = await (_db.select(
      _db.accounts,
    )..where((a) => a.isActive.equals(true))).get();
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

    // Compare the GL and sub-ledgers at the exact same instant. Party cache
    // columns are intentionally excluded because they may be stale.
    final partyBalances = await PartyControlAccountBalanceService(
      _db,
    ).load(asOf: trialBalance.asOfDate);
    final customerDishonouredCheques =
        await _dishonouredChequeReceivableForPartyType(
          'customer',
          trialBalance.asOfDate,
        );
    final supplierDishonouredCheques =
        await _dishonouredChequeReceivableForPartyType(
          'supplier',
          trialBalance.asOfDate,
        );

    final arAccount = await getAccountByCode('1100');
    if (arAccount != null) {
      final arItem = trialBalance.items
          .where((i) => i.accountId == arAccount.id)
          .firstOrNull;
      final arBalance = arItem?.naturalBalanceCents ?? 0;
      final customerControlBalance = arBalance + customerDishonouredCheques;
      final customerTotal = partyBalances.customerBalanceCents;
      if (customerControlBalance != customerTotal) {
        issues.add(
          customerDishonouredCheques == 0
              ? 'Accounts receivable mismatch: GL(journal_lines)=$arBalance, Customers=$customerTotal'
              : 'Accounts receivable mismatch: GL(1100+customer 1030)='
                    '$customerControlBalance, Customers=$customerTotal',
        );
      }
    }

    final apAccount = await getAccountByCode('2000');
    if (apAccount != null) {
      final apItem = trialBalance.items
          .where((i) => i.accountId == apAccount.id)
          .firstOrNull;
      final apBalance = apItem?.naturalBalanceCents ?? 0;
      final supplierControlBalance = apBalance - supplierDishonouredCheques;
      final supplierTotal = partyBalances.supplierBalanceCents;
      if (supplierControlBalance != supplierTotal) {
        issues.add(
          supplierDishonouredCheques == 0
              ? 'Accounts payable mismatch: GL(journal_lines)=$apBalance, Suppliers=$supplierTotal'
              : 'Accounts payable mismatch: GL(2000-supplier 1030)='
                    '$supplierControlBalance, Suppliers=$supplierTotal',
        );
      }
    }

    return ReconciliationResult(
      isHealthy: issues.isEmpty,
      issues: issues,
      timestamp: DateTime.now(),
    );
  }

  /// Portion of account 1030 attributable to one party sub-ledger.
  ///
  /// Customer and supplier dishonoured cheques share the same GL account,
  /// while their sub-ledgers use opposite signs. Keeping the split by the
  /// cheque's party type prevents valid 1030 balances from being reported as
  /// false AR/AP reconciliation deficits.
  Future<int> _dishonouredChequeReceivableForPartyType(
    String partyType,
    DateTime asOf,
  ) async {
    final row = await _db
        .customSelect(
          '''
SELECT COALESCE(SUM(jel.debit_cents - jel.credit_cents), 0) AS balance
  FROM journal_entries je
  JOIN journal_entry_lines jel ON jel.journal_entry_id = je.id
  JOIN accounts a ON a.id = jel.account_id
  JOIN cheque_instruments ci
    ON je.source_table = 'cheque_instruments' AND je.source_id = ci.id
 WHERE je.entry_type = 'cheque_dishonour'
   AND je.status = 'posted'
   AND je.is_reversed = 0
   AND je.entry_date <= ?
   AND a.account_code = '1030'
   AND ci.direction = 'incoming'
   AND ci.status = 'bounced'
   AND ci.resolved_at IS NULL
   AND ci.party_type = ?
''',
          variables: [
            Variable.withDateTime(asOf),
            Variable.withString(partyType),
          ],
        )
        .getSingle();
    return row.read<int>('balance');
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
    // These two system accounts are intentionally contra accounts and are
    // classified opposite to their numeric prefix.
    switch (trimmed) {
      case '4100':
        return 'expense';
      case '5700':
        return 'revenue';
    }
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
          ..orderBy([
            (p) =>
                OrderingTerm(expression: p.startDate, mode: OrderingMode.desc),
          ]))
        .getSingleOrNull();
  }

  /// Create accounting period
  Future<int> createAccountingPeriod({
    required String periodName,
    required DateTime startDate,
    required DateTime endDate,
  }) {
    return _db
        .into(_db.accountingPeriods)
        .insert(
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
    final updated =
        await (_db.update(
          _db.accountingPeriods,
        )..where((p) => p.id.equals(periodId))).write(
          AccountingPeriodsCompanion(
            isClosed: const Value(true),
            closedAt: Value(DateTime.now()),
            closedBy: Value(userId),
            updatedAt: Value(DateTime.now()),
          ),
        );
    return updated > 0;
  }

  /// Check if a date falls within a closed accounting period.
  /// Returns true if the date is in a closed period (transaction should be blocked).
  Future<bool> isDateInClosedPeriod(DateTime date) async {
    final closedPeriods =
        await (_db.select(_db.accountingPeriods)
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

    await (_db.update(
      _db.accounts,
    )..where((a) => a.id.equals(accountId))).write(
      AccountsCompanion(
        balanceCents: Value(Decimal.fromInt(newBalance)),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Generate unique entry number
  /// Execute a raw SQL SELECT query and return the results.
  /// Used by JournalEntryService for repair operations.
  Future<List<QueryRow>> rawSelect(String sql) {
    return _db.customSelect(sql).get();
  }

  Future<String> _generateEntryNumber() async {
    final now = DateTime.now();
    final prefix = 'JE${now.year}${now.month.toString().padLeft(2, '0')}';

    final lastEntry =
        await (_db.select(_db.journalEntries)
              ..where((e) => e.entryNumber.like('$prefix%'))
              ..orderBy([
                (e) => OrderingTerm(expression: e.id, mode: OrderingMode.desc),
              ])
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
