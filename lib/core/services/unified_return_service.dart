// ══════════════════════════════════════════════════════════════════════════════
// UNIFIED RETURN SERVICE
// ══════════════════════════════════════════════════════════════════════════════
//
// Core business logic for the unified return flow. The user never chooses
// the return type — this service decides automatically per line item:
//   • Linked (invoice-based) — price matches exactly, quantity available
//   • Adjustment (unlinked) — price mismatch, no invoice history, or overflow
//
// Hybrid splitting of the SAME item's quantity across types is forbidden.
// Overflow scenario: all linkable qty goes to linked, remainder to adjustment.
// ══════════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
import 'business/warehouse_stock_scope.dart';
import 'business/branch_tax_policy.dart';
import 'business/branch_tax_policy_store.dart';
import 'business/document_posting_scope.dart';
import 'business/warehouse_document_scope.dart';
import '../measurement/measurement.dart';
import '../database/daos/purchase_dao.dart';
import '../database/daos/sale_dao.dart';
import '../database/daos/adjustment_return_dao.dart';
import '../pricing/pricing_snapshot.dart';
import '../pricing/invoice_pricing_engine.dart';
import '../pricing/line_item_pricing_engine.dart';
import '../money/money.dart';
import '../../features/settings/data/services/app_settings_service.dart';
import '../../features/settings/domain/entities/app_settings.dart';
import 'journal_entry_service.dart';
import 'commissions/commission_service.dart';
import 'loyalty/loyalty_points_service.dart';
import 'return_calculation_service.dart';
import 'cashier_shift_service.dart';
import '../../features/auth/data/services/session_service.dart';

// ─── Enums & Data Classes ────────────────────────────────────────────────────

/// Why the system chose a particular return mode for an item.
enum ReturnModeReason {
  /// Price matches an invoice line exactly and qty is available.
  priceMatch,

  /// User edited the price — no longer matches any invoice line.
  priceMismatch,

  /// Product was never purchased/sold on any invoice for this party.
  noInvoiceHistory,

  /// Requested qty exceeds what's returnable on invoices; overflow portion.
  quantityOverflow,
}

/// The resolved mode for a single line item.
enum ReturnMode { linked, adjustment }

/// Whether this is a sale-side or purchase-side return.
enum ReturnSide { sale, purchase }

/// Internal preview, bound to its database, side, inputs and tax policy.
/// This is not an authorization token or a serialized LAN contract.
class UnifiedAdjustmentQuote {
  const UnifiedAdjustmentQuote._(
    this._database,
    this._side,
    this._fingerprint,
    this._policy,
    this._legacyPolicy,
    this.pricing,
    this.taxInclusive,
  );
  final AppDatabase _database;
  final ReturnSide _side;
  final String _fingerprint;
  final BranchTaxPolicySnapshot? _policy;
  final BranchTaxPolicy _legacyPolicy;
  final InvoicePricingResult pricing;
  final bool taxInclusive;
}

/// A single line item in the unified return form.
class UnifiedReturnLineItem {
  final int productId;
  final int? variantId;
  final String productName;
  final String? variantLabel;
  final int quantity;
  final int quantityScale;
  final String measurementType;
  final int unitPriceCents;
  final String? reason;

  /// Resolved by the service — not set by the user.
  final ReturnMode mode;
  final ReturnModeReason modeReason;

  /// If linked, which invoice items are consumed (FIFO order).
  /// Each entry: (invoiceItemId, quantity consumed from that item).
  final List<InvoiceItemAllocation> linkedAllocations;

  const UnifiedReturnLineItem({
    required this.productId,
    this.variantId,
    required this.productName,
    this.variantLabel,
    required this.quantity,
    this.quantityScale = 1,
    this.measurementType = 'piece',
    required this.unitPriceCents,
    this.reason,
    required this.mode,
    required this.modeReason,
    this.linkedAllocations = const [],
  });

  UnifiedReturnLineItem copyWith({
    int? quantity,
    int? unitPriceCents,
    String? reason,
    ReturnMode? mode,
    ReturnModeReason? modeReason,
    List<InvoiceItemAllocation>? linkedAllocations,
  }) {
    return UnifiedReturnLineItem(
      productId: productId,
      variantId: variantId,
      productName: productName,
      variantLabel: variantLabel,
      quantity: quantity ?? this.quantity,
      quantityScale: quantityScale,
      measurementType: measurementType,
      unitPriceCents: unitPriceCents ?? this.unitPriceCents,
      reason: reason ?? this.reason,
      mode: mode ?? this.mode,
      modeReason: modeReason ?? this.modeReason,
      linkedAllocations: linkedAllocations ?? this.linkedAllocations,
    );
  }

  int get totalCents => MeasuredAmount.cents(
    unitCents: unitPriceCents,
    quantity: quantity,
    quantityScale: quantityScale,
  );

  bool get isAdjustment => mode == ReturnMode.adjustment;
}

/// Allocation of return quantity against a specific invoice item.
class InvoiceItemAllocation {
  /// The invoice item ID (sale_item.id or purchase_item.id).
  final int invoiceItemId;

  /// The invoice ID (sale.id or purchase.id).
  final int invoiceId;

  /// How many units are consumed from this invoice item.
  final int quantity;
  final int quantityScale;
  final String measurementType;

  /// Original unit price on the invoice item (cents).
  final int unitPriceCents;

  /// Original item fields needed for proportional return calculation.
  final int originalQuantity;
  final int originalSubtotalCents;
  final int originalDiscountCents;
  final int originalTaxCents;
  final LinkedReturnHistory previousLinkedHistory;
  final bool taxInclusivePricing;

  const InvoiceItemAllocation({
    required this.invoiceItemId,
    required this.invoiceId,
    required this.quantity,
    this.quantityScale = 1,
    this.measurementType = 'piece',
    required this.unitPriceCents,
    required this.originalQuantity,
    required this.originalSubtotalCents,
    required this.originalDiscountCents,
    required this.originalTaxCents,
    this.previousLinkedHistory = LinkedReturnHistory.zero,
    this.taxInclusivePricing = false,
  });
}

/// An invoice candidate found during search (for display in search results).
class InvoiceSearchResult {
  final int invoiceId;
  final String invoiceNumber;
  final DateTime date;
  final int totalCents;
  final int? partyId;
  final String? partyName;

  const InvoiceSearchResult({
    required this.invoiceId,
    required this.invoiceNumber,
    required this.date,
    required this.totalCents,
    this.partyId,
    this.partyName,
  });
}

/// A product candidate found during search.
class ProductSearchResult {
  final int productId;
  final int? variantId;
  final String productName;
  final String? variantLabel;
  final String? sku;
  final String? barcode;

  /// Last known price from invoice history (or current product price).
  final int lastPriceCents;

  /// Tax rate in basis points (e.g. 1000 = 10%).
  final int taxRateBps;

  /// On-hand stock for this product or variant. Used purely for display in
  /// the search result tile so the user knows how much is available before
  /// creating an unlinked (adjustment) return.
  final int stockQuantity;
  final String measurementType;

  const ProductSearchResult({
    required this.productId,
    this.variantId,
    required this.productName,
    this.variantLabel,
    this.sku,
    this.barcode,
    required this.lastPriceCents,
    this.taxRateBps = 0,
    this.stockQuantity = 0,
    this.measurementType = 'piece',
  });
}

