import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/services/sync/branch_operational_projection_service.dart';
import 'package:tapix/core/services/sync/offline_sync_event_store.dart';
import 'package:tapix/core/services/sync/sync_inbound_projection_service.dart';

void main() {
  late AppDatabase db;
  late OfflineSyncEventStore events;
  late SyncInboundProjectionService projection;
  late String organizationId;
  late String destinationDatabaseId;
  late String destinationBranchId;
  late String destinationWarehouseId;

  const sourceDatabaseId = '11111111-1111-4111-8111-111111111111';
  const sourceBranchId = '22222222-2222-4222-8222-222222222222';
  const sourceWarehouseId = '33333333-3333-4333-8333-333333333333';
  const transferId = '44444444-4444-4444-8444-444444444444';
  const allocationId = '55555555-5555-4555-8555-555555555555';
  setUp(() async {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    await db.customSelect('SELECT 1').get();
    events = OfflineSyncEventStore(db);
    final operational = BranchOperationalProjectionService(db);
    projection = SyncInboundProjectionService(
      db,
      events,
      operationalProjector: operational.apply,
    );
    final context = await db
        .customSelect(
          'SELECT organization_id,database_id,branch_id,warehouse_id '
          'FROM business_contexts WHERE id=1',
        )
        .getSingle();
    organizationId = context.read<String>('organization_id');
    destinationDatabaseId = context.read<String>('database_id');
    destinationBranchId = context.read<String>('branch_id');
    destinationWarehouseId = context.read<String>('warehouse_id');
    await events.activateWriterRecording(
      enrollmentId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    );
    await events.enrollSource(
      sourceDatabaseId: sourceDatabaseId,
      organizationId: organizationId,
      branchId: sourceBranchId,
    );
  });

  tearDown(() => db.close());

  test('addressed dispatch becomes one pending inbound document', () async {
    final event = _event(
      sequence: 1,
      eventId: '88888888-8888-4888-8888-888888888888',
      organizationId: organizationId,
      payload: _dispatchPayload(
        organizationId: organizationId,
        destinationWarehouseId: destinationWarehouseId,
      ),
    );

    expect(await projection.apply(event), InboundSyncResult.applied);
    expect(await projection.apply(event), InboundSyncResult.duplicate);

    final dispatch = await db
        .customSelect('SELECT * FROM distributed_transfer_inbound_dispatches')
        .getSingle();
    expect(dispatch.read<String>('transfer_id'), transferId);
    expect(dispatch.read<String>('source_database_id'), sourceDatabaseId);
    expect(
      dispatch.read<String>('destination_warehouse_id'),
      destinationWarehouseId,
    );
    expect(dispatch.read<String>('catalogue_state'), 'awaiting_catalogue');
    expect(dispatch.read<String>('lifecycle_state'), 'awaiting_receipt');
    expect(dispatch.read<int>('owned_value_minor'), 1250);

    final allocation = await db
        .customSelect('SELECT * FROM distributed_transfer_inbound_allocations')
        .getSingle();
    expect(allocation.read<String>('allocation_id'), allocationId);
    expect(allocation.read<int>('quantity_scaled'), 2);
    expect(allocation.read<int>('value_minor'), 1250);

    final stock = await db
        .customSelect(
          'SELECT COALESCE(SUM(quantity),0) AS quantity '
          'FROM business_warehouse_stocks',
        )
        .getSingle();
    expect(stock.read<int>('quantity'), 0);
  });

  test(
    'dispatch for another warehouse is retained only as audit projection',
    () async {
      final event = _event(
        sequence: 1,
        eventId: '99999999-9999-4999-8999-999999999999',
        organizationId: organizationId,
        payload: _dispatchPayload(
          organizationId: organizationId,
          destinationWarehouseId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        ),
      );

      expect(await projection.apply(event), InboundSyncResult.applied);
      expect(
        await db
            .customSelect(
              'SELECT COUNT(*) AS n FROM distributed_transfer_inbound_dispatches',
            )
            .map((row) => row.read<int>('n'))
            .getSingle(),
        0,
      );
      expect(
        await db
            .customSelect(
              'SELECT COUNT(*) AS n FROM sync_remote_event_projections',
            )
            .map((row) => row.read<int>('n'))
            .getSingle(),
        1,
      );
    },
  );

  test('invalid owned value rolls back inbox and operational document', () async {
    final payload = _dispatchPayload(
      organizationId: organizationId,
      destinationWarehouseId: destinationWarehouseId,
    )..['ownedValueMinor'] = 1249;
    final event = _event(
      sequence: 1,
      eventId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
      organizationId: organizationId,
      payload: payload,
    );

    await expectLater(
      projection.apply(event),
      throwsA(
        isA<OfflineSyncException>().having(
          (error) => error.code,
          'code',
          'distributed_transfer_value_mismatch',
        ),
      ),
    );
    expect(await projection.nextSequenceFor(sourceDatabaseId), 1);
    expect(
      await db
          .customSelect(
            'SELECT COUNT(*) AS n FROM distributed_transfer_inbound_dispatches',
          )
          .map((row) => row.read<int>('n'))
          .getSingle(),
      0,
    );
  });

  test('source recall closes an unreceived inbound dispatch', () async {
    await projection.apply(
      _event(
        sequence: 1,
        eventId: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
        organizationId: organizationId,
        payload: _dispatchPayload(
          organizationId: organizationId,
          destinationWarehouseId: destinationWarehouseId,
        ),
      ),
    );
    await projection.apply(
      _event(
        sequence: 2,
        eventId: 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
        organizationId: organizationId,
        eventType: 'warehouse_transfer.recalled.v1',
        payload: {
          'contract': 'warehouse_transfer.recalled',
          'contractVersion': 1,
          'transferId': transferId,
          'organizationId': organizationId,
          'branchId': sourceBranchId,
          'sourceDatabaseId': sourceDatabaseId,
          'sourceWarehouseId': sourceWarehouseId,
          'destinationWarehouseId': destinationWarehouseId,
          'currencyCode': 'USD',
          'recalledAt': DateTime.utc(2026, 9, 28, 12).toIso8601String(),
          'ownedValueMinor': 1250,
          'reason': 'Dispatch cancelled before destination receipt',
          'itemCount': 1,
          'items': const [
            {
              'allocationId': allocationId,
              'quantityScaled': 2,
              'valueMinor': 1250,
            },
          ],
        },
      ),
    );

    final state = await db
        .customSelect(
          'SELECT lifecycle_state FROM distributed_transfer_inbound_dispatches '
          'WHERE transfer_id=?',
          variables: [Variable.withString(transferId)],
        )
        .map((row) => row.read<String>('lifecycle_state'))
        .getSingle();
    expect(state, 'recalled');
  });

  test(
    'recall request closes only an unreceived dispatch and emits acceptance',
    () async {
      await projection.apply(
        _event(
          sequence: 1,
          eventId: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
          organizationId: organizationId,
          payload: _dispatchPayload(
            organizationId: organizationId,
            destinationWarehouseId: destinationWarehouseId,
          ),
        ),
      );
      await projection.apply(
        _event(
          sequence: 2,
          eventId: 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
          organizationId: organizationId,
          eventType: 'warehouse_transfer.recall_requested.v1',
          payload: _recallRequestPayload(
            organizationId: organizationId,
            destinationDatabaseId: destinationDatabaseId,
            destinationBranchId: destinationBranchId,
            destinationWarehouseId: destinationWarehouseId,
          ),
        ),
      );

      final state = await db
          .customSelect(
            'SELECT lifecycle_state FROM distributed_transfer_inbound_dispatches '
            'WHERE transfer_id=?',
            variables: [Variable.withString(transferId)],
          )
          .map((row) => row.read<String>('lifecycle_state'))
          .getSingle();
      expect(state, 'recalled');
      final response = await db
          .customSelect(
            "SELECT payload_json FROM sync_outbox_events WHERE event_type='warehouse_transfer.recall_resolved.v1'",
          )
          .getSingle();
      final payload =
          jsonDecode(response.read<String>('payload_json'))
              as Map<String, dynamic>;
      expect(payload['accepted'], isTrue);
      expect(payload['reason'], 'destination_confirmed_unreceived');
    },
  );

  test('recall request is rejected after destination receipt has started', () async {
    await projection.apply(
      _event(
        sequence: 1,
        eventId: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
        organizationId: organizationId,
        payload: _dispatchPayload(
          organizationId: organizationId,
          destinationWarehouseId: destinationWarehouseId,
        ),
      ),
    );
    await db.customStatement(
      "UPDATE distributed_transfer_inbound_dispatches SET lifecycle_state='completed' WHERE transfer_id=?",
      [transferId],
    );
    await projection.apply(
      _event(
        sequence: 2,
        eventId: 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
        organizationId: organizationId,
        eventType: 'warehouse_transfer.recall_requested.v1',
        payload: _recallRequestPayload(
          organizationId: organizationId,
          destinationDatabaseId: destinationDatabaseId,
          destinationBranchId: destinationBranchId,
          destinationWarehouseId: destinationWarehouseId,
        ),
      ),
    );

    final response = await db
        .customSelect(
          "SELECT payload_json FROM sync_outbox_events WHERE event_type='warehouse_transfer.recall_resolved.v1'",
        )
        .getSingle();
    final payload =
        jsonDecode(response.read<String>('payload_json'))
            as Map<String, dynamic>;
    expect(payload['accepted'], isFalse);
    expect(payload['reason'], 'destination_already_received');
    expect(
      await db
          .customSelect(
            'SELECT lifecycle_state FROM distributed_transfer_inbound_dispatches '
            'WHERE transfer_id=?',
            variables: [Variable.withString(transferId)],
          )
          .map((row) => row.read<String>('lifecycle_state'))
          .getSingle(),
      'completed',
    );
  });
}

