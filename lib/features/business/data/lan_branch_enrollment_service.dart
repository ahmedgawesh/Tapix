import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/services/audit_log_service.dart';
import '../../../core/services/business/branch_currency_policy_store.dart';
import '../../../core/services/business/branch_tax_policy_store.dart';
import '../../../core/services/business/warehouse_operation_scope.dart';
import '../../../core/services/lan/lan_models.dart';
import '../../../core/services/sync/offline_sync_event_store.dart';
import '../../../core/services/sync/branch_catalogue_sync_service.dart';
import '../../../core/services/sync/branch_location_directory_sync_service.dart';
import '../../auth/data/services/session_service.dart';
import 'warehouse_setup_service.dart';

class LanBranchEnrollmentException implements Exception {
  const LanBranchEnrollmentException(this.code);

  final String code;

  @override
  String toString() => 'LanBranchEnrollmentException($code)';
}

class LanBranchInvitation {
  const LanBranchInvitation({
    required this.enrollmentId,
    required this.organizationId,
    required this.organizationName,
    required this.coordinatorBranchId,
    required this.branchId,
    required this.branchName,
    required this.branchCode,
    required this.warehouseId,
    required this.warehouseName,
    required this.warehouseCode,
    required this.coordinatorDatabaseId,
    required this.secret,
    required this.expiresAt,
    this.recovery = false,
    this.expectedRemoteDatabaseId,
  });

  final String enrollmentId;
  final String organizationId;
  final String organizationName;
  final String coordinatorBranchId;
  final String branchId;
  final String branchName;
  final String branchCode;
  final String warehouseId;
  final String warehouseName;
  final String warehouseCode;
  final String coordinatorDatabaseId;
  final String secret;
  final DateTime expiresAt;
  final bool recovery;
  final String? expectedRemoteDatabaseId;

  Map<String, Object?> toJson() => {
    'enrollmentId': enrollmentId,
    'organizationId': organizationId,
    'organizationName': organizationName,
    'coordinatorBranchId': coordinatorBranchId,
    'branchId': branchId,
    'branchName': branchName,
    'branchCode': branchCode,
    'warehouseId': warehouseId,
    'warehouseName': warehouseName,
    'warehouseCode': warehouseCode,
    'coordinatorDatabaseId': coordinatorDatabaseId,
    'secret': secret,
    'expiresAt': expiresAt.toUtc().toIso8601String(),
    'recovery': recovery,
    if (expectedRemoteDatabaseId != null)
      'expectedRemoteDatabaseId': expectedRemoteDatabaseId,
  };

  String encode() => base64Url.encode(utf8.encode(jsonEncode(toJson())));
}

class LanBranchConnectionInvitation {
  const LanBranchConnectionInvitation({
    required this.hosts,
    required this.port,
    required this.coordinatorFingerprint,
    required this.branch,
  });

  final List<String> hosts;
  final int port;
  final String coordinatorFingerprint;
  final LanBranchInvitation branch;

  String encode() => base64Url.encode(
    utf8.encode(
      jsonEncode({
        'type': 'tapix.lan.branch.enrollment',
        'version': 1,
        'hosts': hosts,
        'port': port,
        'coordinatorFingerprint': coordinatorFingerprint,
        'branch': branch.toJson(),
      }),
    ),
  );

