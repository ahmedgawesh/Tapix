import 'package:equatable/equatable.dart';

class ImportResult extends Equatable {
  final int totalRows;
  final int successfulRows;
  final int failedRows;
  final List<ImportError> errors;
  final Map<int, int> rowToProductId;
  final Duration duration;

  const ImportResult({
    required this.totalRows,
    required this.successfulRows,
    required this.failedRows,
    required this.errors,
    required this.rowToProductId,
    required this.duration,
  });

  bool get hasErrors => errors.isNotEmpty;
  bool get isFullSuccess => failedRows == 0;
  bool get isPartialSuccess => successfulRows > 0 && failedRows > 0;
  bool get isFullFailure => successfulRows == 0 && failedRows > 0;

  @override
  List<Object?> get props => [
    totalRows,
    successfulRows,
    failedRows,
    errors,
    rowToProductId,
    duration,
  ];
}

class ImportError extends Equatable {
  final int rowIndex;
  final String field;
  final String message;
  final ImportErrorSeverity severity;
  final Map<String, dynamic>? rowData;

  const ImportError({
    required this.rowIndex,
    required this.field,
    required this.message,
    required this.severity,
    this.rowData,
  });

  @override
  List<Object?> get props => [rowIndex, field, message, severity, rowData];
}

enum ImportErrorSeverity { error, warning }

class ImportProgress extends Equatable {
  final int processedRows;
  final int totalRows;
  final double percentage;
  final String? currentOperation;

  const ImportProgress({
    required this.processedRows,
    required this.totalRows,
    required this.percentage,
    this.currentOperation,
  });

  @override
  List<Object?> get props => [
    processedRows,
    totalRows,
    percentage,
    currentOperation,
  ];
}
