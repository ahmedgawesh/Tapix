import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/services/business/branch_consignment_policy_store.dart';
import 'package:tapix/core/services/business/warehouse_operation_scope.dart';
import 'package:tapix/core/services/inventory/inventory_stock_source_service.dart';
import 'package:tapix/core/services/journal_entry_service.dart';
import 'package:tapix/core/services/sync/branch_catalogue_sync_service.dart';
import 'package:tapix/core/services/sync/branch_operational_projection_service.dart';
import 'package:tapix/core/services/sync/offline_sync_event_store.dart';
import 'package:tapix/core/services/sync/sync_entity_identity_store.dart';
import 'package:tapix/core/services/sync/sync_inbound_projection_service.dart';
import 'package:tapix/features/business/data/distributed_transfer_receipt_service.dart';
import 'package:tapix/features/auth/data/services/session_service.dart';
import 'package:tapix/features/consignment/data/consignment_agreement_service.dart';
import 'package:tapix/features/consignment/data/consignment_custody_service.dart';
import 'package:tapix/features/consignment/data/consignment_entitlement.dart';
import 'package:tapix/features/consignment/data/consignment_module_service.dart';
import 'package:tapix/features/consignment/data/consignment_receipt_service.dart';
import 'package:tapix/features/accounting/data/repositories/accounting_repository.dart';

const sourceDatabaseId = '11111111-1111-4111-8111-111111111111';
const sourceBranchId = '22222222-2222-4222-8222-222222222222';
const sourceWarehouseId = '33333333-3333-4333-8333-333333333333';
const transferId = '44444444-4444-4444-8444-444444444444';
const allocationId = '55555555-5555-4555-8555-555555555555';
const productGlobalId = '66666666-6666-4666-8666-666666666666';
const variantGlobalId = '77777777-7777-4777-8777-777777777777';
const supplierGlobalId = '88888888-8888-4888-8888-888888888888';
const snapshotId = '99999999-9999-4999-8999-999999999999';
const consignmentTransferId = '16161616-1616-4161-8161-161616161616';
const consignmentAllocationId = '17171717-1717-4171-8171-171717171717';
const sourceAgreementId = '18181818-1818-4181-8181-181818181818';
const sourceLayerId = '19191919-1919-4191-8191-191919191919';

class _Session extends SessionService {
  _Session(this.actor);
  final int actor;

  @override
  Future<int?> getCurrentUserId() async => actor;
}

