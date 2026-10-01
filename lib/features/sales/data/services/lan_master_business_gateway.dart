import '../../../../core/services/returns/purchase_return_disposition.dart';
import '../../../../core/services/loyalty/sale_loyalty_settlement.dart';
import 'dart:async';
import 'dart:convert';

import '../../../../core/pricing/pricing_preview_fingerprint.dart';
import '../../../../core/services/business/branch_tax_policy_store.dart';
import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/migrations/consignment_return_liability.dart';
import '../../../../core/services/business/warehouse_catalog_scope.dart';
import '../../../../core/services/business/document_posting_scope.dart';
import '../../../../core/services/business/warehouse_operation_scope.dart';
import '../../../../core/services/business/warehouse_read_scope.dart';
import '../../../../core/services/business/warehouse_stock_initialization_service.dart';
import '../../../../core/services/business/warehouse_transfer_preflight.dart';
import '../../../business/data/warehouse_setup_service.dart';
import '../../../business/data/warehouse_transfer_dispatch_service.dart';
import '../../../business/data/warehouse_transfer_receipt_service.dart';
import '../../../business/data/warehouse_transfer_recall_service.dart';
import '../../../business/data/warehouse_transfer_repository.dart';
import '../../../../core/database/daos/adjustment_return_dao.dart';
import '../../../../core/database/daos/pharmacy_dao.dart';
import '../../../../core/measurement/measurement.dart';
import '../../../../core/money/money.dart';
import '../../../../core/payments/checkout_settlement.dart';
import '../../../../core/pricing/discount.dart';
import '../../../../core/pricing/invoice_pricing_engine.dart';
import '../../../../core/pricing/line_item_pricing_engine.dart';
import '../../../../core/pricing/pricing_snapshot.dart';
import '../../../../core/promotions/promotion_engine.dart';
import '../../../../core/promotions/promotion_margin_policy.dart';
import '../../../../core/promotions/promotion_repository.dart';
import '../../../../core/promotions/promotion_return_policy.dart';
import '../../../../core/services/cashier_shift_service.dart';
import '../../../../core/services/audit_log_service.dart';
import '../../../../core/services/currency_service.dart'
    show CurrencyService, SymbolPosition;
import '../../../../core/services/currency_service.dart'
    as currency_model
    show Currency;
import '../../../../core/services/feature_gate_service.dart';
import '../../../../core/services/commissions/commission_service.dart';
import '../../../../core/services/journal_entry_service.dart';
import '../../../../core/services/loyalty/loyalty_points_service.dart';
import '../../../../core/services/inventory/supplier_identity_rules.dart';
import '../../../../core/services/inventory/supplier_product_identity_service.dart';
import '../../../../core/services/inventory/inventory_stock_source_service.dart';
import '../../../../core/services/lan/lan_request_receipt_store.dart';
import '../../../../core/services/lan/lan_business_models.dart';
import '../../../../core/services/lan/lan_void_impact_codec.dart';
import '../../../../core/services/lan/lan_models.dart';
import '../../../../core/services/void_impact_analyzer.dart';
import '../../../settings/data/services/app_settings_service.dart';
import '../../../purchases/domain/entities/purchase_entity.dart';
import '../../../purchases/domain/repositories/purchase_repository.dart';
import '../../../purchases/data/repositories/purchase_repository_impl.dart';
import '../../domain/entities/sale_entity.dart';
import '../../domain/repositories/sale_repository.dart';
import '../repositories/sale_repository_impl.dart';

