import 'dart:convert';

import 'package:drift/drift.dart';

import '../../database/app_database.dart';
import '../business/warehouse_operation_scope.dart';

class ConsignmentReturnRestoration {
  const ConsignmentReturnRestoration(this.quantity, this.reversedAmountCents);
  final int quantity;
  final int reversedAmountCents;
  static const empty = ConsignmentReturnRestoration(0, 0);
}

/// Restores supplier ownership from the exact source portions returned by a
/// linked sale return. It never infers a supplier from the product card.
class ConsignmentLinkedReturnService {
  ConsignmentLinkedReturnService._();

  static Future<ConsignmentReturnRestoration> restoreAfterStock(
    DatabaseAccessor<AppDatabase> dao, {
    required Sale sale,
    required SaleItem saleItem,
    required SaleReturnItem returnItem,
    required WarehouseOperationScope scope,
    required bool usesBatches,
    required bool restoresStock,
  }) async {
    final db = dao.attachedDatabase;
    final returnDocument = await (db.select(
      db.saleReturns,
    )..where((r) => r.id.equals(returnItem.returnId))).getSingle();
    final existing =
        await (db.select(db.consignmentObligationEvents)..where(
              (e) =>
                  e.kind.equals('linked_return_reversal') &
                  e.sourceItemId.equals(returnItem.id),
            ))
            .get();
    if (existing.isNotEmpty) {
      throw StateError('Consignment linked-return reversal already exists.');
    }

    final pieces = restoresStock
        ? usesBatches
              ? await _batchPieces(db, saleItem.id, returnItem.id)
              : await _wacPieces(db, scope, saleItem.id, returnItem.id)
        : await _allocationPieces(db, saleItem.id, returnItem.quantity);
    if (pieces.isEmpty) return ConsignmentReturnRestoration.empty;

    var restoredQuantity = 0;
    var reversedAmount = 0;
    for (final piece in pieces) {
      final allocation = piece.allocation;
      final available = allocation.quantity - allocation.reversedQuantity;
      if (piece.quantity <= 0 || piece.quantity > available) {
        throw StateError('Return exceeds its consignment allocation.');
      }
      final newReversedQuantity = allocation.reversedQuantity + piece.quantity;
      final cumulativeAmount = _proportional(
        allocation.obligationCents,
        newReversedQuantity,
        allocation.quantity,
      );
      final amount = cumulativeAmount - allocation.reversedObligationCents;
      final fullyReversed = newReversedQuantity == allocation.quantity;
      final changed =
          await (db.update(db.consignmentSaleAllocations)..where(
                (a) =>
                    a.id.equals(allocation.id) &
                    a.reversedQuantity.equals(allocation.reversedQuantity) &
                    a.reversedObligationCents.equals(
                      allocation.reversedObligationCents,
                    ),
              ))
              .write(
                ConsignmentSaleAllocationsCompanion(
                  reversedQuantity: Value(newReversedQuantity),
                  reversedObligationCents: Value(cumulativeAmount),
                  status: Value(
                    fullyReversed ? 'fully_reversed' : 'partially_reversed',
                  ),
                  updatedAt: Value(DateTime.now().toUtc()),
                ),
              );
      if (changed != 1) {
        throw StateError('Consignment allocation changed during return.');
      }
      if (restoresStock) {
        final layerChanged = await db.customUpdate(
          'UPDATE consignment_inventory_layers SET '
          'remaining_quantity=remaining_quantity+?,status=?,updated_at=? '
          'WHERE id=? AND remaining_quantity+?<=received_quantity',
          variables: [
            Variable.withInt(piece.quantity),
            Variable.withString('open'),
            Variable.withString(DateTime.now().toUtc().toIso8601String()),
            Variable.withString(allocation.layerId),
            Variable.withInt(piece.quantity),
          ],
          updates: {db.consignmentInventoryLayers},
        );
        if (layerChanged != 1) {
          throw StateError('Consignment ownership layer cannot accept return.');
        }
      }
      await db
          .into(db.consignmentObligationEvents)
          .insert(
            ConsignmentObligationEventsCompanion.insert(
              allocationId: allocation.id,
              supplierId: allocation.supplierId,
              agreementId: allocation.agreementId,
              currencyId: sale.currencyId,
              kind: 'linked_return_reversal',
              signedQuantity: -piece.quantity,
              signedAmountCents: -amount,
              restoresStock: Value(restoresStock),
              sourceTable: 'sale_returns',
              sourceId: returnItem.returnId,
              sourceItemId: returnItem.id,
              requestKey:
                  'sale_return:${returnItem.returnId}:item:${returnItem.id}:allocation:${allocation.id}',
              occurredAt: returnDocument.returnDate.toUtc(),
            ),
          );
      restoredQuantity += piece.quantity;
      reversedAmount += amount;
    }

    if (restoresStock) {
      final stockChanged = await db.customUpdate(
        'UPDATE business_warehouse_stocks SET '
        'supplier_owned_quantity=supplier_owned_quantity+?,updated_at=? '
        'WHERE warehouse_id=? AND variant_id=? '
        'AND supplier_owned_quantity+?<=quantity',
        variables: [
          Variable.withInt(restoredQuantity),
          Variable.withString(DateTime.now().toUtc().toIso8601String()),
          Variable.withString(scope.warehouseId),
          Variable.withInt(pieces.first.allocationVariantId),
          Variable.withInt(restoredQuantity),
        ],
        updates: {db.businessWarehouseStocks},
      );
      if (stockChanged != 1) {
        throw StateError('Supplier ownership cannot be restored to warehouse.');
      }
    }
    return ConsignmentReturnRestoration(restoredQuantity, reversedAmount);
  }

