import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/features/auth/auth.dart';

void main() {
  group('AuthWrapper State Logic', () {
    test('AuthNeedsSetup state indicates setup is needed', () {
      const state = AuthNeedsSetup();
      expect(state, isA<AuthNeedsSetup>());
    });

    test('AuthUnauthenticated state indicates user needs to login', () {
      const state = AuthUnauthenticated();
      expect(state, isA<AuthUnauthenticated>());
    });

    test('AuthAuthenticated state contains user data', () {
      final user = UserEntity(
        id: 1,
        username: 'test',
        role: UserRole.owner,
        isActive: true,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final state = AuthAuthenticated(user: user);
      expect(state, isA<AuthAuthenticated>());
      expect(state.user.username, equals('test'));
      expect(state.user.role, equals(UserRole.owner));
    });

    test('AuthLoading state indicates loading', () {
      const state = AuthLoading();
      expect(state, isA<AuthLoading>());
    });

    test('AuthError state contains error message', () {
      const state = AuthError(message: 'Test error');
      expect(state, isA<AuthError>());
      expect(state.message, equals('Test error'));
    });

    test('UserEntity has correct properties', () {
      final now = DateTime.now();
      final user = UserEntity(
        id: 1,
        username: 'testuser',
        role: UserRole.manager,
        isActive: true,
        createdAt: now,
        updatedAt: now,
      );

      expect(user.id, equals(1));
      expect(user.username, equals('testuser'));
      expect(user.role, equals(UserRole.manager));
      expect(user.isActive, isTrue);
      expect(user.createdAt, equals(now));
      expect(user.updatedAt, equals(now));
    });
  });
}
