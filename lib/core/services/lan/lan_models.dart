enum LanMode { standalone, master, client }

enum LanConnectionStatus { idle, starting, online, connecting, paired, error }

/// Operational use of an enrolled installation. This is intentionally
/// separate from the signed-in user's permission role.
enum LanDeviceKind { branchWorkstation, warehouseWorkstation, pointOfSale }

enum LanMasterActivityType { sale, saleReturn, saleAdjustmentReturn }

class LanMasterActivityEvent {
  final LanMasterActivityType type;
  final String actorName;
  final String deviceName;
  final String documentNumber;
  final int totalCents;

  const LanMasterActivityEvent({
    required this.type,
    required this.actorName,
    required this.deviceName,
    required this.documentNumber,
    required this.totalCents,
  });
}

class LanRemoteUser {
  final int id;
  final String username;
  final String role;
  final int? employeeId;
  final String? employeeName;
  final String? branchId;
  final String? warehouseId;
  final bool hasGlobalLocationAccess;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastLoginAt;
  final List<String> permissions;

  const LanRemoteUser({
    required this.id,
    required this.username,
    required this.role,
    this.employeeId,
    this.employeeName,
    this.branchId,
    this.warehouseId,
    this.hasGlobalLocationAccess = false,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    this.lastLoginAt,
    this.permissions = const [],
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'username': username,
    'role': role,
    'employeeId': employeeId,
    'employeeName': employeeName,
    'branchId': branchId,
    'warehouseId': warehouseId,
    'hasGlobalLocationAccess': hasGlobalLocationAccess,
    'isActive': isActive,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'lastLoginAt': lastLoginAt?.toUtc().toIso8601String(),
    'permissions': permissions,
  };

  factory LanRemoteUser.fromJson(Map<String, dynamic> json) {
    return LanRemoteUser(
      id: (json['id'] as num).toInt(),
      username: json['username']?.toString() ?? '',
      role: json['role']?.toString() ?? 'salesperson',
      employeeId: (json['employeeId'] as num?)?.toInt(),
      employeeName: json['employeeName']?.toString(),
      branchId: json['branchId']?.toString(),
      warehouseId: json['warehouseId']?.toString(),
      hasGlobalLocationAccess: json['hasGlobalLocationAccess'] == true,
      isActive: json['isActive'] == true,
      createdAt: DateTime.parse(json['createdAt'].toString()),
      updatedAt: DateTime.parse(json['updatedAt'].toString()),
      lastLoginAt: json['lastLoginAt'] == null
          ? null
          : DateTime.tryParse(json['lastLoginAt'].toString()),
      permissions: (json['permissions'] as List<dynamic>? ?? const [])
          .map((value) => value.toString())
          .toList(growable: false),
    );
  }
}

class LanAuthAccount {
  final LanRemoteUser user;
  final String passwordHash;

  const LanAuthAccount({required this.user, required this.passwordHash});
}

class LanAuthAuditEvent {
  final String action;
  final int? targetUserId;
  final String? username;
  final String? role;
  final String deviceId;
  final String deviceName;
  final String? remoteAddress;
  final bool authenticatedActor;
  final int? actorUserId;
  final String? actorUsername;
  final String? reason;

  const LanAuthAuditEvent({
    required this.action,
    this.targetUserId,
    this.username,
    this.role,
    required this.deviceId,
    required this.deviceName,
    this.remoteAddress,
    this.authenticatedActor = false,
    this.actorUserId,
    this.actorUsername,
    this.reason,
  });
}

abstract interface class LanMasterAuthGateway {
  Future<LanAuthAccount?> findActiveAccount(String username);
  Future<void> markLoginSucceeded(int userId);
  Future<void> recordSecurityEvent(LanAuthAuditEvent event);
}

class LanRemoteLoginResult {
  final bool success;
  final LanRemoteUser? user;
  final String? message;

  const LanRemoteLoginResult.success(this.user)
    : success = true,
      message = null;

  const LanRemoteLoginResult.failure(this.message)
    : success = false,
      user = null;
}

class LanNetworkSnapshot {
  final LanMode mode;
  final LanConnectionStatus status;
  final List<String> addresses;
  final int port;
  final String? pairingCode;
  final String? masterHost;
  final String? masterId;
  final String? masterLocaleCode;
  final String? assignedBranchId;
  final String? assignedWarehouseId;
  final String? assignedBranchName;
  final String? assignedWarehouseName;
  final LanDeviceKind? assignedDeviceKind;
  final int pairedDevices;
  final int connectedDevices;
  final String? error;

