import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/features/auth/auth.dart';

void main() {
  late PasswordService passwordService;

  setUp(() {
    passwordService = PasswordService();
  });

  group('PasswordService', () {
    test('hashPassword returns a bcrypt hash', () {
      const password = 'testpassword123';
      final hash = passwordService.hashPassword(password);

      expect(hash, isNotEmpty);
      expect(hash, startsWith(r'$2'));
      expect(hash.length, greaterThan(50));
    });

    test('hashPassword returns different hashes for same password (due to salt)', () {
      const password = 'testpassword123';
      final hash1 = passwordService.hashPassword(password);
      final hash2 = passwordService.hashPassword(password);

      expect(hash1, isNot(equals(hash2)));
    });

    test('verifyPassword returns true for correct password', () {
      const password = 'testpassword123';
      final hash = passwordService.hashPassword(password);

      expect(passwordService.verifyPassword(password, hash), isTrue);
    });

    test('verifyPassword returns false for incorrect password', () {
      const password = 'testpassword123';
      const wrongPassword = 'wrongpassword';
      final hash = passwordService.hashPassword(password);

      expect(passwordService.verifyPassword(wrongPassword, hash), isFalse);
    });

    test('verifyPassword returns false for invalid hash', () {
      const password = 'testpassword123';
      const invalidHash = 'not-a-valid-hash';

      expect(passwordService.verifyPassword(password, invalidHash), isFalse);
    });

    test('verifyPassword handles empty password', () {
      const password = '';
      final hash = passwordService.hashPassword(password);

      expect(passwordService.verifyPassword(password, hash), isTrue);
      expect(passwordService.verifyPassword('notempty', hash), isFalse);
    });
  });
}
