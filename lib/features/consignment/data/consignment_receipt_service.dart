import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/services/batch_service.dart';
import '../../../core/services/business/warehouse_inventory_reader.dart';
import '../../../core/services/business/warehouse_operation_scope.dart';
import '../../../core/services/stock_service.dart';
import 'consignment_module_service.dart';

class ConsignmentReceiptLineInput {
  const ConsignmentReceiptLineInput({
    required this.productId,
    required this.variantId,
    required this.quantity,
    this.manufacturerLotNumber,
    this.expiryDate,
  });

  final int productId;
  final int variantId;
  final int quantity;
  final String? manufacturerLotNumber;
  final DateTime? expiryDate;
}

/// Posts physical custody only. It never creates a purchase, supplier
/// transaction, payable, journal entry or WAC cost update.
class ConsignmentReceiptService {
  ConsignmentReceiptService(this._db, this._module);

  final AppDatabase _db;
  final ConsignmentModuleService _module;

  Future<ConsignmentReceipt> createDraft({
    required String requestKey,
    required String receiptNumber,
    required String warehouseId,
    required int supplierId,
    required String agreementId,
    required int currencyId,
    required DateTime receivedAt,
    String notes = '',
    required List<ConsignmentReceiptLineInput> lines,
  }) => _db.transaction(() async {
    final access = await _module.requireManageAccess();
    _validateUuid(requestKey, 'requestKey');
    final number = receiptNumber.trim();
    final cleanNotes = notes.trim();
    if (number.isEmpty || number.length > 64) {
      throw ArgumentError('Receipt number is required.');
    }
    if (cleanNotes.length > 2000) {
      throw ArgumentError('Receipt notes are too long.');
    }
    if (lines.isEmpty || lines.length > 500) {
      throw ArgumentError('A receipt requires 1 to 500 lines.');
    }
    final operation = await WarehouseOperationScope.resolve(
      _db,
      warehouseId: warehouseId,
    );
    await operation.validate(_db);
    if (operation.organizationId != access.scope.organizationId ||
        operation.branchId != access.scope.branchId) {
      throw StateError('Receipt warehouse is outside the local branch.');
    }

    final agreement =
        await (_db.select(_db.consignmentAgreements)..where(
              (a) =>
                  a.id.equals(agreementId) &
                  a.status.equals('active') &
                  a.supplierId.equals(supplierId) &
                  a.currencyId.equals(currencyId),
            ))
            .getSingleOrNull();
    final instant = receivedAt.toUtc();
    if (agreement == null ||
        agreement.organizationId != access.scope.organizationId ||
        agreement.branchId != access.scope.branchId ||
        agreement.databaseId != access.scope.databaseId ||
        instant.isBefore(agreement.effectiveFrom.toUtc()) ||
        (agreement.effectiveTo != null &&
            instant.isAfter(agreement.effectiveTo!.toUtc()))) {
      throw StateError('No active consignment agreement covers this receipt.');
    }

    final normalized = <Map<String, Object?>>[];
    final resolved = <_ResolvedReceiptLine>[];
    final identities = <String>{};
    for (final input in lines) {
      if (input.quantity <= 0 || input.quantity > 9007199254740991) {
        throw ArgumentError('Receipt quantity is outside the safe range.');
      }
      final lot = input.manufacturerLotNumber?.trim();
      final identity =
          '${input.productId}:${input.variantId}:${lot ?? ''}:'
          '${input.expiryDate?.toUtc().toIso8601String() ?? ''}';
      if (!identities.add(identity)) {
        throw ArgumentError('Duplicate receipt line.');
      }
      final product =
          await (_db.select(_db.products)..where(
                (p) =>
                    p.id.equals(input.productId) &
                    p.isActive.equals(true) &
                    p.trackInventory.equals(true),
              ))
              .getSingleOrNull();
      final variant =
          await (_db.select(_db.productVariants)..where(
                (v) =>
                    v.id.equals(input.variantId) &
                    v.productId.equals(input.productId) &
                    v.isActive.equals(true),
              ))
              .getSingleOrNull();
      if (product == null ||
          variant == null ||
          product.currencyId != currencyId) {
        throw StateError(
          'Receipt product is unavailable or uses another currency.',
        );
      }
      final terms =
          await (_db.select(_db.consignmentAgreementItems)..where(
                (i) =>
                    i.agreementId.equals(agreement.id) &
                    i.productId.equals(product.id) &
                    (i.variantId.equals(variant.id) | i.variantId.isNull()),
              ))
              .get();
      if (terms.length != 1) {
        throw StateError('Product is not covered by one agreement term.');
      }
      final tracked =
          product.costingMethod == 'fifo' ||
          product.inventoryTrackingType == 'batch' ||
          product.inventoryTrackingType == 'batch_expiry';
      if (tracked && (lot == null || lot.isEmpty)) {
        throw ArgumentError('Tracked consignment stock requires a lot number.');
      }
      if (product.inventoryTrackingType == 'batch_expiry' &&
          input.expiryDate == null) {
        throw ArgumentError('Expiry-tracked stock requires an expiry date.');
      }
      final quantityScale = product.measurementType == 'piece' ? 1 : 1000;
      final term = terms.single;
      resolved.add(
        _ResolvedReceiptLine(
          input: input,
          agreementItem: term,
          measurementType: product.measurementType,
          quantityScale: quantityScale,
          lot: lot,
        ),
      );
      normalized.add({
        'productId': input.productId,
        'variantId': input.variantId,
        'quantity': input.quantity,
        'lot': lot,
        'expiry': input.expiryDate?.toUtc().toIso8601String(),
        'agreementItemId': term.id,
      });
    }

    final hash = _hash({
      'warehouseId': warehouseId,
      'supplierId': supplierId,
      'agreementId': agreementId,
      'currencyId': currencyId,
      'receiptNumber': number,
      'receivedAt': instant.toIso8601String(),
      'notes': cleanNotes,
      'lines': normalized,
    });
    final prior = await (_db.select(
      _db.consignmentReceipts,
    )..where((r) => r.requestKey.equals(requestKey))).getSingleOrNull();
    if (prior != null) {
      if (prior.requestHash != hash) {
        throw StateError('Receipt request key was reused with different data.');
      }
      return prior;
    }

    final receiptId = const Uuid().v4();
    await _db
        .into(_db.consignmentReceipts)
        .insert(
          ConsignmentReceiptsCompanion.insert(
            id: receiptId,
            organizationId: access.scope.organizationId,
            branchId: access.scope.branchId,
            databaseId: access.scope.databaseId,
            warehouseId: warehouseId,
            supplierId: supplierId,
            agreementId: agreementId,
            currencyId: currencyId,
            receiptNumber: number,
            requestKey: requestKey,
            requestHash: hash,
            receivedAt: instant,
            notes: Value(cleanNotes),
            lineCount: resolved.length,
            createdBy: access.actorId,
          ),
        );
    for (final line in resolved) {
      final term = line.agreementItem;
      await _db
          .into(_db.consignmentReceiptItems)
          .insert(
            ConsignmentReceiptItemsCompanion.insert(
              id: const Uuid().v4(),
              receiptId: receiptId,
              agreementItemId: term.id,
              productId: line.input.productId,
              variantId: line.input.variantId,
              quantity: line.input.quantity,
              quantityScale: line.quantityScale,
              measurementType: line.measurementType,
              settlementBasis: term.settlementBasis,
              unitCostCents: Value(term.unitCostCents),
              supplierShareBps: Value(term.supplierShareBps),
              includeLineDiscount: term.includeLineDiscount,
              includeInvoiceDiscount: term.includeInvoiceDiscount,
              includeSalesTax: term.includeSalesTax,
              manufacturerLotNumber: Value(line.lot),
              expiryDate: Value(line.input.expiryDate?.toUtc()),
            ),
          );
    }
    return (_db.select(
      _db.consignmentReceipts,
    )..where((r) => r.id.equals(receiptId))).getSingle();
  });

