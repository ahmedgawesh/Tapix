import 'dart:async';

import 'package:flutter/foundation.dart';

import '../lan/lan_models.dart';
import '../sync/offline_sync_event_store.dart';
import 'online_branch_sync_service.dart';
import 'online_sync_gateway.dart';

enum OnlineSyncState {
  unconfigured,
  paused,
  syncing,
  healthy,
  retrying,
  blocked,
}

/// Runs while the app is active; resume triggers an immediate check. Credentials
/// are reloaded by the service, and timers never overlap an in-flight exchange.
class OnlineSyncController extends ChangeNotifier {
  OnlineSyncController({
    required Future<OnlineConnectionSummary?> Function() inspect,
    required Future<LanBranchSyncRunResult> Function() synchronize,
    required bool Function() canRun,
    DateTime Function()? clock,
  }) : _inspect = inspect,
       _synchronize = synchronize,
       _canRun = canRun,
       _clock = clock ?? DateTime.now;

  final Future<OnlineConnectionSummary?> Function() _inspect;
  final Future<LanBranchSyncRunResult> Function() _synchronize;
  final bool Function() _canRun;
  final DateTime Function() _clock;
  Timer? _timer;
  Future<void>? _inFlight;
  bool _active = false, _disposed = false;
  int _failures = 0;
  OnlineSyncState state = OnlineSyncState.unconfigured;
  String? errorCode;
  DateTime? lastSuccess, nextAttempt;
  LanBranchSyncRunResult? lastResult;

  void start() {
    if (_disposed) return;
    _active = true;
    unawaited(refresh());
  }

  void stop() {
    _active = false;
    _timer?.cancel();
    _timer = null;
    nextAttempt = null;
  }

  Future<void> refresh() {
    if (_disposed) return Future.value();
    _timer?.cancel();
    _timer = null;
    nextAttempt = null;
    return _inFlight ??= _run().whenComplete(() => _inFlight = null);
  }

  Future<void> _run() async {
    Duration? delay;
    try {
      if (!_canRun()) {
        state = OnlineSyncState.paused;
        errorCode = 'online_writer_device_required';
        return;
      }
      final config = await _inspect();
      if (_disposed) return;
      errorCode = null;
      if (config == null) {
        state = OnlineSyncState.unconfigured;
        return;
      }
      if (!config.enabled) {
        state = OnlineSyncState.paused;
        return;
      }
      state = OnlineSyncState.syncing;
      notifyListeners();
      lastResult = await _synchronize();
      if (_disposed) return;
      lastSuccess = _clock().toUtc();
      state = OnlineSyncState.healthy;
      _failures = 0;
      // Drain batches promptly, with a bounded pause between exchanges.
      delay = Duration(
        seconds: lastResult!.uploaded >= 50 || lastResult!.downloaded >= 50
            ? 1
            : 15,
      );
    } catch (error) {
      if (_disposed) return;
      errorCode = error is OnlineSyncException
          ? error.code
          : error is OfflineSyncException
          ? error.code
          : 'online_sync_failed';
      if (errorCode == 'online_writer_not_enrolled' ||
          errorCode == 'online_not_configured') {
        state = OnlineSyncState.unconfigured;
      } else if (errorCode == 'online_paused') {
        state = OnlineSyncState.paused;
      } else if (const {
        'online_connection_unavailable',
        'storage_unavailable',
        'service_unavailable',
        'server_busy',
        'request_timeout',
        'online_sync_busy',
        'online_sync_failed',
      }.contains(errorCode)) {
        state = OnlineSyncState.retrying;
        _failures = (_failures + 1).clamp(1, 6);
        delay = Duration(seconds: (5 * (1 << (_failures - 1))).clamp(5, 160));
      } else {
        // Identity, entitlement and contract failures need attention; do not
        // hammer the service or hide them behind a green connection indicator.
        state = OnlineSyncState.blocked;
      }
    } finally {
      if (!_disposed) {
        if (_active && delay != null) {
          nextAttempt = _clock().toUtc().add(delay);
          _timer = Timer(delay, () => unawaited(refresh()));
        }
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    stop();
    _disposed = true;
    super.dispose();
  }
}
