import 'package:equatable/equatable.dart';
import '../../domain/entities/import_file_data.dart';

abstract class ImportProductsEvent extends Equatable {
  const ImportProductsEvent();

  @override
  List<Object?> get props => [];
}

class ImportFileSelected extends ImportProductsEvent {
  final List<int> fileBytes;
  final String fileName;

  const ImportFileSelected({required this.fileBytes, required this.fileName});

  @override
  List<Object?> get props => [fileBytes, fileName];
}

class ImportColumnMapped extends ImportProductsEvent {
  final ColumnMapping columnMapping;

  const ImportColumnMapped(this.columnMapping);

  @override
  List<Object?> get props => [columnMapping];
}

class ImportValidationRequested extends ImportProductsEvent {
  const ImportValidationRequested();
}

class ImportExecutionStarted extends ImportProductsEvent {
  const ImportExecutionStarted();
}

class ImportCancelled extends ImportProductsEvent {
  const ImportCancelled();
}

class ImportReset extends ImportProductsEvent {
  const ImportReset();
}
