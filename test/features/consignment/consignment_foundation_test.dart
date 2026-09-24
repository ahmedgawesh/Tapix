import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/database/daos/inventory_adjustment_dao.dart';
import 'package:tapix/core/services/business/branch_consignment_policy_store.dart';
import 'package:tapix/core/services/business/local_branch_scope.dart';
import 'package:tapix/core/services/business/warehouse_operation_scope.dart';
import 'package:tapix/core/services/inventory/inventory_adjustment_service.dart';
import 'package:tapix/core/services/inventory/inventory_stock_source_service.dart';
import 'package:tapix/core/services/journal_entry_service.dart';
import 'package:tapix/core/services/ledger_rebuild_service.dart';
import 'package:tapix/core/services/stock_service.dart';
import 'package:tapix/features/accounting/data/repositories/accounting_repository.dart';
import 'package:tapix/features/accounting/data/repositories/journal_repository_impl.dart';
import 'package:tapix/features/consignment/data/consignment_sale_accounting_service.dart';
import 'package:tapix/features/accounting/data/datasources/journal_local_datasource.dart';
import 'package:tapix/features/auth/data/services/session_service.dart';
import 'package:tapix/features/consignment/data/consignment_agreement_service.dart';
import 'package:tapix/features/consignment/data/consignment_entitlement.dart';
import 'package:tapix/features/consignment/data/consignment_module_service.dart';
import 'package:tapix/features/consignment/data/consignment_receipt_service.dart';
import 'package:tapix/features/consignment/data/consignment_reporting_service.dart';
import 'package:tapix/features/consignment/data/consignment_settlement_service.dart';
import 'package:tapix/features/reports/presentation/bloc/supplier_sales_report_bloc.dart';

class _TestSession extends SessionService {
  _TestSession(this.userId);
  final int? userId;

  @override
  Future<int?> getCurrentUserId() async => userId;
}

AppDatabase _memoryDb() =>
    AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));

Future<int> _user(AppDatabase db, String name, String role) => db
    .into(db.users)
    .insert(
      UsersCompanion.insert(
        username: name,
        passwordHash: 'not-used',
        role: role,
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      ),
    );

ConsignmentModuleService _module(
  AppDatabase db,
  int actor, {
  ConsignmentEntitlement entitlement = const GrantedConsignmentEntitlement(),
  bool remote = false,
}) => ConsignmentModuleService(
  db,
  _TestSession(actor),
  entitlement,
  BranchConsignmentPolicyStore(db),
  isRemoteClient: () => remote,
);

Future<
  ({
    int owner,
    int manager,
    int cashier,
    int currency,
    int supplier,
    int product,
    int variant,
  })
>
_seed(AppDatabase db) async {
  final owner = await _user(db, 'consignment-owner', 'owner');
  final manager = await _user(db, 'consignment-manager', 'manager');
  final cashier = await _user(db, 'consignment-cashier', 'cashier');
  final currency = (await (db.select(
    db.currencies,
  )..where((c) => c.code.equals('USD'))).getSingle()).id;
  final supplier = await db
      .into(db.suppliers)
      .insert(
        SuppliersCompanion.insert(
          name: 'Consignment supplier',
          currencyId: currency,
        ),
      );
  final product = await db
      .into(db.products)
      .insert(
        ProductsCompanion.insert(
          name: 'Consignment product',
          currencyId: Value(currency),
          costCents: Decimal.fromInt(1000),
          priceCents: Decimal.fromInt(1500),
        ),
      );
  final variant = await db
      .into(db.productVariants)
      .insert(
        ProductVariantsCompanion.insert(
          productId: product,
          costCents: Decimal.fromInt(1000),
          priceCents: Decimal.fromInt(1500),
        ),
      );
  return (
    owner: owner,
    manager: manager,
    cashier: cashier,
    currency: currency,
    supplier: supplier,
    product: product,
    variant: variant,
  );
}

