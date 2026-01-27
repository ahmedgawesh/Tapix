import '../../features/accounting/domain/models/journal_entry_data.dart';

/// ValidationEngine - Validates all business rules BEFORE any changes are committed
/// 
/// This is a critical component of the accounting integrity system.
/// ALL transactions MUST pass validation before execution.
class ValidationEngine {
  /// Validate a journal entry
  ValidationResult validateJournalEntry(JournalEntryData entry) {
    final errors = <String>[];

    // Rule 1: Must have description
    if (entry.description.trim().isEmpty) {
      errors.add('Journal entry description is required');
    }

    // Rule 2: Must have at least 2 lines
    if (entry.lines.length < 2) {
      errors.add('Journal entry must have at least 2 lines');
    }

    // Rule 3: Debits must equal credits
    int totalDebits = 0;
    int totalCredits = 0;
    
    for (int i = 0; i < entry.lines.length; i++) {
      final line = entry.lines[i];
      totalDebits += line.debitCents;
      totalCredits += line.creditCents;

      // Rule 4: Each line must have debit OR credit, not both
      if (line.debitCents > 0 && line.creditCents > 0) {
        errors.add('Line ${i + 1}: Cannot have both debit and credit');
      }

      // Rule 5: Each line must have either debit or credit
      if (line.debitCents == 0 && line.creditCents == 0) {
        errors.add('Line ${i + 1}: Must have either debit or credit');
      }

      // Rule 6: Amounts must be positive
      if (line.debitCents < 0) {
        errors.add('Line ${i + 1}: Debit cannot be negative');
      }
      if (line.creditCents < 0) {
        errors.add('Line ${i + 1}: Credit cannot be negative');
      }

      // Rule 7: Account ID must be valid
      if (line.accountId <= 0) {
        errors.add('Line ${i + 1}: Invalid account ID');
      }

      // Rule 8: Currency ID must be valid
      if (line.currencyId <= 0) {
        errors.add('Line ${i + 1}: Invalid currency ID');
      }
    }

    if (totalDebits != totalCredits) {
      errors.add('Debits ($totalDebits) must equal Credits ($totalCredits)');
    }

    return ValidationResult(
      isValid: errors.isEmpty,
      errors: errors,
    );
  }

  /// Validate sale data
  ValidationResult validateSale(SaleValidationData sale) {
    final errors = <String>[];

    // Rule 1: Total must be positive
    if (sale.totalCents <= 0) {
      errors.add('Sale total must be positive');
    }

    // Rule 2: Must have items
    if (sale.items.isEmpty) {
      errors.add('Sale must have at least one item');
    }

    // Rule 3: Validate each item
    for (int i = 0; i < sale.items.length; i++) {
      final item = sale.items[i];

      if (item.quantity <= 0) {
        errors.add('Item ${i + 1}: Quantity must be positive');
      }

      if (item.priceInCents < 0) {
        errors.add('Item ${i + 1}: Price cannot be negative');
      }

      if (item.productId <= 0) {
        errors.add('Item ${i + 1}: Invalid product ID');
      }
    }

    // Rule 4: Subtotal calculation
    final calculatedSubtotal = sale.items.fold<int>(
      0,
      (sum, item) => sum + (item.quantity * item.priceInCents),
    );
    
    // Allow for discounts and taxes
    final expectedTotal = calculatedSubtotal - sale.discountCents + sale.taxCents;
    if (sale.totalCents != expectedTotal) {
      errors.add(
        'Total mismatch: Expected $expectedTotal, got ${sale.totalCents}'
      );
    }

    // Rule 5: Discount cannot exceed subtotal
    if (sale.discountCents > calculatedSubtotal) {
      errors.add('Discount cannot exceed subtotal');
    }

    // Rule 6: Tax cannot be negative
    if (sale.taxCents < 0) {
      errors.add('Tax cannot be negative');
    }

    return ValidationResult(
      isValid: errors.isEmpty,
      errors: errors,
    );
  }

  /// Validate purchase data
  ValidationResult validatePurchase(PurchaseValidationData purchase) {
    final errors = <String>[];

    // Rule 1: Total must be positive
    if (purchase.totalCents <= 0) {
      errors.add('Purchase total must be positive');
    }

    // Rule 2: Must have items
    if (purchase.items.isEmpty) {
      errors.add('Purchase must have at least one item');
    }

    // Rule 3: Supplier must be valid
    if (purchase.supplierId <= 0) {
      errors.add('Invalid supplier ID');
    }

    // Rule 4: Validate each item
    for (int i = 0; i < purchase.items.length; i++) {
      final item = purchase.items[i];

      if (item.quantity <= 0) {
        errors.add('Item ${i + 1}: Quantity must be positive');
      }

      if (item.costInCents < 0) {
        errors.add('Item ${i + 1}: Cost cannot be negative');
      }

      if (item.productId <= 0) {
        errors.add('Item ${i + 1}: Invalid product ID');
      }
    }

    return ValidationResult(
      isValid: errors.isEmpty,
      errors: errors,
    );
  }

