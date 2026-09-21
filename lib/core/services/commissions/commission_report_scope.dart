import 'package:drift/drift.dart';

import '../../database/app_database.dart';
import '../business/warehouse_document_scope.dart';
import '../business/warehouse_read_scope.dart';

enum CommissionReportScope { account, primaryWarehouse }

class UnresolvedCommissionSources implements Exception {
  final int count;
  const UnresolvedCommissionSources(this.count);
}

/// Location follows the recorded economic event, never a guessed return.
/// Unbound/manual and ambiguous historical events remain in the full account.
class CommissionSourceScope {
  CommissionSourceScope._();

  static const classified = '''(
    SELECT c.*, w.id AS source_warehouse_id
    FROM commissions c
    LEFT JOIN sales s ON s.id = c.sale_id
    LEFT JOIN sale_returns r ON r.id = c.sale_return_id
    LEFT JOIN sale_return_adjustments a ON a.id = c.sale_return_adjustment_id
    LEFT JOIN business_document_locations l ON
      l.source_table = CASE
        WHEN c.commission_amount_cents >= 0 AND c.sale_id IS NOT NULL
          AND c.sale_return_id IS NULL AND c.sale_return_adjustment_id IS NULL
          AND s.status = 'completed' AND s.currency_id = c.currency_id THEN 'sales'
        WHEN c.commission_amount_cents < 0 AND c.sale_return_id IS NOT NULL
          AND c.sale_return_adjustment_id IS NULL AND r.sale_id = c.sale_id
          AND r.status = 'posted' AND r.currency_id = c.currency_id THEN 'sale_returns'
        WHEN c.commission_amount_cents < 0 AND c.sale_return_adjustment_id IS NOT NULL
          AND c.sale_id IS NULL AND c.sale_return_id IS NULL
          AND a.status = 'posted' AND a.currency_id = c.currency_id THEN 'sale_return_adjustments'
      END
      AND l.source_id = CASE
        WHEN c.sale_return_id IS NOT NULL THEN c.sale_return_id
        WHEN c.sale_return_adjustment_id IS NOT NULL THEN c.sale_return_adjustment_id
        ELSE c.sale_id END
    LEFT JOIN business_branches b ON b.id = l.branch_id
      AND b.organization_id = l.organization_id
    LEFT JOIN business_warehouses w ON w.id = l.warehouse_id
      AND w.branch_id = b.id AND w.organization_id = b.organization_id
  )''';

  static String get primary =>
      '''(
    SELECT event.* FROM $classified event
    WHERE EXISTS (
      SELECT 1 FROM business_contexts ctx
      JOIN business_warehouses w ON w.id = ctx.warehouse_id
        AND w.branch_id = ctx.branch_id AND w.organization_id = ctx.organization_id
      JOIN business_branches b ON b.id = ctx.branch_id
        AND b.organization_id = ctx.organization_id
      WHERE ctx.id = 1 AND event.source_warehouse_id = ctx.warehouse_id
    )
  )''';

  static String forWarehouse(WarehouseReadScope scope) =>
      '(SELECT event.* FROM $classified event '
      'JOIN ${scope.warehouses} w ON w.id = event.source_warehouse_id)';

  static Set<TableInfo<Table, dynamic>> dependencies(AppDatabase db) => {
    db.commissions,
    db.sales,
    db.saleReturns,
    db.saleReturnAdjustments,
    ...WarehouseDocumentScope.dependencies(db),
  };

  static Future<void> requireResolvedPeriod(
    AppDatabase db,
    DateTime start,
    DateTime end,
  ) async {
    final row = await db
        .customSelect(
          '''
      SELECT COUNT(*) AS unresolved FROM $classified c
      WHERE c.source_warehouse_id IS NULL
        AND COALESCE(c.effective_date, c.created_at) >= ?
        AND COALESCE(c.effective_date, c.created_at) <= ?
    ''',
          variables: [
            Variable.withString(start.toIso8601String()),
            Variable.withString(end.toIso8601String()),
          ],
          readsFrom: dependencies(db),
        )
        .getSingle();
    final count = row.read<int>('unresolved');
    if (count > 0) throw UnresolvedCommissionSources(count);
  }
}
