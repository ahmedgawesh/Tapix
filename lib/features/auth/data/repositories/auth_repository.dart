import 'dart:async';

import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../domain/entities/user_entity.dart';
import '../../domain/repositories/auth_repository_interface.dart';
import '../services/password_service.dart';
import '../services/session_service.dart';

class AuthRepository implements AuthRepositoryInterface {
  final AppDatabase _database;
  final PasswordService _passwordService;
  final SessionService _sessionService;

  final _userController = StreamController<UserEntity?>.broadcast();

  AuthRepository({
    required AppDatabase database,
    required PasswordService passwordService,
    required SessionService sessionService,
  })  : _database = database,
        _passwordService = passwordService,
        _sessionService = sessionService {
    _initializeSession();
  }

  void _initializeSession() {
    _sessionService.sessionStream.listen((userId) async {
      if (userId != null) {
        final user = await _getUserById(userId);
        _userController.add(user);
      } else {
        _userController.add(null);
      }
    });
  }

  @override
  Future<UserEntity?> login(String username, String password, {bool rememberMe = false}) async {
    final query = _database.select(_database.users)
      ..where((u) => u.username.equals(username))
      ..where((u) => u.isActive.equals(1));

    final user = await query.getSingleOrNull();
    if (user == null) return null;

    if (!_passwordService.verifyPassword(password, user.passwordHash)) {
      return null;
    }

    await updateLastLogin(user.id);
    await _sessionService.saveSession(user.id, rememberMe: rememberMe);

    final entity = _mapToEntity(user);
    _userController.add(entity);
    return entity;
  }

  @override
  Future<void> logout() async {
    await _sessionService.clearSession();
    _userController.add(null);
  }

  @override
  Future<UserEntity?> getCurrentUser() async {
    final userId = await _sessionService.getCurrentUserId();
    if (userId == null) return null;

    final isValid = await _sessionService.isSessionValid();
    if (!isValid) {
      await _sessionService.clearSession();
      return null;
    }

    return _getUserById(userId);
  }

  @override
  Stream<UserEntity?> watchCurrentUser() => _userController.stream;

  @override
  Future<bool> hasAnyUsers() async {
    final query = _database.selectOnly(_database.users)
      ..addColumns([_database.users.id.count()]);
    final result = await query.getSingle();
    final count = result.read(_database.users.id.count()) ?? 0;
    return count > 0;
  }

  @override
  Future<UserEntity> createFirstOwner(
    String username,
    String password, {
    String? securityQuestion,
    String? securityAnswer,
  }) async {
    final hasUsers = await hasAnyUsers();
    if (hasUsers) {
      throw Exception('Cannot create first owner: users already exist');
    }

    final now = DateTime.now();
    final hashedPassword = _passwordService.hashPassword(password);
    final hashedAnswer = securityAnswer != null
        ? _passwordService.hashPassword(securityAnswer.trim().toLowerCase())
        : null;

    final id = await _database.into(_database.users).insert(
      UsersCompanion.insert(
        username: username,
        passwordHash: hashedPassword,
        role: 'owner',
        securityQuestion: Value(securityQuestion),
        securityAnswerHash: Value(hashedAnswer),
        createdAt: now,
        updatedAt: now,
      ),
    );

    final user = await (_database.select(_database.users)
          ..where((u) => u.id.equals(id)))
        .getSingle();

    await _sessionService.saveSession(id);
    final entity = _mapToEntity(user);
    _userController.add(entity);
    return entity;
  }

  @override
  Future<void> updateLastLogin(int userId) async {
    final now = DateTime.now();
    await (_database.update(_database.users)..where((u) => u.id.equals(userId)))
        .write(UsersCompanion(lastLoginAt: Value(now)));
  }

  Future<UserEntity?> _getUserById(int userId) async {
    final query = _database.select(_database.users)
      ..where((u) => u.id.equals(userId));

    final user = await query.getSingleOrNull();
    if (user == null) return null;

    return _mapToEntity(user);
  }

  @override
  Future<String?> getSecurityQuestion(String username) async {
    final query = _database.select(_database.users)
      ..where((u) => u.username.equals(username))
      ..where((u) => u.isActive.equals(1));

    final user = await query.getSingleOrNull();
    return user?.securityQuestion;
  }

  @override
  Future<bool> resetPasswordWithSecurityAnswer({
    required String username,
    required String securityAnswer,
    required String newPassword,
  }) async {
    final query = _database.select(_database.users)
      ..where((u) => u.username.equals(username))
      ..where((u) => u.isActive.equals(1));

    final user = await query.getSingleOrNull();
    if (user == null) return false;
    if (user.securityAnswerHash == null) return false;

    final normalizedAnswer = securityAnswer.trim().toLowerCase();
    if (!_passwordService.verifyPassword(normalizedAnswer, user.securityAnswerHash!)) {
      return false;
    }

    final hashedPassword = _passwordService.hashPassword(newPassword);
    final now = DateTime.now();
    await (_database.update(_database.users)..where((u) => u.id.equals(user.id)))
        .write(UsersCompanion(
      passwordHash: Value(hashedPassword),
      updatedAt: Value(now),
    ));

    return true;
  }

  @override
  Future<void> setSecurityQuestion({
    required int userId,
    required String question,
    required String answer,
  }) async {
    final hashedAnswer = _passwordService.hashPassword(answer.trim().toLowerCase());
    final now = DateTime.now();
    await (_database.update(_database.users)..where((u) => u.id.equals(userId)))
        .write(UsersCompanion(
      securityQuestion: Value(question),
      securityAnswerHash: Value(hashedAnswer),
      updatedAt: Value(now),
    ));
  }

  @override
  Future<UserEntity?> loginWithBiometrics() async {
    // Re-authenticate using the last saved session user
    final userId = await _sessionService.getCurrentUserId();
    if (userId == null) return null;

    final user = await _getUserById(userId);
    if (user == null) return null;

    // Refresh the session
    await updateLastLogin(user.id);
    await _sessionService.saveSession(user.id);

    _userController.add(user);
    return user;
  }

  UserEntity _mapToEntity(User user) {
    return UserEntity(
      id: user.id,
      username: user.username,
      role: UserRole.fromString(user.role),
      employeeId: user.employeeId,
      isActive: user.isActive == 1,
      createdAt: user.createdAt,
      updatedAt: user.updatedAt,
      lastLoginAt: user.lastLoginAt,
    );
  }

  void dispose() {
    _userController.close();
  }
}
