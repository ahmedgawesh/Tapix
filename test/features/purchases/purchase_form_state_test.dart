import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/features/products/domain/entities/product_entity.dart';
import 'package:tapix/features/purchases/presentation/bloc/purchase_form_bloc.dart';

void main() {
  final testProduct = Product(
    id: 1,
    name: 'Test Product',
    sku: 'SKU-001',
    costCents: Decimal.fromInt(5000),
    priceCents: Decimal.fromInt(10000),
    stockQuantity: 100,
    minQuantity: 0,
    hasVariants: false,
    isTaxable: true,
    purchaseTaxRateBps: 1000, // 10%
    salesTaxRateBps: 1500,
    isActive: true,
    trackInventory: true,
  );

  group('PurchaseFormState', () {
    test('initial state has correct defaults', () {
      final state = PurchaseFormState(
        currencyId: 1,
        purchaseDate: DateTime(2026, 1, 15),
      );

      expect(state.items, isEmpty);
      expect(state.discountMode, DiscountMode.perItem);
      expect(state.paymentMethod, PurchasePaymentMethod.cash);
      expect(state.isSubmitting, isFalse);
      expect(state.isSuccess, isFalse);
      expect(state.error, isNull);
      expect(state.isDraft, isTrue);
    });

    test('subtotalCents calculates sum of item subtotals', () {
      final state = PurchaseFormState(
        currencyId: 1,
        purchaseDate: DateTime(2026, 1, 15),
        items: [
          PurchaseLineItem(
            tempId: '1',
            product: testProduct,
            quantity: 2,
            unitCostCents: Decimal.fromInt(5000),
            originalCostCents: 5000,
            originalPriceCents: 10000,
          ),
          PurchaseLineItem(
            tempId: '2',
            product: testProduct,
            quantity: 3,
            unitCostCents: Decimal.fromInt(3000),
            originalCostCents: 3000,
            originalPriceCents: 6000,
          ),
        ],
      );

      // 2 * 5000 + 3 * 3000 = 19000
      expect(state.subtotalCents, equals(Decimal.fromInt(19000)));
    });

    test('totalDiscountCents uses item discounts in perItem mode', () {
      final state = PurchaseFormState(
        currencyId: 1,
        purchaseDate: DateTime(2026, 1, 15),
        discountMode: DiscountMode.perItem,
        items: [
          PurchaseLineItem(
            tempId: '1',
            product: testProduct,
            quantity: 1,
            unitCostCents: Decimal.fromInt(5000),
            discountCents: Decimal.fromInt(500),
            originalCostCents: 5000,
            originalPriceCents: 10000,
          ),
          PurchaseLineItem(
            tempId: '2',
            product: testProduct,
            quantity: 1,
            unitCostCents: Decimal.fromInt(3000),
            discountCents: Decimal.fromInt(300),
            originalCostCents: 3000,
            originalPriceCents: 6000,
          ),
        ],
      );

      expect(state.totalDiscountCents, equals(Decimal.fromInt(800)));
    });

    test('totalDiscountCents uses invoice discount in invoice mode', () {
      final state = PurchaseFormState(
        currencyId: 1,
        purchaseDate: DateTime(2026, 1, 15),
        discountMode: DiscountMode.invoice,
        invoiceDiscountCents: Decimal.fromInt(1000),
        items: [
          PurchaseLineItem(
            tempId: '1',
            product: testProduct,
            quantity: 1,
            unitCostCents: Decimal.fromInt(5000),
            discountCents: Decimal.fromInt(500), // Should be ignored
            originalCostCents: 5000,
            originalPriceCents: 10000,
          ),
        ],
      );

      expect(state.totalDiscountCents, equals(Decimal.fromInt(1000)));
    });

    test('effectiveInvoiceDiscountCents reflects the fixed invoice discount', () {
      final state = PurchaseFormState(
        currencyId: 1,
        purchaseDate: DateTime(2026, 1, 15),
        discountMode: DiscountMode.invoice,
        // Fixed cents is the single source of truth; the UI converts any
        // typed percentage to cents before it reaches the state.
        invoiceDiscountCents: Decimal.fromInt(1000), // 10% of 10000¢
        items: [
          PurchaseLineItem(
            tempId: '1',
            product: testProduct,
            quantity: 1,
            unitCostCents: Decimal.fromInt(10000),
            originalCostCents: 10000,
            originalPriceCents: 20000,
          ),
        ],
      );

      expect(state.effectiveInvoiceDiscountCents, equals(Decimal.fromInt(1000)));
    });

    test('totalCents calculates correctly with tax', () {
      final state = PurchaseFormState(
        currencyId: 1,
        purchaseDate: DateTime(2026, 1, 15),
        enableTaxCalculations: true,
        defaultPurchaseTaxRateBps: 0,
        items: [
          PurchaseLineItem(
            tempId: '1',
            product: testProduct, // 10% tax rate
            quantity: 1,
            unitCostCents: Decimal.fromInt(10000),
            originalCostCents: 10000,
            originalPriceCents: 20000,
          ),
        ],
      );

      // Subtotal: 10000, Tax: 10000 * 10% = 1000, Total: 11000
      expect(state.subtotalCents, equals(Decimal.fromInt(10000)));
      expect(state.taxCents, equals(Decimal.fromInt(1000)));
      expect(state.totalCents, equals(Decimal.fromInt(11000)));
    });

    test('remainingCents calculates correctly', () {
      final nonTaxableProduct = Product(
        id: 2,
        name: 'Non-Taxable',
        costCents: Decimal.fromInt(5000),
        priceCents: Decimal.fromInt(10000),
        stockQuantity: 100,
        minQuantity: 0,
        hasVariants: false,
        isTaxable: false,
        purchaseTaxRateBps: 0,
        salesTaxRateBps: 0,
        isActive: true,
        trackInventory: true,
      );
      
      final state = PurchaseFormState(
        currencyId: 1,
        purchaseDate: DateTime(2026, 1, 15),
        enableTaxCalculations: false,
        paidAmountCents: Decimal.fromInt(3000),
        items: [
          PurchaseLineItem(
            tempId: '1',
            product: nonTaxableProduct,
            quantity: 1,
            unitCostCents: Decimal.fromInt(10000),
            originalCostCents: 10000,
            originalPriceCents: 20000,
          ),
        ],
      );

      // Total: 10000, Paid: 3000, Remaining: 7000
      expect(state.remainingCents, equals(Decimal.fromInt(7000)));
    });

    test('changeCents calculates correctly when overpaid', () {
      final nonTaxableProduct = Product(
        id: 2,
        name: 'Non-Taxable',
        costCents: Decimal.fromInt(5000),
        priceCents: Decimal.fromInt(10000),
        stockQuantity: 100,
        minQuantity: 0,
        hasVariants: false,
        isTaxable: false,
        purchaseTaxRateBps: 0,
        salesTaxRateBps: 0,
        isActive: true,
        trackInventory: true,
      );
      
      final state = PurchaseFormState(
        currencyId: 1,
        purchaseDate: DateTime(2026, 1, 15),
        enableTaxCalculations: false,
        paidAmountCents: Decimal.fromInt(12000),
        items: [
          PurchaseLineItem(
            tempId: '1',
            product: nonTaxableProduct,
            quantity: 1,
            unitCostCents: Decimal.fromInt(10000),
            originalCostCents: 10000,
            originalPriceCents: 20000,
          ),
        ],
      );

      // Total: 10000, Paid: 12000, Change: 2000
      expect(state.changeCents, equals(Decimal.fromInt(2000)));
    });

    test('totalQuantity sums all item quantities', () {
      final state = PurchaseFormState(
        currencyId: 1,
        purchaseDate: DateTime(2026, 1, 15),
        items: [
          PurchaseLineItem(
            tempId: '1',
            product: testProduct,
            quantity: 5,
            unitCostCents: Decimal.fromInt(5000),
            originalCostCents: 5000,
            originalPriceCents: 10000,
          ),
          PurchaseLineItem(
            tempId: '2',
            product: testProduct,
            quantity: 3,
            unitCostCents: Decimal.fromInt(3000),
            originalCostCents: 3000,
            originalPriceCents: 6000,
          ),
        ],
      );

      expect(state.totalQuantity, equals(8));
    });

    test('isDraft returns true when purchaseId is null', () {
      final draftState = PurchaseFormState(
        currencyId: 1,
        purchaseDate: DateTime(2026, 1, 15),
      );
      expect(draftState.isDraft, isTrue);

      final savedState = PurchaseFormState(
        purchaseId: 1,
        currencyId: 1,
        purchaseDate: DateTime(2026, 1, 15),
      );
      expect(savedState.isDraft, isFalse);
    });
  });

  group('PurchaseLineItem', () {
    test('subtotalCents calculates quantity * unitCost', () {
      final item = PurchaseLineItem(
        tempId: '1',
        product: testProduct,
        quantity: 4,
        unitCostCents: Decimal.fromInt(5000),
        originalCostCents: 5000,
        originalPriceCents: 10000,
      );

      expect(item.subtotalCents, equals(Decimal.fromInt(20000)));
    });

    test('netCents subtracts discount from subtotal', () {
      final item = PurchaseLineItem(
        tempId: '1',
        product: testProduct,
        quantity: 2,
        unitCostCents: Decimal.fromInt(5000),
        discountCents: Decimal.fromInt(1000),
        originalCostCents: 5000,
        originalPriceCents: 10000,
      );

      // Subtotal: 10000, Discount: 1000, Net: 9000
      expect(item.netCents, equals(Decimal.fromInt(9000)));
    });

    test('taxCentsWithSettings uses product tax rate when available', () {
      final item = PurchaseLineItem(
        tempId: '1',
        product: testProduct, // 10% purchase tax rate
        quantity: 1,
        unitCostCents: Decimal.fromInt(10000),
        originalCostCents: 10000,
        originalPriceCents: 20000,
      );

      final tax = item.taxCentsWithSettings(
        enableTaxCalculations: true,
        defaultTaxRateBps: 500, // 5% default - should be ignored
      );

      // Uses product's 10% rate: 10000 * 0.10 = 1000
      expect(tax, equals(Decimal.fromInt(1000)));
    });

    test('taxCentsWithSettings returns zero when tax disabled', () {
      final item = PurchaseLineItem(
        tempId: '1',
        product: testProduct,
        quantity: 1,
        unitCostCents: Decimal.fromInt(10000),
        originalCostCents: 10000,
        originalPriceCents: 20000,
      );

      final tax = item.taxCentsWithSettings(
        enableTaxCalculations: false,
        defaultTaxRateBps: 1000,
      );

      expect(tax, equals(Decimal.zero));
    });

    test('displayName shows product name only when no variant info', () {
      final item = PurchaseLineItem(
        tempId: '1',
        product: testProduct,
        quantity: 1,
        unitCostCents: Decimal.fromInt(5000),
        originalCostCents: 5000,
        originalPriceCents: 10000,
      );

      expect(item.displayName, equals('Test Product'));
    });
  });
}