/// Invoice item available for return linking (with remaining returnable qty).
class ReturnableInvoiceItem {
  final int invoiceItemId;
  final int invoiceId;
  final String invoiceNumber;
  final DateTime invoiceDate;
  final int productId;
  final int? variantId;
  final int originalQuantity;
  final int quantityScale;
  final String measurementType;
  final int alreadyReturnedQuantity;
  final int unitPriceCents;
  final int originalSubtotalCents;
  final int originalDiscountCents;
  final int originalTaxCents;
  final LinkedReturnHistory linkedReturnHistory;
  final bool taxInclusivePricing;

  int get remainingQuantity => originalQuantity - alreadyReturnedQuantity;

  const ReturnableInvoiceItem({
    required this.invoiceItemId,
    required this.invoiceId,
    required this.invoiceNumber,
    required this.invoiceDate,
    required this.productId,
    this.variantId,
    required this.originalQuantity,
    this.quantityScale = 1,
    this.measurementType = 'piece',
    required this.alreadyReturnedQuantity,
    required this.unitPriceCents,
    required this.originalSubtotalCents,
    required this.originalDiscountCents,
    required this.originalTaxCents,
    this.linkedReturnHistory = LinkedReturnHistory.zero,
    this.taxInclusivePricing = false,
  });
}

// ─── Service ─────────────────────────────────────────────────────────────────

class UnifiedReturnService {
  final AppDatabase _db;
  final PurchaseDao _purchaseDao;
  final SaleDao _saleDao;
  final AdjustmentReturnDao _adjDao;
  final JournalEntryService _journalService;
  final CommissionService _commissionService;
  final LoyaltyPointsService _loyaltyPointsService;
  final SessionService? _sessionService;
  final CashierShiftService? _cashierShiftService;
  final AppSettingsService? _settings;

  UnifiedReturnService(
    this._db,
    this._purchaseDao,
    this._saleDao,
    this._adjDao,
    this._journalService,
    this._commissionService,
    this._loyaltyPointsService, {
    SessionService? sessionService,
    CashierShiftService? cashierShiftService,
    AppSettingsService? settings,
  }) : _sessionService = sessionService,
       _cashierShiftService = cashierShiftService,
       _settings = settings;

  // ════════════════════════════════════════════════════════════════════════════
  // SEARCH
  // ════════════════════════════════════════════════════════════════════════════

  /// Search sale invoices by number, product name, or SKU for a customer.
  Future<List<InvoiceSearchResult>> searchSaleInvoices(
    String query, {
    int? customerId,
    int limit = 20,
  }) async {
    final q = '%$query%';
    final rows = await _db
        .customSelect(
          'SELECT DISTINCT s.id, s.invoice_number, s.sale_date, s.total_cents, '
          '  s.customer_id, c.name AS customer_name '
          'FROM ${WarehouseDocumentScope.primaryDocuments(InventoryPostingDocument.sale)} s '
          'LEFT JOIN customers c ON c.id = s.customer_id '
          'LEFT JOIN sale_items si ON si.sale_id = s.id '
          'LEFT JOIN products p ON p.id = si.product_id '
          'LEFT JOIN product_variants pv ON pv.id = si.variant_id '
          "WHERE s.status = 'completed' "
          '  AND (s.invoice_number LIKE ? '
          '    OR p.name LIKE ? OR p.sku LIKE ? OR p.barcode LIKE ? '
          '    OR pv.sku LIKE ? OR pv.barcode LIKE ?) '
          '${customerId != null ? "AND s.customer_id = $customerId " : ""}'
          'ORDER BY s.sale_date DESC '
          'LIMIT ?',
          variables: [
            Variable.withString(q),
            Variable.withString(q),
            Variable.withString(q),
            Variable.withString(q),
            Variable.withString(q),
            Variable.withString(q),
            Variable.withInt(limit),
          ],
        )
        .get();

    return rows
        .map(
          (r) => InvoiceSearchResult(
            invoiceId: r.read<int>('id'),
            invoiceNumber: r.read<String>('invoice_number'),
            date: DateTime.parse(r.read<String>('sale_date')),
            totalCents: r.read<int>('total_cents'),
            partyId: r.readNullable<int>('customer_id'),
            partyName: r.readNullable<String>('customer_name'),
          ),
        )
        .toList();
  }

  /// Search purchase invoices by number, product name, or SKU for a supplier.
  Future<List<InvoiceSearchResult>> searchPurchaseInvoices(
    String query, {
    int? supplierId,
    int limit = 20,
  }) async {
    final q = '%$query%';
    final rows = await _db
        .customSelect(
          'SELECT DISTINCT pu.id, pu.purchase_number, pu.purchase_date, pu.total_cents, '
          '  pu.supplier_id, sup.name AS supplier_name '
          'FROM ${WarehouseDocumentScope.primaryDocuments(InventoryPostingDocument.purchase)} pu '
          'LEFT JOIN suppliers sup ON sup.id = pu.supplier_id '
          'LEFT JOIN purchase_items pi ON pi.purchase_id = pu.id '
          'LEFT JOIN products p ON p.id = pi.product_id '
          'LEFT JOIN product_variants pv ON pv.id = pi.variant_id '
          "WHERE pu.status = 'posted' "
          '  AND (pu.purchase_number LIKE ? '
          '    OR p.name LIKE ? OR p.sku LIKE ? OR p.barcode LIKE ? '
          '    OR pv.sku LIKE ? OR pv.barcode LIKE ?) '
          '${supplierId != null ? "AND pu.supplier_id = $supplierId " : ""}'
          'ORDER BY pu.purchase_date DESC '
          'LIMIT ?',
          variables: [
            Variable.withString(q),
            Variable.withString(q),
            Variable.withString(q),
            Variable.withString(q),
            Variable.withString(q),
            Variable.withString(q),
            Variable.withInt(limit),
          ],
        )
        .get();

    return rows
        .map(
          (r) => InvoiceSearchResult(
            invoiceId: r.read<int>('id'),
            invoiceNumber: r.read<String>('purchase_number'),
            date: DateTime.parse(r.read<String>('purchase_date')),
            totalCents: r.read<int>('total_cents'),
            partyId: r.readNullable<int>('supplier_id'),
            partyName: r.readNullable<String>('supplier_name'),
          ),
        )
        .toList();
  }

