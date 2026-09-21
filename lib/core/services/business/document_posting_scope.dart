import 'package:drift/drift.dart';

import '../../database/app_database.dart';
import 'warehouse_operation_scope.dart';
import 'branch_currency_policy_store.dart';

enum InventoryPostingDocument {
  sale('sales', 'sale_items', 'sale_id'),
  purchase('purchases', 'purchase_items', 'purchase_id'),
  saleReturn('sale_returns', 'sale_return_items', 'return_id'),
  purchaseReturn('purchase_returns', 'purchase_return_items', 'return_id'),
  saleAdjustment(
    'sale_return_adjustments',
    'sale_return_adjustment_items',
    'return_id',
  ),
  purchaseAdjustment(
    'purchase_return_adjustments',
    'purchase_return_adjustment_items',
    'return_id',
  );

  const InventoryPostingDocument(this.table, this.items, this.parentKey);
  final String table;
  final String items;
  final String parentKey;
}

/// Invoked inside the document's posting/void transaction, before any stock,
/// return counters, payments or accounting changes. Does not recalculate prices
/// or require an invoice for a genuinely unlinked adjustment return.
class DocumentPostingScope {
  DocumentPostingScope._();

  /// History remains readable for an inactive warehouse; only posting requires
  /// activation. Closed aliases keep SQL identifiers outside client control.
  static String historyPredicate(
    InventoryPostingDocument kind,
    String alias, {
    WarehouseOperationScope? scope,
  }) {
    if (!const {'s', 'pu', 'sales', 'purchases'}.contains(alias) ||
        (kind != InventoryPostingDocument.sale &&
            kind != InventoryPostingDocument.purchase)) {
      throw ArgumentError('Unsupported inventory history source.');
    }
    // The identifier/alias remains a closed enum/list. Escape the internal
    // scope value as a SQL literal for both Drift expressions and raw queries.
    final warehouse = scope == null
        ? 'c.warehouse_id = l.warehouse_id'
        : "l.warehouse_id = '${scope.warehouseId.replaceAll("'", "''")}'";
    return '''EXISTS (SELECT 1 FROM business_document_locations l
      JOIN business_contexts c ON c.organization_id = l.organization_id
        AND c.branch_id = l.branch_id AND $warehouse
      WHERE c.id = 1 AND l.source_table = '${kind.table}' AND l.source_id = $alias.id)''';
  }

  /// Resolve an internal posting scope from immutable stored ownership, never
  /// from a request selector. Existing validate() callers stay primary-only.
  /// Call inside the document transaction after entry-point authorization.
  static Future<WarehouseOperationScope> resolveForDocument(
    AppDatabase db,
    InventoryPostingDocument kind,
    int id,
  ) async {
    final location = await db
        .customSelect(
          'SELECT warehouse_id FROM business_document_locations '
          'WHERE source_table = ? AND source_id = ?',
          variables: [Variable.withString(kind.table), Variable.withInt(id)],
        )
        .getSingleOrNull();
    if (location == null) throw StateError('Document location is missing.');
    final scope = await WarehouseOperationScope.resolve(
      db,
      warehouseId: location.read<String>('warehouse_id'),
    );
    await validate(db, kind, id, scope: scope);
    return scope;
  }

  /// Additional warehouse posting has no implicit currency conversion. This
  /// guard is separate from validate(), because historical voids must remain
  /// possible after a currency or shift is closed.
  static Future<void> validatePostingTerms(
    AppDatabase db,
    InventoryPostingDocument kind,
    int id,
    WarehouseOperationScope scope,
  ) async {
    await scope.validate(db);
    if (scope.isPrimary && await BranchCurrencyPolicyStore(db).read() == null) {
      return;
    }
    final header = await db
        .customSelect(
          'SELECT * FROM ${kind.table} WHERE id = ?',
          variables: [Variable.withInt(id)],
        )
        .getSingle();
    final currencyId = header.read<int>('currency_id');
    await BranchCurrencyPolicyStore(
      db,
    ).requireCurrency(currencyId, requireBinding: true);
    final currency = await db
        .customSelect(
          'SELECT id FROM currencies WHERE id = ? AND is_active = 1',
          variables: [Variable.withInt(currencyId)],
        )
        .getSingleOrNull();
    if (currency == null) throw StateError('Document currency is inactive.');
    final saleSide =
        kind == InventoryPostingDocument.sale ||
        kind == InventoryPostingDocument.saleAdjustment ||
        kind == InventoryPostingDocument.saleReturn;
    final linked =
        kind == InventoryPostingDocument.saleReturn ||
        kind == InventoryPostingDocument.purchaseReturn;
    final partyColumn = saleSide ? 'customer_id' : 'supplier_id';
    final partyTable = saleSide ? 'customers' : 'suppliers';
    final source = linked
        ? await db
              .customSelect(
                'SELECT * FROM ${saleSide ? 'sales' : 'purchases'} WHERE id = ?',
                variables: [
                  Variable.withInt(
                    header.read<int>(saleSide ? 'sale_id' : 'purchase_id'),
                  ),
                ],
              )
              .getSingle()
        : header;
    final partyId = source.readNullable<int>(partyColumn);
    if (partyId != null) {
      final party = await db
          .customSelect(
            'SELECT currency_id FROM $partyTable WHERE id = ?',
            variables: [Variable.withInt(partyId)],
          )
          .getSingle();
      if (party.read<int>('currency_id') != currencyId) {
        throw StateError('Party currency does not match the document.');
      }
    }
    if (!linked) {
      final invalid = await db
          .customSelect(
            'SELECT i.id FROM ${kind.items} i JOIN products p ON p.id = i.product_id '
            'WHERE i.${kind.parentKey} = ? AND (p.currency_id IS NULL OR p.currency_id != ?) LIMIT 1',
            variables: [Variable.withInt(id), Variable.withInt(currencyId)],
          )
          .getSingleOrNull();
      if (invalid != null) {
        throw StateError('Product currency does not match the document.');
      }
    }
    if (kind == InventoryPostingDocument.sale ||
        kind == InventoryPostingDocument.purchase) {
      final payments = saleSide ? 'sale_payments' : 'purchase_payments';
      final parent = saleSide ? 'sale_id' : 'purchase_id';
      final invalid = await db
          .customSelect(
            'SELECT id FROM $payments WHERE $parent = ? AND currency_id != ? LIMIT 1',
            variables: [Variable.withInt(id), Variable.withInt(currencyId)],
          )
          .getSingleOrNull();
      if (invalid != null) {
        throw StateError('Payment currency does not match the document.');
      }
    }
    if (kind == InventoryPostingDocument.sale ||
        kind == InventoryPostingDocument.saleAdjustment) {
      final shiftId = header.readNullable<int>('cashier_shift_id');
      if (shiftId != null) {
        final shift = await db
            .customSelect(
              "SELECT id FROM cashier_shifts WHERE id = ? AND currency_id = ? AND status = 'open'",
              variables: [
                Variable.withInt(shiftId),
                Variable.withInt(currencyId),
              ],
            )
            .getSingleOrNull();
        if (shift == null) {
          throw StateError('Cashier shift is closed or uses another currency.');
        }
      }
    }
  }