void main() {
  late AppDatabase db;
  late OfflineSyncEventStore events;
  late SyncInboundProjectionService inbound;
  late DistributedTransferReceiptService receipts;
  late String organizationId;
  late String warehouseId;
  late int actorId;

  setUp(() async {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    await db.customSelect('SELECT 1').get();
    final context = await db
        .customSelect('SELECT * FROM business_contexts WHERE id=1')
        .getSingle();
    organizationId = context.read<String>('organization_id');
    warehouseId = context.read<String>('warehouse_id');
    actorId = await db.customInsert(
      '''INSERT INTO users(username,password_hash,role,is_active,created_at,updated_at)
      VALUES('distributed-owner','x','owner',1,0,0)''',
    );
    events = OfflineSyncEventStore(db);
    await events.activateWriterRecording(
      enrollmentId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    );
    await events.enrollSource(
      sourceDatabaseId: sourceDatabaseId,
      organizationId: organizationId,
      branchId: sourceBranchId,
    );
    await db.customStatement(
      '''INSERT INTO app_settings(key,value)
      VALUES('lan.branch_sync.coordinator_database_id.v1',?)
      ON CONFLICT(key) DO UPDATE SET value=excluded.value''',
      [sourceDatabaseId],
    );
    final catalogue = BranchCatalogueSyncService(
      db,
      events,
      SyncEntityIdentityStore(db),
    );
    inbound = SyncInboundProjectionService(
      db,
      events,
      operationalProjector: BranchOperationalProjectionService(
        db,
        catalogue: catalogue,
      ).apply,
    );
    receipts = DistributedTransferReceiptService(
      db,
      authorizeWarehouse: (selected) async {
        expect(selected, warehouseId);
        return actorId;
      },
      syncEvents: events,
    );
    await _bootstrapCatalogue(inbound, organizationId, warehouseId);
  });

  tearDown(() => db.close());

  test('partial receipt is atomic idempotent and posts stock WAC and journal', () async {
    expect((await receipts.pending(transferId)).single.remainingQuantity, 2);

    await expectLater(
      receipts.receive(
        transferId: transferId,
        requestKey: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
        items: const [
          DistributedTransferReceiptItemRequest(
            allocationId: allocationId,
            acceptedQuantity: 3,
          ),
        ],
      ),
      throwsA(isA<StateError>()),
    );

    final first = await receipts.receive(
      transferId: transferId,
      requestKey: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
      items: const [
        DistributedTransferReceiptItemRequest(
          allocationId: allocationId,
          acceptedQuantity: 1,
        ),
      ],
    );
    expect(first.completed, isFalse);
    expect(first.acceptedOwnedValueMinor, 625);
    expect((await receipts.pending(transferId)).single.remainingQuantity, 1);

    final replay = await receipts.receive(
      transferId: transferId,
      requestKey: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
      items: const [
        DistributedTransferReceiptItemRequest(
          allocationId: allocationId,
          acceptedQuantity: 1,
        ),
      ],
    );
    expect(replay.receiptId, first.receiptId);

    final local = await db
        .customSelect(
          '''SELECT p.id AS product_id,v.id AS variant_id,p.cost_cents,
            v.cost_cents AS variant_cost,s.quantity
            FROM sync_entity_identities pi
            JOIN products p ON p.id=pi.local_id AND pi.entity_type='product'
            JOIN sync_entity_identities vi ON vi.entity_type='product_variant'
            JOIN product_variants v ON v.id=vi.local_id AND v.product_id=p.id
            JOIN business_warehouse_stocks s ON s.variant_id=v.id AND s.warehouse_id=?
            WHERE pi.global_id=? AND vi.global_id=?''',
          variables: [
            Variable.withString(warehouseId),
            Variable.withString(productGlobalId),
            Variable.withString(variantGlobalId),
          ],
        )
        .getSingle();
    expect(local.read<int>('quantity'), 1);
    expect(local.read<int>('cost_cents'), 625);
    expect(local.read<int>('variant_cost'), 625);
    expect(
      await db
          .customSelect(
            "SELECT COUNT(*) AS n FROM journal_entries WHERE source_table='distributed_transfer_inbound_receipts' AND status='posted'",
          )
          .map((row) => row.read<int>('n'))
          .getSingle(),
      1,
    );
    expect(
      await db
          .customSelect(
            "SELECT total_debit_cents FROM journal_entries WHERE source_table='distributed_transfer_inbound_receipts'",
          )
          .map((row) => row.read<int>('total_debit_cents'))
          .getSingle(),
      625,
    );
    expect(
      await db
          .customSelect(
            "SELECT COUNT(*) AS n FROM sync_outbox_events WHERE event_type='warehouse_transfer.received.v1'",
          )
          .map((row) => row.read<int>('n'))
          .getSingle(),
      1,
    );

    final finalReceipt = await receipts.receive(
      transferId: transferId,
      requestKey: 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
      notes: 'Damaged during transport',
      items: const [
        DistributedTransferReceiptItemRequest(
          allocationId: allocationId,
          damagedQuantity: 1,
        ),
      ],
    );
    expect(finalReceipt.completed, isTrue);
    expect(finalReceipt.varianceOwnedValueMinor, 625);
    expect(await receipts.pending(transferId), isEmpty);
    expect(
      await db
          .customSelect(
            'SELECT lifecycle_state FROM distributed_transfer_inbound_dispatches WHERE transfer_id=?',
            variables: [Variable.withString(transferId)],
          )
          .map((row) => row.read<String>('lifecycle_state'))
          .getSingle(),
      'completed',
    );
    expect(
      await db
          .customSelect(
            'SELECT quantity FROM business_warehouse_stocks WHERE warehouse_id=? AND variant_id=?',
            variables: [
              Variable.withString(warehouseId),
              Variable.withInt(local.read<int>('variant_id')),
            ],
          )
          .map((row) => row.read<int>('quantity'))
          .getSingle(),
      1,
    );
    expect(
      await db
          .customSelect(
            "SELECT COUNT(*) AS n FROM sync_outbox_events WHERE event_type='warehouse_transfer.received.v1'",
          )
          .map((row) => row.read<int>('n'))
          .getSingle(),
      2,
    );
  });

  test(
    'owned receipt preserves supplier without requiring a supplier barcode code',
    () async {
      await db.customStatement('UPDATE suppliers SET product_code=NULL');

      final result = await receipts.receive(
        transferId: transferId,
        requestKey: '30303030-3030-4030-8030-303030303030',
        items: const [
          DistributedTransferReceiptItemRequest(
            allocationId: allocationId,
            acceptedQuantity: 2,
          ),
        ],
      );

      expect(result.completed, isTrue);
      expect(
        await db
            .customSelect(
              'SELECT COUNT(*) AS n FROM supplier_product_identities',
            )
            .map((row) => row.read<int>('n'))
            .getSingle(),
        0,
      );
      final local = await db
          .customSelect(
            '''SELECT p.id AS product_id,v.id AS variant_id
            FROM sync_entity_identities pi
            JOIN products p ON p.id=pi.local_id AND pi.entity_type='product'
            JOIN sync_entity_identities vi ON vi.entity_type='product_variant'
            JOIN product_variants v ON v.id=vi.local_id AND v.product_id=p.id
            WHERE pi.global_id=? AND vi.global_id=?''',
            variables: [
              Variable.withString(productGlobalId),
              Variable.withString(variantGlobalId),
            ],
          )
          .getSingle();
      final snapshot = await InventoryStockSourceService(db).loadProduct(
        local.read<int>('product_id'),
        variantId: local.read<int>('variant_id'),
        scope: await WarehouseOperationScope.resolveForOrganization(
          db,
          warehouseId: warehouseId,
        ),
      );
      expect(snapshot.sources, hasLength(1));
      expect(snapshot.sources.single.supplierName, 'Source supplier');
      expect(snapshot.sources.single.sourceCode, null);
      expect(snapshot.sources.single.quantity, 2);
    },
  );

  test(
    'consignment receipt mirrors terms and preserves supplier ownership',
    () async {
      await inbound.apply(
        _consignmentDispatchEvent(
          sequence: 5,
          eventId: '20202020-2020-4020-8020-202020202020',
          organizationId: organizationId,
          destinationWarehouseId: warehouseId,
        ),
      );
      final policy = BranchConsignmentPolicyStore(db);
      final module = ConsignmentModuleService(
        db,
        _Session(actorId),
        const GrantedConsignmentEntitlement(),
        policy,
        isRemoteClient: () => false,
      );
      await module.initialize();
      await module.setEnabled(
        enabled: true,
        reason: 'Distributed custody test',
      );
      final agreements = ConsignmentAgreementService(db, module);
      final consignmentReceipts = ConsignmentReceiptService(db, module);
      final service = DistributedTransferReceiptService(
        db,
        authorizeWarehouse: (_) async => actorId,
        syncEvents: events,
        consignmentAgreements: agreements,
        consignmentReceipts: consignmentReceipts,
        consignmentCustody: ConsignmentCustodyService(
          db,
          module,
          JournalEntryService(AccountingRepository(db)),
        ),
      );

      final result = await service.receive(
        transferId: consignmentTransferId,
        requestKey: '21212121-2121-4121-8121-212121212121',
        notes: 'Damaged in transit; supplier accepted responsibility',
        items: const [
          DistributedTransferReceiptItemRequest(
            allocationId: consignmentAllocationId,
            acceptedQuantity: 1,
            damagedQuantity: 1,
            varianceResponsibility: 'supplier',
          ),
        ],
      );
      expect(result.completed, isTrue);
      expect(result.acceptedOwnedValueMinor, 0);
      expect(
        await db
            .customSelect(
              'SELECT quantity,supplier_owned_quantity '
              'FROM business_warehouse_stocks s '
              'JOIN sync_entity_identities i ON i.local_id=s.variant_id '
              "AND i.entity_type='product_variant' "
              'WHERE s.warehouse_id=? AND i.global_id=?',
              variables: [
                Variable.withString(warehouseId),
                Variable.withString(variantGlobalId),
              ],
            )
            .map(
              (row) => (
                quantity: row.read<int>('quantity'),
                supplierOwned: row.read<int>('supplier_owned_quantity'),
              ),
            )
            .getSingle(),
        (quantity: 1, supplierOwned: 1),
      );
      expect(
        await db
            .customSelect(
              'SELECT remaining_quantity FROM consignment_inventory_layers',
            )
            .map((row) => row.read<int>('remaining_quantity'))
            .getSingle(),
        1,
      );
      expect(
        await db
            .customSelect(
              'SELECT COUNT(*) AS n FROM distributed_consignment_agreement_mirrors',
            )
            .map((row) => row.read<int>('n'))
            .getSingle(),
        1,
      );
      expect(
        await db
            .customSelect(
              "SELECT COUNT(*) AS n FROM consignment_custody_documents WHERE document_type='damage' AND responsibility='supplier' AND status='posted'",
            )
            .map((row) => row.read<int>('n'))
            .getSingle(),
        1,
      );
      expect(
        await db
            .customSelect(
              'SELECT COUNT(*) AS n FROM distributed_consignment_layer_links',
            )
            .map((row) => row.read<int>('n'))
            .getSingle(),
        1,
      );
    },
  );
}