  /// Search products with last known price from party invoice history.
  ///
  /// For products WITH variants (`has_variants = 1`): returns one row per
  /// active variant, including color/size labels and variant-level pricing.
  /// For products WITHOUT variants: returns the base product row.
  Future<List<ProductSearchResult>> searchProducts(
    String query, {
    required ReturnSide side,
    int? partyId,
    int limit = 30,
  }) async {
    final q = '%$query%';
    final results = <ProductSearchResult>[];

    // ── 1) Products WITHOUT variants ──
    // Non-variant products still have a default row in `product_variants` that
    // may carry `color_id` / `size_id` (e.g. when the product was previously a
    // variant product, or when color/size was assigned to the default variant
    // later). We LEFT JOIN the active default variant so the same color/size
    // chip rendered for variant products is also rendered here when present.
    final baseRows = await _db
        .customSelect(
          'SELECT p.id, p.name, p.sku, p.barcode, p.price_cents, p.cost_cents, '
          '  p.last_purchase_price_cents, '
          '  p.sales_tax_rate_bps, p.purchase_tax_rate_bps, p.measurement_type, '
          '  CASE WHEN pv.id IS NULL THEN p.stock_quantity ELSE ws.quantity END AS stock_quantity, '
          '  (SELECT COUNT(*) FROM product_variants v WHERE v.product_id = p.id AND v.is_active = 1) AS operational_count, '
          '  pc.name AS color_name, sz.name AS size_name '
          'FROM products p '
          'LEFT JOIN product_variants pv ON pv.id = ('
          '  SELECT MIN(pv2.id) FROM product_variants pv2 '
          '  WHERE pv2.product_id = p.id AND pv2.is_active = 1) '
          'LEFT JOIN ${WarehouseStockScope.primaryStocks} ws ON ws.variant_id = pv.id '
          'LEFT JOIN product_colors pc ON pc.id = pv.color_id '
          'LEFT JOIN sizes sz ON sz.id = pv.size_id '
          'WHERE p.is_active = 1 AND p.has_variants = 0 '
          '  AND (p.name LIKE ? OR p.sku LIKE ? OR p.barcode LIKE ?) '
          'ORDER BY p.name ASC '
          'LIMIT ?',
          variables: [
            Variable.withString(q),
            Variable.withString(q),
            Variable.withString(q),
            Variable.withInt(limit),
          ],
        )
        .get();

    for (final row in baseRows) {
      if (row.read<int>('operational_count') > 1) {
        throw StateError(
          'Ambiguous simple-product operational row in return search.',
        );
      }
      final productId = row.read<int>('id');
      // Purchase side MUST surface the GROSS supplier reference
      // (`last_purchase_price_cents ?? cost_cents`) — the same convention
      // used by `purchase_form_screen.dart` (Phase 15.1) and the picker in
      // `purchase_adj_return_form_screen.dart`. Falling back to `cost_cents`
      // alone (IAS-2 NET basis) caused the variant-vs-no-variant asymmetry
      // visible in the adjustment-return picker when entered via
      // `unified_return_search_sheet.dart` (Phase 15.2).
      final defaultPrice = side == ReturnSide.sale
          ? row.read<int>('price_cents')
          : (row.readNullable<int>('last_purchase_price_cents') ??
                row.read<int>('cost_cents'));

      int lastPrice = defaultPrice;
      if (partyId != null) {
        final hp = await _getLastInvoicePrice(
          productId: productId,
          side: side,
          partyId: partyId,
        );
        if (hp != null) lastPrice = hp;
      }

      final taxBps = side == ReturnSide.sale
          ? row.read<int>('sales_tax_rate_bps')
          : row.read<int>('purchase_tax_rate_bps');

      // Build variant label from the default variant's color/size (if any).
      final colorName = row.readNullable<String>('color_name');
      final sizeName = row.readNullable<String>('size_name');
      final parts = <String>[?colorName, ?sizeName];
      final label = parts.isNotEmpty ? parts.join(' / ') : null;

      results.add(
        ProductSearchResult(
          productId: productId,
          productName: row.read<String>('name'),
          variantLabel: label,
          sku: row.readNullable<String>('sku'),
          barcode: row.readNullable<String>('barcode'),
          lastPriceCents: lastPrice,
          taxRateBps: taxBps,
          stockQuantity: row.read<int>('stock_quantity'),
          measurementType: row.read<String>('measurement_type'),
        ),
      );
    }

    // ── 2) Products WITH variants ──
    final variantRows = await _db
        .customSelect(
          'SELECT p.id AS product_id, p.name AS product_name, '
          '  p.sales_tax_rate_bps, p.purchase_tax_rate_bps, p.measurement_type, '
          '  pv.id AS variant_id, pv.sku AS variant_sku, pv.barcode AS variant_barcode, '
          '  pv.price_cents AS variant_price, pv.cost_cents AS variant_cost, '
          '  pv.last_purchase_price_cents AS variant_last_purchase_price_cents, '
          '  ws.quantity AS variant_stock, '
          '  pc.name AS color_name, sz.name AS size_name '
          'FROM products p '
          'JOIN product_variants pv ON pv.product_id = p.id AND pv.is_active = 1 '
          'LEFT JOIN ${WarehouseStockScope.primaryStocks} ws ON ws.variant_id = pv.id '
          'LEFT JOIN product_colors pc ON pc.id = pv.color_id '
          'LEFT JOIN sizes sz ON sz.id = pv.size_id '
          'WHERE p.is_active = 1 AND p.has_variants = 1 '
          '  AND (p.name LIKE ? OR p.sku LIKE ? OR p.barcode LIKE ? '
          '    OR pv.sku LIKE ? OR pv.barcode LIKE ?) '
          'ORDER BY p.name ASC, pc.name ASC, sz.name ASC '
          'LIMIT ?',
          variables: [
            Variable.withString(q),
            Variable.withString(q),
            Variable.withString(q),
            Variable.withString(q),
            Variable.withString(q),
            Variable.withInt(limit),
          ],
        )
        .get();

    for (final row in variantRows) {
      final productId = row.read<int>('product_id');
      final variantId = row.read<int>('variant_id');
      // See base-products comment above — same Phase 15.2 rule for variants.
      final defaultPrice = side == ReturnSide.sale
          ? row.read<int>('variant_price')
          : (row.readNullable<int>('variant_last_purchase_price_cents') ??
                row.read<int>('variant_cost'));

      int lastPrice = defaultPrice;
      if (partyId != null) {
        final hp = await _getLastInvoicePrice(
          productId: productId,
          variantId: variantId,
          side: side,
          partyId: partyId,
        );
        if (hp != null) lastPrice = hp;
      }

      // Build variant label from color + size
      final colorName = row.readNullable<String>('color_name');
      final sizeName = row.readNullable<String>('size_name');
      final parts = <String>[?colorName, ?sizeName];
      final label = parts.isNotEmpty ? parts.join(' / ') : null;

      final taxBps = side == ReturnSide.sale
          ? row.read<int>('sales_tax_rate_bps')
          : row.read<int>('purchase_tax_rate_bps');

      results.add(
        ProductSearchResult(
          productId: productId,
          variantId: variantId,
          productName: row.read<String>('product_name'),
          variantLabel: label,
          sku: row.readNullable<String>('variant_sku'),
          barcode: row.readNullable<String>('variant_barcode'),
          lastPriceCents: lastPrice,
          taxRateBps: taxBps,
          stockQuantity: row.read<int>('variant_stock'),
          measurementType: row.read<String>('measurement_type'),
        ),
      );
    }

    return results;
  }

  /// Get last invoice price for a product+variant from party history.
  Future<int?> _getLastInvoicePrice({
    required int productId,
    int? variantId,
    required ReturnSide side,
    required int partyId,
  }) async {
    if (side == ReturnSide.sale) {
      final row = await _db
          .customSelect(
            'SELECT si.unit_price_cents FROM sale_items si '
            'JOIN ${WarehouseDocumentScope.primaryDocuments(InventoryPostingDocument.sale)} s ON s.id = si.sale_id '
            "WHERE s.status = 'completed' AND s.customer_id = ? "
            'AND si.product_id = ? '
            '${variantId != null ? "AND si.variant_id = $variantId " : ""}'
            'ORDER BY s.sale_date DESC LIMIT 1',
            variables: [Variable.withInt(partyId), Variable.withInt(productId)],
          )
          .getSingleOrNull();
      return row?.read<int>('unit_price_cents');
    } else {
      final row = await _db
          .customSelect(
            'SELECT pi.unit_cost_cents FROM purchase_items pi '
            'JOIN ${WarehouseDocumentScope.primaryDocuments(InventoryPostingDocument.purchase)} pu ON pu.id = pi.purchase_id '
            "WHERE pu.status = 'posted' AND pu.supplier_id = ? "
            'AND pi.product_id = ? '
            '${variantId != null ? "AND pi.variant_id = $variantId " : ""}'
            'ORDER BY pu.purchase_date DESC LIMIT 1',
            variables: [Variable.withInt(partyId), Variable.withInt(productId)],
          )
          .getSingleOrNull();
      return row?.read<int>('unit_cost_cents');
    }
  }

