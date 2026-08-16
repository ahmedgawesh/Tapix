import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/features/accounting/data/datasources/journal_local_datasource.dart';
import 'package:tapix/features/accounting/data/repositories/accounting_repository.dart';
import 'package:tapix/features/accounting/data/repositories/journal_repository_impl.dart';
import 'package:tapix/features/accounting/domain/models/journal_entry_data.dart';
import 'package:tapix/features/accounting/domain/models/reconciliation_result.dart';
import 'package:tapix/features/accounting/domain/models/trial_balance.dart';
import 'package:tapix/features/accounting/domain/repositories/journal_repository.dart';

/// Fake datasource that records calls for verification
class FakeJournalLocalDatasource extends Fake
    implements JournalLocalDatasource {
  int createAccountCallCount = 0;
  int createEntryCallCount = 0;
  int createLineCallCount = 0;
  int updateEntryCallCount = 0;
  int updateAccountCallCount = 0;
  int getEntryLinesCallCount = 0;

  JournalEntry? _entryToReturn;
  Account? Function(int id)? _accountLookup;
  List<JournalEntryLine> _linesToReturn = [];
  bool _isDateInClosedPeriod = false;
  int _customerBalanceTotal = 0;
  int _supplierBalanceTotal = 0;

  void setEntryToReturn(JournalEntry? entry) => _entryToReturn = entry;
  void setAccountLookup(Account? Function(int id) fn) => _accountLookup = fn;
  void setLinesToReturn(List<JournalEntryLine> lines) => _linesToReturn = lines;
  void setIsDateInClosedPeriod(bool value) => _isDateInClosedPeriod = value;
  void setCustomerBalanceTotal(int value) => _customerBalanceTotal = value;
  void setSupplierBalanceTotal(int value) => _supplierBalanceTotal = value;

  @override
  Future<String> generateNextEntryNumber() async => 'JE-000001';

  @override
  Future<int> createJournalEntry(JournalEntriesCompanion entry) async {
    createEntryCallCount++;
    return 1;
  }

  @override
  Future<int> createJournalEntryLine(JournalEntryLinesCompanion line) async {
    createLineCallCount++;
    return createLineCallCount;
  }

  @override
  Future<JournalEntry?> getJournalEntry(int id) async => _entryToReturn;

  @override
  Future<bool> updateJournalEntry(JournalEntry entry) async {
    updateEntryCallCount++;
    return true;
  }

  @override
  Future<List<JournalEntryLine>> getJournalEntryLines(int entryId) async {
    getEntryLinesCallCount++;
    return _linesToReturn;
  }

  @override
  Future<Account?> getAccount(int id) async => _accountLookup?.call(id);

  @override
  Future<bool> isDateInClosedPeriod(DateTime date) async =>
      _isDateInClosedPeriod;

  @override
  Future<int> getCustomerBalanceTotal() async => _customerBalanceTotal;

  @override
  Future<int> getSupplierBalanceTotal() async => _supplierBalanceTotal;

  @override
  Future<bool> updateAccount(Account account) async {
    updateAccountCallCount++;
    return true;
  }

  @override
  Stream<List<Account>> watchAllAccounts() => Stream.value([]);

  @override
  Stream<List<JournalEntry>> watchJournalEntries() => Stream.value([]);

  // Seeding support
  Account? _findByCodeResult;
  void setFindByCodeResult(Account? a) => _findByCodeResult = a;

  @override
  Future<Account?> findByCode(String code) async => _findByCodeResult;

  @override
  Future<int> createAccount(AccountsCompanion account) async {
    createAccountCallCount++;
    return createAccountCallCount;
  }
}

/// Fake AccountingRepository.
///
/// Phase 1: `JournalRepositoryImpl` now delegates all balance-affecting
/// writes and trial-balance computation to `AccountingRepository`. This
/// fake records each delegated call so tests can verify that the adapter
/// forwards correctly without re-running the full accounting math.
class FakeAccountingRepository extends Fake implements AccountingRepository {
  int createJournalEntryCallCount = 0;
  int postJournalEntryCallCount = 0;
  int voidJournalEntryCallCount = 0;
  int getTrialBalanceCallCount = 0;

