import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../database/app_database.dart';
import '../../measurement/measurement.dart';
import '../business/warehouse_batch_scope.dart';
import '../business/warehouse_operation_scope.dart';
import 'supplier_identity_rules.dart';

class ConsignmentSaleAllocationSummary {
  const ConsignmentSaleAllocationSummary(this.quantity, this.obligationCents);
  final int quantity;
  final int obligationCents;
  static const empty = ConsignmentSaleAllocationSummary(0, 0);
}

/// Freezes the exact supplier-owned source selected by the existing WAC or
/// batch source order before physical stock is reduced.
class ConsignmentSaleAllocationService {
  ConsignmentSaleAllocationService._();

  static Future<ConsignmentSaleAllocationSummary> allocateBeforeStock(
    DatabaseAccessor<AppDatabase> dao, {
    required SaleItem item,
    required Sale sale,
    required WarehouseOperationScope scope,
  }) async {
    final db = dao.attachedDatabase;
    if (await (db.select(db.consignmentSaleAllocations)
          ..where((a) => a.saleItemId.equals(item.id)))
        .get()
        .then((rows) => rows.isNotEmpty)) {
      throw StateError('Consignment sale allocation already exists.');
    }
    final stock = await _stock(
      dao,
      scope.warehouseId,
      item.productId,
      item.variantId,
    );
    final supplierOwned = stock.read<int>('supplier_owned_quantity');
    final selectedLayerId = item.consignmentLayerId;
    // A missing consignment layer is an explicit enterprise-owned selection.
    // This includes verified ordinary supplier identities and the deliberately
    // unverified source shown by the sale picker. Never turn that selection
    // into consignment merely because a supplier-owned layer happens to be
    // first in FIFO/WAC order. Consignment must always carry its exact layer.
    if (selectedLayerId == null) {
      final enterpriseOwned = stock.read<int>('quantity') - supplierOwned;
      if (enterpriseOwned < item.quantity) {
        throw SupplierIdentityException(
          item.supplierIdentityId == null
              ? 'stock_sources.insufficient'
              : 'supplier_identity.insufficient_source_quantity',
        );
      }
      return ConsignmentSaleAllocationSummary.empty;
    }
    if (supplierOwned == 0) return ConsignmentSaleAllocationSummary.empty;
    final itemDiscount = item.itemDiscountAtPostCents?.toBigInt().toInt();
    final invoiceDiscount = item.invoiceDiscountAtPostCents?.toBigInt().toInt();
    if (itemDiscount == null ||
        invoiceDiscount == null ||
        itemDiscount + invoiceDiscount !=
            item.discountCents.toBigInt().toInt()) {
      throw StateError(
        'Consignment sale requires valid item and invoice discount snapshots.',
      );
    }

    final variantId = stock.read<int>('variant_id');
    final product = await (db.select(
      db.products,
    )..where((p) => p.id.equals(item.productId))).getSingle();
    final batched =
        product.costingMethod == 'fifo' ||
        product.inventoryTrackingType == 'batch' ||
        product.inventoryTrackingType == 'batch_expiry';
    final sources = batched
        ? await _batchSources(
            dao,
            scope,
            item.productId,
            variantId,
            supplierOwned,
          )
        : await _wacSources(
            dao,
            scope,
            variantId,
            stock.read<int>('quantity'),
            supplierOwned,
          );
    final matches = sources
        .where((source) => source.layer?.id == selectedLayerId)
        .toList(growable: false);
    final available = matches.fold<int>(
      0,
      (sum, source) => sum + source.quantity,
    );
    if (available < item.quantity || matches.isEmpty) {
      throw const SupplierIdentityException('stock_sources.insufficient');
    }
    final selected = _take(matches, item.quantity);
    if (selected.any((source) => source.layer == null)) {
      throw const SupplierIdentityException('stock_sources.source_mismatch');
    }
    final weights = selected.map((source) => source.quantity).toList();
    final subtotal = _allocate(item.subtotalCents.toBigInt().toInt(), weights);
    final lineDiscount = _allocate(itemDiscount, weights);
    final invoiceDiscountShares = _allocate(invoiceDiscount, weights);
    final tax = _allocate(item.taxCents.toBigInt().toInt(), weights);

    var sequence = 0;
    var supplierQuantity = 0;
    var dueTotal = 0;
    for (var index = 0; index < selected.length; index++) {
      final source = selected[index];
      final layer = source.layer;
      if (layer == null) continue;
      final base =
          subtotal[index] -
          (layer.includeLineDiscount ? lineDiscount[index] : 0) -
          (layer.includeInvoiceDiscount ? invoiceDiscountShares[index] : 0) +
          (layer.includeSalesTax ? tax[index] : 0);
      if (base < 0) throw StateError('Negative consignment settlement base.');
      final due = layer.settlementBasis == 'fixed_unit_cost'
          ? MeasuredAmount.cents(
              unitCents: layer.unitCostCents!,
              quantity: source.quantity,
              quantityScale: item.quantityScale,
            )
          : _bps(base, layer.supplierShareBps!);
      final allocationId = const Uuid().v4();
      sequence++;
      await db
          .into(db.consignmentSaleAllocations)
          .insert(
            ConsignmentSaleAllocationsCompanion.insert(
              id: allocationId,
              saleItemId: item.id,
              layerId: layer.id,
              warehouseId: scope.warehouseId,
              supplierId: layer.supplierId,
              agreementId: layer.agreementId,
              sequence: sequence,
              quantity: source.quantity,
              quantityScale: item.quantityScale,
              measurementType: item.measurementType,
              settlementBasis: layer.settlementBasis,
              unitCostCents: Value(layer.unitCostCents),
              supplierShareBps: Value(layer.supplierShareBps),
              includeLineDiscount: layer.includeLineDiscount,
              includeInvoiceDiscount: layer.includeInvoiceDiscount,
              includeSalesTax: layer.includeSalesTax,
              allocatedSubtotalCents: subtotal[index],
              allocatedLineDiscountCents: lineDiscount[index],
              allocatedInvoiceDiscountCents: invoiceDiscountShares[index],
              allocatedTaxCents: tax[index],
              settlementBaseCents: base,
              obligationCents: due,
            ),
          );
      final changed = await db.customUpdate(
        'UPDATE consignment_inventory_layers SET '
        'remaining_quantity=remaining_quantity-?,'
        "status=CASE WHEN remaining_quantity-?=0 THEN 'exhausted' ELSE 'open' END,"
        'updated_at=? WHERE id=? AND status=? AND remaining_quantity>=?',
        variables: [
          Variable.withInt(source.quantity),
          Variable.withInt(source.quantity),
          Variable.withString(DateTime.now().toUtc().toIso8601String()),
          Variable.withString(layer.id),
          Variable.withString('open'),
          Variable.withInt(source.quantity),
        ],
        updates: {db.consignmentInventoryLayers},
      );
      if (changed != 1) {
        throw StateError('Consignment source changed during sale posting.');
      }
      // Quantity provenance must remain complete even when an agreement has a
      // legitimate zero settlement (for example a temporary 0% share). The
      // accounting service deliberately leaves zero-value events unjournaled.
      await db
          .into(db.consignmentObligationEvents)
          .insert(
            ConsignmentObligationEventsCompanion.insert(
              allocationId: allocationId,
              supplierId: layer.supplierId,
              agreementId: layer.agreementId,
              currencyId: sale.currencyId,
              kind: 'sale_accrual',
              signedQuantity: source.quantity,
              signedAmountCents: due,
              sourceTable: 'sales',
              sourceId: sale.id,
              sourceItemId: item.id,
              requestKey:
                  'sale:${sale.id}:item:${item.id}:allocation:$allocationId',
              occurredAt: sale.saleDate.toUtc(),
            ),
          );
      supplierQuantity += source.quantity;
      dueTotal += due;
    }
    if (supplierQuantity == 0) return ConsignmentSaleAllocationSummary.empty;
    final changed = await db.customUpdate(
      'UPDATE business_warehouse_stocks SET '
      'supplier_owned_quantity=supplier_owned_quantity-?,updated_at=? '
      'WHERE warehouse_id=? AND variant_id=? AND supplier_owned_quantity>=?',
      variables: [
        Variable.withInt(supplierQuantity),
        Variable.withString(DateTime.now().toUtc().toIso8601String()),
        Variable.withString(scope.warehouseId),
        Variable.withInt(variantId),
        Variable.withInt(supplierQuantity),
      ],
      updates: {db.businessWarehouseStocks},
    );
    if (changed != 1) {
      throw StateError('Supplier-owned sale quantity changed concurrently.');
    }
    return ConsignmentSaleAllocationSummary(supplierQuantity, dueTotal);
  }

