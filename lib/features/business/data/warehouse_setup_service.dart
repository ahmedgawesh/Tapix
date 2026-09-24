import '../../../core/services/business/warehouse_read_scope.dart';
import 'package:uuid/uuid.dart';
import '../../../core/services/inventory/inventory_adjustment_service.dart';
import '../../../core/services/business/branch_currency_policy_store.dart';
import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/services/audit_log_service.dart';
import '../../../core/services/business/warehouse_operation_scope.dart';
import '../../../core/services/business/warehouse_stocktake_service.dart';
import '../../../core/services/business/warehouse_stock_initialization_service.dart';
import '../../../core/services/currency_service.dart' as money;
import '../../../core/services/desktop_license_service.dart';
import '../../../core/services/revenuecat_service.dart';
import '../../../core/utils/platform_utils.dart';
import '../../auth/data/services/session_service.dart';

/// Commercial boundary for local multi-warehouse management, included in Pro.
abstract interface class WarehouseSetupEntitlement {
  Future<bool> permits(WarehouseOperationScope scope);
}

class UnreleasedWarehouseSetupEntitlement implements WarehouseSetupEntitlement {
  const UnreleasedWarehouseSetupEntitlement();
  @override
  Future<bool> permits(WarehouseOperationScope scope) async => false;
}

/// Uses the existing Pro entitlement. Online branch synchronization has a
/// different, separately priced entitlement and must never be inferred here.
class PlatformProWarehouseSetupEntitlement
    implements WarehouseSetupEntitlement {
  const PlatformProWarehouseSetupEntitlement({
    required RevenueCatService revenueCat,
    required DesktopLicenseService desktopLicense,
  }) : _revenueCat = revenueCat,
       _desktopLicense = desktopLicense;

  final RevenueCatService _revenueCat;
  final DesktopLicenseService _desktopLicense;

  @override
  Future<bool> permits(WarehouseOperationScope scope) async {
    if (PlatformUtils.isAndroid || PlatformUtils.isIOS) {
      return _revenueCat.hasActiveEntitlement(RevenueCatConfig.entitlementId);
    }
    if (PlatformUtils.isWindows || PlatformUtils.isLinux) {
      return await _desktopLicense.initialize() == DesktopLicenseStatus.valid;
    }
    return false;
  }
}

class WarehouseSetupDenied implements Exception {
  const WarehouseSetupDenied();
}

class WarehouseSetupItem {
  const WarehouseSetupItem({
    required this.variantId,
    required this.name,
    required this.label,
    required this.currencyId,
    required this.currencyCode,
    required this.decimalDigits,
    this.quantityScale = 1,
    this.tracking = 'standard',
  });
  final int variantId;
  final String name, label, currencyCode;
  final int currencyId, decimalDigits, quantityScale;
  final String tracking;

  int parseQuantity(String input) => WarehouseSetupItem(
    variantId: variantId,
    name: name,
    label: label,
    currencyId: currencyId,
    currencyCode: currencyCode,
    decimalDigits: quantityScale == 1 ? 0 : 3,
  ).parseCost(input);

  int parseCost(String input) {
    var text = input.trim().replaceAll('٫', '.').replaceAll(',', '.');
    const arabic = '٠١٢٣٤٥٦٧٨٩';
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    for (var i = 0; i < 10; i++) {
      text = text.replaceAll(arabic[i], '$i').replaceAll(persian[i], '$i');
    }
    if (text.length > 40 ||
        decimalDigits < 0 ||
        decimalDigits > 3 ||
        !RegExp(r'^\d+(\.\d+)?$').hasMatch(text)) {
      throw const FormatException('Invalid cost');
    }
    final parts = text.split('.');
    final fraction = parts.length == 2 ? parts[1] : '';
    if (fraction.length > decimalDigits) {
      throw const FormatException('Cost precision');
    }
    final value = BigInt.parse(
      parts[0] + fraction.padRight(decimalDigits, '0'),
    );
    if (value > BigInt.from(9007199254740991)) {
      throw const FormatException('Cost range');
    }
    return value.toInt();
  }
}

class WarehouseCountItem {
  const WarehouseCountItem({
    required this.snapshot,
    required this.name,
    required this.label,
    required this.quantityScale,
  });
  final WarehouseStocktakeSnapshot snapshot;
  final String name, label;
  final int quantityScale;
  int get quantity => snapshot.quantity;

  String displayQuantity(int value) => quantityScale == 1
      ? '$value'
      : '${value < 0 ? '-' : ''}${value.abs() ~/ 1000}.${(value.abs() % 1000).toString().padLeft(3, '0')}';