Future<void> _bootstrapCatalogue(
  SyncInboundProjectionService inbound,
  String organizationId,
  String warehouseId,
) async {
  await inbound.apply(
    _catalogueEvent(
      sequence: 1,
      eventId: 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
      organizationId: organizationId,
      entityType: 'supplier',
      entities: const [
        {
          'globalId': supplierGlobalId,
          'originDatabaseId': sourceDatabaseId,
          'name': 'Source supplier',
          'productCode': 'SRC',
          'email': null,
          'phone': null,
          'address': null,
          'defaultSupplyMode': 'mixed',
          'currencyCode': 'USD',
          'isActive': true,
        },
      ],
    ),
  );
  await inbound.apply(
    _catalogueEvent(
      sequence: 2,
      eventId: 'ffffffff-ffff-4fff-8fff-ffffffffffff',
      organizationId: organizationId,
      entityType: 'product',
      entities: const [
        {
          'globalId': productGlobalId,
          'originDatabaseId': sourceDatabaseId,
          'sku': 'DIST-1',
          'barcode': '9876543210123',
          'name': 'Distributed item',
          'nameAr': null,
          'nameFr': null,
          'description': null,
          'supplierGlobalId': supplierGlobalId,
          'referenceCostMinor': 500,
          'priceMinor': 900,
          'wholesalePriceMinor': null,
          'currencyCode': 'USD',
          'trackInventory': true,
          'measurementType': 'piece',
          'minimumQuantityScaled': 0,
          'hasVariants': false,
          'isTaxable': false,
          'purchaseTaxRateBps': 0,
          'salesTaxRateBps': 0,
          'costingMethod': 'wac',
          'inventoryTrackingType': 'standard',
          'isActive': true,
        },
      ],
    ),
  );
  await inbound.apply(
    _catalogueEvent(
      sequence: 3,
      eventId: '12121212-1212-4121-8121-121212121212',
      organizationId: organizationId,
      entityType: 'variant',
      entities: const [
        {
          'globalId': variantGlobalId,
          'originDatabaseId': sourceDatabaseId,
          'productGlobalId': productGlobalId,
          'sku': 'DIST-1-V',
          'barcode': null,
          'referenceCostMinor': 500,
          'priceMinor': 900,
          'wholesalePriceMinor': null,
          'priceAdjustmentMinor': 0,
          'isActive': true,
        },
      ],
    ),
  );
  await inbound.apply(
    _dispatchEvent(
      sequence: 4,
      eventId: '13131313-1313-4131-8131-131313131313',
      organizationId: organizationId,
      destinationWarehouseId: warehouseId,
    ),
  );
}

