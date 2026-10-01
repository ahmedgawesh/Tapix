import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../database/app_database.dart';
import 'offline_sync_event_store.dart';
import 'sync_entity_identity_store.dart';

class SharedCatalogueAuthorityRequired implements Exception {
  const SharedCatalogueAuthorityRequired();

  @override
  String toString() => 'Shared catalogue changes require the LAN coordinator.';
}

/// Publishes and applies the shared catalogue used by independent LAN branch
/// databases. Quantities, balances and journal history never travel in this
/// snapshot: every branch starts those values at zero and owns its movements.
class BranchCatalogueSyncService {
  BranchCatalogueSyncService(
    this._db,
    this._events,
    this._identities, {
    Uuid uuid = const Uuid(),
  }) : _uuid = uuid;

  final AppDatabase _db;
  final OfflineSyncEventStore _events;
  final SyncEntityIdentityStore _identities;
  final Uuid _uuid;

  static const eventType = 'catalogue.snapshot_page.v1';
  static const customerProfileEventType = 'customer.profile_upserted.v1';
  static const _pageSize = 10;
  static const _entityOrder = <String>[
    'supplier',
    'customer',
    'category',
    'color',
    'size',
    'product',
    'variant',
    'promotion',
  ];

  /// Shared product and supplier master data is authored by the coordinator.
  /// Independent branch databases receive it through catalogue snapshots and
  /// must not create a competing local version that a later snapshot replaces.
  Future<bool> isSharedCatalogueAuthority() async {
    final localDatabaseId = await _db
        .customSelect('SELECT database_id FROM sync_local_state WHERE id=1')
        .map((row) => row.read<String>('database_id'))
        .getSingle();
    final authority = await _db
        .customSelect(
          'SELECT value FROM app_settings WHERE key='
          "'lan.branch_sync.coordinator_database_id.v1'",
        )
        .map((row) => row.read<String>('value'))
        .getSingleOrNull();
    return authority == null || authority == localDatabaseId;
  }

  /// Once this database participates in branch synchronization, removals are
  /// represented as inactive catalogue rows so every branch receives the
  /// same tombstone and historical document references remain resolvable.
  Future<bool> isSharedCatalogueDistributed() =>
      _events.isWriterRecordingEnabled();

  Future<String> publishSnapshot() async {
    final state = await _db
        .customSelect(
          'SELECT database_id,organization_id,branch_id '
          'FROM sync_local_state WHERE id=1',
        )
        .getSingle();
    final sourceDatabaseId = state.read<String>('database_id');
    final organizationId = state.read<String>('organization_id');
    final branchId = state.read<String>('branch_id');
    final featurePolicy = await _featurePolicyPayload();
    final entities = <String, List<Map<String, Object?>>>{
      'supplier': await _supplierPayload(),
      'customer': await _customerPayload(),
      'category': await _categoryPayload(sourceDatabaseId),
      'color': await _dimensionPayload('color', 'product_colors'),
      'size': await _dimensionPayload('size', 'sizes'),
      'product': await _productPayload(),
      'variant': await _variantPayload(),
      'promotion': await _promotionPayload(),
    };
    final canonical = jsonEncode({
      'featurePolicy': featurePolicy,
      'entities': [for (final type in _entityOrder) ...entities[type]!],
    });
    final digest = sha256.convert(utf8.encode(canonical)).toString();
    final snapshotId = _uuid.v5(
      Namespace.url.value,
      'tapix-catalogue-v1:$sourceDatabaseId:$digest',
    );
    final generatedAt = DateTime.now().toUtc();

    for (final type in _entityOrder) {
      final values = entities[type]!;
      final pageCount = values.isEmpty ? 1 : (values.length / _pageSize).ceil();
      for (var pageIndex = 0; pageIndex < pageCount; pageIndex++) {
        final start = pageIndex * _pageSize;
        final end = values.isEmpty
            ? 0
            : (start + _pageSize).clamp(0, values.length);
        final page = values.isEmpty
            ? const <Map<String, Object?>>[]
            : values.sublist(start, end);
        await _events.transaction((sync) async {
          if (!await sync.isWriterRecordingEnabled()) {
            throw const OfflineSyncException(
              'catalogue_writer_not_enrolled',
              'Catalogue publication requires an enrolled branch writer.',
            );
          }
          await sync.appendOnce(
            producerKey: 'catalogue:$snapshotId:$type:$pageIndex',
            eventType: eventType,
            aggregateType: 'catalogue_snapshot',
            aggregateId: snapshotId,
            payload: {
              'contract': 'catalogue.snapshot_page',
              'contractVersion': 1,
              'snapshotId': snapshotId,
              'organizationId': organizationId,
              'sourceDatabaseId': sourceDatabaseId,
              'sourceBranchId': branchId,
              'entityType': type,
              'featurePolicy': featurePolicy,
              'pageIndex': pageIndex,
              'pageCount': pageCount,
              'entities': page,
            },
            occurredAt: generatedAt,
          );
        });
      }
    }
    return snapshotId;
  }

  Future<void> applyPage(SyncEventEnvelope event) async {
    final payload = event.payload;
    if (event.eventType != eventType ||
        event.contractVersion != 1 ||
        payload['contract'] != 'catalogue.snapshot_page' ||
        payload['contractVersion'] != 1 ||
        event.aggregateType != 'catalogue_snapshot') {
      throw const OfflineSyncException(
        'invalid_catalogue_contract',
        'The catalogue synchronization contract is invalid.',
      );
    }
    final authority = await _db
        .customSelect(
          "SELECT value FROM app_settings WHERE key='lan.branch_sync.coordinator_database_id.v1'",
        )
        .getSingleOrNull();
    if (authority == null ||
        authority.read<String>('value') != event.sourceDatabaseId) {
      throw const OfflineSyncException(
        'catalogue_source_not_authoritative',
        'Only the enrolled LAN coordinator can publish the shared catalogue.',
      );
    }
    final snapshotId = _uuidField(payload, 'snapshotId');
    final organizationId = _uuidField(payload, 'organizationId');
    final sourceDatabaseId = _uuidField(payload, 'sourceDatabaseId');
    final sourceBranchId = _uuidField(payload, 'sourceBranchId');
    if (snapshotId != event.aggregateId ||
        organizationId != event.organizationId ||
        sourceDatabaseId != event.sourceDatabaseId ||
        sourceBranchId != event.branchId) {
      throw const OfflineSyncException(
        'catalogue_envelope_mismatch',
        'The catalogue page does not match its event envelope.',
      );
    }
    final localOrganization = await _db
        .customSelect(
          'SELECT organization_id FROM business_contexts WHERE id=1',
        )
        .map((row) => row.read<String>('organization_id'))
        .getSingle();
    if (localOrganization != organizationId) {
      throw const OfflineSyncException(
        'catalogue_organization_mismatch',
        'The catalogue belongs to another organization.',
      );
    }
    final type = payload['entityType']?.toString() ?? '';
    final pageIndex = payload['pageIndex'];
    final pageCount = payload['pageCount'];
    final rawEntities = payload['entities'];
    if (!_entityOrder.contains(type) ||
        pageIndex is! int ||
        pageIndex < 0 ||
        pageCount is! int ||
        pageCount <= 0 ||
        pageIndex >= pageCount ||
        rawEntities is! List ||
        rawEntities.length > _pageSize) {
      throw const OfflineSyncException(
        'invalid_catalogue_page',
        'The catalogue page metadata is invalid.',
      );
    }
    final rawFeaturePolicy = payload['featurePolicy'];
    if (rawFeaturePolicy != null) {
      if (rawFeaturePolicy is! Map) {
        throw const OfflineSyncException(
          'invalid_catalogue_feature_policy',
          'The shared feature policy has an invalid structure.',
        );
      }
      await _applyFeaturePolicy(Map<String, Object?>.from(rawFeaturePolicy));
    }
    for (final raw in rawEntities) {
      if (raw is! Map) {
        throw const OfflineSyncException(
          'invalid_catalogue_entity',
          'A catalogue entity has an invalid structure.',
        );
      }
      await _applyEntity(type, Map<String, Object?>.from(raw), event);
    }
    await _db.customStatement(
      '''INSERT INTO sync_catalogue_pages(
        event_id,snapshot_id,entity_type,page_index,page_count,source_database_id)
        VALUES(?,?,?,?,?,?)''',
      [
        event.eventId,
        snapshotId,
        type,
        pageIndex,
        pageCount,
        event.sourceDatabaseId,
      ],
    );
  }

  /// Applies a customer identity/contact change authored by any enrolled
  /// branch. Financial balances, loyalty points and counters are deliberately
  /// absent from this contract and remain owned by the source branch ledger.
  Future<void> applyCustomerProfile(SyncEventEnvelope event) async {
    final payload = event.payload;
    final rawCustomer = payload['customer'];
    if (event.eventType != customerProfileEventType ||
        event.contractVersion != 1 ||
        event.aggregateType != 'customer' ||
        payload['contract'] != 'customer.profile_upserted' ||
        payload['contractVersion'] != 1 ||
        payload['organizationId'] != event.organizationId ||
        payload['sourceDatabaseId'] != event.sourceDatabaseId ||
        payload['sourceBranchId'] != event.branchId ||
        rawCustomer is! Map) {
      throw const OfflineSyncException(
        'invalid_customer_profile_contract',
        'The customer profile synchronization contract is invalid.',
      );
    }
    final customer = Map<String, Object?>.from(rawCustomer);
    if (_uuidField(customer, 'globalId') != event.aggregateId) {
      throw const OfflineSyncException(
        'customer_profile_identity_mismatch',
        'The customer profile identity does not match its event envelope.',
      );
    }
    await _applyCustomer(customer, event);
  }

