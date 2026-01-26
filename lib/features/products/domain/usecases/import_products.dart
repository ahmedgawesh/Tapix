import '../entities/import_file_data.dart';
import '../entities/import_result.dart';

abstract class ImportProducts {
  Future<ImportResult> call({
    required ImportFileData fileData,
    required ColumnMapping columnMapping,
    Stream<ImportProgress> Function()? progressStream,
  });
}
