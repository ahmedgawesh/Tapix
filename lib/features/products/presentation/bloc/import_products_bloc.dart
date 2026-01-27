import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/services/currency_service.dart';
import '../../domain/entities/import_file_data.dart';
import '../../domain/usecases/import_products.dart';
import '../../domain/usecases/parse_import_file.dart';
import '../../domain/usecases/validate_import_data.dart';
import 'import_products_event.dart';
import 'import_products_state.dart';

class ImportProductsBloc extends Bloc<ImportProductsEvent, ImportProductsState> {
  final ParseImportFile _parseImportFile;
  final ValidateImportData _validateImportData;
  final ImportProducts _importProducts;
  final CurrencyService _currencyService;

  ImportProductsBloc({
    required ParseImportFile parseImportFile,
    required ValidateImportData validateImportData,
    required ImportProducts importProducts,
    required CurrencyService currencyService,
  })  : _parseImportFile = parseImportFile,
        _validateImportData = validateImportData,
        _importProducts = importProducts,
        _currencyService = currencyService,
        super(const ImportProductsInitial()) {
    on<ImportFileSelected>(_onFileSelected);
    on<ImportColumnMapped>(_onColumnMapped);
    on<ImportValidationRequested>(_onValidationRequested);
    on<ImportExecutionStarted>(_onExecutionStarted);
    on<ImportCancelled>(_onCancelled);
    on<ImportReset>(_onReset);
  }

  Future<void> _onFileSelected(
    ImportFileSelected event,
    Emitter<ImportProductsState> emit,
  ) async {
    emit(const ImportFileLoading());

    try {
      final fileData = await _parseImportFile(
        bytes: event.fileBytes,
        fileName: event.fileName,
      );

      final availableFields = _getAvailableFields();

      emit(ImportFileParsed(
        fileData: fileData,
        availableFields: availableFields,
      ));
    } catch (e) {
      emit(ImportFailed(
        errorMessage: 'import_products.error_parse_file'.tr(args: [e.toString()]),
      ));
    }
  }

  Future<void> _onColumnMapped(
    ImportColumnMapped event,
    Emitter<ImportProductsState> emit,
  ) async {
    if (state is ImportFileParsed) {
      final currentState = state as ImportFileParsed;
      emit(ImportColumnMappingReady(
        fileData: currentState.fileData,
        columnMapping: event.columnMapping,
        availableFields: currentState.availableFields,
      ));
    }
  }

  Future<void> _onValidationRequested(
    ImportValidationRequested event,
    Emitter<ImportProductsState> emit,
  ) async {
    if (state is ImportColumnMappingReady) {
      final currentState = state as ImportColumnMappingReady;

      emit(ImportValidating(
        fileData: currentState.fileData,
        columnMapping: currentState.columnMapping,
      ));

      try {
        final errors = await _validateImportData(
          fileData: currentState.fileData,
          columnMapping: currentState.columnMapping,
        );

        emit(ImportValidated(
          fileData: currentState.fileData,
          columnMapping: currentState.columnMapping,
          validationErrors: errors,
        ));
      } catch (e) {
        emit(ImportFailed(
          errorMessage: 'import_products.error_validation'.tr(args: [e.toString()]),
          fileData: currentState.fileData,
        ));
      }
    }
  }

  Future<void> _onExecutionStarted(
    ImportExecutionStarted event,
    Emitter<ImportProductsState> emit,
  ) async {
    if (state is ImportValidated) {
      final currentState = state as ImportValidated;

      if (currentState.hasErrors) {
        emit(ImportFailed(
          errorMessage: 'import_products.error_validation_errors'.tr(),
          fileData: currentState.fileData,
        ));
        return;
      }

      emit(ImportInProgress(
        fileData: currentState.fileData,
        columnMapping: currentState.columnMapping,
        processedRows: 0,
        totalRows: currentState.fileData.totalRows,
      ));

      try {
        final result = await _importProducts(
          fileData: currentState.fileData,
          columnMapping: currentState.columnMapping,
        );

        emit(ImportCompleted(result));
      } catch (e) {
        emit(ImportFailed(
          errorMessage: 'import_products.error_import'.tr(args: [e.toString()]),
          fileData: currentState.fileData,
        ));
      }
    }
  }

  void _onCancelled(
    ImportCancelled event,
    Emitter<ImportProductsState> emit,
  ) {
    emit(const ImportProductsInitial());
  }

  void _onReset(
    ImportReset event,
    Emitter<ImportProductsState> emit,
  ) {
    emit(const ImportProductsInitial());
  }

  // Expose currency service for potential use in widgets
  CurrencyService get currencyService => _currencyService;

  List<ImportFieldDefinition> _getAvailableFields() {
    return [
      ImportFieldDefinition(
        fieldName: 'name',
        displayName: 'import_products.field_name'.tr(),
        isRequired: true,
        fieldType: ImportFieldType.text,
        hint: 'import_products.field_required_hint'.tr(),
      ),
      ImportFieldDefinition(
        fieldName: 'color',
        displayName: 'import_products.field_color'.tr(),
        isRequired: false,
        fieldType: ImportFieldType.text,
      ),
      ImportFieldDefinition(
        fieldName: 'size',
        displayName: 'import_products.field_size'.tr(),
        isRequired: false,
        fieldType: ImportFieldType.text,
      ),
      ImportFieldDefinition(
        fieldName: 'category',
        displayName: 'import_products.field_category'.tr(),
        isRequired: false,
        fieldType: ImportFieldType.text,
      ),
      ImportFieldDefinition(
        fieldName: 'sku',
        displayName: 'import_products.field_sku'.tr(),
        isRequired: false,
        fieldType: ImportFieldType.text,
        hint: 'import_products.field_sku_hint'.tr(),
      ),
      ImportFieldDefinition(
        fieldName: 'barcode',
        displayName: 'import_products.field_barcode'.tr(),
        isRequired: false,
        fieldType: ImportFieldType.text,
      ),
      ImportFieldDefinition(
        fieldName: 'cost',
        displayName: 'import_products.field_cost'.tr(),
        isRequired: false,
        fieldType: ImportFieldType.money,
        hint: 'import_products.field_cost_hint'.tr(),
      ),
      ImportFieldDefinition(
        fieldName: 'price',
        displayName: 'import_products.field_price'.tr(),
        isRequired: true,
        fieldType: ImportFieldType.money,
        hint: 'import_products.field_required_hint'.tr(),
      ),
      ImportFieldDefinition(
        fieldName: 'wholesale_price',
        displayName: 'import_products.field_wholesale_price'.tr(),
        isRequired: false,
        fieldType: ImportFieldType.money,
      ),
      ImportFieldDefinition(
        fieldName: 'stock_quantity',
        displayName: 'import_products.field_stock_quantity'.tr(),
        isRequired: false,
        fieldType: ImportFieldType.integer,
        hint: 'Current stock level',
      ),
      ImportFieldDefinition(
        fieldName: 'min_quantity',
        displayName: 'import_products.field_min_quantity'.tr(),
        isRequired: false,
        fieldType: ImportFieldType.integer,
        hint: 'Reorder level',
      ),
      ImportFieldDefinition(
        fieldName: 'is_taxable',
        displayName: 'import_products.field_is_taxable'.tr(),
        isRequired: false,
        fieldType: ImportFieldType.boolean,
        hint: 'true/false or 1/0',
      ),
      ImportFieldDefinition(
        fieldName: 'is_active',
        displayName: 'import_products.field_is_active'.tr(),
        isRequired: false,
        fieldType: ImportFieldType.boolean,
        hint: 'true/false or 1/0',
      ),
    ];
  }
}
