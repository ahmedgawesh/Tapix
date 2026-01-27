import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart' hide Product;
import '../../../../core/database/daos/barcode_template_dao.dart';
import '../../../products/domain/entities/product_entity.dart';
import '../../../settings/data/services/company_profile_service.dart';
import '../../../settings/domain/entities/company_profile.dart';
import '../../domain/models/barcode_design_state.dart';
import '../../services/barcode_printer_service.dart';
import 'barcode_design_event.dart';

class BarcodeDesignBloc extends RealtimeBloc<BarcodeDesignData, BarcodeDesignEvent> {
  final BarcodeTemplateDao _templateDao;
  final BarcodePrinterService _printerService;
  final CompanyProfileService _companyProfileService;

  final StreamController<BarcodeDesignData> _dataController =
      StreamController<BarcodeDesignData>.broadcast();
  StreamSubscription<List<BarcodeTemplate>>? _templatesSubscription;
  StreamSubscription<CompanyProfile>? _companyProfileSubscription;

  List<Product> _selectedProducts = [];
  List<BarcodeTemplate> _templates = [];
  BarcodeTemplate? _selectedTemplate;
  BarcodeDesignSettings _settings = const BarcodeDesignSettings();
  CompanyProfile _companyProfile = const CompanyProfile(name: '');
  PrintOperationStatus _operationStatus = PrintOperationStatus.idle;
  double? _progress;
  String? _errorMessage;
  final List<PrintHistory> _recentPrintHistory = [];

  BarcodeDesignBloc({
    required BarcodeTemplateDao templateDao,
    required BarcodePrinterService printerService,
    required CompanyProfileService companyProfileService,
  })  : _templateDao = templateDao,
        _printerService = printerService,
        _companyProfileService = companyProfileService,
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
        templates: _templates,
        selectedTemplate: _selectedTemplate,
        settings: _settings,
        companyProfile: _companyProfile,
        operationStatus: _operationStatus,
        progress: _progress,
        errorMessage: _errorMessage,
        recentPrintHistory: _recentPrintHistory,
      );

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
        _selectedProducts = List.from(event.initialProducts!);
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
  ) {
    final existingIds = _selectedProducts.map((p) => p.id).toSet();
    final newProducts = event.products.where((p) => !existingIds.contains(p.id)).toList();
    _selectedProducts = [..._selectedProducts, ...newProducts];
    emit(RealtimeSuccess(data: _currentData));
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
    if (_selectedProducts.isEmpty) {
      _errorMessage = 'No products selected for printing';
      emit(RealtimeSuccess(data: _currentData));
      return;
    }

    try {
      _operationStatus = PrintOperationStatus.preparing;
      _errorMessage = null;
      emit(RealtimeSuccess(data: _currentData));

      final barcodeType = _printerService.getBarcodeTypeFromString(_settings.barcodeType);

      for (int i = 0; i < _selectedProducts.length; i++) {
        final product = _selectedProducts[i];
        _progress = (i + 1) / _selectedProducts.length;
        _operationStatus = PrintOperationStatus.printing;
        emit(RealtimeSuccess(data: _currentData));

        final copies = _calculateCopies(product);
        
        final companyName = _settings.includeCompanyName ? _companyProfile.name : null;
        final companyAddress = _companyProfile.address;
        final companyPhone = _companyProfile.phone;

        await _printerService.printLabel(
          product: product,
          barcode: barcodeType,
          widthMm: _settings.labelWidthMm,
          heightMm: _settings.labelHeightMm,
          includeName: _settings.includeName,
          includePrice: _settings.includePrice,
          includeCompanyName: _settings.includeCompanyName,
          companyName: companyName,
          includeCompanyContact: _settings.includeCompanyContact,
          companyAddress: companyAddress,
          companyPhone: companyPhone,
          copies: copies,
        );

        // Log print history
        await _templateDao.logPrint(
          productId: product.id,
          templateId: _selectedTemplate?.id,
          quantityPrinted: copies,
          printerName: event.printerName,
          printType: _settings.printType,
          status: 'success',
        );
      }

      _operationStatus = PrintOperationStatus.success;
      _progress = null;
      emit(RealtimeSuccess(data: _currentData));
    } catch (e) {
      _operationStatus = PrintOperationStatus.error;
      _errorMessage = e.toString();
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

      // For now, share the first product's label
      // TODO: Implement batch PDF generation for multiple products
      final product = _selectedProducts.first;
      
      final companyName = _settings.includeCompanyName ? _companyProfile.name : null;
      final companyAddress = _companyProfile.address;
      final companyPhone = _companyProfile.phone;

      await _printerService.shareLabelPdf(
        product: product,
        barcode: barcodeType,
        widthMm: _settings.labelWidthMm,
        heightMm: _settings.labelHeightMm,
        includeName: _settings.includeName,
        includePrice: _settings.includePrice,
        includeCompanyName: _settings.includeCompanyName,
        companyName: companyName,
        includeCompanyContact: _settings.includeCompanyContact,
        companyAddress: companyAddress,
        companyPhone: companyPhone,
        copies: _settings.copies,
      );

      _operationStatus = PrintOperationStatus.success;
      emit(RealtimeSuccess(data: _currentData));
    } catch (e) {
      _operationStatus = PrintOperationStatus.error;
      _errorMessage = e.toString();
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

  int _calculateCopies(Product product) {
    switch (_settings.printType) {
      case 'all_quantity':
        return product.stockQuantity > 0 ? product.stockQuantity : _settings.copies;
      case 'batch':
      case 'single':
      default:
        return _settings.copies;
    }
  }

  String _getPaperSizeFromDimensions() {
    if (_settings.labelWidthMm <= 58) return '58mm';
    if (_settings.labelWidthMm <= 80) return '80mm';
    return 'A4';
  }
}
