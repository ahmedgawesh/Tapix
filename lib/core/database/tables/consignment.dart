import 'package:drift/drift.dart';

import 'accounting.dart';
import 'business.dart';
import 'parties.dart';
import 'products.dart';
import 'settings.dart';
import 'supplier_product_identities.dart';
import 'transactions.dart';
import 'users.dart';

/// Versioned commercial terms. Active rows are immutable; revised terms use
/// the same agreementKey and the next revision number.
@DataClassName('ConsignmentAgreement')
class ConsignmentAgreements extends Table {
  TextColumn get id => text().withLength(min: 36, max: 36)();
  TextColumn get agreementKey => text().withLength(min: 36, max: 36)();
  IntColumn get revision => integer().withDefault(const Constant(1))();
  TextColumn get organizationId =>
      text().references(BusinessOrganizations, #id)();
  TextColumn get branchId => text()();
  TextColumn get databaseId =>
      text().references(BusinessContexts, #databaseId)();
  IntColumn get supplierId =>
      integer().references(Suppliers, #id, onDelete: KeyAction.restrict)();
  IntColumn get currencyId =>
      integer().references(Currencies, #id, onDelete: KeyAction.restrict)();
  TextColumn get agreementNumber => text().withLength(min: 1, max: 64)();
  TextColumn get status => text().withDefault(const Constant('draft'))();
  DateTimeColumn get effectiveFrom => dateTime()();
  DateTimeColumn get effectiveTo => dateTime().nullable()();
  TextColumn get settlementFrequency =>
      text().withDefault(const Constant('monthly'))();
  IntColumn get paymentTermsDays => integer().withDefault(const Constant(0))();
  IntColumn get settlementTaxRateBps => integer()
      .check(
        const CustomExpression<bool>(
          'settlement_tax_rate_bps BETWEEN 0 AND 10000',
        ),
      )
      .withDefault(const Constant(0))();
  BoolColumn get settlementTaxInclusive =>
      boolean().withDefault(const Constant(false))();
  TextColumn get notes => text().withDefault(const Constant(''))();
  @ReferenceName('consignmentAgreementCreator')
  IntColumn get createdBy => integer().references(Users, #id)();
  @ReferenceName('consignmentAgreementActivator')
  IntColumn get activatedBy => integer().nullable().references(Users, #id)();
  DateTimeColumn get activatedAt => dateTime().nullable()();
  @ReferenceName('consignmentAgreementEnder')
  IntColumn get endedBy => integer().nullable().references(Users, #id)();
  DateTimeColumn get endedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {agreementKey, revision},
    {branchId, agreementNumber, revision},
  ];

  @override
  List<String> get customConstraints => [
    'FOREIGN KEY (branch_id, organization_id) REFERENCES business_branches (id, organization_id) ON DELETE RESTRICT',
    "CHECK (status IN ('draft','active','superseded','closed'))",
    "CHECK (settlement_frequency IN ('immediate','daily','weekly','monthly','manual'))",
    'CHECK (revision >= 1 AND revision <= 9007199254740991)',
    'CHECK (payment_terms_days BETWEEN 0 AND 3650)',
    'CHECK (length(notes) <= 2000)',
    'CHECK (effective_to IS NULL OR effective_to >= effective_from)',
    "CHECK ((status='draft' AND activated_by IS NULL AND activated_at IS NULL) OR (status!='draft' AND activated_by IS NOT NULL AND activated_at IS NOT NULL))",
    "CHECK ((status IN ('draft','active') AND ended_by IS NULL AND ended_at IS NULL) OR (status IN ('superseded','closed') AND ended_by IS NOT NULL AND ended_at IS NOT NULL))",
  ];
}

@DataClassName('ConsignmentAgreementItem')
class ConsignmentAgreementItems extends Table {
  TextColumn get id => text().withLength(min: 36, max: 36)();
  TextColumn get agreementId => text().references(
    ConsignmentAgreements,
    #id,
    onDelete: KeyAction.restrict,
  )();
  IntColumn get productId =>
      integer().references(Products, #id, onDelete: KeyAction.restrict)();
  IntColumn get variantId => integer().nullable().references(
    ProductVariants,
    #id,
    onDelete: KeyAction.restrict,
  )();
  TextColumn get settlementBasis => text()();
  IntColumn get unitCostCents => integer().nullable()();
  IntColumn get supplierShareBps => integer().nullable()();
  BoolColumn get includeLineDiscount =>
      boolean().withDefault(const Constant(true))();
  BoolColumn get includeInvoiceDiscount =>
      boolean().withDefault(const Constant(true))();
  BoolColumn get includeSalesTax =>
      boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    "CHECK (settlement_basis IN ('fixed_unit_cost','net_sales_percentage'))",
    "CHECK ((settlement_basis='fixed_unit_cost' AND unit_cost_cents IS NOT NULL AND unit_cost_cents>=0 AND unit_cost_cents<=9007199254740991 AND supplier_share_bps IS NULL) OR (settlement_basis='net_sales_percentage' AND unit_cost_cents IS NULL AND supplier_share_bps BETWEEN 0 AND 10000))",
  ];
}

/// Physical delivery from a consignment supplier. Drafts have no stock or
/// financial effect. Posting is an immutable event implemented separately.
@DataClassName('ConsignmentReceipt')
class ConsignmentReceipts extends Table {
  TextColumn get id => text().withLength(min: 36, max: 36)();
  TextColumn get organizationId =>
      text().references(BusinessOrganizations, #id)();
  TextColumn get branchId => text()();
  TextColumn get databaseId =>
      text().references(BusinessContexts, #databaseId)();
  TextColumn get warehouseId => text()();
  IntColumn get supplierId =>
      integer().references(Suppliers, #id, onDelete: KeyAction.restrict)();
  TextColumn get agreementId => text().references(
    ConsignmentAgreements,
    #id,
    onDelete: KeyAction.restrict,
  )();
  IntColumn get currencyId =>
      integer().references(Currencies, #id, onDelete: KeyAction.restrict)();
  TextColumn get receiptNumber => text().withLength(min: 1, max: 64)();
  TextColumn get status => text().withDefault(const Constant('draft'))();
  TextColumn get requestKey => text().withLength(min: 36, max: 36).unique()();
  TextColumn get requestHash => text().withLength(min: 64, max: 64)();
  DateTimeColumn get receivedAt => dateTime()();
  TextColumn get notes => text().withDefault(const Constant(''))();
  IntColumn get lineCount => integer()();
  @ReferenceName('consignmentReceiptCreator')
  IntColumn get createdBy => integer().references(Users, #id)();
  @ReferenceName('consignmentReceiptPoster')
  IntColumn get postedBy => integer().nullable().references(Users, #id)();
  DateTimeColumn get postedAt => dateTime().nullable()();
  @ReferenceName('consignmentReceiptVoider')
  IntColumn get voidedBy => integer().nullable().references(Users, #id)();
  DateTimeColumn get voidedAt => dateTime().nullable()();
  TextColumn get voidReason => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {branchId, receiptNumber},
  ];

  @override
  List<String> get customConstraints => [
    'FOREIGN KEY (warehouse_id,branch_id,organization_id) REFERENCES business_warehouses (id,branch_id,organization_id) ON DELETE RESTRICT',
    "CHECK (status IN ('draft','posted','voided'))",
    'CHECK (line_count BETWEEN 1 AND 500)',
    'CHECK (length(notes)<=2000)',
    'CHECK (length(void_reason)<=500)',
    "CHECK ((status='draft' AND posted_by IS NULL AND posted_at IS NULL AND voided_by IS NULL AND voided_at IS NULL AND length(void_reason)=0) OR (status='posted' AND posted_by IS NOT NULL AND posted_at IS NOT NULL AND voided_by IS NULL AND voided_at IS NULL AND length(void_reason)=0) OR (status='voided' AND posted_by IS NOT NULL AND posted_at IS NOT NULL AND voided_by IS NOT NULL AND voided_at IS NOT NULL AND length(trim(void_reason))>0))",
  ];
}

@DataClassName('ConsignmentReceiptItem')
class ConsignmentReceiptItems extends Table {
  TextColumn get id => text().withLength(min: 36, max: 36)();
  TextColumn get receiptId => text().references(
    ConsignmentReceipts,
    #id,
    onDelete: KeyAction.restrict,
  )();
  TextColumn get agreementItemId => text().references(
    ConsignmentAgreementItems,
    #id,
    onDelete: KeyAction.restrict,
  )();
  IntColumn get productId =>
      integer().references(Products, #id, onDelete: KeyAction.restrict)();
  IntColumn get variantId => integer().references(
    ProductVariants,
    #id,
    onDelete: KeyAction.restrict,
  )();
  IntColumn get quantity => integer()();
  IntColumn get quantityScale => integer()();
  TextColumn get measurementType => text()();
  TextColumn get settlementBasis => text()();
  IntColumn get unitCostCents => integer().nullable()();
  IntColumn get supplierShareBps => integer().nullable()();
  BoolColumn get includeLineDiscount => boolean()();
  BoolColumn get includeInvoiceDiscount => boolean()();
  BoolColumn get includeSalesTax => boolean()();
  TextColumn get manufacturerLotNumber => text().nullable()();
  DateTimeColumn get expiryDate => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    'CHECK (quantity>0 AND quantity<=9007199254740991)',
    "CHECK ((measurement_type='piece' AND quantity_scale=1) OR (measurement_type IN ('weight','length','volume') AND quantity_scale=1000))",
    "CHECK ((settlement_basis='fixed_unit_cost' AND unit_cost_cents IS NOT NULL AND unit_cost_cents>=0 AND unit_cost_cents<=9007199254740991 AND supplier_share_bps IS NULL) OR (settlement_basis='net_sales_percentage' AND unit_cost_cents IS NULL AND supplier_share_bps BETWEEN 0 AND 10000))",
    'CHECK (manufacturer_lot_number IS NULL OR length(trim(manufacturer_lot_number)) BETWEEN 1 AND 100)',
  ];
}

/// Remaining supplier-owned quantity by immutable receipt line. The sum for a
/// warehouse/variant must equal business_warehouse_stocks.supplierOwnedQuantity.
@DataClassName('ConsignmentInventoryLayer')
class ConsignmentInventoryLayers extends Table {
  TextColumn get id => text().withLength(min: 36, max: 36)();
  TextColumn get receiptItemId => text().references(
    ConsignmentReceiptItems,
    #id,
    onDelete: KeyAction.restrict,
  )();

  /// Null on the original receipt layer. A transferred layer points to the
  /// immediately preceding custody layer so ownership provenance remains
  /// auditable across any number of warehouses.
  TextColumn get originLayerId => text().nullable().references(
    ConsignmentInventoryLayers,
    #id,
    onDelete: KeyAction.restrict,
  )();

  /// Filled only for custody created by an inter-warehouse receipt. The SQL
  /// guards validate the referenced transfer allocation without introducing a
  /// circular Drift table import.
  TextColumn get transferAllocationId => text().nullable()();
  TextColumn get warehouseId => text().references(
    BusinessWarehouses,
    #id,
    onDelete: KeyAction.restrict,
  )();
  IntColumn get supplierId =>
      integer().references(Suppliers, #id, onDelete: KeyAction.restrict)();
  TextColumn get agreementId => text().references(
    ConsignmentAgreements,
    #id,
    onDelete: KeyAction.restrict,
  )();
  IntColumn get productId =>
      integer().references(Products, #id, onDelete: KeyAction.restrict)();
  IntColumn get variantId => integer().references(
    ProductVariants,
    #id,
    onDelete: KeyAction.restrict,
  )();
  IntColumn get batchId => integer().nullable().references(
    ProductBatches,
    #id,
    onDelete: KeyAction.restrict,
  )();
  IntColumn get receivedQuantity => integer()();
  IntColumn get remainingQuantity => integer()();
  IntColumn get quantityScale => integer()();
  TextColumn get measurementType => text()();
  TextColumn get settlementBasis => text()();
  IntColumn get unitCostCents => integer().nullable()();
  IntColumn get supplierShareBps => integer().nullable()();
  BoolColumn get includeLineDiscount => boolean()();
  BoolColumn get includeInvoiceDiscount => boolean()();
  BoolColumn get includeSalesTax => boolean()();
  TextColumn get status => text().withDefault(const Constant('open'))();
  DateTimeColumn get receivedAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    'CHECK (received_quantity>0 AND received_quantity<=9007199254740991)',
    'CHECK (remaining_quantity>=0 AND remaining_quantity<=received_quantity)',
    "CHECK ((measurement_type='piece' AND quantity_scale=1) OR (measurement_type IN ('weight','length','volume') AND quantity_scale=1000))",
    "CHECK ((settlement_basis='fixed_unit_cost' AND unit_cost_cents IS NOT NULL AND unit_cost_cents>=0 AND unit_cost_cents<=9007199254740991 AND supplier_share_bps IS NULL) OR (settlement_basis='net_sales_percentage' AND unit_cost_cents IS NULL AND supplier_share_bps BETWEEN 0 AND 10000))",
    "CHECK (status IN ('open','exhausted','voided'))",
    "CHECK ((remaining_quantity=0 AND status IN ('exhausted','voided')) OR (remaining_quantity>0 AND status='open'))",
  ];
}

@DataClassName('ConsignmentReceiptEvent')
class ConsignmentReceiptEvents extends Table {
  TextColumn get id => text().withLength(min: 36, max: 36)();
  TextColumn get receiptId => text().references(
    ConsignmentReceipts,
    #id,
    onDelete: KeyAction.restrict,
  )();
  TextColumn get kind => text()();
  TextColumn get requestKey => text().withLength(min: 36, max: 36).unique()();
  TextColumn get requestHash => text().withLength(min: 64, max: 64)();
  @ReferenceName('consignmentReceiptEventActor')
  IntColumn get actorId => integer().references(Users, #id)();
  TextColumn get reason => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {receiptId, kind},
  ];

  @override
  List<String> get customConstraints => [
    "CHECK (kind IN ('posted','voided'))",
    'CHECK (length(reason)<=500)',
    "CHECK (kind!='voided' OR length(trim(reason))>0)",
  ];
}

/// A controlled, fully-audited reclassification of stock already owned by the
/// enterprise into supplier-owned consignment stock. The linked receipt creates
/// the consignment layer while the conversion removes the same quantity from
/// its proven enterprise source, so physical stock never changes.
@DataClassName('ConsignmentOwnershipConversion')
class ConsignmentOwnershipConversions extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get organizationId =>
      text().references(BusinessOrganizations, #id)();
  TextColumn get branchId => text()();
  TextColumn get databaseId =>
      text().references(BusinessContexts, #databaseId)();
  TextColumn get warehouseId => text()();
  IntColumn get supplierId =>
      integer().references(Suppliers, #id, onDelete: KeyAction.restrict)();
  TextColumn get agreementId => text().references(
    ConsignmentAgreements,
    #id,
    onDelete: KeyAction.restrict,
  )();
  IntColumn get currencyId =>
      integer().references(Currencies, #id, onDelete: KeyAction.restrict)();
  TextColumn get receiptId => text().unique().references(
    ConsignmentReceipts,
    #id,
    onDelete: KeyAction.restrict,
  )();
  TextColumn get conversionNumber => text().withLength(min: 1, max: 64)();
  TextColumn get evidenceReference => text().withLength(min: 1, max: 200)();
  DateTimeColumn get convertedAt => dateTime()();
  TextColumn get notes => text().withDefault(const Constant(''))();
  IntColumn get lineCount => integer()();
  IntColumn get inventoryValueCents => integer()();
  TextColumn get status => text().withDefault(const Constant('posting'))();
  TextColumn get requestKey => text().withLength(min: 36, max: 36).unique()();
  TextColumn get requestHash => text().withLength(min: 64, max: 64)();
  @ReferenceName('consignmentOwnershipConversionJournal')
  IntColumn get journalEntryId => integer().nullable().unique().references(
    JournalEntries,
    #id,
    onDelete: KeyAction.restrict,
  )();
  @ReferenceName('consignmentOwnershipConversionSupplierTransaction')
  IntColumn get supplierTransactionId => integer()
      .nullable()
      .unique()
      .references(SupplierTransactions, #id, onDelete: KeyAction.restrict)();
  @ReferenceName('consignmentOwnershipConversionCreator')
  IntColumn get createdBy => integer().references(Users, #id)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  TextColumn get voidRequestKey => text().nullable().unique()();
  TextColumn get voidRequestHash => text().nullable()();
  @ReferenceName('consignmentOwnershipConversionVoider')
  IntColumn get voidedBy => integer().nullable().references(Users, #id)();
  DateTimeColumn get voidedAt => dateTime().nullable()();
  TextColumn get voidReason => text().withDefault(const Constant(''))();
  @ReferenceName('consignmentOwnershipConversionReversalJournal')
  IntColumn get reversalJournalEntryId => integer()
      .nullable()
      .unique()
      .references(JournalEntries, #id, onDelete: KeyAction.restrict)();
  @ReferenceName('consignmentOwnershipConversionReversalSupplierTransaction')
  IntColumn get reversalSupplierTransactionId => integer()
      .nullable()
      .unique()
      .references(SupplierTransactions, #id, onDelete: KeyAction.restrict)();

  @override
  List<Set<Column>> get uniqueKeys => [
    {branchId, conversionNumber},
  ];

  @override
  List<String> get customConstraints => [
    'FOREIGN KEY (warehouse_id,branch_id,organization_id) REFERENCES business_warehouses (id,branch_id,organization_id) ON DELETE RESTRICT',
    'CHECK (line_count BETWEEN 1 AND 500)',
    'CHECK (inventory_value_cents>0 AND inventory_value_cents<=9007199254740991)',
    "CHECK (status IN ('posting','posted','voided'))",
    'CHECK (length(notes)<=2000 AND length(void_reason)<=500)',
    "CHECK ((status='posting' AND journal_entry_id IS NULL AND supplier_transaction_id IS NULL AND void_request_key IS NULL AND void_request_hash IS NULL AND voided_by IS NULL AND voided_at IS NULL AND length(void_reason)=0 AND reversal_journal_entry_id IS NULL AND reversal_supplier_transaction_id IS NULL) OR (status='posted' AND journal_entry_id IS NOT NULL AND supplier_transaction_id IS NOT NULL AND void_request_key IS NULL AND void_request_hash IS NULL AND voided_by IS NULL AND voided_at IS NULL AND length(void_reason)=0 AND reversal_journal_entry_id IS NULL AND reversal_supplier_transaction_id IS NULL) OR (status='voided' AND journal_entry_id IS NOT NULL AND supplier_transaction_id IS NOT NULL AND length(void_request_key)=36 AND length(void_request_hash)=64 AND voided_by IS NOT NULL AND voided_at IS NOT NULL AND length(trim(void_reason))>0 AND reversal_journal_entry_id IS NOT NULL AND reversal_supplier_transaction_id IS NOT NULL))",
  ];
}

@DataClassName('ConsignmentOwnershipConversionItem')
class ConsignmentOwnershipConversionItems extends Table {
  TextColumn get id => text().withLength(min: 36, max: 36)();
  IntColumn get conversionId => integer().references(
    ConsignmentOwnershipConversions,
    #id,
    onDelete: KeyAction.restrict,
  )();
  TextColumn get receiptItemId => text().unique().references(
    ConsignmentReceiptItems,
    #id,
    onDelete: KeyAction.restrict,
  )();
  IntColumn get productId =>
      integer().references(Products, #id, onDelete: KeyAction.restrict)();
  IntColumn get variantId => integer().references(
    ProductVariants,
    #id,
    onDelete: KeyAction.restrict,
  )();
  IntColumn get supplierIdentityId => integer().nullable().references(
    SupplierProductIdentities,
    #id,
    onDelete: KeyAction.restrict,
  )();
  IntColumn get sourceBatchId => integer().nullable().references(
    ProductBatches,
    #id,
    onDelete: KeyAction.restrict,
  )();
  IntColumn get quantity => integer()();
  IntColumn get quantityScale => integer()();
  TextColumn get measurementType => text()();
  IntColumn get inventoryUnitCostCents => integer()();
  IntColumn get inventoryAmountCents => integer()();
  TextColumn get originRemovalEventKey => text().nullable()();
  IntColumn get batchConsumptionId => integer().nullable().references(
    BatchConsumptions,
    #id,
    onDelete: KeyAction.restrict,
  )();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    'CHECK ((supplier_identity_id IS NOT NULL AND source_batch_id IS NULL AND origin_removal_event_key IS NOT NULL AND batch_consumption_id IS NULL) OR (supplier_identity_id IS NULL AND source_batch_id IS NOT NULL AND origin_removal_event_key IS NULL AND batch_consumption_id IS NOT NULL))',
    'CHECK (quantity>0 AND quantity<=9007199254740991)',
    "CHECK ((measurement_type='piece' AND quantity_scale=1) OR (measurement_type IN ('weight','length','volume') AND quantity_scale=1000))",
    'CHECK (inventory_unit_cost_cents>=0 AND inventory_unit_cost_cents<=9007199254740991)',
    'CHECK (inventory_amount_cents>0 AND inventory_amount_cents<=9007199254740991)',
  ];
}

/// Immutable allocation of a posted sale line to a supplier-owned receipt
/// layer. Monetary snapshots are apportioned with integer largest-remainder
/// arithmetic so reports can be replayed without current prices or settings.
@DataClassName('ConsignmentSaleAllocation')
class ConsignmentSaleAllocations extends Table {
  TextColumn get id => text().withLength(min: 36, max: 36)();
  IntColumn get saleItemId =>
      integer().references(SaleItems, #id, onDelete: KeyAction.restrict)();
  TextColumn get layerId => text().references(
    ConsignmentInventoryLayers,
    #id,
    onDelete: KeyAction.restrict,
  )();
  TextColumn get warehouseId => text().references(
    BusinessWarehouses,
    #id,
    onDelete: KeyAction.restrict,
  )();
  IntColumn get supplierId =>
      integer().references(Suppliers, #id, onDelete: KeyAction.restrict)();
  TextColumn get agreementId => text().references(
    ConsignmentAgreements,
    #id,
    onDelete: KeyAction.restrict,
  )();
  IntColumn get sequence => integer()();
  IntColumn get quantity => integer()();
  IntColumn get reversedQuantity => integer().withDefault(const Constant(0))();
  IntColumn get quantityScale => integer()();
  TextColumn get measurementType => text()();
  TextColumn get settlementBasis => text()();
  IntColumn get unitCostCents => integer().nullable()();
  IntColumn get supplierShareBps => integer().nullable()();
  BoolColumn get includeLineDiscount => boolean()();
  BoolColumn get includeInvoiceDiscount => boolean()();
  BoolColumn get includeSalesTax => boolean()();
  IntColumn get allocatedSubtotalCents => integer()();
  IntColumn get allocatedLineDiscountCents => integer()();
  IntColumn get allocatedInvoiceDiscountCents => integer()();
  IntColumn get allocatedTaxCents => integer()();
  IntColumn get settlementBaseCents => integer()();
  IntColumn get obligationCents => integer()();
  IntColumn get reversedObligationCents =>
      integer().withDefault(const Constant(0))();
  TextColumn get status => text().withDefault(const Constant('active'))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {saleItemId, layerId},
    {saleItemId, sequence},
  ];

  @override
  List<String> get customConstraints => [
    'CHECK (sequence>=1 AND sequence<=500)',
    'CHECK (quantity>0 AND quantity<=9007199254740991)',
    'CHECK (reversed_quantity>=0 AND reversed_quantity<=quantity)',
    "CHECK ((measurement_type='piece' AND quantity_scale=1) OR (measurement_type IN ('weight','length','volume') AND quantity_scale=1000))",
    "CHECK ((settlement_basis='fixed_unit_cost' AND unit_cost_cents IS NOT NULL AND unit_cost_cents>=0 AND supplier_share_bps IS NULL) OR (settlement_basis='net_sales_percentage' AND unit_cost_cents IS NULL AND supplier_share_bps BETWEEN 0 AND 10000))",
    'CHECK (allocated_subtotal_cents>=0 AND allocated_line_discount_cents>=0 AND allocated_invoice_discount_cents>=0 AND allocated_tax_cents>=0)',
    'CHECK (allocated_line_discount_cents+allocated_invoice_discount_cents<=allocated_subtotal_cents)',
    'CHECK (settlement_base_cents>=0 AND obligation_cents>=0)',
    'CHECK (reversed_obligation_cents>=0 AND reversed_obligation_cents<=obligation_cents)',
    "CHECK (status IN ('active','partially_reversed','fully_reversed'))",
    "CHECK ((reversed_quantity=0 AND reversed_obligation_cents=0 AND status='active') OR (reversed_quantity>0 AND reversed_quantity<quantity AND status='partially_reversed') OR (reversed_quantity=quantity AND reversed_obligation_cents=obligation_cents AND status='fully_reversed'))",
  ];
}

/// Append-only financial sub-ledger. Positive rows accrue supplier
/// consideration; negative rows reverse it. Every row receives one posted GL
/// journal before the surrounding document transaction can commit.
@DataClassName('ConsignmentObligationEvent')
class ConsignmentObligationEvents extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get allocationId => text().references(
    ConsignmentSaleAllocations,
    #id,
    onDelete: KeyAction.restrict,
  )();
  IntColumn get supplierId =>
      integer().references(Suppliers, #id, onDelete: KeyAction.restrict)();
  TextColumn get agreementId => text().references(
    ConsignmentAgreements,
    #id,
    onDelete: KeyAction.restrict,
  )();
  IntColumn get currencyId =>
      integer().references(Currencies, #id, onDelete: KeyAction.restrict)();
  TextColumn get kind => text()();
  IntColumn get signedQuantity => integer()();
  IntColumn get signedAmountCents => integer()();

  /// True when this event restores/removes sellable stock. Damaged or
  /// scrapped customer returns reverse the supplier obligation while staying
  /// outside sellable inventory.
  BoolColumn get restoresStock => boolean().withDefault(const Constant(true))();
  TextColumn get sourceTable => text()();
  IntColumn get sourceId => integer()();
  IntColumn get sourceItemId => integer()();
  TextColumn get requestKey => text().withLength(min: 1, max: 160).unique()();
  IntColumn get journalEntryId => integer().nullable().unique().references(
    JournalEntries,
    #id,
    onDelete: KeyAction.restrict,
  )();
  TextColumn get settlementStatus =>
      text().withDefault(const Constant('unassigned'))();
  DateTimeColumn get occurredAt => dateTime()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<Set<Column>> get uniqueKeys => [
    {allocationId, kind, sourceTable, sourceItemId},
  ];

  @override
  List<String> get customConstraints => [
    "CHECK (kind IN ('sale_accrual','linked_return_reversal','return_void_reaccrual','sale_void_reversal','adjustment_return_accrual','adjustment_return_reversal'))",
    'CHECK (signed_quantity!=0 AND signed_quantity BETWEEN -9007199254740991 AND 9007199254740991)',
    'CHECK (signed_amount_cents BETWEEN -9007199254740991 AND 9007199254740991)',
    "CHECK ((kind IN ('sale_accrual','return_void_reaccrual','adjustment_return_accrual') AND signed_quantity>0 AND signed_amount_cents>=0) OR (kind IN ('linked_return_reversal','sale_void_reversal','adjustment_return_reversal') AND signed_quantity<0 AND signed_amount_cents<=0))",
    "CHECK (source_table IN ('sales','sale_returns','sale_return_adjustments'))",
    "CHECK (settlement_status IN ('unassigned','assigned'))",
  ];
}

/// Financial sub-ledger for standalone sale returns explicitly attributed to a
/// consignment custody layer. It is separate from sale allocations because a
/// no-invoice return must never invent an original sale line.
@DataClassName('ConsignmentAdjustmentReturnEvent')
class ConsignmentAdjustmentReturnEvents extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get layerId => text().references(
    ConsignmentInventoryLayers,
    #id,
    onDelete: KeyAction.restrict,
  )();
  IntColumn get supplierId =>
      integer().references(Suppliers, #id, onDelete: KeyAction.restrict)();
  TextColumn get agreementId => text().references(
    ConsignmentAgreements,
    #id,
    onDelete: KeyAction.restrict,
  )();
  IntColumn get currencyId =>
      integer().references(Currencies, #id, onDelete: KeyAction.restrict)();
  TextColumn get kind => text()();
  IntColumn get signedQuantity => integer()();
  IntColumn get signedAmountCents => integer()();

  /// Mirrors the return-line disposition. False records supplier-owned
  /// damaged/scrapped custody without making it available for resale.
  BoolColumn get restoresStock => boolean().withDefault(const Constant(true))();
  IntColumn get returnId => integer().references(
    SaleReturnAdjustments,
    #id,
    onDelete: KeyAction.restrict,
  )();
  IntColumn get returnItemId => integer().references(
    SaleReturnAdjustmentItems,
    #id,
    onDelete: KeyAction.restrict,
  )();
  TextColumn get requestKey => text().withLength(min: 1, max: 160).unique()();
  IntColumn get journalEntryId => integer().nullable().unique().references(
    JournalEntries,
    #id,
    onDelete: KeyAction.restrict,
  )();
  TextColumn get settlementStatus =>
      text().withDefault(const Constant('unassigned'))();
  DateTimeColumn get occurredAt => dateTime()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<Set<Column>> get uniqueKeys => [
    {returnItemId, kind},
  ];

  @override
  List<String> get customConstraints => [
    "CHECK (kind IN ('adjustment_return_reversal','adjustment_return_void_reaccrual'))",
    'CHECK (signed_quantity!=0 AND signed_quantity BETWEEN -9007199254740991 AND 9007199254740991)',
    'CHECK (signed_amount_cents BETWEEN -9007199254740991 AND 9007199254740991)',
    "CHECK ((kind='adjustment_return_reversal' AND signed_quantity<0 AND signed_amount_cents<=0) OR (kind='adjustment_return_void_reaccrual' AND signed_quantity>0 AND signed_amount_cents>=0))",
    "CHECK (settlement_status IN ('unassigned','assigned'))",
  ];
}

/// Auditable removal of supplier-owned custody. A document is either a good
/// return to the supplier, a loss, or damage. Drafts have no stock or
/// accounting effect; posting is atomic and immutable.
@DataClassName('ConsignmentCustodyDocument')
class ConsignmentCustodyDocuments extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get organizationId =>
      text().references(BusinessOrganizations, #id)();
  TextColumn get branchId => text()();
  TextColumn get databaseId =>
      text().references(BusinessContexts, #databaseId)();
  TextColumn get warehouseId => text().references(
    BusinessWarehouses,
    #id,
    onDelete: KeyAction.restrict,
  )();
  IntColumn get supplierId =>
      integer().references(Suppliers, #id, onDelete: KeyAction.restrict)();
  TextColumn get agreementId => text().references(
    ConsignmentAgreements,
    #id,
    onDelete: KeyAction.restrict,
  )();
  IntColumn get currencyId =>
      integer().references(Currencies, #id, onDelete: KeyAction.restrict)();
  TextColumn get documentNumber => text().withLength(min: 1, max: 64)();
  TextColumn get documentType => text()();
  TextColumn get responsibility => text()();
  TextColumn get status => text().withDefault(const Constant('draft'))();
  DateTimeColumn get occurredAt => dateTime()();
  TextColumn get reason => text().withLength(min: 1, max: 500)();
  TextColumn get notes => text().withDefault(const Constant(''))();
  IntColumn get lineCount => integer()();
  TextColumn get requestKey => text().withLength(min: 36, max: 36).unique()();
  TextColumn get requestHash => text().withLength(min: 64, max: 64)();
  @ReferenceName('consignmentCustodyCreator')
  IntColumn get createdBy => integer().references(Users, #id)();
  @ReferenceName('consignmentCustodyPoster')
  IntColumn get postedBy => integer().nullable().references(Users, #id)();
  DateTimeColumn get postedAt => dateTime().nullable()();
  @ReferenceName('consignmentCustodyVoider')
  IntColumn get voidedBy => integer().nullable().references(Users, #id)();
  DateTimeColumn get voidedAt => dateTime().nullable()();
  TextColumn get voidReason => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<Set<Column>> get uniqueKeys => [
    {branchId, documentNumber},
  ];

  @override
  List<String> get customConstraints => [
    'FOREIGN KEY (branch_id,organization_id) REFERENCES business_branches (id,organization_id) ON DELETE RESTRICT',
    "CHECK (document_type IN ('supplier_return','loss','damage'))",
    "CHECK (responsibility IN ('supplier','company'))",
    "CHECK (document_type!='supplier_return' OR responsibility='supplier')",
    "CHECK (status IN ('draft','posted','voided'))",
    'CHECK (line_count BETWEEN 1 AND 500)',
    'CHECK (length(trim(reason)) BETWEEN 1 AND 500)',
    'CHECK (length(notes)<=2000 AND length(void_reason)<=500)',
  ];
}

@DataClassName('ConsignmentCustodyItem')
class ConsignmentCustodyItems extends Table {
  TextColumn get id => text().withLength(min: 36, max: 36)();
  IntColumn get documentId => integer().references(
    ConsignmentCustodyDocuments,
    #id,
    onDelete: KeyAction.restrict,
  )();
  TextColumn get layerId => text().references(
    ConsignmentInventoryLayers,
    #id,
    onDelete: KeyAction.restrict,
  )();
  IntColumn get productId =>
      integer().references(Products, #id, onDelete: KeyAction.restrict)();
  IntColumn get variantId => integer().references(
    ProductVariants,
    #id,
    onDelete: KeyAction.restrict,
  )();
  IntColumn get batchId => integer().nullable().references(
    ProductBatches,
    #id,
    onDelete: KeyAction.restrict,
  )();
  IntColumn get quantity => integer()();
  IntColumn get quantityScale => integer()();
  IntColumn get liabilityUnitCents => integer().nullable()();
  IntColumn get liabilityAmountCents =>
      integer().withDefault(const Constant(0))();
  IntColumn get batchConsumptionId => integer().nullable().references(
    BatchConsumptions,
    #id,
    onDelete: KeyAction.restrict,
  )();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {documentId, layerId},
  ];

  @override
  List<String> get customConstraints => [
    'CHECK (quantity>0 AND quantity<=9007199254740991)',
    'CHECK (quantity_scale IN (1,1000))',
    'CHECK (liability_unit_cents IS NULL OR liability_unit_cents BETWEEN 0 AND 9007199254740991)',
    'CHECK (liability_amount_cents BETWEEN 0 AND 9007199254740991)',
  ];
}

/// Append-only post/void audit and the settlement source for company-borne
/// custody losses. Zero-value events are operational only.
@DataClassName('ConsignmentCustodyEvent')
class ConsignmentCustodyEvents extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get documentId => integer().references(
    ConsignmentCustodyDocuments,
    #id,
    onDelete: KeyAction.restrict,
  )();
  TextColumn get kind => text()();
  IntColumn get supplierId =>
      integer().references(Suppliers, #id, onDelete: KeyAction.restrict)();
  TextColumn get agreementId => text().references(
    ConsignmentAgreements,
    #id,
    onDelete: KeyAction.restrict,
  )();
  IntColumn get currencyId =>
      integer().references(Currencies, #id, onDelete: KeyAction.restrict)();
  IntColumn get signedQuantity => integer()();
  IntColumn get signedAmountCents => integer()();
  TextColumn get requestKey => text().withLength(min: 36, max: 36).unique()();
  TextColumn get requestHash => text().withLength(min: 64, max: 64)();
  IntColumn get journalEntryId => integer().nullable().unique().references(
    JournalEntries,
    #id,
    onDelete: KeyAction.restrict,
  )();
  TextColumn get settlementStatus =>
      text().withDefault(const Constant('not_applicable'))();
  @ReferenceName('consignmentCustodyEventActor')
  IntColumn get actorId => integer().references(Users, #id)();
  TextColumn get reason => text().withDefault(const Constant(''))();
  DateTimeColumn get occurredAt => dateTime()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<Set<Column>> get uniqueKeys => [
    {documentId, kind},
  ];

  @override
  List<String> get customConstraints => [
    "CHECK (kind IN ('posted','voided'))",
    'CHECK (signed_quantity!=0 AND signed_quantity BETWEEN -9007199254740991 AND 9007199254740991)',
    'CHECK (signed_amount_cents BETWEEN -9007199254740991 AND 9007199254740991)',
    "CHECK (settlement_status IN ('not_applicable','unassigned','assigned'))",
    "CHECK ((signed_amount_cents=0 AND settlement_status='not_applicable' AND journal_entry_id IS NULL) OR (signed_amount_cents!=0 AND settlement_status IN ('unassigned','assigned') AND journal_entry_id IS NOT NULL))",
    "CHECK ((kind='posted' AND signed_quantity>0 AND signed_amount_cents>=0) OR (kind='voided' AND signed_quantity<0 AND signed_amount_cents<=0 AND length(trim(reason))>0))",
    'CHECK (length(reason)<=500)',
  ];
}

/// A reviewed period statement that transfers accrued consignment obligations
/// to the supplier AP sub-ledger. Draft rows reserve source events; posting
/// freezes tax and due-date snapshots for replay and audit.
@DataClassName('ConsignmentSettlementStatement')
class ConsignmentSettlementStatements extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get organizationId =>
      text().references(BusinessOrganizations, #id)();
  TextColumn get branchId => text()();
  TextColumn get databaseId =>
      text().references(BusinessContexts, #databaseId)();
  IntColumn get supplierId =>
      integer().references(Suppliers, #id, onDelete: KeyAction.restrict)();
  TextColumn get agreementId => text().references(
    ConsignmentAgreements,
    #id,
    onDelete: KeyAction.restrict,
  )();
  IntColumn get currencyId =>
      integer().references(Currencies, #id, onDelete: KeyAction.restrict)();
  TextColumn get statementNumber => text().withLength(min: 1, max: 64)();
  DateTimeColumn get periodStart => dateTime()();
  DateTimeColumn get periodEnd => dateTime()();
  IntColumn get taxRateBps => integer().withDefault(const Constant(0))();
  BoolColumn get taxInclusive => boolean().withDefault(const Constant(false))();
  IntColumn get obligationSubtotalCents => integer()();
  IntColumn get taxCents => integer().withDefault(const Constant(0))();
  IntColumn get totalCents => integer()();
  IntColumn get paidCents => integer().withDefault(const Constant(0))();
  IntColumn get lineCount => integer()();
  TextColumn get status => text().withDefault(const Constant('draft'))();
  DateTimeColumn get dueDate => dateTime()();
  TextColumn get requestKey => text().withLength(min: 36, max: 36).unique()();
  TextColumn get requestHash => text().withLength(min: 64, max: 64)();
  TextColumn get notes => text().withDefault(const Constant(''))();
  @ReferenceName('consignmentStatementPostingJournal')
  IntColumn get journalEntryId => integer().nullable().unique().references(
    JournalEntries,
    #id,
    onDelete: KeyAction.restrict,
  )();
  @ReferenceName('consignmentStatementPostingTransaction')
  IntColumn get supplierTransactionId => integer()
      .nullable()
      .unique()
      .references(SupplierTransactions, #id, onDelete: KeyAction.restrict)();
  @ReferenceName('consignmentStatementVoidJournal')
  IntColumn get voidJournalEntryId => integer().nullable().unique().references(
    JournalEntries,
    #id,
    onDelete: KeyAction.restrict,
  )();
  @ReferenceName('consignmentStatementVoidTransaction')
  IntColumn get voidSupplierTransactionId => integer()
      .nullable()
      .unique()
      .references(SupplierTransactions, #id, onDelete: KeyAction.restrict)();
  @ReferenceName('consignmentStatementCreator')
  IntColumn get createdBy => integer().references(Users, #id)();
  @ReferenceName('consignmentStatementReviewer')
  IntColumn get reviewedBy => integer().nullable().references(Users, #id)();
  DateTimeColumn get reviewedAt => dateTime().nullable()();
  @ReferenceName('consignmentStatementPoster')
  IntColumn get postedBy => integer().nullable().references(Users, #id)();
  DateTimeColumn get postedAt => dateTime().nullable()();
  @ReferenceName('consignmentStatementVoider')
  IntColumn get voidedBy => integer().nullable().references(Users, #id)();
  DateTimeColumn get voidedAt => dateTime().nullable()();
  TextColumn get voidReason => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<Set<Column>> get uniqueKeys => [
    {branchId, statementNumber},
  ];

  @override
  List<String> get customConstraints => [
    'FOREIGN KEY (branch_id,organization_id) REFERENCES business_branches (id,organization_id) ON DELETE RESTRICT',
    'CHECK (period_end>=period_start)',
    'CHECK (tax_rate_bps BETWEEN 0 AND 10000)',
    'CHECK (obligation_subtotal_cents BETWEEN -9007199254740991 AND 9007199254740991)',
    'CHECK (tax_cents BETWEEN -9007199254740991 AND 9007199254740991)',
    'CHECK (total_cents BETWEEN -9007199254740991 AND 9007199254740991)',
    'CHECK ((obligation_subtotal_cents<0 AND tax_cents<=0 AND total_cents<=0) OR (obligation_subtotal_cents=0 AND tax_cents=0 AND total_cents=0) OR (obligation_subtotal_cents>0 AND tax_cents>=0 AND total_cents>=0))',
    'CHECK (paid_cents>=0 AND (total_cents<=0 OR paid_cents<=total_cents))',
    'CHECK (line_count BETWEEN 1 AND 10000)',
    "CHECK (status IN ('draft','reviewed','posted','partially_paid','paid','voided'))",
    'CHECK (length(notes)<=2000 AND length(void_reason)<=500)',
  ];
}

@DataClassName('ConsignmentSettlementItem')
class ConsignmentSettlementItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get statementId => integer().references(
    ConsignmentSettlementStatements,
    #id,
    onDelete: KeyAction.restrict,
  )();
  TextColumn get sourceLedger => text()();
  IntColumn get eventId => integer()();
  IntColumn get signedQuantity => integer()();
  IntColumn get signedAmountCents => integer()();
  DateTimeColumn get occurredAt => dateTime()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<String> get customConstraints => [
    "CHECK (source_ledger IN ('sale_obligation','adjustment_return','custody_loss'))",
    'CHECK (signed_quantity!=0 AND signed_quantity BETWEEN -9007199254740991 AND 9007199254740991)',
    'CHECK (signed_amount_cents BETWEEN -9007199254740991 AND 9007199254740991)',
  ];
}

@DataClassName('ConsignmentSettlementPayment')
class ConsignmentSettlementPayments extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get statementId => integer().references(
    ConsignmentSettlementStatements,
    #id,
    onDelete: KeyAction.restrict,
  )();
  IntColumn get amountCents => integer()();
  TextColumn get paymentMethod => text()();
  TextColumn get reference => text().withDefault(const Constant(''))();
  TextColumn get status => text().withDefault(const Constant('posted'))();
  TextColumn get requestKey => text().withLength(min: 36, max: 36).unique()();
  @ReferenceName('consignmentPaymentTransaction')
  IntColumn get supplierTransactionId => integer().unique().references(
    SupplierTransactions,
    #id,
    onDelete: KeyAction.restrict,
  )();
  @ReferenceName('consignmentPaymentJournal')
  IntColumn get journalEntryId => integer().unique().references(
    JournalEntries,
    #id,
    onDelete: KeyAction.restrict,
  )();
  @ReferenceName('consignmentPaymentReversalTransaction')
  IntColumn get reversalSupplierTransactionId => integer()
      .nullable()
      .unique()
      .references(SupplierTransactions, #id, onDelete: KeyAction.restrict)();
  @ReferenceName('consignmentPaymentReversalJournal')
  IntColumn get reversalJournalEntryId => integer()
      .nullable()
      .unique()
      .references(JournalEntries, #id, onDelete: KeyAction.restrict)();
  DateTimeColumn get paidAt => dateTime()();
  @ReferenceName('consignmentPaymentCreator')
  IntColumn get createdBy => integer().references(Users, #id)();
  DateTimeColumn get reversedAt => dateTime().nullable()();
  @ReferenceName('consignmentPaymentReverser')
  IntColumn get reversedBy => integer().nullable().references(Users, #id)();
  TextColumn get reversalReason => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<String> get customConstraints => [
    'CHECK (amount_cents>0 AND amount_cents<=9007199254740991)',
    "CHECK (payment_method IN ('cash','card','bank_transfer'))",
    "CHECK (status IN ('posted','reversed'))",
    'CHECK (length(reference)<=200 AND length(reversal_reason)<=500)',
    "CHECK ((status='posted' AND reversal_supplier_transaction_id IS NULL AND reversal_journal_entry_id IS NULL AND reversed_at IS NULL AND reversed_by IS NULL AND length(reversal_reason)=0) OR (status='reversed' AND reversal_supplier_transaction_id IS NOT NULL AND reversal_journal_entry_id IS NOT NULL AND reversed_at IS NOT NULL AND reversed_by IS NOT NULL AND length(trim(reversal_reason))>0))",
  ];
}
