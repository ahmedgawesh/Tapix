import 'database_reset_native.dart'
    if (dart.library.html) 'database_reset_web.dart';

abstract class DatabaseReset {
  static Future<bool> deleteDatabaseFile() => deleteDatabaseFileImpl();

  /// Deletes every local Tapix database variant, including SQLite WAL/SHM
  /// companions. Used only when an owner turns a LAN client into a fresh device.
  static Future<void> deleteAllLocalDatabaseFiles() =>
      deleteAllLocalDatabaseFilesImpl();

  static Future<String> getDatabaseLocation() => getDatabaseLocationImpl();
}
