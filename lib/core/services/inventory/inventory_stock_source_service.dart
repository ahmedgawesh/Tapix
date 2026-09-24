import 'dart:convert';

import 'package:drift/drift.dart';

import '../../database/app_database.dart';
import '../business/warehouse_batch_scope.dart';
import '../business/warehouse_operation_scope.dart';

enum InventoryStockOwnership { enterprise, consignment, unverified }

class InventoryStockSourceBalance {
  const InventoryStockSourceBalance({
    required this.productId,
    required this.variantId,
    required this.quantity,
    required this.quantityScale,
    required this.measurementType,
    required this.ownership,
    required this.variantLabel,
    this.supplierId,
    this.supplierName,
    this.supplierIdentityId,
    this.consignmentLayerId,
    this.sourceCode,
    this.receiptNumber,
    this.batchId,
    this.batchNumber,
  });

  final int productId;
  final int variantId;
  final int quantity;
  final int quantityScale;
  final String measurementType;
  final InventoryStockOwnership ownership;
  final String variantLabel;
  final int? supplierId;
  final String? supplierName;
  final int? supplierIdentityId;
  final String? consignmentLayerId;
  final String? sourceCode;
  final String? receiptNumber;
  final int? batchId;
  final String? batchNumber;

  bool get isConsignment => ownership == InventoryStockOwnership.consignment;
  bool get isVerified =>
      supplierIdentityId != null || consignmentLayerId != null;
}

class ProductStockSourceSnapshot {
  const ProductStockSourceSnapshot({
    required this.productId,
    required this.warehouseId,
    required this.physicalQuantity,
    required this.enterpriseQuantity,
    required this.consignmentQuantity,
    required this.quantityScale,
    required this.measurementType,
    required this.sources,
    required this.reconciled,
  });

  final int productId;
  final String warehouseId;
  final int physicalQuantity;
  final int enterpriseQuantity;
  final int consignmentQuantity;
  final int quantityScale;
  final String measurementType;
  final List<InventoryStockSourceBalance> sources;
  final bool reconciled;
}

class StockSourceIntegrityException implements Exception {
  const StockSourceIntegrityException(this.messageKey);
  final String messageKey;

  @override
  String toString() => messageKey;
}

/// Read model for the physical stock ownership/provenance ledger.
///
/// It never derives ownership from the preferred supplier on the product card.
/// Standard/WAC items come from inventory_origin_states, batch-tracked items
/// come from product_batches, and supplier-owned quantities always come from
/// consignment_inventory_layers.
class InventoryStockSourceService {
  InventoryStockSourceService(this.db);

  final AppDatabase db;

  static String consignmentSourceCode(String layerId) => 'C-$layerId';

  Future<InventoryStockSourceBalance?> resolveConsignmentCode(
    String input, {
    WarehouseOperationScope? scope,
  }) async {
    final code = input.trim();
    if (!code.startsWith('C-') || code.length != 38) return null;
    final layerId = code.substring(2);
    final operation = scope ?? await WarehouseOperationScope.resolve(db);
    await operation.validate(db);
    final row = await db
        .customSelect(
          '''SELECT product_id,variant_id
         FROM consignment_inventory_layers
         WHERE id=? AND warehouse_id=? AND status='open'
           AND remaining_quantity>0''',
          variables: [
            Variable.withString(layerId),
            Variable.withString(operation.warehouseId),
          ],
          readsFrom: {db.consignmentInventoryLayers},
        )
        .getSingleOrNull();
    if (row == null) return null;
    final snapshot = await loadProduct(
      row.read<int>('product_id'),
      variantId: row.read<int>('variant_id'),
      scope: operation,
    );
    return snapshot.sources
        .where((source) => source.consignmentLayerId == layerId)
        .firstOrNull;
  }