  /// Reverses the ownership restoration made by a linked return before the
  /// physical return quantity is removed again.
  static Future<ConsignmentReturnRestoration> prepareVoidBeforeStock(
    DatabaseAccessor<AppDatabase> dao, {
    required SaleReturnItem returnItem,
    required WarehouseOperationScope scope,
  }) async {
    final db = dao.attachedDatabase;
    final prior =
        await (db.select(db.consignmentObligationEvents)..where(
              (e) =>
                  e.kind.equals('linked_return_reversal') &
                  e.sourceTable.equals('sale_returns') &
                  e.sourceId.equals(returnItem.returnId) &
                  e.sourceItemId.equals(returnItem.id),
            ))
            .get();
    if (prior.isEmpty) return ConsignmentReturnRestoration.empty;
    final duplicate =
        await (db.select(db.consignmentObligationEvents)..where(
              (e) =>
                  e.kind.equals('return_void_reaccrual') &
                  e.sourceItemId.equals(returnItem.id),
            ))
            .get();
    if (duplicate.isNotEmpty) {
      throw StateError('Consignment return void was already recorded.');
    }

    var quantity = 0;
    var amount = 0;
    int? variantId;
    for (final reversal in prior) {
      final allocation = await (db.select(
        db.consignmentSaleAllocations,
      )..where((a) => a.id.equals(reversal.allocationId))).getSingle();
      final restoreQuantity = -reversal.signedQuantity;
      final restoreAmount = -reversal.signedAmountCents;
      if (restoreQuantity <= 0 ||
          restoreQuantity > allocation.reversedQuantity ||
          restoreAmount < 0 ||
          restoreAmount > allocation.reversedObligationCents) {
        throw StateError('Invalid consignment return reversal history.');
      }
      final layer = await (db.select(
        db.consignmentInventoryLayers,
      )..where((l) => l.id.equals(allocation.layerId))).getSingle();
      variantId ??= layer.variantId;
      if (variantId != layer.variantId ||
          layer.warehouseId != scope.warehouseId) {
        throw StateError('Return void spans an invalid custody scope.');
      }
      if (reversal.restoresStock) {
        final layerChanged = await db.customUpdate(
          'UPDATE consignment_inventory_layers SET '
          'remaining_quantity=remaining_quantity-?,'
          "status=CASE WHEN remaining_quantity-?=0 THEN 'exhausted' ELSE 'open' END,"
          'updated_at=? WHERE id=? AND remaining_quantity>=?',
          variables: [
            Variable.withInt(restoreQuantity),
            Variable.withInt(restoreQuantity),
            Variable.withString(DateTime.now().toUtc().toIso8601String()),
            Variable.withString(layer.id),
            Variable.withInt(restoreQuantity),
          ],
          updates: {db.consignmentInventoryLayers},
        );
        if (layerChanged != 1) {
          throw StateError(
            'Returned consignment layer is no longer available.',
          );
        }
      }
      final newQuantity = allocation.reversedQuantity - restoreQuantity;
      final newAmount = allocation.reversedObligationCents - restoreAmount;
      final allocationChanged =
          await (db.update(db.consignmentSaleAllocations)..where(
                (a) =>
                    a.id.equals(allocation.id) &
                    a.reversedQuantity.equals(allocation.reversedQuantity),
              ))
              .write(
                ConsignmentSaleAllocationsCompanion(
                  reversedQuantity: Value(newQuantity),
                  reversedObligationCents: Value(newAmount),
                  status: Value(
                    newQuantity == 0 ? 'active' : 'partially_reversed',
                  ),
                  updatedAt: Value(DateTime.now().toUtc()),
                ),
              );
      if (allocationChanged != 1) {
        throw StateError('Consignment allocation changed during return void.');
      }
      await db
          .into(db.consignmentObligationEvents)
          .insert(
            ConsignmentObligationEventsCompanion.insert(
              allocationId: allocation.id,
              supplierId: allocation.supplierId,
              agreementId: allocation.agreementId,
              currencyId: reversal.currencyId,
              kind: 'return_void_reaccrual',
              signedQuantity: restoreQuantity,
              signedAmountCents: restoreAmount,
              restoresStock: Value(reversal.restoresStock),
              sourceTable: 'sale_returns',
              sourceId: returnItem.returnId,
              sourceItemId: returnItem.id,
              requestKey:
                  'sale_return_void:${returnItem.returnId}:item:${returnItem.id}:allocation:${allocation.id}',
              occurredAt: DateTime.now().toUtc(),
            ),
          );
      quantity += restoreQuantity;
      amount += restoreAmount;
    }
    final restockedQuantity = prior
        .where((event) => event.restoresStock)
        .fold<int>(0, (sum, event) => sum - event.signedQuantity);
    if (restockedQuantity > 0) {
      final changed = await db.customUpdate(
        'UPDATE business_warehouse_stocks SET '
        'supplier_owned_quantity=supplier_owned_quantity-?,updated_at=? '
        'WHERE warehouse_id=? AND variant_id=? AND supplier_owned_quantity>=?',
        variables: [
          Variable.withInt(restockedQuantity),
          Variable.withString(DateTime.now().toUtc().toIso8601String()),
          Variable.withString(scope.warehouseId),
          Variable.withInt(variantId!),
          Variable.withInt(restockedQuantity),
        ],
        updates: {db.businessWarehouseStocks},
      );
      if (changed != 1) {
        throw StateError(
          'Supplier ownership cannot be removed for return void.',
        );
      }
    }
    return ConsignmentReturnRestoration(quantity, amount);
  }

