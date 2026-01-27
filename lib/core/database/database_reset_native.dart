import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

Future<String> getDatabaseLocationImpl() async {
  final dbFolder = await getApplicationDocumentsDirectory();
  return p.join(dbFolder.path, 'tapix.db');
}

Future<bool> deleteDatabaseFileImpl() async {
  final path = await getDatabaseLocationImpl();
  final file = File(path);
  if (await file.exists()) {
    await file.delete();
    return true;
  }
  return false;
}
