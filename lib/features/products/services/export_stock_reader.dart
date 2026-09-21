import '../../../core/database/app_database.dart' as db;
import '../../../core/services/business/warehouse_catalog_scope.dart';
import '../../../core/services/business/warehouse_read_scope.dart';
import '../domain/entities/product_variant_entity.dart';

abstract class ExportStockReader {
  Future<ProductVariant> read(ProductVariant variant);
  Future<T> snapshot<T>(Future<T> Function() action);
}

class WarehouseExportStockReader implements ExportStockReader {
  final db.AppDatabase database;
  final WarehouseReadScope? scope;
  const WarehouseExportStockReader(this.database, {this.scope});

  @override
  Future<T> snapshot<T>(Future<T> Function() action) =>
      database.transaction(action);

  @override
  Future<ProductVariant> read(ProductVariant variant) async {
    final rows = await WarehouseCatalogScope.readVariants(database, [
      variant.id,
    ], scope: scope);
    if (rows.length != 1 || rows.single.productId != variant.productId) {
      throw StateError(
        'Export variant is missing or belongs to another product.',
      );
    }
    return variant.copyWith(
      stockQuantity: rows.single.stockQuantity,
      costCents: rows.single.costCents,
    );
  }
}
