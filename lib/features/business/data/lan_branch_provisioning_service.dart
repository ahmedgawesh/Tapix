import '../../../core/database/app_database.dart';
import '../../../core/database/migrations/offline_sync_ledger.dart';
import '../../../core/services/business/branch_currency_policy_store.dart';
import '../../../core/services/business/branch_tax_policy.dart';
import '../../../core/services/business/branch_tax_policy_store.dart';
import '../../../core/services/business/warehouse_operation_scope.dart';
import '../../../core/services/lan/lan_network_service.dart';
import '../../../core/services/sync/offline_sync_event_store.dart';
import '../../../core/services/sync/branch_catalogue_sync_service.dart';
import '../../../core/services/sync/branch_location_directory_sync_service.dart';
import '../../settings/data/services/app_settings_service.dart';
import 'lan_branch_enrollment_service.dart';
import 'warehouse_setup_service.dart';

class LanBranchProvisioningException implements Exception {
  const LanBranchProvisioningException(this.code);

  final String code;

  @override
  String toString() => 'LanBranchProvisioningException($code)';
}

class LanBranchProvisioningResult {
  const LanBranchProvisioningResult({
    required this.organizationName,
    required this.branchName,
    required this.warehouseName,
    this.catalogueReady = true,
    this.locationsReady = true,
  });

  final String organizationName;
  final String branchName;
  final String warehouseName;
  final bool catalogueReady;
  final bool locationsReady;

  bool get sharedDataReady => catalogueReady && locationsReady;
}

/// Adopts an invitation on a brand-new database and turns this device into an
/// independent branch server. This is deliberately unrelated to cashier
/// pairing: the local database id is retained and the LAN mode is never
/// changed to [LanMode.client].
class LanBranchProvisioningService {
  LanBranchProvisioningService({
    required AppDatabase database,
    required WarehouseSetupEntitlement entitlement,
    required LanNetworkService network,
    required OfflineSyncEventStore syncEvents,
    required AppSettingsService settings,
    BranchCatalogueSyncService? catalogue,
    BranchLocationDirectorySyncService? locations,
  }) : _db = database,
       _entitlement = entitlement,
       _network = network,
       _syncEvents = syncEvents,
       _settings = settings,
       _catalogue = catalogue,
       _locations = locations;

  final AppDatabase _db;
  final WarehouseSetupEntitlement _entitlement;
  final LanNetworkService _network;
  final OfflineSyncEventStore _syncEvents;
  final AppSettingsService _settings;
  final BranchCatalogueSyncService? _catalogue;
  final BranchLocationDirectorySyncService? _locations;

  static const _operationalTables = <String>[
    'users',
    'products',
    'product_variants',
    'customers',
    'suppliers',
    'sales',
    'purchases',
    'sale_returns',
    'purchase_returns',
    'sale_return_adjustments',
    'purchase_return_adjustments',
    'journal_entries',
    'inventory_adjustments',
    'business_warehouse_stocks',
    'product_batches',
    'batch_consumptions',
    'warehouse_transfers',
    'consignment_agreements',
    'employees',
    'expenses',
    'cashier_shifts',
  ];

