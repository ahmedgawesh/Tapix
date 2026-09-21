import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/database/daos/batch_audit_dao.dart';
import 'package:tapix/core/services/batch_service.dart';

void main() {
  late AppDatabase db;
  late int productId;
  late int variantId;

  setUp(() async {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    await db.customSelect('SELECT 1').get();
    productId = await db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            name: 'Traceable medicine',
            sku: const Value('MED-LOT'),
            costCents: Decimal.fromInt(100),
            priceCents: Decimal.fromInt(200),
            inventoryTrackingType: const Value('batch_expiry'),
          ),
        );
    variantId = await db
        .into(db.productVariants)
        .insert(
          ProductVariantsCompanion.insert(
            productId: productId,
            costCents: Decimal.fromInt(100),
            priceCents: Decimal.fromInt(200),
          ),
        );
  });

  tearDown(() => db.close());

  test(
    'stores manufacturer lot separately and finds it in batch search',
    () async {
      final batchId = await BatchService.createOpeningBatch(
        db.purchaseDao,
        productId: productId,
        variantId: variantId,
        quantity: 10,
      unitCostCents: 100,
      source: 'opening',
      receivedDate: DateTime(2026, 9, 20),
        expiryDate: DateTime(2028, 9, 20),
        manufacturerLotNumber: ' LOT-24A ',
      );

      final stored = await (db.select(
        db.productBatches,
      )..where((row) => row.id.equals(batchId))).getSingle();
      expect(stored.manufacturerLotNumber, 'LOT-24A');
      expect(stored.batchNumber, isNot('LOT-24A'));

      final matches = await BatchAuditDao(
        db,
      ).watchAllBatches(query: 'LOT-24A').first;
      expect(matches, hasLength(1));
      expect(matches.single.manufacturerLotNumber, 'LOT-24A');
    },
  );

  test('rejects manufacturer lots longer than GS1 AI (10) maximum', () async {
    await expectLater(
      () => BatchService.createOpeningBatch(
        db.purchaseDao,
        productId: productId,
        variantId: variantId,
        quantity: 1,
        unitCostCents: 100,
        source: 'opening',
        manufacturerLotNumber: '123456789012345678901',
      ),
      throwsA(isA<ArgumentError>()),
    );
  });
}
