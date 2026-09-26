import 'dart:convert';

import 'package:drift/drift.dart';

import '../../database/app_database.dart';
import 'offline_sync_event_store.dart';
import 'sync_entity_identity_store.dart';

/// Immutable transport contract for a completed sale.
///
/// The contract keeps commercial amounts, inventory provenance and supplier
/// ownership as separate ledgers. Local integer identifiers are carried only
/// inside a source-database-qualified reference; master data uses global IDs.
class SaleSyncContractBuilder {
  const SaleSyncContractBuilder(this.db, this.identities);

  final AppDatabase db;
  final SyncEntityIdentityStore identities;

  Future<Map<String, Object?>> buildPostedSale({
    required Sale sale,
    required int? actorUserId,
  }) async {
    if (sale.status != 'completed') {
      throw const OfflineSyncException(
        'sale_not_completed',
        'Only a completed sale can produce a synchronization event.',
      );
    }
    final location = await _location('sales', sale.id);
    final localDatabaseId = await _localDatabaseId();
    if (location.originDatabaseId != localDatabaseId) {
      throw const OfflineSyncException(
        'sale_database_identity_mismatch',
        'The sale belongs to another source database.',
      );
    }
    final currency = await (db.select(
      db.currencies,
    )..where((row) => row.id.equals(sale.currencyId))).getSingle();
    final customerGlobalId = sale.customerId == null
        ? null
        : (await identities.getOrCreateLocal(
            entityType: 'customer',
            localId: sale.customerId!,
          )).globalId;
    final rows =
        await (db.select(db.saleItems)
              ..where((row) => row.saleId.equals(sale.id))
              ..orderBy([(row) => OrderingTerm.asc(row.id)]))
            .get();
    if (rows.isEmpty) {
      throw const OfflineSyncException(
        'sale_items_missing',
        'A completed sale must contain at least one item.',
      );
    }

    final items = <Map<String, Object?>>[];
    var subtotal = 0;
    var discount = 0;
    var tax = 0;
    var total = 0;
    var ownedInventoryValue = 0;
    for (final item in rows) {
      subtotal += item.subtotalCents.toBigInt().toInt();
      discount += item.discountCents.toBigInt().toInt();
      tax += item.taxCents.toBigInt().toInt();
      total += item.totalCents.toBigInt().toInt();
      ownedInventoryValue +=
          item.inventoryValueAtPostCents?.toBigInt().toInt() ?? 0;
      items.add(
        await _buildItem(
          item: item,
          warehouseId: location.warehouseId,
          localDatabaseId: localDatabaseId,
        ),
      );
    }
    if (subtotal != sale.subtotalCents.toBigInt().toInt() ||
        discount != sale.discountCents.toBigInt().toInt() ||
        tax != sale.taxCents.toBigInt().toInt() ||
        total != sale.totalCents.toBigInt().toInt()) {
      throw const OfflineSyncException(
        'sale_money_mismatch',
        'The sale line amounts do not match the completed sale.',
      );
    }

    final payments =
        await (db.select(db.salePayments)
              ..where((row) => row.saleId.equals(sale.id))
              ..orderBy([(row) => OrderingTerm.asc(row.id)]))
            .get();
    return {
      'contract': 'sale.posted',
      'contractVersion': 1,
      'documentId': location.documentId,
      'sourceDocumentRef': {
        'databaseId': localDatabaseId,
        'table': 'sales',
        'localId': sale.id,
      },
      'organizationId': location.organizationId,
      'branchId': location.branchId,
      'warehouseId': location.warehouseId,
      'invoiceNumber': sale.invoiceNumber,
      'saleDate': sale.saleDate.toUtc().toIso8601String(),
      'dueDate': sale.dueDate?.toUtc().toIso8601String(),
      'customerGlobalId': ?customerGlobalId,
      'employeeRef': sale.employeeId == null
          ? null
          : {'databaseId': localDatabaseId, 'localId': sale.employeeId},
      'cashierShiftRef': sale.cashierShiftId == null
          ? null
          : {'databaseId': localDatabaseId, 'localId': sale.cashierShiftId},
      'actorRef': actorUserId == null
          ? null
          : {'databaseId': localDatabaseId, 'localId': actorUserId},
      'currencyCode': currency.code,
      'paymentMethod': sale.paymentMethod,
      'subtotalMinor': sale.subtotalCents.toBigInt().toInt(),
      'discountMinor': sale.discountCents.toBigInt().toInt(),
      'taxMinor': sale.taxCents.toBigInt().toInt(),
      'totalMinor': sale.totalCents.toBigInt().toInt(),
      'paidMinor': sale.paidAmountCents.toBigInt().toInt(),
      'ownedInventoryValueMinor': ownedInventoryValue,
      'pricing': {
        'engineVersion': sale.pricingEngineVersion,
        'taxInclusive': sale.taxInclusiveAtPost,
        'roundingMode': sale.roundingModeAtPost,
      },
      'notes': sale.notes,
      'payments': [
        for (final payment in payments)
          {
            'paymentRef': {
              'databaseId': localDatabaseId,
              'localId': payment.id,
            },
            'amountMinor': payment.amountCents.toBigInt().toInt(),
            'currencyCode': currency.code,
            'method': payment.paymentMethod,
            'reference': payment.reference,
            'paymentDate': payment.paymentDate.toUtc().toIso8601String(),
          },
      ],
      'itemCount': items.length,
      'items': items,
    };
  }

