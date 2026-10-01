import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/services/sync/branch_catalogue_sync_service.dart';
import 'package:tapix/core/services/sync/branch_operational_projection_service.dart';
import 'package:tapix/core/services/sync/offline_sync_event_store.dart';
import 'package:tapix/core/services/sync/sync_entity_identity_store.dart';
import 'package:tapix/core/services/sync/sync_inbound_projection_service.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    await db.customSelect('SELECT 1').get();
  });

  tearDown(() => db.close());

  test('applies supplier product and variant with zero local balances', () async {
    const sourceDatabaseId = '22222222-2222-4222-8222-222222222222';
    const sourceBranchId = '33333333-3333-4333-8333-333333333333';
    const snapshotId = '44444444-4444-4444-8444-444444444444';
    const supplierGlobalId = '55555555-5555-4555-8555-555555555555';
    const customerGlobalId = '12121212-1212-4212-8212-121212121212';
    const productGlobalId = '66666666-6666-4666-8666-666666666666';
    const variantGlobalId = '77777777-7777-4777-8777-777777777777';
    final organizationId = await db
        .customSelect(
          'SELECT organization_id FROM business_contexts WHERE id=1',
        )
        .map((row) => row.read<String>('organization_id'))
        .getSingle();
    await db.customStatement(
      '''INSERT INTO app_settings(key,value)
      VALUES('lan.branch_sync.coordinator_database_id.v1',?)
      ON CONFLICT(key) DO UPDATE SET value=excluded.value''',
      [sourceDatabaseId],
    );
    final events = OfflineSyncEventStore(db);
    await events.enrollSource(
      sourceDatabaseId: sourceDatabaseId,
      organizationId: organizationId,
      branchId: sourceBranchId,
    );
    final catalogue = BranchCatalogueSyncService(
      db,
      events,
      SyncEntityIdentityStore(db),
    );
    final inbound = SyncInboundProjectionService(
      db,
      events,
      operationalProjector: BranchOperationalProjectionService(
        db,
        catalogue: catalogue,
      ).apply,
    );

    await inbound.apply(
      _event(
        eventId: '88888888-8888-4888-8888-888888888888',
        sequence: 1,
        organizationId: organizationId,
        sourceDatabaseId: sourceDatabaseId,
        sourceBranchId: sourceBranchId,
        snapshotId: snapshotId,
        entityType: 'supplier',
        entities: const [
          {
            'globalId': supplierGlobalId,
            'originDatabaseId': sourceDatabaseId,
            'name': 'Remote supplier',
            'productCode': 'REM',
            'email': null,
            'phone': null,
            'address': null,
            'defaultSupplyMode': 'mixed',
            'currencyCode': 'USD',
            'isActive': true,
          },
        ],
      ),
    );
    await inbound.apply(
      _event(
        eventId: '13131313-1313-4313-8313-131313131313',
        sequence: 2,
        organizationId: organizationId,
        sourceDatabaseId: sourceDatabaseId,
        sourceBranchId: sourceBranchId,
        snapshotId: snapshotId,
        entityType: 'customer',
        entities: const [
          {
            'globalId': customerGlobalId,
            'originDatabaseId': sourceDatabaseId,
            'name': 'Remote customer',
            'email': 'customer@example.test',
            'phone': '01000000000',
            'address': 'Cairo',
            'currencyCode': 'USD',
            'segment': 'premium',
            'loyaltyEnabled': true,
            'isActive': true,
          },
        ],
      ),
    );
    await inbound.apply(
      _event(
        eventId: '99999999-9999-4999-8999-999999999999',
        sequence: 3,
        organizationId: organizationId,
        sourceDatabaseId: sourceDatabaseId,
        sourceBranchId: sourceBranchId,
        snapshotId: snapshotId,
        entityType: 'product',
        entities: const [
          {
            'globalId': productGlobalId,
            'originDatabaseId': sourceDatabaseId,
            'sku': 'REMOTE-1',
            'barcode': '9876543210123',
            'name': 'Remote item',
            'nameAr': null,
            'nameFr': null,
            'description': null,
            'supplierGlobalId': supplierGlobalId,
            'referenceCostMinor': 500,
            'priceMinor': 900,
            'wholesalePriceMinor': null,
            'currencyCode': 'USD',
            'trackInventory': true,
            'measurementType': 'piece',
            'minimumQuantityScaled': 2,
            'hasVariants': false,
            'isTaxable': true,
            'purchaseTaxRateBps': 100,
            'salesTaxRateBps': 150,
            'costingMethod': 'wac',
            'inventoryTrackingType': 'standard',
            'isActive': true,
          },
        ],
      ),
    );
    await inbound.apply(
      _event(
        eventId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        sequence: 4,
        organizationId: organizationId,
        sourceDatabaseId: sourceDatabaseId,
        sourceBranchId: sourceBranchId,
        snapshotId: snapshotId,
        entityType: 'variant',
        entities: const [
          {
            'globalId': variantGlobalId,
            'originDatabaseId': sourceDatabaseId,
            'productGlobalId': productGlobalId,
            'sku': 'REMOTE-1-V',
            'barcode': null,
            'referenceCostMinor': 500,
            'priceMinor': 900,
            'wholesalePriceMinor': null,
            'priceAdjustmentMinor': 0,
            'isActive': true,
          },
        ],
      ),
    );

    final supplier = await db
        .customSelect(
          "SELECT balance_cents,opening_balance_cents FROM suppliers WHERE product_code='REM'",
        )
        .getSingle();
    expect(supplier.read<int>('balance_cents'), 0);
    expect(supplier.read<int>('opening_balance_cents'), 0);
    final customer = await db
        .customSelect(
          'SELECT balance_cents,opening_balance_cents,loyalty_points_balance,'
          'total_spent_cents,total_transactions FROM customers '
          "WHERE email='customer@example.test'",
        )
        .getSingle();
    expect(customer.read<int>('balance_cents'), 0);
    expect(customer.read<int>('opening_balance_cents'), 0);
    expect(customer.read<int>('loyalty_points_balance'), 0);
    expect(customer.read<int>('total_spent_cents'), 0);
    expect(customer.read<int>('total_transactions'), 0);
    expect(
      await db
          .customSelect(
            "SELECT stock_quantity FROM products WHERE sku='REMOTE-1'",
          )
          .map((row) => row.read<int>('stock_quantity'))
          .getSingle(),
      0,
    );
    expect(
      await db
          .customSelect(
            "SELECT stock_quantity FROM product_variants WHERE sku='REMOTE-1-V'",
          )
          .map((row) => row.read<int>('stock_quantity'))
          .getSingle(),
      0,
    );
    expect(
      await db
          .customSelect('SELECT COUNT(*) AS n FROM sync_catalogue_pages')
          .map((row) => row.read<int>('n'))
          .getSingle(),
      4,
    );

    // A later coordinator snapshot may refresh shared catalogue metadata, but
    // must never overwrite branch-owned balances, loyalty, stock or valuation.
    await db.customStatement(
      "UPDATE suppliers SET balance_cents=12345 WHERE product_code='REM'",
    );
    await db.customStatement(
      'UPDATE customers SET balance_cents=23456,loyalty_points_balance=77 '
      "WHERE email='customer@example.test'",
    );
    await db.customStatement(
      "UPDATE products SET stock_quantity=7,cost_cents=650 WHERE sku='REMOTE-1'",
    );
    await db.customStatement(
      'UPDATE product_variants SET stock_quantity=7,cost_cents=660 '
      "WHERE sku='REMOTE-1-V'",
    );
    const updatedSnapshotId = 'abababab-abab-4bab-8bab-abababababab';
    await inbound.apply(
      _event(
        eventId: '15151515-1515-4515-8515-151515151515',
        sequence: 5,
        organizationId: organizationId,
        sourceDatabaseId: sourceDatabaseId,
        sourceBranchId: sourceBranchId,
        snapshotId: updatedSnapshotId,
        entityType: 'supplier',
        entities: const [
          {
            'globalId': supplierGlobalId,
            'originDatabaseId': sourceDatabaseId,
            'name': 'Remote supplier updated',
            'productCode': 'REM',
            'email': 'updated-supplier@example.test',
            'phone': '01111111111',
            'address': 'Alexandria',
            'defaultSupplyMode': 'consignment',
            'currencyCode': 'USD',
            'isActive': true,
          },
        ],
      ),
    );
    await inbound.apply(
      _event(
        eventId: '16161616-1616-4616-8616-161616161616',
        sequence: 6,
        organizationId: organizationId,
        sourceDatabaseId: sourceDatabaseId,
        sourceBranchId: sourceBranchId,
        snapshotId: updatedSnapshotId,
        entityType: 'customer',
        entities: const [
          {
            'globalId': customerGlobalId,
            'originDatabaseId': sourceDatabaseId,
            'name': 'Remote customer updated',
            'email': 'updated-customer@example.test',
            'phone': '01222222222',
            'address': 'Giza',
            'currencyCode': 'USD',
            'segment': 'wholesale',
            'loyaltyEnabled': false,
            'isActive': true,
          },
        ],
      ),
    );
    await inbound.apply(
      _event(
        eventId: '17171717-1717-4717-8717-171717171717',
        sequence: 7,
        organizationId: organizationId,
        sourceDatabaseId: sourceDatabaseId,
        sourceBranchId: sourceBranchId,
        snapshotId: updatedSnapshotId,
        entityType: 'product',
        entities: const [
          {
            'globalId': productGlobalId,
            'originDatabaseId': sourceDatabaseId,
            'sku': 'REMOTE-1-UPDATED',
            'barcode': '9876543210999',
            'name': 'Remote item updated',
            'nameAr': 'صنف محدث',
            'nameFr': null,
            'description': 'Updated metadata',
            'supplierGlobalId': supplierGlobalId,
            'referenceCostMinor': 999,
            'priceMinor': 1200,
            'wholesalePriceMinor': 1100,
            'currencyCode': 'USD',
            'trackInventory': true,
            'measurementType': 'piece',
            'minimumQuantityScaled': 3,
            'hasVariants': false,
            'isTaxable': true,
            'purchaseTaxRateBps': 100,
            'salesTaxRateBps': 150,
            'costingMethod': 'wac',
            'inventoryTrackingType': 'standard',
            'isActive': true,
          },
        ],
      ),
    );
    await inbound.apply(
      _event(
        eventId: '18181818-1818-4818-8818-181818181818',
        sequence: 8,
        organizationId: organizationId,
        sourceDatabaseId: sourceDatabaseId,
        sourceBranchId: sourceBranchId,
        snapshotId: updatedSnapshotId,
        entityType: 'variant',
        entities: const [
          {
            'globalId': variantGlobalId,
            'originDatabaseId': sourceDatabaseId,
            'productGlobalId': productGlobalId,
            'sku': 'REMOTE-1-V-UPDATED',
            'barcode': '9876543210888',
            'referenceCostMinor': 998,
            'priceMinor': 1250,
            'wholesalePriceMinor': 1150,
            'priceAdjustmentMinor': 50,
            'isActive': true,
          },
        ],
      ),
    );

    final updatedSupplier = await db
        .customSelect(
          "SELECT name,balance_cents FROM suppliers WHERE product_code='REM'",
        )
        .getSingle();
    expect(updatedSupplier.read<String>('name'), 'Remote supplier updated');
    expect(updatedSupplier.read<int>('balance_cents'), 12345);
    final updatedCustomer = await db
        .customSelect(
          'SELECT name,balance_cents,loyalty_points_balance FROM customers '
          "WHERE email='updated-customer@example.test'",
        )
        .getSingle();
    expect(updatedCustomer.read<String>('name'), 'Remote customer updated');
    expect(updatedCustomer.read<int>('balance_cents'), 23456);
    expect(updatedCustomer.read<int>('loyalty_points_balance'), 77);
    final updatedProduct = await db
        .customSelect(
          'SELECT name,cost_cents,price_cents,stock_quantity FROM products '
          "WHERE sku='REMOTE-1-UPDATED'",
        )
        .getSingle();
    expect(updatedProduct.read<String>('name'), 'Remote item updated');
    expect(updatedProduct.read<int>('cost_cents'), 650);
    expect(updatedProduct.read<int>('price_cents'), 1200);
    expect(updatedProduct.read<int>('stock_quantity'), 7);
    final updatedVariant = await db
        .customSelect(
          'SELECT cost_cents,price_cents,stock_quantity FROM product_variants '
          "WHERE sku='REMOTE-1-V-UPDATED'",
        )
        .getSingle();
    expect(updatedVariant.read<int>('cost_cents'), 660);
    expect(updatedVariant.read<int>('price_cents'), 1250);
    expect(updatedVariant.read<int>('stock_quantity'), 7);
  });
  test(
    'applies branch pharmacy promotions and measured product semantics',
    () async {
      const sourceDatabaseId = '20202020-2020-4020-8020-202020202020';
      const sourceBranchId = '30303030-3030-4030-8030-303030303030';
      const snapshotId = '40404040-4040-4040-8040-404040404040';
      const supplierGlobalId = '50505050-5050-4050-8050-505050505050';
      const medicineGlobalId = '60606060-6060-4060-8060-606060606060';
      final organizationId = await db
          .customSelect(
            'SELECT organization_id FROM business_contexts WHERE id=1',
          )
          .map((row) => row.read<String>('organization_id'))
          .getSingle();
      await db.customStatement(
        '''INSERT INTO app_settings(key,value)
      VALUES('lan.branch_sync.coordinator_database_id.v1',?)
      ON CONFLICT(key) DO UPDATE SET value=excluded.value''',
        [sourceDatabaseId],
      );
      final events = OfflineSyncEventStore(db);
      await events.enrollSource(
        sourceDatabaseId: sourceDatabaseId,
        organizationId: organizationId,
        branchId: sourceBranchId,
      );
      final catalogue = BranchCatalogueSyncService(
        db,
        events,
        SyncEntityIdentityStore(db),
      );
      final inbound = SyncInboundProjectionService(
        db,
        events,
        operationalProjector: BranchOperationalProjectionService(
          db,
          catalogue: catalogue,
        ).apply,
      );
      const policy = <String, Object?>{
        'pharmacyEnabled': true,
        'promotionsEnabled': true,
      };
      await inbound.apply(
        _event(
          eventId: '70707070-7070-4070-8070-707070707070',
          sequence: 1,
          organizationId: organizationId,
          sourceDatabaseId: sourceDatabaseId,
          sourceBranchId: sourceBranchId,
          snapshotId: snapshotId,
          entityType: 'supplier',
          featurePolicy: policy,
          entities: const [
            {
              'globalId': supplierGlobalId,
              'originDatabaseId': sourceDatabaseId,
              'name': 'Pharmacy supplier',
              'productCode': 'PHSUP',
              'email': null,
              'phone': null,
              'address': null,
              'defaultSupplyMode': 'standard',
              'currencyCode': 'USD',
              'isActive': true,
            },
          ],
        ),
      );
      Map<String, Object?> product(
        String globalId,
        String sku,
        String measurement,
        String tracking, {
        Object? medicineProfile,
      }) => {
        'globalId': globalId,
        'originDatabaseId': sourceDatabaseId,
        'sku': sku,
        'barcode': null,
        'name': sku,
        'nameAr': null,
        'nameFr': null,
        'description': null,
        'supplierGlobalId': supplierGlobalId,
        'referenceCostMinor': 250,
        'priceMinor': 400,
        'wholesalePriceMinor': null,
        'currencyCode': 'USD',
        'trackInventory': true,
        'measurementType': measurement,
        'minimumQuantityScaled': measurement == 'piece' ? 1 : 1000,
        'hasVariants': false,
        'isTaxable': true,
        'purchaseTaxRateBps': 0,
        'salesTaxRateBps': 0,
        'costingMethod': 'wac',
        'inventoryTrackingType': tracking,
        'medicineProfile': medicineProfile,
        'isActive': true,
      };
      await inbound.apply(
        _event(
          eventId: '80808080-8080-4080-8080-808080808080',
          sequence: 2,
          organizationId: organizationId,
          sourceDatabaseId: sourceDatabaseId,
          sourceBranchId: sourceBranchId,
          snapshotId: snapshotId,
          entityType: 'product',
          featurePolicy: policy,
          entities: [
            product(
              medicineGlobalId,
              'SYNC-MED-WEIGHT',
              'weight',
              'batch_expiry',
              medicineProfile: const {
                'dosageForm': 'powder',
                'administrationRoute': 'oral',
                'substitutionEligible': true,
                'notes': null,
                'ingredients': [
                  {
                    'canonicalName': 'Synced ingredient',
                    'normalizedName': 'synced ingredient',
                    'nameAr': 'مادة متزامنة',
                    'nameFr': null,
                    'description': null,
                    'isActive': true,
                    'strengthValueMicros': 500000000,
                    'strengthUnit': 'mg',
                    'basisValueMicros': null,
                    'basisUnit': null,
                    'sortOrder': 0,
                    'aliases': <Map<String, Object?>>[],
                  },
                ],
              },
            ),
            product(
              '61616161-6161-4161-8161-616161616161',
              'SYNC-LENGTH',
              'length',
              'standard',
            ),
            product(
              '62626262-6262-4262-8262-626262626262',
              'SYNC-VOLUME',
              'volume',
              'batch',
            ),
          ],
        ),
      );
      await inbound.apply(
        _event(
          eventId: '90909090-9090-4090-8090-909090909090',
          sequence: 3,
          organizationId: organizationId,
          sourceDatabaseId: sourceDatabaseId,
          sourceBranchId: sourceBranchId,
          snapshotId: snapshotId,
          entityType: 'promotion',
          featurePolicy: policy,
          entities: const [
            {
              'code': 'SYNC-MED-OFFER',
              'version': 1,
              'name': 'Synced medicine offer',
              'nameAr': null,
              'nameFr': null,
              'description': null,
              'promotionType': 'quantity',
              'status': 'active',
              'applicationMode': 'automatic',
              'concurrencyMode': 'best_price',
              'priority': 10,
              'currencyCode': 'USD',
              'priceMode': 'retail',
              'couponCode': null,
              'startsAt': null,
              'endsAt': null,
              'maxApplicationsPerTransaction': 2,
              'maxApplicationsPerCustomer': null,
              'allowManualDiscountCombination': false,
              'allowBelowCost': false,
              'conditions': [
                {
                  'conditionType': 'minimum_quantity',
                  'conditionGroup': 'default',
                  'minimumQuantity': 2000,
                  'quantityScale': 1000,
                  'measurementType': 'weight',
                  'minimumSpendMinor': null,
                  'paymentMethod': null,
                  'couponCode': null,
                  'metadataJson': null,
                },
              ],
              'scopes': [
                {
                  'role': 'eligible',
                  'targetType': 'product',
                  'productGlobalId': medicineGlobalId,
                  'variantGlobalId': null,
                  'categoryGlobalId': null,
                  'isExcluded': false,
                  'lineGroup': 'A',
                  'requiredQuantity': 2000,
                  'quantityScale': 1000,
                  'sortOrder': 0,
                },
              ],
              'rewards': [
                {
                  'rewardType': 'percentage_off',
                  'applyTo': 'qualifying_lines',
                  'percentBps': 1000,
                  'amountMinor': null,
                  'fixedPriceMinor': null,
                  'rewardQuantity': null,
                  'quantityScale': 1000,
                  'maxDiscountMinor': null,
                  'productGlobalId': null,
                  'variantGlobalId': null,
                  'categoryGlobalId': null,
                  'cheapestFirst': true,
                },
              ],
              'schedules': [],
            },
          ],
        ),
      );

      expect(await db.settingsDao.getSetting('pharmacy_features_enabled'), '1');
      expect(await db.settingsDao.getSetting('promotions_enabled'), '1');
      final products = await db.customSelect(
        """SELECT id,sku,measurement_type,inventory_tracking_type,stock_quantity
            FROM products WHERE sku LIKE 'SYNC-%' ORDER BY sku""",
      ).get();
      expect({
        for (final row in products) row.read<String>('measurement_type'),
      }, containsAll({'weight', 'length', 'volume'}));
      expect(
        products.every((row) => row.read<int>('stock_quantity') == 0),
        isTrue,
      );
      final medicineId = products
          .singleWhere((row) => row.read<String>('sku') == 'SYNC-MED-WEIGHT')
          .read<int>('id');
      expect(
        await db
            .customSelect(
              'SELECT COUNT(*) AS n FROM medicine_profiles WHERE product_id=?',
              variables: [Variable.withInt(medicineId)],
            )
            .map((row) => row.read<int>('n'))
            .getSingle(),
        1,
      );
      final promotion = await db.customSelect('''
      SELECT p.code,c.measurement_type,s.quantity_scale,r.percent_bps
      FROM promotions p
      JOIN promotion_conditions c ON c.promotion_id=p.id
      JOIN promotion_scopes s ON s.promotion_id=p.id
      JOIN promotion_rewards r ON r.promotion_id=p.id
      WHERE p.code='SYNC-MED-OFFER'
    ''').getSingle();
      expect(promotion.read<String>('measurement_type'), 'weight');
      expect(promotion.read<int>('quantity_scale'), 1000);
      expect(promotion.read<int>('percent_bps'), 1000);
    },
  );

  test(
    'replica accepts first supplier code assignment but rejects replacement',
    () async {
      const sourceDatabaseId = '22222222-2222-4222-8222-222222222222';
      const sourceBranchId = '33333333-3333-4333-8333-333333333333';
      const supplierGlobalId = '55555555-5555-4555-8555-555555555555';
      final organizationId = await db
          .customSelect(
            'SELECT organization_id FROM business_contexts WHERE id=1',
          )
          .map((row) => row.read<String>('organization_id'))
          .getSingle();
      await db.customStatement(
        '''INSERT INTO app_settings(key,value)
      VALUES('lan.branch_sync.coordinator_database_id.v1',?)''',
        [sourceDatabaseId],
      );
      final events = OfflineSyncEventStore(db);
      await events.enrollSource(
        sourceDatabaseId: sourceDatabaseId,
        organizationId: organizationId,
        branchId: sourceBranchId,
      );
      final catalogue = BranchCatalogueSyncService(
        db,
        events,
        SyncEntityIdentityStore(db),
      );

      List<Map<String, Object?>> supplier(String? code) => [
        {
          'globalId': supplierGlobalId,
          'originDatabaseId': sourceDatabaseId,
          'name': 'Medicine supplier',
          'productCode': code,
          'email': null,
          'phone': null,
          'address': null,
          'defaultSupplyMode': 'mixed',
          'currencyCode': 'USD',
          'isActive': true,
        },
      ];
      Future<void> apply({
        required String eventId,
        required String snapshotId,
        required int sequence,
        required String? code,
      }) async {
        await events.applyInbound(
          event: _event(
            eventId: eventId,
            sequence: sequence,
            organizationId: organizationId,
            sourceDatabaseId: sourceDatabaseId,
            sourceBranchId: sourceBranchId,
            snapshotId: snapshotId,
            entityType: 'supplier',
            entities: supplier(code),
          ),
          apply: catalogue.applyPage,
        );
      }

      await apply(
        eventId: '61616161-6161-4161-8161-616161616161',
        snapshotId: '71717171-7171-4171-8171-717171717171',
        sequence: 1,
        code: null,
      );
      await apply(
        eventId: '62626262-6262-4262-8262-626262626262',
        snapshotId: '72727272-7272-4272-8272-727272727272',
        sequence: 2,
        code: 'MEDS',
      );
      expect(
        await db
            .customSelect('SELECT product_code FROM suppliers')
            .map((row) => row.readNullable<String>('product_code'))
            .getSingle(),
        'MEDS',
      );
      await expectLater(
        apply(
          eventId: '63636363-6363-4363-8363-636363636363',
          snapshotId: '73737373-7373-4373-8373-737373737373',
          sequence: 3,
          code: 'OTHER',
        ),
        throwsA(
          isA<OfflineSyncException>().having(
            (error) => error.code,
            'code',
            'catalogue_supplier_code_conflict',
          ),
        ),
      );
    },
  );
  test(
    'managed branch assortment hides unassigned products and can switch to all',
    () async {
      const sourceDatabaseId = '81818181-8181-4181-8181-818181818181';
      const sourceBranchId = '82828282-8282-4282-8282-828282828282';
      const allowedId = '83838383-8383-4383-8383-838383838383';
      const hiddenId = '84848484-8484-4484-8484-848484848484';
      final organizationId = await db
          .customSelect(
            'SELECT organization_id FROM business_contexts WHERE id=1',
          )
          .map((row) => row.read<String>('organization_id'))
          .getSingle();
      final localBranchId = await db
          .customSelect('SELECT branch_id FROM business_contexts WHERE id=1')
          .map((row) => row.read<String>('branch_id'))
          .getSingle();
      await db.customStatement(
        "INSERT INTO app_settings(key,value) VALUES('lan.branch_sync.coordinator_database_id.v1',?)",
        [sourceDatabaseId],
      );
      final events = OfflineSyncEventStore(db);
      await events.enrollSource(
        sourceDatabaseId: sourceDatabaseId,
        organizationId: organizationId,
        branchId: sourceBranchId,
      );
      final catalogue = BranchCatalogueSyncService(
        db,
        events,
        SyncEntityIdentityStore(db),
      );
      final inbound = SyncInboundProjectionService(
        db,
        events,
        operationalProjector: BranchOperationalProjectionService(
          db,
          catalogue: catalogue,
        ).apply,
      );
      Map<String, Object?> product(String id, String sku) => {
        'globalId': id,
        'originDatabaseId': sourceDatabaseId,
        'sku': sku,
        'barcode': null,
        'name': sku,
        'nameAr': null,
        'nameFr': null,
        'description': null,
        'referenceCostMinor': 100,
        'priceMinor': 200,
        'wholesalePriceMinor': null,
        'currencyCode': 'USD',
        'trackInventory': true,
        'measurementType': 'piece',
        'minimumQuantityScaled': 0,
        'hasVariants': false,
        'isTaxable': false,
        'purchaseTaxRateBps': 0,
        'salesTaxRateBps': 0,
        'costingMethod': 'wac',
        'inventoryTrackingType': 'standard',
        'isActive': true,
      };
      final managedPolicy = <String, Object?>{
        'pharmacyEnabled': false,
        'promotionsEnabled': false,
        'branchAssortments': {
          localBranchId: {
            'mode': 'managed_assortment',
            'categoryGlobalIds': <String>[],
            'productGlobalIds': [allowedId],
            'excludedProductGlobalIds': <String>[],
          },
        },
      };
      await inbound.apply(
        _event(
          eventId: '85858585-8585-4585-8585-858585858585',
          sequence: 1,
          organizationId: organizationId,
          sourceDatabaseId: sourceDatabaseId,
          sourceBranchId: sourceBranchId,
          snapshotId: '86868686-8686-4686-8686-868686868686',
          entityType: 'product',
          featurePolicy: managedPolicy,
          entities: [
            product(allowedId, 'ALLOWED'),
            product(hiddenId, 'HIDDEN'),
          ],
        ),
      );
      var rows = await db
          .customSelect(
            "SELECT sku,is_active FROM products WHERE sku IN('ALLOWED','HIDDEN') ORDER BY sku",
          )
          .get();
      expect(rows.map((row) => row.read<int>('is_active')), [1, 0]);

      await inbound.apply(
        _event(
          eventId: '87878787-8787-4787-8787-878787878787',
          sequence: 2,
          organizationId: organizationId,
          sourceDatabaseId: sourceDatabaseId,
          sourceBranchId: sourceBranchId,
          snapshotId: '88888888-8888-4888-8888-888888888881',
          entityType: 'product',
          featurePolicy: {
            'pharmacyEnabled': false,
            'promotionsEnabled': false,
            'branchAssortments': {
              localBranchId: {
                'mode': 'all_company_products',
                'categoryGlobalIds': <String>[],
                'productGlobalIds': <String>[],
                'excludedProductGlobalIds': <String>[],
              },
            },
          },
          entities: [
            product(allowedId, 'ALLOWED'),
            product(hiddenId, 'HIDDEN'),
          ],
        ),
      );
      rows = await db
          .customSelect(
            "SELECT sku,is_active FROM products WHERE sku IN('ALLOWED','HIDDEN') ORDER BY sku",
          )
          .get();
      expect(rows.map((row) => row.read<int>('is_active')), [1, 1]);
    },
  );
}

