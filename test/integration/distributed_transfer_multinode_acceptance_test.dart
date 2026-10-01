import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/database/migrations/offline_sync_ledger.dart';
import 'package:tapix/core/services/business/branch_currency_policy_store.dart';
import 'package:tapix/core/services/business/warehouse_operation_scope.dart';
import 'package:tapix/core/services/inventory/supplier_product_identity_service.dart';
import 'package:tapix/core/services/stock_service.dart';
import 'package:tapix/core/services/sync/branch_catalogue_sync_service.dart';
import 'package:tapix/core/services/sync/branch_operational_projection_service.dart';
import 'package:tapix/core/services/sync/offline_sync_event_store.dart';
import 'package:tapix/core/services/sync/sync_entity_identity_store.dart';
import 'package:tapix/core/services/sync/sync_inbound_projection_service.dart';
import 'package:tapix/features/business/data/distributed_transfer_dispatch_service.dart';
import 'package:tapix/features/business/data/distributed_transfer_receipt_service.dart';

const _uuid = Uuid();

void main() {
  final routes = <({String name, bool sourceWarehouse, bool targetWarehouse})>[
    (name: 'branch to branch', sourceWarehouse: false, targetWarehouse: false),
    (
      name: 'branch to warehouse',
      sourceWarehouse: false,
      targetWarehouse: true,
    ),
    (
      name: 'warehouse to branch',
      sourceWarehouse: true,
      targetWarehouse: false,
    ),
    (
      name: 'warehouse to warehouse',
      sourceWarehouse: true,
      targetWarehouse: true,
    ),
  ];

  for (final route in routes) {
    test('${route.name} completes across two independent ledgers', () async {
      final sourceDb = AppDatabase.connect(
        DatabaseConnection(NativeDatabase.memory()),
      );
      final targetDb = AppDatabase.connect(
        DatabaseConnection(NativeDatabase.memory()),
      );
      addTearDown(sourceDb.close);
      addTearDown(targetDb.close);
      await sourceDb.customSelect('SELECT 1').get();
      await targetDb.customSelect('SELECT 1').get();

      final sourceDefault = await WarehouseOperationScope.resolve(sourceDb);
      final organizationId = sourceDefault.organizationId;
      final targetDatabaseId = await targetDb
          .customSelect('SELECT database_id FROM business_contexts WHERE id=1')
          .map((row) => row.read<String>('database_id'))
          .getSingle();
      final routeKey = route.name.replaceAll(' ', '-');
      final targetBranchId = _stable('target-branch-$routeKey');
      final targetDefaultWarehouseId = _stable('target-default-$routeKey');
      await _adoptFreshNode(
        targetDb,
        organizationId: organizationId,
        branchId: targetBranchId,
        warehouseId: targetDefaultWarehouseId,
        branchName: 'Target ${route.name}',
      );
      final targetWarehouseId = route.targetWarehouse
          ? _stable('target-secondary-$routeKey')
          : targetDefaultWarehouseId;
      if (route.targetWarehouse) {
        await _addWarehouse(
          targetDb,
          organizationId: organizationId,
          branchId: targetBranchId,
          warehouseId: targetWarehouseId,
          code: 'TARGET-SECONDARY',
          name: 'Target secondary warehouse',
        );
      }

      final sourceWarehouseId = route.sourceWarehouse
          ? _stable('source-secondary-$routeKey')
          : sourceDefault.warehouseId;
      if (route.sourceWarehouse) {
        await _addWarehouse(
          sourceDb,
          organizationId: organizationId,
          branchId: sourceDefault.branchId,
          warehouseId: sourceWarehouseId,
          code: 'SOURCE-SECONDARY',
          name: 'Source secondary warehouse',
        );
      }
      final source = await WarehouseOperationScope.resolve(
        sourceDb,
        warehouseId: sourceWarehouseId,
      );
      final target = await WarehouseOperationScope.resolve(
        targetDb,
        warehouseId: targetWarehouseId,
      );

      await BranchCurrencyPolicyStore(sourceDb).bind('USD');
      await BranchCurrencyPolicyStore(targetDb).bind('USD');
      final sourceEvents = OfflineSyncEventStore(sourceDb);
      final targetEvents = OfflineSyncEventStore(targetDb);
      await sourceEvents.activateWriterRecording(
        enrollmentId: _stable('source-enrollment-$routeKey'),
      );
      await targetEvents.activateWriterRecording(
        enrollmentId: _stable('target-enrollment-$routeKey'),
      );
      await targetEvents.enrollSource(
        sourceDatabaseId: source.databaseId,
        organizationId: organizationId,
        branchId: source.branchId,
      );
      await sourceEvents.enrollSource(
        sourceDatabaseId: targetDatabaseId,
        organizationId: organizationId,
        branchId: targetBranchId,
      );
      await targetDb.customStatement(
        '''INSERT INTO app_settings(key,value) VALUES(?,?)
        ON CONFLICT(key) DO UPDATE SET value=excluded.value''',
        ['lan.branch_sync.coordinator_database_id.v1', source.databaseId],
      );

      await sourceDb.customStatement(
        '''INSERT INTO sync_branch_directory(
          branch_id,organization_id,code,name,writer_database_id,is_active)
          VALUES(?,?,?,?,?,1)''',
        [
          targetBranchId,
          organizationId,
          'TARGET',
          'Target branch',
          targetDatabaseId,
        ],
      );
      await sourceDb.customStatement(
        '''INSERT INTO sync_warehouse_directory(
          warehouse_id,organization_id,branch_id,code,name,is_active)
          VALUES(?,?,?,?,?,1)''',
        [
          targetWarehouseId,
          organizationId,
          targetBranchId,
          'TARGET-WH',
          'Target warehouse',
        ],
      );

      final currency = await (sourceDb.select(
        sourceDb.currencies,
      )..where((row) => row.code.equals('USD'))).getSingle();
      final sourceActor = await _actor(sourceDb, 'source-$routeKey');
      final targetActor = await _actor(targetDb, 'target-$routeKey');
      final supplierId = await sourceDb
          .into(sourceDb.suppliers)
          .insert(
            SuppliersCompanion.insert(
              name: 'Documented source supplier',
              productCode: const Value('DOC'),
              currencyId: currency.id,
              openingBalanceCents: Value(Decimal.fromInt(7700)),
              balanceCents: Value(Decimal.fromInt(7700)),
            ),
          );
      await sourceDb
          .into(sourceDb.customers)
          .insert(
            CustomersCompanion.insert(
              name: 'Unrelated customer',
              currencyId: currency.id,
              openingBalanceCents: Value(Decimal.fromInt(3300)),
              balanceCents: Value(Decimal.fromInt(3300)),
            ),
          );
      final productId = await sourceDb
          .into(sourceDb.products)
          .insert(
            ProductsCompanion.insert(
              name: 'Transferred documented item',
              sku: Value('TR-$routeKey'),
              currencyId: Value(currency.id),
              costCents: Decimal.fromInt(1000),
              priceCents: Decimal.fromInt(1600),
            ),
          );
      final variantId = await sourceDb
          .into(sourceDb.productVariants)
          .insert(
            ProductVariantsCompanion.insert(
              productId: productId,
              costCents: Decimal.fromInt(1000),
              priceCents: Decimal.fromInt(1600),
            ),
          );
      await sourceDb.customStatement(
        'INSERT INTO business_warehouse_stocks('
        'warehouse_id,variant_id,quantity,supplier_owned_quantity,'
        'unit_cost_cents) SELECT ?,?,0,0,0 WHERE NOT EXISTS('
        'SELECT 1 FROM business_warehouse_stocks WHERE warehouse_id=? '
        'AND variant_id=?)',
        [sourceWarehouseId, variantId, sourceWarehouseId, variantId],
      );
      final supplierIdentity = await SupplierProductIdentityService(sourceDb)
          .ensureIssued(
            supplierId: supplierId,
            productId: productId,
            variantId: variantId,
          );
      await StockService.adjustStock(
        sourceDb.productDao,
        productId: productId,
        variantId: variantId,
        quantity: 5,
        direction: StockDirection.increase,
        scope: source,
        origin: InventoryOriginIntent.keyed(
          'adjustment',
          'multinode-opening-$routeKey',
          supplierIdentityId: supplierIdentity.id,
        ),
      );
      await sourceDb.customStatement(
        'UPDATE business_warehouse_stocks SET unit_cost_cents=1000 '
        'WHERE warehouse_id=? AND variant_id=?',
        [sourceWarehouseId, variantId],
      );

      final targetCatalogue = BranchCatalogueSyncService(
        targetDb,
        targetEvents,
        SyncEntityIdentityStore(targetDb),
      );
      final targetInbound = SyncInboundProjectionService(
        targetDb,
        targetEvents,
        operationalProjector: BranchOperationalProjectionService(
          targetDb,
          catalogue: targetCatalogue,
          events: targetEvents,
        ).apply,
      );
      await BranchCatalogueSyncService(
        sourceDb,
        sourceEvents,
        SyncEntityIdentityStore(sourceDb),
      ).publishSnapshot();
      for (final event in await _outbox(sourceDb)) {
        expect(await targetInbound.apply(event), InboundSyncResult.applied);
      }
      expect(await targetCatalogue.hasCompleteSnapshot(), isTrue);

      final sourcePartiesBefore = await _partyBalances(sourceDb);
      final targetPartiesBefore = await _partyBalances(targetDb);
      final sourceArApBefore = await _accountBalances(sourceDb, {
        '1100',
        '2000',
      });
      final targetArApBefore = await _accountBalances(targetDb, {
        '1100',
        '2000',
      });
      final sourceInventoryBefore = await _accountBalances(sourceDb, {
        '1200',
        '1210',
      });
      final targetInventoryBefore = await _accountBalances(targetDb, {
        '1200',
        '1210',
      });

      final dispatches = DistributedTransferDispatchService(
        sourceDb,
        authorize: (from, to) async {
          expect(from, sourceWarehouseId);
          expect(to, targetWarehouseId);
          return sourceActor;
        },
        syncEvents: sourceEvents,
      );
      final draft = await dispatches.create(
        requestKey: _stable('create-$routeKey'),
        sourceWarehouseId: sourceWarehouseId,
        destinationWarehouseId: targetWarehouseId,
        lines: [
          DistributedTransferLineInput(
            productId: productId,
            variantId: variantId,
            quantity: 2,
            ownedQuantity: 2,
            consignmentQuantity: 0,
          ),
        ],
        notes: 'Acceptance ${route.name}',
      );
      await dispatches.dispatch(
        transferId: draft.transferId,
        requestKey: _stable('dispatch-$routeKey'),
        dispatchedAt: DateTime.utc(2026, 9, 30, 10),
      );
      expect(await _stock(sourceDb, sourceWarehouseId, variantId), 3);

      final dispatchEvent = (await _outbox(
        sourceDb,
        eventType: 'warehouse_transfer.dispatched.v1',
      )).single;
      expect(
        await targetInbound.apply(dispatchEvent),
        InboundSyncResult.applied,
      );
      expect(
        await targetInbound.apply(dispatchEvent),
        InboundSyncResult.duplicate,
      );

      final receiptService = DistributedTransferReceiptService(
        targetDb,
        authorizeWarehouse: (warehouse) async {
          expect(warehouse, targetWarehouseId);
          return targetActor;
        },
        syncEvents: targetEvents,
      );
      final pending = (await receiptService.pending(draft.transferId)).single;
      final receipt = await receiptService.receive(
        transferId: draft.transferId,
        requestKey: _stable('receive-$routeKey'),
        receivedAt: DateTime.utc(2026, 9, 30, 11),
        items: [
          DistributedTransferReceiptItemRequest(
            allocationId: pending.allocationId,
            acceptedQuantity: 2,
          ),
        ],
      );
      expect(receipt.completed, isTrue);
      // Local ids may coincide by chance, so resolve using the shared global id.
      final sourceVariantGlobal = await sourceDb
          .customSelect(
            "SELECT global_id FROM sync_entity_identities WHERE entity_type='product_variant' AND local_id=?",
            variables: [Variable.withInt(variantId)],
          )
          .map((row) => row.read<String>('global_id'))
          .getSingle();
      final resolvedTargetVariant = await targetDb
          .customSelect(
            "SELECT local_id FROM sync_entity_identities WHERE entity_type='product_variant' AND global_id=?",
            variables: [Variable.withString(sourceVariantGlobal)],
          )
          .map((row) => row.read<int>('local_id'))
          .getSingle();
      expect(
        await _stock(targetDb, targetWarehouseId, resolvedTargetVariant),
        2,
      );

      final receiptEvent = (await _outbox(
        targetDb,
        eventType: 'warehouse_transfer.received.v1',
      )).single;
      final sourceInbound = SyncInboundProjectionService(
        sourceDb,
        sourceEvents,
        operationalProjector: BranchOperationalProjectionService(
          sourceDb,
          events: sourceEvents,
        ).apply,
      );
      expect(
        await sourceInbound.apply(receiptEvent),
        InboundSyncResult.applied,
      );
      expect(
        await sourceInbound.apply(receiptEvent),
        InboundSyncResult.duplicate,
      );
      expect(
        (await dispatches.list({'completed'})).single.transferId,
        draft.transferId,
      );

      expect(await _partyBalances(sourceDb), sourcePartiesBefore);
      expect(await _partyBalances(targetDb), targetPartiesBefore);
      expect(
        await _accountBalances(sourceDb, {'1100', '2000'}),
        sourceArApBefore,
      );
      expect(
        await _accountBalances(targetDb, {'1100', '2000'}),
        targetArApBefore,
      );

      final sourceInventoryAfter = await _accountBalances(sourceDb, {
        '1200',
        '1210',
      });
      final targetInventoryAfter = await _accountBalances(targetDb, {
        '1200',
        '1210',
      });
      expect(
        sourceInventoryAfter['1200']! - sourceInventoryBefore['1200']!,
        -2000,
      );
      expect(
        sourceInventoryAfter['1210']! - sourceInventoryBefore['1210']!,
        2000,
      );
      expect(
        targetInventoryAfter['1200']! - targetInventoryBefore['1200']!,
        2000,
      );
      expect(
        targetInventoryAfter['1210']! - targetInventoryBefore['1210']!,
        -2000,
      );

      final origin = await targetDb
          .customSelect(
            'SELECT layers FROM inventory_origin_states WHERE warehouse_id=? AND variant_id=?',
            variables: [
              Variable.withString(targetWarehouseId),
              Variable.withInt(resolvedTargetVariant),
            ],
          )
          .map((row) => jsonDecode(row.read<String>('layers')) as List<dynamic>)
          .getSingle();
      final destinationIdentityId = (origin.single as Map)['i'] as int?;
      expect(destinationIdentityId, isNot(equals(null)));
      final destinationSupplier = await targetDb
          .customSelect(
            'SELECT s.name FROM supplier_product_identities i '
            'JOIN suppliers s ON s.id=i.supplier_id WHERE i.id=?',
            variables: [Variable.withInt(destinationIdentityId!)],
          )
          .map((row) => row.read<String>('name'))
          .getSingle();
      expect(destinationSupplier, 'Documented source supplier');

      expect(source.databaseId, isNot(targetDatabaseId));
      expect(source.branchId, isNot(target.branchId));
      expect(sourceWarehouseId, isNot(targetWarehouseId));
    });
  }
}

