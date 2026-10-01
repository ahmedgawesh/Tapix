import 'dart:convert';
import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:uuid/uuid.dart';

import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/database/daos/adjustment_return_dao.dart';
import 'package:tapix/core/database/daos/accounting_dao.dart';
import 'package:tapix/core/database/daos/inventory_adjustment_dao.dart';
import 'package:tapix/core/database/daos/pharmacy_dao.dart';
import 'package:tapix/core/promotions/promotion_engine.dart';
import 'package:tapix/core/promotions/promotion_repository.dart';
import 'package:tapix/core/services/audit_log_service.dart';
import 'package:tapix/core/services/business/branch_consignment_policy_store.dart';
import 'package:tapix/core/services/business/branch_currency_policy_store.dart';
import 'package:tapix/core/services/business/local_branch_scope.dart';
import 'package:tapix/core/services/business/warehouse_operation_scope.dart';
import 'package:tapix/core/services/business/warehouse_transfer_preflight.dart';
import 'package:tapix/core/services/inventory/inventory_adjustment_service.dart';
import 'package:tapix/core/services/journal_entry_service.dart';
import 'package:tapix/core/services/sync/offline_sync_event_store.dart';
import 'package:tapix/core/services/sync/sync_inbound_projection_service.dart';
import 'package:tapix/core/services/sync/sync_entity_identity_store.dart';
import 'package:tapix/features/accounting/data/datasources/journal_local_datasource.dart';
import 'package:tapix/features/accounting/data/repositories/accounting_repository.dart';
import 'package:tapix/features/accounting/data/repositories/journal_repository_impl.dart';
import 'package:tapix/features/auth/data/services/password_service.dart';
import 'package:tapix/features/auth/data/services/session_service.dart';
import 'package:tapix/features/business/data/warehouse_transfer_dispatch_service.dart';
import 'package:tapix/features/business/data/warehouse_transfer_receipt_service.dart';
import 'package:tapix/features/business/data/warehouse_transfer_repository.dart';
import 'package:tapix/features/consignment/data/consignment_agreement_service.dart';
import 'package:tapix/features/consignment/data/consignment_entitlement.dart';
import 'package:tapix/features/consignment/data/consignment_module_service.dart';
import 'package:tapix/features/consignment/data/consignment_receipt_service.dart';

/// Repeatable acceptance dataset for manual Android/Linux validation.
///
/// The generator always creates a new database and never reads customer data.
/// It deliberately uses production DAOs/services for posted accounting,
/// consignment and warehouse-transfer flows. Run with:
/// `flutter test tool/generate_comprehensive_acceptance_database_test.dart`.
class _FixedSession extends SessionService {
  _FixedSession(this.userId);

  final int userId;

  @override
  Future<int?> getCurrentUserId() async => userId;
}

class _ProductSeed {
  const _ProductSeed(this.productId, this.variantId);
  final int productId;
  final int variantId;
}

Future<void> main(List<String> arguments) async {
  final output = File(
    arguments.isEmpty
        ? 'backups/generated/acceptance_${DateTime.now().toUtc().millisecondsSinceEpoch}.db'
        : arguments.first,
  ).absolute;
  await output.parent.create(recursive: true);
  for (final path in [
    output.path,
    '${output.path}-wal',
    '${output.path}-shm',
  ]) {
    final file = File(path);
    if (await file.exists()) {
      throw StateError('Refusing to overwrite existing acceptance data: $path');
    }
  }

  final db = AppDatabase.connect(
    DatabaseConnection(NativeDatabase(output, logStatements: false)),
  );
  try {
    await _generate(db);
    await db.customStatement('PRAGMA wal_checkpoint(TRUNCATE)');
    final integrity = await db.customSelect('PRAGMA integrity_check').get();
    final foreignKeys = await db.customSelect('PRAGMA foreign_key_check').get();
    if (integrity.length != 1 || integrity.single.data.values.single != 'ok') {
      throw StateError('Generated database failed integrity_check: $integrity');
    }
    if (foreignKeys.isNotEmpty) {
      throw StateError(
        'Generated database has foreign-key errors: $foreignKeys',
      );
    }
    final unbalanced = await db.customSelect('''
      SELECT je.id,
             SUM(jel.debit_cents) AS debit,
             SUM(jel.credit_cents) AS credit
      FROM journal_entries je
      JOIN journal_entry_lines jel ON jel.journal_entry_id=je.id
      WHERE je.status='posted'
      GROUP BY je.id
      HAVING debit<>credit
    ''').get();
    if (unbalanced.isNotEmpty) {
      throw StateError(
        'Generated database has unbalanced journals: $unbalanced',
      );
    }
    final reconciliation = await JournalRepositoryImpl(
      JournalLocalDatasourceImpl(AccountingDao(db)),
      AccountingRepository(db),
    ).reconcileBalances();
    if (!reconciliation.isHealthy) {
      throw StateError(
        'Generated database failed accounting reconciliation: '
        '${reconciliation.issues}',
      );
    }
    final counts = await db.customSelect('''
      SELECT
        (SELECT COUNT(*) FROM business_branches) AS branches,
        (SELECT COUNT(*) FROM business_warehouses) AS warehouses,
        (SELECT COUNT(*) FROM products) AS products,
        (SELECT COUNT(*) FROM purchases) AS purchases,
        (SELECT COUNT(*) FROM sales) AS sales,
        (SELECT COUNT(*) FROM sale_returns) AS linked_returns,
        (SELECT COUNT(*) FROM sale_return_adjustments) AS settlement_returns,
        (SELECT COUNT(*) FROM warehouse_transfers) AS transfers,
        (SELECT COUNT(*) FROM consignment_receipts) AS consignment_receipts,
        (SELECT COUNT(*) FROM promotions) AS promotions,
        (SELECT COUNT(*) FROM journal_entries WHERE status='posted') AS journals
    ''').getSingle();
    stdout.writeln(jsonEncode({'database': output.path, ...counts.data}));
  } finally {
    await db.close();
  }
}