  /// True only when one snapshot contains every entity family and every page
  /// declared for that family. Empty families still publish one empty page.
  Future<bool> hasCompleteSnapshot() async {
    final rows = await _db
        .customSelect(
          'SELECT snapshot_id,entity_type,page_index,page_count '
          'FROM sync_catalogue_pages ORDER BY applied_at DESC',
        )
        .get();
    final snapshots = <String, Map<String, ({int count, int pages})>>{};
    final invalidSnapshots = <String>{};
    for (final row in rows) {
      final snapshot = row.read<String>('snapshot_id');
      final type = row.read<String>('entity_type');
      final pageCount = row.read<int>('page_count');
      final byType = snapshots.putIfAbsent(snapshot, () => {});
      final current = byType[type];
      if (current != null && current.pages != pageCount) {
        invalidSnapshots.add(snapshot);
        continue;
      }
      byType[type] = (count: (current?.count ?? 0) + 1, pages: pageCount);
    }
    return snapshots.entries.any(
      (snapshot) =>
          !invalidSnapshots.contains(snapshot.key) &&
          _entityOrder.every(snapshot.value.containsKey) &&
          snapshot.value.values.every((entry) => entry.count == entry.pages),
    );
  }

  Future<Map<String, Object?>> _featurePolicyPayload() async {
    final rows = await _db.customSelect(
      """SELECT key,value FROM app_settings WHERE key IN
          ('pharmacy_features_enabled','promotions_enabled')""",
    ).get();
    final values = {
      for (final row in rows)
        row.read<String>('key'): row.read<String>('value'),
    };
    bool enabled(String key) {
      final value = values[key]?.trim().toLowerCase();
      return value == '1' || value == 'true';
    }

    return {
      'pharmacyEnabled': enabled('pharmacy_features_enabled'),
      'promotionsEnabled': enabled('promotions_enabled'),
      'branchAssortments': await _branchAssortmentPayload(),
    };
  }

  Future<Map<String, Object?>> _branchAssortmentPayload() async {
    final rows = await _db
        .customSelect(
          "SELECT key,value FROM app_settings WHERE key LIKE 'lan.branch_catalogue.policy.v1.%' ORDER BY key",
        )
        .get();
    final result = <String, Object?>{};
    for (final row in rows) {
      final key = row.read<String>('key');
      final branchId = key.substring('lan.branch_catalogue.policy.v1.'.length);
      if (!Uuid.isValidUUID(fromString: branchId)) continue;
      Object? decoded;
      try {
        decoded = jsonDecode(row.read<String>('value'));
      } on FormatException {
        continue;
      }
      if (decoded is! Map) continue;
      final decodedMap = Map<String, Object?>.from(decoded);
      final mode = decodedMap['mode'] == 'managed_assortment'
          ? 'managed_assortment'
          : 'all_company_products';
      Set<int> localIds(String field) =>
          (decodedMap[field] is List
                  ? decodedMap[field] as List
                  : const <Object?>[])
              .map((value) => value is int ? value : int.tryParse('$value'))
              .whereType<int>()
              .where((value) => value > 0)
              .toSet();
      final categoryIds = await _expandCategoryIds(localIds('categoryIds'));
      final categoryGlobalIds = <String>[];
      final sourceDatabaseId = await _localDatabaseId();
      for (final id in categoryIds) {
        final exists = await _db
            .customSelect(
              'SELECT 1 AS present FROM product_categories WHERE id=?',
              variables: [Variable.withInt(id)],
            )
            .getSingleOrNull();
        if (exists != null) {
          categoryGlobalIds.add(
            (await _dimensionIdentity(
              type: 'category',
              localId: id,
              sourceDatabaseId: sourceDatabaseId,
            )).globalId,
          );
        }
      }
      final productGlobalIds = <String>[];
      for (final id in localIds('productIds')) {
        final exists = await _db
            .customSelect(
              'SELECT 1 AS present FROM products WHERE id=?',
              variables: [Variable.withInt(id)],
            )
            .getSingleOrNull();
        if (exists != null) {
          productGlobalIds.add(
            (await _identities.getOrCreateLocal(
              entityType: 'product',
              localId: id,
            )).globalId,
          );
        }
      }
      final excludedGlobalIds = <String>[];
      for (final id in localIds('excludedProductIds')) {
        final exists = await _db
            .customSelect(
              'SELECT 1 AS present FROM products WHERE id=?',
              variables: [Variable.withInt(id)],
            )
            .getSingleOrNull();
        if (exists != null) {
          excludedGlobalIds.add(
            (await _identities.getOrCreateLocal(
              entityType: 'product',
              localId: id,
            )).globalId,
          );
        }
      }
      categoryGlobalIds.sort();
      productGlobalIds.sort();
      excludedGlobalIds.sort();
      result[branchId] = {
        'mode': mode,
        'categoryGlobalIds': categoryGlobalIds,
        'productGlobalIds': productGlobalIds,
        'excludedProductGlobalIds': excludedGlobalIds,
      };
    }
    return result;
  }

  Future<Set<int>> _expandCategoryIds(Set<int> roots) async {
    if (roots.isEmpty) return {};
    final rows = await _db
        .customSelect('SELECT id,parent_id FROM product_categories')
        .get();
    final children = <int, Set<int>>{};
    for (final row in rows) {
      final parent = row.readNullable<int>('parent_id');
      if (parent != null) {
        children.putIfAbsent(parent, () => <int>{}).add(row.read<int>('id'));
      }
    }
    final expanded = <int>{...roots};
    final pending = <int>[...roots];
    while (pending.isNotEmpty) {
      final id = pending.removeLast();
      for (final child in children[id] ?? const <int>{}) {
        if (expanded.add(child)) pending.add(child);
      }
    }
    return expanded;
  }

  Future<void> _applyFeaturePolicy(Map<String, Object?> policy) async {
    final pharmacy = _bool(policy, 'pharmacyEnabled');
    final promotions = _bool(policy, 'promotionsEnabled');
    await _applyLocalBranchAssortment(policy['branchAssortments']);
    await _db.customStatement(
      '''INSERT INTO app_settings(key,value,description,updated_at)
      VALUES('pharmacy_features_enabled',?,'Shared LAN branch feature policy',CURRENT_TIMESTAMP)
      ON CONFLICT(key) DO UPDATE SET value=excluded.value,
      description=excluded.description,updated_at=CURRENT_TIMESTAMP''',
      [pharmacy ? '1' : '0'],
    );
    await _db.customStatement(
      '''INSERT INTO app_settings(key,value,description,updated_at)
      VALUES('promotions_enabled',?,'Shared LAN branch feature policy',CURRENT_TIMESTAMP)
      ON CONFLICT(key) DO UPDATE SET value=excluded.value,
      description=excluded.description,updated_at=CURRENT_TIMESTAMP''',
      [promotions ? '1' : '0'],
    );
  }

  Future<void> _applyLocalBranchAssortment(Object? rawPolicies) async {
    final localBranchId = await _db
        .customSelect('SELECT branch_id FROM business_contexts WHERE id=1')
        .map((row) => row.read<String>('branch_id'))
        .getSingle();
    var normalized = <String, Object?>{
      'mode': 'all_company_products',
      'categoryGlobalIds': const <String>[],
      'productGlobalIds': const <String>[],
      'excludedProductGlobalIds': const <String>[],
    };
    if (rawPolicies is Map && rawPolicies[localBranchId] is Map) {
      final raw = Map<String, Object?>.from(rawPolicies[localBranchId] as Map);
      List<String> uuidList(String key) {
        final value = raw[key];
        if (value is! List || value.length > 100000) {
          throw const OfflineSyncException(
            'invalid_branch_assortment_policy',
            'The branch assortment policy is invalid.',
          );
        }
        final values = value.map((item) => item.toString()).toList();
        if (values.any((item) => !Uuid.isValidUUID(fromString: item))) {
          throw const OfflineSyncException(
            'invalid_branch_assortment_policy',
            'The branch assortment policy contains an invalid identity.',
          );
        }
        return values..sort();
      }

      final mode = raw['mode']?.toString();
      if (mode != 'all_company_products' && mode != 'managed_assortment') {
        throw const OfflineSyncException(
          'invalid_branch_assortment_policy',
          'The branch assortment mode is invalid.',
        );
      }
      normalized = {
        'mode': mode,
        'categoryGlobalIds': uuidList('categoryGlobalIds'),
        'productGlobalIds': uuidList('productGlobalIds'),
        'excludedProductGlobalIds': uuidList('excludedProductGlobalIds'),
      };
    }
    await _db.customStatement(
      '''INSERT INTO app_settings(key,value,description,updated_at)
      VALUES('lan.branch_catalogue.local_policy.v1',?,
      'Authoritative branch assortment from coordinator',CURRENT_TIMESTAMP)
      ON CONFLICT(key) DO UPDATE SET value=excluded.value,
      description=excluded.description,updated_at=CURRENT_TIMESTAMP''',
      [jsonEncode(normalized)],
    );
  }

  Future<bool> _isProductListed({
    required String productGlobalId,
    required String? categoryGlobalId,
    required bool sourceActive,
  }) async {
    if (!sourceActive) return false;
    final row = await _db
        .customSelect(
          "SELECT value FROM app_settings WHERE key='lan.branch_catalogue.local_policy.v1'",
        )
        .getSingleOrNull();
    if (row == null) return true;
    final raw = jsonDecode(row.read<String>('value'));
    if (raw is! Map || raw['mode'] != 'managed_assortment') return true;
    final excluded = (raw['excludedProductGlobalIds'] as List? ?? const [])
        .map((value) => value.toString())
        .toSet();
    if (excluded.contains(productGlobalId)) return false;
    final products = (raw['productGlobalIds'] as List? ?? const [])
        .map((value) => value.toString())
        .toSet();
    final categories = (raw['categoryGlobalIds'] as List? ?? const [])
        .map((value) => value.toString())
        .toSet();
    return products.contains(productGlobalId) ||
        categoryGlobalId != null && categories.contains(categoryGlobalId);
  }