  // ════════════════════════════════════════════════════════════════════════════
  // SMART MODE RESOLUTION
  // ════════════════════════════════════════════════════════════════════════════

  /// Get all returnable invoice items for a product+variant from a party.
  /// Returns items in FIFO order (oldest first) with remaining returnable qty.
  Future<List<ReturnableInvoiceItem>> getReturnableInvoiceItems({
    required int productId,
    int? variantId,
    required ReturnSide side,
    required int partyId,
  }) async {
    if (side == ReturnSide.sale) {
      return _getSaleReturnableItems(productId, variantId, partyId);
    } else {
      return _getPurchaseReturnableItems(productId, variantId, partyId);
    }
  }

  Future<List<ReturnableInvoiceItem>> _getSaleReturnableItems(
    int productId,
    int? variantId,
    int customerId,
  ) async {
    // `already_returned` MUST union linked + adjustment quantity:
    //   • Linked: sum of `sale_return_items.quantity` on non-voided
    //     parents.
    //   • Adjustment: `sale_items.qty_returned_adjustment` counter,
    //     which is FIFO-allocated to specific sale_items by
    //     `AdjustmentReturnDao._allocateSaleItemsForAdjustment`.
    // Without the second term the FIFO allocator in `resolveLineItem`
    // would happily produce a linked-return chunk for units that were
    // already withdrawn via an adjustment return, driving stock and GL
    // inventory above the original sold quantity.
    final rows = await _db
        .customSelect(
          'SELECT si.id AS item_id, si.sale_id, s.invoice_number, s.sale_date, '
          '  si.quantity, si.quantity_scale, si.measurement_type, si.unit_price_cents, '
          '  si.subtotal_cents, si.discount_cents, si.tax_cents, '
          '  COALESCE(s.tax_inclusive_at_post, 0) AS tax_inclusive, '
          '  COALESCE(('
          '    SELECT SUM(sri.quantity) FROM sale_return_items sri '
          '    JOIN sale_returns sr ON sr.id = sri.return_id '
          "    WHERE sri.sale_item_id = si.id AND sr.status != 'voided'"
          '  ), 0) AS linked_quantity, '
          '  COALESCE(('
          '    SELECT SUM(sri.subtotal_cents) FROM sale_return_items sri '
          '    JOIN sale_returns sr ON sr.id = sri.return_id '
          "    WHERE sri.sale_item_id = si.id AND sr.status != 'voided'"
          '  ), 0) AS linked_subtotal, '
          '  COALESCE(('
          '    SELECT SUM(sri.discount_cents) FROM sale_return_items sri '
          '    JOIN sale_returns sr ON sr.id = sri.return_id '
          "    WHERE sri.sale_item_id = si.id AND sr.status != 'voided'"
          '  ), 0) AS linked_discount, '
          '  COALESCE(('
          '    SELECT SUM(sri.tax_cents) FROM sale_return_items sri '
          '    JOIN sale_returns sr ON sr.id = sri.return_id '
          "    WHERE sri.sale_item_id = si.id AND sr.status != 'voided'"
          '  ), 0) AS linked_tax, '
          '  COALESCE(('
          '    SELECT SUM(sri.refund_cents) FROM sale_return_items sri '
          '    JOIN sale_returns sr ON sr.id = sri.return_id '
          "    WHERE sri.sale_item_id = si.id AND sr.status != 'voided'"
          '  ), 0) AS linked_refund, '
          '  ('
          '    COALESCE(('
          '      SELECT SUM(sri.quantity) FROM sale_return_items sri '
          '      JOIN sale_returns sr ON sr.id = sri.return_id '
          "      WHERE sri.sale_item_id = si.id AND sr.status != 'voided'"
          '    ), 0) '
          '    + COALESCE(si.qty_returned_adjustment, 0)'
          '  ) AS already_returned '
          'FROM sale_items si '
          'JOIN ${WarehouseDocumentScope.primaryDocuments(InventoryPostingDocument.sale)} s ON s.id = si.sale_id '
          "WHERE s.status = 'completed' AND s.customer_id = ? "
          '  AND si.product_id = ? '
          '${variantId != null ? "AND si.variant_id = $variantId " : ""}'
          'ORDER BY s.sale_date ASC',
          variables: [
            Variable.withInt(customerId),
            Variable.withInt(productId),
          ],
        )
        .get();

    return rows
        .map((r) {
          final orig = r.read<int>('quantity');
          final returned = r.read<int>('already_returned');
          return ReturnableInvoiceItem(
            invoiceItemId: r.read<int>('item_id'),
            invoiceId: r.read<int>('sale_id'),
            invoiceNumber: r.read<String>('invoice_number'),
            invoiceDate: DateTime.parse(r.read<String>('sale_date')),
            productId: productId,
            variantId: variantId,
            originalQuantity: orig,
            quantityScale: r.read<int>('quantity_scale'),
            measurementType: r.read<String>('measurement_type'),
            alreadyReturnedQuantity: returned,
            unitPriceCents: r.read<int>('unit_price_cents'),
            originalSubtotalCents: r.read<int>('subtotal_cents'),
            originalDiscountCents: r.read<int>('discount_cents'),
            originalTaxCents: r.read<int>('tax_cents'),
            linkedReturnHistory: LinkedReturnHistory(
              quantity: r.read<int>('linked_quantity'),
              subtotalCents: r.read<int>('linked_subtotal'),
              discountCents: r.read<int>('linked_discount'),
              taxCents: r.read<int>('linked_tax'),
              refundCents: r.read<int>('linked_refund'),
            ),
            taxInclusivePricing: r.read<int>('tax_inclusive') != 0,
          );
        })
        .where((item) => item.remainingQuantity > 0)
        .toList();
  }

