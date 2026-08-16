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
  manual, // Manual journal entry
  sale, // Auto-generated from sale
  saleReturn, // Auto-generated from sale return
  purchase, // Auto-generated from purchase
  purchaseReturn, // Auto-generated from purchase return
  purchaseReturnAdjustment, // Auto-generated from purchase adjustment return (unlinked)
  saleReturnAdjustment, // Auto-generated from sale adjustment return (unlinked)
  payment, // Auto-generated from payment
  expense, // Auto-generated from expense
  reversal, // Reversal of another entry (void)
  adjustment, // Balance adjustment
  inventoryShrinkage, // Manual stock loss (theft / damage / expiry)
  inventoryGain, // Manual stock surplus (found stock / count correction)
  inventoryRevaluation, // Unit-cost change without physical movement
  inventoryOpeningBalance, // Starting stock for a newly-created product/variant
  ownerContribution,
  ownerWithdrawal,
  ownerLoanReceived,
  ownerLoanRepayment,
  fixedAssetAcquisition,
  fixedAssetDepreciation,
}

/// Journal entry status
enum JournalEntryStatusEnum {
  draft, // Not yet posted
  posted, // Posted and immutable
  voided, // Voided (reversed)
}

@DataClassName('Account')
class Accounts extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get accountCode => text().unique()();
  TextColumn get accountName => text()();
  TextColumn get accountType =>
      text()(); // asset, liability, equity, revenue, expense
  IntColumn get parentAccountId => integer().nullable().references(
    Accounts,
    #id,
    onDelete: KeyAction.restrict,
  )();
  IntColumn get balanceCents =>
      integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  IntColumn get currencyId =>
      integer().references(Currencies, #id, onDelete: KeyAction.restrict)();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  BoolColumn get isSystemAccount =>
      boolean().withDefault(const Constant(false))(); // Cannot be deleted
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
  IntColumn get accountingPeriodId => integer().nullable().references(
    AccountingPeriods,
    #id,
    onDelete: KeyAction.restrict,
  )();
  TextColumn get status =>
      text().withDefault(const Constant('draft'))(); // draft, posted, voided
  TextColumn get entryType => text().withDefault(
    const Constant('manual'),
  )(); // manual, sale, purchase, etc.

  // Source reference for auto-generated entries
  TextColumn get sourceTable =>
      text().nullable()(); // 'sales', 'purchases', 'expenses', etc.
  IntColumn get sourceId => integer().nullable()(); // ID in source table

  // Reversal tracking for immutability
  IntColumn get reversedEntryId => integer().nullable().references(
    JournalEntries,
    #id,
  )(); // If this is a reversal
  BoolColumn get isReversed => boolean().withDefault(
    const Constant(false),
  )(); // If this entry has been reversed

  // Totals for quick validation (must always be equal)
  IntColumn get totalDebitCents =>
      integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  IntColumn get totalCreditCents =>
      integer().map(const MoneyConverter()).withDefault(const Constant(0))();

  @ReferenceName('createdJournalEntries')
  IntColumn get createdBy => integer().nullable().references(Users, #id)();
  @ReferenceName('postedJournalEntries')
  IntColumn get postedBy => integer().nullable().references(Users, #id)();
  DateTimeColumn get postedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('JournalEntryLine')
class JournalEntryLines extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get journalEntryId =>
      integer().references(JournalEntries, #id, onDelete: KeyAction.cascade)();
  IntColumn get accountId =>
      integer().references(Accounts, #id, onDelete: KeyAction.restrict)();
  IntColumn get debitCents =>
      integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  IntColumn get creditCents =>
      integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  IntColumn get currencyId =>
      integer().references(Currencies, #id, onDelete: KeyAction.restrict)();
  IntColumn get lineNumber =>
      integer().withDefault(const Constant(1))(); // For ordering
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
  @ReferenceName('closedAccountingPeriods')
  IntColumn get closedBy => integer().nullable().references(Users, #id)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('Expense')
class Expenses extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get categoryId => integer().references(
    ExpenseCategories,
    #id,
    onDelete: KeyAction.restrict,
  )();
  TextColumn get description => text()();
  IntColumn get amountCents => integer().map(const MoneyConverter())();
  IntColumn get currencyId =>
      integer().references(Currencies, #id, onDelete: KeyAction.restrict)();
  IntColumn get accountId => integer().nullable().references(
    Accounts,
    #id,
    onDelete: KeyAction.restrict,
  )();
  DateTimeColumn get expenseDate =>
      dateTime().withDefault(currentDateAndTime)();
  TextColumn get receiptPath => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

/// Append-only business document for money introduced by, withdrawn by, or
/// lent by the owner. The posted journal entry is the accounting source of
/// truth; this row supplies the operational context and an immutable audit
/// trail for the dedicated Owner Finance screen.
@DataClassName('OwnerFinanceTransaction')
class OwnerFinanceTransactions extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get transactionNumber => text().unique()();
  TextColumn get transactionType => text()();
  IntColumn get amountCents => integer().map(const MoneyConverter())();
  IntColumn get currencyId =>
      integer().references(Currencies, #id, onDelete: KeyAction.restrict)();
  IntColumn get offsetAccountId =>
      integer().references(Accounts, #id, onDelete: KeyAction.restrict)();
  DateTimeColumn get transactionDate => dateTime()();
  TextColumn get description => text()();
  TextColumn get notes => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('posted'))();
  @ReferenceName('ownerFinanceJournalEntries')
  IntColumn get journalEntryId => integer().nullable().unique().references(
    JournalEntries,
    #id,
    onDelete: KeyAction.restrict,
  )();
  @ReferenceName('ownerFinanceReversalJournalEntries')
  IntColumn get reversalJournalEntryId => integer()
      .nullable()
      .unique()
      .references(JournalEntries, #id, onDelete: KeyAction.restrict)();
  @ReferenceName('createdOwnerFinanceTransactions')
  IntColumn get createdBy => integer().nullable().references(
    Users,
    #id,
    onDelete: KeyAction.setNull,
  )();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

/// Fixed-asset sub-ledger. Monetary balances are never maintained here: cost
/// comes from the immutable acquisition JE and accumulated depreciation comes
/// from [FixedAssetDepreciations]. This prevents a second mutable balance from
/// drifting away from the general ledger.
@DataClassName('FixedAsset')
class FixedAssets extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get assetNumber => text().unique()();
  TextColumn get name => text()();
  TextColumn get category => text()();
  TextColumn get description => text().nullable()();
  DateTimeColumn get acquisitionDate => dateTime()();
  DateTimeColumn get inServiceDate => dateTime()();
  IntColumn get costCents => integer().map(const MoneyConverter())();
  IntColumn get residualValueCents =>
      integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  IntColumn get usefulLifeMonths => integer()();
  TextColumn get depreciationMethod =>
      text().withDefault(const Constant('straight_line'))();
  @ReferenceName('fixedAssetsByAssetAccount')
  IntColumn get assetAccountId =>
      integer().references(Accounts, #id, onDelete: KeyAction.restrict)();
  @ReferenceName('fixedAssetsByAccumulatedDepreciationAccount')
  IntColumn get accumulatedDepreciationAccountId =>
      integer().references(Accounts, #id, onDelete: KeyAction.restrict)();
  @ReferenceName('fixedAssetsByDepreciationExpenseAccount')
  IntColumn get depreciationExpenseAccountId =>
      integer().references(Accounts, #id, onDelete: KeyAction.restrict)();
  @ReferenceName('fixedAssetsByFundingAccount')
  IntColumn get fundingAccountId =>
      integer().references(Accounts, #id, onDelete: KeyAction.restrict)();
  IntColumn get currencyId =>
      integer().references(Currencies, #id, onDelete: KeyAction.restrict)();
  TextColumn get status => text().withDefault(const Constant('active'))();
  @ReferenceName('fixedAssetAcquisitionJournalEntries')
  IntColumn get acquisitionJournalEntryId => integer()
      .nullable()
      .unique()
      .references(JournalEntries, #id, onDelete: KeyAction.restrict)();
  @ReferenceName('fixedAssetReversalJournalEntries')
  IntColumn get reversalJournalEntryId => integer()
      .nullable()
      .unique()
      .references(JournalEntries, #id, onDelete: KeyAction.restrict)();
  @ReferenceName('createdFixedAssets')
  IntColumn get createdBy => integer().nullable().references(
    Users,
    #id,
    onDelete: KeyAction.setNull,
  )();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

/// One immutable straight-line depreciation instalment for a fixed asset.
/// Reversals use a separate journal entry and status=voided.
@DataClassName('FixedAssetDepreciation')
class FixedAssetDepreciations extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get assetId =>
      integer().references(FixedAssets, #id, onDelete: KeyAction.restrict)();
  IntColumn get installmentNumber => integer()();
  DateTimeColumn get periodStart => dateTime()();
  DateTimeColumn get periodEnd => dateTime()();
  IntColumn get amountCents => integer().map(const MoneyConverter())();
  TextColumn get status => text().withDefault(const Constant('posted'))();
  TextColumn get notes => text().nullable()();
  @ReferenceName('fixedAssetDepreciationJournalEntries')
  IntColumn get journalEntryId => integer().nullable().unique().references(
    JournalEntries,
    #id,
    onDelete: KeyAction.restrict,
  )();
  @ReferenceName('fixedAssetDepreciationReversalJournalEntries')
  IntColumn get reversalJournalEntryId => integer()
      .nullable()
      .unique()
      .references(JournalEntries, #id, onDelete: KeyAction.restrict)();
  @ReferenceName('postedFixedAssetDepreciations')
  IntColumn get postedBy => integer().nullable().references(
    Users,
    #id,
    onDelete: KeyAction.setNull,
  )();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {assetId, installmentNumber},
  ];
}