  /// Resolves a consignment label to its immutable receipt reference, even
  /// when the layer is exhausted. This is used only to identify the original
  /// source for returns; sale availability still comes from [loadProduct].
  Future<InventoryStockSourceBalance?> resolveConsignmentCodeReference(
    String input, {
    WarehouseOperationScope? scope,
  }) async {
    final code = input.trim();
    if (!code.startsWith('C-') || code.length != 38) return null;
    final layerId = code.substring(2);
    final operation = scope ?? await WarehouseOperationScope.resolve(db);
    await operation.validate(db);
    final row = await db
        .customSelect(
          '''SELECT l.id,l.product_id,l.variant_id,l.supplier_id,
                s.name AS supplier_name,l.remaining_quantity,
                CASE WHEN p.measurement_type='piece' THEN 1 ELSE 1000 END AS quantity_scale,
                p.measurement_type,r.receipt_number,
                b.batch_number,pc.name AS color_name,sz.name AS size_name,
                COALESCE(v.sku,p.sku) AS sku
         FROM consignment_inventory_layers l
         JOIN suppliers s ON s.id=l.supplier_id
         JOIN consignment_receipt_items ri ON ri.id=l.receipt_item_id
         JOIN consignment_receipts r ON r.id=ri.receipt_id
         JOIN products p ON p.id=l.product_id
         JOIN product_variants v ON v.id=l.variant_id
         LEFT JOIN product_batches b ON b.id=l.batch_id
         LEFT JOIN product_colors pc ON pc.id=v.color_id
         LEFT JOIN sizes sz ON sz.id=v.size_id
         WHERE l.id=? AND l.warehouse_id=? AND l.status!='voided'
           AND r.status='posted' AND v.is_active=1''',
          variables: [
            Variable.withString(layerId),
            Variable.withString(operation.warehouseId),
          ],
          readsFrom: {
            db.consignmentInventoryLayers,
            db.consignmentReceiptItems,
            db.consignmentReceipts,
            db.suppliers,
            db.products,
            db.productVariants,
            db.productBatches,
            db.productColors,
            db.sizes,
          },
        )
        .getSingleOrNull();
    if (row == null) return null;
    return InventoryStockSourceBalance(
      productId: row.read<int>('product_id'),
      variantId: row.read<int>('variant_id'),
      supplierId: row.read<int>('supplier_id'),
      supplierName: row.read<String>('supplier_name'),
      quantity: row.read<int>('remaining_quantity'),
      quantityScale: row.read<int>('quantity_scale'),
      measurementType: row.read<String>('measurement_type'),
      ownership: InventoryStockOwnership.consignment,
      variantLabel: _variantLabel(row),
      consignmentLayerId: row.read<String>('id'),
      sourceCode: code,
      receiptNumber: row.read<String>('receipt_number'),
      batchNumber: row.readNullable<String>('batch_number'),
    );
  }

