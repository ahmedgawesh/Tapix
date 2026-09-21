import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../features/settings/domain/entities/app_settings.dart' as legacy;
import '../../database/app_database.dart';
import 'branch_tax_policy.dart';
import 'local_branch_scope.dart';

/// An internal optimistic-concurrency token, not a permission or a client
/// selector. Only this store constructs tokens after checking local ownership.
class BranchTaxPolicySnapshot {
  BranchTaxPolicySnapshot._(
    this._database,
    this._encoded,
    this.organizationId,
    this.branchId,
    this.databaseId,
    this.revision,
    this.policy,
  );
  final AppDatabase _database;
  final String _encoded;
  final String organizationId;
  final String branchId;
  final String databaseId;
  final int revision;
  final BranchTaxPolicy policy;
}

/// Internal foundation. Activation and authorized settings UI integration are
/// deliberately separate: constructing this store never imports preferences.
///
/// Uses the existing durable settings table, so no schema migration is needed.
/// The reserved keys are owned by this store; do not write them via SettingsDao.
class BranchTaxPolicyStore {
  BranchTaxPolicyStore(this._db);
  final AppDatabase _db;

  String _headKey(String branchId) => 'business.tax_policy.v1.$branchId.head';
  String _revisionKey(String branchId, int revision) =>
      'business.tax_policy.v1.$branchId.revision.$revision';

  Future<BranchTaxPolicySnapshot?> read() => _db.transaction(() async {
    final scope = await LocalBranchScope.read(_db);
    return _read(scope);
  });

  Future<String?> _value(String key) async => (await (_db.select(
    _db.appSettings,
  )..where((s) => s.key.equals(key))).getSingleOrNull())?.value;

  Future<BranchTaxPolicySnapshot?> _read(LocalBranchScope scope) async {
    final raw = await _value(_headKey(scope.branchId));
    if (raw == null) {
      // An orphan history is corruption, not an invitation to reset policy.
      final prefix = 'business.tax_policy.v1.${scope.branchId}.revision.';
      final history = await _db
          .customSelect(
            'SELECT id FROM app_settings WHERE substr(key, 1, ?) = ? LIMIT 1',
            variables: [
              Variable.withInt(prefix.length),
              Variable.withString(prefix),
            ],
            readsFrom: {_db.appSettings},
          )
          .get();
      if (history.isNotEmpty) {
        throw StateError('Missing branch tax policy head.');
      }
      return null;
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map ||
        decoded['version'] != 1 ||
        decoded['organizationId'] != scope.organizationId ||
        decoded['branchId'] != scope.branchId ||
        decoded['databaseId'] != scope.databaseId ||
        decoded['revision'] is! int) {
      throw const FormatException('Invalid branch tax policy binding.');
    }
    final revision = decoded['revision'] as int;
    if (revision < 1 || revision > BranchTaxPolicy.maxSafeInteger) {
      throw const FormatException('Invalid branch tax policy revision.');
    }
    if (await _value(_revisionKey(scope.branchId, revision)) != raw) {
      throw StateError(
        'Branch tax policy history differs from current policy.',
      );
    }
    return BranchTaxPolicySnapshot._(
      _db,
      raw,
      scope.organizationId,
      scope.branchId,
      scope.databaseId,
      revision,
      BranchTaxPolicy.fromJson(decoded['policy']),
    );
  }

  /// Explicit adoption preserves the effective legacy rates. An existing
  /// durable policy always wins; repeated adoption never resets it.
  Future<BranchTaxPolicySnapshot> initializeFromLegacy(
    legacy.AppSettings settings,
  ) => _db.transaction(() async {
    final scope = await LocalBranchScope.read(_db);
    final existing = await _read(scope);
    if (existing != null) return existing;
    return _save(scope, BranchTaxPolicy.fromLegacy(settings), 1);
  });

  /// Call within the posting transaction to reject a stale preview token.
  Future<void> assertCurrent(BranchTaxPolicySnapshot expected) async {
    if (!identical(expected._database, _db)) {
      throw StateError(
        'Tax policy token belongs to another database connection.',
      );
    }
    final scope = await LocalBranchScope.read(_db);
    final current = await _read(scope);
    if (current == null || current._encoded != expected._encoded) {
      throw StateError('Branch tax policy changed; refresh the preview.');
    }
  }

  Future<BranchTaxPolicySnapshot> update({
    required BranchTaxPolicySnapshot expected,
    required BranchTaxPolicy policy,
  }) => _db.transaction(() async {
    await assertCurrent(expected);
    if (expected.policy.hasSameValues(policy)) return expected;
    if (expected.revision == BranchTaxPolicy.maxSafeInteger) {
      throw StateError('Tax policy revision limit reached.');
    }
    final scope = await LocalBranchScope.read(_db);
    return _save(scope, policy, expected.revision + 1, previous: expected);
  });

  Future<BranchTaxPolicySnapshot> _save(
    LocalBranchScope scope,
    BranchTaxPolicy policy,
    int revision, {
    BranchTaxPolicySnapshot? previous,
  }) async {
    final encoded = jsonEncode({
      'version': 1,
      'organizationId': scope.organizationId,
      'branchId': scope.branchId,
      'databaseId': scope.databaseId,
      'revision': revision,
      'policy': policy.toJson(),
    });
    // Plain INSERT preserves revision uniqueness; never replace prior history.
    await _db
        .into(_db.appSettings)
        .insert(
          AppSettingsCompanion.insert(
            key: _revisionKey(scope.branchId, revision),
            value: encoded,
            description: const Value('Branch tax policy revision'),
          ),
        );
    if (previous == null) {
      await _db
          .into(_db.appSettings)
          .insert(
            AppSettingsCompanion.insert(
              key: _headKey(scope.branchId),
              value: encoded,
              description: const Value('Current branch tax policy'),
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
      if (changed != 1) throw StateError('Concurrent tax policy update.');
    }
    return BranchTaxPolicySnapshot._(
      _db,
      encoded,
      scope.organizationId,
      scope.branchId,
      scope.databaseId,
      revision,
      policy,
    );
  }
}
