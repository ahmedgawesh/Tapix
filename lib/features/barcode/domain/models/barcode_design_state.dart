import 'package:equatable/equatable.dart';

import '../../../products/domain/entities/product_entity.dart';
import '../../../../core/database/app_database.dart' hide Product;
import '../../../settings/domain/entities/company_profile.dart';
import '../../data/models/invoice_print_data.dart';

/// Represents the UI state for barcode design screen
class BarcodeDesignData extends Equatable {
  final List<Product> selectedProducts;
  final Map<int, String> variantInfoByProductId;

  /// When non-empty, only these explicit variants are included for products
  /// that have variants. An empty set means all active dimensional variants.
  final Set<int> selectedVariantIds;
  final List<BarcodeTemplate> templates;
  final BarcodeTemplate? selectedTemplate;
  final BarcodeDesignSettings settings;
  final CompanyProfile companyProfile;
  final PrintOperationStatus operationStatus;
  final double? progress;
  final String? errorMessage;
  final List<PrintHistory> recentPrintHistory;

  // Invoice-related fields
  final InvoicePrintData? invoiceData;
  final Map<int, int> currentQuantities;

  const BarcodeDesignData({
    this.selectedProducts = const [],
    this.variantInfoByProductId = const {},
    this.selectedVariantIds = const {},
    this.templates = const [],
    this.selectedTemplate,
    this.settings = const BarcodeDesignSettings(),
    this.companyProfile = const CompanyProfile(name: ''),
    this.operationStatus = PrintOperationStatus.idle,
    this.progress,
    this.errorMessage,
    this.recentPrintHistory = const [],
    this.invoiceData,
    this.currentQuantities = const {},
  });

  BarcodeDesignData copyWith({
    List<Product>? selectedProducts,
    Map<int, String>? variantInfoByProductId,
    Set<int>? selectedVariantIds,
    List<BarcodeTemplate>? templates,
    BarcodeTemplate? selectedTemplate,
    BarcodeDesignSettings? settings,
    CompanyProfile? companyProfile,
    PrintOperationStatus? operationStatus,
    double? progress,
    String? errorMessage,
    List<PrintHistory>? recentPrintHistory,
    InvoicePrintData? invoiceData,
    Map<int, int>? currentQuantities,
    bool clearError = false,
    bool clearTemplate = false,
  }) {
    return BarcodeDesignData(
      selectedProducts: selectedProducts ?? this.selectedProducts,
      variantInfoByProductId:
          variantInfoByProductId ?? this.variantInfoByProductId,
      selectedVariantIds: selectedVariantIds ?? this.selectedVariantIds,
      templates: templates ?? this.templates,
      selectedTemplate: clearTemplate
          ? null
          : (selectedTemplate ?? this.selectedTemplate),
      settings: settings ?? this.settings,
      companyProfile: companyProfile ?? this.companyProfile,
      operationStatus: operationStatus ?? this.operationStatus,
      progress: progress ?? this.progress,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      recentPrintHistory: recentPrintHistory ?? this.recentPrintHistory,
      invoiceData: invoiceData ?? this.invoiceData,
      currentQuantities: currentQuantities ?? this.currentQuantities,
    );
  }

  static BarcodeDesignData empty() => const BarcodeDesignData();

  @override
  List<Object?> get props => [
    selectedProducts,
    variantInfoByProductId,
    selectedVariantIds,
    templates,
    selectedTemplate,
    settings,
    companyProfile,
    operationStatus,
    progress,
    errorMessage,
    recentPrintHistory,
    invoiceData,
    currentQuantities,
  ];

  /// Check if this state has invoice data
  bool get hasInvoiceData => invoiceData != null;

  /// Check if quantities have been modified from original invoice values
  bool get quantitiesModified {
    if (invoiceData == null) return false;

    for (final line in invoiceData!.lines) {
      final current = currentQuantities[line.variantId] ?? 0;
      final original = line.quantity;
      if (current != original) return true;
    }

    return false;
  }

  /// Get total quantity for all invoice lines
  int get totalInvoiceQuantity {
    if (invoiceData == null) return 0;
    return currentQuantities.values.fold(0, (sum, qty) => sum + qty);
  }
}

/// Print mode for label printing
enum LabelPrintMode {
  /// Single label per page (thermal printer)
  thermal,

  /// Multiple labels on A4 sheet
  a4Sheet,
}

/// Quantity mode for determining how many labels to print
enum QuantityMode {
  /// Print one label per product
  single,

  /// Print specified number of copies
  custom,

  /// Print based on invoice quantity
  invoiceQuantity,

  /// Print based on stock quantity
  stockQuantity,
}

/// Which selling price is shown on the barcode label.
enum PriceDisplayMode {
  /// Regular retail selling price.
  retail,

  /// Wholesale selling price.
  wholesale,

  /// Regular and wholesale selling prices together.
  both,
}

/// Destination used when the user presses the print button.
enum PrintDestination {
  /// Native print dialog (Android, Windows, Linux, web, etc.).
  system,

  /// Direct Android Bluetooth Classic connection to a TSPL label printer.
  bluetooth,
}

/// Settings for barcode label design
class BarcodeDesignSettings extends Equatable {
  final double labelWidthMm;
  final double labelHeightMm;
  final bool includeName;
  final bool includePrice;
  final PriceDisplayMode priceDisplayMode;
  final PrintDestination printDestination;
  final bool includeBarcode;
  final bool includeSku;
  final bool includeCompanyName;
  final bool includeCompanyContact;
  final bool includeVariantInfo;
  final String barcodeType;
  final int copies;
  final String printType; // 'single', 'batch', 'all_quantity'

