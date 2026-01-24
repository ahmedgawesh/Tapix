import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';
import 'dart:developer' as developer;

import 'web/storage_notifier.dart';

Future<QueryExecutor> openDatabase() async {
  final result = await WasmDatabase.open(
    databaseName: 'tapix.db',
    sqlite3Uri: Uri.parse('sqlite3.wasm'),
    driftWorkerUri: Uri.parse('drift_worker.dart.js'),
  );

  StorageNotifier.update(_inferStorageTier(result));

  if (result.missingFeatures.isNotEmpty) {
    developer.log(
      'Using ${result.chosenImplementation} due to missing browser features: ${result.missingFeatures}',
      name: 'tapix.database',
    );
  }

  return result.resolvedExecutor;
}

String getStorageType(WasmDatabaseResult result) {
  return result.chosenImplementation.toString();
}

StorageTier _inferStorageTier(WasmDatabaseResult result) {
  final impl = result.chosenImplementation.toString().toLowerCase();
  if (impl.contains('opfs')) {
    return StorageTier.opfs;
  }
  if (impl.contains('indexed')) {
    return StorageTier.indexedDb;
  }
  return StorageTier.memory;
}
