import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/services/push_notification_service.dart';
import 'package:tapix/core/services/sync/branch_operational_projection_service.dart';
import 'package:tapix/core/services/sync/offline_sync_event_store.dart';
import 'package:tapix/core/services/sync/sync_inbound_projection_service.dart';
import 'package:tapix/features/business/data/warehouse_transfer_arrival_notification_service.dart';

void main() {
  test('destination dispatch creates one durable arrival notification', () async {
    SharedPreferences.setMockInitialValues({'locale_code': 'en'});
    final preferences = await SharedPreferences.getInstance();
    final db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    addTearDown(db.close);
    await db.customSelect('SELECT 1').get();

    const sourceDatabaseId = '11111111-1111-4111-8111-111111111111';
    const sourceBranchId = '22222222-2222-4222-8222-222222222222';
    const sourceWarehouseId = '33333333-3333-4333-8333-333333333333';
    const transferId = '44444444-4444-4444-8444-444444444444';
    const eventId = '55555555-5555-4555-8555-555555555555';
    final context = await db
        .customSelect(
          'SELECT organization_id,warehouse_id FROM business_contexts WHERE id=1',
        )
        .getSingle();
    final organizationId = context.read<String>('organization_id');
    final destinationWarehouseId = context.read<String>('warehouse_id');
    final events = OfflineSyncEventStore(db);
    await events.enrollSource(
      sourceDatabaseId: sourceDatabaseId,
      organizationId: organizationId,
      branchId: sourceBranchId,
    );
    var notifyCalls = 0;
    final notification = WarehouseTransferArrivalNotificationService(
      db,
      preferences,
      notify:
          ({
            required title,
            required body,
            required payload,
            required stableKey,
          }) async {
            notifyCalls++;
          },
    );
    final projection = SyncInboundProjectionService(
      db,
      events,
      operationalProjector: BranchOperationalProjectionService(db).apply,
      appliedObserver: notification.handle,
    );

    final payload = <String, Object?>{
      'contract': 'warehouse_transfer.dispatched',
      'contractVersion': 1,
      'transferId': transferId,
      'requestKey': '66666666-6666-4666-8666-666666666666',
      'organizationId': organizationId,
      'branchId': sourceBranchId,
      'sourceDatabaseId': sourceDatabaseId,
      'sourceWarehouseId': sourceWarehouseId,
      'destinationWarehouseId': destinationWarehouseId,
      'currencyCode': 'USD',
      'dispatchedAt': DateTime.utc(2026, 10, 1).toIso8601String(),
      'ownedValueMinor': 500,
      'allocationCount': 1,
      'allocations': const [
        {
          'allocationId': '77777777-7777-4777-8777-777777777777',
          'lineId': '88888888-8888-4888-8888-888888888888',
          'sequence': 1,
          'productGlobalId': '99999999-9999-4999-8999-999999999999',
          'variantGlobalId': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
          'ownerType': 'owned',
          'quantityScaled': 1,
          'quantityScale': 1,
          'measurementType': 'piece',
          'unitCostMinor': 500,
          'valueMinor': 500,
        },
      ],
    };
    final unsigned = SyncEventEnvelope(
      eventId: eventId,
      sourceDatabaseId: sourceDatabaseId,
      organizationId: organizationId,
      branchId: sourceBranchId,
      sequence: 1,
      eventType: 'warehouse_transfer.dispatched.v1',
      aggregateType: 'warehouse_transfer',
      aggregateId: transferId,
      contractVersion: 1,
      payload: payload,
      occurredAt: DateTime.utc(2026, 10, 1),
      eventHash: '',
    );
    final event = SyncEventEnvelope(
      eventId: unsigned.eventId,
      sourceDatabaseId: unsigned.sourceDatabaseId,
      organizationId: unsigned.organizationId,
      branchId: unsigned.branchId,
      sequence: unsigned.sequence,
      eventType: unsigned.eventType,
      aggregateType: unsigned.aggregateType,
      aggregateId: unsigned.aggregateId,
      contractVersion: unsigned.contractVersion,
      payload: unsigned.payload,
      occurredAt: unsigned.occurredAt,
      eventHash: OfflineSyncTransaction.eventHashFor(unsigned),
    );

    expect(await projection.apply(event), InboundSyncResult.applied);
    expect(await projection.apply(event), InboundSyncResult.duplicate);
    final rows = await db.select(db.notifications).get();
    expect(rows, hasLength(1));
    expect(rows.single.title, 'New stock transfer');
    expect(rows.single.message, contains('#44444444'));
    expect(rows.single.type, 'warehouse_transfer_arrived:$eventId');

    // A dispatch projected before notification support is reconciled once.
    await db.delete(db.notifications).go();
    await notification.reconcilePending();
    await notification.reconcilePending();
    final reconciled = await db.select(db.notifications).get();
    expect(reconciled, hasLength(1));
    expect(notifyCalls, 2);
  });

  test(
    'thin client transfer feed notifies an assigned warehouse once',
    () async {
      SharedPreferences.setMockInitialValues({'locale_code': 'ar'});
      final preferences = await SharedPreferences.getInstance();
      final db = AppDatabase.connect(
        DatabaseConnection(NativeDatabase.memory()),
      );
      addTearDown(db.close);
      await db.customSelect('SELECT 1').get();

      var notifyCalls = 0;
      final notification = WarehouseTransferArrivalNotificationService(
        db,
        preferences,
        notify:
            ({
              required title,
              required body,
              required payload,
              required stableKey,
            }) async {
              notifyCalls++;
              expect(title, 'وصل تحويل مخزون جديد');
              expect(stableKey, startsWith('remote:'));
            },
      );

      await notification.notifyRemoteTransfer(
        transferId: '44444444-4444-4444-8444-444444444444',
        lineCount: 2,
      );
      await notification.notifyRemoteTransfer(
        transferId: '44444444-4444-4444-8444-444444444444',
        lineCount: 2,
      );

      final rows = await db.select(db.notifications).get();
      expect(rows, hasLength(1));
      expect(rows.single.message, contains('#44444444'));
      expect(
        rows.single.type,
        'warehouse_transfer_remote_arrived:'
        '44444444-4444-4444-8444-444444444444',
      );
      expect(notifyCalls, 1);
    },
  );

  test(
    'durable notification survives unavailable native notification channel',
    () async {
      SharedPreferences.setMockInitialValues({'locale_code': 'en'});
      final preferences = await SharedPreferences.getInstance();
      final db = AppDatabase.connect(
        DatabaseConnection(NativeDatabase.memory()),
      );
      addTearDown(db.close);
      await db.customSelect('SELECT 1').get();

      final notification = WarehouseTransferArrivalNotificationService(
        db,
        preferences,
        notify:
            ({
              required title,
              required body,
              required payload,
              required stableKey,
            }) async {
              throw StateError('native notifications are unavailable');
            },
      );

      await expectLater(
        notification.notifyRemoteTransfer(
          transferId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
          lineCount: 3,
        ),
        completes,
      );

      final rows = await db.select(db.notifications).get();
      expect(rows, hasLength(1));
      expect(rows.single.title, 'New stock transfer');
      expect(rows.single.message, contains('#BBBBBBBB'));
    },
  );

  test('constructing local notification service does not require Firebase', () {
    expect(() => PushNotificationService.instance, returnsNormally);
  });

  test('default notifier is safe without a Firebase app on desktop', () async {
    SharedPreferences.setMockInitialValues({'locale_code': 'en'});
    final preferences = await SharedPreferences.getInstance();
    final db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    addTearDown(db.close);
    await db.customSelect('SELECT 1').get();

    final notification = WarehouseTransferArrivalNotificationService(
      db,
      preferences,
    );

    await expectLater(
      notification.notifyRemoteTransfer(
        transferId: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
        lineCount: 1,
      ),
      completes,
    );
    expect(await db.select(db.notifications).get(), hasLength(1));
  });
}