  /// Returns the checked scope so downstream writes share this exact binding.
  static Future<WarehouseOperationScope> validate(
    AppDatabase db,
    InventoryPostingDocument kind,
    int id, {
    WarehouseOperationScope? scope,
  }) async {
    final operationScope = scope ?? await WarehouseOperationScope.resolve(db);
    await operationScope.validate(db);
    await _location(db, operationScope, kind.table, id);
    final linked = switch (kind) {
      InventoryPostingDocument.saleReturn => InventoryPostingDocument.sale,
      InventoryPostingDocument.purchaseReturn =>
        InventoryPostingDocument.purchase,
      _ => null,
    };

    String lines;
    if (linked != null) {
      final parentColumn = linked.parentKey;
      final itemColumn = linked == InventoryPostingDocument.sale
          ? 'sale_item_id'
          : 'purchase_item_id';
      final header = await db
          .customSelect(
            'SELECT $parentColumn AS parent_id FROM ${kind.table} WHERE id = ?',
            variables: [Variable.withInt(id)],
          )
          .getSingle();
      final parentId = header.read<int>('parent_id');
      await _location(db, operationScope, linked.table, parentId);
      final wrongSource = await db
          .customSelect(
            'SELECT r.id FROM ${kind.items} r '
            'LEFT JOIN ${linked.items} original ON original.id = r.$itemColumn '
            'WHERE r.return_id = ? AND (original.id IS NULL OR original.$parentColumn != ?) LIMIT 1',
            variables: [Variable.withInt(id), Variable.withInt(parentId)],
          )
          .get();
      if (wrongSource.isNotEmpty) {
        throw StateError(
          'Return line does not belong to its original invoice.',
        );
      }
      lines =
          'SELECT original.product_id, original.variant_id FROM ${kind.items} r '
          'JOIN ${linked.items} original ON original.id = r.$itemColumn WHERE r.return_id = ?';
    } else {
      lines =
          'SELECT product_id, variant_id FROM ${kind.items} WHERE ${kind.parentKey} = ?';
    }

    // NULL is the existing simple-product contract, not a request to select
    // an arbitrary variant. Existing canonical-row resolution remains in the
    // stock engine. Explicit variants must belong to their declared product.
    final invalid = await db
        .customSelect(
          'SELECT line.product_id FROM ($lines) line '
          'LEFT JOIN products p ON p.id = line.product_id '
          'LEFT JOIN product_variants v ON v.id = line.variant_id '
          'WHERE p.id IS NULL OR (line.variant_id IS NOT NULL '
          'AND (v.id IS NULL OR v.product_id != line.product_id)) LIMIT 1',
          variables: [Variable.withInt(id)],
        )
        .get();
    if (invalid.isNotEmpty) {
      throw StateError(
        'Document line has an invalid product/variant identity.',
      );
    }
    return operationScope;
  }

  static Future<void> _location(
    AppDatabase db,
    WarehouseOperationScope scope,
    String table,
    int id,
  ) async {
    final row = await db
        .customSelect(
          'SELECT source_id FROM business_document_locations '
          'WHERE source_table = ? AND source_id = ? AND organization_id = ? '
          'AND branch_id = ? AND warehouse_id = ?',
          variables: [
            Variable.withString(table),
            Variable.withInt(id),
            Variable.withString(scope.organizationId),
            Variable.withString(scope.branchId),
            Variable.withString(scope.warehouseId),
          ],
        )
        .getSingleOrNull();
    if (row == null) {
      throw StateError(
        'Document does not belong to the selected active warehouse.',
      );
    }
  }
}
