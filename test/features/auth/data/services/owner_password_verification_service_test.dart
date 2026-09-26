import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/features/auth/data/services/owner_password_verification_service.dart';
import 'package:tapix/features/auth/data/services/password_service.dart';
import 'package:tapix/features/auth/data/services/session_service.dart';

class _MockSecureStorage extends Mock implements FlutterSecureStorage {}

void main() {
  late AppDatabase database;
  late SessionService session;
  late PasswordService passwords;
  late OwnerPasswordVerificationService service;

  setUp(() async {
    database = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    final storage = _MockSecureStorage();
    final values = <String, String?>{};
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
          call.namedArguments[#value] as String?;
    });
    when(() => storage.delete(key: any(named: 'key'))).thenAnswer((call) async {
      values.remove(call.namedArguments[#key] as String);
    });
    session = SessionService(storage: storage);
    passwords = PasswordService();
    service = OwnerPasswordVerificationService(
      database: database,
      passwordService: passwords,
      sessionService: session,
    );
  });

  tearDown(() async {
    session.dispose();
    await database.close();
  });

  Future<int> createUser(String role) async {
    final now = DateTime.now();
    return database
        .into(database.users)
        .insert(
          UsersCompanion.insert(
            username: role,
            passwordHash: passwords.hashPassword('correct-password'),
            role: role,
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  test('accepts only the current active owner password', () async {
    final ownerId = await createUser('owner');
    await session.saveSession(ownerId);

    expect(await service.verifyCurrentOwner('correct-password'), isTrue);
    expect(await service.verifyCurrentOwner('wrong-password'), isFalse);
  });

  test('rejects a valid password when the current user is not owner', () async {
    final managerId = await createUser('manager');
    await session.saveSession(managerId);

    expect(await service.verifyCurrentOwner('correct-password'), isFalse);
  });

  test('rejects verification without an authenticated session', () async {
    await createUser('owner');

    expect(await service.verifyCurrentOwner('correct-password'), isFalse);
  });
}
