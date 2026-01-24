import 'package:drift/drift.dart';
import '../converters/money_converter.dart';
import 'settings.dart';
import 'users.dart';

@DataClassName('Account')
class Accounts extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get accountCode => text().unique()();
  TextColumn get accountName => text()();
  TextColumn get accountType => text()();
  IntColumn get parentAccountId => integer().nullable().references(Accounts, #id, onDelete: KeyAction.restrict)();
  IntColumn get balanceCents => integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  IntColumn get currencyId => integer().references(Currencies, #id, onDelete: KeyAction.restrict)();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('JournalEntry')
class JournalEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get entryNumber => text().unique()();
  TextColumn get description => text()();
  DateTimeColumn get entryDate => dateTime().withDefault(currentDateAndTime)();
  IntColumn get accountingPeriodId => integer().nullable().references(AccountingPeriods, #id, onDelete: KeyAction.restrict)();
  TextColumn get status => text().withDefault(const Constant('draft'))();
  IntColumn get createdBy => integer().nullable().references(Users, #id)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('JournalEntryLine')
class JournalEntryLines extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get journalEntryId => integer().references(JournalEntries, #id, onDelete: KeyAction.cascade)();
  IntColumn get accountId => integer().references(Accounts, #id, onDelete: KeyAction.restrict)();
  IntColumn get debitCents => integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  IntColumn get creditCents => integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  IntColumn get currencyId => integer().references(Currencies, #id, onDelete: KeyAction.restrict)();
  TextColumn get description => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('AccountingPeriod')
class AccountingPeriods extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get periodName => text()();
  DateTimeColumn get startDate => dateTime()();
  DateTimeColumn get endDate => dateTime()();
  BoolColumn get isClosed => boolean().withDefault(const Constant(false))();
  DateTimeColumn get closedAt => dateTime().nullable()();
  IntColumn get closedBy => integer().nullable().references(Users, #id)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('Expense')
class Expenses extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get categoryId => integer().references(ExpenseCategories, #id, onDelete: KeyAction.restrict)();
  TextColumn get description => text()();
  IntColumn get amountCents => integer().map(const MoneyConverter())();
  IntColumn get currencyId => integer().references(Currencies, #id, onDelete: KeyAction.restrict)();
  IntColumn get accountId => integer().nullable().references(Accounts, #id, onDelete: KeyAction.restrict)();
  DateTimeColumn get expenseDate => dateTime().withDefault(currentDateAndTime)();
  TextColumn get receiptPath => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
