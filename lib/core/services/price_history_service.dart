import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';

import '../database/app_database.dart';

/// Centralized writer for the immutable `product_price_histories` audit log.
///
/// Mirrors `BatchService` / `StockService` in style: pure-static, takes a
/// `DatabaseAccessor<AppDatabase>` so it composes inside any DAO transaction.
///
/// SINGLE SOURCE OF TRUTH for "a product's cost / retail price / wholesale
/// price changed". Every code path that mutates one of those three fields
/// MUST funnel through here, otherwise the in-app price-history surface and
/// the per-line snapshots in invoices will drift apart (and the user will
/// rightly complain that price history is "scattered").
///
/// Sanctioned call sites:
///   - `PurchaseDao.postPurchase` — WAC / last-cost / FIFO cost mutation,
///     plus the per-line `newSellPrice` / `newWholesalePrice` overrides
///     entered in the purchase bottom sheet.
///   - `InventoryAdjustmentService` — revaluation (cost-only mutation).
///   - `ProductFormBloc` — manual edits from the product-edit form.
///   - Future: purchase / sale return DAOs when reversing prior prices.
///
/// Storage convention (matches the rest of the app):
///   - All `*Cents` parameters are integer cents (e.g. 12345 = $123.45).
///   - The DB columns store those integer cents directly. Do not divide by
///     100 here: `MoneyConverter` is an integer-preserving converter, not a
///     major-unit converter.
class PriceHistoryService {
  PriceHistoryService._();

  /// Append an immutable price-history row when at least one of cost / retail
  /// / wholesale actually changed. No-op when nothing differs — keeps the
  /// audit log free of phantom rows.
  ///
  /// [variantId] is optional and lets callers attribute the change to a
  /// specific dimensional variant (color/size). When null, the row is
  /// product-level (applies to the default variant or the whole product).
  static Future<void> recordIfChanged(
    DatabaseAccessor<AppDatabase> dao, {
    required int productId,
    int? variantId,
    required int oldCostCents,
    required int newCostCents,
    required int oldPriceCents,
    required int newPriceCents,
    int? oldWholesalePriceCents,
    int? newWholesalePriceCents,
    int? userId,
    String? changeReason,
  }) async {
    final costChanged = oldCostCents != newCostCents;
    final priceChanged = oldPriceCents != newPriceCents;
    final wholesaleChanged = oldWholesalePriceCents != newWholesalePriceCents;
    if (!costChanged && !priceChanged && !wholesaleChanged) return;

    // `MoneyConverter` round-trips Decimal.toBigInt() ↔ SQL INTEGER, so the
    // Decimal supplied here must itself contain integer cents. Legacy rows
    // that used a major-unit-like convention are normalized once by schema
    // migration 10067.
    final db = dao.attachedDatabase;
    await db
        .into(db.productPriceHistories)
        .insert(
          ProductPriceHistoriesCompanion.insert(
            productId: productId,
            variantId: Value(variantId),
            oldCostCents: Decimal.fromInt(oldCostCents),
            newCostCents: Decimal.fromInt(newCostCents),
            oldPriceCents: Decimal.fromInt(oldPriceCents),
            newPriceCents: Decimal.fromInt(newPriceCents),
            oldWholesalePriceCents: Value(
              oldWholesalePriceCents == null
                  ? null
                  : Decimal.fromInt(oldWholesalePriceCents),
            ),
            newWholesalePriceCents: Value(
              newWholesalePriceCents == null
                  ? null
                  : Decimal.fromInt(newWholesalePriceCents),
            ),
            userId: Value(userId == 0 ? null : userId),
            changeReason: Value(changeReason),
          ),
        );
  }
}
