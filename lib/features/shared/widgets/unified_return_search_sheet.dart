import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../../core/di/injection_container.dart';
import '../../../core/services/currency_service.dart';
import '../../../core/services/unified_return_service.dart';
import '../../../core/services/lan/lan_network_service.dart';

/// Opens the unified return search bottom sheet.
///
/// All "Return" entry points (customer profile, supplier profile,
/// sale detail, purchase detail, returns lists) call this single function.
///
/// - [side]: sale or purchase
/// - [partyId] / [partyName]: pre-selected customer or supplier (optional)
/// - [invoiceId] / [invoiceNumber]: when opened from an invoice detail screen,
///   the user can still search, but the current invoice is highlighted.
Future<void> showUnifiedReturnSearchSheet(
  BuildContext context, {
  required ReturnSide side,
  int? partyId,
  String? partyName,
  int? invoiceId,
  String? invoiceNumber,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _UnifiedReturnSearchSheet(
      side: side,
      partyId: partyId,
      partyName: partyName,
      invoiceId: invoiceId,
      invoiceNumber: invoiceNumber,
    ),
  );
}

class _UnifiedReturnSearchSheet extends StatefulWidget {
  final ReturnSide side;
  final int? partyId;
  final String? partyName;
  final int? invoiceId;
  final String? invoiceNumber;

  const _UnifiedReturnSearchSheet({
    required this.side,
    this.partyId,
    this.partyName,
    this.invoiceId,
    this.invoiceNumber,
  });

  @override
  State<_UnifiedReturnSearchSheet> createState() =>
      _UnifiedReturnSearchSheetState();
}

class _UnifiedReturnSearchSheetState extends State<_UnifiedReturnSearchSheet> {
  final _searchController = TextEditingController();
  final _service = sl<UnifiedReturnService>();
  final _currencyService = sl<CurrencyService>();
  final _lan = sl<LanNetworkService>();

  bool get _isRemoteClient =>
      _lan.snapshot.mode == LanMode.client && _lan.hasRemoteUserSession;

  List<InvoiceSearchResult> _invoices = [];
  List<ProductSearchResult> _products = [];
  bool _isSearching = false;
  bool _hasSearched = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _onSearch(String query) async {
    final q = query.trim();
    if (q.isEmpty) {
      setState(() {
        _invoices = [];
        _products = [];
        _hasSearched = false;
        _isSearching = false;
      });
      return;
    }

    setState(() => _isSearching = true);

    try {
      late List<InvoiceSearchResult> invoices;
      late List<ProductSearchResult> products;
      if (_isRemoteClient) {
        final responses = await Future.wait([
          widget.side == ReturnSide.sale
              ? _lan.fetchRemoteReturnableSales(query: q, limit: 50)
              : _lan.fetchRemoteReturnablePurchases(query: q, limit: 50),
          _lan.fetchRemoteCatalog(
            query: q,
            limit: 50,
            management: widget.side == ReturnSide.purchase,
          ),
        ]);
        final catalogPage = responses[1] as LanCatalogPage;
        if (widget.side == ReturnSide.sale) {
          final invoicePage = responses[0] as LanReturnableSalesPage;
          invoices = invoicePage.sales
              .map(
                (sale) => InvoiceSearchResult(
                  invoiceId: sale.saleId,
                  invoiceNumber: sale.invoiceNumber,
                  date: sale.saleDate,
                  totalCents: sale.totalCents,
                  partyName: sale.customerName,
                ),
              )
              .toList(growable: false);
        } else {
          final invoicePage = responses[0] as LanReturnablePurchasesPage;
          invoices = invoicePage.purchases
              .where(
                (purchase) =>
                    widget.partyId == null ||
                    purchase.supplierId == widget.partyId,
              )
              .map(
                (purchase) => InvoiceSearchResult(
                  invoiceId: purchase.purchaseId,
                  invoiceNumber: purchase.purchaseNumber,
                  date: purchase.purchaseDate,
                  totalCents: purchase.totalCents,
                  partyName: purchase.supplierName,
                ),
              )
              .toList(growable: false);
        }
        products = _mapRemoteProducts(
          catalogPage.products,
          purchase: widget.side == ReturnSide.purchase,
        );
      } else {
        if (widget.side == ReturnSide.sale) {
          invoices = await _service.searchSaleInvoices(
            q,
            customerId: widget.partyId,
          );
        } else {
          invoices = await _service.searchPurchaseInvoices(
            q,
            supplierId: widget.partyId,
          );
        }
        products = await _service.searchProducts(
          q,
          side: widget.side,
          partyId: widget.partyId,
        );
      }

      if (mounted) {
        setState(() {
          _invoices = invoices;
          _products = products;
          _isSearching = false;
          _hasSearched = true;
        });
      }
    } catch (e, st) {
      debugPrint('UnifiedReturnSearchSheet search error: $e\n$st');
      if (mounted) setState(() => _isSearching = false);
    }
  }