  /// Restores every supplier-owned portion consumed by a sale when the sale
  /// itself is voided. Linked returns are cascade-voided first, so an
  /// allocation must be active again before this final inverse is applied.
  static Future<ConsignmentReturnRestoration> restoreSaleVoidAfterStock(
    DatabaseAccessor<AppDatabase> dao, {
    required Sale sale,
    required SaleItem saleItem,
    required WarehouseOperationScope scope,
  }) async {
    final db = dao.attachedDatabase;
    final allocations =
        await (db.select(db.consignmentSaleAllocations)..where(
              (a) =>
                  a.saleItemId.equals(saleItem.id) &
                  a.warehouseId.equals(scope.warehouseId),
            ))
            .get();
    if (allocations.isEmpty) return ConsignmentReturnRestoration.empty;

    var quantity = 0;
    var amount = 0;
    int? variantId;
    for (final allocation in allocations) {
      final restoreQuantity = allocation.quantity - allocation.reversedQuantity;
      final restoreAmount =
          allocation.obligationCents - allocation.reversedObligationCents;
      if (restoreQuantity <= 0 || restoreAmount < 0) {
        throw StateError('Consignment sale allocation is not voidable.');
      }
      final layer = await (db.select(
        db.consignmentInventoryLayers,
      )..where((l) => l.id.equals(allocation.layerId))).getSingle();
      variantId ??= layer.variantId;
      if (variantId != layer.variantId ||
          layer.variantId != (saleItem.variantId ?? layer.variantId) ||
          layer.warehouseId != scope.warehouseId) {
        throw StateError('Sale void spans an invalid consignment scope.');
      }
      final layerChanged = await db.customUpdate(
        'UPDATE consignment_inventory_layers SET '
        'remaining_quantity=remaining_quantity+?,status=?,updated_at=? '
        'WHERE id=? AND remaining_quantity+?<=received_quantity',
        variables: [
          Variable.withInt(restoreQuantity),
          Variable.withString('open'),
          Variable.withString(DateTime.now().toUtc().toIso8601String()),
          Variable.withString(layer.id),
          Variable.withInt(restoreQuantity),
        ],
        updates: {db.consignmentInventoryLayers},
      );
      if (layerChanged != 1) {
        throw StateError('Consignment layer cannot accept sale void.');
      }
      await db
          .into(db.consignmentObligationEvents)
          .insert(
            ConsignmentObligationEventsCompanion.insert(
              allocationId: allocation.id,
              supplierId: allocation.supplierId,
              agreementId: allocation.agreementId,
              currencyId: sale.currencyId,
              kind: 'sale_void_reversal',
              signedQuantity: -restoreQuantity,
              signedAmountCents: -restoreAmount,
              sourceTable: 'sales',
              sourceId: sale.id,
              sourceItemId: saleItem.id,
              requestKey:
                  'sale_void:${sale.id}:item:${saleItem.id}:allocation:${allocation.id}',
              occurredAt: DateTime.now().toUtc(),
            ),
          );
      final allocationChanged =
          await (db.update(db.consignmentSaleAllocations)..where(
                (a) =>
                    a.id.equals(allocation.id) &
                    a.reversedQuantity.equals(allocation.reversedQuantity) &
                    a.reversedObligationCents.equals(
                      allocation.reversedObligationCents,
                    ),
              ))
              .write(
                ConsignmentSaleAllocationsCompanion(
                  reversedQuantity: Value(allocation.quantity),
                  reversedObligationCents: Value(allocation.obligationCents),
                  status: const Value('fully_reversed'),
                  updatedAt: Value(DateTime.now().toUtc()),
                ),
              );
      if (allocationChanged != 1) {
        throw StateError('Consignment allocation changed during sale void.');
      }
      quantity += restoreQuantity;
      amount += restoreAmount;
    }
    final changed = await db.customUpdate(
      'UPDATE business_warehouse_stocks SET '
      'supplier_owned_quantity=supplier_owned_quantity+?,updated_at=? '
      'WHERE warehouse_id=? AND variant_id=? '
      'AND supplier_owned_quantity+?<=quantity',
      variables: [
        Variable.withInt(quantity),
        Variable.withString(DateTime.now().toUtc().toIso8601String()),
        Variable.withString(scope.warehouseId),
        Variable.withInt(variantId!),
        Variable.withInt(quantity),
      ],
      updates: {db.businessWarehouseStocks},
    );
    if (changed != 1) {
      throw StateError('Supplier ownership cannot be restored for sale void.');
    }
    return ConsignmentReturnRestoration(quantity, amount);
  }

