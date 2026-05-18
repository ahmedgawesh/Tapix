import 'dart:convert';

/// Centralized application settings entity.
/// All settings are persisted via SharedPreferences as a single JSON blob.
class AppSettings {
  // ── Receipt / Invoice ──
  final String receiptHeaderText;
  final String receiptFooterText;
  final bool showLogoOnReceipt;
  final String receiptPaperSize; // '58mm', '80mm'
  final int receiptCopies;
  final bool autoPrintReceipt;
  final bool includeTaxBreakdown;
  final String receiptLanguage; // 'app', 'en', 'ar', 'fr'
  final bool showHeaderFooterOnPurchases; // Show header/footer text on purchase invoices

  // ── Barcode / Label ──
  final String defaultLabelSize; // 'small', 'medium', 'large'
  final String labelTemplate; // 'standard', 'compact', 'detailed'
  final String printerConnection; // 'none', 'bluetooth', 'usb', 'network'
  final bool includePriceOnLabel;
  final bool includeBarcodeText;

  // ── Tax ──
  final double defaultPurchaseTaxRate;
  final double defaultSalesTaxRate;
  final String taxRegistrationNumber;
  final bool taxInclusivePricing;
  final bool enableTaxCalculations;

  // ── Inventory ──
  final int lowStockThreshold;
  final bool enableStockAlerts;
  final bool allowNegativeStock;
  final bool autoGenerateSku;
  final String skuFormat; // e.g. 'PRD-{0000}'
  final bool autoGenerateBarcode;
  final bool defaultTrackInventory;

  // ── Sales ──
  final String defaultPaymentMethod; // 'cash', 'card', 'bank_transfer'
  final bool allowPartialPayments;
  final bool allowDiscounts;
  final double maxDiscountPercent;
  final bool requireCustomerForSales;
  final bool enableLoyaltyPoints;
  final int pointsPerCurrencyUnit;

  // ── Security ──
  final bool enableSessionTimeout; // Enable/disable session timeout
  final int sessionTimeoutMinutes;
  final int rememberMeDurationHours; // How long "Remember Me" keeps user logged in (max 168h = 7 days)
  final bool requirePinForVoidRefund;
  final bool enableBiometricLogin;
  final bool enableDatabaseEncryption;

  // ── Reports ──
  final String defaultReportDateRange; // 'today', 'week', 'month'
  final String defaultExportFormat; // 'pdf', 'excel', 'csv'
  final bool includeInactiveInReports;

  // ── Notifications ──
  final bool lowStockNotifications;
  final bool dailySalesSummary;
  final bool paymentReminders;

  // ── Printer ──
  final String receiptPrinterName;
  final String labelPrinterName;

  const AppSettings({
    // Receipt
    this.receiptHeaderText = '',
    this.receiptFooterText = '',
    this.showLogoOnReceipt = true,
    this.receiptPaperSize = '80mm',
    this.receiptCopies = 1,
    this.autoPrintReceipt = false,
    this.includeTaxBreakdown = true,
    this.receiptLanguage = 'app',
    this.showHeaderFooterOnPurchases = true,
    // Barcode
    this.defaultLabelSize = 'medium',
    this.labelTemplate = 'standard',
    this.printerConnection = 'none',
    this.includePriceOnLabel = true,
    this.includeBarcodeText = true,
    // Tax
    this.defaultPurchaseTaxRate = 0.0,
    this.defaultSalesTaxRate = 0.0,
    this.taxRegistrationNumber = '',
    this.taxInclusivePricing = false,
    this.enableTaxCalculations = true,
    // Inventory
    this.lowStockThreshold = 5,
    this.enableStockAlerts = true,
    this.allowNegativeStock = false,
    this.autoGenerateSku = false,
    this.skuFormat = 'PRD-{0000}',
    this.autoGenerateBarcode = true,
    this.defaultTrackInventory = true,
    // Sales
    this.defaultPaymentMethod = 'cash',
    this.allowPartialPayments = false,
    this.allowDiscounts = true,
    this.maxDiscountPercent = 100.0,
    this.requireCustomerForSales = false,
    this.enableLoyaltyPoints = false,
    this.pointsPerCurrencyUnit = 1,
    // Security
    this.enableSessionTimeout = true,
    this.sessionTimeoutMinutes = 30,
    this.rememberMeDurationHours = 72,
    this.requirePinForVoidRefund = false,
    this.enableBiometricLogin = false,
    this.enableDatabaseEncryption = false,
    // Reports
    this.defaultReportDateRange = 'month',
    this.defaultExportFormat = 'pdf',
    this.includeInactiveInReports = false,
    // Notifications
    this.lowStockNotifications = true,
    this.dailySalesSummary = false,
    this.paymentReminders = false,
    // Printer
    this.receiptPrinterName = '',
    this.labelPrinterName = '',
  });

