import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/services/sync/offline_sync_event_store.dart';
import 'package:tapix/core/services/sync/sync_inbound_projection_service.dart';

void main() {
  late AppDatabase db;
  late OfflineSyncEventStore events;
  late SyncInboundProjectionService projections;
  late String organizationId;

  const sourceDatabaseId = '11111111-1111-4111-8111-111111111111';
  const sourceBranchId = '22222222-2222-4222-8222-222222222222';

  setUp(() async {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    await db.customSelect('SELECT 1').get();
    events = OfflineSyncEventStore(db);
    projections = SyncInboundProjectionService(db, events);
    organizationId = await db
        .customSelect(
          'SELECT organization_id FROM business_contexts WHERE id=1',
        )
        .map((row) => row.read<String>('organization_id'))
        .getSingle();
    await events.enrollSource(
      sourceDatabaseId: sourceDatabaseId,
      organizationId: organizationId,
      branchId: sourceBranchId,
    );
  });

  tearDown(() => db.close());

  test(
    'supported event is projected once with canonical integer payload',
    () async {
      final event = _event(
        organizationId: organizationId,
        eventType: 'sale.posted.v1',
        payload: const {
          'z': 2,
          'a': {'minor': 1250},
        },
      );
      expect(await projections.apply(event), InboundSyncResult.applied);
      expect(await projections.apply(event), InboundSyncResult.duplicate);
      final row = await db
          .customSelect(
            'SELECT payload_json,event_hash FROM sync_remote_event_projections',
          )
          .getSingle();
      expect(jsonDecode(row.read<String>('payload_json')), {
        'a': {'minor': 1250},
        'z': 2,
      });
      expect(row.read<String>('event_hash'), event.eventHash);
      expect(await projections.nextSequenceFor(sourceDatabaseId), 2);
    },
  );

  test(
    'unknown financial contract is rejected without advancing inbox',
    () async {
      final event = _event(
        organizationId: organizationId,
        eventType: 'future.money.posted.v9',
        payload: const {'minor': 500},
      );
      await expectLater(
        projections.apply(event),
        throwsA(
          isA<OfflineSyncException>().having(
            (error) => error.code,
            'code',
            'unsupported_event_contract',
          ),
        ),
      );
      expect(await projections.nextSequenceFor(sourceDatabaseId), 1);
      expect(
        await db
            .customSelect('SELECT COUNT(*) AS n FROM sync_inbox_receipts')
            .map((row) => row.read<int>('n'))
            .getSingle(),
        0,
      );
    },
  );

  test('document payload cannot impersonate another branch', () async {
    final event = _event(
      organizationId: organizationId,
      eventType: 'purchase.posted.v1',
      payload: const {
        'documentId': '44444444-4444-4444-8444-444444444444',
        'branchId': '99999999-9999-4999-8999-999999999999',
      },
    );
    await expectLater(
      projections.apply(event),
      throwsA(
        isA<OfflineSyncException>().having(
          (error) => error.code,
          'code',
          'payload_branch_mismatch',
        ),
      ),
    );
    expect(await projections.nextSequenceFor(sourceDatabaseId), 1);
    expect(
      await db
          .customSelect(
            'SELECT COUNT(*) AS n FROM sync_remote_event_projections',
          )
          .map((row) => row.read<int>('n'))
          .getSingle(),
      0,
    );
  });
}

SyncEventEnvelope _event({
  required String organizationId,
  required String eventType,
  required Map<String, Object?> payload,
}) {
  final draft = SyncEventEnvelope(
    eventId: '33333333-3333-4333-8333-333333333333',
    sourceDatabaseId: '11111111-1111-4111-8111-111111111111',
    organizationId: organizationId,
    branchId: '22222222-2222-4222-8222-222222222222',
    sequence: 1,
    eventType: eventType,
    aggregateType: 'sale',
    aggregateId: '44444444-4444-4444-8444-444444444444',
    contractVersion: eventType.endsWith('.v1') ? 1 : 9,
    payload: payload,
    occurredAt: DateTime.utc(2026, 9, 28, 9),
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
