import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/services/logging_service.dart';
import '../../domain/entities/product_entity.dart';
import '../../services/export_service.dart';
import 'export_event.dart';
import 'export_state.dart';

class ExportBloc extends RealtimeBloc<ExportUiData, ExportEvent> {
  final ExportService _exportService;

  StreamSubscription<List<Product>>? _productsSubscription;

  List<Product> _products = const <Product>[];
  Set<int> _selectedProductIds = <int>{};
  ExportFormat _format = ExportFormat.csv;
  int? _categoryId;
  int? _supplierId;
  bool _activeOnly = true;
  ExportOperationStatus _operationStatus = ExportOperationStatus.idle;
  double? _progress;
  ExportPayload? _lastExport;

  ExportBloc(this._exportService) : super(const RealtimeLoading()) {
    // No work here; wait for LoadExportPreview to set filters and subscribe.
  }

  @override
  Stream<ExportUiData> get dataStream => const Stream.empty();

  @override
  void registerEventHandlers() {
    on<LoadExportPreview>(_onLoadExportPreview);
    on<ExportToCSV>(_onExportToCSV);
    on<ExportToExcel>(_onExportToExcel);
    on<UpdateExportFormat>(_onUpdateExportFormat);
    on<UpdateCategoryFilter>(_onUpdateCategoryFilter);
    on<UpdateSupplierFilter>(_onUpdateSupplierFilter);
    on<UpdateActiveFilter>(_onUpdateActiveFilter);
    on<ExportAcknowledged>(_onExportAcknowledged);
    on<ToggleProductSelection>(_onToggleProductSelection);
    on<ToggleSelectAllProducts>(_onToggleSelectAllProducts);
  }

  @override
  Future<void> close() async {
    await _productsSubscription?.cancel();
    return super.close();
  }

  void _subscribeProducts() {
    _productsSubscription?.cancel();
    _productsSubscription = _exportService
        .watchProducts(
          categoryId: _categoryId,
          supplierId: _supplierId,
          activeOnly: _activeOnly,
        )
        .listen(
          (products) {
            _products = products;

            final visibleIds = _products.map((p) => p.id).toSet();
            _selectedProductIds = _selectedProductIds.intersection(visibleIds);

            add(
              RealtimeDataUpdated<ExportUiData>(
                ExportUiData(
                  products: _products,
                  selectedProductIds: _selectedProductIds,
                  format: _format,
                  categoryId: _categoryId,
                  supplierId: _supplierId,
                  activeOnly: _activeOnly,
                  operationStatus: _operationStatus,
                  progress: _progress,
                  lastExport: _lastExport,
                ),
              ),
            );
          },
          onError: (Object e, StackTrace st) {
            add(RealtimeErrorOccurred(e, st));
          },
        );
  }

  void _onLoadExportPreview(
    LoadExportPreview event,
    Emitter<RealtimeState<ExportUiData>> emit,
  ) {
    _categoryId = event.categoryId ?? _categoryId;
    _supplierId = event.supplierId ?? _supplierId;
    _activeOnly = event.activeOnly ?? _activeOnly;

    emit(RealtimeLoading<ExportUiData>(previousData: currentData));
    _subscribeProducts();
  }

  Future<void> _onExportToCSV(
    ExportToCSV event,
    Emitter<RealtimeState<ExportUiData>> emit,
  ) async {
    await _runExport(
      emit: emit,
      format: ExportFormat.csv,
      action: event.action,
      selectedProductIds: event.selectedProductIds ?? _selectedProductIds,
      categoryId: event.categoryId ?? _categoryId,
      supplierId: event.supplierId ?? _supplierId,
      activeOnly: event.activeOnly ?? _activeOnly,
    );
  }

  Future<void> _onExportToExcel(
    ExportToExcel event,
    Emitter<RealtimeState<ExportUiData>> emit,
  ) async {
    await _runExport(
      emit: emit,
      format: ExportFormat.excel,
      action: event.action,
      selectedProductIds: event.selectedProductIds ?? _selectedProductIds,
      categoryId: event.categoryId ?? _categoryId,
      supplierId: event.supplierId ?? _supplierId,
      activeOnly: event.activeOnly ?? _activeOnly,
    );
  }

