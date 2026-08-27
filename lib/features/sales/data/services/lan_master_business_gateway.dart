import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/daos/adjustment_return_dao.dart';
import '../../../../core/measurement/measurement.dart';
import '../../../../core/money/money.dart';
import '../../../../core/pricing/discount.dart';
import '../../../../core/pricing/invoice_pricing_engine.dart';
import '../../../../core/pricing/line_item_pricing_engine.dart';
import '../../../../core/pricing/pricing_snapshot.dart';
import '../../../../core/services/cashier_shift_service.dart';
import '../../../../core/services/currency_service.dart' show CurrencyService;
import '../../../../core/services/commissions/commission_service.dart';
import '../../../../core/services/journal_entry_service.dart';
import '../../../../core/services/loyalty/loyalty_points_service.dart';
import '../../../../core/services/lan/lan_business_models.dart';
import '../../../../core/services/lan/lan_models.dart';
import '../../../settings/data/services/app_settings_service.dart';
import '../../domain/repositories/sale_repository.dart';

class LanMasterBusinessGatewayImpl implements LanMasterBusinessGateway {
  final AppDatabase _database;
  final SaleRepository _sales;
  final AppSettingsService _settings;
  final CashierShiftService _shifts;
  final CurrencyService _currencyService;
  final AdjustmentReturnDao _adjustmentReturns;
  final JournalEntryService _journalEntries;
  final CommissionService _commissions;
  final LoyaltyPointsService _loyaltyPoints;

  const LanMasterBusinessGatewayImpl({
    required AppDatabase database,
    required SaleRepository sales,
    required AppSettingsService settings,
    required CashierShiftService shifts,
    required CurrencyService currencyService,
    required AdjustmentReturnDao adjustmentReturns,
    required JournalEntryService journalEntries,
    required CommissionService commissions,
    required LoyaltyPointsService loyaltyPoints,
  }) : _database = database,
       _sales = sales,
       _settings = settings,
       _shifts = shifts,
       _currencyService = currencyService,
       _adjustmentReturns = adjustmentReturns,
       _journalEntries = journalEntries,
       _commissions = commissions,
       _loyaltyPoints = loyaltyPoints;

  @override
  Future<LanCatalogPage> fetchCatalog({
    required String query,
    required int offset,
    required int limit,
  }) async {
    final safeOffset = offset.clamp(0, 1000000);
    final safeLimit = limit.clamp(1, 200);
    final normalized = query.trim();
    final statement = _database.select(_database.products)
      ..where((row) {
        var expression = row.isActive.equals(true);
        if (normalized.isNotEmpty) {
          final pattern = '%$normalized%';
          expression =
              expression &
              (row.name.like(pattern) |
                  row.sku.like(pattern) |
                  row.barcode.like(pattern));
        }
        return expression;
      })
      ..orderBy([(row) => OrderingTerm.asc(row.name)])
      ..limit(safeLimit + 1, offset: safeOffset);
    final rows = await statement.get();
    final hasMore = rows.length > safeLimit;
    final pageRows = rows.take(safeLimit).toList(growable: false);
    final productIds = pageRows.map((row) => row.id).toList(growable: false);

    final variants = productIds.isEmpty
        ? <ProductVariant>[]
        : await (_database.select(_database.productVariants)
                ..where(
                  (row) =>
                      row.productId.isIn(productIds) &
                      row.isActive.equals(true),
                )
                ..orderBy([(row) => OrderingTerm.asc(row.id)]))
              .get();
    final colors = await _database.select(_database.productColors).get();
    final sizes = await _database.select(_database.sizes).get();
    final colorNames = {for (final value in colors) value.id: value.name};
    final colorHexes = {for (final value in colors) value.id: value.hexCode};
    final sizeNames = {for (final value in sizes) value.id: value.name};

    final variantsByProduct = <int, List<LanCatalogVariant>>{};
    for (final variant in variants) {
      variantsByProduct
          .putIfAbsent(variant.productId, () => [])
          .add(
            LanCatalogVariant(
              id: variant.id,
              productId: variant.productId,
              sku: variant.sku,
              barcode: variant.barcode,
              colorName: variant.colorId == null
                  ? null
                  : colorNames[variant.colorId],
              colorHex: variant.colorId == null
                  ? null
                  : colorHexes[variant.colorId],
              sizeName: variant.sizeId == null
                  ? null
                  : sizeNames[variant.sizeId],
              priceCents: _cents(variant.priceCents),
              wholesalePriceCents: variant.wholesalePriceCents == null
                  ? null
                  : _cents(variant.wholesalePriceCents!),
              stockQuantity: variant.stockQuantity,
            ),
          );
    }

    final appSettings = _settings.current;
    final currency = await _selectedCurrency();

    return LanCatalogPage(
      products: pageRows
          .map(
            (product) => LanCatalogProduct(
              id: product.id,
              name: product.name,
              sku: product.sku,
              barcode: product.barcode,
              priceCents: _cents(product.priceCents),
              wholesalePriceCents: product.wholesalePriceCents == null
                  ? null
                  : _cents(product.wholesalePriceCents!),
              stockQuantity: product.stockQuantity,
              hasVariants: product.hasVariants,
              isTaxable: product.isTaxable,
              salesTaxRateBps: product.salesTaxRateBps,
              trackInventory: product.trackInventory,
              measurementType: product.measurementType,
              quantityScale: MeasurementType.fromDb(
                product.measurementType,
              ).quantityScale,
              hasImage: product.imagePath?.trim().isNotEmpty == true,
              variants: variantsByProduct[product.id] ?? const [],
              nameAr: product.nameAr,
              nameFr: product.nameFr,
              description: product.description,
              costCents: _cents(product.costCents),
              lastPurchasePriceCents: product.lastPurchasePriceCents == null
                  ? null
                  : _cents(product.lastPurchasePriceCents!),
              minQuantity: product.minQuantity,
              categoryId: product.categoryId,
              supplierId: product.supplierId,
              currencyId: product.currencyId,
              purchaseTaxRateBps: product.purchaseTaxRateBps,
              isActive: product.isActive,
              costingMethod: product.costingMethod,
              inventoryTrackingType: product.inventoryTrackingType,
            ),
          )
          .toList(growable: false),
      offset: safeOffset,
      limit: safeLimit,
      hasMore: hasMore,
      currencyId: currency?.id ?? 1,
      currencyCode: _currencyService.currencyCode,
      currencySymbol: _currencyService.currencySymbol,
      enableTaxCalculations: appSettings.enableTaxCalculations,
      defaultSalesTaxRateBps: (appSettings.defaultSalesTaxRate * 100).round(),
      taxInclusivePricing: appSettings.taxInclusivePricing,
      allowNegativeStock: appSettings.allowNegativeStock,
      allowPartialPayments: appSettings.allowPartialPayments,
      requireCustomerForSales: appSettings.requireCustomerForSales,
      allowDiscounts: appSettings.allowDiscounts,
      maxDiscountPercent: appSettings.maxDiscountPercent,
    );
  }

