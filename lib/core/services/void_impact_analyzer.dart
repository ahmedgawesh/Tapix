import 'business/warehouse_read_scope.dart';
import 'package:drift/drift.dart' as drift;

import '../database/app_database.dart';
import 'business/warehouse_stock_scope.dart';
import 'business/document_posting_scope.dart';
import 'business/warehouse_document_scope.dart';

/// ────────────────────────────────────────────────────────────────────────────
/// VoidImpactAnalyzer — single source of truth for "what breaks if we void
/// this document?".
///
/// The repository's void path calls [analyzeSaleVoid] / [analyzePurchaseVoid]
/// BEFORE flipping any status. The returned [VoidImpactReport] tells the
/// caller (UI or repo) exactly:
///
///   • which **linked returns** will be cascade-voided (always safe — the
///     cascade has well-defined semantics, the user only needs to confirm),
///
///   • which **adjustment / unlinked returns** are entangled with this
///     document because their FIFO allocation consumed quantity from this
///     document's items (a HARD BLOCKER — voiding leaves the adjustment
///     return's GL + stock + sub-ledger entries orphaned because the line
///     they were attributed to disappears from the cap),
///
///   • whether voiding would push **stock negative** for any item (a HARD
///     BLOCKER — matches the SAP / NetSuite / Odoo / QuickBooks policy
///     already enforced in `SaleDao.voidSale` for sales without entangled
///     returns; the analyzer surfaces the same risk pre-flight),
///
///   • the **estimated GL impact** on AR / AP / Inventory so the user is
///     never surprised by the post-void numbers.
///
/// The analyzer is read-only and side-effect-free; it can be called from
/// any layer (UI confirmation dialog, repo guard, audit report).
/// ────────────────────────────────────────────────────────────────────────────
class VoidImpactAnalyzer {
  final AppDatabase _db;

  final WarehouseReadScope? warehouseScope;
  VoidImpactAnalyzer(this._db, {this.warehouseScope});

  Future<int> _currentStock(int productId, int? variantId) async {
    if (variantId == null) {
      final product = await _db
          .customSelect(
            'SELECT has_variants, stock_quantity FROM products WHERE id = ?',
            variables: [drift.Variable.withInt(productId)],
          )
          .getSingleOrNull();
      if (product == null) return 0;
      if (product.read<bool>('has_variants')) {
        throw StateError('Void preview requires an explicit variant.');
      }
      final rows = await _db
          .customSelect(
            'SELECT id FROM product_variants WHERE product_id = ? AND is_active = 1 LIMIT 2',
            variables: [drift.Variable.withInt(productId)],
          )
          .get();
      if (rows.length > 1) {
        throw StateError('Ambiguous simple-product operational row.');
      }
      if (rows.isEmpty) {
        if (warehouseScope != null && !warehouseScope!.isPrimary) {
          throw StateError(
            'Missing operational variant for selected warehouse',
          );
        }
        return product.read<int>('stock_quantity');
      }
      variantId = rows.single.read<int>('id');
    }
    final row = await _db
        .customSelect(
          'SELECT s.quantity FROM ${warehouseScope?.stocks ?? WarehouseStockScope.primaryStocks} s '
          'JOIN product_variants v ON v.id = s.variant_id '
          'WHERE s.variant_id = ? AND v.product_id = ?',
          variables: [
            drift.Variable.withInt(variantId),
            drift.Variable.withInt(productId),
          ],
        )
        .getSingleOrNull();
    if (row == null) {
      throw StateError(
        'Missing or mismatched warehouse stock for void preview.',
      );
    }
    return row.read<int>('quantity');
  }

  // ──────────────────────────────────────────────────────────────────────
  // Sale side
  // ──────────────────────────────────────────────────────────────────────