  JournalEntryData? lastCreateEntryData;
  int? lastCreateUserId;
  int? lastPostEntryId;
  int? lastPostUserId;
  int? lastVoidEntryId;
  String? lastVoidReason;
  int? lastVoidUserId;
  DateTime? lastTrialBalanceAsOf;

  int createJournalEntryReturnValue = 42;
  int voidJournalEntryReturnValue = 99;
  TrialBalance trialBalanceReturnValue = TrialBalance(
    asOfDate: DateTime(2026, 1, 1),
    items: const [],
    totalDebitCents: 0,
    totalCreditCents: 0,
    isBalanced: true,
  );

  @override
  Future<int> createJournalEntry({
    required JournalEntryData entryData,
    required int? userId,
  }) async {
    createJournalEntryCallCount++;
    lastCreateEntryData = entryData;
    lastCreateUserId = userId;
    return createJournalEntryReturnValue;
  }

  @override
  Future<bool> postJournalEntry({
    required int entryId,
    required int? userId,
  }) async {
    postJournalEntryCallCount++;
    lastPostEntryId = entryId;
    lastPostUserId = userId;
    return true;
  }

  @override
  Future<int> voidJournalEntry({
    required int entryId,
    required String reason,
    required int? userId,
  }) async {
    voidJournalEntryCallCount++;
    lastVoidEntryId = entryId;
    lastVoidReason = reason;
    lastVoidUserId = userId;
    return voidJournalEntryReturnValue;
  }

  @override
  Future<TrialBalance> getTrialBalance({DateTime? asOfDate}) async {
    getTrialBalanceCallCount++;
    lastTrialBalanceAsOf = asOfDate;
    return trialBalanceReturnValue;
  }

  @override
  Future<ReconciliationResult> reconcileBalances() async {
    return ReconciliationResult(
      isHealthy: true,
      issues: const [],
      timestamp: DateTime.now(),
    );
  }
}