String _stable(String name) => _uuid.v5(Namespace.url.value, 'tapix:$name');

Future<void> _adoptFreshNode(
  AppDatabase db, {
  required String organizationId,
  required String branchId,
  required String warehouseId,
  required String branchName,
}) async {
  final current = await db
      .customSelect('SELECT * FROM business_contexts WHERE id=1')
      .getSingle();
  final oldOrganization = current.read<String>('organization_id');
  final oldBranch = current.read<String>('branch_id');
  final oldWarehouse = current.read<String>('warehouse_id');
  final databaseId = current.read<String>('database_id');
  await db.transaction(() async {
    await db.customStatement(
      'INSERT INTO business_organizations(id,name) VALUES(?,?)',
      [organizationId, 'Acceptance company'],
    );
    await db.customStatement(
      'INSERT INTO business_branches(id,organization_id,code,name,is_active) '
      'VALUES(?,?,?,?,1)',
      [branchId, organizationId, 'TARGET', branchName],
    );
    await db.customStatement(
      'INSERT INTO business_warehouses('
      'id,organization_id,branch_id,code,name,is_active) VALUES(?,?,?,?,?,1)',
      [
        warehouseId,
        organizationId,
        branchId,
        'TARGET-MAIN',
        '$branchName main',
      ],
    );
    await db.customStatement(
      'DROP TRIGGER IF EXISTS business_location_context_update',
    );
    await db.customStatement(
      'UPDATE business_contexts SET organization_id=?,branch_id=?,warehouse_id=? '
      'WHERE id=1 AND database_id=?',
      [organizationId, branchId, warehouseId, databaseId],
    );
    await db.customStatement('''
      CREATE TRIGGER business_location_context_update
      BEFORE UPDATE ON business_contexts
      WHEN (NEW.organization_id != OLD.organization_id
        OR NEW.branch_id != OLD.branch_id
        OR NEW.warehouse_id != OLD.warehouse_id
        OR NEW.database_id != OLD.database_id)
      BEGIN SELECT RAISE(ABORT,
        'Cannot reassign existing business documents'); END
    ''');
    await db.customStatement('DROP TRIGGER IF EXISTS trg_sync_local_update');
    await db.customStatement(
      'UPDATE sync_local_state SET organization_id=?,branch_id=? '
      'WHERE id=1 AND database_id=? AND next_sequence=1',
      [organizationId, branchId, databaseId],
    );
    await db.customStatement('DELETE FROM business_warehouses WHERE id=?', [
      oldWarehouse,
    ]);
    await db.customStatement('DELETE FROM business_branches WHERE id=?', [
      oldBranch,
    ]);
    await db.customStatement('DELETE FROM business_organizations WHERE id=?', [
      oldOrganization,
    ]);
  });
  await installOfflineSyncLedger(db);
}