  AppSettings copyWith({
    String? receiptHeaderText,
    String? receiptFooterText,
    bool? showLogoOnReceipt,
    String? receiptPaperSize,
    int? receiptCopies,
    bool? autoPrintReceipt,
    bool? includeTaxBreakdown,
    String? receiptLanguage,
    bool? showHeaderFooterOnPurchases,
    String? defaultLabelSize,
    String? labelTemplate,
    String? printerConnection,
    bool? includePriceOnLabel,
    bool? includeBarcodeText,
    double? defaultPurchaseTaxRate,
    double? defaultSalesTaxRate,
    String? taxRegistrationNumber,
    bool? taxInclusivePricing,
    bool? enableTaxCalculations,
    int? lowStockThreshold,
    bool? enableStockAlerts,
    bool? allowNegativeStock,
    bool? autoGenerateSku,
    String? skuFormat,
    bool? autoGenerateBarcode,
    bool? defaultTrackInventory,
    String? defaultPaymentMethod,
    bool? allowPartialPayments,
    bool? allowDiscounts,
    double? maxDiscountPercent,
    bool? requireCustomerForSales,
    bool? enableLoyaltyPoints,
    int? pointsPerCurrencyUnit,
    bool? enableSessionTimeout,
    int? sessionTimeoutMinutes,
    int? rememberMeDurationHours,
    bool? requirePinForVoidRefund,
    bool? enableBiometricLogin,
    bool? enableDatabaseEncryption,
    String? defaultReportDateRange,
    String? defaultExportFormat,
    bool? includeInactiveInReports,
    bool? lowStockNotifications,
    bool? dailySalesSummary,
    bool? paymentReminders,
    String? receiptPrinterName,
    String? labelPrinterName,
  }) {
    return AppSettings(
      receiptHeaderText: receiptHeaderText ?? this.receiptHeaderText,
      receiptFooterText: receiptFooterText ?? this.receiptFooterText,
      showLogoOnReceipt: showLogoOnReceipt ?? this.showLogoOnReceipt,
      receiptPaperSize: receiptPaperSize ?? this.receiptPaperSize,
      receiptCopies: receiptCopies ?? this.receiptCopies,
      autoPrintReceipt: autoPrintReceipt ?? this.autoPrintReceipt,
      includeTaxBreakdown: includeTaxBreakdown ?? this.includeTaxBreakdown,
      receiptLanguage: receiptLanguage ?? this.receiptLanguage,
      showHeaderFooterOnPurchases: showHeaderFooterOnPurchases ?? this.showHeaderFooterOnPurchases,
      defaultLabelSize: defaultLabelSize ?? this.defaultLabelSize,
      labelTemplate: labelTemplate ?? this.labelTemplate,
      printerConnection: printerConnection ?? this.printerConnection,
      includePriceOnLabel: includePriceOnLabel ?? this.includePriceOnLabel,
      includeBarcodeText: includeBarcodeText ?? this.includeBarcodeText,
      defaultPurchaseTaxRate: defaultPurchaseTaxRate ?? this.defaultPurchaseTaxRate,
      defaultSalesTaxRate: defaultSalesTaxRate ?? this.defaultSalesTaxRate,
      taxRegistrationNumber: taxRegistrationNumber ?? this.taxRegistrationNumber,
      taxInclusivePricing: taxInclusivePricing ?? this.taxInclusivePricing,
      enableTaxCalculations: enableTaxCalculations ?? this.enableTaxCalculations,
      lowStockThreshold: lowStockThreshold ?? this.lowStockThreshold,
      enableStockAlerts: enableStockAlerts ?? this.enableStockAlerts,
      allowNegativeStock: allowNegativeStock ?? this.allowNegativeStock,
      autoGenerateSku: autoGenerateSku ?? this.autoGenerateSku,
      skuFormat: skuFormat ?? this.skuFormat,
      autoGenerateBarcode: autoGenerateBarcode ?? this.autoGenerateBarcode,
      defaultTrackInventory: defaultTrackInventory ?? this.defaultTrackInventory,
      defaultPaymentMethod: defaultPaymentMethod ?? this.defaultPaymentMethod,
      allowPartialPayments: allowPartialPayments ?? this.allowPartialPayments,
      allowDiscounts: allowDiscounts ?? this.allowDiscounts,
      maxDiscountPercent: maxDiscountPercent ?? this.maxDiscountPercent,
      requireCustomerForSales: requireCustomerForSales ?? this.requireCustomerForSales,
      enableLoyaltyPoints: enableLoyaltyPoints ?? this.enableLoyaltyPoints,
      pointsPerCurrencyUnit: pointsPerCurrencyUnit ?? this.pointsPerCurrencyUnit,
      enableSessionTimeout: enableSessionTimeout ?? this.enableSessionTimeout,
      sessionTimeoutMinutes: sessionTimeoutMinutes ?? this.sessionTimeoutMinutes,
      rememberMeDurationHours: rememberMeDurationHours ?? this.rememberMeDurationHours,
      requirePinForVoidRefund: requirePinForVoidRefund ?? this.requirePinForVoidRefund,
      enableBiometricLogin: enableBiometricLogin ?? this.enableBiometricLogin,
      enableDatabaseEncryption: enableDatabaseEncryption ?? this.enableDatabaseEncryption,
      defaultReportDateRange: defaultReportDateRange ?? this.defaultReportDateRange,
      defaultExportFormat: defaultExportFormat ?? this.defaultExportFormat,
      includeInactiveInReports: includeInactiveInReports ?? this.includeInactiveInReports,
      lowStockNotifications: lowStockNotifications ?? this.lowStockNotifications,
      dailySalesSummary: dailySalesSummary ?? this.dailySalesSummary,
      paymentReminders: paymentReminders ?? this.paymentReminders,
      receiptPrinterName: receiptPrinterName ?? this.receiptPrinterName,
      labelPrinterName: labelPrinterName ?? this.labelPrinterName,
    );
  }