  static Future<QueryRow> _stock(
    DatabaseAccessor<AppDatabase> dao,
    String warehouse,
    int product,
    int? variant,
  ) async {
    final vars = <Variable>[Variable.withString(warehouse)];
    final filter = variant == null ? '' : 'AND v.id=?';
    if (variant != null) vars.add(Variable.withInt(variant));
    vars.add(Variable.withInt(product));
    final rows = await dao
        .customSelect(
          'SELECT s.variant_id,s.quantity,s.supplier_owned_quantity '
          'FROM business_warehouse_stocks s JOIN product_variants v '
          'ON v.id=s.variant_id WHERE s.warehouse_id=? $filter '
          'AND v.product_id=? AND v.is_active=1',
          variables: vars,
        )
        .get();
    if (rows.length != 1) {
      throw StateError('Consignment requires one operational stock variant.');
    }
    return rows.single;
  }

  static Future<List<_Source>> _batchSources(
    DatabaseAccessor<AppDatabase> dao,
    WarehouseOperationScope scope,
    int product,
    int variant,
    int expectedSupplier,
  ) async {
    final rows = await dao
        .customSelect(
          'SELECT pb.remaining_quantity,l.id AS layer_id '
          'FROM product_batches pb LEFT JOIN consignment_inventory_layers l '
          "ON l.batch_id=pb.id AND l.status='open' "
          'WHERE pb.product_id=? AND pb.variant_id=? AND pb.is_active=1 '
          'AND pb.remaining_quantity>0 '
          "AND ${WarehouseBatchScope.operationPredicate('pb')} "
          'ORDER BY (pb.expiry_date IS NULL),pb.expiry_date,pb.received_date,pb.id',
          variables: [
            Variable.withInt(product),
            Variable.withInt(variant),
            ...WarehouseBatchScope.operationVariables(scope),
          ],
        )
        .get();
    final ids = rows
        .map((row) => row.readNullable<String>('layer_id'))
        .whereType<String>()
        .toList();
    final layers = ids.isEmpty
        ? <String, ConsignmentInventoryLayer>{}
        : {
            for (final layer in await (dao.attachedDatabase.select(
              dao.attachedDatabase.consignmentInventoryLayers,
            )..where((l) => l.id.isIn(ids))).get())
              layer.id: layer,
          };
    var supplier = 0;
    final result = <_Source>[];
    for (final row in rows) {
      final quantity = row.read<int>('remaining_quantity');
      final id = row.readNullable<String>('layer_id');
      final layer = id == null ? null : layers[id];
      if (layer != null) {
        if (layer.remainingQuantity != quantity) {
          throw StateError('Consignment batch and layer quantities differ.');
        }
        supplier += quantity;
      }
      result.add(_Source(quantity, layer));
    }
    if (supplier != expectedSupplier) {
      throw StateError('Supplier batch total differs from custody.');
    }
    return result;
  }