Future<void> _generate(AppDatabase db) async {
  await db.customSelect('SELECT 1').get();
  final currency = await (db.select(
    db.currencies,
  )..where((row) => row.code.equals('USD'))).getSingle();
  final scope = await WarehouseOperationScope.resolve(db);
  final now = DateTime.utc(2026, 9, 29, 18);
  final ownerId = await db
      .into(db.users)
      .insert(
        UsersCompanion.insert(
          username: 'acceptance_owner',
          passwordHash: PasswordService().hashPassword('TapixTest#2026'),
          role: 'owner',
          createdAt: now,
          updatedAt: now,
        ),
      );
  await db
      .into(db.users)
      .insert(
        UsersCompanion.insert(
          username: 'acceptance_cashier',
          passwordHash: PasswordService().hashPassword('Cashier#2026'),
          role: 'cashier',
          createdAt: now,
          updatedAt: now,
        ),
      );
  final session = _FixedSession(ownerId);
  final accounting = AccountingRepository(db);
  final journal = JournalEntryService(accounting);
  final adjustments = InventoryAdjustmentService(
    db: db,
    dao: InventoryAdjustmentDao(db),
    journal: journal,
  );

  Future<void> recordOpening(
    _ProductSeed product,
    int quantity, {
    DateTime? expiryDate,
    String? manufacturerLotNumber,
  }) async {
    await adjustments.adjust(
      productId: product.productId,
      variantId: product.variantId,
      type: InventoryAdjustmentType.openingBalance,
      quantityDelta: quantity,
      reason: 'رصيد افتتاحي موثق لبيانات القبول',
      currencyId: currency.id,
      userId: ownerId,
      scope: scope,
      expiryDate: expiryDate,
      manufacturerLotNumber: manufacturerLotNumber,
    );
  }

  await (db.update(
    db.businessOrganizations,
  )..where((row) => row.id.equals(scope.organizationId))).write(
    const BusinessOrganizationsCompanion(name: Value('شركة قبول Tapix')),
  );
  await (db.update(
    db.businessBranches,
  )..where((row) => row.id.equals(scope.branchId))).write(
    const BusinessBranchesCompanion(
      code: Value('MAIN'),
      name: Value('الفرع الرئيسي'),
    ),
  );
  await (db.update(
    db.businessWarehouses,
  )..where((row) => row.id.equals(scope.warehouseId))).write(
    const BusinessWarehousesCompanion(
      code: Value('MAIN-WH'),
      name: Value('المخزن الرئيسي'),
    ),
  );

  const mainSecondaryWarehouse = '20000000-0000-4000-8000-000000000000';
  await db
      .into(db.businessWarehouses)
      .insert(
        BusinessWarehousesCompanion.insert(
          id: mainSecondaryWarehouse,
          organizationId: scope.organizationId,
          branchId: scope.branchId,
          code: 'MAIN-SECONDARY',
          name: const Value('مخزن رئيسي إضافي'),
        ),
      );
  const cairoBranch = '10000000-0000-4000-8000-000000000001';
  const cairoWarehouse = '20000000-0000-4000-8000-000000000001';
  const alexBranch = '10000000-0000-4000-8000-000000000002';
  const alexWarehouse = '20000000-0000-4000-8000-000000000002';
  const depotBranch = '10000000-0000-4000-8000-000000000003';
  const depotWarehouse = '20000000-0000-4000-8000-000000000003';
  await _location(
    db,
    scope.organizationId,
    cairoBranch,
    cairoWarehouse,
    branchCode: 'CAIRO',
    branchName: 'فرع القاهرة للملابس والتجميل',
    warehouseCode: 'CAIRO-WH',
    warehouseName: 'مخزن فرع القاهرة',
  );
  await _location(
    db,
    scope.organizationId,
    alexBranch,
    alexWarehouse,
    branchCode: 'ALEX',
    branchName: 'فرع الإسكندرية المماثل',
    warehouseCode: 'ALEX-WH',
    warehouseName: 'مخزن فرع الإسكندرية',
  );
  await _location(
    db,
    scope.organizationId,
    depotBranch,
    depotWarehouse,
    branchCode: 'DEPOT',
    branchName: 'وحدة مخزن التوزيع',
    warehouseCode: 'DEPOT-WH',
    warehouseName: 'مخزن التوزيع',
  );

  await BranchCurrencyPolicyStore(db).bind('USD');
  // This database is installed on the acceptance coordinator. Remote branch
  // servers receive their own database during enrollment and must never reuse
  // this file. Seeding the role also makes replacing the coordinator database
  // deterministic without asking the owner to assign the same device again.
  for (final setting in const {
    'lan.mode': 'master',
    'lan.port': '45820',
  }.entries) {
    await db.customStatement(
      '''INSERT INTO app_settings(key,value,description,updated_at)
         VALUES(?,?,?,CURRENT_TIMESTAMP)''',
      [setting.key, setting.value, 'Acceptance coordinator network setting'],
    );
  }
  await db.customStatement(
    '''INSERT INTO app_settings(key,value,description,updated_at)
       VALUES(?,?,?,CURRENT_TIMESTAMP)''',
    [
      'company_profile',
      jsonEncode({
        'name': 'شركة قبول Tapix',
        'phone': '',
        'email': '',
        'address': '',
      }),
      'Acceptance company profile',
    ],
  );
  await db.customStatement(
    '''INSERT INTO app_settings(key,value,description,updated_at)
       VALUES(?,?,?,CURRENT_TIMESTAMP)''',
    [
      'lan.branch_catalogue.policy.v1.$alexBranch',
      jsonEncode({
        'version': 1,
        'mode': 'all_company_products',
        'categoryIds': <int>[],
        'productIds': <int>[],
        'excludedProductIds': <int>[],
      }),
      'Branch catalogue policy',
    ],
  );

  final groceries = await _category(db, 'مواد غذائية');
  final pharmacy = await _category(db, 'صيدلية');
  final fashion = await _category(db, 'ملابس ومتغيرات');
  final measured = await _category(db, 'وزن وطول وحجم');
  final cosmetics = await _category(db, 'مستحضرات تجميل');

  final regularSupplier = await _supplier(
    db,
    currency.id,
    'شركة الأمل للتوريدات',
    productCode: 'AML',
  );
  final pharmaSupplier = await _supplier(
    db,
    currency.id,
    'المورد الطبي المتحد',
    productCode: 'MED',
  );
  final consignmentSupplier = await _supplier(
    db,
    currency.id,
    'مورد الأمانة العالمية',
    productCode: 'CON',
  );
  final customer = await db
      .into(db.customers)
      .insert(
        CustomersCompanion.insert(
          name: 'عميل اختبار آجل وولاء',
          currencyId: currency.id,
          balanceCents: Value(Decimal.zero),
        ),
      );

  final rice = await _product(
    db,
    currency.id,
    scope.warehouseId,
    name: 'أرز فاخر 1 كجم',
    sku: 'GROC-RICE-1KG',
    barcode: '6290000000011',
    categoryId: groceries,
    supplierId: regularSupplier,
    cost: 4200,
    price: 6000,
    quantity: 40,
    taxable: true,
  );
  final juice = await _product(
    db,
    currency.id,
    scope.warehouseId,
    name: 'عصير برتقال',
    sku: 'GROC-JUICE',
    barcode: '6290000000028',
    categoryId: groceries,
    supplierId: regularSupplier,
    cost: 1200,
    price: 2000,
    quantity: 60,
    taxable: true,
  );
  final fabric = await _product(
    db,
    currency.id,
    scope.warehouseId,
    name: 'قماش قطني بالمتر',
    sku: 'LEN-COTTON',
    categoryId: measured,
    supplierId: regularSupplier,
    cost: 5000,
    price: 8500,
    quantity: 25000,
    measurementType: 'length',
  );
  final fruit = await _product(
    db,
    currency.id,
    scope.warehouseId,
    name: 'تفاح بالكيلو',
    sku: 'WGT-APPLE',
    categoryId: measured,
    supplierId: regularSupplier,
    cost: 4500,
    price: 7000,
    quantity: 35000,
    measurementType: 'weight',
  );
  final oil = await _product(
    db,
    currency.id,
    scope.warehouseId,
    name: 'زيت سائل باللتر',
    sku: 'VOL-OIL',
    categoryId: measured,
    supplierId: regularSupplier,
    cost: 6500,
    price: 9000,
    quantity: 18000,
    measurementType: 'volume',
  );
  final shirt = await _variableProduct(
    db,
    currency.id,
    scope.warehouseId,
    categoryId: fashion,
    supplierId: regularSupplier,
  );
  final medicine = await _product(
    db,
    currency.id,
    scope.warehouseId,
    name: 'باراسيتامول 500 مجم',
    sku: 'PH-PARA500',
    barcode: '6220000000105',
    categoryId: pharmacy,
    supplierId: pharmaSupplier,
    cost: 3000,
    price: 4500,
    quantity: 24,
    taxable: false,
    tracking: 'batch_expiry',
  );
  final cream = await _product(
    db,
    currency.id,
    scope.warehouseId,
    name: 'كريم عناية أمانة',
    sku: 'COS-CONS-01',
    categoryId: cosmetics,
    supplierId: consignmentSupplier,
    cost: 8000,
    price: 14000,
    quantity: 0,
  );

  await recordOpening(rice, 40);
  await recordOpening(juice, 60);
  await recordOpening(fabric, 25000);
  await recordOpening(fruit, 35000);
  await recordOpening(oil, 18000);
  await recordOpening(shirt, 12);
  await recordOpening(
    medicine,
    24,
    expiryDate: DateTime.utc(2028, 9, 30),
    manufacturerLotNumber: 'LOT-PARA-A29',
  );

  await db.customStatement(
    '''INSERT INTO app_settings(key,value,description,updated_at)
       VALUES(?,?,?,CURRENT_TIMESTAMP)''',
    [
      'lan.branch_catalogue.policy.v1.$cairoBranch',
      jsonEncode({
        'version': 1,
        'mode': 'managed_assortment',
        'categoryIds': [fashion, cosmetics],
        'productIds': <int>[],
        'excludedProductIds': <int>[],
      }),
      'Branch catalogue policy',
    ],
  );
  await db.customStatement(
    '''INSERT INTO app_settings(key,value,description,updated_at)
       VALUES(?,?,?,CURRENT_TIMESTAMP)''',
    [
      'lan.branch_catalogue.policy.v1.$depotBranch',
      jsonEncode({
        'version': 1,
        'mode': 'managed_assortment',
        'categoryIds': [groceries, pharmacy, measured],
        'productIds': <int>[],
        'excludedProductIds': <int>[],
      }),
      'Branch catalogue policy',
    ],
  );

  final ingredient = await PharmacyDao(db).saveActiveIngredient(
    canonicalName: 'Paracetamol',
    nameAr: 'باراسيتامول',
    nameFr: 'Paracétamol',
  );
  await PharmacyDao(db).saveMedicineProfile(
    MedicineProfileDraft(
      productId: medicine.productId,
      dosageForm: 'tablet',
      administrationRoute: 'oral',
      substitutionEligible: true,
      ingredients: [
        MedicineIngredientDraft(
          ingredientId: ingredient.id,
          value: '500',
          unit: 'mg',
        ),
      ],
    ),
  );
  final batch = await (db.select(
    db.productBatches,
  )..where((row) => row.productId.equals(medicine.productId))).getSingle();
  await (db.update(
    db.productBatches,
  )..where((row) => row.id.equals(batch.id))).write(
    ProductBatchesCompanion(
      batchNumber: const Value('BATCH-PARA-202609-A'),
      receivedDate: Value(DateTime.utc(2026, 9, 1)),
    ),
  );

  final promotion = PromotionRepository(db, AuditLogService(db));
  final promotionId = await promotion.create(
    PromotionDraft(
      code: 'RICE-2-SAVE10',
      name: 'خصم 10% عند شراء قطعتين أرز',
      type: PromotionType.quantity,
      rewardType: PromotionRewardType.percentageOff,
      productIds: [rice.productId],
      minimumQuantity: 2,
      percentBps: 1000,
    ),
  );
  await promotion.setActive(promotionId, true);

  final purchaseId = await _postedPurchase(
    db,
    journal,
    currencyId: currency.id,
    supplierId: regularSupplier,
    product: juice,
    quantity: 10,
    unitCost: 1200,
    number: 'PI-ACCEPT-0001',
    ownerId: ownerId,
  );
  final sale = await _postedSale(
    db,
    journal,
    currencyId: currency.id,
    customerId: customer,
    product: rice,
    quantity: 2,
    unitPrice: 6000,
    tax: 1680,
    number: 'SI-ACCEPT-0001',
    ownerId: ownerId,
    paymentMethod: 'credit',
  );

  final linkedReturn = await db.saleDao.createSaleReturn(
    SaleReturnsCompanion.insert(
      saleId: sale.saleId,
      returnNumber: 'SR-ACCEPT-0001',
      subtotalCents: Value(Decimal.fromInt(6000)),
      taxCents: Value(Decimal.fromInt(840)),
      totalCents: Decimal.fromInt(6840),
      currencyId: currency.id,
      refundMethod: const Value('credit'),
      status: const Value('draft'),
    ),
    [
      SaleReturnItemsCompanion.insert(
        returnId: 0,
        saleItemId: sale.itemId,
        quantity: 1,
        subtotalCents: Value(Decimal.fromInt(6000)),
        taxCents: Value(Decimal.fromInt(840)),
        refundCents: Decimal.fromInt(6840),
      ),
    ],
  );
  await db.saleDao.postSaleReturn(linkedReturn);
  await journal.recordSaleReturnJournalEntry(
    returnId: linkedReturn,
    totalCents: 6840,
    taxCents: 840,
    currencyId: currency.id,
    refundMethod: 'credit',
    partyId: customer,
    userId: ownerId,
  );
  await journal.recordSaleReturnCOGSReversalJournalEntry(
    returnId: linkedReturn,
    costCents: await db.saleDao.computeSaleReturnCostCents(linkedReturn),
    currencyId: currency.id,
    userId: ownerId,
  );

  final adjDao = AdjustmentReturnDao(db);
  final adjustmentId = await adjDao.createSaleAdjReturn(
    SaleReturnAdjustmentsCompanion.insert(
      returnNumber: 'SAR-ACCEPT-0001',
      customerId: Value(customer),
      currencyId: currency.id,
      totalCents: Decimal.fromInt(2000),
      refundMethod: const Value('credit'),
      notes: const Value('مصدر غير موثق مختار عمدًا لاختبار مسار المراجعة'),
    ),
    [
      SaleReturnAdjustmentItemsCompanion.insert(
        returnId: 0,
        productId: juice.productId,
        variantId: Value(juice.variantId),
        quantity: 1,
        unitPriceCents: Decimal.fromInt(2000),
        unitCostCents: Value(Decimal.fromInt(1200)),
        totalCents: Decimal.fromInt(2000),
        sourceResolution: const Value('unverified'),
        sourceResolutionReason: const Value('اختبار قرار مصدر غير موثق'),
        sourceResolvedBy: Value(ownerId),
        sourceResolvedAt: Value(now),
      ),
    ],
  );
  await adjDao.postSaleAdjReturn(
    adjustmentId,
    journalEntryService: journal,
    allowOverHistory: true,
  );

  final purchaseItem = await (db.select(
    db.purchaseItems,
  )..where((row) => row.purchaseId.equals(purchaseId))).getSingle();
  final purchaseReturnId = await db.purchaseDao.createPurchaseReturn(
    PurchaseReturnsCompanion.insert(
      purchaseId: purchaseId,
      returnNumber: 'PR-ACCEPT-0001',
      subtotalCents: Value(Decimal.fromInt(2400)),
      taxCents: Value(Decimal.zero),
      totalCents: Decimal.fromInt(2400),
      currencyId: currency.id,
      refundMethod: const Value('credit'),
      status: const Value('draft'),
    ),
    [
      PurchaseReturnItemsCompanion.insert(
        returnId: 0,
        purchaseItemId: purchaseItem.id,
        quantity: 2,
        subtotalCents: Value(Decimal.fromInt(2400)),
        refundCents: Decimal.fromInt(2400),
      ),
    ],
  );
  await db.purchaseDao.postPurchaseReturn(purchaseReturnId);
  await journal.recordPurchaseReturnJournalEntry(
    returnId: purchaseReturnId,
    totalCents: 2400,
    inventoryCostCents: await db.purchaseDao
        .computePurchaseReturnInventoryCostCents(purchaseReturnId),
    currencyId: currency.id,
    refundMethod: 'credit',
    userId: ownerId,
  );

  final voidPurchaseId = await _postedPurchase(
    db,
    journal,
    currencyId: currency.id,
    supplierId: regularSupplier,
    product: juice,
    quantity: 3,
    unitCost: 1200,
    number: 'PI-ACCEPT-VOID',
    ownerId: ownerId,
  );
  await journal.voidJournalEntriesForSource(
    sourceTable: 'purchases',
    sourceId: voidPurchaseId,
    reason: 'سيناريو قبول إلغاء فاتورة شراء',
    userId: ownerId,
  );
  await db.purchaseDao.voidPurchase(
    voidPurchaseId,
    journalEntryService: journal,
  );

  await _postedSale(
    db,
    journal,
    currencyId: currency.id,
    customerId: customer,
    product: fabric,
    quantity: 1500,
    unitPrice: 8500,
    tax: 0,
    quantityScale: 1000,
    measurementType: 'length',
    number: 'SI-ACCEPT-LENGTH',
    ownerId: ownerId,
    paymentMethod: 'cash',
  );
  await _postedSale(
    db,
    journal,
    currencyId: currency.id,
    customerId: customer,
    product: oil,
    quantity: 2000,
    unitPrice: 9000,
    tax: 0,
    quantityScale: 1000,
    measurementType: 'volume',
    number: 'SI-ACCEPT-VOLUME',
    ownerId: ownerId,
    paymentMethod: 'cash',
  );

  final voided = await _postedSale(
    db,
    journal,
    currencyId: currency.id,
    customerId: customer,
    product: fruit,
    quantity: 1000,
    unitPrice: 7000,
    tax: 0,
    quantityScale: 1000,
    measurementType: 'weight',
    number: 'SI-ACCEPT-VOID',
    ownerId: ownerId,
    paymentMethod: 'cash',
  );
  await journal.voidJournalEntriesForSource(
    sourceTable: 'sales',
    sourceId: voided.saleId,
    reason: 'سيناريو قبول إلغاء فاتورة',
    userId: ownerId,
  );
  await db.saleDao.voidSale(voided.saleId, journalEntryService: journal);

  await _seedTransfer(db, rice, scope, mainSecondaryWarehouse, ownerId);
  await _seedConsignment(
    db,
    session,
    currency.id,
    consignmentSupplier,
    cream,
    ownerId,
  );
  await _seedCentralMonitorEvents(
    db,
    organizationId: scope.organizationId,
    cairoBranchId: cairoBranch,
    cairoWarehouseId: cairoWarehouse,
    alexBranchId: alexBranch,
    alexWarehouseId: alexWarehouse,
    supplierId: regularSupplier,
    customerId: customer,
    medicine: medicine,
    shirt: shirt,
    rice: rice,
  );

  // Remote branches intentionally have no stock rows in this database.
  // Each enrolled branch owns its local warehouse ledger and receives only
  // catalogue identities and business events through synchronization.
  await db.customStatement(
    '''
    INSERT INTO app_settings(key,value,description,updated_at)
    VALUES('acceptance_dataset_manifest_v1',?,?,CURRENT_TIMESTAMP)
  ''',
    [
      jsonEncode({
        'generatedAt': now.toIso8601String(),
        'schema': db.schemaVersion,
        'scenarios': [
          'heterogeneous_managed_branch',
          'homogeneous_all_products_branch',
          'warehouse_only_site',
          'pharmacy_batch_expiry',
          'promotion',
          'variants',
          'piece_weight_length_volume',
          'purchase',
          'credit_sale',
          'linked_return',
          'linked_purchase_return',
          'settlement_return_unverified_source',
          'voided_sale',
          'voided_purchase',
          'measured_sales_weight_length_volume',
          'completed_warehouse_transfer',
          'consignment_agreement_and_receipt',
        ],
        'purchaseId': purchaseId,
      }),
      'Generated acceptance dataset manifest',
    ],
  );
}