  /// Builds the immutable contract for a return that is backed by an
  /// original sale. Commercial credit, physical inventory disposition and
  /// supplier obligation reversals remain separate in the payload.
  Future<Map<String, Object?>> buildPostedLinkedReturn({
    required SaleReturn saleReturn,
    required int? actorUserId,
  }) async {
    if (saleReturn.status != 'posted') {
      throw const OfflineSyncException(
        'sale_return_not_posted',
        'Only a posted sale return can produce a synchronization event.',
      );
    }
    final location = await _location('sale_returns', saleReturn.id);
    final sourceLocation = await _location('sales', saleReturn.saleId);
    final localDatabaseId = await _localDatabaseId();
    if (location.originDatabaseId != localDatabaseId ||
        sourceLocation.originDatabaseId != localDatabaseId) {
      throw const OfflineSyncException(
        'sale_return_database_identity_mismatch',
        'The return and its source sale must belong to the local database.',
      );
    }
    final originalSale = await (db.select(
      db.sales,
    )..where((row) => row.id.equals(saleReturn.saleId))).getSingle();
    final currency = await (db.select(
      db.currencies,
    )..where((row) => row.id.equals(saleReturn.currencyId))).getSingle();
    final customerGlobalId = originalSale.customerId == null
        ? null
        : (await identities.getOrCreateLocal(
            entityType: 'customer',
            localId: originalSale.customerId!,
          )).globalId;
    final rows =
        await (db.select(db.saleReturnItems)
              ..where((row) => row.returnId.equals(saleReturn.id))
              ..orderBy([(row) => OrderingTerm.asc(row.id)]))
            .get();
    if (rows.isEmpty) {
      throw const OfflineSyncException(
        'sale_return_items_missing',
        'A posted sale return must contain at least one item.',
      );
    }

    final restoresStock = !const {
      'write_off',
      'damaged',
      'scrap',
    }.contains(saleReturn.dispositionType);
    final items = <Map<String, Object?>>[];
    var subtotal = 0;
    var discount = 0;
    var tax = 0;
    var total = 0;
    var ownedInventoryValue = 0;
    for (final item in rows) {
      subtotal += item.subtotalCents.toBigInt().toInt();
      discount += item.discountCents.toBigInt().toInt();
      tax += item.taxCents.toBigInt().toInt();
      total += item.refundCents.toBigInt().toInt();
      ownedInventoryValue +=
          item.inventoryValueAtPostCents?.toBigInt().toInt() ?? 0;
      items.add(
        await _buildReturnItem(
          item: item,
          warehouseId: location.warehouseId,
          localDatabaseId: localDatabaseId,
          restoresStock: restoresStock,
        ),
      );
    }
    if (subtotal != saleReturn.subtotalCents.toBigInt().toInt() ||
        discount != saleReturn.discountCents.toBigInt().toInt() ||
        tax != saleReturn.taxCents.toBigInt().toInt() ||
        total != saleReturn.totalCents.toBigInt().toInt()) {
      throw const OfflineSyncException(
        'sale_return_money_mismatch',
        'The return line amounts do not match the posted return.',
      );
    }

    return {
      'contract': 'sale_return.posted',
      'contractVersion': 1,
      'documentId': location.documentId,
      'sourceDocumentRef': {
        'databaseId': localDatabaseId,
        'table': 'sale_returns',
        'localId': saleReturn.id,
      },
      'originalSaleDocumentId': sourceLocation.documentId,
      'originalSaleRef': {
        'databaseId': localDatabaseId,
        'table': 'sales',
        'localId': saleReturn.saleId,
      },
      'organizationId': location.organizationId,
      'branchId': location.branchId,
      'warehouseId': location.warehouseId,
      'returnNumber': saleReturn.returnNumber,
      'returnDate': saleReturn.returnDate.toUtc().toIso8601String(),
      'dueDate': saleReturn.dueDate?.toUtc().toIso8601String(),
      'customerGlobalId': ?customerGlobalId,
      'cashierShiftRef': saleReturn.cashierShiftId == null
          ? null
          : {
              'databaseId': localDatabaseId,
              'localId': saleReturn.cashierShiftId,
            },
      'actorRef': actorUserId == null
          ? null
          : {'databaseId': localDatabaseId, 'localId': actorUserId},
      'currencyCode': currency.code,
      'refundMethod': saleReturn.refundMethod,
      'dispositionType': saleReturn.dispositionType,
      'restoresSellableStock': restoresStock,
      'subtotalMinor': saleReturn.subtotalCents.toBigInt().toInt(),
      'discountMinor': saleReturn.discountCents.toBigInt().toInt(),
      'taxMinor': saleReturn.taxCents.toBigInt().toInt(),
      'totalMinor': saleReturn.totalCents.toBigInt().toInt(),
      'ownedInventoryValueMinor': ownedInventoryValue,
      'pricing': {
        'engineVersion': saleReturn.pricingEngineVersion,
        'taxInclusive': saleReturn.taxInclusiveAtPost,
        'roundingMode': saleReturn.roundingModeAtPost,
      },
      'reason': saleReturn.reason,
      'itemCount': items.length,
      'items': items,
    };
  }

