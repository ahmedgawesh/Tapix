import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/database/migrations/warehouse_transfer_provenance.dart';
import 'package:tapix/core/services/batch_service.dart';
import 'package:tapix/core/services/business/branch_consignment_policy_store.dart';
import 'package:tapix/core/services/business/branch_currency_policy_store.dart';
import 'package:tapix/core/services/business/warehouse_operation_scope.dart';
import 'package:tapix/core/services/business/warehouse_transfer_preflight.dart';
import 'package:tapix/core/services/sync/offline_sync_event_store.dart';
import 'package:tapix/features/auth/data/services/session_service.dart';
import 'package:tapix/features/business/data/warehouse_transfer_dispatch_service.dart';
import 'package:tapix/features/business/data/warehouse_transfer_repository.dart';
import 'package:tapix/features/business/data/warehouse_transfer_receipt_service.dart';
import 'package:tapix/features/business/data/warehouse_transfer_recall_service.dart';
import 'package:tapix/features/business/data/warehouse_transfer_reporting_service.dart';
import 'package:tapix/features/consignment/data/consignment_agreement_service.dart';
import 'package:tapix/features/consignment/data/consignment_entitlement.dart';
import 'package:tapix/features/consignment/data/consignment_module_service.dart';
import 'package:tapix/features/consignment/data/consignment_receipt_service.dart';

class _Session extends SessionService {
  _Session(this.userId);

  final int userId;

  @override
  Future<int?> getCurrentUserId() async => userId;
}

class _Fixture {
  const _Fixture({
    required this.db,
    required this.source,
    required this.destination,
    required this.currency,
    required this.user,
    required this.product,
    required this.variant,
    required this.preflight,
    required this.repository,
    required this.dispatch,
    required this.receipt,
    required this.recall,
  });

  final AppDatabase db;
  final WarehouseOperationScope source;
  final WarehouseOperationScope destination;
  final int currency;
  final int user;
  final int product;
  final int variant;
  final WarehouseTransferPreflight preflight;
  final WarehouseTransferRepository repository;
  final WarehouseTransferDispatchService dispatch;
  final WarehouseTransferReceiptService receipt;
  final WarehouseTransferRecallService recall;
}

Future<_Fixture> _fixture({
  bool withOpeningStock = true,
  bool withOnlineSync = true,
}) async {
  final db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
  final source = await WarehouseOperationScope.resolve(db);
  if (withOnlineSync) {
    await OfflineSyncEventStore(db).activateWriterRecording(
      enrollmentId: '10101010-1010-4010-8010-101010101010',
    );
  }
  final currency = (await (db.select(
    db.currencies,
  )..where((c) => c.code.equals('USD'))).getSingle()).id;
  final user = await db
      .into(db.users)
      .insert(
        UsersCompanion.insert(
          username: 'transfer-dispatch-owner',
          passwordHash: 'test',
          role: 'owner',
          createdAt: DateTime.utc(2026, 9, 24),
          updatedAt: DateTime.utc(2026, 9, 24),
        ),
      );
  final product = await db
      .into(db.products)
      .insert(
        ProductsCompanion.insert(
          name: 'Dispatch item',
          currencyId: Value(currency),
          stockQuantity: Value(withOpeningStock ? 5 : 0),
          costCents: Decimal.fromInt(1000),
          priceCents: Decimal.fromInt(1500),
        ),
      );
  final variant = await db
      .into(db.productVariants)
      .insert(
        ProductVariantsCompanion.insert(
          productId: product,
          stockQuantity: Value(withOpeningStock ? 5 : 0),
          costCents: Decimal.fromInt(1000),
          priceCents: Decimal.fromInt(1500),
        ),
      );
  const destinationId = '66666666-6666-4666-8666-666666666666';
  await db
      .into(db.businessWarehouses)
      .insert(
        BusinessWarehousesCompanion.insert(
          id: destinationId,
          organizationId: source.organizationId,
          branchId: source.branchId,
          code: 'DST',
          name: const Value('Destination'),
        ),
      );
  await db
      .into(db.businessWarehouseStocks)
      .insert(
        BusinessWarehouseStocksCompanion.insert(
          warehouseId: destinationId,
          variantId: variant,
          unitCostCents: const Value(0),
        ),
      );
  final destination = await WarehouseOperationScope.resolve(
    db,
    warehouseId: destinationId,
  );
  await BranchCurrencyPolicyStore(db).bind('USD');

  final preflight = WarehouseTransferPreflight(
    db,
    authorizeWarehouse: (_) async {},
  );
  Future<int> authorize(
    TransferDraftAction action,
    String from,
    String to,
  ) async {
    expect(from, source.warehouseId);
    expect(to, destination.warehouseId);
    return user;
  }

  final repository = WarehouseTransferRepository(
    db,
    preflight: preflight,
    authorize: authorize,
  );
  return _Fixture(
    db: db,
    source: source,
    destination: destination,
    currency: currency,
    user: user,
    product: product,
    variant: variant,
    preflight: preflight,
    repository: repository,
    dispatch: WarehouseTransferDispatchService(
      db,
      preflight: preflight,
      authorize: authorize,
    ),
    receipt: WarehouseTransferReceiptService(db, authorize: authorize),
    recall: WarehouseTransferRecallService(db, authorize: authorize),
  );
}

Future<WarehouseTransferDraft> _draft(
  _Fixture fixture, {
  int quantity = 2,
}) async {
  final preview = await fixture.preflight.preview(
    source: fixture.source,
    destination: fixture.destination,
    lines: [
      WarehouseTransferRequestLine(
        productId: fixture.product,
        variantId: fixture.variant,
        quantity: quantity,
      ),
    ],
  );
  return fixture.repository.create(
    requestKey: const Uuid().v4(),
    preview: preview,
  );
}

