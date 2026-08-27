// ignore_for_file: invalid_use_of_visible_for_testing_member
//
// Phase-14 regression: discount-mode toggle on the sale form must clear
// the OTHER mode's discount inputs so a back-toggle cannot silently
// re-activate stale data and produce a "double-discount the user can't
// notice".
//
// Symmetric to:
//   test/features/purchases/purchase_form_discount_mode_toggle_test.dart
//
// SoT under test:
//   `SaleFormBloc._onDiscountModeChanged` (lib/features/sales/
//   presentation/bloc/sale_form_bloc.dart) — must mirror the proven
//   `SaleAdjReturnFormBloc._onDiscountModeChanged` reference pattern.

import 'package:bloc_test/bloc_test.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tapix/core/services/audit_log_service.dart';
import 'package:tapix/features/products/domain/entities/product_entity.dart';
import 'package:tapix/features/products/domain/repositories/product_repository.dart';
import 'package:tapix/features/products/domain/repositories/product_variant_repository.dart';
import 'package:tapix/features/sales/domain/repositories/sale_repository.dart';
import 'package:tapix/features/sales/presentation/bloc/sale_form_bloc.dart';

class _MockSaleRepository extends Mock implements SaleRepository {}

class _MockProductVariantRepository extends Mock
    implements ProductVariantRepository {}

class _MockProductRepository extends Mock implements ProductRepository {}

class _MockAuditLogService extends Mock implements AuditLogService {}

