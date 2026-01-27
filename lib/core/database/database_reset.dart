import 'database_reset_native.dart' if (dart.library.html) 'database_reset_web.dart';

abstract class DatabaseReset {
  static Future<bool> deleteDatabaseFile() => deleteDatabaseFileImpl();

  static Future<String> getDatabaseLocation() => getDatabaseLocationImpl();
}