Future<int> _stock(
  AppDatabase db,
  String warehouse,
  int variant, {
  bool supplierOwned = false,
}) async {
  final row =
      await (db.select(db.businessWarehouseStocks)..where(
            (stock) =>
                stock.warehouseId.equals(warehouse) &
                stock.variantId.equals(variant),
          ))
          .getSingle();
  return supplierOwned ? row.supplierOwnedQuantity : row.quantity;
}

void main() {
  test(
    'single-branch and LAN-only operation does not accumulate cloud outbox',
    () async {
      final fixture = await _fixture(withOnlineSync: false);
      addTearDown(fixture.db.close);
      final draft = await _draft(fixture);
      await fixture.dispatch.dispatch(
        transferId: draft.header.id,
        requestKey: const Uuid().v4(),
      );
      expect(
        await fixture.db
            .customSelect('SELECT COUNT(*) AS c FROM sync_outbox_events')
            .map((row) => row.read<int>('c'))
            .getSingle(),
        0,
      );
    },
  );

  test(
    'dispatch atomically freezes WAC value and moves it to inventory in transit',
    () async {
      final fixture = await _fixture();
      addTearDown(fixture.db.close);
      final draft = await _draft(fixture);
      final key = const Uuid().v4();

      final posted = await fixture.dispatch.dispatch(
        transferId: draft.header.id,
        requestKey: key,
        dispatchedAt: DateTime.utc(2026, 9, 24, 12),
      );

      expect(posted.transfer.status, 'in_transit');
      expect(posted.dispatch.sealed, isTrue);
      expect(posted.dispatch.ownedValueCents, 2000);
      expect(posted.allocations, hasLength(1));
      expect(posted.allocations.single.ownerType, 'owned');
      expect(posted.allocations.single.quantity, 2);
      expect(
        await _stock(fixture.db, fixture.source.warehouseId, fixture.variant),
        3,
      );
      expect(
        await _stock(
          fixture.db,
          fixture.destination.warehouseId,
          fixture.variant,
        ),
        0,
      );

      final journal =
          await (fixture.db.select(fixture.db.journalEntries)..where(
                (entry) =>
                    entry.id.equals(posted.dispatch.journalEntryId!) &
                    entry.entryType.equals('warehouse_transfer_dispatch'),
              ))
              .getSingle();
      expect(journal.totalDebitCents.toBigInt().toInt(), 2000);
      final rows =
          await (fixture.db.select(fixture.db.journalEntryLines).join([
                innerJoin(
                  fixture.db.accounts,
                  fixture.db.accounts.id.equalsExp(
                    fixture.db.journalEntryLines.accountId,
                  ),
                ),
              ])..where(
                fixture.db.journalEntryLines.journalEntryId.equals(journal.id),
              ))
              .get();
      final amounts = {
        for (final row in rows)
          row.readTable(fixture.db.accounts).accountCode: (
            debit: row
                .readTable(fixture.db.journalEntryLines)
                .debitCents
                .toBigInt()
                .toInt(),
            credit: row
                .readTable(fixture.db.journalEntryLines)
                .creditCents
                .toBigInt()
                .toInt(),
          ),
      };
      expect(amounts['1210'], (debit: 2000, credit: 0));
      expect(amounts['1200'], (debit: 0, credit: 2000));

      final location =
          await (fixture.db.select(fixture.db.businessDocumentLocations)..where(
                (item) =>
                    item.sourceTable.equals('journal_entries') &
                    item.sourceId.equals(journal.id),
              ))
              .getSingle();
      expect(location.warehouseId, fixture.source.warehouseId);

      final replay = await fixture.dispatch.dispatch(
        transferId: draft.header.id,
        requestKey: key,
      );
      expect(replay.dispatch.id, posted.dispatch.id);
      expect(
        await fixture.db.select(fixture.db.warehouseTransferDispatches).get(),
        hasLength(1),
      );
      final outbox = await fixture.db
          .customSelect('SELECT * FROM sync_outbox_events')
          .getSingle();
      expect(
        outbox.read<String>('event_type'),
        'warehouse_transfer.dispatched.v1',
      );
      expect(outbox.read<String>('aggregate_id'), draft.header.id);
      final payload =
          jsonDecode(outbox.read<String>('payload_json'))
              as Map<String, dynamic>;
      expect(payload['sourceDatabaseId'], fixture.source.databaseId);
      expect(payload['currencyCode'], 'USD');
      expect(payload['ownedValueMinor'], 2000);
      final syncedAllocation = Map<String, dynamic>.from(
        (payload['allocations'] as List).single as Map,
      );
      expect(syncedAllocation['quantityScaled'], 2);
      expect(syncedAllocation['productGlobalId'], hasLength(36));
      expect(syncedAllocation['variantGlobalId'], hasLength(36));
      expect(syncedAllocation.containsKey('productId'), isFalse);
      final origin = Map<String, dynamic>.from(
        (syncedAllocation['originSlices'] as List).single as Map,
      );
      expect(origin['quantityScaled'], 2);
      expect(origin['originKind'], 'unknown');
      expect(origin['sourceQuality'], 'unverified');
    },
  );

  test(
    'partial then final WAC receipt clears in-transit value and records loss',
    () async {
      final fixture = await _fixture();
      addTearDown(fixture.db.close);
      final draft = await _draft(fixture, quantity: 5);
      final dispatchKey = const Uuid().v4();
      final dispatch = await fixture.dispatch.dispatch(
        transferId: draft.header.id,
        requestKey: dispatchKey,
      );
      final allocation = dispatch.allocations.single;
      final beforeReceipt = await fixture.receipt.pending(draft.header.id);
      expect(beforeReceipt, hasLength(1));
      expect(beforeReceipt.single.remainingQuantity, 5);
      expect(beforeReceipt.single.productName, 'Dispatch item');
      final firstKey = const Uuid().v4();

      final first = await fixture.receipt.receive(
        transferId: draft.header.id,
        requestKey: firstKey,
        items: [
          WarehouseTransferReceiptRequestItem(
            allocationId: allocation.id,
            acceptedQuantity: 2,
          ),
        ],
      );

      expect(first.transfer.status, 'partially_received');
      expect(first.receipt.acceptedOwnedValueCents, 2000);
      expect(first.receipt.varianceOwnedValueCents, 0);
      expect(
        (await fixture.receipt.pending(
          draft.header.id,
        )).single.remainingQuantity,
        3,
      );
      expect(
        await _stock(
          fixture.db,
          fixture.destination.warehouseId,
          fixture.variant,
        ),
        2,
      );
      final replay = await fixture.receipt.receive(
        transferId: draft.header.id,
        requestKey: firstKey,
        items: [
          WarehouseTransferReceiptRequestItem(
            allocationId: allocation.id,
            acceptedQuantity: 2,
          ),
        ],
      );
      expect(replay.receipt.id, first.receipt.id);

      final finalReceipt = await fixture.receipt.receive(
        transferId: draft.header.id,
        requestKey: const Uuid().v4(),
        notes: 'One unit was missing on arrival',
        items: [
          WarehouseTransferReceiptRequestItem(
            allocationId: allocation.id,
            acceptedQuantity: 2,
            lostQuantity: 1,
          ),
        ],
      );

      expect(finalReceipt.transfer.status, 'completed');
      final lateDispatchReplay = await fixture.dispatch.dispatch(
        transferId: draft.header.id,
        requestKey: dispatchKey,
      );
      expect(lateDispatchReplay.dispatch.id, dispatch.dispatch.id);
      final lateReceiptReplay = await fixture.receipt.receive(
        transferId: draft.header.id,
        requestKey: firstKey,
        items: [
          WarehouseTransferReceiptRequestItem(
            allocationId: allocation.id,
            acceptedQuantity: 2,
          ),
        ],
      );
      expect(lateReceiptReplay.receipt.id, first.receipt.id);
      expect(finalReceipt.receipt.acceptedOwnedValueCents, 2000);
      expect(finalReceipt.receipt.varianceOwnedValueCents, 1000);
      expect(
        await _stock(
          fixture.db,
          fixture.destination.warehouseId,
          fixture.variant,
        ),
        4,
      );
      final balances = {
        for (final account
            in await fixture.db.select(fixture.db.accounts).get())
          account.accountCode: account.balanceCents.toBigInt().toInt(),
      };
      expect(balances['1210'], 0);
      expect(balances['1200'], -1000);
      expect(balances['5800'], 1000);
      final receiptJournalLocation =
          await (fixture.db.select(fixture.db.businessDocumentLocations)..where(
                (location) =>
                    location.sourceTable.equals('journal_entries') &
                    location.sourceId.equals(
                      finalReceipt.receipt.journalEntryId!,
                    ),
              ))
              .getSingle();
      expect(
        receiptJournalLocation.warehouseId,
        fixture.destination.warehouseId,
      );
      expect(
        await fixture.db.select(fixture.db.warehouseTransferEvents).get(),
        hasLength(3),
      );
      final syncRows = await fixture.db
          .customSelect(
            'SELECT event_type,payload_json FROM sync_outbox_events '
            'ORDER BY local_sequence',
          )
          .get();
      expect(syncRows.map((row) => row.read<String>('event_type')), [
        'warehouse_transfer.dispatched.v1',
        'warehouse_transfer.received.v1',
        'warehouse_transfer.received.v1',
      ]);
      final receiptPayloads = syncRows
          .skip(1)
          .map(
            (row) =>
                jsonDecode(row.read<String>('payload_json'))
                    as Map<String, dynamic>,
          )
          .toList(growable: false);
      expect(receiptPayloads.first['completedTransfer'], isFalse);
      expect(receiptPayloads.last['completedTransfer'], isTrue);
      expect(receiptPayloads.last['acceptedOwnedValueMinor'], 2000);
      expect(receiptPayloads.last['varianceOwnedValueMinor'], 1000);
      final finalItem = Map<String, dynamic>.from(
        (receiptPayloads.last['items'] as List).single as Map,
      );
      expect(finalItem['acceptedQuantityScaled'], 2);
      expect(finalItem['lostQuantityScaled'], 1);
    },
  );

  test(
    'partial WAC receipt then recall clears only the remaining transit',
    () async {
      final fixture = await _fixture();
      addTearDown(fixture.db.close);
      final draft = await _draft(fixture, quantity: 5);
      final dispatch = await fixture.dispatch.dispatch(
        transferId: draft.header.id,
        requestKey: const Uuid().v4(),
        dispatchedAt: DateTime.utc(2026, 9, 24, 9),
      );
      final receiptKey = const Uuid().v4();
      final partialReceipt = await fixture.receipt.receive(
        transferId: draft.header.id,
        requestKey: receiptKey,
        receivedAt: DateTime.utc(2026, 9, 24, 10),
        items: [
          WarehouseTransferReceiptRequestItem(
            allocationId: dispatch.allocations.single.id,
            acceptedQuantity: 2,
          ),
        ],
      );
      final key = const Uuid().v4();

      final recalled = await fixture.recall.recall(
        transferId: draft.header.id,
        requestKey: key,
        reason: 'Vehicle returned to source',
        recalledAt: DateTime.utc(2026, 9, 24, 11),
      );

      expect(recalled.transfer.status, 'cancelled');
      expect(recalled.items.single.quantity, 3);
      expect(recalled.recall.ownedValueCents, 3000);
      expect(
        await _stock(fixture.db, fixture.source.warehouseId, fixture.variant),
        3,
      );
      expect(
        await _stock(
          fixture.db,
          fixture.destination.warehouseId,
          fixture.variant,
        ),
        2,
      );
      final balances = {
        for (final account
            in await fixture.db.select(fixture.db.accounts).get())
          account.accountCode: account.balanceCents.toBigInt().toInt(),
      };
      expect(balances['1210'], 0);
      expect(balances['1200'], 0);
      final location =
          await (fixture.db.select(fixture.db.businessDocumentLocations)..where(
                (row) =>
                    row.sourceTable.equals('journal_entries') &
                    row.sourceId.equals(recalled.recall.journalEntryId!),
              ))
              .getSingle();
      expect(location.warehouseId, fixture.source.warehouseId);
      final replay = await fixture.recall.recall(
        transferId: draft.header.id,
        requestKey: key,
        reason: 'Vehicle returned to source',
      );
      expect(replay.recall.id, recalled.recall.id);
      final receiptReplay = await fixture.receipt.receive(
        transferId: draft.header.id,
        requestKey: receiptKey,
        items: [
          WarehouseTransferReceiptRequestItem(
            allocationId: dispatch.allocations.single.id,
            acceptedQuantity: 2,
          ),
        ],
      );
      expect(receiptReplay.receipt.id, partialReceipt.receipt.id);
      final report =
          await WarehouseTransferReportingService(
            fixture.db,
            authorizeWarehouse: (warehouseId) async {
              expect(warehouseId, fixture.source.warehouseId);
            },
          ).report(
            warehouseId: fixture.source.warehouseId,
            from: DateTime.utc(2026, 9, 23),
            toExclusive: DateTime.utc(2026, 9, 26),
          );
      expect(report.transferCount, 1);
      expect(report.rows.single.acceptedQuantity, 2);
      expect(report.rows.single.recalledQuantity, 3);
      expect(report.rows.single.inTransitQuantity, 0);
      expect(report.rows.single.sources.single.quality, 'unknown');
      final syncRows = await fixture.db
          .customSelect(
            'SELECT event_type,payload_json FROM sync_outbox_events '
            'ORDER BY local_sequence',
          )
          .get();
      expect(syncRows.map((row) => row.read<String>('event_type')), [
        'warehouse_transfer.dispatched.v1',
        'warehouse_transfer.received.v1',
        'warehouse_transfer.recalled.v1',
      ]);
      final recallPayload =
          jsonDecode(syncRows.last.read<String>('payload_json'))
              as Map<String, dynamic>;
      expect(recallPayload['ownedValueMinor'], 3000);
      expect(recallPayload['reason'], 'Vehicle returned to source');
      final recallItem = Map<String, dynamic>.from(
        (recallPayload['items'] as List).single as Map,
      );
      expect(recallItem['quantityScaled'], 3);
      expect(recallItem['valueMinor'], 3000);
    },
  );

  test(
    'failure while sealing recall rolls stock accounting and document back',
    () async {
      final fixture = await _fixture();
      addTearDown(fixture.db.close);
      final draft = await _draft(fixture);
      await fixture.dispatch.dispatch(
        transferId: draft.header.id,
        requestKey: const Uuid().v4(),
      );
      await fixture.db.customStatement(
        '''CREATE TRIGGER fail_recall_seal BEFORE UPDATE OF sealed
        ON warehouse_transfer_recalls WHEN NEW.sealed=1
        BEGIN SELECT RAISE(ABORT,'injected'); END''',
      );

      await expectLater(
        fixture.recall.recall(
          transferId: draft.header.id,
          requestKey: const Uuid().v4(),
          reason: 'Injected rollback check',
        ),
        throwsA(anything),
      );

      expect(
        await _stock(fixture.db, fixture.source.warehouseId, fixture.variant),
        3,
      );
      expect(
        await fixture.db.select(fixture.db.warehouseTransferRecalls).get(),
        isEmpty,
      );
      expect(
        await fixture.db.select(fixture.db.warehouseTransferRecallItems).get(),
        isEmpty,
      );
      expect(
        (await fixture.repository.get(draft.header.id)).header.status,
        'in_transit',
      );
      expect(
        await fixture.db.select(fixture.db.journalEntries).get(),
        hasLength(1),
      );
      final balances = {
        for (final account
            in await fixture.db.select(fixture.db.accounts).get())
          account.accountCode: account.balanceCents.toBigInt().toInt(),
      };
      expect(balances['1210'], 2000);
      expect(balances['1200'], -2000);
    },
  );

  test(
    'failure after stock and journal work rolls the whole dispatch back',
    () async {
      final fixture = await _fixture();
      addTearDown(fixture.db.close);
      final draft = await _draft(fixture);
      final beforeAccounts = {
        for (final account
            in await fixture.db.select(fixture.db.accounts).get())
          account.accountCode: account.balanceCents,
      };
      await fixture.db.customStatement(
        '''CREATE TRIGGER fail_dispatch_event BEFORE INSERT ON warehouse_transfer_events
        WHEN NEW.kind='dispatched' BEGIN SELECT RAISE(ABORT,'injected'); END''',
      );

      await expectLater(
        fixture.dispatch.dispatch(
          transferId: draft.header.id,
          requestKey: const Uuid().v4(),
        ),
        throwsA(anything),
      );

      expect(
        await _stock(fixture.db, fixture.source.warehouseId, fixture.variant),
        5,
      );
      expect(
        await fixture.db.select(fixture.db.warehouseTransferDispatches).get(),
        isEmpty,
      );
      expect(
        await fixture.db.select(fixture.db.warehouseTransferAllocations).get(),
        isEmpty,
      );
      expect(await fixture.db.select(fixture.db.journalEntries).get(), isEmpty);
      final afterAccounts = {
        for (final account
            in await fixture.db.select(fixture.db.accounts).get())
          account.accountCode: account.balanceCents,
      };
      expect(afterAccounts, beforeAccounts);
      expect(
        (await fixture.repository.get(draft.header.id)).header.status,
        'draft',
      );
    },
  );

  test(
    'failure while finalizing receipt rolls stock and accounting back',
    () async {
      final fixture = await _fixture();
      addTearDown(fixture.db.close);
      final draft = await _draft(fixture);
      final dispatch = await fixture.dispatch.dispatch(
        transferId: draft.header.id,
        requestKey: const Uuid().v4(),
      );
      final allocation = dispatch.allocations.single;
      await fixture.db.customStatement(
        """CREATE TRIGGER fail_receipt_completion BEFORE INSERT ON warehouse_transfer_events
        WHEN NEW.kind='completed' BEGIN SELECT RAISE(ABORT,'injected'); END""",
      );

      await expectLater(
        fixture.receipt.receive(
          transferId: draft.header.id,
          requestKey: const Uuid().v4(),
          items: [
            WarehouseTransferReceiptRequestItem(
              allocationId: allocation.id,
              acceptedQuantity: allocation.quantity,
            ),
          ],
        ),
        throwsA(anything),
      );

      expect(
        await _stock(
          fixture.db,
          fixture.destination.warehouseId,
          fixture.variant,
        ),
        0,
      );
      expect(
        await fixture.db.select(fixture.db.warehouseTransferReceipts).get(),
        isEmpty,
      );
      expect(
        await fixture.db.select(fixture.db.warehouseTransferReceiptItems).get(),
        isEmpty,
      );
      expect(
        (await fixture.repository.get(draft.header.id)).header.status,
        'in_transit',
      );
      expect(
        await fixture.db.select(fixture.db.warehouseTransferEvents).get(),
        hasLength(2),
      );
      expect(
        await fixture.db.select(fixture.db.journalEntries).get(),
        hasLength(1),
      );
      final balances = {
        for (final account
            in await fixture.db.select(fixture.db.accounts).get())
          account.accountCode: account.balanceCents.toBigInt().toInt(),
      };
      expect(balances['1210'], 2000);
      expect(balances['1200'], -2000);
      expect(balances['5800'], 0);
    },
  );

  test(
    'FIFO dispatch freezes FEFO batch slices and their carrying values',
    () async {
      final fixture = await _fixture();
      addTearDown(fixture.db.close);
      await (fixture.db.update(
        fixture.db.products,
      )..where((product) => product.id.equals(fixture.product))).write(
        const ProductsCompanion(
          costingMethod: Value('fifo'),
          inventoryTrackingType: Value('batch_expiry'),
        ),
      );
      final firstBatch = await fixture.db
          .into(fixture.db.productBatches)
          .insert(
            ProductBatchesCompanion.insert(
              warehouseId: Value(fixture.source.warehouseId),
              productId: fixture.product,
              variantId: Value(fixture.variant),
              batchNumber: 'TRANSFER-FIFO-1',
              manufacturerLotNumber: const Value('LOT-EARLY'),
              source: const Value('opening'),
              receivedDate: Value(DateTime.utc(2026, 9, 1)),
              expiryDate: Value(DateTime.utc(2027, 1, 1)),
              receivedQuantity: 1,
              remainingQuantity: 1,
              unitCostCents: Decimal.fromInt(700),
            ),
          );
      final secondBatch = await fixture.db
          .into(fixture.db.productBatches)
          .insert(
            ProductBatchesCompanion.insert(
              warehouseId: Value(fixture.source.warehouseId),
              productId: fixture.product,
              variantId: Value(fixture.variant),
              batchNumber: 'TRANSFER-FIFO-2',
              manufacturerLotNumber: const Value('LOT-LATER'),
              source: const Value('opening'),
              receivedDate: Value(DateTime.utc(2026, 9, 2)),
              expiryDate: Value(DateTime.utc(2028, 1, 1)),
              receivedQuantity: 4,
              remainingQuantity: 4,
              unitCostCents: Decimal.fromInt(1100),
            ),
          );
      final draft = await _draft(fixture);

      final posted = await fixture.dispatch.dispatch(
        transferId: draft.header.id,
        requestKey: const Uuid().v4(),
      );

      expect(posted.dispatch.ownedValueCents, 1800);
      expect(posted.allocations, hasLength(2));
      expect(posted.allocations.map((allocation) => allocation.sourceBatchId), [
        firstBatch,
        secondBatch,
      ]);
      expect(posted.allocations.map((allocation) => allocation.quantity), [
        1,
        1,
      ]);
      expect(posted.allocations.map((allocation) => allocation.valueCents), [
        700,
        1100,
      ]);
      expect(
        posted.allocations.map(
          (allocation) => allocation.manufacturerLotNumber,
        ),
        ['LOT-EARLY', 'LOT-LATER'],
      );
      final fifoEvent = await fixture.db
          .customSelect('SELECT payload_json FROM sync_outbox_events')
          .getSingle();
      final fifoPayload =
          jsonDecode(fifoEvent.read<String>('payload_json'))
              as Map<String, dynamic>;
      final syncedBatches = (fifoPayload['allocations'] as List)
          .map(
            (raw) =>
                Map<String, dynamic>.from((raw as Map)['sourceBatch'] as Map),
          )
          .toList(growable: false);
      expect(
        syncedBatches.map((batch) => batch['globalId']),
        everyElement(hasLength(36)),
      );
      expect(
        syncedBatches.map((batch) => batch['globalId']).toSet(),
        hasLength(2),
      );
      expect(
        await fixture.db
            .customSelect(
              'SELECT COUNT(*) AS c FROM sync_inventory_layer_identities',
            )
            .map((row) => row.read<int>('c'))
            .getSingle(),
        2,
      );
      final remaining = {
        for (final batch
            in await fixture.db.select(fixture.db.productBatches).get())
          batch.id: batch.remainingQuantity,
      };
      expect(remaining[firstBatch], 0);
      expect(remaining[secondBatch], 3);
      expect(
        await _stock(fixture.db, fixture.source.warehouseId, fixture.variant),
        3,
      );

      final receipt = await fixture.receipt.receive(
        transferId: draft.header.id,
        requestKey: const Uuid().v4(),
        items: [
          for (final allocation in posted.allocations)
            WarehouseTransferReceiptRequestItem(
              allocationId: allocation.id,
              acceptedQuantity: allocation.quantity,
            ),
        ],
      );
      expect(receipt.transfer.status, 'completed');
      final destinationBatches =
          await (fixture.db.select(fixture.db.productBatches)..where(
                (batch) =>
                    batch.warehouseId.equals(fixture.destination.warehouseId) &
                    batch.source.equals('warehouse_transfer'),
              ))
              .get();
      expect(destinationBatches, hasLength(2));
      expect(destinationBatches.map((batch) => batch.originBatchId).toSet(), {
        firstBatch,
        secondBatch,
      });
      expect(
        destinationBatches.map((batch) => batch.transferAllocationId).toSet(),
        posted.allocations.map((allocation) => allocation.id).toSet(),
      );
      expect(
        destinationBatches.map((batch) => batch.manufacturerLotNumber),
        unorderedEquals(['LOT-EARLY', 'LOT-LATER']),
      );
      expect(
        await _stock(
          fixture.db,
          fixture.destination.warehouseId,
          fixture.variant,
        ),
        2,
      );
    },
  );

  test(
    'transfer batch provenance rejects raw SQL tampering but keeps expiry correction usable',
    () async {
      final fixture = await _fixture();
      addTearDown(fixture.db.close);
      await installWarehouseTransferProvenanceGuards(fixture.db);
      await (fixture.db.update(
        fixture.db.products,
      )..where((product) => product.id.equals(fixture.product))).write(
        const ProductsCompanion(
          costingMethod: Value('fifo'),
          inventoryTrackingType: Value('batch_expiry'),
        ),
      );
      final sourceBatch = await fixture.db
          .into(fixture.db.productBatches)
          .insert(
            ProductBatchesCompanion.insert(
              warehouseId: Value(fixture.source.warehouseId),
              productId: fixture.product,
              variantId: Value(fixture.variant),
              batchNumber: 'PROVENANCE-SOURCE',
              manufacturerLotNumber: const Value('PROVENANCE-LOT'),
              source: const Value('opening'),
              receivedDate: Value(DateTime.utc(2026, 9, 1)),
              expiryDate: Value(DateTime.utc(2027, 1, 1)),
              receivedQuantity: 5,
              remainingQuantity: 5,
              unitCostCents: Decimal.fromInt(1000),
            ),
          );
      final draft = await _draft(fixture);
      final dispatch = await fixture.dispatch.dispatch(
        transferId: draft.header.id,
        requestKey: const Uuid().v4(),
      );
      final allocation = dispatch.allocations.single;
      await fixture.receipt.receive(
        transferId: draft.header.id,
        requestKey: const Uuid().v4(),
        items: [
          WarehouseTransferReceiptRequestItem(
            allocationId: allocation.id,
            acceptedQuantity: allocation.quantity,
          ),
        ],
      );
      final destinationBatch =
          await (fixture.db.select(fixture.db.productBatches)..where(
                (batch) =>
                    batch.warehouseId.equals(fixture.destination.warehouseId) &
                    batch.transferAllocationId.equals(allocation.id),
              ))
              .getSingle();

      final correctedExpiry = DateTime.utc(2027, 2, 1);
      await BatchService.updateExpiryDate(
        fixture.db.productDao,
        batchId: destinationBatch.id,
        newExpiry: correctedExpiry,
        scope: fixture.destination,
      );
      expect(
        (await (fixture.db.select(fixture.db.productBatches)
                  ..where((batch) => batch.id.equals(destinationBatch.id)))
                .getSingle())
            .expiryDate,
        correctedExpiry,
      );

      final batchTampering = <(String, List<Object?>)>[
        (
          "UPDATE product_batches SET source='opening' WHERE id=?",
          [destinationBatch.id],
        ),
        (
          'UPDATE product_batches SET origin_batch_id=NULL WHERE id=?',
          [destinationBatch.id],
        ),
        (
          'UPDATE product_batches SET transfer_allocation_id=NULL WHERE id=?',
          [destinationBatch.id],
        ),
        (
          'UPDATE product_batches SET received_quantity=3 WHERE id=?',
          [destinationBatch.id],
        ),
        (
          'UPDATE product_batches SET unit_cost_cents=999 WHERE id=?',
          [destinationBatch.id],
        ),
        (
          "UPDATE product_batches SET batch_number='TAMPERED' WHERE id=?",
          [destinationBatch.id],
        ),
        (
          "UPDATE product_batches SET manufacturer_lot_number='TAMPERED' WHERE id=?",
          [destinationBatch.id],
        ),
        (
          'UPDATE product_batches SET received_date=? WHERE id=?',
          [DateTime.utc(2030).toIso8601String(), destinationBatch.id],
        ),
        (
          'UPDATE product_batches SET transfer_allocation_id=? WHERE id=?',
          [allocation.id, sourceBatch],
        ),
        (
          'INSERT OR REPLACE INTO product_batches '
              'SELECT * FROM product_batches WHERE id=?',
          [destinationBatch.id],
        ),
        ('DELETE FROM product_batches WHERE id=?', [destinationBatch.id]),
      ];
      for (final attempt in batchTampering) {
        await expectLater(
          fixture.db.customStatement(attempt.$1, attempt.$2),
          throwsA(anything),
          reason: attempt.$1,
        );
      }

      final transferConsumption =
          await (fixture.db.select(
                fixture.db.batchConsumptions,
              )..where((row) => row.transferAllocationId.equals(allocation.id)))
              .getSingle();
      for (final attempt in <(String, List<Object?>)>[
        (
          'UPDATE batch_consumptions SET quantity=1 WHERE id=?',
          [transferConsumption.id],
        ),
        (
          'UPDATE batch_consumptions SET transfer_allocation_id=NULL WHERE id=?',
          [transferConsumption.id],
        ),
        (
          'INSERT OR REPLACE INTO batch_consumptions '
              'SELECT * FROM batch_consumptions WHERE id=?',
          [transferConsumption.id],
        ),
        ('DELETE FROM batch_consumptions WHERE id=?', [transferConsumption.id]),
      ]) {
        await expectLater(
          fixture.db.customStatement(attempt.$1, attempt.$2),
          throwsA(anything),
          reason: attempt.$1,
        );
      }

      final preserved = await (fixture.db.select(
        fixture.db.productBatches,
      )..where((batch) => batch.id.equals(destinationBatch.id))).getSingle();
      expect(preserved.source, 'warehouse_transfer');
      expect(preserved.originBatchId, sourceBatch);
      expect(preserved.transferAllocationId, allocation.id);
      expect(preserved.receivedQuantity, 2);
      expect(preserved.unitCostCents.toBigInt().toInt(), 1000);
      expect(
        await fixture.db.select(fixture.db.batchConsumptions).get(),
        contains(transferConsumption),
      );
    },
  );

  test(
    'FIFO recall restores exact source lots and allocation ledger',
    () async {
      final fixture = await _fixture();
      addTearDown(fixture.db.close);
      await (fixture.db.update(
        fixture.db.products,
      )..where((product) => product.id.equals(fixture.product))).write(
        const ProductsCompanion(
          costingMethod: Value('fifo'),
          inventoryTrackingType: Value('batch_expiry'),
        ),
      );
      final firstBatch = await fixture.db
          .into(fixture.db.productBatches)
          .insert(
            ProductBatchesCompanion.insert(
              warehouseId: Value(fixture.source.warehouseId),
              productId: fixture.product,
              variantId: Value(fixture.variant),
              batchNumber: 'RECALL-FIFO-1',
              manufacturerLotNumber: const Value('RECALL-EARLY'),
              source: const Value('opening'),
              receivedDate: Value(DateTime.utc(2026, 9, 1)),
              expiryDate: Value(DateTime.utc(2027, 1, 1)),
              receivedQuantity: 1,
              remainingQuantity: 1,
              unitCostCents: Decimal.fromInt(700),
            ),
          );
      final secondBatch = await fixture.db
          .into(fixture.db.productBatches)
          .insert(
            ProductBatchesCompanion.insert(
              warehouseId: Value(fixture.source.warehouseId),
              productId: fixture.product,
              variantId: Value(fixture.variant),
              batchNumber: 'RECALL-FIFO-2',
              manufacturerLotNumber: const Value('RECALL-LATER'),
              source: const Value('opening'),
              receivedDate: Value(DateTime.utc(2026, 9, 2)),
              expiryDate: Value(DateTime.utc(2028, 1, 1)),
              receivedQuantity: 4,
              remainingQuantity: 4,
              unitCostCents: Decimal.fromInt(1100),
            ),
          );
      final draft = await _draft(fixture);
      final dispatch = await fixture.dispatch.dispatch(
        transferId: draft.header.id,
        requestKey: const Uuid().v4(),
      );

      final recalled = await fixture.recall.recall(
        transferId: draft.header.id,
        requestKey: const Uuid().v4(),
        reason: 'Truck returned before delivery',
      );

      expect(recalled.transfer.status, 'cancelled');
      final restored = {
        for (final batch
            in await fixture.db.select(fixture.db.productBatches).get())
          batch.id: batch.remainingQuantity,
      };
      expect(restored[firstBatch], 1);
      expect(restored[secondBatch], 4);
      expect(
        await _stock(fixture.db, fixture.source.warehouseId, fixture.variant),
        5,
      );
      final ledger = await fixture.db
          .select(fixture.db.batchConsumptions)
          .get();
      for (final allocation in dispatch.allocations) {
        final linked = ledger
            .where((row) => row.transferAllocationId == allocation.id)
            .toList();
        expect(linked, hasLength(2));
        expect(
          linked.map((row) => row.direction),
          unorderedEquals(['out', 'in']),
        );
        expect(
          linked.map((row) => row.quantity),
          everyElement(allocation.quantity),
        );
        expect(
          linked.map((row) => row.unitCostCents.toBigInt().toInt()),
          everyElement(allocation.unitCostCents),
        );
      }
      final balances = {
        for (final account
            in await fixture.db.select(fixture.db.accounts).get())
          account.accountCode: account.balanceCents.toBigInt().toInt(),
      };
      expect(balances['1210'], 0);
      expect(balances['1200'], 0);
    },
  );

  test(
    'consignment dispatch moves custody quantity without enterprise GL value',
    () async {
      final fixture = await _fixture(withOpeningStock: false);
      addTearDown(fixture.db.close);

      final module = ConsignmentModuleService(
        fixture.db,
        _Session(fixture.user),
        const GrantedConsignmentEntitlement(),
        BranchConsignmentPolicyStore(fixture.db),
        isRemoteClient: () => false,
      );
      await module.initialize();
      await module.setEnabled(enabled: true, reason: 'transfer dispatch test');
      final agreements = ConsignmentAgreementService(fixture.db, module);
      final agreement = await agreements.createDraft(
        supplierId: await fixture.db
            .into(fixture.db.suppliers)
            .insert(
              SuppliersCompanion.insert(
                name: 'Consignment transfer supplier',
                currencyId: fixture.currency,
              ),
            ),
        currencyId: fixture.currency,
        agreementNumber: 'CON-TRANSFER',
        effectiveFrom: DateTime.utc(2026, 9, 1),
        terms: [
          ConsignmentAgreementTermInput.fixedCost(
            productId: fixture.product,
            variantId: fixture.variant,
            amountCents: 900,
          ),
        ],
      );
      await agreements.activate(agreement.id);
      final supplier = agreement.supplierId;
      final receipts = ConsignmentReceiptService(fixture.db, module);
      final receipt = await receipts.createDraft(
        requestKey: const Uuid().v4(),
        receiptNumber: 'CR-TRANSFER',
        warehouseId: fixture.source.warehouseId,
        supplierId: supplier,
        agreementId: agreement.id,
        currencyId: fixture.currency,
        receivedAt: DateTime.utc(2026, 9, 24),
        lines: [
          ConsignmentReceiptLineInput(
            productId: fixture.product,
            variantId: fixture.variant,
            quantity: 5,
          ),
        ],
      );
      await receipts.post(receiptId: receipt.id, requestKey: const Uuid().v4());
      final layer = await fixture.db
          .select(fixture.db.consignmentInventoryLayers)
          .getSingle();
      final draft = await _draft(fixture, quantity: 3);

      final posted = await fixture.dispatch.dispatch(
        transferId: draft.header.id,
        requestKey: const Uuid().v4(),
        dispatchedAt: DateTime.utc(2026, 9, 24, 9),
      );

      expect(posted.dispatch.ownedValueCents, 0);
      expect(posted.dispatch.journalEntryId, isNull);
      expect(posted.allocations.single.ownerType, 'consignment');
      expect(posted.allocations.single.sourceConsignmentLayerId, layer.id);
      expect(posted.allocations.single.supplierId, supplier);
      final consignmentEvent = await fixture.db
          .customSelect('SELECT payload_json FROM sync_outbox_events')
          .getSingle();
      final consignmentPayload =
          jsonDecode(consignmentEvent.read<String>('payload_json'))
              as Map<String, dynamic>;
      final syncedConsignment = Map<String, dynamic>.from(
        (consignmentPayload['allocations'] as List).single as Map,
      );
      expect(syncedConsignment['ownerType'], 'consignment');
      expect(syncedConsignment['supplierGlobalId'], hasLength(36));
      expect(syncedConsignment['consignmentAgreementId'], agreement.id);
      expect(syncedConsignment['sourceConsignmentLayerId'], layer.id);
      expect(
        await _stock(fixture.db, fixture.source.warehouseId, fixture.variant),
        2,
      );
      expect(
        await _stock(
          fixture.db,
          fixture.source.warehouseId,
          fixture.variant,
          supplierOwned: true,
        ),
        2,
      );
      expect(
        (await fixture.db
                .select(fixture.db.consignmentInventoryLayers)
                .getSingle())
            .remainingQuantity,
        2,
      );
      expect(await fixture.db.select(fixture.db.journalEntries).get(), isEmpty);

      final transferReceipt = await fixture.receipt.receive(
        transferId: draft.header.id,
        requestKey: const Uuid().v4(),
        receivedAt: DateTime.utc(2026, 9, 24, 10),
        items: [
          WarehouseTransferReceiptRequestItem(
            allocationId: posted.allocations.single.id,
            acceptedQuantity: 2,
          ),
        ],
      );
      expect(transferReceipt.transfer.status, 'partially_received');
      expect(transferReceipt.receipt.journalEntryId, isNull);
      expect(
        await _stock(
          fixture.db,
          fixture.destination.warehouseId,
          fixture.variant,
        ),
        2,
      );
      expect(
        await _stock(
          fixture.db,
          fixture.destination.warehouseId,
          fixture.variant,
          supplierOwned: true,
        ),
        2,
      );
      final destinationLayer =
          await (fixture.db.select(fixture.db.consignmentInventoryLayers)
                ..where(
                  (item) =>
                      item.warehouseId.equals(fixture.destination.warehouseId),
                ))
              .getSingle();
      expect(destinationLayer.originLayerId, layer.id);
      expect(
        destinationLayer.transferAllocationId,
        posted.allocations.single.id,
      );
      expect(destinationLayer.remainingQuantity, 2);

      final recalled = await fixture.recall.recall(
        transferId: draft.header.id,
        requestKey: const Uuid().v4(),
        reason: 'Return remaining custody to source',
        recalledAt: DateTime.utc(2026, 9, 24, 11),
      );
      expect(recalled.transfer.status, 'cancelled');
      expect(recalled.items.single.quantity, 1);
      expect(recalled.recall.ownedValueCents, 0);
      expect(recalled.recall.journalEntryId, isNull);
      expect(
        await _stock(fixture.db, fixture.source.warehouseId, fixture.variant),
        3,
      );
      expect(
        await _stock(
          fixture.db,
          fixture.source.warehouseId,
          fixture.variant,
          supplierOwned: true,
        ),
        3,
      );
      expect(
        (await fixture.db.select(fixture.db.consignmentInventoryLayers).get())
            .where((row) => row.id == layer.id)
            .single
            .remainingQuantity,
        3,
      );
      expect(await fixture.db.select(fixture.db.journalEntries).get(), isEmpty);
      final report =
          await WarehouseTransferReportingService(
            fixture.db,
            authorizeWarehouse: (_) async {},
          ).report(
            warehouseId: fixture.destination.warehouseId,
            from: DateTime.utc(2026, 9, 23),
            toExclusive: DateTime.utc(2026, 9, 26),
            supplierId: supplier,
            direction: 'incoming',
          );
      expect(report.rows, hasLength(1));
      final reportRow = report.rows.single;
      expect(reportRow.ownerType, 'consignment');
      expect(reportRow.acceptedQuantity, 2);
      expect(reportRow.recalledQuantity, 1);
      expect(reportRow.sources.single.supplierId, supplier);
      expect(reportRow.sources.single.quality, 'consignment');
    },
  );
}