  static Future<List<_Source>> _wacSources(
    DatabaseAccessor<AppDatabase> dao,
    WarehouseOperationScope scope,
    int variant,
    int expectedPhysical,
    int expectedSupplier,
  ) async {
    final state = await dao
        .customSelect(
          'SELECT quantity,dirty,layers FROM inventory_origin_states '
          'WHERE warehouse_id=? AND variant_id=?',
          variables: [
            Variable.withString(scope.warehouseId),
            Variable.withInt(variant),
          ],
        )
        .getSingleOrNull();
    if (state == null ||
        state.read<int>('dirty') != 0 ||
        state.read<int>('quantity') != expectedPhysical) {
      throw StateError('Supplier-owned WAC stock has unreconciled sources.');
    }
    final decoded = (jsonDecode(state.read<String>('layers')) as List)
        .map((value) => Map<String, dynamic>.from(value as Map))
        .toList();
    final receiptIds = decoded
        .where((value) => value['k'] == 'consignment_receipt')
        .map((value) => _receiptId(value['r'] as String?))
        .toList();
    final layerRows = receiptIds.isEmpty
        ? <ConsignmentInventoryLayer>[]
        : await (dao.attachedDatabase.select(
                dao.attachedDatabase.consignmentInventoryLayers,
              )..where(
                (l) =>
                    l.receiptItemId.isIn(receiptIds) &
                    l.warehouseId.equals(scope.warehouseId) &
                    l.variantId.equals(variant) &
                    l.status.equals('open'),
              ))
              .get();
    final layers = {for (final layer in layerRows) layer.receiptItemId: layer};
    var physical = 0;
    var supplier = 0;
    final result = <_Source>[];
    for (final value in decoded) {
      final quantity = value['q'] as int? ?? 0;
      if (quantity <= 0) throw StateError('Invalid WAC source quantity.');
      physical += quantity;
      ConsignmentInventoryLayer? layer;
      if (value['k'] == 'consignment_receipt') {
        layer = layers[_receiptId(value['r'] as String?)];
        if (layer == null) throw StateError('Missing consignment WAC layer.');
        supplier += quantity;
      }
      result.add(_Source(quantity, layer));
    }
    if (physical != expectedPhysical || supplier != expectedSupplier) {
      throw StateError('WAC sources differ from custody balances.');
    }
    return result;
  }