Map<String, Object?> _recallRequestPayload({
  required String organizationId,
  required String destinationDatabaseId,
  required String destinationBranchId,
  required String destinationWarehouseId,
}) => {
  'contract': 'warehouse_transfer.recall_requested',
  'contractVersion': 1,
  'transferId': '44444444-4444-4444-8444-444444444444',
  'requestId': '99999999-9999-4999-8999-999999999999',
  'requestKey': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaab',
  'organizationId': organizationId,
  'branchId': '22222222-2222-4222-8222-222222222222',
  'sourceDatabaseId': '11111111-1111-4111-8111-111111111111',
  'sourceWarehouseId': '33333333-3333-4333-8333-333333333333',
  'destinationDatabaseId': destinationDatabaseId,
  'destinationBranchId': destinationBranchId,
  'destinationWarehouseId': destinationWarehouseId,
  'requestedAt': DateTime.utc(2026, 9, 28, 12).toIso8601String(),
  'reason': 'Destination cannot receive today',
};

Map<String, Object?> _dispatchPayload({
  required String organizationId,
  required String destinationWarehouseId,
}) => {
  'contract': 'warehouse_transfer.dispatched',
  'contractVersion': 1,
  'transferId': '44444444-4444-4444-8444-444444444444',
  'requestKey': 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
  'organizationId': organizationId,
  'branchId': '22222222-2222-4222-8222-222222222222',
  'sourceDatabaseId': '11111111-1111-4111-8111-111111111111',
  'sourceWarehouseId': '33333333-3333-4333-8333-333333333333',
  'destinationWarehouseId': destinationWarehouseId,
  'currencyCode': 'USD',
  'dispatchedAt': DateTime.utc(2026, 9, 28, 10).toIso8601String(),
  'ownedValueMinor': 1250,
  'allocationCount': 1,
  'allocations': const [
    {
      'allocationId': '55555555-5555-4555-8555-555555555555',
      'lineId': 'ffffffff-ffff-4fff-8fff-ffffffffffff',
      'sequence': 1,
      'productGlobalId': '66666666-6666-4666-8666-666666666666',
      'variantGlobalId': '77777777-7777-4777-8777-777777777777',
      'ownerType': 'owned',
      'quantityScaled': 2,
      'quantityScale': 1,
      'measurementType': 'piece',
      'unitCostMinor': 625,
      'valueMinor': 1250,
    },
  ],
};

SyncEventEnvelope _event({
  required int sequence,
  required String eventId,
  required String organizationId,
  required Map<String, Object?> payload,
  String eventType = 'warehouse_transfer.dispatched.v1',
}) {
  final draft = SyncEventEnvelope(
    eventId: eventId,
    sourceDatabaseId: '11111111-1111-4111-8111-111111111111',
    organizationId: organizationId,
    branchId: '22222222-2222-4222-8222-222222222222',
    sequence: sequence,
    eventType: eventType,
    aggregateType: 'warehouse_transfer',
    aggregateId: '44444444-4444-4444-8444-444444444444',
    contractVersion: 1,
    payload: payload,
    occurredAt: DateTime.utc(2026, 9, 28, 10 + sequence),
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