  // A4 Sheet settings
  final LabelPrintMode printMode;
  final int labelsPerRow;
  final double horizontalGapMm;
  final double verticalGapMm;
  final double pageMarginMm;

  // Quantity mode
  final QuantityMode quantityMode;

  const BarcodeDesignSettings({
    this.labelWidthMm = 58.0,
    this.labelHeightMm = 40.0,
    this.includeName = true,
    this.includePrice = true,
    this.priceDisplayMode = PriceDisplayMode.retail,
    this.printDestination = PrintDestination.system,
    this.includeBarcode = true,
    this.includeSku = false,
    this.includeCompanyName = true,
    this.includeCompanyContact = true,
    this.includeVariantInfo = true,
    this.barcodeType = 'auto',
    this.copies = 1,
    this.printType = 'single',
    this.printMode = LabelPrintMode.thermal,
    this.labelsPerRow = 3,
    this.horizontalGapMm = 2.0,
    this.verticalGapMm = 2.0,
    this.pageMarginMm = 10.0,
    this.quantityMode = QuantityMode.single,
  });

  BarcodeDesignSettings copyWith({
    double? labelWidthMm,
    double? labelHeightMm,
    bool? includeName,
    bool? includePrice,
    PriceDisplayMode? priceDisplayMode,
    PrintDestination? printDestination,
    bool? includeBarcode,
    bool? includeSku,
    bool? includeCompanyName,
    bool? includeCompanyContact,
    bool? includeVariantInfo,
    String? barcodeType,
    int? copies,
    String? printType,
    LabelPrintMode? printMode,
    int? labelsPerRow,
    double? horizontalGapMm,
    double? verticalGapMm,
    double? pageMarginMm,
    QuantityMode? quantityMode,
  }) {
    return BarcodeDesignSettings(
      labelWidthMm: labelWidthMm ?? this.labelWidthMm,
      labelHeightMm: labelHeightMm ?? this.labelHeightMm,
      includeName: includeName ?? this.includeName,
      includePrice: includePrice ?? this.includePrice,
      priceDisplayMode: priceDisplayMode ?? this.priceDisplayMode,
      printDestination: printDestination ?? this.printDestination,
      includeBarcode: includeBarcode ?? this.includeBarcode,
      includeSku: includeSku ?? this.includeSku,
      includeCompanyName: includeCompanyName ?? this.includeCompanyName,
      includeCompanyContact:
          includeCompanyContact ?? this.includeCompanyContact,
      includeVariantInfo: includeVariantInfo ?? this.includeVariantInfo,
      barcodeType: barcodeType ?? this.barcodeType,
      copies: copies ?? this.copies,
      printType: printType ?? this.printType,
      printMode: printMode ?? this.printMode,
      labelsPerRow: labelsPerRow ?? this.labelsPerRow,
      horizontalGapMm: horizontalGapMm ?? this.horizontalGapMm,
      verticalGapMm: verticalGapMm ?? this.verticalGapMm,
      pageMarginMm: pageMarginMm ?? this.pageMarginMm,
      quantityMode: quantityMode ?? this.quantityMode,
    );
  }

  /// Create settings from a template
  factory BarcodeDesignSettings.fromTemplate(BarcodeTemplate template) {
    // Determine print mode based on paper size
    final isA4 = template.paperSize.toLowerCase() == 'a4';

    return BarcodeDesignSettings(
      labelWidthMm: template.widthMm,
      labelHeightMm: template.heightMm,
      includeName: template.includeName,
      includePrice: template.includePrice,
      includeBarcode: true,
      includeSku: template.includeSku,
      includeCompanyName: template.includeCompanyName,
      includeVariantInfo: template.includeVariantInfo,
      barcodeType: template.barcodeType,
      printMode: isA4 ? LabelPrintMode.a4Sheet : LabelPrintMode.thermal,
    );
  }

  /// Check if using A4 sheet mode
  bool get isA4Mode => printMode == LabelPrintMode.a4Sheet;

  /// Calculate how many labels fit per row on A4
  int get calculatedLabelsPerRow {
    const a4WidthMm = 210.0;
    final availableWidth = a4WidthMm - (2 * pageMarginMm);
    final labelWithGap = labelWidthMm + horizontalGapMm;
    return (availableWidth / labelWithGap).floor().clamp(1, 10);
  }

  /// Calculate how many labels fit per column on A4
  int get calculatedLabelsPerColumn {
    const a4HeightMm = 297.0;
    final availableHeight = a4HeightMm - (2 * pageMarginMm);
    final labelWithGap = labelHeightMm + verticalGapMm;
    return (availableHeight / labelWithGap).floor().clamp(1, 20);
  }

  /// Total labels per A4 page
  int get labelsPerPage => labelsPerRow * calculatedLabelsPerColumn;

  @override
  List<Object?> get props => [
    labelWidthMm,
    labelHeightMm,
    includeName,
    includePrice,
    priceDisplayMode,
    printDestination,
    includeBarcode,
    includeSku,
    includeCompanyName,
    includeCompanyContact,
    includeVariantInfo,
    barcodeType,
    copies,
    printType,
    printMode,
    labelsPerRow,
    horizontalGapMm,
    verticalGapMm,
    pageMarginMm,
    quantityMode,
  ];
}

/// Status of print operation
enum PrintOperationStatus { idle, preparing, printing, success, error }
