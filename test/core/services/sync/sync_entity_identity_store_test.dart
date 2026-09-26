import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/services/sync/offline_sync_event_store.dart';
import 'package:tapix/core/services/sync/sync_entity_identity_store.dart';

void main() {
  late AppDatabase db;
  late SyncEntityIdentityStore identities;
  late OfflineSyncEventStore events;
  late int currencyId;
  late int productId;
  late int variantId;
  late int supplierId;
  late int customerId;
  late int batchId;
  late String organizationId;
  late String localDatabaseId;

  setUp(() async {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    await db.customSelect('SELECT 1').get();
    identities = SyncEntityIdentityStore(db);
    events = OfflineSyncEventStore(db);
    currencyId = (await db.select(db.currencies).get()).first.id;
    productId = await db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            name: 'Global item',
            currencyId: Value(currencyId),
            costCents: Decimal.fromInt(100),
            priceCents: Decimal.fromInt(150),
          ),
        );
    variantId = await db
        .into(db.productVariants)
        .insert(
          ProductVariantsCompanion.insert(
            productId: productId,
            costCents: Decimal.fromInt(100),
            priceCents: Decimal.fromInt(150),
          ),
        );
    supplierId = await db
        .into(db.suppliers)
        .insert(
          SuppliersCompanion.insert(
            name: 'Source supplier',
            currencyId: currencyId,
          ),
        );
    customerId = await db
        .into(db.customers)
        .insert(
          CustomersCompanion.insert(
            name: 'Source customer',
            currencyId: currencyId,
          ),
        );
    batchId = await db
        .into(db.productBatches)
        .insert(
          ProductBatchesCompanion.insert(
            productId: productId,
            variantId: Value(variantId),
            supplierId: Value(supplierId),
            batchNumber: 'SYNC-BATCH-1',
            receivedQuantity: 2,
            remainingQuantity: 2,
            unitCostCents: Decimal.fromInt(100),
          ),
        );
    final context = await db
        .customSelect(
          'SELECT organization_id,database_id FROM business_contexts WHERE id=1',
        )
        .getSingle();
    organizationId = context.read<String>('organization_id');
    localDatabaseId = context.read<String>('database_id');
  });

  tearDown(() => db.close());

  test(
    'local mapping is stable and records the authoritative database',
    () async {
      final first = await identities.getOrCreateLocal(
        entityType: 'product',
        localId: productId,
      );
      final replay = await identities.getOrCreateLocal(
        entityType: 'product',
        localId: productId,
      );
      expect(replay.globalId, first.globalId);
      expect(first.originDatabaseId, localDatabaseId);
      expect(first.globalId, hasLength(36));
    },
  );

  test('variant mapping creates its parent product mapping first', () async {
    final variant = await identities.getOrCreateLocal(
      entityType: 'product_variant',
      localId: variantId,
    );
    final product = await identities.findByLocal(
      entityType: 'product',
      localId: productId,
    );
    expect(variant.entityType, 'product_variant');
    expect(product, isNotNull);
    final count = await db
        .customSelect('SELECT COUNT(*) AS c FROM sync_entity_identities')
        .map((row) => row.read<int>('c'))
        .getSingle();
    expect(count, 2);
  });

  test(
    'batch mapping is stable and creates product variant supplier identities',
    () async {
      final batch = await identities.getOrCreateLocal(
        entityType: 'product_batch',
        localId: batchId,
      );
      final replay = await identities.getOrCreateLocal(
        entityType: 'product_batch',
        localId: batchId,
      );
      expect(replay.globalId, batch.globalId);
      expect(batch.originDatabaseId, localDatabaseId);
      expect(
        await identities.findByGlobal(
          entityType: 'product_batch',
          globalId: batch.globalId,
        ),
        isNotNull,
      );
      final masterTypes = await db
          .customSelect(
            'SELECT entity_type FROM sync_entity_identities ORDER BY entity_type',
          )
          .map((row) => row.read<String>('entity_type'))
          .get();
      expect(masterTypes, ['product', 'product_variant', 'supplier']);
      await expectLater(
        db.customStatement(
          'UPDATE sync_inventory_layer_identities SET global_id=? '
          'WHERE local_batch_id=?',
          ['99999999-9999-4999-8999-999999999999', batchId],
        ),
        throwsA(anything),
      );
      await expectLater(
        db.customStatement(
          'DELETE FROM sync_inventory_layer_identities WHERE local_batch_id=?',
          [batchId],
        ),
        throwsA(anything),
      );
    },
  );

  test('remote binding requires enrollment and is idempotent', () async {
    const remoteDatabase = '11111111-1111-4111-8111-111111111111';
    const remoteBranch = '22222222-2222-4222-8222-222222222222';
    const globalCustomer = '33333333-3333-4333-8333-333333333333';
    await expectLater(
      identities.bindRemote(
        entityType: 'customer',
        localId: customerId,
        globalId: globalCustomer,
        originDatabaseId: remoteDatabase,
      ),
      throwsA(_code('identity_source_not_enrolled')),
    );
    await events.enrollSource(
      sourceDatabaseId: remoteDatabase,
      organizationId: organizationId,
      branchId: remoteBranch,
    );
    final bound = await identities.bindRemote(
      entityType: 'customer',
      localId: customerId,
      globalId: globalCustomer,
      originDatabaseId: remoteDatabase,
    );
    final replay = await identities.bindRemote(
      entityType: 'customer',
      localId: customerId,
      globalId: globalCustomer,
      originDatabaseId: remoteDatabase,
    );
    expect(bound.globalId, globalCustomer);
    expect(replay.globalId, globalCustomer);
    expect(
      (await identities.findByGlobal(
        entityType: 'customer',
        globalId: globalCustomer,
      ))?.localId,
      customerId,
    );
  });

  test(
    'conflicting local or global binding is rejected without guessing',
    () async {
      const remoteDatabase = '44444444-4444-4444-8444-444444444444';
      const remoteBranch = '55555555-5555-4555-8555-555555555555';
      const globalSupplier = '66666666-6666-4666-8666-666666666666';
      await events.enrollSource(
        sourceDatabaseId: remoteDatabase,
        organizationId: organizationId,
        branchId: remoteBranch,
      );
      await identities.bindRemote(
        entityType: 'supplier',
        localId: supplierId,
        globalId: globalSupplier,
        originDatabaseId: remoteDatabase,
      );
      await expectLater(
        identities.bindRemote(
          entityType: 'supplier',
          localId: supplierId,
          globalId: '77777777-7777-4777-8777-777777777777',
          originDatabaseId: remoteDatabase,
        ),
        throwsA(_code('entity_identity_conflict')),
      );
    },
  );

  test('missing, unsupported, and mutated identities are rejected', () async {
    await expectLater(
      identities.getOrCreateLocal(entityType: 'product', localId: 999999),
      throwsA(_code('sync_entity_not_found')),
    );
    await expectLater(
      identities.getOrCreateLocal(entityType: 'warehouse', localId: 1),
      throwsA(_code('unsupported_entity_type')),
    );
    final identity = await identities.getOrCreateLocal(
      entityType: 'product',
      localId: productId,
    );
    await expectLater(
      db.customStatement(
        'UPDATE sync_entity_identities SET global_id=? WHERE entity_type=? AND local_id=?',
        ['88888888-8888-4888-8888-888888888888', 'product', productId],
      ),
      throwsA(anything),
    );
    await expectLater(
      db.customStatement(
        'DELETE FROM sync_entity_identities WHERE global_id=?',
        [identity.globalId],
      ),
      throwsA(anything),
    );
  });
}

Matcher _code(String code) =>
    isA<OfflineSyncException>().having((error) => error.code, 'code', code);
