import 'package:drift/drift.dart';
import '../converters/money_converter.dart';
import 'settings.dart';

@DataClassName('Customer')
class Customers extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get email => text().nullable()();
  TextColumn get phone => text().nullable()();
  TextColumn get address => text().nullable()();
  IntColumn get balanceCents => integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  IntColumn get currencyId => integer().references(Currencies, #id, onDelete: KeyAction.restrict)();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('CustomerTransaction')
class CustomerTransactions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get customerId => integer().references(Customers, #id, onDelete: KeyAction.restrict)();
  TextColumn get transactionType => text()();
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
  IntColumn get currencyId => integer().references(Currencies, #id, onDelete: KeyAction.restrict)();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('SupplierTransaction')
class SupplierTransactions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get supplierId => integer().references(Suppliers, #id, onDelete: KeyAction.restrict)();
  TextColumn get transactionType => text()();
  IntColumn get amountCents => integer().map(const MoneyConverter())();
  IntColumn get currencyId => integer().references(Currencies, #id, onDelete: KeyAction.restrict)();
  TextColumn get description => text().nullable()();
  IntColumn get referenceId => integer().nullable()();
  TextColumn get referenceType => text().nullable()();
  DateTimeColumn get transactionDate => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