  factory LanBranchConnectionInvitation.decode(
    String encoded, {
    DateTime? now,
  }) {
    try {
      final decoded = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(encoded.trim()))),
      );
      if (decoded is! Map<String, dynamic> ||
          decoded['type'] != 'tapix.lan.branch.enrollment' ||
          decoded['version'] != 1 ||
          decoded['branch'] is! Map) {
        throw const FormatException('Invalid branch invitation');
      }
      final rawHosts = decoded['hosts'];
      final port = decoded['port'];
      final fingerprint = decoded['coordinatorFingerprint']?.toString() ?? '';
      if (rawHosts is! List ||
          rawHosts.isEmpty ||
          rawHosts.length > 8 ||
          port is! int ||
          port < 1 ||
          port > 65535 ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(fingerprint)) {
        throw const FormatException('Invalid branch invitation network');
      }
      final hosts = rawHosts.map((value) => value.toString().trim()).toList();
      if (hosts.any(
        (host) =>
            host.isEmpty ||
            host.length > 253 ||
            RegExp(r'[\s/\\]').hasMatch(host),
      )) {
        throw const FormatException('Invalid branch invitation host');
      }
      final raw = Map<String, dynamic>.from(decoded['branch'] as Map);
      String text(String key, {int max = 100, bool allowEmpty = false}) {
        final value = raw[key]?.toString() ?? '';
        if ((!allowEmpty && value.isEmpty) || value.length > max) {
          throw const FormatException('Invalid branch invitation field');
        }
        return value;
      }

      final ids = [
        text('enrollmentId', max: 36),
        text('organizationId', max: 36),
        text('coordinatorBranchId', max: 36),
        text('branchId', max: 36),
        text('warehouseId', max: 36),
        text('coordinatorDatabaseId', max: 36),
      ];
      if (ids.any((id) => !Uuid.isValidUUID(fromString: id))) {
        throw const FormatException('Invalid branch invitation identity');
      }
      final secret = text('secret', max: 128);
      final expiresAt = DateTime.parse(text('expiresAt', max: 40)).toUtc();
      final recovery = raw['recovery'] == true;
      final expectedRemoteDatabaseId = raw['expectedRemoteDatabaseId']
          ?.toString();
      if (expectedRemoteDatabaseId != null &&
          !Uuid.isValidUUID(fromString: expectedRemoteDatabaseId)) {
        throw const FormatException('Invalid recovery database identity');
      }
      if (recovery && expectedRemoteDatabaseId == null) {
        throw const FormatException('Missing recovery database identity');
      }
      if (!(now ?? DateTime.now()).toUtc().isBefore(expiresAt)) {
        throw const FormatException('Expired branch invitation');
      }
      return LanBranchConnectionInvitation(
        hosts: List.unmodifiable(hosts),
        port: port,
        coordinatorFingerprint: fingerprint,
        branch: LanBranchInvitation(
          enrollmentId: ids[0],
          organizationId: ids[1],
          organizationName: text('organizationName', allowEmpty: true),
          coordinatorBranchId: ids[2],
          branchId: ids[3],
          branchName: text('branchName', allowEmpty: true),
          branchCode: text('branchCode', max: 32),
          warehouseId: ids[4],
          warehouseName: text('warehouseName', allowEmpty: true),
          warehouseCode: text('warehouseCode', max: 32),
          coordinatorDatabaseId: ids[5],
          secret: secret,
          expiresAt: expiresAt,
          recovery: recovery,
          expectedRemoteDatabaseId: expectedRemoteDatabaseId,
        ),
      );
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('Invalid branch invitation');
    }
  }
}

class LanBranchEnrollmentRecord {
  const LanBranchEnrollmentRecord({
    required this.enrollmentId,
    required this.branchId,
    required this.branchName,
    required this.branchCode,
    required this.warehouseName,
    required this.status,
    required this.expiresAt,
    this.remoteDatabaseId,
  });

  final String enrollmentId;
  final String branchId;
  final String branchName;
  final String branchCode;
  final String warehouseName;
  final String status;
  final DateTime expiresAt;
  final String? remoteDatabaseId;
}

/// Coordinator-side enrollment authority for independent LAN branch writers.
/// Cashier-device pairing is a separate protocol. The Pro entitlement is the
/// only commercial gate here; the online-branches add-on is never consulted.
class LanBranchEnrollmentService {
  LanBranchEnrollmentService(
    this._db,
    this._session,
    this._entitlement,
    this._syncEvents, {
    required bool Function() isDependentLanClient,
    required BranchCurrencyPolicyStore currencyPolicy,
    required BranchTaxPolicyStore taxPolicy,
    required String Function() operatingCurrencyCode,
    BranchCatalogueSyncService? catalogue,
    BranchLocationDirectorySyncService? locations,
    Random? random,
    Uuid uuid = const Uuid(),
  }) : _isDependentLanClient = isDependentLanClient,
       _currencyPolicy = currencyPolicy,
       _taxPolicy = taxPolicy,
       _operatingCurrencyCode = operatingCurrencyCode,
       _catalogue = catalogue,
       _locations = locations,
       _random = random ?? Random.secure(),
       _uuid = uuid;

