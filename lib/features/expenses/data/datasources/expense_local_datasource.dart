import '../../../../core/database/app_database.dart';
import '../../../../core/database/daos/accounting_dao.dart';

/// Local datasource for expense operations
abstract class ExpenseLocalDatasource {
  // Categories
  Stream<List<ExpenseCategory>> watchAllCategories({bool? isActive});
  Future<ExpenseCategory?> getCategory(int id);
  Future<ExpenseCategory?> findCategoryByName(String name);
  Future<int> createCategory(ExpenseCategoriesCompanion category);
  Future<bool> updateCategory(ExpenseCategory category);
  Future<int> deleteCategory(int id);
  Stream<int> watchCategoryCount({bool? isActive});

  // Expenses
  Stream<List<Expense>> watchAllExpenses();
  Stream<List<Expense>> watchExpensesByCategory(int categoryId);
  Stream<List<Expense>> watchExpensesByDateRange(DateTime start, DateTime end);
  Future<Expense?> getExpense(int id);
  Future<List<Expense>> searchExpenses(String query);
  Future<int> createExpense(ExpensesCompanion expense);
  Future<bool> updateExpense(Expense expense);
  Future<int> deleteExpense(int id);
  Stream<int> watchExpenseCount();
  Stream<int> watchTotalExpenseCents();
}

/// Implementation of ExpenseLocalDatasource using AccountingDao
class ExpenseLocalDatasourceImpl implements ExpenseLocalDatasource {
  final AccountingDao _accountingDao;

  ExpenseLocalDatasourceImpl(this._accountingDao);

  // ── Categories ──────────────────────────────────────────

  @override
  Stream<List<ExpenseCategory>> watchAllCategories({bool? isActive}) {
    return _accountingDao.watchAllExpenseCategories(isActive: isActive);
  }

  @override
  Future<ExpenseCategory?> getCategory(int id) {
    return _accountingDao.getExpenseCategory(id);
  }

  @override
  Future<ExpenseCategory?> findCategoryByName(String name) {
    return _accountingDao.findExpenseCategoryByName(name);
  }

  @override
  Future<int> createCategory(ExpenseCategoriesCompanion category) {
    return _accountingDao.createExpenseCategory(category);
  }

  @override
  Future<bool> updateCategory(ExpenseCategory category) {
    return _accountingDao.updateExpenseCategory(category);
  }

  @override
  Future<int> deleteCategory(int id) {
    return _accountingDao.deleteExpenseCategory(id);
  }

  @override
  Stream<int> watchCategoryCount({bool? isActive}) {
    return _accountingDao.watchExpenseCategoryCount(isActive: isActive);
  }

  // ── Expenses ────────────────────────────────────────────

  @override
  Stream<List<Expense>> watchAllExpenses() {
    return _accountingDao.watchExpenses();
  }

  @override
  Stream<List<Expense>> watchExpensesByCategory(int categoryId) {
    return _accountingDao.watchExpensesByCategory(categoryId);
  }

  @override
  Stream<List<Expense>> watchExpensesByDateRange(DateTime start, DateTime end) {
    return _accountingDao.watchExpensesByDateRange(start, end);
  }

  @override
  Future<Expense?> getExpense(int id) {
    return _accountingDao.getExpense(id);
  }

  @override
  Future<List<Expense>> searchExpenses(String query) {
    return _accountingDao.searchExpenses(query);
  }

  @override
  Future<int> createExpense(ExpensesCompanion expense) {
    return _accountingDao.createExpense(expense);
  }

  @override
  Future<bool> updateExpense(Expense expense) {
    return _accountingDao.updateExpense(expense);
  }

  @override
  Future<int> deleteExpense(int id) {
    return _accountingDao.deleteExpense(id);
  }

  @override
  Stream<int> watchExpenseCount() {
    return _accountingDao.watchExpenseCount();
  }

  @override
  Stream<int> watchTotalExpenseCents() {
    return _accountingDao.watchTotalExpenseCents();
  }
}