  Future<Map<String, Object?>> _buildReturnItem({
    required SaleReturnItem item,
    required String warehouseId,
    required String localDatabaseId,
    required bool restoresStock,
  }) async {
    if (item.quantity <= 0 || item.quantityScale <= 0) {
      throw const OfflineSyncException(
        'invalid_sale_return_quantity',
        'A posted sale return line has an invalid quantity.',
      );
    }
    final saleItem = await (db.select(
      db.saleItems,
    )..where((row) => row.id.equals(item.saleItemId))).getSingle();
    if (saleItem.quantityScale != item.quantityScale ||
        saleItem.measurementType != item.measurementType) {
      throw const OfflineSyncException(
        'sale_return_unit_mismatch',
        'A return line no longer matches the unit used by its source sale.',
      );
    }
    final product = await (db.select(
      db.products,
    )..where((row) => row.id.equals(saleItem.productId))).getSingle();
    final productIdentity = await identities.getOrCreateLocal(
      entityType: 'product',
      localId: saleItem.productId,
    );
    final variantIdentity = saleItem.variantId == null
        ? null
        : await identities.getOrCreateLocal(
            entityType: 'product_variant',
            localId: saleItem.variantId!,
          );
    final batches = product.trackInventory && restoresStock
        ? await _returnBatchSources(item, localDatabaseId)
        : const <Map<String, Object?>>[];
    final origins = product.trackInventory && restoresStock && batches.isEmpty
        ? await _returnOriginSources(item, warehouseId, localDatabaseId)
        : const <Map<String, Object?>>[];
    if (product.trackInventory &&
        restoresStock &&
        batches.isEmpty &&
        origins.isEmpty) {
      throw const OfflineSyncException(
        'sale_return_inventory_source_missing',
        'A restocked return line has no inventory provenance.',
      );
    }
    final restoredQuantity = batches.isNotEmpty
        ? batches.fold<int>(
            0,
            (sum, row) => sum + (row['quantityScaled']! as int),
          )
        : origins.fold<int>(
            0,
            (sum, row) => sum + (row['quantityScaled']! as int),
          );
    if (product.trackInventory &&
        restoresStock &&
        restoredQuantity != item.quantity) {
      throw const OfflineSyncException(
        'sale_return_inventory_quantity_mismatch',
        'The restored source quantities do not equal the return quantity.',
      );
    }

    final reversals =
        await (db.select(db.consignmentObligationEvents)
              ..where(
                (row) =>
                    row.sourceTable.equals('sale_returns') &
                    row.sourceId.equals(item.returnId) &
                    row.sourceItemId.equals(item.id) &
                    row.kind.equals('linked_return_reversal'),
              )
              ..orderBy([(row) => OrderingTerm.asc(row.id)]))
            .get();
    var consignmentQuantity = 0;
    final reversalPayload = <Map<String, Object?>>[];
    for (final reversal in reversals) {
      if (reversal.signedQuantity >= 0 || reversal.signedAmountCents > 0) {
        throw const OfflineSyncException(
          'invalid_consignment_return_reversal',
          'A consignment return reversal has an invalid sign.',
        );
      }
      if (reversal.restoresStock != restoresStock) {
        throw const OfflineSyncException(
          'consignment_return_disposition_mismatch',
          'A consignment reversal disagrees with the return disposition.',
        );
      }
      if (reversal.signedAmountCents != 0 && reversal.journalEntryId == null) {
        throw const OfflineSyncException(
          'consignment_return_journal_missing',
          'A consignment return reversal has no posted journal.',
        );
      }
      consignmentQuantity += -reversal.signedQuantity;
      final supplier = await identities.getOrCreateLocal(
        entityType: 'supplier',
        localId: reversal.supplierId,
      );
      reversalPayload.add({
        'eventRef': {'databaseId': localDatabaseId, 'localId': reversal.id},
        'allocationId': reversal.allocationId,
        'agreementId': reversal.agreementId,
        'supplierGlobalId': supplier.globalId,
        'signedQuantityScaled': reversal.signedQuantity,
        'signedObligationMinor': reversal.signedAmountCents,
        'restoresSellableStock': reversal.restoresStock,
        'settlementStatus': reversal.settlementStatus,
        if (reversal.journalEntryId != null)
          'journalRef': {
            'databaseId': localDatabaseId,
            'localId': reversal.journalEntryId,
          },
      });
    }
    if (consignmentQuantity > item.quantity) {
      throw const OfflineSyncException(
        'sale_return_consignment_quantity_mismatch',
        'Consignment reversals exceed the returned quantity.',
      );
    }

    return {
      'lineRef': {'databaseId': localDatabaseId, 'localId': item.id},
      'sourceSaleLineRef': {
        'databaseId': localDatabaseId,
        'localId': item.saleItemId,
      },
      'productGlobalId': productIdentity.globalId,
      'variantGlobalId': variantIdentity?.globalId,
      'quantityScaled': item.quantity,
      'quantityScale': item.quantityScale,
      'measurementType': item.measurementType,
      'subtotalMinor': item.subtotalCents.toBigInt().toInt(),
      'discountMinor': item.discountCents.toBigInt().toInt(),
      'taxMinor': item.taxCents.toBigInt().toInt(),
      'refundMinor': item.refundCents.toBigInt().toInt(),
      'ownedUnitCostMinor': item.unitCostAtPostCents?.toBigInt().toInt(),
      'ownedInventoryValueMinor':
          item.inventoryValueAtPostCents?.toBigInt().toInt() ?? 0,
      'inventoryEffect': !product.trackInventory
          ? 'not_tracked'
          : !restoresStock
          ? 'not_restocked'
          : batches.isNotEmpty
          ? 'batch_restored'
          : 'wac_origin_restored',
      'originSlices': origins,
      'batchRestorations': batches,
      'consignmentQuantityScaled': consignmentQuantity,
      'consignmentReversals': reversalPayload,
      'reason': item.reason,
    };
  }