  final AppDatabase _db;
  final SessionService _session;
  final WarehouseSetupEntitlement _entitlement;
  final OfflineSyncEventStore _syncEvents;
  final bool Function() _isDependentLanClient;
  final BranchCurrencyPolicyStore _currencyPolicy;
  final BranchTaxPolicyStore _taxPolicy;
  final String Function() _operatingCurrencyCode;
  final BranchCatalogueSyncService? _catalogue;
  final BranchLocationDirectorySyncService? _locations;
  final Random _random;
  final Uuid _uuid;

  Future<({int actorId, WarehouseOperationScope scope})> _authorize() async {
    if (_isDependentLanClient()) {
      throw const LanBranchEnrollmentException('dependent_client_denied');
    }
    final actorId = await _session.getCurrentUserId();
    if (actorId == null) {
      throw const LanBranchEnrollmentException('owner_required');
    }
    final user = await (_db.select(
      _db.users,
    )..where((row) => row.id.equals(actorId))).getSingleOrNull();
    if (user == null || user.isActive != 1 || user.role != 'owner') {
      throw const LanBranchEnrollmentException('owner_required');
    }
    final scope = await WarehouseOperationScope.resolve(_db);
    if (!await _entitlement.permits(scope)) {
      throw const LanBranchEnrollmentException('pro_required');
    }
    return (actorId: actorId, scope: scope);
  }

  Future<String> _ensureCoordinatorWriter(WarehouseOperationScope scope) async {
    final writerId = await _db.transaction(() async {
      final existing = await _db
          .customSelect(
            'SELECT organization_id,database_id,writer_enrollment_id '
            'FROM lan_branch_coordinator_state WHERE id=1',
          )
          .getSingleOrNull();
      if (existing != null) {
        if (existing.read<String>('organization_id') != scope.organizationId ||
            existing.read<String>('database_id') != scope.databaseId) {
          throw const LanBranchEnrollmentException(
            'coordinator_identity_conflict',
          );
        }
        return existing.read<String>('writer_enrollment_id');
      }
      final created = _uuid.v4().toLowerCase();
      await _db.customStatement(
        'INSERT INTO lan_branch_coordinator_state('
        'id,organization_id,database_id,writer_enrollment_id) VALUES(1,?,?,?)',
        [scope.organizationId, scope.databaseId, created],
      );
      return created;
    });
    // Idempotent and immutable. This enables the local outbox for LAN branch
    // synchronization without using the paid online entitlement.
    await _syncEvents.activateWriterRecording(enrollmentId: writerId);
    return writerId;
  }

  Future<LanBranchInvitation> issueInvitation({
    required String branchId,
    required String warehouseId,
    Duration validity = const Duration(minutes: 15),
    DateTime? now,
  }) => _issueInvitation(
    branchId: branchId,
    warehouseId: warehouseId,
    validity: validity,
    now: now,
    replaceActive: false,
  );

  /// Fences the old branch server before issuing credentials for a fresh
  /// replacement database. The old device may keep working locally while it
  /// is disconnected, but its credential and event source are quarantined and
  /// can no longer enter the company stream when it returns.
  Future<LanBranchInvitation> issueReplacementInvitation({
    required String branchId,
    required String warehouseId,
    required String reason,
    Duration validity = const Duration(minutes: 15),
    DateTime? now,
  }) {
    final cleanReason = reason.trim();
    if (cleanReason.isEmpty || cleanReason.length > 500) {
      throw const LanBranchEnrollmentException('replacement_reason_required');
    }
    return _issueInvitation(
      branchId: branchId,
      warehouseId: warehouseId,
      validity: validity,
      now: now,
      replaceActive: true,
      replacementReason: cleanReason,
    );
  }