Future<void> _addWarehouse(
  AppDatabase db, {
  required String organizationId,
  required String branchId,
  required String warehouseId,
  required String code,
  required String name,
}) => db.customStatement(
  'INSERT INTO business_warehouses('
  'id,organization_id,branch_id,code,name,is_active) VALUES(?,?,?,?,?,1)',
  [warehouseId, organizationId, branchId, code, name],
);

Future<int> _actor(AppDatabase db, String username) => db.customInsert(
  '''INSERT INTO users(username,password_hash,role,is_active,created_at,updated_at)
  VALUES(?,?,'owner',1,0,0)''',
  variables: [Variable.withString(username), Variable.withString('x')],
);

Future<List<SyncEventEnvelope>> _outbox(
  AppDatabase db, {
  String? eventType,
}) async {
  final rows = await db
      .customSelect(
        'SELECT * FROM sync_outbox_events '
        '${eventType == null ? '' : 'WHERE event_type=? '}ORDER BY local_sequence',
        variables: eventType == null
            ? const []
            : [Variable.withString(eventType)],
      )
      .get();
  return rows
      .map(
        (row) => SyncEventEnvelope(
          eventId: row.read<String>('event_id'),
          sourceDatabaseId: row.read<String>('source_database_id'),
          organizationId: row.read<String>('organization_id'),
          branchId: row.read<String>('branch_id'),
          sequence: row.read<int>('local_sequence'),
          eventType: row.read<String>('event_type'),
          aggregateType: row.read<String>('aggregate_type'),
          aggregateId: row.read<String>('aggregate_id'),
          contractVersion: row.read<int>('contract_version'),
          payload: (jsonDecode(row.read<String>('payload_json')) as Map).map(
            (key, value) => MapEntry(key.toString(), value as Object?),
          ),
          occurredAt: DateTime.parse(row.read<String>('occurred_at')).toUtc(),
          eventHash: row.read<String>('event_hash'),
        ),
      )
      .toList(growable: false);
}

