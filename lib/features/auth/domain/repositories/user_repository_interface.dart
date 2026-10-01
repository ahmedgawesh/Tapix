import '../entities/user_entity.dart';

enum UserDeleteResult { deleted, ownerProtected, hasOperationalHistory }

abstract class UserRepositoryInterface {
  Stream<List<UserEntity>> watchAllUsers();
  Future<UserEntity?> getUserById(int id);
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
  });
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
  });
  Future<void> toggleUserActive(int id, bool isActive);
  Future<UserDeleteResult> deleteUser(int id);
  Future<bool> isUsernameTaken(String username, {int? excludeUserId});
  Future<Map<UserRole, int>> getRoleCounts();
  Stream<Map<UserRole, int>> watchRoleCounts();
}