  Map<String, dynamic> toMap() => {
        'receiptHeaderText': receiptHeaderText,
        'receiptFooterText': receiptFooterText,
        'showLogoOnReceipt': showLogoOnReceipt,
        'receiptPaperSize': receiptPaperSize,
        'receiptCopies': receiptCopies,
        'autoPrintReceipt': autoPrintReceipt,
        'includeTaxBreakdown': includeTaxBreakdown,
        'receiptLanguage': receiptLanguage,
        'showHeaderFooterOnPurchases': showHeaderFooterOnPurchases,
        'defaultLabelSize': defaultLabelSize,
        'labelTemplate': labelTemplate,
        'printerConnection': printerConnection,
        'includePriceOnLabel': includePriceOnLabel,
        'includeBarcodeText': includeBarcodeText,
        'defaultPurchaseTaxRate': defaultPurchaseTaxRate,
        'defaultSalesTaxRate': defaultSalesTaxRate,
        'taxRegistrationNumber': taxRegistrationNumber,
        'taxInclusivePricing': taxInclusivePricing,
        'enableTaxCalculations': enableTaxCalculations,
        'lowStockThreshold': lowStockThreshold,
        'enableStockAlerts': enableStockAlerts,
        'allowNegativeStock': allowNegativeStock,
        'autoGenerateSku': autoGenerateSku,
        'skuFormat': skuFormat,
        'autoGenerateBarcode': autoGenerateBarcode,
        'defaultTrackInventory': defaultTrackInventory,
        'defaultPaymentMethod': defaultPaymentMethod,
        'allowPartialPayments': allowPartialPayments,
        'allowDiscounts': allowDiscounts,
        'maxDiscountPercent': maxDiscountPercent,
        'requireCustomerForSales': requireCustomerForSales,
        'enableLoyaltyPoints': enableLoyaltyPoints,
        'pointsPerCurrencyUnit': pointsPerCurrencyUnit,
        'enableSessionTimeout': enableSessionTimeout,
        'sessionTimeoutMinutes': sessionTimeoutMinutes,
        'rememberMeDurationHours': rememberMeDurationHours,
        'requirePinForVoidRefund': requirePinForVoidRefund,
        'enableBiometricLogin': enableBiometricLogin,
        'enableDatabaseEncryption': enableDatabaseEncryption,
        'defaultReportDateRange': defaultReportDateRange,
        'defaultExportFormat': defaultExportFormat,
        'includeInactiveInReports': includeInactiveInReports,
        'lowStockNotifications': lowStockNotifications,
        'dailySalesSummary': dailySalesSummary,
        'paymentReminders': paymentReminders,
        'receiptPrinterName': receiptPrinterName,
        'labelPrinterName': labelPrinterName,
      };

  String toJson() => jsonEncode(toMap());