SyncEventEnvelope _catalogueEvent({
  required int sequence,
  required String eventId,
  required String organizationId,
  required String entityType,
  required List<Map<String, Object?>> entities,
}) => _signed(
  eventId: eventId,
  sequence: sequence,
  organizationId: organizationId,
  eventType: BranchCatalogueSyncService.eventType,
  aggregateType: 'catalogue_snapshot',
  aggregateId: snapshotId,
  payload: {
    'contract': 'catalogue.snapshot_page',
    'contractVersion': 1,
    'snapshotId': snapshotId,
    'organizationId': organizationId,
    'sourceDatabaseId': sourceDatabaseId,
    'sourceBranchId': sourceBranchId,
    'entityType': entityType,
    'pageIndex': 0,
    'pageCount': 1,
    'entities': entities,
  },
);

SyncEventEnvelope _dispatchEvent({
  required int sequence,
  required String eventId,
  required String organizationId,
  required String destinationWarehouseId,
}) => _signed(
  eventId: eventId,
  sequence: sequence,
  organizationId: organizationId,
  eventType: 'warehouse_transfer.dispatched.v1',
  aggregateType: 'warehouse_transfer',
  aggregateId: transferId,
  payload: {
    'contract': 'warehouse_transfer.dispatched',
    'contractVersion': 1,
    'transferId': transferId,
    'requestKey': '14141414-1414-4141-8141-141414141414',
    'organizationId': organizationId,
    'branchId': sourceBranchId,
    'sourceDatabaseId': sourceDatabaseId,
    'sourceWarehouseId': sourceWarehouseId,
    'destinationWarehouseId': destinationWarehouseId,
    'currencyCode': 'USD',
    'dispatchedAt': DateTime.utc(2026, 9, 28, 10).toIso8601String(),
    'ownedValueMinor': 1250,
    'allocationCount': 1,
    'allocations': const [
      {
        'allocationId': allocationId,
        'lineId': '15151515-1515-4151-8151-151515151515',
        'sequence': 1,
        'productGlobalId': productGlobalId,
        'variantGlobalId': variantGlobalId,
        'ownerType': 'owned',
        'quantityScaled': 2,
        'quantityScale': 1,
        'measurementType': 'piece',
        'unitCostMinor': 625,
        'valueMinor': 1250,
        'supplierGlobalId': supplierGlobalId,
        'originSlices': [
          {
            'quantityScaled': 2,
            'originKind': 'purchase',
            'supplierGlobalId': supplierGlobalId,
            'sourceReference': 'purchase:remote:1',
            'sourceQuality': 'documented',
          },
        ],
      },
    ],
  },
);