  /// Fences a lost device and rotates credentials for an exact database backup
  /// restore. The restored database keeps its immutable database id, local
  /// sequence and writer enrollment; only the network credential changes.
  Future<LanBranchInvitation> issueBackupRecoveryInvitation({
    required String branchId,
    required String reason,
    Duration validity = const Duration(minutes: 15),
    DateTime? now,
  }) async {
    final cleanReason = reason.trim();
    if (cleanReason.isEmpty || cleanReason.length > 500) {
      throw const LanBranchEnrollmentException('replacement_reason_required');
    }
    if (validity < const Duration(minutes: 1) ||
        validity > const Duration(hours: 1)) {
      throw const LanBranchEnrollmentException('invalid_validity');
    }
    final auth = await _authorize();
    final clock = (now ?? DateTime.now()).toUtc();
    final expiresAt = clock.add(validity);
    final secretBytes = List<int>.generate(32, (_) => _random.nextInt(256));
    final secret = base64Url.encode(secretBytes).replaceAll('=', '');
    final secretHash = sha256.convert(utf8.encode(secret)).toString();
    final challengeId = _uuid.v4().toLowerCase();
    return _db.transaction(() async {
      final row = await _db
          .customSelect(
            '''SELECT e.enrollment_id,e.warehouse_id,e.remote_database_id,
            o.name AS organization_name,b.name AS branch_name,
            b.code AS branch_code,w.name AS warehouse_name,w.code AS warehouse_code
            FROM lan_branch_enrollments e
            JOIN business_branches b ON b.id=e.branch_id
            JOIN business_organizations o ON o.id=e.organization_id
            JOIN business_warehouses w ON w.id=e.warehouse_id
            WHERE e.branch_id=? AND e.organization_id=? AND e.status='active' ''',
            variables: [
              Variable.withString(branchId),
              Variable.withString(auth.scope.organizationId),
            ],
          )
          .getSingleOrNull();
      final remoteDatabaseId = row?.readNullable<String>('remote_database_id');
      if (row == null || remoteDatabaseId == null) {
        throw const LanBranchEnrollmentException('branch_not_enrolled');
      }
      final enrollmentId = row.read<String>('enrollment_id');
      await _db.customStatement(
        "UPDATE lan_branch_recovery_challenges SET status='revoked' "
        "WHERE enrollment_id=? AND status='pending'",
        [enrollmentId],
      );
      await _db.customStatement(
        "UPDATE lan_branch_sync_credentials SET status='revoked' "
        "WHERE enrollment_id=? AND status='active'",
        [enrollmentId],
      );
      await _db.customStatement(
        "UPDATE lan_branch_recovery_credentials SET status='revoked' "
        "WHERE enrollment_id=? AND status='active'",
        [enrollmentId],
      );
      await _db.customStatement(
        "UPDATE sync_source_checkpoints SET status='quarantined',updated_at=? "
        'WHERE source_database_id=?',
        [clock.toIso8601String(), remoteDatabaseId],
      );
      await _db.customStatement(
        "UPDATE sync_delivery_peers SET status='quarantined',updated_at=? "
        'WHERE target_database_id=?',
        [clock.toIso8601String(), remoteDatabaseId],
      );
      await _db.customStatement(
        '''INSERT INTO lan_branch_recovery_challenges(
        challenge_id,enrollment_id,remote_database_id,secret_hash,reason,
        issued_by,expires_at) VALUES(?,?,?,?,?,?,?)''',
        [
          challengeId,
          enrollmentId,
          remoteDatabaseId,
          secretHash,
          cleanReason,
          auth.actorId,
          expiresAt.toIso8601String(),
        ],
      );
      await AuditLogService(_db).log(
        entityType: 'business_branches',
        entityId: auth.actorId,
        action: 'issue_lan_branch_backup_recovery',
        userId: auth.actorId,
        userRole: 'owner',
        newValue: {
          'challengeId': challengeId,
          'enrollmentId': enrollmentId,
          'branchId': branchId,
          'remoteDatabaseId': remoteDatabaseId,
          'reason': cleanReason,
          'expiresAt': expiresAt.toIso8601String(),
        },
      );
      return LanBranchInvitation(
        enrollmentId: enrollmentId,
        organizationId: auth.scope.organizationId,
        organizationName: row.read<String>('organization_name'),
        coordinatorBranchId: auth.scope.branchId,
        branchId: branchId,
        branchName: row.read<String>('branch_name'),
        branchCode: row.read<String>('branch_code'),
        warehouseId: row.read<String>('warehouse_id'),
        warehouseName: row.read<String>('warehouse_name'),
        warehouseCode: row.read<String>('warehouse_code'),
        coordinatorDatabaseId: auth.scope.databaseId,
        secret: secret,
        expiresAt: expiresAt,
        recovery: true,
        expectedRemoteDatabaseId: remoteDatabaseId,
      );
    });
  }

