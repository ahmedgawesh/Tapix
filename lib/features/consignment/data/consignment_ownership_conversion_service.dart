import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/measurement/measurement.dart';
import '../../../core/services/balance_service.dart';
import '../../../core/services/batch_service.dart';
import '../../../core/services/business/warehouse_inventory_reader.dart';
import '../../../core/services/business/warehouse_operation_scope.dart';
import '../../../core/services/inventory/inventory_stock_source_service.dart';
import '../../../core/services/journal_entry_service.dart';
import '../../../core/services/stock_service.dart';
import 'consignment_module_service.dart';
import 'consignment_receipt_service.dart';

class ConsignmentOwnershipConversionLineInput {
  const ConsignmentOwnershipConversionLineInput({
    required this.productId,
    required this.variantId,
    required this.quantity,
    this.supplierIdentityId,
    this.sourceBatchId,
  });

  final int productId;
  final int variantId;
  final int quantity;
  final int? supplierIdentityId;
  final int? sourceBatchId;
}

/// Reclassifies proven enterprise-owned stock as supplier-owned consignment.
///
/// The linked consignment receipt first creates the destination custody layer;
/// the exact enterprise source is then removed in the same SQLite transaction.
/// Consequently physical stock never changes. The supplier credit/evidence
/// reference is mandatory and the historical inventory carrying value is
/// removed through Dr AP / Cr Inventory and the supplier sub-ledger.
class ConsignmentOwnershipConversionService {
  ConsignmentOwnershipConversionService(
    this._db,
    this._module,
    this._receipts,
    this._journal,
  );

  final AppDatabase _db;
  final ConsignmentModuleService _module;
  final ConsignmentReceiptService _receipts;
  final JournalEntryService _journal;