  Future<List<Map<String, Object?>>> _supplierPayload() async {
    final rows = await _db.customSelect('''
      SELECT s.*,c.code AS currency_code FROM suppliers s
      JOIN currencies c ON c.id=s.currency_id ORDER BY s.id
    ''').get();
    final result = <Map<String, Object?>>[];
    for (final row in rows) {
      final id = row.read<int>('id');
      final identity = await _identities.getOrCreateLocal(
        entityType: 'supplier',
        localId: id,
      );
      result.add({
        'globalId': identity.globalId,
        'originDatabaseId': identity.originDatabaseId,
        'name': row.read<String>('name'),
        'productCode': row.readNullable<String>('product_code'),
        'email': row.readNullable<String>('email'),
        'phone': row.readNullable<String>('phone'),
        'address': row.readNullable<String>('address'),
        'defaultSupplyMode': row.read<String>('default_supply_mode'),
        'currencyCode': row.read<String>('currency_code'),
        'isActive': row.read<int>('is_active') == 1,
      });
    }
    return result;
  }

  /// Shares only the customer's company-wide identity and contact metadata.
  /// Financial balances, loyalty points and activity counters are branch-owned
  /// movements and must never be copied as opening values into another branch.
  Future<List<Map<String, Object?>>> _customerPayload() async {
    final rows = await _db.customSelect('''
      SELECT c.*,currency.code AS currency_code FROM customers c
      JOIN currencies currency ON currency.id=c.currency_id ORDER BY c.id
    ''').get();
    final result = <Map<String, Object?>>[];
    for (final row in rows) {
      final identity = await _identities.getOrCreateLocal(
        entityType: 'customer',
        localId: row.read<int>('id'),
      );
      result.add({
        'globalId': identity.globalId,
        'originDatabaseId': identity.originDatabaseId,
        'name': row.read<String>('name'),
        'email': row.readNullable<String>('email'),
        'phone': row.readNullable<String>('phone'),
        'address': row.readNullable<String>('address'),
        'currencyCode': row.read<String>('currency_code'),
        'segment': row.read<String>('segment'),
        'loyaltyEnabled': row.read<int>('loyalty_enabled') == 1,
        'isActive': row.read<int>('is_active') == 1,
      });
    }
    return result;
  }

  Future<List<Map<String, Object?>>> _categoryPayload(
    String sourceDatabaseId,
  ) async {
    final rows = await _db
        .customSelect('SELECT * FROM product_categories ORDER BY id')
        .get();
    for (final row in rows) {
      await _dimensionIdentity(
        type: 'category',
        localId: row.read<int>('id'),
        sourceDatabaseId: sourceDatabaseId,
      );
    }
    final byId = {for (final row in rows) row.read<int>('id'): row};
    final emitted = <int>{};
    final ordered = <QueryRow>[];
    void visit(int id, Set<int> stack) {
      if (emitted.contains(id)) return;
      if (!stack.add(id)) {
        throw const OfflineSyncException(
          'catalogue_category_cycle',
          'The product category hierarchy contains a cycle.',
        );
      }
      final row = byId[id]!;
      final parent = row.readNullable<int>('parent_id');
      if (parent != null && byId.containsKey(parent)) visit(parent, stack);
      stack.remove(id);
      emitted.add(id);
      ordered.add(row);
    }

    for (final id in byId.keys) {
      visit(id, <int>{});
    }
    final result = <Map<String, Object?>>[];
    for (final row in ordered) {
      final id = row.read<int>('id');
      final identity = await _findDimension('category', id);
      final parentId = row.readNullable<int>('parent_id');
      result.add({
        'globalId': identity.globalId,
        'originDatabaseId': identity.originDatabaseId,
        'name': row.read<String>('name'),
        'description': row.readNullable<String>('description'),
        if (parentId != null)
          'parentGlobalId': (await _findDimension(
            'category',
            parentId,
          )).globalId,
        'isActive': row.read<int>('is_active') == 1,
      });
    }
    return result;
  }

  Future<List<Map<String, Object?>>> _dimensionPayload(
    String type,
    String table,
  ) async {
    final sourceDatabaseId = await _localDatabaseId();
    final rows = await _db
        .customSelect('SELECT * FROM $table ORDER BY id')
        .get();
    final result = <Map<String, Object?>>[];
    for (final row in rows) {
      final identity = await _dimensionIdentity(
        type: type,
        localId: row.read<int>('id'),
        sourceDatabaseId: sourceDatabaseId,
      );
      result.add({
        'globalId': identity.globalId,
        'originDatabaseId': identity.originDatabaseId,
        'name': row.read<String>('name'),
        if (type == 'color') 'hexCode': row.readNullable<String>('hex_code'),
        if (type == 'size')
          'description': row.readNullable<String>('description'),
        if (type == 'size') 'sortOrder': row.read<int>('sort_order'),
        'isActive': row.read<int>('is_active') == 1,
      });
    }
    return result;
  }

  Future<List<Map<String, Object?>>> _productPayload() async {
    final rows = await _db.customSelect('''
      SELECT p.*,c.code AS currency_code FROM products p
      LEFT JOIN currencies c ON c.id=p.currency_id ORDER BY p.id
    ''').get();
    final result = <Map<String, Object?>>[];
    for (final row in rows) {
      final id = row.read<int>('id');
      final identity = await _identities.getOrCreateLocal(
        entityType: 'product',
        localId: id,
      );
      final categoryId = row.readNullable<int>('category_id');
      final supplierId = row.readNullable<int>('supplier_id');
      result.add({
        'globalId': identity.globalId,
        'originDatabaseId': identity.originDatabaseId,
        'sku': row.readNullable<String>('sku'),
        'barcode': row.readNullable<String>('barcode'),
        'name': row.read<String>('name'),
        'nameAr': row.readNullable<String>('name_ar'),
        'nameFr': row.readNullable<String>('name_fr'),
        'description': row.readNullable<String>('description'),
        if (categoryId != null)
          'categoryGlobalId': (await _findDimension(
            'category',
            categoryId,
          )).globalId,
        if (supplierId != null)
          'supplierGlobalId': (await _identities.getOrCreateLocal(
            entityType: 'supplier',
            localId: supplierId,
          )).globalId,
        'referenceCostMinor': row.read<int>('cost_cents'),
        'priceMinor': row.read<int>('price_cents'),
        'wholesalePriceMinor': row.readNullable<int>('wholesale_price_cents'),
        'currencyCode': row.readNullable<String>('currency_code'),
        'trackInventory': row.read<int>('track_inventory') == 1,
        'measurementType': row.read<String>('measurement_type'),
        'minimumQuantityScaled': row.read<int>('min_quantity'),
        'hasVariants': row.read<int>('has_variants') == 1,
        'isTaxable': row.read<int>('is_taxable') == 1,
        'purchaseTaxRateBps': row.read<int>('purchase_tax_rate_bps'),
        'salesTaxRateBps': row.read<int>('sales_tax_rate_bps'),
        'costingMethod': row.read<String>('costing_method'),
        'inventoryTrackingType': row.read<String>('inventory_tracking_type'),
        'medicineProfile': await _medicineProfilePayload(id),
        'isActive': row.read<int>('is_active') == 1,
      });
    }
    return result;
  }

  Future<Object?> _medicineProfilePayload(int productId) async {
    final profile = await _db
        .customSelect(
          'SELECT * FROM medicine_profiles WHERE product_id=?',
          variables: [Variable.withInt(productId)],
        )
        .getSingleOrNull();
    if (profile == null) return null;
    final ingredientRows = await _db
        .customSelect(
          '''
      SELECT mai.*,ai.canonical_name,ai.normalized_name,ai.name_ar,ai.name_fr,
      ai.description,ai.is_active
      FROM medicine_active_ingredients mai
      JOIN active_ingredients ai ON ai.id=mai.ingredient_id
      WHERE mai.product_id=? ORDER BY mai.sort_order,ai.id
    ''',
          variables: [Variable.withInt(productId)],
        )
        .get();
    final ingredients = <Map<String, Object?>>[];
    for (final row in ingredientRows) {
      final ingredientId = row.read<int>('ingredient_id');
      final aliases = await _db
          .customSelect(
            '''
        SELECT alias,normalized_alias,language_code
        FROM active_ingredient_aliases WHERE ingredient_id=? ORDER BY id
      ''',
            variables: [Variable.withInt(ingredientId)],
          )
          .get();
      ingredients.add({
        'canonicalName': row.read<String>('canonical_name'),
        'normalizedName': row.read<String>('normalized_name'),
        'nameAr': row.readNullable<String>('name_ar'),
        'nameFr': row.readNullable<String>('name_fr'),
        'description': row.readNullable<String>('description'),
        'isActive': row.read<int>('is_active') == 1,
        'strengthValueMicros': row.read<int>(
          'normalized_strength_value_micros',
        ),
        'strengthUnit': row.read<String>('normalized_strength_unit'),
        'basisValueMicros': row.readNullable<int>(
          'normalized_basis_value_micros',
        ),
        'basisUnit': row.readNullable<String>('normalized_basis_unit'),
        'sortOrder': row.read<int>('sort_order'),
        'aliases': [
          for (final alias in aliases)
            {
              'alias': alias.read<String>('alias'),
              'normalizedAlias': alias.read<String>('normalized_alias'),
              'languageCode': alias.readNullable<String>('language_code'),
            },
        ],
      });
    }
    return {
      'dosageForm': profile.read<String>('dosage_form'),
      'administrationRoute': profile.readNullable<String>(
        'administration_route',
      ),
      'substitutionEligible': profile.read<int>('substitution_eligible') == 1,
      'notes': profile.readNullable<String>('notes'),
      'ingredients': ingredients,
    };
  }