  Future<List<Map<String, Object?>>> _returnBatchSources(
    SaleReturnItem item,
    String localDatabaseId,
  ) async {
    final rows = await db
        .customSelect(
          'SELECT bc.batch_id,bc.quantity,bc.unit_cost_cents,b.supplier_id,'
          'b.purchase_item_id FROM batch_consumptions bc '
          'JOIN product_batches b ON b.id=bc.batch_id '
          "WHERE bc.sale_return_item_id=? AND bc.direction='in' "
          "AND bc.consumption_type='sale_return_reverse' ORDER BY bc.id",
          variables: [Variable.withInt(item.id)],
        )
        .get();
    final result = <Map<String, Object?>>[];
    for (final row in rows) {
      final batch = await identities.getOrCreateLocal(
        entityType: 'product_batch',
        localId: row.read<int>('batch_id'),
      );
      final supplierId = row.readNullable<int>('supplier_id');
      final purchaseItemId = row.readNullable<int>('purchase_item_id');
      result.add({
        'batchGlobalId': batch.globalId,
        'batchOriginDatabaseId': batch.originDatabaseId,
        'quantityScaled': row.read<int>('quantity'),
        'unitCostMinor': row.read<int>('unit_cost_cents'),
        'supplierGlobalId': supplierId == null
            ? null
            : (await identities.getOrCreateLocal(
                entityType: 'supplier',
                localId: supplierId,
              )).globalId,
        if (purchaseItemId != null)
          'purchaseLineRef': {
            'databaseId': localDatabaseId,
            'localId': purchaseItemId,
          },
      });
    }
    return result;
  }

