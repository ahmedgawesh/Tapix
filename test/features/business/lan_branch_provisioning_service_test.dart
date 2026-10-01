import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/services/business/branch_tax_policy_store.dart';
import 'package:tapix/core/services/business/branch_currency_policy_store.dart';
import 'package:tapix/core/services/business/warehouse_operation_scope.dart';
import 'package:tapix/core/services/lan/lan_network_service.dart';
import 'package:tapix/core/services/sync/branch_catalogue_sync_service.dart';
import 'package:tapix/core/services/sync/branch_location_directory_sync_service.dart';
import 'package:tapix/core/services/sync/offline_sync_event_store.dart';
import 'package:tapix/core/services/sync/sync_entity_identity_store.dart';
import 'package:tapix/features/business/data/lan_branch_enrollment_service.dart';
import 'package:tapix/features/business/data/lan_branch_provisioning_service.dart';
import 'package:tapix/features/business/data/warehouse_setup_service.dart';
import 'package:tapix/features/settings/data/services/app_settings_service.dart';

import 'business_foundation_test.dart' as fixtures;

class _License implements WarehouseSetupEntitlement {
  _License(this.allowed);
  bool allowed;

  @override
  Future<bool> permits(WarehouseOperationScope scope) async => allowed;
}

class _Network extends Fake implements LanNetworkService {
  late LanBranchWriterActivationResult result;
  int calls = 0;
  String? remoteDatabaseId;
  String? configuredHost;
  String? configuredToken;
  int syncCalls = 0;
  int masterStarts = 0;

  @override
  LanNetworkSnapshot get snapshot => const LanNetworkSnapshot();

  @override
  Future<LanBranchWriterActivationResult> activateIndependentBranchWriter({
    required String host,
    required int port,
    required String coordinatorFingerprint,
    required String enrollmentId,
    required String secret,
    required String remoteDatabaseId,
  }) async {
    calls++;
    this.remoteDatabaseId = remoteDatabaseId;
    return result;
  }

  @override
  Future<void> configureIndependentBranchSync({
    required String host,
    required int port,
    required String coordinatorFingerprint,
    required String enrollmentId,
    required String coordinatorDatabaseId,
    required String syncAccessToken,
  }) async {
    configuredHost = host;
    configuredToken = syncAccessToken;
  }

  @override
  Future<LanBranchSyncRunResult> synchronizeIndependentBranchOnce() async {
    syncCalls++;
    return const LanBranchSyncRunResult(uploaded: 0, downloaded: 0);
  }