  factory AppSettings.fromMap(Map<String, dynamic> m) {
    return AppSettings(
      receiptHeaderText: (m['receiptHeaderText'] as String?) ?? '',
      receiptFooterText: (m['receiptFooterText'] as String?) ?? '',
      showLogoOnReceipt: (m['showLogoOnReceipt'] as bool?) ?? true,
      receiptPaperSize: (m['receiptPaperSize'] as String?) ?? '80mm',
      receiptCopies: (m['receiptCopies'] as int?) ?? 1,
      autoPrintReceipt: (m['autoPrintReceipt'] as bool?) ?? false,
      includeTaxBreakdown: (m['includeTaxBreakdown'] as bool?) ?? true,
      receiptLanguage: (m['receiptLanguage'] as String?) ?? 'app',
      showHeaderFooterOnPurchases: (m['showHeaderFooterOnPurchases'] as bool?) ?? true,
      defaultLabelSize: (m['defaultLabelSize'] as String?) ?? 'medium',
      labelTemplate: (m['labelTemplate'] as String?) ?? 'standard',
      printerConnection: (m['printerConnection'] as String?) ?? 'none',
      includePriceOnLabel: (m['includePriceOnLabel'] as bool?) ?? true,
      includeBarcodeText: (m['includeBarcodeText'] as bool?) ?? true,
      defaultPurchaseTaxRate: (m['defaultPurchaseTaxRate'] as num?)?.toDouble() ?? 0.0,
      defaultSalesTaxRate: (m['defaultSalesTaxRate'] as num?)?.toDouble() ?? 0.0,
      taxRegistrationNumber: (m['taxRegistrationNumber'] as String?) ?? '',
      taxInclusivePricing: (m['taxInclusivePricing'] as bool?) ?? false,
      enableTaxCalculations: (m['enableTaxCalculations'] as bool?) ?? true,
      lowStockThreshold: (m['lowStockThreshold'] as int?) ?? 5,
      enableStockAlerts: (m['enableStockAlerts'] as bool?) ?? true,
      allowNegativeStock: (m['allowNegativeStock'] as bool?) ?? false,
      autoGenerateSku: (m['autoGenerateSku'] as bool?) ?? false,
      skuFormat: (m['skuFormat'] as String?) ?? 'PRD-{0000}',
      autoGenerateBarcode: (m['autoGenerateBarcode'] as bool?) ?? true,
      defaultTrackInventory: (m['defaultTrackInventory'] as bool?) ?? true,
      defaultPaymentMethod: (m['defaultPaymentMethod'] as String?) ?? 'cash',
      allowPartialPayments: (m['allowPartialPayments'] as bool?) ?? false,
      allowDiscounts: (m['allowDiscounts'] as bool?) ?? true,
      maxDiscountPercent: (m['maxDiscountPercent'] as num?)?.toDouble() ?? 100.0,
      requireCustomerForSales: (m['requireCustomerForSales'] as bool?) ?? false,
      enableLoyaltyPoints: (m['enableLoyaltyPoints'] as bool?) ?? false,
      pointsPerCurrencyUnit: (m['pointsPerCurrencyUnit'] as int?) ?? 1,
      enableSessionTimeout: (m['enableSessionTimeout'] as bool?) ?? true,
      sessionTimeoutMinutes: (m['sessionTimeoutMinutes'] as int?) ?? 30,
      rememberMeDurationHours: (m['rememberMeDurationHours'] as int?) ?? 72,
      requirePinForVoidRefund: (m['requirePinForVoidRefund'] as bool?) ?? false,
      enableBiometricLogin: (m['enableBiometricLogin'] as bool?) ?? false,
      enableDatabaseEncryption: (m['enableDatabaseEncryption'] as bool?) ?? false,
      defaultReportDateRange: (m['defaultReportDateRange'] as String?) ?? 'month',
      defaultExportFormat: (m['defaultExportFormat'] as String?) ?? 'pdf',
      includeInactiveInReports: (m['includeInactiveInReports'] as bool?) ?? false,
      lowStockNotifications: (m['lowStockNotifications'] as bool?) ?? true,
      dailySalesSummary: (m['dailySalesSummary'] as bool?) ?? false,
      paymentReminders: (m['paymentReminders'] as bool?) ?? false,
      receiptPrinterName: (m['receiptPrinterName'] as String?) ?? '',
      labelPrinterName: (m['labelPrinterName'] as String?) ?? '',
    );
  }

  factory AppSettings.fromJson(String json) {
    try {
      return AppSettings.fromMap(jsonDecode(json) as Map<String, dynamic>);
    } catch (_) {
      return const AppSettings();
    }
  }

  // ── Barcode label size helpers ──

  /// Convert [defaultLabelSize] ('small','medium','large') to width in mm.
  double get labelWidthMm {
    switch (defaultLabelSize) {
      case 'small':
        return 40.0;
      case 'large':
        return 80.0;
      case 'medium':
      default:
        return 58.0;
    }
  }

  /// Convert [defaultLabelSize] ('small','medium','large') to height in mm.
  double get labelHeightMm {
    switch (defaultLabelSize) {
      case 'small':
        return 25.0;
      case 'large':
        return 50.0;
      case 'medium':
      default:
        return 40.0;
    }
  }
}
