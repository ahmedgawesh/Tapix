import 'package:drift/drift.dart';

import 'accounting.dart';
import 'business.dart';
import 'consignment.dart';
import 'products.dart';
import 'settings.dart';
import 'users.dart';

/// Immutable transfer intent plus its derived lifecycle state.
@DataClassName('WarehouseTransfer')
class WarehouseTransfers extends Table {
  TextColumn get id => text().withLength(min: 36, max: 36)();
  TextColumn get organizationId =>
      text().references(BusinessOrganizations, #id)();
  TextColumn get branchId => text()();
  TextColumn get databaseId =>
      text().references(BusinessContexts, #databaseId)();
  TextColumn get sourceWarehouseId => text()();
  TextColumn get destinationWarehouseId => text()();
  IntColumn get currencyId => integer().references(Currencies, #id)();
  IntColumn get createdBy => integer().references(Users, #id)();
  TextColumn get requestKey => text().withLength(min: 36, max: 36).unique()();
  TextColumn get requestHash => text().withLength(min: 64, max: 64)();
  TextColumn get notes => text().withDefault(const Constant(''))();
  IntColumn get lineCount => integer()();
  TextColumn get status => text().withDefault(const Constant('draft'))();
  BoolColumn get sealed => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    'FOREIGN KEY (source_warehouse_id, branch_id, organization_id) REFERENCES business_warehouses (id, branch_id, organization_id) ON DELETE RESTRICT',
    'FOREIGN KEY (destination_warehouse_id, branch_id, organization_id) REFERENCES business_warehouses (id, branch_id, organization_id) ON DELETE RESTRICT',
    'CHECK (source_warehouse_id != destination_warehouse_id)',
    "CHECK (status IN ('draft','in_transit','partially_received','completed','cancelled'))",
    'CHECK (line_count BETWEEN 1 AND 500)',
    'CHECK (length(notes) <= 500)',
  ];
}

@DataClassName('WarehouseTransferLine')
class WarehouseTransferLines extends Table {
  TextColumn get id => text().withLength(min: 36, max: 36)();
  TextColumn get transferId => text().references(
    WarehouseTransfers,
    #id,
    onDelete: KeyAction.restrict,
  )();
  IntColumn get productId => integer().references(Products, #id)();
  IntColumn get variantId => integer().references(ProductVariants, #id)();
  IntColumn get quantity => integer()();
  IntColumn get quantityScale => integer()();
  TextColumn get measurementType => text()();

  /// Informational preview only; dispatch recaptures and freezes carrying value.
  IntColumn get previewValueCents => integer()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {transferId, variantId},
  ];

  @override
  List<String> get customConstraints => [
    'CHECK (quantity > 0 AND quantity <= 9007199254740991)',
    "CHECK ((measurement_type='piece' AND quantity_scale=1) OR (measurement_type IN ('weight','length','volume') AND quantity_scale=1000))",
    'CHECK (preview_value_cents >= 0)',
  ];
}

/// One immutable dispatch per transfer. The journal moves enterprise-owned
/// value from Inventory to Inventory in Transit; consignment has zero GL value.
@DataClassName('WarehouseTransferDispatch')
class WarehouseTransferDispatches extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get transferId => text().unique().references(
    WarehouseTransfers,
    #id,
    onDelete: KeyAction.restrict,
  )();
  TextColumn get requestKey => text().withLength(min: 36, max: 36).unique()();
  TextColumn get requestHash => text().withLength(min: 64, max: 64)();
  IntColumn get actorId => integer().references(Users, #id)();
  IntColumn get allocationCount => integer()();
  IntColumn get ownedValueCents => integer()();
  IntColumn get journalEntryId => integer().nullable().unique().references(
    JournalEntries,
    #id,
    onDelete: KeyAction.restrict,
  )();
  BoolColumn get sealed => boolean().withDefault(const Constant(false))();
  DateTimeColumn get dispatchedAt => dateTime()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<String> get customConstraints => [
    'CHECK (allocation_count BETWEEN 1 AND 5000)',
    'CHECK (owned_value_cents BETWEEN 0 AND 9007199254740991)',
    'CHECK (sealed=0 AND journal_entry_id IS NULL OR sealed=1 AND owned_value_cents=0 AND journal_entry_id IS NULL OR sealed=1 AND owned_value_cents>0 AND journal_entry_id IS NOT NULL)',
  ];
}

/// Frozen ownership/source slice created at dispatch. Receipt documents consume
/// these rows without mutating them, which makes partial receipts replay-safe.
@DataClassName('WarehouseTransferAllocation')
class WarehouseTransferAllocations extends Table {
  TextColumn get id => text().withLength(min: 36, max: 36)();
  IntColumn get dispatchId => integer().references(
    WarehouseTransferDispatches,
    #id,
    onDelete: KeyAction.restrict,
  )();
  TextColumn get lineId => text().references(
    WarehouseTransferLines,
    #id,
    onDelete: KeyAction.restrict,
  )();
  IntColumn get sequence => integer()();
  TextColumn get ownerType => text()();
  IntColumn get quantity => integer()();
  IntColumn get quantityScale => integer()();
  TextColumn get measurementType => text()();
  IntColumn get unitCostCents => integer()();
  IntColumn get valueCents => integer()();
  IntColumn get sourceBatchId => integer().nullable().references(
    ProductBatches,
    #id,
    onDelete: KeyAction.restrict,
  )();
  TextColumn get sourceConsignmentLayerId => text().nullable().references(
    ConsignmentInventoryLayers,
    #id,
    onDelete: KeyAction.restrict,
  )();
  IntColumn get supplierId => integer().nullable()();
  TextColumn get agreementId => text().nullable()();
  TextColumn get manufacturerLotNumber => text().nullable()();
  DateTimeColumn get expiryDate => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {dispatchId, sequence},
  ];

  @override
  List<String> get customConstraints => [
    "CHECK (owner_type IN ('owned','consignment'))",
    'CHECK (sequence BETWEEN 1 AND 5000)',
    'CHECK (quantity>0 AND quantity<=9007199254740991)',
    "CHECK ((measurement_type='piece' AND quantity_scale=1) OR (measurement_type IN ('weight','length','volume') AND quantity_scale=1000))",
    'CHECK (unit_cost_cents>=0 AND value_cents>=0)',
    "CHECK ((owner_type='owned' AND source_consignment_layer_id IS NULL AND supplier_id IS NULL AND agreement_id IS NULL) OR (owner_type='consignment' AND source_consignment_layer_id IS NOT NULL AND supplier_id IS NOT NULL AND agreement_id IS NOT NULL AND value_cents=0))",
    'CHECK (manufacturer_lot_number IS NULL OR length(trim(manufacturer_lot_number)) BETWEEN 1 AND 100)',
  ];
}

/// Immutable posted receipt. Several rows may receive one dispatch partially.
@DataClassName('WarehouseTransferReceipt')
class WarehouseTransferReceipts extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get transferId => text().references(
    WarehouseTransfers,
    #id,
    onDelete: KeyAction.restrict,
  )();
  TextColumn get requestKey => text().withLength(min: 36, max: 36).unique()();
  TextColumn get requestHash => text().withLength(min: 64, max: 64)();
  IntColumn get actorId => integer().references(Users, #id)();
  IntColumn get itemCount => integer()();
  IntColumn get acceptedOwnedValueCents => integer()();
  IntColumn get varianceOwnedValueCents => integer()();
  IntColumn get destinationInventoryDeltaCents => integer()();
  IntColumn get journalEntryId => integer().nullable().unique().references(
    JournalEntries,
    #id,
    onDelete: KeyAction.restrict,
  )();
  BoolColumn get sealed => boolean().withDefault(const Constant(false))();
  TextColumn get notes => text().withDefault(const Constant(''))();
  DateTimeColumn get receivedAt => dateTime()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<String> get customConstraints => [
    'CHECK (item_count BETWEEN 1 AND 5000)',
    'CHECK (accepted_owned_value_cents>=0 AND variance_owned_value_cents>=0 AND destination_inventory_delta_cents>=0)',
    'CHECK (length(notes)<=500)',
    'CHECK (sealed=0 AND journal_entry_id IS NULL OR sealed=1 AND accepted_owned_value_cents=0 AND variance_owned_value_cents=0 AND destination_inventory_delta_cents=0 AND journal_entry_id IS NULL OR sealed=1 AND accepted_owned_value_cents+variance_owned_value_cents>0 AND journal_entry_id IS NOT NULL)',
  ];
}

/// Disposition of one dispatched allocation: accepted stock, damaged in
/// transit, or missing. Their sum consumes part or all of the allocation.
@DataClassName('WarehouseTransferReceiptItem')
class WarehouseTransferReceiptItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get receiptId => integer().references(
    WarehouseTransferReceipts,
    #id,
    onDelete: KeyAction.restrict,
  )();
  TextColumn get allocationId => text().references(
    WarehouseTransferAllocations,
    #id,
    onDelete: KeyAction.restrict,
  )();
  IntColumn get acceptedQuantity => integer().withDefault(const Constant(0))();
  IntColumn get damagedQuantity => integer().withDefault(const Constant(0))();
  IntColumn get lostQuantity => integer().withDefault(const Constant(0))();
  IntColumn get acceptedValueCents =>
      integer().withDefault(const Constant(0))();
  IntColumn get varianceValueCents =>
      integer().withDefault(const Constant(0))();
  IntColumn get destinationBatchId => integer().nullable().references(
    ProductBatches,
    #id,
    onDelete: KeyAction.restrict,
  )();
  TextColumn get destinationConsignmentLayerId => text().nullable().references(
    ConsignmentInventoryLayers,
    #id,
    onDelete: KeyAction.restrict,
  )();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<Set<Column>> get uniqueKeys => [
    {receiptId, allocationId},
  ];

  @override
  List<String> get customConstraints => [
    'CHECK (accepted_quantity>=0 AND damaged_quantity>=0 AND lost_quantity>=0)',
    'CHECK (accepted_quantity+damaged_quantity+lost_quantity>0)',
    'CHECK (accepted_value_cents>=0 AND variance_value_cents>=0)',
  ];
}

/// Immutable closure of all quantities that are still in transit. A recall
/// restores them to the source; quantities already received remain untouched.
@DataClassName('WarehouseTransferRecall')
class WarehouseTransferRecalls extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get transferId => text().unique().references(
    WarehouseTransfers,
    #id,
    onDelete: KeyAction.restrict,
  )();
  TextColumn get requestKey => text().withLength(min: 36, max: 36).unique()();
  TextColumn get requestHash => text().withLength(min: 64, max: 64)();
  IntColumn get actorId => integer().references(Users, #id)();
  IntColumn get itemCount => integer()();
  IntColumn get ownedValueCents => integer()();
  IntColumn get journalEntryId => integer().nullable().unique().references(
    JournalEntries,
    #id,
    onDelete: KeyAction.restrict,
  )();
  BoolColumn get sealed => boolean().withDefault(const Constant(false))();
  TextColumn get reason => text()();
  DateTimeColumn get recalledAt => dateTime()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<String> get customConstraints => [
    'CHECK (item_count BETWEEN 1 AND 5000)',
    'CHECK (owned_value_cents BETWEEN 0 AND 9007199254740991)',
    'CHECK (length(trim(reason)) BETWEEN 1 AND 500)',
    'CHECK (sealed=0 AND journal_entry_id IS NULL OR sealed=1 AND owned_value_cents=0 AND journal_entry_id IS NULL OR sealed=1 AND owned_value_cents>0 AND journal_entry_id IS NOT NULL)',
  ];
}

@DataClassName('WarehouseTransferRecallItem')
class WarehouseTransferRecallItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get recallId => integer().references(
    WarehouseTransferRecalls,
    #id,
    onDelete: KeyAction.restrict,
  )();
  TextColumn get allocationId => text().references(
    WarehouseTransferAllocations,
    #id,
    onDelete: KeyAction.restrict,
  )();
  IntColumn get quantity => integer()();
  IntColumn get valueCents => integer()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<Set<Column>> get uniqueKeys => [
    {recallId, allocationId},
    {allocationId},
  ];

  @override
  List<String> get customConstraints => [
    'CHECK (quantity>0 AND quantity<=9007199254740991)',
    'CHECK (value_cents>=0 AND value_cents<=9007199254740991)',
  ];
}

@DataClassName('WarehouseTransferEvent')
class WarehouseTransferEvents extends Table {
  TextColumn get id => text().withLength(min: 36, max: 36)();
  TextColumn get transferId => text().references(
    WarehouseTransfers,
    #id,
    onDelete: KeyAction.restrict,
  )();
  TextColumn get kind => text()();
  TextColumn get requestKey => text().withLength(min: 36, max: 36).unique()();
  TextColumn get requestHash => text().withLength(min: 64, max: 64)();
  IntColumn get actorId => integer().references(Users, #id)();
  TextColumn get reason => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {transferId, kind},
  ];

  @override
  List<String> get customConstraints => [
    "CHECK (kind IN ('created','cancelled','dispatched','completed'))",
    'CHECK (length(reason)<=500)',
    "CHECK (kind != 'cancelled' OR length(trim(reason))>0)",
  ];
}