void main() {
  test(
    'fresh foundation is disabled and historical suppliers stay standard',
    () async {
      final db = _memoryDb();
      addTearDown(db.close);
      final seed = await _seed(db);
      expect(db.schemaVersion, 10115);

      final policy = await BranchConsignmentPolicyStore(
        db,
      ).initializeDisabled();
      expect(policy.policy.enabled, isFalse);
      expect(policy.revision, 1);
      expect(policy.changedBy, isNull);
      expect(
        (await (db.select(
              db.suppliers,
            )..where((s) => s.id.equals(seed.supplier))).getSingle())
            .defaultSupplyMode,
        'standard',
      );
    },
  );

  test('only owner or manager can change branch policy', () async {
    final db = _memoryDb();
    addTearDown(db.close);
    final seed = await _seed(db);
    final store = BranchConsignmentPolicyStore(db);
    final initial = await store.initializeDisabled();

    await expectLater(
      store.update(
        expected: initial,
        enabled: true,
        actorId: seed.cashier,
        reason: 'unauthorized attempt',
      ),
      throwsStateError,
    );
    final enabled = await store.update(
      expected: initial,
      enabled: true,
      actorId: seed.manager,
      reason: 'approved module activation',
    );
    expect(enabled.policy.enabled, isTrue);
    expect(enabled.changedBy, seed.manager);
    expect(enabled.revision, 2);

    await expectLater(
      store.update(
        expected: initial,
        enabled: false,
        actorId: seed.owner,
        reason: 'stale editor',
      ),
      throwsStateError,
    );
  });

  test('license, local mode and branch switch are independent gates', () async {
    final db = _memoryDb();
    addTearDown(db.close);
    final seed = await _seed(db);

    final unlicensed = _module(
      db,
      seed.owner,
      entitlement: const UnreleasedConsignmentEntitlement(),
    );
    await unlicensed.initialize();
    expect(await unlicensed.canEnable(), isFalse);
    await expectLater(
      unlicensed.setEnabled(enabled: true, reason: 'no entitlement'),
      throwsA(isA<ConsignmentAccessDenied>()),
    );

    final remote = _module(db, seed.owner, remote: true);
    expect(await remote.canEnable(), isFalse);
    await expectLater(
      remote.setEnabled(enabled: true, reason: 'remote device'),
      throwsA(isA<ConsignmentAccessDenied>()),
    );
  });

  test(
    'agreement lifecycle is versioned and has no stock or financial effect',
    () async {
      final db = _memoryDb();
      addTearDown(db.close);
      final seed = await _seed(db);
      final module = _module(db, seed.owner);
      await module.initialize();
      await module.setEnabled(enabled: true, reason: 'test activation');
      final service = ConsignmentAgreementService(db, module);

      final stockBefore = await db.select(db.businessWarehouseStocks).get();
      final purchasesBefore = await db.select(db.purchases).get();
      final journalBefore = await db.select(db.journalEntries).get();
      final supplierBefore = await (db.select(
        db.suppliers,
      )..where((s) => s.id.equals(seed.supplier))).getSingle();

      final draft = await service.createDraft(
        supplierId: seed.supplier,
        currencyId: seed.currency,
        agreementNumber: 'CON-001',
        effectiveFrom: DateTime.utc(2026, 9, 1),
        terms: [
          ConsignmentAgreementTermInput.fixedCost(
            productId: seed.product,
            variantId: seed.variant,
            amountCents: 900,
          ),
        ],
      );
      expect(draft.status, 'draft');
      final active = await service.activate(draft.id);
      expect(active.status, 'active');

      expect(await db.select(db.businessWarehouseStocks).get(), stockBefore);
      expect(await db.select(db.purchases).get(), purchasesBefore);
      expect(await db.select(db.journalEntries).get(), journalBefore);
      expect(
        (await (db.select(
          db.suppliers,
        )..where((s) => s.id.equals(seed.supplier))).getSingle()).balanceCents,
        supplierBefore.balanceCents,
      );

      await expectLater(
        (db.update(
          db.consignmentAgreementItems,
        )..where((i) => i.agreementId.equals(active.id))).write(
          const ConsignmentAgreementItemsCompanion(unitCostCents: Value(901)),
        ),
        throwsA(anything),
      );

      final addedProduct = await db
          .into(db.products)
          .insert(
            ProductsCompanion.insert(
              name: 'Added agreement product',
              currencyId: Value(seed.currency),
              costCents: Decimal.fromInt(700),
              priceCents: Decimal.fromInt(1200),
            ),
          );
      final addedVariant = await db
          .into(db.productVariants)
          .insert(
            ProductVariantsCompanion.insert(
              productId: addedProduct,
              costCents: Decimal.fromInt(700),
              priceCents: Decimal.fromInt(1200),
            ),
          );
      final revision = await service.createDraftOrRevision(
        supplierId: seed.supplier,
        currencyId: seed.currency,
        agreementNumber: 'CON-001',
        effectiveFrom: DateTime.utc(2026, 9, 23),
        terms: [
          ConsignmentAgreementTermInput.salesPercentage(
            productId: addedProduct,
            variantId: addedVariant,
            shareBps: 6000,
            includeSalesTax: false,
          ),
        ],
      );
      expect(revision.revision, 2);
      final revisionTerms = await (db.select(
        db.consignmentAgreementItems,
      )..where((item) => item.agreementId.equals(revision.id))).get();
      expect(revisionTerms, hasLength(2));
      expect(
        revisionTerms.singleWhere((item) => item.productId == seed.product),
        isA<ConsignmentAgreementItem>()
            .having((item) => item.settlementBasis, 'basis', 'fixed_unit_cost')
            .having((item) => item.unitCostCents, 'unit cost', 900),
      );
      expect(
        revisionTerms.singleWhere((item) => item.productId == addedProduct),
        isA<ConsignmentAgreementItem>()
            .having(
              (item) => item.settlementBasis,
              'basis',
              'net_sales_percentage',
            )
            .having((item) => item.supplierShareBps, 'share', 6000),
      );
      final activeRevision = await service.activate(revision.id);
      expect(activeRevision.status, 'active');
      expect(
        (await (db.select(
          db.consignmentAgreements,
        )..where((a) => a.id.equals(active.id))).getSingle()).status,
        'superseded',
      );
    },
  );

  test('future agreement remains a draft until its effective date', () async {
    final db = _memoryDb();
    addTearDown(db.close);
    final seed = await _seed(db);
    final module = _module(db, seed.owner);
    await module.initialize();
    await module.setEnabled(enabled: true, reason: 'future agreement test');
    final service = ConsignmentAgreementService(db, module);
    final draft = await service.createDraft(
      supplierId: seed.supplier,
      currencyId: seed.currency,
      agreementNumber: 'CON-FUTURE',
      effectiveFrom: DateTime.now().toUtc().add(const Duration(days: 1)),
      terms: [
        ConsignmentAgreementTermInput.fixedCost(
          productId: seed.product,
          variantId: seed.variant,
          amountCents: 900,
        ),
      ],
    );

    await expectLater(service.activate(draft.id), throwsStateError);
    expect(
      (await (db.select(
        db.consignmentAgreements,
      )..where((row) => row.id.equals(draft.id))).getSingle()).status,
      'draft',
    );
  });

  test(
    'overlapping product-wide and variant terms are rejected atomically',
    () async {
      final db = _memoryDb();
      addTearDown(db.close);
      final seed = await _seed(db);
      final module = _module(db, seed.owner);
      await module.initialize();
      await module.setEnabled(enabled: true, reason: 'test activation');
      final service = ConsignmentAgreementService(db, module);

      await expectLater(
        service.createDraft(
          supplierId: seed.supplier,
          currencyId: seed.currency,
          agreementNumber: 'CON-OVERLAP',
          effectiveFrom: DateTime.utc(2026, 9, 1),
          terms: [
            ConsignmentAgreementTermInput.fixedCost(
              productId: seed.product,
              amountCents: 900,
            ),
            ConsignmentAgreementTermInput.fixedCost(
              productId: seed.product,
              variantId: seed.variant,
              amountCents: 850,
            ),
          ],
        ),
        throwsA(anything),
      );
      expect(await db.select(db.consignmentAgreements).get(), isEmpty);
      expect(await db.select(db.consignmentAgreementItems).get(), isEmpty);
    },
  );

  test(
    'agreement rejects supplier or product currency mismatch atomically',
    () async {
      final db = _memoryDb();
      addTearDown(db.close);
      final seed = await _seed(db);
      final module = _module(db, seed.owner);
      await module.initialize();
      await module.setEnabled(enabled: true, reason: 'currency validation');
      final service = ConsignmentAgreementService(db, module);
      final otherCurrency = (await (db.select(
        db.currencies,
      )..where((row) => row.code.equals('EUR'))).getSingle()).id;
      final otherProduct = await db
          .into(db.products)
          .insert(
            ProductsCompanion.insert(
              name: 'Euro consignment product',
              currencyId: Value(otherCurrency),
              costCents: Decimal.fromInt(1000),
              priceCents: Decimal.fromInt(1500),
            ),
          );
      final otherVariant = await db
          .into(db.productVariants)
          .insert(
            ProductVariantsCompanion.insert(
              productId: otherProduct,
              costCents: Decimal.fromInt(1000),
              priceCents: Decimal.fromInt(1500),
            ),
          );

      await expectLater(
        service.createDraft(
          supplierId: seed.supplier,
          currencyId: otherCurrency,
          agreementNumber: 'CON-BAD-SUPPLIER-CURRENCY',
          effectiveFrom: DateTime.utc(2026, 9, 1),
          terms: [
            ConsignmentAgreementTermInput.fixedCost(
              productId: otherProduct,
              variantId: otherVariant,
              amountCents: 900,
            ),
          ],
        ),
        throwsStateError,
      );
      await expectLater(
        service.createDraft(
          supplierId: seed.supplier,
          currencyId: seed.currency,
          agreementNumber: 'CON-BAD-PRODUCT-CURRENCY',
          effectiveFrom: DateTime.utc(2026, 9, 1),
          terms: [
            ConsignmentAgreementTermInput.fixedCost(
              productId: otherProduct,
              variantId: otherVariant,
              amountCents: 900,
            ),
          ],
        ),
        throwsStateError,
      );
      expect(await db.select(db.consignmentAgreements).get(), isEmpty);
      expect(await db.select(db.consignmentAgreementItems).get(), isEmpty);
    },
  );

  test(
    'disabling the branch blocks new agreements but allows standard reset',
    () async {
      final db = _memoryDb();
      addTearDown(db.close);
      final seed = await _seed(db);
      final module = _module(db, seed.owner);
      await module.initialize();
      await module.setEnabled(enabled: true, reason: 'test activation');
      final service = ConsignmentAgreementService(db, module);
      await service.setSupplierDefaultMode(seed.supplier, 'consignment');

      await module.setEnabled(enabled: false, reason: 'temporary shutdown');
      await expectLater(
        service.createDraft(
          supplierId: seed.supplier,
          currencyId: seed.currency,
          agreementNumber: 'BLOCKED',
          effectiveFrom: DateTime.utc(2026, 9, 1),
          terms: [
            ConsignmentAgreementTermInput.fixedCost(
              productId: seed.product,
              variantId: seed.variant,
              amountCents: 900,
            ),
          ],
        ),
        throwsA(isA<ConsignmentModuleDisabled>()),
      );
      await service.setSupplierDefaultMode(seed.supplier, 'standard');
      expect(
        (await (db.select(
              db.suppliers,
            )..where((s) => s.id.equals(seed.supplier))).getSingle())
            .defaultSupplyMode,
        'standard',
      );
    },
  );

  test(
    'posting WAC consignment changes custody but not owned value or payables',
    () async {
      final db = _memoryDb();
      addTearDown(db.close);
      final seed = await _seed(db);
      final module = _module(db, seed.owner);
      await module.initialize();
      await module.setEnabled(enabled: true, reason: 'test activation');
      final agreements = ConsignmentAgreementService(db, module);
      final agreement = await agreements.createDraft(
        supplierId: seed.supplier,
        currencyId: seed.currency,
        agreementNumber: 'CON-WAC-001',
        effectiveFrom: DateTime.utc(2026, 9, 1),
        terms: [
          ConsignmentAgreementTermInput.fixedCost(
            productId: seed.product,
            variantId: seed.variant,
            amountCents: 900,
          ),
        ],
      );
      await agreements.activate(agreement.id);

      final supplierBefore = await (db.select(
        db.suppliers,
      )..where((s) => s.id.equals(seed.supplier))).getSingle();
      final journalsBefore = await db.select(db.journalEntries).get();
      final purchasesBefore = await db.select(db.purchases).get();
      final valuation = JournalLocalDatasourceImpl(db.accountingDao);
      final valueBefore = await valuation.getTotalInventoryValueCents();
      final scope = await LocalBranchScope.read(db);
      final receipts = ConsignmentReceiptService(db, module);
      final draft = await receipts.createDraft(
        requestKey: const Uuid().v4(),
        receiptNumber: 'CR-001',
        warehouseId: scope.warehouseId,
        supplierId: seed.supplier,
        agreementId: agreement.id,
        currencyId: seed.currency,
        receivedAt: DateTime.utc(2026, 9, 23),
        lines: [
          ConsignmentReceiptLineInput(
            productId: seed.product,
            variantId: seed.variant,
            quantity: 5,
          ),
        ],
      );
      expect(draft.status, 'draft');

      final postingKey = const Uuid().v4();
      final posted = await receipts.post(
        receiptId: draft.id,
        requestKey: postingKey,
      );
      expect(posted.status, 'posted');
      final retry = await receipts.post(
        receiptId: draft.id,
        requestKey: postingKey,
      );
      expect(retry.id, posted.id);

      final stock =
          await (db.select(db.businessWarehouseStocks)..where(
                (s) =>
                    s.warehouseId.equals(scope.warehouseId) &
                    s.variantId.equals(seed.variant),
              ))
              .getSingle();
      expect(stock.quantity, 5);
      expect(stock.supplierOwnedQuantity, 5);
      expect(
        (await (db.select(
          db.productVariants,
        )..where((v) => v.id.equals(seed.variant))).getSingle()).stockQuantity,
        5,
      );
      expect(await valuation.getTotalInventoryValueCents(), valueBefore);
      expect(await db.select(db.journalEntries).get(), journalsBefore);
      expect(await db.select(db.purchases).get(), purchasesBefore);
      expect(
        (await (db.select(
          db.suppliers,
        )..where((s) => s.id.equals(seed.supplier))).getSingle()).balanceCents,
        supplierBefore.balanceCents,
      );
      final layer =
          (await db.select(db.consignmentInventoryLayers).get()).single;
      expect(layer.remainingQuantity, 5);
      expect(layer.supplierId, seed.supplier);
      expect(layer.batchId, isNull);
      final origin = (await db.select(db.inventoryOriginStates).get()).single;
      expect(origin.layers, contains('consignment_receipt'));
      final sourceSnapshot = await InventoryStockSourceService(
        db,
      ).loadProduct(seed.product, variantId: seed.variant);
      expect(sourceSnapshot.physicalQuantity, 5);
      expect(sourceSnapshot.enterpriseQuantity, 0);
      expect(sourceSnapshot.consignmentQuantity, 5);
      expect(sourceSnapshot.reconciled, isTrue);
      expect(sourceSnapshot.sources, hasLength(1));
      expect(sourceSnapshot.sources.single.supplierId, seed.supplier);
      expect(sourceSnapshot.sources.single.consignmentLayerId, layer.id);
      final sourceCode = sourceSnapshot.sources.single.sourceCode!;
      expect(sourceCode, 'C-${layer.id}');
      final resolvedSource = await InventoryStockSourceService(
        db,
      ).resolveConsignmentCodeReference(sourceCode);
      expect(resolvedSource?.consignmentLayerId, layer.id);
      expect(resolvedSource?.supplierId, seed.supplier);

      final operationScope = await WarehouseOperationScope.resolve(
        db,
        warehouseId: scope.warehouseId,
      );
      final adjustments = InventoryAdjustmentService(
        db: db,
        dao: InventoryAdjustmentDao(db),
        journal: JournalEntryService(AccountingRepository(db)),
      );
      for (final request in [
        () => adjustments.adjust(
          productId: seed.product,
          variantId: seed.variant,
          type: InventoryAdjustmentType.revaluation,
          newUnitCostCents: 1100,
          reason: 'Must use custody workflow',
          currencyId: seed.currency,
          scope: operationScope,
        ),
        () => adjustments.adjust(
          productId: seed.product,
          variantId: seed.variant,
          type: InventoryAdjustmentType.shrinkage,
          quantityDelta: -1,
          reason: 'Must use custody workflow',
          currencyId: seed.currency,
          scope: operationScope,
        ),
        () => adjustments.adjust(
          productId: seed.product,
          variantId: seed.variant,
          type: InventoryAdjustmentType.gain,
          quantityDelta: 1,
          reason: 'Must use custody workflow',
          currencyId: seed.currency,
          scope: operationScope,
        ),
      ]) {
        await expectLater(
          request(),
          throwsA(isA<InventoryAdjustmentException>()),
        );
      }
      final protectedStock =
          await (db.select(db.businessWarehouseStocks)..where(
                (row) =>
                    row.warehouseId.equals(scope.warehouseId) &
                    row.variantId.equals(seed.variant),
              ))
              .getSingle();
      expect(protectedStock.quantity, 5);
      expect(protectedStock.supplierOwnedQuantity, 5);
      expect(
        (await db.select(db.consignmentInventoryLayers).get())
            .single
            .remainingQuantity,
        5,
      );

      await module.setEnabled(enabled: false, reason: 'history-only test');
      final expiredModule = _module(
        db,
        seed.owner,
        entitlement: const UnreleasedConsignmentEntitlement(),
      );
      final history = await ConsignmentReportingService(
        db,
        expiredModule,
      ).load();
      expect(history.operationsEnabled, isFalse);
      expect(await expiredModule.canOpenCenter(), isTrue);
      expect(history.reportRows.single.remainingQuantities, {'piece': 5});

      final voided = await ConsignmentReceiptService(db, expiredModule)
          .voidReceipt(
            receiptId: posted.id,
            requestKey: const Uuid().v4(),
            reason: 'Correct a historical receipt',
          );
      expect(voided.status, 'voided');
      final stockAfterVoid =
          await (db.select(db.businessWarehouseStocks)..where(
                (row) =>
                    row.warehouseId.equals(scope.warehouseId) &
                    row.variantId.equals(seed.variant),
              ))
              .getSingle();
      expect(stockAfterVoid.quantity, 0);
      expect(stockAfterVoid.supplierOwnedQuantity, 0);
      expect(
        (await ConsignmentReportingService(
          db,
          module,
        ).load()).reportRows.single.remainingQuantities,
        isEmpty,
      );
    },
  );

  test(
    'custody report keeps measured quantities in their own dimension',
    () async {
      final db = _memoryDb();
      addTearDown(db.close);
      final seed = await _seed(db);
      await (db.update(db.products)
            ..where((row) => row.id.equals(seed.product)))
          .write(const ProductsCompanion(measurementType: Value('weight')));
      final module = _module(db, seed.owner);
      await module.initialize();
      await module.setEnabled(enabled: true, reason: 'measured report test');
      final agreements = ConsignmentAgreementService(db, module);
      final agreement = await agreements.createDraft(
        supplierId: seed.supplier,
        currencyId: seed.currency,
        agreementNumber: 'CON-WEIGHT-001',
        effectiveFrom: DateTime.utc(2026, 9, 1),
        terms: [
          ConsignmentAgreementTermInput.fixedCost(
            productId: seed.product,
            variantId: seed.variant,
            amountCents: 900,
          ),
        ],
      );
      await agreements.activate(agreement.id);
      final scope = await LocalBranchScope.read(db);
      final receipts = ConsignmentReceiptService(db, module);
      final receipt = await receipts.createDraft(
        requestKey: const Uuid().v4(),
        receiptNumber: 'CR-WEIGHT-001',
        warehouseId: scope.warehouseId,
        supplierId: seed.supplier,
        agreementId: agreement.id,
        currencyId: seed.currency,
        receivedAt: DateTime.utc(2026, 9, 23),
        lines: [
          ConsignmentReceiptLineInput(
            productId: seed.product,
            variantId: seed.variant,
            quantity: 1500,
          ),
        ],
      );
      await receipts.post(receiptId: receipt.id, requestKey: const Uuid().v4());

      final snapshot = await ConsignmentReportingService(db, module).load();
      expect(snapshot.supplierOwnedQuantities, {'weight': 1500});
      expect(snapshot.reportRows.single.receivedQuantities, {'weight': 1500});
      expect(snapshot.reportRows.single.remainingQuantities, {'weight': 1500});
    },
  );

  test(
    'zero settlement preserves quantity provenance through return and void',
    () async {
      final db = _memoryDb();
      addTearDown(db.close);
      final seed = await _seed(db);
      final module = _module(db, seed.owner);
      await module.initialize();
      await module.setEnabled(enabled: true, reason: 'zero settlement test');

      final agreements = ConsignmentAgreementService(db, module);
      final agreement = await agreements.createDraft(
        supplierId: seed.supplier,
        currencyId: seed.currency,
        agreementNumber: 'CON-ZERO-001',
        effectiveFrom: DateTime.utc(2026, 9, 1),
        terms: [
          ConsignmentAgreementTermInput.fixedCost(
            productId: seed.product,
            variantId: seed.variant,
            amountCents: 0,
          ),
        ],
      );
      await agreements.activate(agreement.id);
      final scope = await WarehouseOperationScope.resolve(db);
      final receipt = await ConsignmentReceiptService(db, module).createDraft(
        requestKey: const Uuid().v4(),
        receiptNumber: 'CR-ZERO-001',
        warehouseId: scope.warehouseId,
        supplierId: seed.supplier,
        agreementId: agreement.id,
        currencyId: seed.currency,
        receivedAt: DateTime.utc(2026, 9, 20),
        lines: [
          ConsignmentReceiptLineInput(
            productId: seed.product,
            variantId: seed.variant,
            quantity: 2,
          ),
        ],
      );
      await ConsignmentReceiptService(
        db,
        module,
      ).post(receiptId: receipt.id, requestKey: const Uuid().v4());

      final accountingService = ConsignmentSaleAccountingService(
        db,
        JournalEntryService(AccountingRepository(db)),
      );
      final saleId = await db.saleDao.createSaleWithItems(
        SalesCompanion.insert(
          invoiceNumber: 'SI-CON-ZERO-001',
          subtotalCents: Decimal.fromInt(1500),
          taxCents: Decimal.zero,
          totalCents: Decimal.fromInt(1500),
          currencyId: seed.currency,
          paymentMethod: 'cash',
          status: const Value('draft'),
          saleDate: Value(DateTime.utc(2026, 9, 23)),
        ),
        [
          SaleItemsCompanion.insert(
            saleId: 0,
            productId: seed.product,
            variantId: Value(seed.variant),
            quantity: 1,
            unitPriceCents: Decimal.fromInt(1500),
            subtotalCents: Decimal.fromInt(1500),
            itemDiscountAtPostCents: Value(Decimal.zero),
            invoiceDiscountAtPostCents: Value(Decimal.zero),
            totalCents: Decimal.fromInt(1500),
          ),
        ],
        scope: scope,
      );
      await db.saleDao.postSale(
        saleId,
        scope: scope,
        beforeCompletion: (id) =>
            accountingService.postPendingAccruals(id, userId: seed.owner),
      );
      final saleItem = (await db.saleDao.getSaleItems(saleId)).single;
      var events = await db.select(db.consignmentObligationEvents).get();
      expect(events.map((event) => event.kind), ['sale_accrual']);
      expect(events.single.signedQuantity, 1);
      expect(events.single.signedAmountCents, 0);
      expect(events.single.journalEntryId, isNull);
      expect(await db.select(db.journalEntries).get(), isEmpty);

      final returnId = await db.saleDao.createSaleReturn(
        SaleReturnsCompanion.insert(
          saleId: saleId,
          returnNumber: 'SR-CON-ZERO-001',
          subtotalCents: Value(Decimal.fromInt(1500)),
          totalCents: Decimal.fromInt(1500),
          currencyId: seed.currency,
          status: const Value('draft'),
          returnDate: Value(DateTime.utc(2026, 9, 23)),
        ),
        [
          SaleReturnItemsCompanion.insert(
            returnId: 0,
            saleItemId: saleItem.id,
            quantity: 1,
            subtotalCents: Value(Decimal.fromInt(1500)),
            refundCents: Decimal.fromInt(1500),
          ),
        ],
      );
      await db.saleDao.postSaleReturn(
        returnId,
        scope: scope,
        beforeCompletion: (id) => accountingService.postPendingReturnReversals(
          id,
          userId: seed.owner,
        ),
      );
      await db.saleDao.voidSaleReturn(
        returnId,
        scope: scope,
        beforeCompletion: (id) => accountingService
            .postPendingReturnVoidReaccruals(id, userId: seed.owner),
      );
      await db.saleDao.voidSale(
        saleId,
        scope: scope,
        beforeReturnCompletion: (id) => accountingService
            .postPendingReturnVoidReaccruals(id, userId: seed.owner),
        beforeCompletion: (id) => accountingService
            .postPendingSaleVoidReversals(id, userId: seed.owner),
      );

      events = await (db.select(
        db.consignmentObligationEvents,
      )..orderBy([(event) => OrderingTerm.asc(event.createdAt)])).get();
      expect(events.map((event) => event.kind).toSet(), {
        'sale_accrual',
        'linked_return_reversal',
        'return_void_reaccrual',
        'sale_void_reversal',
      });
      expect(events.every((event) => event.signedAmountCents == 0), isTrue);
      expect(events.every((event) => event.journalEntryId == null), isTrue);
      expect(await db.select(db.journalEntries).get(), isEmpty);
      final stock =
          await (db.select(db.businessWarehouseStocks)..where(
                (row) =>
                    row.warehouseId.equals(scope.warehouseId) &
                    row.variantId.equals(seed.variant),
              ))
              .getSingle();
      expect(stock.quantity, 2);
      expect(stock.supplierOwnedQuantity, 2);
      final report = await ConsignmentReportingService(db, module).loadReport(
        range: ConsignmentReportRange(
          start: DateTime.utc(2026, 9, 1),
          end: DateTime.utc(2026, 9, 30, 23, 59, 59),
        ),
      );
      expect(report.single.netSoldQuantities, isEmpty);
      expect(report.single.returnedQuantities, isEmpty);
      expect(report.single.remainingQuantities, {'piece': 2});
      expect(report.single.periodObligationCents, 0);
    },
  );

  test(
    'percentage agreements split discounts and tax across multiple suppliers',
    () async {
      final db = _memoryDb();
      addTearDown(db.close);
      final seed = await _seed(db);
      final secondSupplier = await db
          .into(db.suppliers)
          .insert(
            SuppliersCompanion.insert(
              name: 'Second consignment supplier',
              currencyId: seed.currency,
            ),
          );
      final module = _module(db, seed.owner);
      await module.initialize();
      await module.setEnabled(
        enabled: true,
        reason: 'multi-supplier percentage test',
      );
      final agreements = ConsignmentAgreementService(db, module);
      final firstAgreement = await agreements.createDraft(
        supplierId: seed.supplier,
        currencyId: seed.currency,
        agreementNumber: 'CON-PERCENT-001',
        effectiveFrom: DateTime.utc(2026, 9, 1),
        terms: [
          ConsignmentAgreementTermInput.salesPercentage(
            productId: seed.product,
            variantId: seed.variant,
            shareBps: 5000,
          ),
        ],
      );
      final secondAgreement = await agreements.createDraft(
        supplierId: secondSupplier,
        currencyId: seed.currency,
        agreementNumber: 'CON-PERCENT-002',
        effectiveFrom: DateTime.utc(2026, 9, 1),
        terms: [
          ConsignmentAgreementTermInput.salesPercentage(
            productId: seed.product,
            variantId: seed.variant,
            shareBps: 6000,
          ),
        ],
      );
      await agreements.activate(firstAgreement.id);
      await agreements.activate(secondAgreement.id);
      final scope = await WarehouseOperationScope.resolve(db);
      final receipts = ConsignmentReceiptService(db, module);

      Future<void> receive({
        required String number,
        required int supplierId,
        required String agreementId,
      }) async {
        final receipt = await receipts.createDraft(
          requestKey: const Uuid().v4(),
          receiptNumber: number,
          warehouseId: scope.warehouseId,
          supplierId: supplierId,
          agreementId: agreementId,
          currencyId: seed.currency,
          receivedAt: DateTime.utc(2026, 9, 20),
          lines: [
            ConsignmentReceiptLineInput(
              productId: seed.product,
              variantId: seed.variant,
              quantity: 2,
            ),
          ],
        );
        await receipts.post(
          receiptId: receipt.id,
          requestKey: const Uuid().v4(),
        );
      }

      await receive(
        number: 'CR-PERCENT-001',
        supplierId: seed.supplier,
        agreementId: firstAgreement.id,
      );
      await receive(
        number: 'CR-PERCENT-002',
        supplierId: secondSupplier,
        agreementId: secondAgreement.id,
      );

      final accounting = AccountingRepository(db);
      await JournalRepositoryImpl(
        JournalLocalDatasourceImpl(db.accountingDao),
        accounting,
      ).seedDefaultAccounts(seed.currency);
      final saleAccounting = ConsignmentSaleAccountingService(
        db,
        JournalEntryService(accounting),
      );
      final saleId = await db.saleDao.createSaleWithItems(
        SalesCompanion.insert(
          invoiceNumber: 'SI-CON-PERCENT-001',
          subtotalCents: Decimal.fromInt(12000),
          discountCents: Value(Decimal.fromInt(1800)),
          taxCents: Decimal.fromInt(1020),
          totalCents: Decimal.fromInt(11220),
          currencyId: seed.currency,
          paymentMethod: 'cash',
          status: const Value('draft'),
          saleDate: Value(DateTime.utc(2026, 9, 23)),
        ),
        [
          SaleItemsCompanion.insert(
            saleId: 0,
            productId: seed.product,
            variantId: Value(seed.variant),
            quantity: 3,
            unitPriceCents: Decimal.fromInt(4000),
            subtotalCents: Decimal.fromInt(12000),
            discountCents: Value(Decimal.fromInt(1800)),
            itemDiscountAtPostCents: Value(Decimal.fromInt(1200)),
            invoiceDiscountAtPostCents: Value(Decimal.fromInt(600)),
            taxCents: Value(Decimal.fromInt(1020)),
            totalCents: Decimal.fromInt(11220),
          ),
        ],
        scope: scope,
      );
      await db.saleDao.postSale(
        saleId,
        scope: scope,
        beforeCompletion: (id) =>
            saleAccounting.postPendingAccruals(id, userId: seed.owner),
      );

      final allocations = await (db.select(
        db.consignmentSaleAllocations,
      )..orderBy([(row) => OrderingTerm.asc(row.sequence)])).get();
      expect(allocations, hasLength(2));
      expect(
        allocations
            .map(
              (row) => (
                supplier: row.supplierId,
                quantity: row.quantity,
                subtotal: row.allocatedSubtotalCents,
                lineDiscount: row.allocatedLineDiscountCents,
                invoiceDiscount: row.allocatedInvoiceDiscountCents,
                tax: row.allocatedTaxCents,
                base: row.settlementBaseCents,
                due: row.obligationCents,
              ),
            )
            .toList(),
        [
          (
            supplier: seed.supplier,
            quantity: 2,
            subtotal: 8000,
            lineDiscount: 800,
            invoiceDiscount: 400,
            tax: 680,
            base: 6800,
            due: 3400,
          ),
          (
            supplier: secondSupplier,
            quantity: 1,
            subtotal: 4000,
            lineDiscount: 400,
            invoiceDiscount: 200,
            tax: 340,
            base: 3400,
            due: 2040,
          ),
        ],
      );
      final stock =
          await (db.select(db.businessWarehouseStocks)..where(
                (row) =>
                    row.warehouseId.equals(scope.warehouseId) &
                    row.variantId.equals(seed.variant),
              ))
              .getSingle();
      expect(stock.quantity, 1);
      expect(stock.supplierOwnedQuantity, 1);
      expect(
        (await db.saleDao.getSaleItems(
          saleId,
        )).single.inventoryValueAtPostCents!.toBigInt().toInt(),
        0,
      );
      Future<int> accountBalance(String code) async =>
          (await (db.select(
                db.accounts,
              )..where((row) => row.accountCode.equals(code))).getSingle())
              .balanceCents
              .toBigInt()
              .toInt();
      expect(await accountBalance('2050'), 5440);
      expect(await accountBalance('5300'), 5440);

      final report = await ConsignmentReportingService(db, module).loadReport(
        range: ConsignmentReportRange(
          start: DateTime.utc(2026, 9, 1),
          end: DateTime.utc(2026, 9, 30, 23, 59, 59),
        ),
      );
      final bySupplier = {for (final row in report) row.supplierId: row};
      expect(bySupplier[seed.supplier]!.grossSoldQuantities, {'piece': 2});
      expect(bySupplier[seed.supplier]!.periodObligationCents, 3400);
      expect(bySupplier[secondSupplier]!.grossSoldQuantities, {'piece': 1});
      expect(bySupplier[secondSupplier]!.periodObligationCents, 2040);
      expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
    },
  );

  test(
    'mixed WAC sale separates owned COGS from consignment accrual',
    () async {
      final db = _memoryDb();
      addTearDown(db.close);
      final seed = await _seed(db);
      final module = _module(db, seed.owner);
      await module.initialize();
      await module.setEnabled(enabled: true, reason: 'test activation');
      final agreements = ConsignmentAgreementService(db, module);
      final agreement = await agreements.createDraft(
        supplierId: seed.supplier,
        currencyId: seed.currency,
        agreementNumber: 'CON-MIXED-001',
        effectiveFrom: DateTime.utc(2026, 9, 1),
        terms: [
          ConsignmentAgreementTermInput.fixedCost(
            productId: seed.product,
            variantId: seed.variant,
            amountCents: 900,
          ),
        ],
      );
      await agreements.activate(agreement.id);
      final scope = await WarehouseOperationScope.resolve(db);
      final receipts = ConsignmentReceiptService(db, module);
      final receipt = await receipts.createDraft(
        requestKey: const Uuid().v4(),
        receiptNumber: 'CR-MIXED-001',
        warehouseId: scope.warehouseId,
        supplierId: seed.supplier,
        agreementId: agreement.id,
        currencyId: seed.currency,
        receivedAt: DateTime.utc(2026, 9, 20),
        lines: [
          ConsignmentReceiptLineInput(
            productId: seed.product,
            variantId: seed.variant,
            quantity: 5,
          ),
        ],
      );
      await receipts.post(receiptId: receipt.id, requestKey: const Uuid().v4());
      await StockService.adjustStock(
        db.productDao,
        productId: seed.product,
        variantId: seed.variant,
        quantity: 5,
        direction: StockDirection.increase,
        scope: scope,
        origin: const InventoryOriginIntent('purchase', 999),
      );
      await StockService.syncProductStockFromVariants(
        db.productDao,
        productId: seed.product,
        scope: scope,
      );

      final accounting = AccountingRepository(db);
      await JournalRepositoryImpl(
        JournalLocalDatasourceImpl(db.accountingDao),
        accounting,
      ).seedDefaultAccounts(seed.currency);
      final accountingService = ConsignmentSaleAccountingService(
        db,
        JournalEntryService(accounting),
      );
      final supplierBalanceBefore = (await (db.select(
        db.suppliers,
      )..where((s) => s.id.equals(seed.supplier))).getSingle()).balanceCents;

      final saleId = await db.saleDao.createSaleWithItems(
        SalesCompanion.insert(
          invoiceNumber: 'SI-CON-MIXED-001',
          subtotalCents: Decimal.fromInt(9000),
          taxCents: Decimal.zero,
          totalCents: Decimal.fromInt(9000),
          currencyId: seed.currency,
          paymentMethod: 'cash',
          status: const Value('draft'),
          saleDate: Value(DateTime.utc(2026, 9, 23)),
        ),
        [
          SaleItemsCompanion.insert(
            saleId: 0,
            productId: seed.product,
            variantId: Value(seed.variant),
            quantity: 6,
            unitPriceCents: Decimal.fromInt(1500),
            subtotalCents: Decimal.fromInt(9000),
            itemDiscountAtPostCents: Value(Decimal.zero),
            invoiceDiscountAtPostCents: Value(Decimal.zero),
            totalCents: Decimal.fromInt(9000),
          ),
        ],
        scope: scope,
      );
      await db.saleDao.postSale(
        saleId,
        scope: scope,
        beforeCompletion: (id) =>
            accountingService.postPendingAccruals(id, userId: seed.owner),
      );

      final stock =
          await (db.select(db.businessWarehouseStocks)..where(
                (row) =>
                    row.warehouseId.equals(scope.warehouseId) &
                    row.variantId.equals(seed.variant),
              ))
              .getSingle();
      expect(stock.quantity, 4);
      expect(stock.supplierOwnedQuantity, 0);
      final item = (await db.saleDao.getSaleItems(saleId)).single;
      expect(item.inventoryValueAtPostCents!.toBigInt().toInt(), 1000);
      final allocation =
          (await db.select(db.consignmentSaleAllocations).get()).single;
      expect(allocation.quantity, 5);
      expect(allocation.obligationCents, 4500);
      expect(allocation.allocatedSubtotalCents, 7500);
      final event =
          (await db.select(db.consignmentObligationEvents).get()).single;
      expect(event.signedAmountCents, 4500);
      expect(event.journalEntryId, isNotNull);
      final accrued = await (db.select(
        db.accounts,
      )..where((a) => a.accountCode.equals('2050'))).getSingle();
      final cogs = await (db.select(
        db.accounts,
      )..where((a) => a.accountCode.equals('5300'))).getSingle();
      expect(accrued.balanceCents.toBigInt().toInt(), 4500);
      expect(cogs.balanceCents.toBigInt().toInt(), 4500);
      expect(
        (await (db.select(
          db.suppliers,
        )..where((s) => s.id.equals(seed.supplier))).getSingle()).balanceCents,
        supplierBalanceBefore,
      );

      final returnId = await db.saleDao.createSaleReturn(
        SaleReturnsCompanion.insert(
          saleId: saleId,
          returnNumber: 'SR-CON-MIXED-001',
          subtotalCents: Value(Decimal.fromInt(3000)),
          totalCents: Decimal.fromInt(3000),
          currencyId: seed.currency,
          status: const Value('draft'),
          returnDate: Value(DateTime.utc(2026, 9, 22)),
        ),
        [
          SaleReturnItemsCompanion.insert(
            returnId: 0,
            saleItemId: item.id,
            quantity: 2,
            subtotalCents: Value(Decimal.fromInt(3000)),
            refundCents: Decimal.fromInt(3000),
          ),
        ],
      );
      await db.saleDao.postSaleReturn(
        returnId,
        scope: scope,
        beforeCompletion: (id) => accountingService.postPendingReturnReversals(
          id,
          userId: seed.owner,
        ),
      );

      final stockAfterReturn =
          await (db.select(db.businessWarehouseStocks)..where(
                (row) =>
                    row.warehouseId.equals(scope.warehouseId) &
                    row.variantId.equals(seed.variant),
              ))
              .getSingle();
      expect(stockAfterReturn.quantity, 6);
      expect(stockAfterReturn.supplierOwnedQuantity, 2);
      final returnedItem =
          (await db.saleDao.watchSaleReturnItems(returnId).first).single;
      expect(returnedItem.inventoryValueAtPostCents!.toBigInt().toInt(), 0);
      final reversed = await (db.select(
        db.consignmentSaleAllocations,
      )..where((row) => row.id.equals(allocation.id))).getSingle();
      expect(reversed.reversedQuantity, 2);
      expect(reversed.reversedObligationCents, 1800);
      expect(reversed.status, 'partially_reversed');
      final reversal =
          (await (db.select(db.consignmentObligationEvents)
                    ..where((row) => row.kind.equals('linked_return_reversal')))
                  .get())
              .single;
      expect(reversal.signedAmountCents, -1800);
      expect(reversal.journalEntryId, isNotNull);
      final supplierReport = SupplierSalesReportBloc(db);
      addTearDown(supplierReport.close);
      final supplierReportData = await supplierReport.load();
      final consignmentRow = supplierReportData.rows.singleWhere(
        (row) => row.sourceQuality == 'consignment',
      );
      expect(consignmentRow.supplierId, seed.supplier);
      expect(consignmentRow.soldQuantity, 5);
      expect(consignmentRow.returnedQuantity, 2);
      expect(consignmentRow.consignmentReceipts, {'CR-MIXED-001'});
      expect(consignmentRow.purchaseInvoices, isEmpty);
      expect(
        (await (db.select(
              db.accounts,
            )..where((a) => a.accountCode.equals('2050'))).getSingle())
            .balanceCents
            .toBigInt()
            .toInt(),
        2700,
      );
      expect(
        (await (db.select(
              db.accounts,
            )..where((a) => a.accountCode.equals('5300'))).getSingle())
            .balanceCents
            .toBigInt()
            .toInt(),
        2700,
      );
      await db.saleDao.voidSaleReturn(
        returnId,
        scope: scope,
        beforeCompletion: (id) => accountingService
            .postPendingReturnVoidReaccruals(id, userId: seed.owner),
      );
      final stockAfterVoid =
          await (db.select(db.businessWarehouseStocks)..where(
                (row) =>
                    row.warehouseId.equals(scope.warehouseId) &
                    row.variantId.equals(seed.variant),
              ))
              .getSingle();
      expect(stockAfterVoid.quantity, 4);
      expect(stockAfterVoid.supplierOwnedQuantity, 0);
      final activeAgain = await (db.select(
        db.consignmentSaleAllocations,
      )..where((row) => row.id.equals(allocation.id))).getSingle();
      expect(activeAgain.reversedQuantity, 0);
      expect(activeAgain.reversedObligationCents, 0);
      expect(activeAgain.status, 'active');
      final reaccrual =
          (await (db.select(db.consignmentObligationEvents)
                    ..where((row) => row.kind.equals('return_void_reaccrual')))
                  .get())
              .single;
      expect(reaccrual.signedAmountCents, 1800);
      expect(reaccrual.journalEntryId, isNotNull);
      expect(
        (await (db.select(
              db.accounts,
            )..where((a) => a.accountCode.equals('2050'))).getSingle())
            .balanceCents
            .toBigInt()
            .toInt(),
        4500,
      );

      final damagedReturnId = await db.saleDao.createSaleReturn(
        SaleReturnsCompanion.insert(
          saleId: saleId,
          returnNumber: 'SR-CON-MIXED-DAMAGED-001',
          subtotalCents: Value(Decimal.fromInt(1500)),
          totalCents: Decimal.fromInt(1500),
          currencyId: seed.currency,
          status: const Value('draft'),
          dispositionType: const Value('write_off'),
          returnDate: Value(DateTime.utc(2026, 9, 23)),
        ),
        [
          SaleReturnItemsCompanion.insert(
            returnId: 0,
            saleItemId: item.id,
            quantity: 1,
            subtotalCents: Value(Decimal.fromInt(1500)),
            refundCents: Decimal.fromInt(1500),
          ),
        ],
      );
      await db.saleDao.postSaleReturn(
        damagedReturnId,
        scope: scope,
        beforeCompletion: (id) => accountingService.postPendingReturnReversals(
          id,
          userId: seed.owner,
        ),
      );
      final stockAfterDamaged =
          await (db.select(db.businessWarehouseStocks)..where(
                (row) =>
                    row.warehouseId.equals(scope.warehouseId) &
                    row.variantId.equals(seed.variant),
              ))
              .getSingle();
      expect(stockAfterDamaged.quantity, 4);
      expect(stockAfterDamaged.supplierOwnedQuantity, 0);
      final damagedEvent =
          (await (db.select(db.consignmentObligationEvents)..where(
                    (row) =>
                        row.sourceId.equals(damagedReturnId) &
                        row.kind.equals('linked_return_reversal'),
                  ))
                  .get())
              .single;
      expect(damagedEvent.signedQuantity, -1);
      expect(damagedEvent.signedAmountCents, -900);
      expect(damagedEvent.restoresStock, isFalse);
      var custodyReport = await ConsignmentReportingService(db, module)
          .loadReport(
            range: ConsignmentReportRange(
              start: DateTime.utc(2026, 9, 1),
              end: DateTime.utc(2026, 9, 30, 23, 59, 59),
            ),
          );
      expect(custodyReport.single.remainingQuantities, isEmpty);
      expect(custodyReport.single.unavailableQuantities, {'piece': 1});

      await db.saleDao.voidSaleReturn(
        damagedReturnId,
        scope: scope,
        beforeCompletion: (id) => accountingService
            .postPendingReturnVoidReaccruals(id, userId: seed.owner),
      );
      final stockAfterDamagedVoid =
          await (db.select(db.businessWarehouseStocks)..where(
                (row) =>
                    row.warehouseId.equals(scope.warehouseId) &
                    row.variantId.equals(seed.variant),
              ))
              .getSingle();
      expect(stockAfterDamagedVoid.quantity, 4);
      expect(stockAfterDamagedVoid.supplierOwnedQuantity, 0);
      custodyReport = await ConsignmentReportingService(db, module).loadReport(
        range: ConsignmentReportRange(
          start: DateTime.utc(2026, 9, 1),
          end: DateTime.utc(2026, 9, 30, 23, 59, 59),
        ),
      );
      expect(custodyReport.single.unavailableQuantities, isEmpty);

      await db.saleDao.voidSale(
        saleId,
        scope: scope,
        beforeReturnCompletion: (id) => accountingService
            .postPendingReturnVoidReaccruals(id, userId: seed.owner),
        beforeCompletion: (id) => accountingService
            .postPendingSaleVoidReversals(id, userId: seed.owner),
      );
      final stockAfterSaleVoid =
          await (db.select(db.businessWarehouseStocks)..where(
                (row) =>
                    row.warehouseId.equals(scope.warehouseId) &
                    row.variantId.equals(seed.variant),
              ))
              .getSingle();
      expect(stockAfterSaleVoid.quantity, 10);
      expect(stockAfterSaleVoid.supplierOwnedQuantity, 5);
      final voidedAllocation = await (db.select(
        db.consignmentSaleAllocations,
      )..where((row) => row.id.equals(allocation.id))).getSingle();
      expect(voidedAllocation.reversedQuantity, 5);
      expect(voidedAllocation.reversedObligationCents, 4500);
      expect(voidedAllocation.status, 'fully_reversed');
      final voidReversal = (await (db.select(
        db.consignmentObligationEvents,
      )..where((row) => row.kind.equals('sale_void_reversal'))).get()).single;
      expect(voidReversal.signedQuantity, -5);
      expect(voidReversal.signedAmountCents, -4500);
      expect(voidReversal.journalEntryId, isNotNull);
      expect(
        (await (db.select(
              db.accounts,
            )..where((a) => a.accountCode.equals('2050'))).getSingle())
            .balanceCents
            .toBigInt()
            .toInt(),
        0,
      );
      expect(
        (await (db.select(
              db.accounts,
            )..where((a) => a.accountCode.equals('5300'))).getSingle())
            .balanceCents
            .toBigInt()
            .toInt(),
        0,
      );
      expect((await db.saleDao.getSaleById(saleId))!.status, 'voided');
    },
  );

  test(
    'FIFO partial returns restore each original consignment batch once',
    () async {
      final db = _memoryDb();
      addTearDown(db.close);
      final seed = await _seed(db);
      await (db.update(
        db.products,
      )..where((p) => p.id.equals(seed.product))).write(
        const ProductsCompanion(
          costingMethod: Value('fifo'),
          inventoryTrackingType: Value('batch'),
        ),
      );
      final module = _module(db, seed.owner);
      await module.initialize();
      await module.setEnabled(enabled: true, reason: 'FIFO test activation');
      final agreements = ConsignmentAgreementService(db, module);
      final agreement = await agreements.createDraft(
        supplierId: seed.supplier,
        currencyId: seed.currency,
        agreementNumber: 'CON-FIFO-001',
        effectiveFrom: DateTime.utc(2026, 9, 1),
        terms: [
          ConsignmentAgreementTermInput.fixedCost(
            productId: seed.product,
            variantId: seed.variant,
            amountCents: 900,
          ),
        ],
      );
      await agreements.activate(agreement.id);
      final scope = await WarehouseOperationScope.resolve(db);
      final receipts = ConsignmentReceiptService(db, module);
      for (var index = 0; index < 2; index++) {
        final receipt = await receipts.createDraft(
          requestKey: const Uuid().v4(),
          receiptNumber: 'CR-FIFO-00${index + 1}',
          warehouseId: scope.warehouseId,
          supplierId: seed.supplier,
          agreementId: agreement.id,
          currencyId: seed.currency,
          receivedAt: DateTime.utc(2026, 9, 20 + index),
          lines: [
            ConsignmentReceiptLineInput(
              productId: seed.product,
              variantId: seed.variant,
              quantity: 3,
              manufacturerLotNumber: 'LOT-${index + 1}',
            ),
          ],
        );
        await receipts.post(
          receiptId: receipt.id,
          requestKey: const Uuid().v4(),
        );
      }

      final accounting = AccountingRepository(db);
      await JournalRepositoryImpl(
        JournalLocalDatasourceImpl(db.accountingDao),
        accounting,
      ).seedDefaultAccounts(seed.currency);
      final journal = JournalEntryService(accounting);
      final accountingService = ConsignmentSaleAccountingService(db, journal);
      final saleId = await db.saleDao.createSaleWithItems(
        SalesCompanion.insert(
          invoiceNumber: 'SI-CON-FIFO-001',
          subtotalCents: Decimal.fromInt(7500),
          taxCents: Decimal.zero,
          totalCents: Decimal.fromInt(7500),
          currencyId: seed.currency,
          paymentMethod: 'cash',
          status: const Value('draft'),
          saleDate: Value(DateTime.utc(2026, 9, 23)),
        ),
        [
          SaleItemsCompanion.insert(
            saleId: 0,
            productId: seed.product,
            variantId: Value(seed.variant),
            quantity: 5,
            unitPriceCents: Decimal.fromInt(1500),
            subtotalCents: Decimal.fromInt(7500),
            itemDiscountAtPostCents: Value(Decimal.zero),
            invoiceDiscountAtPostCents: Value(Decimal.zero),
            totalCents: Decimal.fromInt(7500),
          ),
        ],
        scope: scope,
      );
      await db.saleDao.postSale(
        saleId,
        scope: scope,
        beforeCompletion: (id) =>
            accountingService.postPendingAccruals(id, userId: seed.owner),
      );
      final saleItem = (await db.saleDao.getSaleItems(saleId)).single;
      final batchesAfterSale = await (db.select(
        db.productBatches,
      )..orderBy([(b) => OrderingTerm.asc(b.receivedDate)])).get();
      expect(
        batchesAfterSale.map((batch) => batch.remainingQuantity).toList(),
        [0, 1],
      );

      Future<int> postReturn(String number, DateTime date) async {
        final id = await db.saleDao.createSaleReturn(
          SaleReturnsCompanion.insert(
            saleId: saleId,
            returnNumber: number,
            subtotalCents: Value(Decimal.fromInt(3000)),
            totalCents: Decimal.fromInt(3000),
            currencyId: seed.currency,
            status: const Value('draft'),
            returnDate: Value(date),
          ),
          [
            SaleReturnItemsCompanion.insert(
              returnId: 0,
              saleItemId: saleItem.id,
              quantity: 2,
              subtotalCents: Value(Decimal.fromInt(3000)),
              refundCents: Decimal.fromInt(3000),
            ),
          ],
        );
        await db.saleDao.postSaleReturn(
          id,
          scope: scope,
          beforeCompletion: (returnId) => accountingService
              .postPendingReturnReversals(returnId, userId: seed.owner),
        );
        return id;
      }

      await postReturn('SR-CON-FIFO-001', DateTime.utc(2026, 9, 24));
      await postReturn('SR-CON-FIFO-002', DateTime.utc(2026, 9, 25));
      final batchesAfterReturns = await (db.select(
        db.productBatches,
      )..orderBy([(b) => OrderingTerm.asc(b.receivedDate)])).get();
      expect(
        batchesAfterReturns.map((batch) => batch.remainingQuantity).toList(),
        [3, 2],
      );
      final allocations = await (db.select(
        db.consignmentSaleAllocations,
      )..orderBy([(a) => OrderingTerm.asc(a.sequence)])).get();
      expect(allocations.map((a) => a.reversedQuantity).toList(), [3, 1]);
      expect(
        (await (db.select(
              db.accounts,
            )..where((a) => a.accountCode.equals('2050'))).getSingle())
            .balanceCents
            .toBigInt()
            .toInt(),
        900,
      );

      await db.saleDao.voidSale(
        saleId,
        journalEntryService: journal,
        userId: seed.owner,
        scope: scope,
        beforeReturnCompletion: (returnId) => accountingService
            .postPendingReturnVoidReaccruals(returnId, userId: seed.owner),
        beforeCompletion: (id) => accountingService
            .postPendingSaleVoidReversals(id, userId: seed.owner),
      );
      final batchesAfterVoid = await (db.select(
        db.productBatches,
      )..orderBy([(b) => OrderingTerm.asc(b.receivedDate)])).get();
      expect(
        batchesAfterVoid.map((batch) => batch.remainingQuantity).toList(),
        [3, 3],
      );
      final stock =
          await (db.select(db.businessWarehouseStocks)..where(
                (row) =>
                    row.warehouseId.equals(scope.warehouseId) &
                    row.variantId.equals(seed.variant),
              ))
              .getSingle();
      expect(stock.quantity, 6);
      expect(stock.supplierOwnedQuantity, 6);
      expect(
        (await (db.select(
              db.accounts,
            )..where((a) => a.accountCode.equals('2050'))).getSingle())
            .balanceCents
            .toBigInt()
            .toInt(),
        0,
      );
    },
  );

  test(
    'WAC adjustment return restores an explicitly selected consignment source',
    () async {
      final db = _memoryDb();
      addTearDown(db.close);
      final seed = await _seed(db);
      final module = _module(db, seed.owner);
      await module.initialize();
      await module.setEnabled(
        enabled: true,
        reason: 'adjustment-return test activation',
      );
      final agreements = ConsignmentAgreementService(db, module);
      final agreement = await agreements.createDraft(
        supplierId: seed.supplier,
        currencyId: seed.currency,
        agreementNumber: 'CON-ADJ-WAC-001',
        effectiveFrom: DateTime.utc(2026, 9, 1),
        terms: [
          ConsignmentAgreementTermInput.fixedCost(
            productId: seed.product,
            variantId: seed.variant,
            amountCents: 900,
          ),
        ],
      );
      await agreements.activate(agreement.id);
      final scope = await WarehouseOperationScope.resolve(db);
      final receipts = ConsignmentReceiptService(db, module);
      final receipt = await receipts.createDraft(
        requestKey: const Uuid().v4(),
        receiptNumber: 'CR-ADJ-WAC-001',
        warehouseId: scope.warehouseId,
        supplierId: seed.supplier,
        agreementId: agreement.id,
        currencyId: seed.currency,
        receivedAt: DateTime.utc(2026, 9, 20),
        lines: [
          ConsignmentReceiptLineInput(
            productId: seed.product,
            variantId: seed.variant,
            quantity: 5,
          ),
        ],
      );
      await receipts.post(receiptId: receipt.id, requestKey: const Uuid().v4());
      final layer =
          (await db.select(db.consignmentInventoryLayers).get()).single;

      final accounting = AccountingRepository(db);
      await JournalRepositoryImpl(
        JournalLocalDatasourceImpl(db.accountingDao),
        accounting,
      ).seedDefaultAccounts(seed.currency);
      final journal = JournalEntryService(accounting);
      final saleAccounting = ConsignmentSaleAccountingService(db, journal);
      final saleId = await db.saleDao.createSaleWithItems(
        SalesCompanion.insert(
          invoiceNumber: 'SI-CON-ADJ-WAC-001',
          subtotalCents: Decimal.fromInt(3000),
          taxCents: Decimal.zero,
          totalCents: Decimal.fromInt(3000),
          currencyId: seed.currency,
          paymentMethod: 'cash',
          status: const Value('draft'),
          saleDate: Value(DateTime.utc(2026, 9, 21)),
        ),
        [
          SaleItemsCompanion.insert(
            saleId: 0,
            productId: seed.product,
            variantId: Value(seed.variant),
            quantity: 2,
            unitPriceCents: Decimal.fromInt(1500),
            subtotalCents: Decimal.fromInt(3000),
            itemDiscountAtPostCents: Value(Decimal.zero),
            invoiceDiscountAtPostCents: Value(Decimal.zero),
            totalCents: Decimal.fromInt(3000),
            consignmentLayerId: Value(layer.id),
          ),
        ],
        scope: scope,
      );
      await db.saleDao.postSale(
        saleId,
        scope: scope,
        beforeCompletion: (id) =>
            saleAccounting.postPendingAccruals(id, userId: seed.owner),
      );
      final soldLayer = await (db.select(
        db.consignmentInventoryLayers,
      )..where((row) => row.id.equals(layer.id))).getSingle();
      expect(soldLayer.remainingQuantity, 3);
      await module.setEnabled(enabled: false, reason: 'sell-through return');
      final availableSources = await db.adjustmentReturnDao
          .getConsignmentAdjustmentReturnSources(
            productId: seed.product,
            variantId: seed.variant,
            scope: scope,
          );
      expect(availableSources, hasLength(1));
      expect(availableSources.single.layerId, layer.id);
      expect(availableSources.single.supplierId, seed.supplier);
      expect(availableSources.single.maximumReturnQuantity, 2);

      final returnId = await db.adjustmentReturnDao.createSaleAdjReturn(
        SaleReturnAdjustmentsCompanion.insert(
          returnNumber: 'SAR-CON-WAC-001',
          currencyId: seed.currency,
          subtotalCents: Value(Decimal.fromInt(1500)),
          totalCents: Decimal.fromInt(1500),
          refundMethod: const Value('cash'),
          returnDate: Value(DateTime.utc(2026, 9, 22)),
        ),
        [
          SaleReturnAdjustmentItemsCompanion.insert(
            sourceResolution: const Value('consignment'),
            returnId: 0,
            productId: seed.product,
            variantId: Value(seed.variant),
            quantity: 1,
            unitPriceCents: Decimal.fromInt(1500),
            discountCents: Value(Decimal.zero),
            itemDiscountAtPostCents: Value(Decimal.zero),
            invoiceDiscountAtPostCents: Value(Decimal.zero),
            taxCents: Value(Decimal.zero),
            totalCents: Decimal.fromInt(1500),
            consignmentLayerId: Value(layer.id),
          ),
        ],
        scope: scope,
      );
      await db.adjustmentReturnDao.postSaleAdjReturn(
        returnId,
        journalEntryService: journal,
        userId: seed.owner,
        allowOverHistory: true,
        scope: scope,
      );

      var stock =
          await (db.select(db.businessWarehouseStocks)..where(
                (row) =>
                    row.warehouseId.equals(scope.warehouseId) &
                    row.variantId.equals(seed.variant),
              ))
              .getSingle();
      expect(stock.quantity, 4);
      expect(stock.supplierOwnedQuantity, 4);
      var updatedLayer = await (db.select(
        db.consignmentInventoryLayers,
      )..where((row) => row.id.equals(layer.id))).getSingle();
      expect(updatedLayer.remainingQuantity, 4);
      var events = await db.select(db.consignmentAdjustmentReturnEvents).get();
      expect(events, hasLength(1));
      expect(events.single.kind, 'adjustment_return_reversal');
      expect(events.single.signedQuantity, -1);
      expect(events.single.signedAmountCents, -900);
      expect(events.single.journalEntryId, isNotNull);
      var accrued = await (db.select(
        db.accounts,
      )..where((row) => row.accountCode.equals('2050'))).getSingle();
      expect(accrued.balanceCents.toBigInt().toInt(), 900);
      final returnItem = (await db.adjustmentReturnDao.getSaleAdjReturnItems(
        returnId,
      )).single;
      expect(returnItem.inventoryValueAtPostCents!.toBigInt().toInt(), 0);

      await db.adjustmentReturnDao.voidSaleAdjReturn(
        returnId,
        journalEntryService: journal,
        voidedBy: seed.owner,
        scope: scope,
      );
      stock =
          await (db.select(db.businessWarehouseStocks)..where(
                (row) =>
                    row.warehouseId.equals(scope.warehouseId) &
                    row.variantId.equals(seed.variant),
              ))
              .getSingle();
      expect(stock.quantity, 3);
      expect(stock.supplierOwnedQuantity, 3);
      updatedLayer = await (db.select(
        db.consignmentInventoryLayers,
      )..where((row) => row.id.equals(layer.id))).getSingle();
      expect(updatedLayer.remainingQuantity, 3);
      events = await db.select(db.consignmentAdjustmentReturnEvents).get();
      expect(events, hasLength(2));
      expect(events.last.kind, 'adjustment_return_void_reaccrual');
      expect(events.last.signedAmountCents, 900);
      expect(events.last.journalEntryId, isNotNull);
      accrued = await (db.select(
        db.accounts,
      )..where((row) => row.accountCode.equals('2050'))).getSingle();
      expect(accrued.balanceCents.toBigInt().toInt(), 1800);

      final damagedReturnId = await db.adjustmentReturnDao.createSaleAdjReturn(
        SaleReturnAdjustmentsCompanion.insert(
          returnNumber: 'SAR-CON-WAC-DAMAGED-001',
          currencyId: seed.currency,
          subtotalCents: Value(Decimal.fromInt(1500)),
          totalCents: Decimal.fromInt(1500),
          refundMethod: const Value('cash'),
          returnDate: Value(DateTime.utc(2026, 9, 23)),
        ),
        [
          SaleReturnAdjustmentItemsCompanion.insert(
            sourceResolution: const Value('consignment'),
            returnId: 0,
            productId: seed.product,
            variantId: Value(seed.variant),
            quantity: 1,
            unitPriceCents: Decimal.fromInt(1500),
            discountCents: Value(Decimal.zero),
            itemDiscountAtPostCents: Value(Decimal.zero),
            invoiceDiscountAtPostCents: Value(Decimal.zero),
            taxCents: Value(Decimal.zero),
            totalCents: Decimal.fromInt(1500),
            consignmentLayerId: Value(layer.id),
            dispositionType: const Value('damaged'),
          ),
        ],
        scope: scope,
      );
      await db.adjustmentReturnDao.postSaleAdjReturn(
        damagedReturnId,
        journalEntryService: journal,
        userId: seed.owner,
        allowOverHistory: true,
        scope: scope,
      );
      stock =
          await (db.select(db.businessWarehouseStocks)..where(
                (row) =>
                    row.warehouseId.equals(scope.warehouseId) &
                    row.variantId.equals(seed.variant),
              ))
              .getSingle();
      expect(stock.quantity, 3);
      expect(stock.supplierOwnedQuantity, 3);
      updatedLayer = await (db.select(
        db.consignmentInventoryLayers,
      )..where((row) => row.id.equals(layer.id))).getSingle();
      expect(updatedLayer.remainingQuantity, 3);
      final damagedEvent =
          (await (db.select(db.consignmentAdjustmentReturnEvents)..where(
                    (row) =>
                        row.returnId.equals(damagedReturnId) &
                        row.kind.equals('adjustment_return_reversal'),
                  ))
                  .get())
              .single;
      expect(damagedEvent.signedQuantity, -1);
      expect(damagedEvent.signedAmountCents, -900);
      expect(damagedEvent.restoresStock, isFalse);
      var report = await ConsignmentReportingService(db, module).loadReport(
        range: ConsignmentReportRange(
          start: DateTime.utc(2026, 9, 1),
          end: DateTime.utc(2026, 9, 30, 23, 59, 59),
        ),
      );
      expect(report.single.remainingQuantities, {'piece': 3});
      expect(report.single.unavailableQuantities, {'piece': 1});

      await db.adjustmentReturnDao.voidSaleAdjReturn(
        damagedReturnId,
        journalEntryService: journal,
        voidedBy: seed.owner,
        scope: scope,
      );
      stock =
          await (db.select(db.businessWarehouseStocks)..where(
                (row) =>
                    row.warehouseId.equals(scope.warehouseId) &
                    row.variantId.equals(seed.variant),
              ))
              .getSingle();
      expect(stock.quantity, 3);
      expect(stock.supplierOwnedQuantity, 3);
      report = await ConsignmentReportingService(db, module).loadReport(
        range: ConsignmentReportRange(
          start: DateTime.utc(2026, 9, 1),
          end: DateTime.utc(2026, 9, 30, 23, 59, 59),
        ),
      );
      expect(report.single.unavailableQuantities, isEmpty);
    },
  );

  test(
    'FIFO adjustment return restores and voids the selected consignment batch',
    () async {
      final db = _memoryDb();
      addTearDown(db.close);
      final seed = await _seed(db);
      await (db.update(
        db.products,
      )..where((row) => row.id.equals(seed.product))).write(
        const ProductsCompanion(
          costingMethod: Value('fifo'),
          inventoryTrackingType: Value('batch'),
        ),
      );
      final module = _module(db, seed.owner);
      await module.initialize();
      await module.setEnabled(
        enabled: true,
        reason: 'FIFO adjustment-return test activation',
      );
      final agreements = ConsignmentAgreementService(db, module);
      final agreement = await agreements.createDraft(
        supplierId: seed.supplier,
        currencyId: seed.currency,
        agreementNumber: 'CON-ADJ-FIFO-001',
        effectiveFrom: DateTime.utc(2026, 9, 1),
        terms: [
          ConsignmentAgreementTermInput.fixedCost(
            productId: seed.product,
            variantId: seed.variant,
            amountCents: 900,
          ),
        ],
      );
      await agreements.activate(agreement.id);
      final scope = await WarehouseOperationScope.resolve(db);
      final receipts = ConsignmentReceiptService(db, module);
      final receipt = await receipts.createDraft(
        requestKey: const Uuid().v4(),
        receiptNumber: 'CR-ADJ-FIFO-001',
        warehouseId: scope.warehouseId,
        supplierId: seed.supplier,
        agreementId: agreement.id,
        currencyId: seed.currency,
        receivedAt: DateTime.utc(2026, 9, 20),
        lines: [
          ConsignmentReceiptLineInput(
            productId: seed.product,
            variantId: seed.variant,
            quantity: 5,
            manufacturerLotNumber: 'LOT-ADJ-FIFO-1',
          ),
        ],
      );
      await receipts.post(receiptId: receipt.id, requestKey: const Uuid().v4());
      final layer =
          (await db.select(db.consignmentInventoryLayers).get()).single;
      final batchId = layer.batchId!;

      final accounting = AccountingRepository(db);
      await JournalRepositoryImpl(
        JournalLocalDatasourceImpl(db.accountingDao),
        accounting,
      ).seedDefaultAccounts(seed.currency);
      final journal = JournalEntryService(accounting);
      final saleAccounting = ConsignmentSaleAccountingService(db, journal);
      final saleId = await db.saleDao.createSaleWithItems(
        SalesCompanion.insert(
          invoiceNumber: 'SI-CON-ADJ-FIFO-001',
          subtotalCents: Decimal.fromInt(3000),
          taxCents: Decimal.zero,
          totalCents: Decimal.fromInt(3000),
          currencyId: seed.currency,
          paymentMethod: 'cash',
          status: const Value('draft'),
          saleDate: Value(DateTime.utc(2026, 9, 21)),
        ),
        [
          SaleItemsCompanion.insert(
            saleId: 0,
            productId: seed.product,
            variantId: Value(seed.variant),
            quantity: 2,
            unitPriceCents: Decimal.fromInt(1500),
            subtotalCents: Decimal.fromInt(3000),
            itemDiscountAtPostCents: Value(Decimal.zero),
            invoiceDiscountAtPostCents: Value(Decimal.zero),
            totalCents: Decimal.fromInt(3000),
            consignmentLayerId: Value(layer.id),
          ),
        ],
        scope: scope,
      );
      await db.saleDao.postSale(
        saleId,
        scope: scope,
        beforeCompletion: (id) =>
            saleAccounting.postPendingAccruals(id, userId: seed.owner),
      );
      expect(
        (await (db.select(
              db.productBatches,
            )..where((row) => row.id.equals(batchId))).getSingle())
            .remainingQuantity,
        3,
      );

      final returnId = await db.adjustmentReturnDao.createSaleAdjReturn(
        SaleReturnAdjustmentsCompanion.insert(
          returnNumber: 'SAR-CON-FIFO-001',
          currencyId: seed.currency,
          subtotalCents: Value(Decimal.fromInt(1500)),
          totalCents: Decimal.fromInt(1500),
          refundMethod: const Value('cash'),
          returnDate: Value(DateTime.utc(2026, 9, 22)),
        ),
        [
          SaleReturnAdjustmentItemsCompanion.insert(
            sourceResolution: const Value('consignment'),
            returnId: 0,
            productId: seed.product,
            variantId: Value(seed.variant),
            quantity: 1,
            unitPriceCents: Decimal.fromInt(1500),
            discountCents: Value(Decimal.zero),
            itemDiscountAtPostCents: Value(Decimal.zero),
            invoiceDiscountAtPostCents: Value(Decimal.zero),
            taxCents: Value(Decimal.zero),
            totalCents: Decimal.fromInt(1500),
            consignmentLayerId: Value(layer.id),
          ),
        ],
        scope: scope,
      );
      await db.adjustmentReturnDao.postSaleAdjReturn(
        returnId,
        journalEntryService: journal,
        userId: seed.owner,
        allowOverHistory: true,
        scope: scope,
      );
      var returnItem = (await db.adjustmentReturnDao.getSaleAdjReturnItems(
        returnId,
      )).single;
      expect(returnItem.returnBatchId, batchId);
      expect(returnItem.inventoryValueAtPostCents!.toBigInt().toInt(), 0);
      final supplierReport = SupplierSalesReportBloc(db);
      addTearDown(supplierReport.close);
      final supplierReportData = await supplierReport.load();
      final consignmentRow = supplierReportData.rows.singleWhere(
        (row) => row.sourceQuality == 'consignment',
      );
      expect(consignmentRow.supplierId, seed.supplier);
      expect(consignmentRow.soldQuantity, 2);
      expect(consignmentRow.returnedQuantity, 1);
      expect(consignmentRow.netCents, 1500);
      expect(consignmentRow.consignmentReceipts, {'CR-ADJ-FIFO-001'});
      expect(consignmentRow.purchaseInvoices, isEmpty);
      expect(
        (await (db.select(
              db.productBatches,
            )..where((row) => row.id.equals(batchId))).getSingle())
            .remainingQuantity,
        4,
      );

      await db.adjustmentReturnDao.voidSaleAdjReturn(
        returnId,
        journalEntryService: journal,
        voidedBy: seed.owner,
        scope: scope,
      );
      returnItem = (await db.adjustmentReturnDao.getSaleAdjReturnItems(
        returnId,
      )).single;
      expect(returnItem.returnBatchId, batchId);
      expect(
        (await (db.select(
              db.productBatches,
            )..where((row) => row.id.equals(batchId))).getSingle())
            .remainingQuantity,
        3,
      );
      final stock =
          await (db.select(db.businessWarehouseStocks)..where(
                (row) =>
                    row.warehouseId.equals(scope.warehouseId) &
                    row.variantId.equals(seed.variant),
              ))
              .getSingle();
      expect(stock.quantity, 3);
      expect(stock.supplierOwnedQuantity, 3);
      expect(
        (await (db.select(
              db.accounts,
            )..where((row) => row.accountCode.equals('2050'))).getSingle())
            .balanceCents
            .toBigInt()
            .toInt(),
        1800,
      );
    },
  );

  test('supplier-owned quantity can never exceed physical stock', () async {
    final db = _memoryDb();
    addTearDown(db.close);
    final seed = await _seed(db);
    final scope = await LocalBranchScope.read(db);
    await expectLater(
      db.customStatement(
        'UPDATE business_warehouse_stocks '
        'SET quantity=1,supplier_owned_quantity=2 '
        'WHERE warehouse_id=? AND variant_id=?',
        [scope.warehouseId, seed.variant],
      ),
      throwsA(anything),
    );
    final stock =
        await (db.select(db.businessWarehouseStocks)..where(
              (s) =>
                  s.warehouseId.equals(scope.warehouseId) &
                  s.variantId.equals(seed.variant),
            ))
            .getSingle();
    expect(stock.quantity, 0);
    expect(stock.supplierOwnedQuantity, 0);
  });

  test(
    'reviewed settlement moves accrual to AP and payment reversal plus void reconcile',
    () async {
      final db = _memoryDb();
      addTearDown(db.close);
      final seed = await _seed(db);
      final module = _module(db, seed.owner);
      await module.initialize();
      await module.setEnabled(enabled: true, reason: 'settlement test');
      final agreements = ConsignmentAgreementService(db, module);
      final agreement = await agreements.createDraft(
        supplierId: seed.supplier,
        currencyId: seed.currency,
        agreementNumber: 'CON-SETTLE-001',
        effectiveFrom: DateTime.utc(2026, 9, 1),
        settlementTaxRateBps: 1000,
        settlementTaxInclusive: false,
        paymentTermsDays: 14,
        terms: [
          ConsignmentAgreementTermInput.fixedCost(
            productId: seed.product,
            variantId: seed.variant,
            amountCents: 900,
          ),
        ],
      );
      await agreements.activate(agreement.id);
      final scope = await WarehouseOperationScope.resolve(db);
      final receipts = ConsignmentReceiptService(db, module);
      final receipt = await receipts.createDraft(
        requestKey: const Uuid().v4(),
        receiptNumber: 'CR-SETTLE-001',
        warehouseId: scope.warehouseId,
        supplierId: seed.supplier,
        agreementId: agreement.id,
        currencyId: seed.currency,
        receivedAt: DateTime.utc(2026, 9, 20),
        lines: [
          ConsignmentReceiptLineInput(
            productId: seed.product,
            variantId: seed.variant,
            quantity: 5,
          ),
        ],
      );
      await receipts.post(receiptId: receipt.id, requestKey: const Uuid().v4());

      final accounting = AccountingRepository(db);
      await JournalRepositoryImpl(
        JournalLocalDatasourceImpl(db.accountingDao),
        accounting,
      ).seedDefaultAccounts(seed.currency);
      final journal = JournalEntryService(accounting);
      final saleAccounting = ConsignmentSaleAccountingService(db, journal);
      final saleId = await db.saleDao.createSaleWithItems(
        SalesCompanion.insert(
          invoiceNumber: 'SI-CON-SETTLE-001',
          subtotalCents: Decimal.fromInt(3000),
          taxCents: Decimal.zero,
          totalCents: Decimal.fromInt(3000),
          currencyId: seed.currency,
          paymentMethod: 'cash',
          status: const Value('draft'),
          saleDate: Value(DateTime.utc(2026, 9, 22, 12)),
        ),
        [
          SaleItemsCompanion.insert(
            saleId: 0,
            productId: seed.product,
            variantId: Value(seed.variant),
            quantity: 2,
            unitPriceCents: Decimal.fromInt(1500),
            subtotalCents: Decimal.fromInt(3000),
            itemDiscountAtPostCents: Value(Decimal.zero),
            invoiceDiscountAtPostCents: Value(Decimal.zero),
            totalCents: Decimal.fromInt(3000),
          ),
        ],
        scope: scope,
      );
      await db.saleDao.postSale(
        saleId,
        scope: scope,
        beforeCompletion: (id) =>
            saleAccounting.postPendingAccruals(id, userId: seed.owner),
      );

      final pendingEvents = await db
          .select(db.consignmentObligationEvents)
          .get();
      expect(pendingEvents, hasLength(1));
      expect(pendingEvents.single.agreementId, agreement.id);
      expect(pendingEvents.single.currencyId, seed.currency);
      expect(pendingEvents.single.settlementStatus, 'unassigned');
      expect(pendingEvents.single.occurredAt, DateTime.utc(2026, 9, 22, 12));
      await module.setEnabled(enabled: false, reason: 'sell-through closure');
      final expiredModule = _module(
        db,
        seed.owner,
        entitlement: const UnreleasedConsignmentEntitlement(),
      );
      final settlements = ConsignmentSettlementService(
        db,
        expiredModule,
        journal,
      );
      final requestKey = const Uuid().v4();
      final draft = await settlements.createDraft(
        requestKey: requestKey,
        agreementId: agreement.id,
        periodStart: DateTime.utc(2026, 9, 1),
        periodEnd: DateTime.utc(2026, 9, 30, 23, 59, 59),
      );
      expect(draft.obligationSubtotalCents, 1800);
      expect(draft.taxCents, 180);
      expect(draft.totalCents, 1980);
      expect(draft.lineCount, 1);
      expect(
        (await settlements.createDraft(
          requestKey: requestKey,
          agreementId: agreement.id,
          periodStart: DateTime.utc(2026, 9, 1),
          periodEnd: DateTime.utc(2026, 9, 30, 23, 59, 59),
        )).id,
        draft.id,
      );

      await settlements.review(draft.id);
      final posted = await settlements.post(draft.id);
      expect(posted.status, 'posted');
      expect(posted.dueDate, DateTime.utc(2026, 10, 14, 23, 59, 59));
      await expectLater(
        db.customStatement(
          'UPDATE consignment_settlement_statements '
          "SET paid_cents=1,status='partially_paid' WHERE id=?",
          [posted.id],
        ),
        throwsA(anything),
      );
      expect(
        (await (db.select(
              db.suppliers,
            )..where((row) => row.id.equals(seed.supplier))).getSingle())
            .balanceCents
            .toBigInt()
            .toInt(),
        1980,
      );
      Future<int> accountBalance(String code) async =>
          (await (db.select(
                db.accounts,
              )..where((row) => row.accountCode.equals(code))).getSingle())
              .balanceCents
              .toBigInt()
              .toInt();
      expect(await accountBalance('2050'), 0);
      expect(await accountBalance('2000'), 1980);
      expect(await accountBalance('1300'), 180);

      final reportService = ConsignmentReportingService(db, module);
      final reportRange = ConsignmentReportRange(
        start: DateTime.utc(2026, 9, 1),
        end: DateTime.utc(2026, 9, 30, 23, 59, 59),
      );
      var report = (await reportService.loadReport(
        range: reportRange,
        supplierId: seed.supplier,
      )).single;
      expect(report.receivedQuantities, {'piece': 5});
      expect(report.grossSoldQuantities, {'piece': 2});
      expect(report.returnedQuantities, isEmpty);
      expect(report.netSoldQuantities, {'piece': 2});
      expect(report.remainingQuantities, {'piece': 3});
      expect(report.periodObligationCents, 1800);
      expect(report.postedSettlementCents, 1800);
      expect(report.paidCents, 0);
      expect(report.unsettledObligationCents, 0);
      expect(report.outstandingPayableCents, 1980);

      // A return posted after the original sale event has already been
      // settled belongs to the next statement as a supplier credit. It must
      // never mutate the frozen statement.
      final settledSaleItem = (await db.saleDao.getSaleItems(saleId)).single;
      final postSettlementReturnId = await db.saleDao.createSaleReturn(
        SaleReturnsCompanion.insert(
          saleId: saleId,
          returnNumber: 'SR-CON-AFTER-SETTLEMENT-001',
          subtotalCents: Value(Decimal.fromInt(1500)),
          totalCents: Decimal.fromInt(1500),
          currencyId: seed.currency,
          status: const Value('draft'),
          returnDate: Value(DateTime.utc(2026, 9, 23)),
        ),
        [
          SaleReturnItemsCompanion.insert(
            returnId: 0,
            saleItemId: settledSaleItem.id,
            quantity: 1,
            subtotalCents: Value(Decimal.fromInt(1500)),
            refundCents: Decimal.fromInt(1500),
          ),
        ],
      );
      await db.saleDao.postSaleReturn(
        postSettlementReturnId,
        scope: scope,
        beforeCompletion: (id) =>
            saleAccounting.postPendingReturnReversals(id, userId: seed.owner),
      );
      final creditDraft = await settlements.createDraft(
        requestKey: const Uuid().v4(),
        agreementId: agreement.id,
        periodStart: DateTime.utc(2026, 9, 1),
        periodEnd: DateTime.utc(2026, 9, 30, 23, 59, 59),
      );
      expect(creditDraft.obligationSubtotalCents, -900);
      expect(creditDraft.taxCents, -90);
      expect(creditDraft.totalCents, -990);
      expect(creditDraft.lineCount, 1);
      await settlements.voidStatement(
        statementId: creditDraft.id,
        reason: 'Regression test releases the supplier credit',
      );
      await db.saleDao.voidSaleReturn(
        postSettlementReturnId,
        scope: scope,
        beforeCompletion: (id) => saleAccounting
            .postPendingReturnVoidReaccruals(id, userId: seed.owner),
      );
      expect(
        (await (db.select(
              db.consignmentSettlementStatements,
            )..where((row) => row.id.equals(posted.id))).getSingle())
            .obligationSubtotalCents,
        1800,
      );

      expect((await reportService.load()).operationsEnabled, isFalse);

      final payment = await settlements.recordPayment(
        statementId: posted.id,
        amountCents: 1980,
        paymentMethod: 'bank_transfer',
        requestKey: const Uuid().v4(),
        reference: 'BANK-SETTLE-001',
      );
      expect(
        (await settlements.getStatementPayments(posted.id)).single.id,
        payment.id,
      );
      expect(
        (await (db.select(
          db.consignmentSettlementStatements,
        )..where((row) => row.id.equals(posted.id))).getSingle()).status,
        'paid',
      );
      expect(await accountBalance('2000'), 0);
      expect(
        (await (db.select(
              db.suppliers,
            )..where((row) => row.id.equals(seed.supplier))).getSingle())
            .balanceCents
            .toBigInt()
            .toInt(),
        0,
      );
      report = (await reportService.loadReport(
        range: reportRange,
        supplierId: seed.supplier,
      )).single;
      expect(report.paidCents, 1980);
      expect(report.outstandingPayableCents, 0);

      final linkedJournalIdsBefore = <int>{
        ...(await db.select(db.consignmentObligationEvents).get())
            .map((event) => event.journalEntryId)
            .nonNulls,
        posted.journalEntryId!,
        payment.journalEntryId,
      };
      final consignmentBalancesBeforeRebuild = <String, int>{
        for (final code in ['2000', '2050', '1300', '5300'])
          code: await accountBalance(code),
      };
      final rebuild = LedgerRebuildService(
        db: db,
        accountingRepo: accounting,
        journalService: journal,
      );
      final rebuildReport = await rebuild.rebuild(confirmationToken: true);
      expect(rebuildReport.errors, isEmpty);
      expect(
        rebuildReport.consignmentJournalEntriesRetained,
        linkedJournalIdsBefore.length,
      );
      expect(
        (await db.select(db.journalEntries).get())
            .where((entry) => linkedJournalIdsBefore.contains(entry.id))
            .map((entry) => entry.id)
            .toSet(),
        linkedJournalIdsBefore,
      );
      expect(<String, int>{
        for (final code in consignmentBalancesBeforeRebuild.keys)
          code: await accountBalance(code),
      }, consignmentBalancesBeforeRebuild);
      expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);

      await settlements.reversePayment(
        paymentId: payment.id,
        reason: 'Bank transfer rejected',
      );
      expect(
        (await (db.select(
          db.consignmentSettlementStatements,
        )..where((row) => row.id.equals(posted.id))).getSingle()).status,
        'posted',
      );
      expect(await accountBalance('2000'), 1980);
      final voided = await settlements.voidStatement(
        statementId: posted.id,
        reason: 'Statement review correction',
      );
      expect(voided.status, 'voided');
      expect(await accountBalance('2050'), 1800);
      expect(await accountBalance('2000'), 0);
      expect(await accountBalance('1300'), 0);
      expect(
        (await (db.select(
              db.suppliers,
            )..where((row) => row.id.equals(seed.supplier))).getSingle())
            .balanceCents
            .toBigInt()
            .toInt(),
        0,
      );
      final unassignedEvents = await db
          .select(db.consignmentObligationEvents)
          .get();
      expect(
        unassignedEvents.every(
          (event) => event.settlementStatus == 'unassigned',
        ),
        isTrue,
      );
      expect(
        unassignedEvents.fold<int>(
          0,
          (sum, event) => sum + event.signedAmountCents,
        ),
        1800,
      );
      report = (await reportService.loadReport(
        range: reportRange,
        supplierId: seed.supplier,
      )).single;
      expect(report.postedSettlementCents, 0);
      expect(report.paidCents, 0);
      expect(report.unsettledObligationCents, 1800);
      expect(report.outstandingPayableCents, 0);
      expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
    },
  );
}
