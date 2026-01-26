import 'package:equatable/equatable.dart';

class ImportFileData extends Equatable {
  final String fileName;
  final ImportFileType fileType;
  final List<String> headers;
  final List<List<String>> rows;
  final int totalRows;

  const ImportFileData({
    required this.fileName,
    required this.fileType,
    required this.headers,
    required this.rows,
    required this.totalRows,
  });

  @override
  List<Object?> get props => [fileName, fileType, headers, rows, totalRows];
}

enum ImportFileType {
  csv,
  excel,
}

class ColumnMapping extends Equatable {
  final Map<String, int> fieldToColumnIndex;

  const ColumnMapping(this.fieldToColumnIndex);

  int? getColumnIndex(String field) => fieldToColumnIndex[field];

  bool hasMapping(String field) => fieldToColumnIndex.containsKey(field);

  @override
  List<Object?> get props => [fieldToColumnIndex];
}

class ImportFieldDefinition extends Equatable {
  final String fieldName;
  final String displayName;
  final bool isRequired;
  final ImportFieldType fieldType;
  final String? hint;

  const ImportFieldDefinition({
    required this.fieldName,
    required this.displayName,
    required this.isRequired,
    required this.fieldType,
    this.hint,
  });

  @override
  List<Object?> get props => [fieldName, displayName, isRequired, fieldType, hint];
}

enum ImportFieldType {
  text,
  number,
  money,
  boolean,
  integer,
}
