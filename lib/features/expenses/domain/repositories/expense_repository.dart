import 'package:decimal/decimal.dart';
import '../../../../core/database/app_database.dart';

/// Domain repository interface for expense operations
abstract class ExpenseRepository {
  // ── Expense Categories ──────────────────────────────────

  /// Watch all expense categories with optional active filter
  Stream<List<ExpenseCategory>> watchAllCategories({bool? isActive});

  /// Get a single category by ID
  Future<ExpenseCategory?> getCategory(int id);

  /// Find category by name (for uniqueness validation)
  Future<ExpenseCategory?> findCategoryByName(String name);

  /// Create a new expense category
  Future<int> createCategory({required String name, String? description});

  /// Update an existing expense category
  Future<bool> updateCategory(ExpenseCategory category);

  /// Delete an expense category by ID
  Future<int> deleteCategory(int id);

  /// Watch category count
  Stream<int> watchCategoryCount({bool? isActive});

  // ── Expenses ────────────────────────────────────────────

  /// Watch all expenses ordered by date descending
  Stream<List<Expense>> watchAllExpenses();

  /// Watch expenses filtered by category
  Stream<List<Expense>> watchExpensesByCategory(int categoryId);

  /// Watch expenses filtered by date range
  Stream<List<Expense>> watchExpensesByDateRange(DateTime start, DateTime end);

  /// Get a single expense by ID
  Future<Expense?> getExpense(int id);

  /// Search expenses by description
  Future<List<Expense>> searchExpenses(String query);

  /// Create a new expense
  Future<int> createExpense({
    required int categoryId,
    required String description,
    required Decimal amountCents,
    required int currencyId,
    int? accountId,
    DateTime? expenseDate,
    String? receiptPath,
  });

  /// Update an existing expense
  Future<bool> updateExpense(Expense expense);

  /// Delete an expense by ID
  Future<int> deleteExpense(int id);

  /// Watch total expense count
  Stream<int> watchExpenseCount();

  /// Watch total expense amount in cents
  Stream<int> watchTotalExpenseCents();
}