  @override
  Future<void> startMaster({int port = 45820}) async {
    masterStarts++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late _License license;
  late _Network network;
  late AppSettingsService settings;
  late LanBranchProvisioningService service;

  const organizationId = '11111111-1111-4111-8111-111111111111';
  const coordinatorBranchId = '22222222-2222-4222-8222-222222222222';
  const branchId = '33333333-3333-4333-8333-333333333333';
  const warehouseId = '44444444-4444-4444-8444-444444444444';
  const coordinatorDatabaseId = '55555555-5555-4555-8555-555555555555';
  const enrollmentId = '66666666-6666-4666-8666-666666666666';

  String invitation({
    DateTime? expiresAt,
    bool recovery = false,
    String? expectedRemoteDatabaseId,
  }) => LanBranchConnectionInvitation(
    hosts: const ['192.168.1.20', 'branch-main.local'],
    port: 45820,
    coordinatorFingerprint: List.filled(64, 'a').join(),
    branch: LanBranchInvitation(
      enrollmentId: enrollmentId,
      organizationId: organizationId,
      organizationName: 'Tapix Company',
      coordinatorBranchId: coordinatorBranchId,
      branchId: branchId,
      branchName: 'Cairo',
      branchCode: 'CAIRO',
      warehouseId: warehouseId,
      warehouseName: 'Cairo main',
      warehouseCode: 'CAI-MAIN',
      coordinatorDatabaseId: coordinatorDatabaseId,
      secret: 'a-secure-one-time-secret',
      expiresAt:
          expiresAt ?? DateTime.now().toUtc().add(const Duration(hours: 1)),
      recovery: recovery,
      expectedRemoteDatabaseId: expectedRemoteDatabaseId,
    ),
  ).encode();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = fixtures.memoryDb();
    final preferences = await SharedPreferences.getInstance();
    settings = AppSettingsService(
      preferences,
      taxStore: BranchTaxPolicyStore(db),
    );
    await settings.initializeTaxPolicy();
    license = _License(true);
    network = _Network();
    network.result = const LanBranchWriterActivationResult.success(
      LanBranchWriterBinding(
        organizationId: organizationId,
        coordinatorBranchId: coordinatorBranchId,
        branchId: branchId,
        warehouseId: warehouseId,
        coordinatorDatabaseId: coordinatorDatabaseId,
        accountingCurrencyCode: 'USD',
        taxPolicy: {
          'enabled': true,
          'salesRateBps': 1400,
          'purchaseRateBps': 1400,
          'inclusivePricing': false,
          'registrationNumber': 'EG-123',
        },
        syncAccessToken: 'test-sync-token-01234567890123456789012345678901',
      ),
    );
    service = LanBranchProvisioningService(
      database: db,
      entitlement: license,
      network: network,
      syncEvents: OfflineSyncEventStore(db),
      settings: settings,
    );
  });

  tearDown(() async {
    settings.dispose();
    await db.close();
  });

  test(
    'fresh database atomically adopts invited branch and keeps database id',
    () async {
      final before = await db
          .customSelect('SELECT database_id FROM business_contexts WHERE id=1')
          .map((row) => row.read<String>('database_id'))
          .getSingle();

      final result = await service.join(invitation());

      expect(result.branchName, 'Cairo');
      expect(network.calls, 1);
      expect(network.remoteDatabaseId, before);
      expect(network.configuredHost, '192.168.1.20');
      expect(network.masterStarts, 1);
      expect(
        network.configuredToken,
        'test-sync-token-01234567890123456789012345678901',
      );
      final context = await db
          .customSelect(
            'SELECT organization_id,branch_id,warehouse_id,database_id '
            'FROM business_contexts WHERE id=1',
          )
          .getSingle();
      expect(context.read<String>('organization_id'), organizationId);
      expect(context.read<String>('branch_id'), branchId);
      expect(context.read<String>('warehouse_id'), warehouseId);
      expect(context.read<String>('database_id'), before);
      expect(
        await db
            .customSelect('SELECT COUNT(*) n FROM business_organizations')
            .map((row) => row.read<int>('n'))
            .getSingle(),
        1,
      );
      expect(
        await db
            .customSelect(
              'SELECT enrollment_id FROM sync_writer_enrollment WHERE id=1',
            )
            .map((row) => row.read<String>('enrollment_id'))
            .getSingle(),
        enrollmentId,
      );
      expect(
        await db
            .customSelect(
              'SELECT branch_id FROM sync_source_checkpoints '
              'WHERE source_database_id=?',
              variables: [
                // Keep the query typed and avoid interpolating identity values.
                Variable.withString(coordinatorDatabaseId),
              ],
            )
            .map((row) => row.read<String>('branch_id'))
            .getSingle(),
        coordinatorBranchId,
      );
      expect(
        await db
            .customSelect(
              'SELECT branch_id FROM sync_delivery_peers '
              'WHERE target_database_id=?',
              variables: [Variable.withString(coordinatorDatabaseId)],
            )
            .map((row) => row.read<String>('branch_id'))
            .getSingle(),
        coordinatorBranchId,
      );
      expect((await BranchTaxPolicyStore(db).read())?.branchId, branchId);
      expect((await BranchCurrencyPolicyStore(db).read())?.code, 'USD');
      final taxes = await BranchTaxPolicyStore(db).read();
      expect(taxes?.policy.salesRateBps, 1400);
      expect(taxes?.policy.registrationNumber, 'EG-123');

      // Lost-response recovery is idempotent and cannot duplicate identities.
      await service.join(invitation());
      expect(network.calls, 2);
      expect(
        await db
            .customSelect('SELECT COUNT(*) n FROM business_branches')
            .map((row) => row.read<int>('n'))
            .getSingle(),
        1,
      );
    },
  );

  test(
    'operational data blocks enrollment before any network activation',
    () async {
      await db.customStatement(
        'INSERT INTO users(username,password_hash,role,is_active,created_at,updated_at) '
        "VALUES('owner','x','owner',1,0,0)",
      );
      await expectLater(
        service.join(invitation()),
        throwsA(
          isA<LanBranchProvisioningException>().having(
            (error) => error.code,
            'code',
            'fresh_database_required',
          ),
        ),
      );
      expect(network.calls, 0);
    },
  );

  test(
    'committed enrollment survives an interrupted shared-data bootstrap',
    () async {
      final events = OfflineSyncEventStore(db);
      final guardedService = LanBranchProvisioningService(
        database: db,
        entitlement: license,
        network: network,
        syncEvents: events,
        settings: settings,
        catalogue: BranchCatalogueSyncService(
          db,
          events,
          SyncEntityIdentityStore(db),
        ),
        locations: BranchLocationDirectorySyncService(db, events),
      );

      final result = await guardedService.join(invitation());

      expect(result.sharedDataReady, isFalse);
      expect(result.catalogueReady, isFalse);
      expect(result.locationsReady, isFalse);
      expect(network.syncCalls, 2);
      expect(
        await db
            .customSelect('SELECT branch_id FROM business_contexts WHERE id=1')
            .map((row) => row.read<String>('branch_id'))
            .getSingle(),
        branchId,
      );
      expect(
        await db
            .customSelect(
              'SELECT enrollment_id FROM sync_writer_enrollment WHERE id=1',
            )
            .map((row) => row.read<String>('enrollment_id'))
            .getSingle(),
        enrollmentId,
      );
    },
  );

  test(
    'verified recovery invitation accepts only the same non-empty branch database',
    () async {
      await service.join(invitation());
      final databaseId = await db
          .customSelect('SELECT database_id FROM business_contexts WHERE id=1')
          .map((row) => row.read<String>('database_id'))
          .getSingle();
      await db.customStatement(
        'INSERT INTO users(username,password_hash,role,is_active,created_at,updated_at) '
        "VALUES('restored-owner','x','owner',1,0,0)",
      );
      final beforeCalls = network.calls;

      await service.join(
        invitation(recovery: true, expectedRemoteDatabaseId: databaseId),
      );
      expect(network.calls, beforeCalls + 1);
      expect(network.remoteDatabaseId, databaseId);
      expect(
        await db
            .customSelect('SELECT COUNT(*) AS n FROM users')
            .map((row) => row.read<int>('n'))
            .getSingle(),
        1,
      );

      await expectLater(
        service.join(
          invitation(
            recovery: true,
            expectedRemoteDatabaseId: '77777777-7777-4777-8777-777777777777',
          ),
        ),
        throwsA(
          isA<LanBranchProvisioningException>().having(
            (error) => error.code,
            'code',
            'recovery_database_identity_mismatch',
          ),
        ),
      );
    },
  );

  test(
    'Pro denial and coordinator failure leave local identity unchanged',
    () async {
      final before = await db
          .customSelect('SELECT * FROM business_contexts WHERE id=1')
          .getSingle();
      license.allowed = false;
      await expectLater(
        service.join(invitation()),
        throwsA(
          isA<LanBranchProvisioningException>().having(
            (error) => error.code,
            'code',
            'pro_required',
          ),
        ),
      );
      expect(network.calls, 0);

      license.allowed = true;
      network.result = const LanBranchWriterActivationResult.failure(
        'branch_coordinator_unreachable',
      );
      await expectLater(
        service.join(invitation()),
        throwsA(
          isA<LanBranchProvisioningException>().having(
            (error) => error.code,
            'code',
            'branch_coordinator_unreachable',
          ),
        ),
      );
      final after = await db
          .customSelect('SELECT * FROM business_contexts WHERE id=1')
          .getSingle();
      expect(after.data, before.data);
    },
  );

  test(
    'expired or malformed invitations are rejected before network',
    () async {
      await expectLater(
        service.join(invitation(expiresAt: DateTime.utc(2020))),
        throwsA(
          isA<LanBranchProvisioningException>().having(
            (error) => error.code,
            'code',
            'invitation_expired',
          ),
        ),
      );
      await expectLater(
        service.join('not-an-invitation'),
        throwsA(isA<LanBranchProvisioningException>()),
      );
      expect(network.calls, 0);
    },
  );

  test(
    'authoritative coordinator binding rejects a tampered invitation',
    () async {
      final before = await db
          .customSelect('SELECT * FROM business_contexts WHERE id=1')
          .getSingle();
      network.result = const LanBranchWriterActivationResult.success(
        LanBranchWriterBinding(
          organizationId: organizationId,
          coordinatorBranchId: coordinatorBranchId,
          branchId: '77777777-7777-4777-8777-777777777777',
          warehouseId: warehouseId,
          coordinatorDatabaseId: coordinatorDatabaseId,
          accountingCurrencyCode: 'USD',
          taxPolicy: {
            'enabled': true,
            'salesRateBps': 1400,
            'purchaseRateBps': 1400,
            'inclusivePricing': false,
            'registrationNumber': 'EG-123',
          },
          syncAccessToken: 'test-sync-token-01234567890123456789012345678901',
        ),
      );
      await expectLater(
        service.join(invitation()),
        throwsA(
          isA<LanBranchProvisioningException>().having(
            (error) => error.code,
            'code',
            'identity_conflict',
          ),
        ),
      );
      final after = await db
          .customSelect('SELECT * FROM business_contexts WHERE id=1')
          .getSingle();
      expect(after.data, before.data);
    },
  );
}
