// ignore_for_file: invalid_use_of_visible_for_testing_member
//
// Phase-14 regression: discount-mode toggle must clear the OTHER mode's
// discount inputs so a back-toggle cannot silently re-activate stale data
// and produce a "double-discount the user can't notice".
//
// SoT under test:
//   `PurchaseFormBloc._onDiscountModeChanged` (lib/features/purchases/
//   presentation/bloc/purchase_form_bloc.dart) — must mirror the proven
//   `SaleAdjReturnFormBloc._onDiscountModeChanged` reference pattern.
//
// Banned pattern this test pins (see ACCOUNTING_INTEGRITY_GUIDELINES.md):
//   "Discount-mode handler that only zeroes invoiceDiscountCents/Percent
//    while leaving per-line `discountCents` populated on `state.items`."

import 'package:bloc_test/bloc_test.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tapix/features/products/domain/entities/product_entity.dart';
import 'package:tapix/features/products/domain/repositories/product_repository.dart';
import 'package:tapix/features/products/domain/repositories/product_variant_repository.dart';
import 'package:tapix/features/purchases/domain/repositories/purchase_repository.dart';
import 'package:tapix/features/purchases/presentation/bloc/purchase_form_bloc.dart';

class _MockPurchaseRepository extends Mock implements PurchaseRepository {}

class _MockProductVariantRepository extends Mock
    implements ProductVariantRepository {}

class _MockProductRepository extends Mock implements ProductRepository {}

void main() {
  late _MockPurchaseRepository repo;
  late _MockProductVariantRepository variantRepo;
  late _MockProductRepository productRepo;

  final taxableProduct = Product(
    id: 1,
    name: 'Taxable',
    costCents: Decimal.fromInt(5000),
    priceCents: Decimal.fromInt(10000),
    stockQuantity: 100,
    minQuantity: 0,
    hasVariants: false,
    isTaxable: true,
    purchaseTaxRateBps: 1000,
    salesTaxRateBps: 1500,
    isActive: true,
    trackInventory: true,
  );

  PurchaseLineItem buildLine({
    required String tempId,
    required int qty,
    required int unitCostCents,
    int? discountCents,
  }) {
    return PurchaseLineItem(
      tempId: tempId,
      product: taxableProduct,
      quantity: qty,
      unitCostCents: Decimal.fromInt(unitCostCents),
      discountCents:
          discountCents != null ? Decimal.fromInt(discountCents) : null,
      originalCostCents: unitCostCents,
      originalPriceCents: unitCostCents * 2,
    );
  }

  setUp(() {
    repo = _MockPurchaseRepository();
    variantRepo = _MockProductVariantRepository();
    productRepo = _MockProductRepository();
  });

  group('PurchaseFormBloc — discount-mode toggle clears other-mode inputs', () {
    blocTest<PurchaseFormBloc, PurchaseFormState>(
      'perItem -> invoice wipes per-line discountCents on every item',
      build: () => PurchaseFormBloc(repo, variantRepo, productRepo),
      seed: () => PurchaseFormState(
        currencyId: 1,
        purchaseDate: DateTime(2026, 5, 18),
        discountMode: DiscountMode.perItem,
        items: [
          buildLine(tempId: 'L1', qty: 1, unitCostCents: 10000, discountCents: 500),
          buildLine(tempId: 'L2', qty: 2, unitCostCents: 7500, discountCents: 1200),
        ],
      ),
      act: (bloc) => bloc
          .add(const PurchaseDiscountModeChanged(DiscountMode.invoice)),
      verify: (bloc) {
        final s = bloc.state;
        expect(s.discountMode, DiscountMode.invoice);
        // EVERY line's per-line discount must be zero after the switch.
        for (final item in s.items) {
          expect(item.discountCents, Decimal.zero,
              reason: 'line ${item.tempId} retained stale discount');
        }
        // Engine view also confirms — itemDiscountCents must be zero.
        expect(s.itemDiscountCents, Decimal.zero);
        // Invoice discount fields stay zero (no double-credit).
        expect(s.invoiceDiscountCents, Decimal.zero);
        expect(s.invoiceDiscountPercent, Decimal.zero);
      },
    );

    blocTest<PurchaseFormBloc, PurchaseFormState>(
      'invoice -> perItem wipes invoice-level discount; lines stay clean',
      build: () => PurchaseFormBloc(repo, variantRepo, productRepo),
      seed: () => PurchaseFormState(
        currencyId: 1,
        purchaseDate: DateTime(2026, 5, 18),
        discountMode: DiscountMode.invoice,
        invoiceDiscountCents: Decimal.fromInt(2000),
        invoiceDiscountPercent: Decimal.fromInt(5),
        items: [
          buildLine(tempId: 'L1', qty: 1, unitCostCents: 10000),
        ],
      ),
      act: (bloc) => bloc
          .add(const PurchaseDiscountModeChanged(DiscountMode.perItem)),
      verify: (bloc) {
        final s = bloc.state;
        expect(s.discountMode, DiscountMode.perItem);
        expect(s.invoiceDiscountCents, Decimal.zero);
        expect(s.invoiceDiscountPercent, Decimal.zero);
        for (final item in s.items) {
          expect(item.discountCents, Decimal.zero);
        }
      },
    );

    blocTest<PurchaseFormBloc, PurchaseFormState>(
      'back-and-forth toggle never resurrects stale per-line discounts',
      build: () => PurchaseFormBloc(repo, variantRepo, productRepo),
      seed: () => PurchaseFormState(
        currencyId: 1,
        purchaseDate: DateTime(2026, 5, 18),
        discountMode: DiscountMode.perItem,
        items: [
          buildLine(tempId: 'L1', qty: 1, unitCostCents: 10000, discountCents: 500),
        ],
      ),
      act: (bloc) async {
        bloc.add(const PurchaseDiscountModeChanged(DiscountMode.invoice));
        await Future<void>.delayed(Duration.zero);
        bloc.add(const PurchaseDiscountModeChanged(DiscountMode.perItem));
        await Future<void>.delayed(Duration.zero);
      },
      verify: (bloc) {
        final s = bloc.state;
        expect(s.discountMode, DiscountMode.perItem);
        expect(s.items.single.discountCents, Decimal.zero,
            reason: 'switching invoice→perItem resurrected the wiped 500');
        expect(s.itemDiscountCents, Decimal.zero);
        // Total discount is now genuinely zero — no double-credit possible.
        expect(s.totalDiscountCents, Decimal.zero);
      },
    );

    test(
        'sanity: pricing engine already masks per-line discount in invoice mode '
        '(defence-in-depth — the bug never reached the books, but state '
        'leaked into the UI before Phase-14)', () {
      // Construct a state that simulates the PRE-FIX bug: invoice mode
      // selected but per-line discounts still populated. The persisted
      // engine output must still be correct (Q3 mode-exclusivity at
      // compute-time).
      final state = PurchaseFormState(
        currencyId: 1,
        purchaseDate: DateTime(2026, 5, 18),
        discountMode: DiscountMode.invoice,
        invoiceDiscountCents: Decimal.fromInt(1000),
        items: [
          PurchaseLineItem(
            tempId: 'L1',
            product: taxableProduct,
            quantity: 1,
            unitCostCents: Decimal.fromInt(10000),
            discountCents: Decimal.fromInt(500), // stale
            originalCostCents: 10000,
            originalPriceCents: 20000,
          ),
        ],
      );
      // Engine takes only the invoice discount (1000), per-line (500) is masked.
      expect(state.totalDiscountCents, Decimal.fromInt(1000));
    });
  });
}