  @override
  Future<String?> resolveProductImagePath({required int productId}) async {
    final product =
        await (_database.select(_database.products)
              ..where(
                (row) => row.id.equals(productId) & row.isActive.equals(true),
              )
              ..limit(1))
            .getSingleOrNull();
    final path = product?.imagePath?.trim();
    return path == null || path.isEmpty ? null : path;
  }

  @override
  Future<List<LanCustomerSummary>> fetchCustomers({
    required String query,
    required int limit,
  }) async {
    final normalized = query.trim();
    final safeLimit = limit.clamp(1, 200);
    final statement = _database.select(_database.customers)
      ..where((row) {
        var expression = row.isActive.equals(true);
        if (normalized.isNotEmpty) {
          final pattern = '%$normalized%';
          expression =
              expression &
              (row.name.like(pattern) |
                  row.phone.like(pattern) |
                  row.email.like(pattern));
        }
        return expression;
      })
      ..orderBy([(row) => OrderingTerm.asc(row.name)])
      ..limit(safeLimit);
    final rows = await statement.get();
    return rows
        .map(
          (row) => LanCustomerSummary(
            id: row.id,
            name: row.name,
            phone: row.phone,
            segment: row.segment,
            balanceCents: _cents(row.balanceCents),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<List<LanEmployeeSummary>> fetchSalespeople({
    required String query,
    required int limit,
  }) async {
    final normalized = query.trim();
    final statement = _database.select(_database.employees)
      ..where((row) {
        var expression = row.isActive.equals(true);
        if (normalized.isNotEmpty) {
          final pattern = '%$normalized%';
          expression =
              expression &
              (row.name.like(pattern) |
                  row.employeeCode.like(pattern) |
                  row.phone.like(pattern));
        }
        return expression;
      })
      ..orderBy([(row) => OrderingTerm.asc(row.name)])
      ..limit(limit.clamp(1, 200));
    final rows = await statement.get();
    return rows
        .map(
          (row) => LanEmployeeSummary(
            id: row.id,
            name: row.name,
            position: row.position,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<LanCashierShiftSnapshot?> getOwnShift({
    required LanRemoteUser actor,
  }) async {
    final view = await _shifts.getOpenShiftForUser(actor.id);
    return view == null ? null : await _shiftSnapshot(view);
  }

  @override
  Future<LanCashierShiftSnapshot> openOwnShift({
    required LanRemoteUser actor,
    required int openingCashCents,
    String? notes,
  }) async {
    _requireCashierEmployee(actor);
    try {
      final view = await _shifts.openShift(
        userId: actor.id,
        openingCashCents: openingCashCents,
        notes: notes,
      );
      return _shiftSnapshot(view);
    } on StateError catch (error) {
      throw LanBusinessException(
        'shift_open_failed',
        error.message.toString(),
        statusCode: 409,
      );
    }
  }

  @override
  Future<LanCashierShiftSnapshot> closeOwnShift({
    required LanRemoteUser actor,
    required int countedCashCents,
    String? notes,
  }) async {
    _requireCashierEmployee(actor);
    final view = await _shifts.getOpenShiftForUser(actor.id);
    if (view == null) {
      throw const LanBusinessException(
        'cashier_shift_required',
        'This cashier has no open shift.',
        statusCode: 409,
      );
    }
    try {
      await _shifts.closeShift(
        shiftId: view.shift.id,
        closedByUserId: actor.id,
        countedClosingCashCents: countedCashCents,
        notes: notes,
      );
      final closed = await _shifts.getShift(view.shift.id);
      return _shiftSnapshot(closed!);
    } on StateError catch (error) {
      throw LanBusinessException(
        'shift_close_failed',
        error.message.toString(),
        statusCode: 409,
      );
    }
  }

  @override
  Future<LanReturnableSalesPage> fetchReturnableSales({
    required String query,
    required int offset,
    required int limit,
  }) async {
    final safeOffset = offset.clamp(0, 1000000);
    final safeLimit = limit.clamp(1, 100);
    final normalized = query.trim();
    final statement =
        _database.select(_database.sales).join([
            innerJoin(
              _database.saleItems,
              _database.saleItems.saleId.equalsExp(_database.sales.id),
            ),
            innerJoin(
              _database.products,
              _database.products.id.equalsExp(_database.saleItems.productId),
            ),
            leftOuterJoin(
              _database.productVariants,
              _database.productVariants.id.equalsExp(
                _database.saleItems.variantId,
              ),
            ),
            leftOuterJoin(
              _database.customers,
              _database.customers.id.equalsExp(_database.sales.customerId),
            ),
            innerJoin(
              _database.currencies,
              _database.currencies.id.equalsExp(_database.sales.currencyId),
            ),
          ])
          ..where(_database.sales.status.equals('completed'))
          ..orderBy([
            OrderingTerm.desc(_database.sales.saleDate),
            OrderingTerm.desc(_database.sales.id),
          ]);
    if (normalized.isNotEmpty) {
      final pattern = '%$normalized%';
      statement.where(
        _database.sales.invoiceNumber.like(pattern) |
            _database.customers.name.like(pattern) |
            _database.products.name.like(pattern) |
            _database.products.sku.like(pattern) |
            _database.products.barcode.like(pattern) |
            _database.productVariants.sku.like(pattern) |
            _database.productVariants.barcode.like(pattern),
      );
    }

    final rows = await statement.get();
    final summaries = <int, LanReturnableSaleSummary>{};
    for (final row in rows) {
      final item = row.readTable(_database.saleItems);
      final returned = item.qtyReturnedLinked + item.qtyReturnedAdjustment;
      if (item.quantity <= returned) continue;

      final sale = row.readTable(_database.sales);
      final customer = row.readTableOrNull(_database.customers);
      final currency = row.readTable(_database.currencies);
      final current = summaries[sale.id];
      summaries[sale.id] = LanReturnableSaleSummary(
        saleId: sale.id,
        invoiceNumber: sale.invoiceNumber,
        customerName: customer?.name,
        saleDate: sale.saleDate,
        totalCents: _cents(sale.totalCents),
        paymentMethod: sale.paymentMethod,
        currencyCode: currency.code,
        currencySymbol: currency.symbol,
        currencyId: currency.id,
        taxInclusiveAtPost: sale.taxInclusiveAtPost ?? false,
        returnableLineCount: (current?.returnableLineCount ?? 0) + 1,
      );
    }

    final pageRows = summaries.values
        .skip(safeOffset)
        .take(safeLimit + 1)
        .toList(growable: false);
    return LanReturnableSalesPage(
      sales: pageRows.take(safeLimit).toList(growable: false),
      offset: safeOffset,
      limit: safeLimit,
      hasMore: pageRows.length > safeLimit,
    );
  }

  @override
  Future<LanReturnableSaleDetails?> fetchReturnableSale({
    required int saleId,
  }) async {
    if (saleId <= 0) return null;
    final sale =
        await (_database.select(_database.sales)
              ..where(
                (row) => row.id.equals(saleId) & row.status.equals('completed'),
              )
              ..limit(1))
            .getSingleOrNull();
    if (sale == null) return null;

    final customer = sale.customerId == null
        ? null
        : await (_database.select(_database.customers)
                ..where((row) => row.id.equals(sale.customerId!))
                ..limit(1))
              .getSingleOrNull();
    final currency =
        await (_database.select(_database.currencies)
              ..where((row) => row.id.equals(sale.currencyId))
              ..limit(1))
            .getSingleOrNull();
    if (currency == null) return null;

    final itemRows = await (_database.select(_database.saleItems).join([
      innerJoin(
        _database.products,
        _database.products.id.equalsExp(_database.saleItems.productId),
      ),
      leftOuterJoin(
        _database.productVariants,
        _database.productVariants.id.equalsExp(_database.saleItems.variantId),
      ),
      leftOuterJoin(
        _database.productColors,
        _database.productColors.id.equalsExp(_database.productVariants.colorId),
      ),
      leftOuterJoin(
        _database.sizes,
        _database.sizes.id.equalsExp(_database.productVariants.sizeId),
      ),
    ])..where(_database.saleItems.saleId.equals(saleId))).get();

    final lines = <LanReturnableSaleLine>[];
    for (final row in itemRows) {
      final item = row.readTable(_database.saleItems);
      final returned = item.qtyReturnedLinked + item.qtyReturnedAdjustment;
      final available = item.quantity - returned;
      if (available <= 0) continue;
      final product = row.readTable(_database.products);
      final variant = row.readTableOrNull(_database.productVariants);
      final linkedHistory = await _sales.getLinkedReturnHistory(item.id);
      lines.add(
        LanReturnableSaleLine(
          saleItemId: item.id,
          productId: item.productId,
          variantId: item.variantId,
          productName: product.name,
          variantSku: variant?.sku,
          colorName: row.readTableOrNull(_database.productColors)?.name,
          sizeName: row.readTableOrNull(_database.sizes)?.name,
          originalQuantity: item.quantity,
          returnedQuantity: returned,
          availableQuantity: available,
          quantityScale: item.quantityScale,
          measurementType: item.measurementType,
          unitPriceCents: _cents(item.unitPriceCents),
          subtotalCents: _cents(item.subtotalCents),
          discountCents: _cents(item.discountCents),
          taxCents: _cents(item.taxCents),
          totalCents: _cents(item.totalCents),
          linkedReturnedQuantity: linkedHistory.quantity,
          linkedReturnedSubtotalCents: linkedHistory.subtotalCents,
          linkedReturnedDiscountCents: linkedHistory.discountCents,
          linkedReturnedTaxCents: linkedHistory.taxCents,
          linkedReturnedRefundCents: linkedHistory.refundCents,
        ),
      );
    }
    if (lines.isEmpty) return null;

    return LanReturnableSaleDetails(
      sale: LanReturnableSaleSummary(
        saleId: sale.id,
        invoiceNumber: sale.invoiceNumber,
        customerName: customer?.name,
        saleDate: sale.saleDate,
        totalCents: _cents(sale.totalCents),
        paymentMethod: sale.paymentMethod,
        currencyCode: currency.code,
        currencySymbol: currency.symbol,
        currencyId: currency.id,
        taxInclusiveAtPost: sale.taxInclusiveAtPost ?? false,
        returnableLineCount: lines.length,
      ),
      lines: lines,
    );
  }

  @override
  Future<LanSaleReturnsPage> fetchSaleReturns({
    required String query,
    required int offset,
    required int limit,
  }) async {
    final safeOffset = offset.clamp(0, 1000000);
    final safeLimit = limit.clamp(1, 200);
    final normalized = query.trim().toLowerCase();
    final all = await _sales.watchAllSaleReturns().first;
    final filtered = normalized.isEmpty
        ? all
        : all
              .where(
                (value) =>
                    value.returnNumber.toLowerCase().contains(normalized) ||
                    (value.saleInvoiceNumber?.toLowerCase().contains(
                          normalized,
                        ) ??
                        false) ||
                    (value.customerName?.toLowerCase().contains(normalized) ??
                        false) ||
                    (value.customerPhone?.toLowerCase().contains(normalized) ??
                        false),
              )
              .toList(growable: false);
    final pageRows = filtered
        .skip(safeOffset)
        .take(safeLimit + 1)
        .toList(growable: false);
    return LanSaleReturnsPage(
      returns: pageRows
          .take(safeLimit)
          .map(
            (value) => LanSaleReturnSummary(
              id: value.id,
              saleId: value.saleId,
              saleInvoiceNumber: value.saleInvoiceNumber,
              customerName: value.customerName,
              customerPhone: value.customerPhone,
              customerId: value.customerId,
              returnNumber: value.returnNumber,
              subtotalCents: value.subtotalCents.toBigInt().toInt(),
              discountCents: value.discountCents.toBigInt().toInt(),
              taxCents: value.taxCents.toBigInt().toInt(),
              totalCents: value.totalCents.toBigInt().toInt(),
              currencyId: value.currencyId,
              status: value.status,
              dispositionType: value.dispositionType,
              refundMethod: value.refundMethod,
              reason: value.reason,
              returnDate: value.returnDate,
              createdAt: value.createdAt,
              isAdjustment: value.isAdjustment,
              unifiedId: value.unifiedId,
            ),
          )
          .toList(growable: false),
      offset: safeOffset,
      limit: safeLimit,
      hasMore: pageRows.length > safeLimit,
    );
  }

  @override
  Future<LanSaleReturnResult> createSaleReturn({
    required LanRemoteUser actor,
    required LanSaleReturnRequest request,
  }) async {
    final key = request.idempotencyKey.trim();
    if (key.isEmpty || key.length > 120) {
      throw const LanBusinessException(
        'invalid_idempotency_key',
        'A valid request identity is required.',
      );
    }
    if (request.saleId <= 0 || request.lines.isEmpty) {
      throw const LanBusinessException(
        'invalid_sale_return',
        'The sale and at least one return line are required.',
      );
    }
    const refundMethods = {'cash', 'card', 'credit', 'cheque'};
    if (!refundMethods.contains(request.refundMethod)) {
      throw const LanBusinessException(
        'invalid_refund_method',
        'Unsupported refund method.',
      );
    }
    const dispositions = {'restock', 'damaged', 'write_off'};
    if (!dispositions.contains(request.dispositionType)) {
      throw const LanBusinessException(
        'invalid_disposition',
        'Unsupported return disposition.',
      );
    }
    if (request.refundMethod == 'cheque' && request.dueDate == null) {
      throw const LanBusinessException(
        'cheque_due_date_required',
        'A cheque due date is required.',
      );
    }

    if (actor.role == 'cashier') {
      _requireCashierEmployee(actor);
      final shift = await getOwnShift(actor: actor);
      if (shift == null || !shift.isOpen) {
        throw const LanBusinessException(
          'cashier_shift_required',
          'Open your cashier shift before processing a return.',
          statusCode: 409,
        );
      }
    }

    final existing =
        await (_database.select(_database.saleReturns)
              ..where((row) => row.idempotencyKey.equals(key))
              ..limit(1))
            .getSingleOrNull();
    if (existing != null) {
      return LanSaleReturnResult(
        returnId: existing.id,
        returnNumber: existing.returnNumber,
        totalCents: _cents(existing.totalCents),
        duplicate: true,
      );
    }

    final details = await fetchReturnableSale(saleId: request.saleId);
    if (details == null) {
      throw const LanBusinessException(
        'sale_not_returnable',
        'The sale was not found or has no returnable items.',
        statusCode: 409,
      );
    }
    final availableById = {
      for (final line in details.lines) line.saleItemId: line,
    };
    final seen = <int>{};
    final items = <SaleReturnItemInput>[];
    for (final requested in request.lines) {
      final source = availableById[requested.saleItemId];
      if (source == null ||
          requested.quantity <= 0 ||
          requested.quantity > source.availableQuantity ||
          !seen.add(requested.saleItemId)) {
        throw const LanBusinessException(
          'invalid_return_quantity',
          'A return line is invalid or exceeds the available quantity.',
          statusCode: 409,
        );
      }
      // The client sends quantities and reasons only. The repository rebuilds
      // every monetary value from the original invoice snapshot on the master.
      items.add(
        SaleReturnItemInput(
          saleItemId: requested.saleItemId,
          quantity: requested.quantity,
          quantityScale: source.quantityScale,
          measurementType: source.measurementType,
          subtotalCents: Decimal.zero,
          discountCents: Decimal.zero,
          taxCents: Decimal.zero,
          refundCents: Decimal.zero,
          reason: requested.reason,
        ),
      );
    }

    final returnId = await _sales.createSaleReturn(
      saleId: request.saleId,
      currencyId: details.sale.currencyId,
      subtotalCents: Decimal.zero,
      discountCents: Decimal.zero,
      taxCents: Decimal.zero,
      totalCents: Decimal.zero,
      items: items,
      reason: request.reason,
      dispositionType: request.dispositionType,
      refundMethod: request.refundMethod,
      returnDate: DateTime.now(),
      dueDate: request.dueDate,
      idempotencyKey: key,
      actorUserId: actor.id,
      taxInclusiveAtPost: details.sale.taxInclusiveAtPost,
    );
    final created =
        await (_database.select(_database.saleReturns)
              ..where((row) => row.id.equals(returnId))
              ..limit(1))
            .getSingle();
    return LanSaleReturnResult(
      returnId: created.id,
      returnNumber: created.returnNumber,
      totalCents: _cents(created.totalCents),
    );
  }

  @override
  Future<LanSaleReturnResult> createSaleAdjustmentReturn({
    required LanRemoteUser actor,
    required LanSaleAdjustmentReturnRequest request,
  }) async {
    final key = request.idempotencyKey.trim();
    if (key.length < 8 || key.length > 128) {
      throw const LanBusinessException(
        'invalid_idempotency_key',
        'Invalid request identity.',
      );
    }
    if (request.lines.isEmpty || request.lines.length > 200) {
      throw const LanBusinessException(
        'invalid_lines',
        'A return must contain between 1 and 200 lines.',
      );
    }
    const refundMethods = {'cash', 'card', 'credit', 'cheque'};
    if (!refundMethods.contains(request.refundMethod)) {
      throw const LanBusinessException(
        'invalid_refund_method',
        'Unsupported refund method.',
      );
    }
    if (request.refundMethod == 'cheque' && request.dueDate == null) {
      throw const LanBusinessException(
        'cheque_due_date_required',
        'A cheque due date is required.',
      );
    }
    const reasons = {
      'damaged',
      'defective',
      'wrongItem',
      'gift',
      'goodwill',
      'noReceipt',
      'other',
    };
    if (!reasons.contains(request.reasonCode)) {
      throw const LanBusinessException(
        'return_reason_required',
        'A valid return reason is required.',
      );
    }

    final existing =
        await (_database.select(_database.saleReturnAdjustments)
              ..where((row) => row.idempotencyKey.equals(key))
              ..limit(1))
            .getSingleOrNull();
    if (existing != null) {
      return LanSaleReturnResult(
        returnId: existing.id,
        returnNumber: existing.returnNumber,
        totalCents: _cents(existing.totalCents),
        duplicate: true,
      );
    }

    if (actor.role == 'cashier') {
      _requireCashierEmployee(actor);
      final openShift = await _shifts.getOpenShiftForUser(actor.id);
      if (openShift == null) {
        throw const LanBusinessException(
          'cashier_shift_required',
          'Open your cashier shift before processing a return.',
          statusCode: 409,
        );
      }
    }

    Customer? customer;
    if (request.customerId != null) {
      customer =
          await (_database.select(_database.customers)
                ..where((row) => row.id.equals(request.customerId!))
                ..limit(1))
              .getSingleOrNull();
      if (customer == null || !customer.isActive) {
        throw const LanBusinessException(
          'customer_unavailable',
          'The selected customer is unavailable.',
          statusCode: 409,
        );
      }
    }
    if ((request.refundMethod == 'credit' ||
            request.refundMethod == 'cheque') &&
        customer == null) {
      throw const LanBusinessException(
        'customer_required_for_credit',
        'Credit and cheque returns require a customer.',
      );
    }

    if (request.employeeId != null) {
      final employee =
          await (_database.select(_database.employees)
                ..where(
                  (row) =>
                      row.id.equals(request.employeeId!) &
                      row.isActive.equals(true),
                )
                ..limit(1))
              .getSingleOrNull();
      if (employee == null) {
        throw const LanBusinessException(
          'salesperson_unavailable',
          'The selected salesperson is unavailable.',
          statusCode: 409,
        );
      }
    }

    final productIds = request.lines
        .map((line) => line.productId)
        .toSet()
        .toList(growable: false);
    final products = await (_database.select(
      _database.products,
    )..where((row) => row.id.isIn(productIds))).get();
    final productMap = {for (final value in products) value.id: value};
    final variantIds = request.lines
        .map((line) => line.variantId)
        .whereType<int>()
        .toSet()
        .toList(growable: false);
    final variants = variantIds.isEmpty
        ? <ProductVariant>[]
        : await (_database.select(
            _database.productVariants,
          )..where((row) => row.id.isIn(variantIds))).get();
    final variantMap = {for (final value in variants) value.id: value};

    final pricingInputs = <LineItemPricingInput>[];
    final resolved =
        <
          ({
            LanSaleAdjustmentReturnLineRequest request,
            Product product,
            ProductVariant? variant,
            int quantityScale,
            int taxRateBps,
          })
        >[];
    const dispositions = {'restock', 'damaged', 'scrap'};
    for (final line in request.lines) {
      final product = productMap[line.productId];
      if (product == null || !product.isActive) {
        throw const LanBusinessException(
          'product_unavailable',
          'A selected product is unavailable.',
          statusCode: 409,
        );
      }
      ProductVariant? variant;
      if (line.variantId != null) {
        variant = variantMap[line.variantId];
        if (variant == null ||
            !variant.isActive ||
            variant.productId != product.id) {
          throw const LanBusinessException(
            'variant_unavailable',
            'A selected product variant is unavailable.',
            statusCode: 409,
          );
        }
      } else if (product.hasVariants) {
        throw const LanBusinessException(
          'variant_required',
          'Choose a product variant.',
        );
      }
      if (line.quantity <= 0 ||
          line.unitPriceCents < 0 ||
          line.discountCents < 0 ||
          line.discountPercentBps < 0 ||
          line.discountPercentBps > 10000 ||
          (line.discountCents > 0 && line.discountPercentBps > 0)) {
        throw const LanBusinessException(
          'invalid_return_line',
          'A return line contains an invalid quantity, price, or discount.',
        );
      }
      if (!dispositions.contains(line.dispositionType)) {
        throw const LanBusinessException(
          'invalid_disposition',
          'Unsupported return disposition.',
        );
      }
      final quantityScale = MeasurementType.fromDb(
        product.measurementType,
      ).quantityScale;
      final taxRateBps = product.isTaxable ? product.salesTaxRateBps : 0;
      final discount = line.discountPercentBps > 0
          ? Discount.percent(line.discountPercentBps)
          : line.discountCents > 0
          ? Discount.fixed(Money.fromCents(line.discountCents))
          : Discount.none;
      pricingInputs.add(
        LineItemPricingInput(
          unitPrice: Money.fromCents(line.unitPriceCents),
          quantity: line.quantity,
          quantityScale: quantityScale,
          discount: discount,
          isTaxable: product.isTaxable,
          productTaxRateBps: taxRateBps,
        ),
      );
      resolved.add((
        request: line,
        product: product,
        variant: variant,
        quantityScale: quantityScale,
        taxRateBps: taxRateBps,
      ));
    }

    if (request.overallDiscountCents < 0 ||
        (request.overallDiscountIsPercent &&
            request.overallDiscountCents > 10000)) {
      throw const LanBusinessException(
        'invalid_discount',
        'The overall discount is invalid.',
      );
    }
    final appSettings = _settings.current;
    final overallDiscount = request.overallDiscountIsPercent
        ? Discount.percent(request.overallDiscountCents)
        : request.overallDiscountCents > 0
        ? Discount.fixed(Money.fromCents(request.overallDiscountCents))
        : Discount.none;
    final pricing = InvoicePricingEngine.compute(
      InvoicePricingInput(
        lines: pricingInputs,
        overallDiscount: overallDiscount,
        enableTaxCalculations: appSettings.enableTaxCalculations,
        defaultTaxRateBps: (appSettings.defaultSalesTaxRate * 100).round(),
        taxInclusivePricing: appSettings.taxInclusivePricing,
      ),
    );
    if (pricing.totalDiscount.cents > 0 && !appSettings.allowDiscounts) {
      throw const LanBusinessException(
        'discounts_disabled',
        'Discounts are disabled on the master.',
      );
    }

    final currency = await _selectedCurrency();
    if (currency == null) {
      throw const LanBusinessException(
        'currency_unavailable',
        'The master currency is unavailable.',
        statusCode: 409,
      );
    }

    final cleanNotes = request.notes?.trim();
    final taggedNotes =
        '[REASON:${request.reasonCode}]'
        '${cleanNotes == null || cleanNotes.isEmpty ? '' : ' $cleanNotes'}';
    final returnData = SaleReturnAdjustmentsCompanion.insert(
      returnNumber: '',
      customerId: Value(request.customerId),
      employeeId: Value(request.employeeId),
      currencyId: currency.id,
      subtotalCents: Value(Decimal.fromInt(pricing.subtotal.cents)),
      discountCents: Value(Decimal.fromInt(pricing.totalDiscount.cents)),
      taxCents: Value(Decimal.fromInt(pricing.tax.cents)),
      totalCents: Decimal.fromInt(pricing.total.cents),
      notes: Value(taggedNotes),
      returnDate: Value(request.returnDate.toLocal()),
      refundMethod: Value(request.refundMethod),
      dueDate: Value(request.dueDate?.toLocal()),
      idempotencyKey: Value(key),
      returnMode: const Value('auto_adjustment'),
      modeReason: const Value('Remote unlinked sale return'),
    ).withPricingSnapshot(taxInclusive: appSettings.taxInclusivePricing);

    final itemCompanions = <SaleReturnAdjustmentItemsCompanion>[];
    for (var index = 0; index < resolved.length; index++) {
      final value = resolved[index];
      final line = pricing.lines[index];
      itemCompanions.add(
        SaleReturnAdjustmentItemsCompanion.insert(
          returnId: 0,
          productId: value.product.id,
          variantId: Value(value.variant?.id),
          quantity: value.request.quantity,
          quantityScale: Value(value.quantityScale),
          measurementType: Value(value.product.measurementType),
          unitPriceCents: Decimal.fromInt(value.request.unitPriceCents),
          discountCents: Value(Decimal.fromInt(line.totalLineDiscount.cents)),
          taxCents: Value(Decimal.fromInt(line.tax.cents)),
          totalCents: Decimal.fromInt(line.total.cents),
          reason: Value(value.request.reason),
          taxRateBpsAtPost: Value(value.taxRateBps),
          dispositionType: Value(value.request.dispositionType),
        ),
      );
    }

    try {
      final returnId = await _adjustmentReturns.createAndPostSaleAdjReturn(
        returnData,
        itemCompanions,
        journalEntryService: _journalEntries,
        userId: actor.id,
        commissionService: _commissions,
        loyaltyPointsService: _loyaltyPoints,
      );
      final created = await _adjustmentReturns.getSaleAdjReturnById(returnId);
      if (created == null) {
        throw const LanBusinessException(
          'return_creation_failed',
          'The return could not be loaded after posting.',
          statusCode: 500,
        );
      }
      return LanSaleReturnResult(
        returnId: created.id,
        returnNumber: created.returnNumber,
        totalCents: _cents(created.totalCents),
      );
    } on LanBusinessException {
      rethrow;
    } on StateError catch (error) {
      throw LanBusinessException(
        'return_rejected',
        error.message.toString(),
        statusCode: 409,
      );
    } on Exception catch (error) {
      throw LanBusinessException(
        'return_rejected',
        error.toString(),
        statusCode: 409,
      );
    }
  }

  @override
  Future<LanSaleResult> createSale({
    required LanRemoteUser actor,
    required LanSaleRequest request,
  }) async {
    final key = request.idempotencyKey.trim();
    if (key.length < 8 || key.length > 128) {
      throw const LanBusinessException(
        'invalid_idempotency_key',
        'Invalid request identity.',
      );
    }
    if (request.lines.isEmpty || request.lines.length > 200) {
      throw const LanBusinessException(
        'invalid_lines',
        'A sale must contain between 1 and 200 lines.',
      );
    }

    final existing = await (_database.select(
      _database.sales,
    )..where((row) => row.idempotencyKey.equals(key))).getSingleOrNull();
    if (existing != null) {
      return _resultFromSale(existing, duplicate: true);
    }

    if (actor.role == 'cashier') {
      _requireCashierEmployee(actor);
      final openShift = await _shifts.getOpenShiftForUser(actor.id);
      if (openShift == null) {
        throw const LanBusinessException(
          'cashier_shift_required',
          'Open your cashier shift before creating a sale.',
          statusCode: 409,
        );
      }
    }

    const allowedPayments = {'cash', 'card', 'credit', 'cheque'};
    if (!allowedPayments.contains(request.paymentMethod)) {
      throw const LanBusinessException(
        'invalid_payment_method',
        'Unsupported payment method.',
      );
    }

    Customer? customer;
    if (request.customerId != null) {
      customer = await (_database.select(
        _database.customers,
      )..where((row) => row.id.equals(request.customerId!))).getSingleOrNull();
      if (customer == null || !customer.isActive) {
        throw const LanBusinessException(
          'customer_unavailable',
          'The selected customer is unavailable.',
          statusCode: 409,
        );
      }
    }

    final appSettings = _settings.current;
    if (appSettings.requireCustomerForSales && customer == null) {
      throw const LanBusinessException(
        'customer_required',
        'A customer is required for sales.',
      );
    }
    if ((request.paymentMethod == 'credit' ||
            request.paymentMethod == 'cheque') &&
        customer == null) {
      throw const LanBusinessException(
        'customer_required_for_credit',
        'Credit and cheque sales require a customer.',
      );
    }

    final productIds = request.lines
        .map((line) => line.productId)
        .toSet()
        .toList(growable: false);
    final products = await (_database.select(
      _database.products,
    )..where((row) => row.id.isIn(productIds))).get();
    final productMap = {for (final value in products) value.id: value};

    final variantIds = request.lines
        .map((line) => line.variantId)
        .whereType<int>()
        .toSet()
        .toList(growable: false);
    final variants = variantIds.isEmpty
        ? <ProductVariant>[]
        : await (_database.select(
            _database.productVariants,
          )..where((row) => row.id.isIn(variantIds))).get();
    final variantMap = {for (final value in variants) value.id: value};

    final salespersonIds = <int>{
      if (request.salespersonId != null) request.salespersonId!,
      ...request.lines.map((line) => line.salespersonId).whereType<int>(),
    };
    final salespersonRows = salespersonIds.isEmpty
        ? <Employee>[]
        : await (_database.select(_database.employees)..where(
                (row) =>
                    row.id.isIn(salespersonIds.toList()) &
                    row.isActive.equals(true),
              ))
              .get();
    final salespeople = {for (final value in salespersonRows) value.id: value};
    if (salespeople.length != salespersonIds.length) {
      throw const LanBusinessException(
        'salesperson_unavailable',
        'A selected salesperson is unavailable.',
        statusCode: 409,
      );
    }

    final pricingInputs = <LineItemPricingInput>[];
    final resolved = <_ResolvedLanLine>[];

    for (final requested in request.lines) {
      if (requested.quantity <= 0) {
        throw const LanBusinessException(
          'invalid_quantity',
          'Sale quantities must be positive.',
        );
      }
      final product = productMap[requested.productId];
      if (product == null || !product.isActive) {
        throw const LanBusinessException(
          'product_unavailable',
          'A selected product is unavailable.',
          statusCode: 409,
        );
      }

      ProductVariant? variant;
      if (requested.variantId != null) {
        variant = variantMap[requested.variantId];
        if (variant == null ||
            !variant.isActive ||
            variant.productId != product.id) {
          throw const LanBusinessException(
            'variant_unavailable',
            'A selected product variant is unavailable.',
            statusCode: 409,
          );
        }
      } else if (product.hasVariants) {
        throw const LanBusinessException(
          'variant_required',
          'Choose a product variant.',
        );
      }

      final available = variant?.stockQuantity ?? product.stockQuantity;
      if (product.trackInventory &&
          !appSettings.allowNegativeStock &&
          requested.quantity > available) {
        throw LanBusinessException(
          'insufficient_stock',
          'Insufficient stock for ${product.name}.',
          statusCode: 409,
        );
      }

      final retailPrice = variant == null
          ? _cents(product.priceCents)
          : _cents(variant.priceCents);
      final variantWholesale = variant?.wholesalePriceCents;
      final wholesalePrice = variantWholesale != null
          ? _cents(variantWholesale)
          : product.wholesalePriceCents == null
          ? null
          : _cents(product.wholesalePriceCents!);
      if (requested.priceTier != 'retail' &&
          requested.priceTier != 'wholesale') {
        throw const LanBusinessException(
          'invalid_price_tier',
          'Unsupported sale price tier.',
        );
      }
      if (requested.priceTier == 'wholesale' && wholesalePrice == null) {
        throw LanBusinessException(
          'wholesale_price_unavailable',
          'No wholesale price is configured for ${product.name}.',
          statusCode: 409,
        );
      }
      final unitPrice = requested.priceTier == 'wholesale'
          ? wholesalePrice!
          : retailPrice;
      final salespersonId = requested.salespersonId ?? request.salespersonId;
      final salesperson = salespersonId == null
          ? null
          : salespeople[salespersonId];
      final quantityScale = MeasurementType.fromDb(
        product.measurementType,
      ).quantityScale;

      resolved.add(
        _ResolvedLanLine(
          request: requested,
          product: product,
          variant: variant,
          unitPriceCents: unitPrice,
          salesperson: salesperson,
        ),
      );
      final discount = _discountForRequest(requested);
      pricingInputs.add(
        LineItemPricingInput(
          unitPrice: Money.fromCents(unitPrice),
          quantity: requested.quantity,
          quantityScale: quantityScale,
          discount: discount,
          isTaxable: product.isTaxable,
          productTaxRateBps: product.salesTaxRateBps,
        ),
      );
    }

    final pricing = InvoicePricingEngine.compute(
      InvoicePricingInput(
        lines: pricingInputs,
        enableTaxCalculations: appSettings.enableTaxCalculations,
        defaultTaxRateBps: (appSettings.defaultSalesTaxRate * 100).round(),
        taxInclusivePricing: appSettings.taxInclusivePricing,
      ),
    );

    for (var index = 0; index < resolved.length; index++) {
      final value = resolved[index];
      final variantCost = value.variant?.costCents;
      final unitCostCents = _cents(variantCost ?? value.product.costCents);
      if (unitCostCents <= 0) continue;

      final quantityScale = MeasurementType.fromDb(
        value.product.measurementType,
      ).quantityScale;
      final totalCostCents = Money.fromCents(
        unitCostCents,
      ).multiplyRatio(value.request.quantity, quantityScale).round().cents;
      if (pricing.lines[index].adjustedNet.cents < totalCostCents) {
        throw const LanBusinessException(
          'sale_below_cost',
          'The discount would sell an item below its recorded cost.',
          statusCode: 409,
        );
      }
    }

    if (pricing.totalDiscount.cents > 0) {
      if (!appSettings.allowDiscounts) {
        throw const LanBusinessException(
          'discounts_disabled',
          'Discounts are disabled on the master.',
          statusCode: 409,
        );
      }
      final maxBps = (appSettings.maxDiscountPercent * 100).round();
      if (maxBps < 10000 && pricing.subtotal.cents > 0) {
        final actual =
            BigInt.from(pricing.totalDiscount.cents) * BigInt.from(10000);
        final allowed =
            BigInt.from(pricing.subtotal.cents) * BigInt.from(maxBps);
        if (actual > allowed) {
          throw const LanBusinessException(
            'discount_exceeds_max',
            'The discount exceeds the maximum configured on the master.',
            statusCode: 409,
          );
        }
      }
    }

    final totalCents = pricing.total.cents;
    final requestedPaid = request.paidAmountCents ?? totalCents;
    late final int paidAmountCents;
    switch (request.paymentMethod) {
      case 'card':
        paidAmountCents = totalCents;
        break;
      case 'credit':
      case 'cheque':
        paidAmountCents = 0;
        break;
      case 'cash':
        if (requestedPaid < 0) {
          throw const LanBusinessException(
            'invalid_paid_amount',
            'Paid amount cannot be negative.',
          );
        }
        if (requestedPaid < totalCents) {
          if (!appSettings.allowPartialPayments) {
            throw const LanBusinessException(
              'partial_payment_disabled',
              'Partial payments are disabled on the master.',
            );
          }
          if (customer == null) {
            throw const LanBusinessException(
              'customer_required_for_partial_payment',
              'Partial payment requires a customer.',
            );
          }
        }
        // The original sale screen sends the full amount only when the user
        // explicitly chooses to keep an overpayment as customer credit. A
        // walk-in customer cannot own a credit balance, so their excess is
        // still treated as returned change and capped at the invoice total.
        paidAmountCents = requestedPaid > totalCents && customer == null
            ? totalCents
            : requestedPaid;
        break;
    }

    final items = <SaleItemInput>[];
    for (var index = 0; index < resolved.length; index++) {
      final value = resolved[index];
      final line = pricing.lines[index];
      final quantityScale = MeasurementType.fromDb(
        value.product.measurementType,
      ).quantityScale;
      items.add(
        SaleItemInput(
          productId: value.product.id,
          variantId: value.variant?.id,
          quantity: value.request.quantity,
          quantityScale: quantityScale,
          measurementType: value.product.measurementType,
          unitPriceCents: Decimal.fromInt(value.unitPriceCents),
          subtotalCents: Decimal.fromInt(line.subtotal.cents),
          discountCents: Decimal.fromInt(line.totalLineDiscount.cents),
          taxCents: Decimal.fromInt(line.tax.cents),
          totalCents: Decimal.fromInt(line.total.cents),
          employeeId: value.salesperson?.id,
          employeeName: value.salesperson?.name,
        ),
      );
    }

    final currency = await _selectedCurrency();
    if (currency == null) {
      throw const LanBusinessException(
        'currency_unavailable',
        'The master has no configured currency.',
        statusCode: 409,
      );
    }

    final saleId = await _sales.createSale(
      customerId: customer?.id,
      employeeId: request.salespersonId,
      currencyId: currency.id,
      subtotalCents: Decimal.fromInt(pricing.subtotal.cents),
      discountCents: Decimal.fromInt(pricing.totalDiscount.cents),
      taxCents: Decimal.fromInt(pricing.tax.cents),
      totalCents: Decimal.fromInt(totalCents),
      paidAmountCents: Decimal.fromInt(paidAmountCents),
      paymentMethod: request.paymentMethod,
      items: items,
      notes: request.notes,
      saleDate: DateTime.now(),
      allowNegativeStock: appSettings.allowNegativeStock,
      idempotencyKey: key,
      actorUserId: actor.id,
      taxInclusiveAtPost: appSettings.taxInclusivePricing,
    );

    final sale = await (_database.select(
      _database.sales,
    )..where((row) => row.id.equals(saleId))).getSingle();
    return _resultFromSale(sale);
  }

  Discount _discountForRequest(LanSaleLineRequest line) {
    if (line.discountValue < 0) {
      throw const LanBusinessException(
        'invalid_discount',
        'Discount value cannot be negative.',
      );
    }
    switch (line.discountType) {
      case 'none':
        if (line.discountValue != 0) {
          throw const LanBusinessException(
            'invalid_discount',
            'A no-discount line must have a zero value.',
          );
        }
        return Discount.none;
      case 'fixed':
        return line.discountValue == 0
            ? Discount.none
            : Discount.fixed(Money.fromCents(line.discountValue));
      case 'percentage':
        if (line.discountValue > 10000) {
          throw const LanBusinessException(
            'invalid_discount',
            'Percentage discount cannot exceed 100%.',
          );
        }
        return line.discountValue == 0
            ? Discount.none
            : Discount.percent(line.discountValue);
      default:
        throw const LanBusinessException(
          'invalid_discount',
          'Unsupported discount type.',
        );
    }
  }

  void _requireCashierEmployee(LanRemoteUser actor) {
    if (actor.role != 'cashier' ||
        actor.employeeId == null ||
        actor.employeeName?.trim().isEmpty != false) {
      throw const LanBusinessException(
        'cashier_employee_required',
        'The cashier account must be linked to an active employee.',
        statusCode: 409,
      );
    }
  }

  Future<LanCashierShiftSnapshot> _shiftSnapshot(CashierShiftView view) async {
    final summary = await _shifts.getSummary(view.shift.id);
    return LanCashierShiftSnapshot(
      id: view.shift.id,
      shiftNumber: view.shift.shiftNumber,
      status: view.shift.status,
      cashierUserId: view.shift.cashierUserId,
      employeeId:
          (await (_database.select(_database.users)
                    ..where((row) => row.id.equals(view.shift.cashierUserId))
                    ..limit(1))
                  .getSingleOrNull())
              ?.employeeId,
      cashierName: view.cashierName,
      currencyCode: view.currencyCode,
      currencySymbol: view.currencySymbol,
      openingCashCents: _cents(view.shift.openingCashCents),
      expectedCashCents: summary.expectedCashCents,
      salesCount: summary.salesCount,
      returnsCount: summary.returnsCount,
      openedAt: view.shift.openedAt,
      closedAt: view.shift.closedAt,
    );
  }

  LanSaleResult _resultFromSale(Sale sale, {bool duplicate = false}) {
    return LanSaleResult(
      saleId: sale.id,
      invoiceNumber: sale.invoiceNumber,
      subtotalCents: _cents(sale.subtotalCents),
      discountCents: _cents(sale.discountCents),
      taxCents: _cents(sale.taxCents),
      totalCents: _cents(sale.totalCents),
      paidAmountCents: _cents(sale.paidAmountCents),
      duplicate: duplicate,
    );
  }

  Future<Currency?> _selectedCurrency() async {
    final selectedCode = _currencyService.currencyCode.trim().toUpperCase();
    if (selectedCode.isNotEmpty) {
      final selected =
          await (_database.select(_database.currencies)
                ..where(
                  (row) =>
                      row.code.equals(selectedCode) & row.isActive.equals(true),
                )
                ..limit(1))
              .getSingleOrNull();
      if (selected != null) return selected;
    }
    return await (_database.select(_database.currencies)
              ..where(
                (row) => row.isBase.equals(true) & row.isActive.equals(true),
              )
              ..limit(1))
            .getSingleOrNull() ??
        await (_database.select(
          _database.currencies,
        )..limit(1)).getSingleOrNull();
  }

  int _cents(Decimal value) => value.toBigInt().toInt();
}

class _ResolvedLanLine {
  final LanSaleLineRequest request;
  final Product product;
  final ProductVariant? variant;
  final int unitPriceCents;
  final Employee? salesperson;

  const _ResolvedLanLine({
    required this.request,
    required this.product,
    required this.variant,
    required this.unitPriceCents,
    this.salesperson,
  });
}
