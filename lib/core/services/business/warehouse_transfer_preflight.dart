import 'dart:convert';
import 'package:drift/drift.dart';
import '../../database/app_database.dart';
import '../../measurement/measurement.dart';
import 'branch_currency_policy_store.dart';
import 'warehouse_inventory_reader.dart';
import 'warehouse_operation_scope.dart';

class WarehouseTransferRequestLine {
  const WarehouseTransferRequestLine({
    required this.productId,
    this.variantId,
    required this.quantity,
  });
  final int productId, quantity;
  final int? variantId;
}

class WarehouseTransferLayer {
  const WarehouseTransferLayer({
    required this.batchId,
    required this.quantity,
    required this.unitCostCents,
    required this.valueCents,
    this.purchaseItemId,
    this.supplierId,
  });
  final int batchId, quantity, unitCostCents, valueCents;
  final int? purchaseItemId, supplierId;
}

class WarehouseTransferPreviewLine {
  WarehouseTransferPreviewLine._(
    this.request,
    this.variantId,
    this.quantityScale,
    this.measurementType,
    this.sourceAvailable,
    this.destinationAvailable,
    this.valueCents,
    List<WarehouseTransferLayer> layers,
  ) : layers = List.unmodifiable(layers);
  final WarehouseTransferRequestLine request;
  final String measurementType;
  final int variantId,
      quantityScale,
      sourceAvailable,
      destinationAvailable,
      valueCents;
  final List<WarehouseTransferLayer> layers;
}

class WarehouseTransferPreview {
  WarehouseTransferPreview._(
    this._db,
    this.source,
    this.destination,
    this.currencyId,
    List<WarehouseTransferPreviewLine> lines,
    this._fingerprint,
  ) : lines = List.unmodifiable(lines);
  final AppDatabase _db;
  final WarehouseOperationScope source, destination;
  final int currencyId;
  final List<WarehouseTransferPreviewLine> lines;
  final String _fingerprint;
  int get valueCents => lines.fold(0, (sum, line) => sum + line.valueCents);
}

