import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';

import '../database/app_database.dart';

/// Exercises product/variant insertion without persisting diagnostic rows,
/// inventory, or sequence changes, on both success and failure.
class DatabaseHealthCheckService {
  final AppDatabase db;
  const DatabaseHealthCheckService(this.db);

  Future<bool> checkNullableVariantSku() async {
    try {
      await db.transaction(() async {
        final currency = await (db.select(db.currencies)..limit(1)).getSingle();
        final productId = await db
            .into(db.products)
            .insert(
              ProductsCompanion.insert(
                name: 'Health Check Product',
                costCents: Decimal.fromInt(100),
                priceCents: Decimal.fromInt(200),
                currencyId: Value(currency.id),
              ),
            );
        final variantId = await db
            .into(db.productVariants)
            .insert(
              ProductVariantsCompanion.insert(
                productId: productId,
                costCents: Decimal.fromInt(100),
                priceCents: Decimal.fromInt(200),
                sku: const Value(null),
                stockQuantity: const Value(0),
              ),
            );
        final variant = await (db.select(
          db.productVariants,
        )..where((v) => v.id.equals(variantId))).getSingle();
        // Deliberately roll back even on success. Cleanup DELETE statements
        // cannot guarantee recovery if a trigger or later operation fails.
        throw _ProbeCompleted(
          variant.sku == null && variant.stockQuantity == 0,
        );
      });
    } on _ProbeCompleted catch (result) {
      return result.passed;
    }
  }
}

class _ProbeCompleted implements Exception {
  final bool passed;
  const _ProbeCompleted(this.passed);
}
