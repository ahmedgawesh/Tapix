import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/services/sync/branch_location_directory_sync_service.dart';
import 'package:tapix/core/services/sync/offline_sync_event_store.dart';

void main() {
  late AppDatabase db;
  late OfflineSyncEventStore events;
  late BranchLocationDirectorySyncService locations;

  setUp(() async {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    await db.customSelect('SELECT 1').get();
    events = OfflineSyncEventStore(db);
    locations = BranchLocationDirectorySyncService(db, events);
    await events.activateWriterRecording(
      enrollmentId: '31313131-3131-4131-8131-313131313131',
    );
  });

  tearDown(() => db.close());

  test('publishes routing identities only and retry is idempotent', () async {
    final physicalBefore = await db
        .customSelect(
          'SELECT COALESCE(SUM(quantity),0) AS quantity '
          'FROM business_warehouse_stocks',
        )
        .map((row) => row.read<int>('quantity'))
        .getSingle();
    final first = await locations.publishSnapshot();
    final second = await locations.publishSnapshot();
    expect(second, first);

    final rows = await db
        .customSelect(
          'SELECT event_type,payload_json FROM sync_outbox_events '
          'ORDER BY local_sequence',
        )
        .get();
    expect(rows.length, 2);
    expect(rows.map((row) => row.read<String>('event_type')).toSet(), {
      BranchLocationDirectorySyncService.eventType,
    });
    for (final row in rows) {
      final payload = row.read<String>('payload_json');
      expect(payload, isNot(contains('quantity')));
      expect(payload, isNot(contains('balance')));
      expect(payload, isNot(contains('"name":""')));
      if (payload.contains('"entityType":"warehouse"')) {
        expect(payload, contains('"locationKind":"branch_store"'));
      }
    }
    final physicalAfter = await db
        .customSelect(
          'SELECT COALESCE(SUM(quantity),0) AS quantity '
          'FROM business_warehouse_stocks',
        )
        .map((row) => row.read<int>('quantity'))
        .getSingle();
    expect(physicalAfter, physicalBefore);
  });

  test('accepts legacy empty names using stable codes as display names', () async {
    const sourceDatabaseId = '41414141-4141-4141-8141-414141414141';
    const sourceBranchId = '42424242-4242-4242-8242-424242424242';
    const remoteBranchId = '43434343-4343-4343-8343-434343434343';
    const remoteWarehouseId = '44444444-4444-4444-8444-444444444444';
    const localPhysicalWarehouseId = '48484848-4848-4848-8848-484848484848';
    const snapshotId = '45454545-4545-4545-8545-454545454545';
    final context = await db
        .customSelect(
          'SELECT organization_id,branch_id FROM business_contexts WHERE id=1',
        )
        .getSingle();
    final organizationId = context.read<String>('organization_id');
    final localBranchId = context.read<String>('branch_id');
    await db.customStatement(
      '''INSERT INTO app_settings(key,value)
      VALUES('lan.branch_sync.coordinator_database_id.v1',?)''',
      [sourceDatabaseId],
    );
    await events.enrollSource(
      sourceDatabaseId: sourceDatabaseId,
      organizationId: organizationId,
      branchId: sourceBranchId,
    );

    SyncEventEnvelope event({
      required String id,
      required int sequence,
      required String type,
      required List<Map<String, Object?>> entities,
    }) {
      final draft = SyncEventEnvelope(
        eventId: id,
        sourceDatabaseId: sourceDatabaseId,
        organizationId: organizationId,
        branchId: sourceBranchId,
        sequence: sequence,
        eventType: BranchLocationDirectorySyncService.eventType,
        aggregateType: 'location_snapshot',
        aggregateId: snapshotId,
        contractVersion: 1,
        occurredAt: DateTime.utc(2026, 9, 29),
        eventHash: '',
        payload: {
          'contract': 'location.snapshot_page',
          'contractVersion': 1,
          'snapshotId': snapshotId,
          'organizationId': organizationId,
          'sourceDatabaseId': sourceDatabaseId,
          'sourceBranchId': sourceBranchId,
          'entityType': type,
          'pageIndex': 0,
          'pageCount': 1,
          'entities': entities,
        },
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

    await events.applyInbound(
      event: event(
        id: '46464646-4646-4646-8646-464646464646',
        sequence: 1,
        type: 'branch',
        entities: [
          {
            'branchId': remoteBranchId,
            'organizationId': organizationId,
            'code': 'MAIN',
            'name': '',
            'writerDatabaseId': sourceDatabaseId,
            'isActive': true,
          },
          {
            'branchId': localBranchId,
            'organizationId': organizationId,
            'code': 'CAIRO',
            'name': 'Cairo branch',
            'writerDatabaseId': sourceDatabaseId,
            'isActive': true,
          },
        ],
      ),
      apply: locations.applyPage,
    );
    await events.applyInbound(
      event: event(
        id: '47474747-4747-4747-8747-474747474747',
        sequence: 2,
        type: 'warehouse',
        entities: [
          {
            'warehouseId': remoteWarehouseId,
            'organizationId': organizationId,
            'branchId': remoteBranchId,
            'code': 'MAIN-WH',
            'name': '',
            'isActive': true,
          },
          {
            'warehouseId': localPhysicalWarehouseId,
            'organizationId': organizationId,
            'branchId': localBranchId,
            'code': 'CAIRO-STORAGE',
            'name': 'Cairo physical warehouse',
            'locationKind': 'warehouse',
            'isActive': true,
          },
        ],
      ),
      apply: locations.applyPage,
    );

    final branch = await db
        .customSelect(
          'SELECT name FROM sync_branch_directory WHERE branch_id=?',
          variables: [Variable.withString(remoteBranchId)],
        )
        .map((row) => row.read<String>('name'))
        .getSingle();
    final warehouse = await db
        .customSelect(
          'SELECT name,location_kind FROM sync_warehouse_directory WHERE warehouse_id=?',
          variables: [Variable.withString(remoteWarehouseId)],
        )
        .getSingle();
    expect(branch, 'MAIN');
    expect(warehouse.read<String>('name'), 'MAIN-WH');
    expect(warehouse.read<String>('location_kind'), 'warehouse');
    final localPhysical = await db
        .customSelect(
          'SELECT name,location_kind FROM business_warehouses WHERE id=?',
          variables: [Variable.withString(localPhysicalWarehouseId)],
        )
        .getSingle();
    expect(localPhysical.read<String>('name'), 'Cairo physical warehouse');
    expect(localPhysical.read<String>('location_kind'), 'warehouse');
    expect(
      await db
          .customSelect(
            'SELECT COUNT(*) AS n FROM business_warehouse_stocks '
            'WHERE warehouse_id=?',
            variables: [Variable.withString(localPhysicalWarehouseId)],
          )
          .map((row) => row.read<int>('n'))
          .getSingle(),
      0,
    );

    // Upgrade path: the directory may predate local warehouse materialization.
    await db.customStatement('DELETE FROM business_warehouses WHERE id=?', [
      localPhysicalWarehouseId,
    ]);
    await locations.reconcileLocalWarehouses();
    final reconciled = await db
        .customSelect(
          'SELECT name,location_kind FROM business_warehouses WHERE id=?',
          variables: [Variable.withString(localPhysicalWarehouseId)],
        )
        .getSingle();
    expect(reconciled.read<String>('name'), 'Cairo physical warehouse');
    expect(reconciled.read<String>('location_kind'), 'warehouse');
    expect(
      await db
          .customSelect(
            'SELECT COUNT(*) AS n FROM business_warehouse_stocks '
            'WHERE warehouse_id=?',
            variables: [Variable.withString(localPhysicalWarehouseId)],
          )
          .map((row) => row.read<int>('n'))
          .getSingle(),
      0,
    );
  });
}
