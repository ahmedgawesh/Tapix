import '../../../../core/database/app_database.dart';
import 'password_service.dart';
import 'session_service.dart';

class OwnerPasswordVerificationService {
  const OwnerPasswordVerificationService({
    required AppDatabase database,
    required PasswordService passwordService,
    required SessionService sessionService,
  }) : _database = database,
       _passwordService = passwordService,
       _sessionService = sessionService;

  final AppDatabase _database;
  final PasswordService _passwordService;
  final SessionService _sessionService;

  Future<bool> verifyCurrentOwner(String password) async {
    if (password.isEmpty) return false;
    final userId = await _sessionService.getCurrentUserId();
    if (userId == null) return false;
    final user =
        await (_database.select(_database.users)
              ..where((row) => row.id.equals(userId))
              ..where((row) => row.isActive.equals(1)))
            .getSingleOrNull();
    if (user == null || user.role.toLowerCase() != 'owner') return false;
    return _passwordService.verifyPassword(password, user.passwordHash);
  }
}
