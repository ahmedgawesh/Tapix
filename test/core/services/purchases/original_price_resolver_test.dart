import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/services/purchases/original_price_resolver.dart';
import 'package:tapix/features/products/domain/entities/product_entity.dart';
import 'package:tapix/features/products/domain/entities/product_variant_entity.dart';

/// Centralized resolver tests — exhaustive coverage of:
///   * variant present vs no variant
///   * inventory tracking modes (orthogonal, but exercised via [Product])
///   * saved snapshot present (>0) vs zero (legacy default-init) vs null
///   * variant.previous fallback when current is 0
///   * wholesale `null` semantics (genuine absence vs default-init 0)
///   * persist-vs-display divergence for the default-init case
void main() {
  // ───── helpers ─────────────────────────────────────────────────────────
  Product makeProduct({
    int costCents = 0,
    int priceCents = 0,
    int? wholesaleCents,
    int? prevCostCents,
    int? prevPriceCents,
    int? prevWholesaleCents,
    bool hasVariants = false,
    String inventoryTrackingType = 'standard',
  }) {
    return Product(
      id: 1,
      name: 'P',
      costCents: Decimal.fromInt(costCents),
      priceCents: Decimal.fromInt(priceCents),
      wholesalePriceCents:
          wholesaleCents != null ? Decimal.fromInt(wholesaleCents) : null,
      previousCostCents:
          prevCostCents != null ? Decimal.fromInt(prevCostCents) : null,
      previousPriceCents:
          prevPriceCents != null ? Decimal.fromInt(prevPriceCents) : null,
      previousWholesalePriceCents: prevWholesaleCents != null
          ? Decimal.fromInt(prevWholesaleCents)
          : null,
      stockQuantity: 0,
      minQuantity: 0,
      hasVariants: hasVariants,
      isTaxable: false,
      purchaseTaxRateBps: 0,
      salesTaxRateBps: 0,
      isActive: true,
      trackInventory: true,
      inventoryTrackingType: inventoryTrackingType,
    );
  }

  ProductVariant makeVariant({
    int costCents = 0,
    int priceCents = 0,
    int? wholesaleCents,
    int? prevCostCents,
    int? prevPriceCents,
    int? prevWholesaleCents,
  }) {
    return ProductVariant(
      id: 100,
      productId: 1,
      costCents: Decimal.fromInt(costCents),
      priceCents: Decimal.fromInt(priceCents),
      wholesalePriceCents:
          wholesaleCents != null ? Decimal.fromInt(wholesaleCents) : null,
      previousCostCents:
          prevCostCents != null ? Decimal.fromInt(prevCostCents) : null,
      previousPriceCents:
          prevPriceCents != null ? Decimal.fromInt(prevPriceCents) : null,
      previousWholesalePriceCents: prevWholesaleCents != null
          ? Decimal.fromInt(prevWholesaleCents)
          : null,
      priceAdjustmentCents: Decimal.zero,
      stockQuantity: 0,
      isActive: true,
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // captureForNewLine: live capture, no saved snapshot
  // ─────────────────────────────────────────────────────────────────────

  group('captureForNewLine — variant', () {
    test('uses variant current values (cost/price/wholesale all > 0)', () {
      final product = makeProduct(hasVariants: true);
      final variant = makeVariant(
        costCents: 5000,
        priceCents: 9000,
        wholesaleCents: 7500,
      );
      final s = OriginalPriceResolver.captureForNewLine(
        product: product,
        variant: variant,
      );
      expect(s.costCents, 5000);
      expect(s.priceCents, 9000);
      expect(s.wholesalePriceCents, 7500);
      expect(s.persistCostCents, 5000);
      expect(s.persistPriceCents, 9000);
      expect(s.persistWholesalePriceCents, 7500);
    });

    test('falls back to variant.previous when current is 0', () {
      final product = makeProduct(hasVariants: true);
      final variant = makeVariant(
        costCents: 0,
        priceCents: 0,
        wholesaleCents: 0,
        prevCostCents: 4000,
        prevPriceCents: 6000,
        prevWholesaleCents: 5000,
      );
      final s = OriginalPriceResolver.captureForNewLine(
        product: product,
        variant: variant,
      );
      expect(s.costCents, 4000);
      expect(s.priceCents, 6000);
      expect(s.wholesalePriceCents, 5000);
      // Display falls through to previous, so persistence captures previous too
      expect(s.persistCostCents, 4000);
      expect(s.persistPriceCents, 6000);
      expect(s.persistWholesalePriceCents, 5000);
    });

    test(
        'brand-new variant (cost=0, price=0, no previous, wholesale null) '
        'displays 0 but persists null — root fix for the "0.00 in old price" bug',
        () {
      final product = makeProduct(hasVariants: true, costCents: 999, priceCents: 999);
      final variant = makeVariant(
        costCents: 0,
        priceCents: 0,
        wholesaleCents: null,
      );
      final s = OriginalPriceResolver.captureForNewLine(
        product: product,
        variant: variant,
      );
      expect(s.costCents, 0);
      expect(s.priceCents, 0);
      expect(s.wholesalePriceCents, isNull);
      // KEY ASSERTIONS: persist null (not 0) when there is no real history.
      // A future re-load will fall back through the resolver chain instead of
      // freezing a meaningless 0 in the DB.
      expect(s.persistCostCents, isNull);
      expect(s.persistPriceCents, isNull);
      expect(s.persistWholesalePriceCents, isNull);
    });

    test(
        'never bubbles up to product-level when variant exists (sibling-leak guard)',
        () {
      // The products row aggregate keeps MAX(variant.wholesale) for legacy
      // reporting. If we fell through to product.wholesalePriceCents from a
      // variant whose wholesale is null, we would leak a sibling variant's
      // value. The resolver MUST stay strictly inside the variant.
      final product = makeProduct(
        hasVariants: true,
        costCents: 12345,
        priceCents: 67890,
        wholesaleCents: 99999, // sibling variant's MAX would land here
      );
      final variant = makeVariant(
        costCents: 5000,
        priceCents: 9000,
        wholesaleCents: null, // this variant has NO wholesale
      );
      final s = OriginalPriceResolver.captureForNewLine(
        product: product,
        variant: variant,
      );
      expect(s.costCents, 5000);
      expect(s.priceCents, 9000);
      // CRITICAL: must be null, not 99999. Wholesale must NEVER leak from
      // product-level when a variant is present.
      expect(s.wholesalePriceCents, isNull);
      expect(s.persistWholesalePriceCents, isNull);
    });
  });

  group('captureForNewLine — no variant', () {
    test('uses product current values', () {
      final product = makeProduct(
        costCents: 3000,
        priceCents: 7000,
        wholesaleCents: 5500,
      );
      final s = OriginalPriceResolver.captureForNewLine(
        product: product,
        variant: null,
      );
      expect(s.costCents, 3000);
      expect(s.priceCents, 7000);
      expect(s.wholesalePriceCents, 5500);
      expect(s.persistCostCents, 3000);
      expect(s.persistPriceCents, 7000);
      expect(s.persistWholesalePriceCents, 5500);
    });

    test('falls back to product.previous when current is 0', () {
      final product = makeProduct(
        costCents: 0,
        priceCents: 0,
        prevCostCents: 2500,
        prevPriceCents: 4500,
      );
      final s = OriginalPriceResolver.captureForNewLine(
        product: product,
        variant: null,
      );
      expect(s.costCents, 2500);
      expect(s.priceCents, 4500);
      expect(s.persistCostCents, 2500);
      expect(s.persistPriceCents, 4500);
    });

    test('brand-new no-variant product persists nulls when everything is 0', () {
      final product = makeProduct(costCents: 0, priceCents: 0);
      final s = OriginalPriceResolver.captureForNewLine(
        product: product,
        variant: null,
      );
      expect(s.costCents, 0);
      expect(s.priceCents, 0);
      expect(s.persistCostCents, isNull);
      expect(s.persistPriceCents, isNull);
      expect(s.persistWholesalePriceCents, isNull);
    });
  });

  // ─────────────────────────────────────────────────────────────────────
  // resolveForEdit: saved snapshot priority
  // ─────────────────────────────────────────────────────────────────────

  group('resolveForEdit — saved snapshot present', () {
    test('saved values > 0 take priority over live values', () {
      final product = makeProduct(hasVariants: true);
      final variant = makeVariant(costCents: 9999, priceCents: 9999);
      final s = OriginalPriceResolver.resolveForEdit(
        product: product,
        variant: variant,
        savedCostCents: 5000,
        savedPriceCents: 7000,
        savedWholesalePriceCents: 6000,
      );
      // Saved snapshot wins — it represents the historical state at the time
      // of the original purchase.
      expect(s.costCents, 5000);
      expect(s.priceCents, 7000);
      expect(s.wholesalePriceCents, 6000);
      expect(s.persistCostCents, 5000);
      expect(s.persistPriceCents, 7000);
      expect(s.persistWholesalePriceCents, 6000);
    });

    test('saved 0 is treated as MISSING (legacy default-init), falls through', () {
      // This is the screenshot bug: the original purchase saved
      // originalCostCents = 0 because the variant was freshly created.
      // The resolver must NOT display 0.00 — it must fall back to the live
      // variant value (which by now has been updated to a real cost).
      final product = makeProduct(hasVariants: true);
      final variant = makeVariant(
        costCents: 70 * 100, // 70.00 — current live cost (post WAC update)
        priceCents: 100 * 100,
        wholesaleCents: 90 * 100,
      );
      final s = OriginalPriceResolver.resolveForEdit(
        product: product,
        variant: variant,
        savedCostCents: 0, // legacy zero
        savedPriceCents: 0,
        savedWholesalePriceCents: 0,
      );
      expect(s.costCents, 7000, reason: 'saved 0 must fall through to live');
      expect(s.priceCents, 10000);
      expect(s.wholesalePriceCents, 9000);
      // Persist should re-snapshot the live values (which are now real).
      expect(s.persistCostCents, 7000);
      expect(s.persistPriceCents, 10000);
      expect(s.persistWholesalePriceCents, 9000);
    });

    test('saved null falls through to live (the original null-fallback case)', () {
      final product = makeProduct(hasVariants: true);
      final variant = makeVariant(costCents: 4000, priceCents: 8000);
      final s = OriginalPriceResolver.resolveForEdit(
        product: product,
        variant: variant,
        savedCostCents: null,
        savedPriceCents: null,
        savedWholesalePriceCents: null,
      );
      expect(s.costCents, 4000);
      expect(s.priceCents, 8000);
    });

    test('mixed: saved cost > 0 honored, saved price = 0 falls through', () {
      final product = makeProduct(hasVariants: true);
      final variant = makeVariant(costCents: 9000, priceCents: 7000);
      final s = OriginalPriceResolver.resolveForEdit(
        product: product,
        variant: variant,
        savedCostCents: 5000, // honored
        savedPriceCents: 0,   // legacy zero → fallback
      );
      expect(s.costCents, 5000);
      expect(s.priceCents, 7000);
    });
  });

  group('resolveForEdit — wholesale-leak guard with saved snapshot', () {
    test(
        'when saved wholesale is 0 and variant wholesale is null, NEVER bubble '
        'up to product wholesale (sibling variant leak)', () {
      final product = makeProduct(
        hasVariants: true,
        wholesaleCents: 99999, // poisoned aggregate from sibling variant
      );
      final variant = makeVariant(
        costCents: 1000,
        priceCents: 2000,
        wholesaleCents: null,
      );
      final s = OriginalPriceResolver.resolveForEdit(
        product: product,
        variant: variant,
        savedCostCents: 1000,
        savedPriceCents: 2000,
        savedWholesalePriceCents: 0, // legacy zero
      );
      // CRITICAL: must NOT be 99999. Sibling-variant wholesale must never leak.
      expect(s.wholesalePriceCents, isNull);
      expect(s.persistWholesalePriceCents, isNull);
    });
  });

  // ─────────────────────────────────────────────────────────────────────
  // Inventory-tracking-type orthogonality
  // ─────────────────────────────────────────────────────────────────────

  group('inventory tracking type is orthogonal to price resolution', () {
    test('standard / batch / batch_expiry resolve identically', () {
      for (final type in const ['standard', 'batch', 'batch_expiry']) {
        final product = makeProduct(
          inventoryTrackingType: type,
          costCents: 1234,
          priceCents: 5678,
        );
        final s = OriginalPriceResolver.captureForNewLine(
          product: product,
          variant: null,
        );
        expect(s.costCents, 1234, reason: 'failed for tracking type=$type');
        expect(s.priceCents, 5678, reason: 'failed for tracking type=$type');
      }
    });
  });
}