  int parseQuantity(String input) => WarehouseSetupItem(
    variantId: snapshot.variantId,
    name: name,
    label: label,
    currencyId: snapshot.currencyId,
    currencyCode: '',
    decimalDigits: quantityScale == 1 ? 0 : 3,
  ).parseCost(input);
}

class WarehouseValuationItem {
  const WarehouseValuationItem(this.count, this.money);
  final WarehouseCountItem count;
  final WarehouseSetupItem money;
  String get name => count.name;
  String get label => count.label;
  int get quantity => count.quantity;
  String displayQuantity(int value) => count.displayQuantity(value);
  int parseCost(String input) => money.parseCost(input);
  String displayMoney(int minorUnits) {
    final digits = money.decimalDigits;
    final text = minorUnits.abs().toString().padLeft(digits + 1, '0');
    final amount = digits == 0
        ? text
        : '${text.substring(0, text.length - digits)}.${text.substring(text.length - digits)}';
    return '${minorUnits < 0 ? '-' : ''}$amount ${money.currencyCode}';
  }
}

/// Owner-only initial release boundary. Rechecks the current DB user and Pro
/// entitlement for every read and write. A LAN replica cannot write directly.
class WarehouseSetupService {
  WarehouseSetupService(
    this._db,
    this._session,
    this._entitlement, {
    required bool Function() isRemoteClient,
    WarehouseStocktakeService? stocktake,
    InventoryAdjustmentService? adjustments,
    String Function()? operatingCurrencyCode,
  }) : _isRemoteClient = isRemoteClient,
       _stocktake = stocktake,
       _adjustments = adjustments,
       _operatingCurrencyCode = operatingCurrencyCode;
  final AppDatabase _db;
  final SessionService _session;
  final WarehouseSetupEntitlement _entitlement;
  final bool Function() _isRemoteClient;
  final WarehouseStocktakeService? _stocktake;
  final InventoryAdjustmentService? _adjustments;
  final String Function()? _operatingCurrencyCode;

  Future<int> _authorize() async {
    if (_isRemoteClient()) throw const WarehouseSetupDenied();
    final id = await _session.getCurrentUserId();
    if (id == null) throw const WarehouseSetupDenied();
    final user = await (_db.select(
      _db.users,
    )..where((u) => u.id.equals(id))).getSingleOrNull();
    if (user == null || user.isActive != 1 || user.role != 'owner') {
      throw const WarehouseSetupDenied();
    }
    return id;
  }

  Future<WarehouseOperationScope> _scope(String warehouseId) async {
    final scope = await WarehouseOperationScope.resolve(
      _db,
      warehouseId: warehouseId,
    );
    if (scope.isPrimary || !await _entitlement.permits(scope)) {
      throw const WarehouseSetupDenied();
    }
    return scope;
  }

  Future<bool> canCreateWarehouse() => _db.transaction(() async {
    try {
      await _authorize();
      return await _entitlement.permits(
        await WarehouseOperationScope.resolve(_db),
      );
    } on WarehouseSetupDenied {
      return false;
    }
  });

  Future<BusinessWarehouse> createWarehouse({
    required String name,
    required String code,
  }) => _db.transaction(() async {
    final actor = await _authorize();
    final primary = await WarehouseOperationScope.resolve(_db);
    if (!await _entitlement.permits(primary)) {
      throw const WarehouseSetupDenied();
    }
    final normalizedCode = code.trim().toUpperCase();
    final normalizedName = name.trim();
    if (!RegExp(r'^[A-Z0-9][A-Z0-9_-]{0,31}$').hasMatch(normalizedCode) ||
        normalizedName.isEmpty ||
        normalizedName.length > 100) {
      throw ArgumentError('Warehouse requires a name and a unique short code');
    }
    final duplicate = await _db
        .customSelect(
          'SELECT id FROM business_warehouses WHERE organization_id = ? AND UPPER(code) = ?',
          variables: [
            Variable.withString(primary.organizationId),
            Variable.withString(normalizedCode),
          ],
        )
        .getSingleOrNull();
    if (duplicate != null) throw StateError('Warehouse code already exists');
    final operatingCode = _operatingCurrencyCode?.call();
    if (operatingCode == null) {
      throw StateError('Configure the branch currency first');
    }
    await BranchCurrencyPolicyStore(_db).bind(operatingCode);
    final id = const Uuid().v4();
    final rowId = await _db
        .into(_db.businessWarehouses)
        .insert(
          BusinessWarehousesCompanion.insert(
            id: id,
            organizationId: primary.organizationId,
            branchId: primary.branchId,
            code: normalizedCode,
            name: Value(normalizedName),
          ),
        );
    await _scope(id);
    await AuditLogService(_db).log(
      entityType: 'business_warehouses',
      entityId: rowId,
      action: 'create_warehouse',
      userId: actor,
      userRole: 'owner',
      newValue: {
        'warehouseId': id,
        'name': normalizedName,
        'code': normalizedCode,
      },
    );
    return (_db.select(
      _db.businessWarehouses,
    )..where((w) => w.id.equals(id))).getSingle();
  });