/// Station 3 preflight only. This neither reserves nor posts stock or journals.
/// The later dispatch transaction must revalidate the preview before writing.
class WarehouseTransferPreflight {
  WarehouseTransferPreflight(this.db, {required this.authorizeWarehouse});
  final AppDatabase db;
  final Future<void> Function(String warehouseId) authorizeWarehouse;
  Future<WarehouseTransferPreview> preview({
    required WarehouseOperationScope source,
    required WarehouseOperationScope destination,
    required List<WarehouseTransferRequestLine> lines,
  }) => db.transaction(() async {
    await authorizeWarehouse(source.warehouseId);
    await authorizeWarehouse(destination.warehouseId);
    await source.validate(db);
    await destination.validate(db);
    if (source.warehouseId == destination.warehouseId ||
        source.branchId != destination.branchId ||
        source.organizationId != destination.organizationId ||
        source.databaseId != destination.databaseId) {
      throw StateError(
        'Transfer requires distinct warehouses of the local branch',
      );
    }
    if (lines.isEmpty || lines.length > 500) {
      throw ArgumentError('Transfer requires 1 to 500 lines');
    }
    final currency = await BranchCurrencyPolicyStore(db).read();
    if (currency == null) {
      throw StateError('Bind operating currency before transfers');
    }
    await BranchCurrencyPolicyStore(
      db,
    ).requireCurrency(currency.id, requireBinding: true);
    final seen = <int>{}, fingerprints = <Object>[];
    final result = <WarehouseTransferPreviewLine>[];
    final sourceRead = await source.forReading(db),
        destinationRead = await destination.forReading(db);
    for (final line in lines) {
      if (line.quantity <= 0 || line.quantity > 9007199254740991) {
        throw ArgumentError(
          'Transfer quantity must be positive safe base units',
        );
      }
      final from = await WarehouseInventoryReader.read(
        db.inventoryAdjustmentDao,
        source,
        line.productId,
        line.variantId,
      );
      final to = await WarehouseInventoryReader.read(
        db.inventoryAdjustmentDao,
        destination,
        line.productId,
        from.variantId,
      );
      if (!seen.add(from.variantId)) {
        throw ArgumentError('Duplicate transfer variant');
      }
      final meta = await db
          .customSelect(
            '''SELECT p.currency_id,p.measurement_type,p.costing_method,p.inventory_tracking_type,
        p.is_active,p.track_inventory,v.is_active AS variant_active FROM products p JOIN product_variants v ON v.product_id=p.id WHERE v.id=?''',
            variables: [Variable.withInt(from.variantId)],
          )
          .getSingle();
      if (meta.read<int>('is_active') != 1 ||
          meta.read<int>('variant_active') != 1 ||
          meta.read<int>('track_inventory') != 1 ||
          meta.readNullable<int>('currency_id') != currency.id) {
        throw StateError(
          'Transfer requires an active stocked product in operating currency',
        );
      }
      if (from.quantity < line.quantity || to.quantity < 0) {
        throw StateError('Insufficient or invalid warehouse stock');
      }
      final scale = MeasurementType.fromDb(
        meta.read<String>('measurement_type'),
      ).quantityScale;
      final batched =
          meta.read<String>('costing_method') == 'fifo' ||
          meta.read<String>('inventory_tracking_type') != 'standard';
      final ownershipRows = await db
          .customSelect(
            '''SELECT warehouse_id,quantity,supplier_owned_quantity,unit_cost_cents
               FROM business_warehouse_stocks
               WHERE variant_id=? AND warehouse_id IN (?,?)
               ORDER BY warehouse_id''',
            variables: [
              Variable.withInt(from.variantId),
              Variable.withString(source.warehouseId),
              Variable.withString(destination.warehouseId),
            ],
          )
          .get();
      if (ownershipRows.length != 2) {
        throw StateError('Transfer warehouse ownership balance is missing');
      }
      final sourceOwnership = ownershipRows.singleWhere(
        (row) => row.read<String>('warehouse_id') == source.warehouseId,
      );
      final sourceSupplierOwned = sourceOwnership.read<int>(
        'supplier_owned_quantity',
      );
      if (sourceSupplierOwned < 0 || sourceSupplierOwned > from.quantity) {
        throw StateError('Invalid supplier-owned source balance');
      }
      final layers = <WarehouseTransferLayer>[];
      final state = <Object?>[
        line.productId,
        from.variantId,
        line.quantity,
        from.quantity,
        from.unitCostCents,
        to.quantity,
        to.unitCostCents,
        meta.data,
        ownershipRows.map((row) => row.data).toList(),
      ];
      int poolValue(int quantity, int cost) => MeasuredAmount.cents(
        unitCents: cost,
        quantity: quantity,
        quantityScale: scale,
      );
      final enterpriseAvailable = from.quantity - sourceSupplierOwned;
      final enterpriseTake = line.quantity < enterpriseAvailable
          ? line.quantity
          : enterpriseAvailable;
      var value =
          poolValue(enterpriseAvailable, from.unitCostCents) -
          poolValue(enterpriseAvailable - enterpriseTake, from.unitCostCents);
      if (!batched) {
        final origins = await db
            .customSelect(
              '''SELECT warehouse_id,quantity,measurement_type,dirty,layers
             FROM inventory_origin_states
             WHERE variant_id=? AND warehouse_id IN (?,?)
             ORDER BY warehouse_id''',
              variables: [
                Variable.withInt(from.variantId),
                Variable.withString(source.warehouseId),
                Variable.withString(destination.warehouseId),
              ],
            )
            .get();
        state.add(origins.map((row) => row.data).toList());
      }
      if (batched) {
        var remaining = line.quantity;
        value = 0;
        for (final target in [
          (sourceRead, from.quantity, true),
          (destinationRead, to.quantity, false),
        ]) {
          final batches = await db
              .customSelect(
                '''SELECT b.id,b.product_id,b.variant_id,b.remaining_quantity,b.unit_cost_cents,
            b.purchase_item_id,b.supplier_id,b.expiry_date,b.manufacturer_lot_number,
            b.received_date,l.id AS consignment_layer_id
            FROM ${target.$1.batches} b
            LEFT JOIN consignment_inventory_layers l
              ON l.batch_id=b.id AND l.status='open'
            WHERE b.variant_id=? AND b.is_active=1 AND b.remaining_quantity>0
            ORDER BY (b.expiry_date IS NULL) ASC,b.expiry_date ASC,b.received_date ASC,b.id ASC''',
                variables: [Variable.withInt(from.variantId)],
              )
              .get();
          if (batches.fold<int>(
                0,
                (sum, b) => sum + b.read<int>('remaining_quantity'),
              ) !=
              target.$2) {
            throw StateError('Batch ledger does not match warehouse stock');
          }
          state.add(batches.map((b) => b.data).toList());
          if (!target.$3) continue;
          for (final batch in batches) {
            if (remaining == 0) break;
            final available = batch.read<int>('remaining_quantity'),
                cost = batch.read<int>('unit_cost_cents');
            if (batch.read<int>('product_id') != line.productId || cost < 0) {
              throw StateError('Invalid source layer');
            }
            final take = remaining < available ? remaining : available;
            final delta =
                batch.readNullable<String>('consignment_layer_id') == null
                ? poolValue(available, cost) - poolValue(available - take, cost)
                : 0;
            layers.add(
              WarehouseTransferLayer(
                batchId: batch.read<int>('id'),
                quantity: take,
                unitCostCents: cost,
                valueCents: delta,
                purchaseItemId: batch.readNullable<int>('purchase_item_id'),
                supplierId: batch.readNullable<int>('supplier_id'),
              ),
            );
            value += delta;
            remaining -= take;
          }
        }
      }
      if (value < 0) {
        throw StateError('Invalid transfer cost');
      }
      result.add(
        WarehouseTransferPreviewLine._(
          line,
          from.variantId,
          scale,
          meta.read<String>('measurement_type'),
          from.quantity,
          to.quantity,
          value,
          layers,
        ),
      );
      fingerprints.add(state);
    }
    return WarehouseTransferPreview._(
      db,
      source,
      destination,
      currency.id,
      result,
      jsonEncode(fingerprints),
    );
  });
  Future<void> validateUnchanged(WarehouseTransferPreview expected) =>
      db.transaction(() async {
        if (!identical(db, expected._db)) {
          throw StateError('Preview belongs to another database');
        }
        final current = await preview(
          source: expected.source,
          destination: expected.destination,
          lines: expected.lines.map((l) => l.request).toList(),
        );
        if (current.currencyId != expected.currencyId ||
            current._fingerprint != expected._fingerprint) {
          throw StateError('Transfer stock or layers changed; review again');
        }
      });
}