SyncEventEnvelope _consignmentDispatchEvent({
  required int sequence,
  required String eventId,
  required String organizationId,
  required String destinationWarehouseId,
}) => _signed(
  eventId: eventId,
  sequence: sequence,
  organizationId: organizationId,
  eventType: 'warehouse_transfer.dispatched.v1',
  aggregateType: 'warehouse_transfer',
  aggregateId: consignmentTransferId,
  payload: {
    'contract': 'warehouse_transfer.dispatched',
    'contractVersion': 1,
    'transferId': consignmentTransferId,
    'requestKey': '23232323-2323-4232-8232-232323232323',
    'organizationId': organizationId,
    'branchId': sourceBranchId,
    'sourceDatabaseId': sourceDatabaseId,
    'sourceWarehouseId': sourceWarehouseId,
    'destinationWarehouseId': destinationWarehouseId,
    'currencyCode': 'USD',
    'dispatchedAt': DateTime.utc(2026, 9, 28, 10).toIso8601String(),
    'ownedValueMinor': 0,
    'allocationCount': 1,
    'allocations': [
      {
        'allocationId': consignmentAllocationId,
        'lineId': '24242424-2424-4242-8242-242424242424',
        'sequence': 1,
        'productGlobalId': productGlobalId,
        'variantGlobalId': variantGlobalId,
        'ownerType': 'consignment',
        'quantityScaled': 2,
        'quantityScale': 1,
        'measurementType': 'piece',
        'unitCostMinor': 500,
        'valueMinor': 0,
        'supplierGlobalId': supplierGlobalId,
        'consignmentAgreementId': sourceAgreementId,
        'sourceConsignmentLayerId': sourceLayerId,
        'consignmentTerms': {
          'sourceAgreementId': sourceAgreementId,
          'agreementKey': '25252525-2525-4252-8252-252525252525',
          'revision': 1,
          'agreementNumber': 'SOURCE-CONSIGNMENT',
          'supplierGlobalId': supplierGlobalId,
          'settlementFrequency': 'monthly',
          'paymentTermsDays': 14,
          'settlementTaxRateBps': 0,
          'settlementTaxInclusive': false,
          'effectiveFrom': DateTime.utc(2026, 1, 1).toIso8601String(),
          'terms': const [
            {
              'productGlobalId': productGlobalId,
              'variantGlobalId': variantGlobalId,
              'settlementBasis': 'fixed_unit_cost',
              'unitCostMinor': 500,
              'supplierShareBps': null,
              'includeLineDiscount': true,
              'includeInvoiceDiscount': true,
              'includeSalesTax': false,
            },
          ],
        },
      },
    ],
  },
);

SyncEventEnvelope _signed({
  required String eventId,
  required int sequence,
  required String organizationId,
  required String eventType,
  required String aggregateType,
  required String aggregateId,
  required Map<String, Object?> payload,
}) {
  final draft = SyncEventEnvelope(
    eventId: eventId,
    sourceDatabaseId: sourceDatabaseId,
    organizationId: organizationId,
    branchId: sourceBranchId,
    sequence: sequence,
    eventType: eventType,
    aggregateType: aggregateType,
    aggregateId: aggregateId,
    contractVersion: 1,
    payload: payload,
    occurredAt: DateTime.utc(2026, 9, 28, 9, sequence),
    eventHash: '',
  );
  return SyncEventEnvelope(
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
  );
}
