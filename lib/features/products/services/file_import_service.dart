import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';
import '../domain/entities/import_file_data.dart';
import '../domain/usecases/parse_import_file.dart';

class FileImportService implements ParseImportFile {
  @override
  Future<ImportFileData> call({
    required List<int> bytes,
    required String fileName,
  }) async {
    final fileType = _determineFileType(bytes, fileName);

    debugPrint('[FileImportService] Detected file type=$fileType name=$fileName size=${bytes.length}');
    
    if (fileType == ImportFileType.csv) {
      return _parseCsv(bytes, fileName);
    } else {
      return _parseExcel(bytes, fileName);
    }
  }

  ImportFileType _determineFileType(List<int> bytes, String fileName) {
    final lowerName = fileName.toLowerCase();

    // 1) Magic bytes
    if (_looksLikeZip(bytes) || _looksLikeLegacyXls(bytes)) {
      return ImportFileType.excel;
    }

    // 2) Fallback to filename extension if present
    final extension = lowerName.contains('.') ? lowerName.split('.').last : '';
    if (extension == 'xlsx' || extension == 'xls') {
      return ImportFileType.excel;
    }
    if (extension == 'csv') {
      return ImportFileType.csv;
    }

    // 3) Heuristic CSV detection
    if (_looksLikeCsv(bytes)) {
      return ImportFileType.csv;
    }

    throw Exception('Unsupported file type: $fileName');
  }

  bool _looksLikeZip(List<int> bytes) {
    if (bytes.length < 4) return false;
    // ZIP magic: PK\x03\x04
    return bytes[0] == 0x50 && bytes[1] == 0x4B && bytes[2] == 0x03 && bytes[3] == 0x04;
  }

  bool _looksLikeLegacyXls(List<int> bytes) {
    if (bytes.length < 8) return false;
    // OLE Compound File magic (old .xls): D0 CF 11 E0 A1 B1 1A E1
    return bytes[0] == 0xD0 &&
        bytes[1] == 0xCF &&
        bytes[2] == 0x11 &&
        bytes[3] == 0xE0 &&
        bytes[4] == 0xA1 &&
        bytes[5] == 0xB1 &&
        bytes[6] == 0x1A &&
        bytes[7] == 0xE1;
  }

  bool _looksLikeCsv(List<int> bytes) {
    if (bytes.isEmpty) return false;
    final sampleSize = bytes.length > 4096 ? 4096 : bytes.length;
    var commas = 0;
    var newLines = 0;
    var printable = 0;
    for (var i = 0; i < sampleSize; i++) {
      final b = bytes[i];
      if (b == 0x2C) commas++;
      if (b == 0x0A || b == 0x0D) newLines++;
      final isPrintable = (b >= 0x20 && b <= 0x7E) || b == 0x09 || b == 0x0A || b == 0x0D;
      if (isPrintable) printable++;
    }
    final printableRatio = printable / sampleSize;
    return printableRatio > 0.85 && commas > 0 && newLines > 0;
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

      Sheet? selectedSheet;
      String? selectedSheetName;

      for (final sheetName in excel.tables.keys) {
        final sheet = excel.tables[sheetName];
        if (sheet == null) continue;

        // Consider a sheet non-empty if it has at least a header row with any non-empty cell
        final hasAnyCell = sheet.rows.any(
          (List<Data?> row) => row.any(
            (Data? cell) => (cell?.value?.toString() ?? '').trim().isNotEmpty,
          ),
        );
        if (hasAnyCell) {
          selectedSheet = sheet;
          selectedSheetName = sheetName;
          break;
        }
      }

      if (selectedSheet == null) {
        throw Exception('Excel sheet is empty');
      }

      debugPrint(
        '[FileImportService] Excel sheets=${excel.tables.keys.length} selected=$selectedSheetName rows=${selectedSheet.rows.length}',
      );

      final rows = selectedSheet.rows;
      final headerRow = rows.first;
      final headers = headerRow
          .map((Data? cell) => cell?.value?.toString() ?? '')
          .map((String h) => h.trim())
          .toList();

      final dataRows = rows
          .skip(1)
          .map(
            (List<Data?> row) => row
                .map((Data? cell) => (cell?.value?.toString() ?? '').trim())
                .toList(),
          )
          .where((List<String> row) => row.any((String cell) => cell.isNotEmpty))
          .toList();

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
