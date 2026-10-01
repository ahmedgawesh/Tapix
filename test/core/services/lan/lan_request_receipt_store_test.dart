import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/database/migrations/lan_request_receipts.dart';
import 'package:tapix/core/services/lan/lan_business_models.dart';
import 'package:tapix/core/services/lan/lan_request_receipt_store.dart';

void main() {
  late AppDatabase db;
  late LanRequestReceiptStore store;

  setUp(() async {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    await db.customSelect('SELECT 1').get();
    store = LanRequestReceiptStore(db);
  });

  tearDown(() => db.close());

  test('fingerprint is canonical and excludes only the transport key', () {
    final first = store.fingerprint({
      'idempotencyKey': 'key-one',
      'customerId': 7,
      'line': {'quantity': 2, 'productId': 11},
    });
    final reordered = store.fingerprint({
      'line': {'productId': 11, 'quantity': 2},
      'customerId': 7,
      'idempotencyKey': 'key-two',
    });
    final changed = store.fingerprint({
      'customerId': 7,
      'line': {'productId': 11, 'quantity': 3},
    });

    expect(reordered, first);
    expect(changed, isNot(first));
  });

  test(
    'same payload replays and a changed payload conflicts with 409',
    () async {
      const payload = <String, dynamic>{
        'idempotencyKey': 'sale-0001',
        'quantity': 2,
      };
      await db.transaction(() async {
        final reservation = await store.reserve(
          operation: 'sale',
          idempotencyKey: 'sale-0001',
          payload: payload,
          findLegacyDocument: () async => null,
        );
        expect(reservation.shouldCreate, isTrue);
        await store.complete(
          operation: 'sale',
          idempotencyKey: 'sale-0001',
          payload: payload,
          documentId: 41,
          documentNumber: 'SI-41',
          totalCents: 2200,
        );
      });

      final replay = await db.transaction(
        () => store.reserve(
          operation: 'sale',
          idempotencyKey: 'sale-0001',
          payload: payload,
          findLegacyDocument: () async => null,
        ),
      );
      expect(replay.shouldCreate, isFalse);
      expect(replay.documentId, 41);

      await expectLater(
        db.transaction(
          () => store.reserve(
            operation: 'sale',
            idempotencyKey: 'sale-0001',
            payload: const {'idempotencyKey': 'sale-0001', 'quantity': 3},
            findLegacyDocument: () async => null,
          ),
        ),
        throwsA(
          isA<LanBusinessException>()
              .having(
                (error) => error.code,
                'code',
                'idempotency_payload_conflict',
              )
              .having((error) => error.statusCode, 'statusCode', 409),
        ),
      );
    },
  );

  test('a failed business transaction rolls its reservation back', () async {
    await expectLater(
      db.transaction(() async {
        await store.reserve(
          operation: 'sale_return',
          idempotencyKey: 'return-rollback',
          payload: const {'quantity': 1},
          findLegacyDocument: () async => null,
        );
        throw StateError('simulated posting failure');
      }),
      throwsStateError,
    );

    await db.transaction(() async {
      final retry = await store.reserve(
        operation: 'sale_return',
        idempotencyKey: 'return-rollback',
        payload: const {'quantity': 2},
        findLegacyDocument: () async => null,
      );
      expect(retry.shouldCreate, isTrue);
      await store.complete(
        operation: 'sale_return',
        idempotencyKey: 'return-rollback',
        payload: const {'quantity': 2},
        documentId: 9,
        documentNumber: 'SR-9',
        totalCents: 500,
      );
    });
  });

  test('purchase invoices have a durable idempotency operation', () async {
    const payload = {
      'idempotencyKey': 'purchase-invoice-001',
      'warehouseId': 'warehouse-1',
      'actorUserId': 8,
      'quantity': 500,
    };
    await db.transaction(() async {
      final reservation = await store.reserve(
        operation: 'purchase',
        idempotencyKey: 'purchase-invoice-001',
        payload: payload,
        findLegacyDocument: () async => null,
      );
      expect(reservation.shouldCreate, isTrue);
      await store.complete(
        operation: 'purchase',
        idempotencyKey: 'purchase-invoice-001',
        payload: payload,
        documentId: 81,
        documentNumber: 'PI-81',
        totalCents: 400,
      );
    });

    final replay = await db.transaction(
      () => store.reserve(
        operation: 'purchase',
        idempotencyKey: 'purchase-invoice-001',
        payload: payload,
        findLegacyDocument: () async => null,
      ),
    );
    expect(replay.shouldCreate, isFalse);
    expect(replay.documentId, 81);
  });

  test(
    'legacy ledger upgrade preserves receipts and adds protected purchases',
    () async {
      await db.customStatement(
        'DROP TRIGGER IF EXISTS trg_lan_request_receipts_no_delete',
      );
      await db.customStatement(
        'DROP TRIGGER IF EXISTS trg_lan_request_receipts_complete_once',
      );
      await db.customStatement('DROP TABLE lan_request_receipts');
      await db.customStatement('''
        CREATE TABLE lan_request_receipts (
          operation TEXT NOT NULL CHECK (operation IN (
            'sale',
            'sale_return',
            'sale_adjustment_return',
            'purchase_return',
            'purchase_adjustment_return'
          )),
          idempotency_key TEXT NOT NULL,
          request_hash TEXT,
          state TEXT NOT NULL CHECK (state IN ('pending', 'completed', 'legacy')),
          document_id INTEGER,
          document_number TEXT,
          total_cents INTEGER,
          created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
          completed_at TEXT,
          PRIMARY KEY (operation, idempotency_key)
        )
      ''');
      await db.customStatement('''
        INSERT INTO lan_request_receipts (
          operation, idempotency_key, request_hash, state, document_id,
          document_number, total_cents, completed_at
        ) VALUES (
          'sale', 'legacy-sale-001',
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          'completed', 17, 'SI-17', 900, CURRENT_TIMESTAMP
        )
      ''');

      await installLanRequestReceiptLedger(db);

      final legacy = await db.customSelect('''
            SELECT document_id, document_number, total_cents
            FROM lan_request_receipts
            WHERE operation='sale' AND idempotency_key='legacy-sale-001'
          ''').getSingle();
      expect(legacy.read<int>('document_id'), 17);
      expect(legacy.read<String>('document_number'), 'SI-17');
      expect(legacy.read<int>('total_cents'), 900);

      const purchasePayload = {
        'warehouseId': 'warehouse-2',
        'actorUserId': 9,
        'quantity': 250,
      };
      await db.transaction(() async {
        final purchase = await store.reserve(
          operation: 'purchase',
          idempotencyKey: 'upgraded-purchase-001',
          payload: purchasePayload,
          findLegacyDocument: () async => null,
        );
        expect(purchase.shouldCreate, isTrue);
        await store.complete(
          operation: 'purchase',
          idempotencyKey: 'upgraded-purchase-001',
          payload: purchasePayload,
          documentId: 91,
          documentNumber: 'PI-91',
          totalCents: 700,
        );
      });

      await expectLater(
        db.customStatement('''
          UPDATE lan_request_receipts SET total_cents=1
          WHERE operation='sale' AND idempotency_key='legacy-sale-001'
        '''),
        throwsA(anything),
      );
      await expectLater(
        db.customStatement('''
          DELETE FROM lan_request_receipts
          WHERE operation='purchase'
            AND idempotency_key='upgraded-purchase-001'
        '''),
        throwsA(anything),
      );
    },
  );

  test('concurrent same-payload retries produce one durable owner', () async {
    var creators = 0;

    Future<int> execute() => db.transaction(() async {
      final reservation = await store.reserve(
        operation: 'purchase_return',
        idempotencyKey: 'purchase-return-race',
        payload: const {'purchaseId': 3, 'quantity': 1},
        findLegacyDocument: () async => null,
      );
      if (!reservation.shouldCreate) return reservation.documentId!;
      creators++;
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await store.complete(
        operation: 'purchase_return',
        idempotencyKey: 'purchase-return-race',
        payload: const {'purchaseId': 3, 'quantity': 1},
        documentId: 77,
        documentNumber: 'PR-77',
        totalCents: 100,
      );
      return 77;
    });

    final results = await Future.wait([execute(), execute()]);
    expect(results, [77, 77]);
    expect(creators, 1);
  });

  test('completed receipts cannot be rewritten or deleted', () async {
    await db.transaction(() async {
      await store.reserve(
        operation: 'purchase_adjustment_return',
        idempotencyKey: 'immutable-receipt',
        payload: const {'supplierId': 8, 'quantity': 1},
        findLegacyDocument: () async => null,
      );
      await store.complete(
        operation: 'purchase_adjustment_return',
        idempotencyKey: 'immutable-receipt',
        payload: const {'supplierId': 8, 'quantity': 1},
        documentId: 90,
        documentNumber: 'PRA-90',
        totalCents: 700,
      );
    });

    await expectLater(
      db.customStatement('''
UPDATE lan_request_receipts
SET total_cents = 1
WHERE operation = 'purchase_adjustment_return'
  AND idempotency_key = 'immutable-receipt'
'''),
      throwsA(anything),
    );
    await expectLater(
      db.customStatement('''
DELETE FROM lan_request_receipts
WHERE operation = 'purchase_adjustment_return'
  AND idempotency_key = 'immutable-receipt'
'''),
      throwsA(anything),
    );
    final row = await db.customSelect('''
SELECT state, document_id, total_cents
FROM lan_request_receipts
WHERE operation = 'purchase_adjustment_return'
  AND idempotency_key = 'immutable-receipt'
''').getSingle();
    expect(row.read<String>('state'), 'completed');
    expect(row.read<int>('document_id'), 90);
    expect(row.read<int>('total_cents'), 700);
  });

  test(
    'legacy document is preserved without inventing a payload hash',
    () async {
      final first = await db.transaction(
        () => store.reserve(
          operation: 'sale_adjustment_return',
          idempotencyKey: 'legacy-key',
          payload: const {'quantity': 1},
          findLegacyDocument: () async => const LanLegacyRequestDocument(
            id: 15,
            number: 'SRA-15',
            totalCents: 800,
          ),
        ),
      );
      final replay = await db.transaction(
        () => store.reserve(
          operation: 'sale_adjustment_return',
          idempotencyKey: 'legacy-key',
          payload: const {'quantity': 99},
          findLegacyDocument: () async => null,
        ),
      );

      expect(first.documentId, 15);
      expect(replay.documentId, 15);
      final row = await db.customSelect('''
SELECT state, request_hash
FROM lan_request_receipts
WHERE operation = 'sale_adjustment_return'
  AND idempotency_key = 'legacy-key'
''').getSingle();
      expect(row.read<String>('state'), 'legacy');
      expect(row.readNullable<String>('request_hash'), isNull);
    },
  );
}
