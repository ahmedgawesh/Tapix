import 'dart:convert';

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
import '../../../core/services/sync/branch_catalogue_sync_service.dart';
import '../../../core/services/sync/branch_location_directory_sync_service.dart';
import '../../../core/services/sync/offline_sync_event_store.dart';
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

/// Company locations are maintained by the LAN coordinator. Independent
/// branch databases receive that directory through synchronization so two
/// devices can never create competing definitions for the same company.
class WarehouseDirectoryAuthorityRequired implements Exception {
  const WarehouseDirectoryAuthorityRequired();
}

/// A branch is an operating identity. Its warehouses are stock locations.
/// Creating this directory entry never changes the local database identity and
/// never copies stock into the new branch.
class BusinessBranchOverview {
  const BusinessBranchOverview({
    required this.branch,
    required this.defaultWarehouse,
    required this.warehouseCount,
    required this.isLocal,
    this.warehouses = const [],
    this.connectionStatus = 'not_connected',
    this.isOnline = false,
    this.lastSeenAt,
    this.catalogueMode = BranchCatalogueMode.allCompanyProducts,
  });

  final BusinessBranch branch;
  final BusinessWarehouse defaultWarehouse;
  final int warehouseCount;
  final bool isLocal;
  final List<BusinessWarehouse> warehouses;
  final String connectionStatus;
  final bool isOnline;
  final DateTime? lastSeenAt;
  final BranchCatalogueMode catalogueMode;

  List<BusinessWarehouse> get visibleWarehouses =>
      warehouses.isEmpty ? [defaultWarehouse] : warehouses;
}

enum BranchCatalogueMode { allCompanyProducts, managedAssortment }

class BranchCataloguePolicy {
  const BranchCataloguePolicy({
    this.mode = BranchCatalogueMode.allCompanyProducts,
    this.categoryIds = const {},
    this.productIds = const {},
    this.excludedProductIds = const {},
  });

  final BranchCatalogueMode mode;
  final Set<int> categoryIds;
  final Set<int> productIds;
  final Set<int> excludedProductIds;

  bool get isManaged => mode == BranchCatalogueMode.managedAssortment;

  Map<String, Object?> toJson() => {
    'version': 1,
    'mode': mode == BranchCatalogueMode.allCompanyProducts
        ? 'all_company_products'
        : 'managed_assortment',
    'categoryIds': categoryIds.toList()..sort(),
    'productIds': productIds.toList()..sort(),
    'excludedProductIds': excludedProductIds.toList()..sort(),
  };

  factory BranchCataloguePolicy.fromJson(Object? raw) {
    if (raw is! Map) return const BranchCataloguePolicy();
    Set<int> ids(String key) =>
        (raw[key] is List ? raw[key] as List : const <Object?>[])
            .map((value) => value is int ? value : int.tryParse('$value'))
            .whereType<int>()
            .where((value) => value > 0)
            .toSet();
    return BranchCataloguePolicy(
      mode: raw['mode'] == 'managed_assortment'
          ? BranchCatalogueMode.managedAssortment
          : BranchCatalogueMode.allCompanyProducts,
      categoryIds: ids('categoryIds'),
      productIds: ids('productIds'),
      excludedProductIds: ids('excludedProductIds'),
    );
  }
}

class BranchCatalogueOption {
  const BranchCatalogueOption({
    required this.id,
    required this.name,
    this.code,
  });

  final int id;
  final String name;
  final String? code;
}

class BranchCatalogueOptions {
  const BranchCatalogueOptions({
    required this.categories,
    required this.products,
  });

  final List<BranchCatalogueOption> categories;
  final List<BranchCatalogueOption> products;
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
    this.suggestedUnitCostCents,
  });
  final int variantId;
  final String name, label, currencyCode;
  final int currencyId, decimalDigits, quantityScale;
  final String tracking;
  final int? suggestedUnitCostCents;

  String get suggestedCostText {
    final cost = suggestedUnitCostCents;
    if (cost == null || cost < 0) return '';
    final digits = cost.toString().padLeft(decimalDigits + 1, '0');
    if (decimalDigits == 0) return digits;
    return '${digits.substring(0, digits.length - decimalDigits)}.${digits.substring(digits.length - decimalDigits)}';
  }

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

