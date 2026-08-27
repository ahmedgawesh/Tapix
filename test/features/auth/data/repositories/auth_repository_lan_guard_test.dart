import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/database/daos/settings_dao.dart';
import 'package:tapix/core/services/audit_log_service.dart';
import 'package:tapix/core/services/lan/lan_network_service.dart';
import 'package:tapix/features/auth/data/repositories/auth_repository.dart';
import 'package:tapix/features/auth/data/services/lan_master_auth_gateway.dart';
import 'package:tapix/features/auth/data/services/password_service.dart';
import 'package:tapix/features/auth/data/services/permission_service.dart';
import 'package:tapix/features/auth/data/services/session_service.dart';

class _MockSecureStorage extends Mock implements FlutterSecureStorage {}

void main() {
  late AppDatabase masterDb;
  late AppDatabase clientDb;
  late LanNetworkService master;
  late LanNetworkService client;
  late SessionService session;
  late AuthRepository repository;

  setUp(() async {
    masterDb = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    clientDb = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    final now = DateTime.now();
    await masterDb
        .into(masterDb.users)
        .insert(
          UsersCompanion.insert(
            username: 'master-cashier',
            passwordHash: PasswordService().hashPassword('master-password'),
            role: 'cashier',
            createdAt: now,
            updatedAt: now,
          ),
        );
    master = LanNetworkService(
      SettingsDao(masterDb),
      authGateway: LanMasterAuthGatewayImpl(
        database: masterDb,
        permissionService: PermissionService(),
        auditLogService: AuditLogService(masterDb),
      ),
    );
    client = LanNetworkService(SettingsDao(clientDb));
    await master.initialize();
    await client.initialize();
    await master.startMaster(port: 0);
    final paired = await client.pairWithMaster(
      host: '127.0.0.1',
      port: master.snapshot.port,
      pairingCode: master.snapshot.pairingCode!,
      deviceName: 'Guard test cashier',
    );
    expect(paired.success, isTrue);

    final storage = _MockSecureStorage();
    when(
      () => storage.read(key: any(named: 'key')),
    ).thenAnswer((_) async => null);
    when(
      () => storage.write(
        key: any(named: 'key'),
        value: any(named: 'value'),
      ),
    ).thenAnswer((_) async {});
    when(() => storage.delete(key: any(named: 'key'))).thenAnswer((_) async {});
    session = SessionService(storage: storage);
    repository = AuthRepository(
      database: clientDb,
      passwordService: PasswordService(),
      sessionService: session,
      lanNetworkService: client,
    );
  });

  tearDown(() async {
    repository.dispose();
    session.dispose();
    await client.stop();
    await master.stop();
    await clientDb.close();
    await masterDb.close();
  });

  test(
    'paired client never authenticates against its local users table',
    () async {
      final now = DateTime.now();
      await clientDb
          .into(clientDb.users)
          .insert(
            UsersCompanion.insert(
              username: 'local-owner',
              passwordHash: PasswordService().hashPassword('correct-password'),
              role: 'owner',
              createdAt: now,
              updatedAt: now,
            ),
          );

      // Correct credentials for a user that exists only on Linux must still
      // be rejected: the master is the sole identity authority.
      expect(await repository.login('local-owner', 'correct-password'), isNull);

      final remote = await repository.login(
        'master-cashier',
        'master-password',
      );
      expect(remote?.username, 'master-cashier');
      expect(remote?.role.name, 'cashier');
    },
  );

  test(
    'paired empty client is routed to master login, not local owner setup',
    () async {
      expect(await repository.hasAnyUsers(), isTrue);
      expect(await repository.getCurrentUser(), equals(null));
    },
  );
}
