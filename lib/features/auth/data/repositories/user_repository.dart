import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../domain/entities/user_entity.dart';
import '../../domain/repositories/user_repository_interface.dart';
import '../services/password_service.dart';

class UserRepository implements UserRepositoryInterface {
  final AppDatabase _database;
  final PasswordService _passwordService;

  UserRepository({
    required AppDatabase database,
    required PasswordService passwordService,
  }) : _database = database,
       _passwordService = passwordService;

  @override
  Stream<List<UserEntity>> watchAllUsers() {
    final query = _database.select(_database.users)
      ..orderBy([
        (u) => OrderingTerm(expression: u.createdAt, mode: OrderingMode.desc),
      ]);
    return query.watch().map((rows) => rows.map(_mapToEntity).toList());
  }

  @override
  Future<UserEntity?> getUserById(int id) async {
    final query = _database.select(_database.users)
      ..where((u) => u.id.equals(id));
    final user = await query.getSingleOrNull();
    if (user == null) return null;
    return _mapToEntity(user);
  }

  @override
  Future<UserEntity> createUser({
    required String username,
    required String password,
    required UserRole role,
    int? employeeId,
    String? branchId,
    String? warehouseId,
    bool hasGlobalLocationAccess = false,
    String? securityQuestion,
    String? securityAnswer,
  }) async {
    final now = DateTime.now();
    final hashedPassword = _passwordService.hashPassword(password);
    final hashedAnswer = securityAnswer != null && securityAnswer.isNotEmpty
        ? _passwordService.hashPassword(securityAnswer.trim().toLowerCase())
        : null;

    final id = await _database
        .into(_database.users)
        .insert(
          UsersCompanion.insert(
            username: username,
            passwordHash: hashedPassword,
            role: role.name,
            employeeId: Value(employeeId),
            branchId: Value(branchId),
            warehouseId: Value(warehouseId),
            globalLocationAccess: Value(hasGlobalLocationAccess),
            securityQuestion: Value(securityQuestion),
            securityAnswerHash: Value(hashedAnswer),
            createdAt: now,
            updatedAt: now,
          ),
        );

    final user = await (_database.select(
      _database.users,
    )..where((u) => u.id.equals(id))).getSingle();

    return _mapToEntity(user);
  }

  @override
  Future<void> updateUser({
    required int id,
    String? username,
    String? password,
    UserRole? role,
    int? employeeId,
    bool clearEmployeeLink = false,
    String? branchId,
    String? warehouseId,
    bool? hasGlobalLocationAccess,
    bool clearLocationAssignment = false,
    String? securityQuestion,
    String? securityAnswer,
  }) async {
    final now = DateTime.now();
    final hashedAnswer = securityAnswer != null && securityAnswer.isNotEmpty
        ? _passwordService.hashPassword(securityAnswer.trim().toLowerCase())
        : null;

    final companion = UsersCompanion(
      username: username != null ? Value(username) : const Value.absent(),
      passwordHash: password != null
          ? Value(_passwordService.hashPassword(password))
          : const Value.absent(),
      role: role != null ? Value(role.name) : const Value.absent(),
      employeeId: clearEmployeeLink
          ? const Value(null)
          : (employeeId != null ? Value(employeeId) : const Value.absent()),
      branchId: clearLocationAssignment
          ? const Value(null)
          : (branchId != null ? Value(branchId) : const Value.absent()),
      warehouseId: clearLocationAssignment
          ? const Value(null)
          : (warehouseId != null ? Value(warehouseId) : const Value.absent()),
      globalLocationAccess: hasGlobalLocationAccess != null
          ? Value(hasGlobalLocationAccess)
          : const Value.absent(),
      securityQuestion: securityQuestion != null
          ? Value(securityQuestion)
          : const Value.absent(),
      securityAnswerHash: hashedAnswer != null
          ? Value(hashedAnswer)
          : const Value.absent(),
      updatedAt: Value(now),
    );

    await (_database.update(
      _database.users,
    )..where((u) => u.id.equals(id))).write(companion);
  }