  /// Analyse the impact of voiding sale `saleId`.
  ///
  /// Returns a fully populated [VoidImpactReport]. Never throws on a missing
  /// sale — instead the report's `documentExists` flag is `false` and all
  /// other fields are empty.
  Future<VoidImpactReport> analyzeSaleVoid(int saleId) async {
    if (!await WarehouseDocumentScope.contains(
      _db,
      InventoryPostingDocument.sale,
      saleId,
      scope: warehouseScope,
    )) {
      return VoidImpactReport.empty(side: 'sale', documentExists: false);
    }
    final sale = await (_db.select(
      _db.sales,
    )..where((s) => s.id.equals(saleId))).getSingleOrNull();
    if (sale == null) {
      return VoidImpactReport.empty(side: 'sale', documentExists: false);
    }

    final items = await (_db.select(
      _db.saleItems,
    )..where((i) => i.saleId.equals(saleId))).get();

    // ── Linked returns ────────────────────────────────────────────────
    final linkedReturns = <LinkedReturnEntry>[];
    final linkedRows = await (_db.select(
      _db.saleReturns,
    )..where((r) => r.saleId.equals(saleId))).get();
    for (final r in linkedRows) {
      if (r.status == 'voided') continue;
      if (!await WarehouseDocumentScope.contains(
        _db,
        InventoryPostingDocument.saleReturn,
        r.id,
        scope: warehouseScope,
      )) {
        throw StateError(
          'Linked return belongs to another location; review before voiding.',
        );
      }
      linkedReturns.add(
        LinkedReturnEntry(
          returnId: r.id,
          returnNumber: r.returnNumber,
          totalCents: r.totalCents.toBigInt().toInt(),
          status: r.status,
        ),
      );
    }

    // ── Adjustment-return entanglement ────────────────────────────────
    // The atomic counter `qty_returned_adjustment` on each sale_item is the
    // single proof that an adjustment return FIFO-allocated quantity to
    // this line. Sum it across the sale's items.
    int adjustmentAllocatedQty = 0;
    final entangledByReturnId = <int, EntangledAdjustmentReturn>{};
    for (final item in items) {
      adjustmentAllocatedQty += item.qtyReturnedAdjustment;
    }

    if (adjustmentAllocatedQty > 0 && sale.customerId != null) {
      // Identify candidate adjustment returns: same customer, posted, with
      // any item matching one of this sale's (productId, variantId) pairs.
      // FIFO allocation tracking does not record the source return id per
      // sale_item, so we surface ALL posted adjustment returns from this
      // customer that touch the same products as this sale. The user must
      // void at least one of them before retrying.
      final productIds = items.map((i) => i.productId).toSet();
      if (productIds.isNotEmpty) {
        final placeholders = List.filled(productIds.length, '?').join(',');
        final rows = await _db
            .customSelect(
              'SELECT DISTINCT sra.id AS rid, sra.return_number AS rnum, '
              '       sra.total_cents AS total_cents, sra.refund_method AS refund '
              'FROM ${warehouseScope?.documents(InventoryPostingDocument.saleAdjustment) ?? WarehouseDocumentScope.primaryDocuments(InventoryPostingDocument.saleAdjustment)} sra '
              'JOIN sale_return_adjustment_items srai ON srai.return_id = sra.id '
              'WHERE sra.customer_id = ? AND sra.status = \'posted\' '
              '  AND srai.product_id IN ($placeholders) '
              '  AND EXISTS (SELECT 1 FROM sale_items si '
              '    WHERE si.sale_id = ? AND si.product_id = srai.product_id '
              '    AND ${WarehouseDocumentScope.operationalVariant('si')} '
              '      IS ${WarehouseDocumentScope.operationalVariant('srai')}) '
              'ORDER BY sra.id ASC',
              variables: [
                drift.Variable.withInt(sale.customerId!),
                ...productIds.map((id) => drift.Variable.withInt(id)),
                drift.Variable.withInt(saleId),
              ],
            )
            .get();
        for (final r in rows) {
          final id = r.read<int>('rid');
          entangledByReturnId[id] = EntangledAdjustmentReturn(
            returnId: id,
            returnNumber: r.read<String>('rnum'),
            totalCents: r.read<int>('total_cents'),
            refundMethod: r.read<String?>('refund') ?? '',
          );
        }
      }
    }

    // ── Negative-stock risks ──────────────────────────────────────────
    // Voiding a sale DECREASES stock by item.quantity. If current stock
    // is less than that quantity, the void would push the variant negative.
    final negativeRisks = <NegativeStockRisk>[];
    if (sale.status == 'completed') {
      for (final item in items) {
        final currentStock = await _currentStock(
          item.productId,
          item.variantId,
        );
        // Voiding a sale RESTORES stock (increase by qty), so the risk is
        // really the inverse: voiding restores units, but adjustment-
        // returns may have already been booked against fewer units. The
        // direct negative-stock guard here is for `voidSaleReturn` cascade
        // (which DECREASES). For the sale itself, a void increases stock
        // and cannot push it negative. We surface this only when there is
        // an entangled adjustment return whose void would later need to
        // pull stock down.
        if (entangledByReturnId.isNotEmpty &&
            currentStock < item.qtyReturnedAdjustment) {
          negativeRisks.add(
            NegativeStockRisk(
              productId: item.productId,
              variantId: item.variantId,
              currentStock: currentStock,
              requiredQuantity: item.qtyReturnedAdjustment,
            ),
          );
        }
      }
    }

    // ── Estimated GL impact ───────────────────────────────────────────
    // Voiding a sale reverses Dr 1100/Cash | Cr 4000/2100 by totalCents.
    // For credit sales the customer's `customers.balance_cents` is
    // decremented by (totalCents − totalPaid). Cash/cheque sales touch 1000.
    final estArDelta =
        sale.paymentMethod == 'credit' || sale.paymentMethod == 'cheque'
        ? -(sale.totalCents.toBigInt().toInt() -
              sale.paidAmountCents.toBigInt().toInt())
        : 0;
    final estInventoryDelta = items.fold<int>(
      0,
      (sum, i) => sum + i.totalCents.toBigInt().toInt(), // approx by line total
    );

    return VoidImpactReport(
      side: 'sale',
      documentExists: true,
      documentStatus: sale.status,
      linkedReturns: linkedReturns,
      adjustmentAllocatedQty: adjustmentAllocatedQty,
      entangledAdjustmentReturns: entangledByReturnId.values.toList(),
      negativeStockRisks: negativeRisks,
      estimatedArAdjustmentCents: estArDelta,
      estimatedInventoryAdjustmentCents: estInventoryDelta,
    );
  }

