import 'dart:async';
import 'dart:typed_data';

import 'package:decimal/decimal.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/di/injection_container.dart';
import '../../../../core/measurement/measurement.dart';
import '../../../../core/money/money.dart';
import '../../../../core/pricing/discount.dart';
import '../../../../core/pricing/invoice_pricing_engine.dart';
import '../../../../core/pricing/line_item_pricing_engine.dart';
import '../../../../core/services/lan/lan_network_service.dart';
import '../../../../core/widgets/action_confirmation_dialog.dart';
import '../../../../core/widgets/theme_toggle_button.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';

class LanRemoteSaleScreen extends StatefulWidget {
  const LanRemoteSaleScreen({super.key});

  @override
  State<LanRemoteSaleScreen> createState() => _LanRemoteSaleScreenState();
}

class _LanRemoteSaleScreenState extends State<LanRemoteSaleScreen> {
  final _searchController = TextEditingController();
  final _paidController = TextEditingController();
  final _notesController = TextEditingController();
  final _cart = <_RemoteCartLine>[];
  final _imageFutures = <int, Future<Uint8List?>>{};
  Timer? _searchDebounce;
  Timer? _catalogRefresh;
  LanCatalogPage? _catalog;
  List<LanCustomerSummary> _customers = const [];
  List<LanEmployeeSummary> _salespeople = const [];
  LanCustomerSummary? _customer;
  LanEmployeeSummary? _salesperson;
  String _priceTier = 'retail';
  String _paymentMethod = 'cash';
  bool _loading = true;
  bool _submitting = false;
  bool _paidManuallyEdited = false;
  String? _error;
  LanSaleRequest? _pendingRequest;

  LanNetworkService get _lan => sl<LanNetworkService>();