Future<int> _stock(AppDatabase db, String warehouseId, int variantId) => db
    .customSelect(
      'SELECT quantity FROM business_warehouse_stocks '
      'WHERE warehouse_id=? AND variant_id=?',
      variables: [
        Variable.withString(warehouseId),
        Variable.withInt(variantId),
      ],
    )
    .map((row) => row.read<int>('quantity'))
    .getSingle();

Future<Map<String, int>> _partyBalances(AppDatabase db) async {
  final supplier = await db
      .customSelect('SELECT COALESCE(SUM(balance_cents),0) AS n FROM suppliers')
      .map((row) => row.read<int>('n'))
      .getSingle();
  final customer = await db
      .customSelect('SELECT COALESCE(SUM(balance_cents),0) AS n FROM customers')
      .map((row) => row.read<int>('n'))
      .getSingle();
  return {'supplier': supplier, 'customer': customer};
}

Future<Map<String, int>> _accountBalances(
  AppDatabase db,
  Set<String> codes,
) async {
  final result = <String, int>{};
  for (final code in codes) {
    result[code] = await db
        .customSelect(
          '''SELECT COALESCE(SUM(CASE WHEN j.status='posted'
            THEN l.debit_cents-l.credit_cents ELSE 0 END),0) AS n
          FROM accounts a LEFT JOIN journal_entry_lines l ON l.account_id=a.id
          LEFT JOIN journal_entries j ON j.id=l.journal_entry_id
          WHERE a.account_code=?''',
          variables: [Variable.withString(code)],
        )
        .map((row) => row.read<int>('n'))
        .getSingle();
  }
  return result;
}
