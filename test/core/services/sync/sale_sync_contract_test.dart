import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/database/daos/adjustment_return_dao.dart';
import 'package:tapix/core/services/audit_log_service.dart';
import 'package:tapix/core/services/business/branch_consignment_policy_store.dart';
import 'package:tapix/core/services/business/warehouse_operation_scope.dart';
import 'package:tapix/core/services/commissions/commission_service.dart';
import 'package:tapix/core/services/journal_entry_service.dart';
import 'package:tapix/core/services/loyalty/loyalty_points_service.dart';
import 'package:tapix/core/services/sync/offline_sync_event_store.dart';
import 'package:tapix/core/services/sync/sale_sync_contract.dart';
import 'package:tapix/core/services/sync/sync_entity_identity_store.dart';
import 'package:tapix/features/accounting/data/repositories/accounting_repository.dart';
import 'package:tapix/features/auth/data/services/session_service.dart';
import 'package:tapix/features/consignment/data/consignment_agreement_service.dart';
import 'package:tapix/features/consignment/data/consignment_entitlement.dart';
import 'package:tapix/features/consignment/data/consignment_module_service.dart';
import 'package:tapix/features/consignment/data/consignment_receipt_service.dart';
import 'package:tapix/features/customers/data/repositories/loyalty_repository_impl.dart';
import 'package:tapix/features/sales/data/datasources/sale_local_datasource.dart';
import 'package:tapix/features/sales/data/repositories/sale_repository_impl.dart';
import 'package:tapix/features/sales/domain/repositories/sale_repository.dart';

class _Session extends SessionService {
  _Session(this.userId);
  final int userId;

  @override
  Future<int?> getCurrentUserId() async => userId;
}

class _Fixture {
  const _Fixture({
    required this.db,
    required this.sales,
    required this.currencyId,
    required this.userId,
  });

  final AppDatabase db;
  final SaleRepositoryImpl sales;
  final int currencyId;
  final int userId;
}

Future<_Fixture> _fixture() async {
  final db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
  await db.seedInitialDataForTest();
  final currencyId = (await (db.select(
    db.currencies,
  )..where((row) => row.isBase.equals(true))).getSingle()).id;
  final userId = await db
      .into(db.users)
      .insert(
        UsersCompanion.insert(
          username: 'sale-sync-owner',
          passwordHash: 'test',
          role: 'owner',
          createdAt: DateTime.utc(2026, 9, 25),
          updatedAt: DateTime.utc(2026, 9, 25),
        ),
      );
  final journal = JournalEntryService(AccountingRepository(db));
  final loyalty = LoyaltyRepositoryImpl(db, journal);
  final sales = SaleRepositoryImpl(
    SaleLocalDatasourceImpl(db.saleDao, AdjustmentReturnDao(db)),
    db.saleDao,
    journal,
    AuditLogService(db),
    _Session(userId),
    loyalty,
    CommissionService(db.employeeDao),
    LoyaltyPointsService(loyalty, journal, db),
  );
  return _Fixture(db: db, sales: sales, currencyId: currencyId, userId: userId);
}

Future<(int, int)> _product(
  _Fixture fixture, {
  required String name,
  bool tracked = true,
  int stock = 5,
}) async {
  final productId = await fixture.db
      .into(fixture.db.products)
      .insert(
        ProductsCompanion.insert(
          name: name,
          currencyId: Value(fixture.currencyId),
          stockQuantity: Value(stock),
          costCents: Decimal.fromInt(600),
          priceCents: Decimal.fromInt(1000),
          trackInventory: Value(tracked),
        ),
      );
  final variantId = await fixture.db
      .into(fixture.db.productVariants)
      .insert(
        ProductVariantsCompanion.insert(
          productId: productId,
          stockQuantity: Value(stock),
          costCents: Decimal.fromInt(600),
          priceCents: Decimal.fromInt(1000),
        ),
      );
  return (productId, variantId);
}

Future<int> _sell(
  _Fixture fixture, {
  required int productId,
  required int variantId,
  required String key,
  String? consignmentLayerId,
}) => fixture.sales.createSale(
  currencyId: fixture.currencyId,
  subtotalCents: Decimal.fromInt(2000),
  discountCents: Decimal.fromInt(100),
  taxCents: Decimal.fromInt(190),
  totalCents: Decimal.fromInt(2090),
  paidAmountCents: Decimal.fromInt(2090),
  paymentMethod: 'cash',
  saleDate: DateTime.utc(2026, 9, 25, 12),
  idempotencyKey: key,
  actorUserId: fixture.userId,
  taxInclusiveAtPost: false,
  items: [
    SaleItemInput(
      lineId: 'line-1',
      productId: productId,
      variantId: variantId,
      consignmentLayerId: consignmentLayerId,
      quantity: 2,
      unitPriceCents: Decimal.fromInt(1000),
      subtotalCents: Decimal.fromInt(2000),
      discountCents: Decimal.fromInt(100),
      itemDiscountAtPostCents: Decimal.fromInt(100),
      invoiceDiscountAtPostCents: Decimal.zero,
      taxCents: Decimal.fromInt(190),
      totalCents: Decimal.fromInt(2090),
    ),
  ],
);

