import '../entities/user_entity.dart';

abstract class UserRepositoryInterface {
  Stream<List<UserEntity>> watchAllUsers();
  Future<UserEntity?> getUserById(int id);
  Future<UserEntity> createUser({
    required String username,
    required String password,
    required UserRole role,
    int? employeeId,
    String? securityQuestion,
    String? securityAnswer,
  });
  Future<void> updateUser({
    required int id,
    String? username,
    String? password,
    UserRole? role,
    int? employeeId,
    bool clearEmployeeLink = false,
    String? securityQuestion,
    String? securityAnswer,
  });
  Future<void> toggleUserActive(int id, bool isActive);
  Future<bool> isUsernameTaken(String username, {int? excludeUserId});
  Future<Map<UserRole, int>> getRoleCounts();
  Stream<Map<UserRole, int>> watchRoleCounts();
}
