import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/features/auth/data/repositories/user_repository.dart';
import 'package:tapix/features/auth/data/services/password_service.dart';
import 'package:tapix/features/auth/domain/entities/user_entity.dart';
import 'package:tapix/features/auth/domain/repositories/user_repository_interface.dart';

void main() {
  late AppDatabase db;
  late UserRepository repository;

  setUp(() {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    repository = UserRepository(
      database: db,
      passwordService: PasswordService(),
    );
  });

  tearDown(() async {
    await db.close();
  });

  test(
    'warehouse clerk role parsing accepts persisted camel and snake case',
    () {
      expect(UserRole.fromString('warehouseClerk'), UserRole.warehouseClerk);
      expect(UserRole.fromString('warehouse_clerk'), UserRole.warehouseClerk);
    },
  );

  test('warehouse clerk role and location survive create and edit', () async {
    final created = await repository.createUser(
      username: 'storekeeper',
      password: '123456',
      role: UserRole.salesperson,
      branchId: 'branch-a',
      warehouseId: 'warehouse-a',
    );

    await repository.updateUser(
      id: created.id,
      role: UserRole.warehouseClerk,
      branchId: 'branch-b',
      warehouseId: 'warehouse-b',
      hasGlobalLocationAccess: false,
    );

    final updated = await repository.getUserById(created.id);
    expect(updated?.role, UserRole.warehouseClerk);
    expect(updated?.branchId, 'branch-b');
    expect(updated?.warehouseId, 'warehouse-b');
  });

  test('unused non-owner account can be deleted', () async {
    final user = await repository.createUser(
      username: 'wrong-account',
      password: '123456',
      role: UserRole.salesperson,
    );

    expect(await repository.deleteUser(user.id), UserDeleteResult.deleted);
    expect(await repository.getUserById(user.id), isNull);
  });

  test('owner account is protected from deletion', () async {
    final user = await repository.createUser(
      username: 'owner',
      password: '123456',
      role: UserRole.owner,
      hasGlobalLocationAccess: true,
    );

    expect(
      await repository.deleteUser(user.id),
      UserDeleteResult.ownerProtected,
    );
    expect(await repository.getUserById(user.id), isNotNull);
  });

  test('account with audit history is retained for attribution', () async {
    final user = await repository.createUser(
      username: 'audited-user',
      password: '123456',
      role: UserRole.warehouseClerk,
      branchId: 'branch-a',
      warehouseId: 'warehouse-a',
    );
    await db.customStatement(
      'INSERT INTO audit_logs '
      '(target_table, record_id, action, changes, user_id) '
      "VALUES ('users', ?, 'update', '{}', ?)",
      [user.id, user.id],
    );

    expect(
      await repository.deleteUser(user.id),
      UserDeleteResult.hasOperationalHistory,
    );
    expect(await repository.getUserById(user.id), isNotNull);
  });
}
