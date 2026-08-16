import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';

/// One posted sales/return document used by both the dashboard card and PDF.
class DailySalesReportRow {
  final String documentType;
  final String documentNumber;
  final DateTime documentDate;
  final String? customerName;
  final String paymentMethod;
  final int grossCents;
  final int revenueCents;
  final int costCents;
  final int discountCents;
  final int taxCents;

  const DailySalesReportRow({
    required this.documentType,
    required this.documentNumber,
    required this.documentDate,
    this.customerName,
    required this.paymentMethod,
    required this.grossCents,
    required this.revenueCents,
    required this.costCents,
    required this.discountCents,
    required this.taxCents,
  });
}

/// Single read model for today's profit card and its printable report.
/// Revenue is net of VAT; COGS mirrors FIFO batch consumption / WAC snapshots;
/// linked and adjustment returns are negative documents in their own date.
class DailySalesReportingService {
  final AppDatabase _db;

  DailySalesReportingService(this._db);

  Stream<List<DailySalesReportRow>> watchDay(DateTime day) {
    return _query(day).watch().map(_mapRows);
  }

  Future<List<DailySalesReportRow>> loadDay(DateTime day) async {
    return _mapRows(await _query(day).get());
  }

  Selectable<QueryRow> _query(DateTime day) {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    return _db.customSelect(
      '''
      SELECT * FROM (
        SELECT
          'sale' AS document_type,
          s.invoice_number AS document_number,
          s.sale_date AS document_date,
          c.name AS customer_name,
          s.payment_method,
          s.total_cents AS gross_cents,
          (s.total_cents - s.tax_cents) AS revenue_cents,
          s.discount_cents AS discount_cents,
          s.tax_cents AS tax_cents,
          COALESCE((
            SELECT SUM(
              CASE
                WHEN p.track_inventory = 0 THEN 0
                WHEN EXISTS (
                  SELECT 1 FROM batch_consumptions bc
                  WHERE bc.sale_item_id = si.id AND bc.direction = 'out'
                    AND bc.consumption_type = 'sale'
                ) THEN (
                  SELECT COALESCE(SUM(CAST(ROUND(1.0 * bc.quantity * bc.unit_cost_cents / si.quantity_scale) AS INTEGER)), 0)
                  FROM batch_consumptions bc
                  WHERE bc.sale_item_id = si.id AND bc.direction = 'out'
                    AND bc.consumption_type = 'sale'
                )
                ELSE CAST(ROUND(1.0 * COALESCE(si.cost_cents, v.cost_cents, p.cost_cents)
                     * si.quantity / si.quantity_scale) AS INTEGER)
              END
            )
            FROM sale_items si
            INNER JOIN products p ON p.id = si.product_id
            LEFT JOIN product_variants v ON v.id = si.variant_id
            WHERE si.sale_id = s.id
          ), 0) AS cost_cents
        FROM sales s
        LEFT JOIN customers c ON c.id = s.customer_id
        WHERE s.status = 'completed'
          AND s.sale_date >= ? AND s.sale_date < ?

        UNION ALL

        SELECT
          'linked_return',
          sr.return_number,
          sr.return_date,
          c.name,
          sr.refund_method,
          -sr.total_cents,
          -(sr.total_cents - sr.tax_cents),
          -sr.discount_cents,
          -sr.tax_cents,
          -COALESCE((
            SELECT SUM(
              CASE
                WHEN p.track_inventory = 0 THEN 0
                WHEN EXISTS (
                  SELECT 1 FROM batch_consumptions bc
                  WHERE bc.sale_return_item_id = sri.id AND bc.direction = 'in'
                    AND bc.consumption_type = 'sale_return_reverse'
                ) THEN (
                  SELECT COALESCE(SUM(CAST(ROUND(1.0 * bc.quantity * bc.unit_cost_cents / sri.quantity_scale) AS INTEGER)), 0)
                  FROM batch_consumptions bc
                  WHERE bc.sale_return_item_id = sri.id AND bc.direction = 'in'
                    AND bc.consumption_type = 'sale_return_reverse'
                )
                ELSE CAST(ROUND(1.0 * COALESCE(sri.unit_cost_at_post_cents, si.cost_cents,
                              v.cost_cents, p.cost_cents) * sri.quantity
                              / sri.quantity_scale) AS INTEGER)
              END
            )
            FROM sale_return_items sri
            INNER JOIN sale_items si ON si.id = sri.sale_item_id
            INNER JOIN products p ON p.id = si.product_id
            LEFT JOIN product_variants v ON v.id = si.variant_id
            WHERE sri.return_id = sr.id
          ), 0)
        FROM sale_returns sr
        INNER JOIN sales s ON s.id = sr.sale_id
        LEFT JOIN customers c ON c.id = s.customer_id
        WHERE sr.status = 'posted'
          AND sr.return_date >= ? AND sr.return_date < ?

        UNION ALL

        SELECT
          'adjustment_return',
          sra.return_number,
          sra.return_date,
          c.name,
          sra.refund_method,
          -sra.total_cents,
          -(sra.total_cents - sra.tax_cents),
          -sra.discount_cents,
          -sra.tax_cents,
          -COALESCE((
            SELECT SUM(
              CASE WHEN p.track_inventory = 0 THEN 0
                   ELSE CAST(ROUND(1.0 * COALESCE(srai.unit_cost_at_post_cents,
                                 srai.unit_cost_cents) * srai.quantity
                                 / srai.quantity_scale) AS INTEGER)
              END
            )
            FROM sale_return_adjustment_items srai
            INNER JOIN products p ON p.id = srai.product_id
            WHERE srai.return_id = sra.id
          ), 0)
        FROM sale_return_adjustments sra
        LEFT JOIN customers c ON c.id = sra.customer_id
        WHERE sra.status = 'posted'
          AND sra.return_date >= ? AND sra.return_date < ?
      ) documents
      ORDER BY document_date DESC
      ''',
      variables: [
        Variable.withDateTime(start),
        Variable.withDateTime(end),
        Variable.withDateTime(start),
        Variable.withDateTime(end),
        Variable.withDateTime(start),
        Variable.withDateTime(end),
      ],
      readsFrom: {
        _db.sales,
        _db.saleItems,
        _db.saleReturns,
        _db.saleReturnItems,
        _db.saleReturnAdjustments,
        _db.saleReturnAdjustmentItems,
        _db.products,
        _db.productVariants,
        _db.batchConsumptions,
        _db.customers,
      },
    );
  }

  List<DailySalesReportRow> _mapRows(List<QueryRow> rows) {
    return rows
        .map(
          (row) => DailySalesReportRow(
            documentType: row.read<String>('document_type'),
            documentNumber: row.read<String>('document_number'),
            documentDate: row.read<DateTime>('document_date'),
            customerName: row.readNullable<String>('customer_name'),
            paymentMethod: row.read<String>('payment_method'),
            grossCents: row.read<int>('gross_cents'),
            revenueCents: row.read<int>('revenue_cents'),
            costCents: row.read<int>('cost_cents'),
            discountCents: row.read<int>('discount_cents'),
            taxCents: row.read<int>('tax_cents'),
          ),
        )
        .toList();
  }
}