  Future<List<ReturnableInvoiceItem>> _getPurchaseReturnableItems(
    int productId,
    int? variantId,
    int supplierId,
  ) async {
    // Mirror of `_getSaleReturnableItems`: `already_returned` MUST union
    // linked + adjustment quantity. Without the
    // `purchase_items.qty_returned_adjustment` term, a linked purchase
    // return could be raised against units that were already withdrawn
    // by a posted adjustment return, putting stock above what was
    // actually received from the supplier.
    final rows = await _db
        .customSelect(
          'SELECT pi.id AS item_id, pi.purchase_id, pu.purchase_number, pu.purchase_date, '
          '  pi.quantity, pi.quantity_scale, pi.measurement_type, pi.unit_cost_cents, '
          '  pi.subtotal_cents, pi.discount_cents, pi.tax_cents, '
          '  COALESCE(pu.tax_inclusive_at_post, 0) AS tax_inclusive, '
          '  COALESCE(('
          '    SELECT SUM(pri.quantity) FROM purchase_return_items pri '
          '    JOIN purchase_returns pr ON pr.id = pri.return_id '
          "    WHERE pri.purchase_item_id = pi.id AND pr.status != 'voided'"
          '  ), 0) AS linked_quantity, '
          '  COALESCE(('
          '    SELECT SUM(pri.subtotal_cents) FROM purchase_return_items pri '
          '    JOIN purchase_returns pr ON pr.id = pri.return_id '
          "    WHERE pri.purchase_item_id = pi.id AND pr.status != 'voided'"
          '  ), 0) AS linked_subtotal, '
          '  COALESCE(('
          '    SELECT SUM(pri.discount_cents) FROM purchase_return_items pri '
          '    JOIN purchase_returns pr ON pr.id = pri.return_id '
          "    WHERE pri.purchase_item_id = pi.id AND pr.status != 'voided'"
          '  ), 0) AS linked_discount, '
          '  COALESCE(('
          '    SELECT SUM(pri.tax_cents) FROM purchase_return_items pri '
          '    JOIN purchase_returns pr ON pr.id = pri.return_id '
          "    WHERE pri.purchase_item_id = pi.id AND pr.status != 'voided'"
          '  ), 0) AS linked_tax, '
          '  COALESCE(('
          '    SELECT SUM(pri.refund_cents) FROM purchase_return_items pri '
          '    JOIN purchase_returns pr ON pr.id = pri.return_id '
          "    WHERE pri.purchase_item_id = pi.id AND pr.status != 'voided'"
          '  ), 0) AS linked_refund, '
          '  ('
          '    COALESCE(('
          '      SELECT SUM(pri.quantity) FROM purchase_return_items pri '
          '      JOIN purchase_returns pr ON pr.id = pri.return_id '
          "      WHERE pri.purchase_item_id = pi.id AND pr.status != 'voided'"
          '    ), 0) '
          '    + COALESCE(pi.qty_returned_adjustment, 0)'
          '  ) AS already_returned '
          'FROM purchase_items pi '
          'JOIN ${WarehouseDocumentScope.primaryDocuments(InventoryPostingDocument.purchase)} pu ON pu.id = pi.purchase_id '
          "WHERE pu.status = 'posted' AND pu.supplier_id = ? "
          '  AND pi.product_id = ? '
          '${variantId != null ? "AND pi.variant_id = $variantId " : ""}'
          'ORDER BY pu.purchase_date ASC',
          variables: [
            Variable.withInt(supplierId),
            Variable.withInt(productId),
          ],
        )
        .get();

    return rows
        .map((r) {
          final orig = r.read<int>('quantity');
          final returned = r.read<int>('already_returned');
          return ReturnableInvoiceItem(
            invoiceItemId: r.read<int>('item_id'),
            invoiceId: r.read<int>('purchase_id'),
            invoiceNumber: r.read<String>('purchase_number'),
            invoiceDate: DateTime.parse(r.read<String>('purchase_date')),
            productId: productId,
            variantId: variantId,
            originalQuantity: orig,
            quantityScale: r.read<int>('quantity_scale'),
            measurementType: r.read<String>('measurement_type'),
            alreadyReturnedQuantity: returned,
            unitPriceCents: r.read<int>('unit_cost_cents'),
            originalSubtotalCents: r.read<int>('subtotal_cents'),
            originalDiscountCents: r.read<int>('discount_cents'),
            originalTaxCents: r.read<int>('tax_cents'),
            linkedReturnHistory: LinkedReturnHistory(
              quantity: r.read<int>('linked_quantity'),
              subtotalCents: r.read<int>('linked_subtotal'),
              discountCents: r.read<int>('linked_discount'),
              taxCents: r.read<int>('linked_tax'),
              refundCents: r.read<int>('linked_refund'),
            ),
            taxInclusivePricing: r.read<int>('tax_inclusive') != 0,
          );
        })
        .where((item) => item.remainingQuantity > 0)
        .toList();
  }

  /// Resolve the return mode for a single line item.
  ///
  /// Rules:
  /// 1. If no invoice history → adjustment (noInvoiceHistory)
  /// 2. If price differs from all invoice prices → adjustment (priceMismatch)
  /// 3. If price matches and qty fits → linked (priceMatch)
  /// 4. If price matches but qty exceeds available → linked for available,
  ///    adjustment for overflow (quantityOverflow)
  ///
  /// Returns one or two UnifiedReturnLineItems (linked + overflow adjustment).
  Future<List<UnifiedReturnLineItem>> resolveLineItem({
    required int productId,
    int? variantId,
    required String productName,
    String? variantLabel,
    required int quantity,
    int quantityScale = 1,
    String measurementType = 'piece',
    required int unitPriceCents,
    String? reason,
    required ReturnSide side,
    required int partyId,
  }) async {
    final returnableItems = await getReturnableInvoiceItems(
      productId: productId,
      variantId: variantId,
      side: side,
      partyId: partyId,
    );

    // Rule 1: No invoice history
    if (returnableItems.isEmpty) {
      return [
        UnifiedReturnLineItem(
          productId: productId,
          variantId: variantId,
          productName: productName,
          variantLabel: variantLabel,
          quantity: quantity,
          quantityScale: quantityScale,
          measurementType: measurementType,
          unitPriceCents: unitPriceCents,
          reason: reason,
          mode: ReturnMode.adjustment,
          modeReason: ReturnModeReason.noInvoiceHistory,
        ),
      ];
    }

    // Find items matching the exact price
    final matchingItems = returnableItems
        .where((item) => item.unitPriceCents == unitPriceCents)
        .toList();

    // Rule 2: Price doesn't match any invoice item
    if (matchingItems.isEmpty) {
      return [
        UnifiedReturnLineItem(
          productId: productId,
          variantId: variantId,
          productName: productName,
          variantLabel: variantLabel,
          quantity: quantity,
          quantityScale: quantityScale,
          measurementType: measurementType,
          unitPriceCents: unitPriceCents,
          reason: reason,
          mode: ReturnMode.adjustment,
          modeReason: ReturnModeReason.priceMismatch,
        ),
      ];
    }

    // FIFO allocation against matching invoice items
    int remainingQty = quantity;
    final allocations = <InvoiceItemAllocation>[];

    for (final item in matchingItems) {
      if (remainingQty <= 0) break;
      final take = remainingQty.clamp(0, item.remainingQuantity);
      if (take > 0) {
        allocations.add(
          InvoiceItemAllocation(
            invoiceItemId: item.invoiceItemId,
            invoiceId: item.invoiceId,
            quantity: take,
            quantityScale: item.quantityScale,
            measurementType: item.measurementType,
            unitPriceCents: item.unitPriceCents,
            originalQuantity: item.originalQuantity,
            originalSubtotalCents: item.originalSubtotalCents,
            originalDiscountCents: item.originalDiscountCents,
            originalTaxCents: item.originalTaxCents,
            previousLinkedHistory: item.linkedReturnHistory,
            taxInclusivePricing: item.taxInclusivePricing,
          ),
        );
        remainingQty -= take;
      }
    }

    final linkedQty = quantity - remainingQty;
    final results = <UnifiedReturnLineItem>[];

    // Rule 3: All qty fits in linked
    if (remainingQty == 0) {
      results.add(
        UnifiedReturnLineItem(
          productId: productId,
          variantId: variantId,
          productName: productName,
          variantLabel: variantLabel,
          quantity: linkedQty,
          quantityScale: allocations.first.quantityScale,
          measurementType: allocations.first.measurementType,
          unitPriceCents: unitPriceCents,
          reason: reason,
          mode: ReturnMode.linked,
          modeReason: ReturnModeReason.priceMatch,
          linkedAllocations: allocations,
        ),
      );
    } else {
      // Rule 4: Overflow — linked portion + adjustment remainder
      if (linkedQty > 0) {
        results.add(
          UnifiedReturnLineItem(
            productId: productId,
            variantId: variantId,
            productName: productName,
            variantLabel: variantLabel,
            quantity: linkedQty,
            quantityScale: allocations.first.quantityScale,
            measurementType: allocations.first.measurementType,
            unitPriceCents: unitPriceCents,
            reason: reason,
            mode: ReturnMode.linked,
            modeReason: ReturnModeReason.priceMatch,
            linkedAllocations: allocations,
          ),
        );
      }
      results.add(
        UnifiedReturnLineItem(
          productId: productId,
          variantId: variantId,
          productName: productName,
          variantLabel: variantLabel,
          quantity: remainingQty,
          quantityScale: quantityScale,
          measurementType: measurementType,
          unitPriceCents: unitPriceCents,
          reason: reason,
          mode: ReturnMode.adjustment,
          modeReason: ReturnModeReason.quantityOverflow,
        ),
      );
    }

    return results;
  }

