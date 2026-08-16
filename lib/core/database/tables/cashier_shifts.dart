import 'package:drift/drift.dart';

import '../converters/money_converter.dart';
import 'settings.dart';
import 'users.dart';

/// A real POS cashier session. This is deliberately separate from
/// `ShiftSchedules`, which is an HR roster and does not prove who operated
/// the till for a transaction.
@DataClassName('CashierShift')
class CashierShifts extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get shiftNumber => text().unique()();
  @ReferenceName('cashierShiftCashier')
  IntColumn get cashierUserId =>
      integer().references(Users, #id, onDelete: KeyAction.restrict)();
  IntColumn get currencyId =>
      integer().references(Currencies, #id, onDelete: KeyAction.restrict)();

  /// `open` | `closed`.
  TextColumn get status => text().withDefault(const Constant('open'))();
  IntColumn get openingCashCents =>
      integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  IntColumn get expectedClosingCashCents =>
      integer().nullable().map(const MoneyConverter())();
  IntColumn get countedClosingCashCents =>
      integer().nullable().map(const MoneyConverter())();
  IntColumn get cashVarianceCents =>
      integer().nullable().map(const MoneyConverter())();
  TextColumn get openingNotes => text().nullable()();
  TextColumn get closingNotes => text().nullable()();
  DateTimeColumn get openedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get closedAt => dateTime().nullable()();
  @ReferenceName('cashierShiftClosedBy')
  IntColumn get closedBy => integer().nullable().references(
    Users,
    #id,
    onDelete: KeyAction.setNull,
  )();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