  Future<ConsignmentReceipt> post({
    required String receiptId,
    required String requestKey,
  }) => _db.transaction(() async {
    final access = await _module.requireManageAccess();
    _validateUuid(requestKey, 'requestKey');
    final hash = _hash({'kind': 'posted', 'receiptId': receiptId});
    final prior = await (_db.select(
      _db.consignmentReceiptEvents,
    )..where((e) => e.requestKey.equals(requestKey))).getSingleOrNull();
    if (prior != null) {
      if (prior.receiptId != receiptId ||
          prior.kind != 'posted' ||
          prior.requestHash != hash) {
        throw StateError('Posting request key was reused with different data.');
      }
      return (_db.select(
        _db.consignmentReceipts,
      )..where((r) => r.id.equals(receiptId))).getSingle();
    }

    final receipt =
        await (_db.select(_db.consignmentReceipts)
              ..where((r) => r.id.equals(receiptId) & r.status.equals('draft')))
            .getSingle();
    final scope = await WarehouseOperationScope.resolve(
      _db,
      warehouseId: receipt.warehouseId,
    );
    await scope.validate(_db);
    if (scope.organizationId != access.scope.organizationId ||
        scope.branchId != access.scope.branchId ||
        receipt.databaseId != access.scope.databaseId) {
      throw StateError('Receipt scope changed before posting.');
    }
    final items = await (_db.select(
      _db.consignmentReceiptItems,
    )..where((i) => i.receiptId.equals(receipt.id))).get();
    if (items.length != receipt.lineCount) {
      throw StateError('Receipt lines are incomplete.');
    }

    await _db
        .into(_db.consignmentReceiptEvents)
        .insert(
          ConsignmentReceiptEventsCompanion.insert(
            id: const Uuid().v4(),
            receiptId: receipt.id,
            kind: 'posted',
            requestKey: requestKey,
            requestHash: hash,
            actorId: access.actorId,
          ),
        );

    final productIds = <int>{};
    final trackedProductIds = <int>{};
    for (final item in items) {
      final product = await (_db.select(
        _db.products,
      )..where((p) => p.id.equals(item.productId))).getSingle();
      final tracked =
          product.costingMethod == 'fifo' ||
          product.inventoryTrackingType == 'batch' ||
          product.inventoryTrackingType == 'batch_expiry';

      await StockService.adjustStock(
        _db.productDao,
        productId: item.productId,
        variantId: item.variantId,
        quantity: item.quantity,
        direction: StockDirection.increase,
        scope: scope,
        origin: InventoryOriginIntent.keyed(
          'consignment_receipt',
          'consignment_receipt:${item.id}',
        ),
      );
      final changed = await _db.customUpdate(
        'UPDATE business_warehouse_stocks '
        'SET supplier_owned_quantity=supplier_owned_quantity+?, updated_at=? '
        'WHERE warehouse_id=? AND variant_id=? '
        'AND supplier_owned_quantity+?<=quantity',
        variables: [
          Variable.withInt(item.quantity),
          Variable.withString(DateTime.now().toUtc().toIso8601String()),
          Variable.withString(receipt.warehouseId),
          Variable.withInt(item.variantId),
          Variable.withInt(item.quantity),
        ],
        updates: {_db.businessWarehouseStocks},
      );
      if (changed != 1) {
        throw StateError('Supplier-owned stock update failed.');
      }

      int? batchId;
      if (tracked) {
        trackedProductIds.add(item.productId);
        batchId = await BatchService.createBatchFromConsignment(
          _db.productDao,
          productId: item.productId,
          variantId: item.variantId,
          receiptItemId: item.id,
          supplierId: receipt.supplierId,
          quantity: item.quantity,
          operationalUnitCostCents: item.unitCostCents ?? 0,
          receivedDate: receipt.receivedAt,
          expiryDate: item.expiryDate,
          manufacturerLotNumber: item.manufacturerLotNumber,
          scope: scope,
        );
      }
      await _db
          .into(_db.consignmentInventoryLayers)
          .insert(
            ConsignmentInventoryLayersCompanion.insert(
              id: const Uuid().v4(),
              receiptItemId: item.id,
              warehouseId: receipt.warehouseId,
              supplierId: receipt.supplierId,
              agreementId: receipt.agreementId,
              productId: item.productId,
              variantId: item.variantId,
              batchId: Value(batchId),
              receivedQuantity: item.quantity,
              remainingQuantity: item.quantity,
              quantityScale: item.quantityScale,
              measurementType: item.measurementType,
              settlementBasis: item.settlementBasis,
              unitCostCents: Value(item.unitCostCents),
              supplierShareBps: Value(item.supplierShareBps),
              includeLineDiscount: item.includeLineDiscount,
              includeInvoiceDiscount: item.includeInvoiceDiscount,
              includeSalesTax: item.includeSalesTax,
              receivedAt: receipt.receivedAt,
            ),
          );
      productIds.add(item.productId);
    }

    for (final productId in productIds) {
      await StockService.syncProductStockFromVariants(
        _db.productDao,
        productId: productId,
        scope: scope,
      );
      if (trackedProductIds.contains(productId)) {
        await WarehouseInventoryReader.assertBatches(
          _db.productDao,
          scope: scope,
          productId: productId,
        );
      }
    }

    final now = DateTime.now().toUtc();
    await (_db.update(
      _db.consignmentReceipts,
    )..where((r) => r.id.equals(receipt.id))).write(
      ConsignmentReceiptsCompanion(
        status: const Value('posted'),
        postedBy: Value(access.actorId),
        postedAt: Value(now),
      ),
    );
    return (_db.select(
      _db.consignmentReceipts,
    )..where((r) => r.id.equals(receipt.id))).getSingle();
  });