  Future<List<Map<String, Object?>>> _variantPayload() async {
    final rows = await _db
        .customSelect('SELECT * FROM product_variants ORDER BY id')
        .get();
    final result = <Map<String, Object?>>[];
    for (final row in rows) {
      final id = row.read<int>('id');
      final identity = await _identities.getOrCreateLocal(
        entityType: 'product_variant',
        localId: id,
      );
      final product = await _identities.getOrCreateLocal(
        entityType: 'product',
        localId: row.read<int>('product_id'),
      );
      final colorId = row.readNullable<int>('color_id');
      final sizeId = row.readNullable<int>('size_id');
      result.add({
        'globalId': identity.globalId,
        'originDatabaseId': identity.originDatabaseId,
        'productGlobalId': product.globalId,
        'sku': row.readNullable<String>('sku'),
        'barcode': row.readNullable<String>('barcode'),
        if (colorId != null)
          'colorGlobalId': (await _findDimension('color', colorId)).globalId,
        if (sizeId != null)
          'sizeGlobalId': (await _findDimension('size', sizeId)).globalId,
        'referenceCostMinor': row.read<int>('cost_cents'),
        'priceMinor': row.read<int>('price_cents'),
        'wholesalePriceMinor': row.readNullable<int>('wholesale_price_cents'),
        'priceAdjustmentMinor': row.read<int>('price_adjustment_cents'),
        'isActive': row.read<int>('is_active') == 1,
      });
    }
    return result;
  }

  Future<List<Map<String, Object?>>> _promotionPayload() async {
    final rows = await _db.customSelect('''
      SELECT p.*,c.code AS currency_code FROM promotions p
      LEFT JOIN currencies c ON c.id=p.currency_id ORDER BY p.id
    ''').get();
    final result = <Map<String, Object?>>[];
    for (final row in rows) {
      final id = row.read<int>('id');
      final conditions = await _db
          .customSelect(
            'SELECT * FROM promotion_conditions WHERE promotion_id=? ORDER BY id',
            variables: [Variable.withInt(id)],
          )
          .get();
      final scopes = await _db
          .customSelect(
            'SELECT * FROM promotion_scopes WHERE promotion_id=? ORDER BY sort_order,id',
            variables: [Variable.withInt(id)],
          )
          .get();
      final rewards = await _db
          .customSelect(
            'SELECT * FROM promotion_rewards WHERE promotion_id=? ORDER BY id',
            variables: [Variable.withInt(id)],
          )
          .get();
      final schedules = await _db
          .customSelect(
            'SELECT * FROM promotion_schedules WHERE promotion_id=? ORDER BY id',
            variables: [Variable.withInt(id)],
          )
          .get();
      final scopePayload = <Map<String, Object?>>[];
      for (final scope in scopes) {
        scopePayload.add({
          'role': scope.read<String>('scope_role'),
          'targetType': scope.read<String>('target_type'),
          'productGlobalId': await _optionalEntityGlobalId(
            'product',
            scope.readNullable<int>('product_id'),
          ),
          'variantGlobalId': await _optionalEntityGlobalId(
            'product_variant',
            scope.readNullable<int>('variant_id'),
          ),
          'categoryGlobalId': await _optionalDimensionGlobalId(
            'category',
            scope.readNullable<int>('category_id'),
          ),
          'isExcluded': scope.read<int>('is_excluded') == 1,
          'lineGroup': scope.read<String>('line_group'),
          'requiredQuantity': scope.readNullable<int>('required_quantity'),
          'quantityScale': scope.read<int>('quantity_scale'),
          'sortOrder': scope.read<int>('sort_order'),
        });
      }
      final rewardPayload = <Map<String, Object?>>[];
      for (final reward in rewards) {
        rewardPayload.add({
          'rewardType': reward.read<String>('reward_type'),
          'applyTo': reward.read<String>('apply_to'),
          'percentBps': reward.readNullable<int>('percent_bps'),
          'amountMinor': reward.readNullable<int>('amount_cents'),
          'fixedPriceMinor': reward.readNullable<int>('fixed_price_cents'),
          'rewardQuantity': reward.readNullable<int>('reward_quantity'),
          'quantityScale': reward.read<int>('quantity_scale'),
          'maxDiscountMinor': reward.readNullable<int>('max_discount_cents'),
          'productGlobalId': await _optionalEntityGlobalId(
            'product',
            reward.readNullable<int>('product_id'),
          ),
          'variantGlobalId': await _optionalEntityGlobalId(
            'product_variant',
            reward.readNullable<int>('variant_id'),
          ),
          'categoryGlobalId': await _optionalDimensionGlobalId(
            'category',
            reward.readNullable<int>('category_id'),
          ),
          'cheapestFirst': reward.read<int>('cheapest_first') == 1,
        });
      }
      result.add({
        'code': row.read<String>('code'),
        'version': row.read<int>('version'),
        'name': row.read<String>('name'),
        'nameAr': row.readNullable<String>('name_ar'),
        'nameFr': row.readNullable<String>('name_fr'),
        'description': row.readNullable<String>('description'),
        'promotionType': row.read<String>('promotion_type'),
        'status': row.read<String>('status'),
        'applicationMode': row.read<String>('application_mode'),
        'concurrencyMode': row.read<String>('concurrency_mode'),
        'priority': row.read<int>('priority'),
        'currencyCode': row.readNullable<String>('currency_code'),
        'priceMode': row.read<String>('price_mode'),
        'couponCode': row.readNullable<String>('coupon_code'),
        'startsAt': row
            .readNullable<DateTime>('starts_at')
            ?.toUtc()
            .toIso8601String(),
        'endsAt': row
            .readNullable<DateTime>('ends_at')
            ?.toUtc()
            .toIso8601String(),
        'maxApplicationsPerTransaction': row.readNullable<int>(
          'max_applications_per_transaction',
        ),
        'maxApplicationsPerCustomer': row.readNullable<int>(
          'max_applications_per_customer',
        ),
        'allowManualDiscountCombination':
            row.read<int>('allow_manual_discount_combination') == 1,
        'allowBelowCost': row.read<int>('allow_below_cost') == 1,
        'conditions': [
          for (final condition in conditions)
            {
              'conditionType': condition.read<String>('condition_type'),
              'conditionGroup': condition.read<String>('condition_group'),
              'minimumQuantity': condition.readNullable<int>(
                'minimum_quantity',
              ),
              'quantityScale': condition.read<int>('quantity_scale'),
              'measurementType': condition.readNullable<String>(
                'measurement_type',
              ),
              'minimumSpendMinor': condition.readNullable<int>(
                'minimum_spend_cents',
              ),
              'paymentMethod': condition.readNullable<String>('payment_method'),
              'couponCode': condition.readNullable<String>('coupon_code'),
              'metadataJson': condition.readNullable<String>('metadata_json'),
            },
        ],
        'scopes': scopePayload,
        'rewards': rewardPayload,
        'schedules': [
          for (final schedule in schedules)
            {
              'weekday': schedule.readNullable<int>('weekday'),
              'startMinute': schedule.read<int>('start_minute'),
              'endMinute': schedule.read<int>('end_minute'),
            },
        ],
      });
    }
    return result;
  }

  Future<String?> _optionalEntityGlobalId(String type, int? localId) async {
    if (localId == null) return null;
    return (await _identities.getOrCreateLocal(
      entityType: type,
      localId: localId,
    )).globalId;
  }

  Future<String?> _optionalDimensionGlobalId(String type, int? localId) async {
    if (localId == null) return null;
    return (await _findDimension(type, localId)).globalId;
  }

  Future<void> _applyEntity(
    String type,
    Map<String, Object?> entity,
    SyncEventEnvelope event,
  ) async {
    switch (type) {
      case 'supplier':
        await _applySupplier(entity, event);
      case 'customer':
        await _applyCustomer(entity, event);
      case 'category':
      case 'color':
      case 'size':
        await _applyDimension(type, entity, event);
      case 'product':
        await _applyProduct(entity, event);
      case 'variant':
        await _applyVariant(entity, event);
      case 'promotion':
        await _applyPromotion(entity);
    }
  }

  Future<void> _applySupplier(
    Map<String, Object?> entity,
    SyncEventEnvelope event,
  ) async {
    final globalId = _uuidField(entity, 'globalId');
    final existing = await _identities.findByGlobal(
      entityType: 'supplier',
      globalId: globalId,
    );
    final currencyId = await _currencyId(_text(entity, 'currencyCode', max: 3));
    final name = _text(entity, 'name', max: 200);
    final productCode = _optionalText(entity, 'productCode', max: 32);
    await _assertNoCollision('suppliers', {
      'product_code': productCode,
    }, excludeId: existing?.localId);
    final values = [
      name,
      productCode,
      _optionalText(entity, 'email', max: 254),
      _optionalText(entity, 'phone', max: 80),
      _optionalText(entity, 'address', max: 500),
      _enum(entity, 'defaultSupplyMode', {'standard', 'consignment', 'mixed'}),
      currencyId,
      _bool(entity, 'isActive') ? 1 : 0,
    ];
    if (existing != null) {
      final local = await _db
          .customSelect(
            'SELECT currency_id,product_code FROM suppliers WHERE id=?',
            variables: [Variable.withInt(existing.localId)],
          )
          .getSingle();
      if (local.read<int>('currency_id') != currencyId) {
        throw const OfflineSyncException(
          'catalogue_party_currency_conflict',
          'A supplier currency cannot change after it has local financial history.',
        );
      }
      final localProductCode = local.readNullable<String>('product_code');
      // A supplier code is assigned once and then immutable. A replica may
      // have received the supplier before the coordinator assigned that first
      // code, so null -> code is the one valid transition to replay.
      if (localProductCode != productCode &&
          !(localProductCode == null && productCode != null)) {
        throw const OfflineSyncException(
          'catalogue_supplier_code_conflict',
          'A supplier identity code cannot change through catalogue synchronization.',
        );
      }
      await _db.customStatement(
        '''UPDATE suppliers SET name=?,product_code=?,email=?,phone=?,address=?,
        default_supply_mode=?,is_active=?,updated_at=CURRENT_TIMESTAMP
        WHERE id=?''',
        [values[0], ...values.skip(1).take(5), values.last, existing.localId],
      );
      return;
    }
    await _db.customStatement(
      '''INSERT INTO suppliers(name,product_code,email,phone,address,
        default_supply_mode,balance_cents,opening_balance_cents,currency_id,is_active)
        VALUES(?,?,?,?,?,?,0,0,?,?)''',
      values,
    );
    final localId = await _db
        .customSelect('SELECT last_insert_rowid() AS id')
        .map((row) => row.read<int>('id'))
        .getSingle();
    await _identities.bindRemote(
      entityType: 'supplier',
      localId: localId,
      globalId: globalId,
      originDatabaseId: event.sourceDatabaseId,
    );
  }