  Future<ProductStockSourceSnapshot> loadProduct(
    int productId, {
    int? variantId,
    WarehouseOperationScope? scope,
  }) async {
    final operation = scope ?? await WarehouseOperationScope.resolve(db);
    await operation.validate(db);

    final variantFilter = variantId == null ? '' : 'AND v.id=?';
    final variables = <Variable>[
      Variable.withString(operation.warehouseId),
      Variable.withInt(productId),
      if (variantId != null) Variable.withInt(variantId),
    ];
    final variants = await db
        .customSelect(
          '''SELECT v.id AS variant_id,
                COALESCE(ws.quantity,0) AS physical_quantity,
                COALESCE(ws.supplier_owned_quantity,0) AS supplier_owned_quantity,
                CASE WHEN p.measurement_type='piece' THEN 1 ELSE 1000 END AS quantity_scale,
                p.measurement_type,p.costing_method,
                p.inventory_tracking_type,pc.name AS color_name,sz.name AS size_name,
                COALESCE(v.sku,p.sku) AS sku
         FROM product_variants v
         JOIN products p ON p.id=v.product_id
         LEFT JOIN business_warehouse_stocks ws
           ON ws.variant_id=v.id AND ws.warehouse_id=?
         LEFT JOIN product_colors pc ON pc.id=v.color_id
         LEFT JOIN sizes sz ON sz.id=v.size_id
         WHERE v.product_id=? AND v.is_active=1 $variantFilter
         ORDER BY v.id''',
          variables: variables,
          readsFrom: {
            db.products,
            db.productVariants,
            db.businessWarehouseStocks,
            db.productColors,
            db.sizes,
          },
        )
        .get();

    if (variants.isEmpty) {
      throw const StockSourceIntegrityException(
        'stock_sources.no_operational_variant',
      );
    }

    final result = <InventoryStockSourceBalance>[];
    var physicalTotal = 0;
    var consignmentTotal = 0;
    var enterpriseTotal = 0;
    var reconciled = true;
    final measurementType = variants.first.read<String>('measurement_type');
    final quantityScale = variants.first.read<int>('quantity_scale');

    for (final variant in variants) {
      final resolvedVariantId = variant.read<int>('variant_id');
      final physical = variant.read<int>('physical_quantity');
      final supplierOwned = variant.read<int>('supplier_owned_quantity');
      if (physical < 0 || supplierOwned < 0 || supplierOwned > physical) {
        throw const StockSourceIntegrityException(
          'stock_sources.custody_balance_mismatch',
        );
      }
      physicalTotal += physical;
      consignmentTotal += supplierOwned;
      enterpriseTotal += physical - supplierOwned;
      final variantLabel = _variantLabel(variant);

      final consignment = await _loadConsignmentLayers(
        operation.warehouseId,
        productId,
        resolvedVariantId,
        quantityScale,
        measurementType,
        variantLabel,
      );
      final consignmentLayerTotal = consignment.fold<int>(
        0,
        (sum, source) => sum + source.quantity,
      );
      if (consignmentLayerTotal != supplierOwned) {
        throw const StockSourceIntegrityException(
          'stock_sources.custody_balance_mismatch',
        );
      }
      result.addAll(consignment);

      final isBatched =
          variant.read<String>('costing_method') == 'fifo' ||
          variant.read<String>('inventory_tracking_type') != 'standard';
      final ownedTarget = physical - supplierOwned;
      final owned = isBatched
          ? await _loadBatchOwnedSources(
              operation,
              productId,
              resolvedVariantId,
              quantityScale,
              measurementType,
              variantLabel,
            )
          : await _loadStandardOwnedSources(
              operation.warehouseId,
              productId,
              resolvedVariantId,
              physical,
              quantityScale,
              measurementType,
              variantLabel,
            );
      final ownedTotal = owned.fold<int>(
        0,
        (sum, source) => sum + source.quantity,
      );
      if (ownedTotal == ownedTarget) {
        result.addAll(owned);
      } else {
        // A stale/legacy provenance state must never be presented as a proven
        // supplier allocation. Keep the physical balance exact and explicit.
        reconciled = false;
        if (ownedTarget > 0) {
          result.add(
            InventoryStockSourceBalance(
              productId: productId,
              variantId: resolvedVariantId,
              quantity: ownedTarget,
              quantityScale: quantityScale,
              measurementType: measurementType,
              ownership: InventoryStockOwnership.unverified,
              variantLabel: variantLabel,
            ),
          );
        }
      }
    }

    final grouped = _group(result);
    final displayed = grouped.fold<int>(
      0,
      (sum, source) => sum + source.quantity,
    );
    if (displayed != physicalTotal) {
      throw const StockSourceIntegrityException(
        'stock_sources.physical_balance_mismatch',
      );
    }
    return ProductStockSourceSnapshot(
      productId: productId,
      warehouseId: operation.warehouseId,
      physicalQuantity: physicalTotal,
      enterpriseQuantity: enterpriseTotal,
      consignmentQuantity: consignmentTotal,
      quantityScale: quantityScale,
      measurementType: measurementType,
      sources: grouped,
      reconciled: reconciled,
    );
  }

  Future<List<InventoryStockSourceBalance>> _loadConsignmentLayers(
    String warehouseId,
    int productId,
    int variantId,
    int quantityScale,
    String measurementType,
    String variantLabel,
  ) async {
    final rows = await db
        .customSelect(
          '''SELECT l.id,l.batch_id,l.supplier_id,s.name AS supplier_name,l.remaining_quantity,
                r.receipt_number,b.batch_number
         FROM consignment_inventory_layers l
         JOIN suppliers s ON s.id=l.supplier_id
         JOIN consignment_receipt_items ri ON ri.id=l.receipt_item_id
         JOIN consignment_receipts r ON r.id=ri.receipt_id
         LEFT JOIN product_batches b ON b.id=l.batch_id
         WHERE l.warehouse_id=? AND l.product_id=? AND l.variant_id=?
           AND l.status='open' AND l.remaining_quantity>0
           AND r.status='posted'
         ORDER BY r.received_at,l.id''',
          variables: [
            Variable.withString(warehouseId),
            Variable.withInt(productId),
            Variable.withInt(variantId),
          ],
          readsFrom: {
            db.consignmentInventoryLayers,
            db.consignmentReceiptItems,
            db.consignmentReceipts,
            db.suppliers,
            db.productBatches,
          },
        )
        .get();
    return rows
        .map(
          (row) => InventoryStockSourceBalance(
            productId: productId,
            variantId: variantId,
            supplierId: row.read<int>('supplier_id'),
            supplierName: row.read<String>('supplier_name'),
            quantity: row.read<int>('remaining_quantity'),
            quantityScale: quantityScale,
            measurementType: measurementType,
            ownership: InventoryStockOwnership.consignment,
            variantLabel: variantLabel,
            consignmentLayerId: row.read<String>('id'),
            sourceCode: consignmentSourceCode(row.read<String>('id')),
            receiptNumber: row.read<String>('receipt_number'),
            batchId: row.readNullable<int>('batch_id'),
            batchNumber: row.readNullable<String>('batch_number'),
          ),
        )
        .toList(growable: false);
  }

