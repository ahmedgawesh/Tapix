import 'package:decimal/decimal.dart';
import '../../../../core/database/app_database.dart';
import '../../domain/models/trial_balance.dart';
import '../../domain/models/reconciliation_result.dart';

/// Domain repository interface for journal entry and account operations
abstract class JournalRepository {
  // ── Accounts ──────────────────────────────────────────────

  /// Watch all active accounts ordered by code
  Stream<List<Account>> watchAllAccounts();

  /// Watch accounts filtered by type
  Stream<List<Account>> watchAccountsByType(String accountType);

  /// Watch a single account by ID
  Stream<Account?> watchAccount(int id);

  /// Get a single account by ID
  Future<Account?> getAccount(int id);

  /// Find account by code
  Future<Account?> findAccountByCode(String code);

  /// Get child accounts of a parent
  Future<List<Account>> getChildAccounts(int parentId);

  /// Create a new account
  Future<int> createAccount({
    required String accountCode,
    required String accountName,
    required String accountType,
    required int currencyId,
    int? parentAccountId,
    bool isSystemAccount,
    int displayOrder,
    String? description,
  });

  /// Update an existing account
  Future<bool> updateAccount(Account account);

  /// Delete an account by ID
  Future<int> deleteAccount(int id);

  /// Watch account count
  Stream<int> watchAccountCount({bool? isActive});

  // ── Journal Entries ───────────────────────────────────────

  /// Watch all journal entries ordered by date descending
  Stream<List<JournalEntry>> watchAllJournalEntries();

  /// Watch journal entries filtered by date range
  Stream<List<JournalEntry>> watchJournalEntriesByDateRange(DateTime start, DateTime end);

  /// Watch journal entries filtered by type
  Stream<List<JournalEntry>> watchJournalEntriesByType(String entryType);

  /// Watch journal entries filtered by status
  Stream<List<JournalEntry>> watchJournalEntriesByStatus(String status);

  /// Get a single journal entry by ID
  Future<JournalEntry?> getJournalEntry(int id);

  /// Find journal entry by entry number
  Future<JournalEntry?> findJournalEntryByNumber(String entryNumber);

  /// Find journal entry by source document
  Future<JournalEntry?> findJournalEntryBySource(String sourceTable, int sourceId);

  /// Search journal entries by description or entry number
  Future<List<JournalEntry>> searchJournalEntries(String query);

  /// Create a journal entry with lines (transactional)
  Future<int> createJournalEntryWithLines({
    required String description,
    required DateTime entryDate,
    required String entryType,
    required List<JournalLineInput> lines,
    String? sourceTable,
    int? sourceId,
    int? createdBy,
  });

  /// Post a draft journal entry (makes it immutable)
  Future<void> postJournalEntry(int entryId, {int? postedBy});

  /// Void a posted journal entry (creates reversal)
  Future<int> voidJournalEntry(int entryId, {required String reason, int? createdBy});

  /// Watch journal entry count
  Stream<int> watchJournalEntryCount({String? status});

  // ── Journal Entry Lines ───────────────────────────────────

  /// Watch lines for a specific journal entry
  Stream<List<JournalEntryLine>> watchJournalEntryLines(int entryId);

  /// Get lines for a specific journal entry
  Future<List<JournalEntryLine>> getJournalEntryLines(int entryId);

  /// Watch all lines for a specific account (general ledger)
  Stream<List<JournalEntryLine>> watchJournalLinesByAccount(int accountId);

  // ── Accounting Periods ────────────────────────────────────

  /// Watch all accounting periods
  Stream<List<AccountingPeriod>> watchAccountingPeriods();

  /// Get the active (open) accounting period
  Future<AccountingPeriod?> getActiveAccountingPeriod();

  /// Seed default chart of accounts (idempotent)
  Future<void> seedDefaultAccounts(int currencyId);

  // ── Trial Balance & Reconciliation ────────────────────────

  /// Get trial balance computed from current account balances
  Future<TrialBalance> getTrialBalance({DateTime? asOfDate});

  /// Run reconciliation checks and return any issues found
  Future<ReconciliationResult> reconcileBalances();

  // ── Date-Range Queries ──────────────────────────────────

  /// Watch posted journal entry lines within a date range
  Stream<List<JournalEntryLine>> watchPostedLinesByDateRange(
    DateTime startDate, DateTime endDate);

  /// Watch posted journal entry lines for a specific account within a date range
  Stream<List<JournalEntryLine>> watchPostedLinesByAccountAndDateRange(
    int accountId, DateTime startDate, DateTime endDate);
}

/// Input model for creating journal entry lines
class JournalLineInput {
  final int accountId;
  final Decimal debitCents;
  final Decimal creditCents;
  final int currencyId;
  final String? description;

  const JournalLineInput({
    required this.accountId,
    required this.debitCents,
    required this.creditCents,
    required this.currencyId,
    this.description,
  });
}