  Future<void> _applyCustomer(
    Map<String, Object?> entity,
    SyncEventEnvelope event,
  ) async {
    final globalId = _uuidField(entity, 'globalId');
    final existing = await _identities.findByGlobal(
      entityType: 'customer',
      globalId: globalId,
    );
    final currencyId = await _currencyId(_text(entity, 'currencyCode', max: 3));
    final values = [
      _text(entity, 'name', max: 300),
      _optionalText(entity, 'email', max: 254),
      _optionalText(entity, 'phone', max: 80),
      _optionalText(entity, 'address', max: 500),
      currencyId,
      _enum(entity, 'segment', {'retail', 'wholesale', 'premium'}),
      _bool(entity, 'loyaltyEnabled') ? 1 : 0,
      _bool(entity, 'isActive') ? 1 : 0,
    ];
    if (existing != null) {
      final localCurrencyId = await _db
          .customSelect(
            'SELECT currency_id FROM customers WHERE id=?',
            variables: [Variable.withInt(existing.localId)],
          )
          .map((row) => row.read<int>('currency_id'))
          .getSingle();
      if (localCurrencyId != currencyId) {
        throw const OfflineSyncException(
          'catalogue_party_currency_conflict',
          'A customer currency cannot change after it has local financial history.',
        );
      }
      await _db.customStatement(
        '''UPDATE customers SET name=?,email=?,phone=?,address=?,
        segment=?,loyalty_enabled=?,is_active=?,updated_at=CURRENT_TIMESTAMP
        WHERE id=?''',
        [...values.take(4), ...values.skip(5), existing.localId],
      );
      return;
    }
    await _db.customStatement('''INSERT INTO customers(
        name,email,phone,address,balance_cents,opening_balance_cents,currency_id,
        segment,loyalty_enabled,loyalty_points_balance,total_spent_cents,
        total_transactions,last_transaction_at,is_active)
        VALUES(?,?,?,?,0,0,?,?,?,0,0,0,NULL,?)''', values);
    final localId = await _db
        .customSelect('SELECT last_insert_rowid() AS id')
        .map((row) => row.read<int>('id'))
        .getSingle();
    await _identities.bindRemote(
      entityType: 'customer',
      localId: localId,
      globalId: globalId,
      originDatabaseId: event.sourceDatabaseId,
    );
  }

  Future<void> _applyDimension(
    String type,
    Map<String, Object?> entity,
    SyncEventEnvelope event,
  ) async {
    final globalId = _uuidField(entity, 'globalId');
    final existing = await _findDimensionByGlobal(type, globalId);
    final name = _text(entity, 'name', max: 200);
    if (existing != null) {
      if (type == 'category') {
        final parentGlobal = _optionalUuid(entity, 'parentGlobalId');
        final parentId = parentGlobal == null
            ? null
            : (await _findDimensionByGlobal('category', parentGlobal))?.localId;
        if (parentGlobal != null && parentId == null) {
          throw const OfflineSyncException(
            'catalogue_parent_missing',
            'A parent category page must arrive before its child.',
          );
        }
        await _db.customStatement(
          'UPDATE product_categories SET name=?,description=?,parent_id=?,is_active=? WHERE id=?',
          [
            name,
            _optionalText(entity, 'description', max: 1000),
            parentId,
            _bool(entity, 'isActive') ? 1 : 0,
            existing.localId,
          ],
        );
      } else if (type == 'color') {
        await _db.customStatement(
          'UPDATE product_colors SET name=?,hex_code=?,is_active=? WHERE id=?',
          [
            name,
            _optionalText(entity, 'hexCode', max: 20),
            _bool(entity, 'isActive') ? 1 : 0,
            existing.localId,
          ],
        );
      } else {
        await _db.customStatement(
          'UPDATE sizes SET name=?,description=?,sort_order=?,is_active=? WHERE id=?',
          [
            name,
            _optionalText(entity, 'description', max: 1000),
            _int(entity, 'sortOrder', min: -100000, max: 100000),
            _bool(entity, 'isActive') ? 1 : 0,
            existing.localId,
          ],
        );
      }
      return;
    }
    late int localId;
    if (type == 'category') {
      final parentGlobal = _optionalUuid(entity, 'parentGlobalId');
      final parentId = parentGlobal == null
          ? null
          : (await _findDimensionByGlobal('category', parentGlobal))?.localId;
      if (parentGlobal != null && parentId == null) {
        throw const OfflineSyncException(
          'catalogue_parent_missing',
          'A parent category page must arrive before its child.',
        );
      }
      await _db.customStatement(
        'INSERT INTO product_categories(name,description,parent_id,is_active) '
        'VALUES(?,?,?,?)',
        [
          name,
          _optionalText(entity, 'description', max: 1000),
          parentId,
          _bool(entity, 'isActive') ? 1 : 0,
        ],
      );
    } else if (type == 'color') {
      await _db.customStatement(
        'INSERT INTO product_colors(name,hex_code,is_active) VALUES(?,?,?)',
        [
          name,
          _optionalText(entity, 'hexCode', max: 20),
          _bool(entity, 'isActive') ? 1 : 0,
        ],
      );
    } else {
      await _db.customStatement(
        'INSERT INTO sizes(name,description,sort_order,is_active) VALUES(?,?,?,?)',
        [
          name,
          _optionalText(entity, 'description', max: 1000),
          _int(entity, 'sortOrder', min: -100000, max: 100000),
          _bool(entity, 'isActive') ? 1 : 0,
        ],
      );
    }
    localId = await _db
        .customSelect('SELECT last_insert_rowid() AS id')
        .map((row) => row.read<int>('id'))
        .getSingle();
    await _db.customStatement(
      'INSERT INTO sync_catalogue_dimension_identities('
      'entity_type,local_id,global_id,origin_database_id) VALUES(?,?,?,?)',
      [type, localId, globalId, event.sourceDatabaseId],
    );
  }

