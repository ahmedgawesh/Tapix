import 'package:drift/drift.dart';
import 'parties.dart';

/// Durable reservation after a supplier code has been used in a saved document.
/// Cancelling/deleting a document must not make an already-used code mutable.
/// This contains no quantities, costs or financial postings.
@DataClassName('SupplierProductCodeLock')
class SupplierProductCodeLocks extends Table {
  IntColumn get supplierId =>
      integer().references(Suppliers, #id, onDelete: KeyAction.restrict)();
  TextColumn get productCode => text()();
  DateTimeColumn get lockedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {supplierId};
}
