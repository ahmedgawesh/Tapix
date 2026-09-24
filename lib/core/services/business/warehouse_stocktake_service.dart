import '../../measurement/measurement.dart';
import 'dart:convert';
import 'package:drift/drift.dart';

import '../../database/app_database.dart';
import '../inventory/inventory_adjustment_service.dart';
import 'warehouse_operation_scope.dart';
import 'warehouse_batch_scope.dart';

/// A database-bound observation. Callers cannot fabricate an expected balance.
class WarehouseStocktakeSnapshot {
  WarehouseStocktakeSnapshot._(
    this._db,
    this.scope,
    this.productId,
    this.variantId,
    this.currencyId,
    this.quantity,
    this._state,
  );

  final AppDatabase _db;
  final WarehouseOperationScope scope;
  final int productId, variantId, currencyId, quantity;
  final Map<String, Object?> _state;
}

class WarehouseRevaluationPreview {
  WarehouseRevaluationPreview._(
    this.snapshot,
    this.newUnitCostCents,
    this.deltaValueCents,
  );
  final WarehouseStocktakeSnapshot snapshot;
  final int newUnitCostCents, deltaValueCents;
}

class WarehouseCount {
  const WarehouseCount({required this.snapshot, required this.countedQuantity});
  final WarehouseStocktakeSnapshot snapshot;

  /// Base units: pieces, or thousandths for measured products.
  final int countedQuantity;
}

/// Internal stocktake posting; entry points must authorize the warehouse/user.
/// Observed balances are checked again inside the same transaction as all
/// adjustments and journals. Changed stock requires a fresh count/review.
class WarehouseStocktakeService {
  WarehouseStocktakeService(this._db, this._adjustments);
  final AppDatabase _db;
  final InventoryAdjustmentService _adjustments;

  Future<Map<String, Object?>> _read(
    WarehouseOperationScope scope,
    int variantId,
  ) async {
    await scope.validate(_db);
    final row = await _db
        .customSelect(
          '''
      SELECT s.quantity, s.supplier_owned_quantity, s.unit_cost_cents, s.updated_at, v.product_id,
        v.is_active AS variant_active, p.is_active AS product_active,
        p.track_inventory, p.currency_id, p.measurement_type,
        p.costing_method, p.inventory_tracking_type
      FROM business_warehouse_stocks s
      JOIN product_variants v ON v.id = s.variant_id
      JOIN products p ON p.id = v.product_id
      WHERE s.warehouse_id = ? AND s.variant_id = ?
    ''',
          variables: [
            Variable.withString(scope.warehouseId),
            Variable.withInt(variantId),
          ],
        )
        .getSingleOrNull();
    if (row == null ||
        row.read<int>('variant_active') != 1 ||
        row.read<int>('product_active') != 1 ||
        row.read<int>('track_inventory') != 1 ||
        row.readNullable<int>('currency_id') == null) {
      throw StateError(
        'Stocktake requires an active initialized inventory variant with currency',
      );
    }
    final state = Map<String, Object?>.of(row.data);
    if (row.read<String>('costing_method') == 'fifo' ||
        row.read<String>('inventory_tracking_type') != 'standard') {
      final layers = await _db
          .customSelect(
            '''SELECT pb.id, pb.remaining_quantity,
        pb.unit_cost_cents, pb.received_date, pb.expiry_date, pb.is_active
        FROM product_batches pb WHERE pb.variant_id = ?
          AND ${WarehouseBatchScope.operationPredicate('pb')} ORDER BY pb.id''',
            variables: [
              Variable.withInt(variantId),
              ...WarehouseBatchScope.operationVariables(scope),
            ],
          )
          .get();
      state['layers'] = jsonEncode(layers.map((r) => r.data).toList());
    }
    return Map.unmodifiable(state);
  }

  Future<WarehouseStocktakeSnapshot> capture({
    required WarehouseOperationScope scope,
    required int variantId,
  }) => _db.transaction(() async {
    final state = await _read(scope, variantId);
    return WarehouseStocktakeSnapshot._(
      _db,
      scope,
      state['product_id']! as int,
      variantId,
      state['currency_id']! as int,
      state['quantity']! as int,
      state,
    );
  });