  Future<LanBranchProvisioningResult> join(String encodedInvitation) async {
    final invitation = _decode(encodedInvitation);
    final local = await _assertFreshOrMatching(invitation);
    final scope = await WarehouseOperationScope.resolve(_db);
    if (!await _entitlement.permits(scope)) {
      throw const LanBranchProvisioningException('pro_required');
    }
    if (_network.snapshot.mode == LanMode.client) {
      throw const LanBranchProvisioningException('cashier_client_denied');
    }

    LanBranchWriterActivationResult? activation;
    String? activatedHost;
    for (final host in invitation.hosts) {
      activation = await _network.activateIndependentBranchWriter(
        host: host,
        port: invitation.port,
        coordinatorFingerprint: invitation.coordinatorFingerprint,
        enrollmentId: invitation.branch.enrollmentId,
        secret: invitation.branch.secret,
        remoteDatabaseId: local.databaseId,
      );
      if (activation.success) {
        activatedHost = host;
        break;
      }
    }
    if (activation == null || !activation.success) {
      throw LanBranchProvisioningException(
        activation?.message ?? 'coordinator_unreachable',
      );
    }
    final binding = activation.binding;
    final target = invitation.branch;
    if (binding == null ||
        binding.organizationId != target.organizationId ||
        binding.coordinatorBranchId != target.coordinatorBranchId ||
        binding.branchId != target.branchId ||
        binding.warehouseId != target.warehouseId ||
        binding.coordinatorDatabaseId != target.coordinatorDatabaseId) {
      throw const LanBranchProvisioningException('identity_conflict');
    }

    await _adoptIdentity(invitation, local.databaseId, binding);
    await _network.configureIndependentBranchSync(
      host: activatedHost!,
      port: invitation.port,
      coordinatorFingerprint: invitation.coordinatorFingerprint,
      enrollmentId: invitation.branch.enrollmentId,
      coordinatorDatabaseId: invitation.branch.coordinatorDatabaseId,
      syncAccessToken: binding.syncAccessToken,
    );
    // The branch becomes the LAN server for its dependent cashier and
    // warehouse devices immediately. Its upstream coordinator sync continues
    // independently through the credential saved above.
    await _network.startMaster();
    // These operations are idempotent. If the coordinator response arrived
    // but the app was interrupted locally, submitting the same unexpired code
    // safely finishes the exact enrollment instead of creating another one.
    await _syncEvents.activateWriterRecording(
      enrollmentId: invitation.branch.enrollmentId,
    );
    await _syncEvents.enrollSource(
      sourceDatabaseId: invitation.branch.coordinatorDatabaseId,
      organizationId: invitation.branch.organizationId,
      branchId: invitation.branch.coordinatorBranchId,
    );
    await _syncEvents.registerDeliveryPeer(
      targetDatabaseId: invitation.branch.coordinatorDatabaseId,
      organizationId: invitation.branch.organizationId,
      branchId: invitation.branch.coordinatorBranchId,
    );
    var catalogueReady = _catalogue == null;
    final catalogue = _catalogue;
    if (catalogue != null) {
      try {
        catalogueReady = await catalogue.hasCompleteSnapshot();
        for (var round = 0; !catalogueReady && round < 100; round++) {
          final result = await _network.synchronizeIndependentBranchOnce();
          catalogueReady = await catalogue.hasCompleteSnapshot();
          if (!catalogueReady && result.downloaded == 0) break;
        }
      } catch (_) {
        // The coordinator already committed this writer identity. Keep the
        // valid enrollment and let the periodic synchronizer resume safely.
        catalogueReady = false;
      }
    }
    var locationsReady = _locations == null;
    final locations = _locations;
    if (locations != null) {
      try {
        locationsReady = await locations.hasCompleteSnapshot();
        for (var round = 0; !locationsReady && round < 100; round++) {
          final result = await _network.synchronizeIndependentBranchOnce();
          locationsReady = await locations.hasCompleteSnapshot();
          if (!locationsReady && result.downloaded == 0) break;
        }
      } catch (_) {
        locationsReady = false;
      }
    }
    await _settings.initializeTaxPolicy();
    await _settings.initializeSharedFeaturePolicy();

    return LanBranchProvisioningResult(
      organizationName: invitation.branch.organizationName,
      branchName: invitation.branch.branchName,
      warehouseName: invitation.branch.warehouseName,
      catalogueReady: catalogueReady,
      locationsReady: locationsReady,
    );
  }

  LanBranchConnectionInvitation _decode(String encoded) {
    if (encoded.trim().isEmpty || encoded.length > 16384) {
      throw const LanBranchProvisioningException('invalid_invitation');
    }
    try {
      return LanBranchConnectionInvitation.decode(encoded);
    } on FormatException catch (error) {
      final message = error.message.toString().toLowerCase();
      throw LanBranchProvisioningException(
        message.contains('expired')
            ? 'invitation_expired'
            : 'invalid_invitation',
      );
    }
  }

