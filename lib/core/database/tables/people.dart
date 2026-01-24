import 'package:drift/drift.dart';
import '../converters/money_converter.dart';
import 'settings.dart';
import 'transactions.dart';

@DataClassName('Employee')
class Employees extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get email => text().nullable()();
  TextColumn get phone => text().nullable()();
  TextColumn get position => text().nullable()();
  IntColumn get salaryCents => integer().map(const MoneyConverter()).nullable()();
  IntColumn get currencyId => integer().references(Currencies, #id, onDelete: KeyAction.restrict)();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get hireDate => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('Commission')
class Commissions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get employeeId => integer().references(Employees, #id, onDelete: KeyAction.cascade)();
  IntColumn get saleId => integer().references(Sales, #id, onDelete: KeyAction.cascade)();
  IntColumn get commissionRateBps => integer().map(const BasisPointsConverter())();
  IntColumn get commissionAmountCents => integer().map(const MoneyConverter())();
  IntColumn get currencyId => integer().references(Currencies, #id, onDelete: KeyAction.restrict)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
