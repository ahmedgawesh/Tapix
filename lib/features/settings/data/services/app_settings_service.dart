import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/services/business/branch_tax_policy.dart';
import '../../../../core/services/business/branch_tax_policy_store.dart';
import '../../domain/entities/app_settings.dart';

const _kAppSettingsKey = 'app_settings_v1';

class AppSettingsService {
  final SharedPreferences _prefs;
  final BranchTaxPolicyStore? _taxStore;
  final StreamController<AppSettings> _controller =
      StreamController<AppSettings>.broadcast();
  Future<void> _pending = Future<void>.value();
  BranchTaxPolicySnapshot? _taxSnapshot;
  bool _disposed = false;
  late AppSettings _current;

  AppSettingsService(this._prefs, {BranchTaxPolicyStore? taxStore})
    : _taxStore = taxStore {
    _current = _load();
  }

  AppSettings get current => _current;
  bool get requiresPersistedTaxPolicy => _taxStore != null;
  Stream<AppSettings> get stream => _controller.stream;

  AppSettings _load() {
    final json = _prefs.getString(_kAppSettingsKey);
    return json == null ? const AppSettings() : AppSettings.fromJson(json);
  }

  /// Await before exposing settings or starting the LAN server. An existing
  /// database policy wins over a stale device cache or restored preferences.
  Future<void> initializeTaxPolicy() => _enqueue(() async {
    if (_taxStore == null) return;
    final snapshot = await _taxStore.initializeFromLegacy(_current);
    _taxSnapshot = snapshot;
    _current = snapshot.policy.applyTo(_current);
    _publish();
  });

  Future<void> update(AppSettings settings) => _enqueue(() => _save(settings));

  /// Evaluate patches only when their turn arrives, against the latest state.
  Future<void> patch(AppSettings Function(AppSettings current) patcher) =>
      _enqueue(() => _save(patcher(_current)));

  Future<void> _enqueue(Future<void> Function() action) {
    final result = _pending.then((_) {
      if (_disposed) throw StateError('Settings service is disposed.');
      return action();
    });
    // A failed write must not poison the queue for subsequent retries.
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<void> _save(AppSettings requested) async {
    final store = _taxStore;
    if (store == null) {
      try {
        if (!await _prefs.setString(_kAppSettingsKey, requested.toJson())) {
          throw StateError('Settings could not be saved.');
        }
      } catch (_) {
        await _restorePreferencesCache();
        rethrow;
      }
      _current = requested;
      _publish();
      return;
    }
    final expected = _taxSnapshot;
    if (expected == null) {
      throw StateError('Branch tax policy must be initialized before saving.');
    }
    final desired = BranchTaxPolicy.fromLegacy(requested);
    BranchTaxPolicySnapshot latest;
    try {
      if (desired.hasSameValues(expected.policy)) {
        final stored = await store.read();
        if (stored == null) throw StateError('Branch tax policy is missing.');
        latest = stored;
      } else {
        latest = await store.update(expected: expected, policy: desired);
      }
    } catch (_) {
      // Refresh a stale editor to the committed policy. Corrupt/missing policy
      // is never replaced from preferences as an error-recovery shortcut.
      final stored = await store.read();
      if (stored != null) {
        _taxSnapshot = stored;
        _current = stored.policy.applyTo(_current);
        _publish();
      }
      rethrow;
    }
    _taxSnapshot = latest;
    // The database has committed. Expose its tax values immediately, even if
    // mirroring the device preferences is slow. Non-tax fields wait for save.
    if (!latest.policy.hasSameValues(BranchTaxPolicy.fromLegacy(_current))) {
      _current = latest.policy.applyTo(_current);
      _publish();
    }
    final committed = latest.policy.applyTo(requested);
    try {
      if (!await _prefs.setString(_kAppSettingsKey, committed.toJson())) {
        throw StateError('Device settings could not be saved.');
      }
    } catch (_) {
      await _restorePreferencesCache();
      // SQLite owns taxes and has already committed. Keep those values visible,
      // while retaining prior non-tax preferences if their save failed.
      _current = latest.policy.applyTo(_current);
      _publish();
      rethrow;
    }
    _current = committed;
    _publish();
  }

  Future<void> _restorePreferencesCache() async {
    // SharedPreferences mutates its cache before the platform write completes.
    try {
      await _prefs.reload();
    } catch (_) {
      // Retain _current and propagate the original save failure to the caller.
    }
  }

  void _publish() {
    if (!_disposed) _controller.add(_current);
  }

  void dispose() {
    _disposed = true;
    _controller.close();
  }
}
