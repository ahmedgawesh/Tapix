import '../entities/user_entity.dart';

abstract class AuthRepositoryInterface {
  Future<UserEntity?> login(String username, String password, {bool rememberMe = false});
  Future<void> logout();
  Future<UserEntity?> getCurrentUser();
  Stream<UserEntity?> watchCurrentUser();
  Future<bool> hasAnyUsers();
  Future<UserEntity> createFirstOwner(
    String username,
    String password, {
    String? securityQuestion,
    String? securityAnswer,
  });
  Future<void> updateLastLogin(int userId);

  /// Get the security question for a user by username.
  /// Returns null if user not found or no security question set.
  Future<String?> getSecurityQuestion(String username);

  /// Verify the security answer and reset the password.
  /// Returns true if the answer was correct and password was reset.
  Future<bool> resetPasswordWithSecurityAnswer({
    required String username,
    required String securityAnswer,
    required String newPassword,
  });

  /// Set or update the security question and answer for a user.
  Future<void> setSecurityQuestion({
    required int userId,
    required String question,
    required String answer,
  });

  /// Re-authenticate the last logged-in user via biometric verification.
  /// Returns the user if a valid last-login user exists, null otherwise.
  Future<UserEntity?> loginWithBiometrics();
}
