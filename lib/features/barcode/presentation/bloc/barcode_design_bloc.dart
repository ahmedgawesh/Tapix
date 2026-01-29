import 'dart:async';

import 'package:drift/drift.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart' hide Product;
import '../../../../core/database/daos/product_variant_dao.dart';
import '../../../../core/database/daos/barcode_template_dao.dart';
import '../../../products/domain/entities/product_entity.dart';
import '../../../settings/data/services/company_profile_service.dart';
import '../../../settings/domain/entities/company_profile.dart';
import '../../data/models/invoice_print_data.dart';
import '../../domain/models/barcode_design_state.dart';
import '../../services/barcode_printer_service.dart';
import 'barcode_design_event.dart';

class BarcodeDesignBloc extends RealtimeBloc<BarcodeDesignData, BarcodeDesignEvent> {
  final BarcodeTemplateDao _templateDao;
  final BarcodePrinterService _printerService;
  final CompanyProfileService _companyProfileService;
  final ProductVariantDao _productVariantDao;

  final StreamController<BarcodeDesignData> _dataController =
      StreamController<BarcodeDesignData>.broadcast();
  StreamSubscription<List<BarcodeTemplate>>? _templatesSubscription;
  StreamSubscription<CompanyProfile>? _companyProfileSubscription;

  List<Product> _selectedProducts = [];
  Map<int, String> _variantInfoByProductId = {};
  List<BarcodeTemplate> _templates = [];
  BarcodeTemplate? _selectedTemplate;
  BarcodeDesignSettings _settings = const BarcodeDesignSettings();
  CompanyProfile _companyProfile = const CompanyProfile(name: '');
  PrintOperationStatus _operationStatus = PrintOperationStatus.idle;
  double? _progress;
  String? _errorMessage;
  final List<PrintHistory> _recentPrintHistory = [];

  InvoicePrintData? _invoiceData;
  Map<int, int> _currentQuantities = {};

  BarcodeDesignBloc({
    required BarcodeTemplateDao templateDao,
    required BarcodePrinterService printerService,
    required CompanyProfileService companyProfileService,
    required ProductVariantDao productVariantDao,
  })  : _templateDao = templateDao,
        _printerService = printerService,
        _companyProfileService = companyProfileService,
        _productVariantDao = productVariantDao,
        super(const RealtimeLoading()) {
    _initializeSubscriptions();
  }

  void _initializeSubscriptions() {
    _templatesSubscription?.cancel();
    _templatesSubscription = _templateDao.watchTemplates().listen(
      (templates) {
        _templates = templates;
        _pushData();
      },
      onError: (Object e, StackTrace st) {
        add(RealtimeErrorOccurred(e, st));
      },
    );

    _companyProfileSubscription?.cancel();
    _companyProfileSubscription = _companyProfileService.watchProfile().listen(
      (profile) {
        _companyProfile = profile;
        _pushData();
      },
      onError: (Object e, StackTrace st) {
        add(RealtimeErrorOccurred(e, st));
      },
    );
  }

  void _pushData() {
    if (_dataController.isClosed) return;
    _dataController.add(_currentData);
  }

  Future<List<Product>> _normalizeProductsStockQuantities(List<Product> products) async {
    final result = <Product>[];
    for (final p in products) {
      if (!p.hasVariants) {
        result.add(p);
        continue;
      }
      try {
        final summary = await _productVariantDao.getVariantSummaryByProduct(p.id);
        if (summary == null) {
          result.add(p);
          continue;
        }
        result.add(p.copyWith(stockQuantity: summary.totalStock));
      } catch (_) {
        result.add(p);
      }
    }
    return result;
  }

  @override
  Stream<BarcodeDesignData> get dataStream => _dataController.stream;

