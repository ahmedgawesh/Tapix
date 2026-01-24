import 'package:drift/drift.dart';
import '../converters/json_converter.dart';
import 'users.dart';

@DataClassName('AuditLog')
class AuditLogs extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get targetTable => text()();
  IntColumn get recordId => integer()();
  TextColumn get action => text()();
  TextColumn get changes => text().map(const JsonMapConverter())();
  IntColumn get userId => integer().nullable().references(Users, #id)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('VoidLog')
class VoidLogs extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get targetTable => text()();
  IntColumn get recordId => integer()();
  TextColumn get reason => text()();
  IntColumn get voidedBy => integer().nullable().references(Users, #id)();
  DateTimeColumn get voidedAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('Notification')
class Notifications extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get userId => integer().nullable().references(Users, #id)();
  TextColumn get title => text()();
  TextColumn get message => text()();
  TextColumn get type => text()();
  BoolColumn get isRead => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
