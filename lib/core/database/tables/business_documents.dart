import 'package:drift/drift.dart';

/// Immutable ownership and global identity for legacy document headers and
/// stock batches. Existing integer IDs and financial rows are not rewritten.
/// Lines inherit their header's location; batch movements inherit their batch.
@DataClassName('BusinessDocumentLocation')
class BusinessDocumentLocations extends Table {
  TextColumn get documentId => text().withLength(min: 36, max: 36)();
  TextColumn get sourceTable => text()();
  IntColumn get sourceId => integer()();
  TextColumn get organizationId => text()();
  TextColumn get branchId => text()();
  TextColumn get warehouseId => text()();
  TextColumn get originDatabaseId => text().withLength(min: 36, max: 36)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {documentId};

  @override
  List<Set<Column>> get uniqueKeys => [
    {sourceTable, sourceId},
  ];

  @override
  List<String> get customConstraints => [
    'FOREIGN KEY (warehouse_id, branch_id, organization_id) REFERENCES business_warehouses (id, branch_id, organization_id) ON DELETE RESTRICT',
    'CHECK (source_id > 0)',
    "CHECK (source_table IN ('sales', 'purchases', 'sale_returns', 'purchase_returns', 'sale_return_adjustments', 'purchase_return_adjustments', 'inventory_adjustments', 'product_batches', 'journal_entries'))",
  ];
}