  Future<LanBranchInvitation> _issueInvitation({
    required String branchId,
    required String warehouseId,
    required Duration validity,
    required DateTime? now,
    required bool replaceActive,
    String? replacementReason,
  }) async {
    final auth = await _authorize();
    if (validity < const Duration(minutes: 1) ||
        validity > const Duration(hours: 1)) {
      throw const LanBranchEnrollmentException('invalid_validity');
    }
    final clock = (now ?? DateTime.now()).toUtc();
    final expiresAt = clock.add(validity);
    final secretBytes = List<int>.generate(32, (_) => _random.nextInt(256));
    final secret = base64Url.encode(secretBytes).replaceAll('=', '');
    final secretHash = sha256.convert(utf8.encode(secret)).toString();
    final enrollmentId = _uuid.v4().toLowerCase();

    return _db.transaction(() async {
      final row = await _db
          .customSelect(
            '''SELECT o.name AS organization_name,
            b.name AS branch_name,b.code AS branch_code,
            w.name AS warehouse_name,w.code AS warehouse_code
            FROM business_branches b
            JOIN business_organizations o ON o.id=b.organization_id
            JOIN business_warehouses w
              ON w.branch_id=b.id AND w.organization_id=b.organization_id
            WHERE b.id=? AND w.id=? AND b.organization_id=?
              AND b.is_active=1 AND w.is_active=1''',
            variables: [
              Variable.withString(branchId),
              Variable.withString(warehouseId),
              Variable.withString(auth.scope.organizationId),
            ],
          )
          .getSingleOrNull();
      if (row == null || branchId == auth.scope.branchId) {
        throw const LanBranchEnrollmentException('invalid_independent_branch');
      }
      final active = await _db
          .customSelect(
            'SELECT enrollment_id,remote_database_id FROM lan_branch_enrollments '
            "WHERE branch_id=? AND status='active'",
            variables: [Variable.withString(branchId)],
          )
          .getSingleOrNull();
      if (active != null && !replaceActive) {
        throw const LanBranchEnrollmentException('branch_already_enrolled');
      }
      if (await _currencyPolicy.read() == null) {
        await _currencyPolicy.bind(_operatingCurrencyCode());
      }
      if (await _taxPolicy.read() == null) {
        throw const LanBranchEnrollmentException('tax_policy_required');
      }
      await _ensureCoordinatorWriter(auth.scope);
      if (active != null) {
        final oldEnrollment = active.read<String>('enrollment_id');
        final oldDatabase = active.readNullable<String>('remote_database_id');
        await _db.customStatement(
          "UPDATE lan_branch_sync_credentials SET status='revoked' "
          'WHERE enrollment_id=?',
          [oldEnrollment],
        );
        await _db.customStatement(
          "UPDATE lan_branch_enrollments SET status='revoked' "
          'WHERE enrollment_id=?',
          [oldEnrollment],
        );
        if (oldDatabase != null) {
          await _db.customStatement(
            "UPDATE sync_source_checkpoints SET status='quarantined',"
            'updated_at=? WHERE source_database_id=?',
            [clock.toIso8601String(), oldDatabase],
          );
          await _db.customStatement(
            "UPDATE sync_delivery_peers SET status='revoked',updated_at=? "
            'WHERE target_database_id=?',
            [clock.toIso8601String(), oldDatabase],
          );
        }
      }
      await _db.customStatement(
        "UPDATE lan_branch_enrollments SET status='revoked' "
        "WHERE branch_id=? AND status='pending'",
        [branchId],
      );
      await _db.customStatement(
        '''INSERT INTO lan_branch_enrollments(
          enrollment_id,organization_id,branch_id,warehouse_id,
          coordinator_database_id,secret_hash,status,issued_by,expires_at)
          VALUES(?,?,?,?,?,?,'pending',?,?)''',
        [
          enrollmentId,
          auth.scope.organizationId,
          branchId,
          warehouseId,
          auth.scope.databaseId,
          secretHash,
          auth.actorId,
          expiresAt.toIso8601String(),
        ],
      );
      await AuditLogService(_db).log(
        entityType: 'business_branches',
        entityId: auth.actorId,
        action: 'issue_lan_branch_invitation',
        userId: auth.actorId,
        userRole: 'owner',
        newValue: {
          'enrollmentId': enrollmentId,
          'branchId': branchId,
          'warehouseId': warehouseId,
          'expiresAt': expiresAt.toIso8601String(),
          if (active != null) ...{
            'replacesEnrollmentId': active.read<String>('enrollment_id'),
            'replacesDatabaseId': active.readNullable<String>(
              'remote_database_id',
            ),
            'replacementReason': replacementReason,
          },
        },
      );
      return LanBranchInvitation(
        enrollmentId: enrollmentId,
        organizationId: auth.scope.organizationId,
        organizationName: row.read<String>('organization_name'),
        coordinatorBranchId: auth.scope.branchId,
        branchId: branchId,
        branchName: row.read<String>('branch_name'),
        branchCode: row.read<String>('branch_code'),
        warehouseId: warehouseId,
        warehouseName: row.read<String>('warehouse_name'),
        warehouseCode: row.read<String>('warehouse_code'),
        coordinatorDatabaseId: auth.scope.databaseId,
        secret: secret,
        expiresAt: expiresAt,
      );
    });
  }