Future<void> _seedCentralMonitorEvents(
  AppDatabase db, {
  required String organizationId,
  required String cairoBranchId,
  required String cairoWarehouseId,
  required String alexBranchId,
  required String alexWarehouseId,
  required int supplierId,
  required int customerId,
  required _ProductSeed medicine,
  required _ProductSeed shirt,
  required _ProductSeed rice,
}) async {
  final identities = SyncEntityIdentityStore(db);
  final supplierGlobalId = (await identities.getOrCreateLocal(
    entityType: 'supplier',
    localId: supplierId,
  )).globalId;
  final customerGlobalId = (await identities.getOrCreateLocal(
    entityType: 'customer',
    localId: customerId,
  )).globalId;
  Future<({String product, String variant})> productIdentity(
    _ProductSeed seed,
  ) async => (
    product: (await identities.getOrCreateLocal(
      entityType: 'product',
      localId: seed.productId,
    )).globalId,
    variant: (await identities.getOrCreateLocal(
      entityType: 'product_variant',
      localId: seed.variantId,
    )).globalId,
  );
  final medicineIdentity = await productIdentity(medicine);
  final shirtIdentity = await productIdentity(shirt);
  final riceIdentity = await productIdentity(rice);
  const cairoDatabaseId = '30000000-0000-4000-8000-000000000001';
  const alexDatabaseId = '30000000-0000-4000-8000-000000000002';
  final store = OfflineSyncEventStore(db);
  final projection = SyncInboundProjectionService(db, store);
  await store.enrollSource(
    sourceDatabaseId: cairoDatabaseId,
    organizationId: organizationId,
    branchId: cairoBranchId,
  );
  await store.enrollSource(
    sourceDatabaseId: alexDatabaseId,
    organizationId: organizationId,
    branchId: alexBranchId,
  );

  Future<void> apply({
    required String eventId,
    required String sourceDatabaseId,
    required String branchId,
    required int sequence,
    required String eventType,
    required String aggregateType,
    required String aggregateId,
    required Map<String, Object?> payload,
    required DateTime occurredAt,
  }) async {
    final draft = SyncEventEnvelope(
      eventId: eventId,
      sourceDatabaseId: sourceDatabaseId,
      organizationId: organizationId,
      branchId: branchId,
      sequence: sequence,
      eventType: eventType,
      aggregateType: aggregateType,
      aggregateId: aggregateId,
      contractVersion: 1,
      payload: payload,
      occurredAt: occurredAt,
      eventHash: '',
    );
    await projection.apply(
      SyncEventEnvelope(
        eventId: draft.eventId,
        sourceDatabaseId: draft.sourceDatabaseId,
        organizationId: draft.organizationId,
        branchId: draft.branchId,
        sequence: draft.sequence,
        eventType: draft.eventType,
        aggregateType: draft.aggregateType,
        aggregateId: draft.aggregateId,
        contractVersion: draft.contractVersion,
        payload: draft.payload,
        occurredAt: draft.occurredAt,
        eventHash: OfflineSyncTransaction.eventHashFor(draft),
      ),
    );
  }

  const cairoPurchaseDocument = '40000000-0000-4000-8000-000000000001';
  await apply(
    eventId: '50000000-0000-4000-8000-000000000001',
    sourceDatabaseId: cairoDatabaseId,
    branchId: cairoBranchId,
    sequence: 1,
    eventType: 'purchase.posted.v1',
    aggregateType: 'purchase',
    aggregateId: cairoPurchaseDocument,
    occurredAt: DateTime.utc(2026, 9, 29, 19),
    payload: {
      'contract': 'purchase.posted',
      'contractVersion': 1,
      'documentId': cairoPurchaseDocument,
      'organizationId': organizationId,
      'branchId': cairoBranchId,
      'warehouseId': cairoWarehouseId,
      'purchaseNumber': 'PI-CAIRO-ACCEPT-0001',
      'purchaseDate': '2026-09-29T19:00:00.000Z',
      'supplierGlobalId': supplierGlobalId,
      'currencyCode': 'USD',
      'paymentMethod': 'credit',
      'subtotalMinor': 24500,
      'discountMinor': 0,
      'taxMinor': 0,
      'paidMinor': 0,
      'totalMinor': 24500,
      'itemCount': 3,
      'items': [
        {
          'productGlobalId': medicineIdentity.product,
          'variantGlobalId': medicineIdentity.variant,
          'productName': 'باراسيتامول 500 مجم',
          'productSku': 'PH-PARA500',
          'variantName': 'الافتراضي',
          'variantSku': 'PH-PARA500',
          'quantityScaled': 2,
          'quantityScale': 1,
          'measurementType': 'piece',
          'unitCostMinor': 3000,
          'subtotalMinor': 6000,
          'discountMinor': 0,
          'taxMinor': 0,
          'totalMinor': 6000,
          'batches': [
            {
              'batchNumber': 'CAIRO-PARA-2609',
              'quantityScaled': 2,
              'expiryDate': '2028-09-30T00:00:00.000Z',
            },
          ],
        },
        {
          'productGlobalId': shirtIdentity.product,
          'variantGlobalId': shirtIdentity.variant,
          'productName': 'قميص بمتغيرات',
          'productSku': 'FASH-SHIRT',
          'variantName': 'أزرق / M',
          'variantSku': 'FASH-SHIRT-BLUE-M',
          'quantityScaled': 1,
          'quantityScale': 1,
          'measurementType': 'piece',
          'unitCostMinor': 9500,
          'subtotalMinor': 9500,
          'discountMinor': 0,
          'taxMinor': 0,
          'totalMinor': 9500,
        },
        {
          'productGlobalId': riceIdentity.product,
          'variantGlobalId': riceIdentity.variant,
          'productName': 'أرز فاخر 1 كجم',
          'productSku': 'GROC-RICE-1KG',
          'variantName': 'الافتراضي',
          'variantSku': 'GROC-RICE-1KG',
          'quantityScaled': 3000,
          'quantityScale': 1000,
          'measurementType': 'weight',
          'unitCostMinor': 3000,
          'subtotalMinor': 9000,
          'discountMinor': 0,
          'taxMinor': 0,
          'totalMinor': 9000,
        },
      ],
    },
  );
  const cairoSaleDocument = '40000000-0000-4000-8000-000000000002';
  await apply(
    eventId: '50000000-0000-4000-8000-000000000002',
    sourceDatabaseId: cairoDatabaseId,
    branchId: cairoBranchId,
    sequence: 2,
    eventType: 'sale.posted.v1',
    aggregateType: 'sale',
    aggregateId: cairoSaleDocument,
    occurredAt: DateTime.utc(2026, 9, 29, 19, 10),
    payload: {
      'contract': 'sale.posted',
      'contractVersion': 1,
      'documentId': cairoSaleDocument,
      'organizationId': organizationId,
      'branchId': cairoBranchId,
      'warehouseId': cairoWarehouseId,
      'invoiceNumber': 'SI-CAIRO-ACCEPT-0001',
      'saleDate': '2026-09-29T19:10:00.000Z',
      'customerGlobalId': customerGlobalId,
      'currencyCode': 'USD',
      'paymentMethod': 'cash',
      'subtotalMinor': 31000,
      'discountMinor': 0,
      'taxMinor': 0,
      'paidMinor': 31000,
      'totalMinor': 31000,
      'itemCount': 2,
      'items': [
        {
          'productGlobalId': shirtIdentity.product,
          'variantGlobalId': shirtIdentity.variant,
          'productName': 'قميص بمتغيرات',
          'productSku': 'FASH-SHIRT',
          'variantName': 'أزرق / M',
          'variantSku': 'FASH-SHIRT-BLUE-M',
          'quantityScaled': 1,
          'quantityScale': 1,
          'measurementType': 'piece',
          'unitPriceMinor': 17000,
          'subtotalMinor': 17000,
          'discountMinor': 0,
          'taxMinor': 0,
          'totalMinor': 17000,
        },
        {
          'productGlobalId': medicineIdentity.product,
          'variantGlobalId': medicineIdentity.variant,
          'productName': 'باراسيتامول 500 مجم',
          'productSku': 'PH-PARA500',
          'variantName': 'الافتراضي',
          'variantSku': 'PH-PARA500',
          'quantityScaled': 2,
          'quantityScale': 1,
          'measurementType': 'piece',
          'unitPriceMinor': 7000,
          'subtotalMinor': 14000,
          'discountMinor': 0,
          'taxMinor': 0,
          'totalMinor': 14000,
          'batches': [
            {
              'batchNumber': 'CAIRO-PARA-2609',
              'quantityScaled': 2,
              'expiryDate': '2028-09-30T00:00:00.000Z',
            },
          ],
        },
      ],
    },
  );
  const alexSaleDocument = '40000000-0000-4000-8000-000000000003';
  await apply(
    eventId: '50000000-0000-4000-8000-000000000003',
    sourceDatabaseId: alexDatabaseId,
    branchId: alexBranchId,
    sequence: 1,
    eventType: 'sale.posted.v1',
    aggregateType: 'sale',
    aggregateId: alexSaleDocument,
    occurredAt: DateTime.utc(2026, 9, 29, 19, 20),
    payload: {
      'contract': 'sale.posted',
      'contractVersion': 1,
      'documentId': alexSaleDocument,
      'organizationId': organizationId,
      'branchId': alexBranchId,
      'warehouseId': alexWarehouseId,
      'invoiceNumber': 'SI-ALEX-ACCEPT-0001',
      'saleDate': '2026-09-29T19:20:00.000Z',
      'customerGlobalId': customerGlobalId,
      'currencyCode': 'USD',
      'paymentMethod': 'cash',
      'subtotalMinor': 18000,
      'discountMinor': 0,
      'taxMinor': 0,
      'paidMinor': 18000,
      'totalMinor': 18000,
      'itemCount': 1,
      'items': [
        {
          'productGlobalId': riceIdentity.product,
          'variantGlobalId': riceIdentity.variant,
          'productName': 'أرز فاخر 1 كجم',
          'productSku': 'GROC-RICE-1KG',
          'variantName': 'الافتراضي',
          'variantSku': 'GROC-RICE-1KG',
          'quantityScaled': 2000,
          'quantityScale': 1000,
          'measurementType': 'weight',
          'unitPriceMinor': 9000,
          'subtotalMinor': 18000,
          'discountMinor': 0,
          'taxMinor': 0,
          'totalMinor': 18000,
        },
      ],
    },
  );
}

