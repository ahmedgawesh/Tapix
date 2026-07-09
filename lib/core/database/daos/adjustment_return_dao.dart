import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/transactions.dart';
import '../tables/parties.dart';
import '../tables/products.dart';
import '../../services/stock_service.dart';
import '../../services/balance_service.dart';
import '../../services/batch_service.dart';
import '../../services/journal_entry_service.dart';
import '../../services/commissions/commission_service.dart';
import '../../services/loyalty/loyalty_points_service.dart';
import '../../services/tax_calculation_service.dart';
import '../../services/returns/posted_return.dart';
import '../../services/returns/return_approval_decision.dart';
import '../../services/returns/return_approval_exceptions.dart';
import '../../services/returns/return_approval_service.dart';

part 'adjustment_return_dao.g.dart';

/// Thrown when a return cannot be processed because stock is insufficient.
class StockInsufficientException implements Exception {
  final int? variantId;
  final int productId;
  final int currentStock;
  final int requestedQuantity;

  StockInsufficientException({
    this.variantId,
    required this.productId,
    required this.currentStock,
    required this.requestedQuantity,
  });

  @override
  String toString() =>
      'StockInsufficientException: stock ($currentStock) < requested ($requestedQuantity) '
      'for ${variantId != null ? "variant #$variantId" : "product #$productId"}';
}

/// Thrown when an adjustment / unlinked return tries to send back more units
/// of a `(party, product, variant)` than the party's net invoice history
/// supports — i.e. the requested qty would exceed
/// `Σ(invoiced) − Σ(already_returned_linked) − Σ(already_returned_adjustment)`.
///
/// This is the **server-side hard cap** introduced in Phase 0. The previous
/// system relied on a UI warning that did not block submission, and the DAO
/// only checked stock — both of which let an operator return more pieces
/// than the party ever bought / supplied.
///
/// The exception carries enough context for the UI to surface a precise,
/// actionable message in any locale (the `toString()` is for logs only).
class QuantityExceedsHistoryException implements Exception {
  /// `'sale'` or `'purchase'` — which side of the ledger raised the cap.
  final String side;
  final int? partyId;
  final int productId;
  final int? variantId;

  /// Requested return quantity for this `(product, variant)` line.
  final int requestedQuantity;

  /// Net returnable quantity from history at the moment of the check:
  ///   `historicallyInvoiced − alreadyReturnedLinked − alreadyReturnedAdjustment`.
  /// Always non-negative; zero means "nothing left to return".
  final int availableQuantity;

  /// Sum of invoiced quantity from this party for the line.
  final int historicallyInvoiced;

  /// Sum of already-returned quantity (both linked + adjustment) for the line.
  final int alreadyReturned;

  QuantityExceedsHistoryException({
    required this.side,
    required this.partyId,
    required this.productId,
    required this.variantId,
    required this.requestedQuantity,
    required this.availableQuantity,
    required this.historicallyInvoiced,
    required this.alreadyReturned,
  });

  @override
  String toString() =>
      'QuantityExceedsHistoryException: $side return requested '
      '$requestedQuantity for product #$productId'
      '${variantId != null ? " (variant #$variantId)" : ""}'
      ' from party #$partyId — only $availableQuantity available '
      '(invoiced $historicallyInvoiced, already returned $alreadyReturned).';
}

/// Data class for purchase adjustment return item with product details
class PurchaseAdjReturnItemWithDetails {
  final PurchaseReturnAdjustmentItem item;
  final Product product;
  final ProductVariant? variant;

  PurchaseAdjReturnItemWithDetails({
    required this.item,
    required this.product,
    this.variant,
  });
}

/// Data class for sale adjustment return item with product details
class SaleAdjReturnItemWithDetails {
  final SaleReturnAdjustmentItem item;
  final Product product;
  final ProductVariant? variant;

  SaleAdjReturnItemWithDetails({
    required this.item,
    required this.product,
    this.variant,
  });
}

/// Data class for purchase adjustment return joined with supplier info
class PurchaseAdjReturnWithParty {
  final PurchaseReturnAdjustment adjustment;
  final String? supplierName;
  final String? supplierPhone;

  PurchaseAdjReturnWithParty({
    required this.adjustment,
    this.supplierName,
    this.supplierPhone,
  });
}

/// Data class for sale adjustment return joined with customer info
class SaleAdjReturnWithParty {
  final SaleReturnAdjustment adjustment;
  final String? customerName;
  final String? customerPhone;

  SaleAdjReturnWithParty({
    required this.adjustment,
    this.customerName,
    this.customerPhone,
  });
}