  /// Completes the coordinator side only after the remote fresh database has
  /// proved possession of the one-time secret and supplies its unique DB id.
  Future<LanBranchWriterBinding> activateRemoteWriter({
    required String enrollmentId,
    required String secret,
    required String remoteDatabaseId,
    DateTime? now,
  }) async {
    final normalizedEnrollment = enrollmentId.trim().toLowerCase();
    final normalizedDatabase = remoteDatabaseId.trim().toLowerCase();
    if (!Uuid.isValidUUID(fromString: normalizedEnrollment) ||
        !Uuid.isValidUUID(fromString: normalizedDatabase) ||
        secret.isEmpty) {
      throw const LanBranchEnrollmentException('invalid_invitation');
    }
    final clock = (now ?? DateTime.now()).toUtc();
    final syncAccessToken = _deriveSyncAccessToken(
      enrollmentId: normalizedEnrollment,
      remoteDatabaseId: normalizedDatabase,
      secret: secret,
    );
    final syncTokenHash = sha256
        .convert(utf8.encode(syncAccessToken))
        .toString();
    var recoveryExpired = false;
    await _db.transaction(() async {
      final row = await _db
          .customSelect(
            'SELECT * FROM lan_branch_enrollments WHERE enrollment_id=?',
            variables: [Variable.withString(normalizedEnrollment)],
          )
          .getSingleOrNull();
      if (row == null) {
        throw const LanBranchEnrollmentException('invitation_not_pending');
      }
      final suppliedHash = sha256.convert(utf8.encode(secret)).toString();
      final recovery = await _db
          .customSelect(
            'SELECT * FROM lan_branch_recovery_challenges '
            "WHERE enrollment_id=? AND status='pending'",
            variables: [Variable.withString(normalizedEnrollment)],
          )
          .getSingleOrNull();
      if (recovery != null &&
          _constantTimeEquals(
            recovery.read<String>('secret_hash'),
            suppliedHash,
          )) {
        if (!clock.isBefore(
          DateTime.parse(recovery.read<String>('expires_at')).toUtc(),
        )) {
          await _db.customStatement(
            "UPDATE lan_branch_recovery_challenges SET status='revoked' "
            'WHERE challenge_id=?',
            [recovery.read<String>('challenge_id')],
          );
          recoveryExpired = true;
          return;
        }
        if (row.read<String>('status') != 'active' ||
            row.readNullable<String>('remote_database_id') !=
                normalizedDatabase ||
            recovery.read<String>('remote_database_id') != normalizedDatabase) {
          throw const LanBranchEnrollmentException(
            'writer_activation_conflict',
          );
        }
        await _db.customStatement(
          "UPDATE lan_branch_recovery_credentials SET status='revoked' "
          "WHERE enrollment_id=? AND status='active'",
          [normalizedEnrollment],
        );
        final generation = await _db
            .customSelect(
              'SELECT COALESCE(MAX(generation),0)+1 AS generation '
              'FROM lan_branch_recovery_credentials WHERE enrollment_id=?',
              variables: [Variable.withString(normalizedEnrollment)],
            )
            .map((value) => value.read<int>('generation'))
            .getSingle();
        await _db.customStatement(
          '''INSERT INTO lan_branch_recovery_credentials(
          challenge_id,enrollment_id,remote_database_id,token_hash,generation)
          VALUES(?,?,?,?,?)''',
          [
            recovery.read<String>('challenge_id'),
            normalizedEnrollment,
            normalizedDatabase,
            syncTokenHash,
            generation,
          ],
        );
        await _db.customStatement(
          "UPDATE lan_branch_recovery_challenges SET status='used',used_at=? "
          'WHERE challenge_id=?',
          [clock.toIso8601String(), recovery.read<String>('challenge_id')],
        );
        await _db.customStatement(
          "UPDATE sync_source_checkpoints SET status='active',updated_at=? "
          'WHERE source_database_id=?',
          [clock.toIso8601String(), normalizedDatabase],
        );
        await _db.customStatement(
          "UPDATE sync_delivery_peers SET status='active',updated_at=? "
          'WHERE target_database_id=?',
          [clock.toIso8601String(), normalizedDatabase],
        );
        await AuditLogService(_db).log(
          entityType: 'business_branches',
          entityId: row.read<int>('issued_by'),
          action: 'activate_lan_branch_backup_recovery',
          userId: row.read<int>('issued_by'),
          userRole: 'owner',
          newValue: {
            'challengeId': recovery.read<String>('challenge_id'),
            'enrollmentId': normalizedEnrollment,
            'branchId': row.read<String>('branch_id'),
            'remoteDatabaseId': normalizedDatabase,
            'generation': generation,
          },
        );
        return;
      }
      final secretMatches = _constantTimeEquals(
        row.read<String>('secret_hash'),
        suppliedHash,
      );
      final enrollmentStatus = row.read<String>('status');
      if (enrollmentStatus == 'active') {
        if (!secretMatches ||
            row.readNullable<String>('remote_database_id') !=
                normalizedDatabase) {
          throw const LanBranchEnrollmentException(
            'writer_activation_conflict',
          );
        }
        await _syncEvents.enrollSource(
          sourceDatabaseId: normalizedDatabase,
          organizationId: row.read<String>('organization_id'),
          branchId: row.read<String>('branch_id'),
        );
        await _syncEvents.registerDeliveryPeer(
          targetDatabaseId: normalizedDatabase,
          organizationId: row.read<String>('organization_id'),
          branchId: row.read<String>('branch_id'),
        );
        await _ensureSyncCredential(
          enrollmentId: normalizedEnrollment,
          remoteDatabaseId: normalizedDatabase,
          tokenHash: syncTokenHash,
        );
        return;
      }
      if (enrollmentStatus != 'pending') {
        throw const LanBranchEnrollmentException('invitation_not_pending');
      }
      if (!clock.isBefore(
        DateTime.parse(row.read<String>('expires_at')).toUtc(),
      )) {
        await _db.customStatement(
          "UPDATE lan_branch_enrollments SET status='revoked' WHERE enrollment_id=?",
          [normalizedEnrollment],
        );
        return;
      }
      if (!secretMatches) {
        throw const LanBranchEnrollmentException('invalid_invitation_secret');
      }
      if (normalizedDatabase == row.read<String>('coordinator_database_id')) {
        throw const LanBranchEnrollmentException('database_identity_reused');
      }
      await _syncEvents.enrollSource(
        sourceDatabaseId: normalizedDatabase,
        organizationId: row.read<String>('organization_id'),
        branchId: row.read<String>('branch_id'),
      );
      await _syncEvents.registerDeliveryPeer(
        targetDatabaseId: normalizedDatabase,
        organizationId: row.read<String>('organization_id'),
        branchId: row.read<String>('branch_id'),
      );
      await _ensureSyncCredential(
        enrollmentId: normalizedEnrollment,
        remoteDatabaseId: normalizedDatabase,
        tokenHash: syncTokenHash,
      );
      await _db.customStatement(
        "UPDATE lan_branch_enrollments SET status='active',"
        'remote_database_id=?,activated_at=? WHERE enrollment_id=?',
        [normalizedDatabase, clock.toIso8601String(), normalizedEnrollment],
      );
      await AuditLogService(_db).log(
        entityType: 'business_branches',
        entityId: row.read<int>('issued_by'),
        action: 'activate_lan_branch_writer',
        userId: row.read<int>('issued_by'),
        userRole: 'owner',
        newValue: {
          'enrollmentId': normalizedEnrollment,
          'branchId': row.read<String>('branch_id'),
          'remoteDatabaseId': normalizedDatabase,
        },
      );
    });
    if (recoveryExpired) {
      throw const LanBranchEnrollmentException('invitation_expired');
    }
    final status = await _db
        .customSelect(
          'SELECT status FROM lan_branch_enrollments WHERE enrollment_id=?',
          variables: [Variable.withString(normalizedEnrollment)],
        )
        .map((row) => row.read<String>('status'))
        .getSingle();
    if (status == 'revoked') {
      throw const LanBranchEnrollmentException('invitation_expired');
    }
    // Publication is idempotent. A retry after activation repairs a partial
    // catalogue enqueue before the branch starts receiving business events.
    await _catalogue?.publishSnapshot();
    // The directory is published after activation so it contains the new
    // branch writer database id. It is routing metadata only; no remote stock
    // row is created on either device.
    await _locations?.publishSnapshot();
    final activated = await _db
        .customSelect(
          'SELECT organization_id,branch_id,warehouse_id,'
          'coordinator_database_id FROM lan_branch_enrollments '
          'WHERE enrollment_id=? AND status=\'active\'',
          variables: [Variable.withString(normalizedEnrollment)],
        )
        .getSingle();
    final authScope = await WarehouseOperationScope.resolve(_db);
    final currency = await _currencyPolicy.read();
    final taxes = await _taxPolicy.read();
    if (currency == null || taxes == null) {
      throw const LanBranchEnrollmentException('accounting_policy_unavailable');
    }
    return LanBranchWriterBinding(
      organizationId: activated.read<String>('organization_id'),
      coordinatorBranchId: authScope.branchId,
      branchId: activated.read<String>('branch_id'),
      warehouseId: activated.read<String>('warehouse_id'),
      coordinatorDatabaseId: activated.read<String>('coordinator_database_id'),
      accountingCurrencyCode: currency.code,
      taxPolicy: taxes.policy.toJson(),
      syncAccessToken: syncAccessToken,
    );
  }

