import 'package:bcrypt/bcrypt.dart';

class PasswordService {
  static const int _saltRounds = 12;

  String hashPassword(String password) {
    return BCrypt.hashpw(password, BCrypt.gensalt(logRounds: _saltRounds));
  }

  bool verifyPassword(String password, String hashedPassword) {
    try {
      return BCrypt.checkpw(password, hashedPassword);
    } catch (_) {
      return false;
    }
  }
}