  @override
  Future<void> toggleUserActive(int id, bool isActive) async {
    final now = DateTime.now();
    await (_database.update(
      _database.users,
    )..where((u) => u.id.equals(id))).write(
      UsersCompanion(isActive: Value(isActive ? 1 : 0), updatedAt: Value(now)),
    );
  }

  @override
  Future<UserDeleteResult> deleteUser(int id) async {
    return _database.transaction(() async {
      final user = await (_database.select(
        _database.users,
      )..where((row) => row.id.equals(id))).getSingleOrNull();
      if (user == null) return UserDeleteResult.deleted;
      if (UserRole.fromString(user.role) == UserRole.owner) {
        return UserDeleteResult.ownerProtected;
      }

      if (await _hasOperationalHistory(id)) {
        return UserDeleteResult.hasOperationalHistory;
      }

      // The employee link is an identity assignment rather than an accounting
      // event. SQLite clears it through ON DELETE SET NULL. Every operational
      // reference is checked above and therefore remains immutable.
      final deleted = await (_database.delete(
        _database.users,
      )..where((row) => row.id.equals(id))).go();
      return deleted == 1
          ? UserDeleteResult.deleted
          : UserDeleteResult.hasOperationalHistory;
    });
  }

  Future<bool> _hasOperationalHistory(int userId) async {
    final tables = await _database
        .customSelect(
          'SELECT name FROM sqlite_master '
          'WHERE type = \'table\' AND name NOT LIKE \'sqlite_%\'',
        )
        .get();

    for (final tableRow in tables) {
      final tableName = tableRow.read<String>('name');
      if (tableName == 'users' || tableName == 'employees') continue;
      final quotedTable = _quoteIdentifier(tableName);
      final foreignKeys = await _database
          .customSelect('PRAGMA foreign_key_list($quotedTable)')
          .get();
      for (final foreignKey in foreignKeys) {
        if (foreignKey.read<String>('table') != 'users') continue;
        final columnName = foreignKey.read<String>('from');
        final quotedColumn = _quoteIdentifier(columnName);
        final reference = await _database
            .customSelect(
              'SELECT EXISTS('
              'SELECT 1 FROM $quotedTable WHERE $quotedColumn = ? LIMIT 1'
              ') AS has_reference',
              variables: [Variable<int>(userId)],
            )
            .getSingle();
        if (reference.read<int>('has_reference') == 1) return true;
      }
    }
    return false;
  }

  String _quoteIdentifier(String value) => '"${value.replaceAll('"', '""')}"';

  @override
  Future<bool> isUsernameTaken(String username, {int? excludeUserId}) async {
    final query = _database.select(_database.users)
      ..where((u) => u.username.equals(username));
    if (excludeUserId != null) {
      query.where((u) => u.id.equals(excludeUserId).not());
    }
    final result = await query.getSingleOrNull();
    return result != null;
  }

  @override
  Future<Map<UserRole, int>> getRoleCounts() async {
    final users = await _database.select(_database.users).get();
    final counts = <UserRole, int>{};
    for (final role in UserRole.values) {
      counts[role] = users.where((u) => u.role == role.name).length;
    }
    return counts;
  }

  @override
  Stream<Map<UserRole, int>> watchRoleCounts() {
    return _database.select(_database.users).watch().map((users) {
      final counts = <UserRole, int>{};
      for (final role in UserRole.values) {
        counts[role] = users.where((u) => u.role == role.name).length;
      }
      return counts;
    });
  }

  UserEntity _mapToEntity(User user) {
    return UserEntity(
      id: user.id,
      username: user.username,
      role: UserRole.fromString(user.role),
      employeeId: user.employeeId,
      branchId: user.branchId,
      warehouseId: user.warehouseId,
      hasGlobalLocationAccess: user.globalLocationAccess,
      isActive: user.isActive == 1,
      createdAt: user.createdAt,
      updatedAt: user.updatedAt,
      lastLoginAt: user.lastLoginAt,
    );
  }
}
