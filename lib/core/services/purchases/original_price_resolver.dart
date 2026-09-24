import 'package:equatable/equatable.dart';

import '../../../features/products/domain/entities/product_entity.dart';
import '../../../features/products/domain/entities/product_variant_entity.dart';

/// Result of resolving the "original" (pre-purchase) prices for a single
/// purchase line item.
///
/// Two parallel views of the same data:
///
/// * **Display fields** ([costCents], [priceCents], [wholesalePriceCents]) —
///   always non-null where the underlying field is non-nullable, ready to be
///   rendered in the bottom-sheet "old cost / old price / old wholesale"
///   labels. They are the result of walking the resolution chain (saved →
///   variant.previous → variant.current → product.previous → product.current).
///
/// * **Persistence fields** ([persistCostCents], [persistPriceCents],
///   [persistWholesalePriceCents]) — nullable. They are `null` when there is
///   no real historical value worth freezing into the DB (e.g. a brand-new
///   variant whose live cost is still 0 from default-init). Persisting `null`
///   instead of `0` means a future re-load can fall back through the same
///   resolution chain rather than displaying a meaningless `0.00`.
class OriginalPriceSnapshot extends Equatable {
  /// Display-ready cost (cents). Falls back through the resolution chain.
  final int costCents;

  /// Display-ready retail price (cents). Falls back through the resolution
  /// chain.
  final int priceCents;

  /// Display-ready wholesale price (cents). Genuinely nullable: `null` means
  /// "no wholesale price configured for this product/variant".
  final int? wholesalePriceCents;

  /// Cost to persist as `original_cost_cents` on the purchase line. `null`
  /// when there is no real historical cost (e.g. a brand-new variant whose
  /// live cost is 0 from default-init).
  final int? persistCostCents;

  /// Retail price to persist as `original_price_cents`. `null` semantics same
  /// as [persistCostCents].
  final int? persistPriceCents;

  /// Wholesale price to persist as `original_wholesale_price_cents`. `null`
  /// when no wholesale price exists OR it is a default-init `0`.
  final int? persistWholesalePriceCents;

  const OriginalPriceSnapshot({
    required this.costCents,
    required this.priceCents,
    required this.wholesalePriceCents,
    required this.persistCostCents,
    required this.persistPriceCents,
    required this.persistWholesalePriceCents,
  });

  @override
  List<Object?> get props => [
    costCents,
    priceCents,
    wholesalePriceCents,
    persistCostCents,
    persistPriceCents,
    persistWholesalePriceCents,
  ];
}

/// **Single source of truth** for resolving the "original" (pre-purchase)
/// prices that appear in the purchase form's bottom-sheet ("old cost",
/// "old sell price", "old wholesale price") and that get frozen as a
/// historical snapshot on the purchase line.
///
/// Centralizing here eliminates a long-standing class of bugs:
///
/// 1. **Scattered logic drift.** Previously the same chain was duplicated in
///    `PurchaseFormBloc` under `_onLineItemAdded` (using `previousX ?? currentX`)
///    AND `_onInitialized` (using `savedX ?? currentX`). The two diverged in
///    subtle ways and swapped meanings of "previous".
///
/// 2. **Sibling-variant wholesale leak.** The products-table aggregate keeps
///    `wholesale_price_cents = MAX(variant.wholesale)` for backwards-compat.
///    Falling back to the product row when a variant exists but has a NULL
///    wholesale would leak a sibling variant's value. **This resolver never
///    bubbles up to product-level pricing once a variant is resolved.**
///
/// 3. **Default-init `0` frozen forever.** A freshly-created variant has
///    `cost_cents = 0`, `price_cents = 0`. If the user immediately makes a
///    purchase, the line previously froze `originalCostCents = 0`. On
///    re-edit the dialog displayed `0.00`. **This resolver treats saved `0`
///    the same as `null` (defaults-as-missing) on the read path AND avoids
///    persisting `0` on the write path — null is persisted instead.**
///
/// **Variant vs no-variant** is handled uniformly: callers always pass the
/// product, optionally pass the variant. When variant is non-null, ALL
/// fallbacks stay strictly inside the variant's own row. When variant is
/// null (product without variants OR product whose default variant could not
/// be resolved), fallbacks use product-level pricing.
///
/// **Inventory tracking type** ([Product.inventoryTrackingType]) is
/// orthogonal to pricing — the resolver does not branch on it. Standard,
/// batch, and batch_expiry products all resolve prices the same way.
class OriginalPriceResolver {
  OriginalPriceResolver._();

