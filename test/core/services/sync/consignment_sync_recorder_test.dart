import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/services/sync/consignment_sync_recorder.dart';
import 'package:tapix/core/services/sync/offline_sync_event_store.dart';

void main() {
  late AppDatabase db;
  late int currencyId;
  late int supplierId;
  late int productId;
  late int variantId;

  setUp(() async {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    await db.customSelect('SELECT 1').get();
    currencyId = (await (db.select(
      db.currencies,
    )..where((row) => row.code.equals('USD'))).getSingle()).id;
    supplierId = await db
        .into(db.suppliers)
        .insert(
          SuppliersCompanion.insert(
            name: 'Consignment source',
            currencyId: currencyId,
          ),
        );
    productId = await db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            name: 'Consigned item',
            currencyId: Value(currencyId),
            stockQuantity: const Value(7),
            costCents: Decimal.fromInt(450),
            priceCents: Decimal.fromInt(800),
          ),
        );
    variantId = await db
        .into(db.productVariants)
        .insert(
          ProductVariantsCompanion.insert(
            productId: productId,
            stockQuantity: const Value(7),
            costCents: Decimal.fromInt(450),
            priceCents: Decimal.fromInt(800),
          ),
        );
  });

  tearDown(() => db.close());

  test(
    'single database skips network evidence without changing data',
    () async {
      await _record(db, currencyId, supplierId, productId, variantId);

      expect(await _count(db, 'sync_outbox_events'), 0);
      expect(await _count(db, 'sync_entity_identities'), 0);
      expect(await _stock(db, 'products', productId), 7);
      expect(await _stock(db, 'product_variants', variantId), 7);
    },
  );

  test(
    'enrolled writer records globally identified read-only evidence',
    () async {
      await OfflineSyncEventStore(db).activateWriterRecording(
        enrollmentId: '11111111-1111-4111-8111-111111111111',
      );

      await _record(db, currencyId, supplierId, productId, variantId);

      final row = await db
          .customSelect(
            'SELECT event_type,aggregate_type,payload_json '
            'FROM sync_outbox_events',
          )
          .getSingle();
      expect(row.read<String>('event_type'), 'consignment_receipt.posted.v1');
      expect(row.read<String>('aggregate_type'), 'consignment_receipt');
      final payload =
          jsonDecode(row.read<String>('payload_json')) as Map<String, dynamic>;
      expect(payload['contract'], 'consignment_receipt.posted');
      expect(payload['sourceDocumentRef']['localId'], 42);
      expect(payload['supplierGlobalId'], isNotEmpty);
      expect(payload['currencyCode'], 'USD');
      expect(payload['lineCount'], 1);
      final line = (payload['lines'] as List).single as Map<String, dynamic>;
      expect(line['productGlobalId'], isNotEmpty);
      expect(line['variantGlobalId'], isNotEmpty);
      expect(line['quantityScaled'], 3);
      expect(line['unitCostMinor'], 450);

      // Publishing evidence must never repost the source document locally.
      expect(await _stock(db, 'products', productId), 7);
      expect(await _stock(db, 'product_variants', variantId), 7);
      expect(await _count(db, 'supplier_transactions'), 0);

      // A retry of the same finalized document/action remains idempotent.
      await _record(db, currencyId, supplierId, productId, variantId);
      expect(await _count(db, 'sync_outbox_events'), 1);
    },
  );
}

Future<void> _record(
  AppDatabase db,
  int currencyId,
  int supplierId,
  int productId,
  int variantId,
) => ConsignmentSyncRecorder(db).record(
  eventType: 'consignment_receipt.posted.v1',
  contract: 'consignment_receipt.posted',
  documentType: 'consignment_receipt',
  localDocumentId: 42,
  action: 'posted',
  occurredAt: DateTime.utc(2026, 9, 28, 10),
  supplierId: supplierId,
  currencyId: currencyId,
  warehouseId: '22222222-2222-4222-8222-222222222222',
  agreementId: 'agreement-1',
  values: const {'totalMinor': 1350},
  lines: [
    {
      'productId': productId,
      'variantId': variantId,
      'quantityScaled': 3,
      'unitCostMinor': 450,
    },
  ],
);

Future<int> _count(AppDatabase db, String table) => db
    .customSelect('SELECT COUNT(*) AS n FROM $table')
    .map((row) => row.read<int>('n'))
    .getSingle();

Future<int> _stock(AppDatabase db, String table, int id) => db
    .customSelect(
      'SELECT stock_quantity FROM $table WHERE id=?',
      variables: [Variable.withInt(id)],
    )
    .map((row) => row.read<int>('stock_quantity'))
    .getSingle();