  // ════════════════════════════════════════════════════════════════════════════
  // SUBMISSION
  // ════════════════════════════════════════════════════════════════════════════

  /// Price only unlinked adjustments. Linked returns use their original
  /// invoice allocations instead. A caller can use this result for preview;
  /// posting re-reads product rules within its database transaction.
  /// Pass this result as expectedAdjustmentQuote to reject a stale preview.
  /// Legacy callers without a preview are priced at posting time.
  Future<UnifiedAdjustmentQuote> priceAdjustmentItems({
    required ReturnSide side,
    required List<UnifiedReturnLineItem> items,
  }) => _db.transaction(() async {
    final policy = await BranchTaxPolicyStore(_db).read();
    if (policy == null && (_settings?.requiresPersistedTaxPolicy ?? false)) {
      throw StateError('Branch tax policy is missing.');
    }
    final deviceSettings = _settings?.current ?? const AppSettings();
    final settings = policy?.policy.applyTo(deviceSettings) ?? deviceSettings;
    final ids = items.map((i) => i.productId).toSet();
    final products = await (_db.select(
      _db.products,
    )..where((p) => p.id.isIn(ids))).get();
    final byId = {for (final p in products) p.id: p};
    final inputs = <LineItemPricingInput>[];
    for (final item in items) {
      if (!item.isAdjustment) {
        throw ArgumentError('Linked returns must use invoice pricing.');
      }
      final product = byId[item.productId];
      if (product == null) throw StateError('Unknown adjustment product.');
      final scale = MeasurementType.fromDb(
        product.measurementType,
      ).quantityScale;
      if (item.quantityScale != scale) {
        throw StateError('Adjustment quantity scale differs from product.');
      }
      inputs.add(
        LineItemPricingInput(
          unitPrice: Money.fromCents(item.unitPriceCents),
          quantity: item.quantity,
          quantityScale: scale,
          isTaxable: product.isTaxable,
          productTaxRateBps: side == ReturnSide.sale
              ? product.salesTaxRateBps
              : product.purchaseTaxRateBps,
        ),
      );
    }
    return UnifiedAdjustmentQuote._(
      _db,
      side,
      jsonEncode([
        for (final item in items)
          [
            item.productId,
            item.variantId,
            item.quantity,
            item.quantityScale,
            item.unitPriceCents,
            item.measurementType,
            byId[item.productId]!.isTaxable,
            side == ReturnSide.sale
                ? byId[item.productId]!.salesTaxRateBps
                : byId[item.productId]!.purchaseTaxRateBps,
          ],
      ]),
      policy,
      BranchTaxPolicy.fromLegacy(settings),
      InvoicePricingEngine.compute(
        InvoicePricingInput(
          lines: inputs,
          enableTaxCalculations: settings.enableTaxCalculations,
          defaultTaxRateBps:
              ((side == ReturnSide.sale
                          ? settings.defaultSalesTaxRate
                          : settings.defaultPurchaseTaxRate) *
                      100)
                  .round(),
          taxInclusivePricing: settings.taxInclusivePricing,
        ),
      ),
      settings.taxInclusivePricing,
    );
  });

  Future<UnifiedAdjustmentQuote?> _postingQuote(
    ReturnSide side,
    List<UnifiedReturnLineItem> items,
    UnifiedAdjustmentQuote? expected,
  ) async {
    if (expected != null) {
      if (!identical(expected._database, _db) ||
          expected._side != side ||
          items.isEmpty) {
        throw StateError('Adjustment preview does not match this return.');
      }
      if (expected._policy != null) {
        await BranchTaxPolicyStore(_db).assertCurrent(expected._policy);
      }
    }
    if (items.isEmpty) return null;
    final current = await priceAdjustmentItems(side: side, items: items);
    if (expected != null &&
        (expected._fingerprint != current._fingerprint ||
            (expected._policy == null) != (current._policy == null) ||
            !expected._legacyPolicy.hasSameValues(current._legacyPolicy))) {
      throw StateError('Adjustment pricing changed; refresh the preview.');
    }
    return current;
  }

