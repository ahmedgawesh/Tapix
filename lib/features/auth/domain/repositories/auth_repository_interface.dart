import '../entities/user_entity.dart';

abstract class AuthRepositoryInterface {
  Future<UserEntity?> login(String username, String password);
  Future<void> logout();
  Future<UserEntity?> getCurrentUser();
  Stream<UserEntity?> watchCurrentUser();
  Future<bool> hasAnyUsers();
  Future<UserEntity> createFirstOwner(String username, String password);
  Future<void> updateLastLogin(int userId);
}