  Future<WarehouseReadScope> reportScope(String warehouseId) =>
      _db.transaction(() async {
        await _authorize();
        final operation = await _scope(warehouseId);
        final read = await operation.forReading(_db);
        return read.withAccessCheck(() async {
          await _authorize();
          if (!await _entitlement.permits(operation)) {
            throw const WarehouseSetupDenied();
          }
        });
      });

  Future<List<BusinessWarehouse>> warehouses() => _db.transaction(() async {
    await _authorize();
    final primary = await WarehouseOperationScope.resolve(_db);
    final rows =
        await (_db.select(_db.businessWarehouses)
              ..where(
                (w) =>
                    w.branchId.equals(primary.branchId) &
                    w.organizationId.equals(primary.organizationId) &
                    w.isActive.equals(true) &
                    w.id.equals(primary.warehouseId).not(),
              )
              ..orderBy([(w) => OrderingTerm.asc(w.code)]))
            .get();
    final allowed = <BusinessWarehouse>[];
    for (final row in rows) {
      final scope = await WarehouseOperationScope.resolve(
        _db,
        warehouseId: row.id,
      );
      if (await _entitlement.permits(scope)) allowed.add(row);
    }
    return allowed;
  });

  Future<List<WarehouseSetupItem>> items(
    String warehouseId, {
    String query = '',
    int offset = 0,
  }) => _db.transaction(() async {
    await _authorize();
    await _scope(warehouseId);
    if (offset < 0) throw ArgumentError.value(offset);
    final rows = await _db
        .customSelect(
          '''
      SELECT v.id, p.name, COALESCE(v.sku, v.barcode, '') label,
             p.currency_id, c.code, p.measurement_type, p.inventory_tracking_type FROM product_variants v
      JOIN products p ON p.id = v.product_id
      JOIN currencies c ON c.id = p.currency_id
      WHERE v.is_active = 1 AND p.is_active = 1 AND p.track_inventory = 1
        AND c.is_active = 1
        AND (instr(lower(p.name), lower(?)) > 0 OR instr(lower(COALESCE(v.sku, '')), lower(?)) > 0)
        AND NOT EXISTS (SELECT 1 FROM business_warehouse_stocks s
          WHERE s.warehouse_id = ? AND s.variant_id = v.id)
      ORDER BY p.name, v.id LIMIT 50 OFFSET ?
    ''',
          variables: [
            Variable.withString(query.trim()),
            Variable.withString(query.trim()),
            Variable.withString(warehouseId),
            Variable.withInt(offset),
          ],
        )
        .get();
    return rows.map((r) {
      final code = r.read<String>('code');
      // Unknown currencies must be configured, never silently treated as USD.
      final currency = money.Currency.allCurrencies.firstWhere(
        (c) => c.code == code,
      );
      return WarehouseSetupItem(
        variantId: r.read<int>('id'),
        name: r.read<String>('name'),
        label: r.read<String>('label'),
        currencyId: r.read<int>('currency_id'),
        currencyCode: code,
        decimalDigits: currency.decimalDigits,
        quantityScale: r.read<String>('measurement_type') == 'piece' ? 1 : 1000,
        tracking: r.read<String>('inventory_tracking_type'),
      );
    }).toList();
  });

  Future<List<WarehouseCountItem>> countItems(
    String warehouseId, {
    String query = '',
    int offset = 0,
  }) => _countItems(
    warehouseId,
    query: query,
    offset: offset,
    includeBatches: false,
  );