  Future<ConsignmentOwnershipConversion> convert({
    required String requestKey,
    required String conversionNumber,
    required String evidenceReference,
    required String warehouseId,
    required int supplierId,
    required String agreementId,
    required int currencyId,
    required DateTime convertedAt,
    String notes = '',
    required List<ConsignmentOwnershipConversionLineInput> lines,
  }) => _db.transaction(() async {
    final access = await _module.requireManageAccess();
    _validateUuid(requestKey, 'requestKey');
    final number = conversionNumber.trim();
    final evidence = evidenceReference.trim();
    final cleanNotes = notes.trim();
    if (number.isEmpty || number.length > 61) {
      throw const ConsignmentUserException(
        'consignment.conversion_number_required',
      );
    }
    if (evidence.isEmpty || evidence.length > 200) {
      throw const ConsignmentUserException(
        'consignment.conversion_evidence_required',
      );
    }
    if (cleanNotes.length > 2000) {
      throw const ConsignmentUserException('consignment.notes_too_long');
    }
    if (lines.isEmpty || lines.length > 500) {
      throw const ConsignmentUserException(
        'consignment.conversion_lines_required',
      );
    }

    final prior = await (_db.select(
      _db.consignmentOwnershipConversions,
    )..where((row) => row.requestKey.equals(requestKey))).getSingleOrNull();
    final inputHash = _hash({
      'conversionNumber': number,
      'evidenceReference': evidence,
      'warehouseId': warehouseId,
      'supplierId': supplierId,
      'agreementId': agreementId,
      'currencyId': currencyId,
      'convertedAt': convertedAt.toUtc().toIso8601String(),
      'notes': cleanNotes,
      'lines': [
        for (final line in lines)
          {
            'productId': line.productId,
            'variantId': line.variantId,
            'quantity': line.quantity,
            'supplierIdentityId': line.supplierIdentityId,
            'sourceBatchId': line.sourceBatchId,
          },
      ],
    });
    if (prior != null) {
      if (prior.requestHash != inputHash) {
        throw const ConsignmentUserException('consignment.request_key_reused');
      }
      return prior;
    }

    final scope = await WarehouseOperationScope.resolve(
      _db,
      warehouseId: warehouseId,
    );
    await scope.validate(_db);
    if (scope.organizationId != access.scope.organizationId ||
        scope.branchId != access.scope.branchId) {
      throw const ConsignmentUserException(
        'consignment.warehouse_outside_branch',
      );
    }
    final instant = convertedAt.toUtc();
    final agreement =
        await (_db.select(_db.consignmentAgreements)..where(
              (row) =>
                  row.id.equals(agreementId) &
                  row.status.equals('active') &
                  row.supplierId.equals(supplierId) &
                  row.currencyId.equals(currencyId),
            ))
            .getSingleOrNull();
    if (agreement == null ||
        agreement.organizationId != access.scope.organizationId ||
        agreement.branchId != access.scope.branchId ||
        agreement.databaseId != access.scope.databaseId ||
        instant.isBefore(agreement.effectiveFrom.toUtc()) ||
        (agreement.effectiveTo != null &&
            instant.isAfter(agreement.effectiveTo!.toUtc()))) {
      throw const ConsignmentUserException(
        'consignment.conversion_agreement_invalid',
      );
    }

    final resolved = <_ResolvedConversionLine>[];
    final variantIds = <int>{};
    final sourceReader = InventoryStockSourceService(_db);
    for (final input in lines) {
      if (!variantIds.add(input.variantId)) {
        throw const ConsignmentUserException(
          'consignment.conversion_duplicate_variant',
        );
      }
      if (input.quantity <= 0 || input.quantity > 9007199254740991) {
        throw const ConsignmentUserException(
          'consignment.conversion_quantity_invalid',
        );
      }
      final product =
          await (_db.select(_db.products)..where(
                (row) =>
                    row.id.equals(input.productId) &
                    row.isActive.equals(true) &
                    row.trackInventory.equals(true),
              ))
              .getSingleOrNull();
      final variant =
          await (_db.select(_db.productVariants)..where(
                (row) =>
                    row.id.equals(input.variantId) &
                    row.productId.equals(input.productId) &
                    row.isActive.equals(true),
              ))
              .getSingleOrNull();
      if (product == null ||
          variant == null ||
          product.currencyId != currencyId) {
        throw const ConsignmentUserException(
          'consignment.conversion_product_invalid',
        );
      }
      final terms =
          await (_db.select(_db.consignmentAgreementItems)..where(
                (row) =>
                    row.agreementId.equals(agreementId) &
                    row.productId.equals(input.productId) &
                    (row.variantId.equals(input.variantId) |
                        row.variantId.isNull()),
              ))
              .get();
      if (terms.length != 1) {
        throw const ConsignmentUserException(
          'consignment.conversion_term_missing',
        );
      }
      final tracked =
          product.costingMethod == 'fifo' ||
          product.inventoryTrackingType != 'standard';
      if (tracked != (input.sourceBatchId != null) ||
          tracked == (input.supplierIdentityId != null)) {
        throw const ConsignmentUserException(
          'consignment.conversion_source_required',
        );
      }
      final snapshot = await sourceReader.loadProduct(
        input.productId,
        variantId: input.variantId,
        scope: scope,
      );
      final source = snapshot.sources.where((row) {
        if (row.ownership != InventoryStockOwnership.enterprise ||
            row.supplierId != supplierId) {
          return false;
        }
        return tracked
            ? row.batchId == input.sourceBatchId
            : row.supplierIdentityId == input.supplierIdentityId;
      }).firstOrNull;
      if (source == null || source.quantity < input.quantity) {
        throw const ConsignmentUserException(
          'consignment.conversion_source_insufficient',
        );
      }

      int unitCostCents;
      DateTime? expiryDate;
      String? lotNumber;
      if (tracked) {
        final batch = await (_db.select(
          _db.productBatches,
        )..where((row) => row.id.equals(input.sourceBatchId!))).getSingle();
        if (!batch.isActive || batch.remainingQuantity < input.quantity) {
          throw const ConsignmentUserException(
            'consignment.conversion_source_insufficient',
          );
        }
        unitCostCents = batch.unitCostCents.toBigInt().toInt();
        expiryDate = batch.expiryDate;
        lotNumber = batch.manufacturerLotNumber ?? batch.batchNumber;
      } else {
        final stock =
            await (_db.select(_db.businessWarehouseStocks)..where(
                  (row) =>
                      row.warehouseId.equals(warehouseId) &
                      row.variantId.equals(input.variantId),
                ))
                .getSingle();
        unitCostCents = stock.unitCostCents;
      }
      final amount = MeasuredAmount.cents(
        unitCents: unitCostCents,
        quantity: input.quantity,
        quantityScale: source.quantityScale,
      );
      if (unitCostCents <= 0 || amount <= 0 || amount > 9007199254740991) {
        throw const ConsignmentUserException(
          'consignment.conversion_cost_invalid',
        );
      }
      resolved.add(
        _ResolvedConversionLine(
          input: input,
          quantityScale: source.quantityScale,
          measurementType: source.measurementType,
          unitCostCents: unitCostCents,
          inventoryAmountCents: amount,
          expiryDate: expiryDate,
          lotNumber: lotNumber,
        ),
      );
    }

    final receipt = await _receipts.createDraft(
      requestKey: const Uuid().v4(),
      receiptNumber: 'CV-$number',
      warehouseId: warehouseId,
      supplierId: supplierId,
      agreementId: agreementId,
      currencyId: currencyId,
      receivedAt: instant,
      notes:
          'Ownership conversion $number — $evidence${cleanNotes.isEmpty ? '' : ' — $cleanNotes'}',
      lines: [
        for (final line in resolved)
          ConsignmentReceiptLineInput(
            productId: line.input.productId,
            variantId: line.input.variantId,
            quantity: line.input.quantity,
            manufacturerLotNumber: line.lotNumber,
            expiryDate: line.expiryDate,
          ),
      ],
    );
    await _receipts.post(receiptId: receipt.id, requestKey: const Uuid().v4());
    final receiptItems = await (_db.select(
      _db.consignmentReceiptItems,
    )..where((row) => row.receiptId.equals(receipt.id))).get();

    final pendingItems = <_PendingConversionItem>[];
    final touchedProducts = <int>{};
    final trackedProducts = <int>{};
    for (var index = 0; index < resolved.length; index++) {
      final line = resolved[index];
      final receiptItem = receiptItems.singleWhere(
        (row) =>
            row.productId == line.input.productId &&
            row.variantId == line.input.variantId,
      );
      final eventKey = 'consignment_ownership_conversion:$requestKey:$index';
      await StockService.adjustStock(
        _db.productDao,
        productId: line.input.productId,
        variantId: line.input.variantId,
        quantity: line.input.quantity,
        direction: StockDirection.decrease,
        scope: scope,
        origin: InventoryOriginIntent.keyed(
          'consignment_ownership_conversion',
          eventKey,
          supplierIdentityId: line.input.supplierIdentityId,
        ),
      );

      int? consumptionId;
      if (line.input.sourceBatchId != null) {
        final consumptions = await BatchService.consumeFifo(
          _db.productDao,
          productId: line.input.productId,
          variantId: line.input.variantId,
          quantity: line.input.quantity,
          consumptionType: 'consignment_ownership_conversion',
          requiredBatchId: line.input.sourceBatchId,
          requiredSupplierId: supplierId,
          notes: '$number — $evidence',
          scope: scope,
        );
        if (consumptions.length != 1 ||
            consumptions.single.quantity != line.input.quantity) {
          throw StateError('consignment.conversion_batch_consumption_invalid');
        }
        consumptionId = consumptions.single.consumptionId;
        trackedProducts.add(line.input.productId);
      }
      pendingItems.add(
        _PendingConversionItem(
          id: const Uuid().v4(),
          receiptItemId: receiptItem.id,
          line: line,
          originRemovalEventKey: line.input.sourceBatchId == null
              ? eventKey
              : null,
          batchConsumptionId: consumptionId,
        ),
      );
      touchedProducts.add(line.input.productId);
    }

    for (final productId in touchedProducts) {
      await StockService.syncProductStockFromVariants(
        _db.productDao,
        productId: productId,
        scope: scope,
      );
      if (trackedProducts.contains(productId)) {
        await WarehouseInventoryReader.assertBatches(
          _db.productDao,
          scope: scope,
          productId: productId,
        );
      }
    }

    final totalValue = resolved.fold<int>(
      0,
      (sum, row) => sum + row.inventoryAmountCents,
    );
    final conversionId = await _db
        .into(_db.consignmentOwnershipConversions)
        .insert(
          ConsignmentOwnershipConversionsCompanion.insert(
            organizationId: access.scope.organizationId,
            branchId: access.scope.branchId,
            databaseId: access.scope.databaseId,
            warehouseId: warehouseId,
            supplierId: supplierId,
            agreementId: agreementId,
            currencyId: currencyId,
            receiptId: receipt.id,
            conversionNumber: number,
            evidenceReference: evidence,
            convertedAt: instant,
            notes: Value(cleanNotes),
            lineCount: pendingItems.length,
            inventoryValueCents: totalValue,
            requestKey: requestKey,
            requestHash: inputHash,
            createdBy: access.actorId,
          ),
        );
    for (final item in pendingItems) {
      await _db
          .into(_db.consignmentOwnershipConversionItems)
          .insert(
            ConsignmentOwnershipConversionItemsCompanion.insert(
              id: item.id,
              conversionId: conversionId,
              receiptItemId: item.receiptItemId,
              productId: item.line.input.productId,
              variantId: item.line.input.variantId,
              supplierIdentityId: Value(item.line.input.supplierIdentityId),
              sourceBatchId: Value(item.line.input.sourceBatchId),
              quantity: item.line.input.quantity,
              quantityScale: item.line.quantityScale,
              measurementType: item.line.measurementType,
              inventoryUnitCostCents: item.line.unitCostCents,
              inventoryAmountCents: item.line.inventoryAmountCents,
              originRemovalEventKey: Value(item.originRemovalEventKey),
              batchConsumptionId: Value(item.batchConsumptionId),
            ),
          );
    }

    final journalId = await _journal
        .recordConsignmentOwnershipConversionJournalEntry(
          conversionId: conversionId,
          signedInventoryValueCents: totalValue,
          currencyId: currencyId,
          entryDate: instant,
          evidenceReference: evidence,
          userId: access.actorId,
        );
    final supplierTransactionId = await _db
        .into(_db.supplierTransactions)
        .insert(
          SupplierTransactionsCompanion.insert(
            supplierId: supplierId,
            transactionNumber: Value(number),
            transactionType: 'consignment_ownership_conversion',
            amountCents: Decimal.fromInt(-totalValue),
            currencyId: currencyId,
            description: Value(
              'Consignment ownership conversion $number — $evidence',
            ),
            referenceId: Value(conversionId),
            referenceType: const Value('consignment_ownership_conversion'),
            transactionDate: Value(instant),
          ),
        );
    await BalanceService.adjustSupplierBalance(
      _db.supplierDao,
      supplierId: supplierId,
      deltaCents: -totalValue,
    );
    await (_db.update(_db.consignmentOwnershipConversions)..where(
          (row) => row.id.equals(conversionId) & row.status.equals('posting'),
        ))
        .write(
          ConsignmentOwnershipConversionsCompanion(
            status: const Value('posted'),
            journalEntryId: Value(journalId),
            supplierTransactionId: Value(supplierTransactionId),
          ),
        );
    return (_db.select(
      _db.consignmentOwnershipConversions,
    )..where((row) => row.id.equals(conversionId))).getSingle();
  });