  Future<List<Map<String, Object?>>> _returnOriginSources(
    SaleReturnItem item,
    String warehouseId,
    String localDatabaseId,
  ) async {
    final row = await db
        .customSelect(
          'SELECT delta,allocations FROM inventory_origin_events '
          'WHERE warehouse_id=? AND event_key=?',
          variables: [
            Variable.withString(warehouseId),
            Variable.withString('return:${item.id}'),
          ],
        )
        .getSingleOrNull();
    if (row == null || row.read<int>('delta') != item.quantity) {
      throw const OfflineSyncException(
        'sale_return_origin_event_mismatch',
        'The WAC return source event is missing or has a different quantity.',
      );
    }
    final decoded = jsonDecode(row.read<String>('allocations'));
    if (decoded is! List) {
      throw const OfflineSyncException(
        'invalid_sale_return_origin',
        'The WAC return source allocation is not a list.',
      );
    }
    final result = <Map<String, Object?>>[];
    for (final value in decoded) {
      if (value is! Map) {
        throw const OfflineSyncException(
          'invalid_sale_return_origin',
          'A WAC return source slice is invalid.',
        );
      }
      final part = value.map((key, value) => MapEntry(key.toString(), value));
      final quantity = part['q'];
      if (quantity is! int || quantity <= 0) {
        throw const OfflineSyncException(
          'invalid_sale_return_origin',
          'A WAC return source quantity is invalid.',
        );
      }
      final purchaseItemId = part['p'] is int ? part['p'] as int : null;
      final supplierIdentityId = part['i'] is int ? part['i'] as int : null;
      final supplierId = await _originSupplier(
        purchaseItemId: purchaseItemId,
        supplierIdentityId: supplierIdentityId,
      );
      result.add({
        'quantityScaled': quantity,
        'originKind': part['k']?.toString() ?? 'unknown',
        'supplierGlobalId': supplierId == null
            ? null
            : (await identities.getOrCreateLocal(
                entityType: 'supplier',
                localId: supplierId,
              )).globalId,
        if (purchaseItemId != null)
          'purchaseLineRef': {
            'databaseId': localDatabaseId,
            'localId': purchaseItemId,
          },
        if (part['r'] != null) 'sourceReference': part['r'].toString(),
        'sourceQuality': supplierId == null ? 'unverified' : 'documented',
      });
    }
    return result;
  }

