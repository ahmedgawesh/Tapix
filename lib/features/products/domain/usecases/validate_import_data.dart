import '../entities/import_file_data.dart';
import '../entities/import_result.dart';

abstract class ValidateImportData {
  Future<List<ImportError>> call({
    required ImportFileData fileData,
    required ColumnMapping columnMapping,
  });
}
