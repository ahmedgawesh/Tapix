import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/services/audit_log_service.dart';
import '../../../../core/services/lan/lan_models.dart';
import '../../domain/entities/user_entity.dart';
import 'permission_service.dart';

class LanMasterAuthGatewayImpl implements LanMasterAuthGateway {
  LanMasterAuthGatewayImpl({
    required AppDatabase database,
    required PermissionService permissionService,
    required AuditLogService auditLogService,
  }) : _database = database,
       _permissionService = permissionService,
       _auditLogService = auditLogService;

  final AppDatabase _database;
  final PermissionService _permissionService;
  final AuditLogService _auditLogService;

  @override
  Future<LanAuthAccount?> findActiveAccount(String username) async {
    final normalized = username.trim();
    if (normalized.isEmpty) return null;

    final query = _database.select(_database.users)
      ..where((user) => user.username.equals(normalized))
      ..where((user) => user.isActive.equals(1));
    final row = await query.getSingleOrNull();
    if (row == null) return null;

    final role = UserRole.fromString(row.role);
    final employee = row.employeeId == null
        ? null
        : await (_database.select(_database.employees)
                ..where((value) => value.id.equals(row.employeeId!))
                ..limit(1))
              .getSingleOrNull();
    // Legacy cashier accounts may still sign in so the UI can explain that
    // an employee link is required. Opening a shift or posting a sale remains
    // blocked by the master until an active employee is linked.
    return LanAuthAccount(
      passwordHash: row.passwordHash,
      user: LanRemoteUser(
        id: row.id,
        username: row.username,
        role: role.name,
        employeeId: employee?.id,
        employeeName: employee?.name,
        isActive: row.isActive == 1,
        createdAt: row.createdAt,
        updatedAt: row.updatedAt,
        lastLoginAt: row.lastLoginAt,
        permissions: _permissionService.getPermissionsForRole(role),
      ),
    );
  }

  @override
  Future<void> markLoginSucceeded(int userId) async {
    await (_database.update(_database.users)
          ..where((user) => user.id.equals(userId)))
        .write(UsersCompanion(lastLoginAt: Value(DateTime.now())));
  }

  @override
  Future<void> recordSecurityEvent(LanAuthAuditEvent event) {
    return _auditLogService
        .logLanSecurityEvent(
          action: event.action,
          targetUserId: event.targetUserId,
          username: event.username,
          role: event.role,
          deviceId: event.deviceId,
          deviceName: event.deviceName,
          remoteAddress: event.remoteAddress,
          authenticatedActor: event.authenticatedActor,
          actorUserId: event.actorUserId,
          actorUsername: event.actorUsername,
          reason: event.reason,
        )
        .then((_) {});
  }
}