  Future<
    ({
      String organizationId,
      String branchId,
      String warehouseId,
      String databaseId,
    })
  >
  _assertFreshOrMatching(LanBranchConnectionInvitation invitation) async {
    final local = await _db.transaction(() async {
      final context = await _db
          .customSelect(
            'SELECT organization_id,branch_id,warehouse_id,database_id '
            'FROM business_contexts WHERE id=1',
          )
          .getSingleOrNull();
      if (context == null) {
        throw const LanBranchProvisioningException('invalid_local_identity');
      }
      final result = (
        organizationId: context.read<String>('organization_id'),
        branchId: context.read<String>('branch_id'),
        warehouseId: context.read<String>('warehouse_id'),
        databaseId: context.read<String>('database_id'),
      );
      final target = invitation.branch;
      final alreadyMatches =
          result.organizationId == target.organizationId &&
          result.branchId == target.branchId &&
          result.warehouseId == target.warehouseId;

      if (target.recovery) {
        if (!alreadyMatches ||
            target.expectedRemoteDatabaseId != result.databaseId) {
          throw const LanBranchProvisioningException(
            'recovery_database_identity_mismatch',
          );
        }
        final writer = await _db
            .customSelect(
              'SELECT enrollment_id,database_id,organization_id,branch_id '
              'FROM sync_writer_enrollment WHERE id=1',
            )
            .getSingleOrNull();
        if (writer == null ||
            writer.read<String>('enrollment_id') != target.enrollmentId ||
            writer.read<String>('database_id') != result.databaseId ||
            writer.read<String>('organization_id') != result.organizationId ||
            writer.read<String>('branch_id') != result.branchId) {
          throw const LanBranchProvisioningException(
            'recovery_writer_identity_mismatch',
          );
        }
        return result;
      }

      final counts = await Future.wait([
        _count('business_organizations'),
        _count('business_branches'),
        _count('business_warehouses'),
        _count('business_contexts'),
      ]);
      if (!alreadyMatches && counts.any((value) => value != 1)) {
        throw const LanBranchProvisioningException('fresh_database_required');
      }
      for (final table in _operationalTables) {
        if (await _count(table) != 0) {
          throw const LanBranchProvisioningException('fresh_database_required');
        }
      }
      for (final table in const [
        'lan_branch_coordinator_state',
        'lan_branch_enrollments',
        'sync_outbox_events',
        'sync_inbox_receipts',
        'sync_entity_identities',
        'sync_inventory_layer_identities',
      ]) {
        if (await _count(table) != 0) {
          throw const LanBranchProvisioningException('fresh_database_required');
        }
      }
      final writer = await _db
          .customSelect(
            'SELECT enrollment_id FROM sync_writer_enrollment WHERE id=1',
          )
          .getSingleOrNull();
      if (writer != null &&
          writer.read<String>('enrollment_id') != target.enrollmentId) {
        throw const LanBranchProvisioningException('identity_conflict');
      }
      final checkpoints = await _db
          .customSelect(
            'SELECT source_database_id,organization_id,branch_id '
            'FROM sync_source_checkpoints',
          )
          .get();
      if (checkpoints.any(
        (row) =>
            row.read<String>('source_database_id') !=
                target.coordinatorDatabaseId ||
            row.read<String>('organization_id') != target.organizationId ||
            row.read<String>('branch_id') != target.coordinatorBranchId,
      )) {
        throw const LanBranchProvisioningException('identity_conflict');
      }
      return result;
    });
    if (local.databaseId == invitation.branch.coordinatorDatabaseId) {
      throw const LanBranchProvisioningException('database_identity_reused');
    }
    return local;
  }

  Future<int> _count(String table) async => _db
      .customSelect('SELECT COUNT(*) AS n FROM $table')
      .map((row) => row.read<int>('n'))
      .getSingle();