  /// Submit a unified sale return. Splits items into linked and adjustment
  /// records, creates all within one transaction with shared batchId/timestamp.
  Future<String> submitSaleReturn({
    required int customerId,
    required int currencyId,
    required List<UnifiedReturnLineItem> items,
    required String refundMethod,
    String? notes,
    bool allowNegativeStock = false,
    bool allowOverHistory = false,
    UnifiedAdjustmentQuote? expectedAdjustmentQuote,
  }) async {
    if (items.isEmpty) throw Exception('No items to return');

    final batchId = const Uuid().v4();
    final now = DateTime.now();
    final userId = await _sessionService?.getCurrentUserId();
    final cashierShiftId = await _cashierShiftService?.resolveOpenShiftId(
      userId,
    );

    final linkedItems = items
        .where((i) => i.mode == ReturnMode.linked)
        .toList();
    final adjustmentItems = items
        .where((i) => i.mode == ReturnMode.adjustment)
        .toList();

    return _db.transaction(() async {
      final adjustmentQuote = await _postingQuote(
        ReturnSide.sale,
        adjustmentItems,
        expectedAdjustmentQuote,
      );
      final linkedHistories = <int, LinkedReturnHistory>{};
      // ── Linked returns (grouped by invoice) ──
      if (linkedItems.isNotEmpty) {
        // Group allocations by invoice
        final byInvoice = <int, List<_LinkedReturnEntry>>{};
        for (final item in linkedItems) {
          for (final alloc in item.linkedAllocations) {
            byInvoice.putIfAbsent(alloc.invoiceId, () => []);
            byInvoice[alloc.invoiceId]!.add(
              _LinkedReturnEntry(item: item, allocation: alloc),
            );
          }
        }

        for (final entry in byInvoice.entries) {
          final saleId = entry.key;
          final entries = entry.value;

          final returnNumber = await _saleDao.generateSaleReturnNumber();

          // Build return items with proportional calculations
          final returnItemCompanions = <SaleReturnItemsCompanion>[];
          for (final e in entries) {
            final history =
                linkedHistories[e.allocation.invoiceItemId] ??
                await _saleDao.getLinkedReturnHistory(
                  e.allocation.invoiceItemId,
                );
            final calc = ReturnCalculationService.computeProportionalReturn(
              originalQuantity: e.allocation.originalQuantity,
              returnQuantity: e.allocation.quantity,
              originalSubtotalCents: e.allocation.originalSubtotalCents,
              originalDiscountCents: e.allocation.originalDiscountCents,
              originalTaxCents: e.allocation.originalTaxCents,
              previousLinkedHistory: history,
              taxInclusivePricing: e.allocation.taxInclusivePricing,
            );
            linkedHistories[e.allocation.invoiceItemId] = history.add(
              calc,
              e.allocation.quantity,
            );

            returnItemCompanions.add(
              SaleReturnItemsCompanion.insert(
                returnId: 0, // Set by DAO
                saleItemId: e.allocation.invoiceItemId,
                quantity: e.allocation.quantity,
                quantityScale: Value(e.allocation.quantityScale),
                measurementType: Value(e.allocation.measurementType),
                refundCents: Decimal.fromInt(calc.refundCents),
                subtotalCents: Value(Decimal.fromInt(calc.subtotalCents)),
                discountCents: Value(Decimal.fromInt(calc.discountCents)),
                taxCents: Value(Decimal.fromInt(calc.taxCents)),
                reason: Value(e.item.reason),
              ),
            );
          }

          final totalRefund = returnItemCompanions.fold<int>(
            0,
            (sum, c) => sum + c.refundCents.value.toBigInt().toInt(),
          );

          final returnData =
              SaleReturnsCompanion.insert(
                saleId: saleId,
                cashierShiftId: cashierShiftId != null
                    ? Value(cashierShiftId)
                    : const Value.absent(),
                returnNumber: returnNumber,
                totalCents: Decimal.fromInt(totalRefund),
                currencyId: currencyId,
                status: const Value('draft'),
                dispositionType: const Value('restock'),
                refundMethod: Value(refundMethod),
                reason: Value(notes),
                returnDate: Value(now),
                createdAt: Value(now),
              ).withPricingSnapshot(
                taxInclusive: entries.first.allocation.taxInclusivePricing,
              );

          final returnId = await _saleDao.createSaleReturn(
            returnData,
            returnItemCompanions,
          );

          // Update header totals from items
          await _saleDao.updateSaleReturnTotals(returnId);

          // Post the return
          await _saleDao.postSaleReturn(returnId);

          // ── JOURNAL ENTRIES ────────────────────────────────────────────
          // The unified service used to skip JE creation for the linked
          // path entirely (only the adjustment path delegated to the DAO).
          // That left every linked return without a GL entry — silent
          // accounting drift. We now mirror SaleRepositoryImpl exactly.
          //
          // 1) Sales-return JE: Dr Revenue (+VAT Payable on tax), Cr Cash/AR
          // 2) COGS reversal JE: Dr Inventory, Cr COGS
          //
          // Commission and loyalty-points reversal are deliberately deferred
          // to Phase 1 (ReturnPostingService) — they require sale-context
          // helpers currently private to SaleRepositoryImpl. Linked returns
          // submitted through the legacy single-flow form still go through
          // the repository and keep that behaviour; this fix only covers
          // the GL gap that mattered for tax/audit compliance.
          final returnTaxCents = returnItemCompanions.fold<int>(
            0,
            (sum, c) =>
                sum +
                (c.taxCents.present ? c.taxCents.value.toBigInt().toInt() : 0),
          );
          await _journalService.recordSaleReturnJournalEntry(
            returnId: returnId,
            totalCents: totalRefund,
            taxCents: returnTaxCents,
            currencyId: currencyId,
            refundMethod: refundMethod,
            userId: userId,
          );

          final returnCostCents = await _saleDao.computeSaleReturnCostCents(
            returnId,
          );
          await _journalService.recordSaleReturnCOGSReversalJournalEntry(
            returnId: returnId,
            costCents: returnCostCents,
            currencyId: currencyId,
            userId: userId,
          );
        }
      }

      // ── Adjustment returns ──
      if (adjustmentItems.isNotEmpty) {
        final adjReturnNumber = await _adjDao.generateSaleAdjReturnNumber();

        final quote = adjustmentQuote!;
        final pricing = quote.pricing;

        final modeReasons = adjustmentItems
            .map((i) => i.modeReason.name)
            .toSet()
            .join(', ');

        final adjReturnData = SaleReturnAdjustmentsCompanion.insert(
          returnNumber: adjReturnNumber,
          customerId: Value(customerId),
          currencyId: currencyId,
          subtotalCents: Value(Decimal.fromInt(pricing.subtotal.cents)),
          taxCents: Value(Decimal.fromInt(pricing.tax.cents)),
          totalCents: Decimal.fromInt(pricing.total.cents),
          status: const Value('draft'),
          refundMethod: Value(refundMethod),
          returnMode: const Value('adjustment'),
          modeReason: Value(modeReasons),
          batchId: Value(batchId),
          notes: Value(notes),
          returnDate: Value(now),
          createdAt: Value(now),
          updatedAt: Value(now),
        ).withPricingSnapshot(taxInclusive: quote.taxInclusive);

        final adjItemCompanions = adjustmentItems.asMap().entries.map((entry) {
          final item = entry.value;
          final line = pricing.lines[entry.key];
          return SaleReturnAdjustmentItemsCompanion.insert(
            returnId: 0, // Set by DAO
            productId: item.productId,
            variantId: Value(item.variantId),
            quantity: item.quantity,
            quantityScale: Value(item.quantityScale),
            measurementType: Value(item.measurementType),
            unitPriceCents: Decimal.fromInt(item.unitPriceCents),
            taxCents: Value(Decimal.fromInt(line.tax.cents)),
            taxRateBpsAtPost: Value(line.local.effectiveTaxRateBps),
            totalCents: Decimal.fromInt(line.total.cents),
            reason: Value(item.reason),
          );
        }).toList();

        final adjReturnId = await _adjDao.createSaleAdjReturn(
          adjReturnData,
          adjItemCompanions,
        );

        await _adjDao.postSaleAdjReturn(
          adjReturnId,
          journalEntryService: _journalService,
          userId: userId,
          allowOverHistory: allowOverHistory,
          commissionService: _commissionService,
          loyaltyPointsService: _loyaltyPointsService,
        );
      }

      return batchId;
    });
  }