  @override
  void registerEventHandlers() {
    on<LoadBarcodeDesignData>(_onLoadData);
    on<AddProductsToSelection>(_onAddProducts);
    on<RemoveProductFromSelection>(_onRemoveProduct);
    on<ClearProductSelection>(_onClearSelection);
    on<SelectTemplate>(_onSelectTemplate);
    on<UpdateDesignSettings>(_onUpdateSettings);
    on<UpdateLabelDimensions>(_onUpdateDimensions);
    on<ToggleIncludeName>(_onToggleIncludeName);
    on<ToggleIncludePrice>(_onToggleIncludePrice);
    on<ToggleIncludeBarcode>(_onToggleIncludeBarcode);
    on<ToggleIncludeSku>(_onToggleIncludeSku);
    on<ToggleIncludeCompanyName>(_onToggleIncludeCompanyName);
    on<ToggleIncludeCompanyContact>(_onToggleIncludeCompanyContact);
    on<ToggleIncludeVariantInfo>(_onToggleIncludeVariantInfo);
    on<UpdateBarcodeType>(_onUpdateBarcodeType);
    on<UpdateCopies>(_onUpdateCopies);
    on<UpdatePrintType>(_onUpdatePrintType);
    on<PrintLabels>(_onPrintLabels);
    on<ShareLabels>(_onShareLabels);
    on<SaveAsTemplate>(_onSaveAsTemplate);
    on<AcknowledgePrintResult>(_onAcknowledgePrintResult);
    on<UpdatePrintMode>(_onUpdatePrintMode);
    on<UpdateQuantityMode>(_onUpdateQuantityMode);
    on<UpdateLabelsPerRow>(_onUpdateLabelsPerRow);
    on<UpdateA4LayoutGaps>(_onUpdateA4LayoutGaps);

    on<LoadInvoicePrintData>(_onLoadInvoicePrintData);
    on<UpdateInvoiceLineQuantity>(_onUpdateInvoiceLineQuantity);
    on<ResetToInvoiceQuantities>(_onResetToInvoiceQuantities);
  }

  @override
  Future<void> close() async {
    await _templatesSubscription?.cancel();
    await _companyProfileSubscription?.cancel();
    await _dataController.close();
    return super.close();
  }

  BarcodeDesignData get _currentData => BarcodeDesignData(
        selectedProducts: _selectedProducts,
        variantInfoByProductId: _variantInfoByProductId,
        templates: _templates,
        selectedTemplate: _selectedTemplate,
        settings: _settings,
        companyProfile: _companyProfile,
        operationStatus: _operationStatus,
        progress: _progress,
        errorMessage: _errorMessage,
        recentPrintHistory: _recentPrintHistory,
        invoiceData: _invoiceData,
        currentQuantities: _currentQuantities,
      );

  void _onLoadInvoicePrintData(
    LoadInvoicePrintData event,
    Emitter<RealtimeState<BarcodeDesignData>> emit,
  ) {
    _invoiceData = event.invoiceData;
    _currentQuantities = {
      for (final line in event.invoiceData.lines) line.variantId: line.quantity,
    };
    emit(RealtimeSuccess(data: _currentData));
  }

  void _onUpdateInvoiceLineQuantity(
    UpdateInvoiceLineQuantity event,
    Emitter<RealtimeState<BarcodeDesignData>> emit,
  ) {
    _currentQuantities = {
      ..._currentQuantities,
      event.variantId: event.newQuantity,
    };
    emit(RealtimeSuccess(data: _currentData));
  }

  void _onResetToInvoiceQuantities(
    ResetToInvoiceQuantities event,
    Emitter<RealtimeState<BarcodeDesignData>> emit,
  ) {
    final invoiceData = _invoiceData;
    if (invoiceData == null) {
      emit(RealtimeSuccess(data: _currentData));
      return;
    }
    _currentQuantities = {
      for (final line in invoiceData.lines) line.variantId: line.quantity,
    };
    emit(RealtimeSuccess(data: _currentData));
  }

  Product _productFromInvoiceLine(InvoiceLinePrintData line) {
    return Product(
      id: line.variantId,
      name: line.productName,
      sku: line.sku,
      barcode: line.barcode,
      costCents: Decimal.zero,
      priceCents: Decimal.fromInt(line.unitPriceCents),
      wholesalePriceCents: null,
      stockQuantity: 0,
      minQuantity: 0,
      categoryId: null,
      supplierId: null,
      currencyId: null,
      imagePath: null,
      hasVariants: false,
      isTaxable: false,
      taxRateBps: 0,
      isActive: true,
      trackInventory: false,
    );
  }

