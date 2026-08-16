class Permissions {
  Permissions._();

  // User Management
  static const String manageUsers = 'manage_users';
  static const String promoteUsers = 'promote_users';
  static const String deactivateUsers = 'deactivate_users';
  static const String viewUserActivity = 'view_user_activity';

  // Employee Management
  static const String manageEmployees = 'manage_employees';
  static const String viewEmployees = 'view_employees';

  // Product Management
  static const String editProducts = 'edit_products';
  static const String deleteProducts = 'delete_products';
  static const String adjustStock = 'adjust_stock';
  static const String manageCategories = 'manage_categories';
  static const String viewProducts = 'view_products';
  static const String viewProductCost = 'view_product_cost';
  static const String manageBarcodes = 'manage_barcodes';

  // Financial Operations
  static const String viewReports = 'view_reports';
  static const String manageExpenses = 'manage_expenses';
  static const String accessSettings = 'access_settings';
  static const String manageTaxes = 'manage_taxes';
  static const String manageAccounting = 'manage_accounting';
  static const String exportData = 'export_data';
  static const String backupRestore = 'backup_restore';

  // Sales Operations
  static const String processSales = 'process_sales';
  static const String handleReturns = 'handle_returns';
  static const String viewDailyReports = 'view_daily_reports';
  static const String manageDiscounts = 'manage_discounts';
  static const String voidTransactions = 'void_transactions';
  static const String createSales = 'create_sales';

  // Customer Management
  static const String manageCustomers = 'manage_customers';
  static const String viewCustomers = 'view_customers';

  // Supplier Management
  static const String manageSuppliers = 'manage_suppliers';
  static const String viewSuppliers = 'view_suppliers';

  // Purchase Management
  static const String managePurchases = 'manage_purchases';
  static const String viewPurchases = 'view_purchases';

  // Transaction Editing
  static const String editTransactions = 'edit_transactions';

  // Audit & Security
  static const String viewAuditLogs = 'view_audit_logs';

  // ── Phase 11.3b — granular accounting controls ─────────────────────────
  // The existing `voidTransactions` permission only covers user-visible
  // documents (sale / purchase / return invoices). The three constants
  // below isolate the three accounting operations whose financial blast
  // radius is the entire GL — they MUST be approvable independently of
  // sale/purchase voids and independently of generic `manageAccounting`.
  //
  //   • voidJournalEntry  — reverse a posted JE (creates a counter-JE).
  //   • closeFiscalPeriod — freeze GL postings for a YYYY-MM month.
  //   • reopenFiscalPeriod — undo a close; logged as a critical audit event.
  //
  // Default assignment: owner-only. Managers retain `voidTransactions`
  // (invoice voids) and accountants retain `manageAccounting` (general
  // GL access) — but neither role can void a JE, close, or reopen a
  // fiscal period without an explicit grant.
  static const String voidJournalEntry = 'void_journal_entry';
  static const String closeFiscalPeriod = 'close_fiscal_period';
  static const String reopenFiscalPeriod = 'reopen_fiscal_period';

  static const List<String> all = [
    manageUsers,
    promoteUsers,
    deactivateUsers,
    viewUserActivity,
    manageEmployees,
    viewEmployees,
    editProducts,
    deleteProducts,
    adjustStock,
    manageCategories,
    viewProducts,
    viewProductCost,
    manageBarcodes,
    viewReports,
    manageExpenses,
    accessSettings,
    manageTaxes,
    manageAccounting,
    exportData,
    backupRestore,
    processSales,
    handleReturns,
    viewDailyReports,
    manageDiscounts,
    voidTransactions,
    createSales,
    manageCustomers,
    viewCustomers,
    manageSuppliers,
    viewSuppliers,
    managePurchases,
    viewPurchases,
    editTransactions,
    viewAuditLogs,
    voidJournalEntry,
    closeFiscalPeriod,
    reopenFiscalPeriod,
  ];
}