  Future<void> _runExport({
    required Emitter<RealtimeState<ExportUiData>> emit,
    required ExportFormat format,
    required ExportAction action,
    required Set<int> selectedProductIds,
    required int? categoryId,
    required int? supplierId,
    required bool activeOnly,
  }) async {
    LoggingService.methodEntry(
      '_runExport',
      params: {
        'format': format.toString(),
        'categoryId': categoryId,
        'supplierId': supplierId,
        'activeOnly': activeOnly,
      },
      tag: 'ExportBloc',
    );

    try {
      _operationStatus = ExportOperationStatus.inProgress;
      _progress = null;
      _lastExport = null;
      emit(
        RealtimeSuccess<ExportUiData>(
          data:
              currentData?.copyWith(
                operationStatus: _operationStatus,
                progress: _progress,
                clearLastExport: true,
              ) ??
              ExportUiData.empty(),
        ),
      );

      Uint8List bytes;
      String filename;

      if (format == ExportFormat.csv) {
        LoggingService.serviceOperation(
          'ExportService',
          'exportToCSV',
          tag: 'ExportBloc',
        );
        final csv = await _exportService.exportToCSV(
          categoryId: categoryId,
          supplierId: supplierId,
          activeOnly: activeOnly,
          selectedProductIds: selectedProductIds,
        );
        bytes = Uint8List.fromList(utf8.encode(csv));
        filename = 'products_export.csv';
      } else {
        LoggingService.serviceOperation(
          'ExportService',
          'exportToExcel',
          tag: 'ExportBloc',
        );
        bytes = await _exportService.exportToExcel(
          categoryId: categoryId,
          supplierId: supplierId,
          activeOnly: activeOnly,
          selectedProductIds: selectedProductIds,
        );
        filename = 'products_export.xlsx';
      }

      _operationStatus = ExportOperationStatus.success;
      _lastExport = ExportPayload(
        format: format,
        action: action,
        bytes: bytes,
        filename: filename,
      );

      LoggingService.info(
        'Export completed successfully',
        params: {
          'format': format.toString(),
          'filename': filename,
          'size': '${bytes.length} bytes',
        },
        tag: 'ExportBloc',
      );

      emit(
        RealtimeSuccess<ExportUiData>(
          data: (currentData ?? ExportUiData.empty()).copyWith(
            operationStatus: _operationStatus,
            progress: null,
            lastExport: _lastExport,
          ),
        ),
      );
    } catch (e, st) {
      _operationStatus = ExportOperationStatus.idle;
      _progress = null;
      _lastExport = null;

      LoggingService.error(
        'Export failed',
        error: e,
        stackTrace: st,
        params: {
          'format': format.toString(),
          'categoryId': categoryId,
          'supplierId': supplierId,
          'activeOnly': activeOnly,
        },
        tag: 'ExportBloc',
      );

      add(RealtimeErrorOccurred(e, st));
    } finally {
      LoggingService.methodExit('_runExport', tag: 'ExportBloc');
    }
  }

  void _onUpdateExportFormat(
    UpdateExportFormat event,
    Emitter<RealtimeState<ExportUiData>> emit,
  ) {
    _format = event.format;
    emit(
      RealtimeSuccess<ExportUiData>(
        data: (currentData ?? ExportUiData.empty()).copyWith(format: _format),
      ),
    );
  }

  void _onUpdateCategoryFilter(
    UpdateCategoryFilter event,
    Emitter<RealtimeState<ExportUiData>> emit,
  ) {
    _categoryId = event.categoryId;
    emit(
      RealtimeSuccess<ExportUiData>(
        data: (currentData ?? ExportUiData.empty()).copyWith(
          categoryId: _categoryId,
        ),
      ),
    );
    _subscribeProducts();
  }

  void _onUpdateSupplierFilter(
    UpdateSupplierFilter event,
    Emitter<RealtimeState<ExportUiData>> emit,
  ) {
    _supplierId = event.supplierId;
    emit(
      RealtimeSuccess<ExportUiData>(
        data: (currentData ?? ExportUiData.empty()).copyWith(
          supplierId: _supplierId,
        ),
      ),
    );
    _subscribeProducts();
  }

  void _onUpdateActiveFilter(
    UpdateActiveFilter event,
    Emitter<RealtimeState<ExportUiData>> emit,
  ) {
    _activeOnly = event.activeOnly ?? true;
    emit(
      RealtimeSuccess<ExportUiData>(
        data: (currentData ?? ExportUiData.empty()).copyWith(
          activeOnly: _activeOnly,
        ),
      ),
    );
    _subscribeProducts();
  }

  void _onExportAcknowledged(
    ExportAcknowledged event,
    Emitter<RealtimeState<ExportUiData>> emit,
  ) {
    _operationStatus = ExportOperationStatus.idle;
    _progress = null;
    _lastExport = null;
    emit(
      RealtimeSuccess<ExportUiData>(
        data: (currentData ?? ExportUiData.empty()).copyWith(
          operationStatus: _operationStatus,
          progress: _progress,
          clearLastExport: true,
        ),
      ),
    );
  }

  void _onToggleProductSelection(
    ToggleProductSelection event,
    Emitter<RealtimeState<ExportUiData>> emit,
  ) {
    if (_selectedProductIds.contains(event.productId)) {
      _selectedProductIds = {..._selectedProductIds}..remove(event.productId);
    } else {
      _selectedProductIds = {..._selectedProductIds, event.productId};
    }

    emit(
      RealtimeSuccess<ExportUiData>(
        data: (currentData ?? ExportUiData.empty()).copyWith(
          selectedProductIds: _selectedProductIds,
        ),
      ),
    );
  }

  void _onToggleSelectAllProducts(
    ToggleSelectAllProducts event,
    Emitter<RealtimeState<ExportUiData>> emit,
  ) {
    final allIds = _products.map((p) => p.id).toSet();
    if (_selectedProductIds.length == allIds.length && allIds.isNotEmpty) {
      _selectedProductIds = <int>{};
    } else {
      _selectedProductIds = allIds;
    }

    emit(
      RealtimeSuccess<ExportUiData>(
        data: (currentData ?? ExportUiData.empty()).copyWith(
          selectedProductIds: _selectedProductIds,
        ),
      ),
    );
  }
}
