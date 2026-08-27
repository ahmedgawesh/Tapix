import 'dart:async';

import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/services/audit_log_service.dart';
import '../../../../core/services/currency_service.dart' as money;
import '../../../../core/services/lan/lan_network_service.dart';
import '../../domain/entities/user_entity.dart';
import '../../domain/repositories/auth_repository_interface.dart';
import '../services/password_service.dart';
import '../services/session_service.dart';

class AuthRepository implements AuthRepositoryInterface {
  final AppDatabase _database;
  final PasswordService _passwordService;
  final SessionService _sessionService;
  final LanNetworkService? _lanNetworkService;
  final AuditLogService? _auditLogService;
  final money.CurrencyService? _currencyService;

  final _userController = StreamController<UserEntity?>.broadcast();
  LanRemoteUser? _lastKnownRemoteUser;

  AuthRepository({
    required AppDatabase database,
    required PasswordService passwordService,
    required SessionService sessionService,
    LanNetworkService? lanNetworkService,
    AuditLogService? auditLogService,
    money.CurrencyService? currencyService,
  }) : _database = database,
       _passwordService = passwordService,
       _sessionService = sessionService,
       _lanNetworkService = lanNetworkService,
       _auditLogService = auditLogService,
       _currencyService = currencyService {
    _initializeSession();
    _lastKnownRemoteUser = _lanNetworkService?.remoteUser;
    _lanNetworkService?.changes.listen((snapshot) {
      final currentRemoteUser = _lanNetworkService.remoteUser;
      if (snapshot.mode == LanMode.client &&
          currentRemoteUser == null &&
          _lastKnownRemoteUser != null) {
        _userController.add(null);
      }
      _lastKnownRemoteUser = currentRemoteUser;
    });
  }

  void _initializeSession() {
    _sessionService.sessionStream.listen((userId) async {
      if (userId != null) {
        if (_isRemoteClient) {
          _userController.add(null);
          return;
        }
        final user = await _getUserById(userId);
        _userController.add(user);
      } else {
        _userController.add(null);
      }
    });
  }

  bool get _isRemoteClient =>
      _lanNetworkService?.snapshot.mode == LanMode.client;

  @override
  Future<UserEntity?> login(
    String username,
    String password, {
    bool rememberMe = false,
  }) async {
    // A paired device authenticates only against the master. It must never
    // fall back to a local desktop account with the same credentials.
    if (_isRemoteClient) {
      final result = await _lanNetworkService!.loginToMaster(
        username: username,
        password: password,
        rememberMe: rememberMe,
      );
      final remote = result.user;
      if (!result.success || remote == null) return null;
      await _syncRemoteCurrency();
      final entity = _mapRemoteToEntity(remote);
      _userController.add(entity);
      return entity;
    }
    final query = _database.select(_database.users)
      ..where((u) => u.username.equals(username))
      ..where((u) => u.isActive.equals(1));

    final user = await query.getSingleOrNull();
    if (user == null ||
        !_passwordService.verifyPassword(password, user.passwordHash)) {
      await _auditLogService?.logLanSecurityEvent(
        action: 'login_failed',
        targetUserId: user?.id,
        username: username,
        role: user?.role,
        deviceId: 'local',
        deviceName: 'Local master device',
        reason: 'Invalid credentials.',
      );
      return null;
    }

    await updateLastLogin(user.id);
    await _sessionService.saveSession(user.id, rememberMe: rememberMe);

    final entity = _mapToEntity(user);
    await _auditLogService?.logUserLogin(
      targetUserId: entity.id,
      username: entity.username,
      role: entity.role.name,
    );
    _userController.add(entity);
    return entity;
  }