@DriftAccessor(tables: [
  PurchaseReturnAdjustments,
  PurchaseReturnAdjustmentItems,
  SaleReturnAdjustments,
  SaleReturnAdjustmentItems,
  Products,
  ProductVariants,
  Suppliers,
  Customers,
  SupplierTransactions,
  CustomerTransactions,
  Sales,
  SaleItems,
  Purchases,
  PurchaseItems,
])
class AdjustmentReturnDao extends DatabaseAccessor<AppDatabase>
    with _$AdjustmentReturnDaoMixin {
  AdjustmentReturnDao(super.db);

  /// Returns `true` when the product needs **batch-level books**.
  ///
  /// Phase B (two-layer inventory architecture): the predicate is the OR of
  /// `inventory_tracking_type IN ('batch','batch_expiry')` and the legacy
  /// `costing_method = 'fifo'`. Both stay in sync via `setInventoryTrackingType`
  /// and migration v10048; the OR is defensive against transient skew.
  Future<bool> _isFifoProduct(int productId) async {
    final row = await customSelect(
      'SELECT inventory_tracking_type, costing_method FROM products WHERE id = ?',
      variables: [Variable.withInt(productId)],
    ).getSingleOrNull();
    if (row == null) return false;
    final tracking = row.read<String?>('inventory_tracking_type');
    if (tracking == 'batch' || tracking == 'batch_expiry') return true;
    return (row.read<String?>('costing_method') ?? 'wac') == 'fifo';
  }

  /// Bulk-read the per-product `track_inventory` flag for the given ids in
  /// one round-trip. Defaults to `true` for any id whose row is missing —
  /// matches the column default and avoids surprising stock-skip behaviour
  /// for legacy rows. Returned map keys are productIds so callers can do
  /// `tracked[item.productId] == false` cleanly inside a loop.
  Future<Map<int, bool>> _trackInventoryByProduct(Set<int> productIds) async {
    if (productIds.isEmpty) return const {};
    final placeholders = List.filled(productIds.length, '?').join(',');
    final rows = await customSelect(
      'SELECT id, track_inventory FROM products WHERE id IN ($placeholders)',
      variables: productIds.map((id) => Variable.withInt(id)).toList(),
    ).get();
    final out = <int, bool>{for (final id in productIds) id: true};
    for (final r in rows) {
      out[r.read<int>('id')] = r.read<int>('track_inventory') == 1;
    }
    return out;
  }

  /// Resolve a concrete `variantId` for a stock movement.
  ///
  /// `StockService.adjustStock` requires a real variantId whenever the product
  /// does not have a strict default variant (color_id IS NULL AND size_id IS
  /// NULL). Adjustment-return line items can arrive with `variantId == null`
  /// from entry points that don't carry the variant context (deep links from
  /// product detail screens, legacy data, etc.) — even for products that do
  /// have variants. Without this resolver every such submission would fail
  /// with a `StateError` from StockService and surface to the user as a
  /// generic "return failed" toast.
  ///
  /// Resolution order (matches the rest of the app, e.g. the product picker
  /// and `getDefaultVariantByProduct`):
  ///   1. The passed [variantId], when non-null.
  ///   2. The strict default variant (color_id IS NULL AND size_id IS NULL).
  ///   3. The lowest-id active variant for the product (any color/size).
  /// Throws if no active variant exists at all — that is a genuine data
  /// integrity problem that must not be silently swallowed.
  Future<int?> _resolveVariantIdForStock({
    required int productId,
    required int? variantId,
  }) async {
    if (variantId != null) return variantId;

    // Try strict default first — this is what StockService prefers and what
    // non-variant products always have.
    final strict = await customSelect(
      'SELECT id FROM product_variants '
      'WHERE product_id = ? AND color_id IS NULL AND size_id IS NULL '
      '  AND is_active = 1 '
      'ORDER BY id ASC LIMIT 1',
      variables: [Variable.withInt(productId)],
    ).getSingleOrNull();
    if (strict != null) {
      // A strict default exists — StockService can handle a null variantId
      // for this product, so keep the null semantics so it also updates the
      // products table directly (which is its happy path).
      return null;
    }

    // No strict default → product has variants. Pick the lowest-id active
    // variant deterministically so subsequent reads/voids are stable.
    final fallback = await customSelect(
      'SELECT id FROM product_variants '
      'WHERE product_id = ? AND is_active = 1 '
      'ORDER BY id ASC LIMIT 1',
      variables: [Variable.withInt(productId)],
    ).getSingleOrNull();
    if (fallback != null) {
      return fallback.read<int>('id');
    }

    throw StateError(
      'AdjustmentReturnDao: product=$productId has no active variant. '
      'Cannot adjust stock for an adjustment return line referencing it.',
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // HISTORICAL QUANTITY QUERIES (for fraud-prevention warnings)
  // ══════════════════════════════════════════════════════════════════════════

  /// Total quantity of a given (product, variant) that [customerId] has
  /// purchased across all completed sales. Used to warn when an unlinked
  /// (adjustment) sale return exceeds — or has no basis in — history.
  /// Returns 0 if customerId is null, or the customer never bought it.
  ///
  /// When [variantId] is null (caller is treating the product as "no variant"),
  /// the query intentionally drops the variant filter entirely and matches
  /// any historical row for the same `(customer, product)`. The sale form
  /// resolves non-variant products to whatever `getDefaultVariantByProduct`
  /// returns at save time — which is the strict default when present, but
  /// otherwise falls back to ANY active variant (e.g. a default that was
  /// later given a color/size). Filtering on a strict default id therefore
  /// misses the legitimate row and produces a bogus "never purchased" warning.
  /// Since the picker only emits `variantId: null` for products where
  /// `hasVariants == false`, the per-product aggregation is exactly the
  /// intended history.
  Future<int> getCustomerProductPurchasedQty({
    required int? customerId,
    required int productId,
    int? variantId,
  }) async {
    if (customerId == null) return 0;
    final qtyExp = saleItems.quantity.sum();
    final query = selectOnly(saleItems).join([
      innerJoin(sales, sales.id.equalsExp(saleItems.saleId)),
    ])
      ..addColumns([qtyExp])
      // 2026-05-13 — exclude voided / draft / pending sales from the cap.
      // Without this filter the cap counts items from sales that were
      // either never delivered (draft / pending) or already reversed
      // (voided), letting an adjustment return ship goods that the party
      // never actually received. Confirmed in the field via
      // tapix_backup_20260513_121448.db: $148.50 inventory drift +
      // $229.97 AR drift after a sale with a posted adjustment return
      // was voided. Mirror in `getSupplierProductSuppliedQty`.
      ..where(sales.status.equals('completed'))
      ..where(sales.customerId.equals(customerId))
      ..where(saleItems.productId.equals(productId));
    if (variantId != null) {
      query.where(saleItems.variantId.equals(variantId));
    }
    // else: no variant filter — see doc comment above.
    final row = await query.getSingleOrNull();
    return row?.read(qtyExp) ?? 0;
  }

  /// Total quantity of a given (product, variant) that was sold *by*
  /// [employeeId] across all completed sales. Used to warn — on an
  /// unlinked (adjustment) sale return — when the attributed salesperson
  /// never actually sold the product being returned.
  ///
  /// Mirrors the commission attribution rule in `SaleRepositoryImpl` and
  /// `getEmployeeSalesStats`: a sale is credited to the salesperson either
  /// via the header (`sales.employee_id`, per-invoice mode) or via the line
  /// item (`sale_items.employee_id`, per-item mode). Both paths are counted
  /// here. Voided / draft / pending sales are excluded so the warning only
  /// reflects goods that were actually sold and delivered.
  ///
  /// When [variantId] is null the variant filter is dropped (same rationale
  /// as `getCustomerProductPurchasedQty`). Returns 0 when the employee never
  /// sold the product.
  Future<int> getEmployeeProductSoldQty({
    required int? employeeId,
    required int productId,
    int? variantId,
  }) async {
    if (employeeId == null) return 0;
    final variantClause =
        variantId != null ? 'AND si.variant_id = ${variantId.toString()} ' : '';
    final row = await customSelect(
      'SELECT COALESCE(SUM(si.quantity), 0) AS c '
      'FROM sale_items si '
      'JOIN sales s ON s.id = si.sale_id '
      "WHERE s.status = 'completed' "
      '  AND si.product_id = ? '
      '  AND (s.employee_id = ? OR si.employee_id = ?) '
      '$variantClause',
      variables: [
        Variable.withInt(productId),
        Variable.withInt(employeeId),
        Variable.withInt(employeeId),
      ],
    ).getSingleOrNull();
    return row?.read<int>('c') ?? 0;
  }

  /// Total quantity of a given (product, variant) that [supplierId] has
  /// supplied across all completed purchases. Used to warn when an
  /// unlinked (adjustment) purchase return exceeds — or has no basis
  /// in — history. Returns 0 if the supplier never supplied it.
  ///
  /// When [variantId] is null (caller is treating the product as "no variant"),
  /// the query intentionally drops the variant filter entirely and matches
  /// any historical row for the same `(supplier, product)`. The purchase
  /// form resolves non-variant products to whatever
  /// `getDefaultVariantByProduct` returns at save time — which is the strict
  /// default when present, but otherwise falls back to ANY active variant
  /// (e.g. a default that was later given a color/size). Filtering on a
  /// strict default id therefore misses the legitimate row and produces a
  /// bogus "never supplied" warning. Since the picker only emits
  /// `variantId: null` for products where `hasVariants == false`, the
  /// per-product aggregation is exactly the intended history.
  Future<int> getSupplierProductSuppliedQty({
    required int supplierId,
    required int productId,
    int? variantId,
  }) async {
    final qtyExp = purchaseItems.quantity.sum();
    final query = selectOnly(purchaseItems).join([
      innerJoin(purchases, purchases.id.equalsExp(purchaseItems.purchaseId)),
    ])
      ..addColumns([qtyExp])
      // 2026-05-13 — symmetric fix to `getCustomerProductPurchasedQty`.
      // Only `'posted'` purchases physically delivered goods; `'draft'`
      // and `'voided'` rows must not feed the adjustment-return cap.
      ..where(purchases.status.equals('posted'))
      ..where(purchases.supplierId.equals(supplierId))
      ..where(purchaseItems.productId.equals(productId));
    if (variantId != null) {
      query.where(purchaseItems.variantId.equals(variantId));
    }
    // else: no variant filter — see doc comment above.
    final row = await query.getSingleOrNull();
    return row?.read(qtyExp) ?? 0;
  }

  /// Sum of `qty_returned_linked + qty_returned_adjustment` on every
  /// `sale_items` row matching `(customerId, productId, variantId)` — i.e.
  /// the total units the customer already returned across linked AND
  /// adjustment paths. Reads from the **atomic counters** (Phase 0), so the
  /// answer is consistent with the cap enforced inside transactions.
  ///
  /// `variantId == null` matches every variant for the product (mirrors
  /// `getCustomerProductPurchasedQty` for non-variant products).
  Future<int> getCustomerProductReturnedQty({
    required int? customerId,
    required int productId,
    int? variantId,
  }) async {
    if (customerId == null) return 0;
    final variantClause =
        variantId != null ? 'AND si.variant_id = ${variantId.toString()} ' : '';
    final row = await customSelect(
      'SELECT COALESCE(SUM(si.qty_returned_linked + si.qty_returned_adjustment), 0) AS c '
      'FROM sale_items si '
      'JOIN sales s ON s.id = si.sale_id '
      "WHERE s.status = 'completed' AND s.customer_id = ? "
      '  AND si.product_id = ? '
      '$variantClause',
      variables: [
        Variable.withInt(customerId),
        Variable.withInt(productId),
      ],
    ).getSingleOrNull();
    return row?.read<int>('c') ?? 0;
  }

  /// Mirror of [getCustomerProductReturnedQty] for the supplier side.
  Future<int> getSupplierProductReturnedQty({
    required int supplierId,
    required int productId,
    int? variantId,
  }) async {
    final variantClause =
        variantId != null ? 'AND pi.variant_id = ${variantId.toString()} ' : '';
    final row = await customSelect(
      'SELECT COALESCE(SUM(pi.qty_returned_linked + pi.qty_returned_adjustment), 0) AS c '
      'FROM purchase_items pi '
      'JOIN purchases pu ON pu.id = pi.purchase_id '
      "WHERE pu.status = 'posted' AND pu.supplier_id = ? "
      '  AND pi.product_id = ? '
      '$variantClause',
      variables: [
        Variable.withInt(supplierId),
        Variable.withInt(productId),
      ],
    ).getSingleOrNull();
    return row?.read<int>('c') ?? 0;
  }

  /// Server-side hard cap for adjustment / unlinked returns.
  ///
  /// Throws [QuantityExceedsHistoryException] when
  /// `requestedQuantity > Σ(invoiced) − Σ(already_returned)`.
  ///
  /// Pass [allowOverHistory] = true ONLY when an explicit manager override has
  /// been recorded with a `reason` — never as a UI default. This is the same
  /// policy SAP / NetSuite / Odoo apply: an over-return is allowed only when
  /// the user has authorised the deviation; the system never silently lets
  /// it slip.
  ///
  /// Walk-in customers (`customerId == null`) cannot exceed history because
  /// they have no history — this method short-circuits and throws if a
  /// positive request comes in for a sale-side adjustment with no customer
  /// (the bloc-side guard surfaces the same message earlier in the flow).
  Future<void> validateAdjustmentQuantityCap({
    required String side, // 'sale' or 'purchase'
    required int? partyId, // customerId or supplierId
    required int productId,
    required int? variantId,
    required int requestedQuantity,
    bool allowOverHistory = false,
  }) async {
    if (allowOverHistory) return;
    if (requestedQuantity <= 0) return;

    final int invoiced;
    final int returned;
    if (side == 'sale') {
      invoiced = await getCustomerProductPurchasedQty(
        customerId: partyId,
        productId: productId,
        variantId: variantId,
      );
      returned = await getCustomerProductReturnedQty(
        customerId: partyId,
        productId: productId,
        variantId: variantId,
      );
    } else if (side == 'purchase') {
      if (partyId == null) {
        throw ArgumentError(
          'validateAdjustmentQuantityCap: supplierId is required '
          'for purchase-side returns.',
        );
      }
      invoiced = await getSupplierProductSuppliedQty(
        supplierId: partyId,
        productId: productId,
        variantId: variantId,
      );
      returned = await getSupplierProductReturnedQty(
        supplierId: partyId,
        productId: productId,
        variantId: variantId,
      );
    } else {
      throw ArgumentError('side must be "sale" or "purchase", got "$side"');
    }

    final available = (invoiced - returned).clamp(0, 1 << 31);
    if (requestedQuantity > available) {
      throw QuantityExceedsHistoryException(
        side: side,
        partyId: partyId,
        productId: productId,
        variantId: variantId,
        requestedQuantity: requestedQuantity,
        availableQuantity: available,
        historicallyInvoiced: invoiced,
        alreadyReturned: returned,
      );
    }
  }

  /// FIFO allocation of `requestedQty` against the party's invoice items
  /// for `(productId, variantId)`, using the atomic
  /// `qty_returned_linked + qty_returned_adjustment` counter as the
  /// authoritative cap per line. Returns the chosen `(saleItemId, qty)`
  /// pairs in oldest-first order; total of returned `qty` <= `requestedQty`.
  ///
  /// Used by the adjustment-return post path to bump per-line counters in
  /// proportion to the adjustment quantity, so future caps stay accurate
  /// across mixed linked + adjustment usage.
  Future<List<({int saleItemId, int qty})>> _allocateSaleItemsForAdjustment({
    required int customerId,
    required int productId,
    required int? variantId,
    required int requestedQty,
  }) async {
    if (requestedQty <= 0) return const [];
    final variantClause =
        variantId != null ? 'AND si.variant_id = ${variantId.toString()} ' : '';
    final rows = await customSelect(
      'SELECT si.id AS item_id, si.quantity, '
      '       si.qty_returned_linked, si.qty_returned_adjustment '
      'FROM sale_items si '
      'JOIN sales s ON s.id = si.sale_id '
      "WHERE s.status = 'completed' AND s.customer_id = ? "
      '  AND si.product_id = ? '
      '$variantClause'
      'ORDER BY s.sale_date ASC, si.id ASC',
      variables: [
        Variable.withInt(customerId),
        Variable.withInt(productId),
      ],
    ).get();

    final out = <({int saleItemId, int qty})>[];
    int remaining = requestedQty;
    for (final r in rows) {
      if (remaining <= 0) break;
      final orig = r.read<int>('quantity');
      final retLinked = r.read<int>('qty_returned_linked');
      final retAdj = r.read<int>('qty_returned_adjustment');
      final available = orig - retLinked - retAdj;
      if (available <= 0) continue;
      final take = remaining < available ? remaining : available;
      out.add((saleItemId: r.read<int>('item_id'), qty: take));
      remaining -= take;
    }
    return out;
  }

  /// Mirror of [_allocateSaleItemsForAdjustment] for the supplier side.
  Future<List<({int purchaseItemId, int qty})>>
      _allocatePurchaseItemsForAdjustment({
    required int supplierId,
    required int productId,
    required int? variantId,
    required int requestedQty,
  }) async {
    if (requestedQty <= 0) return const [];
    final variantClause =
        variantId != null ? 'AND pi.variant_id = ${variantId.toString()} ' : '';
    final rows = await customSelect(
      'SELECT pi.id AS item_id, pi.quantity, '
      '       pi.qty_returned_linked, pi.qty_returned_adjustment '
      'FROM purchase_items pi '
      'JOIN purchases pu ON pu.id = pi.purchase_id '
      "WHERE pu.status = 'posted' AND pu.supplier_id = ? "
      '  AND pi.product_id = ? '
      '$variantClause'
      'ORDER BY pu.purchase_date ASC, pi.id ASC',
      variables: [
        Variable.withInt(supplierId),
        Variable.withInt(productId),
      ],
    ).get();

    final out = <({int purchaseItemId, int qty})>[];
    int remaining = requestedQty;
    for (final r in rows) {
      if (remaining <= 0) break;
      final orig = r.read<int>('quantity');
      final retLinked = r.read<int>('qty_returned_linked');
      final retAdj = r.read<int>('qty_returned_adjustment');
      final available = orig - retLinked - retAdj;
      if (available <= 0) continue;
      final take = remaining < available ? remaining : available;
      out.add((purchaseItemId: r.read<int>('item_id'), qty: take));
      remaining -= take;
    }
    return out;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PURCHASE ADJUSTMENT RETURNS
  // ══════════════════════════════════════════════════════════════════════════

  /// Watch all purchase adjustment returns
  Stream<List<PurchaseReturnAdjustment>> watchAllPurchaseAdjustmentReturns() {
    return (select(purchaseReturnAdjustments)
          ..orderBy([(r) => OrderingTerm.desc(r.returnDate)]))
        .watch();
  }

  /// Watch purchase adjustment returns by supplier
  Stream<List<PurchaseReturnAdjustment>> watchPurchaseAdjReturnsBySupplier(
      int supplierId) {
    return (select(purchaseReturnAdjustments)
          ..where((r) => r.supplierId.equals(supplierId))
          ..orderBy([(r) => OrderingTerm.desc(r.returnDate)]))
        .watch();
  }

  /// Get purchase adjustment return by ID
  Future<PurchaseReturnAdjustment?> getPurchaseAdjReturnById(int id) {
    return (select(purchaseReturnAdjustments)..where((r) => r.id.equals(id)))
        .getSingleOrNull();
  }

  /// Generate next purchase adjustment return number
  Future<String> generatePurchaseAdjReturnNumber() async {
    final now = DateTime.now();
    final prefix =
        'PAR-${now.year}${now.month.toString().padLeft(2, '0')}';

    final last = await (select(purchaseReturnAdjustments)
          ..where((r) => r.returnNumber.like('$prefix%'))
          ..orderBy([(r) => OrderingTerm.desc(r.returnNumber)])
          ..limit(1))
        .getSingleOrNull();

    int nextNum = 1;
    if (last != null) {
      final lastNum =
          int.tryParse(last.returnNumber.split('-').last) ?? 0;
      nextNum = lastNum + 1;
    }

    return '$prefix-${nextNum.toString().padLeft(4, '0')}';
  }

  /// Create purchase adjustment return with items.
  /// Automatically fetches and freezes each product's current cost_cents
  /// into `unitCostCents` for perpetual inventory journal entries.
  Future<int> createPurchaseAdjReturn(
    PurchaseReturnAdjustmentsCompanion returnData,
    List<PurchaseReturnAdjustmentItemsCompanion> items, {
    ReturnApprovalService? approvalService,
    bool overHistoryOverride = false,
  }) {
    return transaction(() async {
      for (final item in items) {
        assert(item.quantity.value > 0, 'quantity must be > 0');
        assert(item.productId.present, 'productId is required');
      }

      final returnId =
          await into(purchaseReturnAdjustments).insert(returnData);

      // ── Phase 3: approval-policy evaluation at draft time ──
      // Centralized in `ReturnApprovalService.evaluate`. The decision is
      // persisted on the header so `postPurchaseAdjReturn` and the UI
      // approval screen consume the same single source of truth.
      if (approvalService != null) {
        final totalCents = returnData.totalCents.present
            ? returnData.totalCents.value.toBigInt().toInt()
            : 0;
        final decision = await approvalService.evaluate(
          ReturnApprovalContext(
            totalCents: totalCents,
            linked: false,
            overHistoryOverride: overHistoryOverride,
            side: 'purchase',
          ),
        );
        await (update(purchaseReturnAdjustments)
              ..where((r) => r.id.equals(returnId)))
            .write(PurchaseReturnAdjustmentsCompanion(
          approvalStatus: Value(decision.persistedStatus),
          approvalRequired: Value(decision.required),
          approvalReason: Value(decision.persistedReason),
          updatedAt: Value(DateTime.now()),
        ));
      }

      for (final item in items) {
        // Auto-fetch current cost from variant or product
        int costCents = 0;
        if (item.variantId.present && item.variantId.value != null) {
          final row = await customSelect(
            'SELECT cost_cents FROM product_variants WHERE id = ?',
            variables: [Variable.withInt(item.variantId.value!)],
          ).getSingleOrNull();
          costCents = row?.read<int>('cost_cents') ?? 0;
        } else {
          final row = await customSelect(
            'SELECT cost_cents FROM products WHERE id = ?',
            variables: [Variable.withInt(item.productId.value)],
          ).getSingleOrNull();
          costCents = row?.read<int>('cost_cents') ?? 0;
        }

        final itemWithCost = item.copyWith(
          returnId: Value(returnId),
          unitCostCents: Value(Decimal.fromInt(costCents)),
        );
        await into(purchaseReturnAdjustmentItems).insert(itemWithCost);
      }

      return returnId;
    });
  }

  /// Post purchase adjustment return.
  ///
  /// BUSINESS LOGIC (Perpetual Inventory):
  /// 1. QUANTITY-CAP: refuse to return more units of (supplier, product,
  ///    variant) than `Σ(invoiced) − Σ(already_returned linked + adj)`
  ///    unless [allowOverHistory] is explicitly set by a manager override.
  /// 2. CREDIT/CHEQUE GUARD: AP/Bank refunds require a real supplier; we
  ///    refuse to create orphan ledgers with no party reference.
  /// 3. STOCK: decrease via StockService (goods leaving inventory).
  /// 4. BALANCE: reduce supplier balance (we owe them less).
  /// 5. ATOMIC COUNTERS: bump `qty_returned_adjustment` on the FIFO-oldest
  ///    matching `purchase_items` rows so the cap stays accurate for any
  ///    future return (linked or adjustment) of the same line.
  /// 6. JOURNAL: 4-way compound entry:
  ///    Financial: Dr AP (2000) | Cr Purchase Return Adj (4100)
  ///    Inventory: Dr COGS (5300) | Cr Inventory (1200)
  Future<void> postPurchaseAdjReturn(
    int returnId, {
    required JournalEntryService journalEntryService,
    int? userId,
    bool allowNegativeStock = false,
    bool allowOverHistory = false,
  }) {
    return transaction(() async {
      final returnData = await getPurchaseAdjReturnById(returnId);
      if (returnData == null) throw Exception('Adjustment return not found');
      if (returnData.status == 'posted') {
        throw Exception('Adjustment return already posted');
      }
      if (returnData.status == 'voided') {
        throw Exception('Cannot post a voided adjustment return');
      }

      // Defense-in-depth: AP/Bank refunds require a real supplier — orphan
      // ledger entries make AP aging meaningless. The bloc already prevents
      // this in the UI; we re-assert here so any non-UI caller (test, batch
      // import, future API) cannot bypass it.
      if (returnData.refundMethod == 'credit' ||
          returnData.refundMethod == 'cheque') {
        // supplierId on PurchaseReturnAdjustments is non-nullable but we
        // still defend against an upstream zero / negative slipping in.
        if (returnData.supplierId <= 0) {
          throw StateError(
            'Purchase adjustment return #$returnId uses '
            "refund_method='${returnData.refundMethod}' but supplierId is "
            'not set — cannot post an orphan AP/Bank ledger entry.',
          );
        }
      }

      final items = await getPurchaseAdjReturnItems(returnId);

      // ── Quantity-cap pre-check (atomic + per-line aggregated) ──
      // Aggregate request by (productId, variantId) so two lines in the
      // same return targeting the same product get a single capped check.
      final requestByLine = <String, int>{};
      for (final item in items) {
        final key = '${item.productId}:${item.variantId ?? 'null'}';
        requestByLine[key] = (requestByLine[key] ?? 0) + item.quantity;
      }
      for (final entry in requestByLine.entries) {
        final parts = entry.key.split(':');
        final pid = int.parse(parts[0]);
        final vid = parts[1] == 'null' ? null : int.parse(parts[1]);
        await validateAdjustmentQuantityCap(
          side: 'purchase',
          partyId: returnData.supplierId,
          productId: pid,
          variantId: vid,
          requestedQuantity: entry.value,
          allowOverHistory: allowOverHistory,
        );
      }
      final affectedProductIds = <int>{};
      // I4 (Invariant I1): products whose batch ledger was actually mutated.
      // Used to bound the cross-table assertion to FIFO/batch products —
      // WAC products legitimately have stock without matching batch rows so
      // an unconditional assertion would false-positive.
      final batchedProductIds = <int>{};
      int totalInventoryCostCents = 0;
      int totalTaxCents = 0;

      // ── Single source of truth for the inventory (1200) GL leg ──
      // The amount credited to 1200 MUST equal the ACTUAL inventory
      // valuation removed by the stock ledger, never the product's current
      // cost. For FIFO products the goods leave specific batches at their
      // FROZEN per-batch cost — which is exactly how
      // `getTotalInventoryValueCents` values them — so the GL leg must use
      // Σ(consumed batch cost). Using the product's current cost instead
      // (the old behaviour) drifts 1200 away from Σ(stock×cost) by
      // (batch_cost − product_cost) × qty on every FIFO line. Keyed by
      // return-item id so the per-line journal entry stays exact.
      final actualInvCostByItem = <int, int>{};

      // Per-product track_inventory map. Non-tracked products (services,
      // labour, expense-only items) skip every stock / batch / negative-stock
      // hook below but still hit the GL — accounting must still book the
      // financial leg even when there's no perpetual-inventory leg.
      final trackedByProduct = await _trackInventoryByProduct(
        items.map((i) => i.productId).toSet(),
      );

      for (final item in items) {
        final tracksInventory = trackedByProduct[item.productId] ?? true;

        // Tax is aggregated for every line (tracked or not).
        totalTaxCents += item.taxCents.toBigInt().toInt();

        // Non-tracked products never touch stock / batches / variant-stock
        // resolution and contribute zero to the inventory leg. Skip straight
        // to the next line; the financial leg of the journal entry is
        // recorded once after the loop. They also intentionally stay out of
        // `affectedProductIds` so the post-loop `syncProductStockFromVariants`
        // doesn't attempt to overwrite a stock value that is meaningless for
        // the product.
        if (!tracksInventory) {
          actualInvCostByItem[item.id] = 0;
          continue;
        }
        affectedProductIds.add(item.productId);

        // Resolve a concrete variant for the stock movement BEFORE any
        // stock-touching call so that StockService never throws its
        // "no default variant" StateError. Persist the resolved id back
        // to the line so the void path and reports stay truthful.
        final resolvedVariantId = await _resolveVariantIdForStock(
          productId: item.productId,
          variantId: item.variantId,
        );
        if (resolvedVariantId != item.variantId) {
          await (update(purchaseReturnAdjustmentItems)
                ..where((i) => i.id.equals(item.id)))
              .write(PurchaseReturnAdjustmentItemsCompanion(
            variantId: Value(resolvedVariantId),
          ));
        }

        // Guard against negative stock unless explicitly allowed by policy.
        if (!allowNegativeStock) {
          if (resolvedVariantId != null) {
            final variantRow = await customSelect(
              'SELECT stock_quantity FROM product_variants WHERE id = ?',
              variables: [Variable.withInt(resolvedVariantId)],
            ).getSingleOrNull();
            if (variantRow != null) {
              final currentStock = variantRow.read<int>('stock_quantity');
              if (currentStock < item.quantity) {
                throw StockInsufficientException(
                  variantId: resolvedVariantId,
                  productId: item.productId,
                  currentStock: currentStock,
                  requestedQuantity: item.quantity,
                );
              }
            }
          } else {
            final productRow = await customSelect(
              'SELECT stock_quantity FROM products WHERE id = ?',
              variables: [Variable.withInt(item.productId)],
            ).getSingleOrNull();
            if (productRow != null) {
              final currentStock = productRow.read<int>('stock_quantity');
              if (currentStock < item.quantity) {
                throw StockInsufficientException(
                  productId: item.productId,
                  currentStock: currentStock,
                  requestedQuantity: item.quantity,
                );
              }
            }
          }
        }

        // DECREASE stock (purchase return = goods leaving our warehouse)
        await StockService.adjustStock(
          this,
          productId: item.productId,
          variantId: resolvedVariantId,
          quantity: item.quantity,
          direction: StockDirection.decrease,
        );

        // Inventory cost = ACTUAL valuation removed (see `actualInvCostByItem`).
        if (await _isFifoProduct(item.productId)) {
          // FIFO: deduct oldest batches and link the consumption to this
          // return item so a later void can mirror it back precisely to the
          // same batches at the FROZEN unit cost. The returned rows carry
          // the per-batch cost, so Σ(totalCostCents) is the exact 1200 leg.
          final consumed = await BatchService.consumeFifo(
            this,
            productId: item.productId,
            variantId: resolvedVariantId,
            quantity: item.quantity,
            consumptionType: 'purchase_adj_return',
            purchaseReturnAdjustmentItemId: item.id,
          );
          final lineCost =
              consumed.fold<int>(0, (s, c) => s + c.totalCostCents);
          actualInvCostByItem[item.id] = lineCost;
          totalInventoryCostCents += lineCost;
          batchedProductIds.add(item.productId);
        } else {
          // WAC: the variant carries a single blended cost, so qty × the
          // frozen snapshot is already the exact valuation delta (an outflow
          // never changes the WAC unit cost).
          final lineCost =
              item.unitCostCents.toBigInt().toInt() * item.quantity;
          actualInvCostByItem[item.id] = lineCost;
          totalInventoryCostCents += lineCost;
        }
      }

      // Sync products table from variants
      for (final productId in affectedProductIds) {
        await StockService.syncProductStockFromVariants(this,
            productId: productId);
      }

      // I4 (Invariant I1): assert Σ(batch.remaining) == variant.stock_quantity
      // for every product whose batch ledger was touched. Catches any silent
      // desync between the batch ledger and the variant stock counter
      // BEFORE the transaction commits — turns Phase A's documented invariant
      // into an enforced one.
      for (final productId in batchedProductIds) {
        await BatchService.assertInvariantForProduct(this,
            productId: productId);
      }

      // Update status to posted (Phase 3: stamp postedBy / postedAt audit)
      await (update(purchaseReturnAdjustments)
            ..where((r) => r.id.equals(returnId)))
          .write(PurchaseReturnAdjustmentsCompanion(
        status: const Value('posted'),
        postedBy: Value(userId),
        postedAt: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
      ));

      // ── Supplier ledger ──
      // The JE policy routes the financial leg as follows:
      //   credit → Dr 2000 AP    (we owe the supplier less)
      //   cash   → Dr 1000 Cash  (supplier physically refunded us)
      //   cheque → Dr 1010 Bank  (supplier issued us a cheque)
      //
      // Only the `credit` path reduces what we owe the supplier (= AP).
      // Cash / cheque refunds settle physically and leave AP unchanged.
      // Inserting a `supplier_transactions` row with -refundCents AND
      // calling `adjustSupplierBalance` for non-credit refunds would
      // (a) double-count the refund against AP and (b) drift on every
      // `SupplierDao.recalculateBalance` rebuild (which sums
      // supplier_transactions.amount_cents back into suppliers.balance_cents).
      // So we gate BOTH writes on `refundMethod == 'credit'`, mirroring
      // the linked-return logic in `purchase_dao.postPurchaseReturn`.
      final refundCents = returnData.totalCents.toBigInt().toInt();
      final isCreditRefund = returnData.refundMethod == 'credit';
      if (isCreditRefund) {
        await into(supplierTransactions).insert(
          SupplierTransactionsCompanion.insert(
            supplierId: returnData.supplierId,
            transactionType: 'adjustment_return',
            amountCents: Decimal.fromInt(-refundCents),
            currencyId: returnData.currencyId,
            description: Value(
                'Purchase Adjustment Return ${returnData.returnNumber}'),
            referenceId: Value(returnId),
            referenceType: const Value('purchase_return_adjustment'),
          ),
        );

        // Reduce supplier balance (we owe them less)
        await BalanceService.adjustSupplierBalance(
          this,
          supplierId: returnData.supplierId,
          deltaCents: -refundCents,
        );
      }

      // ── Phase 2.1: snapshot-column back-fill ──
      // Freeze `tax_rate_bps_at_post` + `unit_cost_at_post_cents` on each
      // line so a later WAC drift / VAT rate change cannot retroactively
      // distort an already-posted return. Computed deterministically from
      // the already-frozen `unitCostCents`, `subtotalCents`, and
      // `taxCents` fields — no external sources, no scattered logic.
      for (final item in items) {
        // subtotal = unitPrice * qty − lineDiscount (pre-tax base).
        final unitPrice = item.unitPriceCents.toBigInt().toInt();
        final discount = item.discountCents.toBigInt().toInt();
        final subtotal = unitPrice * item.quantity - discount;
        final taxOnLine = item.taxCents.toBigInt().toInt();
        // Phase 7 — tax-rate snapshot recovery via SoT.
        final taxRateBps = TaxCalculationService.recoverRateBps(
          taxableSubtotalCents: subtotal,
          taxOnLineCents: taxOnLine,
        );
        await (update(purchaseReturnAdjustmentItems)
              ..where((i) => i.id.equals(item.id)))
            .write(PurchaseReturnAdjustmentItemsCompanion(
          taxRateBpsAtPost: Value(taxRateBps),
          unitCostAtPostCents:
              Value(Decimal.fromInt(item.unitCostCents.toBigInt().toInt())),
        ));
      }

      // ── Phase 2.2 + 2.5: build per-line PostedReturnLine list so the
      // policy can route each line to 1200 / 1290 by its disposition, and
      // pass the return date as posting date so the fiscal-period guard
      // inside ReturnPostingService can reject posts into closed periods.
      final explicitLines = <PostedReturnLine>[];
      for (final item in items) {
        // Use the ACTUAL inventory cost captured during the stock movement
        // (FIFO batch consumption / WAC snapshot) so the per-line 1200 leg
        // reconciles 1:1 with Σ(stock×cost). Falls back to 0 for any line
        // that never moved stock (non-tracked products).
        final lineInvCost = actualInvCostByItem[item.id] ?? 0;
        final lineTotal = item.totalCents.toBigInt().toInt();
        final lineTax = item.taxCents.toBigInt().toInt();
        explicitLines.add(PostedReturnLine(
          totalCents: lineTotal,
          taxCents: lineTax,
          inventoryCostCents: lineInvCost,
          disposition: ReturnDispositionX.fromWire(item.dispositionType),
          productId: item.productId,
          variantId: item.variantId,
          qty: item.quantity,
        ));
      }

      // Create journal entry (financial + tax + inventory) via the unified
      // pipeline. All Phase 2 invariants (fiscal period, credit notes,
      // disposition routing) are enforced centrally inside
      // `ReturnPostingService.post`; this call site only supplies data.
      await journalEntryService.recordPurchaseAdjustmentReturnJournalEntry(
        returnId: returnId,
        totalCents: refundCents,
        taxCents: totalTaxCents,
        inventoryCostCents: totalInventoryCostCents,
        currencyId: returnData.currencyId,
        refundMethod: returnData.refundMethod,
        userId: userId,
        postingDate: returnData.returnDate,
        explicitLines: explicitLines,
        approvalStatus: returnData.approvalStatus,
        approvalReason: returnData.approvalReason,
        supplierId: returnData.supplierId,
      );

      // ── Atomic counters: bump qty_returned_adjustment on FIFO-oldest
      //    purchase_items matching this (supplier, product, variant). The
      //    counter is the single source of truth for future cap checks
      //    regardless of which return path (linked or adjustment) consumes
      //    the line. We re-aggregate from `items` (not the request map
      //    above) so the actual posted quantity drives the increment.
      final bumpByLine = <String, int>{};
      for (final item in items) {
        final key = '${item.productId}:${item.variantId ?? 'null'}';
        bumpByLine[key] = (bumpByLine[key] ?? 0) + item.quantity;
      }
      for (final entry in bumpByLine.entries) {
        final parts = entry.key.split(':');
        final pid = int.parse(parts[0]);
        final vid = parts[1] == 'null' ? null : int.parse(parts[1]);
        final allocations = await _allocatePurchaseItemsForAdjustment(
          supplierId: returnData.supplierId,
          productId: pid,
          variantId: vid,
          requestedQty: entry.value,
        );
        for (final a in allocations) {
          await customStatement(
            'UPDATE purchase_items '
            'SET qty_returned_adjustment = qty_returned_adjustment + ? '
            'WHERE id = ?',
            [a.qty, a.purchaseItemId],
          );
        }
      }
    });
  }

  /// Atomically create AND post a purchase adjustment return in a single
  /// transaction. If the post step fails (e.g. insufficient stock), the
  /// entire transaction is rolled back — no orphaned draft record.
  ///
  /// The return number is generated **inside** the transaction to prevent
  /// race conditions (two concurrent submissions getting the same number).
  Future<int> createAndPostPurchaseAdjReturn(
    PurchaseReturnAdjustmentsCompanion returnData,
    List<PurchaseReturnAdjustmentItemsCompanion> items, {
    required JournalEntryService journalEntryService,
    int? userId,
    bool allowNegativeStock = false,
    bool allowOverHistory = false,
    ReturnApprovalService? approvalService,
  }) {
    return transaction(() async {
      // Generate number atomically inside the transaction
      final number = await generatePurchaseAdjReturnNumber();
      final dataWithNumber = returnData.copyWith(
        returnNumber: Value(number),
      );
      final returnId = await createPurchaseAdjReturn(
        dataWithNumber,
        items,
        approvalService: approvalService,
        overHistoryOverride: allowOverHistory,
      );
      await postPurchaseAdjReturn(
        returnId,
        journalEntryService: journalEntryService,
        userId: userId,
        allowNegativeStock: allowNegativeStock,
        allowOverHistory: allowOverHistory,
      );
      return returnId;
    });
  }

  /// Void a posted purchase adjustment return.
  /// Reverses stock, balance, and GL journal entries.
  Future<void> voidPurchaseAdjReturn(
    int returnId, {
    required JournalEntryService journalEntryService,
    int? voidedBy,
    String? voidReason,
  }) {
    return transaction(() async {
      final returnData = await getPurchaseAdjReturnById(returnId);
      if (returnData == null) throw Exception('Adjustment return not found');
      if (returnData.status == 'voided') {
        throw Exception('Adjustment return already voided');
      }

      if (returnData.status == 'posted') {
        final items = await getPurchaseAdjReturnItems(returnId);
        final affectedProductIds = <int>{};
        // I4: see post path — track which products had batch mutations so
        // the cross-table invariant is asserted only where it must hold.
        final batchedProductIds = <int>{};

        // Same track_inventory contract as the post path. Voiding only
        // touches stock for tracked products (non-tracked products had no
        // stock leg on post, so there is nothing to reverse).
        final trackedByProduct = await _trackInventoryByProduct(
          items.map((i) => i.productId).toSet(),
        );

        for (final item in items) {
          final tracksInventory = trackedByProduct[item.productId] ?? true;
          if (!tracksInventory) continue;
          affectedProductIds.add(item.productId);

          // Defensive variant resolution mirrors the post path so legacy
          // rows that were posted before this fix can still be voided.
          final resolvedVariantId = await _resolveVariantIdForStock(
            productId: item.productId,
            variantId: item.variantId,
          );

          // INCREASE stock back (reverse the decrease)
          await StockService.adjustStock(
            this,
            productId: item.productId,
            variantId: resolvedVariantId,
            quantity: item.quantity,
            direction: StockDirection.increase,
          );

          // FIFO restoration: mirror every 'out' consumption row this
          // return item produced back into its source batch at the
          // FROZEN unit_cost — preserves COGS truth across revaluations.
          // No-op for WAC products (no consumption rows were emitted).
          await BatchService.restoreConsumptions(
            this,
            reverseConsumptionType: 'purchase_adj_return_void',
            purchaseReturnAdjustmentItemId: item.id,
          );
          if (await _isFifoProduct(item.productId)) {
            batchedProductIds.add(item.productId);
          }
        }

        // Sync products table from variants
        for (final productId in affectedProductIds) {
          await StockService.syncProductStockFromVariants(this,
              productId: productId);
        }

        // I4 (Invariant I1): cross-table invariant for FIFO products.
        for (final productId in batchedProductIds) {
          await BatchService.assertInvariantForProduct(this,
              productId: productId);
        }

        // ── Supplier ledger reversal (mirrors forward-path gating) ──
        // The forward path only wrote to `supplier_transactions` /
        // `suppliers.balance_cents` when `refundMethod == 'credit'`.
        // Mirror the same gate here so the reversal exactly undoes
        // what the post did. Skipping this gate would re-introduce the
        // double-count for cash / cheque refunds (suppliers.balance
        // gains back amounts that were never deducted at post time).
        final refundCents = returnData.totalCents.toBigInt().toInt();
        final wasCreditRefund = returnData.refundMethod == 'credit';
        if (wasCreditRefund) {
          await into(supplierTransactions).insert(
            SupplierTransactionsCompanion.insert(
              supplierId: returnData.supplierId,
              transactionType: 'adjustment_return_reversal',
              amountCents: Decimal.fromInt(refundCents),
              currencyId: returnData.currencyId,
              description: Value(
                  'Voided Purchase Adjustment Return ${returnData.returnNumber}'),
              referenceId: Value(returnId),
              referenceType: const Value('purchase_return_adjustment'),
            ),
          );

          // Restore supplier balance
          await BalanceService.adjustSupplierBalance(
            this,
            supplierId: returnData.supplierId,
            deltaCents: refundCents,
          );
        }

        // Reverse GL journal entries
        await journalEntryService.voidJournalEntriesForSource(
          sourceTable: 'purchase_return_adjustments',
          sourceId: returnId,
          reason: 'Voided Purchase Adjustment Return ${returnData.returnNumber}',
        );

        // ── Atomic counters: reverse qty_returned_adjustment in the same
        //    FIFO order as the post path so the counters return to their
        //    pre-post state and another return can be created.
        final voidBumpByLine = <String, int>{};
        for (final item in items) {
          final key = '${item.productId}:${item.variantId ?? 'null'}';
          voidBumpByLine[key] = (voidBumpByLine[key] ?? 0) + item.quantity;
        }
        for (final entry in voidBumpByLine.entries) {
          final parts = entry.key.split(':');
          final pid = int.parse(parts[0]);
          final vid = parts[1] == 'null' ? null : int.parse(parts[1]);
          // Allocate against rows that currently carry adjustment counters,
          // newest-first (LIFO of the post path) — this gives an exact
          // inverse when no concurrent return raced in between.
          final variantClause =
              vid != null ? 'AND pi.variant_id = ${vid.toString()} ' : '';
          final rows = await customSelect(
            'SELECT pi.id AS item_id, pi.qty_returned_adjustment '
            'FROM purchase_items pi '
            'JOIN purchases pu ON pu.id = pi.purchase_id '
            "WHERE pu.status = 'posted' AND pu.supplier_id = ? "
            '  AND pi.product_id = ? '
            '$variantClause'
            '  AND pi.qty_returned_adjustment > 0 '
            'ORDER BY pu.purchase_date DESC, pi.id DESC',
            variables: [
              Variable.withInt(returnData.supplierId),
              Variable.withInt(pid),
            ],
          ).get();
          int remaining = entry.value;
          for (final r in rows) {
            if (remaining <= 0) break;
            final available = r.read<int>('qty_returned_adjustment');
            final take = remaining < available ? remaining : available;
            await customStatement(
              'UPDATE purchase_items '
              'SET qty_returned_adjustment = qty_returned_adjustment - ? '
              'WHERE id = ?',
              [take, r.read<int>('item_id')],
            );
            remaining -= take;
          }
          // If `remaining > 0` here, the counters are already at zero on
          // every candidate line — this means a concurrent operation drove
          // them down. We swallow silently rather than failing the void;
          // an alternative would be to allow the counter to go negative
          // but that breaks the invariant `0 <= counter <= quantity`.
        }
      }

      // Phase 3 — stamp voidedBy / voidedAt / voidReason audit columns.
      await (update(purchaseReturnAdjustments)
            ..where((r) => r.id.equals(returnId)))
          .write(PurchaseReturnAdjustmentsCompanion(
        status: const Value('voided'),
        voidedBy: Value(voidedBy),
        voidedAt: Value(DateTime.now()),
        voidReason: Value(voidReason),
        updatedAt: Value(DateTime.now()),
      ));
    });
  }

  /// Get items for a purchase adjustment return
  Future<List<PurchaseReturnAdjustmentItem>> getPurchaseAdjReturnItems(
      int returnId) {
    return (select(purchaseReturnAdjustmentItems)
          ..where((i) => i.returnId.equals(returnId)))
        .get();
  }

  /// Watch items with product details for a purchase adjustment return
  Stream<List<PurchaseAdjReturnItemWithDetails>>
      watchPurchaseAdjReturnItemsWithDetails(int returnId) {
    final query = select(purchaseReturnAdjustmentItems).join([
      innerJoin(products,
          products.id.equalsExp(purchaseReturnAdjustmentItems.productId)),
      leftOuterJoin(
          productVariants,
          productVariants.id
              .equalsExp(purchaseReturnAdjustmentItems.variantId)),
    ])
      ..where(purchaseReturnAdjustmentItems.returnId.equals(returnId));

    return query.watch().map((rows) => rows.map((row) {
          return PurchaseAdjReturnItemWithDetails(
            item: row.readTable(purchaseReturnAdjustmentItems),
            product: row.readTable(products),
            variant: row.readTableOrNull(productVariants),
          );
        }).toList());
  }

  /// Delete a draft purchase adjustment return
  Future<int> deletePurchaseAdjReturn(int returnId) {
    return transaction(() async {
      final returnData = await getPurchaseAdjReturnById(returnId);
      if (returnData == null || returnData.status != 'draft') {
        throw Exception('Cannot delete non-draft adjustment return');
      }
      return (delete(purchaseReturnAdjustments)
            ..where((r) => r.id.equals(returnId)))
          .go();
    });
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SALE ADJUSTMENT RETURNS
  // ══════════════════════════════════════════════════════════════════════════

  /// Watch all sale adjustment returns
  Stream<List<SaleReturnAdjustment>> watchAllSaleAdjustmentReturns() {
    return (select(saleReturnAdjustments)
          ..orderBy([(r) => OrderingTerm.desc(r.returnDate)]))
        .watch();
  }

  /// Watch sale adjustment returns by customer
  Stream<List<SaleReturnAdjustment>> watchSaleAdjReturnsByCustomer(
      int customerId) {
    return (select(saleReturnAdjustments)
          ..where((r) => r.customerId.equals(customerId))
          ..orderBy([(r) => OrderingTerm.desc(r.returnDate)]))
        .watch();
  }

  /// Get sale adjustment return by ID
  Future<SaleReturnAdjustment?> getSaleAdjReturnById(int id) {
    return (select(saleReturnAdjustments)..where((r) => r.id.equals(id)))
        .getSingleOrNull();
  }

  /// Generate next sale adjustment return number
  Future<String> generateSaleAdjReturnNumber() async {
    final now = DateTime.now();
    final prefix =
        'SAR-${now.year}${now.month.toString().padLeft(2, '0')}';

    final last = await (select(saleReturnAdjustments)
          ..where((r) => r.returnNumber.like('$prefix%'))
          ..orderBy([(r) => OrderingTerm.desc(r.returnNumber)])
          ..limit(1))
        .getSingleOrNull();

    int nextNum = 1;
    if (last != null) {
      final lastNum =
          int.tryParse(last.returnNumber.split('-').last) ?? 0;
      nextNum = lastNum + 1;
    }

    return '$prefix-${nextNum.toString().padLeft(4, '0')}';
  }

  /// Create sale adjustment return with items.
  /// Automatically fetches and freezes each product's current cost_cents
  /// into `unitCostCents` for perpetual inventory journal entries.
  Future<int> createSaleAdjReturn(
    SaleReturnAdjustmentsCompanion returnData,
    List<SaleReturnAdjustmentItemsCompanion> items, {
    ReturnApprovalService? approvalService,
    bool overHistoryOverride = false,
  }) {
    return transaction(() async {
      for (final item in items) {
        assert(item.quantity.value > 0, 'quantity must be > 0');
        assert(item.productId.present, 'productId is required');
      }

      final returnId =
          await into(saleReturnAdjustments).insert(returnData);

      // ── Phase 3: approval-policy evaluation at draft time ──
      // Same single source of truth as the purchase side.
      if (approvalService != null) {
        final totalCents = returnData.totalCents.present
            ? returnData.totalCents.value.toBigInt().toInt()
            : 0;
        final decision = await approvalService.evaluate(
          ReturnApprovalContext(
            totalCents: totalCents,
            linked: false,
            overHistoryOverride: overHistoryOverride,
            side: 'sale',
          ),
        );
        await (update(saleReturnAdjustments)
              ..where((r) => r.id.equals(returnId)))
            .write(SaleReturnAdjustmentsCompanion(
          approvalStatus: Value(decision.persistedStatus),
          approvalRequired: Value(decision.required),
          approvalReason: Value(decision.persistedReason),
          updatedAt: Value(DateTime.now()),
        ));
      }

      for (final item in items) {
        // Auto-fetch current cost from variant or product
        int costCents = 0;
        if (item.variantId.present && item.variantId.value != null) {
          final row = await customSelect(
            'SELECT cost_cents FROM product_variants WHERE id = ?',
            variables: [Variable.withInt(item.variantId.value!)],
          ).getSingleOrNull();
          costCents = row?.read<int>('cost_cents') ?? 0;
        } else {
          final row = await customSelect(
            'SELECT cost_cents FROM products WHERE id = ?',
            variables: [Variable.withInt(item.productId.value)],
          ).getSingleOrNull();
          costCents = row?.read<int>('cost_cents') ?? 0;
        }

        final itemWithCost = item.copyWith(
          returnId: Value(returnId),
          unitCostCents: Value(Decimal.fromInt(costCents)),
        );
        await into(saleReturnAdjustmentItems).insert(itemWithCost);
      }

      return returnId;
    });
  }

  /// Post sale adjustment return.
  ///
  /// BUSINESS LOGIC (Perpetual Inventory):
  /// 1. QUANTITY-CAP: refuse to return more units of (customer, product,
  ///    variant) than `Σ(invoiced) − Σ(already_returned linked + adj)`
  ///    unless [allowOverHistory] is explicitly set by a manager override.
  ///    Walk-in (`customerId == null`) cannot exceed history because there
  ///    is none — any positive request fails the cap.
  /// 2. CREDIT/CHEQUE GUARD: AR/Bank refunds require a real customer; we
  ///    refuse to create orphan ledgers with no party reference.
  /// 3. STOCK: increase via StockService (goods coming back to inventory).
  /// 4. BALANCE: reduce customer balance (they owe us less).
  /// 5. ATOMIC COUNTERS: bump `qty_returned_adjustment` on the FIFO-oldest
  ///    matching `sale_items` rows so the cap stays accurate for any
  ///    future return (linked or adjustment) of the same line.
  /// 6. JOURNAL: 4-way compound entry:
  ///    Financial: Dr Sales Return Adj (5700) | Cr AR (1100)
  ///    Inventory: Dr Inventory (1200) | Cr COGS (5300)
  Future<void> postSaleAdjReturn(
    int returnId, {
    required JournalEntryService journalEntryService,
    int? userId,
    bool allowOverHistory = false,
    CommissionService? commissionService,
    LoyaltyPointsService? loyaltyPointsService,
  }) {
    return transaction(() async {
      final returnData = await getSaleAdjReturnById(returnId);
      if (returnData == null) throw Exception('Adjustment return not found');
      if (returnData.status == 'posted') {
        throw Exception('Adjustment return already posted');
      }
      if (returnData.status == 'voided') {
        throw Exception('Cannot post a voided adjustment return');
      }

      // Defense-in-depth: AR/Bank refunds require a real customer — orphan
      // ledger entries make AR aging meaningless. The bloc already prevents
      // this in the UI; we re-assert here so any non-UI caller cannot
      // bypass it.
      if (returnData.refundMethod == 'credit' ||
          returnData.refundMethod == 'cheque') {
        if (returnData.customerId == null) {
          throw StateError(
            'Sale adjustment return #$returnId uses '
            "refund_method='${returnData.refundMethod}' but customerId is "
            'null (walk-in) — cannot post an orphan AR/Bank ledger entry. '
            'Use cash for walk-in refunds.',
          );
        }
      }

      final items = await getSaleAdjReturnItems(returnId);

      // ── Quantity-cap pre-check (atomic + per-line aggregated) ──
      // Walk-in cash refunds (customerId == null + refundMethod == 'cash')
      // are exempt because there is no history to cap against — this is
      // the standard POS pattern (a customer brings in goods without a
      // receipt and the cashier swaps them for cash, after manager
      // approval). For every other case the cap applies; over-history is
      // only permitted via the explicit `allowOverHistory` override which
      // must be passed by an authorised caller.
      final isWalkInCash = returnData.customerId == null &&
          returnData.refundMethod == 'cash';
      final effectiveAllowOver = allowOverHistory || isWalkInCash;
      final requestByLine = <String, int>{};
      for (final item in items) {
        final key = '${item.productId}:${item.variantId ?? 'null'}';
        requestByLine[key] = (requestByLine[key] ?? 0) + item.quantity;
      }
      for (final entry in requestByLine.entries) {
        final parts = entry.key.split(':');
        final pid = int.parse(parts[0]);
        final vid = parts[1] == 'null' ? null : int.parse(parts[1]);
        await validateAdjustmentQuantityCap(
          side: 'sale',
          partyId: returnData.customerId,
          productId: pid,
          variantId: vid,
          requestedQuantity: entry.value,
          allowOverHistory: effectiveAllowOver,
        );
      }
      final affectedProductIds = <int>{};
      // I4: see postPurchaseAdjReturn for the rationale.
      final batchedProductIds = <int>{};
      int totalInventoryCostCents = 0;
      int totalTaxCents = 0;

      // Per-product track_inventory map. See `postPurchaseAdjReturn` for the
      // full rationale — same gating contract: non-tracked products skip the
      // stock / batch / variant resolution legs but still hit the GL.
      final trackedByProduct = await _trackInventoryByProduct(
        items.map((i) => i.productId).toSet(),
      );

      for (final item in items) {
        final tracksInventory = trackedByProduct[item.productId] ?? true;

        // Aggregate tax for GL entry. Inventory cost is aggregated only for
        // tracked products (non-tracked items contribute zero to the
        // inventory leg of the compound journal entry).
        if (tracksInventory) {
          totalInventoryCostCents +=
              item.unitCostCents.toBigInt().toInt() * item.quantity;
        }
        totalTaxCents += item.taxCents.toBigInt().toInt();

        // Non-tracked products skip stock / batch / variant resolution. They
        // also stay out of `affectedProductIds` so the post-loop sync skips
        // them.
        if (!tracksInventory) continue;
        affectedProductIds.add(item.productId);

        // Resolve a concrete variant before any stock-touching call.
        // See `_resolveVariantIdForStock` for rationale.
        final resolvedVariantId = await _resolveVariantIdForStock(
          productId: item.productId,
          variantId: item.variantId,
        );
        if (resolvedVariantId != item.variantId) {
          await (update(saleReturnAdjustmentItems)
                ..where((i) => i.id.equals(item.id)))
              .write(SaleReturnAdjustmentItemsCompanion(
            variantId: Value(resolvedVariantId),
          ));
        }

        // INCREASE stock (sale return = goods coming back to our warehouse)
        await StockService.adjustStock(
          this,
          productId: item.productId,
          variantId: resolvedVariantId,
          quantity: item.quantity,
          direction: StockDirection.increase,
        );

        // FIFO sync: a sale-adjustment-return has no original invoice we can
        // restore against, so we materialise a new batch carrying the snapshot
        // unit cost stamped on the return item. `source = 'sale_return'`
        // distinguishes it from purchase batches in audit/expiry reports.
        // The batch is named after this return's `SAR-…` document number
        // (via [documentReference]) so it is traceable in the Batch Management
        // report and never confused with a LINKED `SR-…` return document.
        // WAC products keep their batches untouched (legacy path).
        if (await _isFifoProduct(item.productId)) {
          await BatchService.createOpeningBatch(
            this,
            productId: item.productId,
            variantId: resolvedVariantId,
            quantity: item.quantity,
            unitCostCents: item.unitCostCents.toBigInt().toInt(),
            source: 'sale_return',
            documentReference: returnData.returnNumber,
          );
          batchedProductIds.add(item.productId);
        }
      }

      // Sync products table from variants
      for (final productId in affectedProductIds) {
        await StockService.syncProductStockFromVariants(this,
            productId: productId);
      }

      // I4 (Invariant I1): cross-table invariant for FIFO products.
      for (final productId in batchedProductIds) {
        await BatchService.assertInvariantForProduct(this,
            productId: productId);
      }

      // Update status to posted (Phase 3: stamp postedBy / postedAt audit)
      await (update(saleReturnAdjustments)
            ..where((r) => r.id.equals(returnId)))
          .write(SaleReturnAdjustmentsCompanion(
        status: const Value('posted'),
        postedBy: Value(userId),
        postedAt: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
      ));

      // ── Customer ledger (mirror of the purchase-adjustment supplier path) ──
      // For a CREDIT ("رصيد") refund on an adjustment sale return the store
      // owes the customer less, so we reduce 1100 AR directly (symmetric with
      // a LINKED credit return in `sale_dao.postSaleReturn` and with the
      // supplier side of `postPurchaseAdjReturn`). We:
      //   1. Write an `adjustment_return` row to `customer_transactions`
      //      (amount = −refund) so it surfaces in the customer profile's
      //      transactions list, AND
      //   2. Reduce `customers.balance_cents` by the same amount.
      // Because `CustomerDao.recalculateBalance` rebuilds the balance from
      // SUM(customer_transactions.amount_cents), writing BOTH keeps the AR
      // sub-ledger reconciled with GL 1100 (the JE settlement leg credits
      // 1100 via `creditToReceivable`). The reconciliation invariant
      // Σ(customers.balance_cents) == GL(1100) therefore holds.
      //
      // CASH / CHEQUE refunds are intentionally NOT recorded here: the money
      // physically left the till/bank (Cr 1000/1010), never touching AR, so
      // touching `customers.balance_cents` would drift it from GL 1100. Those
      // refunds are audited via the `sale_return_adjustments` row + the JE.
      final refundCents = returnData.totalCents.toBigInt().toInt();
      final isCreditRefund = returnData.refundMethod == 'credit';
      if (isCreditRefund && returnData.customerId != null && refundCents > 0) {
        await into(customerTransactions).insert(
          CustomerTransactionsCompanion.insert(
            customerId: returnData.customerId!,
            transactionType: 'adjustment_return',
            amountCents: Decimal.fromInt(-refundCents),
            currencyId: returnData.currencyId,
            description:
                Value('Adjustment sale return ${returnData.returnNumber} (credit)'),
            referenceId: Value(returnId),
            referenceType: const Value('sale_return_adjustment'),
          ),
        );

        // Reduce customer balance (they owe us less).
        await BalanceService.adjustCustomerBalance(
          this,
          customerId: returnData.customerId!,
          deltaCents: -refundCents,
        );
      }

      // ── Phase 2.1: snapshot-column back-fill (sale adjustment side) ──
      // Freeze `tax_rate_bps_at_post` + `unit_cost_at_post_cents` per line.
      for (final item in items) {
        final unitPrice = item.unitPriceCents.toBigInt().toInt();
        final discount = item.discountCents.toBigInt().toInt();
        final subtotal = unitPrice * item.quantity - discount;
        final taxOnLine = item.taxCents.toBigInt().toInt();
        // Phase 7 — tax-rate snapshot recovery via SoT.
        final taxRateBps = TaxCalculationService.recoverRateBps(
          taxableSubtotalCents: subtotal,
          taxOnLineCents: taxOnLine,
        );
        await (update(saleReturnAdjustmentItems)
              ..where((i) => i.id.equals(item.id)))
            .write(SaleReturnAdjustmentItemsCompanion(
          taxRateBpsAtPost: Value(taxRateBps),
          unitCostAtPostCents:
              Value(Decimal.fromInt(item.unitCostCents.toBigInt().toInt())),
        ));
      }

      // ── Phase 2.2 + 2.5: per-line PostedReturnLine with disposition +
      // postingDate so the unified pipeline can route restock→1200,
      // damaged/scrap→5800 and assert the fiscal period is open.
      final explicitLines = <PostedReturnLine>[];
      for (final item in items) {
        final tracks = trackedByProduct[item.productId] ?? true;
        final lineInvCost = tracks
            ? item.unitCostCents.toBigInt().toInt() * item.quantity
            : 0;
        final lineTotal = item.totalCents.toBigInt().toInt();
        final lineTax = item.taxCents.toBigInt().toInt();
        explicitLines.add(PostedReturnLine(
          totalCents: lineTotal,
          taxCents: lineTax,
          inventoryCostCents: lineInvCost,
          disposition: ReturnDispositionX.fromWire(item.dispositionType),
          productId: item.productId,
          variantId: item.variantId,
          qty: item.quantity,
        ));
      }

      // Create journal entry (financial + tax + inventory) via the unified
      // pipeline. The Phase 2 centralized guards (fiscal period, credit
      // notes, disposition routing) all fire inside
      // `ReturnPostingService.post` — there is no per-caller logic here.
      //
      // `creditToReceivable` routes a CREDIT settlement to 1100 AR (mirroring
      // the `customers.balance_cents` reduction above) instead of issuing a
      // 2400 store-credit note — keeping the AR sub-ledger reconciled with GL.
      await journalEntryService.recordSaleAdjustmentReturnJournalEntry(
        returnId: returnId,
        totalCents: refundCents,
        taxCents: totalTaxCents,
        inventoryCostCents: totalInventoryCostCents,
        currencyId: returnData.currencyId,
        refundMethod: returnData.refundMethod,
        partyId: returnData.customerId,
        userId: userId,
        postingDate: returnData.returnDate,
        explicitLines: explicitLines,
        approvalStatus: returnData.approvalStatus,
        approvalReason: returnData.approvalReason,
        creditToReceivable: isCreditRefund,
      );

      // ── Atomic counters: bump qty_returned_adjustment on FIFO-oldest
      //    sale_items rows for this (customer, product, variant). Skipped
      //    for walk-in (no customer = no history to attribute to).
      if (returnData.customerId != null) {
        final bumpByLine = <String, int>{};
        for (final item in items) {
          final key = '${item.productId}:${item.variantId ?? 'null'}';
          bumpByLine[key] = (bumpByLine[key] ?? 0) + item.quantity;
        }
        for (final entry in bumpByLine.entries) {
          final parts = entry.key.split(':');
          final pid = int.parse(parts[0]);
          final vid = parts[1] == 'null' ? null : int.parse(parts[1]);
          final allocations = await _allocateSaleItemsForAdjustment(
            customerId: returnData.customerId!,
            productId: pid,
            variantId: vid,
            requestedQty: entry.value,
          );
          for (final a in allocations) {
            await customStatement(
              'UPDATE sale_items '
              'SET qty_returned_adjustment = qty_returned_adjustment + ? '
              'WHERE id = ?',
              [a.qty, a.saleItemId],
            );
          }
          // Note: when `allowOverHistory` was effective, fewer (or zero)
          // allocations may come back than the requested qty. That is the
          // intended behaviour — counters only advance up to the available
          // history; the residual is the over-history portion that the
          // override permitted. Walk-in returns leave counters untouched.
        }
      }

      // ── Commission reversal (Phase 6 SoT) ──
      // An adjustment return attributed to a salesperson must DEDUCT their
      // commission, symmetrically with a linked return. Because the return
      // is unlinked there is no original commission to prorate against, so
      // `CommissionService.reverseForAdjustmentReturn` computes a fresh
      // deduction from the return's own net (subtotal − discount) × the
      // employee's current rate. Keyed by `returnId` so a void deletes it
      // exactly. No-op when no employee is attributed. Runs inside this
      // transaction (shared AppDatabase) so it is atomic with the post.
      if (commissionService != null && returnData.employeeId != null) {
        final commissionItemCount =
            items.fold<int>(0, (sum, i) => sum + i.quantity);
        await commissionService.reverseForAdjustmentReturn(
          adjustmentReturnId: returnId,
          employeeId: returnData.employeeId!,
          returnSubtotalCents: returnData.subtotalCents.toBigInt().toInt(),
          returnDiscountCents: returnData.discountCents.toBigInt().toInt(),
          itemCount: commissionItemCount,
          currencyId: returnData.currencyId,
          returnDate: returnData.returnDate,
        );
      }

      // ── Loyalty-points reversal ──
      // When a customer is attributed, returning goods must DEDUCT the
      // loyalty points that the equivalent spend would have earned — the
      // same rule the user expects ("طالما انا مختار العميل"). Because the
      // return is unlinked there is no original sale to prorate against, so
      // `LoyaltyPointsService.reverseForAdjustmentReturn` recomputes the
      // deduction from the return's own total using the live settings +
      // the customer's tier multiplier, capped at their current balance.
      // Never throws (loyalty is non-critical) so it cannot roll back the
      // accounting post.
      if (loyaltyPointsService != null && returnData.customerId != null) {
        await loyaltyPointsService.reverseForAdjustmentReturn(
          customerId: returnData.customerId!,
          adjustmentReturnId: returnId,
          returnTotalCents: returnData.totalCents.toBigInt().toInt(),
          returnDate: returnData.returnDate,
        );
      }
    });
  }

  /// Atomically create AND post a sale adjustment return in a single
  /// transaction. If the post step fails, the entire transaction is
  /// rolled back — no orphaned draft record.
  ///
  /// The return number is generated **inside** the transaction to prevent
  /// race conditions (two concurrent submissions getting the same number).
  Future<int> createAndPostSaleAdjReturn(
    SaleReturnAdjustmentsCompanion returnData,
    List<SaleReturnAdjustmentItemsCompanion> items, {
    required JournalEntryService journalEntryService,
    int? userId,
    bool allowOverHistory = false,
    ReturnApprovalService? approvalService,
    CommissionService? commissionService,
    LoyaltyPointsService? loyaltyPointsService,
  }) {
    return transaction(() async {
      // Generate number atomically inside the transaction
      final number = await generateSaleAdjReturnNumber();
      final dataWithNumber = returnData.copyWith(
        returnNumber: Value(number),
      );
      final returnId = await createSaleAdjReturn(
        dataWithNumber,
        items,
        approvalService: approvalService,
        overHistoryOverride: allowOverHistory,
      );
      await postSaleAdjReturn(
        returnId,
        journalEntryService: journalEntryService,
        userId: userId,
        allowOverHistory: allowOverHistory,
        commissionService: commissionService,
        loyaltyPointsService: loyaltyPointsService,
      );
      return returnId;
    });
  }

  /// Void a posted sale adjustment return.
  /// Reverses stock, balance, and GL journal entries.
  ///
  /// Voiding DECREASES stock (reverses the restoration done on post).
  /// If [allowNegativeStock] is false and current stock is insufficient,
  /// the operation is rejected — matching SAP / NetSuite / Odoo / QuickBooks.
  Future<void> voidSaleAdjReturn(
    int returnId, {
    required JournalEntryService journalEntryService,
    bool allowNegativeStock = false,
    int? voidedBy,
    String? voidReason,
    CommissionService? commissionService,
    LoyaltyPointsService? loyaltyPointsService,
  }) {
    return transaction(() async {
      final returnData = await getSaleAdjReturnById(returnId);
      if (returnData == null) throw Exception('Adjustment return not found');
      if (returnData.status == 'voided') {
        throw Exception('Adjustment return already voided');
      }

      if (returnData.status == 'posted') {
        final items = await getSaleAdjReturnItems(returnId);
        final affectedProductIds = <int>{};
        // I4: see post path.
        final batchedProductIds = <int>{};

        // Same track_inventory contract as the post path. Non-tracked
        // products had no stock leg on post, so the void has nothing to
        // reverse for them.
        final trackedByProduct = await _trackInventoryByProduct(
          items.map((i) => i.productId).toSet(),
        );

        for (final item in items) {
          final tracksInventory = trackedByProduct[item.productId] ?? true;
          if (!tracksInventory) continue;
          affectedProductIds.add(item.productId);

          // Defensive variant resolution mirrors the post path so legacy
          // rows that were posted before this fix can still be voided.
          final resolvedVariantId = await _resolveVariantIdForStock(
            productId: item.productId,
            variantId: item.variantId,
          );

          // Guard against negative stock unless explicitly allowed by policy.
          if (!allowNegativeStock) {
            if (resolvedVariantId != null) {
              final variantRow = await customSelect(
                'SELECT stock_quantity FROM product_variants WHERE id = ?',
                variables: [Variable.withInt(resolvedVariantId)],
              ).getSingleOrNull();
              if (variantRow != null) {
                final currentStock = variantRow.read<int>('stock_quantity');
                if (currentStock < item.quantity) {
                  throw Exception(
                    'Cannot void: variant #$resolvedVariantId stock ($currentStock) '
                    'is less than return quantity (${item.quantity}). '
                    'Some items may have been sold.',
                  );
                }
              }
            } else {
              final productRow = await customSelect(
                'SELECT stock_quantity FROM products WHERE id = ?',
                variables: [Variable.withInt(item.productId)],
              ).getSingleOrNull();
              if (productRow != null) {
                final currentStock = productRow.read<int>('stock_quantity');
                if (currentStock < item.quantity) {
                  throw Exception(
                    'Cannot void: product #${item.productId} stock ($currentStock) '
                    'is less than return quantity (${item.quantity}). '
                    'Some items may have been sold.',
                  );
                }
              }
            }
          }

          // DECREASE stock (reverse the increase)
          await StockService.adjustStock(
            this,
            productId: item.productId,
            variantId: resolvedVariantId,
            quantity: item.quantity,
            direction: StockDirection.decrease,
          );

          // FIFO sync: deduct oldest batches in FIFO order, linked to this
          // return item so the consumption can be audited / replayed. The
          // batch we created on posting (source='sale_return') is amongst
          // the candidates; whether it is consumed first depends on its
          // received_date relative to other lots, which is the correct
          // FIFO behaviour. WAC products keep their batches untouched.
          if (await _isFifoProduct(item.productId)) {
            await BatchService.consumeFifo(
              this,
              productId: item.productId,
              variantId: resolvedVariantId,
              quantity: item.quantity,
              consumptionType: 'sale_adj_return_void',
              saleReturnAdjustmentItemId: item.id,
            );
            batchedProductIds.add(item.productId);
          }
        }

        // Sync products table from variants
        for (final productId in affectedProductIds) {
          await StockService.syncProductStockFromVariants(this,
              productId: productId);
        }

        // I4 (Invariant I1): cross-table invariant for FIFO products.
        for (final productId in batchedProductIds) {
          await BatchService.assertInvariantForProduct(this,
              productId: productId);
        }

        // ── Customer ledger reversal ──
        // The forward path (`postSaleAdjReturn`) writes an
        // `adjustment_return` row to `customer_transactions` and REDUCES
        // `customers.balance_cents` by the refund when the refund method
        // is `credit` (the customer owes us less). Voiding must undo both,
        // symmetric with the supplier side of `voidPurchaseAdjReturn` and
        // with a linked-return void in `sale_dao`. Cash/bank refunds never
        // touched the customer sub-ledger, so nothing is reversed for them.
        final voidRefundCents = returnData.totalCents.toBigInt().toInt();
        final wasCreditRefund = returnData.refundMethod == 'credit';
        if (wasCreditRefund &&
            returnData.customerId != null &&
            voidRefundCents > 0) {
          await into(customerTransactions).insert(
            CustomerTransactionsCompanion.insert(
              customerId: returnData.customerId!,
              transactionType: 'adjustment_return_reversal',
              amountCents: Decimal.fromInt(voidRefundCents),
              currencyId: returnData.currencyId,
              description: Value(
                'Void adjustment return ${returnData.returnNumber} (credit)',
              ),
              referenceType: const Value('sale_return_adjustment'),
              referenceId: Value(returnId),
            ),
          );

          // Restore customer balance (they owe us the amount again).
          await BalanceService.adjustCustomerBalance(
            this,
            customerId: returnData.customerId!,
            deltaCents: voidRefundCents,
          );
        }

        // Reverse GL journal entries
        await journalEntryService.voidJournalEntriesForSource(
          sourceTable: 'sale_return_adjustments',
          sourceId: returnId,
          reason: 'Voided Sale Adjustment Return ${returnData.returnNumber}',
        );

        // ── Atomic counters: reverse qty_returned_adjustment newest-first.
        //    Skipped for walk-in (no customer = no counter to reverse).
        if (returnData.customerId != null) {
          final voidBumpByLine = <String, int>{};
          for (final item in items) {
            final key = '${item.productId}:${item.variantId ?? 'null'}';
            voidBumpByLine[key] = (voidBumpByLine[key] ?? 0) + item.quantity;
          }
          for (final entry in voidBumpByLine.entries) {
            final parts = entry.key.split(':');
            final pid = int.parse(parts[0]);
            final vid = parts[1] == 'null' ? null : int.parse(parts[1]);
            final variantClause =
                vid != null ? 'AND si.variant_id = ${vid.toString()} ' : '';
            final rows = await customSelect(
              'SELECT si.id AS item_id, si.qty_returned_adjustment '
              'FROM sale_items si '
              'JOIN sales s ON s.id = si.sale_id '
              "WHERE s.status = 'completed' AND s.customer_id = ? "
              '  AND si.product_id = ? '
              '$variantClause'
              '  AND si.qty_returned_adjustment > 0 '
              'ORDER BY s.sale_date DESC, si.id DESC',
              variables: [
                Variable.withInt(returnData.customerId!),
                Variable.withInt(pid),
              ],
            ).get();
            int remaining = entry.value;
            for (final r in rows) {
              if (remaining <= 0) break;
              final available = r.read<int>('qty_returned_adjustment');
              final take = remaining < available ? remaining : available;
              await customStatement(
                'UPDATE sale_items '
                'SET qty_returned_adjustment = qty_returned_adjustment - ? '
                'WHERE id = ?',
                [take, r.read<int>('item_id')],
              );
              remaining -= take;
            }
          }
        }

        // ── Commission reversal cleanup ──
        // Delete the negative commission row(s) this adjustment return
        // created on post (keyed by returnId). Deleting — rather than
        // re-posting an offsetting positive — is exact and rate-change
        // safe. No-op when none exist (return had no attributed employee).
        if (commissionService != null) {
          await commissionService.deleteForAdjustmentReturn(returnId);
        }

        // ── Loyalty-points restore ──
        // Re-credit the points that the post path deducted for this
        // return (keyed by returnId). Reads back the exact deducted
        // amount from the ledger, so a partial-cap deduction is restored
        // exactly. No-op when no customer / no deduction row. Never throws.
        if (loyaltyPointsService != null && returnData.customerId != null) {
          await loyaltyPointsService.restoreForAdjustmentReturnVoid(
            customerId: returnData.customerId!,
            adjustmentReturnId: returnId,
          );
        }
      }

      // Phase 3 — stamp voidedBy / voidedAt / voidReason audit columns.
      await (update(saleReturnAdjustments)
            ..where((r) => r.id.equals(returnId)))
          .write(SaleReturnAdjustmentsCompanion(
        status: const Value('voided'),
        voidedBy: Value(voidedBy),
        voidedAt: Value(DateTime.now()),
        voidReason: Value(voidReason),
        updatedAt: Value(DateTime.now()),
      ));
    });
  }

  /// Get items for a sale adjustment return
  Future<List<SaleReturnAdjustmentItem>> getSaleAdjReturnItems(int returnId) {
    return (select(saleReturnAdjustmentItems)
          ..where((i) => i.returnId.equals(returnId)))
        .get();
  }

  /// Watch items with product details for a sale adjustment return
  Stream<List<SaleAdjReturnItemWithDetails>>
      watchSaleAdjReturnItemsWithDetails(int returnId) {
    final query = select(saleReturnAdjustmentItems).join([
      innerJoin(products,
          products.id.equalsExp(saleReturnAdjustmentItems.productId)),
      leftOuterJoin(
          productVariants,
          productVariants.id
              .equalsExp(saleReturnAdjustmentItems.variantId)),
    ])
      ..where(saleReturnAdjustmentItems.returnId.equals(returnId));

    return query.watch().map((rows) => rows.map((row) {
          return SaleAdjReturnItemWithDetails(
            item: row.readTable(saleReturnAdjustmentItems),
            product: row.readTable(products),
            variant: row.readTableOrNull(productVariants),
          );
        }).toList());
  }

  /// Delete a draft sale adjustment return
  Future<int> deleteSaleAdjReturn(int returnId) {
    return transaction(() async {
      final returnData = await getSaleAdjReturnById(returnId);
      if (returnData == null || returnData.status != 'draft') {
        throw Exception('Cannot delete non-draft adjustment return');
      }
      return (delete(saleReturnAdjustments)
            ..where((r) => r.id.equals(returnId)))
          .go();
    });
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SEARCH SUPPORT METHODS
  // ══════════════════════════════════════════════════════════════════════════

  /// Watch all purchase adjustment returns with supplier info
  Stream<List<PurchaseAdjReturnWithParty>> watchAllPurchaseAdjReturnsWithParty() {
    final query = select(purchaseReturnAdjustments).join([
      innerJoin(suppliers,
          suppliers.id.equalsExp(purchaseReturnAdjustments.supplierId)),
    ])
      ..orderBy([OrderingTerm.desc(purchaseReturnAdjustments.returnDate)]);

    return query.watch().map((rows) => rows.map((row) {
          return PurchaseAdjReturnWithParty(
            adjustment: row.readTable(purchaseReturnAdjustments),
            supplierName: row.readTable(suppliers).name,
            supplierPhone: row.readTable(suppliers).phone,
          );
        }).toList());
  }

  /// Watch all sale adjustment returns with customer info
  Stream<List<SaleAdjReturnWithParty>> watchAllSaleAdjReturnsWithParty() {
    final query = select(saleReturnAdjustments).join([
      leftOuterJoin(customers,
          customers.id.equalsExp(saleReturnAdjustments.customerId)),
    ])
      ..orderBy([OrderingTerm.desc(saleReturnAdjustments.returnDate)]);

    return query.watch().map((rows) => rows.map((row) {
          return SaleAdjReturnWithParty(
            adjustment: row.readTable(saleReturnAdjustments),
            customerName: row.readTableOrNull(customers)?.name,
            customerPhone: row.readTableOrNull(customers)?.phone,
          );
        }).toList());
  }

  /// Watch product search terms for purchase adjustment return items
  Stream<Map<String, List<String>>> watchPurchaseAdjReturnProductSearchTerms() {
    final query = select(purchaseReturnAdjustmentItems).join([
      innerJoin(products,
          products.id.equalsExp(purchaseReturnAdjustmentItems.productId)),
      leftOuterJoin(productVariants,
          productVariants.id.equalsExp(purchaseReturnAdjustmentItems.variantId)),
    ]);

    return query.watch().map((rows) {
      final map = <String, List<String>>{};
      for (final row in rows) {
        final item = row.readTable(purchaseReturnAdjustmentItems);
        final product = row.readTable(products);
        final variant = row.readTableOrNull(productVariants);
        final key = 'PRA-${item.returnId}';
        final terms = <String>[];
        terms.add(product.name);
        if (product.nameAr != null) terms.add(product.nameAr!);
        if (product.nameFr != null) terms.add(product.nameFr!);
        if (product.barcode != null) terms.add(product.barcode!);
        if (product.sku != null) terms.add(product.sku!);
        if (variant?.barcode != null) terms.add(variant!.barcode!);
        if (variant?.sku != null) terms.add(variant!.sku!);
        map.putIfAbsent(key, () => []).addAll(terms);
      }
      return map;
    });
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PHASE 3 — APPROVAL TRANSITIONS
  // ══════════════════════════════════════════════════════════════════════════
  //
  // Single chokepoint for moving a `pending` return to `approved` /
  // `rejected`. Status transitions are guarded so the UI cannot create
  // illegal flows (e.g. approving a posted return, or re-approving an
  // auto_approved one).

  Future<void> approvePurchaseAdjReturn(
    int returnId, {
    required int approvedBy,
  }) async {
    final row = await getPurchaseAdjReturnById(returnId);
    if (row == null) {
      throw const ReturnApprovalStateException('Return not found');
    }
    if (row.approvalStatus != ApprovalStatus.pending) {
      throw ReturnApprovalStateException(
        'Cannot approve a return whose approval_status is '
        "'${row.approvalStatus}' (must be '${ApprovalStatus.pending}').",
      );
    }
    await (update(purchaseReturnAdjustments)
          ..where((r) => r.id.equals(returnId)))
        .write(PurchaseReturnAdjustmentsCompanion(
      approvalStatus: const Value(ApprovalStatus.approved),
      approvedBy: Value(approvedBy),
      approvedAt: Value(DateTime.now()),
      updatedAt: Value(DateTime.now()),
    ));
  }

  Future<void> rejectPurchaseAdjReturn(
    int returnId, {
    required int approvedBy,
  }) async {
    final row = await getPurchaseAdjReturnById(returnId);
    if (row == null) {
      throw const ReturnApprovalStateException('Return not found');
    }
    if (row.approvalStatus != ApprovalStatus.pending) {
      throw ReturnApprovalStateException(
        'Cannot reject a return whose approval_status is '
        "'${row.approvalStatus}'.",
      );
    }
    await (update(purchaseReturnAdjustments)
          ..where((r) => r.id.equals(returnId)))
        .write(PurchaseReturnAdjustmentsCompanion(
      approvalStatus: const Value(ApprovalStatus.rejected),
      approvedBy: Value(approvedBy),
      approvedAt: Value(DateTime.now()),
      updatedAt: Value(DateTime.now()),
    ));
  }

  Future<void> approveSaleAdjReturn(
    int returnId, {
    required int approvedBy,
  }) async {
    final row = await getSaleAdjReturnById(returnId);
    if (row == null) {
      throw const ReturnApprovalStateException('Return not found');
    }
    if (row.approvalStatus != ApprovalStatus.pending) {
      throw ReturnApprovalStateException(
        'Cannot approve a return whose approval_status is '
        "'${row.approvalStatus}' (must be '${ApprovalStatus.pending}').",
      );
    }
    await (update(saleReturnAdjustments)
          ..where((r) => r.id.equals(returnId)))
        .write(SaleReturnAdjustmentsCompanion(
      approvalStatus: const Value(ApprovalStatus.approved),
      approvedBy: Value(approvedBy),
      approvedAt: Value(DateTime.now()),
      updatedAt: Value(DateTime.now()),
    ));
  }

  Future<void> rejectSaleAdjReturn(
    int returnId, {
    required int approvedBy,
  }) async {
    final row = await getSaleAdjReturnById(returnId);
    if (row == null) {
      throw const ReturnApprovalStateException('Return not found');
    }
    if (row.approvalStatus != ApprovalStatus.pending) {
      throw ReturnApprovalStateException(
        'Cannot reject a return whose approval_status is '
        "'${row.approvalStatus}'.",
      );
    }
    await (update(saleReturnAdjustments)
          ..where((r) => r.id.equals(returnId)))
        .write(SaleReturnAdjustmentsCompanion(
      approvalStatus: const Value(ApprovalStatus.rejected),
      approvedBy: Value(approvedBy),
      approvedAt: Value(DateTime.now()),
      updatedAt: Value(DateTime.now()),
    ));
  }

  /// Watch product search terms for sale adjustment return items
  Stream<Map<String, List<String>>> watchSaleAdjReturnProductSearchTerms() {
    final query = select(saleReturnAdjustmentItems).join([
      innerJoin(products,
          products.id.equalsExp(saleReturnAdjustmentItems.productId)),
      leftOuterJoin(productVariants,
          productVariants.id.equalsExp(saleReturnAdjustmentItems.variantId)),
    ]);

    return query.watch().map((rows) {
      final map = <String, List<String>>{};
      for (final row in rows) {
        final item = row.readTable(saleReturnAdjustmentItems);
        final product = row.readTable(products);
        final variant = row.readTableOrNull(productVariants);
        final key = 'SRA-${item.returnId}';
        final terms = <String>[];
        terms.add(product.name);
        if (product.nameAr != null) terms.add(product.nameAr!);
        if (product.nameFr != null) terms.add(product.nameFr!);
        if (product.barcode != null) terms.add(product.barcode!);
        if (product.sku != null) terms.add(product.sku!);
        if (variant?.barcode != null) terms.add(variant!.barcode!);
        if (variant?.sku != null) terms.add(variant!.sku!);
        map.putIfAbsent(key, () => []).addAll(terms);
      }
      return map;
    });
  }
}