  Future<List<InventoryStockSourceBalance>> _loadBatchOwnedSources(
    WarehouseOperationScope scope,
    int productId,
    int variantId,
    int quantityScale,
    String measurementType,
    String variantLabel,
  ) async {
    final rows = await db
        .customSelect(
          '''SELECT pb.id AS batch_id,pb.remaining_quantity,pb.batch_number,
                COALESCE(pb.supplier_id,pch.supplier_id) AS supplier_id,
                COALESCE(sp.name,ps.name) AS supplier_name,
                pi.supplier_identity_id,i.source_sku,
                l.id AS consignment_layer_id
         FROM product_batches pb
         LEFT JOIN purchase_items pi ON pi.id=pb.purchase_item_id
         LEFT JOIN purchases pch ON pch.id=pi.purchase_id
         LEFT JOIN suppliers ps ON ps.id=pch.supplier_id
         LEFT JOIN suppliers sp ON sp.id=pb.supplier_id
         LEFT JOIN supplier_product_identities i
           ON i.id=pi.supplier_identity_id
         LEFT JOIN consignment_inventory_layers l
           ON l.batch_id=pb.id AND l.warehouse_id=? AND l.status='open'
         WHERE pb.product_id=? AND pb.variant_id=? AND pb.is_active=1
           AND pb.remaining_quantity>0
           AND ${WarehouseBatchScope.operationPredicate('pb')}
         ORDER BY pb.received_date,pb.id''',
          variables: [
            Variable.withString(scope.warehouseId),
            Variable.withInt(productId),
            Variable.withInt(variantId),
            ...WarehouseBatchScope.operationVariables(scope),
          ],
          readsFrom: {
            db.productBatches,
            db.purchaseItems,
            db.purchases,
            db.suppliers,
            db.supplierProductIdentities,
            db.consignmentInventoryLayers,
          },
        )
        .get();
    return rows
        .where(
          (row) => row.readNullable<String>('consignment_layer_id') == null,
        )
        .map((row) {
          final identityId = row.readNullable<int>('supplier_identity_id');
          final supplierId = row.readNullable<int>('supplier_id');
          return InventoryStockSourceBalance(
            productId: productId,
            variantId: variantId,
            supplierId: supplierId,
            supplierName: row.readNullable<String>('supplier_name'),
            supplierIdentityId: identityId,
            sourceCode: row.readNullable<String>('source_sku'),
            quantity: row.read<int>('remaining_quantity'),
            quantityScale: quantityScale,
            measurementType: measurementType,
            ownership: supplierId == null && identityId == null
                ? InventoryStockOwnership.unverified
                : InventoryStockOwnership.enterprise,
            variantLabel: variantLabel,
            batchId: row.read<int>('batch_id'),
            batchNumber: row.readNullable<String>('batch_number'),
          );
        })
        .toList(growable: false);
  }

  Future<List<InventoryStockSourceBalance>> _loadStandardOwnedSources(
    String warehouseId,
    int productId,
    int variantId,
    int physicalQuantity,
    int quantityScale,
    String measurementType,
    String variantLabel,
  ) async {
    final state = await db
        .customSelect(
          'SELECT quantity,dirty,layers FROM inventory_origin_states '
          'WHERE warehouse_id=? AND variant_id=?',
          variables: [
            Variable.withString(warehouseId),
            Variable.withInt(variantId),
          ],
          readsFrom: {db.inventoryOriginStates},
        )
        .getSingleOrNull();
    if (state == null ||
        state.read<int>('dirty') != 0 ||
        state.read<int>('quantity') != physicalQuantity) {
      return const [];
    }
    final decoded = (jsonDecode(state.read<String>('layers')) as List)
        .map((value) => Map<String, dynamic>.from(value as Map))
        .toList(growable: false);
    final result = <InventoryStockSourceBalance>[];
    for (final layer in decoded) {
      final quantity = layer['q'] as int? ?? 0;
      if (quantity <= 0 || layer['k'] == 'consignment_receipt') continue;
      final identityId = layer['i'] as int?;
      final purchaseItemId = layer['p'] as int?;
      final source = await _resolveOwnedSource(
        identityId: identityId,
        purchaseItemId: purchaseItemId,
      );
      result.add(
        InventoryStockSourceBalance(
          productId: productId,
          variantId: variantId,
          supplierId: source?.supplierId,
          supplierName: source?.supplierName,
          supplierIdentityId: source?.identityId,
          sourceCode: source?.sourceSku,
          quantity: quantity,
          quantityScale: quantityScale,
          measurementType: measurementType,
          ownership: source == null
              ? InventoryStockOwnership.unverified
              : InventoryStockOwnership.enterprise,
          variantLabel: variantLabel,
        ),
      );
    }
    return result;
  }