  Future<void> _applyProduct(
    Map<String, Object?> entity,
    SyncEventEnvelope event,
  ) async {
    final globalId = _uuidField(entity, 'globalId');
    final existing = await _identities.findByGlobal(
      entityType: 'product',
      globalId: globalId,
    );
    final sku = _optionalText(entity, 'sku', max: 100);
    final barcode = _optionalText(entity, 'barcode', max: 200);
    await _assertNoCollision('products', {
      'sku': sku,
      'barcode': barcode,
    }, excludeId: existing?.localId);
    final categoryGlobal = _optionalUuid(entity, 'categoryGlobalId');
    final supplierGlobal = _optionalUuid(entity, 'supplierGlobalId');
    final categoryId = categoryGlobal == null
        ? null
        : (await _findDimensionByGlobal('category', categoryGlobal))?.localId;
    final supplierId = supplierGlobal == null
        ? null
        : (await _identities.findByGlobal(
            entityType: 'supplier',
            globalId: supplierGlobal,
          ))?.localId;
    if (categoryGlobal != null && categoryId == null ||
        supplierGlobal != null && supplierId == null) {
      throw const OfflineSyncException(
        'catalogue_dependency_missing',
        'A product catalogue dependency has not arrived yet.',
      );
    }
    final currencyCode = _optionalText(entity, 'currencyCode', max: 3);
    final currencyId = currencyCode == null
        ? null
        : await _currencyId(currencyCode);
    final measurement = _enum(entity, 'measurementType', {
      'piece',
      'weight',
      'length',
      'volume',
    });
    final trackInventory = _bool(entity, 'trackInventory') ? 1 : 0;
    final hasVariants = _bool(entity, 'hasVariants') ? 1 : 0;
    final costingMethod = _enum(entity, 'costingMethod', {'wac', 'fifo'});
    final inventoryTrackingType = _enum(entity, 'inventoryTrackingType', {
      'standard',
      'batch',
      'batch_expiry',
    });
    final isListed = await _isProductListed(
      productGlobalId: globalId,
      categoryGlobalId: categoryGlobal,
      sourceActive: _bool(entity, 'isActive'),
    );
    if (existing != null) {
      final local = await _db
          .customSelect(
            '''SELECT currency_id,track_inventory,measurement_type,has_variants,
            costing_method,inventory_tracking_type FROM products WHERE id=?''',
            variables: [Variable.withInt(existing.localId)],
          )
          .getSingle();
      if (local.readNullable<int>('currency_id') != currencyId ||
          local.read<int>('track_inventory') != trackInventory ||
          local.read<String>('measurement_type') != measurement ||
          local.read<int>('has_variants') != hasVariants ||
          local.read<String>('costing_method') != costingMethod ||
          local.read<String>('inventory_tracking_type') !=
              inventoryTrackingType) {
        throw const OfflineSyncException(
          'catalogue_product_structure_conflict',
          'A product inventory structure cannot change through catalogue synchronization.',
        );
      }
      await _db.customStatement(
        '''UPDATE products SET sku=?,barcode=?,name=?,name_ar=?,name_fr=?,
        description=?,category_id=?,supplier_id=?,price_cents=?,
        wholesale_price_cents=?,min_quantity=?,is_taxable=?,
        purchase_tax_rate_bps=?,sales_tax_rate_bps=?,is_active=?,
        updated_at=CURRENT_TIMESTAMP WHERE id=?''',
        [
          sku,
          barcode,
          _text(entity, 'name', max: 300),
          _optionalText(entity, 'nameAr', max: 300),
          _optionalText(entity, 'nameFr', max: 300),
          _optionalText(entity, 'description', max: 2000),
          categoryId,
          supplierId,
          _int(entity, 'priceMinor', min: 0),
          _optionalInt(entity, 'wholesalePriceMinor', min: 0),
          _int(entity, 'minimumQuantityScaled', min: 0),
          _bool(entity, 'isTaxable') ? 1 : 0,
          _int(entity, 'purchaseTaxRateBps', min: 0, max: 10000),
          _int(entity, 'salesTaxRateBps', min: 0, max: 10000),
          isListed ? 1 : 0,
          existing.localId,
        ],
      );
      if (entity.containsKey('medicineProfile')) {
        await _applyMedicineProfile(
          existing.localId,
          entity['medicineProfile'],
        );
      }
      return;
    }
    await _db.customStatement(
      '''INSERT INTO products(
        sku,barcode,name,name_ar,name_fr,description,category_id,supplier_id,
        cost_cents,price_cents,wholesale_price_cents,currency_id,
        track_inventory,measurement_type,stock_quantity,min_quantity,
        has_variants,is_taxable,purchase_tax_rate_bps,sales_tax_rate_bps,
        image_path,is_active,costing_method,inventory_tracking_type)
        VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,0,?,?,?,?,?,NULL,?,?,?)''',
      [
        sku,
        barcode,
        _text(entity, 'name', max: 300),
        _optionalText(entity, 'nameAr', max: 300),
        _optionalText(entity, 'nameFr', max: 300),
        _optionalText(entity, 'description', max: 2000),
        categoryId,
        supplierId,
        _int(entity, 'referenceCostMinor', min: 0),
        _int(entity, 'priceMinor', min: 0),
        _optionalInt(entity, 'wholesalePriceMinor', min: 0),
        currencyId,
        trackInventory,
        measurement,
        _int(entity, 'minimumQuantityScaled', min: 0),
        hasVariants,
        _bool(entity, 'isTaxable') ? 1 : 0,
        _int(entity, 'purchaseTaxRateBps', min: 0, max: 10000),
        _int(entity, 'salesTaxRateBps', min: 0, max: 10000),
        isListed ? 1 : 0,
        costingMethod,
        inventoryTrackingType,
      ],
    );
    final localId = await _db
        .customSelect('SELECT last_insert_rowid() AS id')
        .map((row) => row.read<int>('id'))
        .getSingle();
    await _identities.bindRemote(
      entityType: 'product',
      localId: localId,
      globalId: globalId,
      originDatabaseId: event.sourceDatabaseId,
    );
    if (entity.containsKey('medicineProfile')) {
      await _applyMedicineProfile(localId, entity['medicineProfile']);
    }
  }

  Future<void> _applyVariant(
    Map<String, Object?> entity,
    SyncEventEnvelope event,
  ) async {
    final globalId = _uuidField(entity, 'globalId');
    final existing = await _identities.findByGlobal(
      entityType: 'product_variant',
      globalId: globalId,
    );
    final product = await _identities.findByGlobal(
      entityType: 'product',
      globalId: _uuidField(entity, 'productGlobalId'),
    );
    if (product == null) {
      throw const OfflineSyncException(
        'catalogue_product_missing',
        'A variant product has not arrived yet.',
      );
    }
    final sku = _optionalText(entity, 'sku', max: 100);
    final barcode = _optionalText(entity, 'barcode', max: 200);
    await _assertNoCollision('product_variants', {
      'sku': sku,
      'barcode': barcode,
    }, excludeId: existing?.localId);
    final colorGlobal = _optionalUuid(entity, 'colorGlobalId');
    final sizeGlobal = _optionalUuid(entity, 'sizeGlobalId');
    final colorId = colorGlobal == null
        ? null
        : (await _findDimensionByGlobal('color', colorGlobal))?.localId;
    final sizeId = sizeGlobal == null
        ? null
        : (await _findDimensionByGlobal('size', sizeGlobal))?.localId;
    if (colorGlobal != null && colorId == null ||
        sizeGlobal != null && sizeId == null) {
      throw const OfflineSyncException(
        'catalogue_variant_dimension_missing',
        'A variant dimension has not arrived yet.',
      );
    }
    if (existing != null) {
      final local = await _db
          .customSelect(
            'SELECT product_id,color_id,size_id FROM product_variants WHERE id=?',
            variables: [Variable.withInt(existing.localId)],
          )
          .getSingle();
      if (local.read<int>('product_id') != product.localId ||
          local.readNullable<int>('color_id') != colorId ||
          local.readNullable<int>('size_id') != sizeId) {
        throw const OfflineSyncException(
          'catalogue_variant_structure_conflict',
          'A variant product or dimension cannot change through catalogue synchronization.',
        );
      }
      await _db.customStatement(
        '''UPDATE product_variants SET sku=?,barcode=?,price_cents=?,
        wholesale_price_cents=?,price_adjustment_cents=?,is_active=?,
        updated_at=CURRENT_TIMESTAMP WHERE id=?''',
        [
          sku,
          barcode,
          _int(entity, 'priceMinor', min: 0),
          _optionalInt(entity, 'wholesalePriceMinor', min: 0),
          _int(entity, 'priceAdjustmentMinor'),
          _bool(entity, 'isActive') ? 1 : 0,
          existing.localId,
        ],
      );
      return;
    }
    await _db.customStatement(
      '''INSERT INTO product_variants(
        product_id,sku,barcode,color_id,size_id,cost_cents,price_cents,
        wholesale_price_cents,price_adjustment_cents,stock_quantity,is_active)
        VALUES(?,?,?,?,?,?,?,?,?,0,?)''',
      [
        product.localId,
        sku,
        barcode,
        colorId,
        sizeId,
        _int(entity, 'referenceCostMinor', min: 0),
        _int(entity, 'priceMinor', min: 0),
        _optionalInt(entity, 'wholesalePriceMinor', min: 0),
        _int(entity, 'priceAdjustmentMinor'),
        _bool(entity, 'isActive') ? 1 : 0,
      ],
    );
    final localId = await _db
        .customSelect('SELECT last_insert_rowid() AS id')
        .map((row) => row.read<int>('id'))
        .getSingle();
    await _identities.bindRemote(
      entityType: 'product_variant',
      localId: localId,
      globalId: globalId,
      originDatabaseId: event.sourceDatabaseId,
    );
  }

  Future<void> _applyMedicineProfile(int productId, Object? raw) async {
    if (raw == null) {
      await _db.customStatement(
        'DELETE FROM medicine_profiles WHERE product_id=?',
        [productId],
      );
      return;
    }
    if (raw is! Map) {
      throw const OfflineSyncException(
        'invalid_medicine_profile',
        'The medicine profile has an invalid structure.',
      );
    }
    final profile = Map<String, Object?>.from(raw);
    final ingredients = _mapList(profile, 'ingredients', max: 50);
    await _db.customStatement(
      '''
      INSERT INTO medicine_profiles(product_id,dosage_form,
        administration_route,substitution_eligible,notes,updated_at)
      VALUES(?,?,?,?,?,CURRENT_TIMESTAMP)
      ON CONFLICT(product_id) DO UPDATE SET dosage_form=excluded.dosage_form,
        administration_route=excluded.administration_route,
        substitution_eligible=excluded.substitution_eligible,
        notes=excluded.notes,updated_at=CURRENT_TIMESTAMP
    ''',
      [
        productId,
        _text(profile, 'dosageForm', max: 80),
        _optionalText(profile, 'administrationRoute', max: 80),
        _bool(profile, 'substitutionEligible') ? 1 : 0,
        _optionalText(profile, 'notes', max: 2000),
      ],
    );
    await _db.customStatement(
      'DELETE FROM medicine_active_ingredients WHERE product_id=?',
      [productId],
    );
    for (final ingredient in ingredients) {
      final normalizedName = _text(ingredient, 'normalizedName', max: 200);
      await _db.customStatement(
        '''
        INSERT INTO active_ingredients(canonical_name,normalized_name,name_ar,
          name_fr,description,is_active,updated_at)
        VALUES(?,?,?,?,?,?,CURRENT_TIMESTAMP)
        ON CONFLICT(normalized_name) DO UPDATE SET
          canonical_name=excluded.canonical_name,name_ar=excluded.name_ar,
          name_fr=excluded.name_fr,description=excluded.description,
          is_active=excluded.is_active,updated_at=CURRENT_TIMESTAMP
      ''',
        [
          _text(ingredient, 'canonicalName', max: 200),
          normalizedName,
          _optionalText(ingredient, 'nameAr', max: 200),
          _optionalText(ingredient, 'nameFr', max: 200),
          _optionalText(ingredient, 'description', max: 2000),
          _bool(ingredient, 'isActive') ? 1 : 0,
        ],
      );
      final ingredientId = await _db
          .customSelect(
            'SELECT id FROM active_ingredients WHERE normalized_name=?',
            variables: [Variable.withString(normalizedName)],
          )
          .map((row) => row.read<int>('id'))
          .getSingle();
      for (final alias in _mapList(ingredient, 'aliases', max: 100)) {
        await _db.customStatement(
          '''
          INSERT INTO active_ingredient_aliases(
            ingredient_id,alias,normalized_alias,language_code)
          VALUES(?,?,?,?)
          ON CONFLICT(normalized_alias) DO UPDATE SET
            ingredient_id=excluded.ingredient_id,alias=excluded.alias,
            language_code=excluded.language_code
        ''',
          [
            ingredientId,
            _text(alias, 'alias', max: 200),
            _text(alias, 'normalizedAlias', max: 200),
            _optionalText(alias, 'languageCode', max: 10),
          ],
        );
      }
      final basisValue = _optionalInt(ingredient, 'basisValueMicros', min: 1);
      final basisUnit = _optionalText(ingredient, 'basisUnit', max: 24);
      if ((basisValue == null) != (basisUnit == null)) {
        throw const OfflineSyncException(
          'invalid_medicine_strength_basis',
          'A medicine strength basis is incomplete.',
        );
      }
      await _db.customStatement(
        '''
        INSERT INTO medicine_active_ingredients(product_id,ingredient_id,
          normalized_strength_value_micros,normalized_strength_unit,
          normalized_basis_value_micros,normalized_basis_unit,sort_order,
          updated_at) VALUES(?,?,?,?,?,?,?,CURRENT_TIMESTAMP)
      ''',
        [
          productId,
          ingredientId,
          _int(ingredient, 'strengthValueMicros', min: 1),
          _text(ingredient, 'strengthUnit', max: 24),
          basisValue,
          basisUnit,
          _int(ingredient, 'sortOrder', min: 0, max: 10000),
        ],
      );
    }
  }