  /// Voids an untouched posted receipt. Once any unit has been sold, moved or
  /// adjusted, the receipt stays immutable and must be corrected by a later
  /// ownership movement instead of rewriting history.
  Future<ConsignmentReceipt> voidReceipt({
    required String receiptId,
    required String requestKey,
    required String reason,
    bool allowOwnershipConversion = false,
  }) => _db.transaction(() async {
    final access = await _module.requireHistoricalManageAccess();
    _validateUuid(requestKey, 'requestKey');
    final cleanReason = reason.trim();
    if (cleanReason.isEmpty || cleanReason.length > 500) {
      throw ArgumentError(
        'A void reason between 1 and 500 characters is required.',
      );
    }
    final hash = _hash({
      'kind': 'voided',
      'receiptId': receiptId,
      'reason': cleanReason,
    });
    final prior = await (_db.select(
      _db.consignmentReceiptEvents,
    )..where((e) => e.requestKey.equals(requestKey))).getSingleOrNull();
    if (prior != null) {
      if (prior.receiptId != receiptId ||
          prior.kind != 'voided' ||
          prior.requestHash != hash) {
        throw StateError('Void request key was reused with different data.');
      }
      return (_db.select(
        _db.consignmentReceipts,
      )..where((r) => r.id.equals(receiptId))).getSingle();
    }

    final receipt =
        await (_db.select(
              _db.consignmentReceipts,
            )..where((r) => r.id.equals(receiptId) & r.status.equals('posted')))
            .getSingle();
    if (!allowOwnershipConversion) {
      final conversion =
          await (_db.select(_db.consignmentOwnershipConversions)..where(
                (row) =>
                    row.receiptId.equals(receiptId) &
                    row.status.equals('posted'),
              ))
              .getSingleOrNull();
      if (conversion != null) {
        throw const ConsignmentUserException(
          'consignment.conversion_use_dedicated_void',
        );
      }
    }
    final scope = await WarehouseOperationScope.resolve(
      _db,
      warehouseId: receipt.warehouseId,
    );
    await scope.validate(_db);
    if (scope.organizationId != access.scope.organizationId ||
        scope.branchId != access.scope.branchId ||
        receipt.databaseId != access.scope.databaseId) {
      throw StateError('Receipt scope changed before voiding.');
    }

    final layers = await (_db.select(_db.consignmentInventoryLayers).join([
      innerJoin(
        _db.consignmentReceiptItems,
        _db.consignmentReceiptItems.id.equalsExp(
          _db.consignmentInventoryLayers.receiptItemId,
        ),
      ),
    ])..where(_db.consignmentReceiptItems.receiptId.equals(receipt.id))).get();
    if (layers.length != receipt.lineCount) {
      throw StateError('Receipt ownership layers are incomplete.');
    }
    for (final row in layers) {
      final layer = row.readTable(_db.consignmentInventoryLayers);
      if (layer.status != 'open' ||
          layer.remainingQuantity != layer.receivedQuantity) {
        throw StateError(
          'A consumed or previously adjusted consignment receipt cannot be voided.',
        );
      }
      if (layer.batchId != null) {
        final batch = await (_db.select(
          _db.productBatches,
        )..where((b) => b.id.equals(layer.batchId!))).getSingle();
        if (!batch.isActive ||
            batch.remainingQuantity != layer.receivedQuantity) {
          throw StateError(
            'The receipt batch changed and cannot be removed by voiding.',
          );
        }
      }
    }

    await _db
        .into(_db.consignmentReceiptEvents)
        .insert(
          ConsignmentReceiptEventsCompanion.insert(
            id: const Uuid().v4(),
            receiptId: receipt.id,
            kind: 'voided',
            requestKey: requestKey,
            requestHash: hash,
            actorId: access.actorId,
            reason: Value(cleanReason),
          ),
        );

    final productIds = <int>{};
    final batchedProductIds = <int>{};
    for (final row in layers) {
      final layer = row.readTable(_db.consignmentInventoryLayers);
      final item = row.readTable(_db.consignmentReceiptItems);
      final ownershipChanged = await _db.customUpdate(
        'UPDATE business_warehouse_stocks '
        'SET supplier_owned_quantity=supplier_owned_quantity-?, updated_at=? '
        'WHERE warehouse_id=? AND variant_id=? '
        'AND supplier_owned_quantity>=?',
        variables: [
          Variable.withInt(layer.receivedQuantity),
          Variable.withString(DateTime.now().toUtc().toIso8601String()),
          Variable.withString(receipt.warehouseId),
          Variable.withInt(layer.variantId),
          Variable.withInt(layer.receivedQuantity),
        ],
        updates: {_db.businessWarehouseStocks},
      );
      if (ownershipChanged != 1) {
        throw StateError('Supplier-owned stock reversal failed.');
      }
      await StockService.adjustStock(
        _db.productDao,
        productId: layer.productId,
        variantId: layer.variantId,
        quantity: layer.receivedQuantity,
        direction: StockDirection.decrease,
        scope: scope,
        origin: InventoryOriginIntent.keyed(
          'consignment_receipt_void',
          'consignment_receipt_void:${item.id}',
          reference: 'consignment_receipt:${item.id}',
        ),
      );
      if (layer.batchId != null) {
        batchedProductIds.add(layer.productId);
        await BatchService.consumeFifo(
          _db.productDao,
          productId: layer.productId,
          variantId: layer.variantId,
          quantity: layer.receivedQuantity,
          consumptionType: 'consignment_receipt_void',
          requiredBatchId: layer.batchId,
          notes: cleanReason,
          scope: scope,
        );
      }
      await (_db.update(
        _db.consignmentInventoryLayers,
      )..where((l) => l.id.equals(layer.id))).write(
        ConsignmentInventoryLayersCompanion(
          remainingQuantity: const Value(0),
          status: const Value('voided'),
          updatedAt: Value(DateTime.now().toUtc()),
        ),
      );
      productIds.add(layer.productId);
    }

    for (final productId in productIds) {
      await StockService.syncProductStockFromVariants(
        _db.productDao,
        productId: productId,
        scope: scope,
      );
      if (batchedProductIds.contains(productId)) {
        await WarehouseInventoryReader.assertBatches(
          _db.productDao,
          scope: scope,
          productId: productId,
        );
      }
    }

    final now = DateTime.now().toUtc();
    await (_db.update(
      _db.consignmentReceipts,
    )..where((r) => r.id.equals(receipt.id))).write(
      ConsignmentReceiptsCompanion(
        status: const Value('voided'),
        voidedBy: Value(access.actorId),
        voidedAt: Value(now),
        voidReason: Value(cleanReason),
      ),
    );
    return (_db.select(
      _db.consignmentReceipts,
    )..where((r) => r.id.equals(receipt.id))).getSingle();
  });

  void _validateUuid(String value, String name) {
    if (!RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
    ).hasMatch(value)) {
      throw ArgumentError.value(value, name, 'A UUID is required.');
    }
  }

  String _hash(Object value) =>
      sha256.convert(utf8.encode(jsonEncode(value))).toString();
}

class _ResolvedReceiptLine {
  const _ResolvedReceiptLine({
    required this.input,
    required this.agreementItem,
    required this.measurementType,
    required this.quantityScale,
    required this.lot,
  });

  final ConsignmentReceiptLineInput input;
  final ConsignmentAgreementItem agreementItem;
  final String measurementType;
  final int quantityScale;
  final String? lot;
}
