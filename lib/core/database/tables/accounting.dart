import 'package:drift/drift.dart';
import '../converters/money_converter.dart';
import 'settings.dart';
import 'users.dart';

/// Account types for double-entry bookkeeping
/// - asset: Debit increases, Credit decreases (1xxx codes)
/// - liability: Credit increases, Debit decreases (2xxx codes)
/// - equity: Credit increases, Debit decreases (3xxx codes)
/// - revenue: Credit increases, Debit decreases (4xxx codes)
/// - expense: Debit increases, Credit decreases (5xxx codes)
enum AccountTypeEnum { asset, liability, equity, revenue, expense }

/// Journal entry types for tracking transaction sources
enum JournalEntryTypeEnum {
  manual,      // Manual journal entry
  sale,        // Auto-generated from sale
  saleReturn,  // Auto-generated from sale return
  purchase,    // Auto-generated from purchase
  purchaseReturn, // Auto-generated from purchase return
  payment,     // Auto-generated from payment
  expense,     // Auto-generated from expense
  reversal,    // Reversal of another entry (void)
  adjustment,  // Balance adjustment
}

/// Journal entry status
enum JournalEntryStatusEnum {
  draft,   // Not yet posted
  posted,  // Posted and immutable
  voided,  // Voided (reversed)
}

@DataClassName('Account')
class Accounts extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get accountCode => text().unique()();
  TextColumn get accountName => text()();
  TextColumn get accountType => text()(); // asset, liability, equity, revenue, expense
  IntColumn get parentAccountId => integer().nullable().references(Accounts, #id, onDelete: KeyAction.restrict)();
  IntColumn get balanceCents => integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  IntColumn get currencyId => integer().references(Currencies, #id, onDelete: KeyAction.restrict)();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  BoolColumn get isSystemAccount => boolean().withDefault(const Constant(false))(); // Cannot be deleted
  IntColumn get displayOrder => integer().withDefault(const Constant(0))();
  TextColumn get description => text().nullable()();
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
  TextColumn get status => text().withDefault(const Constant('draft'))(); // draft, posted, voided
  TextColumn get entryType => text().withDefault(const Constant('manual'))(); // manual, sale, purchase, etc.
  
  // Source reference for auto-generated entries
  TextColumn get sourceTable => text().nullable()(); // 'sales', 'purchases', 'expenses', etc.
  IntColumn get sourceId => integer().nullable()(); // ID in source table
  
  // Reversal tracking for immutability
  IntColumn get reversedEntryId => integer().nullable().references(JournalEntries, #id)(); // If this is a reversal
  BoolColumn get isReversed => boolean().withDefault(const Constant(false))(); // If this entry has been reversed
  
  // Totals for quick validation (must always be equal)
  IntColumn get totalDebitCents => integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  IntColumn get totalCreditCents => integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  
  IntColumn get createdBy => integer().nullable().references(Users, #id)();
  IntColumn get postedBy => integer().nullable().references(Users, #id)();
  DateTimeColumn get postedAt => dateTime().nullable()();
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
  IntColumn get lineNumber => integer().withDefault(const Constant(1))(); // For ordering
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
