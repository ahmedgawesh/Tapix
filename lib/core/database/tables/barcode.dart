import 'package:drift/drift.dart';
import 'products.dart';

/// Barcode label templates for customizable label designs
@DataClassName('BarcodeTemplate')
class BarcodeTemplates extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();

  /// JSON configuration for layout (font sizes, colors, element positions, etc.)
  TextColumn get layoutConfig => text()();

  /// Paper size: '58mm', '80mm', 'A4', 'custom'
  TextColumn get paperSize => text().withDefault(const Constant('58mm'))();

  /// Label width in mm
  RealColumn get widthMm => real().withDefault(const Constant(58.0))();

  /// Label height in mm
  RealColumn get heightMm => real().withDefault(const Constant(40.0))();

  /// Whether to include product name on label
  BoolColumn get includeName => boolean().withDefault(const Constant(true))();

  /// Whether to include price on label
  BoolColumn get includePrice => boolean().withDefault(const Constant(true))();

  /// Whether to include SKU on label
  BoolColumn get includeSku => boolean().withDefault(const Constant(false))();

  /// Whether to include company name on label
  BoolColumn get includeCompanyName =>
      boolean().withDefault(const Constant(false))();

  /// Whether to show size/color variant info
  BoolColumn get includeVariantInfo =>
      boolean().withDefault(const Constant(false))();

  /// Barcode type: 'auto', 'code128', 'ean13', 'ean8', 'upca', 'qr'
  TextColumn get barcodeType => text().withDefault(const Constant('auto'))();

  /// Whether this is the default template
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

/// Print history log for tracking all printed labels
@DataClassName('PrintHistory')
class PrintHistories extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get productId =>
      integer().references(Products, #id, onDelete: KeyAction.cascade)();
  IntColumn get variantId => integer().nullable().references(
    ProductVariants,
    #id,
    onDelete: KeyAction.cascade,
  )();
  IntColumn get templateId => integer().nullable().references(
    BarcodeTemplates,
    #id,
    onDelete: KeyAction.setNull,
  )();
  IntColumn get quantityPrinted => integer()();
  TextColumn get printerName => text().nullable()();

  /// Print type: 'single', 'batch', 'all_quantity'
  TextColumn get printType => text().withDefault(const Constant('single'))();

  /// Status: 'success', 'failed', 'cancelled'
  TextColumn get status => text().withDefault(const Constant('success'))();
  TextColumn get errorMessage => text().nullable()();
  DateTimeColumn get printDate => dateTime().withDefault(currentDateAndTime)();
}
