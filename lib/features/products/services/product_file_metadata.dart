import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../core/database/app_database.dart';
import '../../../core/services/business/warehouse_stock_scope.dart';
import '../../../core/services/inventory/supplier_product_identity_service.dart';

/// Portable catalog references. Database row ids are never portable identities.
class ProductFileMetadata {
  final AppDatabase db;
  const ProductFileMetadata(this.db);

  Future<Map<String, Object>> export(int productId, int? variantId) async {
    final row = await db
        .customSelect(
          '''
      SELECT s.product_code, s.name AS supplier_name, c.code AS currency_code
      FROM products p LEFT JOIN suppliers s ON s.id=p.supplier_id
      LEFT JOIN currencies c ON c.id=p.currency_id WHERE p.id=?
    ''',
          variables: [Variable.withInt(productId)],
        )
        .getSingle();
    final identities = variantId == null
        ? <QueryRow>[]
        : await db
              .customSelect(
                '''
      SELECT supplier_code_snapshot AS supplier_code, base_sku_snapshot AS base_sku,
        source_sku FROM supplier_product_identities WHERE canonical_variant_id=?
      ORDER BY supplier_code_snapshot
    ''',
                variables: [Variable.withInt(variantId)],
              )
              .get();
    final stock = variantId == null
        ? null
        : await db
              .customSelect(
                'SELECT supplier_owned_quantity FROM ${WarehouseStockScope.primaryStocks} WHERE variant_id=?',
                variables: [Variable.withInt(variantId)],
              )
              .getSingleOrNull();
    return {
      'supplier_code': row.readNullable<String>('product_code') ?? '',
      'supplier_name': row.readNullable<String>('supplier_name') ?? '',
      'currency_code': row.readNullable<String>('currency_code') ?? '',
      'supplier_identities': identities.isEmpty
          ? ''
          : jsonEncode(identities.map((r) => r.data).toList()),
      'supplier_owned_quantity':
          stock?.read<int>('supplier_owned_quantity') ?? 0,
    };
  }

  Future<int?> supplier(String code, String name, String legacyId) async {
    if (code.isEmpty && name.isEmpty) {
      if (legacyId.isNotEmpty) {
        throw FormatException('import_products.reference_required'.tr());
      }
      return null;
    }
    final rows = await db
        .customSelect(
          code.isNotEmpty
              ? 'SELECT id FROM suppliers WHERE product_code=? COLLATE NOCASE'
              : 'SELECT id FROM suppliers WHERE name=?',
          variables: [Variable.withString(code.isNotEmpty ? code : name)],
        )
        .get();
    if (rows.length != 1) {
      throw FormatException(
        'import_products.reference_missing'.tr(
          args: [code.isNotEmpty ? code : name],
        ),
      );
    }
    return rows.single.read<int>('id');
  }

  Future<int?> currency(String code, String legacyId) async {
    if (code.isEmpty) {
      if (legacyId.isNotEmpty) {
        throw FormatException('import_products.reference_required'.tr());
      }
      return null;
    }
    final rows = await db
        .customSelect(
          'SELECT id FROM currencies WHERE code=? COLLATE NOCASE AND is_active=1',
          variables: [Variable.withString(code)],
        )
        .get();
    if (rows.length != 1) {
      throw FormatException(
        'import_products.reference_missing'.tr(args: [code]),
      );
    }
    return rows.single.read<int>('id');
  }

  Future<void> importIdentities(
    String value,
    int productId,
    int variantId,
  ) async {
    if (value.isEmpty) return;
    final entries = jsonDecode(value) as List;
    final service = SupplierProductIdentityService(db);
    for (final entry in entries) {
      final item = Map<String, dynamic>.from(entry as Map);
      final code = item['supplier_code'] as String;
      final supplierId = await supplier(code, '', '');
      if (supplierId == null) {
        throw FormatException('import_products.reference_required'.tr());
      }
      final identity = await service.ensureIssued(
        supplierId: supplierId,
        productId: productId,
        variantId: variantId,
      );
      if (identity.baseSkuSnapshot != item['base_sku'] ||
          identity.sourceSku != item['source_sku']) {
        throw FormatException('import_products.identity_mismatch'.tr());
      }
    }
  }
}
