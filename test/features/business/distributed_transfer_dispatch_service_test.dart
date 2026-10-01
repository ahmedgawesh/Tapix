import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/services/business/branch_currency_policy_store.dart';
import 'package:tapix/core/services/business/warehouse_operation_scope.dart';
import 'package:tapix/core/services/stock_service.dart';
import 'package:tapix/core/services/sync/offline_sync_event_store.dart';
import 'package:tapix/features/business/data/distributed_transfer_dispatch_service.dart';

void main() {
  late AppDatabase db;
  late WarehouseOperationScope source;
  late DistributedTransferDispatchService service;
  late int productId;
  late int variantId;

  const remoteDatabase = '11111111-1111-4111-8111-111111111111';
  const remoteBranch = '22222222-2222-4222-8222-222222222222';
  const remoteWarehouse = '33333333-3333-4333-8333-333333333333';

  setUp(() async {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    source = await WarehouseOperationScope.resolve(db);
    final currency = await (db.select(
      db.currencies,
    )..where((row) => row.code.equals('USD'))).getSingle();
    final actor = await db
        .into(db.users)
        .insert(
          UsersCompanion.insert(
            username: 'distributed-transfer-owner',
            passwordHash: 'x',
            role: 'owner',
            createdAt: DateTime.utc(2026, 9, 28),
            updatedAt: DateTime.utc(2026, 9, 28),
          ),
        );
    productId = await db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            name: 'Distributed WAC item',
            currencyId: Value(currency.id),
            costCents: Decimal.fromInt(1000),
            priceCents: Decimal.fromInt(1500),
          ),
        );
    variantId = await db
        .into(db.productVariants)
        .insert(
          ProductVariantsCompanion.insert(
            productId: productId,
            costCents: Decimal.fromInt(1000),
            priceCents: Decimal.fromInt(1500),
          ),
        );
    await db.customStatement(
      'UPDATE business_warehouse_stocks SET unit_cost_cents=1000 '
      'WHERE warehouse_id=? AND variant_id=?',
      [source.warehouseId, variantId],
    );
    await StockService.adjustStock(
      db.productDao,
      productId: productId,
      variantId: variantId,
      quantity: 5,
      direction: StockDirection.increase,
      scope: source,
      origin: const InventoryOriginIntent.keyed(
        'opening_balance',
        'distributed-dispatch-test-opening',
      ),
    );
    await BranchCurrencyPolicyStore(db).bind('USD');
    final events = OfflineSyncEventStore(db);
    await events.activateWriterRecording(
      enrollmentId: '44444444-4444-4444-8444-444444444444',
    );
    await db.customStatement(
      '''INSERT INTO sync_branch_directory(
        branch_id,organization_id,code,name,writer_database_id,is_active)
        VALUES(?,?,?,?,?,1)''',
      [remoteBranch, source.organizationId, 'CAI', 'Cairo', remoteDatabase],
    );
    await db.customStatement(
      '''INSERT INTO sync_warehouse_directory(
        warehouse_id,organization_id,branch_id,code,name,is_active)
        VALUES(?,?,?,?,?,1)''',
      [
        remoteWarehouse,
        source.organizationId,
        remoteBranch,
        'CAI-MAIN',
        'Cairo main',
      ],
    );
    service = DistributedTransferDispatchService(
      db,
      authorize: (from, to) async {
        expect(from, source.warehouseId);
        expect(to, remoteWarehouse);
        return actor;
      },
      syncEvents: events,
    );
  });

  tearDown(() => db.close());

  test(
    'dispatch and recall conserve local stock and write atomic evidence',
    () async {
      final draft = await service.create(
        requestKey: '55555555-5555-4555-8555-555555555555',
        sourceWarehouseId: source.warehouseId,
        destinationWarehouseId: remoteWarehouse,
        lines: [
          DistributedTransferLineInput(
            productId: productId,
            variantId: variantId,
            quantity: 2,
            ownedQuantity: 2,
            consignmentQuantity: 0,
          ),
        ],
      );
      await service.dispatch(
        transferId: draft.transferId,
        requestKey: '66666666-6666-4666-8666-666666666666',
      );
      expect(await _stock(db, source.warehouseId, variantId), 3);
      expect(
        (await service.list({'in_transit'})).single.transferId,
        draft.transferId,
      );
      expect(await _count(db, 'distributed_transfer_outbound_allocations'), 1);
      expect(await _count(db, 'sync_outbox_events'), 1);

      await service.recall(
        transferId: draft.transferId,
        requestKey: '77777777-7777-4777-8777-777777777777',
        reason: 'Destination cannot receive today',
      );
      expect(await _stock(db, source.warehouseId, variantId), 3);
      expect(
        (await service.list({'recall_pending'})).single.transferId,
        draft.transferId,
      );
      expect(await _count(db, 'distributed_transfer_outbound_recalls'), 0);
      expect(await _count(db, 'sync_outbox_events'), 2);

      final request = await db
          .customSelect(
            'SELECT request_id FROM distributed_transfer_outbound_recall_requests '
            'WHERE transfer_id=?',
            variables: [Variable.withString(draft.transferId)],
          )
          .getSingle();
      await service.applyRecallResolution(
        _recallResolution(
          transferId: draft.transferId,
          requestId: request.read<String>('request_id'),
          organizationId: source.organizationId,
          originalSourceDatabaseId: source.databaseId,
          sourceWarehouseId: source.warehouseId,
          accepted: true,
        ),
      );
      expect(await _stock(db, source.warehouseId, variantId), 5);
      expect(
        (await service.list({'recalled'})).single.transferId,
        draft.transferId,
      );
      expect(await _count(db, 'distributed_transfer_outbound_recalls'), 1);

      // Replaying the immutable destination decision cannot restore twice.
      await service.applyRecallResolution(
        _recallResolution(
          transferId: draft.transferId,
          requestId: request.read<String>('request_id'),
          organizationId: source.organizationId,
          originalSourceDatabaseId: source.databaseId,
          sourceWarehouseId: source.warehouseId,
          accepted: true,
        ),
      );
      expect(await _stock(db, source.warehouseId, variantId), 5);
    },
  );
}