  @override
  void initState() {
    super.initState();
    _load();
    _searchController.addListener(_scheduleSearch);
    _catalogRefresh = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted && !_loading && !_submitting) {
        _loadProducts(silent: true);
      }
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _catalogRefresh?.cancel();
    _searchController
      ..removeListener(_scheduleSearch)
      ..dispose();
    _paidController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _scheduleSearch() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), _loadProducts);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final values = await Future.wait<Object>([
        _lan.fetchRemoteCatalog(query: _searchController.text, limit: 120),
        _lan.fetchRemoteCustomers(limit: 150),
        _lan.fetchRemoteSalespeople(limit: 150),
      ]);
      if (!mounted) return;
      final catalog = values[0] as LanCatalogPage;
      setState(() {
        _catalog = catalog;
        _customers = values[1] as List<LanCustomerSummary>;
        _salespeople = values[2] as List<LanEmployeeSummary>;
        _loading = false;
        _syncPaidWithTotal();
      });
    } on LanBusinessException catch (error) {
      _handleError(error);
    } catch (_) {
      _handleError(
        const LanBusinessException(
          'network_error',
          'Unable to load data from the master.',
        ),
      );
    }
  }

  Future<void> _loadProducts({bool silent = false}) async {
    try {
      final catalog = await _lan.fetchRemoteCatalog(
        query: _searchController.text,
        limit: 120,
      );
      if (!mounted) return;
      setState(() {
        _catalog = catalog;
        _refreshCartProducts(catalog);
        _syncPaidWithTotal();
        _error = null;
      });
    } on LanBusinessException catch (error) {
      if (!silent || error.statusCode == 401) {
        _handleError(error);
      }
    }
  }

  void _refreshCartProducts(LanCatalogPage catalog) {
    if (_cart.isEmpty) return;
    final products = {for (final value in catalog.products) value.id: value};
    for (var index = 0; index < _cart.length; index++) {
      final current = _cart[index];
      final product = products[current.product.id];
      if (product == null) continue;
      LanCatalogVariant? variant;
      if (current.variant != null) {
        for (final value in product.variants) {
          if (value.id == current.variant!.id) {
            variant = value;
            break;
          }
        }
        if (variant == null) continue;
      }
      _cart[index] = _RemoteCartLine(
        product: product,
        variant: variant,
        quantity: current.quantity,
        priceTier: current.priceTier,
        discountType: current.discountType,
        discountValue: current.discountValue,
      );
    }
  }

  void _handleError(LanBusinessException error) {
    if (!mounted) return;
    if (error.statusCode == 401) {
      context.read<AuthBloc>().add(const AuthLogoutRequested());
      return;
    }
    if (error.code == 'sale_below_cost') {
      setState(() {
        _loading = false;
        _submitting = false;
        _error = null;
      });
      unawaited(_showBelowCostBlocked(error));
      return;
    }
    final localizedMessage = switch (error.code) {
      'sale_below_cost_reason_required' =>
        'settings.network.sale.below_cost_reason_required'.tr(),
      'discount_exceeds_max' =>
        'settings.network.sale.discount_exceeds_max'.tr(),
      _ => error.message,
    };
    setState(() {
      _loading = false;
      _submitting = false;
      _error = localizedMessage;
    });
  }

  Future<void> _showBelowCostBlocked(LanBusinessException error) async {
    if (!mounted) return;
    final productName = error.details['productName']?.toString().trim();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(
          LucideIcons.ban,
          color: Theme.of(dialogContext).colorScheme.error,
        ),
        title: Text('sales.below_cost_title'.tr()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (productName?.isNotEmpty == true) ...[
              Text(
                productName!,
                style: Theme.of(
                  dialogContext,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
            ],
            Text('sales.below_cost_blocked'.tr()),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('common.ok'.tr()),
          ),
        ],
      ),
    );
  }

  Future<void> _addProduct(LanCatalogProduct product) async {
    LanCatalogVariant? variant;
    if (product.hasVariants) {
      if (product.variants.isEmpty) {
        _showMessage('settings.network.sale.no_variants'.tr());
        return;
      }
      variant = await showDialog<LanCatalogVariant>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('settings.network.sale.choose_variant'.tr()),
          content: SizedBox(
            width: 420,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: product.variants.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, index) {
                final value = product.variants[index];
                return ListTile(
                  title: Text(value.label),
                  subtitle: Text(
                    _money(_priceFor(product, value, tier: _priceTier)),
                  ),
                  trailing: Text(_quantityLabel(value.stockQuantity, product)),
                  onTap: () => Navigator.pop(dialogContext, value),
                );
              },
            ),
          ),
        ),
      );
      if (variant == null) return;
    }

    final wholesale =
        variant?.wholesalePriceCents ?? product.wholesalePriceCents;
    if (_priceTier == 'wholesale' && wholesale == null) {
      _showMessage('settings.network.sale.wholesale_unavailable'.tr());
      return;
    }
    final variantId = variant?.id;
    final existingIndex = _cart.indexWhere(
      (line) =>
          line.product.id == product.id &&
          line.variant?.id == variantId &&
          line.priceTier == _priceTier,
    );
    final step = product.quantityScale;
    setState(() {
      if (existingIndex >= 0) {
        final current = _cart[existingIndex];
        final next = current.quantity + step;
        final available = variant?.stockQuantity ?? product.stockQuantity;
        if (_catalog?.allowNegativeStock == true ||
            !product.trackInventory ||
            next <= available) {
          _cart[existingIndex] = current.copyWith(quantity: next);
        }
      } else {
        _cart.add(
          _RemoteCartLine(
            product: product,
            variant: variant,
            quantity: step,
            priceTier: _priceTier,
          ),
        );
      }
      _invalidatePendingRequest();
    });
  }

  Future<void> _editQuantity(int index) async {
    final line = _cart[index];
    final type = MeasurementType.fromDb(line.product.measurementType);
    var selectedUnit = type.majorUnit;
    final controller = TextEditingController(
      text: MeasuredQuantity.editableValue(line.quantity, selectedUnit),
    );
    final result = await showDialog<int>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('settings.network.sale.quantity'.tr()),
          content: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  autofocus: true,
                ),
              ),
              const SizedBox(width: 12),
              DropdownButton<MeasurementUnit>(
                value: selectedUnit,
                items: type.inputUnits
                    .map(
                      (unit) => DropdownMenuItem(
                        value: unit,
                        child: Text(_unitLabel(unit)),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  final oldStored = MeasuredQuantity.parseToStored(
                    controller.text,
                    selectedUnit,
                  );
                  setDialogState(() {
                    selectedUnit = value;
                    controller.text = MeasuredQuantity.editableValue(
                      oldStored,
                      value,
                    );
                  });
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text('common.cancel'.tr()),
            ),
            FilledButton(
              onPressed: () {
                try {
                  final stored = MeasuredQuantity.parseToStored(
                    controller.text,
                    selectedUnit,
                  );
                  if (stored <= 0) return;
                  Navigator.pop(dialogContext, stored);
                } catch (_) {
                  _showMessage('settings.network.sale.invalid_quantity'.tr());
                }
              },
              child: Text('common.save'.tr()),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (result == null || !mounted) return;

    final available = line.variant?.stockQuantity ?? line.product.stockQuantity;
    if (_catalog?.allowNegativeStock != true &&
        line.product.trackInventory &&
        result > available) {
      _showMessage('settings.network.sale.insufficient_stock'.tr());
      return;
    }
    setState(() {
      _cart[index] = line.copyWith(quantity: result);
      _invalidatePendingRequest();
    });
  }

  InvoicePricingResult get _pricing {
    final catalog = _catalog;
    if (catalog == null || _cart.isEmpty) {
      return InvoicePricingResult.empty();
    }
    return InvoicePricingEngine.compute(
      InvoicePricingInput(
        lines: _cart
            .map(
              (line) => LineItemPricingInput(
                unitPrice: Money.fromCents(
                  _priceFor(line.product, line.variant, tier: line.priceTier),
                ),
                quantity: line.quantity,
                quantityScale: line.product.quantityScale,
                discount: line.discount,
                isTaxable: line.product.isTaxable,
                productTaxRateBps: line.product.salesTaxRateBps,
              ),
            )
            .toList(growable: false),
        enableTaxCalculations: catalog.enableTaxCalculations,
        defaultTaxRateBps: catalog.defaultSalesTaxRateBps,
        taxInclusivePricing: catalog.taxInclusivePricing,
      ),
    );
  }

  int _priceFor(
    LanCatalogProduct product,
    LanCatalogVariant? variant, {
    String? tier,
  }) {
    final retail = variant?.priceCents ?? product.priceCents;
    final wholesale =
        variant?.wholesalePriceCents ?? product.wholesalePriceCents;
    return (tier ?? _priceTier) == 'wholesale' && wholesale != null
        ? wholesale
        : retail;
  }

  void _invalidatePendingRequest() {
    _pendingRequest = null;
    _syncPaidWithTotal();
  }

  void _syncPaidWithTotal() {
    if (_paymentMethod == 'cash' && !_paidManuallyEdited) {
      _paidController.text = (_pricing.total.cents / 100).toStringAsFixed(2);
    }
  }

  int? _parsePaidCents() {
    final normalized = _paidController.text.trim().replaceAll(',', '.');
    if (normalized.isEmpty) return null;
    final value = Decimal.tryParse(normalized);
    if (value == null || value < Decimal.zero) return null;
    final cents = value * Decimal.fromInt(100);
    if (!cents.isInteger) return null;
    return cents.toBigInt().toInt();
  }

  int _lineSubtotalCents(_RemoteCartLine line) {
    return Money.fromCents(
      _priceFor(line.product, line.variant, tier: line.priceTier),
    ).multiplyRatio(line.quantity, line.product.quantityScale).round().cents;
  }

  Future<void> _editDiscount(int index) async {
    final catalog = _catalog;
    if (catalog == null || !catalog.allowDiscounts) return;
    final line = _cart[index];
    var mode = line.discountType == 'percentage' ? 'percentage' : 'fixed';
    final controller = TextEditingController(
      text: line.discountValue == 0
          ? ''
          : mode == 'percentage'
          ? (line.discountValue / 100).toStringAsFixed(2)
          : (line.discountValue / 100).toStringAsFixed(2),
    );
    String? errorText;
    final result = await showDialog<_DiscountEditResult>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('settings.network.sale.item_discount'.tr()),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(
                      value: 'fixed',
                      label: Text('settings.network.sale.discount_amount'.tr()),
                    ),
                    ButtonSegment(
                      value: 'percentage',
                      label: Text(
                        'settings.network.sale.discount_percentage'.tr(),
                      ),
                    ),
                  ],
                  selected: {mode},
                  onSelectionChanged: (values) => setDialogState(() {
                    mode = values.first;
                    controller.clear();
                    errorText = null;
                  }),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: mode == 'percentage'
                        ? 'settings.network.sale.discount_percentage'.tr()
                        : 'settings.network.sale.discount_amount'.tr(),
                    suffixText: mode == 'percentage'
                        ? '%'
                        : catalog.currencySymbol,
                    errorText: errorText,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(
                dialogContext,
                const _DiscountEditResult('none', 0),
              ),
              child: Text('settings.network.sale.remove_discount'.tr()),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text('common.cancel'.tr()),
            ),
            FilledButton(
              onPressed: () {
                final value = Decimal.tryParse(
                  controller.text.trim().replaceAll(',', '.'),
                );
                if (value == null || value < Decimal.zero) {
                  setDialogState(() {
                    errorText = 'settings.network.sale.invalid_discount'.tr();
                  });
                  return;
                }
                final scaled = value * Decimal.fromInt(100);
                if (!scaled.isInteger) {
                  setDialogState(() {
                    errorText = 'settings.network.sale.invalid_discount'.tr();
                  });
                  return;
                }
                final stored = scaled.toBigInt().toInt();
                final maxBps = (catalog.maxDiscountPercent * 100).round();
                final percentCap = maxBps.clamp(0, 9999);
                final subtotalCents = _lineSubtotalCents(line);
                final configuredFixedCap =
                    ((BigInt.from(subtotalCents) * BigInt.from(percentCap)) ~/
                            BigInt.from(10000))
                        .toInt();
                final belowFullValueCap = subtotalCents > 0
                    ? subtotalCents - 1
                    : 0;
                final maxAllowed = mode == 'percentage'
                    ? percentCap
                    : configuredFixedCap < belowFullValueCap
                    ? configuredFixedCap
                    : belowFullValueCap;
                if (stored > maxAllowed) {
                  setDialogState(() {
                    errorText = 'settings.network.sale.discount_exceeds_max'
                        .tr();
                  });
                  return;
                }
                Navigator.pop(
                  dialogContext,
                  stored == 0
                      ? const _DiscountEditResult('none', 0)
                      : _DiscountEditResult(mode, stored),
                );
              },
              child: Text('common.save'.tr()),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (result == null || !mounted) return;
    setState(() {
      _cart[index] = line.copyWith(
        discountType: result.type,
        discountValue: result.value,
      );
      _invalidatePendingRequest();
    });
  }

  Future<void> _showCartDialog() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, refreshDialog) => Dialog(
          insetPadding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760, maxHeight: 760),
            child: _buildCartPane(
              inDialog: true,
              refreshOverlay: () => refreshDialog(() {}),
              onClose: () => Navigator.pop(dialogContext),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _leaveSale() async {
    if (_cart.isNotEmpty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('settings.network.sale.leave_title'.tr()),
          content: Text('settings.network.sale.leave_message'.tr()),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text('common.cancel'.tr()),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text('settings.network.sale.back_to_shift'.tr()),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return;
    }
    context.go('/client-session');
  }

  Future<Uint8List?> _imageFor(LanCatalogProduct product) {
    if (!product.hasImage) return Future<Uint8List?>.value();
    return _imageFutures.putIfAbsent(
      product.id,
      () => _lan.fetchRemoteProductImage(product.id).catchError((_) => null),
    );
  }

  Widget _productImage(LanCatalogProduct product, {double size = 64}) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: ColoredBox(
          color: cs.surfaceContainerHighest,
          child: FutureBuilder<Uint8List?>(
            future: _imageFor(product),
            builder: (context, snapshot) {
              final bytes = snapshot.data;
              if (bytes != null && bytes.isNotEmpty) {
                return Image.memory(
                  bytes,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                );
              }
              return Icon(LucideIcons.package, color: cs.onSurfaceVariant);
            },
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (_cart.isEmpty || _submitting) return;
    final paid = _paymentMethod == 'cash' ? _parsePaidCents() : null;
    if (_paymentMethod == 'cash' && paid == null) {
      _showMessage('settings.network.sale.invalid_paid'.tr());
      return;
    }

    final request =
        _pendingRequest ??
        LanSaleRequest(
          idempotencyKey: const Uuid().v4(),
          customerId: _customer?.id,
          salespersonId: _salesperson?.id,
          paymentMethod: _paymentMethod,
          paidAmountCents: paid,
          notes: _notesController.text.trim().isEmpty
              ? null
              : _notesController.text.trim(),
          lines: _cart
              .map(
                (line) => LanSaleLineRequest(
                  productId: line.product.id,
                  variantId: line.variant?.id,
                  quantity: line.quantity,
                  priceTier: line.priceTier,
                  discountType: line.discountType,
                  discountValue: line.discountValue,
                ),
              )
              .toList(growable: false),
        );
    _pendingRequest = request;
    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final result = await _lan.submitRemoteSale(request);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(LucideIcons.badgeCheck),
          title: Text('settings.network.sale.completed'.tr()),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(result.invoiceNumber),
              const SizedBox(height: 8),
              Text(
                _money(result.totalCents),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              if (result.duplicate)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('settings.network.sale.safe_retry'.tr()),
                ),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text('common.ok'.tr()),
            ),
          ],
        ),
      );
      setState(() {
        _cart.clear();
        _customer = null;
        _salesperson = null;
        _priceTier = 'retail';
        _notesController.clear();
        _paidController.clear();
        _paidManuallyEdited = false;
        _pendingRequest = null;
        _submitting = false;
      });
      await _loadProducts();
    } on LanBusinessException catch (error) {
      if (error.code == 'sale_below_cost_reason_required') {
        if (mounted) {
          setState(() {
            _submitting = false;
            _error = null;
          });
        }
        final reason = await _requestBelowCostReason();
        if (reason == null || !mounted) return;
        _pendingRequest = request.copyWith(belowCostOverrideReason: reason);
        await _submit();
        return;
      }
      _handleError(error);
    } catch (_) {
      _handleError(
        const LanBusinessException(
          'network_error',
          'The master did not confirm the sale. Retry safely.',
        ),
      );
    }
  }

  Future<String?> _requestBelowCostReason() async {
    final controller = TextEditingController();
    try {
      final result = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(LucideIcons.shieldAlert),
          title: Text('settings.network.sale.below_cost_reason_title'.tr()),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('settings.network.sale.below_cost_reason_message'.tr()),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'settings.network.sale.below_cost_reason_hint'
                      .tr(),
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text('common.cancel'.tr()),
            ),
            FilledButton(
              onPressed: () {
                final reason = controller.text.trim();
                if (reason.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'settings.network.sale.below_cost_reason_required'.tr(),
                      ),
                    ),
                  );
                  return;
                }
                Navigator.pop(dialogContext, reason);
              },
              child: Text('settings.network.sale.below_cost_approve'.tr()),
            ),
          ],
        ),
      );
      await Future<void>.delayed(kThemeAnimationDuration);
      return result;
    } finally {
      controller.dispose();
    }
  }

  String _money(int cents) {
    final symbol = _catalog?.currencySymbol ?? '';
    return '$symbol${(cents / 100).toStringAsFixed(2)}';
  }

  String _quantityLabel(int stored, LanCatalogProduct product) {
    final type = MeasurementType.fromDb(product.measurementType);
    return '${MeasuredQuantity.majorValue(stored, type)} ${_unitLabel(type.majorUnit)}';
  }

  String _unitLabel(MeasurementUnit unit) {
    return 'measurement.units.${unit.dbValue}'.tr();
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final catalog = _catalog;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leaveSale();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            onPressed: _leaveSale,
            tooltip: 'settings.network.sale.back_to_shift'.tr(),
            icon: const Icon(LucideIcons.arrowLeft),
          ),
          title: Text('settings.network.sale.title'.tr()),
          actions: [
            const ThemeToggleButton(lightDarkOnly: true),
            IconButton(
              onPressed: _showCartDialog,
              tooltip: 'settings.network.sale.open_cart'.tr(),
              icon: Badge(
                isLabelVisible: _cart.isNotEmpty,
                label: Text(_cart.length.toString()),
                child: const Icon(LucideIcons.shoppingCart),
              ),
            ),
            IconButton(
              onPressed: _loading ? null : _load,
              icon: const Icon(LucideIcons.refreshCw),
            ),
          ],
        ),
        body: SafeArea(
          child: _loading && catalog == null
              ? const Center(child: CircularProgressIndicator())
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 900;
                    final products = _buildProductsPane();
                    final cart = _buildCartPane();
                    if (wide) {
                      return Row(
                        children: [
                          Expanded(flex: 3, child: products),
                          const VerticalDivider(width: 1),
                          SizedBox(width: 390, child: cart),
                        ],
                      );
                    }
                    return Column(
                      children: [
                        Expanded(child: products),
                        _buildCartLauncher(),
                      ],
                    );
                  },
                ),
        ),
      ),
    );
  }

  Widget _buildProductsPane() {
    final products = _catalog?.products ?? const <LanCatalogProduct>[];
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: SearchBar(
            controller: _searchController,
            leading: const Icon(LucideIcons.search),
            hintText: 'settings.network.sale.search'.tr(),
          ),
        ),
        if (_error != null)
          MaterialBanner(
            content: Text(_error!),
            actions: [
              TextButton(onPressed: _load, child: Text('common.retry'.tr())),
            ],
          ),
        Expanded(
          child: products.isEmpty
              ? Center(child: Text('settings.network.sale.no_products'.tr()))
              : GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 280,
                    mainAxisExtent: 150,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemCount: products.length,
                  itemBuilder: (_, index) {
                    final product = products[index];
                    return Card(
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => _addProduct(product),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              _productImage(product, size: 74),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text(
                                      product.name,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const Spacer(),
                                    Text(
                                      _money(
                                        _priceFor(
                                          product,
                                          null,
                                          tier: _priceTier,
                                        ),
                                      ),
                                      style: TextStyle(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 18,
                                      ),
                                    ),
                                    Text(
                                      "${'settings.network.sale.available'.tr()}: "
                                      '${_quantityLabel(product.stockQuantity, product)}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildCartLauncher() {
    final pricing = _pricing;
    return SafeArea(
      top: false,
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        child: InkWell(
          onTap: _showCartDialog,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            child: Row(
              children: [
                Badge(
                  isLabelVisible: _cart.isNotEmpty,
                  label: Text(_cart.length.toString()),
                  child: const Icon(LucideIcons.shoppingCart, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    _cart.isEmpty
                        ? 'settings.network.sale.empty_cart'.tr()
                        : 'settings.network.sale.open_cart'.tr(),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Text(
                  _money(pricing.total.cents),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(LucideIcons.chevronUp),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCartPane({
    bool inDialog = false,
    VoidCallback? refreshOverlay,
    VoidCallback? onClose,
  }) {
    final pricing = _pricing;
    return Card(
      margin: inDialog ? EdgeInsets.zero : const EdgeInsets.all(10),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          ListTile(
            onTap: inDialog ? null : _showCartDialog,
            leading: const Icon(LucideIcons.shoppingCart),
            title: Text('settings.network.sale.cart'.tr()),
            subtitle: Text(
              'settings.network.sale.cart_items'.tr(
                args: [_cart.length.toString()],
              ),
            ),
            trailing: inDialog
                ? IconButton(
                    onPressed: onClose,
                    tooltip: 'common.close'.tr(),
                    icon: const Icon(LucideIcons.x),
                  )
                : Badge(label: Text(_cart.length.toString())),
          ),
          const Divider(height: 1),
          Expanded(
            flex: 3,
            child: _cart.isEmpty
                ? Center(child: Text('settings.network.sale.empty_cart'.tr()))
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: _cart.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, index) {
                      final line = _cart[index];
                      final linePricing = pricing.lines[index];
                      return ListTile(
                        leading: _productImage(line.product, size: 54),
                        title: Text(
                          line.variant == null
                              ? line.product.name
                              : '${line.product.name} - ${line.variant!.label}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${_quantityLabel(line.quantity, line.product)} x '
                              '${_money(_priceFor(line.product, line.variant, tier: line.priceTier))} | '
                              '${'settings.network.sale.price_${line.priceTier}'.tr()}',
                            ),
                            if (linePricing.totalLineDiscount.cents > 0)
                              Text(
                                '${'settings.network.sale.item_discount'.tr()}: '
                                '-${_money(linePricing.totalLineDiscount.cents)}',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.tertiary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            if (_catalog?.allowDiscounts == true)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: OutlinedButton.icon(
                                  onPressed: () async {
                                    await _editDiscount(index);
                                    refreshOverlay?.call();
                                  },
                                  icon: const Icon(
                                    LucideIcons.percent,
                                    size: 16,
                                  ),
                                  label: Text(
                                    linePricing.totalLineDiscount.cents > 0
                                        ? '${'settings.network.sale.item_discount'.tr()} '
                                              '(-${_money(linePricing.totalLineDiscount.cents)})'
                                        : 'settings.network.sale.item_discount'
                                              .tr(),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        onTap: () async {
                          await _editQuantity(index);
                          refreshOverlay?.call();
                        },
                        trailing: IconButton(
                          tooltip: 'common.delete'.tr(),
                          icon: const Icon(LucideIcons.trash2),
                          onPressed: () async {
                            final confirmed = await confirmInvoiceLineRemoval(
                              context,
                              itemName: line.product.name,
                            );
                            if (!confirmed || !mounted) return;
                            setState(() {
                              _cart.removeAt(index);
                              _invalidatePendingRequest();
                            });
                            refreshOverlay?.call();
                          },
                        ),
                      );
                    },
                  ),
          ),
          const Divider(height: 1),
          Expanded(
            flex: 4,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  DropdownButtonFormField<LanCustomerSummary?>(
                    initialValue: _customer,
                    decoration: InputDecoration(
                      labelText: 'settings.network.sale.customer'.tr(),
                      prefixIcon: const Icon(LucideIcons.user),
                    ),
                    items: [
                      DropdownMenuItem<LanCustomerSummary?>(
                        value: null,
                        child: Text('settings.network.sale.walk_in'.tr()),
                      ),
                      ..._customers.map(
                        (value) => DropdownMenuItem<LanCustomerSummary?>(
                          value: value,
                          child: Text(value.name),
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _customer = value;
                        _invalidatePendingRequest();
                      });
                      refreshOverlay?.call();
                    },
                  ),
                  const SizedBox(height: 10),
                  SegmentedButton<String>(
                    segments: [
                      ButtonSegment(
                        value: 'retail',
                        label: Text('settings.network.sale.price_retail'.tr()),
                      ),
                      ButtonSegment(
                        value: 'wholesale',
                        label: Text(
                          'settings.network.sale.price_wholesale'.tr(),
                        ),
                      ),
                    ],
                    selected: {_priceTier},
                    onSelectionChanged: (values) {
                      setState(() {
                        _priceTier = values.first;
                        _invalidatePendingRequest();
                      });
                      refreshOverlay?.call();
                    },
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<LanEmployeeSummary?>(
                    initialValue: _salesperson,
                    decoration: InputDecoration(
                      labelText: 'sales.salesperson'.tr(),
                      prefixIcon: const Icon(LucideIcons.badge),
                    ),
                    items: [
                      DropdownMenuItem<LanEmployeeSummary?>(
                        value: null,
                        child: Text('sales.select_salesperson'.tr()),
                      ),
                      ..._salespeople.map(
                        (value) => DropdownMenuItem<LanEmployeeSummary?>(
                          value: value,
                          child: Text(value.name),
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _salesperson = value;
                        _invalidatePendingRequest();
                      });
                      refreshOverlay?.call();
                    },
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: _paymentMethod,
                    decoration: InputDecoration(
                      labelText: 'settings.network.sale.payment'.tr(),
                      prefixIcon: const Icon(LucideIcons.walletCards),
                    ),
                    items: const ['cash', 'card', 'credit', 'cheque']
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(
                              'settings.network.sale.payment_$value'.tr(),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      setState(() {
                        _paymentMethod = value ?? 'cash';
                        _paidController.clear();
                        _paidManuallyEdited = false;
                        _invalidatePendingRequest();
                      });
                      refreshOverlay?.call();
                    },
                  ),
                  if (_paymentMethod == 'cash') ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: _paidController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'settings.network.sale.paid'.tr(),
                        prefixIcon: const Icon(LucideIcons.banknote),
                      ),
                      onChanged: (_) {
                        _paidManuallyEdited = true;
                        _pendingRequest = null;
                      },
                    ),
                  ],
                  const SizedBox(height: 10),
                  TextField(
                    controller: _notesController,
                    decoration: InputDecoration(
                      labelText: 'settings.network.sale.notes'.tr(),
                      prefixIcon: const Icon(LucideIcons.fileText),
                    ),
                    onChanged: (_) => _pendingRequest = null,
                  ),
                  const SizedBox(height: 12),
                  _TotalRow(
                    label: 'settings.network.sale.subtotal'.tr(),
                    value: _money(pricing.subtotal.cents),
                  ),
                  if (pricing.totalDiscount.cents > 0)
                    _TotalRow(
                      label: 'settings.network.sale.discount'.tr(),
                      value: '-${_money(pricing.totalDiscount.cents)}',
                    ),
                  _TotalRow(
                    label: 'settings.network.sale.tax'.tr(),
                    value: _money(pricing.tax.cents),
                  ),
                  _TotalRow(
                    label: 'settings.network.sale.total'.tr(),
                    value: _money(pricing.total.cents),
                    emphasized: true,
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _cart.isEmpty || _submitting
                          ? null
                          : () async {
                              await _submit();
                              refreshOverlay?.call();
                            },
                      icon: _submitting
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(LucideIcons.check),
                      label: Text('settings.network.sale.complete'.tr()),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DiscountEditResult {
  final String type;
  final int value;

  const _DiscountEditResult(this.type, this.value);
}

class _RemoteCartLine {
  final LanCatalogProduct product;
  final LanCatalogVariant? variant;
  final int quantity;
  final String priceTier;
  final String discountType;
  final int discountValue;

  const _RemoteCartLine({
    required this.product,
    this.variant,
    required this.quantity,
    this.priceTier = 'retail',
    this.discountType = 'none',
    this.discountValue = 0,
  });

  Discount get discount => switch (discountType) {
    'fixed' => Discount.fixed(Money.fromCents(discountValue)),
    'percentage' => Discount.percent(discountValue),
    _ => Discount.none,
  };

  _RemoteCartLine copyWith({
    int? quantity,
    String? priceTier,
    String? discountType,
    int? discountValue,
  }) {
    return _RemoteCartLine(
      product: product,
      variant: variant,
      quantity: quantity ?? this.quantity,
      priceTier: priceTier ?? this.priceTier,
      discountType: discountType ?? this.discountType,
      discountValue: discountValue ?? this.discountValue,
    );
  }
}

class _TotalRow extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasized;

  const _TotalRow({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  @override
  Widget build(BuildContext context) {
    final style = emphasized
        ? Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)
        : Theme.of(context).textTheme.bodyLarge;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style),
        ],
      ),
    );
  }
}