Future<void> _location(
  AppDatabase db,
  String organizationId,
  String branchId,
  String warehouseId, {
  required String branchCode,
  required String branchName,
  required String warehouseCode,
  required String warehouseName,
}) async {
  await db
      .into(db.businessBranches)
      .insert(
        BusinessBranchesCompanion.insert(
          id: branchId,
          organizationId: organizationId,
          code: branchCode,
          name: Value(branchName),
        ),
      );
  await db
      .into(db.businessWarehouses)
      .insert(
        BusinessWarehousesCompanion.insert(
          id: warehouseId,
          organizationId: organizationId,
          branchId: branchId,
          code: warehouseCode,
          name: Value(warehouseName),
        ),
      );
}

Future<int> _category(AppDatabase db, String name) => db
    .into(db.productCategories)
    .insert(ProductCategoriesCompanion.insert(name: name));

Future<int> _supplier(
  AppDatabase db,
  int currencyId,
  String name, {
  required String productCode,
}) => db
    .into(db.suppliers)
    .insert(
      SuppliersCompanion.insert(
        name: name,
        currencyId: currencyId,
        productCode: Value(productCode),
        balanceCents: Value(Decimal.zero),
      ),
    );

Future<_ProductSeed> _product(
  AppDatabase db,
  int currencyId,
  String warehouseId, {
  required String name,
  required String sku,
  String? barcode,
  required int categoryId,
  required int supplierId,
  required int cost,
  required int price,
  required int quantity,
  String measurementType = 'piece',
  bool taxable = false,
  String tracking = 'standard',
}) async {
  final productId = await db
      .into(db.products)
      .insert(
        ProductsCompanion.insert(
          name: name,
          nameAr: Value(name),
          sku: Value(sku),
          barcode: Value(barcode),
          categoryId: Value(categoryId),
          supplierId: Value(supplierId),
          currencyId: Value(currencyId),
          costCents: Decimal.fromInt(cost),
          priceCents: Decimal.fromInt(price),
          stockQuantity: const Value(0),
          measurementType: Value(measurementType),
          isTaxable: Value(taxable),
          purchaseTaxRateBps: Value(taxable ? 1400 : 0),
          salesTaxRateBps: Value(taxable ? 1400 : 0),
          inventoryTrackingType: Value(tracking),
        ),
      );
  final variantId = await db
      .into(db.productVariants)
      .insert(
        ProductVariantsCompanion.insert(
          productId: productId,
          sku: Value('$sku-BASE'),
          barcode: Value(barcode == null ? null : '$barcode-0'),
          costCents: Decimal.fromInt(cost),
          priceCents: Decimal.fromInt(price),
          stockQuantity: const Value(0),
        ),
      );
  await (db.update(db.businessWarehouseStocks)..where(
        (row) =>
            row.warehouseId.equals(warehouseId) &
            row.variantId.equals(variantId),
      ))
      .write(
        BusinessWarehouseStocksCompanion(
          quantity: const Value(0),
          unitCostCents: Value(cost),
        ),
      );
  return _ProductSeed(productId, variantId);
}