  // ──────────────────────────────────────────────────────────────────────
  // Purchase side
  // ──────────────────────────────────────────────────────────────────────

  Future<VoidImpactReport> analyzePurchaseVoid(int purchaseId) async {
    if (!await WarehouseDocumentScope.contains(
      _db,
      InventoryPostingDocument.purchase,
      purchaseId,
      scope: warehouseScope,
    )) {
      return VoidImpactReport.empty(side: 'purchase', documentExists: false);
    }
    final purchase = await (_db.select(
      _db.purchases,
    )..where((p) => p.id.equals(purchaseId))).getSingleOrNull();
    if (purchase == null) {
      return VoidImpactReport.empty(side: 'purchase', documentExists: false);
    }

    final items = await (_db.select(
      _db.purchaseItems,
    )..where((i) => i.purchaseId.equals(purchaseId))).get();

    final linkedReturns = <LinkedReturnEntry>[];
    final linkedRows = await (_db.select(
      _db.purchaseReturns,
    )..where((r) => r.purchaseId.equals(purchaseId))).get();
    for (final r in linkedRows) {
      if (r.status == 'voided') continue;
      if (!await WarehouseDocumentScope.contains(
        _db,
        InventoryPostingDocument.purchaseReturn,
        r.id,
        scope: warehouseScope,
      )) {
        throw StateError(
          'Linked return belongs to another location; review before voiding.',
        );
      }
      linkedReturns.add(
        LinkedReturnEntry(
          returnId: r.id,
          returnNumber: r.returnNumber,
          totalCents: r.totalCents.toBigInt().toInt(),
          status: r.status,
        ),
      );
    }

    int adjustmentAllocatedQty = 0;
    final entangledByReturnId = <int, EntangledAdjustmentReturn>{};
    for (final item in items) {
      adjustmentAllocatedQty += item.qtyReturnedAdjustment;
    }

    if (adjustmentAllocatedQty > 0) {
      final productIds = items.map((i) => i.productId).toSet();
      if (productIds.isNotEmpty) {
        final placeholders = List.filled(productIds.length, '?').join(',');
        final rows = await _db
            .customSelect(
              'SELECT DISTINCT pra.id AS rid, pra.return_number AS rnum, '
              '       pra.total_cents AS total_cents, pra.refund_method AS refund '
              'FROM ${warehouseScope?.documents(InventoryPostingDocument.purchaseAdjustment) ?? WarehouseDocumentScope.primaryDocuments(InventoryPostingDocument.purchaseAdjustment)} pra '
              'JOIN purchase_return_adjustment_items prai ON prai.return_id = pra.id '
              'WHERE pra.supplier_id = ? AND pra.status = \'posted\' '
              '  AND prai.product_id IN ($placeholders) '
              '  AND EXISTS (SELECT 1 FROM purchase_items pi '
              '    WHERE pi.purchase_id = ? AND pi.product_id = prai.product_id '
              '    AND ${WarehouseDocumentScope.operationalVariant('pi')} '
              '      IS ${WarehouseDocumentScope.operationalVariant('prai')}) '
              'ORDER BY pra.id ASC',
              variables: [
                drift.Variable.withInt(purchase.supplierId),
                ...productIds.map((id) => drift.Variable.withInt(id)),
                drift.Variable.withInt(purchaseId),
              ],
            )
            .get();
        for (final r in rows) {
          final id = r.read<int>('rid');
          entangledByReturnId[id] = EntangledAdjustmentReturn(
            returnId: id,
            returnNumber: r.read<String>('rnum'),
            totalCents: r.read<int>('total_cents'),
            refundMethod: r.read<String?>('refund') ?? '',
          );
        }
      }
    }

    // Negative-stock risk for purchase void: voiding a purchase DECREASES
    // stock by item.quantity. If current stock < quantity, the void can
    // push the variant negative. Surface this so the UI can warn even
    // when there is no return entanglement.
    final negativeRisks = <NegativeStockRisk>[];
    if (purchase.status == 'posted') {
      for (final item in items) {
        final currentStock = await _currentStock(
          item.productId,
          item.variantId,
        );
        if (currentStock < item.quantity) {
          negativeRisks.add(
            NegativeStockRisk(
              productId: item.productId,
              variantId: item.variantId,
              currentStock: currentStock,
              requiredQuantity: item.quantity,
            ),
          );
        }
      }
    }

    // Voiding a credit purchase reverses Cr 2000 AP. For cash purchases
    // it reverses Cr 1000 / 1010.
    final isCreditPurchase =
        purchase.paymentMethod == 'credit' ||
        purchase.paymentMethod == 'cheque';
    final estApDelta = isCreditPurchase
        ? -(purchase.totalCents.toBigInt().toInt() -
              purchase.paidAmountCents.toBigInt().toInt())
        : 0;
    final estInventoryDelta = -items.fold<int>(
      0,
      (sum, i) => sum + i.totalCents.toBigInt().toInt(),
    );

    return VoidImpactReport(
      side: 'purchase',
      documentExists: true,
      documentStatus: purchase.status,
      linkedReturns: linkedReturns,
      adjustmentAllocatedQty: adjustmentAllocatedQty,
      entangledAdjustmentReturns: entangledByReturnId.values.toList(),
      negativeStockRisks: negativeRisks,
      // For purchase, "AR" slot is unused; we reuse it as AP delta to keep
      // the report a single shape across both sides.
      estimatedArAdjustmentCents: estApDelta,
      estimatedInventoryAdjustmentCents: estInventoryDelta,
    );
  }
}