  List<ProductSearchResult> _mapRemoteProducts(
    List<LanCatalogProduct> catalog, {
    bool purchase = false,
  }) {
    final results = <ProductSearchResult>[];
    for (final product in catalog) {
      if (product.hasVariants) {
        for (final variant in product.variants) {
          results.add(
            ProductSearchResult(
              productId: product.id,
              variantId: variant.id,
              productName: product.name,
              variantLabel: variant.label,
              sku: variant.sku,
              barcode: variant.barcode,
              lastPriceCents: purchase
                  ? variant.lastPurchasePriceCents ??
                        variant.costCents ??
                        product.lastPurchasePriceCents ??
                        product.costCents ??
                        variant.priceCents
                  : variant.priceCents,
              taxRateBps: purchase
                  ? product.purchaseTaxRateBps
                  : product.salesTaxRateBps,
              stockQuantity: variant.stockQuantity,
              measurementType: product.measurementType,
            ),
          );
        }
      } else {
        final defaultVariant = product.variants.isEmpty
            ? null
            : product.variants.first;
        final rawLabel = defaultVariant?.label;
        results.add(
          ProductSearchResult(
            productId: product.id,
            variantId: defaultVariant?.id,
            productName: product.name,
            variantLabel: rawLabel == 'Default' ? null : rawLabel,
            sku: product.sku ?? defaultVariant?.sku,
            barcode: product.barcode ?? defaultVariant?.barcode,
            lastPriceCents: purchase
                ? product.lastPurchasePriceCents ??
                      product.costCents ??
                      product.priceCents
                : product.priceCents,
            taxRateBps: purchase
                ? product.purchaseTaxRateBps
                : product.salesTaxRateBps,
            stockQuantity: product.stockQuantity,
            measurementType: product.measurementType,
          ),
        );
      }
    }
    return results;
  }

  void _onInvoiceTap(InvoiceSearchResult inv) {
    Navigator.pop(context);
    if (widget.side == ReturnSide.sale) {
      context.push('/sales/returns/new?saleId=${inv.invoiceId}');
    } else {
      context.push('/purchases/returns/new?purchaseId=${inv.invoiceId}');
    }
  }