  Future<List<({
    Product product,
    int copies,
    String? variantInfo,
  })>> _buildPrintJobs() async {
    if (_settings.quantityMode == QuantityMode.invoiceQuantity &&
        _invoiceData != null &&
        _invoiceData!.lines.isNotEmpty) {
      final jobs = <({Product product, int copies, String? variantInfo})>[];
      for (final line in _invoiceData!.lines) {
        final qty = _currentQuantities[line.variantId] ?? line.quantity;
        if (qty <= 0) continue;
        final variantInfo = [line.sizeName, line.colorName]
            .whereType<String>()
            .where((x) => x.trim().isNotEmpty)
            .join(' / ');
        jobs.add((
          product: _productFromInvoiceLine(line),
          copies: qty,
          variantInfo: variantInfo.isEmpty ? null : variantInfo,
        ));
      }
      return jobs;
    }

    final jobs = <({Product product, int copies, String? variantInfo})>[];
    for (final product in _selectedProducts) {
      if (!product.hasVariants) {
        final copies = _calculateCopies(product);
        if (copies <= 0) continue;
        jobs.add((product: product, copies: copies, variantInfo: null));
        continue;
      }

      final variants = await _productVariantDao.getVariantsByProduct(product.id);
      if (variants.isEmpty) {
        final copies = _calculateCopies(product);
        if (copies <= 0) continue;
        jobs.add((product: product, copies: copies, variantInfo: null));
        continue;
      }

      final infoByVariantId = await _productVariantDao
          .getVariantInfoByVariantIds(variants.map((v) => v.id).toList());

      for (final v in variants) {
        final variantProduct = product.copyWith(
          sku: v.sku,
          barcode: v.barcode,
        );

        int copies;
        switch (_settings.quantityMode) {
          case QuantityMode.single:
            copies = 1;
          case QuantityMode.custom:
            copies = _settings.copies;
          case QuantityMode.stockQuantity:
            copies = v.stockQuantity > 0 ? v.stockQuantity : 1;
          case QuantityMode.invoiceQuantity:
            copies = 1;
        }

        if (copies <= 0) continue;
        jobs.add((
          product: variantProduct,
          copies: copies,
          variantInfo: infoByVariantId[v.id],
        ));
      }
    }
    return jobs;
  }

  Future<void> _onLoadData(
    LoadBarcodeDesignData event,
    Emitter<RealtimeState<BarcodeDesignData>> emit,
  ) async {
    emit(const RealtimeLoading());

    try {
      // Load templates
      _templates = await _templateDao.getTemplates();

      // Get default template
      _selectedTemplate = await _templateDao.getDefaultTemplate();
      if (_selectedTemplate != null) {
        _settings = BarcodeDesignSettings.fromTemplate(_selectedTemplate!);
      }

      // Set initial products if provided
      if (event.initialProducts != null && event.initialProducts!.isNotEmpty) {
        _selectedProducts = await _normalizeProductsStockQuantities(
          List<Product>.from(event.initialProducts!),
        );
      }

      if (event.variantInfoByProductId != null) {
        _variantInfoByProductId = Map<int, String>.from(event.variantInfoByProductId!);
      }

      if (_variantInfoByProductId.isEmpty && _selectedProducts.isNotEmpty) {
        final ids = _selectedProducts.map((p) => p.id).toList();
        _variantInfoByProductId = await _productVariantDao.getVariantInfoByProductIds(ids);
      }

      // Subscribe to template changes
      _companyProfile = await _companyProfileService.getProfile();

      _pushData();

      emit(RealtimeSuccess(data: _currentData));
    } catch (e, st) {
      emit(RealtimeError(error: e, stackTrace: st));
    }
  }

  void _onAddProducts(
    AddProductsToSelection event,
    Emitter<RealtimeState<BarcodeDesignData>> emit,
  ) async {
    final existingIds = _selectedProducts.map((p) => p.id).toSet();
    final newProducts = event.products.where((p) => !existingIds.contains(p.id)).toList();
    final normalizedNewProducts = await _normalizeProductsStockQuantities(newProducts);
    _selectedProducts = [..._selectedProducts, ...normalizedNewProducts];
    emit(RealtimeSuccess(data: _currentData));

    if (newProducts.isEmpty) return;
    try {
      final ids = newProducts.map((p) => p.id).toList();
      final info = await _productVariantDao.getVariantInfoByProductIds(ids);
      if (info.isEmpty) return;
      _variantInfoByProductId = {
        ..._variantInfoByProductId,
        ...info,
      };
      emit(RealtimeSuccess(data: _currentData));
    } catch (_) {
      // ignore
    }
  }

  void _onRemoveProduct(
    RemoveProductFromSelection event,
    Emitter<RealtimeState<BarcodeDesignData>> emit,
  ) {
    _selectedProducts = _selectedProducts.where((p) => p.id != event.productId).toList();
    emit(RealtimeSuccess(data: _currentData));
  }

  void _onClearSelection(
    ClearProductSelection event,
    Emitter<RealtimeState<BarcodeDesignData>> emit,
  ) {
    _selectedProducts = [];
    emit(RealtimeSuccess(data: _currentData));
  }