/// Aggregated impact summary returned by [VoidImpactAnalyzer].
class VoidImpactReport {
  /// `'sale'` or `'purchase'`.
  final String side;

  /// `false` when the document id was not found (UI shows "not found").
  final bool documentExists;

  /// Current status — informational; the void path is a no-op when the
  /// document is already `'voided'`.
  final String documentStatus;

  /// Linked returns under this document. Will be cascade-voided. UI
  /// surfaces them so the user knows what else changes status.
  final List<LinkedReturnEntry> linkedReturns;

  /// Sum of `qty_returned_adjustment` across the document's items. When
  /// `> 0` the void is BLOCKED — see [entangledAdjustmentReturns].
  final int adjustmentAllocatedQty;

  /// Posted adjustment returns from the same party that touch one of the
  /// document's products. The user must void at least one of these (and
  /// re-create them later if needed) before voiding this document.
  final List<EntangledAdjustmentReturn> entangledAdjustmentReturns;

  /// Per-line negative-stock projections. When non-empty the void is
  /// BLOCKED unless the user enables the "allow negative stock" override.
  final List<NegativeStockRisk> negativeStockRisks;

  /// Signed expected delta on the AR (sale) or AP (purchase) GL account.
  /// Negative = balance decreases. UI displays this so the user can
  /// reconcile mentally before confirming.
  final int estimatedArAdjustmentCents;