  Future<ConsignmentOwnershipConversion> voidConversion({
    required int conversionId,
    required String requestKey,
    required String reason,
  }) => _db.transaction(() async {
    final access = await _module.requireHistoricalManageAccess();
    _validateUuid(requestKey, 'requestKey');
    final cleanReason = reason.trim();
    if (cleanReason.isEmpty || cleanReason.length > 500) {
      throw const ConsignmentUserException('consignment.void_reason_required');
    }
    final requestHash = _hash({
      'conversionId': conversionId,
      'reason': cleanReason,
    });
    final any = await (_db.select(
      _db.consignmentOwnershipConversions,
    )..where((row) => row.id.equals(conversionId))).getSingleOrNull();
    if (any == null) {
      throw const ConsignmentUserException('consignment.conversion_not_posted');
    }
    if (any.status == 'voided') {
      if (any.voidRequestKey == requestKey &&
          any.voidRequestHash == requestHash) {
        return any;
      }
      throw const ConsignmentUserException('consignment.conversion_not_posted');
    }
    if (any.status != 'posted') {
      throw const ConsignmentUserException('consignment.conversion_not_posted');
    }
    final scope = await WarehouseOperationScope.resolve(
      _db,
      warehouseId: any.warehouseId,
    );
    await scope.validate(_db);
    if (scope.organizationId != access.scope.organizationId ||
        scope.branchId != access.scope.branchId ||
        any.databaseId != access.scope.databaseId) {
      throw const ConsignmentUserException(
        'consignment.warehouse_outside_branch',
      );
    }

    final items = await (_db.select(
      _db.consignmentOwnershipConversionItems,
    )..where((row) => row.conversionId.equals(conversionId))).get();
    if (items.length != any.lineCount) {
      throw StateError('consignment.conversion_lines_incomplete');
    }
    await _receipts.voidReceipt(
      receiptId: any.receiptId,
      requestKey: const Uuid().v4(),
      reason: cleanReason,
      allowOwnershipConversion: true,
    );

    final touchedProducts = <int>{};
    final trackedProducts = <int>{};
    for (final item in items) {
      await StockService.adjustStock(
        _db.productDao,
        productId: item.productId,
        variantId: item.variantId,
        quantity: item.quantity,
        direction: StockDirection.increase,
        scope: scope,
        origin: InventoryOriginIntent.keyed(
          'consignment_ownership_conversion_void',
          'consignment_ownership_conversion_void:$requestKey:${item.id}',
          reference: item.originRemovalEventKey,
        ),
      );
      if (item.sourceBatchId != null) {
        if (item.batchConsumptionId == null) {
          throw StateError('consignment.conversion_batch_link_invalid');
        }
        final restored =
            await BatchService.restoreExactOwnershipConversionConsumption(
              _db.productDao,
              consumptionId: item.batchConsumptionId!,
              notes: 'Void ${any.conversionNumber} — $cleanReason',
              scope: scope,
            );
        if (restored != item.quantity) {
          throw StateError('consignment.conversion_batch_restore_failed');
        }
        trackedProducts.add(item.productId);
      }
      touchedProducts.add(item.productId);
    }
    for (final productId in touchedProducts) {
      await StockService.syncProductStockFromVariants(
        _db.productDao,
        productId: productId,
        scope: scope,
      );
      if (trackedProducts.contains(productId)) {
        await WarehouseInventoryReader.assertBatches(
          _db.productDao,
          scope: scope,
          productId: productId,
        );
      }
    }

    final reversalJournalId = await _journal
        .recordConsignmentOwnershipConversionJournalEntry(
          conversionId: conversionId,
          signedInventoryValueCents: -any.inventoryValueCents,
          currencyId: any.currencyId,
          entryDate: DateTime.now().toUtc(),
          evidenceReference: cleanReason,
          userId: access.actorId,
        );
    final reversalSupplierTransactionId = await _db
        .into(_db.supplierTransactions)
        .insert(
          SupplierTransactionsCompanion.insert(
            supplierId: any.supplierId,
            transactionNumber: Value('${any.conversionNumber}-VOID'),
            transactionType: 'consignment_ownership_conversion_void',
            amountCents: Decimal.fromInt(any.inventoryValueCents),
            currencyId: any.currencyId,
            description: Value(
              'Void consignment ownership conversion ${any.conversionNumber} — $cleanReason',
            ),
            referenceId: Value(conversionId),
            referenceType: const Value('consignment_ownership_conversion_void'),
          ),
        );
    await BalanceService.adjustSupplierBalance(
      _db.supplierDao,
      supplierId: any.supplierId,
      deltaCents: any.inventoryValueCents,
    );
    final now = DateTime.now().toUtc();
    final changed =
        await (_db.update(_db.consignmentOwnershipConversions)..where(
              (row) =>
                  row.id.equals(conversionId) & row.status.equals('posted'),
            ))
            .write(
              ConsignmentOwnershipConversionsCompanion(
                status: const Value('voided'),
                voidRequestKey: Value(requestKey),
                voidRequestHash: Value(requestHash),
                voidedBy: Value(access.actorId),
                voidedAt: Value(now),
                voidReason: Value(cleanReason),
                reversalJournalEntryId: Value(reversalJournalId),
                reversalSupplierTransactionId: Value(
                  reversalSupplierTransactionId,
                ),
              ),
            );
    if (changed != 1) {
      throw const ConsignmentUserException(
        'consignment.conversion_void_conflict',
      );
    }
    return (_db.select(
      _db.consignmentOwnershipConversions,
    )..where((row) => row.id.equals(conversionId))).getSingle();
  });

  static void _validateUuid(String value, String name) {
    if (!RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
    ).hasMatch(value)) {
      throw ArgumentError.value(value, name, 'A UUID is required.');
    }
  }

  static String _hash(Object value) =>
      sha256.convert(utf8.encode(jsonEncode(value))).toString();
}

class _ResolvedConversionLine {
  const _ResolvedConversionLine({
    required this.input,
    required this.quantityScale,
    required this.measurementType,
    required this.unitCostCents,
    required this.inventoryAmountCents,
    required this.expiryDate,
    required this.lotNumber,
  });

  final ConsignmentOwnershipConversionLineInput input;
  final int quantityScale;
  final String measurementType;
  final int unitCostCents;
  final int inventoryAmountCents;
  final DateTime? expiryDate;
  final String? lotNumber;
}

class _PendingConversionItem {
  const _PendingConversionItem({
    required this.id,
    required this.receiptItemId,
    required this.line,
    required this.originRemovalEventKey,
    required this.batchConsumptionId,
  });

  final String id;
  final String receiptItemId;
  final _ResolvedConversionLine line;
  final String? originRemovalEventKey;
  final int? batchConsumptionId;
}