void main() {
  late FakeJournalLocalDatasource fakeDatasource;
  late FakeAccountingRepository fakeAccountingRepo;
  late JournalRepositoryImpl repository;

  setUp(() {
    fakeDatasource = FakeJournalLocalDatasource();
    fakeAccountingRepo = FakeAccountingRepository();
    repository = JournalRepositoryImpl(fakeDatasource, fakeAccountingRepo);
  });

  group('createJournalEntryWithLines', () {
    test('should throw ArgumentError when debits != credits', () async {
      final lines = [
        JournalLineInput(
          accountId: 1,
          debitCents: Decimal.fromInt(1000),
          creditCents: Decimal.zero,
          currencyId: 1,
        ),
        JournalLineInput(
          accountId: 2,
          debitCents: Decimal.zero,
          creditCents: Decimal.fromInt(500),
          currencyId: 1,
        ),
      ];

      expect(
        () => repository.createJournalEntryWithLines(
          description: 'Test',
          entryDate: DateTime.now(),
          entryType: 'manual',
          lines: lines,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('should throw ArgumentError when total is zero', () async {
      final lines = [
        JournalLineInput(
          accountId: 1,
          debitCents: Decimal.zero,
          creditCents: Decimal.zero,
          currencyId: 1,
        ),
        JournalLineInput(
          accountId: 2,
          debitCents: Decimal.zero,
          creditCents: Decimal.zero,
          currencyId: 1,
        ),
      ];

      expect(
        () => repository.createJournalEntryWithLines(
          description: 'Test',
          entryDate: DateTime.now(),
          entryType: 'manual',
          lines: lines,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('should throw ArgumentError when less than 2 lines', () async {
      final lines = [
        JournalLineInput(
          accountId: 1,
          debitCents: Decimal.fromInt(1000),
          creditCents: Decimal.zero,
          currencyId: 1,
        ),
      ];

      expect(
        () => repository.createJournalEntryWithLines(
          description: 'Test',
          entryDate: DateTime.now(),
          entryType: 'manual',
          lines: lines,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test(
      'should delegate to AccountingRepository.createJournalEntry when balanced',
      () async {
        // Phase 1: JournalRepositoryImpl is a thin adapter. The actual write
        // is performed by AccountingRepository — verify the delegation
        // contract, not the table writes.
        final lines = [
          JournalLineInput(
            accountId: 1,
            debitCents: Decimal.fromInt(1000),
            creditCents: Decimal.zero,
            currencyId: 1,
          ),
          JournalLineInput(
            accountId: 2,
            debitCents: Decimal.zero,
            creditCents: Decimal.fromInt(1000),
            currencyId: 1,
          ),
        ];

        fakeAccountingRepo.createJournalEntryReturnValue = 7;

        final result = await repository.createJournalEntryWithLines(
          description: 'Test balanced entry',
          entryDate: DateTime(2026, 1, 15),
          entryType: 'manual',
          lines: lines,
          createdBy: 42,
        );

        expect(result, 7);
        expect(fakeAccountingRepo.createJournalEntryCallCount, 1);
        expect(fakeAccountingRepo.lastCreateUserId, 42);

        final captured = fakeAccountingRepo.lastCreateEntryData!;
        expect(captured.description, 'Test balanced entry');
        expect(captured.entryType, 'manual');
        expect(
          captured.autoPost,
          isFalse,
          reason: 'createJournalEntryWithLines must always create drafts',
        );
        expect(captured.lines.length, 2);
        expect(captured.lines[0].debitCents, 1000);
        expect(captured.lines[0].creditCents, 0);
        expect(captured.lines[1].debitCents, 0);
        expect(captured.lines[1].creditCents, 1000);

        // Datasource must NOT be written through directly — that would mean
        // we still have a second writer. Phase 1 invariant.
        expect(fakeDatasource.createEntryCallCount, 0);
        expect(fakeDatasource.createLineCallCount, 0);
      },
    );
  });

  group('postJournalEntry', () {
    test('should throw ArgumentError when entry not found', () async {
      fakeDatasource.setEntryToReturn(null);

      expect(
        () => repository.postJournalEntry(999),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('should throw StateError when entry is not draft', () async {
      fakeDatasource.setEntryToReturn(
        JournalEntry(
          id: 1,
          entryNumber: 'JE-000001',
          description: 'Test',
          entryDate: DateTime.now(),
          status: 'posted',
          entryType: 'manual',
          totalDebitCents: Decimal.fromInt(1000),
          totalCreditCents: Decimal.fromInt(1000),
          isReversed: false,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );

      expect(() => repository.postJournalEntry(1), throwsA(isA<StateError>()));
    });

    test(
      'should delegate to AccountingRepository.postJournalEntry for draft entries',
      () async {
        // Phase 1: balance updates live in AccountingRepository.
        // JournalRepositoryImpl must NOT touch accounts.balance_cents itself.
        final now = DateTime.now();
        fakeDatasource.setEntryToReturn(
          JournalEntry(
            id: 1,
            entryNumber: 'JE-000001',
            description: 'Test',
            entryDate: now,
            status: 'draft',
            entryType: 'manual',
            totalDebitCents: Decimal.fromInt(1000),
            totalCreditCents: Decimal.fromInt(1000),
            isReversed: false,
            createdAt: now,
            updatedAt: now,
          ),
        );

        await repository.postJournalEntry(1, postedBy: 99);

        expect(fakeAccountingRepo.postJournalEntryCallCount, 1);
        expect(fakeAccountingRepo.lastPostEntryId, 1);
        expect(fakeAccountingRepo.lastPostUserId, 99);

        // Phase 1 invariant: the OLD inline balance writer is gone — the
        // datasource must not be used to mutate balances or update the entry
        // status. Both happen inside AccountingRepository now.
        expect(fakeDatasource.updateEntryCallCount, 0);
        expect(fakeDatasource.updateAccountCallCount, 0);
      },
    );
  });

  group('voidJournalEntry', () {
    test('should throw ArgumentError when entry not found', () async {
      fakeDatasource.setEntryToReturn(null);

      expect(
        () => repository.voidJournalEntry(999, reason: 'Test'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('should throw StateError when entry is not posted', () async {
      fakeDatasource.setEntryToReturn(
        JournalEntry(
          id: 1,
          entryNumber: 'JE-000001',
          description: 'Test',
          entryDate: DateTime.now(),
          status: 'draft',
          entryType: 'manual',
          totalDebitCents: Decimal.fromInt(1000),
          totalCreditCents: Decimal.fromInt(1000),
          isReversed: false,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );

      expect(
        () => repository.voidJournalEntry(1, reason: 'Test'),
        throwsA(isA<StateError>()),
      );
    });

    test(
      'should delegate to AccountingRepository.voidJournalEntry for posted entries',
      () async {
        final now = DateTime.now();
        fakeDatasource.setEntryToReturn(
          JournalEntry(
            id: 1,
            entryNumber: 'JE-000001',
            description: 'Test',
            entryDate: now,
            status: 'posted',
            entryType: 'manual',
            totalDebitCents: Decimal.fromInt(1000),
            totalCreditCents: Decimal.fromInt(1000),
            isReversed: false,
            createdAt: now,
            updatedAt: now,
          ),
        );
        fakeAccountingRepo.voidJournalEntryReturnValue = 123;

        final reversalId = await repository.voidJournalEntry(
          1,
          reason: 'User correction',
          createdBy: 77,
        );

        expect(reversalId, 123);
        expect(fakeAccountingRepo.voidJournalEntryCallCount, 1);
        expect(fakeAccountingRepo.lastVoidEntryId, 1);
        expect(fakeAccountingRepo.lastVoidReason, 'User correction');
        expect(fakeAccountingRepo.lastVoidUserId, 77);
      },
    );
  });

  group('getTrialBalance', () {
    test('should delegate to AccountingRepository.getTrialBalance', () async {
      final asOf = DateTime(2026, 6, 30);
      final tb = await repository.getTrialBalance(asOfDate: asOf);

      expect(fakeAccountingRepo.getTrialBalanceCallCount, 1);
      expect(fakeAccountingRepo.lastTrialBalanceAsOf, asOf);
      expect(tb.isBalanced, isTrue);
    });
  });

  group('watchAllAccounts', () {
    test('should delegate to datasource', () {
      final result = repository.watchAllAccounts();
      expect(result, emits(<Account>[]));
    });
  });

  group('watchAllJournalEntries', () {
    test('should delegate to datasource', () {
      final result = repository.watchAllJournalEntries();
      expect(result, emits(<JournalEntry>[]));
    });
  });

  group('seedDefaultAccounts', () {
    test('should skip seeding if accounts already exist', () async {
      fakeDatasource.setFindByCodeResult(
        Account(
          id: 1,
          accountCode: '10000',
          accountName: 'Assets',
          accountType: 'asset',
          balanceCents: Decimal.zero,
          currencyId: 1,
          isActive: true,
          isSystemAccount: true,
          displayOrder: 1,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );

      await repository.seedDefaultAccounts(1);

      expect(fakeDatasource.createAccountCallCount, 0);
    });

    test('should seed 31 default accounts when none exist', () async {
      fakeDatasource.setFindByCodeResult(null);
      fakeDatasource.setAccountLookup(
        (id) => Account(
          id: id,
          accountCode: '10100',
          accountName: 'Cash',
          accountType: 'asset',
          balanceCents: Decimal.zero,
          currencyId: 1,
          isActive: true,
          isSystemAccount: true,
          displayOrder: 1,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );

      await repository.seedDefaultAccounts(1);

      // Phase 1.4 added 2400 Customer Credit Liability (21 → 22).
      // Phase 2.2 added 1290 Returns in Transit, the asset clearing account
      // for the `send_back` disposition on purchase returns (22 → 23).
      // Phase 13 added 4900 Purchase Discounts Earned, the revenue/other-
      // income account for unallocated supplier rebates that previously
      // (and incorrectly) credited Inventory and drove a GL drift below
      // Σ(stock × cost). See supplier_discount_inventory_drift_test.dart.
      // (23 → 24).
      // Phase 10061 added seven owner-finance/fixed-asset accounts:
      // 1500, 1510, 1520, 1590, 2200, 3200, and 6100 (24 → 31).
      expect(fakeDatasource.createAccountCallCount, 31);
    });
  });
}
