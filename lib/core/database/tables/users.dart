import 'package:drift/drift.dart';
import '../converters/timestamp_converter.dart';

@DataClassName('User')
class Users extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get username => text().unique()();
  TextColumn get passwordHash => text()();
  TextColumn get role => text()(); // owner/manager/cashier/salesperson
  IntColumn get employeeId => integer()
      .nullable()(); // FK to employees (circular reference, handled in app layer)
  IntColumn get isActive =>
      integer().withDefault(const Constant(1))(); // 1=active, 0=inactive
  TextColumn get securityQuestion => text().nullable()();
  TextColumn get securityAnswerHash => text().nullable()();
  IntColumn get createdAt => integer().map(const TimestampConverter())();
  IntColumn get updatedAt => integer().map(const TimestampConverter())();
  IntColumn get lastLoginAt =>
      integer().map(const TimestampConverter()).nullable()();
}
