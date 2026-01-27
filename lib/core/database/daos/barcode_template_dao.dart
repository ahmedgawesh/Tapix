import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/barcode.dart';

part 'barcode_template_dao.g.dart';

@DriftAccessor(tables: [BarcodeTemplates, PrintHistories])
class BarcodeTemplateDao extends DatabaseAccessor<AppDatabase>
    with _$BarcodeTemplateDaoMixin {
  BarcodeTemplateDao(super.db);

  /// Watch all active templates
  Stream<List<BarcodeTemplate>> watchTemplates() {
    return (select(barcodeTemplates)
          ..where((t) => t.isActive.equals(true))
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .watch();
  }

  /// Get all active templates
  Future<List<BarcodeTemplate>> getTemplates() {
    return (select(barcodeTemplates)
          ..where((t) => t.isActive.equals(true))
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .get();
  }

  /// Get template by ID
  Future<BarcodeTemplate?> getTemplateById(int id) {
    return (select(barcodeTemplates)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  /// Get default template
  Future<BarcodeTemplate?> getDefaultTemplate() {
    return (select(barcodeTemplates)
          ..where((t) => t.isDefault.equals(true) & t.isActive.equals(true)))
        .getSingleOrNull();
  }

  /// Watch default template
  Stream<BarcodeTemplate?> watchDefaultTemplate() {
    return (select(barcodeTemplates)
          ..where((t) => t.isDefault.equals(true) & t.isActive.equals(true)))
        .watchSingleOrNull();
  }

  /// Create a new template
  Future<int> createTemplate(BarcodeTemplatesCompanion template) {
    return into(barcodeTemplates).insert(template);
  }

  /// Update a template
  Future<bool> updateTemplate(BarcodeTemplate template) {
    return update(barcodeTemplates).replace(template);
  }

  /// Set template as default (unsets other defaults)
  Future<void> setDefaultTemplate(int templateId) async {
    await transaction(() async {
      // Unset all defaults
      await (update(barcodeTemplates)
            ..where((t) => t.isDefault.equals(true)))
          .write(const BarcodeTemplatesCompanion(isDefault: Value(false)));
      // Set new default
      await (update(barcodeTemplates)..where((t) => t.id.equals(templateId)))
          .write(const BarcodeTemplatesCompanion(isDefault: Value(true)));
    });
  }

  /// Soft delete a template
  Future<int> deleteTemplate(int id) {
    return (update(barcodeTemplates)..where((t) => t.id.equals(id)))
        .write(const BarcodeTemplatesCompanion(isActive: Value(false)));
  }

  /// Log a print operation
  Future<int> logPrint({
    required int productId,
    int? variantId,
    int? templateId,
    required int quantityPrinted,
    String? printerName,
    String printType = 'single',
    String status = 'success',
    String? errorMessage,
  }) {
    return into(printHistories).insert(
      PrintHistoriesCompanion.insert(
        productId: productId,
        variantId: Value(variantId),
        templateId: Value(templateId),
        quantityPrinted: quantityPrinted,
        printerName: Value(printerName),
        printType: Value(printType),
        status: Value(status),
        errorMessage: Value(errorMessage),
      ),
    );
  }

  /// Watch print history for a product
  Stream<List<PrintHistory>> watchPrintHistoryForProduct(int productId) {
    return (select(printHistories)
          ..where((p) => p.productId.equals(productId))
          ..orderBy([(p) => OrderingTerm.desc(p.printDate)]))
        .watch();
  }

  /// Get print history with pagination
  Future<List<PrintHistory>> getPrintHistory({
    int? productId,
    int limit = 50,
    int offset = 0,
  }) {
    final query = select(printHistories)
      ..orderBy([(p) => OrderingTerm.desc(p.printDate)])
      ..limit(limit, offset: offset);

    if (productId != null) {
      query.where((p) => p.productId.equals(productId));
    }

    return query.get();
  }

  /// Get total prints for a product
  Future<int> getTotalPrintsForProduct(int productId) async {
    final result = await customSelect(
      'SELECT SUM(quantity_printed) as total FROM print_histories WHERE product_id = ?',
      variables: [Variable.withInt(productId)],
    ).getSingle();
    return result.read<int?>('total') ?? 0;
  }
}