SyncEventEnvelope _event({
  required String eventId,
  required int sequence,
  required String organizationId,
  required String sourceDatabaseId,
  required String sourceBranchId,
  required String snapshotId,
  required String entityType,
  required List<Map<String, Object?>> entities,
  Map<String, Object?>? featurePolicy,
}) {
  final draft = SyncEventEnvelope(
    eventId: eventId,
    sourceDatabaseId: sourceDatabaseId,
    organizationId: organizationId,
    branchId: sourceBranchId,
    sequence: sequence,
    eventType: BranchCatalogueSyncService.eventType,
    aggregateType: 'catalogue_snapshot',
    aggregateId: snapshotId,
    contractVersion: 1,
    payload: {
      'contract': 'catalogue.snapshot_page',
      'contractVersion': 1,
      'snapshotId': snapshotId,
      'organizationId': organizationId,
      'sourceDatabaseId': sourceDatabaseId,
      'sourceBranchId': sourceBranchId,
      'entityType': entityType,
      'featurePolicy': ?featurePolicy,
      'pageIndex': 0,
      'pageCount': 1,
      'entities': entities,
    },
    occurredAt: DateTime.utc(2026, 9, 28, 9, sequence),
    eventHash: '',
  );
  return SyncEventEnvelope(
    eventId: draft.eventId,
    sourceDatabaseId: draft.sourceDatabaseId,
    organizationId: draft.organizationId,
    branchId: draft.branchId,
    sequence: draft.sequence,
    eventType: draft.eventType,
    aggregateType: draft.aggregateType,
    aggregateId: draft.aggregateId,
    contractVersion: draft.contractVersion,
    payload: draft.payload,
    occurredAt: draft.occurredAt,
    eventHash: OfflineSyncTransaction.eventHashFor(draft),
  );
}
