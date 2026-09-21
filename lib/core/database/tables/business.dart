import 'package:drift/drift.dart';

/// Additive location metadata. Legacy financial and stock tables remain the
/// authoritative writers until the multi-location posting engine is enabled.
@DataClassName('BusinessOrganization')
class BusinessOrganizations extends Table {
  TextColumn get id => text().withLength(min: 36, max: 36)();
  TextColumn get name => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('BusinessBranch')
class BusinessBranches extends Table {
  TextColumn get id => text().withLength(min: 36, max: 36)();
  TextColumn get organizationId => text().references(
    BusinessOrganizations,
    #id,
    onDelete: KeyAction.restrict,
  )();
  TextColumn get code => text().withLength(min: 1, max: 32)();
  TextColumn get name => text().withDefault(const Constant(''))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {organizationId, code},
    {id, organizationId},
  ];
}

@DataClassName('BusinessWarehouse')
class BusinessWarehouses extends Table {
  TextColumn get id => text().withLength(min: 36, max: 36)();
  TextColumn get organizationId => text().references(
    BusinessOrganizations,
    #id,
    onDelete: KeyAction.restrict,
  )();
  TextColumn get branchId => text()();
  TextColumn get code => text().withLength(min: 1, max: 32)();
  TextColumn get name => text().withDefault(const Constant(''))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {organizationId, code},
    {id, branchId, organizationId},
  ];

  @override
  List<String> get customConstraints => [
    'FOREIGN KEY (branch_id, organization_id) REFERENCES business_branches (id, organization_id) ON DELETE RESTRICT',
  ];
}

/// Exactly one default context per legacy database. This is a data identity,
/// not a hardware identity: backups must preserve it; cloned live writers must
/// be explicitly enrolled before future synchronization is allowed.
@DataClassName('BusinessContext')
class BusinessContexts extends Table {
  IntColumn get id => integer()();
  TextColumn get organizationId => text()();
  TextColumn get branchId => text()();
  TextColumn get warehouseId => text()();
  TextColumn get databaseId => text().withLength(min: 36, max: 36).unique()();
  IntColumn get foundationVersion => integer().withDefault(const Constant(1))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    'FOREIGN KEY (branch_id, organization_id) REFERENCES business_branches (id, organization_id) ON DELETE RESTRICT',
    'FOREIGN KEY (warehouse_id, branch_id, organization_id) REFERENCES business_warehouses (id, branch_id, organization_id) ON DELETE RESTRICT',
    'CHECK (id = 1)',
    'CHECK (foundation_version = 1)',
  ];
}
