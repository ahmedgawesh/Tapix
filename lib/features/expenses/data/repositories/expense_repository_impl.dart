import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import '../../../../core/database/app_database.dart';
import '../../domain/repositories/expense_repository.dart';
import '../datasources/expense_local_datasource.dart';

/// Implementation of ExpenseRepository
class ExpenseRepositoryImpl implements ExpenseRepository {
  final ExpenseLocalDatasource _datasource;

  ExpenseRepositoryImpl(this._datasource);

  // ── Expense Categories ──────────────────────────────────

  @override
  Stream<List<ExpenseCategory>> watchAllCategories({bool? isActive}) {
    return _datasource.watchAllCategories(isActive: isActive);
  }

  @override
  Future<ExpenseCategory?> getCategory(int id) {
    return _datasource.getCategory(id);
  }

  @override
  Future<ExpenseCategory?> findCategoryByName(String name) {
    return _datasource.findCategoryByName(name);
  }

  @override
  Future<int> createCategory({
    required String name,
    String? description,
  }) {
    final companion = ExpenseCategoriesCompanion(
      name: Value(name),
      description: Value(description),
      isActive: const Value(true),
      createdAt: Value(DateTime.now()),
      updatedAt: Value(DateTime.now()),
    );
    return _datasource.createCategory(companion);
  }

  @override
  Future<bool> updateCategory(ExpenseCategory category) {
    return _datasource.updateCategory(category);
  }

  @override
  Future<int> deleteCategory(int id) {
    return _datasource.deleteCategory(id);
  }

  @override
  Stream<int> watchCategoryCount({bool? isActive}) {
    return _datasource.watchCategoryCount(isActive: isActive);
  }

  // ── Expenses ────────────────────────────────────────────

  @override
  Stream<List<Expense>> watchAllExpenses() {
    return _datasource.watchAllExpenses();
  }

  @override
  Stream<List<Expense>> watchExpensesByCategory(int categoryId) {
    return _datasource.watchExpensesByCategory(categoryId);
  }

  @override
  Stream<List<Expense>> watchExpensesByDateRange(DateTime start, DateTime end) {
    return _datasource.watchExpensesByDateRange(start, end);
  }

  @override
  Future<Expense?> getExpense(int id) {
    return _datasource.getExpense(id);
  }

  @override
  Future<List<Expense>> searchExpenses(String query) {
    return _datasource.searchExpenses(query);
  }

  @override
  Future<int> createExpense({
    required int categoryId,
    required String description,
    required Decimal amountCents,
    required int currencyId,
    int? accountId,
    DateTime? expenseDate,
    String? receiptPath,
  }) {
    final companion = ExpensesCompanion(
      categoryId: Value(categoryId),
      description: Value(description),
      amountCents: Value(amountCents),
      currencyId: Value(currencyId),
      accountId: Value(accountId),
      expenseDate: Value(expenseDate ?? DateTime.now()),
      receiptPath: Value(receiptPath),
      createdAt: Value(DateTime.now()),
      updatedAt: Value(DateTime.now()),
    );
    return _datasource.createExpense(companion);
  }

  @override
  Future<bool> updateExpense(Expense expense) {
    return _datasource.updateExpense(expense);
  }

  @override
  Future<int> deleteExpense(int id) {
    return _datasource.deleteExpense(id);
  }

  @override
  Stream<int> watchExpenseCount() {
    return _datasource.watchExpenseCount();
  }

  @override
  Stream<int> watchTotalExpenseCents() {
    return _datasource.watchTotalExpenseCents();
  }
}
