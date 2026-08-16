import 'package:equatable/equatable.dart';
import '../../domain/entities/import_file_data.dart';
import '../../domain/entities/import_result.dart';

abstract class ImportProductsState extends Equatable {
  const ImportProductsState();

  @override
  List<Object?> get props => [];
}

class ImportProductsInitial extends ImportProductsState {
  const ImportProductsInitial();
}

class ImportFileLoading extends ImportProductsState {
  const ImportFileLoading();
}

class ImportFileParsed extends ImportProductsState {
  final ImportFileData fileData;
  final List<ImportFieldDefinition> availableFields;

  const ImportFileParsed({
    required this.fileData,
    required this.availableFields,
  });

  @override
  List<Object?> get props => [fileData, availableFields];
}

class ImportColumnMappingReady extends ImportProductsState {
  final ImportFileData fileData;
  final ColumnMapping columnMapping;
  final List<ImportFieldDefinition> availableFields;

  const ImportColumnMappingReady({
    required this.fileData,
    required this.columnMapping,
    required this.availableFields,
  });

  @override
  List<Object?> get props => [fileData, columnMapping, availableFields];
}

class ImportValidating extends ImportProductsState {
  final ImportFileData fileData;
  final ColumnMapping columnMapping;

  const ImportValidating({required this.fileData, required this.columnMapping});

  @override
  List<Object?> get props => [fileData, columnMapping];
}

class ImportValidated extends ImportProductsState {
  final ImportFileData fileData;
  final ColumnMapping columnMapping;
  final List<ImportError> validationErrors;

  const ImportValidated({
    required this.fileData,
    required this.columnMapping,
    required this.validationErrors,
  });

  bool get hasErrors => validationErrors.isNotEmpty;

  @override
  List<Object?> get props => [fileData, columnMapping, validationErrors];
}

class ImportInProgress extends ImportProductsState {
  final ImportFileData fileData;
  final ColumnMapping columnMapping;
  final int processedRows;
  final int totalRows;

  const ImportInProgress({
    required this.fileData,
    required this.columnMapping,
    required this.processedRows,
    required this.totalRows,
  });

  double get progress => totalRows > 0 ? (processedRows / totalRows) : 0.0;

  @override
  List<Object?> get props => [
    fileData,
    columnMapping,
    processedRows,
    totalRows,
  ];
}

class ImportCompleted extends ImportProductsState {
  final ImportResult result;

  const ImportCompleted(this.result);

  @override
  List<Object?> get props => [result];
}

class ImportFailed extends ImportProductsState {
  final String errorMessage;
  final ImportFileData? fileData;

  const ImportFailed({required this.errorMessage, this.fileData});

  @override
  List<Object?> get props => [errorMessage, fileData];
}