class LanMasterBusinessGatewayImpl
    implements
        LanMasterBusinessGateway,
        LanWarehouseScopedBusinessGateway,
        LanPurchaseInvoiceGateway,
        LanWarehouseTransferGateway {
  static final Object _warehouseContextKey = Object();
  final AppDatabase _database;
  final SaleRepository _sales;
  final PurchaseRepository _purchases;
  final AppSettingsService _settings;
  final CashierShiftService _shifts;
  final CurrencyService _currencyService;
  final AdjustmentReturnDao _adjustmentReturns;
  final JournalEntryService _journalEntries;
  final CommissionService _commissions;
  final LoyaltyPointsService _loyaltyPoints;
  final PharmacyDao _pharmacy;
  final PromotionRepository _promotions;
  final FeatureGateService _featureGate;
  final AuditLogService _auditLog;
  final WarehouseSetupEntitlement _warehouseEntitlement;

  const LanMasterBusinessGatewayImpl({
    required AppDatabase database,
    required SaleRepository sales,
    required PurchaseRepository purchases,
    required AppSettingsService settings,
    required CashierShiftService shifts,
    required CurrencyService currencyService,
    required AdjustmentReturnDao adjustmentReturns,
    required JournalEntryService journalEntries,
    required CommissionService commissions,
    required LoyaltyPointsService loyaltyPoints,
    required PharmacyDao pharmacy,
    required PromotionRepository promotions,
    required FeatureGateService featureGate,
    required AuditLogService auditLog,
    WarehouseSetupEntitlement warehouseEntitlement =
        const UnreleasedWarehouseSetupEntitlement(),
  }) : _database = database,
       _sales = sales,
       _purchases = purchases,
       _settings = settings,
       _shifts = shifts,
       _currencyService = currencyService,
       _adjustmentReturns = adjustmentReturns,
       _journalEntries = journalEntries,
       _commissions = commissions,
       _loyaltyPoints = loyaltyPoints,
       _pharmacy = pharmacy,
       _promotions = promotions,
       _featureGate = featureGate,
       _auditLog = auditLog,
       _warehouseEntitlement = warehouseEntitlement;

  _LanWarehouseContext? get _warehouseContext =>
      Zone.current[_warehouseContextKey] as _LanWarehouseContext?;

  SaleRepository get _activeSales => _warehouseContext?.sales ?? _sales;
  PurchaseRepository get _activePurchases =>
      _warehouseContext?.purchases ?? _purchases;
  WarehouseOperationScope? get _activeWarehouseScope =>
      _warehouseContext?.scope;

  @override
  Future<T> runForWarehouse<T>(
    String warehouseId,
    Future<T> Function() operation,
  ) async {
    final scope = await WarehouseOperationScope.resolveForOrganization(
      _database,
      warehouseId: warehouseId,
    );
    await scope.validate(_database);
    if (scope.isPrimary) return operation();
    if (_sales is! SaleRepositoryImpl ||
        _purchases is! PurchaseRepositoryImpl) {
      throw StateError('Warehouse-scoped LAN repositories are unavailable.');
    }
    final context = _LanWarehouseContext(
      scope: scope,
      sales: _sales.forWarehouse(scope),
      purchases: _purchases.forWarehouse(scope),
    );
    return runZoned(operation, zoneValues: {_warehouseContextKey: context});
  }

  bool _isEnabled(AppFeature feature, bool settingEnabled) =>
      _featureGate.isEnabled(feature, settingEnabled: settingEnabled);

  Future<WarehouseReadScope> _activeReadScope() async {
    final selected = _activeWarehouseScope;
    return selected == null
        ? WarehouseReadScope.resolve(_database)
        : selected.forReading(_database);
  }

  Future<Set<int>> _activeDocumentIds(InventoryPostingDocument kind) async {
    final scope = await _activeReadScope();
    return (await _database
            .customSelect('SELECT id FROM ${scope.documents(kind)}')
            .get())
        .map((row) => row.read<int>('id'))
        .toSet();
  }

  Future<bool> _containsActiveDocument(
    InventoryPostingDocument kind,
    int id,
  ) async {
    final scope = await _activeReadScope();
    return await _database
            .customSelect(
              'SELECT 1 AS found FROM ${scope.documents(kind)} WHERE id=?',
              variables: [Variable.withInt(id)],
            )
            .getSingleOrNull() !=
        null;
  }

  @override
  Future<LanSalesPage> fetchSales({required int limit}) async {
    final safeLimit = limit.clamp(1, 500);
    final allowed = await _activeDocumentIds(InventoryPostingDocument.sale);
    final results = await Future.wait<dynamic>([
      _activeSales.watchAllSales().first,
      _activeSales.watchDashboardStats().first,
      _activeSales.watchSaleIdsWithReturns().first,
      _activeSales.watchSaleProductSearchTerms().first,
    ]);
    final sales = (results[0] as List<SaleEntity>)
        .where((sale) => allowed.contains(sale.id))
        .take(safeLimit)
        .toList(growable: false);
    final stats = results[1] as SaleDashboardStats;
    final returnIds = results[2] as Set<int>;
    final terms = results[3] as Map<int, List<String>>;
    final visibleIds = sales.map((sale) => sale.id).toSet();

    final currency = _currencyService.getCurrency();
    return LanSalesPage(
      currencyCode: currency.code,
      currencySymbol: currency.symbol,
      currencyDecimalDigits: currency.decimalDigits,
      currencySymbolAfter: currency.symbolPosition.name == 'after',
      sales: sales
          .map<LanSaleSummary>(
            (sale) => LanSaleSummary(
              id: sale.id,
              invoiceNumber: sale.invoiceNumber,
              customerId: sale.customerId,
              customerName: sale.customerName,
              customerPhone: sale.customerPhone,
              employeeId: sale.employeeId,
              employeeName: sale.employeeName,
              subtotalCents: _cents(sale.subtotalCents),
              taxCents: _cents(sale.taxCents),
              discountCents: _cents(sale.discountCents),
              totalCents: _cents(sale.totalCents),
              paidAmountCents: _cents(sale.paidAmountCents),
              currencyId: sale.currencyId,
              paymentMethod: sale.paymentMethod,
              status: sale.status,
              notes: sale.notes,
              saleDate: sale.saleDate,
              dueDate: sale.dueDate,
              taxInclusiveAtPost: sale.taxInclusiveAtPost,
              createdAt: sale.createdAt,
              updatedAt: sale.updatedAt,
            ),
          )
          .toList(growable: false),
      stats: LanSaleDashboardStats(
        totalCount: stats.totalCount,
        completedCount: stats.completedCount,
        voidedCount: stats.voidedCount,
        totalSalesCents: stats.totalSalesCents,
        totalPaidCents: stats.totalPaidCents,
        overdueCount: stats.overdueCount,
        returnsCount: stats.returnsCount,
        totalReturnsCents: stats.totalReturnsCents,
        todaySalesCents: stats.todaySalesCents,
        todayCount: stats.todayCount,
      ),
      saleIdsWithReturns: returnIds.intersection(visibleIds),
      productSearchTerms: Map<int, List<String>>.fromEntries(
        terms.entries.where((entry) => visibleIds.contains(entry.key)),
      ),
    );
  }

  @override
  Future<LanSaleDetails?> fetchSaleDetails({required int saleId}) async {
    if (!await _containsActiveDocument(InventoryPostingDocument.sale, saleId)) {
      return null;
    }
    if (saleId <= 0) return null;
    final sale = await _activeSales.getSaleById(saleId);
    if (sale == null) return null;
    final items = await _activeSales.getSaleItems(saleId);
    final shift = await _shifts.getSaleShift(saleId);
    final promotionApplications = await _promotions.loadSaleApplications(
      saleId,
    );
    final storedCurrency =
        await (_database.select(_database.currencies)
              ..where((row) => row.id.equals(sale.currencyId))
              ..limit(1))
            .getSingleOrNull();
    final configuredCurrency = _currencyService.getCurrency();
    final currencyCode = storedCurrency?.code ?? configuredCurrency.code;
    final currencyDefinition = configuredCurrency.code == currencyCode
        ? configuredCurrency
        : currency_model.Currency.fromCode(currencyCode);
    final appSettings = _settings.current;

    return LanSaleDetails(
      sale: LanSaleSummary(
        id: sale.id,
        invoiceNumber: sale.invoiceNumber,
        customerId: sale.customerId,
        customerName: sale.customerName,
        customerPhone: sale.customerPhone,
        employeeId: sale.employeeId,
        employeeName: sale.employeeName,
        subtotalCents: _cents(sale.subtotalCents),
        taxCents: _cents(sale.taxCents),
        discountCents: _cents(sale.discountCents),
        totalCents: _cents(sale.totalCents),
        paidAmountCents: _cents(sale.paidAmountCents),
        currencyId: sale.currencyId,
        paymentMethod: sale.paymentMethod,
        status: sale.status,
        notes: sale.notes,
        saleDate: sale.saleDate,
        dueDate: sale.dueDate,
        taxInclusiveAtPost: sale.taxInclusiveAtPost,
        createdAt: sale.createdAt,
        updatedAt: sale.updatedAt,
      ),
      lines: items
          .map(
            (item) => LanSaleDetailLine(
              id: item.id,
              saleId: item.saleId,
              productId: item.productId,
              productName: item.productName ?? '',
              productSku: item.productSku,
              variantId: item.variantId,
              variantSku: item.variantSku,
              colorName: item.colorName,
              colorHex: item.colorHex,
              sizeName: item.sizeName,
              quantity: item.quantity,
              quantityScale: item.quantityScale,
              measurementType: item.measurementType,
              unitPriceCents: _cents(item.unitPriceCents),
              subtotalCents: _cents(item.subtotalCents),
              discountCents: _cents(item.discountCents),
              taxCents: _cents(item.taxCents),
              totalCents: _cents(item.totalCents),
              employeeId: item.employeeId,
              employeeName: item.employeeName,
              createdAt: item.createdAt,
            ),
          )
          .toList(growable: false),
      promotionApplications: promotionApplications,
      currencyCode: currencyCode,
      currencySymbol: storedCurrency?.symbol ?? currencyDefinition.symbol,
      currencyDecimalDigits: currencyDefinition.decimalDigits,
      currencySymbolAfter:
          currencyDefinition.symbolPosition == SymbolPosition.after,
      cashierName: shift?.cashierName,
      cashierShiftNumber: shift?.shift.shiftNumber,
      receiptHeaderText: appSettings.receiptHeaderText,
      receiptFooterText: appSettings.receiptFooterText,
    );
  }

  @override
  Future<LanSaleVoidResult> voidSale({
    required LanRemoteUser actor,
    required int saleId,
  }) async {
    if (_settings.current.requirePinForVoidRefund) {
      throw const LanBusinessException(
        'remote_pin_required',
        'PIN-protected voids must be completed on the master device.',
        statusCode: 409,
      );
    }
    if (!await _containsActiveDocument(InventoryPostingDocument.sale, saleId)) {
      throw const LanBusinessException(
        'sale_not_found',
        'Sale not found in the active warehouse.',
        statusCode: 404,
      );
    }
    final sale = await _activeSales.getSaleById(saleId);
    if (sale == null) {
      throw const LanBusinessException(
        'sale_not_found',
        'Sale not found.',
        statusCode: 404,
      );
    }
    if (sale.isVoided) {
      return LanSaleVoidResult(
        saleId: saleId,
        status: 'voided',
        duplicate: true,
      );
    }
    if (!sale.isCompleted) {
      throw const LanBusinessException(
        'sale_not_voidable',
        'Only a completed sale can be voided.',
        statusCode: 409,
      );
    }
    try {
      await _activeSales.voidSale(saleId, actorUserId: actor.id);
      return LanSaleVoidResult(saleId: saleId, status: 'voided');
    } catch (error) {
      throw LanBusinessException(
        'sale_void_failed',
        error.toString().replaceFirst('Exception: ', ''),
        statusCode: 409,
      );
    }
  }

  @override
  Future<LanCatalogPage> fetchCatalog({
    required String query,
    required int offset,
    required int limit,
  }) async {
    final safeOffset = offset.clamp(0, 1000000);
    final safeLimit = limit.clamp(1, 200);
    final normalized = query.trim();
    final policy = await BranchTaxPolicyStore(_database).read();
    if (policy == null && _settings.requiresPersistedTaxPolicy) {
      throw const LanBusinessException(
        'tax_policy_unavailable',
        'The branch tax policy is unavailable.',
        statusCode: 409,
      );
    }
    final appSettings =
        policy?.policy.applyTo(_settings.current) ?? _settings.current;
    final identityMatch = normalized.isEmpty
        ? null
        : await SupplierProductIdentityService(
            _database,
          ).resolveSelection(normalized);
    final consignmentMatch = normalized.isEmpty
        ? null
        : await InventoryStockSourceService(
            _database,
          ).resolveConsignmentCodeReference(
            normalized,
            scope: _activeWarehouseScope,
          );
    final pharmacyEnabled = _isEnabled(
      AppFeature.pharmacy,
      appSettings.enablePharmacyFeatures,
    );
    final promotionsEnabled = _isEnabled(
      AppFeature.promotions,
      appSettings.enablePromotions,
    );
    final cataloguePolicy = await _activeBranchCataloguePolicy();
    final medicineProductIds = pharmacyEnabled && normalized.isNotEmpty
        ? await _pharmacy.searchMedicineProductIds(normalized)
        : const <int>{};
    final statement = _database.select(_database.products)
      ..where((row) {
        var expression = row.isActive.equals(true);
        if (cataloguePolicy.isManaged) {
          Expression<bool> selected = const Constant(false);
          if (cataloguePolicy.categoryIds.isNotEmpty) {
            selected =
                selected | row.categoryId.isIn(cataloguePolicy.categoryIds);
          }
          if (cataloguePolicy.productIds.isNotEmpty) {
            selected = selected | row.id.isIn(cataloguePolicy.productIds);
          }
          expression = expression & selected;
          if (cataloguePolicy.excludedProductIds.isNotEmpty) {
            expression =
                expression & row.id.isNotIn(cataloguePolicy.excludedProductIds);
          }
        }
        if (normalized.isNotEmpty) {
          final pattern = '%$normalized%';
          expression =
              expression &
              (row.name.like(pattern) |
                  row.sku.like(pattern) |
                  row.barcode.like(pattern) |
                  (identityMatch == null
                      ? const Constant(false)
                      : row.id.equals(identityMatch.productId)) |
                  (consignmentMatch == null
                      ? const Constant(false)
                      : row.id.equals(consignmentMatch.productId)) |
                  (medicineProductIds.isEmpty
                      ? const Constant(false)
                      : row.id.isIn(medicineProductIds)));
        }
        return expression;
      })
      ..orderBy([(row) => OrderingTerm.asc(row.name)])
      ..limit(safeLimit + 1, offset: safeOffset);
    final rows = await statement.get();
    final hasMore = rows.length > safeLimit;
    final pageRows = rows.take(safeLimit).toList(growable: false);
    final catalogProducts = await _buildCatalogProducts(
      pageRows,
      includeMedicine: pharmacyEnabled,
      identityMatches: identityMatch == null
          ? const {}
          : {identityMatch.productId: identityMatch},
      consignmentMatches: consignmentMatch == null
          ? const {}
          : {consignmentMatch.productId: consignmentMatch},
    );
    final currency = await _selectedCurrency();
    if (currency == null) {
      throw const LanBusinessException(
        'currency_unavailable',
        'The selected master currency must be active in the database.',
        statusCode: 409,
      );
    }
    final activePromotionRules = promotionsEnabled
        ? await _promotions.loadActiveRules()
        : const <PromotionRule>[];
    final promotionProductIds = <int>{};
    final promotionVariantIds = <int>{};
    for (final rule in activePromotionRules) {
      for (final scope in rule.qualifierScopes.where(
        (scope) => scope.isRequiredComponent,
      )) {
        if (scope.type == PromotionScopeType.product) {
          promotionProductIds.add(scope.targetId!);
        } else if (scope.type == PromotionScopeType.variant) {
          promotionVariantIds.add(scope.targetId!);
        }
      }
    }
    if (promotionVariantIds.isNotEmpty) {
      final variantRows = await (_database.select(
        _database.productVariants,
      )..where((row) => row.id.isIn(promotionVariantIds))).get();
      promotionProductIds.addAll(variantRows.map((row) => row.productId));
    }
    if (cataloguePolicy.isManaged && promotionProductIds.isNotEmpty) {
      final allowed = await _managedCatalogueProductIds(cataloguePolicy);
      promotionProductIds.retainAll(allowed);
    }
    final promotionProducts = promotionProductIds.isEmpty
        ? const <LanCatalogProduct>[]
        : await _buildCatalogProducts(
            await (_database.select(_database.products)
                  ..where(
                    (row) =>
                        row.isActive.equals(true) &
                        row.id.isIn(promotionProductIds),
                  )
                  ..orderBy([(row) => OrderingTerm.asc(row.name)]))
                .get(),
            includeMedicine: false,
          );

    return LanCatalogPage(
      products: catalogProducts,
      offset: safeOffset,
      limit: safeLimit,
      hasMore: hasMore,
      currencyId: currency.id,
      currencyCode: currency.code,
      currencySymbol: currency.symbol,
      currencyDecimalDigits: _currencyService.getCurrency().decimalDigits,
      currencySymbolAfter:
          _currencyService.getCurrency().symbolPosition == SymbolPosition.after,
      enableTaxCalculations: appSettings.enableTaxCalculations,
      defaultSalesTaxRateBps: (appSettings.defaultSalesTaxRate * 100).round(),
      defaultPurchaseTaxRateBps: (appSettings.defaultPurchaseTaxRate * 100)
          .round(),
      taxInclusivePricing: appSettings.taxInclusivePricing,
      allowNegativeStock: appSettings.allowNegativeStock,
      allowPartialPayments: appSettings.allowPartialPayments,
      requireCustomerForSales: appSettings.requireCustomerForSales,
      allowDiscounts: appSettings.allowDiscounts,
      maxDiscountPercent: appSettings.maxDiscountPercent,
      allowBelowCostSales: appSettings.allowBelowCostSales,
      receiptHeaderText: appSettings.receiptHeaderText,
      receiptFooterText: appSettings.receiptFooterText,
      enablePharmacyFeatures: pharmacyEnabled,
      useSupplierProductCodes: appSettings.enableSupplierProductCodes,
      enablePromotions: promotionsEnabled,
      promotionRules: activePromotionRules
          .map((rule) => rule.toTransportMap())
          .toList(growable: false),
      promotionProducts: promotionProducts,
    );
  }

  @override
  Future<LanMedicineAlternativesResult> fetchMedicineAlternatives({
    required int productId,
  }) async {
    if (!_isEnabled(
      AppFeature.pharmacy,
      _settings.current.enablePharmacyFeatures,
    )) {
      return LanMedicineAlternativesResult(
        sourceProductId: productId,
        alternatives: const [],
      );
    }
    final details = await _pharmacy.findExactAlternatives(productId);
    final products = await _buildCatalogProducts(
      details.map((row) => row.product).toList(growable: false),
      includeMedicine: true,
    );
    return LanMedicineAlternativesResult(
      sourceProductId: productId,
      alternatives: products,
    );
  }

  Future<List<LanCatalogProduct>> _buildCatalogProducts(
    List<Product> products, {
    required bool includeMedicine,
    Map<int, SupplierIdentitySelection> identityMatches = const {},
    Map<int, InventoryStockSourceBalance> consignmentMatches = const {},
  }) async {
    await _ensureActiveWarehouseBalances(products);
    final productIds = products.map((row) => row.id).toList(growable: false);
    final readScope = await _activeReadScope();
    final scopedProducts = {
      for (final p in await WarehouseCatalogScope.readProducts(
        _database,
        productIds,
        scope: readScope,
      ))
        p.id: p,
    };
    products = products.map((p) => scopedProducts[p.id]!).toList();
    final storedVariants = productIds.isEmpty
        ? <ProductVariant>[]
        : await (_database.select(_database.productVariants)
                ..where(
                  (row) =>
                      row.productId.isIn(productIds) &
                      row.isActive.equals(true),
                )
                ..orderBy([(row) => OrderingTerm.asc(row.id)]))
              .get();

    final variants = await WarehouseCatalogScope.readVariants(
      _database,
      storedVariants.map((v) => v.id).toList(),
      scope: readScope,
    );
    final colors = await _database.select(_database.productColors).get();
    final sizes = await _database.select(_database.sizes).get();
    final colorNames = {for (final value in colors) value.id: value.name};
    final colorHexes = {for (final value in colors) value.id: value.hexCode};
    final sizeNames = {for (final value in sizes) value.id: value.name};
    final medicineProfiles = includeMedicine
        ? await _pharmacy.getMedicineProfilesForProducts(productIds)
        : const <int, MedicineProfileDetails>{};

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
              costCents: _cents(variant.costCents),
              lastPurchasePriceCents: variant.lastPurchasePriceCents == null
                  ? null
                  : _cents(variant.lastPurchasePriceCents!),
              stockQuantity: variant.stockQuantity,
            ),
          );
    }

    return products
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
            medicine: _toLanMedicine(medicineProfiles[product.id]),
            matchedSupplierIdentityId: identityMatches[product.id]?.identityId,
            matchedCanonicalVariantId:
                identityMatches[product.id]?.canonicalVariantId ??
                consignmentMatches[product.id]?.variantId,
            matchedSupplierSourceSku: identityMatches[product.id]?.sourceSku,
            matchedSupplierName:
                identityMatches[product.id]?.supplierName ??
                consignmentMatches[product.id]?.supplierName,
            matchedConsignmentLayerId:
                consignmentMatches[product.id]?.consignmentLayerId,
            matchedConsignmentSourceCode:
                consignmentMatches[product.id]?.sourceCode,
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
        .toList(growable: false);
  }

  Future<BranchCataloguePolicy> _activeBranchCataloguePolicy() async {
    final scope = _activeWarehouseScope;
    if (scope == null || scope.isPrimary) {
      return const BranchCataloguePolicy();
    }
    final row = await _database
        .customSelect(
          'SELECT value FROM app_settings WHERE key=?',
          variables: [
            Variable.withString(
              'lan.branch_catalogue.policy.v1.${scope.branchId}',
            ),
          ],
        )
        .getSingleOrNull();
    if (row == null) return const BranchCataloguePolicy();
    try {
      return BranchCataloguePolicy.fromJson(
        jsonDecode(row.read<String>('value')),
      );
    } on FormatException {
      return const BranchCataloguePolicy();
    }
  }

  Future<Set<int>> _managedCatalogueProductIds(
    BranchCataloguePolicy policy,
  ) async {
    if (!policy.isManaged) return const <int>{};
    final rows =
        await (_database.select(_database.products)..where((row) {
              Expression<bool> selected = const Constant(false);
              if (policy.categoryIds.isNotEmpty) {
                selected = selected | row.categoryId.isIn(policy.categoryIds);
              }
              if (policy.productIds.isNotEmpty) {
                selected = selected | row.id.isIn(policy.productIds);
              }
              var expression = row.isActive.equals(true) & selected;
              if (policy.excludedProductIds.isNotEmpty) {
                expression =
                    expression & row.id.isNotIn(policy.excludedProductIds);
              }
              return expression;
            }))
            .get();
    return rows.map((row) => row.id).toSet();
  }

  /// A catalogue assignment establishes which SKUs a location may operate.
  /// Creating a zero balance is metadata only: it neither increases stock nor
  /// posts a journal entry. The first purchase/transfer still owns quantity
  /// and valuation, while the saved variant cost is merely the initial WAC
  /// fallback required by the warehouse ledger.
  Future<void> _ensureActiveWarehouseBalances(List<Product> products) async {
    final scope = _activeWarehouseScope;
    if (scope == null || scope.isPrimary || products.isEmpty) return;
    final productIds = products.map((row) => row.id).toSet();
    final variants =
        await (_database.select(_database.productVariants).join([
              innerJoin(
                _database.products,
                _database.products.id.equalsExp(
                  _database.productVariants.productId,
                ),
              ),
            ])..where(
              _database.productVariants.productId.isIn(productIds) &
                  _database.productVariants.isActive.equals(true) &
                  _database.products.isActive.equals(true) &
                  _database.products.trackInventory.equals(true),
            ))
            .get();
    final primaryScope = await WarehouseReadScope.resolve(_database);
    final authoritativeVariants = {
      for (final variant in await WarehouseCatalogScope.readVariants(
        _database,
        variants
            .map((row) => row.readTable(_database.productVariants).id)
            .toList(growable: false),
        scope: primaryScope,
      ))
        variant.id: variant,
    };
    final grouped = <int, List<WarehouseStockSeed>>{};
    for (final row in variants) {
      final variant = row.readTable(_database.productVariants);
      final product = row.readTable(_database.products);
      final authoritative = authoritativeVariants[variant.id];
      if (authoritative == null) {
        throw StateError(
          'Primary warehouse balance is missing for variant ${variant.id}.',
        );
      }
      grouped
          .putIfAbsent(product.currencyId!, () => <WarehouseStockSeed>[])
          .add(
            WarehouseStockSeed(
              variantId: variant.id,
              unitCostCents: _cents(authoritative.costCents),
            ),
          );
    }
    final initializer = WarehouseStockInitializationService(_database);
    for (final entry in grouped.entries) {
      for (var offset = 0; offset < entry.value.length; offset += 500) {
        final end = (offset + 500).clamp(0, entry.value.length);
        await initializer.initialize(
          scope: scope,
          currencyId: entry.key,
          seeds: entry.value.sublist(offset, end),
        );
      }
    }
  }

  LanMedicineProfile? _toLanMedicine(MedicineProfileDetails? details) {
    if (details == null) return null;
    return LanMedicineProfile(
      dosageForm: details.profile.dosageForm,
      administrationRoute: details.profile.administrationRoute,
      substitutionEligible: details.profile.substitutionEligible,
      ingredients: details.ingredients
          .map(
            (row) => LanMedicineIngredient(
              ingredientId: row.ingredient.id,
              canonicalName: row.ingredient.canonicalName,
              nameAr: row.ingredient.nameAr,
              nameFr: row.ingredient.nameFr,
              strengthValueMicros: row.strength.normalizedStrengthValueMicros,
              strengthUnit: row.strength.normalizedStrengthUnit,
              basisValueMicros: row.strength.normalizedBasisValueMicros,
              basisUnit: row.strength.normalizedBasisUnit,
            ),
          )
          .toList(growable: false),
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
  Future<LanCustomerCheckout> fetchCustomerCheckout(int customerId) =>
      _database.transaction(() async {
        final customer =
            await (_database.select(_database.customers)..where(
                  (c) => c.id.equals(customerId) & c.isActive.equals(true),
                ))
                .getSingleOrNull();
        if (customer == null) {
          throw const LanBusinessException(
            'customer_not_found',
            'Customer is unavailable.',
            statusCode: 404,
          );
        }
        final currency = await (_database.select(
          _database.currencies,
        )..where((c) => c.id.equals(customer.currencyId))).getSingle();
        final loyalty = await _database
            .select(_database.loyaltySettingsTable)
            .getSingleOrNull();
        return LanCustomerCheckout(
          customerId: customer.id,
          currencyId: currency.id,
          currencyCode: currency.code,
          balanceCents: _cents(customer.balanceCents),
          pointsBalance: customer.loyaltyPointsBalance,
          redemptionEnabled:
              customer.loyaltyEnabled &&
              loyalty != null &&
              loyalty.isEnabled &&
              loyalty.allowPointsRedemption,
          pointValueCents: loyalty?.pointValueCents ?? 0,
          minRedemptionPoints: loyalty?.minRedemptionPoints ?? 0,
          maxRedemptionPercentBps: loyalty?.maxRedemptionPercentBps ?? 0,
        );
      });

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
    final safeLimit = limit.clamp(1, 200);

    // Fetch all active employees (with optional search filter).
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
      ..orderBy([(row) => OrderingTerm.asc(row.name)]);
    final allRows = await statement.get();

    // Fetch roles to identify salesperson & manager role IDs.
    final roles = await (_database.select(
      _database.roles,
    )..where((r) => r.isActive.equals(true))).get();
    final salespersonRoleIds = <int>{};
    final managerRoleIds = <int>{};
    for (final role in roles) {
      final rn = role.name.toLowerCase();
      if (rn == 'salesperson') {
        salespersonRoleIds.add(role.id);
      } else if (rn == 'manager') {
        managerRoleIds.add(role.id);
      }
    }

    // Collect manager IDs of salespeople.
    final salespersonManagerIds = <int>{};
    for (final e in allRows) {
      if (e.roleId != null && salespersonRoleIds.contains(e.roleId)) {
        if (e.managerId != null) {
          salespersonManagerIds.add(e.managerId!);
        }
      }
    }

    // Filter: keep salespeople, managers, and managers-of-salespeople.
    final filtered = allRows
        .where((e) {
          if (e.roleId != null && salespersonRoleIds.contains(e.roleId)) {
            return true;
          }
          if (e.roleId != null && managerRoleIds.contains(e.roleId)) {
            return true;
          }
          if (salespersonManagerIds.contains(e.id)) {
            return true;
          }
          return false;
        })
        .take(safeLimit)
        .toList(growable: false);

    return filtered
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
    final normalizedNotes = _normalizedShiftNotes(notes);
    final selectedCurrency = await _selectedCurrency();
    if (selectedCurrency == null) {
      throw const LanBusinessException(
        'currency_unavailable',
        'The master has no configured currency.',
        statusCode: 409,
      );
    }
    final existing = await _shifts.getOpenShiftForUser(actor.id);
    if (existing != null) {
      if (existing.currencyCode == selectedCurrency.code &&
          _cents(existing.shift.openingCashCents) == openingCashCents &&
          _normalizedShiftNotes(existing.shift.openingNotes) ==
              normalizedNotes) {
        return _shiftSnapshot(existing);
      }
      throw const LanBusinessException(
        'shift_open_conflict',
        'This cashier already has a different open shift.',
        statusCode: 409,
      );
    }
    try {
      final view = await _shifts.openShift(
        userId: actor.id,
        openingCashCents: openingCashCents,
        currencyCode: selectedCurrency.code,
        notes: normalizedNotes,
      );
      return await _shiftSnapshot(view);
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
    int? shiftId,
    required int countedCashCents,
    String? notes,
  }) async {
    _requireCashierEmployee(actor);
    final view = shiftId == null
        ? await _shifts.getOpenShiftForUser(actor.id)
        : await _shifts.getShift(shiftId);
    if (view == null) {
      throw const LanBusinessException(
        'cashier_shift_required',
        'The requested cashier shift was not found.',
        statusCode: 409,
      );
    }
    if (view.shift.cashierUserId != actor.id) {
      throw const LanBusinessException(
        'cashier_shift_forbidden',
        'A cashier can only close their own shift.',
        statusCode: 403,
      );
    }
    final normalizedNotes = _normalizedShiftNotes(notes);
    if (view.shift.status == 'closed') {
      final counted = view.shift.countedClosingCashCents;
      if (counted != null &&
          _cents(counted) == countedCashCents &&
          _normalizedShiftNotes(view.shift.closingNotes) == normalizedNotes) {
        return _shiftSnapshot(view);
      }
      throw const LanBusinessException(
        'shift_close_conflict',
        'This shift was already closed with different closing details.',
        statusCode: 409,
      );
    }
    if (view.shift.status != 'open') {
      throw const LanBusinessException(
        'shift_close_conflict',
        'This cashier shift cannot be closed in its current state.',
        statusCode: 409,
      );
    }
    try {
      await _shifts.closeShift(
        shiftId: view.shift.id,
        closedByUserId: actor.id,
        countedClosingCashCents: countedCashCents,
        notes: normalizedNotes,
      );
      final closed = await _shifts.getShift(view.shift.id);
      return await _shiftSnapshot(closed!);
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

    final allowed = await _activeDocumentIds(InventoryPostingDocument.sale);
    final rows = (await statement.get())
        .where((row) => allowed.contains(row.readTable(_database.sales).id))
        .toList(growable: false);
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
        customerId: sale.customerId,
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
    if (!await _containsActiveDocument(InventoryPostingDocument.sale, saleId)) {
      return null;
    }
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
      final linkedHistory = await _activeSales.getLinkedReturnHistory(item.id);
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
        customerId: sale.customerId,
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
      promotionApplications: await _promotions.loadSaleApplications(sale.id),
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
    final linkedIds = await _activeDocumentIds(
      InventoryPostingDocument.saleReturn,
    );
    final adjustmentIds = await _activeDocumentIds(
      InventoryPostingDocument.saleAdjustment,
    );
    final all = (await _activeSales.watchAllSaleReturns().first)
        .where(
          (value) => (value.isAdjustment ? adjustmentIds : linkedIds).contains(
            value.id,
          ),
        )
        .toList(growable: false);
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
  Future<LanSaleReturnDetails?> fetchSaleReturnDetails({
    required int returnId,
    required bool adjustment,
  }) async {
    if (!await _containsActiveDocument(
      adjustment
          ? InventoryPostingDocument.saleAdjustment
          : InventoryPostingDocument.saleReturn,
      returnId,
    )) {
      return null;
    }
    if (returnId <= 0) return null;

    if (!adjustment) {
      final ret = await _activeSales.getSaleReturnById(returnId);
      if (ret == null || ret.isAdjustment) return null;
      final currency = await _returnCurrency(ret.currencyId);
      final results = await Future.wait<dynamic>([
        _activeSales.watchSaleReturnItemsWithDetails(returnId).first,
        _activeSales.getSaleItems(ret.saleId),
      ]);
      final returnItems = results[0] as List<SaleReturnItemEntity>;
      final saleItems = results[1] as List<SaleItemEntity>;
      final saleItemsById = {for (final value in saleItems) value.id: value};

      return LanSaleReturnDetails(
        summary: LanSaleReturnSummary(
          id: ret.id,
          saleId: ret.saleId,
          saleInvoiceNumber: ret.saleInvoiceNumber,
          customerName: ret.customerName,
          customerPhone: ret.customerPhone,
          customerId: ret.customerId,
          returnNumber: ret.returnNumber,
          subtotalCents: _cents(ret.subtotalCents),
          discountCents: _cents(ret.discountCents),
          taxCents: _cents(ret.taxCents),
          totalCents: _cents(ret.totalCents),
          currencyId: ret.currencyId,
          status: ret.status,
          dispositionType: ret.dispositionType,
          refundMethod: ret.refundMethod,
          reason: ret.reason,
          returnDate: ret.returnDate,
          createdAt: ret.createdAt,
          isAdjustment: false,
          unifiedId: ret.unifiedId,
        ),
        lines: returnItems
            .map((item) {
              final original = saleItemsById[item.saleItemId];
              return LanSaleReturnDetailLine(
                id: item.id,
                returnId: item.returnId,
                saleItemId: item.saleItemId,
                productId: original?.productId ?? 0,
                variantId: original?.variantId,
                productName: item.productName ?? original?.productName ?? '',
                productSku: item.productSku ?? original?.productSku,
                variantSku: item.variantSku ?? original?.variantSku,
                colorName: item.colorName ?? original?.colorName,
                colorHex: item.colorHex ?? original?.colorHex,
                sizeName: item.sizeName ?? original?.sizeName,
                quantity: item.quantity,
                quantityScale: item.quantityScale,
                measurementType: item.measurementType,
                unitPriceCents: original == null
                    ? null
                    : _cents(original.unitPriceCents),
                subtotalCents: _cents(item.subtotalCents),
                discountCents: _cents(item.discountCents),
                taxCents: _cents(item.taxCents),
                totalCents: _cents(item.refundCents),
                reason: item.reason,
                dispositionType: ret.dispositionType,
                createdAt: item.createdAt,
              );
            })
            .toList(growable: false),
        currencyCode: currency.code,
        currencySymbol: currency.symbol,
        currencyDecimalDigits: currency.decimalDigits,
        currencySymbolAfter: currency.symbolPosition == SymbolPosition.after,
        promotionApplications: await _promotions.loadSaleApplications(
          ret.saleId,
        ),
      );
    }

    final ret = await _adjustmentReturns.getSaleAdjReturnById(returnId);
    if (ret == null) return null;
    final currency = await _returnCurrency(ret.currencyId);
    final rows = await _adjustmentReturns
        .watchSaleAdjReturnItemsWithDetails(returnId)
        .first;
    Customer? customer;
    Employee? employee;
    if (ret.customerId != null) {
      customer = await (_database.select(
        _database.customers,
      )..where((row) => row.id.equals(ret.customerId!))).getSingleOrNull();
    }
    if (ret.employeeId != null) {
      employee = await (_database.select(
        _database.employees,
      )..where((row) => row.id.equals(ret.employeeId!))).getSingleOrNull();
    }
    final disposition = rows.isEmpty
        ? 'restock'
        : rows.first.item.dispositionType;

    return LanSaleReturnDetails(
      summary: LanSaleReturnSummary(
        id: ret.id,
        saleId: 0,
        customerName: customer?.name,
        customerPhone: customer?.phone,
        customerId: ret.customerId,
        returnNumber: ret.returnNumber,
        subtotalCents: _cents(ret.subtotalCents),
        discountCents: _cents(ret.discountCents),
        taxCents: _cents(ret.taxCents),
        totalCents: _cents(ret.totalCents),
        currencyId: ret.currencyId,
        status: ret.status,
        dispositionType: disposition,
        refundMethod: ret.refundMethod,
        reason: ret.notes,
        returnDate: ret.returnDate,
        createdAt: ret.createdAt,
        isAdjustment: true,
        unifiedId: 'SRA-${ret.id}',
      ),
      lines: rows
          .map((row) {
            final item = row.item;
            final total = _cents(item.totalCents);
            final discount = _cents(item.discountCents);
            final tax = _cents(item.taxCents);
            return LanSaleReturnDetailLine(
              id: item.id,
              returnId: item.returnId,
              productId: item.productId,
              variantId: item.variantId,
              productName: row.product.name,
              productSku: row.product.sku,
              variantSku: row.variant?.sku,
              variantBarcode: row.variant?.barcode,
              colorName: row.colorName,
              colorHex: row.colorHex,
              quantity: item.quantity,
              quantityScale: item.quantityScale,
              measurementType: item.measurementType,
              unitPriceCents: _cents(item.unitPriceCents),
              subtotalCents: total + discount - tax,
              discountCents: discount,
              taxCents: tax,
              totalCents: total,
              reason: item.reason,
              dispositionType: item.dispositionType,
              createdAt: item.createdAt,
            );
          })
          .toList(growable: false),
      currencyCode: currency.code,
      currencySymbol: currency.symbol,
      currencyDecimalDigits: currency.decimalDigits,
      currencySymbolAfter: currency.symbolPosition == SymbolPosition.after,
      employeeName: employee?.name,
      returnMode: ret.returnMode,
      notes: ret.notes,
    );
  }

  Future<currency_model.Currency> _returnCurrency(int currencyId) async {
    final configured = _currencyService.getCurrency();
    final stored =
        await (_database.select(_database.currencies)
              ..where((row) => row.id.equals(currencyId))
              ..limit(1))
            .getSingleOrNull();
    if (stored == null || stored.code == configured.code) return configured;
    final definition = currency_model.Currency.fromCode(stored.code);
    return currency_model.Currency(
      code: stored.code,
      symbol: stored.symbol,
      name: definition.name,
      symbolPosition: definition.symbolPosition,
      decimalDigits: definition.decimalDigits,
      isCustom: definition.isCustom,
    );
  }

  @override
  Future<LanSaleReturnResult> createSaleReturn({
    required LanRemoteUser actor,
    required LanSaleReturnRequest request,
  }) => _database.transaction(() async {
    _guardRemotePinProtectedOperation();
    final key = request.idempotencyKey.trim();
    if (key.isEmpty || key.length > 120) {
      throw const LanBusinessException(
        'invalid_idempotency_key',
        'A valid request identity is required.',
      );
    }
    final requestReceipts = LanRequestReceiptStore(_database);
    final reservation = await requestReceipts.reserve(
      operation: 'sale_return',
      idempotencyKey: key,
      payload: request.toJson(),
      findLegacyDocument: () async {
        final legacy =
            await (_database.select(_database.saleReturns)
                  ..where((row) => row.idempotencyKey.equals(key))
                  ..limit(1))
                .getSingleOrNull();
        return legacy == null
            ? null
            : LanLegacyRequestDocument(
                id: legacy.id,
                number: legacy.returnNumber,
                totalCents: _cents(legacy.totalCents),
              );
      },
    );
    if (!reservation.shouldCreate) {
      final existing =
          await (_database.select(_database.saleReturns)
                ..where((row) => row.id.equals(reservation.documentId!))
                ..limit(1))
              .getSingleOrNull();
      if (existing == null) {
        throw const LanBusinessException(
          'idempotency_receipt_corrupt',
          'The saved request result is unavailable.',
          statusCode: 409,
        );
      }
      return LanSaleReturnResult(
        returnId: existing.id,
        returnNumber: existing.returnNumber,
        totalCents: _cents(existing.totalCents),
        duplicate: true,
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

    final details = await fetchReturnableSale(saleId: request.saleId);
    if (details == null) {
      throw const LanBusinessException(
        'sale_not_returnable',
        'The sale was not found or has no returnable items.',
        statusCode: 409,
      );
    }
    if (request.refundMethod == 'cheque' && details.sale.customerId == null) {
      throw const LanBusinessException(
        'customer_required_for_cheque_return',
        'A cheque refund requires a customer.',
      );
    }
    final settlementAllocations = request.payments
        .map(
          (payment) => CheckoutPaymentAllocation(
            method: payment.method,
            amountCents: payment.amountCents,
            reference: payment.reference,
            bankName: payment.bankName,
            issueDate: payment.issueDate,
            dueDate: payment.dueDate,
            note: payment.note,
          ),
        )
        .toList(growable: false);
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

    final bundleViolation = PromotionReturnPolicy.validateLinkedReturn(
      promotionApplications: details.promotionApplications,
      previouslyReturnedQuantityBySaleItemId: {
        for (final line in details.lines)
          line.saleItemId: line.linkedReturnedQuantity,
      },
      requestedQuantityBySaleItemId: {
        for (final line in request.lines) line.saleItemId: line.quantity,
      },
    );
    if (bundleViolation != null) {
      throw const LanBusinessException(
        'promotion_bundle_return_required',
        'All items and quantities in this free-item promotion must be returned together.',
        statusCode: 409,
      );
    }

    late final int returnId;
    try {
      returnId = await _activeSales.createSaleReturn(
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
        settlementAllocations: settlementAllocations,
        consignmentLiabilityResponsibility:
            request.consignmentLiabilityResponsibility,
        consignmentLiabilityReason: request.consignmentLiabilityReason,
      );
    } on ConsignmentReturnLiabilityException catch (error) {
      throw LanBusinessException(error.code, error.code, statusCode: 409);
    }
    final created =
        await (_database.select(_database.saleReturns)
              ..where((row) => row.id.equals(returnId))
              ..limit(1))
            .getSingle();
    await requestReceipts.complete(
      operation: 'sale_return',
      idempotencyKey: key,
      payload: request.toJson(),
      documentId: created.id,
      documentNumber: created.returnNumber,
      totalCents: _cents(created.totalCents),
    );
    return LanSaleReturnResult(
      returnId: created.id,
      returnNumber: created.returnNumber,
      totalCents: _cents(created.totalCents),
    );
  });

  @override
  Future<List<LanConsignmentReturnSource>>
  fetchConsignmentAdjustmentReturnSources({
    required int productId,
    int? variantId,
  }) async {
    if (productId <= 0 || (variantId != null && variantId <= 0)) {
      throw const LanBusinessException(
        'invalid_product',
        'A valid product and variant are required.',
      );
    }
    final sources = await _adjustmentReturns
        .getConsignmentAdjustmentReturnSources(
          productId: productId,
          variantId: variantId,
          scope: _activeWarehouseScope,
        );
    return sources
        .map(
          (source) => LanConsignmentReturnSource(
            layerId: source.layerId,
            supplierId: source.supplierId,
            supplierName: source.supplierName,
            receiptNumber: source.receiptNumber,
            receivedAt: source.receivedAt,
            maximumReturnQuantity: source.maximumReturnQuantity,
            quantityScale: source.quantityScale,
            measurementType: source.measurementType,
            batchNumber: source.batchNumber,
            manufacturerLotNumber: source.manufacturerLotNumber,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<LanProductStockSourceSnapshot> fetchInventoryStockSources({
    required int productId,
    int? variantId,
  }) async {
    if (productId <= 0 || (variantId != null && variantId <= 0)) {
      throw const LanBusinessException(
        'invalid_product',
        'A valid product and variant are required.',
      );
    }
    late final ProductStockSourceSnapshot snapshot;
    try {
      snapshot = await InventoryStockSourceService(_database).loadProduct(
        productId,
        variantId: variantId,
        scope: _activeWarehouseScope,
      );
    } on StockSourceIntegrityException catch (error) {
      throw LanBusinessException(
        error.messageKey,
        error.messageKey,
        statusCode: 409,
      );
    }
    return LanProductStockSourceSnapshot(
      productId: snapshot.productId,
      warehouseId: snapshot.warehouseId,
      physicalQuantity: snapshot.physicalQuantity,
      enterpriseQuantity: snapshot.enterpriseQuantity,
      consignmentQuantity: snapshot.consignmentQuantity,
      quantityScale: snapshot.quantityScale,
      measurementType: snapshot.measurementType,
      reconciled: snapshot.reconciled,
      sources: snapshot.sources
          .map(
            (source) => LanInventoryStockSource(
              productId: source.productId,
              variantId: source.variantId,
              quantity: source.quantity,
              quantityScale: source.quantityScale,
              measurementType: source.measurementType,
              ownership: source.ownership.name,
              variantLabel: source.variantLabel,
              supplierId: source.supplierId,
              supplierName: source.supplierName,
              supplierIdentityId: source.supplierIdentityId,
              consignmentLayerId: source.consignmentLayerId,
              sourceCode: source.sourceCode,
              receiptNumber: source.receiptNumber,
              batchNumber: source.batchNumber,
            ),
          )
          .toList(growable: false),
    );
  }

  @override
  Future<LanSaleReturnResult> createSaleAdjustmentReturn({
    required LanRemoteUser actor,
    required LanSaleAdjustmentReturnRequest request,
  }) => _database.transaction(() async {
    // The request reservation, document posting, and receipt completion all
    // participate in this outer transaction; any failure rolls all three back.
    _guardRemotePinProtectedOperation();
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
    final settlementAllocations = request.payments
        .map(
          (payment) => CheckoutPaymentAllocation(
            method: payment.method,
            amountCents: payment.amountCents,
            reference: payment.reference,
            bankName: payment.bankName,
            issueDate: payment.issueDate?.toLocal(),
            dueDate: payment.dueDate?.toLocal(),
            note: payment.note,
          ),
        )
        .toList(growable: false);
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

    final requestReceipts = LanRequestReceiptStore(_database);
    final reservation = await requestReceipts.reserve(
      operation: 'sale_adjustment_return',
      idempotencyKey: key,
      payload: request.toJson(),
      findLegacyDocument: () async {
        final legacy =
            await (_database.select(_database.saleReturnAdjustments)
                  ..where((row) => row.idempotencyKey.equals(key))
                  ..limit(1))
                .getSingleOrNull();
        return legacy == null
            ? null
            : LanLegacyRequestDocument(
                id: legacy.id,
                number: legacy.returnNumber,
                totalCents: _cents(legacy.totalCents),
              );
      },
    );
    if (!reservation.shouldCreate) {
      final existing =
          await (_database.select(_database.saleReturnAdjustments)
                ..where((row) => row.id.equals(reservation.documentId!))
                ..limit(1))
              .getSingleOrNull();
      if (existing == null) {
        throw const LanBusinessException(
          'idempotency_receipt_corrupt',
          'The saved request result is unavailable.',
          statusCode: 409,
        );
      }
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
            request.refundMethod == 'cheque' ||
            settlementAllocations.isNotEmpty) &&
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
    final products = await WarehouseCatalogScope.readProducts(
      _database,
      productIds,
      scope: await _activeReadScope(),
    );
    final productMap = {for (final value in products) value.id: value};
    final variantIds = request.lines
        .map((line) => line.variantId)
        .whereType<int>()
        .toSet()
        .toList(growable: false);
    final variants = await WarehouseCatalogScope.readVariants(
      _database,
      variantIds,
      scope: await _activeReadScope(),
    );
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
      const sourceResolutions = {
        'supplier_identity',
        'consignment',
        'unverified',
        'not_applicable',
      };
      if (!sourceResolutions.contains(line.sourceResolution) ||
          (product.trackInventory &&
              line.sourceResolution == 'not_applicable') ||
          (!product.trackInventory &&
              line.sourceResolution != 'not_applicable') ||
          (line.sourceResolution == 'supplier_identity' &&
              (line.supplierIdentityId == null ||
                  line.consignmentLayerId != null)) ||
          (line.sourceResolution == 'consignment' &&
              (line.consignmentLayerId == null ||
                  line.supplierIdentityId != null)) ||
          (line.sourceResolution == 'unverified' &&
              (line.supplierIdentityId != null ||
                  line.consignmentLayerId != null ||
                  (line.sourceResolutionReason?.trim().isEmpty ?? true)))) {
        throw const LanBusinessException(
          'returns.source_decision_required',
          'Choose and document the inventory source for every return line.',
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
    final policy = await BranchTaxPolicyStore(_database).read();
    if (policy == null && _settings.requiresPersistedTaxPolicy) {
      throw const LanBusinessException(
        'tax_policy_unavailable',
        'The branch tax policy is unavailable.',
        statusCode: 409,
      );
    }
    final appSettings =
        policy?.policy.applyTo(_settings.current) ?? _settings.current;
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
    if (request.expectedPricingFingerprint != null &&
        request.expectedPricingFingerprint !=
            pricingPreviewFingerprint(
              pricing,
              taxInclusive: appSettings.taxInclusivePricing,
            )) {
      throw const LanBusinessException(
        'pricing_preview_changed',
        'Pricing changed. Refresh and review the return before submitting again.',
        statusCode: 409,
      );
    }
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
      refundMethod: Value(
        settlementAllocations.isEmpty ? request.refundMethod : 'mixed',
      ),
      dueDate: Value(
        settlementAllocations.isEmpty ? request.dueDate?.toLocal() : null,
      ),
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
          itemDiscountAtPostCents: Value(
            Decimal.fromInt(line.local.discount.cents),
          ),
          invoiceDiscountAtPostCents: Value(
            Decimal.fromInt(line.shareOfOverallDiscount.cents),
          ),
          consignmentLayerId: Value(value.request.consignmentLayerId),
          supplierIdentityId: Value(value.request.supplierIdentityId),
          sourceResolution: Value(value.request.sourceResolution),
          sourceResolutionReason: Value(value.request.sourceResolutionReason),
          sourceResolvedBy: Value(actor.id),
          sourceResolvedAt: Value(DateTime.now()),
          taxCents: Value(Decimal.fromInt(line.tax.cents)),
          totalCents: Decimal.fromInt(line.total.cents),
          reason: Value(value.request.reason),
          taxRateBpsAtPost: Value(line.local.effectiveTaxRateBps),
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
        settlementAllocations: settlementAllocations,
        scope: _activeWarehouseScope,
      );
      final created = await _adjustmentReturns.getSaleAdjReturnById(returnId);
      if (created == null) {
        throw const LanBusinessException(
          'return_creation_failed',
          'The return could not be loaded after posting.',
          statusCode: 500,
        );
      }
      await requestReceipts.complete(
        operation: 'sale_adjustment_return',
        idempotencyKey: key,
        payload: request.toJson(),
        documentId: created.id,
        documentNumber: created.returnNumber,
        totalCents: _cents(created.totalCents),
      );
      return LanSaleReturnResult(
        returnId: created.id,
        returnNumber: created.returnNumber,
        totalCents: _cents(created.totalCents),
      );
    } on LanBusinessException {
      rethrow;
    } on SupplierIdentityException catch (error) {
      throw LanBusinessException(
        error.messageKey,
        error.messageKey,
        statusCode: 409,
      );
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
  });

  @override
  Future<List<LanSupplierSummary>> fetchSuppliers({
    required String query,
    required int limit,
  }) async {
    final normalized = query.trim();
    final statement = _database.select(_database.suppliers)
      ..where((row) {
        var expression = row.isActive.equals(true);
        if (normalized.isNotEmpty) {
          final pattern = '%$normalized%';
          expression =
              expression & (row.name.like(pattern) | row.phone.like(pattern));
        }
        return expression;
      })
      ..orderBy([(row) => OrderingTerm.asc(row.name)])
      ..limit(limit.clamp(1, 200));
    final rows = await statement.get();
    return rows
        .map(
          (row) => LanSupplierSummary(
            id: row.id,
            name: row.name,
            phone: row.phone,
            productCode: row.productCode,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<LanReturnablePurchasesPage> fetchReturnablePurchases({
    required String query,
    required int offset,
    required int limit,
  }) async {
    final safeOffset = offset.clamp(0, 1000000);
    final safeLimit = limit.clamp(1, 200);
    final normalized = query.trim().toLowerCase();
    final allowed = await _activeDocumentIds(InventoryPostingDocument.purchase);
    final all = (await _activePurchases.watchAllPurchases().first).where(
      (value) => allowed.contains(value.id),
    );
    final candidates = all.where(
      (value) =>
          value.isPosted &&
          (normalized.isEmpty ||
              value.purchaseNumber.toLowerCase().contains(normalized) ||
              (value.supplierName?.toLowerCase().contains(normalized) ??
                  false) ||
              (value.supplierPhone?.toLowerCase().contains(normalized) ??
                  false)),
    );
    final returnable = <LanReturnablePurchaseSummary>[];
    for (final purchase in candidates) {
      final items = await _activePurchases.getPurchaseItems(purchase.id);
      var actualCount = 0;
      for (final item in items) {
        final returned = await _activePurchases.getReturnedQuantity(item.id);
        if (returned < item.quantity) actualCount++;
      }
      if (actualCount == 0) continue;
      returnable.add(
        LanReturnablePurchaseSummary(
          purchaseId: purchase.id,
          purchaseNumber: purchase.purchaseNumber,
          supplierId: purchase.supplierId,
          supplierName: purchase.supplierName,
          purchaseDate: purchase.purchaseDate,
          totalCents: _cents(purchase.totalCents),
          paymentMethod: purchase.paymentMethod ?? 'credit',
          currencyId: purchase.currencyId,
          taxInclusiveAtPost: purchase.taxInclusiveAtPost,
          returnableLineCount: actualCount,
        ),
      );
    }
    final pageRows = returnable
        .skip(safeOffset)
        .take(safeLimit + 1)
        .toList(growable: false);
    return LanReturnablePurchasesPage(
      purchases: pageRows.take(safeLimit).toList(growable: false),
      offset: safeOffset,
      limit: safeLimit,
      hasMore: pageRows.length > safeLimit,
    );
  }

  @override
  Future<LanReturnablePurchaseDetails?> fetchReturnablePurchase({
    required int purchaseId,
  }) async {
    if (!await _containsActiveDocument(
      InventoryPostingDocument.purchase,
      purchaseId,
    )) {
      return null;
    }
    final purchase = await _activePurchases.getPurchaseById(purchaseId);
    if (purchase == null || !purchase.isPosted) return null;
    final items = await _activePurchases.getPurchaseItems(purchaseId);
    final lines = <LanReturnablePurchaseLine>[];
    for (final item in items) {
      final returned = await _activePurchases.getReturnedQuantity(item.id);
      final available = item.quantity - returned;
      if (available <= 0) continue;
      final history = await _activePurchases.getLinkedReturnHistory(item.id);
      lines.add(
        LanReturnablePurchaseLine(
          purchaseItemId: item.id,
          productId: item.productId,
          variantId: item.variantId,
          productName: item.productName ?? 'Product #${item.productId}',
          variantSku: item.variantSku,
          colorName: item.colorName,
          colorHex: item.colorHex,
          sizeName: item.sizeName,
          originalQuantity: item.quantity,
          returnedQuantity: returned,
          availableQuantity: available,
          currentStockQuantity: item.currentStockQuantity,
          tracksInventory: item.tracksInventory,
          quantityScale: item.quantityScale,
          measurementType: item.measurementType,
          unitCostCents: _cents(item.unitCostCents),
          subtotalCents: _cents(item.subtotalCents),
          discountCents: _cents(item.discountCents),
          taxCents: _cents(item.taxCents),
          totalCents: _cents(item.totalCents),
          linkedReturnedQuantity: history.quantity,
          linkedReturnedSubtotalCents: history.subtotalCents,
          linkedReturnedDiscountCents: history.discountCents,
          linkedReturnedTaxCents: history.taxCents,
          linkedReturnedRefundCents: history.refundCents,
        ),
      );
    }
    if (lines.isEmpty) return null;
    return LanReturnablePurchaseDetails(
      purchase: LanReturnablePurchaseSummary(
        purchaseId: purchase.id,
        purchaseNumber: purchase.purchaseNumber,
        supplierId: purchase.supplierId,
        supplierName: purchase.supplierName,
        purchaseDate: purchase.purchaseDate,
        totalCents: _cents(purchase.totalCents),
        paymentMethod: purchase.paymentMethod ?? 'credit',
        currencyId: purchase.currencyId,
        taxInclusiveAtPost: purchase.taxInclusiveAtPost,
        returnableLineCount: lines.length,
      ),
      lines: lines,
    );
  }

  LanPurchaseReturnSummary _purchaseReturnSummary(PurchaseReturnEntity value) =>
      LanPurchaseReturnSummary(
        id: value.id,
        purchaseId: value.purchaseId,
        supplierId: value.supplierId,
        supplierName: value.supplierName,
        supplierPhone: value.supplierPhone,
        returnNumber: value.returnNumber,
        subtotalCents: _cents(value.subtotalCents),
        discountCents: _cents(value.discountCents),
        taxCents: _cents(value.taxCents),
        totalCents: _cents(value.totalCents),
        currencyId: value.currencyId,
        status: value.status,
        dispositionType: value.dispositionType,
        refundMethod: value.refundMethod,
        reason: value.reason,
        returnDate: value.returnDate,
        createdAt: value.createdAt,
        isAdjustment: value.isAdjustment,
        unifiedId: value.unifiedId,
      );

  @override
  Future<LanPurchaseReturnsPage> fetchPurchaseReturns({
    required String query,
    required int offset,
    required int limit,
  }) async {
    final safeOffset = offset.clamp(0, 1000000);
    final safeLimit = limit.clamp(1, 200);
    final normalized = query.trim().toLowerCase();
    final linkedIds = await _activeDocumentIds(
      InventoryPostingDocument.purchaseReturn,
    );
    final adjustmentIds = await _activeDocumentIds(
      InventoryPostingDocument.purchaseAdjustment,
    );
    final all = (await _activePurchases.watchAllPurchaseReturns().first)
        .where(
          (value) => (value.isAdjustment ? adjustmentIds : linkedIds).contains(
            value.id,
          ),
        )
        .toList(growable: false);
    final filtered = normalized.isEmpty
        ? all
        : all
              .where(
                (value) =>
                    value.returnNumber.toLowerCase().contains(normalized) ||
                    (value.supplierName?.toLowerCase().contains(normalized) ??
                        false) ||
                    (value.supplierPhone?.toLowerCase().contains(normalized) ??
                        false),
              )
              .toList(growable: false);
    final pageRows = filtered
        .skip(safeOffset)
        .take(safeLimit + 1)
        .toList(growable: false);
    final summaries = <LanPurchaseReturnSummary>[];
    for (final value in pageRows.take(safeLimit)) {
      final summary = _purchaseReturnSummary(value);
      String? number;
      if (!value.isAdjustment && value.purchaseId > 0) {
        number = (await _activePurchases.getPurchaseById(
          value.purchaseId,
        ))?.purchaseNumber;
      }
      summaries.add(
        LanPurchaseReturnSummary(
          id: summary.id,
          purchaseId: summary.purchaseId,
          purchaseNumber: number,
          supplierId: summary.supplierId,
          supplierName: summary.supplierName,
          supplierPhone: summary.supplierPhone,
          returnNumber: summary.returnNumber,
          subtotalCents: summary.subtotalCents,
          discountCents: summary.discountCents,
          taxCents: summary.taxCents,
          totalCents: summary.totalCents,
          currencyId: summary.currencyId,
          status: summary.status,
          dispositionType: summary.dispositionType,
          refundMethod: summary.refundMethod,
          reason: summary.reason,
          returnDate: summary.returnDate,
          createdAt: summary.createdAt,
          isAdjustment: summary.isAdjustment,
          unifiedId: summary.unifiedId,
        ),
      );
    }
    return LanPurchaseReturnsPage(
      returns: summaries,
      offset: safeOffset,
      limit: safeLimit,
      hasMore: pageRows.length > safeLimit,
    );
  }

  @override
  Future<LanPurchaseReturnDetails?> fetchPurchaseReturnDetails({
    required int returnId,
    required bool adjustment,
  }) async {
    if (!await _containsActiveDocument(
      adjustment
          ? InventoryPostingDocument.purchaseAdjustment
          : InventoryPostingDocument.purchaseReturn,
      returnId,
    )) {
      return null;
    }
    if (!adjustment) {
      final ret = await _activePurchases.getPurchaseReturnById(returnId);
      if (ret == null || ret.isAdjustment) return null;
      final purchase = await _activePurchases.getPurchaseById(ret.purchaseId);
      final originals = await _activePurchases.getPurchaseItems(ret.purchaseId);
      final byId = {for (final item in originals) item.id: item};
      final items = await _purchases
          .watchPurchaseReturnItemsWithDetails(returnId)
          .first;
      final base = _purchaseReturnSummary(ret);
      return LanPurchaseReturnDetails(
        summary: LanPurchaseReturnSummary(
          id: base.id,
          purchaseId: base.purchaseId,
          purchaseNumber: purchase?.purchaseNumber,
          supplierId: purchase?.supplierId ?? base.supplierId,
          supplierName: purchase?.supplierName ?? base.supplierName,
          supplierPhone: purchase?.supplierPhone ?? base.supplierPhone,
          returnNumber: base.returnNumber,
          subtotalCents: base.subtotalCents,
          discountCents: base.discountCents,
          taxCents: base.taxCents,
          totalCents: base.totalCents,
          currencyId: base.currencyId,
          status: base.status,
          dispositionType: base.dispositionType,
          refundMethod: base.refundMethod,
          reason: base.reason,
          returnDate: base.returnDate,
          createdAt: base.createdAt,
          isAdjustment: false,
          unifiedId: base.unifiedId,
        ),
        lines: items
            .map((item) {
              final original = byId[item.purchaseItemId];
              return LanPurchaseReturnDetailLine(
                id: item.id,
                returnId: item.returnId,
                purchaseItemId: item.purchaseItemId,
                productId: original?.productId ?? 0,
                variantId: original?.variantId,
                productName: item.productName ?? original?.productName ?? '',
                variantSku: item.variantSku ?? original?.variantSku,
                variantBarcode: item.variantBarcode,
                colorName: item.colorName ?? original?.colorName,
                colorHex: item.colorHex ?? original?.colorHex,
                sizeName: item.sizeName ?? original?.sizeName,
                quantity: item.quantity,
                quantityScale: item.quantityScale,
                measurementType: item.measurementType,
                unitPriceCents: original == null
                    ? null
                    : _cents(original.unitCostCents),
                subtotalCents: _cents(item.subtotalCents),
                discountCents: _cents(item.discountCents),
                taxCents: _cents(item.taxCents),
                totalCents: _cents(item.refundCents),
                reason: item.reason,
                dispositionType: ret.dispositionType,
                createdAt: item.createdAt,
              );
            })
            .toList(growable: false),
        originalPurchase: purchase == null
            ? null
            : LanReturnablePurchaseSummary(
                purchaseId: purchase.id,
                purchaseNumber: purchase.purchaseNumber,
                supplierId: purchase.supplierId,
                supplierName: purchase.supplierName,
                purchaseDate: purchase.purchaseDate,
                totalCents: _cents(purchase.totalCents),
                paymentMethod: purchase.paymentMethod ?? 'credit',
                currencyId: purchase.currencyId,
                taxInclusiveAtPost: purchase.taxInclusiveAtPost,
                returnableLineCount: 0,
              ),
      );
    }

    final ret = await _adjustmentReturns.getPurchaseAdjReturnById(returnId);
    if (ret == null) return null;
    final supplier =
        await (_database.select(_database.suppliers)
              ..where((row) => row.id.equals(ret.supplierId))
              ..limit(1))
            .getSingleOrNull();
    final rows = await _adjustmentReturns
        .watchPurchaseAdjReturnItemsWithDetails(returnId)
        .first;
    final disposition = rows.isEmpty
        ? 'restock'
        : rows.first.item.dispositionType;
    return LanPurchaseReturnDetails(
      summary: LanPurchaseReturnSummary(
        id: ret.id,
        purchaseId: 0,
        supplierId: ret.supplierId,
        supplierName: supplier?.name,
        supplierPhone: supplier?.phone,
        returnNumber: ret.returnNumber,
        subtotalCents: _cents(ret.subtotalCents),
        discountCents: _cents(ret.discountCents),
        taxCents: _cents(ret.taxCents),
        totalCents: _cents(ret.totalCents),
        currencyId: ret.currencyId,
        status: ret.status,
        dispositionType: disposition,
        refundMethod: ret.refundMethod,
        reason: ret.notes,
        returnDate: ret.returnDate,
        createdAt: ret.createdAt,
        isAdjustment: true,
        unifiedId: 'PRA-${ret.id}',
      ),
      lines: rows
          .map((row) {
            final item = row.item;
            final total = _cents(item.totalCents);
            final discount = _cents(item.discountCents);
            final tax = _cents(item.taxCents);
            return LanPurchaseReturnDetailLine(
              id: item.id,
              returnId: item.returnId,
              productId: item.productId,
              variantId: item.variantId,
              productName: row.product.name,
              variantSku: row.variant?.sku,
              variantBarcode: row.variant?.barcode,
              colorName: row.colorName,
              colorHex: row.colorHex,
              quantity: item.quantity,
              quantityScale: item.quantityScale,
              measurementType: item.measurementType,
              unitPriceCents: _cents(item.unitPriceCents),
              subtotalCents: total + discount - tax,
              discountCents: discount,
              taxCents: tax,
              totalCents: total,
              reason: item.reason,
              dispositionType: item.dispositionType,
              createdAt: item.createdAt,
            );
          })
          .toList(growable: false),
    );
  }

  List<CheckoutPaymentAllocation> _purchaseReturnAllocations(
    List<LanCheckoutPaymentRequest> payments,
  ) => payments
      .map(
        (payment) => CheckoutPaymentAllocation(
          method: payment.method,
          amountCents: payment.amountCents,
          reference: payment.reference,
          bankName: payment.bankName,
          issueDate: payment.issueDate?.toLocal(),
          dueDate: payment.dueDate?.toLocal(),
          note: payment.note,
        ),
      )
      .toList(growable: false);

  @override
  Future<LanPurchaseReturnResult> createPurchaseReturn({
    required LanRemoteUser actor,
    required LanPurchaseReturnRequest request,
  }) => _database.transaction(() async {
    // Reservation, return posting, and receipt completion are committed as a
    // single unit so a rejected return leaves no stale pending identity.
    _guardRemotePinProtectedOperation();
    final key = request.idempotencyKey.trim();
    if (key.length < 8 || key.length > 128 || request.lines.isEmpty) {
      throw const LanBusinessException(
        'invalid_purchase_return',
        'A valid purchase and at least one return line are required.',
      );
    }
    const methods = {'cash', 'card', 'credit', 'cheque'};
    if (!methods.contains(request.refundMethod)) {
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
    final dispositionError = PurchaseReturnDispositionPolicy.validate(
      disposition: request.dispositionType,
      refundMethod: request.refundMethod,
      reason: request.reason,
      hasSettlementAllocations: request.payments.isNotEmpty,
    );
    if (dispositionError != null) {
      throw LanBusinessException(dispositionError, dispositionError);
    }
    final requestReceipts = LanRequestReceiptStore(_database);
    final reservation = await requestReceipts.reserve(
      operation: 'purchase_return',
      idempotencyKey: key,
      payload: request.toJson(),
      findLegacyDocument: () async {
        final legacy =
            await (_database.select(_database.purchaseReturns)
                  ..where((row) => row.idempotencyKey.equals(key))
                  ..limit(1))
                .getSingleOrNull();
        return legacy == null
            ? null
            : LanLegacyRequestDocument(
                id: legacy.id,
                number: legacy.returnNumber,
                totalCents: _cents(legacy.totalCents),
              );
      },
    );
    if (!reservation.shouldCreate) {
      final existing =
          await (_database.select(_database.purchaseReturns)
                ..where((row) => row.id.equals(reservation.documentId!))
                ..limit(1))
              .getSingleOrNull();
      if (existing == null) {
        throw const LanBusinessException(
          'idempotency_receipt_corrupt',
          'The saved request result is unavailable.',
          statusCode: 409,
        );
      }
      if (!await _containsActiveDocument(
        InventoryPostingDocument.purchaseReturn,
        existing.id,
      )) {
        throw const LanBusinessException(
          'purchase_return_not_found',
          'The saved request belongs to another warehouse.',
          statusCode: 404,
        );
      }
      return LanPurchaseReturnResult(
        returnId: existing.id,
        returnNumber: existing.returnNumber,
        totalCents: _cents(existing.totalCents),
        duplicate: true,
      );
    }
    final details = await fetchReturnablePurchase(
      purchaseId: request.purchaseId,
    );
    if (details == null) {
      throw const LanBusinessException(
        'purchase_not_returnable',
        'The purchase was not found or has no returnable items.',
        statusCode: 409,
      );
    }
    final byId = {for (final line in details.lines) line.purchaseItemId: line};
    final seen = <int>{};
    final items = <PurchaseReturnItemInput>[];
    for (final requested in request.lines) {
      final source = byId[requested.purchaseItemId];
      if (source == null ||
          requested.quantity <= 0 ||
          requested.quantity > source.availableQuantity ||
          !seen.add(requested.purchaseItemId)) {
        throw const LanBusinessException(
          'invalid_return_quantity',
          'A return line is invalid or exceeds the available quantity.',
          statusCode: 409,
        );
      }
      items.add(
        PurchaseReturnItemInput(
          purchaseItemId: requested.purchaseItemId,
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
    try {
      final returnId = await _activePurchases.createPurchaseReturn(
        purchaseId: request.purchaseId,
        currencyId: details.purchase.currencyId,
        subtotalCents: Decimal.zero,
        discountCents: Decimal.zero,
        taxCents: Decimal.zero,
        totalCents: Decimal.zero,
        items: items,
        dispositionType: request.dispositionType,
        refundMethod: request.refundMethod,
        reason: request.reason,
        returnDate: DateTime.now(),
        dueDate: request.dueDate?.toLocal(),
        allowNegativeStock: _settings.current.allowNegativeStock,
        idempotencyKey: key,
        taxInclusiveAtPost: details.purchase.taxInclusiveAtPost,
        settlementAllocations: _purchaseReturnAllocations(request.payments),
        actorUserId: actor.id,
      );
      final created = await _activePurchases.getPurchaseReturnById(returnId);
      if (created == null) throw StateError('Purchase return not found');
      await requestReceipts.complete(
        operation: 'purchase_return',
        idempotencyKey: key,
        payload: request.toJson(),
        documentId: created.id,
        documentNumber: created.returnNumber,
        totalCents: _cents(created.totalCents),
      );
      return LanPurchaseReturnResult(
        returnId: created.id,
        returnNumber: created.returnNumber,
        totalCents: _cents(created.totalCents),
      );
    } catch (error) {
      throw LanBusinessException(
        'purchase_return_rejected',
        error.toString().replaceFirst('Exception: ', ''),
        statusCode: 409,
      );
    }
  });

  @override
  Future<LanPurchaseReturnResult> createPurchaseAdjustmentReturn({
    required LanRemoteUser actor,
    required LanPurchaseAdjustmentReturnRequest request,
  }) => _database.transaction(() async {
    // The outer transaction makes the reservation and posted return one
    // durable outcome; an exception rolls the pending receipt back.
    _guardRemotePinProtectedOperation();
    final key = request.idempotencyKey.trim();
    if (key.length < 8 || key.length > 128 || request.lines.isEmpty) {
      throw const LanBusinessException(
        'invalid_purchase_return',
        'A supplier and at least one return line are required.',
      );
    }
    final supplier =
        await (_database.select(_database.suppliers)
              ..where(
                (row) =>
                    row.id.equals(request.supplierId) &
                    row.isActive.equals(true),
              )
              ..limit(1))
            .getSingleOrNull();
    if (supplier == null) {
      throw const LanBusinessException(
        'supplier_unavailable',
        'The selected supplier is unavailable.',
        statusCode: 409,
      );
    }
    const methods = {'cash', 'card', 'credit', 'cheque'};
    if (!methods.contains(request.refundMethod)) {
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
    if (request.overallDiscountCents < 0 ||
        (request.overallDiscountIsPercent &&
            request.overallDiscountCents > 10000)) {
      throw const LanBusinessException(
        'invalid_discount',
        'The overall discount is invalid.',
      );
    }
    final requestReceipts = LanRequestReceiptStore(_database);
    final reservation = await requestReceipts.reserve(
      operation: 'purchase_adjustment_return',
      idempotencyKey: key,
      payload: request.toJson(),
      findLegacyDocument: () async {
        final legacy =
            await (_database.select(_database.purchaseReturnAdjustments)
                  ..where((row) => row.idempotencyKey.equals(key))
                  ..limit(1))
                .getSingleOrNull();
        return legacy == null
            ? null
            : LanLegacyRequestDocument(
                id: legacy.id,
                number: legacy.returnNumber,
                totalCents: _cents(legacy.totalCents),
              );
      },
    );
    if (!reservation.shouldCreate) {
      final existing =
          await (_database.select(_database.purchaseReturnAdjustments)
                ..where((row) => row.id.equals(reservation.documentId!))
                ..limit(1))
              .getSingleOrNull();
      if (existing == null) {
        throw const LanBusinessException(
          'idempotency_receipt_corrupt',
          'The saved request result is unavailable.',
          statusCode: 409,
        );
      }
      return LanPurchaseReturnResult(
        returnId: existing.id,
        returnNumber: existing.returnNumber,
        totalCents: _cents(existing.totalCents),
        duplicate: true,
      );
    }
    final productIds = request.lines.map((line) => line.productId).toSet();
    final products = await WarehouseCatalogScope.readProducts(
      _database,
      productIds.toList(),
      scope: await _activeReadScope(),
    );
    final productMap = {for (final value in products) value.id: value};
    final variantIds = request.lines
        .map((line) => line.variantId)
        .whereType<int>()
        .toSet();
    final variants = await WarehouseCatalogScope.readVariants(
      _database,
      variantIds.toList(),
      scope: await _activeReadScope(),
    );
    final variantMap = {for (final value in variants) value.id: value};
    final inputs = <LineItemPricingInput>[];
    final resolved =
        <
          ({
            LanPurchaseAdjustmentReturnLineRequest request,
            Product product,
            ProductVariant? variant,
            int scale,
            int taxRate,
          })
        >[];
    for (final line in request.lines) {
      final product = productMap[line.productId];
      final variant = line.variantId == null
          ? null
          : variantMap[line.variantId];
      if (product == null ||
          !product.isActive ||
          (product.hasVariants && line.variantId == null) ||
          (line.variantId != null &&
              (variant == null ||
                  variant.productId != product.id ||
                  !variant.isActive)) ||
          line.quantity <= 0 ||
          line.unitPriceCents < 0 ||
          line.discountCents < 0 ||
          line.discountPercentBps < 0 ||
          line.discountPercentBps > 10000 ||
          (line.discountCents > 0 && line.discountPercentBps > 0)) {
        throw const LanBusinessException(
          'invalid_return_line',
          'A selected return line is invalid.',
        );
      }
      final scale = MeasurementType.fromDb(
        product.measurementType,
      ).quantityScale;
      final taxRate = product.isTaxable ? product.purchaseTaxRateBps : 0;
      final discount = line.discountPercentBps > 0
          ? Discount.percent(line.discountPercentBps)
          : line.discountCents > 0
          ? Discount.fixed(Money.fromCents(line.discountCents))
          : Discount.none;
      inputs.add(
        LineItemPricingInput(
          unitPrice: Money.fromCents(line.unitPriceCents),
          quantity: line.quantity,
          quantityScale: scale,
          discount: discount,
          isTaxable: product.isTaxable,
          productTaxRateBps: taxRate,
        ),
      );
      resolved.add((
        request: line,
        product: product,
        variant: variant,
        scale: scale,
        taxRate: taxRate,
      ));
    }
    final overall = request.overallDiscountIsPercent
        ? Discount.percent(request.overallDiscountCents)
        : request.overallDiscountCents > 0
        ? Discount.fixed(Money.fromCents(request.overallDiscountCents))
        : Discount.none;
    final policy = await BranchTaxPolicyStore(_database).read();
    if (policy == null && _settings.requiresPersistedTaxPolicy) {
      throw const LanBusinessException(
        'tax_policy_unavailable',
        'The branch tax policy is unavailable.',
        statusCode: 409,
      );
    }
    final appSettings =
        policy?.policy.applyTo(_settings.current) ?? _settings.current;
    final pricing = InvoicePricingEngine.compute(
      InvoicePricingInput(
        lines: inputs,
        overallDiscount: overall,
        enableTaxCalculations: appSettings.enableTaxCalculations,
        defaultTaxRateBps: (appSettings.defaultPurchaseTaxRate * 100).round(),
        taxInclusivePricing: appSettings.taxInclusivePricing,
      ),
    );
    final expected = request.expectedPricingFingerprint;
    if (expected != null &&
        expected !=
            pricingPreviewFingerprint(
              pricing,
              taxInclusive: appSettings.taxInclusivePricing,
            )) {
      throw const LanBusinessException(
        'pricing_preview_changed',
        'Pricing changed. Refresh and review the return before submitting again.',
        statusCode: 409,
      );
    }
    final currency = await _selectedCurrency();
    if (currency == null) {
      throw const LanBusinessException(
        'currency_unavailable',
        'The master currency is unavailable.',
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
    final cleanNotes = request.notes?.trim();
    final notes =
        '[REASON:${request.reasonCode}]${cleanNotes == null || cleanNotes.isEmpty ? '' : ' $cleanNotes'}';
    final allocations = _purchaseReturnAllocations(request.payments);
    final data = PurchaseReturnAdjustmentsCompanion.insert(
      returnNumber: '',
      supplierId: request.supplierId,
      currencyId: currency.id,
      subtotalCents: Value(Decimal.fromInt(pricing.subtotal.cents)),
      discountCents: Value(Decimal.fromInt(pricing.totalDiscount.cents)),
      taxCents: Value(Decimal.fromInt(pricing.tax.cents)),
      totalCents: Decimal.fromInt(pricing.total.cents),
      notes: Value(notes),
      returnDate: Value(request.returnDate.toLocal()),
      refundMethod: Value(allocations.isEmpty ? request.refundMethod : 'mixed'),
      dueDate: Value(allocations.isEmpty ? request.dueDate?.toLocal() : null),
      idempotencyKey: Value(key),
      returnMode: const Value('auto_adjustment'),
      modeReason: const Value('Remote unlinked purchase return'),
    ).withPricingSnapshot(taxInclusive: appSettings.taxInclusivePricing);
    final itemRows = <PurchaseReturnAdjustmentItemsCompanion>[];
    for (var index = 0; index < resolved.length; index++) {
      final value = resolved[index];
      final line = pricing.lines[index];
      itemRows.add(
        PurchaseReturnAdjustmentItemsCompanion.insert(
          returnId: 0,
          productId: value.product.id,
          variantId: Value(value.variant?.id),
          quantity: value.request.quantity,
          quantityScale: Value(value.scale),
          measurementType: Value(value.product.measurementType),
          unitPriceCents: Decimal.fromInt(value.request.unitPriceCents),
          discountCents: Value(Decimal.fromInt(line.totalLineDiscount.cents)),
          taxCents: Value(Decimal.fromInt(line.tax.cents)),
          totalCents: Decimal.fromInt(line.total.cents),
          reason: Value(value.request.reason),
          taxRateBpsAtPost: Value(line.local.effectiveTaxRateBps),
          dispositionType: const Value('restock'),
        ),
      );
    }
    try {
      final returnId = await _adjustmentReturns.createAndPostPurchaseAdjReturn(
        data,
        itemRows,
        journalEntryService: _journalEntries,
        userId: actor.id,
        allowNegativeStock: _settings.current.allowNegativeStock,
        settlementAllocations: allocations,
        scope: _activeWarehouseScope,
      );
      final created = await _adjustmentReturns.getPurchaseAdjReturnById(
        returnId,
      );
      if (created == null) throw StateError('Purchase return not found');
      await requestReceipts.complete(
        operation: 'purchase_adjustment_return',
        idempotencyKey: key,
        payload: request.toJson(),
        documentId: created.id,
        documentNumber: created.returnNumber,
        totalCents: _cents(created.totalCents),
      );
      return LanPurchaseReturnResult(
        returnId: created.id,
        returnNumber: created.returnNumber,
        totalCents: _cents(created.totalCents),
      );
    } catch (error) {
      throw LanBusinessException(
        'purchase_return_rejected',
        error.toString().replaceFirst('Exception: ', ''),
        statusCode: 409,
      );
    }
  });

  @override
  Future<void> voidPurchaseReturn({
    required LanRemoteUser actor,
    required int returnId,
    required bool adjustment,
  }) async {
    _guardRemotePinProtectedOperation();
    final kind = adjustment
        ? InventoryPostingDocument.purchaseAdjustment
        : InventoryPostingDocument.purchaseReturn;
    if (!await _containsActiveDocument(kind, returnId)) {
      throw const LanBusinessException(
        'purchase_return_not_found',
        'Purchase return not found in the active warehouse.',
        statusCode: 404,
      );
    }
    final status = adjustment
        ? await (_database.select(_database.purchaseReturnAdjustments)
                ..where((row) => row.id.equals(returnId))
                ..limit(1))
              .getSingleOrNull()
              .then((row) => row?.status)
        : await (_database.select(_database.purchaseReturns)
                ..where((row) => row.id.equals(returnId))
                ..limit(1))
              .getSingleOrNull()
              .then((row) => row?.status);
    if (status == null) {
      throw const LanBusinessException(
        'purchase_return_not_found',
        'Purchase return not found.',
        statusCode: 404,
      );
    }
    // The document id and its terminal state form a natural idempotency key:
    // a lost successful response can be retried without reversing twice.
    if (status == 'voided') return;
    try {
      if (adjustment) {
        await _adjustmentReturns.voidPurchaseAdjReturn(
          returnId,
          journalEntryService: _journalEntries,
          voidedBy: actor.id,
          voidReason: 'Remote user voided purchase adjustment return',
          scope: _activeWarehouseScope,
        );
      } else {
        await _activePurchases.voidPurchaseReturn(
          returnId,
          actorUserId: actor.id,
        );
      }
    } catch (error) {
      throw LanBusinessException(
        'purchase_return_void_rejected',
        error.toString().replaceFirst('Exception: ', ''),
        statusCode: 409,
      );
    }
  }

  @override
  Future<LanPurchasesPage> fetchPurchases({required int limit}) async {
    final safeLimit = limit.clamp(1, 500);
    final allowed = await _activeDocumentIds(InventoryPostingDocument.purchase);
    final results = await Future.wait<dynamic>([
      _activePurchases.watchAllPurchases().first,
      _activePurchases.watchDashboardStats().first,
      _activePurchases.watchPurchaseIdsWithReturns().first,
      _activePurchases.watchPurchaseProductSearchTerms().first,
    ]);
    final purchases = (results[0] as List<PurchaseEntity>)
        .where((value) => allowed.contains(value.id))
        .take(safeLimit)
        .toList(growable: false);
    final stats = results[1] as PurchaseDashboardStats;
    final returned = results[2] as Set<int>;
    final terms = results[3] as Map<int, List<String>>;
    final visibleIds = purchases.map((value) => value.id).toSet();
    final currency = _currencyService.getCurrency();
    return LanPurchasesPage(
      purchases: purchases.map(_purchaseSummary).toList(growable: false),
      stats: LanPurchaseDashboardStats(
        totalCount: stats.totalCount,
        draftCount: stats.draftCount,
        postedCount: stats.postedCount,
        totalPayableCents: stats.totalPayableCents,
        totalPaidCents: stats.totalPaidCents,
        overdueCount: stats.overdueCount,
        returnsCount: stats.returnsCount,
      ),
      purchaseIdsWithReturns: returned.intersection(visibleIds),
      productSearchTerms: Map<int, List<String>>.fromEntries(
        terms.entries.where((entry) => visibleIds.contains(entry.key)),
      ),
      currencyCode: currency.code,
      currencySymbol: currency.symbol,
      currencyDecimalDigits: currency.decimalDigits,
      currencySymbolAfter: currency.symbolPosition == SymbolPosition.after,
    );
  }

  @override
  Future<LanPurchaseDetails?> fetchPurchaseDetails({
    required int purchaseId,
  }) async {
    if (purchaseId <= 0 ||
        !await _containsActiveDocument(
          InventoryPostingDocument.purchase,
          purchaseId,
        )) {
      return null;
    }
    final purchase = await _activePurchases.getPurchaseById(purchaseId);
    if (purchase == null) return null;
    final results = await Future.wait<dynamic>([
      _activePurchases.getPurchaseItems(purchaseId),
      _activePurchases.watchPurchaseReturnsByPurchase(purchaseId).first,
    ]);
    final items = results[0] as List<PurchaseItemEntity>;
    final returns = results[1] as List<PurchaseReturnEntity>;
    final storedCurrency =
        await (_database.select(_database.currencies)
              ..where((row) => row.id.equals(purchase.currencyId))
              ..limit(1))
            .getSingleOrNull();
    final configured = _currencyService.getCurrency();
    final definition =
        storedCurrency == null || storedCurrency.code == configured.code
        ? configured
        : currency_model.Currency.fromCode(storedCurrency.code);
    return LanPurchaseDetails(
      purchase: _purchaseSummary(purchase),
      lines: items
          .map(
            (item) => LanPurchaseDetailLine(
              id: item.id,
              purchaseId: item.purchaseId,
              productId: item.productId,
              productName: item.productName ?? 'Product #${item.productId}',
              variantId: item.variantId,
              variantSku: item.variantSku,
              colorName: item.colorName,
              colorHex: item.colorHex,
              sizeName: item.sizeName,
              supplierIdentityRequested: item.supplierIdentityRequested,
              supplierIdentityId: item.supplierIdentityId,
              supplierSourceSku: item.supplierSourceSku,
              quantity: item.quantity,
              quantityScale: item.quantityScale,
              measurementType: item.measurementType,
              unitCostCents: _cents(item.unitCostCents),
              subtotalCents: _cents(item.subtotalCents),
              discountCents: _cents(item.discountCents),
              taxCents: _cents(item.taxCents),
              totalCents: _cents(item.totalCents),
              originalCostCents: item.originalCostCents == null
                  ? null
                  : _cents(item.originalCostCents!),
              originalPriceCents: item.originalPriceCents == null
                  ? null
                  : _cents(item.originalPriceCents!),
              originalWholesalePriceCents:
                  item.originalWholesalePriceCents == null
                  ? null
                  : _cents(item.originalWholesalePriceCents!),
              newSellPriceCents: item.newSellPriceCents == null
                  ? null
                  : _cents(item.newSellPriceCents!),
              newWholesalePriceCents: item.newWholesalePriceCents == null
                  ? null
                  : _cents(item.newWholesalePriceCents!),
              expiryDate: item.expiryDate,
              manufacturerLotNumber: item.manufacturerLotNumber,
              createdAt: item.createdAt,
            ),
          )
          .toList(growable: false),
      returns: returns.map(_purchaseReturnSummary).toList(growable: false),
      supplierBalanceCents: null,
      currencyCode: storedCurrency?.code ?? configured.code,
      currencySymbol: storedCurrency?.symbol ?? definition.symbol,
      currencyDecimalDigits: definition.decimalDigits,
      currencySymbolAfter: definition.symbolPosition == SymbolPosition.after,
    );
  }

  LanPurchaseSummary _purchaseSummary(PurchaseEntity value) =>
      LanPurchaseSummary(
        id: value.id,
        purchaseNumber: value.purchaseNumber,
        supplierId: value.supplierId,
        supplierName: value.supplierName,
        supplierPhone: value.supplierPhone,
        subtotalCents: _cents(value.subtotalCents),
        discountCents: _cents(value.discountCents),
        taxCents: _cents(value.taxCents),
        totalCents: _cents(value.totalCents),
        paidAmountCents: _cents(value.paidAmountCents),
        currencyId: value.currencyId,
        status: value.status,
        paymentMethod: value.paymentMethod,
        supplierInvoiceRef: value.supplierInvoiceRef,
        notes: value.notes,
        purchaseDate: value.purchaseDate,
        dueDate: value.dueDate,
        taxInclusiveAtPost: value.taxInclusiveAtPost,
        createdAt: value.createdAt,
        updatedAt: value.updatedAt,
      );

  @override
  Future<LanPurchaseResult> createPurchase({
    required LanRemoteUser actor,
    required LanPurchaseRequest request,
  }) => _database.transaction(() async {
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
        'A purchase must contain between 1 and 200 lines.',
      );
    }
    final receipts = LanRequestReceiptStore(_database);
    final warehouseIdentity = _activeWarehouseScope?.warehouseId ?? 'primary';
    const receiptOperation = 'purchase';
    final receiptPayload = <String, dynamic>{
      ...request.toJson(),
      'warehouseId': warehouseIdentity,
      'actorUserId': actor.id,
    };
    final reservation = await receipts.reserve(
      operation: receiptOperation,
      idempotencyKey: key,
      payload: receiptPayload,
      findLegacyDocument: () async => null,
    );
    if (!reservation.shouldCreate) {
      final existing = await _activePurchases.getPurchaseById(
        reservation.documentId!,
      );
      if (existing == null) {
        throw const LanBusinessException(
          'idempotency_receipt_corrupt',
          'The saved request result is unavailable.',
          statusCode: 409,
        );
      }
      return _purchaseResult(existing, duplicate: true);
    }

    final supplier =
        await (_database.select(_database.suppliers)
              ..where(
                (row) =>
                    row.id.equals(request.supplierId) &
                    row.isActive.equals(true),
              )
              ..limit(1))
            .getSingleOrNull();
    if (supplier == null) {
      throw const LanBusinessException(
        'supplier_unavailable',
        'The selected supplier is unavailable.',
        statusCode: 409,
      );
    }
    const paymentMethods = {'cash', 'card', 'credit', 'cheque', 'mixed'};
    if (!paymentMethods.contains(request.paymentMethod)) {
      throw const LanBusinessException(
        'invalid_payment_method',
        'Unsupported payment method.',
      );
    }
    if (request.paymentMethod == 'cheque' && request.dueDate == null) {
      throw const LanBusinessException(
        'cheque_due_date_required',
        'A cheque due date is required.',
      );
    }

    final productIds = request.lines
        .map((line) => line.productId)
        .toSet()
        .toList(growable: false);
    final products = await WarehouseCatalogScope.readProducts(
      _database,
      productIds,
      scope: await _activeReadScope(),
    );
    final productMap = {for (final value in products) value.id: value};
    final variantIds = request.lines
        .map((line) => line.variantId)
        .whereType<int>()
        .toSet()
        .toList(growable: false);
    final variants = await WarehouseCatalogScope.readVariants(
      _database,
      variantIds,
      scope: await _activeReadScope(),
    );
    final variantMap = {for (final value in variants) value.id: value};
    final appSettings = _settings.current;
    final pharmacyEnabled = _isEnabled(
      AppFeature.pharmacy,
      appSettings.enablePharmacyFeatures,
    );
    final medicineIds = pharmacyEnabled
        ? await _pharmacy.getMedicineProductIds()
        : const <int>{};
    final resolved =
        <
          ({
            LanPurchaseLineRequest request,
            Product product,
            ProductVariant? variant,
          })
        >[];
    final pricingInputs = <LineItemPricingInput>[];
    for (final requested in request.lines) {
      final product = productMap[requested.productId];
      if (product == null || !product.isActive || requested.quantity <= 0) {
        throw const LanBusinessException(
          'product_unavailable',
          'A selected product is unavailable or has an invalid quantity.',
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
      if (requested.unitCostCents < 0 ||
          (requested.newSellPriceCents != null &&
              requested.newSellPriceCents! < 0) ||
          (requested.newWholesalePriceCents != null &&
              requested.newWholesalePriceCents! < 0)) {
        throw const LanBusinessException(
          'invalid_purchase_price',
          'Purchase and selling prices cannot be negative.',
        );
      }
      if (product.inventoryTrackingType == 'batch_expiry' &&
          requested.expiryDate == null) {
        throw const LanBusinessException(
          'purchase_expiry_required',
          'An expiry date is required for this product.',
        );
      }
      if (medicineIds.contains(product.id) &&
          (requested.manufacturerLotNumber?.trim().isEmpty ?? true)) {
        throw const LanBusinessException(
          'manufacturer_lot_required',
          'A manufacturer lot number is required for medicines.',
        );
      }
      final quantityScale = MeasurementType.fromDb(
        product.measurementType,
      ).quantityScale;
      resolved.add((request: requested, product: product, variant: variant));
      pricingInputs.add(
        LineItemPricingInput(
          unitPrice: Money.fromCents(requested.unitCostCents),
          quantity: requested.quantity,
          quantityScale: quantityScale,
          discount: _purchaseDiscount(
            requested.discountType,
            requested.discountValue,
          ),
          isTaxable: product.isTaxable,
          productTaxRateBps: product.purchaseTaxRateBps,
        ),
      );
    }

    final policy = await BranchTaxPolicyStore(_database).read();
    if (policy == null && _settings.requiresPersistedTaxPolicy) {
      throw const LanBusinessException(
        'tax_policy_unavailable',
        'The branch tax policy is unavailable.',
        statusCode: 409,
      );
    }
    final effectiveSettings =
        policy?.policy.applyTo(appSettings) ?? appSettings;
    final pricing = InvoicePricingEngine.compute(
      InvoicePricingInput(
        lines: pricingInputs,
        overallDiscount: _purchaseDiscount(
          request.overallDiscountType,
          request.overallDiscountValue,
        ),
        enableTaxCalculations: effectiveSettings.enableTaxCalculations,
        defaultTaxRateBps: (effectiveSettings.defaultPurchaseTaxRate * 100)
            .round(),
        taxInclusivePricing: effectiveSettings.taxInclusivePricing,
      ),
    );
    final expected = request.expectedPricingFingerprint;
    if (expected != null &&
        expected !=
            pricingPreviewFingerprint(
              pricing,
              taxInclusive: effectiveSettings.taxInclusivePricing,
            )) {
      throw const LanBusinessException(
        'pricing_preview_changed',
        'Pricing changed. Refresh and review the purchase before submitting again.',
        statusCode: 409,
      );
    }
    final currency = await _selectedCurrency();
    if (currency == null) {
      throw const LanBusinessException(
        'currency_unavailable',
        'The branch currency is unavailable.',
        statusCode: 409,
      );
    }
    final allocations = request.payments
        .map(
          (payment) => CheckoutPaymentAllocation(
            method: payment.method,
            amountCents: payment.amountCents,
            reference: payment.reference,
            bankName: payment.bankName,
            issueDate: payment.issueDate?.toLocal(),
            dueDate: payment.dueDate?.toLocal(),
            note: payment.note,
          ),
        )
        .toList(growable: false);
    final totalCents = pricing.total.cents;
    late final int paidAmountCents;
    if (allocations.isNotEmpty) {
      const settlementMethods = {'cash', 'card', 'cheque', 'check'};
      if (allocations.any(
        (payment) => !settlementMethods.contains(payment.method),
      )) {
        throw const LanBusinessException(
          'invalid_payment_method',
          'Unsupported settlement payment method.',
        );
      }
      final settlement = CheckoutSettlement(allocations);
      try {
        settlement.validate(invoiceTotalCents: totalCents);
      } on ArgumentError catch (error) {
        throw LanBusinessException(
          'invalid_settlement',
          error.message?.toString() ?? 'Invalid purchase settlement.',
        );
      }
      paidAmountCents = settlement.totalSettledCents;
      if ((request.paidAmountCents ?? paidAmountCents) != paidAmountCents) {
        throw const LanBusinessException(
          'settlement_total_mismatch',
          'Settlement total does not match the paid amount.',
        );
      }
    } else {
      switch (request.paymentMethod) {
        case 'cash':
        case 'card':
          paidAmountCents = request.paidAmountCents ?? totalCents;
          if (paidAmountCents != totalCents) {
            throw const LanBusinessException(
              'purchase_payment_total_mismatch',
              'Cash and card purchases must be paid in full.',
            );
          }
          break;
        case 'credit':
        case 'cheque':
          paidAmountCents = 0;
          if ((request.paidAmountCents ?? 0) != 0) {
            throw const LanBusinessException(
              'purchase_payment_total_mismatch',
              'Credit and cheque purchases require structured payments.',
            );
          }
          break;
        case 'mixed':
          throw const LanBusinessException(
            'settlement_required',
            'Mixed payment requires settlement details.',
          );
        default:
          throw const LanBusinessException(
            'invalid_payment_method',
            'Unsupported payment method.',
          );
      }
    }
    final inputs = <PurchaseItemInput>[];
    for (var index = 0; index < resolved.length; index++) {
      final value = resolved[index];
      final line = pricing.lines[index];
      final originalCost = value.variant?.costCents ?? value.product.costCents;
      final originalPrice =
          value.variant?.priceCents ?? value.product.priceCents;
      final originalWholesale =
          value.variant?.wholesalePriceCents ??
          value.product.wholesalePriceCents;
      inputs.add(
        PurchaseItemInput(
          productId: value.product.id,
          supplierIdentityRequested:
              effectiveSettings.enableSupplierProductCodes &&
              value.request.supplierIdentityRequested &&
              value.product.trackInventory,
          variantId: value.variant?.id,
          quantity: value.request.quantity,
          quantityScale: MeasurementType.fromDb(
            value.product.measurementType,
          ).quantityScale,
          measurementType: value.product.measurementType,
          unitCostCents: Decimal.fromInt(value.request.unitCostCents),
          discountCents: Decimal.fromInt(line.totalLineDiscount.cents),
          subtotalCents: Decimal.fromInt(line.subtotal.cents),
          taxCents: Decimal.fromInt(line.tax.cents),
          totalCents: Decimal.fromInt(line.total.cents),
          expiryDate: value.request.expiryDate?.toLocal(),
          manufacturerLotNumber: _nullableTrim(
            value.request.manufacturerLotNumber,
          ),
          originalCostCents: originalCost,
          originalPriceCents: originalPrice,
          originalWholesalePriceCents: originalWholesale,
          newSellPriceCents: value.request.newSellPriceCents == null
              ? null
              : Decimal.fromInt(value.request.newSellPriceCents!),
          newWholesalePriceCents: value.request.newWholesalePriceCents == null
              ? null
              : Decimal.fromInt(value.request.newWholesalePriceCents!),
        ),
      );
    }
    final purchaseId = await _activePurchases.createPurchase(
      supplierId: supplier.id,
      currencyId: currency.id,
      subtotalCents: Decimal.fromInt(pricing.subtotal.cents),
      discountCents: Decimal.fromInt(pricing.totalDiscount.cents),
      taxCents: Decimal.fromInt(pricing.tax.cents),
      totalCents: Decimal.fromInt(totalCents),
      paidAmountCents: Decimal.fromInt(paidAmountCents),
      items: inputs,
      paymentMethod: allocations.isEmpty ? request.paymentMethod : 'mixed',
      supplierInvoiceRef: _nullableTrim(request.supplierInvoiceRef),
      notes: _nullableTrim(request.notes),
      purchaseDate: request.purchaseDate?.toLocal() ?? DateTime.now(),
      dueDate: request.dueDate?.toLocal(),
      taxInclusiveAtPost: effectiveSettings.taxInclusivePricing,
      initialPayments: allocations,
      actorUserId: actor.id,
    );
    final created = await _activePurchases.getPurchaseById(purchaseId);
    if (created == null) throw StateError('Purchase not found after creation.');
    await receipts.complete(
      operation: receiptOperation,
      idempotencyKey: key,
      payload: receiptPayload,
      documentId: created.id,
      documentNumber: created.purchaseNumber,
      totalCents: _cents(created.totalCents),
    );
    return _purchaseResult(created);
  });

  @override
  Future<LanPurchaseResult> postPurchase({
    required LanRemoteUser actor,
    required int purchaseId,
  }) async {
    final purchase = await _activePurchases.getPurchaseById(purchaseId);
    if (purchase == null) {
      throw const LanBusinessException(
        'purchase_not_found',
        'Purchase not found in the assigned warehouse.',
        statusCode: 404,
      );
    }
    if (purchase.isPosted) return _purchaseResult(purchase, duplicate: true);
    if (!purchase.isDraft) {
      throw const LanBusinessException(
        'purchase_not_postable',
        'Only a draft purchase can be posted.',
        statusCode: 409,
      );
    }
    try {
      await _activePurchases.postPurchase(purchaseId, actorUserId: actor.id);
    } on SupplierIdentityException catch (error) {
      throw LanBusinessException(
        error.messageKey,
        error.messageKey,
        statusCode: 409,
      );
    } catch (error) {
      throw LanBusinessException(
        'purchase_post_rejected',
        error.toString().replaceFirst('Exception: ', ''),
        statusCode: 409,
      );
    }
    return _purchaseResult(
      (await _activePurchases.getPurchaseById(purchaseId))!,
    );
  }

  @override
  Future<LanPurchaseVoidResult> voidPurchase({
    required LanRemoteUser actor,
    required int purchaseId,
  }) async {
    final purchase = await _activePurchases.getPurchaseById(purchaseId);
    if (purchase == null) {
      throw const LanBusinessException(
        'purchase_not_found',
        'Purchase not found in the assigned warehouse.',
        statusCode: 404,
      );
    }
    if (purchase.isVoided) {
      return LanPurchaseVoidResult(
        purchaseId: purchaseId,
        status: 'voided',
        duplicate: true,
      );
    }
    if (!purchase.isPosted) {
      throw const LanBusinessException(
        'purchase_not_voidable',
        'Only a posted purchase can be voided.',
        statusCode: 409,
      );
    }
    try {
      await _activePurchases.voidPurchase(purchaseId, actorUserId: actor.id);
    } on VoidBlockedByImpactException catch (error) {
      throw LanBusinessException(
        'purchase_void_blocked',
        'The purchase cannot be voided because related stock has changed.',
        statusCode: 409,
        details: lanVoidImpactToJson(error.report),
      );
    } catch (error) {
      throw LanBusinessException(
        'purchase_void_rejected',
        error.toString().replaceFirst('Exception: ', ''),
        statusCode: 409,
      );
    }
    return LanPurchaseVoidResult(purchaseId: purchaseId, status: 'voided');
  }

  @override
  Future<bool> deletePurchase({
    required LanRemoteUser actor,
    required int purchaseId,
  }) async {
    final purchase = await _activePurchases.getPurchaseById(purchaseId);
    if (purchase == null) return false;
    if (!purchase.isDraft) {
      throw const LanBusinessException(
        'purchase_not_deletable',
        'Only a draft purchase can be deleted.',
        statusCode: 409,
      );
    }
    return await _activePurchases.deletePurchase(
          purchaseId,
          actorUserId: actor.id,
        ) >
        0;
  }

  @override
  Future<Map<String, dynamic>?> inspectPurchaseVoidImpact({
    required int purchaseId,
  }) async {
    if (!await _containsActiveDocument(
      InventoryPostingDocument.purchase,
      purchaseId,
    )) {
      return null;
    }
    final report = await VoidImpactAnalyzer(
      _database,
      warehouseScope: await _activeReadScope(),
    ).analyzePurchaseVoid(purchaseId);
    return lanVoidImpactToJson(report);
  }

  LanPurchaseResult _purchaseResult(
    PurchaseEntity purchase, {
    bool duplicate = false,
  }) => LanPurchaseResult(
    purchaseId: purchase.id,
    purchaseNumber: purchase.purchaseNumber,
    subtotalCents: _cents(purchase.subtotalCents),
    discountCents: _cents(purchase.discountCents),
    taxCents: _cents(purchase.taxCents),
    totalCents: _cents(purchase.totalCents),
    paidAmountCents: _cents(purchase.paidAmountCents),
    status: purchase.status,
    duplicate: duplicate,
  );

  Discount _purchaseDiscount(String type, int value) {
    if (value < 0) {
      throw const LanBusinessException(
        'invalid_discount',
        'Discount value cannot be negative.',
      );
    }
    switch (type) {
      case 'none':
        if (value != 0) {
          throw const LanBusinessException(
            'invalid_discount',
            'A no-discount value must be zero.',
          );
        }
        return Discount.none;
      case 'fixed':
        return value == 0
            ? Discount.none
            : Discount.fixed(Money.fromCents(value));
      case 'percentage':
        if (value > 10000) {
          throw const LanBusinessException(
            'invalid_discount',
            'Percentage discount cannot exceed 100%.',
          );
        }
        return value == 0 ? Discount.none : Discount.percent(value);
      default:
        throw const LanBusinessException(
          'invalid_discount',
          'Unsupported discount type.',
        );
    }
  }

  String? _nullableTrim(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  @override
  Future<LanSaleResult> createSale({
    required LanRemoteUser actor,
    required LanSaleRequest request,
  }) => _database.transaction(() async {
    // Reserve the key, post the sale, and complete the receipt atomically so
    // a failed checkout never leaves a key permanently in progress.
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

    final requestReceipts = LanRequestReceiptStore(_database);
    final reservation = await requestReceipts.reserve(
      operation: 'sale',
      idempotencyKey: key,
      payload: request.toJson(),
      findLegacyDocument: () async {
        final legacy =
            await (_database.select(_database.sales)
                  ..where((row) => row.idempotencyKey.equals(key))
                  ..limit(1))
                .getSingleOrNull();
        return legacy == null
            ? null
            : LanLegacyRequestDocument(
                id: legacy.id,
                number: legacy.invoiceNumber,
                totalCents: _cents(legacy.totalCents),
              );
      },
    );
    if (!reservation.shouldCreate) {
      final existing =
          await (_database.select(_database.sales)
                ..where((row) => row.id.equals(reservation.documentId!))
                ..limit(1))
              .getSingleOrNull();
      if (existing == null) {
        throw const LanBusinessException(
          'idempotency_receipt_corrupt',
          'The saved request result is unavailable.',
          statusCode: 409,
        );
      }
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

    const allowedPayments = {'cash', 'card', 'credit', 'cheque', 'mixed'};
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
            request.paymentMethod == 'cheque' ||
            request.payments.any(
              (payment) =>
                  payment.method == 'cheque' || payment.method == 'check',
            )) &&
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
    final products = await WarehouseCatalogScope.readProducts(
      _database,
      productIds.toList(),
      scope: await _activeReadScope(),
    );
    final productMap = {for (final value in products) value.id: value};

    final variantIds = request.lines
        .map((line) => line.variantId)
        .whereType<int>()
        .toSet()
        .toList(growable: false);
    final variants = await WarehouseCatalogScope.readVariants(
      _database,
      variantIds.toList(),
      scope: await _activeReadScope(),
    );
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

    final currency = await _selectedCurrency();
    if (currency == null) {
      throw const LanBusinessException(
        'currency_unavailable',
        'The master has no configured currency.',
        statusCode: 409,
      );
    }

    if (request.overallDiscountCents < 0) {
      throw const LanBusinessException(
        'invalid_discount',
        'Invalid invoice discount.',
      );
    }
    final overallDiscount = request.overallDiscountCents == 0
        ? Discount.none
        : Discount.fixed(Money.fromCents(request.overallDiscountCents));
    final manualPricing = InvoicePricingEngine.compute(
      InvoicePricingInput(
        lines: pricingInputs,
        overallDiscount: overallDiscount,
        enableTaxCalculations: appSettings.enableTaxCalculations,
        defaultTaxRateBps: (appSettings.defaultSalesTaxRate * 100).round(),
        taxInclusivePricing: appSettings.taxInclusivePricing,
      ),
    );

    var promotionEvaluation = const PromotionEvaluationResult(applications: []);
    if (_isEnabled(AppFeature.promotions, appSettings.enablePromotions)) {
      final rules = await _promotions.loadActiveRules();
      final promotionLines = <PromotionCartLine>[];
      for (var index = 0; index < resolved.length; index++) {
        final value = resolved[index];
        final quantityScale = MeasurementType.fromDb(
          value.product.measurementType,
        ).quantityScale;
        promotionLines.add(
          PromotionCartLine(
            lineId: 'lan_$index',
            productId: value.product.id,
            variantId: value.variant?.id,
            categoryId: value.product.categoryId,
            measurementType: value.product.measurementType,
            priceMode: value.request.priceTier,
            quantity: value.request.quantity,
            quantityScale: quantityScale,
            unitPrice: Money.fromCents(value.unitPriceCents),
            existingDiscount: manualPricing.lines[index].totalLineDiscount,
          ),
        );
      }
      promotionEvaluation = PromotionEngine.evaluate(
        cart: PromotionCart(
          currencyId: currency.id,
          evaluatedAt: DateTime.now(),
          lines: promotionLines,
        ),
        promotions: rules,
      );
    }

    final promotionByLine = promotionEvaluation.discountByLine;
    final finalPricingInputs = <LineItemPricingInput>[];
    for (var index = 0; index < resolved.length; index++) {
      final value = resolved[index];
      final combinedDiscount =
          manualPricing.lines[index].local.discount +
          (promotionByLine['lan_$index'] ?? Money.zero);
      finalPricingInputs.add(
        LineItemPricingInput(
          unitPrice: Money.fromCents(value.unitPriceCents),
          quantity: value.request.quantity,
          quantityScale: MeasurementType.fromDb(
            value.product.measurementType,
          ).quantityScale,
          discount: combinedDiscount.isPositive
              ? Discount.fixed(combinedDiscount)
              : Discount.none,
          isTaxable: value.product.isTaxable,
          productTaxRateBps: value.product.salesTaxRateBps,
        ),
      );
    }
    final pricing = InvoicePricingEngine.compute(
      InvoicePricingInput(
        lines: finalPricingInputs,
        overallDiscount: overallDiscount,
        enableTaxCalculations: appSettings.enableTaxCalculations,
        defaultTaxRateBps: (appSettings.defaultSalesTaxRate * 100).round(),
        taxInclusivePricing: appSettings.taxInclusivePricing,
      ),
    );

    if (request.expectedPricingFingerprint != null &&
        request.expectedPricingFingerprint !=
            pricingPreviewFingerprint(
              pricing,
              taxInclusive: appSettings.taxInclusivePricing,
            )) {
      throw const LanBusinessException(
        'pricing_preview_changed',
        'Pricing changed. Refresh and review the sale before submitting again.',
        statusCode: 409,
      );
    }

    final profitableFreeBundleLineIds =
        PromotionMarginPolicy.profitableFreeBundleLineIds(
          evaluation: promotionEvaluation,
          lines: [
            for (var index = 0; index < resolved.length; index++)
              PromotionMarginLine(
                lineId: 'lan_$index',
                quantity: resolved[index].request.quantity,
                quantityScale: MeasurementType.fromDb(
                  resolved[index].product.measurementType,
                ).quantityScale,
                unitCost: Money.fromCents(
                  _cents(
                    resolved[index].variant?.costCents ??
                        resolved[index].product.costCents,
                  ),
                ),
                netBeforePromotions: manualPricing.lines[index].adjustedNet,
              ),
          ],
        );

    final belowCostViolations = <_BelowCostViolation>[];
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
      if (pricing.lines[index].adjustedNet.cents < totalCostCents &&
          !profitableFreeBundleLineIds.contains('lan_$index')) {
        final effectiveUnitPriceCents = pricing.lines[index].adjustedNet
            .multiplyRatio(quantityScale, value.request.quantity)
            .round()
            .cents;
        belowCostViolations.add(
          _BelowCostViolation(
            lineIndex: index,
            productId: value.product.id,
            productName: value.product.name,
            costCents: unitCostCents,
            sellingPriceCents: effectiveUnitPriceCents,
            lossCents: unitCostCents - effectiveUnitPriceCents,
          ),
        );
      }
    }
    if (belowCostViolations.isNotEmpty) {
      final privileged = actor.role == 'owner' || actor.role == 'manager';
      final canOverride = appSettings.allowBelowCostSales && privileged;
      final violation = belowCostViolations.first;
      final canViewCost = actor.permissions.contains('view_product_cost');
      final lossPercent = violation.costCents <= 0
          ? 0.0
          : (violation.lossCents / violation.costCents) * 100;
      final warningDetails = <String, dynamic>{
        'lineIndex': violation.lineIndex,
        'productId': violation.productId,
        'productName': violation.productName,
        'canOverride': canOverride,
        if (canViewCost) ...{
          'costCents': violation.costCents,
          'sellingPriceCents': violation.sellingPriceCents,
          'lossCents': violation.lossCents,
          'lossPercent': lossPercent,
          'exceedsThreshold': lossPercent > 50,
        },
      };
      if (!canOverride) {
        throw LanBusinessException(
          'sale_below_cost',
          'The discount would sell an item below its recorded cost.',
          statusCode: 409,
          details: warningDetails,
        );
      }
      if (request.belowCostOverrideReason?.trim().isEmpty != false) {
        throw LanBusinessException(
          'sale_below_cost_reason_required',
          'A reason is required to approve a below-cost sale.',
          statusCode: 409,
          details: warningDetails,
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
    late final int loyaltyValue;
    try {
      loyaltyValue = await SaleLoyaltySettlement.validate(
        _database,
        customerId: customer?.id,
        currencyId: currency.id,
        points: request.loyaltyPointsToRedeem,
        expectedValueCents: request.loyaltyValueCents,
        totalCents: totalCents,
      );
    } on StateError catch (error) {
      throw LanBusinessException(
        'loyalty_balance_or_policy_changed',
        error.message,
        statusCode: 409,
      );
    }
    final payableCents = totalCents - loyaltyValue;
    final initialPayments = request.payments
        .map(
          (payment) => CheckoutPaymentAllocation(
            method: payment.method,
            amountCents: payment.amountCents,
            reference: payment.reference,
            bankName: payment.bankName,
            issueDate: payment.issueDate,
            dueDate: payment.dueDate,
            note: payment.note,
          ),
        )
        .toList(growable: false);
    final requestedPaid = request.paidAmountCents ?? payableCents;
    late final int paidAmountCents;
    if (initialPayments.isNotEmpty) {
      const allowedSettlementMethods = {'cash', 'card', 'cheque', 'check'};
      if (initialPayments.any(
        (payment) => !allowedSettlementMethods.contains(payment.method),
      )) {
        throw const LanBusinessException(
          'invalid_payment_method',
          'Unsupported settlement payment method.',
        );
      }
      final settlement = CheckoutSettlement(initialPayments);
      try {
        settlement.validate(invoiceTotalCents: payableCents);
      } on ArgumentError catch (error) {
        throw LanBusinessException(
          'invalid_settlement',
          error.message?.toString() ?? 'Invalid checkout settlement.',
        );
      }
      paidAmountCents = settlement.totalSettledCents;
      if (requestedPaid != paidAmountCents) {
        throw const LanBusinessException(
          'settlement_total_mismatch',
          'Settlement total does not match the paid amount.',
        );
      }
      if (settlement.totalAllocatedCents < payableCents) {
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
    } else {
      switch (request.paymentMethod) {
        case 'card':
          paidAmountCents = payableCents;
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
          if (requestedPaid < payableCents) {
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
          paidAmountCents = requestedPaid > payableCents && customer == null
              ? payableCents
              : requestedPaid;
          break;
        case 'mixed':
          throw const LanBusinessException(
            'settlement_required',
            'Mixed payment requires settlement details.',
          );
      }
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
          lineId: 'lan_$index',
          productId: value.product.id,
          variantId: value.variant?.id,
          supplierIdentityId: value.request.supplierIdentityId,
          consignmentLayerId: value.request.consignmentLayerId,
          quantity: value.request.quantity,
          quantityScale: quantityScale,
          measurementType: value.product.measurementType,
          unitPriceCents: Decimal.fromInt(value.unitPriceCents),
          subtotalCents: Decimal.fromInt(line.subtotal.cents),
          discountCents: Decimal.fromInt(line.totalLineDiscount.cents),
          itemDiscountAtPostCents: Decimal.fromInt(line.local.discount.cents),
          invoiceDiscountAtPostCents: Decimal.fromInt(
            line.shareOfOverallDiscount.cents,
          ),
          taxCents: Decimal.fromInt(line.tax.cents),
          totalCents: Decimal.fromInt(line.total.cents),
          employeeId: value.salesperson?.id,
          employeeName: value.salesperson?.name,
        ),
      );
    }

    late final int saleId;
    try {
      saleId = await _activeSales.createSale(
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
        appliedPromotions: promotionEvaluation.applications,
        initialPayments: initialPayments,
        loyaltyPointsToRedeem: request.loyaltyPointsToRedeem,
        loyaltyValueCents: loyaltyValue,
      );
    } on SupplierIdentityException catch (error) {
      throw LanBusinessException(
        error.messageKey,
        error.messageKey,
        statusCode: 409,
      );
    }

    for (final violation in belowCostViolations) {
      try {
        await _auditLog.logBelowCostOverride(
          saleId: saleId,
          productId: violation.productId,
          productName: violation.productName,
          costCents: violation.costCents,
          sellingPriceCents: violation.sellingPriceCents,
          lossCents: violation.lossCents,
          reason: request.belowCostOverrideReason!.trim(),
          userId: actor.id,
          userRole: actor.role,
        );
      } catch (_) {
        // The sale and its balanced journals are already authoritative.
      }
    }

    final sale = await (_database.select(
      _database.sales,
    )..where((row) => row.id.equals(saleId))).getSingle();
    await requestReceipts.complete(
      operation: 'sale',
      idempotencyKey: key,
      payload: request.toJson(),
      documentId: sale.id,
      documentNumber: sale.invoiceNumber,
      totalCents: _cents(sale.totalCents),
    );
    return _resultFromSale(sale);
  });

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

  void _requireWarehouseTransferActor(LanRemoteUser actor) {
    if (!actor.isActive ||
        (actor.role != 'owner' &&
            !actor.permissions.contains('adjust_stock'))) {
      throw const LanBusinessException(
        'permission_denied',
        'This user cannot manage warehouse transfers.',
        statusCode: 403,
      );
    }
  }

  Future<WarehouseOperationScope> _authorizeTransferWarehouse(
    LanRemoteUser actor,
    String warehouseId,
  ) async {
    _requireWarehouseTransferActor(actor);
    final active =
        await (_database.select(
              _database.users,
            )..where((row) => row.id.equals(actor.id) & row.isActive.equals(1)))
            .getSingleOrNull();
    if (active == null) {
      throw const LanBusinessException(
        'authentication_required',
        'The user session is no longer active.',
        statusCode: 401,
      );
    }
    final primary = await WarehouseOperationScope.resolve(_database);
    final scope = await WarehouseOperationScope.resolveForOrganization(
      _database,
      warehouseId: warehouseId,
    );
    try {
      await scope.validate(_database);
    } catch (_) {
      throw const LanBusinessException(
        'warehouse_unavailable',
        'The selected warehouse is unavailable.',
        statusCode: 409,
      );
    }
    if (scope.organizationId != primary.organizationId ||
        scope.databaseId != primary.databaseId ||
        !await _warehouseEntitlement.permits(scope)) {
      throw const LanBusinessException(
        'warehouse_access_denied',
        'The selected warehouse is outside the permitted organization.',
        statusCode: 403,
      );
    }
    return scope;
  }

  Future<int> _authorizeTransfer(
    LanRemoteUser actor,
    TransferDraftAction action,
    String sourceWarehouseId,
    String destinationWarehouseId,
  ) async {
    final source = await _authorizeTransferWarehouse(actor, sourceWarehouseId);
    final destination = await _authorizeTransferWarehouse(
      actor,
      destinationWarehouseId,
    );
    if (source.warehouseId == destination.warehouseId ||
        source.organizationId != destination.organizationId ||
        source.databaseId != destination.databaseId) {
      throw const LanBusinessException(
        'invalid_warehouse_route',
        'A transfer requires two distinct warehouses in the same organization.',
        statusCode: 409,
      );
    }
    if (actor.role != 'owner' && !actor.hasGlobalLocationAccess) {
      final assignedBranch = actor.branchId;
      final assignedWarehouse = actor.warehouseId;
      final permitted = switch (action) {
        TransferDraftAction.receive =>
          assignedBranch == destination.branchId &&
              (assignedWarehouse == null ||
                  assignedWarehouse == destination.warehouseId),
        TransferDraftAction.read =>
          (assignedBranch == source.branchId &&
                  (assignedWarehouse == null ||
                      assignedWarehouse == source.warehouseId)) ||
              (assignedBranch == destination.branchId &&
                  (assignedWarehouse == null ||
                      assignedWarehouse == destination.warehouseId)),
        TransferDraftAction.create ||
        TransferDraftAction.cancel ||
        TransferDraftAction.dispatch ||
        TransferDraftAction.recall =>
          assignedBranch == source.branchId &&
              (assignedWarehouse == null ||
                  assignedWarehouse == source.warehouseId),
      };
      if (!permitted) {
        throw const LanBusinessException(
          'warehouse_access_denied',
          'This operation is outside the assigned location.',
          statusCode: 403,
        );
      }
    }
    return actor.id;
  }

  WarehouseTransferPreflight _transferPreflight(LanRemoteUser actor) =>
      WarehouseTransferPreflight(
        _database,
        authorizeWarehouse: (warehouseId) async {
          await _authorizeTransferWarehouse(actor, warehouseId);
        },
      );

  WarehouseTransferRepository _transferRepository(
    LanRemoteUser actor,
    WarehouseTransferPreflight preflight,
  ) => WarehouseTransferRepository(
    _database,
    preflight: preflight,
    authorize: (action, source, destination) =>
        _authorizeTransfer(actor, action, source, destination),
  );

  LanWarehouseTransferDocument _transferDocument(
    WarehouseTransfer transfer, {
    required bool recalled,
  }) => LanWarehouseTransferDocument(
    id: transfer.id,
    sourceWarehouseId: transfer.sourceWarehouseId,
    destinationWarehouseId: transfer.destinationWarehouseId,
    status: transfer.status,
    lineCount: transfer.lineCount,
    notes: transfer.notes,
    recalled: recalled,
  );

  LanWarehouseTransferDocument _transferDraftDocument(
    WarehouseTransferDraft draft,
  ) => _transferDocument(draft.header, recalled: draft.recall != null);

  @override
  Future<List<LanWarehouseTransferWarehouse>> fetchTransferWarehouses({
    required LanRemoteUser actor,
  }) => _database.transaction(() async {
    _requireWarehouseTransferActor(actor);
    final primary = await WarehouseOperationScope.resolve(_database);
    final rows = await _database
        .customSelect(
          '''SELECT w.id,w.code,w.name,w.branch_id,b.name AS branch_name,
            CASE WHEN w.location_kind='branch_store' THEN 1 ELSE 0 END
              AS is_branch_location
          FROM business_warehouses w
          JOIN business_branches b ON b.id=w.branch_id
            AND b.organization_id=w.organization_id AND b.is_active=1
          WHERE w.organization_id=? AND w.is_active=1
          ORDER BY b.created_at,b.code,is_branch_location DESC,w.created_at,w.code''',
          variables: [Variable.withString(primary.organizationId)],
        )
        .get();
    final result = <LanWarehouseTransferWarehouse>[];
    for (final row in rows) {
      final id = row.read<String>('id');
      await _authorizeTransferWarehouse(actor, id);
      final branchId = row.read<String>('branch_id');
      final canSource =
          actor.role == 'owner' ||
          actor.hasGlobalLocationAccess ||
          (actor.branchId == branchId &&
              (actor.warehouseId == null || actor.warehouseId == id));
      result.add(
        LanWarehouseTransferWarehouse(
          id: id,
          code: row.read<String>('code'),
          name: row.read<String>('name'),
          branchName: row.read<String>('branch_name'),
          isBranchLocation: row.read<int>('is_branch_location') == 1,
          canSource: canSource,
        ),
      );
    }
    return List.unmodifiable(result);
  });

  @override
  Future<List<LanWarehouseTransferDocument>> fetchWarehouseTransfers({
    required LanRemoteUser actor,
    required Set<String> statuses,
    required int limit,
  }) async {
    _requireWarehouseTransferActor(actor);
    const validStatuses = {
      'draft',
      'in_transit',
      'partially_received',
      'completed',
      'cancelled',
    };
    if (statuses.isEmpty ||
        !validStatuses.containsAll(statuses) ||
        limit < 1 ||
        limit > 500) {
      throw ArgumentError('Invalid warehouse transfer filter');
    }

    // Select only documents visible to the authenticated location before
    // loading them. Asking the repository to enumerate the whole company and
    // then authorize each row makes one unrelated transfer abort the complete
    // list for a warehouse clerk.
    final marks = List.filled(statuses.length, '?').join(',');
    final variables = <Variable<Object>>[...statuses.map(Variable.withString)];
    var locationClause = '';
    if (actor.role != 'owner' && !actor.hasGlobalLocationAccess) {
      final branchId = actor.branchId;
      if (branchId == null || branchId.isEmpty) {
        throw const LanBusinessException(
          'warehouse_access_denied',
          'The account has no assigned business location.',
          statusCode: 403,
        );
      }
      variables.add(Variable.withString(branchId));
      variables.add(Variable.withString(branchId));
      if (actor.warehouseId == null) {
        locationClause = ' AND (source.branch_id=? OR destination.branch_id=?)';
      } else {
        variables.add(Variable.withString(actor.warehouseId!));
        variables.add(Variable.withString(actor.warehouseId!));
        locationClause =
            ' AND ((source.branch_id=? AND t.source_warehouse_id=?)'
            ' OR (destination.branch_id=? AND t.destination_warehouse_id=?))';
        // Match the placeholder order used by the clause.
        final sourceBranch = variables.removeAt(variables.length - 4);
        final destinationBranch = variables.removeAt(variables.length - 3);
        final sourceWarehouse = variables.removeAt(variables.length - 2);
        final destinationWarehouse = variables.removeLast();
        variables.addAll([
          sourceBranch,
          sourceWarehouse,
          destinationBranch,
          destinationWarehouse,
        ]);
      }
    }
    variables.add(Variable.withInt(limit));
    final headers = await _database.customSelect('''SELECT t.id
         FROM warehouse_transfers t
         JOIN business_warehouses source
           ON source.id=t.source_warehouse_id
         JOIN business_warehouses destination
           ON destination.id=t.destination_warehouse_id
         WHERE t.status IN ($marks)$locationClause
         ORDER BY t.created_at DESC
         LIMIT ?''', variables: variables).get();

    final preflight = _transferPreflight(actor);
    final repository = _transferRepository(actor, preflight);
    final result = <LanWarehouseTransferDocument>[];
    for (final header in headers) {
      result.add(
        _transferDraftDocument(await repository.get(header.read<String>('id'))),
      );
    }
    return List.unmodifiable(result);
  }

  @override
  Future<List<LanWarehouseTransferCatalogItem>> fetchWarehouseTransferCatalog({
    required LanRemoteUser actor,
    required String warehouseId,
    required String query,
    required int offset,
  }) => _database.transaction(() async {
    final scope = await _authorizeTransferWarehouse(actor, warehouseId);
    if (actor.role != 'owner' &&
        !actor.hasGlobalLocationAccess &&
        (actor.branchId != scope.branchId ||
            (actor.warehouseId != null &&
                actor.warehouseId != scope.warehouseId))) {
      throw const LanBusinessException(
        'warehouse_access_denied',
        'The catalogue is outside the assigned warehouse.',
        statusCode: 403,
      );
    }
    if (offset < 0) throw ArgumentError.value(offset, 'offset');
    final search = query.trim();
    final rows = await _database
        .customSelect(
          '''SELECT p.id AS product_id, v.id AS variant_id, p.name,
        COALESCE(v.sku, v.barcode, p.sku, p.barcode, '') AS code,
        s.quantity, s.supplier_owned_quantity, p.measurement_type
      FROM business_warehouse_stocks s
      JOIN product_variants v ON v.id=s.variant_id
      JOIN products p ON p.id=v.product_id
      WHERE s.warehouse_id=? AND s.quantity>0
        AND v.is_active=1 AND p.is_active=1 AND p.track_inventory=1
        AND (instr(lower(p.name),lower(?))>0
          OR instr(lower(COALESCE(v.sku,'')),lower(?))>0
          OR instr(lower(COALESCE(v.barcode,'')),lower(?))>0
          OR instr(lower(COALESCE(p.sku,'')),lower(?))>0
          OR instr(lower(COALESCE(p.barcode,'')),lower(?))>0)
      ORDER BY p.name,v.id LIMIT 50 OFFSET ?''',
          variables: [
            Variable.withString(warehouseId),
            for (var i = 0; i < 5; i++) Variable.withString(search),
            Variable.withInt(offset),
          ],
        )
        .get();
    return List.unmodifiable(
      rows.map(
        (row) => LanWarehouseTransferCatalogItem(
          productId: row.read<int>('product_id'),
          variantId: row.read<int>('variant_id'),
          name: row.read<String>('name'),
          code: row.read<String>('code'),
          quantity: row.read<int>('quantity'),
          supplierOwnedQuantity: row.read<int>('supplier_owned_quantity'),
          quantityScale: row.read<String>('measurement_type') == 'piece'
              ? 1
              : 1000,
          measurementType: row.read<String>('measurement_type'),
        ),
      ),
    );
  });

  @override
  Future<LanWarehouseTransferDocument> createWarehouseTransfer({
    required LanRemoteUser actor,
    required LanWarehouseTransferCreateRequest request,
  }) async {
    for (final line in request.lines) {
      if ((line.ownedQuantity == null) != (line.consignmentQuantity == null)) {
        throw ArgumentError('Transfer ownership selection is incomplete');
      }
      if (line.ownedQuantity != null &&
          (line.ownedQuantity! < 0 ||
              line.consignmentQuantity! < 0 ||
              line.ownedQuantity! + line.consignmentQuantity! !=
                  line.quantity)) {
        throw ArgumentError('Transfer ownership quantities are invalid');
      }
    }
    final preflight = _transferPreflight(actor);
    final source = await _authorizeTransferWarehouse(
      actor,
      request.sourceWarehouseId,
    );
    final destination = await _authorizeTransferWarehouse(
      actor,
      request.destinationWarehouseId,
    );
    await _authorizeTransfer(
      actor,
      TransferDraftAction.create,
      source.warehouseId,
      destination.warehouseId,
    );
    final preview = await preflight.preview(
      source: source,
      destination: destination,
      lines: [
        for (final line in request.lines)
          WarehouseTransferRequestLine(
            productId: line.productId,
            variantId: line.variantId,
            quantity: line.quantity,
          ),
      ],
    );
    final draft = await _transferRepository(actor, preflight).create(
      requestKey: request.requestKey,
      preview: preview,
      ownershipByVariant: {
        for (final line in request.lines)
          if (line.ownedQuantity != null && line.consignmentQuantity != null)
            line.variantId: WarehouseTransferOwnershipIntent(
              ownedQuantity: line.ownedQuantity!,
              consignmentQuantity: line.consignmentQuantity!,
            ),
      },
      notes: request.notes,
    );
    return _transferDraftDocument(draft);
  }

  @override
  Future<LanWarehouseTransferDocument> cancelWarehouseTransfer({
    required LanRemoteUser actor,
    required String transferId,
    required LanWarehouseTransferReasonRequest request,
  }) async {
    final preflight = _transferPreflight(actor);
    final draft = await _transferRepository(actor, preflight).cancel(
      id: transferId,
      requestKey: request.requestKey,
      reason: request.reason,
    );
    return _transferDraftDocument(draft);
  }

  @override
  Future<LanWarehouseTransferDocument> dispatchWarehouseTransfer({
    required LanRemoteUser actor,
    required String transferId,
    required String requestKey,
  }) async {
    final preflight = _transferPreflight(actor);
    final result = await WarehouseTransferDispatchService(
      _database,
      preflight: preflight,
      authorize: (action, source, destination) =>
          _authorizeTransfer(actor, action, source, destination),
    ).dispatch(transferId: transferId, requestKey: requestKey);
    return _transferDocument(result.transfer, recalled: false);
  }

  @override
  Future<List<LanWarehouseTransferPendingAllocation>>
  fetchWarehouseTransferPending({
    required LanRemoteUser actor,
    required String transferId,
  }) async {
    final rows = await WarehouseTransferReceiptService(
      _database,
      authorize: (action, source, destination) =>
          _authorizeTransfer(actor, action, source, destination),
    ).pending(transferId);
    return List.unmodifiable(
      rows.map(
        (row) => LanWarehouseTransferPendingAllocation(
          allocationId: row.allocation.id,
          remainingQuantity: row.remainingQuantity,
          quantityScale: row.allocation.quantityScale,
          productName: row.productName,
          code: row.code,
          ownerType: row.allocation.ownerType,
        ),
      ),
    );
  }

  @override
  Future<LanWarehouseTransferDocument> receiveWarehouseTransfer({
    required LanRemoteUser actor,
    required String transferId,
    required LanWarehouseTransferReceiptRequest request,
  }) async {
    final result =
        await WarehouseTransferReceiptService(
          _database,
          authorize: (action, source, destination) =>
              _authorizeTransfer(actor, action, source, destination),
        ).receive(
          transferId: transferId,
          requestKey: request.requestKey,
          notes: request.notes,
          items: [
            for (final item in request.items)
              WarehouseTransferReceiptRequestItem(
                allocationId: item.allocationId,
                acceptedQuantity: item.acceptedQuantity,
                damagedQuantity: item.damagedQuantity,
                lostQuantity: item.lostQuantity,
              ),
          ],
        );
    return _transferDocument(result.transfer, recalled: false);
  }

  @override
  Future<LanWarehouseTransferDocument> recallWarehouseTransfer({
    required LanRemoteUser actor,
    required String transferId,
    required LanWarehouseTransferReasonRequest request,
  }) async {
    final result =
        await WarehouseTransferRecallService(
          _database,
          authorize: (action, source, destination) =>
              _authorizeTransfer(actor, action, source, destination),
        ).recall(
          transferId: transferId,
          requestKey: request.requestKey,
          reason: request.reason,
        );
    return _transferDocument(result.transfer, recalled: true);
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

  String? _normalizedShiftNotes(String? notes) {
    final normalized = notes?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  Future<LanCashierShiftSnapshot> _shiftSnapshot(CashierShiftView view) async {
    final summary = await _shifts.getSummary(view.shift.id);
    final configuredCurrency = _currencyService.getCurrency();
    final currency = configuredCurrency.code == view.currencyCode
        ? configuredCurrency
        : currency_model.Currency.fromCode(view.currencyCode);
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
      currencyDecimalDigits: currency.decimalDigits,
      currencySymbolAfter: currency.symbolPosition == SymbolPosition.after,
      openingCashCents: _cents(view.shift.openingCashCents),
      expectedCashCents: summary.expectedCashCents,
      salesCount: summary.salesCount,
      returnsCount: summary.returnsCount,
      openedAt: view.shift.openedAt,
      closedAt: view.shift.closedAt,
    );
  }

  LanSaleResult _resultFromSale(Sale sale, {bool duplicate = false}) {
    final appSettings = _settings.current;
    return LanSaleResult(
      saleId: sale.id,
      invoiceNumber: sale.invoiceNumber,
      subtotalCents: _cents(sale.subtotalCents),
      discountCents: _cents(sale.discountCents),
      taxCents: _cents(sale.taxCents),
      totalCents: _cents(sale.totalCents),
      paidAmountCents: _cents(sale.paidAmountCents),
      receiptHeaderText: appSettings.receiptHeaderText,
      receiptFooterText: appSettings.receiptFooterText,
      duplicate: duplicate,
    );
  }

  void _guardRemotePinProtectedOperation() {
    if (_settings.current.requirePinForVoidRefund) {
      throw const LanBusinessException(
        'remote_pin_required',
        'PIN-protected returns must be completed on the master device.',
        statusCode: 409,
      );
    }
  }

  /// The configured currency must resolve exactly. Falling back to the base
  /// currency can label one currency while posting another without conversion.
  Future<Currency?> _selectedCurrency() async {
    final selectedCode = _currencyService.currencyCode.trim().toUpperCase();
    return (_database.select(_database.currencies)..where(
          (row) => row.code.equals(selectedCode) & row.isActive.equals(true),
        ))
        .getSingleOrNull();
  }

  int _cents(Decimal value) => value.toBigInt().toInt();
}

class _LanWarehouseContext {
  const _LanWarehouseContext({
    required this.scope,
    required this.sales,
    required this.purchases,
  });

  final WarehouseOperationScope scope;
  final SaleRepository sales;
  final PurchaseRepository purchases;
}

class _BelowCostViolation {
  final int lineIndex;
  final int productId;
  final String productName;
  final int costCents;
  final int sellingPriceCents;
  final int lossCents;

  const _BelowCostViolation({
    required this.lineIndex,
    required this.productId,
    required this.productName,
    required this.costCents,
    required this.sellingPriceCents,
    required this.lossCents,
  });
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
