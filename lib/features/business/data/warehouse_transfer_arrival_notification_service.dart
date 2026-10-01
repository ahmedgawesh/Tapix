import 'dart:async';

import 'package:drift/drift.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/database/app_database.dart';
import '../../../core/services/lan/lan_network_service.dart';
import '../../../core/services/logging_service.dart';
import '../../../core/services/push_notification_service.dart';
import '../../../core/services/sync/offline_sync_event_store.dart';

/// Creates one durable in-app notification and one device notification after a
/// dispatch has been projected into the destination database.
class WarehouseTransferArrivalNotificationService {
  WarehouseTransferArrivalNotificationService(
    this._db,
    this._preferences, {
    Future<void> Function({
      required String title,
      required String body,
      required Map<String, Object?> payload,
      required String stableKey,
    })?
    notify,
  }) : _notify = notify ?? _defaultNotify;

  final AppDatabase _db;
  final SharedPreferences _preferences;
  final Future<void> Function({
    required String title,
    required String body,
    required Map<String, Object?> payload,
    required String stableKey,
  })
  _notify;
  Timer? _remotePollTimer;
  StreamSubscription<LanNetworkSnapshot>? _networkSubscription;
  LanNetworkService? _remoteNetwork;
  bool _remotePollInFlight = false;

  static Future<void> _defaultNotify({
    required String title,
    required String body,
    required Map<String, Object?> payload,
    required String stableKey,
  }) => PushNotificationService.instance.showLocalBusinessNotification(
    title: title,
    body: body,
    payload: payload,
    stableKey: stableKey,
  );

  Future<void> handle(SyncEventEnvelope event) async {
    if (event.eventType != 'warehouse_transfer.dispatched.v1') return;
    final transferId = event.payload['transferId']?.toString().toLowerCase();
    if (transferId == null || transferId.isEmpty) return;
    await _notifyTransfer(transferId: transferId, eventId: event.eventId);
  }

  /// Notifies a thin LAN workstation after its branch server returns an
  /// inbound transfer. Thin clients do not project sync events into their
  /// private SQLite file, so their arrival signal must come from the
  /// authenticated transfer feed.
  Future<void> notifyRemoteTransfer({
    required String transferId,
    required int lineCount,
  }) async {
    final normalized = transferId.trim().toLowerCase();
    if (normalized.isEmpty || lineCount < 1) return;
    final type = 'warehouse_transfer_remote_arrived:$normalized';
    if (await _hasNotification(type)) return;

    final shortId = normalized.length < 8
        ? normalized.toUpperCase()
        : normalized.substring(0, 8).toUpperCase();
    final locale = (_preferences.getString('locale_code') ?? 'ar')
        .toLowerCase();
    final (title, message) = switch (locale) {
      'fr' => (
        'Nouveau transfert de stock',
        'Le transfert #$shortId est arrivé avec $lineCount article(s) '
            'et attend la réception.',
      ),
      'en' => (
        'New stock transfer',
        'Transfer #$shortId arrived with $lineCount item(s) and is '
            'awaiting receipt.',
      ),
      _ => (
        'وصل تحويل مخزون جديد',
        'وصل التحويل #$shortId ويحتوي $lineCount بند، وهو بانتظار الاستلام.',
      ),
    };
    await _storeAndNotify(
      type: type,
      title: title,
      message: message,
      transferId: normalized,
      stableKey: 'remote:$normalized',
    );
  }

  /// Watches an authenticated LAN workstation for transfers addressed to its
  /// assigned warehouse. This polls the branch server because that database is
  /// the stock writer that can safely receive and post the document offline.
  void startRemotePolling(
    LanNetworkService network, {
    Duration interval = const Duration(seconds: 15),
  }) {
    _remoteNetwork = network;
    _remotePollTimer?.cancel();
    unawaited(_networkSubscription?.cancel());
    _networkSubscription = network.changes.listen((_) {
      unawaited(_pollRemoteTransfers());
    });
    _remotePollTimer = Timer.periodic(
      interval,
      (_) => unawaited(_pollRemoteTransfers()),
    );
    unawaited(_pollRemoteTransfers());
  }

  Future<void> stopRemotePolling() async {
    _remotePollTimer?.cancel();
    _remotePollTimer = null;
    await _networkSubscription?.cancel();
    _networkSubscription = null;
    _remoteNetwork = null;
  }