  Future<Map<String, Object?>> _buildItem({
    required SaleItem item,
    required String warehouseId,
    required String localDatabaseId,
  }) async {
    if (item.quantity <= 0 || item.quantityScale <= 0) {
      throw const OfflineSyncException(
        'invalid_sale_quantity',
        'A completed sale line has an invalid quantity.',
      );
    }
    final product = await (db.select(
      db.products,
    )..where((row) => row.id.equals(item.productId))).getSingle();
    final productIdentity = await identities.getOrCreateLocal(
      entityType: 'product',
      localId: item.productId,
    );
    final variantIdentity = item.variantId == null
        ? null
        : await identities.getOrCreateLocal(
            entityType: 'product_variant',
            localId: item.variantId!,
          );
    final selectedSupplier = await _selectedSupplier(item.supplierIdentityId);
    final batches = await _batchSources(item, localDatabaseId);
    final origins = batches.isEmpty && product.trackInventory
        ? await _originSources(item, warehouseId, localDatabaseId)
        : const <Map<String, Object?>>[];
    if (product.trackInventory && batches.isEmpty && origins.isEmpty) {
      throw const OfflineSyncException(
        'sale_inventory_source_missing',
        'The completed sale line has no inventory provenance.',
      );
    }
    if (batches.isNotEmpty &&
        batches.fold<int>(
              0,
              (sum, row) => sum + (row['quantityScaled']! as int),
            ) !=
            item.quantity) {
      throw const OfflineSyncException(
        'sale_batch_quantity_mismatch',
        'The sale batch quantities do not equal the sold quantity.',
      );
    }

    final consignment =
        await (db.select(db.consignmentSaleAllocations)
              ..where((row) => row.saleItemId.equals(item.id))
              ..orderBy([(row) => OrderingTerm.asc(row.sequence)]))
            .get();
    var consignmentQuantity = 0;
    final consignmentPayload = <Map<String, Object?>>[];
    for (final allocation in consignment) {
      if (allocation.quantityScale != item.quantityScale ||
          allocation.measurementType != item.measurementType) {
        throw const OfflineSyncException(
          'sale_consignment_unit_mismatch',
          'A consignment allocation no longer matches its sale line.',
        );
      }
      consignmentQuantity += allocation.quantity;
      final supplierGlobalId = (await identities.getOrCreateLocal(
        entityType: 'supplier',
        localId: allocation.supplierId,
      )).globalId;
      consignmentPayload.add({
        'allocationId': allocation.id,
        'layerId': allocation.layerId,
        'agreementId': allocation.agreementId,
        'sequence': allocation.sequence,
        'supplierGlobalId': supplierGlobalId,
        'quantityScaled': allocation.quantity,
        'quantityScale': allocation.quantityScale,
        'measurementType': allocation.measurementType,
        'settlementBasis': allocation.settlementBasis,
        'unitCostMinor': allocation.unitCostCents,
        'supplierShareBps': allocation.supplierShareBps,
        'includeLineDiscount': allocation.includeLineDiscount,
        'includeInvoiceDiscount': allocation.includeInvoiceDiscount,
        'includeSalesTax': allocation.includeSalesTax,
        'allocatedSubtotalMinor': allocation.allocatedSubtotalCents,
        'allocatedLineDiscountMinor': allocation.allocatedLineDiscountCents,
        'allocatedInvoiceDiscountMinor':
            allocation.allocatedInvoiceDiscountCents,
        'allocatedTaxMinor': allocation.allocatedTaxCents,
        'settlementBaseMinor': allocation.settlementBaseCents,
        'obligationMinor': allocation.obligationCents,
      });
    }
    if (consignmentQuantity > item.quantity) {
      throw const OfflineSyncException(
        'sale_consignment_quantity_mismatch',
        'Consignment allocations exceed the sold quantity.',
      );
    }

    return {
      'lineRef': {'databaseId': localDatabaseId, 'localId': item.id},
      'productGlobalId': productIdentity.globalId,
      'variantGlobalId': variantIdentity?.globalId,
      'selectedSupplier': selectedSupplier,
      'quantityScaled': item.quantity,
      'quantityScale': item.quantityScale,
      'measurementType': item.measurementType,
      'unitPriceMinor': item.unitPriceCents.toBigInt().toInt(),
      'subtotalMinor': item.subtotalCents.toBigInt().toInt(),
      'discountMinor': item.discountCents.toBigInt().toInt(),
      'itemDiscountMinor': item.itemDiscountAtPostCents?.toBigInt().toInt(),
      'invoiceDiscountMinor': item.invoiceDiscountAtPostCents
          ?.toBigInt()
          .toInt(),
      'taxMinor': item.taxCents.toBigInt().toInt(),
      'totalMinor': item.totalCents.toBigInt().toInt(),
      'ownedUnitCostMinor': item.costCents?.toBigInt().toInt(),
      'ownedInventoryValueMinor':
          item.inventoryValueAtPostCents?.toBigInt().toInt() ?? 0,
      'inventorySourceMode': !product.trackInventory
          ? 'not_tracked'
          : batches.isNotEmpty
          ? 'batch'
          : 'wac_origin',
      'originSlices': origins,
      'batchConsumptions': batches,
      'consignmentQuantityScaled': consignmentQuantity,
      'consignmentAllocations': consignmentPayload,
    };
  }