  void _onProductTap(ProductSearchResult prod) {
    Navigator.pop(context);
    // Pass productName and variantLabel separately so the form's item card
    // can render the color/size as a styled chip below the product name.
    if (widget.side == ReturnSide.sale) {
      context.push(
        '/sales/returns/adjustment'
        '?customerId=${widget.partyId ?? ''}'
        '&customerName=${Uri.encodeComponent(widget.partyName ?? '')}'
        '&productId=${prod.productId}'
        '&variantId=${prod.variantId ?? ''}'
        '&productName=${Uri.encodeComponent(prod.productName)}'
        '&variantLabel=${Uri.encodeComponent(prod.variantLabel ?? '')}'
        '&sku=${Uri.encodeComponent(prod.sku ?? '')}'
        '&price=${prod.lastPriceCents}'
        '&measurementType=${prod.measurementType}'
        '&taxRateBps=${prod.taxRateBps}',
      );
    } else {
      context.push(
        '/purchases/returns/adjustment'
        '?supplierId=${widget.partyId ?? ''}'
        '&supplierName=${Uri.encodeComponent(widget.partyName ?? '')}'
        '&productId=${prod.productId}'
        '&variantId=${prod.variantId ?? ''}'
        '&productName=${Uri.encodeComponent(prod.productName)}'
        '&variantLabel=${Uri.encodeComponent(prod.variantLabel ?? '')}'
        '&sku=${Uri.encodeComponent(prod.sku ?? '')}'
        '&price=${prod.lastPriceCents}'
        '&measurementType=${prod.measurementType}'
        '&taxRateBps=${prod.taxRateBps}',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isSale = widget.side == ReturnSide.sale;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      expand: false,
      builder: (context, scrollController) => Column(
        children: [
          // ── Handle ──
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: cs.onSurfaceVariant.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          // ── Title ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [cs.primary, cs.primary.withValues(alpha: 0.7)],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    LucideIcons.undo2,
                    size: 18,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isSale
                            ? 'returns.create_sale_return'.tr()
                            : 'returns.create_purchase_return'.tr(),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (widget.partyName != null)
                        Text(
                          widget.partyName!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Search bar ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              controller: _searchController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'returns.search_hint'.tr(),
                prefixIcon: const Icon(LucideIcons.search, size: 18),
                suffixIcon: _isSearching
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(LucideIcons.x, size: 16),
                        onPressed: () {
                          _searchController.clear();
                          _onSearch('');
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
              ),
              onChanged: _onSearch,
            ),
          ),
          const SizedBox(height: 12),

          // ── Results ──
          Expanded(
            child: _hasSearched && _invoices.isEmpty && _products.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          LucideIcons.searchX,
                          size: 40,
                          color: cs.onSurfaceVariant.withValues(alpha: 0.3),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'common.no_results'.tr(),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    children: [
                      // ── Invoices section ──
                      if (_invoices.isNotEmpty) ...[
                        _SectionHeader(
                          label: 'returns.invoices'.tr(),
                          color: cs.primary,
                        ),
                        ..._invoices.map(
                          (inv) => _InvoiceTile(
                            invoice: inv,
                            currencyService: _currencyService,
                            onTap: () => _onInvoiceTap(inv),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],

                      // ── Products section ──
                      if (_products.isNotEmpty) ...[
                        _SectionHeader(
                          label: 'returns.products'.tr(),
                          color: cs.secondary,
                        ),
                        ..._products.map(
                          (prod) => _ProductTile(
                            product: prod,
                            currencyService: _currencyService,
                            onTap: () => _onProductTap(prod),
                          ),
                        ),
                      ],

                      const SizedBox(height: 24),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SECTION HEADER
// ═══════════════════════════════════════════════════════════════════════════════

class _SectionHeader extends StatelessWidget {
  final String label;
  final Color color;
  const _SectionHeader({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, top: 4),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// INVOICE TILE
// ═══════════════════════════════════════════════════════════════════════════════

class _InvoiceTile extends StatelessWidget {
  final InvoiceSearchResult invoice;
  final CurrencyService currencyService;
  final VoidCallback onTap;

  const _InvoiceTile({
    required this.invoice,
    required this.currencyService,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: cs.surface,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    LucideIcons.fileText,
                    size: 18,
                    color: cs.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        invoice.invoiceNumber,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '${DateFormat('dd/MM/yyyy').format(invoice.date)} · ${currencyService.formatCents(invoice.totalCents)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  LucideIcons.chevronRight,
                  size: 16,
                  color: cs.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PRODUCT TILE
// ═══════════════════════════════════════════════════════════════════════════════

class _ProductTile extends StatelessWidget {
  final ProductSearchResult product;
  final CurrencyService currencyService;
  final VoidCallback onTap;

  const _ProductTile({
    required this.product,
    required this.currencyService,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: cs.surface,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: cs.secondaryContainer.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    product.variantId != null
                        ? LucideIcons.layers
                        : LucideIcons.package,
                    size: 18,
                    color: cs.secondary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.productName,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (product.variantLabel != null)
                        Text(
                          product.variantLabel!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      Text(
                        '${product.sku ?? ''} · ${currencyService.formatCents(product.lastPriceCents)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: cs.primaryContainer.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${'returns.stock'.tr()}: ${product.stockQuantity}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: cs.onPrimaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    IconButton(
                      icon: Icon(LucideIcons.plus, size: 18, color: cs.primary),
                      onPressed: onTap,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