Future<_ProductSeed> _variableProduct(
  AppDatabase db,
  int currencyId,
  String warehouseId, {
  required int categoryId,
  required int supplierId,
}) async {
  final color = await db
      .into(db.productColors)
      .insert(
        ProductColorsCompanion.insert(
          name: 'أزرق',
          hexCode: const Value('#1565C0'),
        ),
      );
  final size = await db
      .into(db.sizes)
      .insert(
        SizesCompanion.insert(name: 'M', description: const Value('متوسط')),
      );
  final productId = await db
      .into(db.products)
      .insert(
        ProductsCompanion.insert(
          name: 'قميص بمتغيرات',
          nameAr: const Value('قميص بمتغيرات'),
          sku: const Value('FASH-SHIRT'),
          categoryId: Value(categoryId),
          supplierId: Value(supplierId),
          currencyId: Value(currencyId),
          costCents: Decimal.fromInt(9000),
          priceCents: Decimal.fromInt(15000),
          stockQuantity: const Value(0),
          hasVariants: const Value(true),
        ),
      );
  final variantId = await db
      .into(db.productVariants)
      .insert(
        ProductVariantsCompanion.insert(
          productId: productId,
          sku: const Value('FASH-SHIRT-BLUE-M'),
          barcode: const Value('6290000000035'),
          colorId: Value(color),
          sizeId: Value(size),
          costCents: Decimal.fromInt(9000),
          priceCents: Decimal.fromInt(15000),
          stockQuantity: const Value(0),
        ),
      );
  await (db.update(db.businessWarehouseStocks)..where(
        (row) =>
            row.warehouseId.equals(warehouseId) &
            row.variantId.equals(variantId),
      ))
      .write(
        const BusinessWarehouseStocksCompanion(
          quantity: Value(0),
          unitCostCents: Value(9000),
        ),
      );
  return _ProductSeed(productId, variantId);
}

