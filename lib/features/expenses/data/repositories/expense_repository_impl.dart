import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/services/audit_log_service.dart';
import '../../../../core/services/journal_entry_service.dart';
import '../../domain/repositories/expense_repository.dart';
import '../datasources/expense_local_datasource.dart';

/// Implementation of ExpenseRepository
class ExpenseRepositoryImpl implements ExpenseRepository {
  final ExpenseLocalDatasource _datasource;
  final JournalEntryService _journalService;
  final AuditLogService _auditService;
  final AppDatabase _db;

  ExpenseRepositoryImpl(
    this._datasource,
    this._journalService,
    this._auditService,
    this._db,
  );

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
  Future<int> createCategory({required String name, String? description}) {
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
  }) async {
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
    // ATOMIC: Wrap expense creation and journal entry in a single transaction.
    // If the journal entry fails, the expense record is rolled back.
    final expenseId = await _db.transaction(() async {
      final id = await _datasource.createExpense(companion);

      // Create journal entry — MANDATORY (Dr Expense, Cr Cash)
      // Errors MUST propagate — silent failure causes unbalanced ledger
      await _journalService.recordExpenseJournalEntry(
        expenseId: id,
        amountCents: amountCents.toBigInt().toInt(),
        currencyId: currencyId,
      );

      return id;
    });

    // Audit log outside transaction (non-critical)
    _auditService.log(
      entityType: 'expense',
      entityId: expenseId,
      action: 'create',
      newValue: {
        'categoryId': categoryId,
        'description': description,
        'amountCents': amountCents.toString(),
      },
    );

    return expenseId;
  }

  @override
  Future<bool> updateExpense(Expense expense) async {
    // ATOMIC: Wrap void + update + re-create in a single transaction.
    final ok = await _db.transaction(() async {
      await _journalService.voidJournalEntriesForSource(
        sourceTable: 'expenses',
        sourceId: expense.id,
        reason: 'Expense updated',
      );

      final updated = await _datasource.updateExpense(expense);

      if (updated) {
        // Re-create journal entry with new amount
        await _journalService.recordExpenseJournalEntry(
          expenseId: expense.id,
          amountCents: expense.amountCents.toBigInt().toInt(),
          currencyId: expense.currencyId,
        );
      }

      return updated;
    });

    if (ok) {
      // Audit log outside transaction (non-critical)
      _auditService.log(
        entityType: 'expense',
        entityId: expense.id,
        action: 'update',
        newValue: {
          'amountCents': expense.amountCents.toString(),
          'description': expense.description,
        },
      );
    }

    return ok;
  }

  @override
  Future<int> deleteExpense(int id) async {
    // Void journal entries BEFORE deleting the expense record
    await _journalService.voidJournalEntriesForSource(
      sourceTable: 'expenses',
      sourceId: id,
      reason: 'Expense deleted',
    );

    // Audit: log expense deletion (CRITICAL — financial data removed)
    await _auditService.logVoid(
      entityType: 'expense',
      entityId: id,
      reason: 'Expense deleted',
    );

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
