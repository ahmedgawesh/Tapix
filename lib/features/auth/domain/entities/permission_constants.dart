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

  // Audit & Security
  static const String viewAuditLogs = 'view_audit_logs';

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
    viewAuditLogs,
  ];
}
