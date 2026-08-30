import 'package:shared_preferences/shared_preferences.dart';

import '../../../features/auth/domain/entities/user_entity.dart';
import '../../database/app_database.dart';
import '../../database/database_reset.dart';
import 'lan_network_service.dart';

enum FreshDeviceModeTarget { standalone, master }

class DeviceModeResetPolicy {
  const DeviceModeResetPolicy._();

  static bool canReset({
    required UserRole localRole,
    required String? remoteRole,
    required LanMode currentMode,
  }) {
    return localRole == UserRole.owner &&
        remoteRole == UserRole.owner.name &&
        currentMode == LanMode.client;
  }
}

/// Performs an owner-only, local reset of a LAN client device.
///
/// No logout, revoke or mutation request is sent to the current master. The
/// master database remains untouched; only this process is stopped and this
/// device local SQLite files are removed.
class DeviceModeResetService {
  DeviceModeResetService({
    required SharedPreferences preferences,
    required AppDatabase database,
    required LanNetworkService lan,
  }) : _preferences = preferences,
       _database = database,
       _lan = lan;

  static const pendingTargetKey = 'lan.fresh_device.pending_target';

  final SharedPreferences _preferences;
  final AppDatabase _database;
  final LanNetworkService _lan;
  bool _applyingPendingTarget = false;

  Future<void> resetClientToFreshDatabase({
    required FreshDeviceModeTarget target,
    required UserRole actorRole,
  }) async {
    if (!DeviceModeResetPolicy.canReset(
      localRole: actorRole,
      remoteRole: _lan.remoteUser?.role,
      currentMode: _lan.snapshot.mode,
    )) {
      throw StateError(
        'Only the authenticated owner may reset a client device.',
      );
    }

    await _preferences.setString(pendingTargetKey, target.name);
    try {
      // Deliberately use stop(), not logoutFromMaster(): resetting this device
      // must not modify the active master or its authorization records.
      await _lan.stop();
      await _database.close();
      await DatabaseReset.deleteAllLocalDatabaseFiles();
    } catch (_) {
      await _preferences.remove(pendingTargetKey);
      rethrow;
    }
  }

  /// Applies a saved mode only after the fresh database has its first owner.
  /// Until then the new database remains standalone and cannot accept clients.
  Future<void> applyPendingTargetForOwner(UserEntity user) async {
    if (_applyingPendingTarget || user.role != UserRole.owner) return;
    final stored = _preferences.getString(pendingTargetKey);
    FreshDeviceModeTarget? target;
    for (final value in FreshDeviceModeTarget.values) {
      if (value.name == stored) {
        target = value;
        break;
      }
    }
    if (target == null) return;

    _applyingPendingTarget = true;
    try {
      switch (target) {
        case FreshDeviceModeTarget.standalone:
          await _lan.setStandalone();
          break;
        case FreshDeviceModeTarget.master:
          await _lan.startMaster();
          break;
      }
      await _preferences.remove(pendingTargetKey);
    } finally {
      _applyingPendingTarget = false;
    }
  }
}
