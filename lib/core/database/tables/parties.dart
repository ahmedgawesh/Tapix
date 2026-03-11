import 'package:drift/drift.dart';
import '../converters/money_converter.dart';
import 'settings.dart';
import 'loyalty.dart';

@DataClassName('Customer')
class Customers extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get email => text().nullable()();
  TextColumn get phone => text().nullable()();
  TextColumn get address => text().nullable()();
  IntColumn get balanceCents => integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  /// The initial balance when the customer was created (immutable after creation)
  IntColumn get openingBalanceCents => integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  IntColumn get currencyId => integer().references(Currencies, #id, onDelete: KeyAction.restrict)();
  TextColumn get segment => text().withDefault(const Constant('retail'))(); // retail, wholesale, premium
  BoolColumn get loyaltyEnabled => boolean().withDefault(const Constant(true))();
  IntColumn get loyaltyTierId => integer().nullable().references(LoyaltyTiers, #id, onDelete: KeyAction.setNull)();
  IntColumn get loyaltyPointsBalance => integer().withDefault(const Constant(0))();
  IntColumn get totalSpentCents => integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  IntColumn get totalTransactions => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastTransactionAt => dateTime().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('CustomerTransaction')
class CustomerTransactions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get customerId => integer().references(Customers, #id, onDelete: KeyAction.restrict)();
  TextColumn get transactionNumber => text().nullable()();
  TextColumn get transactionType => text()();
  /// For discount transactions: seasonal, volume, loyalty, promotional, early_payment, other
  TextColumn get discountType => text().nullable()();
  IntColumn get amountCents => integer().map(const MoneyConverter())();
  IntColumn get currencyId => integer().references(Currencies, #id, onDelete: KeyAction.restrict)();
  TextColumn get description => text().nullable()();
  IntColumn get referenceId => integer().nullable()();
  TextColumn get referenceType => text().nullable()();
  DateTimeColumn get transactionDate => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('Supplier')
class Suppliers extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get email => text().nullable()();
  TextColumn get phone => text().nullable()();
  TextColumn get address => text().nullable()();
  IntColumn get balanceCents => integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  /// The initial balance when the supplier was created (immutable after creation)
  IntColumn get openingBalanceCents => integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  IntColumn get currencyId => integer().references(Currencies, #id, onDelete: KeyAction.restrict)();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('SupplierTransaction')
class SupplierTransactions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get supplierId => integer().references(Suppliers, #id, onDelete: KeyAction.restrict)();
  TextColumn get transactionNumber => text().nullable()();
  TextColumn get transactionType => text()();
  /// For discount transactions: seasonal, volume, loyalty, promotional, early_payment, other
  TextColumn get discountType => text().nullable()();
  IntColumn get amountCents => integer().map(const MoneyConverter())();
  IntColumn get currencyId => integer().references(Currencies, #id, onDelete: KeyAction.restrict)();
  TextColumn get description => text().nullable()();
  IntColumn get referenceId => integer().nullable()();
  TextColumn get referenceType => text().nullable()();
  DateTimeColumn get transactionDate => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