  void _onSelectTemplate(
    SelectTemplate event,
    Emitter<RealtimeState<BarcodeDesignData>> emit,
  ) {
    _selectedTemplate = event.template;
    _settings = BarcodeDesignSettings.fromTemplate(event.template).copyWith(
      copies: _settings.copies,
      printType: _settings.printType,
    );
    emit(RealtimeSuccess(data: _currentData));
  }

  void _onUpdateSettings(
    UpdateDesignSettings event,
    Emitter<RealtimeState<BarcodeDesignData>> emit,
  ) {
    _settings = event.settings;
    emit(RealtimeSuccess(data: _currentData));
  }

  void _onUpdateDimensions(
    UpdateLabelDimensions event,
    Emitter<RealtimeState<BarcodeDesignData>> emit,
  ) {
    _settings = _settings.copyWith(
      labelWidthMm: event.widthMm,
      labelHeightMm: event.heightMm,
    );
    emit(RealtimeSuccess(data: _currentData));
  }

  void _onToggleIncludeName(
    ToggleIncludeName event,
    Emitter<RealtimeState<BarcodeDesignData>> emit,
  ) {
    _settings = _settings.copyWith(includeName: event.value);
    emit(RealtimeSuccess(data: _currentData));
  }

  void _onToggleIncludePrice(
    ToggleIncludePrice event,
    Emitter<RealtimeState<BarcodeDesignData>> emit,
  ) {
    _settings = _settings.copyWith(includePrice: event.value);
    emit(RealtimeSuccess(data: _currentData));
  }

  void _onToggleIncludeBarcode(
    ToggleIncludeBarcode event,
    Emitter<RealtimeState<BarcodeDesignData>> emit,
  ) {
    _settings = _settings.copyWith(includeBarcode: event.value);
    emit(RealtimeSuccess(data: _currentData));
  }

  void _onToggleIncludeSku(
    ToggleIncludeSku event,
    Emitter<RealtimeState<BarcodeDesignData>> emit,
  ) {
    _settings = _settings.copyWith(includeSku: event.value);
    emit(RealtimeSuccess(data: _currentData));
  }

  void _onToggleIncludeCompanyName(
    ToggleIncludeCompanyName event,
    Emitter<RealtimeState<BarcodeDesignData>> emit,
  ) {
    _settings = _settings.copyWith(includeCompanyName: event.value);
    emit(RealtimeSuccess(data: _currentData));
  }

  void _onToggleIncludeCompanyContact(
    ToggleIncludeCompanyContact event,
    Emitter<RealtimeState<BarcodeDesignData>> emit,
  ) {
    _settings = _settings.copyWith(includeCompanyContact: event.value);
    emit(RealtimeSuccess(data: _currentData));
  }

  void _onToggleIncludeVariantInfo(
    ToggleIncludeVariantInfo event,
    Emitter<RealtimeState<BarcodeDesignData>> emit,
  ) {
    _settings = _settings.copyWith(includeVariantInfo: event.value);
    emit(RealtimeSuccess(data: _currentData));
  }

  void _onUpdateBarcodeType(
    UpdateBarcodeType event,
    Emitter<RealtimeState<BarcodeDesignData>> emit,
  ) {
    _settings = _settings.copyWith(barcodeType: event.barcodeType);
    emit(RealtimeSuccess(data: _currentData));
  }

  void _onUpdateCopies(
    UpdateCopies event,
    Emitter<RealtimeState<BarcodeDesignData>> emit,
  ) {
    _settings = _settings.copyWith(copies: event.copies.clamp(1, 999));
    emit(RealtimeSuccess(data: _currentData));
  }

  void _onUpdatePrintType(
    UpdatePrintType event,
    Emitter<RealtimeState<BarcodeDesignData>> emit,
  ) {
    _settings = _settings.copyWith(printType: event.printType);
    emit(RealtimeSuccess(data: _currentData));
  }