  static Future<List<_ReturnPiece>> _allocationPieces(
    AppDatabase db,
    int saleItemId,
    int requestedQuantity,
  ) async {
    final allocations =
        await (db.select(db.consignmentSaleAllocations)
              ..where((row) => row.saleItemId.equals(saleItemId))
              ..orderBy([(row) => OrderingTerm.asc(row.sequence)]))
            .get();
    var remaining = requestedQuantity;
    final result = <_ReturnPiece>[];
    for (final allocation in allocations) {
      if (remaining == 0) break;
      final available = allocation.quantity - allocation.reversedQuantity;
      if (available <= 0) continue;
      final quantity = available < remaining ? available : remaining;
      final layer = await (db.select(
        db.consignmentInventoryLayers,
      )..where((row) => row.id.equals(allocation.layerId))).getSingle();
      result.add(
        _ReturnPiece(
          quantity: quantity,
          allocation: allocation,
          allocationVariantId: layer.variantId,
        ),
      );
      remaining -= quantity;
    }
    return result;
  }

  static Future<List<_ReturnPiece>> _batchPieces(
    AppDatabase db,
    int saleItemId,
    int returnItemId,
  ) async {
    final rows = await db
        .customSelect(
          'SELECT bc.batch_id,bc.quantity,a.id AS allocation_id '
          'FROM batch_consumptions bc '
          'JOIN consignment_inventory_layers l ON l.batch_id=bc.batch_id '
          'JOIN consignment_sale_allocations a '
          'ON a.layer_id=l.id AND a.sale_item_id=? '
          "WHERE bc.sale_return_item_id=? AND bc.direction='in' "
          "AND bc.consumption_type='sale_return_reverse' ORDER BY bc.id",
          variables: [
            Variable.withInt(saleItemId),
            Variable.withInt(returnItemId),
          ],
        )
        .get();
    return _loadPieces(db, rows);
  }

