import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/services/business/branch_consignment_policy_store.dart';
import '../../../core/services/business/local_branch_scope.dart';
import '../../auth/data/services/session_service.dart';
import 'consignment_entitlement.dart';

class ConsignmentAccessDenied implements Exception {
  const ConsignmentAccessDenied();
}

/// The add-on is licensed for this installation, but the durable branch
/// policy currently keeps it disabled. Keeping this separate from a generic
/// [StateError] prevents accounting and document-state failures from being
/// presented as permission failures in the UI.
class ConsignmentModuleDisabled implements Exception {
  const ConsignmentModuleDisabled();
}

/// A business-rule failure that is safe to show to the operator.
///
/// The service layer carries a translation key instead of an English message
/// so Arabic and French installations never expose internal exception text.
class ConsignmentUserException implements Exception {
  const ConsignmentUserException(this.messageKey);

  final String messageKey;

  @override
  String toString() => messageKey;
}

/// Owns the three independent gates: signed-in role, Pro entitlement and the
/// durable branch policy. It does not create any inventory or financial entry.
class ConsignmentModuleService {
  ConsignmentModuleService(
    this._db,
    this._session,
    this._entitlement,
    this._policyStore, {
    required bool Function() isRemoteClient,
  }) : _isRemoteClient = isRemoteClient;

  final AppDatabase _db;
  final SessionService _session;
  final ConsignmentEntitlement _entitlement;
  final BranchConsignmentPolicyStore _policyStore;
  final bool Function() _isRemoteClient;

  Future<BranchConsignmentPolicySnapshot> initialize() =>
      _policyStore.initializeDisabled();

  Future<bool> canEnable() async {
    if (_isRemoteClient()) return false;
    try {
      await _authorizedActor();
      return await _entitlement.permits(await LocalBranchScope.read(_db));
    } on ConsignmentAccessDenied {
      return false;
    }
  }

  Future<BranchConsignmentPolicySnapshot> setEnabled({
    required bool enabled,
    required String reason,
  }) => _db.transaction(() async {
    final access = await requireRoleAccess();
    if (enabled && !await _entitlement.permits(access.scope)) {
      throw const ConsignmentAccessDenied();
    }
    final expected = await _policyStore.initializeDisabled();
    return _policyStore.update(
      expected: expected,
      enabled: enabled,
      actorId: access.actorId,
      reason: reason,
    );
  });

  Future<({int actorId, LocalBranchScope scope})> requireRoleAccess() =>
      _db.transaction(() async {
        if (_isRemoteClient()) throw const ConsignmentAccessDenied();
        return (
          actorId: await _authorizedActor(),
          scope: await LocalBranchScope.read(_db),
        );
      });

  Future<({int actorId, LocalBranchScope scope})> requireManageAccess() =>
      _db.transaction(() async {
        final access = await requireRoleAccess();
        if (!await _entitlement.permits(access.scope)) {
          throw const ConsignmentAccessDenied();
        }
        await _requireEnabledPolicy();
        return access;
      });

  Future<({int actorId, LocalBranchScope scope})> requireViewAccess() =>
      _db.transaction(() async {
        if (_isRemoteClient()) throw const ConsignmentAccessDenied();
        final actorId = await _session.getCurrentUserId();
        if (actorId == null) throw const ConsignmentAccessDenied();
        final user = await (_db.select(
          _db.users,
        )..where((u) => u.id.equals(actorId))).getSingleOrNull();
        if (user == null ||
            user.isActive != 1 ||
            !const {'owner', 'manager', 'accountant'}.contains(user.role)) {
          throw const ConsignmentAccessDenied();
        }
        final scope = await LocalBranchScope.read(_db);
        return (actorId: actorId, scope: scope);
      });

  /// Allows owners/managers to pay, reverse or void documents created while
  /// the add-on was licensed. Neither a disabled switch nor an expired
  /// Pro entitlement may trap accounting history.
  Future<({int actorId, LocalBranchScope scope})>
  requireHistoricalManageAccess() => requireRoleAccess();

  Future<bool> historicalManagementEnabled() async {
    try {
      await requireHistoricalManageAccess();
      return true;
    } on ConsignmentAccessDenied {
      return false;
    }
  }

  /// True only when the current actor may create or post new consignment work.
  /// It is deliberately stronger than the durable branch switch because a
  /// Pro access can expire while the switch is still stored as enabled.
  Future<bool> operationsEnabled() async {
    try {
      await requireManageAccess();
      return true;
    } on ConsignmentAccessDenied {
      return false;
    } on ConsignmentModuleDisabled {
      return false;
    }
  }

  /// Keeps the center discoverable when a branch has historical consignment
  /// records, even after the module is disabled or Pro access expires.
  Future<bool> hasHistory() async {
    final access = await requireViewAccess();
    final row =
        await (_db.select(_db.consignmentAgreements)
              ..where(
                (agreement) =>
                    agreement.organizationId.equals(
                      access.scope.organizationId,
                    ) &
                    agreement.branchId.equals(access.scope.branchId) &
                    agreement.databaseId.equals(access.scope.databaseId),
              )
              ..limit(1))
            .getSingleOrNull();
    return row != null;
  }

  Future<bool> canOpenCenter() async {
    try {
      final access = await requireViewAccess();
      final policyEnabled = (await _policyStore.read())?.policy.enabled == true;
      if (policyEnabled && await _entitlement.permits(access.scope)) {
        return true;
      }
      return await hasHistory();
    } on ConsignmentAccessDenied {
      return false;
    }
  }

  Future<void> _requireEnabledPolicy() async {
    final current = await _policyStore.read();
    if (current == null || !current.policy.enabled) {
      throw const ConsignmentModuleDisabled();
    }
  }

  Future<int> _authorizedActor() async {
    final actorId = await _session.getCurrentUserId();
    if (actorId == null) throw const ConsignmentAccessDenied();
    final user = await (_db.select(
      _db.users,
    )..where((u) => u.id.equals(actorId))).getSingleOrNull();
    if (user == null ||
        user.isActive != 1 ||
        (user.role != 'owner' && user.role != 'manager')) {
      throw const ConsignmentAccessDenied();
    }
    return actorId;
  }
}