  String _deriveSyncAccessToken({
    required String enrollmentId,
    required String remoteDatabaseId,
    required String secret,
  }) => base64Url
      .encode(
        Hmac(sha256, utf8.encode(secret))
            .convert(
              utf8.encode('tapix-lan-sync-v1:$enrollmentId:$remoteDatabaseId'),
            )
            .bytes,
      )
      .replaceAll('=', '');

  Future<void> _ensureSyncCredential({
    required String enrollmentId,
    required String remoteDatabaseId,
    required String tokenHash,
  }) async {
    final existing = await _db
        .customSelect(
          'SELECT remote_database_id,token_hash,status '
          'FROM lan_branch_sync_credentials WHERE enrollment_id=?',
          variables: [Variable.withString(enrollmentId)],
        )
        .getSingleOrNull();
    if (existing != null) {
      if (existing.read<String>('remote_database_id') != remoteDatabaseId ||
          existing.read<String>('token_hash') != tokenHash ||
          existing.read<String>('status') != 'active') {
        throw const LanBranchEnrollmentException('sync_credential_conflict');
      }
      return;
    }
    await _db.customStatement(
      'INSERT INTO lan_branch_sync_credentials('
      'enrollment_id,remote_database_id,token_hash) VALUES(?,?,?)',
      [enrollmentId, remoteDatabaseId, tokenHash],
    );
  }