  WarehouseRevaluationPreview previewRevaluation({
    required WarehouseStocktakeSnapshot snapshot,
    required int newUnitCostCents,
  }) {
    final supplierOwned = snapshot._state['supplier_owned_quantity']! as int;
    if (supplierOwned > 0) {
      throw StateError(
        'Revaluation requires a source-aware consignment custody workflow.',
      );
    }
    if (!identical(snapshot._db, _db) ||
        snapshot.quantity <= 0 ||
        newUnitCostCents < 0) {
      throw ArgumentError(
        'Revaluation requires an owned positive stock snapshot',
      );
    }
    final scale = snapshot._state['measurement_type'] == 'piece' ? 1 : 1000;
    int value(int cost, int quantity) => MeasuredAmount.cents(
      unitCents: cost,
      quantity: quantity,
      quantityScale: scale,
    );
    int delta;
    if (snapshot._state['costing_method'] == 'fifo') {
      final layers = (jsonDecode(snapshot._state['layers']! as String) as List)
          .cast<Map<String, dynamic>>()
          .where(
            (r) => r['is_active'] == 1 && (r['remaining_quantity'] as int) > 0,
          )
          .toList();
      if (layers.fold<int>(
            0,
            (sum, r) => sum + (r['remaining_quantity'] as int),
          ) !=
          snapshot.quantity) {
        throw StateError('FIFO layer quantities do not match inventory');
      }
      delta = layers.fold<int>(
        0,
        (sum, r) =>
            sum +
            value(newUnitCostCents, r['remaining_quantity'] as int) -
            value(r['unit_cost_cents'] as int, r['remaining_quantity'] as int),
      );
    } else {
      delta =
          value(newUnitCostCents, snapshot.quantity) -
          value(snapshot._state['unit_cost_cents']! as int, snapshot.quantity);
    }
    if (delta == 0) throw ArgumentError('Revaluation has no value change');
    return WarehouseRevaluationPreview._(snapshot, newUnitCostCents, delta);
  }

  Future<InventoryAdjustmentResult> postRevaluation({
    required WarehouseRevaluationPreview preview,
    required String reason,
    int? userId,
  }) => _db.transaction(() async {
    final snapshot = preview.snapshot;
    if (!identical(snapshot._db, _db)) {
      throw ArgumentError('Foreign revaluation preview');
    }
    final current = await _read(snapshot.scope, snapshot.variantId);
    if (current.length != snapshot._state.length ||
        current.entries.any((e) => snapshot._state[e.key] != e.value)) {
      throw StateError(
        'Inventory changed after valuation preview; review again',
      );
    }
    final result = await _adjustments.adjust(
      productId: snapshot.productId,
      variantId: snapshot.variantId,
      scope: snapshot.scope,
      type: InventoryAdjustmentType.revaluation,
      newUnitCostCents: preview.newUnitCostCents,
      currencyId: snapshot.currencyId,
      reason: reason,
      userId: userId,
    );
    if (result.totalValueCents != preview.deltaValueCents) {
      throw StateError('Revaluation differs from the approved preview');
    }
    return result;
  });

  Future<List<InventoryAdjustmentResult>> postCounts({
    required List<WarehouseCount> counts,
    required String reason,
    int? userId,
  }) async {
    final requests = List<WarehouseCount>.unmodifiable(counts);
    if (requests.isEmpty || requests.length > 500 || reason.trim().isEmpty) {
      throw ArgumentError('Stocktake requires 1–500 counts and a reason');
    }
    final warehouse = requests.first.snapshot.scope.warehouseId;
    final variants = <int>{};
    for (final request in requests) {
      if (!identical(request.snapshot._db, _db) ||
          request.snapshot.scope.warehouseId != warehouse ||
          !variants.add(request.snapshot.variantId) ||
          request.countedQuantity < 0 ||
          request.countedQuantity > 9007199254740991) {
        throw ArgumentError('Invalid, duplicated, or foreign stocktake count');
      }
    }
    return _db.transaction(() async {
      for (final request in requests) {
        final snapshot = request.snapshot;
        final supplierOwned =
            snapshot._state['supplier_owned_quantity']! as int;
        if (supplierOwned > 0 && request.countedQuantity != snapshot.quantity) {
          throw StateError(
            'A custody count with supplier-owned stock must identify the '
            'affected source before posting.',
          );
        }
        final current = await _read(snapshot.scope, snapshot.variantId);
        if (current.length != snapshot._state.length ||
            current.entries.any((e) => snapshot._state[e.key] != e.value)) {
          throw StateError(
            'Stock changed since count preview; review a fresh count',
          );
        }
      }
      final results = <InventoryAdjustmentResult>[];
      for (final request in requests) {
        final snapshot = request.snapshot;
        final delta = request.countedQuantity - snapshot.quantity;
        if (delta == 0) continue;
        results.add(
          await _adjustments.adjust(
            productId: snapshot.productId,
            variantId: snapshot.variantId,
            type: delta > 0
                ? InventoryAdjustmentType.gain
                : InventoryAdjustmentType.shrinkage,
            quantityDelta: delta,
            currencyId: snapshot.currencyId,
            reason: reason.trim(),
            notes:
                'Stocktake: observed=${snapshot.quantity}; counted=${request.countedQuantity}',
            userId: userId,
            scope: snapshot.scope,
          ),
        );
      }
      return List.unmodifiable(results);
    });
  }
}