  Future<void> _onPrintLabels(
    PrintLabels event,
    Emitter<RealtimeState<BarcodeDesignData>> emit,
  ) async {
    if (_selectedProducts.isEmpty &&
        !(_settings.quantityMode == QuantityMode.invoiceQuantity &&
            _invoiceData != null &&
            _invoiceData!.lines.isNotEmpty)) {
      _errorMessage = 'No products selected for printing';
      emit(RealtimeSuccess(data: _currentData));
      return;
    }

    try {
      _operationStatus = PrintOperationStatus.preparing;
      _errorMessage = null;
      emit(RealtimeSuccess(data: _currentData));

      final barcodeType = _printerService.getBarcodeTypeFromString(_settings.barcodeType);

      final jobs = await _buildPrintJobs();
      if (jobs.isEmpty) {
        _operationStatus = PrintOperationStatus.error;
        _errorMessage = 'No labels to print';
        emit(RealtimeSuccess(data: _currentData));
        return;
      }

      for (int i = 0; i < jobs.length; i++) {
        final job = jobs[i];
        _progress = (i + 1) / jobs.length;
        _operationStatus = PrintOperationStatus.printing;
        emit(RealtimeSuccess(data: _currentData));

        final companyName = _settings.includeCompanyName ? _companyProfile.name : null;
        final companyAddress = _companyProfile.address;
        final companyPhone = _companyProfile.phone;

        if (_settings.isA4Mode) {
          await _printerService.printA4Grid(
            product: job.product,
            barcode: barcodeType,
            widthMm: _settings.labelWidthMm,
            heightMm: _settings.labelHeightMm,
            includeName: _settings.includeName,
            includePrice: _settings.includePrice,
            includeBarcode: _settings.includeBarcode,
            includeCompanyName: _settings.includeCompanyName,
            companyName: companyName,
            includeCompanyContact: _settings.includeCompanyContact,
            companyAddress: companyAddress,
            companyPhone: companyPhone,
            copies: job.copies,
            labelsPerRow: _settings.labelsPerRow,
            horizontalGapMm: _settings.horizontalGapMm,
            verticalGapMm: _settings.verticalGapMm,
            pageMarginMm: _settings.pageMarginMm,
            variantInfo: job.variantInfo,
            includeVariantInfo: _settings.includeVariantInfo,
          );
        } else {
          await _printerService.printThermalLabel(
            product: job.product,
            barcode: barcodeType,
            widthMm: _settings.labelWidthMm,
            heightMm: _settings.labelHeightMm,
            includeName: _settings.includeName,
            includePrice: _settings.includePrice,
            includeBarcode: _settings.includeBarcode,
            includeCompanyName: _settings.includeCompanyName,
            companyName: companyName,
            includeCompanyContact: _settings.includeCompanyContact,
            companyAddress: companyAddress,
            companyPhone: companyPhone,
            copies: job.copies,
            variantInfo: job.variantInfo,
            includeVariantInfo: _settings.includeVariantInfo,
          );
        }

        await _templateDao.logPrint(
          productId: job.product.id,
          templateId: _selectedTemplate?.id,
          quantityPrinted: job.copies,
          printerName: event.printerName,
          printType: _settings.printType,
          status: 'success',
        );
      }

      _operationStatus = PrintOperationStatus.success;
      _progress = null;
      emit(RealtimeSuccess(data: _currentData));
    } catch (e, st) {
      _operationStatus = PrintOperationStatus.error;
      _errorMessage = e.toString();
      // Ensure error is visible in console with stacktrace
      // ignore: avoid_print
      print('Barcode print failed: $e\n$st');
      _progress = null;
      emit(RealtimeSuccess(data: _currentData));
    }
  }

  Future<void> _onShareLabels(
    ShareLabels event,
    Emitter<RealtimeState<BarcodeDesignData>> emit,
  ) async {
    if (_selectedProducts.isEmpty) {
      _errorMessage = 'No products selected for sharing';
      emit(RealtimeSuccess(data: _currentData));
      return;
    }

    try {
      _operationStatus = PrintOperationStatus.preparing;
      _errorMessage = null;
      emit(RealtimeSuccess(data: _currentData));

      final barcodeType = _printerService.getBarcodeTypeFromString(_settings.barcodeType);

      final product = _selectedProducts.first;
      final copies = _calculateCopies(product);
      
      final companyName = _settings.includeCompanyName ? _companyProfile.name : null;
      final companyAddress = _companyProfile.address;
      final companyPhone = _companyProfile.phone;
      final variantInfo = _variantInfoByProductId[product.id];

      await _printerService.shareLabelPdf(
        product: product,
        barcode: barcodeType,
        widthMm: _settings.labelWidthMm,
        heightMm: _settings.labelHeightMm,
        includeName: _settings.includeName,
        includePrice: _settings.includePrice,
        includeBarcode: _settings.includeBarcode,
        includeCompanyName: _settings.includeCompanyName,
        companyName: companyName,
        includeCompanyContact: _settings.includeCompanyContact,
        companyAddress: companyAddress,
        companyPhone: companyPhone,
        copies: copies,
        isA4Mode: _settings.isA4Mode,
        labelsPerRow: _settings.labelsPerRow,
        horizontalGapMm: _settings.horizontalGapMm,
        verticalGapMm: _settings.verticalGapMm,
        pageMarginMm: _settings.pageMarginMm,
        variantInfo: variantInfo,
        includeVariantInfo: _settings.includeVariantInfo,
      );

      _operationStatus = PrintOperationStatus.success;
      emit(RealtimeSuccess(data: _currentData));
    } catch (e, st) {
      _operationStatus = PrintOperationStatus.error;
      _errorMessage = e.toString();
      // ignore: avoid_print
      print('Barcode share failed: $e\n$st');
      emit(RealtimeSuccess(data: _currentData));
    }
  }