  /// Resolves prices when **loading a saved purchase line** for editing.
  ///
  /// `savedX` parameters come from the purchase_items DB row. They are
  /// authoritative when present and `> 0`. A saved `0` is treated as
  /// "missing" (legacy default-init) and falls through to live values.
  static OriginalPriceSnapshot resolveForEdit({
    required Product product,
    ProductVariant? variant,
    int? savedCostCents,
    int? savedPriceCents,
    int? savedWholesalePriceCents,
  }) {
    return _resolve(
      product: product,
      variant: variant,
      savedCostCents: savedCostCents,
      savedPriceCents: savedPriceCents,
      savedWholesalePriceCents: savedWholesalePriceCents,
    );
  }

  /// Captures prices when **adding a brand-new line** to a draft purchase.
  ///
  /// Pure live-value capture — no saved snapshot exists yet because this
  /// line has never been persisted. The resulting `persist*` fields are
  /// what should land in the DB if the user saves the purchase as-is.
  static OriginalPriceSnapshot captureForNewLine({
    required Product product,
    ProductVariant? variant,
  }) {
    return _resolve(
      product: product,
      variant: variant,
      savedCostCents: null,
      savedPriceCents: null,
      savedWholesalePriceCents: null,
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // Internals
  // ─────────────────────────────────────────────────────────────────────

  static OriginalPriceSnapshot _resolve({
    required Product product,
    required ProductVariant? variant,
    required int? savedCostCents,
    required int? savedPriceCents,
    required int? savedWholesalePriceCents,
  }) {
    // 1. Saved snapshot is honored ONLY when > 0. A saved 0 is almost always
    //    a default-init artifact (variant freshly created with cost=0). A
    //    truly free product is vanishingly rare and would still resolve to 0
    //    via the live-value chain below.
    final realSavedCost = _positiveOrNull(savedCostCents);
    final realSavedPrice = _positiveOrNull(savedPriceCents);
    final realSavedWholesale = _positiveOrNull(savedWholesalePriceCents);

    // 2. Live value chain. When a variant is resolved, the chain stays
    //    strictly inside the variant — falling back to product-level pricing
    //    would re-introduce the wholesale-leak bug (the products table keeps
    //    MAX(variant.wholesale) for legacy reasons).
    final int liveCost;
    final int livePrice;
    final int? liveWholesale;
    if (variant != null) {
      final variantCurrentCost = variant.costCents.toBigInt().toInt();
      final variantCurrentPrice = variant.priceCents.toBigInt().toInt();
      liveCost =
          _firstPositive([
            variantCurrentCost,
            variant.previousCostCents?.toBigInt().toInt(),
          ]) ??
          variantCurrentCost;
      livePrice =
          _firstPositive([
            variantCurrentPrice,
            variant.previousPriceCents?.toBigInt().toInt(),
          ]) ??
          variantCurrentPrice;
      liveWholesale = _firstPositive([
        variant.wholesalePriceCents?.toBigInt().toInt(),
        variant.previousWholesalePriceCents?.toBigInt().toInt(),
      ]);
    } else {
      final productCurrentCost = product.costCents.toBigInt().toInt();
      final productCurrentPrice = product.priceCents.toBigInt().toInt();
      liveCost =
          _firstPositive([
            productCurrentCost,
            product.previousCostCents?.toBigInt().toInt(),
          ]) ??
          productCurrentCost;
      livePrice =
          _firstPositive([
            productCurrentPrice,
            product.previousPriceCents?.toBigInt().toInt(),
          ]) ??
          productCurrentPrice;
      liveWholesale = _firstPositive([
        product.wholesalePriceCents?.toBigInt().toInt(),
        product.previousWholesalePriceCents?.toBigInt().toInt(),
      ]);
    }

    // 3. Display values: prefer real saved (real history), fallback to live.
    final displayCost = realSavedCost ?? liveCost;
    final displayPrice = realSavedPrice ?? livePrice;
    final displayWholesale = realSavedWholesale ?? liveWholesale;

    // 4. Persistence values: prefer real saved; else live IFF live > 0; else
    //    null. Persisting null instead of 0 lets a future re-load fall back
    //    through the same chain rather than freezing a meaningless 0.
    final persistCost = realSavedCost ?? (liveCost > 0 ? liveCost : null);
    final persistPrice = realSavedPrice ?? (livePrice > 0 ? livePrice : null);
    final persistWholesale =
        realSavedWholesale ??
        ((liveWholesale != null && liveWholesale > 0) ? liveWholesale : null);

    return OriginalPriceSnapshot(
      costCents: displayCost,
      priceCents: displayPrice,
      wholesalePriceCents: displayWholesale,
      persistCostCents: persistCost,
      persistPriceCents: persistPrice,
      persistWholesalePriceCents: persistWholesale,
    );
  }

  static int? _positiveOrNull(int? value) {
    if (value == null) return null;
    return value > 0 ? value : null;
  }

  static int? _firstPositive(List<int?> values) {
    for (final v in values) {
      if (v != null && v > 0) return v;
    }
    return null;
  }
}