  Future<Map<String, Object?>?> _selectedSupplier(int? identityId) async {
    if (identityId == null) return null;
    final row = await db
        .customSelect(
          'SELECT supplier_id,source_sku FROM supplier_product_identities '
          'WHERE id=?',
          variables: [Variable.withInt(identityId)],
        )
        .getSingleOrNull();
    if (row == null) {
      throw const OfflineSyncException(
        'sale_supplier_identity_missing',
        'The selected supplier identity no longer exists.',
      );
    }
    final supplier = await identities.getOrCreateLocal(
      entityType: 'supplier',
      localId: row.read<int>('supplier_id'),
    );
    return {
      'supplierGlobalId': supplier.globalId,
      'sourceSku': row.read<String>('source_sku'),
    };
  }

  Future<List<Map<String, Object?>>> _batchSources(
    SaleItem item,
    String localDatabaseId,
  ) async {
    final rows = await db
        .customSelect(
          'SELECT bc.batch_id,bc.quantity,bc.unit_cost_cents,b.supplier_id,'
          'b.purchase_item_id FROM batch_consumptions bc '
          'JOIN product_batches b ON b.id=bc.batch_id '
          "WHERE bc.sale_item_id=? AND bc.direction='out' "
          "AND bc.consumption_type='sale' ORDER BY bc.id",
          variables: [Variable.withInt(item.id)],
        )
        .get();
    final result = <Map<String, Object?>>[];
    for (final row in rows) {
      final batchId = row.read<int>('batch_id');
      final batch = await identities.getOrCreateLocal(
        entityType: 'product_batch',
        localId: batchId,
      );
      final supplierId = row.readNullable<int>('supplier_id');
      final purchaseItemId = row.readNullable<int>('purchase_item_id');
      result.add({
        'batchGlobalId': batch.globalId,
        'batchOriginDatabaseId': batch.originDatabaseId,
        'quantityScaled': row.read<int>('quantity'),
        'unitCostMinor': row.read<int>('unit_cost_cents'),
        'supplierGlobalId': supplierId == null
            ? null
            : (await identities.getOrCreateLocal(
                entityType: 'supplier',
                localId: supplierId,
              )).globalId,
        if (purchaseItemId != null)
          'purchaseLineRef': {
            'databaseId': localDatabaseId,
            'localId': purchaseItemId,
          },
      });
    }
    return result;
  }

