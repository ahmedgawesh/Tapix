import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Service that monitors internet connectivity and exposes a stream.
class ConnectivityService {
  final Connectivity _connectivity;
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  final _controller = StreamController<bool>.broadcast();
  bool _lastKnown = false;

  ConnectivityService({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity();

  /// Whether the device currently has internet (best effort).
  bool get isOnline => _lastKnown;

  /// Stream that emits `true` when online, `false` when offline.
  Stream<bool> get onConnectivityChanged => _controller.stream;

  /// Start listening for connectivity changes.
  Future<void> initialize() async {
    // Check initial state
    final results = await _connectivity.checkConnectivity();
    _lastKnown = _hasInternet(results);
    _controller.add(_lastKnown);

    _subscription = _connectivity.onConnectivityChanged.listen((results) {
      final online = _hasInternet(results);
      if (online != _lastKnown) {
        _lastKnown = online;
        _controller.add(online);
        debugPrint('ConnectivityService: ${online ? "ONLINE" : "OFFLINE"}');
      }
    });
  }

  bool _hasInternet(List<ConnectivityResult> results) {
    return results.any((r) =>
        r == ConnectivityResult.wifi ||
        r == ConnectivityResult.mobile ||
        r == ConnectivityResult.ethernet ||
        r == ConnectivityResult.vpn);
  }

  /// Manually check connectivity right now.
  Future<bool> checkNow() async {
    final results = await _connectivity.checkConnectivity();
    _lastKnown = _hasInternet(results);
    return _lastKnown;
  }

  void dispose() {
    _subscription?.cancel();
    _controller.close();
  }
}
