Future<String> getDatabaseLocationImpl() async {
  return 'web:tapix.db';
}

Future<bool> deleteDatabaseFileImpl() async {
  return false;
}

Future<void> deleteAllLocalDatabaseFilesImpl() async {
  throw UnsupportedError(
    'Creating a fresh LAN device database is not supported on web.',
  );
}