Future<int> _postedPurchase(
  AppDatabase db,
  JournalEntryService journal, {
  required int currencyId,
  required int supplierId,
  required _ProductSeed product,
  required int quantity,
  required int unitCost,
  required String number,
  required int ownerId,
}) async {
  final total = quantity * unitCost;
  final id = await db
      .into(db.purchases)
      .insert(
        PurchasesCompanion.insert(
          purchaseNumber: number,
          supplierId: supplierId,
          subtotalCents: Decimal.fromInt(total),
          taxCents: Decimal.zero,
          totalCents: Decimal.fromInt(total),
          paidAmountCents: Value(Decimal.zero),
          currencyId: currencyId,
          paymentMethod: const Value('credit'),
          status: const Value('draft'),
        ),
      );
  await db
      .into(db.purchaseItems)
      .insert(
        PurchaseItemsCompanion.insert(
          purchaseId: id,
          productId: product.productId,
          variantId: Value(product.variantId),
          quantity: quantity,
          unitCostCents: Decimal.fromInt(unitCost),
          subtotalCents: Decimal.fromInt(total),
          totalCents: Decimal.fromInt(total),
        ),
      );
  await db.purchaseDao.postPurchase(id);
  await journal.recordPurchaseJournalEntry(
    purchaseId: id,
    totalCents: total,
    paidAmountCents: 0,
    currencyId: currencyId,
    inventoryNetCents: total,
    paymentMethod: 'credit',
    userId: ownerId,
  );
  return id;
}