/// One reportable stock location together with its owning branch identity.
///
/// Reports must show the branch explicitly because warehouse codes are only a
/// storage implementation detail and can be similar across different branches.
class WarehouseReportLocation {
  const WarehouseReportLocation({
    required this.warehouse,
    required this.branchName,
    required this.branchCode,
    required this.isLocalBranch,
  });

  final BusinessWarehouse warehouse;
  final String branchName;
  final String branchCode;
  final bool isLocalBranch;

  bool get isBranchLocation => warehouse.locationKind == 'branch_store';
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
    OfflineSyncEventStore? syncEvents,
    BranchLocationDirectorySyncService? locationDirectory,
    BranchCatalogueSyncService? catalogue,
  }) : _isRemoteClient = isRemoteClient,
       _stocktake = stocktake,
       _adjustments = adjustments,
       _operatingCurrencyCode = operatingCurrencyCode,
       _syncEvents = syncEvents,
       _locationDirectory = locationDirectory,
       _catalogue = catalogue;
  final AppDatabase _db;
  final SessionService _session;
  final WarehouseSetupEntitlement _entitlement;
  final bool Function() _isRemoteClient;
  final WarehouseStocktakeService? _stocktake;
  final InventoryAdjustmentService? _adjustments;
  final String Function()? _operatingCurrencyCode;
  final OfflineSyncEventStore? _syncEvents;
  final BranchLocationDirectorySyncService? _locationDirectory;
  final BranchCatalogueSyncService? _catalogue;

  static String _cataloguePolicyKey(String branchId) =>
      'lan.branch_catalogue.policy.v1.$branchId';

  Future<void> _assertDirectoryAuthority(
    WarehouseOperationScope primary,
  ) async {
    final authority = await _db
        .customSelect(
          "SELECT value FROM app_settings WHERE key='lan.branch_sync.coordinator_database_id.v1'",
        )
        .getSingleOrNull();
    if (authority != null &&
        authority.read<String>('value') != primary.databaseId) {
      throw const WarehouseDirectoryAuthorityRequired();
    }
  }

  Future<T> _writeLocationMutation<T>(
    Future<T> Function(OfflineSyncTransaction? sync) action,
  ) async {
    final events = _syncEvents;
    if (events == null) return _db.transaction(() => action(null));
    return events.transaction((sync) async {
      final result = await action(sync);
      if (await sync.isWriterRecordingEnabled()) {
        final directory = _locationDirectory;
        if (directory == null) {
          throw StateError('Location directory publisher is unavailable');
        }
        await directory.publishSnapshot(transaction: sync);
      }
      return result;
    });
  }

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
      final primary = await WarehouseOperationScope.resolve(_db);
      await _assertDirectoryAuthority(primary);
      return await _entitlement.permits(primary);
    } on Object {
      return false;
    }
  });

  Future<WarehouseOperationScope> _authorizePro() async {
    await _authorize();
    final primary = await WarehouseOperationScope.resolve(_db);
    if (!await _entitlement.permits(primary)) {
      throw const WarehouseSetupDenied();
    }
    return primary;
  }

  /// Lists the branch directory for the current organization. A non-local
  /// branch is only a prepared identity until a separate branch database is
  /// explicitly enrolled in a later step.
  Future<List<BusinessBranchOverview>> branches() => _db.transaction(() async {
    final primary = await _authorizePro();
    final branchRows =
        await (_db.select(_db.businessBranches)
              ..where(
                (b) =>
                    b.organizationId.equals(primary.organizationId) &
                    b.isActive.equals(true),
              )
              ..orderBy([
                (b) => OrderingTerm.asc(b.createdAt),
                (b) => OrderingTerm.asc(b.code),
              ]))
            .get();
    final warehouseRows =
        await (_db.select(_db.businessWarehouses)
              ..where(
                (w) =>
                    w.organizationId.equals(primary.organizationId) &
                    w.isActive.equals(true),
              )
              ..orderBy([
                (w) => OrderingTerm.asc(w.createdAt),
                (w) => OrderingTerm.asc(w.code),
              ]))
            .get();
    final policyRows = await _db
        .customSelect(
          "SELECT key,value FROM app_settings WHERE key LIKE 'lan.branch_catalogue.policy.v1.%'",
        )
        .get();
    final catalogueModes = <String, BranchCatalogueMode>{};
    for (final row in policyRows) {
      final key = row.read<String>('key');
      final branchId = key.substring('lan.branch_catalogue.policy.v1.'.length);
      try {
        final decoded = jsonDecode(row.read<String>('value'));
        if (decoded is Map && decoded['mode'] == 'managed_assortment') {
          catalogueModes[branchId] = BranchCatalogueMode.managedAssortment;
        }
      } on FormatException {
        // Invalid legacy values safely fall back to the full company catalogue.
      }
    }
    final enrollmentRows = await _db
        .customSelect(
          '''SELECT e.branch_id,e.status,e.expires_at,
          CASE
            WHEN r.last_seen_at IS NULL THEN c.last_seen_at
            WHEN c.last_seen_at IS NULL THEN r.last_seen_at
            WHEN r.last_seen_at > c.last_seen_at THEN r.last_seen_at
            ELSE c.last_seen_at
          END AS last_seen_at
          FROM lan_branch_enrollments e
          LEFT JOIN lan_branch_sync_credentials c
            ON c.enrollment_id=e.enrollment_id AND c.status='active'
          LEFT JOIN lan_branch_recovery_credentials r
            ON r.enrollment_id=e.enrollment_id AND r.status='active'
          WHERE e.organization_id=? AND e.status IN('pending','active')
          ORDER BY CASE e.status WHEN 'active' THEN 0 ELSE 1 END,e.created_at DESC''',
          variables: [Variable.withString(primary.organizationId)],
        )
        .get();
    final enrollmentByBranch = <String, QueryRow>{};
    for (final row in enrollmentRows) {
      enrollmentByBranch.putIfAbsent(row.read<String>('branch_id'), () => row);
    }
    final result = <BusinessBranchOverview>[];
    for (final branch in branchRows) {
      final branchWarehouses = warehouseRows
          .where((warehouse) => warehouse.branchId == branch.id)
          .toList(growable: false);
      // A branch without a stock location is structurally incomplete and
      // cannot be offered for enrollment or operations.
      if (branchWarehouses.isEmpty) continue;
      final branchLocation = branchWarehouses.firstWhere(
        (warehouse) => warehouse.locationKind == 'branch_store',
        orElse: () => branchWarehouses.first,
      );
      final enrollment = enrollmentByBranch[branch.id];
      var connectionStatus = branch.id == primary.branchId
          ? 'current'
          : 'not_connected';
      if (enrollment != null && branch.id != primary.branchId) {
        connectionStatus = enrollment.read<String>('status');
        if (connectionStatus == 'pending' &&
            !DateTime.now().toUtc().isBefore(
              DateTime.parse(enrollment.read<String>('expires_at')).toUtc(),
            )) {
          connectionStatus = 'expired';
        }
      }
      final lastSeenAt = enrollment == null
          ? null
          : DateTime.tryParse(
              enrollment.readNullable<String>('last_seen_at') ?? '',
            )?.toLocal();
      final isLocal = branch.id == primary.branchId;
      final isOnline =
          isLocal ||
          (connectionStatus == 'active' &&
              lastSeenAt != null &&
              DateTime.now().difference(lastSeenAt).abs() <=
                  const Duration(seconds: 60));
      result.add(
        BusinessBranchOverview(
          branch: branch,
          defaultWarehouse: branchLocation,
          warehouseCount: branchWarehouses.length,
          isLocal: isLocal,
          warehouses: branchWarehouses,
          connectionStatus: connectionStatus,
          isOnline: isOnline,
          lastSeenAt: lastSeenAt,
          catalogueMode:
              catalogueModes[branch.id] ??
              BranchCatalogueMode.allCompanyProducts,
        ),
      );
    }
    return result;
  });

  Future<BranchCataloguePolicy> cataloguePolicy(String branchId) async {
    final primary = await _authorizePro();
    await _assertDirectoryAuthority(primary);
    await _requireBranch(primary, branchId);
    final row = await _db
        .customSelect(
          'SELECT value FROM app_settings WHERE key=?',
          variables: [Variable.withString(_cataloguePolicyKey(branchId))],
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

  Future<BranchCatalogueOptions> catalogueOptions(String branchId) async {
    final primary = await _authorizePro();
    await _assertDirectoryAuthority(primary);
    await _requireBranch(primary, branchId);
    final categories = await _db
        .customSelect(
          'SELECT id,name FROM product_categories WHERE is_active=1 ORDER BY name COLLATE NOCASE,id',
        )
        .get();
    final products = await _db.customSelect(
      '''SELECT id,name,COALESCE(NULLIF(sku,''),NULLIF(barcode,'')) AS code
          FROM products WHERE is_active=1 ORDER BY name COLLATE NOCASE,id''',
    ).get();
    return BranchCatalogueOptions(
      categories: [
        for (final row in categories)
          BranchCatalogueOption(
            id: row.read<int>('id'),
            name: row.read<String>('name'),
          ),
      ],
      products: [
        for (final row in products)
          BranchCatalogueOption(
            id: row.read<int>('id'),
            name: row.read<String>('name'),
            code: row.readNullable<String>('code'),
          ),
      ],
    );
  }

  Future<void> saveCataloguePolicy({
    required String branchId,
    required BranchCataloguePolicy policy,
  }) async {
    final actor = await _authorize();
    final primary = await _authorizePro();
    await _assertDirectoryAuthority(primary);
    await _requireBranch(primary, branchId);
    final options = await catalogueOptions(branchId);
    final validCategories = options.categories.map((item) => item.id).toSet();
    final validProducts = options.products.map((item) => item.id).toSet();
    if (!validCategories.containsAll(policy.categoryIds) ||
        !validProducts.containsAll(policy.productIds) ||
        !validProducts.containsAll(policy.excludedProductIds) ||
        policy.productIds.intersection(policy.excludedProductIds).isNotEmpty) {
      throw ArgumentError('Branch catalogue selection is invalid');
    }
    if (policy.isManaged &&
        policy.categoryIds.isEmpty &&
        policy.productIds.isEmpty) {
      throw ArgumentError('Managed assortment cannot be empty');
    }
    final encoded = jsonEncode(policy.toJson());
    await _db.transaction(() async {
      await _db.customStatement(
        '''INSERT INTO app_settings(key,value,description,updated_at)
        VALUES(?,?,'Branch catalogue policy',CURRENT_TIMESTAMP)
        ON CONFLICT(key) DO UPDATE SET value=excluded.value,
        description=excluded.description,updated_at=CURRENT_TIMESTAMP''',
        [_cataloguePolicyKey(branchId), encoded],
      );
      final branchRowId = await _db
          .customSelect(
            'SELECT rowid AS row_id FROM business_branches WHERE id=?',
            variables: [Variable.withString(branchId)],
          )
          .map((row) => row.read<int>('row_id'))
          .getSingle();
      await AuditLogService(_db).log(
        entityType: 'business_branches',
        entityId: branchRowId,
        action: 'update_branch_catalogue_policy',
        userId: actor,
        userRole: 'owner',
        newValue: {'branchId': branchId, ...policy.toJson()},
      );
    });
    // Content-addressed publication is idempotent. If the network is down,
    // the next authenticated branch pull publishes the same policy again.
    if (await _syncEvents?.isWriterRecordingEnabled() == true) {
      await _catalogue?.publishSnapshot();
    }
  }

  Future<BusinessBranch> _requireBranch(
    WarehouseOperationScope primary,
    String branchId,
  ) async {
    final row =
        await (_db.select(_db.businessBranches)..where(
              (branch) =>
                  branch.id.equals(branchId) &
                  branch.organizationId.equals(primary.organizationId) &
                  branch.isActive.equals(true),
            ))
            .getSingleOrNull();
    if (row == null) throw ArgumentError('Branch is invalid or inactive');
    return row;
  }

  /// Creates a branch directory entry and its branch sales location atomically.
  /// The current device remains bound to its existing branch and no balance is
  /// copied. Device enrollment is deliberately a separate operation.
  Future<BusinessBranchOverview> createBranchWithDefaultWarehouse({
    required String branchName,
    required String branchCode,
    required String warehouseName,
    required String warehouseCode,
  }) => _writeLocationMutation((_) async {
    final actor = await _authorize();
    final primary = await _authorizePro();
    await _assertDirectoryAuthority(primary);
    final normalizedBranchName = branchName.trim();
    final normalizedBranchCode = branchCode.trim().toUpperCase();
    final normalizedWarehouseName = warehouseName.trim();
    final normalizedWarehouseCode = warehouseCode.trim().toUpperCase();
    final codePattern = RegExp(r'^[A-Z0-9][A-Z0-9_-]{0,31}$');
    if (normalizedBranchName.isEmpty ||
        normalizedBranchName.length > 100 ||
        !codePattern.hasMatch(normalizedBranchCode)) {
      throw ArgumentError('Branch requires a name and a unique short code');
    }
    if (normalizedWarehouseName.isEmpty ||
        normalizedWarehouseName.length > 100 ||
        !codePattern.hasMatch(normalizedWarehouseCode)) {
      throw ArgumentError(
        'Default warehouse requires a name and a unique short code',
      );
    }
    final duplicateBranch = await _db
        .customSelect(
          '''SELECT id FROM business_branches
          WHERE organization_id = ? AND UPPER(code) = ?''',
          variables: [
            Variable.withString(primary.organizationId),
            Variable.withString(normalizedBranchCode),
          ],
        )
        .getSingleOrNull();
    if (duplicateBranch != null) {
      throw StateError('Branch code already exists');
    }
    final duplicateWarehouse = await _db
        .customSelect(
          '''SELECT id FROM business_warehouses
          WHERE organization_id = ? AND UPPER(code) = ?''',
          variables: [
            Variable.withString(primary.organizationId),
            Variable.withString(normalizedWarehouseCode),
          ],
        )
        .getSingleOrNull();
    if (duplicateWarehouse != null) {
      throw StateError('Warehouse code already exists');
    }

    final branchId = const Uuid().v4();
    final warehouseId = const Uuid().v4();
    final branchRowId = await _db
        .into(_db.businessBranches)
        .insert(
          BusinessBranchesCompanion.insert(
            id: branchId,
            organizationId: primary.organizationId,
            code: normalizedBranchCode,
            name: Value(normalizedBranchName),
          ),
        );
    final warehouseRowId = await _db
        .into(_db.businessWarehouses)
        .insert(
          BusinessWarehousesCompanion.insert(
            id: warehouseId,
            organizationId: primary.organizationId,
            branchId: branchId,
            code: normalizedWarehouseCode,
            name: Value(normalizedWarehouseName),
            locationKind: const Value('branch_store'),
          ),
        );
    await AuditLogService(_db).log(
      entityType: 'business_branches',
      entityId: branchRowId,
      action: 'create_branch_directory',
      userId: actor,
      userRole: 'owner',
      newValue: {
        'branchId': branchId,
        'organizationId': primary.organizationId,
        'name': normalizedBranchName,
        'code': normalizedBranchCode,
        'localDatabaseChanged': false,
      },
    );
    await AuditLogService(_db).log(
      entityType: 'business_warehouses',
      entityId: warehouseRowId,
      action: 'create_branch_default_warehouse',
      userId: actor,
      userRole: 'owner',
      newValue: {
        'warehouseId': warehouseId,
        'branchId': branchId,
        'name': normalizedWarehouseName,
        'code': normalizedWarehouseCode,
        'locationKind': 'branch_store',
        'openingQuantity': 0,
      },
    );
    final branch = await (_db.select(
      _db.businessBranches,
    )..where((b) => b.id.equals(branchId))).getSingle();
    final warehouse = await (_db.select(
      _db.businessWarehouses,
    )..where((w) => w.id.equals(warehouseId))).getSingle();
    return BusinessBranchOverview(
      branch: branch,
      defaultWarehouse: warehouse,
      warehouseCount: 1,
      isLocal: false,
      warehouses: [warehouse],
      connectionStatus: 'not_connected',
    );
  });

  Future<BusinessWarehouse> createWarehouse({
    required String name,
    required String code,
    String? branchId,
  }) => _writeLocationMutation((_) async {
    final actor = await _authorize();
    final primary = await _authorizePro();
    await _assertDirectoryAuthority(primary);
    final targetBranchId = branchId ?? primary.branchId;
    final targetBranch =
        await (_db.select(_db.businessBranches)..where(
              (branch) =>
                  branch.id.equals(targetBranchId) &
                  branch.organizationId.equals(primary.organizationId) &
                  branch.isActive.equals(true),
            ))
            .getSingleOrNull();
    if (targetBranch == null) {
      throw ArgumentError('Warehouse branch is invalid or inactive');
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
            branchId: targetBranchId,
            code: normalizedCode,
            name: Value(normalizedName),
            locationKind: const Value('warehouse'),
          ),
        );
    await AuditLogService(_db).log(
      entityType: 'business_warehouses',
      entityId: rowId,
      action: 'create_warehouse',
      userId: actor,
      userRole: 'owner',
      newValue: {
        'warehouseId': id,
        'branchId': targetBranchId,
        'name': normalizedName,
        'code': normalizedCode,
        'locationKind': 'warehouse',
      },
    );
    return (_db.select(
      _db.businessWarehouses,
    )..where((w) => w.id.equals(id))).getSingle();
  });

  /// Changes only the human-readable branch name. The immutable code and UUID
  /// keep documents, enrollments and synchronization routes stable.
  Future<BusinessBranch> renameBranch({
    required String branchId,
    required String name,
  }) => _writeLocationMutation((_) async {
    final actor = await _authorize();
    final primary = await _authorizePro();
    await _assertDirectoryAuthority(primary);
    final normalizedId = branchId.trim().toLowerCase();
    final normalizedName = name.trim();
    if (!Uuid.isValidUUID(fromString: normalizedId) ||
        normalizedName.isEmpty ||
        normalizedName.length > 100) {
      throw ArgumentError('Branch requires a valid identity and name');
    }
    final branch =
        await (_db.select(_db.businessBranches)..where(
              (row) =>
                  row.id.equals(normalizedId) &
                  row.organizationId.equals(primary.organizationId) &
                  row.isActive.equals(true),
            ))
            .getSingleOrNull();
    if (branch == null) throw StateError('Branch is unavailable');
    if (branch.name == normalizedName) return branch;
    final duplicate = await _db
        .customSelect(
          '''SELECT id FROM business_branches
          WHERE organization_id=? AND id<>? AND is_active=1
            AND lower(trim(name))=lower(?)''',
          variables: [
            Variable.withString(primary.organizationId),
            Variable.withString(normalizedId),
            Variable.withString(normalizedName),
          ],
        )
        .getSingleOrNull();
    if (duplicate != null) throw StateError('Branch name already exists');
    await (_db.update(_db.businessBranches)
          ..where((row) => row.id.equals(normalizedId)))
        .write(BusinessBranchesCompanion(name: Value(normalizedName)));
    final auditId = await _db
        .customSelect(
          'SELECT rowid AS audit_id FROM business_branches WHERE id=?',
          variables: [Variable.withString(normalizedId)],
        )
        .map((row) => row.read<int>('audit_id'))
        .getSingle();
    await AuditLogService(_db).log(
      entityType: 'business_branches',
      entityId: auditId,
      action: 'rename_branch',
      userId: actor,
      userRole: 'owner',
      oldValue: {'name': branch.name, 'code': branch.code},
      newValue: {'name': normalizedName, 'code': branch.code},
    );
    return (_db.select(
      _db.businessBranches,
    )..where((row) => row.id.equals(normalizedId))).getSingle();
  });

  /// Changes only the human-readable warehouse name and publishes the updated
  /// company directory atomically. Stock, documents and routing IDs do not move.
  Future<BusinessWarehouse> renameWarehouse({
    required String warehouseId,
    required String name,
  }) => _writeLocationMutation((_) async {
    final actor = await _authorize();
    final primary = await _authorizePro();
    await _assertDirectoryAuthority(primary);
    final normalizedId = warehouseId.trim().toLowerCase();
    final normalizedName = name.trim();
    if (!Uuid.isValidUUID(fromString: normalizedId) ||
        normalizedName.isEmpty ||
        normalizedName.length > 100) {
      throw ArgumentError('Warehouse requires a valid identity and name');
    }
    final warehouse =
        await (_db.select(_db.businessWarehouses)..where(
              (row) =>
                  row.id.equals(normalizedId) &
                  row.organizationId.equals(primary.organizationId) &
                  row.isActive.equals(true),
            ))
            .getSingleOrNull();
    if (warehouse == null) throw StateError('Warehouse is unavailable');
    if (warehouse.name == normalizedName) return warehouse;
    final duplicate = await _db
        .customSelect(
          '''SELECT id FROM business_warehouses
          WHERE branch_id=? AND id<>? AND is_active=1
            AND lower(trim(name))=lower(?)''',
          variables: [
            Variable.withString(warehouse.branchId),
            Variable.withString(normalizedId),
            Variable.withString(normalizedName),
          ],
        )
        .getSingleOrNull();
    if (duplicate != null) throw StateError('Warehouse name already exists');
    await (_db.update(_db.businessWarehouses)
          ..where((row) => row.id.equals(normalizedId)))
        .write(BusinessWarehousesCompanion(name: Value(normalizedName)));
    final auditId = await _db
        .customSelect(
          'SELECT rowid AS audit_id FROM business_warehouses WHERE id=?',
          variables: [Variable.withString(normalizedId)],
        )
        .map((row) => row.read<int>('audit_id'))
        .getSingle();
    await AuditLogService(_db).log(
      entityType: 'business_warehouses',
      entityId: auditId,
      action: 'rename_warehouse',
      userId: actor,
      userRole: 'owner',
      oldValue: {
        'name': warehouse.name,
        'code': warehouse.code,
        'branchId': warehouse.branchId,
      },
      newValue: {
        'name': normalizedName,
        'code': warehouse.code,
        'branchId': warehouse.branchId,
      },
    );
    return (_db.select(
      _db.businessWarehouses,
    )..where((row) => row.id.equals(normalizedId))).getSingle();
  });

  /// Resolves an immutable report scope anywhere in the current organization.
  /// This is deliberately separate from [_scope], which restricts stock writes
  /// to the local branch and excludes its primary location.
  Future<WarehouseReadScope> reportScope(String warehouseId) =>
      _db.transaction(() async {
        await _authorize();
        final operation = await WarehouseOperationScope.resolveForOrganization(
          _db,
          warehouseId: warehouseId,
        );
        if (!await _entitlement.permits(operation)) {
          throw const WarehouseSetupDenied();
        }
        final read = await operation.forReading(_db);
        return read.withAccessCheck(() async {
          await _authorize();
          if (!await _entitlement.permits(operation)) {
            throw const WarehouseSetupDenied();
          }
        });
      });

  /// Lists every active branch sales location and independent warehouse that
  /// the central owner can report on. This includes the local primary location.
  Future<List<WarehouseReportLocation>> reportLocations() =>
      _db.transaction(() async {
        final primary = await _authorizePro();
        final rows = await _db
            .customSelect(
              '''SELECT w.*, b.name AS report_branch_name,
                    b.code AS report_branch_code,
                    CASE WHEN b.id=? THEN 1 ELSE 0 END AS report_is_local
             FROM business_warehouses w
             JOIN business_branches b ON b.id=w.branch_id
               AND b.organization_id=w.organization_id
             WHERE w.organization_id=? AND w.is_active=1 AND b.is_active=1
             ORDER BY CASE WHEN w.id=? THEN 0 ELSE 1 END,
               UPPER(b.code),
               CASE w.location_kind WHEN 'branch_store' THEN 0 ELSE 1 END,
               UPPER(w.code)''',
              variables: [
                Variable.withString(primary.branchId),
                Variable.withString(primary.organizationId),
                Variable.withString(primary.warehouseId),
              ],
              readsFrom: {_db.businessWarehouses, _db.businessBranches},
            )
            .get();
        return rows
            .map(
              (row) => WarehouseReportLocation(
                warehouse: _db.businessWarehouses.map(row.data),
                branchName: row.read<String>('report_branch_name'),
                branchCode: row.read<String>('report_branch_code'),
                isLocalBranch: row.read<int>('report_is_local') == 1,
              ),
            )
            .toList(growable: false);
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
      SELECT v.id, v.cost_cents AS suggested_cost, p.name, COALESCE(v.sku, v.barcode, '') label,
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
        suggestedUnitCostCents: r.read<int>('suggested_cost'),
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
