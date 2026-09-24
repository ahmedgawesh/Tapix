import 'dart:convert';

import 'package:drift/drift.dart';

import '../../database/app_database.dart';
import 'branch_consignment_policy.dart';
import 'local_branch_scope.dart';

class BranchConsignmentPolicySnapshot {
  BranchConsignmentPolicySnapshot._(
    this._database,
    this._encoded, {
    required this.organizationId,
    required this.branchId,
    required this.databaseId,
    required this.revision,
    required this.policy,
    required this.changedBy,
    required this.reason,
  });

  final AppDatabase _database;
  final String _encoded;
  final String organizationId;
  final String branchId;
  final String databaseId;
  final int revision;
  final BranchConsignmentPolicy policy;
  final int? changedBy;
  final String reason;
}

/// Database-owned feature policy shared by every device serving this branch.
/// Preferences are deliberately excluded because they are device-local.
class BranchConsignmentPolicyStore {
  BranchConsignmentPolicyStore(this._db);

  static const _version = 1;
  static const _maxSafeInteger = 9007199254740991;
  final AppDatabase _db;

  String _headKey(String branchId) =>
      'business.consignment_policy.v1.$branchId.head';
  String _revisionKey(String branchId, int revision) =>
      'business.consignment_policy.v1.$branchId.revision.$revision';

  Future<BranchConsignmentPolicySnapshot> initializeDisabled() =>
      _db.transaction(() async {
        final scope = await LocalBranchScope.read(_db);
        final current = await _read(scope);
        if (current != null) return current;
        return _save(
          scope,
          const BranchConsignmentPolicy(enabled: false),
          revision: 1,
          changedBy: null,
          reason: 'initial_disabled',
        );
      });

  Future<BranchConsignmentPolicySnapshot?> read() =>
      _db.transaction(() async => _read(await LocalBranchScope.read(_db)));

  Future<BranchConsignmentPolicySnapshot> update({
    required BranchConsignmentPolicySnapshot expected,
    required bool enabled,
    required int actorId,
    required String reason,
  }) => _db.transaction(() async {
    await assertCurrent(expected);
    await _authorize(actorId);
    final normalizedReason = reason.trim();
    if (normalizedReason.isEmpty || normalizedReason.length > 500) {
      throw ArgumentError('A policy change reason is required.');
    }
    if (expected.policy.enabled == enabled) return expected;
    if (expected.revision >= _maxSafeInteger) {
      throw StateError('Consignment policy revision limit reached.');
    }
    return _save(
      await LocalBranchScope.read(_db),
      BranchConsignmentPolicy(enabled: enabled),
      revision: expected.revision + 1,
      changedBy: actorId,
      reason: normalizedReason,
      previous: expected,
    );
  });

  Future<void> assertCurrent(BranchConsignmentPolicySnapshot expected) async {
    if (!identical(expected._database, _db)) {
      throw StateError(
        'Consignment policy token belongs to another database connection.',
      );
    }
    final current = await _read(await LocalBranchScope.read(_db));
    if (current == null || current._encoded != expected._encoded) {
      throw StateError('Consignment policy changed; refresh and retry.');
    }
  }

  Future<void> requireEnabled() async {
    final current = await read();
    if (current == null || !current.policy.enabled) {
      throw StateError('Consignment inventory is disabled for this branch.');
    }
  }

  Future<void> _authorize(int actorId) async {
    final user = await (_db.select(
      _db.users,
    )..where((u) => u.id.equals(actorId))).getSingleOrNull();
    if (user == null ||
        user.isActive != 1 ||
        (user.role != 'owner' && user.role != 'manager')) {
      throw StateError('Only an active owner or manager may change policy.');
    }
  }

  Future<String?> _value(String key) async => (await (_db.select(
    _db.appSettings,
  )..where((s) => s.key.equals(key))).getSingleOrNull())?.value;

  Future<BranchConsignmentPolicySnapshot?> _read(LocalBranchScope scope) async {
    final raw = await _value(_headKey(scope.branchId));
    if (raw == null) {
      final prefix =
          'business.consignment_policy.v1.${scope.branchId}.revision.';
      final history = await _db
          .customSelect(
            'SELECT 1 FROM app_settings WHERE substr(key,1,?)=? LIMIT 1',
            variables: [
              Variable.withInt(prefix.length),
              Variable.withString(prefix),
            ],
            readsFrom: {_db.appSettings},
          )
          .get();
      if (history.isNotEmpty) {
        throw StateError('Missing branch consignment policy head.');
      }
      return null;
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map ||
        decoded['version'] != _version ||
        decoded['organizationId'] != scope.organizationId ||
        decoded['branchId'] != scope.branchId ||
        decoded['databaseId'] != scope.databaseId ||
        decoded['revision'] is! int ||
        decoded['reason'] is! String ||
        (decoded['changedBy'] != null && decoded['changedBy'] is! int)) {
      throw const FormatException('Invalid consignment policy binding.');
    }
    final revision = decoded['revision'] as int;
    final reason = decoded['reason'] as String;
    if (revision < 1 ||
        revision > _maxSafeInteger ||
        reason.isEmpty ||
        reason.length > 500 ||
        await _value(_revisionKey(scope.branchId, revision)) != raw) {
      throw StateError('Invalid consignment policy history.');
    }
    return BranchConsignmentPolicySnapshot._(
      _db,
      raw,
      organizationId: scope.organizationId,
      branchId: scope.branchId,
      databaseId: scope.databaseId,
      revision: revision,
      policy: BranchConsignmentPolicy.fromJson(decoded['policy']),
      changedBy: decoded['changedBy'] as int?,
      reason: reason,
    );
  }

  Future<BranchConsignmentPolicySnapshot> _save(
    LocalBranchScope scope,
    BranchConsignmentPolicy policy, {
    required int revision,
    required int? changedBy,
    required String reason,
    BranchConsignmentPolicySnapshot? previous,
  }) async {
    final encoded = jsonEncode({
      'version': _version,
      'organizationId': scope.organizationId,
      'branchId': scope.branchId,
      'databaseId': scope.databaseId,
      'revision': revision,
      'changedBy': changedBy,
      'reason': reason,
      'changedAt': DateTime.now().toUtc().toIso8601String(),
      'policy': policy.toJson(),
    });
    await _db
        .into(_db.appSettings)
        .insert(
          AppSettingsCompanion.insert(
            key: _revisionKey(scope.branchId, revision),
            value: encoded,
            description: const Value('Branch consignment policy revision'),
          ),
        );
    if (previous == null) {
      await _db
          .into(_db.appSettings)
          .insert(
            AppSettingsCompanion.insert(
              key: _headKey(scope.branchId),
              value: encoded,
              description: const Value('Current branch consignment policy'),
            ),
          );
    } else {
      final changed =
          await (_db.update(_db.appSettings)..where(
                (s) =>
                    s.key.equals(_headKey(scope.branchId)) &
                    s.value.equals(previous._encoded),
              ))
              .write(
                AppSettingsCompanion(
                  value: Value(encoded),
                  updatedAt: Value(DateTime.now()),
                ),
              );
      if (changed != 1) {
        throw StateError('Concurrent consignment policy update.');
      }
    }
    return BranchConsignmentPolicySnapshot._(
      _db,
      encoded,
      organizationId: scope.organizationId,
      branchId: scope.branchId,
      databaseId: scope.databaseId,
      revision: revision,
      policy: policy,
      changedBy: changedBy,
      reason: reason,
    );
  }
}
