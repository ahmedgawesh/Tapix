import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/measurement/measurement.dart';
import '../../../core/services/batch_service.dart';
import '../../../core/services/business/warehouse_inventory_reader.dart';
import '../../../core/services/business/warehouse_operation_scope.dart';
import '../../../core/services/journal_entry_service.dart';
import '../../../core/services/stock_service.dart';
import 'consignment_module_service.dart';

class ConsignmentCustodyLineInput {
  const ConsignmentCustodyLineInput({
    required this.layerId,
    required this.quantity,
    this.liabilityUnitCents,
  });

  final String layerId;
  final int quantity;

  /// Required only when the company bears a loss/damage and the agreement uses
  /// a percentage of sales. Fixed-cost agreements always use their frozen
  /// layer cost.
  final int? liabilityUnitCents;
}

/// Handles supplier returns and custody loss/damage without creating a
/// purchase. Physical stock, supplier ownership, batch rows, audit events and
/// any company-borne liability are committed in one database transaction.
class ConsignmentCustodyService {
  ConsignmentCustodyService(this._db, this._module, this._journal);

  final AppDatabase _db;
  final ConsignmentModuleService _module;
  final JournalEntryService _journal;

  Future<ConsignmentCustodyDocument> createDraft({
    required String requestKey,
    required String documentNumber,
    required String documentType,
    required String responsibility,
    required String warehouseId,
    required int supplierId,
    required String agreementId,
    required int currencyId,
    required DateTime occurredAt,
    required String reason,
    String notes = '',
    required List<ConsignmentCustodyLineInput> lines,
  }) => _db.transaction(() async {
    final access = await _module.requireManageAccess();
    _validateUuid(requestKey, 'requestKey');
    final number = documentNumber.trim();
    final cleanReason = reason.trim();
    final cleanNotes = notes.trim();
    const validTypes = {'supplier_return', 'loss', 'damage'};
    const validResponsibilities = {'supplier', 'company'};
    if (!validTypes.contains(documentType)) {
      throw const ConsignmentUserException('consignment.custody_type_required');
    }
    if (!validResponsibilities.contains(responsibility) ||
        (documentType == 'supplier_return' && responsibility != 'supplier')) {
      throw const ConsignmentUserException(
        'consignment.custody_responsibility_required',
      );
    }
    if (number.isEmpty || number.length > 64) {
      throw const ConsignmentUserException(
        'consignment.custody_number_required',
      );
    }
    if (cleanReason.isEmpty || cleanReason.length > 500) {
      throw const ConsignmentUserException(
        'consignment.custody_reason_required',
      );
    }
    if (cleanNotes.length > 2000) {
      throw const ConsignmentUserException('consignment.notes_too_long');
    }
    if (lines.isEmpty || lines.length > 500) {
      throw const ConsignmentUserException(
        'consignment.custody_lines_required',
      );
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
    final agreement =
        await (_db.select(_db.consignmentAgreements)..where(
              (a) =>
                  a.id.equals(agreementId) &
                  a.supplierId.equals(supplierId) &
                  a.currencyId.equals(currencyId),
            ))
            .getSingleOrNull();
    if (agreement == null ||
        agreement.status == 'draft' ||
        agreement.organizationId != access.scope.organizationId ||
        agreement.branchId != access.scope.branchId ||
        agreement.databaseId != access.scope.databaseId) {
      throw const ConsignmentUserException(
        'consignment.custody_agreement_invalid',
      );
    }

    final resolved = <_ResolvedCustodyLine>[];
    final normalized = <Map<String, Object?>>[];
    final layerIds = <String>{};
    for (final input in lines) {
      if (!layerIds.add(input.layerId)) {
        throw const ConsignmentUserException(
          'consignment.custody_duplicate_layer',
        );
      }
      if (input.quantity <= 0 || input.quantity > 9007199254740991) {
        throw const ConsignmentUserException(
          'consignment.custody_quantity_invalid',
        );
      }
      final layer =
          await (_db.select(_db.consignmentInventoryLayers)..where(
                (l) =>
                    l.id.equals(input.layerId) &
                    l.warehouseId.equals(warehouseId) &
                    l.supplierId.equals(supplierId) &
                    l.agreementId.equals(agreementId) &
                    l.status.equals('open'),
              ))
              .getSingleOrNull();
      if (layer == null || input.quantity > layer.remainingQuantity) {
        throw const ConsignmentUserException(
          'consignment.custody_quantity_exceeds_available',
        );
      }

      int? liabilityUnitCents;
      var liabilityAmountCents = 0;
      if (responsibility == 'company' &&
          (documentType == 'loss' || documentType == 'damage')) {
        if (layer.settlementBasis == 'fixed_unit_cost') {
          liabilityUnitCents = layer.unitCostCents;
        } else {
          liabilityUnitCents = input.liabilityUnitCents;
        }
        if (liabilityUnitCents == null ||
            liabilityUnitCents <= 0 ||
            liabilityUnitCents > 9007199254740991) {
          throw const ConsignmentUserException(
            'consignment.custody_liability_cost_required',
          );
        }
        liabilityAmountCents = MeasuredAmount.cents(
          unitCents: liabilityUnitCents,
          quantity: input.quantity,
          quantityScale: layer.quantityScale,
        );
        if (liabilityAmountCents <= 0 ||
            liabilityAmountCents > 9007199254740991) {
          throw const ConsignmentUserException(
            'consignment.custody_liability_cost_required',
          );
        }
      }

      resolved.add(
        _ResolvedCustodyLine(
          input: input,
          layer: layer,
          liabilityUnitCents: liabilityUnitCents,
          liabilityAmountCents: liabilityAmountCents,
        ),
      );
      normalized.add({
        'layerId': input.layerId,
        'quantity': input.quantity,
        'liabilityUnitCents': liabilityUnitCents,
        'liabilityAmountCents': liabilityAmountCents,
      });
    }

    final instant = occurredAt.toUtc();
    final hash = _hash({
      'documentNumber': number,
      'documentType': documentType,
      'responsibility': responsibility,
      'warehouseId': warehouseId,
      'supplierId': supplierId,
      'agreementId': agreementId,
      'currencyId': currencyId,
      'occurredAt': instant.toIso8601String(),
      'reason': cleanReason,
      'notes': cleanNotes,
      'lines': normalized,
    });
    final prior = await (_db.select(
      _db.consignmentCustodyDocuments,
    )..where((d) => d.requestKey.equals(requestKey))).getSingleOrNull();
    if (prior != null) {
      if (prior.requestHash != hash) {
        throw const ConsignmentUserException('consignment.request_key_reused');
      }
      return prior;
    }

    final documentId = await _db
        .into(_db.consignmentCustodyDocuments)
        .insert(
          ConsignmentCustodyDocumentsCompanion.insert(
            organizationId: access.scope.organizationId,
            branchId: access.scope.branchId,
            databaseId: access.scope.databaseId,
            warehouseId: warehouseId,
            supplierId: supplierId,
            agreementId: agreementId,
            currencyId: currencyId,
            documentNumber: number,
            documentType: documentType,
            responsibility: responsibility,
            occurredAt: instant,
            reason: cleanReason,
            notes: Value(cleanNotes),
            lineCount: resolved.length,
            requestKey: requestKey,
            requestHash: hash,
            createdBy: access.actorId,
          ),
        );
    for (final line in resolved) {
      await _db
          .into(_db.consignmentCustodyItems)
          .insert(
            ConsignmentCustodyItemsCompanion.insert(
              id: const Uuid().v4(),
              documentId: documentId,
              layerId: line.layer.id,
              productId: line.layer.productId,
              variantId: line.layer.variantId,
              batchId: Value(line.layer.batchId),
              quantity: line.input.quantity,
              quantityScale: line.layer.quantityScale,
              liabilityUnitCents: Value(line.liabilityUnitCents),
              liabilityAmountCents: Value(line.liabilityAmountCents),
            ),
          );
    }
    return (_db.select(
      _db.consignmentCustodyDocuments,
    )..where((d) => d.id.equals(documentId))).getSingle();
  });

  Future<ConsignmentCustodyDocument> post({
    required int documentId,
    required String requestKey,
  }) => _db.transaction(() async {
    final access = await _module.requireManageAccess();
    _validateUuid(requestKey, 'requestKey');
    final hash = _hash({'kind': 'posted', 'documentId': documentId});
    final prior = await (_db.select(
      _db.consignmentCustodyEvents,
    )..where((e) => e.requestKey.equals(requestKey))).getSingleOrNull();
    if (prior != null) {
      if (prior.documentId != documentId ||
          prior.kind != 'posted' ||
          prior.requestHash != hash) {
        throw const ConsignmentUserException('consignment.request_key_reused');
      }
      return (_db.select(
        _db.consignmentCustodyDocuments,
      )..where((d) => d.id.equals(documentId))).getSingle();
    }

    final document =
        await (_db.select(
              _db.consignmentCustodyDocuments,
            )..where((d) => d.id.equals(documentId) & d.status.equals('draft')))
            .getSingleOrNull();
    if (document == null) {
      throw const ConsignmentUserException('consignment.custody_not_draft');
    }
    final scope = await WarehouseOperationScope.resolve(
      _db,
      warehouseId: document.warehouseId,
    );
    await scope.validate(_db);
    if (scope.organizationId != access.scope.organizationId ||
        scope.branchId != access.scope.branchId ||
        document.databaseId != access.scope.databaseId) {
      throw const ConsignmentUserException(
        'consignment.warehouse_outside_branch',
      );
    }
    final items = await (_db.select(
      _db.consignmentCustodyItems,
    )..where((i) => i.documentId.equals(documentId))).get();
    if (items.length != document.lineCount) {
      throw StateError('consignment.custody_lines_incomplete');
    }

    final productIds = <int>{};
    final batchedProductIds = <int>{};
    for (final item in items) {
      final layer =
          await (_db.select(_db.consignmentInventoryLayers)..where(
                (l) =>
                    l.id.equals(item.layerId) &
                    l.status.equals('open') &
                    l.remainingQuantity.isBiggerOrEqualValue(item.quantity),
              ))
              .getSingleOrNull();
      if (layer == null ||
          layer.warehouseId != document.warehouseId ||
          layer.supplierId != document.supplierId ||
          layer.agreementId != document.agreementId ||
          layer.productId != item.productId ||
          layer.variantId != item.variantId) {
        throw const ConsignmentUserException(
          'consignment.custody_quantity_changed',
        );
      }

      final ownershipChanged = await _db.customUpdate(
        'UPDATE business_warehouse_stocks '
        'SET supplier_owned_quantity=supplier_owned_quantity-?,updated_at=? '
        'WHERE warehouse_id=? AND variant_id=? '
        'AND supplier_owned_quantity>=?',
        variables: [
          Variable.withInt(item.quantity),
          Variable.withString(DateTime.now().toUtc().toIso8601String()),
          Variable.withString(document.warehouseId),
          Variable.withInt(item.variantId),
          Variable.withInt(item.quantity),
        ],
        updates: {_db.businessWarehouseStocks},
      );
      if (ownershipChanged != 1) {
        throw StateError('consignment.custody_ownership_changed');
      }
      await StockService.adjustStock(
        _db.productDao,
        productId: item.productId,
        variantId: item.variantId,
        quantity: item.quantity,
        direction: StockDirection.decrease,
        scope: scope,
        origin: InventoryOriginIntent.keyed(
          'consignment_custody',
          'consignment_custody:${item.id}',
        ),
      );

      if (item.batchId != null) {
        final consumptions = await BatchService.consumeFifo(
          _db.productDao,
          productId: item.productId,
          variantId: item.variantId,
          quantity: item.quantity,
          consumptionType: 'consignment_custody',
          requiredBatchId: item.batchId,
          requiredSupplierId: document.supplierId,
          notes: '${document.documentType}:${document.documentNumber}',
          scope: scope,
        );
        if (consumptions.length != 1 ||
            consumptions.single.quantity != item.quantity) {
          throw StateError('consignment.custody_batch_consumption_invalid');
        }
        await (_db.update(
          _db.consignmentCustodyItems,
        )..where((i) => i.id.equals(item.id))).write(
          ConsignmentCustodyItemsCompanion(
            batchConsumptionId: Value(consumptions.single.consumptionId),
          ),
        );
        batchedProductIds.add(item.productId);
      }

      final remaining = layer.remainingQuantity - item.quantity;
      final layerChanged = await _db.customUpdate(
        'UPDATE consignment_inventory_layers '
        'SET remaining_quantity=?,status=?,updated_at=? '
        'WHERE id=? AND status=? AND remaining_quantity=?',
        variables: [
          Variable.withInt(remaining),
          Variable.withString(remaining == 0 ? 'exhausted' : 'open'),
          Variable.withString(DateTime.now().toUtc().toIso8601String()),
          Variable.withString(layer.id),
          Variable.withString('open'),
          Variable.withInt(layer.remainingQuantity),
        ],
        updates: {_db.consignmentInventoryLayers},
      );
      if (layerChanged != 1) {
        throw const ConsignmentUserException(
          'consignment.custody_quantity_changed',
        );
      }
      productIds.add(item.productId);
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

    final totalQuantity = items.fold<int>(
      0,
      (sum, item) => sum + item.quantity,
    );
    final totalAmount = items.fold<int>(
      0,
      (sum, item) => sum + item.liabilityAmountCents,
    );
    final journalId = totalAmount == 0
        ? null
        : await _journal.recordConsignmentCustodyLiabilityJournalEntry(
            documentId: document.id,
            signedAmountCents: totalAmount,
            currencyId: document.currencyId,
            entryDate: document.occurredAt,
            reason: document.reason,
            userId: access.actorId,
          );
    await _db
        .into(_db.consignmentCustodyEvents)
        .insert(
          ConsignmentCustodyEventsCompanion.insert(
            documentId: document.id,
            kind: 'posted',
            supplierId: document.supplierId,
            agreementId: document.agreementId,
            currencyId: document.currencyId,
            signedQuantity: totalQuantity,
            signedAmountCents: totalAmount,
            requestKey: requestKey,
            requestHash: hash,
            journalEntryId: Value(journalId),
            settlementStatus: Value(
              totalAmount == 0 ? 'not_applicable' : 'unassigned',
            ),
            actorId: access.actorId,
            occurredAt: document.occurredAt,
          ),
        );

    final now = DateTime.now().toUtc();
    await (_db.update(
      _db.consignmentCustodyDocuments,
    )..where((d) => d.id.equals(document.id))).write(
      ConsignmentCustodyDocumentsCompanion(
        status: const Value('posted'),
        postedBy: Value(access.actorId),
        postedAt: Value(now),
        updatedAt: Value(now),
      ),
    );
    return (_db.select(
      _db.consignmentCustodyDocuments,
    )..where((d) => d.id.equals(document.id))).getSingle();
  });

  Future<ConsignmentCustodyDocument> voidDocument({
    required int documentId,
    required String requestKey,
    required String reason,
  }) => _db.transaction(() async {
    final access = await _module.requireHistoricalManageAccess();
    _validateUuid(requestKey, 'requestKey');
    final cleanReason = reason.trim();
    if (cleanReason.isEmpty || cleanReason.length > 500) {
      throw const ConsignmentUserException('consignment.void_reason_required');
    }
    final hash = _hash({
      'kind': 'voided',
      'documentId': documentId,
      'reason': cleanReason,
    });
    final prior = await (_db.select(
      _db.consignmentCustodyEvents,
    )..where((e) => e.requestKey.equals(requestKey))).getSingleOrNull();
    if (prior != null) {
      if (prior.documentId != documentId ||
          prior.kind != 'voided' ||
          prior.requestHash != hash) {
        throw const ConsignmentUserException('consignment.request_key_reused');
      }
      return (_db.select(
        _db.consignmentCustodyDocuments,
      )..where((d) => d.id.equals(documentId))).getSingle();
    }

    final document =
        await (_db.select(_db.consignmentCustodyDocuments)..where(
              (d) => d.id.equals(documentId) & d.status.equals('posted'),
            ))
            .getSingleOrNull();
    if (document == null) {
      throw const ConsignmentUserException('consignment.custody_not_posted');
    }
    final posted =
        await (_db.select(_db.consignmentCustodyEvents)..where(
              (e) => e.documentId.equals(documentId) & e.kind.equals('posted'),
            ))
            .getSingle();
    if (posted.settlementStatus == 'assigned') {
      throw const ConsignmentUserException(
        'consignment.custody_already_in_settlement',
      );
    }
    final scope = await WarehouseOperationScope.resolve(
      _db,
      warehouseId: document.warehouseId,
    );
    await scope.validate(_db);
    if (scope.organizationId != access.scope.organizationId ||
        scope.branchId != access.scope.branchId ||
        document.databaseId != access.scope.databaseId) {
      throw const ConsignmentUserException(
        'consignment.warehouse_outside_branch',
      );
    }
    final items = await (_db.select(
      _db.consignmentCustodyItems,
    )..where((i) => i.documentId.equals(documentId))).get();
    if (items.length != document.lineCount) {
      throw StateError('consignment.custody_lines_incomplete');
    }

    final productIds = <int>{};
    final batchedProductIds = <int>{};
    for (final item in items) {
      final layer = await (_db.select(
        _db.consignmentInventoryLayers,
      )..where((l) => l.id.equals(item.layerId))).getSingle();
      final layerChanged = await _db.customUpdate(
        'UPDATE consignment_inventory_layers '
        'SET remaining_quantity=remaining_quantity+?,status=?,updated_at=? '
        'WHERE id=? AND remaining_quantity+?<=received_quantity',
        variables: [
          Variable.withInt(item.quantity),
          Variable.withString('open'),
          Variable.withString(DateTime.now().toUtc().toIso8601String()),
          Variable.withString(item.layerId),
          Variable.withInt(item.quantity),
        ],
        updates: {_db.consignmentInventoryLayers},
      );
      if (layerChanged != 1) {
        throw const ConsignmentUserException(
          'consignment.custody_void_conflict',
        );
      }

      await StockService.adjustStock(
        _db.productDao,
        productId: item.productId,
        variantId: item.variantId,
        quantity: item.quantity,
        direction: StockDirection.increase,
        scope: scope,
        origin: InventoryOriginIntent.keyed(
          'consignment_custody_void',
          'consignment_custody_void:${item.id}',
          reference: 'consignment_custody:${item.id}',
        ),
      );
      final ownershipChanged = await _db.customUpdate(
        'UPDATE business_warehouse_stocks '
        'SET supplier_owned_quantity=supplier_owned_quantity+?,updated_at=? '
        'WHERE warehouse_id=? AND variant_id=? '
        'AND supplier_owned_quantity+?<=quantity',
        variables: [
          Variable.withInt(item.quantity),
          Variable.withString(DateTime.now().toUtc().toIso8601String()),
          Variable.withString(document.warehouseId),
          Variable.withInt(item.variantId),
          Variable.withInt(item.quantity),
        ],
        updates: {_db.businessWarehouseStocks},
      );
      if (ownershipChanged != 1) {
        throw StateError('consignment.custody_ownership_restore_failed');
      }

      if (item.batchId != null) {
        if (item.batchConsumptionId == null) {
          throw StateError('consignment.custody_batch_link_missing');
        }
        final restored = await BatchService.restoreExactCustodyConsumption(
          _db.productDao,
          consumptionId: item.batchConsumptionId!,
          notes: 'Void ${document.documentNumber}: $cleanReason',
          scope: scope,
        );
        if (restored != item.quantity) {
          throw StateError('consignment.custody_batch_restore_failed');
        }
        batchedProductIds.add(item.productId);
      } else if (layer.batchId != null) {
        throw StateError('consignment.custody_batch_link_missing');
      }
      productIds.add(item.productId);
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

    final journalId = posted.signedAmountCents == 0
        ? null
        : await _journal.recordConsignmentCustodyLiabilityJournalEntry(
            documentId: document.id,
            signedAmountCents: -posted.signedAmountCents,
            currencyId: document.currencyId,
            entryDate: DateTime.now().toUtc(),
            reason: cleanReason,
            userId: access.actorId,
          );
    await _db
        .into(_db.consignmentCustodyEvents)
        .insert(
          ConsignmentCustodyEventsCompanion.insert(
            documentId: document.id,
            kind: 'voided',
            supplierId: document.supplierId,
            agreementId: document.agreementId,
            currencyId: document.currencyId,
            signedQuantity: -posted.signedQuantity,
            signedAmountCents: -posted.signedAmountCents,
            requestKey: requestKey,
            requestHash: hash,
            journalEntryId: Value(journalId),
            settlementStatus: Value(
              posted.signedAmountCents == 0 ? 'not_applicable' : 'unassigned',
            ),
            actorId: access.actorId,
            reason: Value(cleanReason),
            occurredAt: DateTime.now().toUtc(),
          ),
        );

    final now = DateTime.now().toUtc();
    await (_db.update(
      _db.consignmentCustodyDocuments,
    )..where((d) => d.id.equals(document.id))).write(
      ConsignmentCustodyDocumentsCompanion(
        status: const Value('voided'),
        voidedBy: Value(access.actorId),
        voidedAt: Value(now),
        voidReason: Value(cleanReason),
        updatedAt: Value(now),
      ),
    );
    return (_db.select(
      _db.consignmentCustodyDocuments,
    )..where((d) => d.id.equals(document.id))).getSingle();
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

class _ResolvedCustodyLine {
  const _ResolvedCustodyLine({
    required this.input,
    required this.layer,
    required this.liabilityUnitCents,
    required this.liabilityAmountCents,
  });

  final ConsignmentCustodyLineInput input;
  final ConsignmentInventoryLayer layer;
  final int? liabilityUnitCents;
  final int liabilityAmountCents;
}