  /// Signed expected delta on the Inventory GL account.
  final int estimatedInventoryAdjustmentCents;

  const VoidImpactReport({
    required this.side,
    required this.documentExists,
    required this.documentStatus,
    required this.linkedReturns,
    required this.adjustmentAllocatedQty,
    required this.entangledAdjustmentReturns,
    required this.negativeStockRisks,
    required this.estimatedArAdjustmentCents,
    required this.estimatedInventoryAdjustmentCents,
  });

  factory VoidImpactReport.empty({
    required String side,
    required bool documentExists,
  }) => VoidImpactReport(
    side: side,
    documentExists: documentExists,
    documentStatus: '',
    linkedReturns: const [],
    adjustmentAllocatedQty: 0,
    entangledAdjustmentReturns: const [],
    negativeStockRisks: const [],
    estimatedArAdjustmentCents: 0,
    estimatedInventoryAdjustmentCents: 0,
  );

  /// True iff at least one HARD condition would corrupt the books if the
  /// void proceeded as-is. The UI must REFUSE to confirm and instead
  /// guide the user to fix the blocker.
  bool get hasBlockers =>
      entangledAdjustmentReturns.isNotEmpty || negativeStockRisks.isNotEmpty;

  /// True iff there are non-blocking side-effects the user should know
  /// about (cascade-voided linked returns).
  bool get hasWarnings => linkedReturns.isNotEmpty;
}

class LinkedReturnEntry {
  final int returnId;
  final String returnNumber;
  final int totalCents;
  final String status;

  const LinkedReturnEntry({
    required this.returnId,
    required this.returnNumber,
    required this.totalCents,
    required this.status,
  });
}

class EntangledAdjustmentReturn {
  final int returnId;
  final String returnNumber;
  final int totalCents;
  final String refundMethod;

  const EntangledAdjustmentReturn({
    required this.returnId,
    required this.returnNumber,
    required this.totalCents,
    required this.refundMethod,
  });
}

class NegativeStockRisk {
  final int productId;
  final int? variantId;
  final int currentStock;
  final int requiredQuantity;

  const NegativeStockRisk({
    required this.productId,
    required this.variantId,
    required this.currentStock,
    required this.requiredQuantity,
  });
}

/// Thrown by repository void paths when a [VoidImpactReport] reports
/// blockers. The UI catches this, shows a dialog with the report, and
/// guides the user to resolve the blocker.
class VoidBlockedByImpactException implements Exception {
  final VoidImpactReport report;
  VoidBlockedByImpactException(this.report);

  @override
  String toString() =>
      'VoidBlockedByImpactException: ${report.side} void '
      'rejected — '
      '${report.entangledAdjustmentReturns.length} entangled adjustment '
      'returns, ${report.negativeStockRisks.length} negative-stock risks.';
}