  Future<List<Map<String, Object?>>> _originSources(
    SaleItem item,
    String warehouseId,
    String localDatabaseId,
  ) async {
    final row = await db
        .customSelect(
          'SELECT delta,allocations FROM inventory_origin_events '
          'WHERE warehouse_id=? AND event_key=?',
          variables: [
            Variable.withString(warehouseId),
            Variable.withString('sale:${item.id}'),
          ],
        )
        .getSingleOrNull();
    if (row == null || row.read<int>('delta') != -item.quantity) {
      throw const OfflineSyncException(
        'sale_origin_event_mismatch',
        'The WAC source event is missing or has a different quantity.',
      );
    }
    final decoded = jsonDecode(row.read<String>('allocations'));
    if (decoded is! List) {
      throw const OfflineSyncException(
        'invalid_sale_origin',
        'The WAC source allocation is not a list.',
      );
    }
    final result = <Map<String, Object?>>[];
    var quantity = 0;
    for (final value in decoded) {
      if (value is! Map) {
        throw const OfflineSyncException(
          'invalid_sale_origin',
          'A WAC source slice is invalid.',
        );
      }
      final part = value.map((key, item) => MapEntry(key.toString(), item));
      final partQuantity = part['q'];
      if (partQuantity is! int || partQuantity <= 0) {
        throw const OfflineSyncException(
          'invalid_sale_origin',
          'A WAC source quantity is invalid.',
        );
      }
      quantity += partQuantity;
      final purchaseItemId = part['p'] is int ? part['p'] as int : null;
      final supplierIdentityId = part['i'] is int ? part['i'] as int : null;
      final supplierId = await _originSupplier(
        purchaseItemId: purchaseItemId,
        supplierIdentityId: supplierIdentityId,
      );
      result.add({
        'quantityScaled': partQuantity,
        'originKind': part['k']?.toString() ?? 'unknown',
        'supplierGlobalId': supplierId == null
            ? null
            : (await identities.getOrCreateLocal(
                entityType: 'supplier',
                localId: supplierId,
              )).globalId,
        if (purchaseItemId != null)
          'purchaseLineRef': {
            'databaseId': localDatabaseId,
            'localId': purchaseItemId,
          },
        if (part['r'] != null) 'sourceReference': part['r'].toString(),
        'sourceQuality': supplierId == null ? 'unverified' : 'documented',
      });
    }
    if (quantity != item.quantity) {
      throw const OfflineSyncException(
        'sale_origin_quantity_mismatch',
        'The WAC source slices do not equal the sold quantity.',
      );
    }
    return result;
  }

  Future<int?> _originSupplier({
    required int? purchaseItemId,
    required int? supplierIdentityId,
  }) async {
    int? identitySupplier;
    if (supplierIdentityId != null) {
      identitySupplier = await db
          .customSelect(
            'SELECT supplier_id FROM supplier_product_identities WHERE id=?',
            variables: [Variable.withInt(supplierIdentityId)],
          )
          .map((row) => row.read<int>('supplier_id'))
          .getSingleOrNull();
      if (identitySupplier == null) {
        throw const OfflineSyncException(
          'sale_supplier_identity_missing',
          'A WAC supplier identity no longer exists.',
        );
      }
    }
    int? purchaseSupplier;
    if (purchaseItemId != null) {
      purchaseSupplier = await db
          .customSelect(
            'SELECT p.supplier_id FROM purchase_items i '
            'JOIN purchases p ON p.id=i.purchase_id WHERE i.id=?',
            variables: [Variable.withInt(purchaseItemId)],
          )
          .map((row) => row.read<int>('supplier_id'))
          .getSingleOrNull();
      if (purchaseSupplier == null) {
        throw const OfflineSyncException(
          'sale_purchase_origin_missing',
          'A WAC purchase origin no longer exists.',
        );
      }
    }
    if (identitySupplier != null &&
        purchaseSupplier != null &&
        identitySupplier != purchaseSupplier) {
      throw const OfflineSyncException(
        'sale_origin_supplier_conflict',
        'The purchase and supplier identity origins disagree.',
      );
    }
    return identitySupplier ?? purchaseSupplier;
  }

  Future<_DocumentLocation> _location(String table, int id) async {
    final row = await db
        .customSelect(
          'SELECT document_id,organization_id,branch_id,warehouse_id,'
          'origin_database_id FROM business_document_locations '
          'WHERE source_table=? AND source_id=?',
          variables: [Variable.withString(table), Variable.withInt(id)],
        )
        .getSingleOrNull();
    if (row == null) {
      throw const OfflineSyncException(
        'sale_location_missing',
        'The completed sale has no immutable business location.',
      );
    }
    return _DocumentLocation(
      documentId: row.read<String>('document_id'),
      organizationId: row.read<String>('organization_id'),
      branchId: row.read<String>('branch_id'),
      warehouseId: row.read<String>('warehouse_id'),
      originDatabaseId: row.read<String>('origin_database_id'),
    );
  }

  Future<String> _localDatabaseId() => db
      .customSelect('SELECT database_id FROM sync_local_state WHERE id=1')
      .map((row) => row.read<String>('database_id'))
      .getSingle();
}

class _DocumentLocation {
  const _DocumentLocation({
    required this.documentId,
    required this.organizationId,
    required this.branchId,
    required this.warehouseId,
    required this.originDatabaseId,
  });

  final String documentId;
  final String organizationId;
  final String branchId;
  final String warehouseId;
  final String originDatabaseId;
}