  Future<List<WarehouseCountItem>> _countItems(
    String warehouseId, {
    String query = '',
    int offset = 0,
    required bool includeBatches,
  }) => _db.transaction(() async {
    await _authorize();
    final scope = await _scope(warehouseId);
    final service = _stocktake;
    if (service == null) throw StateError('Stocktake service is unavailable');
    if (offset < 0) throw ArgumentError.value(offset);
    final rows = await _db
        .customSelect(
          '''SELECT v.id, p.name,
      COALESCE(v.sku, v.barcode, '') AS label, p.measurement_type
      FROM business_warehouse_stocks s
      JOIN product_variants v ON v.id = s.variant_id
      JOIN products p ON p.id = v.product_id
      WHERE s.warehouse_id = ? AND v.is_active = 1 AND p.is_active = 1
        AND p.track_inventory = 1 AND ${includeBatches ? 's.quantity > 0' : "p.inventory_tracking_type = 'standard'"}
        AND p.costing_method IN ('wac', 'fifo')
        AND (instr(lower(p.name), lower(?)) > 0 OR instr(lower(COALESCE(v.sku, '')), lower(?)) > 0)
      ORDER BY p.name, v.id LIMIT 50 OFFSET ?''',
          variables: [
            Variable.withString(warehouseId),
            Variable.withString(query.trim()),
            Variable.withString(query.trim()),
            Variable.withInt(offset),
          ],
        )
        .get();
    final items = <WarehouseCountItem>[];
    for (final row in rows) {
      items.add(
        WarehouseCountItem(
          snapshot: await service.capture(
            scope: scope,
            variantId: row.read<int>('id'),
          ),
          name: row.read<String>('name'),
          label: row.read<String>('label'),
          quantityScale: row.read<String>('measurement_type') == 'piece'
              ? 1
              : 1000,
        ),
      );
    }
    return items;
  });

  Future<List<WarehouseValuationItem>> valuationItems(
    String warehouseId, {
    String query = '',
    int offset = 0,
  }) => _db.transaction(() async {
    final rows = await _countItems(
      warehouseId,
      query: query,
      offset: offset,
      includeBatches: true,
    );
    final result = <WarehouseValuationItem>[];
    for (final row in rows) {
      final currency = await (_db.select(
        _db.currencies,
      )..where((c) => c.id.equals(row.snapshot.currencyId))).getSingle();
      final configured = money.Currency.allCurrencies.singleWhere(
        (c) => c.code == currency.code,
      );
      result.add(
        WarehouseValuationItem(
          row,
          WarehouseSetupItem(
            variantId: row.snapshot.variantId,
            name: row.name,
            label: row.label,
            currencyId: currency.id,
            currencyCode: currency.code,
            decimalDigits: configured.decimalDigits,
          ),
        ),
      );
    }
    return result;
  });

  Future<WarehouseRevaluationPreview> previewValuation(
    WarehouseValuationItem item,
    String cost,
  ) => _db.transaction(() async {
    await _authorize();
    await _scope(item.count.snapshot.scope.warehouseId);
    final service = _stocktake;
    if (service == null) throw StateError('Valuation service unavailable');
    return service.previewRevaluation(
      snapshot: item.count.snapshot,
      newUnitCostCents: item.parseCost(cost),
    );
  });

  Future<void> postValuation({
    required WarehouseRevaluationPreview preview,
    required String reason,
  }) => _db.transaction(() async {
    final actor = await _authorize();
    await _scope(preview.snapshot.scope.warehouseId);
    if (reason.trim().isEmpty || reason.length > 500) {
      throw ArgumentError('Valuation reason required');
    }
    final service = _stocktake;
    if (service == null) throw StateError('Valuation service unavailable');
    final result = await service.postRevaluation(
      preview: preview,
      reason: reason,
      userId: actor,
    );
    await AuditLogService(_db).log(
      entityType: 'inventory_adjustments',
      entityId: result.adjustmentId,
      action: 'warehouse_revaluation',
      userId: actor,
      userRole: 'owner',
      newValue: {
        'warehouseId': preview.snapshot.scope.warehouseId,
        'variantId': preview.snapshot.variantId,
        'deltaValueCents': result.totalValueCents,
        'reason': reason.trim(),
      },
    );
  });

  Future<void> postCount({
    required WarehouseCountItem item,
    required String countedQuantity,
    required String reason,
  }) => _db.transaction(() async {
    final actor = await _authorize();
    await _scope(item.snapshot.scope.warehouseId);
    final service = _stocktake;
    if (service == null) throw StateError('Stocktake service is unavailable');
    final product = await (_db.select(
      _db.products,
    )..where((p) => p.id.equals(item.snapshot.productId))).getSingle();
    final scale = product.measurementType == 'piece' ? 1 : 1000;
    if (item.quantityScale != scale) {
      throw StateError('Count unit changed; refresh');
    }
    final quantity = item.parseQuantity(countedQuantity);
    final results = await service.postCounts(
      counts: [
        WarehouseCount(snapshot: item.snapshot, countedQuantity: quantity),
      ],
      reason: reason,
      userId: actor,
    );
    if (results.isNotEmpty) {
      await AuditLogService(_db).log(
        entityType: 'business_warehouse_stocks',
        entityId: item.snapshot.variantId,
        action: 'warehouse_stocktake',
        userId: actor,
        userRole: 'owner',
        newValue: {
          'warehouseId': item.snapshot.scope.warehouseId,
          'countedQuantity': quantity,
          'observedQuantity': item.quantity,
          'reason': reason.trim(),
        },
      );
    }
  });

