import 'dart:typed_data';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import '../domain/entities/import_file_data.dart';
import '../domain/usecases/parse_import_file.dart';

class FileImportService implements ParseImportFile {
  @override
  Future<ImportFileData> call({
    required List<int> bytes,
    required String fileName,
  }) async {
    final fileType = _determineFileType(fileName);
    
    if (fileType == ImportFileType.csv) {
      return _parseCsv(bytes, fileName);
    } else {
      return _parseExcel(bytes, fileName);
    }
  }

  ImportFileType _determineFileType(String fileName) {
    final extension = fileName.toLowerCase().split('.').last;
    if (extension == 'csv') {
      return ImportFileType.csv;
    } else if (extension == 'xlsx' || extension == 'xls') {
      return ImportFileType.excel;
    }
    throw Exception('Unsupported file type: $extension');
  }

  Future<ImportFileData> _parseCsv(List<int> bytes, String fileName) async {
    try {
      final csvString = String.fromCharCodes(bytes);
      final csvConverter = const CsvToListConverter(eol: '\n');
      final rows = csvConverter.convert(csvString);

      if (rows.isEmpty) {
        throw Exception('CSV file is empty');
      }

      final headers = rows.first.map((e) => e.toString().trim()).toList();
      final dataRows = rows.skip(1).map((row) {
        return row.map((cell) => cell?.toString() ?? '').toList();
      }).toList();

      return ImportFileData(
        fileName: fileName,
        fileType: ImportFileType.csv,
        headers: headers,
        rows: dataRows,
        totalRows: dataRows.length,
      );
    } catch (e) {
      throw Exception('Failed to parse CSV file: ${e.toString()}');
    }
  }

  Future<ImportFileData> _parseExcel(List<int> bytes, String fileName) async {
    try {
      final excel = Excel.decodeBytes(Uint8List.fromList(bytes));
      
      if (excel.tables.isEmpty) {
        throw Exception('Excel file has no sheets');
      }

      final sheet = excel.tables[excel.tables.keys.first];
      if (sheet == null || sheet.rows.isEmpty) {
        throw Exception('Excel sheet is empty');
      }

      final rows = sheet.rows;
      final headerRow = rows.first;
      final headers = headerRow
          .map((cell) => cell?.value?.toString() ?? '')
          .toList();

      final dataRows = rows.skip(1).map((row) {
        return row.map((cell) => cell?.value?.toString() ?? '').toList();
      }).toList();

      return ImportFileData(
        fileName: fileName,
        fileType: ImportFileType.excel,
        headers: headers,
        rows: dataRows,
        totalRows: dataRows.length,
      );
    } catch (e) {
      throw Exception('Failed to parse Excel file: ${e.toString()}');
    }
  }
}