  Future<void> _applyPromotion(Map<String, Object?> entity) async {
    final conditions = _mapList(entity, 'conditions', max: 100);
    final scopes = _mapList(entity, 'scopes', max: 500);
    final rewards = _mapList(entity, 'rewards', max: 100);
    final schedules = _mapList(entity, 'schedules', max: 50);
    final code = _text(entity, 'code', max: 120).toUpperCase();
    final currencyCode = _optionalText(entity, 'currencyCode', max: 3);
    final currencyId = currencyCode == null
        ? null
        : await _currencyId(currencyCode);
    final startsAt = _optionalIsoDate(entity, 'startsAt');
    final endsAt = _optionalIsoDate(entity, 'endsAt');
    if (startsAt != null && endsAt != null && endsAt.isBefore(startsAt)) {
      throw const OfflineSyncException(
        'invalid_promotion_period',
        'A promotion end date cannot precede its start date.',
      );
    }
    await _db.customStatement(
      '''
      INSERT INTO promotions(code,version,name,name_ar,name_fr,description,
        promotion_type,status,application_mode,concurrency_mode,priority,
        currency_id,price_mode,coupon_code,starts_at,ends_at,
        max_applications_per_transaction,max_applications_per_customer,
        allow_manual_discount_combination,allow_below_cost,created_by,
        updated_by,updated_at)
      VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,NULL,NULL,CURRENT_TIMESTAMP)
      ON CONFLICT(code) DO UPDATE SET version=excluded.version,
        name=excluded.name,name_ar=excluded.name_ar,name_fr=excluded.name_fr,
        description=excluded.description,promotion_type=excluded.promotion_type,
        status=excluded.status,application_mode=excluded.application_mode,
        concurrency_mode=excluded.concurrency_mode,priority=excluded.priority,
        currency_id=excluded.currency_id,price_mode=excluded.price_mode,
        coupon_code=excluded.coupon_code,starts_at=excluded.starts_at,
        ends_at=excluded.ends_at,
        max_applications_per_transaction=excluded.max_applications_per_transaction,
        max_applications_per_customer=excluded.max_applications_per_customer,
        allow_manual_discount_combination=excluded.allow_manual_discount_combination,
        allow_below_cost=excluded.allow_below_cost,updated_at=CURRENT_TIMESTAMP
    ''',
      [
        code,
        _int(entity, 'version', min: 1, max: 1000000),
        _text(entity, 'name', max: 300),
        _optionalText(entity, 'nameAr', max: 300),
        _optionalText(entity, 'nameFr', max: 300),
        _optionalText(entity, 'description', max: 4000),
        _enum(entity, 'promotionType', {
          'simple',
          'quantity',
          'fixed_bundle',
          'buy_x_get_y',
          'threshold',
        }),
        _enum(entity, 'status', {'draft', 'active', 'paused', 'archived'}),
        _enum(entity, 'applicationMode', {'automatic', 'manual', 'coupon'}),
        _enum(entity, 'concurrencyMode', {
          'exclusive',
          'best_price',
          'compound',
        }),
        _int(entity, 'priority', min: -100000, max: 100000),
        currencyId,
        _enum(entity, 'priceMode', {'retail', 'wholesale', 'any'}),
        _optionalText(entity, 'couponCode', max: 120),
        startsAt?.toIso8601String(),
        endsAt?.toIso8601String(),
        _optionalInt(entity, 'maxApplicationsPerTransaction', min: 1),
        _optionalInt(entity, 'maxApplicationsPerCustomer', min: 1),
        _bool(entity, 'allowManualDiscountCombination') ? 1 : 0,
        _bool(entity, 'allowBelowCost') ? 1 : 0,
      ],
    );
    final promotionId = await _db
        .customSelect(
          'SELECT id FROM promotions WHERE code=?',
          variables: [Variable.withString(code)],
        )
        .map((row) => row.read<int>('id'))
        .getSingle();
    await _db.customStatement(
      'DELETE FROM promotion_conditions WHERE promotion_id=?',
      [promotionId],
    );
    await _db.customStatement(
      'DELETE FROM promotion_scopes WHERE promotion_id=?',
      [promotionId],
    );
    await _db.customStatement(
      'DELETE FROM promotion_rewards WHERE promotion_id=?',
      [promotionId],
    );
    await _db.customStatement(
      'DELETE FROM promotion_schedules WHERE promotion_id=?',
      [promotionId],
    );
    for (final condition in conditions) {
      final measurement = _optionalText(condition, 'measurementType', max: 20);
      if (measurement != null &&
          !{'piece', 'weight', 'length', 'volume'}.contains(measurement)) {
        throw const OfflineSyncException(
          'invalid_promotion_measurement',
          'A promotion measurement type is invalid.',
        );
      }
      await _db.customStatement(
        '''
        INSERT INTO promotion_conditions(promotion_id,condition_type,
          condition_group,minimum_quantity,quantity_scale,measurement_type,
          minimum_spend_cents,payment_method,coupon_code,metadata_json)
        VALUES(?,?,?,?,?,?,?,?,?,?)
      ''',
        [
          promotionId,
          _enum(condition, 'conditionType', {
            'minimum_quantity',
            'minimum_spend',
            'payment_method',
            'coupon',
          }),
          _text(condition, 'conditionGroup', max: 100),
          _optionalInt(condition, 'minimumQuantity', min: 1),
          _int(condition, 'quantityScale', min: 1),
          measurement,
          _optionalInt(condition, 'minimumSpendMinor', min: 0),
          _optionalText(condition, 'paymentMethod', max: 80),
          _optionalText(condition, 'couponCode', max: 120),
          _optionalText(condition, 'metadataJson', max: 20000),
        ],
      );
    }
    for (final scope in scopes) {
      final targetType = _enum(scope, 'targetType', {
        'all',
        'product',
        'variant',
        'category',
      });
      final productId = await _localEntityId(
        'product',
        scope,
        'productGlobalId',
      );
      final variantId = await _localEntityId(
        'product_variant',
        scope,
        'variantGlobalId',
      );
      final categoryId = await _localDimensionId(
        'category',
        scope,
        'categoryGlobalId',
      );
      _validatePromotionTarget(targetType, productId, variantId, categoryId);
      await _db.customStatement(
        '''
        INSERT INTO promotion_scopes(promotion_id,scope_role,target_type,
          product_id,variant_id,category_id,is_excluded,line_group,
          required_quantity,quantity_scale,sort_order)
        VALUES(?,?,?,?,?,?,?,?,?,?,?)
      ''',
        [
          promotionId,
          _enum(scope, 'role', {'qualifier', 'reward', 'eligible'}),
          targetType,
          productId,
          variantId,
          categoryId,
          _bool(scope, 'isExcluded') ? 1 : 0,
          _text(scope, 'lineGroup', max: 40),
          _optionalInt(scope, 'requiredQuantity', min: 1),
          _int(scope, 'quantityScale', min: 1),
          _int(scope, 'sortOrder', min: 0, max: 100000),
        ],
      );
    }
    for (final reward in rewards) {
      final productId = await _localEntityId(
        'product',
        reward,
        'productGlobalId',
      );
      final variantId = await _localEntityId(
        'product_variant',
        reward,
        'variantGlobalId',
      );
      final categoryId = await _localDimensionId(
        'category',
        reward,
        'categoryGlobalId',
      );
      if ([productId, variantId, categoryId].whereType<int>().length > 1) {
        throw const OfflineSyncException(
          'invalid_promotion_target',
          'A promotion reward has more than one target.',
        );
      }
      await _db.customStatement(
        '''
        INSERT INTO promotion_rewards(promotion_id,reward_type,apply_to,
          percent_bps,amount_cents,fixed_price_cents,reward_quantity,
          quantity_scale,max_discount_cents,product_id,variant_id,category_id,
          cheapest_first) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)
      ''',
        [
          promotionId,
          _enum(reward, 'rewardType', {
            'percentage_off',
            'amount_off',
            'fixed_bundle_price',
            'free_quantity',
          }),
          _enum(reward, 'applyTo', {
            'qualifying_lines',
            'reward_lines',
            'entire_cart',
            'cheapest_reward_lines',
          }),
          _optionalInt(reward, 'percentBps', min: 0, max: 10000),
          _optionalInt(reward, 'amountMinor', min: 0),
          _optionalInt(reward, 'fixedPriceMinor', min: 0),
          _optionalInt(reward, 'rewardQuantity', min: 1),
          _int(reward, 'quantityScale', min: 1),
          _optionalInt(reward, 'maxDiscountMinor', min: 0),
          productId,
          variantId,
          categoryId,
          _bool(reward, 'cheapestFirst') ? 1 : 0,
        ],
      );
    }
    for (final schedule in schedules) {
      final start = _int(schedule, 'startMinute', min: 0, max: 1439);
      final end = _int(schedule, 'endMinute', min: 0, max: 1439);
      if (end < start) {
        throw const OfflineSyncException(
          'invalid_promotion_schedule',
          'A promotion schedule end precedes its start.',
        );
      }
      await _db.customStatement(
        '''
        INSERT INTO promotion_schedules(
          promotion_id,weekday,start_minute,end_minute) VALUES(?,?,?,?)
      ''',
        [
          promotionId,
          _optionalInt(schedule, 'weekday', min: 1, max: 7),
          start,
          end,
        ],
      );
    }
  }

