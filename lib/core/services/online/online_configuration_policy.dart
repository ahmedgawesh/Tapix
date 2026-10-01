import '../../database/app_database.dart';
import '../../../features/auth/data/services/session_service.dart';
import '../../../features/business/data/warehouse_setup_service.dart';
import '../business/warehouse_operation_scope.dart';
import 'online_sync_gateway.dart';

/// Mirrors the existing LAN owner/active-user/Pro configuration policy.
class OnlineConfigurationPolicy {
  OnlineConfigurationPolicy(
    this.database,
    this.session,
    this.entitlement, {
    required this.isDependentClient,
  });
  final AppDatabase database;
  final SessionService session;
  final WarehouseSetupEntitlement entitlement;
  final bool Function() isDependentClient;

  Future<void> authorize() async {
    if (isDependentClient()) {
      throw const OnlineSyncException('online_writer_device_required');
    }
    if (!await session.isSessionValid()) {
      throw const OnlineSyncException('owner_required');
    }
    final id = await session.getCurrentUserId();
    if (id == null) throw const OnlineSyncException('owner_required');
    final user = await (database.select(
      database.users,
    )..where((u) => u.id.equals(id))).getSingleOrNull();
    if (user == null || user.isActive != 1 || user.role != 'owner') {
      throw const OnlineSyncException('owner_required');
    }
    if (!await entitlement.permits(
      await WarehouseOperationScope.resolve(database),
    )) {
      throw const OnlineSyncException('pro_required');
    }
  }
}
