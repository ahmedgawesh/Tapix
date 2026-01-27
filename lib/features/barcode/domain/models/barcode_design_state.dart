import 'package:equatable/equatable.dart';

import '../../../products/domain/entities/product_entity.dart';
import '../../../../core/database/app_database.dart' hide Product;
import '../../../settings/domain/entities/company_profile.dart';

/// Represents the UI state for barcode design screen
class BarcodeDesignData extends Equatable {
  final List<Product> selectedProducts;
  final List<BarcodeTemplate> templates;
  final BarcodeTemplate? selectedTemplate;
  final BarcodeDesignSettings settings;
  final CompanyProfile companyProfile;
  final PrintOperationStatus operationStatus;
  final double? progress;
  final String? errorMessage;
  final List<PrintHistory> recentPrintHistory;

  const BarcodeDesignData({
    this.selectedProducts = const [],
    this.templates = const [],
    this.selectedTemplate,
    this.settings = const BarcodeDesignSettings(),
    this.companyProfile = const CompanyProfile(name: ''),
    this.operationStatus = PrintOperationStatus.idle,
    this.progress,
    this.errorMessage,
    this.recentPrintHistory = const [],
  });

  BarcodeDesignData copyWith({
    List<Product>? selectedProducts,
    List<BarcodeTemplate>? templates,
    BarcodeTemplate? selectedTemplate,
    BarcodeDesignSettings? settings,
    CompanyProfile? companyProfile,
    PrintOperationStatus? operationStatus,
    double? progress,
    String? errorMessage,
    List<PrintHistory>? recentPrintHistory,
    bool clearError = false,
    bool clearTemplate = false,
  }) {
    return BarcodeDesignData(
      selectedProducts: selectedProducts ?? this.selectedProducts,
      templates: templates ?? this.templates,
      selectedTemplate: clearTemplate ? null : (selectedTemplate ?? this.selectedTemplate),
      settings: settings ?? this.settings,
      companyProfile: companyProfile ?? this.companyProfile,
      operationStatus: operationStatus ?? this.operationStatus,
      progress: progress ?? this.progress,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      recentPrintHistory: recentPrintHistory ?? this.recentPrintHistory,
    );
  }

  static BarcodeDesignData empty() => const BarcodeDesignData();

  @override
  List<Object?> get props => [
        selectedProducts,
        templates,
        selectedTemplate,
        settings,
        companyProfile,
        operationStatus,
        progress,
        errorMessage,
        recentPrintHistory,
      ];
}

/// Settings for barcode label design
class BarcodeDesignSettings extends Equatable {
  final double labelWidthMm;
  final double labelHeightMm;
  final bool includeName;
  final bool includePrice;
  final bool includeSku;
  final bool includeCompanyName;
  final bool includeCompanyContact;
  final bool includeVariantInfo;
  final String barcodeType;
  final int copies;
  final String printType; // 'single', 'batch', 'all_quantity'

  const BarcodeDesignSettings({
    this.labelWidthMm = 58.0,
    this.labelHeightMm = 40.0,
    this.includeName = true,
    this.includePrice = true,
    this.includeSku = false,
    this.includeCompanyName = false,
    this.includeCompanyContact = false,
    this.includeVariantInfo = false,
    this.barcodeType = 'auto',
    this.copies = 1,
    this.printType = 'single',
  });

  BarcodeDesignSettings copyWith({
    double? labelWidthMm,
    double? labelHeightMm,
    bool? includeName,
    bool? includePrice,
    bool? includeSku,
    bool? includeCompanyName,
    bool? includeCompanyContact,
    bool? includeVariantInfo,
    String? barcodeType,
    int? copies,
    String? printType,
  }) {
    return BarcodeDesignSettings(
      labelWidthMm: labelWidthMm ?? this.labelWidthMm,
      labelHeightMm: labelHeightMm ?? this.labelHeightMm,
      includeName: includeName ?? this.includeName,
      includePrice: includePrice ?? this.includePrice,
      includeSku: includeSku ?? this.includeSku,
      includeCompanyName: includeCompanyName ?? this.includeCompanyName,
      includeCompanyContact: includeCompanyContact ?? this.includeCompanyContact,
      includeVariantInfo: includeVariantInfo ?? this.includeVariantInfo,
      barcodeType: barcodeType ?? this.barcodeType,
      copies: copies ?? this.copies,
      printType: printType ?? this.printType,
    );
  }

  /// Create settings from a template
  factory BarcodeDesignSettings.fromTemplate(BarcodeTemplate template) {
    return BarcodeDesignSettings(
      labelWidthMm: template.widthMm,
      labelHeightMm: template.heightMm,
      includeName: template.includeName,
      includePrice: template.includePrice,
      includeSku: template.includeSku,
      includeCompanyName: template.includeCompanyName,
      includeVariantInfo: template.includeVariantInfo,
      barcodeType: template.barcodeType,
    );
  }

  @override
  List<Object?> get props => [
        labelWidthMm,
        labelHeightMm,
        includeName,
        includePrice,
        includeSku,
        includeCompanyName,
        includeCompanyContact,
        includeVariantInfo,
        barcodeType,
        copies,
        printType,
      ];
}

/// Status of print operation
enum PrintOperationStatus {
  idle,
  preparing,
  printing,
  success,
  error,
}
