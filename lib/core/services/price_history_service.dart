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
///   - The DB columns use `MoneyConverter`, which round-trips integer cents
///     unchanged. Writing via raw SQL with `Variable.withInt(cents)` is
///     equivalent to using the typed Drift companion.
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
    final wholesaleChanged =
        oldWholesalePriceCents != newWholesalePriceCents;
    if (!costChanged && !priceChanged && !wholesaleChanged) return;

    // The `product_price_histories.*_cents` columns use `MoneyConverter`,
    // which round-trips Decimal ↔ integer storage. The existing
    // `ProductLocalDatasource.createPriceHistory` writes Decimal values
    // scaled by 1/100 (cents → dollars) and reads back via `shift(2)`.
    // This service intentionally mirrors that contract so that writes from
    // any sanctioned call site (purchase posting, inventory revaluation,
    // product form, returns) end up in the same shape that the price-history
    // surface in the product edit page already understands.
    final db = dao.attachedDatabase;
    await db.into(db.productPriceHistories).insert(
          ProductPriceHistoriesCompanion.insert(
            productId: productId,
            variantId: Value(variantId),
            oldCostCents: _centsToDecimal(oldCostCents),
            newCostCents: _centsToDecimal(newCostCents),
            oldPriceCents: _centsToDecimal(oldPriceCents),
            newPriceCents: _centsToDecimal(newPriceCents),
            oldWholesalePriceCents: Value(
              oldWholesalePriceCents == null
                  ? null
                  : _centsToDecimal(oldWholesalePriceCents),
            ),
            newWholesalePriceCents: Value(
              newWholesalePriceCents == null
                  ? null
                  : _centsToDecimal(newWholesalePriceCents),
            ),
            userId: Value(userId == 0 ? null : userId),
            changeReason: Value(changeReason),
          ),
        );
  }

  static Decimal _centsToDecimal(int cents) {
    return (Decimal.fromInt(cents) / Decimal.fromInt(100)).toDecimal();
  }
}