  Future<void> _syncRemoteCurrency() async {
    final lan = _lanNetworkService;
    final currencies = _currencyService;
    if (lan == null || currencies == null) return;
    final catalog = await lan.fetchRemoteCatalog(limit: 1);
    final code = catalog.currencyCode.trim().toUpperCase();
    if (code.isEmpty) return;
    if (!money.Currency.allCurrencies.any((value) => value.code == code)) {
      await currencies.addCustomCurrency(
        money.Currency(
          code: code,
          symbol: catalog.currencySymbol,
          name: code,
          isCustom: true,
        ),
      );
    }
    await currencies.setCurrency(code);
  }

  @override
  Future<void> logout() async {
    if (_isRemoteClient) {
      await _lanNetworkService!.logoutFromMaster();
    } else {
      final current = await getCurrentUser();
      await _sessionService.clearSession();
      if (current != null) {
        await _auditLogService?.logUserLogout(
          targetUserId: current.id,
          username: current.username,
          role: current.role.name,
        );
      }
    }
    _userController.add(null);
  }

  @override
  Future<UserEntity?> getCurrentUser() async {
    if (_isRemoteClient) {
      final remote = _lanNetworkService?.remoteUser;
      return remote == null ? null : _mapRemoteToEntity(remote);
    }

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
    // Client devices use the user directory owned by the master. Returning
    // true here routes them to login instead of creating an unsafe local owner.
    if (_isRemoteClient) return true;

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
    if (_isRemoteClient) {
      throw const RemoteAuthenticationRequiredException();
    }
    final hasUsers = await hasAnyUsers();
    if (hasUsers) {
      throw Exception('Cannot create first owner: users already exist');
    }

    final now = DateTime.now();
    final hashedPassword = _passwordService.hashPassword(password);
    final hashedAnswer = securityAnswer != null
        ? _passwordService.hashPassword(securityAnswer.trim().toLowerCase())
        : null;

    final id = await _database
        .into(_database.users)
        .insert(
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

    final user = await (_database.select(
      _database.users,
    )..where((u) => u.id.equals(id))).getSingle();

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
    if (!_passwordService.verifyPassword(
      normalizedAnswer,
      user.securityAnswerHash!,
    )) {
      return false;
    }

    final hashedPassword = _passwordService.hashPassword(newPassword);
    final now = DateTime.now();
    await (_database.update(
      _database.users,
    )..where((u) => u.id.equals(user.id))).write(
      UsersCompanion(
        passwordHash: Value(hashedPassword),
        updatedAt: Value(now),
      ),
    );

    return true;
  }

  @override
  Future<void> setSecurityQuestion({
    required int userId,
    required String question,
    required String answer,
  }) async {
    final hashedAnswer = _passwordService.hashPassword(
      answer.trim().toLowerCase(),
    );
    final now = DateTime.now();
    await (_database.update(
      _database.users,
    )..where((u) => u.id.equals(userId))).write(
      UsersCompanion(
        securityQuestion: Value(question),
        securityAnswerHash: Value(hashedAnswer),
        updatedAt: Value(now),
      ),
    );
  }

  @override
  Future<UserEntity?> loginWithBiometrics() async {
    if (_isRemoteClient) return null;

    // The active session is intentionally gone after logout. Biometrics may
    // only reopen the last locally authenticated account.
    final userId = await _sessionService.getLastAuthenticatedUserId();
    if (userId == null) return null;

    final user = await _getUserById(userId);
    if (user == null || !user.isActive) return null;

    // Refresh the session
    await updateLastLogin(user.id);
    await _sessionService.saveSession(user.id);

    await _auditLogService?.logUserLogin(
      targetUserId: user.id,
      username: user.username,
      role: user.role.name,
    );
    _userController.add(user);
    return user;
  }

  UserEntity _mapRemoteToEntity(LanRemoteUser user) {
    return UserEntity(
      id: user.id,
      username: user.username,
      role: UserRole.fromString(user.role),
      employeeId: user.employeeId,
      isActive: user.isActive,
      createdAt: user.createdAt,
      updatedAt: user.updatedAt,
      lastLoginAt: user.lastLoginAt,
    );
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
