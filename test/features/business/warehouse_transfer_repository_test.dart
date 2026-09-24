import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/services/business/branch_currency_policy_store.dart';
import 'package:tapix/core/services/business/warehouse_operation_scope.dart';
import 'package:tapix/core/services/business/warehouse_transfer_preflight.dart';
import 'package:tapix/features/business/data/warehouse_transfer_repository.dart';
import 'business_foundation_test.dart' as fixtures;

void main() {
  late AppDatabase db;
  late WarehouseOperationScope source, destination;
  late WarehouseTransferPreflight preflight;
  late WarehouseTransferRepository repository;
  late WarehouseTransferPreview preview;
  late int product, variant, user;
  var denied = false;
  setUp(() async {
    db = fixtures.memoryDb();
    source = await WarehouseOperationScope.resolve(db);
    denied = false;
    final currency = (await (db.select(
      db.currencies,
    )..where((c) => c.code.equals('USD'))).getSingle()).id;
    product = await db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            name: 'Transfer item',
            currencyId: Value(currency),
            costCents: Decimal.fromInt(1000),
            priceCents: Decimal.fromInt(2000),
          ),
        );
    variant = await db
        .into(db.productVariants)
        .insert(
          ProductVariantsCompanion.insert(
            productId: product,
            costCents: Decimal.fromInt(1000),
            priceCents: Decimal.fromInt(2000),
            stockQuantity: const Value(5),
          ),
        );
    final target = const Uuid().v4();
    await db
        .into(db.businessWarehouses)
        .insert(
          BusinessWarehousesCompanion.insert(
            id: target,
            organizationId: source.organizationId,
            branchId: source.branchId,
            code: 'DST',
          ),
        );
    await db
        .into(db.businessWarehouseStocks)
        .insert(
          BusinessWarehouseStocksCompanion.insert(
            warehouseId: target,
            variantId: variant,
            unitCostCents: const Value(700),
          ),
        );
    destination = await WarehouseOperationScope.resolve(
      db,
      warehouseId: target,
    );
    user = await db
        .into(db.users)
        .insert(
          UsersCompanion.insert(
            username: 'transfer-owner',
            passwordHash: 'test-only',
            role: 'owner',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );
    await BranchCurrencyPolicyStore(db).bind('USD');
    preflight = WarehouseTransferPreflight(
      db,
      authorizeWarehouse: (_) async {
        if (denied) throw StateError('denied');
      },
    );
    repository = WarehouseTransferRepository(
      db,
      preflight: preflight,
      authorize: (action, from, to) async {
        if (denied) throw StateError('denied');
        expect(from, source.warehouseId);
        expect(to, destination.warehouseId);
        return user;
      },
    );
    preview = await preflight.preview(
      source: source,
      destination: destination,
      lines: [WarehouseTransferRequestLine(productId: product, quantity: 2)],
    );
  });
  tearDown(() => db.close());
  Future<Object> operationalSnapshot() async => [
    for (final table in [
      'business_warehouse_stocks',
      'products',
      'product_variants',
      'product_batches',
      'batch_consumptions',
      'journal_entries',
      'journal_entry_lines',
    ])
      (await db.customSelect('SELECT * FROM $table ORDER BY rowid').get())
          .map((r) => r.data)
          .toList(),
  ];
  test(
    'create seals a stable draft and audit without stock or journal changes',
    () async {
      final before = await operationalSnapshot();
      final draft = await repository.create(
        requestKey: const Uuid().v4(),
        preview: preview,
        notes: 'reviewed',
      );
      expect(draft.header.status, 'draft');
      expect(draft.header.sealed, isTrue);
      expect(draft.lines.single.quantity, 2);
      expect(draft.lines.single.previewValueCents, 2000);
      expect(
        (await repository.get(draft.header.id)).header.id,
        draft.header.id,
      );
      final event = (await db.select(db.warehouseTransferEvents).get()).single;
      expect(event.actorId, user);
      expect(event.kind, 'created');
      expect(await operationalSnapshot(), before);
    },
  );
  test(
    'list returns authorized documents and applies status filters',
    () async {
      final open = await repository.create(
        requestKey: const Uuid().v4(),
        preview: preview,
        notes: 'open',
      );
      final cancelled = await repository.create(
        requestKey: const Uuid().v4(),
        preview: preview,
        notes: 'cancelled',
      );
      await repository.cancel(
        id: cancelled.header.id,
        requestKey: const Uuid().v4(),
        reason: 'test filter',
      );

      final drafts = await repository.list(statuses: {'draft'});
      final cancelledRows = await repository.list(statuses: {'cancelled'});

      expect(drafts.map((row) => row.header.id), [open.header.id]);
      expect(cancelledRows.map((row) => row.header.id), [cancelled.header.id]);
      await expectLater(
        repository.list(statuses: {'invalid'}),
        throwsArgumentError,
      );
    },
  );

  test(
    'concurrent retries preserve one document and one creation event',
    () async {
      final key = const Uuid().v4();
      final results = await Future.wait(
        List.generate(
          4,
          (_) => repository.create(requestKey: key, preview: preview),
        ),
      );
      expect(results.map((r) => r.header.id).toSet(), hasLength(1));
      expect(await db.select(db.warehouseTransfers).get(), hasLength(1));
      expect(await db.select(db.warehouseTransferEvents).get(), hasLength(1));
      await db.customStatement(
        'UPDATE business_warehouse_stocks SET quantity=1 WHERE warehouse_id=?',
        [source.warehouseId],
      );
      expect(
        (await repository.create(requestKey: key, preview: preview)).header.id,
        results.first.header.id,
      );
      await expectLater(
        repository.create(
          requestKey: key,
          preview: preview,
          notes: 'different',
        ),
        throwsStateError,
      );
    },
  );
  test(
    'new request rejects stale preview and rollback leaves no draft',
    () async {
      await db.customStatement(
        'UPDATE business_warehouse_stocks SET quantity=4 WHERE warehouse_id=?',
        [source.warehouseId],
      );
      await expectLater(
        repository.create(requestKey: const Uuid().v4(), preview: preview),
        throwsStateError,
      );
      expect(await db.select(db.warehouseTransfers).get(), isEmpty);
    },
  );
  test('event insert failure rolls back header, lines and seal', () async {
    await db.customStatement(
      "CREATE TRIGGER fail_transfer_event BEFORE INSERT ON warehouse_transfer_events BEGIN SELECT RAISE(ABORT,'injected'); END",
    );
    await expectLater(
      repository.create(requestKey: const Uuid().v4(), preview: preview),
      throwsA(anything),
    );
    expect(await db.select(db.warehouseTransfers).get(), isEmpty);
    expect(await db.select(db.warehouseTransferLines).get(), isEmpty);
  });
  test(
    'cancel and its retry are atomic and preserve original intent',
    () async {
      final key = const Uuid().v4();
      final draft = await repository.create(requestKey: key, preview: preview);
      final before = await operationalSnapshot();
      final cancellation = const Uuid().v4();
      final result = await repository.cancel(
        id: draft.header.id,
        requestKey: cancellation,
        reason: 'Wrong destination',
      );
      expect(result.header.status, 'cancelled');
      expect(
        (await repository.cancel(
          id: draft.header.id,
          requestKey: cancellation,
          reason: 'Wrong destination',
        )).header.status,
        'cancelled',
      );
      expect(
        (await repository.create(
          requestKey: key,
          preview: preview,
        )).header.status,
        'cancelled',
      );
      expect(await db.select(db.warehouseTransferEvents).get(), hasLength(2));
      expect(await operationalSnapshot(), before);
      await expectLater(
        repository.cancel(
          id: draft.header.id,
          requestKey: cancellation,
          reason: 'Changed reason',
        ),
        throwsStateError,
      );
      await expectLater(
        repository.cancel(
          id: draft.header.id,
          requestKey: const Uuid().v4(),
          reason: 'Another cancellation',
        ),
        throwsStateError,
      );
    },
  );
  test('failed cancellation update rolls back its event', () async {
    final draft = await repository.create(
      requestKey: const Uuid().v4(),
      preview: preview,
    );
    await db.customStatement(
      "CREATE TRIGGER fail_transfer_cancel BEFORE UPDATE OF status ON warehouse_transfers BEGIN SELECT RAISE(ABORT,'injected'); END",
    );
    final key = const Uuid().v4();
    await expectLater(
      repository.cancel(id: draft.header.id, requestKey: key, reason: 'Test'),
      throwsA(anything),
    );
    expect(
      (await db.select(db.warehouseTransfers).get()).single.status,
      'draft',
    );
    expect(await db.select(db.warehouseTransferEvents).get(), hasLength(1));
    await db.customStatement('DROP TRIGGER fail_transfer_cancel');
    await repository.cancel(
      id: draft.header.id,
      requestKey: key,
      reason: 'Test',
    );
  });
  test(
    'revoked permission and disabled user cannot read, create, replay or cancel',
    () async {
      final key = const Uuid().v4();
      final draft = await repository.create(requestKey: key, preview: preview);
      denied = true;
      await expectLater(repository.get(draft.header.id), throwsStateError);
      await expectLater(
        repository.create(requestKey: key, preview: preview),
        throwsStateError,
      );
      await expectLater(
        repository.cancel(
          id: draft.header.id,
          requestKey: const Uuid().v4(),
          reason: 'Denied',
        ),
        throwsStateError,
      );
      denied = false;
      await db.customStatement('UPDATE users SET is_active=0 WHERE id=?', [
        user,
      ]);
      await expectLater(repository.get(draft.header.id), throwsStateError);
    },
  );
  test('SQL cannot rebind, alter lines, erase audit, or fake dispatch', () async {
    final draft = await repository.create(
      requestKey: const Uuid().v4(),
      preview: preview,
    );
    for (final sql in [
      'UPDATE warehouse_transfers SET destination_warehouse_id=source_warehouse_id',
      "UPDATE warehouse_transfers SET status='sent'",
      "UPDATE warehouse_transfers SET status='cancelled'",
      'UPDATE warehouse_transfers SET sealed=0',
      'UPDATE warehouse_transfer_lines SET quantity=1',
      "UPDATE warehouse_transfer_events SET reason='changed'",
      'DELETE FROM warehouse_transfer_events',
      'DELETE FROM warehouse_transfer_lines',
      'DELETE FROM warehouse_transfers',
      'INSERT OR REPLACE INTO warehouse_transfers SELECT * FROM warehouse_transfers',
      'INSERT OR REPLACE INTO warehouse_transfer_lines SELECT * FROM warehouse_transfer_lines',
      'INSERT OR REPLACE INTO warehouse_transfer_events SELECT * FROM warehouse_transfer_events',
    ]) {
      await expectLater(
        db.customStatement(sql),
        throwsA(anything),
        reason: sql,
      );
    }
    expect((await repository.get(draft.header.id)).lines.single.quantity, 2);
  });
  test('request keys, reason and notes are validated before writes', () async {
    await expectLater(
      repository.create(requestKey: 'invalid', preview: preview),
      throwsArgumentError,
    );
    await expectLater(
      repository.create(
        requestKey: const Uuid().v4(),
        preview: preview,
        notes: 'x' * 501,
      ),
      throwsArgumentError,
    );
    final draft = await repository.create(
      requestKey: const Uuid().v4(),
      preview: preview,
    );
    await expectLater(
      repository.cancel(
        id: draft.header.id,
        requestKey: const Uuid().v4(),
        reason: ' ',
      ),
      throwsArgumentError,
    );
    await expectLater(
      repository.cancel(
        id: draft.header.id,
        requestKey: draft.header.requestKey,
        reason: 'Conflict',
      ),
      throwsStateError,
    );
  });
}
