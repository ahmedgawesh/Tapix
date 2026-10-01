import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/services/sync/branch_catalogue_sync_service.dart';
import 'package:tapix/core/services/sync/offline_sync_event_store.dart';
import 'package:tapix/core/services/sync/sync_entity_identity_store.dart';

void main() {
  late AppDatabase db;
  late OfflineSyncEventStore events;
  late BranchCatalogueSyncService catalogue;

  setUp(() async {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    await db.customSelect('SELECT 1').get();
    events = OfflineSyncEventStore(db);
    catalogue = BranchCatalogueSyncService(
      db,
      events,
      SyncEntityIdentityStore(db),
    );
    await events.activateWriterRecording(
      enrollmentId: '11111111-1111-4111-8111-111111111111',
    );
  });

  tearDown(() => db.close());

  test('only the coordinator may edit shared catalogue master data', () async {
    expect(await catalogue.isSharedCatalogueAuthority(), isTrue);
    final localDatabaseId = await db
        .customSelect('SELECT database_id FROM sync_local_state WHERE id=1')
        .map((row) => row.read<String>('database_id'))
        .getSingle();
    await db
        .customStatement('INSERT INTO app_settings(key,value) VALUES(?,?)', [
          'lan.branch_sync.coordinator_database_id.v1',
          '99999999-9999-4999-8999-999999999999',
        ]);
    expect(await catalogue.isSharedCatalogueAuthority(), isFalse);
    await db.customStatement('UPDATE app_settings SET value=? WHERE key=?', [
      localDatabaseId,
      'lan.branch_sync.coordinator_database_id.v1',
    ]);
    expect(await catalogue.isSharedCatalogueAuthority(), isTrue);
  });

  test(
    'publishes deterministic catalogue pages without stock or balances',
    () async {
      final currencyId = (await (db.select(
        db.currencies,
      )..where((row) => row.code.equals('USD'))).getSingle()).id;
      final supplierId = await db
          .into(db.suppliers)
          .insert(
            SuppliersCompanion.insert(
              name: 'Shared supplier',
              productCode: const Value('SHR'),
              currencyId: currencyId,
              openingBalanceCents: Value(Decimal.fromInt(9000)),
              balanceCents: Value(Decimal.fromInt(12000)),
            ),
          );
      await db
          .into(db.customers)
          .insert(
            CustomersCompanion.insert(
              name: 'Shared customer',
              currencyId: currencyId,
              openingBalanceCents: Value(Decimal.fromInt(4000)),
              balanceCents: Value(Decimal.fromInt(6500)),
              loyaltyPointsBalance: const Value(900),
              totalSpentCents: Value(Decimal.fromInt(25000)),
              totalTransactions: const Value(12),
            ),
          );
      final productId = await db
          .into(db.products)
          .insert(
            ProductsCompanion.insert(
              name: 'Shared item',
              sku: const Value('SHARED-1'),
              barcode: const Value('1234567890123'),
              supplierId: Value(supplierId),
              currencyId: Value(currencyId),
              stockQuantity: const Value(17),
              costCents: Decimal.fromInt(700),
              priceCents: Decimal.fromInt(1100),
            ),
          );
      await db
          .into(db.productVariants)
          .insert(
            ProductVariantsCompanion.insert(
              productId: productId,
              sku: const Value('SHARED-1-V'),
              stockQuantity: const Value(17),
              costCents: Decimal.fromInt(700),
              priceCents: Decimal.fromInt(1100),
            ),
          );

      final first = await catalogue.publishSnapshot();
      final countAfterFirst = await db
          .customSelect('SELECT COUNT(*) AS n FROM sync_outbox_events')
          .map((row) => row.read<int>('n'))
          .getSingle();
      final second = await catalogue.publishSnapshot();
      final countAfterRetry = await db
          .customSelect('SELECT COUNT(*) AS n FROM sync_outbox_events')
          .map((row) => row.read<int>('n'))
          .getSingle();

      expect(second, first);
      expect(countAfterFirst, greaterThanOrEqualTo(7));
      expect(countAfterRetry, countAfterFirst);
      final envelopes = await events.claimDispatchBatch(
        leaseToken: 'catalogue-test-lease',
        limit: 20,
      );
      expect(envelopes.map((event) => event.eventType).toSet(), {
        BranchCatalogueSyncService.eventType,
      });
      final supplier =
          envelopes
                  .singleWhere(
                    (event) => event.payload['entityType'] == 'supplier',
                  )
                  .payload['entities']
              as List;
      expect(supplier.single, isNot(contains('balanceMinor')));
      expect(supplier.single, isNot(contains('openingBalanceMinor')));
      final customer =
          envelopes
                  .singleWhere(
                    (event) => event.payload['entityType'] == 'customer',
                  )
                  .payload['entities']
              as List;
      expect(customer.single, isNot(contains('balanceMinor')));
      expect(customer.single, isNot(contains('openingBalanceMinor')));
      expect(customer.single, isNot(contains('loyaltyPointsBalance')));
      expect(customer.single, isNot(contains('totalSpentMinor')));
      final product =
          envelopes
                  .singleWhere(
                    (event) => event.payload['entityType'] == 'product',
                  )
                  .payload['entities']
              as List;
      expect(product.single, isNot(contains('stockQuantity')));
      final variant =
          envelopes
                  .singleWhere(
                    (event) => event.payload['entityType'] == 'variant',
                  )
                  .payload['entities']
              as List;
      expect(variant.single, isNot(contains('stockQuantity')));
    },
  );

  test(
    'publishes pharmacy profiles promotions and measured product semantics',
    () async {
      await db.customStatement(
        "UPDATE app_settings SET value='1' WHERE key IN "
        "('pharmacy_features_enabled','promotions_enabled')",
      );
      final currencyId = (await (db.select(
        db.currencies,
      )..where((row) => row.code.equals('USD'))).getSingle()).id;
      final productId = await db
          .into(db.products)
          .insert(
            ProductsCompanion.insert(
              name: 'Measured medicine',
              sku: const Value('MED-W-1'),
              currencyId: Value(currencyId),
              measurementType: const Value('weight'),
              inventoryTrackingType: const Value('batch_expiry'),
              stockQuantity: const Value(9000),
              costCents: Decimal.fromInt(250),
              priceCents: Decimal.fromInt(400),
            ),
          );
      final ingredientId = await db
          .into(db.activeIngredients)
          .insert(
            ActiveIngredientsCompanion.insert(
              canonicalName: 'Example ingredient',
              normalizedName: 'example ingredient',
            ),
          );
      await db
          .into(db.activeIngredientAliases)
          .insert(
            ActiveIngredientAliasesCompanion.insert(
              ingredientId: ingredientId,
              alias: 'Example',
              normalizedAlias: 'example',
              languageCode: const Value('en'),
            ),
          );
      await db
          .into(db.medicineProfiles)
          .insert(
            MedicineProfilesCompanion.insert(
              productId: Value(productId),
              dosageForm: 'powder',
              administrationRoute: const Value('oral'),
            ),
          );
      await db
          .into(db.medicineActiveIngredients)
          .insert(
            MedicineActiveIngredientsCompanion.insert(
              productId: productId,
              ingredientId: ingredientId,
              normalizedStrengthValueMicros: 500000000,
              normalizedStrengthUnit: 'mg',
            ),
          );
      final promotionId = await db
          .into(db.promotions)
          .insert(
            PromotionsCompanion.insert(
              code: 'MED-WEIGHT',
              name: 'Measured medicine offer',
              promotionType: 'quantity',
              status: const Value('active'),
            ),
          );
      await db
          .into(db.promotionConditions)
          .insert(
            PromotionConditionsCompanion.insert(
              promotionId: promotionId,
              conditionType: 'minimum_quantity',
              minimumQuantity: const Value(2000),
              quantityScale: const Value(1000),
              measurementType: const Value('weight'),
            ),
          );
      await db
          .into(db.promotionScopes)
          .insert(
            PromotionScopesCompanion.insert(
              promotionId: promotionId,
              scopeRole: 'eligible',
              targetType: 'product',
              productId: Value(productId),
              quantityScale: const Value(1000),
            ),
          );
      await db
          .into(db.promotionRewards)
          .insert(
            PromotionRewardsCompanion.insert(
              promotionId: promotionId,
              rewardType: 'percentage_off',
              percentBps: const Value(1000),
            ),
          );

      await catalogue.publishSnapshot();
      final envelopes = await events.claimDispatchBatch(
        leaseToken: 'pharmacy-catalogue-test',
        limit: 50,
      );
      expect(envelopes, isNotEmpty);
      for (final event in envelopes) {
        expect(event.payload['featurePolicy'], {
          'pharmacyEnabled': true,
          'promotionsEnabled': true,
          'branchAssortments': <String, Object?>{},
        });
      }
      final productPage = envelopes.singleWhere(
        (event) => event.payload['entityType'] == 'product',
      );
      final product = (productPage.payload['entities'] as List)
          .cast<Map<String, Object?>>()
          .singleWhere((entry) => entry['sku'] == 'MED-W-1');
      expect(product['measurementType'], 'weight');
      expect(product['inventoryTrackingType'], 'batch_expiry');
      expect(product, isNot(contains('stockQuantity')));
      final medicine = product['medicineProfile'] as Map<String, Object?>;
      expect(medicine['dosageForm'], 'powder');
      expect(
        (medicine['ingredients'] as List).single['normalizedName'],
        'example ingredient',
      );

      final promotionPage = envelopes.singleWhere(
        (event) => event.payload['entityType'] == 'promotion',
      );
      final promotion =
          (promotionPage.payload['entities'] as List).single as Map;
      expect(promotion['code'], 'MED-WEIGHT');
      expect(
        (promotion['conditions'] as List).single['measurementType'],
        'weight',
      );
      expect(
        (promotion['scopes'] as List).single['productGlobalId'],
        product['globalId'],
      );
      expect(promotion, isNot(contains('saleApplications')));
    },
  );
}