  Future<
    ({int supplierId, String supplierName, int? identityId, String? sourceSku})?
  >
  _resolveOwnedSource({int? identityId, int? purchaseItemId}) async {
    if (identityId != null) {
      final identity = await db
          .customSelect(
            '''SELECT i.supplier_id,s.name AS supplier_name,i.id AS identity_id,
                  i.source_sku
           FROM supplier_product_identities i
           JOIN suppliers s ON s.id=i.supplier_id
           WHERE i.id=?''',
            variables: [Variable.withInt(identityId)],
            readsFrom: {db.supplierProductIdentities, db.suppliers},
          )
          .getSingleOrNull();
      if (identity == null) return null;
      return (
        supplierId: identity.read<int>('supplier_id'),
        supplierName: identity.read<String>('supplier_name'),
        identityId: identity.read<int>('identity_id'),
        sourceSku: identity.read<String>('source_sku'),
      );
    }
    if (purchaseItemId == null) return null;
    final row = await db
        .customSelect(
          '''SELECT pch.supplier_id,s.name AS supplier_name,
                i.id AS identity_id,i.source_sku
         FROM purchase_items pi
         JOIN purchases pch ON pch.id=pi.purchase_id
         JOIN suppliers s ON s.id=pch.supplier_id
         LEFT JOIN supplier_product_identities i
           ON i.id=pi.supplier_identity_id
         WHERE pi.id=? LIMIT 1''',
          variables: [Variable.withInt(purchaseItemId)],
          readsFrom: {
            db.purchaseItems,
            db.purchases,
            db.suppliers,
            db.supplierProductIdentities,
          },
        )
        .getSingleOrNull();
    if (row == null) return null;
    return (
      supplierId: row.read<int>('supplier_id'),
      supplierName: row.read<String>('supplier_name'),
      identityId: row.readNullable<int>('identity_id'),
      sourceSku: row.readNullable<String>('source_sku'),
    );
  }

  List<InventoryStockSourceBalance> _group(
    List<InventoryStockSourceBalance> sources,
  ) {
    final grouped = <String, InventoryStockSourceBalance>{};
    for (final source in sources) {
      final key = source.consignmentLayerId != null
          ? 'c:${source.consignmentLayerId}'
          : source.supplierIdentityId != null
          ? 'i:${source.supplierIdentityId}'
          : 'u:${source.variantId}:${source.supplierId ?? 0}:${source.batchId ?? 0}:${source.batchNumber ?? ''}';
      final old = grouped[key];
      grouped[key] = old == null
          ? source
          : InventoryStockSourceBalance(
              productId: source.productId,
              variantId: source.variantId,
              quantity: old.quantity + source.quantity,
              quantityScale: source.quantityScale,
              measurementType: source.measurementType,
              ownership: source.ownership,
              variantLabel: source.variantLabel,
              supplierId: source.supplierId,
              supplierName: source.supplierName,
              supplierIdentityId: source.supplierIdentityId,
              consignmentLayerId: source.consignmentLayerId,
              sourceCode: source.sourceCode,
              receiptNumber: source.receiptNumber,
              batchId: source.batchId,
              batchNumber: old.batchNumber == source.batchNumber
                  ? source.batchNumber
                  : null,
            );
    }
    final result = grouped.values.toList(growable: false);
    result.sort((a, b) {
      final ownership = a.ownership.index.compareTo(b.ownership.index);
      if (ownership != 0) return ownership;
      final supplier = (a.supplierName ?? '').compareTo(b.supplierName ?? '');
      if (supplier != 0) return supplier;
      return (a.sourceCode ?? '').compareTo(b.sourceCode ?? '');
    });
    return result;
  }

  String _variantLabel(QueryRow row) {
    final parts = <String>[
      if (row.readNullable<String>('color_name')?.trim().isNotEmpty == true)
        row.read<String>('color_name').trim(),
      if (row.readNullable<String>('size_name')?.trim().isNotEmpty == true)
        row.read<String>('size_name').trim(),
    ];
    if (parts.isNotEmpty) return parts.join(' / ');
    return row.readNullable<String>('sku')?.trim() ?? '';
  }
}
