import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';

import '../../database/app_database.dart';
import 'warehouse_stock_scope.dart';
import 'warehouse_read_scope.dart';

/// Read projections only: catalog prices remain shared, stock and carrying
/// costs come from the primary warehouse. Does not repair or write mirrors.
class WarehouseCatalogScope {
  WarehouseCatalogScope._();

  static String get products => productsFor();

  static String productsFor([WarehouseReadScope? scope]) =>
      '''(
    SELECT p.*, COALESCE(a.variant_count, 0) AS scoped_variant_count,
      COALESCE(a.balance_count, 0) AS scoped_balance_count,
      CASE WHEN a.variant_count > 0 THEN a.quantity ELSE ${scope != null && !scope.isPrimary ? '0' : 'p.stock_quantity'} END AS scoped_quantity,
      CASE WHEN a.variant_count > 0 THEN a.cost ELSE ${scope != null && !scope.isPrimary ? '0' : 'p.cost_cents'} END AS scoped_cost
    FROM products p
    LEFT JOIN (
      SELECT v.product_id, COUNT(*) AS variant_count,
        COUNT(ws.variant_id) AS balance_count, COALESCE(SUM(ws.quantity), 0) AS quantity,
        COALESCE(CAST(ROUND(CAST(SUM(
          (ws.quantity - ws.supplier_owned_quantity) * ws.unit_cost_cents
        ) AS REAL) / NULLIF(SUM(
          ws.quantity - ws.supplier_owned_quantity
        ), 0)) AS INTEGER),
          CAST(ROUND(AVG(ws.unit_cost_cents)) AS INTEGER), 0) AS cost
      FROM product_variants v LEFT JOIN ${scope?.stocks ?? WarehouseStockScope.primaryStocks} ws ON ws.variant_id = v.id
      WHERE v.is_active = 1 GROUP BY v.product_id
    ) a ON a.product_id = p.id
  )''';

  static String get variants => variantsFor();

  static String variantsFor([WarehouseReadScope? scope]) =>
      '''(
    SELECT v.*, ws.quantity AS scoped_quantity, ws.unit_cost_cents AS scoped_cost
    FROM product_variants v LEFT JOIN ${scope?.stocks ?? WarehouseStockScope.primaryStocks} ws ON ws.variant_id = v.id
  )''';

  static Set<TableInfo<Table, dynamic>> dependencies(AppDatabase db) => {
    db.products,
    db.productVariants,
    ...WarehouseStockScope.dependencies(db),
  };

  static Product mapProduct(AppDatabase db, QueryRow row) {
    final product = db.products.map(row.data);
    final count = row.read<int>('scoped_variant_count');
    if (count != row.read<int>('scoped_balance_count')) {
      throw StateError('Missing warehouse balance for product ${product.id}.');
    }
    if (!product.hasVariants && count > 1) {
      throw StateError(
        'Ambiguous operational variant for product ${product.id}.',
      );
    }
    return product.copyWith(
      stockQuantity: row.read<int>('scoped_quantity'),
      costCents: Decimal.fromInt(row.read<int>('scoped_cost')),
    );
  }

  static ProductVariant mapVariant(AppDatabase db, QueryRow row) {
    final variant = db.productVariants.map(row.data);
    final quantity = row.readNullable<int>('scoped_quantity');
    final cost = row.readNullable<int>('scoped_cost');
    if (quantity == null || cost == null) {
      throw StateError('Missing warehouse balance for variant ${variant.id}.');
    }
    return variant.copyWith(
      stockQuantity: quantity,
      costCents: Decimal.fromInt(cost),
    );
  }

  static Future<List<Product>> readProducts(
    AppDatabase db,
    List<int> ids, {
    WarehouseReadScope? scope,
  }) async {
    await scope?.validate(db);
    if (ids.isEmpty) return [];
    final rows = await db
        .customSelect(
          'SELECT * FROM ${productsFor(scope)} WHERE id IN (${List.filled(ids.length, '?').join(',')})',
          variables: ids.map(Variable.withInt).toList(),
          readsFrom: dependencies(db),
        )
        .get();
    return rows.map((row) => mapProduct(db, row)).toList();
  }

  static Future<List<ProductVariant>> readVariants(
    AppDatabase db,
    List<int> ids, {
    WarehouseReadScope? scope,
  }) async {
    await scope?.validate(db);
    if (ids.isEmpty) return [];
    final rows = await db
        .customSelect(
          'SELECT * FROM ${variantsFor(scope)} WHERE id IN (${List.filled(ids.length, '?').join(',')})',
          variables: ids.map(Variable.withInt).toList(),
          readsFrom: dependencies(db),
        )
        .get();
    return rows.map((row) => mapVariant(db, row)).toList();
  }
}