  /// Validate payment data
  ValidationResult validatePayment(PaymentValidationData payment) {
    final errors = <String>[];

    // Rule 1: Amount must be positive
    if (payment.amountCents <= 0) {
      errors.add('Payment amount must be positive');
    }

    // Rule 2: Payment method must be valid
    if (payment.paymentMethod.isEmpty) {
      errors.add('Payment method is required');
    }

    // Rule 3: Either customer or supplier must be specified
    if (payment.customerId == null && payment.supplierId == null) {
      errors.add('Either customer or supplier must be specified');
    }

    // Rule 4: Cannot have both customer and supplier
    if (payment.customerId != null && payment.supplierId != null) {
      errors.add('Cannot have both customer and supplier');
    }

    return ValidationResult(
      isValid: errors.isEmpty,
      errors: errors,
    );
  }

  /// Validate expense data
  ValidationResult validateExpense(ExpenseValidationData expense) {
    final errors = <String>[];

    // Rule 1: Amount must be positive
    if (expense.amountCents <= 0) {
      errors.add('Expense amount must be positive');
    }

    // Rule 2: Category must be valid
    if (expense.categoryId <= 0) {
      errors.add('Invalid expense category');
    }

    // Rule 3: Description is required
    if (expense.description.trim().isEmpty) {
      errors.add('Expense description is required');
    }

    return ValidationResult(
      isValid: errors.isEmpty,
      errors: errors,
    );
  }

  /// Validate stock adjustment
  ValidationResult validateStockAdjustment(StockAdjustmentValidationData adjustment) {
    final errors = <String>[];

    // Rule 1: Product must be valid
    if (adjustment.productId <= 0) {
      errors.add('Invalid product ID');
    }

    // Rule 2: Quantity change cannot be zero
    if (adjustment.quantityChange == 0) {
      errors.add('Quantity change cannot be zero');
    }

    // Rule 3: Reason is required
    if (adjustment.reason.trim().isEmpty) {
      errors.add('Adjustment reason is required');
    }

    // Rule 4: New quantity cannot be negative (unless allowed)
    if (!adjustment.allowNegativeStock && adjustment.newQuantity < 0) {
      errors.add('Stock cannot be negative');
    }

    return ValidationResult(
      isValid: errors.isEmpty,
      errors: errors,
    );
  }
}

/// Result of validation
class ValidationResult {
  final bool isValid;
  final List<String> errors;

  ValidationResult({
    required this.isValid,
    required this.errors,
  });

  /// Get first error message
  String? get firstError => errors.isNotEmpty ? errors.first : null;

  /// Get all errors as single string
  String get errorMessage => errors.join('; ');
}

/// Data class for sale validation
class SaleValidationData {
  final int totalCents;
  final int discountCents;
  final int taxCents;
  final int? customerId;
  final List<SaleItemValidationData> items;

  SaleValidationData({
    required this.totalCents,
    required this.discountCents,
    required this.taxCents,
    this.customerId,
    required this.items,
  });
}

class SaleItemValidationData {
  final int productId;
  final int quantity;
  final int priceInCents;
  final int currentStock;

  SaleItemValidationData({
    required this.productId,
    required this.quantity,
    required this.priceInCents,
    required this.currentStock,
  });
}

/// Data class for purchase validation
class PurchaseValidationData {
  final int totalCents;
  final int supplierId;
  final List<PurchaseItemValidationData> items;

  PurchaseValidationData({
    required this.totalCents,
    required this.supplierId,
    required this.items,
  });
}

class PurchaseItemValidationData {
  final int productId;
  final int quantity;
  final int costInCents;

  PurchaseItemValidationData({
    required this.productId,
    required this.quantity,
    required this.costInCents,
  });
}

/// Data class for payment validation
class PaymentValidationData {
  final int amountCents;
  final String paymentMethod;
  final int? customerId;
  final int? supplierId;

  PaymentValidationData({
    required this.amountCents,
    required this.paymentMethod,
    this.customerId,
    this.supplierId,
  });
}

/// Data class for expense validation
class ExpenseValidationData {
  final int amountCents;
  final int categoryId;
  final String description;

  ExpenseValidationData({
    required this.amountCents,
    required this.categoryId,
    required this.description,
  });
}

/// Data class for stock adjustment validation
class StockAdjustmentValidationData {
  final int productId;
  final int quantityChange;
  final int newQuantity;
  final String reason;
  final bool allowNegativeStock;

  StockAdjustmentValidationData({
    required this.productId,
    required this.quantityChange,
    required this.newQuantity,
    required this.reason,
    this.allowNegativeStock = false,
  });
}
