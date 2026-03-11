import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/features/products/domain/entities/product_entity.dart';
import 'package:tapix/features/sales/presentation/bloc/sale_form_bloc.dart';

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
    purchaseTaxRateBps: 1000,
    salesTaxRateBps: 1500, // 15%
    isActive: true,
    trackInventory: true,
  );

  group('SaleFormState', () {
    test('initial state has correct defaults', () {
      final state = SaleFormState(
        currencyId: 1,
        saleDate: DateTime(2026, 1, 15),
      );

      expect(state.items, isEmpty);
      expect(state.discountMode, SaleDiscountMode.perItem);
      expect(state.paymentMethod, SalePaymentMethod.cash);
      expect(state.isSubmitting, isFalse);
      expect(state.isSuccess, isFalse);
      expect(state.error, isNull);
    });

    test('subtotalCents calculates sum of item subtotals', () {
      final state = SaleFormState(
        currencyId: 1,
        saleDate: DateTime(2026, 1, 15),
        items: [
          SaleLineItem(
            tempId: '1',
            product: testProduct,
            quantity: 2,
            unitPriceCents: Decimal.fromInt(10000),
          ),
          SaleLineItem(
            tempId: '2',
            product: testProduct,
            quantity: 1,
            unitPriceCents: Decimal.fromInt(5000),
          ),
        ],
      );

      // 2 * 10000 + 1 * 5000 = 25000
      expect(state.subtotalCents, equals(Decimal.fromInt(25000)));
    });

    test('totalDiscountCents uses item discounts in perItem mode', () {
      final state = SaleFormState(
        currencyId: 1,
        saleDate: DateTime(2026, 1, 15),
        discountMode: SaleDiscountMode.perItem,
        items: [
          SaleLineItem(
            tempId: '1',
            product: testProduct,
            quantity: 1,
            unitPriceCents: Decimal.fromInt(10000),
            discountCents: Decimal.fromInt(1000),
          ),
          SaleLineItem(
            tempId: '2',
            product: testProduct,
            quantity: 1,
            unitPriceCents: Decimal.fromInt(5000),
            discountCents: Decimal.fromInt(500),
          ),
        ],
      );

      expect(state.totalDiscountCents, equals(Decimal.fromInt(1500)));
    });

    test('totalDiscountCents uses invoice discount in invoice mode', () {
      final state = SaleFormState(
        currencyId: 1,
        saleDate: DateTime(2026, 1, 15),
        discountMode: SaleDiscountMode.invoice,
        invoiceDiscountCents: Decimal.fromInt(2000),
        items: [
          SaleLineItem(
            tempId: '1',
            product: testProduct,
            quantity: 1,
            unitPriceCents: Decimal.fromInt(10000),
            discountCents: Decimal.fromInt(1000), // Should be ignored
          ),
        ],
      );

      expect(state.totalDiscountCents, equals(Decimal.fromInt(2000)));
    });

    test('totalCents calculates correctly with tax', () {
      final state = SaleFormState(
        currencyId: 1,
        saleDate: DateTime(2026, 1, 15),
        enableTaxCalculations: true,
        defaultSalesTaxRateBps: 0,
        items: [
          SaleLineItem(
            tempId: '1',
            product: testProduct, // 15% tax rate
            quantity: 1,
            unitPriceCents: Decimal.fromInt(10000),
          ),
        ],
      );

      // Subtotal: 10000, Tax: 10000 * 15% = 1500, Total: 11500
      expect(state.subtotalCents, equals(Decimal.fromInt(10000)));
      expect(state.taxCents, equals(Decimal.fromInt(1500)));
      expect(state.totalCents, equals(Decimal.fromInt(11500)));
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
      
      final state = SaleFormState(
        currencyId: 1,
        saleDate: DateTime(2026, 1, 15),
        enableTaxCalculations: false,
        paidAmountCents: Decimal.fromInt(5000),
        items: [
          SaleLineItem(
            tempId: '1',
            product: nonTaxableProduct,
            quantity: 1,
            unitPriceCents: Decimal.fromInt(10000),
          ),
        ],
      );

      // Total: 10000, Paid: 5000, Remaining: 5000
      expect(state.remainingCents, equals(Decimal.fromInt(5000)));
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
      
      final state = SaleFormState(
        currencyId: 1,
        saleDate: DateTime(2026, 1, 15),
        enableTaxCalculations: false,
        paidAmountCents: Decimal.fromInt(12000),
        items: [
          SaleLineItem(
            tempId: '1',
            product: nonTaxableProduct,
            quantity: 1,
            unitPriceCents: Decimal.fromInt(10000),
          ),
        ],
      );

      // Total: 10000, Paid: 12000, Change: 2000
      expect(state.changeCents, equals(Decimal.fromInt(2000)));
    });

    test('totalQuantity sums all item quantities', () {
      final state = SaleFormState(
        currencyId: 1,
        saleDate: DateTime(2026, 1, 15),
        items: [
          SaleLineItem(
            tempId: '1',
            product: testProduct,
            quantity: 3,
            unitPriceCents: Decimal.fromInt(10000),
          ),
          SaleLineItem(
            tempId: '2',
            product: testProduct,
            quantity: 2,
            unitPriceCents: Decimal.fromInt(5000),
          ),
        ],
      );

      expect(state.totalQuantity, equals(5));
    });

    test('copyWith preserves values correctly', () {
      final original = SaleFormState(
        currencyId: 1,
        saleDate: DateTime(2026, 1, 15),
        customerId: 1,
        customerName: 'Test Customer',
      );

      final copied = original.copyWith(
        employeeId: 5,
        employeeName: 'Test Employee',
      );

      expect(copied.customerId, equals(1));
      expect(copied.customerName, equals('Test Customer'));
      expect(copied.employeeId, equals(5));
      expect(copied.employeeName, equals('Test Employee'));
    });

    test('copyWith with clearCustomer removes customer', () {
      final original = SaleFormState(
        currencyId: 1,
        saleDate: DateTime(2026, 1, 15),
        customerId: 1,
        customerName: 'Test Customer',
      );

      final copied = original.copyWith(clearCustomer: true);

      expect(copied.customerId, isNull);
      expect(copied.customerName, isNull);
    });
  });

  group('SaleLineItem', () {
    test('subtotalCents calculates quantity * unitPrice', () {
      final item = SaleLineItem(
        tempId: '1',
        product: testProduct,
        quantity: 3,
        unitPriceCents: Decimal.fromInt(10000),
      );

      expect(item.subtotalCents, equals(Decimal.fromInt(30000)));
    });

    test('netCents subtracts discount from subtotal', () {
      final item = SaleLineItem(
        tempId: '1',
        product: testProduct,
        quantity: 2,
        unitPriceCents: Decimal.fromInt(10000),
        discountCents: Decimal.fromInt(2000),
      );

      // Subtotal: 20000, Discount: 2000, Net: 18000
      expect(item.netCents, equals(Decimal.fromInt(18000)));
    });

    test('taxCentsWithSettings uses product tax rate when available', () {
      final item = SaleLineItem(
        tempId: '1',
        product: testProduct, // 15% tax rate
        quantity: 1,
        unitPriceCents: Decimal.fromInt(10000),
      );

      final tax = item.taxCentsWithSettings(
        enableTaxCalculations: true,
        defaultTaxRateBps: 1000, // 10% default - should be ignored
      );

      // Uses product's 15% rate: 10000 * 0.15 = 1500
      expect(tax, equals(Decimal.fromInt(1500)));
    });

    test('taxCentsWithSettings uses default rate when product has no tax', () {
      final nonTaxableProduct = Product(
        id: 2,
        name: 'Non-Taxable Product',
        sku: 'SKU-002',
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

      final item = SaleLineItem(
        tempId: '1',
        product: nonTaxableProduct,
        quantity: 1,
        unitPriceCents: Decimal.fromInt(10000),
      );

      final tax = item.taxCentsWithSettings(
        enableTaxCalculations: true,
        defaultTaxRateBps: 1000, // 10% default
      );

      // Uses default 10% rate: 10000 * 0.10 = 1000
      expect(tax, equals(Decimal.fromInt(1000)));
    });

    test('taxCentsWithSettings returns zero when tax disabled', () {
      final item = SaleLineItem(
        tempId: '1',
        product: testProduct, // 15% tax rate
        quantity: 1,
        unitPriceCents: Decimal.fromInt(10000),
      );

      final tax = item.taxCentsWithSettings(
        enableTaxCalculations: false,
        defaultTaxRateBps: 1000,
      );

      expect(tax, equals(Decimal.zero));
    });

    test('displayName shows product name only when no variant info', () {
      final item = SaleLineItem(
        tempId: '1',
        product: testProduct,
        quantity: 1,
        unitPriceCents: Decimal.fromInt(10000),
      );

      expect(item.displayName, equals('Test Product'));
    });
  });
}
