import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/database/app_database.dart';

import 'business_foundation_test.dart' as fixtures;

void main() {
  late AppDatabase db;
  late int productId;
  setUp(() async {
    db = fixtures.memoryDb();
    productId = await db.customInsert(
      "INSERT INTO products(name, cost_cents, price_cents) VALUES ('Policy probe', 100, 200)",
    );
  });
  tearDown(() => db.close());

  Future<String?> change(String field, String value) async {
    switch (field) {
      case 'measurement_type':
        return db.productDao.setMeasurementType(
          productId: productId,
          measurementType: value,
        );
      case 'costing_method':
        return db.productDao.setCostingMethod(
          productId: productId,
          method: value,
        );
      default:
        return db.productDao.setInventoryTrackingType(
          productId: productId,
          trackingType: value,
        );
    }
  }

  const policies = {
    'measurement_type': ['piece', 'length', 'weight', 'volume'],
    'costing_method': ['wac', 'fifo'],
    'inventory_tracking_type': ['standard', 'batch', 'batch_expiry'],
  };
  for (final policy in policies.entries) {
    test(
      '${policy.key} rejects invalid values without changing data',
      () async {
        final before = await fixtures.legacySnapshot(db);
        for (final value in [
          '',
          'unsupported',
          policy.value.first.toUpperCase(),
          '${policy.value.first} ',
        ]) {
          // ArgumentError, not AssertionError: validation is active in release.
          await expectLater(change(policy.key, value), throwsArgumentError);
          expect(await fixtures.legacySnapshot(db), before);
        }
      },
    );
    for (final value in policy.value) {
      test('${policy.key} accepts $value on a pristine product', () async {
        expect(await change(policy.key, value), isNull);
        final row = await db
            .customSelect(
              'SELECT * FROM products WHERE id = ?',
              variables: [Variable.withInt(productId)],
            )
            .getSingle();
        expect(row.read<String>(policy.key), value);
        if (policy.key == 'inventory_tracking_type') {
          expect(
            row.read<String>('costing_method'),
            value == 'standard' ? 'wac' : 'fifo',
          );
        }
      });
    }
  }
}