  static String _receiptId(String? reference) {
    const prefix = 'consignment_receipt:';
    if (reference == null ||
        !reference.startsWith(prefix) ||
        reference.length != prefix.length + 36) {
      throw StateError('Invalid consignment receipt source.');
    }
    return reference.substring(prefix.length);
  }

  static List<_Source> _take(List<_Source> sources, int quantity) {
    var left = quantity;
    final selected = <_Source>[];
    for (final source in sources) {
      if (left <= 0) break;
      final take = source.quantity < left ? source.quantity : left;
      selected.add(_Source(take, source.layer));
      left -= take;
    }
    if (left > 0) selected.add(_Source(left, null));
    return selected;
  }

  static List<int> _allocate(int total, List<int> weights) {
    final denominator = weights.fold<int>(0, (sum, value) => sum + value);
    if (total < 0 || denominator <= 0 || weights.any((weight) => weight <= 0)) {
      throw ArgumentError('Invalid money allocation.');
    }
    final totalBig = BigInt.from(total);
    final divisor = BigInt.from(denominator);
    final shares = <int>[];
    final remains = <({int index, BigInt value})>[];
    var used = 0;
    for (var i = 0; i < weights.length; i++) {
      final numerator = totalBig * BigInt.from(weights[i]);
      final share = (numerator ~/ divisor).toInt();
      shares.add(share);
      used += share;
      remains.add((index: i, value: numerator.remainder(divisor)));
    }
    remains.sort((a, b) {
      final result = b.value.compareTo(a.value);
      return result == 0 ? a.index.compareTo(b.index) : result;
    });
    for (var i = 0; i < total - used; i++) {
      shares[remains[i].index]++;
    }
    return shares;
  }

  static int _bps(int cents, int bps) =>
      ((BigInt.from(cents) * BigInt.from(bps) + BigInt.from(5000)) ~/
              BigInt.from(10000))
          .toInt();
}

class _Source {
  const _Source(this.quantity, this.layer);
  final int quantity;
  final ConsignmentInventoryLayer? layer;
}