void main() {
  late _MockSaleRepository repo;
  late _MockProductVariantRepository variantRepo;
  late _MockProductRepository productRepo;
  late _MockAuditLogService audit;

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

  SaleLineItem buildLine({
    required String tempId,
    required int qty,
    required int unitPriceCents,
    int? discountCents,
  }) {
    return SaleLineItem(
      tempId: tempId,
      product: taxableProduct,
      quantity: qty,
      unitPriceCents: Decimal.fromInt(unitPriceCents),
      discountCents: discountCents != null
          ? Decimal.fromInt(discountCents)
          : null,
    );
  }

  setUp(() {
    repo = _MockSaleRepository();
    variantRepo = _MockProductVariantRepository();
    productRepo = _MockProductRepository();
    audit = _MockAuditLogService();
  });

  group('SaleFormBloc — discount-mode toggle clears other-mode inputs', () {
    blocTest<SaleFormBloc, SaleFormState>(
      'perItem -> invoice wipes per-line discountCents on every item',
      build: () => SaleFormBloc(repo, variantRepo, productRepo, audit),
      seed: () => SaleFormState(
        currencyId: 1,
        saleDate: DateTime(2026, 5, 18),
        discountMode: SaleDiscountMode.perItem,
        items: [
          buildLine(
            tempId: 'L1',
            qty: 1,
            unitPriceCents: 10000,
            discountCents: 500,
          ),
          buildLine(
            tempId: 'L2',
            qty: 2,
            unitPriceCents: 7500,
            discountCents: 1200,
          ),
        ],
      ),
      act: (bloc) =>
          bloc.add(const SaleDiscountModeChanged(SaleDiscountMode.invoice)),
      verify: (bloc) {
        final s = bloc.state;
        expect(s.discountMode, SaleDiscountMode.invoice);
        for (final item in s.items) {
          expect(
            item.discountCents,
            Decimal.zero,
            reason: 'line ${item.tempId} retained stale discount',
          );
        }
        expect(s.itemDiscountCents, Decimal.zero);
        expect(s.invoiceDiscountCents, Decimal.zero);
      },
    );

    blocTest<SaleFormBloc, SaleFormState>(
      'invoice -> perItem wipes invoice-level discount; lines stay clean',
      build: () => SaleFormBloc(repo, variantRepo, productRepo, audit),
      seed: () => SaleFormState(
        currencyId: 1,
        saleDate: DateTime(2026, 5, 18),
        discountMode: SaleDiscountMode.invoice,
        invoiceDiscountCents: Decimal.fromInt(2000),
        items: [buildLine(tempId: 'L1', qty: 1, unitPriceCents: 10000)],
      ),
      act: (bloc) =>
          bloc.add(const SaleDiscountModeChanged(SaleDiscountMode.perItem)),
      verify: (bloc) {
        final s = bloc.state;
        expect(s.discountMode, SaleDiscountMode.perItem);
        expect(s.invoiceDiscountCents, Decimal.zero);
        for (final item in s.items) {
          expect(item.discountCents, Decimal.zero);
        }
      },
    );

    blocTest<SaleFormBloc, SaleFormState>(
      'back-and-forth toggle never resurrects stale per-line discounts',
      build: () => SaleFormBloc(repo, variantRepo, productRepo, audit),
      seed: () => SaleFormState(
        currencyId: 1,
        saleDate: DateTime(2026, 5, 18),
        discountMode: SaleDiscountMode.perItem,
        items: [
          buildLine(
            tempId: 'L1',
            qty: 1,
            unitPriceCents: 10000,
            discountCents: 500,
          ),
        ],
      ),
      act: (bloc) async {
        bloc.add(const SaleDiscountModeChanged(SaleDiscountMode.invoice));
        await Future<void>.delayed(Duration.zero);
        bloc.add(const SaleDiscountModeChanged(SaleDiscountMode.perItem));
        await Future<void>.delayed(Duration.zero);
      },
      verify: (bloc) {
        final s = bloc.state;
        expect(s.discountMode, SaleDiscountMode.perItem);
        expect(
          s.items.single.discountCents,
          Decimal.zero,
          reason: 'switching invoice→perItem resurrected the wiped 500',
        );
        expect(s.itemDiscountCents, Decimal.zero);
        expect(s.totalDiscountCents, Decimal.zero);
      },
    );

    blocTest<SaleFormBloc, SaleFormState>(
      'line discount is checked against cost after the discount',
      build: () => SaleFormBloc(repo, variantRepo, productRepo, audit),
      seed: () => SaleFormState(
        currencyId: 1,
        saleDate: DateTime(2026, 8, 24),
        enableTaxCalculations: false,
        items: [buildLine(tempId: 'L1', qty: 1, unitPriceCents: 10000)],
      ),
      act: (bloc) => bloc.add(
        SaleLineItemUpdated(tempId: 'L1', discountCents: Decimal.fromInt(6000)),
      ),
      verify: (bloc) {
        expect(bloc.state.belowCostWarning?.isBelowCost, isTrue);
        expect(
          bloc.state.belowCostWarning?.sellingPriceCents,
          Decimal.fromInt(4000),
        );
      },
    );

    blocTest<SaleFormBloc, SaleFormState>(
      'invoice discount cannot bypass the below-cost final gate',
      build: () => SaleFormBloc(repo, variantRepo, productRepo, audit),
      seed: () => SaleFormState(
        currencyId: 1,
        saleDate: DateTime(2026, 8, 24),
        enableTaxCalculations: false,
        discountMode: SaleDiscountMode.invoice,
        invoiceDiscountCents: Decimal.fromInt(6000),
        items: [buildLine(tempId: 'L1', qty: 1, unitPriceCents: 10000)],
      ),
      act: (bloc) => bloc.add(const SaleFormSubmitted()),
      verify: (bloc) {
        expect(bloc.state.belowCostWarning?.isBelowCost, isTrue);
        expect(
          bloc.state.belowCostWarning?.sellingPriceCents,
          Decimal.fromInt(4000),
        );
        verifyZeroInteractions(repo);
      },
    );

    test('sanity: pricing engine masks per-line discount in invoice mode '
        '(defence-in-depth — books were always correct, but state leaked '
        'into the UI before Phase-14)', () {
      final state = SaleFormState(
        currencyId: 1,
        saleDate: DateTime(2026, 5, 18),
        discountMode: SaleDiscountMode.invoice,
        invoiceDiscountCents: Decimal.fromInt(1000),
        items: [
          SaleLineItem(
            tempId: 'L1',
            product: taxableProduct,
            quantity: 1,
            unitPriceCents: Decimal.fromInt(10000),
            discountCents: Decimal.fromInt(500), // stale
          ),
        ],
      );
      // Engine takes only the invoice discount (1000), per-line (500) is masked.
      expect(state.effectiveInvoiceDiscountCents, Decimal.fromInt(1000));
      expect(
        state.itemDiscountCents,
        Decimal.fromInt(500),
        reason:
            'getter still surfaces raw items field — '
            'this proves why state-level wiping (Phase-14) matters',
      );
    });
  });
}
