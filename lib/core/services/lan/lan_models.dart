enum LanMode { standalone, master, client }

enum LanConnectionStatus { idle, starting, online, connecting, paired, error }

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
    this.scopeVerified = false,
    this.sessionStartedAt,
    this.sessionExpiresAt,
  });

  bool get hasUserSession => userId != null;
}