  const LanNetworkSnapshot({
    this.mode = LanMode.standalone,
    this.status = LanConnectionStatus.idle,
    this.addresses = const [],
    this.port = 45820,
    this.pairingCode,
    this.masterHost,
    this.masterId,
    this.masterLocaleCode,
    this.assignedBranchId,
    this.assignedWarehouseId,
    this.assignedBranchName,
    this.assignedWarehouseName,
    this.assignedDeviceKind,
    this.pairedDevices = 0,
    this.connectedDevices = 0,
    this.error,
  });

  LanNetworkSnapshot copyWith({
    LanMode? mode,
    LanConnectionStatus? status,
    List<String>? addresses,
    int? port,
    String? pairingCode,
    String? masterHost,
    String? masterId,
    String? masterLocaleCode,
    String? assignedBranchId,
    String? assignedWarehouseId,
    String? assignedBranchName,
    String? assignedWarehouseName,
    LanDeviceKind? assignedDeviceKind,
    int? pairedDevices,
    int? connectedDevices,
    String? error,
    bool clearError = false,
    bool clearPairingCode = false,
    bool clearMaster = false,
  }) {
    return LanNetworkSnapshot(
      mode: mode ?? this.mode,
      status: status ?? this.status,
      addresses: addresses ?? this.addresses,
      port: port ?? this.port,
      pairingCode: clearPairingCode ? null : (pairingCode ?? this.pairingCode),
      masterHost: clearMaster ? null : (masterHost ?? this.masterHost),
      masterId: clearMaster ? null : (masterId ?? this.masterId),
      masterLocaleCode: clearMaster
          ? null
          : (masterLocaleCode ?? this.masterLocaleCode),
      assignedBranchId: clearMaster
          ? null
          : (assignedBranchId ?? this.assignedBranchId),
      assignedWarehouseId: clearMaster
          ? null
          : (assignedWarehouseId ?? this.assignedWarehouseId),
      assignedBranchName: clearMaster
          ? null
          : (assignedBranchName ?? this.assignedBranchName),
      assignedWarehouseName: clearMaster
          ? null
          : (assignedWarehouseName ?? this.assignedWarehouseName),
      assignedDeviceKind: clearMaster
          ? null
          : (assignedDeviceKind ?? this.assignedDeviceKind),
      pairedDevices: pairedDevices ?? this.pairedDevices,
      connectedDevices: connectedDevices ?? this.connectedDevices,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class LanPairResult {
  final bool success;
  final String? masterId;
  final String? message;

  const LanPairResult.success(this.masterId) : success = true, message = null;

  const LanPairResult.failure(this.message) : success = false, masterId = null;
}

class LanBranchWriterActivationRequest {
  const LanBranchWriterActivationRequest({
    required this.enrollmentId,
    required this.secret,
    required this.remoteDatabaseId,
  });

  final String enrollmentId;
  final String secret;
  final String remoteDatabaseId;
}

class LanBranchWriterBinding {
  const LanBranchWriterBinding({
    required this.organizationId,
    required this.coordinatorBranchId,
    required this.branchId,
    required this.warehouseId,
    required this.coordinatorDatabaseId,
    required this.accountingCurrencyCode,
    required this.taxPolicy,
    required this.syncAccessToken,
  });

  final String organizationId;
  final String coordinatorBranchId;
  final String branchId;
  final String warehouseId;
  final String coordinatorDatabaseId;
  final String accountingCurrencyCode;
  final Map<String, Object?> taxPolicy;

  /// Long-lived random-derived credential for branch-to-coordinator exchange.
  /// It is returned only over the certificate-pinned activation channel and
  /// is never written to the invitation or coordinator database in plaintext.
  final String syncAccessToken;

  Map<String, Object?> toJson() => {
    'organizationId': organizationId,
    'coordinatorBranchId': coordinatorBranchId,
    'branchId': branchId,
    'warehouseId': warehouseId,
    'coordinatorDatabaseId': coordinatorDatabaseId,
    'accountingCurrencyCode': accountingCurrencyCode,
    'taxPolicy': taxPolicy,
    'syncAccessToken': syncAccessToken,
  };
}

class LanBranchWriterActivationResult {
  const LanBranchWriterActivationResult._({
    required this.success,
    this.message,
    this.binding,
  });

  const LanBranchWriterActivationResult.success([
    LanBranchWriterBinding? binding,
  ]) : this._(success: true, binding: binding);

  const LanBranchWriterActivationResult.failure(String message)
    : this._(success: false, message: message);

  final bool success;
  final String? message;
  final LanBranchWriterBinding? binding;
}

/// Server-side bridge only. The implementation owns authorization and the
/// append-only enrollment registry; the transport never touches its database.
abstract interface class LanBranchEnrollmentGateway {
  Future<LanBranchWriterBinding> activateWriter(
    LanBranchWriterActivationRequest request,
  );
}

class LanBranchSyncAuth {
  const LanBranchSyncAuth({
    required this.enrollmentId,
    required this.remoteDatabaseId,
    required this.accessToken,
  });

  final String enrollmentId;
  final String remoteDatabaseId;
  final String accessToken;
}

class LanBranchSyncPushResult {
  const LanBranchSyncPushResult({
    required this.acceptedEventIds,
    required this.nextExpectedSequence,
  });

  final List<String> acceptedEventIds;
  final int nextExpectedSequence;
}

class LanBranchSyncPullResult {
  const LanBranchSyncPullResult({
    required this.leaseToken,
    required this.events,
  });

  final String leaseToken;
  final List<Map<String, Object?>> events;
}

class LanBranchSyncRunResult {
  const LanBranchSyncRunResult({
    required this.uploaded,
    required this.downloaded,
  });

  final int uploaded;
  final int downloaded;
}

class LanBranchSyncHealthSnapshot {
  const LanBranchSyncHealthSnapshot({
    required this.configured,
    required this.coordinator,
    required this.pendingDeliveries,
    required this.deadLetters,
    required this.activeBranchWriters,
    this.host,
    this.lastSuccessAt,
    this.lastError,
  });

  final bool configured;
  final bool coordinator;
  final String? host;
  final int pendingDeliveries;
  final int deadLetters;
  final int activeBranchWriters;
  final DateTime? lastSuccessAt;
  final String? lastError;
}

/// Server-side coordinator bridge for independent branch replication. Cashier
/// sessions and their permissions are intentionally unrelated to this API.
abstract interface class LanBranchSyncGateway {
  Future<LanBranchSyncPushResult> push(
    LanBranchSyncAuth auth,
    List<Map<String, Object?>> events,
  );

  Future<LanBranchSyncPullResult> pull(
    LanBranchSyncAuth auth, {
    int limit = 50,
  });

  Future<void> acknowledge(
    LanBranchSyncAuth auth, {
    required String leaseToken,
    required List<String> eventIds,
  });
}

/// Safe master-side view of a paired LAN device. Authentication secrets are
/// deliberately never exposed to the presentation layer.
class LanMasterDeviceInfo {
  final String id;
  final String name;
  final String platform;
  final String? remoteAddress;
  final DateTime? pairedAt;
  final DateTime? lastSeenAt;
  final bool isConnected;
  final int? userId;
  final String? username;
  final String? userRole;
  final String? employeeName;
  final String? branchName;
  final String? warehouseName;
  final String? branchId;
  final String? warehouseId;
  final LanDeviceKind deviceKind;
  final List<String> allowedWarehouseIds;
  final bool scopeVerified;
  final DateTime? sessionStartedAt;
  final DateTime? sessionExpiresAt;

  const LanMasterDeviceInfo({
    required this.id,
    required this.name,
    required this.platform,
    this.remoteAddress,
    this.pairedAt,
    this.lastSeenAt,
    required this.isConnected,
    this.userId,
    this.username,
    this.userRole,
    this.employeeName,
    this.branchName,
    this.warehouseName,
    this.branchId,
    this.warehouseId,
    this.deviceKind = LanDeviceKind.warehouseWorkstation,
    this.allowedWarehouseIds = const [],
    this.scopeVerified = false,
    this.sessionStartedAt,
    this.sessionExpiresAt,
  });

  bool get hasUserSession => userId != null;
}

class LanDeviceWarehouseOption {
  const LanDeviceWarehouseOption({
    required this.id,
    required this.branchId,
    required this.branchCode,
    required this.branchName,
    required this.code,
    required this.name,
    required this.isPrimary,
  });

  final String id;
  final String branchId;
  final String branchCode;
  final String branchName;
  final String code;
  final String name;
  final bool isPrimary;
}
