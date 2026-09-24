import 'package:drift/drift.dart';
import 'parties.dart';
import 'products.dart';

/// A permanent source-specific SKU, NOT a second product or a stock balance.
///
/// Persist only as part of an approved operation / explicit issuance. Once
/// issued, snapshots and ownership cannot change. Receipts, costs, lots and
/// quantities remain independent, in the existing inventory ledger.
@DataClassName('SupplierProductIdentity')
class SupplierProductIdentities extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get supplierId =>
      integer().references(Suppliers, #id, onDelete: KeyAction.restrict)();
  IntColumn get productId =>
      integer().references(Products, #id, onDelete: KeyAction.restrict)();

  /// Required even for a simple product: use its one operational variant.
  /// This avoids SQLite's nullable-UNIQUE loophole for variant-less lines.
  IntColumn get canonicalVariantId => integer().references(
    ProductVariants,
    #id,
    onDelete: KeyAction.restrict,
  )();
  TextColumn get supplierCodeSnapshot => text()();
  TextColumn get baseSkuSnapshot => text()();
  TextColumn get sourceSku => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<Set<Column>> get uniqueKeys => [
    {supplierId, canonicalVariantId},
  ];
}
