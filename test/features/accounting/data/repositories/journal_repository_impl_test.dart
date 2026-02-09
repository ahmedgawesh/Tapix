import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/features/accounting/data/datasources/journal_local_datasource.dart';
import 'package:tapix/features/accounting/data/repositories/journal_repository_impl.dart';
import 'package:tapix/features/accounting/domain/repositories/journal_repository.dart';

/// Fake datasource that records calls for verification
class FakeJournalLocalDatasource extends Fake implements JournalLocalDatasource {
  int createAccountCallCount = 0;
  int createEntryCallCount = 0;
  int createLineCallCount = 0;
  int updateEntryCallCount = 0;
  int updateAccountCallCount = 0;
  int getEntryLinesCallCount = 0;

  JournalEntry? _entryToReturn;
  Account? Function(int id)? _accountLookup;
  List<JournalEntryLine> _linesToReturn = [];

  void setEntryToReturn(JournalEntry? entry) => _entryToReturn = entry;
  void setAccountLookup(Account? Function(int id) fn) => _accountLookup = fn;
  void setLinesToReturn(List<JournalEntryLine> lines) => _linesToReturn = lines;

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

void main() {
  late FakeJournalLocalDatasource fakeDatasource;
  late JournalRepositoryImpl repository;

  setUp(() {
    fakeDatasource = FakeJournalLocalDatasource();
    repository = JournalRepositoryImpl(fakeDatasource);
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

    test('should create entry and lines when balanced', () async {
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

      final result = await repository.createJournalEntryWithLines(
        description: 'Test balanced entry',
        entryDate: DateTime(2026, 1, 15),
        entryType: 'manual',
        lines: lines,
      );

      expect(result, 1);
      expect(fakeDatasource.createEntryCallCount, 1);
      expect(fakeDatasource.createLineCallCount, 2);
    });
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
      fakeDatasource.setEntryToReturn(JournalEntry(
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
      ));

      expect(
        () => repository.postJournalEntry(1),
        throwsA(isA<StateError>()),
      );
    });

    test('should post draft entry and update account balances', () async {
      final now = DateTime.now();
      fakeDatasource.setEntryToReturn(JournalEntry(
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
      ));

      fakeDatasource.setLinesToReturn([
        JournalEntryLine(
          id: 1, journalEntryId: 1, accountId: 1,
          debitCents: Decimal.fromInt(1000), creditCents: Decimal.zero,
          currencyId: 1, lineNumber: 1, createdAt: now,
        ),
        JournalEntryLine(
          id: 2, journalEntryId: 1, accountId: 2,
          debitCents: Decimal.zero, creditCents: Decimal.fromInt(1000),
          currencyId: 1, lineNumber: 2, createdAt: now,
        ),
      ]);

      fakeDatasource.setAccountLookup((id) {
        if (id == 1) {
          return Account(
            id: 1, accountCode: '10100', accountName: 'Cash',
            accountType: 'asset', balanceCents: Decimal.zero,
            currencyId: 1, isActive: true, isSystemAccount: true,
            displayOrder: 1, createdAt: now, updatedAt: now,
          );
        }
        if (id == 2) {
          return Account(
            id: 2, accountCode: '40100', accountName: 'Sales Revenue',
            accountType: 'revenue', balanceCents: Decimal.zero,
            currencyId: 1, isActive: true, isSystemAccount: true,
            displayOrder: 2, createdAt: now, updatedAt: now,
          );
        }
        return null;
      });

      await repository.postJournalEntry(1);

      expect(fakeDatasource.updateEntryCallCount, 1);
      expect(fakeDatasource.getEntryLinesCallCount, 1);
      expect(fakeDatasource.updateAccountCallCount, 2);
    });
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
      fakeDatasource.setEntryToReturn(JournalEntry(
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
      ));

      expect(
        () => repository.voidJournalEntry(1, reason: 'Test'),
        throwsA(isA<StateError>()),
      );
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
      fakeDatasource.setFindByCodeResult(Account(
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
      ));

      await repository.seedDefaultAccounts(1);

      expect(fakeDatasource.createAccountCallCount, 0);
    });

    test('should seed 21 default accounts when none exist', () async {
      fakeDatasource.setFindByCodeResult(null);
      fakeDatasource.setAccountLookup((id) => Account(
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
          ));

      await repository.seedDefaultAccounts(1);

      expect(fakeDatasource.createAccountCallCount, 21);
    });
  });
}
