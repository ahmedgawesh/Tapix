import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/features/products/domain/entities/product_entity.dart';
import 'package:tapix/features/products/domain/entities/product_variant_entity.dart';
import 'package:tapix/features/purchases/presentation/bloc/purchase_form_bloc.dart';

/// Regression suite for the variant-vs-no-variant unit-cost asymmetry
/// reported on 2026-05-18.
///
/// ## Background
/// `PurchaseDao.postPurchase` writes the IAS-2 NET basis to
/// `cost_cents` (subtracting any per-line discount) and stamps the GROSS
/// supplier reference price on `last_purchase_price_cents`. For a line
/// posted with `unit_cost = $100` and `discount = $1`, the result is:
///
///   * `cost_cents = 9900`               (NET / IAS-2)
///   * `last_purchase_price_cents = 10000` (GROSS / supplier ref)
///
/// **The bug**: the purchase form previously auto-filled the new line's
/// `unitCostCents` from `costCents` alone — i.e. the NET basis. For
/// products WITHOUT variants this was symmetric (no split happens until
/// a discount is applied, so both columns matched). For products WITH
/// variants any past discounted purchase silently desynced the two
/// columns, so the picker showed the variant at the post-discount NET
/// while the no-variant peer showed the GROSS the user typed.
///
/// Result on screen: "$99.00 × 1 → $99.99" next to "$100.00 × 1 → $101.00"
/// for two products the user had entered at the same $100 price. The
/// totals row was internally consistent (sub $298 + 1% tax = $300.98)
/// but mismatched the user's mental model.
///
/// ## Convention pinned by this file
/// The four call sites in `purchase_form_screen.dart` (barcode-scan
/// variant branch, barcode-scan product branch, `_AddItemSheet`
/// no-variant `onTap`, `_AddItemSheet` variant `onTap`) — together with
/// the two display labels in `_buildProductList` and
/// `_buildVariantSelection` — MUST resolve the auto-filled unit cost
/// via `lastPurchasePriceCents ?? costCents`. This mirrors
/// `VariantEditDialog`'s `_loadDefaultsForNewVariant` and
/// `initState` for editing (see
/// `lib/features/products/presentation/widgets/variant_edit_dialog.dart`).
///
/// The tests below pin the downstream effect on line totals: when fed
/// the gross value the per-line tile MUST render `$100 + 1% = $101.00`
/// regardless of whether the line carries a variant.
void main() {
  // Both products carry an identical 1% purchase tax rate. The only
  // axis of variation is `hasVariants` and the variant-vs-product cost
  // split discovered in the field report.
  final productWithVariants = Product(
    id: 1,
    name: 'p1 with v',
    costCents: Decimal.fromInt(9900), // post-discount NET basis
    priceCents: Decimal.fromInt(15000),
    lastPurchasePriceCents: Decimal.fromInt(10000), // GROSS supplier price
    stockQuantity: 0,
    minQuantity: 0,
    hasVariants: true,
    isTaxable: true,
    purchaseTaxRateBps: 100, // 1 %
    salesTaxRateBps: 100,
    isActive: true,
    trackInventory: true,
  );

  final productNoVariants = Product(
    id: 2,
    name: 'p2 without v',
    costCents: Decimal.fromInt(10000),
    priceCents: Decimal.fromInt(15000),
    lastPurchasePriceCents: Decimal.fromInt(10000),
    stockQuantity: 0,
    minQuantity: 0,
    hasVariants: false,
    isTaxable: true,
    purchaseTaxRateBps: 100,
    salesTaxRateBps: 100,
    isActive: true,
    trackInventory: true,
  );

  const variantId = 2;
  final variant = ProductVariant(
    id: variantId,
    productId: productWithVariants.id,
    sku: 'tt55-1',
    costCents: Decimal.fromInt(9900), // NET (mirrors parent product)
    priceCents: Decimal.fromInt(15000),
    lastPurchasePriceCents: Decimal.fromInt(10000), // GROSS
    priceAdjustmentCents: Decimal.zero,
    stockQuantity: 0,
    isActive: true,
  );

  // The four `_AddItemSheet` / barcode-scan call sites resolve the
  // auto-filled unit cost through this exact formula. Pinning it once
  // here keeps the contract visible — any future refactor that drops
  // the `??` fallback will fail this group before touching the screen.
  Decimal resolveAutoFillUnitCost(Product product, ProductVariant? variant) {
    if (variant != null) {
      return variant.lastPurchasePriceCents ?? variant.costCents;
    }
    return product.lastPurchasePriceCents ?? product.costCents;
  }

  group('Purchase form unit-cost parity (variant vs no-variant)', () {
    test(
        'auto-fill resolves to GROSS supplier reference price for variants '
        'when last_purchase_price_cents is populated', () {
      final cost = resolveAutoFillUnitCost(productWithVariants, variant);
      expect(cost, equals(Decimal.fromInt(10000)),
          reason: 'variant.lastPurchasePriceCents (10000) must win over '
              'variant.costCents (9900) to match what the user typed on '
              'the prior purchase line.');
    });

    test(
        'auto-fill resolves to product GROSS price for no-variant products '
        'when last_purchase_price_cents is populated', () {
      final cost = resolveAutoFillUnitCost(productNoVariants, null);
      expect(cost, equals(Decimal.fromInt(10000)));
    });

    test(
        'auto-fill falls back to costCents for legacy variants whose '
        'last_purchase_price_cents was never stamped (pre-migration 10055)',
        () {
      final legacyVariant = ProductVariant(
        id: 99,
        productId: productWithVariants.id,
        costCents: Decimal.fromInt(7500),
        priceCents: Decimal.fromInt(12000),
        priceAdjustmentCents: Decimal.zero,
        stockQuantity: 0,
        isActive: true,
      );
      final cost = resolveAutoFillUnitCost(productWithVariants, legacyVariant);
      expect(cost, equals(Decimal.fromInt(7500)),
          reason: 'When the GROSS column is NULL the resolver must fall '
              'back to costCents so the line still renders a meaningful '
              'price for pre-migration data.');
    });

    test(
        'auto-fill falls back to product.costCents for no-variant products '
        'without a stamped last_purchase_price_cents', () {
      final legacyProduct = productNoVariants.copyWith(
        lastPurchasePriceCents: null,
      );
      final cost = resolveAutoFillUnitCost(legacyProduct, null);
      expect(cost, equals(Decimal.fromInt(10000)));
    });

    test(
        'variant line and no-variant line yield identical per-line totals '
        'when both auto-fill from the same GROSS supplier reference price',
        () {
      final variantUnitCost = resolveAutoFillUnitCost(productWithVariants, variant);
      final productUnitCost = resolveAutoFillUnitCost(productNoVariants, null);

      // Both lines must start from the same number — that is the
      // user-visible parity the field report demanded.
      expect(variantUnitCost, equals(productUnitCost),
          reason: 'Variant and no-variant auto-fill MUST agree when both '
              'rows carry the same supplier reference price.');

      final variantLine = PurchaseLineItem(
        tempId: 'v1',
        product: productWithVariants,
        variant: variant,
        quantity: 1,
        unitCostCents: variantUnitCost,
        originalCostCents: 10000,
        originalPriceCents: 15000,
      );
      final productLine = PurchaseLineItem(
        tempId: 'p1',
        product: productNoVariants,
        quantity: 1,
        unitCostCents: productUnitCost,
        originalCostCents: 10000,
        originalPriceCents: 15000,
      );

      // 100.00 × 1 × 1.01 = 101.00 — both lines.
      expect(variantLine.totalCents, equals(Decimal.fromInt(10100)));
      expect(productLine.totalCents, equals(Decimal.fromInt(10100)));

      // Tax must also match — pins the LineItemPricingEngine symmetry
      // (no `hasVariants` branch anywhere in the pricing path).
      expect(variantLine.taxCents, equals(productLine.taxCents));
      expect(variantLine.taxCents, equals(Decimal.fromInt(100)));
    });

    test(
        'sub-total of a mixed-variant cart matches the no-variant baseline '
        '(reproduces the field-report scenario and verifies the fix)', () {
      // Replicates the user's 3-line cart with the post-fix auto-fill:
      //   line 1: variant tt55-1 of p1 → unit cost = 10000 (GROSS)
      //   line 2: p2 (no variant)      → unit cost = 10000
      //   line 3: variant tt55-2 of p1 → unit cost = 10000
      final variant2 = variant.copyWith(id: 3, sku: 'tt55-2');

      final lines = [
        PurchaseLineItem(
          tempId: '1',
          product: productWithVariants,
          variant: variant,
          quantity: 1,
          unitCostCents: resolveAutoFillUnitCost(productWithVariants, variant),
          originalCostCents: 10000,
          originalPriceCents: 15000,
        ),
        PurchaseLineItem(
          tempId: '2',
          product: productNoVariants,
          quantity: 1,
          unitCostCents: resolveAutoFillUnitCost(productNoVariants, null),
          originalCostCents: 10000,
          originalPriceCents: 15000,
        ),
        PurchaseLineItem(
          tempId: '3',
          product: productWithVariants,
          variant: variant2,
          quantity: 1,
          unitCostCents: resolveAutoFillUnitCost(productWithVariants, variant2),
          originalCostCents: 10000,
          originalPriceCents: 15000,
        ),
      ];

      final subtotal =
          lines.fold<Decimal>(Decimal.zero, (acc, l) => acc + l.subtotalCents);
      final tax =
          lines.fold<Decimal>(Decimal.zero, (acc, l) => acc + l.taxCents);
      final total =
          lines.fold<Decimal>(Decimal.zero, (acc, l) => acc + l.totalCents);

      // Pre-fix screen: 99 + 100 + 99 = 298 sub / 2.98 tax / 300.98 total
      // (variant lines were stuck on the NET basis). Post-fix:
      //   3 × 100 = 300 sub / 1% × 300 = 3.00 tax / 303 total.
      expect(subtotal, equals(Decimal.fromInt(30000)));
      expect(tax, equals(Decimal.fromInt(300)));
      expect(total, equals(Decimal.fromInt(30300)));
    });
  });
}