  Future<List<LanBranchEnrollmentRecord>> records() async {
    final auth = await _authorize();
    final rows = await _db
        .customSelect(
          '''SELECT e.enrollment_id,e.branch_id,b.name AS branch_name,
          b.code AS branch_code,w.name AS warehouse_name,e.status,
          e.expires_at,e.remote_database_id
          FROM lan_branch_enrollments e
          JOIN business_branches b ON b.id=e.branch_id
          JOIN business_warehouses w ON w.id=e.warehouse_id
          WHERE e.organization_id=? ORDER BY e.created_at DESC''',
          variables: [Variable.withString(auth.scope.organizationId)],
        )
        .get();
    return rows
        .map(
          (row) => LanBranchEnrollmentRecord(
            enrollmentId: row.read<String>('enrollment_id'),
            branchId: row.read<String>('branch_id'),
            branchName: row.read<String>('branch_name'),
            branchCode: row.read<String>('branch_code'),
            warehouseName: row.read<String>('warehouse_name'),
            status: row.read<String>('status'),
            expiresAt: DateTime.parse(row.read<String>('expires_at')).toUtc(),
            remoteDatabaseId: row.readNullable<String>('remote_database_id'),
          ),
        )
        .toList(growable: false);
  }

  bool _constantTimeEquals(String left, String right) {
    if (left.length != right.length) return false;
    var difference = 0;
    for (var index = 0; index < left.length; index++) {
      difference |= left.codeUnitAt(index) ^ right.codeUnitAt(index);
    }
    return difference == 0;
  }
}