  /// Initializes quantity and its opening-equity journal atomically. Reusing a
  /// stale selection cannot add another opening quantity to an existing balance.
  Future<int> initializeOpening({
    required String warehouseId,
    required WarehouseSetupItem item,
    required String cost,
    required String quantity,
    required String reason,
    DateTime? expiryDate,
    String? manufacturerLotNumber,
  }) => _db.transaction(() async {
    final actor = await _authorize();
    final scope = await _scope(warehouseId);
    final adjustments = _adjustments;
    if (adjustments == null) throw StateError('Opening service unavailable');
    final amount = item.parseQuantity(quantity);
    if (amount <= 0 || reason.trim().isEmpty || reason.length > 500) {
      throw ArgumentError('Opening quantity and reason are required');
    }
    final variant = await (_db.select(
      _db.productVariants,
    )..where((v) => v.id.equals(item.variantId))).getSingle();
    final product = await (_db.select(
      _db.products,
    )..where((p) => p.id.equals(variant.productId))).getSingle();
    final scale = product.measurementType == 'piece' ? 1 : 1000;
    if (scale != item.quantityScale ||
        product.inventoryTrackingType != item.tracking) {
      throw StateError('Product setup changed; reload the selection');
    }
    final created = await initialize(
      warehouseId: warehouseId,
      item: item,
      cost: cost,
    );
    if (created == 0) {
      throw StateError('Balance already initialized; use a stock adjustment');
    }
    final result = await adjustments.adjust(
      productId: product.id,
      variantId: variant.id,
      scope: scope,
      type: InventoryAdjustmentType.openingBalance,
      quantityDelta: amount,
      currencyId: item.currencyId,
      reason: reason,
      userId: actor,
      expiryDate: expiryDate,
      manufacturerLotNumber: manufacturerLotNumber,
    );
    await AuditLogService(_db).log(
      entityType: 'inventory_adjustments',
      entityId: result.adjustmentId,
      action: 'initialize_warehouse_opening',
      userId: actor,
      userRole: 'owner',
      newValue: {
        'warehouseId': warehouseId,
        'variantId': variant.id,
        'quantity': amount,
        'unitCostCents': item.parseCost(cost),
        'currencyId': item.currencyId,
        'journalEntryId': result.journalEntryId,
      },
    );
    return created;
  });

  Future<int> initialize({
    required String warehouseId,
    required WarehouseSetupItem item,
    required String cost,
  }) => _db.transaction(() async {
    final actor = await _authorize();
    final scope = await _scope(warehouseId);
    final code = await (_db.select(
      _db.currencies,
    )..where((c) => c.id.equals(item.currencyId))).getSingle();
    final configured = money.Currency.allCurrencies.firstWhere(
      (c) => c.code == code.code,
    );
    if (code.code != item.currencyCode ||
        configured.decimalDigits != item.decimalDigits) {
      throw StateError('Currency changed; reload the selection.');
    }
    final operatingCode = _operatingCurrencyCode?.call();
    if (operatingCode == null || operatingCode != item.currencyCode) {
      throw StateError(
        'Initialization must use the configured branch currency',
      );
    }
    await BranchCurrencyPolicyStore(_db).bind(operatingCode);
    final unitCost = item.parseCost(cost);
    final created = await WarehouseStockInitializationService(_db).initialize(
      scope: scope,
      currencyId: item.currencyId,
      seeds: [
        WarehouseStockSeed(variantId: item.variantId, unitCostCents: unitCost),
      ],
    );
    if (created != 0) {
      await AuditLogService(_db).log(
        entityType: 'business_warehouse_stocks',
        entityId: item.variantId,
        action: 'initialize_warehouse_stock',
        userId: actor,
        userRole: 'owner',
        newValue: {
          'warehouseId': warehouseId,
          'quantity': 0,
          'unitCostCents': unitCost,
          'currencyId': item.currencyId,
        },
      );
    }
    return created;
  });
}