  Future<void> _pollRemoteTransfers() async {
    final network = _remoteNetwork;
    if (_remotePollInFlight ||
        network == null ||
        network.snapshot.mode != LanMode.client ||
        network.snapshot.status != LanConnectionStatus.paired ||
        !network.hasRemoteUserSession ||
        !network.supportsCapability('warehouse-transfers-v1')) {
      return;
    }
    final assigned = network.snapshot.assignedWarehouseId;
    if (assigned == null || assigned.isEmpty) return;

    _remotePollInFlight = true;
    try {
      final rows = await network.fetchRemoteWarehouseTransfers(
        statuses: const {'in_transit', 'partially_received'},
        limit: 100,
      );
      for (final row in rows) {
        if (row.destinationWarehouseId == assigned) {
          await notifyRemoteTransfer(
            transferId: row.id,
            lineCount: row.lineCount,
          );
        }
      }
    } on Object catch (error) {
      // Connection state and retry policy belong to the LAN monitor. A
      // transient notification check must never block opening the POS.
      LoggingService.debug(
        'Warehouse transfer notification poll deferred',
        params: {'error': error.toString()},
      );
    } finally {
      _remotePollInFlight = false;
    }
  }

  /// Restores notifications for dispatches projected before this feature was
  /// installed. The durable notification type makes this safe on every start.
  Future<void> reconcilePending() async {
    final rows = await _db.customSelect('''
SELECT transfer_id,dispatch_event_id
FROM distributed_transfer_inbound_dispatches
WHERE lifecycle_state IN('awaiting_receipt','partially_received')
ORDER BY dispatched_at,transfer_id
''').get();
    for (final row in rows) {
      await _notifyTransfer(
        transferId: row.read<String>('transfer_id'),
        eventId: row.read<String>('dispatch_event_id'),
      );
    }
  }

  Future<void> _notifyTransfer({
    required String transferId,
    required String eventId,
  }) async {
    // Non-destination peers retain the central read-only event projection but
    // do not have an actionable inbound dispatch.
    final dispatch = await _db
        .customSelect(
          '''SELECT d.transfer_id,d.allocation_count,
             COALESCE(sw.name,sw.code,d.source_warehouse_id) AS source_name,
             COALESCE(dw.name,dw.code,sdw.name,sdw.code,
                      d.destination_warehouse_id) AS destination_name
           FROM distributed_transfer_inbound_dispatches d
           LEFT JOIN sync_warehouse_directory sw
             ON sw.warehouse_id=d.source_warehouse_id
           LEFT JOIN business_warehouses dw
             ON dw.id=d.destination_warehouse_id
           LEFT JOIN sync_warehouse_directory sdw
             ON sdw.warehouse_id=d.destination_warehouse_id
           WHERE d.transfer_id=? AND d.dispatch_event_id=?''',
          variables: [
            Variable.withString(transferId),
            Variable.withString(eventId),
          ],
        )
        .getSingleOrNull();
    if (dispatch == null) return;

    final type = 'warehouse_transfer_arrived:$eventId';
    if (await _hasNotification(type)) return;

    final shortId = transferId.substring(0, 8).toUpperCase();
    final count = dispatch.read<int>('allocation_count');
    final source = dispatch.read<String>('source_name');
    final destination = dispatch.read<String>('destination_name');
    final locale = (_preferences.getString('locale_code') ?? 'ar')
        .toLowerCase();
    final (title, message) = switch (locale) {
      'fr' => (
        'Nouveau transfert de stock',
        'Le transfert #$shortId de $source vers $destination est arrivé '
            'avec $count article(s) et attend la réception.',
      ),
      'en' => (
        'New stock transfer',
        'Transfer #$shortId from $source to $destination arrived with '
            '$count item(s) and is awaiting receipt.',
      ),
      _ => (
        'وصل تحويل مخزون جديد',
        'وصل التحويل #$shortId من $source إلى $destination ويحتوي '
            '$count بند، وهو بانتظار الاستلام.',
      ),
    };

    await _storeAndNotify(
      type: type,
      title: title,
      message: message,
      transferId: transferId,
      stableKey: eventId,
    );
  }

  Future<bool> _hasNotification(String type) async =>
      await _db
          .customSelect(
            'SELECT 1 AS found FROM notifications WHERE type=? LIMIT 1',
            variables: [Variable.withString(type)],
          )
          .getSingleOrNull() !=
      null;

  Future<void> _storeAndNotify({
    required String type,
    required String title,
    required String message,
    required String transferId,
    required String stableKey,
  }) async {
    await _db
        .into(_db.notifications)
        .insert(
          NotificationsCompanion.insert(
            title: title,
            message: message,
            type: type,
          ),
        );
    try {
      await _notify(
        title: title,
        body: message,
        payload: {'kind': 'warehouse_transfer', 'transferId': transferId},
        stableKey: stableKey,
      );
    } on Object catch (error, stackTrace) {
      // The database row above is the durable, cross-platform notification.
      // A native notification is an optional delivery channel and must never
      // make the authenticated transfer feed or receipt screen fail.
      LoggingService.debug(
        'Warehouse transfer device notification deferred',
        params: {
          'transferId': transferId,
          'error': error.toString(),
          'stackTrace': stackTrace.toString(),
        },
      );
    }
  }
}
