import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/services/audit_log_service.dart';
import 'package:tapix/features/auth/data/repositories/auth_repository.dart';
import 'package:tapix/features/auth/data/services/password_service.dart';
import 'package:tapix/features/auth/data/services/session_service.dart';

class _MockSecureStorage extends Mock implements FlutterSecureStorage {}

void main() {
  late AppDatabase db;
  late SessionService session;
  late AuthRepository repository;

  setUp(() async {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    final storage = _MockSecureStorage();
    final values = <String, String>{};
    when(
      () => storage.read(key: any(named: 'key')),
    ).thenAnswer((call) async => values[call.namedArguments[#key] as String]);
    when(
      () => storage.write(
        key: any(named: 'key'),
        value: any(named: 'value'),
      ),
    ).thenAnswer((call) async {
      values[call.namedArguments[#key] as String] =
          call.namedArguments[#value] as String;
    });
    when(() => storage.delete(key: any(named: 'key'))).thenAnswer((call) async {
      values.remove(call.namedArguments[#key] as String);
    });

    session = SessionService(storage: storage);
    repository = AuthRepository(
      database: db,
      passwordService: PasswordService(),
      sessionService: session,
      auditLogService: AuditLogService(db, session),
    );

    final now = DateTime.now();
    await db
        .into(db.users)
        .insert(
          UsersCompanion.insert(
            username: 'manager',
            passwordHash: PasswordService().hashPassword('manager-password'),
            role: 'manager',
            createdAt: now,
            updatedAt: now,
          ),
        );
  });

  tearDown(() async {
    repository.dispose();
    session.dispose();
    await db.close();
  });

  test('local login, failure, and logout are written to audit_logs', () async {
    expect(await repository.login('manager', 'wrong'), isNull);

    final user = await repository.login('manager', 'manager-password');
    expect(user, isNotNull);
    await repository.logout();

    final logs = await db.select(db.auditLogs).get();
    expect(
      logs.map((row) => row.action),
      containsAll(['login_failed', 'login', 'logout']),
    );
    expect(
      logs.firstWhere((row) => row.action == 'login_failed').userId,
      isNull,
    );
    expect(logs.firstWhere((row) => row.action == 'login').userId, user!.id);
    expect(logs.firstWhere((row) => row.action == 'logout').userId, user.id);
  });
}