  static Future<List<_ReturnPiece>> _wacPieces(
    AppDatabase db,
    WarehouseOperationScope scope,
    int saleItemId,
    int returnItemId,
  ) async {
    final event = await db
        .customSelect(
          'SELECT allocations FROM inventory_origin_events '
          'WHERE warehouse_id=? AND event_key=?',
          variables: [
            Variable.withString(scope.warehouseId),
            Variable.withString('return:$returnItemId'),
          ],
        )
        .getSingleOrNull();
    if (event == null) return const [];
    final parts = (jsonDecode(event.read<String>('allocations')) as List)
        .map((value) => Map<String, dynamic>.from(value as Map))
        .where((value) => value['k'] == 'consignment_receipt')
        .toList();
    final result = <_ReturnPiece>[];
    for (final part in parts) {
      final reference = part['r'] as String?;
      final quantity = part['q'] as int? ?? 0;
      const prefix = 'consignment_receipt:';
      if (reference == null || !reference.startsWith(prefix) || quantity <= 0) {
        throw StateError('Invalid consignment return source.');
      }
      final receiptItemId = reference.substring(prefix.length);
      final row = await db
          .customSelect(
            'SELECT a.id AS allocation_id,? AS quantity '
            'FROM consignment_sale_allocations a '
            'JOIN consignment_inventory_layers l ON l.id=a.layer_id '
            'WHERE a.sale_item_id=? AND l.receipt_item_id=?',
            variables: [
              Variable.withInt(quantity),
              Variable.withInt(saleItemId),
              Variable.withString(receiptItemId),
            ],
          )
          .getSingleOrNull();
      if (row == null) {
        throw StateError(
          'Returned consignment source was not sold by this line.',
        );
      }
      result.addAll(await _loadPieces(db, [row]));
    }
    return result;
  }

  static Future<List<_ReturnPiece>> _loadPieces(
    AppDatabase db,
    List<QueryRow> rows,
  ) async {
    final result = <_ReturnPiece>[];
    for (final row in rows) {
      final allocationId = row.read<String>('allocation_id');
      final allocation = await (db.select(
        db.consignmentSaleAllocations,
      )..where((a) => a.id.equals(allocationId))).getSingle();
      final layer = await (db.select(
        db.consignmentInventoryLayers,
      )..where((l) => l.id.equals(allocation.layerId))).getSingle();
      result.add(
        _ReturnPiece(
          quantity: row.read<int>('quantity'),
          allocation: allocation,
          allocationVariantId: layer.variantId,
        ),
      );
    }
    return result;
  }

  static int _proportional(int total, int quantity, int denominator) =>
      ((BigInt.from(total) * BigInt.from(quantity) +
                  BigInt.from(denominator ~/ 2)) ~/
              BigInt.from(denominator))
          .toInt();
}

class _ReturnPiece {
  const _ReturnPiece({
    required this.quantity,
    required this.allocation,
    required this.allocationVariantId,
  });
  final int quantity;
  final ConsignmentSaleAllocation allocation;
  final int allocationVariantId;
}