Future<({int saleId, int itemId})> _postedSale(
  AppDatabase db,
  JournalEntryService journal, {
  required int currencyId,
  required int customerId,
  required _ProductSeed product,
  required int quantity,
  required int unitPrice,
  required int tax,
  required String number,
  required int ownerId,
  required String paymentMethod,
  int quantityScale = 1,
  String measurementType = 'piece',
}) async {
  final subtotal = (quantity * unitPrice) ~/ quantityScale;
  final total = subtotal + tax;
  final id = await db
      .into(db.sales)
      .insert(
        SalesCompanion.insert(
          invoiceNumber: number,
          customerId: Value(customerId),
          subtotalCents: Decimal.fromInt(subtotal),
          taxCents: Decimal.fromInt(tax),
          totalCents: Decimal.fromInt(total),
          paidAmountCents: Value(
            Decimal.fromInt(paymentMethod == 'cash' ? total : 0),
          ),
          currencyId: currencyId,
          paymentMethod: paymentMethod,
          status: const Value('draft'),
        ),
      );
  final itemId = await db
      .into(db.saleItems)
      .insert(
        SaleItemsCompanion.insert(
          saleId: id,
          productId: product.productId,
          variantId: Value(product.variantId),
          quantity: quantity,
          quantityScale: Value(quantityScale),
          measurementType: Value(measurementType),
          unitPriceCents: Decimal.fromInt(unitPrice),
          subtotalCents: Decimal.fromInt(subtotal),
          taxCents: Value(Decimal.fromInt(tax)),
          totalCents: Decimal.fromInt(total),
        ),
      );
  await db.saleDao.postSale(id);
  await journal.recordSaleJournalEntry(
    saleId: id,
    totalCents: total,
    paidAmountCents: paymentMethod == 'cash' ? total : 0,
    currencyId: currencyId,
    taxCents: tax,
    paymentMethod: paymentMethod,
    userId: ownerId,
  );
  // Keep the acceptance dataset on the exact production posting path:
  // postSale removes the physical stock, while this mandatory leg removes
  // the same carrying value from Inventory (1200) into COGS (5300).
  await journal.recordSaleCOGSJournalEntry(
    saleId: id,
    costCents: await db.saleDao.computeSaleCostCents(id),
    currencyId: currencyId,
    userId: ownerId,
  );
  return (saleId: id, itemId: itemId);
}