SyncEventEnvelope _recallResolution({
  required String transferId,
  required String requestId,
  required String organizationId,
  required String originalSourceDatabaseId,
  required String sourceWarehouseId,
  required bool accepted,
}) {
  final draft = SyncEventEnvelope(
    eventId: '88888888-8888-4888-8888-888888888888',
    sourceDatabaseId: '11111111-1111-4111-8111-111111111111',
    organizationId: organizationId,
    branchId: '22222222-2222-4222-8222-222222222222',
    sequence: 1,
    eventType: 'warehouse_transfer.recall_resolved.v1',
    aggregateType: 'warehouse_transfer',
    aggregateId: transferId,
    contractVersion: 1,
    payload: {
      'contract': 'warehouse_transfer.recall_resolved',
      'contractVersion': 1,
      'transferId': transferId,
      'requestId': requestId,
      'organizationId': organizationId,
      'branchId': '22222222-2222-4222-8222-222222222222',
      'sourceDatabaseId': '11111111-1111-4111-8111-111111111111',
      'originalSourceDatabaseId': originalSourceDatabaseId,
      'sourceWarehouseId': sourceWarehouseId,
      'destinationWarehouseId': '33333333-3333-4333-8333-333333333333',
      'accepted': accepted,
      'resolvedAt': DateTime.utc(2026, 9, 28, 13).toIso8601String(),
      'reason': accepted
          ? 'destination_confirmed_unreceived'
          : 'destination_already_received',
    },
    occurredAt: DateTime.utc(2026, 9, 28, 13),
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

Future<int> _stock(AppDatabase db, String warehouseId, int variantId) => db
    .customSelect(
      'SELECT quantity FROM business_warehouse_stocks '
      'WHERE warehouse_id=? AND variant_id=?',
      variables: [
        Variable.withString(warehouseId),
        Variable.withInt(variantId),
      ],
    )
    .map((row) => row.read<int>('quantity'))
    .getSingle();

Future<int> _count(AppDatabase db, String table) => db
    .customSelect('SELECT COUNT(*) AS n FROM $table')
    .map((row) => row.read<int>('n'))
    .getSingle();