  /// Submit a unified purchase return. Splits items into linked and adjustment
  /// records, creates all within one transaction with shared batchId/timestamp.
  Future<String> submitPurchaseReturn({
    required int supplierId,
    required int currencyId,
    required List<UnifiedReturnLineItem> items,
    required String refundMethod,
    String? notes,
    bool allowNegativeStock = false,
    bool allowOverHistory = false,
    UnifiedAdjustmentQuote? expectedAdjustmentQuote,
  }) async {
    if (items.isEmpty) throw Exception('No items to return');

    final batchId = const Uuid().v4();
    final now = DateTime.now();

    final linkedItems = items
        .where((i) => i.mode == ReturnMode.linked)
        .toList();
    final adjustmentItems = items
        .where((i) => i.mode == ReturnMode.adjustment)
        .toList();

    return _db.transaction(() async {
      final adjustmentQuote = await _postingQuote(
        ReturnSide.purchase,
        adjustmentItems,
        expectedAdjustmentQuote,
      );
      final linkedHistories = <int, LinkedReturnHistory>{};
      // ── Linked returns (grouped by invoice) ──
      if (linkedItems.isNotEmpty) {
        final byInvoice = <int, List<_LinkedReturnEntry>>{};
        for (final item in linkedItems) {
          for (final alloc in item.linkedAllocations) {
            byInvoice.putIfAbsent(alloc.invoiceId, () => []);
            byInvoice[alloc.invoiceId]!.add(
              _LinkedReturnEntry(item: item, allocation: alloc),
            );
          }
        }

        for (final entry in byInvoice.entries) {
          final purchaseId = entry.key;
          final entries = entry.value;

          final returnNumber = await _purchaseDao.generateReturnNumber();

          final returnItemCompanions = <PurchaseReturnItemsCompanion>[];
          for (final e in entries) {
            final history =
                linkedHistories[e.allocation.invoiceItemId] ??
                await _purchaseDao.getLinkedReturnHistory(
                  e.allocation.invoiceItemId,
                );
            final calc = ReturnCalculationService.computeProportionalReturn(
              originalQuantity: e.allocation.originalQuantity,
              returnQuantity: e.allocation.quantity,
              originalSubtotalCents: e.allocation.originalSubtotalCents,
              originalDiscountCents: e.allocation.originalDiscountCents,
              originalTaxCents: e.allocation.originalTaxCents,
              previousLinkedHistory: history,
              taxInclusivePricing: e.allocation.taxInclusivePricing,
            );
            linkedHistories[e.allocation.invoiceItemId] = history.add(
              calc,
              e.allocation.quantity,
            );

            returnItemCompanions.add(
              PurchaseReturnItemsCompanion.insert(
                returnId: 0, // Set by DAO
                purchaseItemId: e.allocation.invoiceItemId,
                quantity: e.allocation.quantity,
                quantityScale: Value(e.allocation.quantityScale),
                measurementType: Value(e.allocation.measurementType),
                refundCents: Decimal.fromInt(calc.refundCents),
                subtotalCents: Value(Decimal.fromInt(calc.subtotalCents)),
                discountCents: Value(Decimal.fromInt(calc.discountCents)),
                taxCents: Value(Decimal.fromInt(calc.taxCents)),
                reason: Value(e.item.reason),
              ),
            );
          }

          final totalRefund = returnItemCompanions.fold<int>(
            0,
            (sum, c) => sum + c.refundCents.value.toBigInt().toInt(),
          );

          final returnData =
              PurchaseReturnsCompanion.insert(
                purchaseId: purchaseId,
                returnNumber: returnNumber,
                totalCents: Decimal.fromInt(totalRefund),
                currencyId: currencyId,
                status: const Value('draft'),
                dispositionType: const Value('restock'),
                refundMethod: Value(refundMethod),
                reason: Value(notes),
                returnDate: Value(now),
                createdAt: Value(now),
              ).withPricingSnapshot(
                taxInclusive: entries.first.allocation.taxInclusivePricing,
              );

          final returnId = await _purchaseDao.createPurchaseReturn(
            returnData,
            returnItemCompanions,
          );

          await _purchaseDao.updatePurchaseReturnTotals(returnId);
          await _purchaseDao.postPurchaseReturn(
            returnId,
            allowNegativeStock: allowNegativeStock,
          );

          // ── JOURNAL ENTRIES ────────────────────────────────────────────
          // Mirror PurchaseRepositoryImpl: Dr Cash/AP, Cr VAT-Receivable
          // (when taxCents > 0), Cr Inventory (net). Without this call the
          // linked purchase-return submitted via the unified form left no
          // GL footprint at all — VAT input was permanently inflated and
          // AP / Cash never reflected the supplier credit.
          final returnTaxCents = returnItemCompanions.fold<int>(
            0,
            (sum, c) =>
                sum +
                (c.taxCents.present ? c.taxCents.value.toBigInt().toInt() : 0),
          );
          // Inventory leg = ACTUAL valuation removed by the stock ledger
          // (FIFO batch consumption / WAC current cost), NOT the refund net.
          // Passing it keeps 1200 reconciled with Σ(stock×cost); the refund
          // vs cost difference flows to 4100 as a purchase price variance.
          final returnInvCost = await _purchaseDao
              .computePurchaseReturnInventoryCostCents(returnId);
          await _journalService.recordPurchaseReturnJournalEntry(
            returnId: returnId,
            totalCents: totalRefund,
            taxCents: returnTaxCents,
            inventoryCostCents: returnInvCost,
            currencyId: currencyId,
            refundMethod: refundMethod,
          );
        }
      }

      // ── Adjustment returns ──
      if (adjustmentItems.isNotEmpty) {
        final adjReturnNumber = await _adjDao.generatePurchaseAdjReturnNumber();

        final quote = adjustmentQuote!;
        final pricing = quote.pricing;

        final modeReasons = adjustmentItems
            .map((i) => i.modeReason.name)
            .toSet()
            .join(', ');

        final adjReturnData = PurchaseReturnAdjustmentsCompanion.insert(
          returnNumber: adjReturnNumber,
          supplierId: supplierId,
          currencyId: currencyId,
          subtotalCents: Value(Decimal.fromInt(pricing.subtotal.cents)),
          taxCents: Value(Decimal.fromInt(pricing.tax.cents)),
          totalCents: Decimal.fromInt(pricing.total.cents),
          status: const Value('draft'),
          refundMethod: Value(refundMethod),
          returnMode: const Value('adjustment'),
          modeReason: Value(modeReasons),
          batchId: Value(batchId),
          notes: Value(notes),
          returnDate: Value(now),
          createdAt: Value(now),
          updatedAt: Value(now),
        ).withPricingSnapshot(taxInclusive: quote.taxInclusive);

        final adjItemCompanions = adjustmentItems.asMap().entries.map((entry) {
          final item = entry.value;
          final line = pricing.lines[entry.key];
          return PurchaseReturnAdjustmentItemsCompanion.insert(
            returnId: 0, // Set by DAO
            productId: item.productId,
            variantId: Value(item.variantId),
            quantity: item.quantity,
            quantityScale: Value(item.quantityScale),
            measurementType: Value(item.measurementType),
            unitPriceCents: Decimal.fromInt(item.unitPriceCents),
            taxCents: Value(Decimal.fromInt(line.tax.cents)),
            taxRateBpsAtPost: Value(line.local.effectiveTaxRateBps),
            totalCents: Decimal.fromInt(line.total.cents),
            reason: Value(item.reason),
          );
        }).toList();

        final adjReturnId = await _adjDao.createPurchaseAdjReturn(
          adjReturnData,
          adjItemCompanions,
        );

        await _adjDao.postPurchaseAdjReturn(
          adjReturnId,
          journalEntryService: _journalService,
          allowNegativeStock: allowNegativeStock,
          allowOverHistory: allowOverHistory,
        );
      }

      return batchId;
    });
  }
}

/// Internal helper for grouping linked return entries by invoice.
class _LinkedReturnEntry {
  final UnifiedReturnLineItem item;
  final InvoiceItemAllocation allocation;

  const _LinkedReturnEntry({required this.item, required this.allocation});
}
