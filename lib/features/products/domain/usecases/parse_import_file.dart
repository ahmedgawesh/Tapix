import '../entities/import_file_data.dart';

abstract class ParseImportFile {
  Future<ImportFileData> call({
    required List<int> bytes,
    required String fileName,
  });
}