Future<void> _seedTransfer(
  AppDatabase db,
  _ProductSeed product,
  WarehouseOperationScope source,
  String destinationWarehouseId,
  int ownerId,
) async {
  final destination = await WarehouseOperationScope.resolve(
    db,
    warehouseId: destinationWarehouseId,
  );
  await db.customStatement(
    'INSERT OR IGNORE INTO business_warehouse_stocks '
    '(warehouse_id,variant_id,quantity,supplier_owned_quantity,unit_cost_cents,updated_at) '
    'VALUES(?,?,0,0,0,CURRENT_TIMESTAMP)',
    [destinationWarehouseId, product.variantId],
  );
  final preflight = WarehouseTransferPreflight(
    db,
    authorizeWarehouse: (_) async {},
  );
  Future<int> authorize(TransferDraftAction _, String from, String to) async =>
      ownerId;
  final repository = WarehouseTransferRepository(
    db,
    preflight: preflight,
    authorize: authorize,
  );
  final preview = await preflight.preview(
    source: source,
    destination: destination,
    lines: [
      WarehouseTransferRequestLine(
        productId: product.productId,
        variantId: product.variantId,
        quantity: 3,
      ),
    ],
  );
  final draft = await repository.create(
    requestKey: const Uuid().v4(),
    preview: preview,
  );
  final dispatch =
      await WarehouseTransferDispatchService(
        db,
        preflight: preflight,
        authorize: authorize,
      ).dispatch(
        transferId: draft.header.id,
        requestKey: const Uuid().v4(),
        dispatchedAt: DateTime.utc(2026, 9, 28, 10),
      );
  await WarehouseTransferReceiptService(db, authorize: authorize).receive(
    transferId: draft.header.id,
    requestKey: const Uuid().v4(),
    receivedAt: DateTime.utc(2026, 9, 28, 11),
    items: [
      WarehouseTransferReceiptRequestItem(
        allocationId: dispatch.allocations.single.id,
        acceptedQuantity: 3,
      ),
    ],
  );
}

Future<void> _seedConsignment(
  AppDatabase db,
  _FixedSession session,
  int currencyId,
  int supplierId,
  _ProductSeed product,
  int ownerId,
) async {
  final module = ConsignmentModuleService(
    db,
    session,
    const GrantedConsignmentEntitlement(),
    BranchConsignmentPolicyStore(db),
    isRemoteClient: () => false,
  );
  await module.initialize();
  await module.setEnabled(enabled: true, reason: 'بيانات قبول شاملة');
  final agreements = ConsignmentAgreementService(db, module);
  await agreements.setSupplierDefaultMode(supplierId, 'consignment');
  final draft = await agreements.createDraft(
    supplierId: supplierId,
    currencyId: currencyId,
    agreementNumber: 'CON-ACCEPT-0001',
    effectiveFrom: DateTime.utc(2026, 9, 1),
    terms: [
      ConsignmentAgreementTermInput.fixedCost(
        productId: product.productId,
        variantId: product.variantId,
        amountCents: 8000,
      ),
    ],
  );
  final active = await agreements.activate(draft.id);
  final local = await LocalBranchScope.read(db);
  final receipts = ConsignmentReceiptService(db, module);
  final receipt = await receipts.createDraft(
    requestKey: const Uuid().v4(),
    receiptNumber: 'CR-ACCEPT-0001',
    warehouseId: local.warehouseId,
    supplierId: supplierId,
    agreementId: active.id,
    currencyId: currencyId,
    receivedAt: DateTime.utc(2026, 9, 27),
    lines: [
      ConsignmentReceiptLineInput(
        productId: product.productId,
        variantId: product.variantId,
        quantity: 8,
      ),
    ],
  );
  await receipts.post(receiptId: receipt.id, requestKey: const Uuid().v4());
}
