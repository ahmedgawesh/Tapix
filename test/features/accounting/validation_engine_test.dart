import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/services/validation_engine.dart';
import 'package:tapix/features/accounting/domain/models/journal_entry_data.dart';

void main() {
  late ValidationEngine validationEngine;

  setUp(() {
    validationEngine = ValidationEngine();
  });

  group('ValidationEngine - Journal Entry Validation', () {
    test('validates balanced journal entry successfully', () {
      final entry = JournalEntryData(
        description: 'Test entry',
        lines: [
          JournalEntryLineData(
            accountId: 1,
            debitCents: 1000,
            creditCents: 0,
            currencyId: 1,
          ),
          JournalEntryLineData(
            accountId: 2,
            debitCents: 0,
            creditCents: 1000,
            currencyId: 1,
          ),
        ],
      );

      final result = validationEngine.validateJournalEntry(entry);

      expect(result.isValid, isTrue);
      expect(result.errors, isEmpty);
    });

    test('rejects unbalanced journal entry', () {
      final entry = JournalEntryData(
        description: 'Unbalanced entry',
        lines: [
          JournalEntryLineData(
            accountId: 1,
            debitCents: 1000,
            creditCents: 0,
            currencyId: 1,
          ),
          JournalEntryLineData(
            accountId: 2,
            debitCents: 0,
            creditCents: 500, // Mismatch!
            currencyId: 1,
          ),
        ],
      );

      final result = validationEngine.validateJournalEntry(entry);

      expect(result.isValid, isFalse);
      expect(result.errors.any((e) => e.contains('must equal')), isTrue);
    });

    test('rejects entry with less than 2 lines', () {
      final entry = JournalEntryData(
        description: 'Single line entry',
        lines: [
          JournalEntryLineData(
            accountId: 1,
            debitCents: 1000,
            creditCents: 0,
            currencyId: 1,
          ),
        ],
      );

      final result = validationEngine.validateJournalEntry(entry);

      expect(result.isValid, isFalse);
      expect(result.errors.any((e) => e.contains('at least 2 lines')), isTrue);
    });

    test('rejects line with both debit and credit', () {
      final entry = JournalEntryData(
        description: 'Invalid line entry',
        lines: [
          JournalEntryLineData(
            accountId: 1,
            debitCents: 1000,
            creditCents: 500, // Both!
            currencyId: 1,
          ),
          JournalEntryLineData(
            accountId: 2,
            debitCents: 0,
            creditCents: 500,
            currencyId: 1,
          ),
        ],
      );

      final result = validationEngine.validateJournalEntry(entry);

      expect(result.isValid, isFalse);
      expect(result.errors.any((e) => e.contains('both debit and credit')), isTrue);
    });

    test('rejects line with zero debit and credit', () {
      final entry = JournalEntryData(
        description: 'Zero line entry',
        lines: [
          JournalEntryLineData(
            accountId: 1,
            debitCents: 1000,
            creditCents: 0,
            currencyId: 1,
          ),
          JournalEntryLineData(
            accountId: 2,
            debitCents: 0,
            creditCents: 0, // Zero!
            currencyId: 1,
          ),
        ],
      );

      final result = validationEngine.validateJournalEntry(entry);

      expect(result.isValid, isFalse);
      expect(result.errors.any((e) => e.contains('either debit or credit')), isTrue);
    });

    test('rejects empty description', () {
      final entry = JournalEntryData(
        description: '', // Empty!
        lines: [
          JournalEntryLineData(
            accountId: 1,
            debitCents: 1000,
            creditCents: 0,
            currencyId: 1,
          ),
          JournalEntryLineData(
            accountId: 2,
            debitCents: 0,
            creditCents: 1000,
            currencyId: 1,
          ),
        ],
      );

      final result = validationEngine.validateJournalEntry(entry);

      expect(result.isValid, isFalse);
      expect(result.errors.any((e) => e.contains('description')), isTrue);
    });

    test('rejects negative amounts', () {
      final entry = JournalEntryData(
        description: 'Negative amount entry',
        lines: [
          JournalEntryLineData(
            accountId: 1,
            debitCents: -1000, // Negative!
            creditCents: 0,
            currencyId: 1,
          ),
          JournalEntryLineData(
            accountId: 2,
            debitCents: 0,
            creditCents: 1000,
            currencyId: 1,
          ),
        ],
      );

      final result = validationEngine.validateJournalEntry(entry);

      expect(result.isValid, isFalse);
      expect(result.errors.any((e) => e.contains('negative')), isTrue);
    });
  });

  group('ValidationEngine - Sale Validation', () {
    test('validates correct sale successfully', () {
      final sale = SaleValidationData(
        totalCents: 1150, // 1000 - 0 + 150 tax
        discountCents: 0,
        taxCents: 150,
        items: [
          SaleItemValidationData(
            productId: 1,
            quantity: 2,
            priceInCents: 500,
            currentStock: 10,
          ),
        ],
      );

      final result = validationEngine.validateSale(sale);

      expect(result.isValid, isTrue);
    });

    test('rejects sale with zero total', () {
      final sale = SaleValidationData(
        totalCents: 0,
        discountCents: 0,
        taxCents: 0,
        items: [
          SaleItemValidationData(
            productId: 1,
            quantity: 1,
            priceInCents: 0,
            currentStock: 10,
          ),
        ],
      );

      final result = validationEngine.validateSale(sale);

      expect(result.isValid, isFalse);
      expect(result.errors.any((e) => e.contains('positive')), isTrue);
    });

    test('rejects sale with no items', () {
      final sale = SaleValidationData(
        totalCents: 1000,
        discountCents: 0,
        taxCents: 0,
        items: [],
      );

      final result = validationEngine.validateSale(sale);

      expect(result.isValid, isFalse);
      expect(result.errors.any((e) => e.contains('at least one item')), isTrue);
    });

    test('rejects sale with zero quantity item', () {
      final sale = SaleValidationData(
        totalCents: 1000,
        discountCents: 0,
        taxCents: 0,
        items: [
          SaleItemValidationData(
            productId: 1,
            quantity: 0, // Zero!
            priceInCents: 1000,
            currentStock: 10,
          ),
        ],
      );

      final result = validationEngine.validateSale(sale);

      expect(result.isValid, isFalse);
      expect(result.errors.any((e) => e.contains('Quantity must be positive')), isTrue);
    });

    test('rejects sale with negative price', () {
      final sale = SaleValidationData(
        totalCents: 1000,
        discountCents: 0,
        taxCents: 0,
        items: [
          SaleItemValidationData(
            productId: 1,
            quantity: 1,
            priceInCents: -1000, // Negative!
            currentStock: 10,
          ),
        ],
      );

      final result = validationEngine.validateSale(sale);

      expect(result.isValid, isFalse);
      expect(result.errors.any((e) => e.contains('negative')), isTrue);
    });

    test('rejects sale with discount exceeding subtotal', () {
      final sale = SaleValidationData(
        totalCents: 500,
        discountCents: 1500, // Exceeds subtotal of 1000!
        taxCents: 0,
        items: [
          SaleItemValidationData(
            productId: 1,
            quantity: 1,
            priceInCents: 1000,
            currentStock: 10,
          ),
        ],
      );

      final result = validationEngine.validateSale(sale);

      expect(result.isValid, isFalse);
      expect(result.errors.any((e) => e.contains('Discount cannot exceed')), isTrue);
    });
  });

  group('ValidationEngine - Payment Validation', () {
    test('validates customer payment successfully', () {
      final payment = PaymentValidationData(
        amountCents: 1000,
        paymentMethod: 'cash',
        customerId: 1,
      );

      final result = validationEngine.validatePayment(payment);

      expect(result.isValid, isTrue);
    });

    test('validates supplier payment successfully', () {
      final payment = PaymentValidationData(
        amountCents: 1000,
        paymentMethod: 'bank_transfer',
        supplierId: 1,
      );

      final result = validationEngine.validatePayment(payment);

      expect(result.isValid, isTrue);
    });

    test('rejects payment with zero amount', () {
      final payment = PaymentValidationData(
        amountCents: 0,
        paymentMethod: 'cash',
        customerId: 1,
      );

      final result = validationEngine.validatePayment(payment);

      expect(result.isValid, isFalse);
      expect(result.errors.any((e) => e.contains('positive')), isTrue);
    });

    test('rejects payment without customer or supplier', () {
      final payment = PaymentValidationData(
        amountCents: 1000,
        paymentMethod: 'cash',
      );

      final result = validationEngine.validatePayment(payment);

      expect(result.isValid, isFalse);
      expect(result.errors.any((e) => e.contains('customer or supplier')), isTrue);
    });

    test('rejects payment with both customer and supplier', () {
      final payment = PaymentValidationData(
        amountCents: 1000,
        paymentMethod: 'cash',
        customerId: 1,
        supplierId: 1,
      );

      final result = validationEngine.validatePayment(payment);

      expect(result.isValid, isFalse);
      expect(result.errors.any((e) => e.contains('Cannot have both')), isTrue);
    });

    test('rejects payment with empty payment method', () {
      final payment = PaymentValidationData(
        amountCents: 1000,
        paymentMethod: '',
        customerId: 1,
      );

      final result = validationEngine.validatePayment(payment);

      expect(result.isValid, isFalse);
      expect(result.errors.any((e) => e.contains('Payment method')), isTrue);
    });
  });

  group('ValidationEngine - Expense Validation', () {
    test('validates expense successfully', () {
      final expense = ExpenseValidationData(
        amountCents: 5000,
        categoryId: 1,
        description: 'Office supplies',
      );

      final result = validationEngine.validateExpense(expense);

      expect(result.isValid, isTrue);
    });

    test('rejects expense with zero amount', () {
      final expense = ExpenseValidationData(
        amountCents: 0,
        categoryId: 1,
        description: 'Office supplies',
      );

      final result = validationEngine.validateExpense(expense);

      expect(result.isValid, isFalse);
      expect(result.errors.any((e) => e.contains('positive')), isTrue);
    });

    test('rejects expense with empty description', () {
      final expense = ExpenseValidationData(
        amountCents: 5000,
        categoryId: 1,
        description: '',
      );

      final result = validationEngine.validateExpense(expense);

      expect(result.isValid, isFalse);
      expect(result.errors.any((e) => e.contains('description')), isTrue);
    });

    test('rejects expense with invalid category', () {
      final expense = ExpenseValidationData(
        amountCents: 5000,
        categoryId: 0,
        description: 'Office supplies',
      );

      final result = validationEngine.validateExpense(expense);

      expect(result.isValid, isFalse);
      expect(result.errors.any((e) => e.contains('category')), isTrue);
    });
  });

  group('ValidationEngine - Stock Adjustment Validation', () {
    test('validates stock increase successfully', () {
      final adjustment = StockAdjustmentValidationData(
        productId: 1,
        quantityChange: 10,
        newQuantity: 20,
        reason: 'Stock received',
      );

      final result = validationEngine.validateStockAdjustment(adjustment);

      expect(result.isValid, isTrue);
    });

    test('validates stock decrease successfully', () {
      final adjustment = StockAdjustmentValidationData(
        productId: 1,
        quantityChange: -5,
        newQuantity: 15,
        reason: 'Damaged goods',
      );

      final result = validationEngine.validateStockAdjustment(adjustment);

      expect(result.isValid, isTrue);
    });

    test('rejects zero quantity change', () {
      final adjustment = StockAdjustmentValidationData(
        productId: 1,
        quantityChange: 0,
        newQuantity: 20,
        reason: 'No change',
      );

      final result = validationEngine.validateStockAdjustment(adjustment);

      expect(result.isValid, isFalse);
      expect(result.errors.any((e) => e.contains('cannot be zero')), isTrue);
    });

    test('rejects empty reason', () {
      final adjustment = StockAdjustmentValidationData(
        productId: 1,
        quantityChange: 10,
        newQuantity: 20,
        reason: '',
      );

      final result = validationEngine.validateStockAdjustment(adjustment);

      expect(result.isValid, isFalse);
      expect(result.errors.any((e) => e.contains('reason')), isTrue);
    });

    test('rejects negative stock when not allowed', () {
      final adjustment = StockAdjustmentValidationData(
        productId: 1,
        quantityChange: -30,
        newQuantity: -10, // Negative!
        reason: 'Over-sold',
        allowNegativeStock: false,
      );

      final result = validationEngine.validateStockAdjustment(adjustment);

      expect(result.isValid, isFalse);
      expect(result.errors.any((e) => e.contains('cannot be negative')), isTrue);
    });

    test('allows negative stock when explicitly allowed', () {
      final adjustment = StockAdjustmentValidationData(
        productId: 1,
        quantityChange: -30,
        newQuantity: -10,
        reason: 'Backorder',
        allowNegativeStock: true,
      );

      final result = validationEngine.validateStockAdjustment(adjustment);

      expect(result.isValid, isTrue);
    });
  });
}
