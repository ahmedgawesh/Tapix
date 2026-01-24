// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'accounting_dao.dart';

// ignore_for_file: type=lint
mixin _$AccountingDaoMixin on DatabaseAccessor<AppDatabase> {
  $CurrenciesTable get currencies => attachedDatabase.currencies;
  $AccountsTable get accounts => attachedDatabase.accounts;
  $AccountingPeriodsTable get accountingPeriods =>
      attachedDatabase.accountingPeriods;
  $JournalEntriesTable get journalEntries => attachedDatabase.journalEntries;
  $JournalEntryLinesTable get journalEntryLines =>
      attachedDatabase.journalEntryLines;
  $ExpenseCategoriesTable get expenseCategories =>
      attachedDatabase.expenseCategories;
  $ExpensesTable get expenses => attachedDatabase.expenses;
  AccountingDaoManager get managers => AccountingDaoManager(this);
}

class AccountingDaoManager {
  final _$AccountingDaoMixin _db;
  AccountingDaoManager(this._db);
  $$CurrenciesTableTableManager get currencies =>
      $$CurrenciesTableTableManager(_db.attachedDatabase, _db.currencies);
  $$AccountsTableTableManager get accounts =>
      $$AccountsTableTableManager(_db.attachedDatabase, _db.accounts);
  $$AccountingPeriodsTableTableManager get accountingPeriods =>
      $$AccountingPeriodsTableTableManager(
        _db.attachedDatabase,
        _db.accountingPeriods,
      );
  $$JournalEntriesTableTableManager get journalEntries =>
      $$JournalEntriesTableTableManager(
        _db.attachedDatabase,
        _db.journalEntries,
      );
  $$JournalEntryLinesTableTableManager get journalEntryLines =>
      $$JournalEntryLinesTableTableManager(
        _db.attachedDatabase,
        _db.journalEntryLines,
      );
  $$ExpenseCategoriesTableTableManager get expenseCategories =>
      $$ExpenseCategoriesTableTableManager(
        _db.attachedDatabase,
        _db.expenseCategories,
      );
  $$ExpensesTableTableManager get expenses =>
      $$ExpensesTableTableManager(_db.attachedDatabase, _db.expenses);
}
