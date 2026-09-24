import 'dart:convert';
import 'dart:math' as math;
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../../database/app_database.dart';
import 'supplier_identity_rules.dart';

/// References a posted movement, never a product's preferred vendor.
class InventoryOriginIntent {
  const InventoryOriginIntent(
    this.kind,
    this.lineId, {
    this.reference,
    this.referenceWarehouse,
    this.supplierIdentityId,
    this.requiredSourceReference,
    this.excludedSourceKind,
  }) : explicitKey = null;

  const InventoryOriginIntent.keyed(
    this.kind,
    this.explicitKey, {
    this.reference,
    this.referenceWarehouse,
    this.supplierIdentityId,
    this.requiredSourceReference,
    this.excludedSourceKind,
  }) : lineId = 0;

  final String kind;
  final int lineId;
  final String? explicitKey;
  final String? reference;
  final String? referenceWarehouse;
  final int? supplierIdentityId;
  final String? requiredSourceReference;
  final String? excludedSourceKind;
  String get key => explicitKey ?? '$kind:$lineId';
}

/// Independent quantity-only allocation. Purchase allocations are POLICY based,
/// not proof of physical picking. Batch-tracked products retain their own ledger.
class InventoryOriginService {
  static List<Map<String, dynamic>> _decode(String value) =>
      (jsonDecode(value) as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
  static Map<String, dynamic> _part(
    int q, {
    int? purchase,
    String kind = 'unknown',
    String? sourceReference,
    int? supplierIdentity,
  }) => {
    'q': q,
    'p': purchase,
    'k': kind,
    'r': ?sourceReference,
    'i': ?supplierIdentity,
  };
  static bool _same(Map<String, dynamic> a, Map<String, dynamic> b) =>
      a['p'] == b['p'] &&
      a['k'] == b['k'] &&
      a['r'] == b['r'] &&
      a['i'] == b['i'];

  static Future<bool> _belongsToIdentity(
    AppDatabase db,
    Map<String, dynamic> layer,
    int identityId,
  ) async {
    if (layer['i'] == identityId) return true;
    final purchaseItemId = layer['p'];
    if (purchaseItemId is! int) return false;
    final match = await db
        .customSelect(
          'SELECT 1 AS found FROM purchase_items '
          'WHERE id=? AND supplier_identity_id=?',
          variables: [
            Variable.withInt(purchaseItemId),
            Variable.withInt(identityId),
          ],
        )
        .getSingleOrNull();
    return match != null;
  }

  /// Called before the stock UPDATE, within StockService's transaction.
  static Future<List<Map<String, dynamic>>?> capture(
    AppDatabase db,
    String warehouse,
    int variant,
  ) async {
    final rows = await db
        .customSelect(
          '''SELECT s.quantity,p.measurement_type,p.costing_method,p.inventory_tracking_type
      FROM business_warehouse_stocks s JOIN product_variants v ON v.id=s.variant_id
      JOIN products p ON p.id=v.product_id WHERE s.warehouse_id=? AND s.variant_id=?''',
          variables: [
            Variable.withString(warehouse),
            Variable.withInt(variant),
          ],
        )
        .get();
    if (rows.isEmpty) return null;
    final r = rows.single;
    if (r.read<String>('costing_method') == 'fifo' ||
        r.read<String>('inventory_tracking_type') != 'standard') {
      return null;
    }
    final q = r.read<int>('quantity');
    final old = await db
        .customSelect(
          'SELECT * FROM inventory_origin_states WHERE warehouse_id=? AND variant_id=?',
          variables: [
            Variable.withString(warehouse),
            Variable.withInt(variant),
          ],
        )
        .getSingleOrNull();
    // Existing inventory is never retrospectively assigned to purchases.
    if (old == null ||
        old.read<int>('dirty') != 0 ||
        old.read<int>('quantity') != q ||
        old.read<String>('measurement_type') !=
            r.read<String>('measurement_type')) {
      return q > 0 ? [_part(q)] : [];
    }
    final layers = _decode(old.read<String>('layers'));
    if (layers.any((e) => (e['q'] as int) <= 0) ||
        layers.fold<int>(0, (n, e) => n + (e['q'] as int)) != math.max(0, q)) {
      throw StateError('Invalid origin quantity balance');
    }
    return layers;
  }

  /// Completes provenance after the stock UPDATE in the same transaction.
  static Future<void> record(
    AppDatabase db, {
    required String warehouse,
    required int variant,
    required int product,
    required int delta,
    required List<Map<String, dynamic>> layers,
    InventoryOriginIntent? intent,
  }) async {
    final meta = await db
        .customSelect(
          '''SELECT s.quantity,p.measurement_type FROM business_warehouse_stocks s
      JOIN product_variants v ON v.id=s.variant_id JOIN products p ON p.id=v.product_id
      WHERE s.warehouse_id=? AND s.variant_id=?''',
          variables: [
            Variable.withString(warehouse),
            Variable.withInt(variant),
          ],
        )
        .getSingle();
    final measurement = meta.read<String>('measurement_type');
    final key = intent?.key ?? 'unattributed:${const Uuid().v4()}';
    Future<QueryRow?> event(String k, {String? inWarehouse}) => db
        .customSelect(
          '''SELECT * FROM inventory_origin_events
      WHERE warehouse_id=? AND variant_id=? AND product_id=? AND measurement_type=? AND event_key=?''',
          variables: [
            Variable.withString(inWarehouse ?? warehouse),
            Variable.withInt(variant),
            Variable.withInt(product),
            Variable.withString(measurement),
            Variable.withString(k),
          ],
        )
        .getSingleOrNull();
    final ref = intent?.reference == null
        ? null
        : await event(
            intent!.reference!,
            inWarehouse: intent.referenceWarehouse,
          );
    String? claim;
    final parts = <Map<String, dynamic>>[];
    final amount = delta.abs();
    if (delta > 0) {
      if (intent?.kind == 'purchase') {
        parts.add(
          _part(
            amount,
            purchase: intent!.lineId,
            kind: 'purchase',
            supplierIdentity: intent.supplierIdentityId,
          ),
        );
      } else if (intent?.kind == 'adjustment' &&
          intent?.supplierIdentityId != null) {
        parts.add(
          _part(
            amount,
            kind: 'supplier_identity_return',
            supplierIdentity: intent!.supplierIdentityId,
          ),
        );
      } else if (intent?.kind == 'consignment_receipt') {
        parts.add(
          _part(
            amount,
            kind: 'consignment_receipt',
            sourceReference: intent!.key,
          ),
        );
      } else if (intent?.kind == 'consignment_adjustment_return') {
        if (ref == null || ref.read<int>('delta') <= 0) {
          throw StateError('Consignment adjustment source is unavailable');
        }
        parts.add(
          _part(
            amount,
            kind: 'consignment_receipt',
            sourceReference: ref.read<String>('event_key'),
          ),
        );
      } else if (ref != null && ref.read<int>('delta') < 0) {
        // Restore only the not-yet-returned portions of the saved outflow.
        claim = ref.read<String>('event_key');
        final available = _decode(ref.read<String>('allocations'));
        final isTransferClaim =
            intent?.kind == 'transfer_in' || intent?.kind == 'transfer_recall';
        final claims = await db
            .customSelect(
              isTransferClaim
                  ? '''SELECT delta,allocations FROM inventory_origin_events
          WHERE variant_id=? AND product_id=? AND measurement_type=?
            AND claim_key=? ORDER BY id'''
                  : '''SELECT delta,allocations FROM inventory_origin_events
          WHERE warehouse_id=? AND variant_id=? AND product_id=?
            AND measurement_type=? AND claim_key=? ORDER BY id''',
              variables: isTransferClaim
                  ? [
                      Variable.withInt(variant),
                      Variable.withInt(product),
                      Variable.withString(measurement),
                      Variable.withString(claim),
                    ]
                  : [
                      Variable.withString(warehouse),
                      Variable.withInt(variant),
                      Variable.withInt(product),
                      Variable.withString(measurement),
                      Variable.withString(claim),
                    ],
            )
            .get();
        for (final c in claims) {
          for (final used in _decode(c.read<String>('allocations'))) {
            var remaining =
                (used['q'] as int) * (c.read<int>('delta') > 0 ? 1 : -1);
            for (final a in available.where((a) => _same(a, used))) {
              if (remaining <= 0) break;
              final n = math.min(a['q'] as int, remaining);
              a['q'] = (a['q'] as int) - n;
              remaining -= n;
            }
            if (remaining < 0) {
              final restored = available
                  .where((a) => _same(a, used))
                  .firstOrNull;
              if (restored == null) {
                throw StateError(
                  'Origin cancellation does not match original sale',
                );
              }
              restored['q'] = (restored['q'] as int) - remaining;
            }
          }
        }
        var remaining = amount;
        for (final a in available) {
          final n = math.min(remaining, a['q'] as int);
          if (n > 0) {
            parts.add({...a, 'q': n});
            remaining -= n;
          }
        }
        if (remaining > 0) {
          if (intent?.kind == 'transfer_in') {
            throw StateError('Transferred origin quantity is incomplete');
          }
          parts.add(_part(remaining));
        }
      } else {
        parts.add(
          _part(
            amount,
            kind: intent?.kind == 'adjustment' ? 'customer_return' : 'unknown',
          ),
        );
      }
      layers.addAll(parts.map((e) => Map<String, dynamic>.of(e)));
    } else {
      // Linked purchase removals / inbound reversals prefer the corresponding
      // origin. If it has already left, consume other available quantities;
      // never manufacture availability or rewrite previously saved sales.
      List<Map<String, dynamic>> preferred = [];
      if (ref != null && ref.read<int>('delta') > 0) {
        preferred = _decode(ref.read<String>('allocations'));
        claim = ref.readNullable<String>('claim_key');
      }
      var remaining = amount;
      void take(Map<String, dynamic> layer, int limit) {
        final n = math.min(remaining, math.min(layer['q'] as int, limit));
        if (n <= 0) return;
        parts.add({...layer, 'q': n});
        layer['q'] = (layer['q'] as int) - n;
        remaining -= n;
      }

      for (final target in preferred) {
        var requested = target['q'] as int;
        for (final layer in layers.where((l) => _same(l, target))) {
          final before = remaining;
          take(layer, requested);
          requested -= before - remaining;
        }
      }
      final requiredSourceReference = intent?.requiredSourceReference;
      final excludedSourceKind = intent?.excludedSourceKind;
      final selectedIdentity = intent?.supplierIdentityId;
      if (requiredSourceReference != null) {
        for (final layer in layers.where(
          (layer) => layer['r'] == requiredSourceReference,
        )) {
          if (remaining == 0) break;
          take(layer, remaining);
        }
        if (remaining > 0) {
          throw StateError('Required inventory origin is unavailable');
        }
      } else if (excludedSourceKind != null) {
        for (final layer in layers.where(
          (layer) => layer['k'] != excludedSourceKind,
        )) {
          if (remaining == 0) break;
          take(layer, remaining);
        }
        if (remaining > 0) {
          throw StateError('Required inventory ownership is unavailable');
        }
      } else if (selectedIdentity != null) {
        for (final layer in layers) {
          if (remaining == 0) break;
          if (await _belongsToIdentity(db, layer, selectedIdentity)) {
            take(layer, remaining);
          }
        }
        if (remaining > 0) {
          throw const SupplierIdentityException(
            'supplier_identity.insufficient_source_quantity',
          );
        }
      } else {
        for (final layer in layers) {
          take(layer, remaining);
        }
      }
      if (remaining > 0) {
        parts.add(_part(remaining)); // negative stock has no proven source
      }
      layers.removeWhere((e) => (e['q'] as int) == 0);
      // A reverse of an inbound return cancels its claim, even when those
      // physical units have since been sold and another source was removed.
      if (claim != null && ref != null) {
        parts.clear();
        parts.addAll(_decode(ref.read<String>('allocations')));
        if (parts.fold<int>(0, (n, e) => n + (e['q'] as int)) != amount) {
          throw StateError('Origin reversal quantity mismatch');
        }
      }
    }
    final expected = math.max(0, meta.read<int>('quantity'));
    // Receiving into negative inventory first settles the unidentified deficit.
    var excess = layers.fold<int>(0, (n, e) => n + (e['q'] as int)) - expected;
    for (final l in layers) {
      final n = math.min(math.max(0, excess), l['q'] as int);
      l['q'] = (l['q'] as int) - n;
      excess -= n;
    }
    layers.removeWhere((e) => (e['q'] as int) == 0);
    if (layers.fold<int>(0, (n, e) => n + (e['q'] as int)) != expected) {
      throw StateError('Origin balance does not match stock');
    }
    await db.customStatement(
      '''INSERT INTO inventory_origin_events(warehouse_id,variant_id,product_id,measurement_type,event_key,claim_key,delta,allocations)
      VALUES(?,?,?,?,?,?,?,?)''',
      [
        warehouse,
        variant,
        product,
        measurement,
        key,
        claim,
        delta,
        jsonEncode(parts),
      ],
    );
    await db.customStatement(
      '''INSERT INTO inventory_origin_states(warehouse_id,variant_id,quantity,measurement_type,dirty,layers)
      VALUES(?,?,?,?,0,?) ON CONFLICT(warehouse_id,variant_id) DO UPDATE SET quantity=excluded.quantity,
      measurement_type=excluded.measurement_type,dirty=0,layers=excluded.layers''',
      [
        warehouse,
        variant,
        meta.read<int>('quantity'),
        measurement,
        jsonEncode(layers),
      ],
    );
  }
}
