import 'dart:math';

import 'package:drift/drift.dart' show Value, Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/services/business/warehouse_operation_scope.dart';
import 'package:tapix/core/services/business/branch_currency_policy_store.dart';
import 'package:tapix/core/services/business/branch_tax_policy_store.dart';
import 'package:tapix/core/services/lan/lan_models.dart';
import 'package:tapix/core/services/sync/offline_sync_event_store.dart';
import 'package:tapix/core/services/sync/sync_inbound_projection_service.dart';
import 'package:tapix/features/auth/data/services/session_service.dart';
import 'package:tapix/features/business/data/lan_branch_enrollment_service.dart';
import 'package:tapix/features/business/data/lan_branch_sync_service.dart';
import 'package:tapix/features/business/data/warehouse_setup_service.dart';
import 'package:tapix/features/settings/domain/entities/app_settings.dart';

import 'business_foundation_test.dart' as fixtures;

class _Session extends Fake implements SessionService {
  int? id = 77;

  @override
  Future<int?> getCurrentUserId() async => id;
}

class _License implements WarehouseSetupEntitlement {
  bool allowed = true;

  @override
  Future<bool> permits(WarehouseOperationScope scope) async => allowed;
}

void main() {
  late AppDatabase db;
  late _Session session;
  late _License license;
  late LanBranchEnrollmentService service;
  late String branchId;
  late String warehouseId;
  var dependent = false;

  setUp(() async {
    db = fixtures.memoryDb();
    await fixtures.seedLegacyData(db);
    await db.customStatement(
      "INSERT INTO users (id,username,password_hash,role,is_active,created_at,updated_at) VALUES(77,'owner','x','owner',1,0,0)",
    );
    final local = await WarehouseOperationScope.resolve(db);
    branchId = '33333333-3333-4333-8333-333333333333';
    warehouseId = '44444444-4444-4444-8444-444444444444';
    await db
        .into(db.businessBranches)
        .insert(
          BusinessBranchesCompanion.insert(
            id: branchId,
            organizationId: local.organizationId,
            code: 'CAIRO',
            name: const Value('Cairo'),
          ),
        );
    await db
        .into(db.businessWarehouses)
        .insert(
          BusinessWarehousesCompanion.insert(
            id: warehouseId,
            organizationId: local.organizationId,
            branchId: branchId,
            code: 'CAI-MAIN',
            name: const Value('Cairo main'),
          ),
        );
    session = _Session();
    license = _License();
    dependent = false;
    final taxPolicy = BranchTaxPolicyStore(db);
    await taxPolicy.initializeFromLegacy(const AppSettings());
    service = LanBranchEnrollmentService(
      db,
      session,
      license,
      OfflineSyncEventStore(db),
      isDependentLanClient: () => dependent,
      currencyPolicy: BranchCurrencyPolicyStore(db),
      taxPolicy: taxPolicy,
      operatingCurrencyCode: () => 'USD',
      random: Random(42),
    );
  });

  tearDown(() => db.close());

  test(
    'invitation enables LAN writer and contains the exact target scope',
    () async {
      final invitation = await service.issueInvitation(
        branchId: branchId,
        warehouseId: warehouseId,
        now: DateTime.utc(2026, 9, 27, 10),
      );
      expect(invitation.organizationId, isNotEmpty);
      expect(invitation.branchId, branchId);
      expect(invitation.warehouseId, warehouseId);
      expect(invitation.branchCode, 'CAIRO');
      expect(invitation.warehouseCode, 'CAI-MAIN');
      expect(invitation.secret.length, greaterThan(30));
      expect(invitation.encode(), isNot(contains(invitation.secret)));
      final connection = LanBranchConnectionInvitation(
        hosts: const ['192.168.1.10'],
        port: 45820,
        coordinatorFingerprint: List.filled(64, 'a').join(),
        branch: invitation,
      );
      final decoded = LanBranchConnectionInvitation.decode(
        connection.encode(),
        now: DateTime.utc(2026, 9, 27, 10, 1),
      );
      expect(decoded.hosts, ['192.168.1.10']);
      expect(decoded.branch.branchId, branchId);
      expect(decoded.branch.coordinatorBranchId, isNot(branchId));
      expect(
        await OfflineSyncEventStore(db).isWriterRecordingEnabled(),
        isTrue,
      );
      expect(
        await db
            .customSelect('SELECT COUNT(*) n FROM lan_branch_coordinator_state')
            .map((r) => r.read<int>('n'))
            .getSingle(),
        1,
      );
      expect((await service.records()).single.status, 'pending');
    },
  );

  test(
    'new invitation revokes old secret and activation enrolls remote source once',
    () async {
      final first = await service.issueInvitation(
        branchId: branchId,
        warehouseId: warehouseId,
        now: DateTime.utc(2026, 9, 27, 10),
      );
      final second = await service.issueInvitation(
        branchId: branchId,
        warehouseId: warehouseId,
        now: DateTime.utc(2026, 9, 27, 10, 1),
      );
      await expectLater(
        service.activateRemoteWriter(
          enrollmentId: first.enrollmentId,
          secret: first.secret,
          remoteDatabaseId: '55555555-5555-4555-8555-555555555555',
        ),
        throwsA(
          isA<LanBranchEnrollmentException>().having(
            (error) => error.code,
            'code',
            'invitation_not_pending',
          ),
        ),
      );
      await expectLater(
        service.activateRemoteWriter(
          enrollmentId: second.enrollmentId,
          secret: 'wrong',
          remoteDatabaseId: '55555555-5555-4555-8555-555555555555',
          now: DateTime.utc(2026, 9, 27, 10, 2),
        ),
        throwsA(
          isA<LanBranchEnrollmentException>().having(
            (error) => error.code,
            'code',
            'invalid_invitation_secret',
          ),
        ),
      );
      final binding = await service.activateRemoteWriter(
        enrollmentId: second.enrollmentId,
        secret: second.secret,
        remoteDatabaseId: '55555555-5555-4555-8555-555555555555',
        now: DateTime.utc(2026, 9, 27, 10, 2),
      );
      expect(binding.accountingCurrencyCode, 'USD');
      expect(binding.taxPolicy, isNotEmpty);
      // A lost response may retry the exact activation without another writer.
      await service.activateRemoteWriter(
        enrollmentId: second.enrollmentId,
        secret: second.secret,
        remoteDatabaseId: '55555555-5555-4555-8555-555555555555',
        now: DateTime.utc(2026, 9, 27, 10, 3),
      );
      final records = await service.records();
      expect(
        records.map((row) => row.status),
        containsAll(['revoked', 'active']),
      );
      expect(
        records.singleWhere((row) => row.status == 'active').remoteDatabaseId,
        '55555555-5555-4555-8555-555555555555',
      );
      final checkpoint = await db
          .customSelect(
            "SELECT branch_id,next_sequence FROM sync_source_checkpoints WHERE source_database_id='55555555-5555-4555-8555-555555555555'",
          )
          .getSingle();
      expect(checkpoint.read<String>('branch_id'), branchId);
      expect(checkpoint.read<int>('next_sequence'), 1);
      final deliveryPeer = await db
          .customSelect(
            "SELECT branch_id,first_sequence,status FROM sync_delivery_peers WHERE target_database_id='55555555-5555-4555-8555-555555555555'",
          )
          .getSingle();
      expect(deliveryPeer.read<String>('branch_id'), branchId);
      expect(deliveryPeer.read<int>('first_sequence'), 1);
      expect(deliveryPeer.read<String>('status'), 'active');
      await expectLater(
        service.issueInvitation(branchId: branchId, warehouseId: warehouseId),
        throwsA(
          isA<LanBranchEnrollmentException>().having(
            (error) => error.code,
            'code',
            'branch_already_enrolled',
          ),
        ),
      );
    },
  );

  test('expired invitation is revoked and cannot be activated', () async {
    final invitation = await service.issueInvitation(
      branchId: branchId,
      warehouseId: warehouseId,
      validity: const Duration(minutes: 1),
      now: DateTime.utc(2026, 9, 27, 10),
    );
    await expectLater(
      service.activateRemoteWriter(
        enrollmentId: invitation.enrollmentId,
        secret: invitation.secret,
        remoteDatabaseId: '55555555-5555-4555-8555-555555555555',
        now: DateTime.utc(2026, 9, 27, 10, 2),
      ),
      throwsA(
        isA<LanBranchEnrollmentException>().having(
          (error) => error.code,
          'code',
          'invitation_expired',
        ),
      ),
    );
    expect((await service.records()).single.status, 'revoked');
  });

  test(
    'replacement invitation fences the old database before a new writer activates',
    () async {
      const oldDatabase = '55555555-5555-4555-8555-555555555555';
      const newDatabase = '66666666-6666-4666-8666-666666666666';
      final old = await service.issueInvitation(
        branchId: branchId,
        warehouseId: warehouseId,
        now: DateTime.utc(2026, 9, 27, 10),
      );
      await service.activateRemoteWriter(
        enrollmentId: old.enrollmentId,
        secret: old.secret,
        remoteDatabaseId: oldDatabase,
        now: DateTime.utc(2026, 9, 27, 10, 1),
      );

      final replacement = await service.issueReplacementInvitation(
        branchId: branchId,
        warehouseId: warehouseId,
        reason: 'Branch server was lost',
        now: DateTime.utc(2026, 9, 27, 10, 2),
      );

      final oldState = await db
          .customSelect(
            '''SELECT e.status AS enrollment_status,
            c.status AS credential_status,s.status AS source_status,
            p.status AS peer_status
            FROM lan_branch_enrollments e
            JOIN lan_branch_sync_credentials c
              ON c.enrollment_id=e.enrollment_id
            JOIN sync_source_checkpoints s
              ON s.source_database_id=e.remote_database_id
            JOIN sync_delivery_peers p
              ON p.target_database_id=e.remote_database_id
            WHERE e.enrollment_id=?''',
            variables: [Variable.withString(old.enrollmentId)],
          )
          .getSingle();
      expect(oldState.read<String>('enrollment_status'), 'revoked');
      expect(oldState.read<String>('credential_status'), 'revoked');
      expect(oldState.read<String>('source_status'), 'quarantined');
      expect(oldState.read<String>('peer_status'), 'revoked');
      expect(
        (await service.records())
            .singleWhere((row) => row.enrollmentId == replacement.enrollmentId)
            .status,
        'pending',
      );

      await service.activateRemoteWriter(
        enrollmentId: replacement.enrollmentId,
        secret: replacement.secret,
        remoteDatabaseId: newDatabase,
        now: DateTime.utc(2026, 9, 27, 10, 3),
      );
      expect(
        (await service.records())
            .singleWhere((row) => row.enrollmentId == replacement.enrollmentId)
            .remoteDatabaseId,
        newDatabase,
      );
    },
  );

  test(
    'backup recovery preserves database sequence and rotates the only active credential',
    () async {
      const databaseId = '55555555-5555-4555-8555-555555555555';
      final original = await service.issueInvitation(
        branchId: branchId,
        warehouseId: warehouseId,
        now: DateTime.utc(2026, 9, 27, 10),
      );
      final originalBinding = await service.activateRemoteWriter(
        enrollmentId: original.enrollmentId,
        secret: original.secret,
        remoteDatabaseId: databaseId,
        now: DateTime.utc(2026, 9, 27, 10, 1),
      );
      await db.customStatement(
        'UPDATE sync_source_checkpoints SET next_sequence=next_sequence+1 '
        'WHERE source_database_id=?',
        [databaseId],
      );

      final recovery = await service.issueBackupRecoveryInvitation(
        branchId: branchId,
        reason: 'Restore verified encrypted branch backup',
        now: DateTime.utc(2026, 9, 27, 10, 2),
      );
      expect(recovery.recovery, isTrue);
      expect(recovery.expectedRemoteDatabaseId, databaseId);
      expect(recovery.enrollmentId, original.enrollmentId);
      expect(
        await db
            .customSelect(
              'SELECT status FROM sync_source_checkpoints '
              'WHERE source_database_id=?',
              variables: [Variable.withString(databaseId)],
            )
            .map((row) => row.read<String>('status'))
            .getSingle(),
        'quarantined',
      );

      final sync = LanBranchSyncService(
        database: db,
        events: OfflineSyncEventStore(db),
        projections: SyncInboundProjectionService(
          db,
          OfflineSyncEventStore(db),
        ),
      );
      await expectLater(
        sync.pull(
          LanBranchSyncAuth(
            enrollmentId: original.enrollmentId,
            remoteDatabaseId: databaseId,
            accessToken: originalBinding.syncAccessToken,
          ),
        ),
        throwsA(
          isA<LanBranchSyncException>().having(
            (error) => error.code,
            'code',
            'branch_sync_denied',
          ),
        ),
      );

      final recoveredBinding = await service.activateRemoteWriter(
        enrollmentId: recovery.enrollmentId,
        secret: recovery.secret,
        remoteDatabaseId: databaseId,
        now: DateTime.utc(2026, 9, 27, 10, 3),
      );
      expect(
        recoveredBinding.syncAccessToken,
        isNot(originalBinding.syncAccessToken),
      );
      final checkpoint = await db
          .customSelect(
            'SELECT status,next_sequence FROM sync_source_checkpoints '
            'WHERE source_database_id=?',
            variables: [Variable.withString(databaseId)],
          )
          .getSingle();
      expect(checkpoint.read<String>('status'), 'active');
      expect(checkpoint.read<int>('next_sequence'), 2);
      expect(
        await db
            .customSelect(
              'SELECT COUNT(*) AS n FROM lan_branch_recovery_credentials '
              "WHERE enrollment_id=? AND status='active'",
              variables: [Variable.withString(original.enrollmentId)],
            )
            .map((row) => row.read<int>('n'))
            .getSingle(),
        1,
      );
      await expectLater(
        sync.pull(
          LanBranchSyncAuth(
            enrollmentId: recovery.enrollmentId,
            remoteDatabaseId: databaseId,
            accessToken: recoveredBinding.syncAccessToken,
          ),
        ),
        completes,
      );
    },
  );

  test(
    'invalid target rolls back writer and accounting currency binding',
    () async {
      await expectLater(
        service.issueInvitation(
          branchId: '99999999-9999-4999-8999-999999999999',
          warehouseId: warehouseId,
        ),
        throwsA(
          isA<LanBranchEnrollmentException>().having(
            (error) => error.code,
            'code',
            'invalid_independent_branch',
          ),
        ),
      );
      expect(await BranchCurrencyPolicyStore(db).read(), isNull);
      expect(
        await db
            .customSelect('SELECT COUNT(*) n FROM lan_branch_coordinator_state')
            .map((row) => row.read<int>('n'))
            .getSingle(),
        0,
      );
      expect(
        await OfflineSyncEventStore(db).isWriterRecordingEnabled(),
        isFalse,
      );
    },
  );

  test('owner, Pro and independent-server boundaries are enforced', () async {
    for (final mode in ['owner', 'pro', 'dependent']) {
      if (mode == 'owner') session.id = null;
      if (mode == 'pro') license.allowed = false;
      if (mode == 'dependent') dependent = true;
      await expectLater(
        service.issueInvitation(branchId: branchId, warehouseId: warehouseId),
        throwsA(isA<LanBranchEnrollmentException>()),
      );
      session.id = 77;
      license.allowed = true;
      dependent = false;
    }
    expect(
      await db
          .customSelect('SELECT COUNT(*) n FROM lan_branch_enrollments')
          .map((r) => r.read<int>('n'))
          .getSingle(),
      0,
    );
  });
}