  Future<int?> _localEntityId(
    String type,
    Map<String, Object?> map,
    String key,
  ) async {
    final globalId = _optionalUuid(map, key);
    if (globalId == null) return null;
    final identity = await _identities.findByGlobal(
      entityType: type,
      globalId: globalId,
    );
    if (identity == null) {
      throw const OfflineSyncException(
        'catalogue_dependency_missing',
        'A promotion product dependency has not arrived yet.',
      );
    }
    return identity.localId;
  }

  Future<int?> _localDimensionId(
    String type,
    Map<String, Object?> map,
    String key,
  ) async {
    final globalId = _optionalUuid(map, key);
    if (globalId == null) return null;
    final identity = await _findDimensionByGlobal(type, globalId);
    if (identity == null) {
      throw const OfflineSyncException(
        'catalogue_dependency_missing',
        'A promotion category dependency has not arrived yet.',
      );
    }
    return identity.localId;
  }

  static void _validatePromotionTarget(
    String targetType,
    int? productId,
    int? variantId,
    int? categoryId,
  ) {
    final count = [productId, variantId, categoryId].whereType<int>().length;
    final valid = targetType == 'all'
        ? count == 0
        : targetType == 'product'
        ? productId != null && count == 1
        : targetType == 'variant'
        ? variantId != null && count == 1
        : categoryId != null && count == 1;
    if (!valid) {
      throw const OfflineSyncException(
        'invalid_promotion_target',
        'A promotion scope target is inconsistent.',
      );
    }
  }

  Future<void> _assertNoCollision(
    String table,
    Map<String, String?> values, {
    int? excludeId,
  }) async {
    for (final entry in values.entries) {
      if (entry.value == null) continue;
      if (await _db
              .customSelect(
                'SELECT 1 AS found FROM $table WHERE ${entry.key}=? '
                '${excludeId == null ? '' : 'AND id<>?'}',
                variables: [
                  Variable.withString(entry.value!),
                  if (excludeId != null) Variable.withInt(excludeId),
                ],
              )
              .getSingleOrNull() !=
          null) {
        throw const OfflineSyncException(
          'catalogue_unique_value_conflict',
          'A local SKU, barcode, or supplier code conflicts with the shared catalogue.',
        );
      }
    }
  }

  Future<int> _currencyId(String code) async {
    final row = await _db
        .customSelect(
          'SELECT id FROM currencies WHERE code=? AND is_active=1',
          variables: [Variable.withString(code.toUpperCase())],
        )
        .getSingleOrNull();
    if (row == null) {
      throw const OfflineSyncException(
        'catalogue_currency_missing',
        'The catalogue currency is unavailable in this branch.',
      );
    }
    return row.read<int>('id');
  }

  Future<_DimensionIdentity> _dimensionIdentity({
    required String type,
    required int localId,
    required String sourceDatabaseId,
  }) async {
    final existing = await _db
        .customSelect(
          'SELECT local_id,global_id,origin_database_id '
          'FROM sync_catalogue_dimension_identities '
          'WHERE entity_type=? AND local_id=?',
          variables: [Variable.withString(type), Variable.withInt(localId)],
        )
        .getSingleOrNull();
    if (existing != null) return _DimensionIdentity.fromRow(existing);
    final globalId = _uuid.v5(
      Namespace.url.value,
      'tapix-catalogue-dimension:$sourceDatabaseId:$type:$localId',
    );
    await _db.customStatement(
      'INSERT INTO sync_catalogue_dimension_identities('
      'entity_type,local_id,global_id,origin_database_id) VALUES(?,?,?,?)',
      [type, localId, globalId, sourceDatabaseId],
    );
    return _DimensionIdentity(
      localId: localId,
      globalId: globalId,
      originDatabaseId: sourceDatabaseId,
    );
  }

  Future<_DimensionIdentity> _findDimension(String type, int localId) async {
    final row = await _db
        .customSelect(
          'SELECT local_id,global_id,origin_database_id '
          'FROM sync_catalogue_dimension_identities '
          'WHERE entity_type=? AND local_id=?',
          variables: [Variable.withString(type), Variable.withInt(localId)],
        )
        .getSingle();
    return _DimensionIdentity.fromRow(row);
  }

  Future<_DimensionIdentity?> _findDimensionByGlobal(
    String type,
    String globalId,
  ) async {
    final row = await _db
        .customSelect(
          'SELECT local_id,global_id,origin_database_id '
          'FROM sync_catalogue_dimension_identities '
          'WHERE entity_type=? AND global_id=?',
          variables: [Variable.withString(type), Variable.withString(globalId)],
        )
        .getSingleOrNull();
    return row == null ? null : _DimensionIdentity.fromRow(row);
  }

  Future<String> _localDatabaseId() async => _db
      .customSelect('SELECT database_id FROM sync_local_state WHERE id=1')
      .map((row) => row.read<String>('database_id'))
      .getSingle();

  static String _uuidField(Map<String, Object?> map, String key) {
    final value = map[key]?.toString() ?? '';
    if (!Uuid.isValidUUID(fromString: value)) {
      throw const OfflineSyncException(
        'invalid_catalogue_identity',
        'A catalogue identity is invalid.',
      );
    }
    return value.toLowerCase();
  }

  static String? _optionalUuid(Map<String, Object?> map, String key) {
    if (map[key] == null) return null;
    return _uuidField(map, key);
  }

  static String _text(
    Map<String, Object?> map,
    String key, {
    required int max,
  }) {
    final value = map[key]?.toString().trim() ?? '';
    if (value.isEmpty || value.length > max) {
      throw const OfflineSyncException(
        'invalid_catalogue_text',
        'A catalogue text value is invalid.',
      );
    }
    return value;
  }

  static String? _optionalText(
    Map<String, Object?> map,
    String key, {
    required int max,
  }) {
    if (map[key] == null) return null;
    final value = map[key].toString().trim();
    if (value.isEmpty || value.length > max) {
      throw const OfflineSyncException(
        'invalid_catalogue_text',
        'A catalogue text value is invalid.',
      );
    }
    return value;
  }

  static bool _bool(Map<String, Object?> map, String key) {
    final value = map[key];
    if (value is! bool) {
      throw const OfflineSyncException(
        'invalid_catalogue_boolean',
        'A catalogue boolean value is invalid.',
      );
    }
    return value;
  }

  static int _int(
    Map<String, Object?> map,
    String key, {
    int min = -9007199254740991,
    int max = 9007199254740991,
  }) {
    final value = map[key];
    if (value is! int || value < min || value > max) {
      throw const OfflineSyncException(
        'invalid_catalogue_number',
        'A catalogue numeric value is invalid.',
      );
    }
    return value;
  }

  static int? _optionalInt(
    Map<String, Object?> map,
    String key, {
    int min = -9007199254740991,
    int max = 9007199254740991,
  }) => map[key] == null ? null : _int(map, key, min: min, max: max);

  static List<Map<String, Object?>> _mapList(
    Map<String, Object?> map,
    String key, {
    required int max,
  }) {
    final value = map[key];
    if (value is! List || value.length > max) {
      throw const OfflineSyncException(
        'invalid_catalogue_list',
        'A catalogue child list is invalid.',
      );
    }
    final result = <Map<String, Object?>>[];
    for (final item in value) {
      if (item is! Map) {
        throw const OfflineSyncException(
          'invalid_catalogue_list',
          'A catalogue child has an invalid structure.',
        );
      }
      result.add(Map<String, Object?>.from(item));
    }
    return result;
  }

  static DateTime? _optionalIsoDate(Map<String, Object?> map, String key) {
    if (map[key] == null) return null;
    final value = DateTime.tryParse(map[key].toString());
    if (value == null) {
      throw const OfflineSyncException(
        'invalid_catalogue_date',
        'A catalogue date is invalid.',
      );
    }
    return value.toUtc();
  }

  static String _enum(
    Map<String, Object?> map,
    String key,
    Set<String> allowed,
  ) {
    final value = map[key]?.toString() ?? '';
    if (!allowed.contains(value)) {
      throw const OfflineSyncException(
        'invalid_catalogue_enum',
        'A catalogue option is invalid.',
      );
    }
    return value;
  }
}

class _DimensionIdentity {
  const _DimensionIdentity({
    required this.localId,
    required this.globalId,
    required this.originDatabaseId,
  });

  final int localId;
  final String globalId;
  final String originDatabaseId;

  factory _DimensionIdentity.fromRow(QueryRow row) => _DimensionIdentity(
    localId: row.read<int>('local_id'),
    globalId: row.read<String>('global_id'),
    originDatabaseId: row.read<String>('origin_database_id'),
  );
}