  Future<void> _onSaveAsTemplate(
    SaveAsTemplate event,
    Emitter<RealtimeState<BarcodeDesignData>> emit,
  ) async {
    try {
      await _templateDao.createTemplate(
        BarcodeTemplatesCompanion.insert(
          name: event.name,
          description: Value(event.description),
          layoutConfig: '{}',
          paperSize: Value(_getPaperSizeFromDimensions()),
          widthMm: Value(_settings.labelWidthMm),
          heightMm: Value(_settings.labelHeightMm),
          includeName: Value(_settings.includeName),
          includePrice: Value(_settings.includePrice),
          includeSku: Value(_settings.includeSku),
          includeCompanyName: Value(_settings.includeCompanyName),
          includeVariantInfo: Value(_settings.includeVariantInfo),
          barcodeType: Value(_settings.barcodeType),
        ),
      );

      // Refresh templates
      _templates = await _templateDao.getTemplates();
      emit(RealtimeSuccess(data: _currentData));
    } catch (e) {
      _errorMessage = 'Failed to save template: $e';
      emit(RealtimeSuccess(data: _currentData));
    }
  }

  void _onAcknowledgePrintResult(
    AcknowledgePrintResult event,
    Emitter<RealtimeState<BarcodeDesignData>> emit,
  ) {
    _operationStatus = PrintOperationStatus.idle;
    _errorMessage = null;
    _progress = null;
    emit(RealtimeSuccess(data: _currentData));
  }

  void _onUpdatePrintMode(
    UpdatePrintMode event,
    Emitter<RealtimeState<BarcodeDesignData>> emit,
  ) {
    _settings = _settings.copyWith(printMode: event.printMode);
    emit(RealtimeSuccess(data: _currentData));
  }

  void _onUpdateQuantityMode(
    UpdateQuantityMode event,
    Emitter<RealtimeState<BarcodeDesignData>> emit,
  ) {
    _settings = _settings.copyWith(quantityMode: event.quantityMode);
    emit(RealtimeSuccess(data: _currentData));
  }

  void _onUpdateLabelsPerRow(
    UpdateLabelsPerRow event,
    Emitter<RealtimeState<BarcodeDesignData>> emit,
  ) {
    _settings = _settings.copyWith(labelsPerRow: event.labelsPerRow.clamp(1, 10));
    emit(RealtimeSuccess(data: _currentData));
  }

  void _onUpdateA4LayoutGaps(
    UpdateA4LayoutGaps event,
    Emitter<RealtimeState<BarcodeDesignData>> emit,
  ) {
    _settings = _settings.copyWith(
      horizontalGapMm: event.horizontalGapMm,
      verticalGapMm: event.verticalGapMm,
      pageMarginMm: event.pageMarginMm,
    );
    emit(RealtimeSuccess(data: _currentData));
  }

  int _calculateCopies(Product product) {
    switch (_settings.quantityMode) {
      case QuantityMode.single:
        return 1;
      case QuantityMode.stockQuantity:
        return product.stockQuantity > 0 ? product.stockQuantity : 1;
      case QuantityMode.invoiceQuantity:
        // Get quantity from invoice data if available
        if (_currentData.invoiceData != null && _currentData.invoiceData!.lines.isNotEmpty) {
          // Use the first line's quantity as fallback
          final firstLine = _currentData.invoiceData!.lines.first;
          return _currentData.currentQuantities[firstLine.variantId] ?? firstLine.quantity;
        }
        return 1;
      case QuantityMode.custom:
        return _settings.copies;
    }
  }

  String _getPaperSizeFromDimensions() {
    if (_settings.labelWidthMm <= 58) return '58mm';
    if (_settings.labelWidthMm <= 80) return '80mm';
    return 'A4';
  }
}