  Future<void> _adoptIdentity(
    LanBranchConnectionInvitation invitation,
    String databaseId,
    LanBranchWriterBinding binding,
  ) async {
    final target = invitation.branch;
    await _db.transaction(() async {
      final current = await _db
          .customSelect(
            'SELECT organization_id,branch_id,warehouse_id,database_id '
            'FROM business_contexts WHERE id=1',
          )
          .getSingle();
      if (current.read<String>('database_id') != databaseId) {
        throw const LanBranchProvisioningException('identity_conflict');
      }
      final oldOrganization = current.read<String>('organization_id');
      final oldBranch = current.read<String>('branch_id');
      final oldWarehouse = current.read<String>('warehouse_id');
      if (oldOrganization == target.organizationId &&
          oldBranch == target.branchId &&
          oldWarehouse == target.warehouseId) {
        await BranchCurrencyPolicyStore(
          _db,
        ).bind(binding.accountingCurrencyCode);
        await BranchTaxPolicyStore(
          _db,
        ).initializeExact(BranchTaxPolicy.fromJson(binding.taxPolicy));
        return;
      }

      await _db.customStatement(
        'INSERT INTO business_organizations(id,name) VALUES(?,?)',
        [target.organizationId, target.organizationName],
      );
      await _db.customStatement(
        'INSERT INTO business_branches(id,organization_id,code,name,is_active) '
        'VALUES(?,?,?,?,1)',
        [
          target.branchId,
          target.organizationId,
          target.branchCode,
          target.branchName,
        ],
      );
      await _db.customStatement(
        'INSERT INTO business_warehouses('
        'id,organization_id,branch_id,code,name,is_active) VALUES(?,?,?,?,?,1)',
        [
          target.warehouseId,
          target.organizationId,
          target.branchId,
          target.warehouseCode,
          target.warehouseName,
        ],
      );
      await _db.customStatement(
        'DROP TRIGGER IF EXISTS business_location_context_update',
      );
      await _db.customStatement(
        'UPDATE business_contexts SET organization_id=?,branch_id=?,'
        'warehouse_id=? WHERE id=1 AND database_id=?',
        [
          target.organizationId,
          target.branchId,
          target.warehouseId,
          databaseId,
        ],
      );
      await _db.customStatement('''
        CREATE TRIGGER business_location_context_update
        BEFORE UPDATE ON business_contexts
        WHEN (NEW.organization_id != OLD.organization_id
          OR NEW.branch_id != OLD.branch_id
          OR NEW.warehouse_id != OLD.warehouse_id
          OR NEW.database_id != OLD.database_id)
        BEGIN SELECT RAISE(ABORT,
          'Cannot reassign existing business documents'); END
      ''');

      // sync_local_state is immutable during normal operation. A fresh-device
      // adoption is its only identity transition, guarded above and performed
      // in the same transaction as business_contexts.
      await _db.customStatement('DROP TRIGGER IF EXISTS trg_sync_local_update');
      await _db.customStatement(
        'UPDATE sync_local_state SET organization_id=?,branch_id=? '
        'WHERE id=1 AND database_id=? AND next_sequence=1',
        [target.organizationId, target.branchId, databaseId],
      );

      await _db.customStatement(
        'DELETE FROM app_settings WHERE key LIKE ? OR key LIKE ?',
        [
          'business.currency.v1.$oldBranch%',
          'business.tax_policy.v1.$oldBranch%',
        ],
      );
      await BranchCurrencyPolicyStore(_db).bind(binding.accountingCurrencyCode);
      await BranchTaxPolicyStore(
        _db,
      ).initializeExact(BranchTaxPolicy.fromJson(binding.taxPolicy));
      await _db.customStatement('DELETE FROM business_warehouses WHERE id=?', [
        oldWarehouse,
      ]);
      await _db.customStatement('DELETE FROM business_branches WHERE id=?', [
        oldBranch,
      ]);
      await _db.customStatement(
        'DELETE FROM business_organizations WHERE id=?',
        [oldOrganization],
      );
    });
    await installOfflineSyncLedger(_db);
  }
}