Future<int> _returnOne(
  _Fixture fixture, {
  required int saleId,
  required String key,
  String dispositionType = 'restock',
}) async {
  final saleItem = await (fixture.db.select(
    fixture.db.saleItems,
  )..where((row) => row.saleId.equals(saleId))).getSingle();
  return fixture.sales.createSaleReturn(
    saleId: saleId,
    currencyId: fixture.currencyId,
    subtotalCents: Decimal.zero,
    discountCents: Decimal.zero,
    taxCents: Decimal.zero,
    totalCents: Decimal.zero,
    items: [
      SaleReturnItemInput(
        saleItemId: saleItem.id,
        quantity: 1,
        subtotalCents: Decimal.zero,
        discountCents: Decimal.zero,
        taxCents: Decimal.zero,
        refundCents: Decimal.zero,
      ),
    ],
    dispositionType: dispositionType,
    refundMethod: 'cash',
    returnDate: DateTime.utc(2026, 9, 25, 13),
    idempotencyKey: key,
    actorUserId: fixture.userId,
  );
}

void main() {
  test('single-branch sale does not create a cloud outbox event', () async {
    final fixture = await _fixture();
    addTearDown(fixture.db.close);
    final ids = await _product(fixture, name: 'Local-only item');
    final saleId = await _sell(
      fixture,
      productId: ids.$1,
      variantId: ids.$2,
      key: 'sale-sync-local-only',
    );
    await _returnOne(
      fixture,
      saleId: saleId,
      key: 'sale-return-sync-local-only',
    );

    final count = await fixture.db
        .customSelect('SELECT COUNT(*) AS c FROM sync_outbox_events')
        .map((row) => row.read<int>('c'))
        .getSingle();
    expect(count, 0);
  });

  test(
    'online writer appends one atomic sale event and retry is idempotent',
    () async {
      final fixture = await _fixture();
      addTearDown(fixture.db.close);
      await OfflineSyncEventStore(fixture.db).activateWriterRecording(
        enrollmentId: '20202020-2020-4020-8020-202020202020',
      );
      final ids = await _product(fixture, name: 'Online item');
      final saleId = await _sell(
        fixture,
        productId: ids.$1,
        variantId: ids.$2,
        key: 'sale-sync-online',
      );
      final replayed = await _sell(
        fixture,
        productId: ids.$1,
        variantId: ids.$2,
        key: 'sale-sync-online',
      );
      expect(replayed, saleId);

      final events = await fixture.db
          .customSelect(
            'SELECT event_type,aggregate_type,payload_json FROM sync_outbox_events ORDER BY local_sequence',
          )
          .get();
      expect(events, hasLength(1));
      expect(events.single.read<String>('event_type'), 'sale.posted.v1');
      expect(events.single.read<String>('aggregate_type'), 'sale');
      final payload =
          jsonDecode(events.single.read<String>('payload_json'))
              as Map<String, dynamic>;
      expect(payload['contract'], 'sale.posted');
      expect(payload['totalMinor'], 2090);
      expect(payload['actorRef']['localId'], fixture.userId);
    },
  );

  test(
    'posted WAC sale carries immutable money and explicit unknown origin',
    () async {
      final fixture = await _fixture();
      addTearDown(fixture.db.close);
      final ids = await _product(fixture, name: 'WAC item');
      final saleId = await _sell(
        fixture,
        productId: ids.$1,
        variantId: ids.$2,
        key: 'sale-sync-wac',
      );
      final sale = await (fixture.db.select(
        fixture.db.sales,
      )..where((row) => row.id.equals(saleId))).getSingle();

      final payload = await SaleSyncContractBuilder(
        fixture.db,
        SyncEntityIdentityStore(fixture.db),
      ).buildPostedSale(sale: sale, actorUserId: fixture.userId);

      expect(payload['contract'], 'sale.posted');
      expect(payload['invoiceNumber'], sale.invoiceNumber);
      expect(payload['subtotalMinor'], 2000);
      expect(payload['discountMinor'], 100);
      expect(payload['taxMinor'], 190);
      expect(payload['totalMinor'], 2090);
      expect(payload['ownedInventoryValueMinor'], 1200);
      expect((payload['documentId']! as String), hasLength(36));
      expect(payload.containsKey('customerGlobalId'), isFalse);

      final lines = payload['items']! as List<Object?>;
      final line = lines.single! as Map<String, Object?>;
      expect(line['quantityScaled'], 2);
      expect(line['inventorySourceMode'], 'wac_origin');
      expect(line['ownedInventoryValueMinor'], 1200);
      expect(line['consignmentQuantityScaled'], 0);
      final origins = line['originSlices']! as List<Object?>;
      final origin = origins.single! as Map<String, Object?>;
      expect(origin['quantityScaled'], 2);
      expect(origin['originKind'], 'unknown');
      expect(origin['sourceQuality'], 'unverified');
      expect(origin.containsKey('supplierGlobalId'), isTrue);
      expect(origin['supplierGlobalId'], isNull);
      expect(line.containsKey('productId'), isFalse);
      expect(line.containsKey('variantId'), isFalse);
    },
  );

  test(
    'linked restock return appends an atomic event after its source sale',
    () async {
      final fixture = await _fixture();
      addTearDown(fixture.db.close);
      await OfflineSyncEventStore(fixture.db).activateWriterRecording(
        enrollmentId: '30303030-3030-4030-8030-303030303030',
      );
      final ids = await _product(fixture, name: 'Returned WAC item');
      final saleId = await _sell(
        fixture,
        productId: ids.$1,
        variantId: ids.$2,
        key: 'sale-sync-return-source',
      );
      final returnId = await _returnOne(
        fixture,
        saleId: saleId,
        key: 'sale-sync-linked-return',
      );

      final events = await fixture.db
          .customSelect(
            'SELECT event_type,aggregate_type,payload_json '
            'FROM sync_outbox_events ORDER BY local_sequence',
          )
          .get();
      expect(events, hasLength(2));
      expect(events.first.read<String>('event_type'), 'sale.posted.v1');
      expect(events.last.read<String>('event_type'), 'sale_return.posted.v1');
      expect(events.last.read<String>('aggregate_type'), 'sale_return');
      final payload =
          jsonDecode(events.last.read<String>('payload_json'))
              as Map<String, dynamic>;
      expect(payload['contract'], 'sale_return.posted');
      expect(payload['sourceDocumentRef']['localId'], returnId);
      expect(payload['originalSaleRef']['localId'], saleId);
      expect(payload['restoresSellableStock'], isTrue);
      expect(payload['subtotalMinor'], 1000);
      expect(payload['discountMinor'], 50);
      expect(payload['taxMinor'], 95);
      expect(payload['totalMinor'], 1045);
      expect(payload['ownedInventoryValueMinor'], 600);
      final line =
          (payload['items'] as List<dynamic>).single as Map<String, dynamic>;
      expect(line['quantityScaled'], 1);
      expect(line['inventoryEffect'], 'wac_origin_restored');
      expect(line['originSlices'], hasLength(1));
      expect(line['consignmentQuantityScaled'], 0);
    },
  );

  test('damaged linked return never advertises sellable stock', () async {
    final fixture = await _fixture();
    addTearDown(fixture.db.close);
    await OfflineSyncEventStore(fixture.db).activateWriterRecording(
      enrollmentId: '40404040-4040-4040-8040-404040404040',
    );
    final ids = await _product(fixture, name: 'Damaged return item');
    final saleId = await _sell(
      fixture,
      productId: ids.$1,
      variantId: ids.$2,
      key: 'sale-sync-damaged-source',
    );
    await _returnOne(
      fixture,
      saleId: saleId,
      key: 'sale-sync-damaged-return',
      dispositionType: 'damaged',
    );

    final row = await fixture.db
        .customSelect(
          'SELECT payload_json FROM sync_outbox_events '
          "WHERE event_type='sale_return.posted.v1'",
        )
        .getSingle();
    final payload =
        jsonDecode(row.read<String>('payload_json')) as Map<String, dynamic>;
    expect(payload['restoresSellableStock'], isFalse);
    final line =
        (payload['items'] as List<dynamic>).single as Map<String, dynamic>;
    expect(line['inventoryEffect'], 'not_restocked');
    expect(line['originSlices'], isEmpty);
    expect(line['batchRestorations'], isEmpty);
    expect(line['ownedInventoryValueMinor'], 600);
  });

  test(
    'linked consignment return carries supplier obligation reversal',
    () async {
      final fixture = await _fixture();
      addTearDown(fixture.db.close);
      final ids = await _product(fixture, name: 'Consignment sync item');
      final supplierId = await fixture.db
          .into(fixture.db.suppliers)
          .insert(
            SuppliersCompanion.insert(
              name: 'Consignment sync supplier',
              currencyId: fixture.currencyId,
            ),
          );
      final module = ConsignmentModuleService(
        fixture.db,
        _Session(fixture.userId),
        const GrantedConsignmentEntitlement(),
        BranchConsignmentPolicyStore(fixture.db),
        isRemoteClient: () => false,
      );
      await module.initialize();
      await module.setEnabled(enabled: true, reason: 'sale sync contract test');
      final agreement = await ConsignmentAgreementService(fixture.db, module)
          .createDraft(
            supplierId: supplierId,
            currencyId: fixture.currencyId,
            agreementNumber: 'CON-SYNC-001',
            effectiveFrom: DateTime.utc(2026, 9, 1),
            terms: [
              ConsignmentAgreementTermInput.fixedCost(
                productId: ids.$1,
                variantId: ids.$2,
                amountCents: 700,
              ),
            ],
          );
      await ConsignmentAgreementService(
        fixture.db,
        module,
      ).activate(agreement.id);
      final scope = await WarehouseOperationScope.resolve(fixture.db);
      final receiptService = ConsignmentReceiptService(fixture.db, module);
      final receipt = await receiptService.createDraft(
        requestKey: const Uuid().v4(),
        receiptNumber: 'CR-SYNC-001',
        warehouseId: scope.warehouseId,
        supplierId: supplierId,
        agreementId: agreement.id,
        currencyId: fixture.currencyId,
        receivedAt: DateTime.utc(2026, 9, 24),
        lines: [
          ConsignmentReceiptLineInput(
            productId: ids.$1,
            variantId: ids.$2,
            quantity: 2,
          ),
        ],
      );
      await receiptService.post(
        receiptId: receipt.id,
        requestKey: const Uuid().v4(),
      );
      final layer =
          (await fixture.db.select(fixture.db.consignmentInventoryLayers).get())
              .single;
      await OfflineSyncEventStore(fixture.db).activateWriterRecording(
        enrollmentId: '50505050-5050-4050-8050-505050505050',
      );
      final saleId = await _sell(
        fixture,
        productId: ids.$1,
        variantId: ids.$2,
        key: 'sale-sync-consignment-source',
        consignmentLayerId: layer.id,
      );
      await _returnOne(
        fixture,
        saleId: saleId,
        key: 'sale-sync-consignment-return',
      );

      final row = await fixture.db
          .customSelect(
            'SELECT payload_json FROM sync_outbox_events '
            "WHERE event_type='sale_return.posted.v1'",
          )
          .getSingle();
      final payload =
          jsonDecode(row.read<String>('payload_json')) as Map<String, dynamic>;
      final line =
          (payload['items'] as List<dynamic>).single as Map<String, dynamic>;
      expect(line['consignmentQuantityScaled'], 1);
      final reversal =
          (line['consignmentReversals'] as List<dynamic>).single
              as Map<String, dynamic>;
      expect(reversal['signedQuantityScaled'], -1);
      expect(reversal['signedObligationMinor'], -700);
      expect(reversal['restoresSellableStock'], isTrue);
      expect(reversal['supplierGlobalId'], isNotEmpty);
      expect(reversal['journalRef'], isNotNull);
    },
  );

  test(
    'non-inventory sale is explicit and needs no fabricated source',
    () async {
      final fixture = await _fixture();
      addTearDown(fixture.db.close);
      final ids = await _product(
        fixture,
        name: 'Service',
        tracked: false,
        stock: 0,
      );
      final saleId = await _sell(
        fixture,
        productId: ids.$1,
        variantId: ids.$2,
        key: 'sale-sync-service',
      );
      final sale = await (fixture.db.select(
        fixture.db.sales,
      )..where((row) => row.id.equals(saleId))).getSingle();

      final payload = await SaleSyncContractBuilder(
        fixture.db,
        SyncEntityIdentityStore(fixture.db),
      ).buildPostedSale(sale: sale, actorUserId: fixture.userId);
      final line =
          ((payload['items']! as List<Object?>).single!
              as Map<String, Object?>);

      expect(line['inventorySourceMode'], 'not_tracked');
      expect(line['originSlices'], isEmpty);
      expect(line['batchConsumptions'], isEmpty);
      expect(line['ownedInventoryValueMinor'], 0);
      expect(payload['ownedInventoryValueMinor'], 0);
    },
  );
}
