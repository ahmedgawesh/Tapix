import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/services/sync/offline_sync_event_store.dart';

void main() {
  late AppDatabase db;
  late OfflineSyncEventStore store;
  late String organizationId;
  late String localDatabaseId;

  setUp(() async {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    await db.customSelect('SELECT 1').get();
    await db.customStatement(
      'CREATE TABLE sync_test_projection(id TEXT PRIMARY KEY,value INTEGER NOT NULL)',
    );
    store = OfflineSyncEventStore(db);
    final context = await db
        .customSelect(
          'SELECT organization_id,database_id FROM business_contexts WHERE id=1',
        )
        .getSingle();
    organizationId = context.read<String>('organization_id');
    localDatabaseId = context.read<String>('database_id');
  });

  tearDown(() => db.close());

  test('current-version customer database receives sidecar on reopen', () async {
    await db.close();
    final directory = await Directory.systemTemp.createTemp(
      'tapix-sync-ledger-',
    );
    final file = File('${directory.path}/customer.sqlite');
    try {
      final original = AppDatabase.connect(
        DatabaseConnection(NativeDatabase(file)),
      );
      await original.customSelect('SELECT 1').get();
      await original.customStatement(
        'DROP TABLE sync_inventory_layer_identities',
      );
      await original.customStatement('DROP TABLE sync_writer_enrollment');
      await original.customStatement('DROP TABLE sync_entity_identities');
      await original.customStatement('DROP TABLE sync_inbox_receipts');
      await original.customStatement('DROP TABLE sync_source_checkpoints');
      await original.customStatement('DROP TABLE sync_outbox_events');
      await original.customStatement('DROP TABLE sync_local_state');
      expect(original.schemaVersion, 10115);
      await original.close();

      final reopened = AppDatabase.connect(
        DatabaseConnection(NativeDatabase(file)),
      );
      final identity = await reopened
          .customSelect(
            'SELECT database_id,next_sequence FROM sync_local_state WHERE id=1',
          )
          .getSingle();
      expect(identity.read<String>('database_id'), hasLength(36));
      expect(identity.read<int>('next_sequence'), 1);
      expect(reopened.schemaVersion, 10115);
      await reopened.close();
      db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
      await db.customSelect('SELECT 1').get();
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('writer recording is opt-in, immutable, and idempotent', () async {
    expect(await store.isWriterRecordingEnabled(), isFalse);
    await expectLater(
      store.activateWriterRecording(enrollmentId: 'invalid'),
      throwsA(_code('invalid_writer_enrollment')),
    );
    const enrollment = '10101010-1010-4010-8010-101010101010';
    await store.activateWriterRecording(enrollmentId: enrollment);
    await store.activateWriterRecording(enrollmentId: enrollment);
    expect(await store.isWriterRecordingEnabled(), isTrue);
    await expectLater(
      store.activateWriterRecording(
        enrollmentId: '20202020-2020-4020-8020-202020202020',
      ),
      throwsA(_code('writer_enrollment_conflict')),
    );
    await expectLater(
      db.customStatement('DELETE FROM sync_writer_enrollment'),
      throwsA(anything),
    );
    await expectLater(
      db.customStatement(
        'UPDATE sync_writer_enrollment SET enrollment_id=? WHERE id=1',
        ['30303030-3030-4030-8030-303030303030'],
      ),
      throwsA(anything),
    );
  });

  test('installer binds immutable sync identity to business context', () async {
    final row = await db
        .customSelect(
          'SELECT database_id,organization_id,next_sequence FROM sync_local_state',
        )
        .getSingle();
    expect(row.read<String>('database_id'), localDatabaseId);
    expect(row.read<String>('organization_id'), organizationId);
    expect(row.read<int>('next_sequence'), 1);
    await expectLater(
      db.customStatement('DELETE FROM sync_local_state'),
      throwsA(anything),
    );
  });

  test('business mutation and outbox append commit atomically', () async {
    final event = await store.transaction((transaction) async {
      await db.customStatement(
        "INSERT INTO sync_test_projection(id,value) VALUES('sale-1',200)",
      );
      return transaction.append(
        eventType: 'sale.posted.v1',
        aggregateType: 'sale',
        aggregateId: 'sale-1',
        payload: const {'totalCents': 200, 'lines': 1},
        occurredAt: DateTime.utc(2026, 9, 25, 10),
      );
    });
    expect(event.sequence, 1);
    expect(event.eventHash, hasLength(64));
    final decoded = SyncEventEnvelope.fromJson(event.toJson());
    expect(decoded.eventHash, event.eventHash);
    expect(decoded.payload, event.payload);
    expect(
      await db
          .customSelect('SELECT COUNT(*) AS c FROM sync_outbox_events')
          .map((row) => row.read<int>('c'))
          .getSingle(),
      1,
    );

    await expectLater(
      store.transaction((transaction) async {
        await db.customStatement(
          "INSERT INTO sync_test_projection(id,value) VALUES('sale-2',300)",
        );
        await transaction.append(
          eventType: 'sale.posted.v1',
          aggregateType: 'sale',
          aggregateId: 'sale-2',
          payload: const {'totalCents': 300},
        );
        throw StateError('posting failed');
      }),
      throwsStateError,
    );
    expect(
      await db
          .customSelect(
            "SELECT COUNT(*) AS c FROM sync_test_projection WHERE id='sale-2'",
          )
          .map((row) => row.read<int>('c'))
          .getSingle(),
      0,
    );
    final state = await db
        .customSelect('SELECT next_sequence FROM sync_local_state')
        .getSingle();
    expect(state.read<int>('next_sequence'), 2);
  });

  test(
    'canonical payload gives stable hash and strictly increasing sequence',
    () async {
      final first = await _append(store, const {'b': 2, 'a': 1});
      final second = await _append(store, const {'a': 1, 'b': 2});
      expect(second.sequence, first.sequence + 1);
      expect(first.eventHash, isNot(second.eventHash));
      final firstContract = SyncEventEnvelope(
        eventId: first.eventId,
        sourceDatabaseId: first.sourceDatabaseId,
        organizationId: first.organizationId,
        branchId: first.branchId,
        sequence: first.sequence,
        eventType: first.eventType,
        aggregateType: first.aggregateType,
        aggregateId: first.aggregateId,
        contractVersion: first.contractVersion,
        payload: const {'a': 1, 'b': 2},
        occurredAt: first.occurredAt,
        eventHash: first.eventHash,
      );
      expect(
        OfflineSyncTransaction.eventHashFor(firstContract),
        first.eventHash,
      );
    },
  );

  test('floating point payload is rejected before changing sequence', () async {
    await expectLater(
      _append(store, const {'amount': 1.25}),
      throwsA(_code('floating_point_payload')),
    );
    final state = await db
        .customSelect('SELECT next_sequence FROM sync_local_state')
        .getSingle();
    expect(state.read<int>('next_sequence'), 1);
  });

  test('appendOnce reuses one event and does not consume a sequence', () async {
    Future<SyncEventEnvelope> write(Map<String, Object?> payload) =>
        store.transaction(
          (transaction) => transaction.appendOnce(
            producerKey: 'sale:42:posted',
            eventType: 'sale.posted.v1',
            aggregateType: 'sale',
            aggregateId: 'sale-42',
            payload: payload,
            occurredAt: DateTime.utc(2026, 9, 25, 10),
          ),
        );

    final first = await write(const {'totalCents': 200, 'lines': 1});
    final replay = await write(const {'lines': 1, 'totalCents': 200});
    expect(replay.eventId, first.eventId);
    expect(replay.sequence, first.sequence);
    expect(replay.eventHash, first.eventHash);
    expect(
      await db
          .customSelect('SELECT COUNT(*) AS c FROM sync_outbox_events')
          .map((row) => row.read<int>('c'))
          .getSingle(),
      1,
    );
    expect(
      await db
          .customSelect('SELECT next_sequence FROM sync_local_state')
          .map((row) => row.read<int>('next_sequence'))
          .getSingle(),
      2,
    );
  });

  test(
    'appendOnce rejects a reused producer key with changed content',
    () async {
      Future<SyncEventEnvelope> write(Map<String, Object?> payload) =>
          store.transaction(
            (transaction) => transaction.appendOnce(
              producerKey: 'transfer:dispatch-7:posted',
              eventType: 'warehouse-transfer.dispatched.v1',
              aggregateType: 'warehouse_transfer',
              aggregateId: 'transfer-7',
              payload: payload,
            ),
          );

      await write(const {'quantityScaled': 2});
      await expectLater(
        write(const {'quantityScaled': 3}),
        throwsA(_code('producer_key_conflict')),
      );
      expect(
        await db
            .customSelect('SELECT next_sequence FROM sync_local_state')
            .map((row) => row.read<int>('next_sequence'))
            .getSingle(),
        2,
      );
    },
  );

  test('outbox leases in order and a live lease blocks later events', () async {
    final first = await _append(store, const {'value': 1});
    await _append(store, const {'value': 2});
    final now = DateTime.utc(2026, 9, 25, 12);
    final claimed = await store.claimDispatchBatch(
      leaseToken: 'worker-a',
      limit: 1,
      now: now,
    );
    expect(claimed.map((event) => event.sequence), [1]);
    expect(
      await store.claimDispatchBatch(leaseToken: 'worker-b', now: now),
      isEmpty,
    );
    await store.acknowledge(
      eventId: first.eventId,
      leaseToken: 'worker-a',
      deliveredAt: now,
    );
    final next = await store.claimDispatchBatch(
      leaseToken: 'worker-b',
      now: now,
    );
    expect(next.map((event) => event.sequence), [2]);
  });

  test('failure policy rejects a non-positive attempt limit', () async {
    final event = await _append(store, const {'value': 1});
    final now = DateTime.utc(2026, 9, 25, 12);
    await store.claimDispatchBatch(leaseToken: 'worker', limit: 1, now: now);
    await expectLater(
      store.recordFailure(
        eventId: event.eventId,
        leaseToken: 'worker',
        error: 'offline',
        retryAt: now,
        maxAttempts: 0,
      ),
      throwsA(_code('invalid_max_attempts')),
    );
  });

  test('failed head retries, then dead-letter blocks the stream', () async {
    final first = await _append(store, const {'value': 1});
    await _append(store, const {'value': 2});
    final now = DateTime.utc(2026, 9, 25, 12);
    await store.claimDispatchBatch(leaseToken: 'worker', limit: 1, now: now);
    await store.recordFailure(
      eventId: first.eventId,
      leaseToken: 'worker',
      error: 'offline',
      retryAt: now.add(const Duration(minutes: 1)),
      maxAttempts: 1,
    );
    expect(
      await store.claimDispatchBatch(
        leaseToken: 'other',
        now: now.add(const Duration(hours: 1)),
      ),
      isEmpty,
    );
  });

  test('inbound apply is ordered, idempotent, and atomic', () async {
    const sourceDatabaseId = '11111111-1111-4111-8111-111111111111';
    const sourceBranchId = '22222222-2222-4222-8222-222222222222';
    await store.enrollSource(
      sourceDatabaseId: sourceDatabaseId,
      organizationId: organizationId,
      branchId: sourceBranchId,
    );
    final event = _remoteEvent(
      sourceDatabaseId: sourceDatabaseId,
      organizationId: organizationId,
      branchId: sourceBranchId,
      sequence: 1,
    );
    var applications = 0;
    Future<void> apply(SyncEventEnvelope _) async {
      applications++;
      await db.customStatement(
        "INSERT INTO sync_test_projection(id,value) VALUES('remote-1',7)",
      );
    }

    expect(
      await store.applyInbound(event: event, apply: apply),
      InboundSyncResult.applied,
    );
    expect(
      await store.applyInbound(event: event, apply: apply),
      InboundSyncResult.duplicate,
    );
    expect(applications, 1);
    await store.enrollSource(
      sourceDatabaseId: sourceDatabaseId,
      organizationId: organizationId,
      branchId: sourceBranchId,
    );
    final changedDraft = SyncEventEnvelope(
      eventId: event.eventId,
      sourceDatabaseId: event.sourceDatabaseId,
      organizationId: event.organizationId,
      branchId: event.branchId,
      sequence: event.sequence,
      eventType: event.eventType,
      aggregateType: event.aggregateType,
      aggregateId: event.aggregateId,
      contractVersion: event.contractVersion,
      payload: const {'totalCents': 999},
      occurredAt: event.occurredAt,
      eventHash: '',
    );
    final changed = SyncEventEnvelope(
      eventId: changedDraft.eventId,
      sourceDatabaseId: changedDraft.sourceDatabaseId,
      organizationId: changedDraft.organizationId,
      branchId: changedDraft.branchId,
      sequence: changedDraft.sequence,
      eventType: changedDraft.eventType,
      aggregateType: changedDraft.aggregateType,
      aggregateId: changedDraft.aggregateId,
      contractVersion: changedDraft.contractVersion,
      payload: changedDraft.payload,
      occurredAt: changedDraft.occurredAt,
      eventHash: OfflineSyncTransaction.eventHashFor(changedDraft),
    );
    await expectLater(
      store.applyInbound(event: changed, apply: (_) async {}),
      throwsA(_code('event_identity_conflict')),
    );

    final failing = _remoteEvent(
      sourceDatabaseId: sourceDatabaseId,
      organizationId: organizationId,
      branchId: sourceBranchId,
      sequence: 2,
    );
    await expectLater(
      store.applyInbound(
        event: failing,
        apply: (_) async {
          await db.customStatement(
            "INSERT INTO sync_test_projection(id,value) VALUES('rollback',9)",
          );
          throw StateError('projection failed');
        },
      ),
      throwsStateError,
    );
    expect(
      await db
          .customSelect(
            "SELECT COUNT(*) AS c FROM sync_test_projection WHERE id='rollback'",
          )
          .map((row) => row.read<int>('c'))
          .getSingle(),
      0,
    );
    final checkpoint = await db
        .customSelect(
          'SELECT next_sequence FROM sync_source_checkpoints '
          'WHERE source_database_id=?',
          variables: [Variable.withString(sourceDatabaseId)],
        )
        .getSingle();
    expect(checkpoint.read<int>('next_sequence'), 2);
  });

  test(
    'gap, changed replay, foreign organization and loopback are rejected',
    () async {
      const sourceDatabaseId = '33333333-3333-4333-8333-333333333333';
      const sourceBranchId = '44444444-4444-4444-8444-444444444444';
      await store.enrollSource(
        sourceDatabaseId: sourceDatabaseId,
        organizationId: organizationId,
        branchId: sourceBranchId,
      );
      final gap = _remoteEvent(
        sourceDatabaseId: sourceDatabaseId,
        organizationId: organizationId,
        branchId: sourceBranchId,
        sequence: 2,
      );
      await expectLater(
        store.applyInbound(event: gap, apply: (_) async {}),
        throwsA(_code('event_gap')),
      );
      final loop = _remoteEvent(
        sourceDatabaseId: localDatabaseId,
        organizationId: organizationId,
        branchId: sourceBranchId,
        sequence: 1,
      );
      await expectLater(
        store.applyInbound(event: loop, apply: (_) async {}),
        throwsA(_code('looped_back_event')),
      );
      final foreign = _remoteEvent(
        sourceDatabaseId: sourceDatabaseId,
        organizationId: '55555555-5555-4555-8555-555555555555',
        branchId: sourceBranchId,
        sequence: 1,
      );
      await expectLater(
        store.applyInbound(event: foreign, apply: (_) async {}),
        throwsA(_code('organization_mismatch')),
      );
    },
  );

  test(
    'outbox and applied inbox evidence cannot be rewritten or deleted',
    () async {
      final local = await _append(store, const {'value': 1});
      await expectLater(
        db.customStatement(
          "UPDATE sync_outbox_events SET payload_json='{}' WHERE event_id=?",
          [local.eventId],
        ),
        throwsA(anything),
      );
      await expectLater(
        db.customStatement('DELETE FROM sync_outbox_events WHERE event_id=?', [
          local.eventId,
        ]),
        throwsA(anything),
      );
    },
  );
}

Future<SyncEventEnvelope> _append(
  OfflineSyncEventStore store,
  Map<String, Object?> payload,
) => store.transaction(
  (transaction) => transaction.append(
    eventType: 'sale.posted.v1',
    aggregateType: 'sale',
    aggregateId: const Uuid().v4(),
    payload: payload,
    occurredAt: DateTime.utc(2026, 9, 25, 10),
  ),
);

SyncEventEnvelope _remoteEvent({
  required String sourceDatabaseId,
  required String organizationId,
  required String branchId,
  required int sequence,
}) {
  final draft = SyncEventEnvelope(
    eventId: const Uuid().v4(),
    sourceDatabaseId: sourceDatabaseId,
    organizationId: organizationId,
    branchId: branchId,
    sequence: sequence,
    eventType: 'sale.posted.v1',
    aggregateType: 'sale',
    aggregateId: 'remote-sale-$sequence',
    contractVersion: 1,
    payload: {'totalCents': 700 + sequence},
    occurredAt: DateTime.utc(2026, 9, 25, 11, sequence),
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

Matcher _code(String code) =>
    isA<OfflineSyncException>().having((error) => error.code, 'code', code);
