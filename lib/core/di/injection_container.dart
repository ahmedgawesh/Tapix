import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../bloc/currency_bloc.dart';
import '../bloc/localization_bloc.dart';
import '../bloc/theme_bloc.dart';
import '../database/app_database.dart';
import '../database/daos/product_dao.dart';
import '../database/daos/product_variant_dao.dart';
import '../database/daos/product_color_dao.dart';
import '../database/daos/category_dao.dart';
import '../database/daos/size_dao.dart';
import '../database/daos/settings_dao.dart';
import '../database/daos/barcode_template_dao.dart';
import '../database/daos/purchase_dao.dart';
import '../database/daos/sale_dao.dart';
import '../services/currency_service.dart';
import '../services/localization_service.dart';
import '../services/audit_log_service.dart';
import '../services/theme_service.dart';
import '../../features/auth/auth.dart';
import '../../features/products/domain/repositories/product_repository.dart';
import '../../features/products/domain/repositories/product_variant_repository.dart';
import '../../features/products/domain/repositories/category_repository.dart';
import '../../features/products/domain/repositories/product_color_repository.dart';
import '../../features/products/domain/repositories/size_repository.dart';
import '../../features/products/data/datasources/product_local_datasource.dart';
import '../../features/products/data/datasources/variant_local_datasource.dart';
import '../../features/products/data/repositories/product_repository_impl.dart';
import '../../features/products/data/repositories/product_variant_repository_impl.dart';
import '../../features/products/data/repositories/category_repository_impl.dart';
import '../../features/products/data/repositories/product_color_repository_impl.dart';
import '../../features/products/data/repositories/size_repository_impl.dart';
import '../../features/products/presentation/bloc/products_bloc.dart';
import '../../features/products/presentation/bloc/product_form_bloc.dart';
import '../../features/products/presentation/bloc/product_variants_bloc.dart';
import '../../features/products/presentation/bloc/bulk_product_bloc.dart';
import '../../features/products/presentation/bloc/edit_prices_bloc.dart';
import '../../features/products/presentation/bloc/import_products_bloc.dart';
import '../../features/products/presentation/bloc/export_bloc.dart';
import '../../features/products/presentation/bloc/categories_bloc.dart';
import '../../features/products/presentation/bloc/colors_bloc.dart';
import '../../features/products/presentation/bloc/sizes_bloc.dart';
import '../../features/products/presentation/bloc/variant_summaries_bloc.dart';
import '../../features/products/presentation/bloc/variant_previews_bloc.dart';
import '../../features/products/services/file_import_service.dart';
import '../../features/products/services/import_validation_service.dart';
import '../../features/products/services/product_import_service.dart';
import '../../features/products/services/export_service.dart';
import '../../features/products/domain/usecases/parse_import_file.dart';
import '../../features/products/domain/usecases/validate_import_data.dart';
import '../../features/products/domain/usecases/import_products.dart';
import '../../features/barcode/services/barcode_validation_service.dart';
import '../../features/barcode/services/barcode_printer_service.dart';
import '../../features/barcode/presentation/bloc/barcode_scanner_bloc.dart';
import '../../features/barcode/presentation/bloc/barcode_design_bloc.dart';
import '../../features/settings/data/services/company_profile_service.dart';
import '../../features/settings/presentation/bloc/company_bloc.dart';
import '../../features/purchases/data/datasources/purchase_local_datasource.dart';
import '../../features/purchases/data/repositories/purchase_repository_impl.dart';
import '../../features/purchases/domain/repositories/purchase_repository.dart';
import '../../features/purchases/presentation/bloc/purchases_bloc.dart';
import '../../features/purchases/presentation/bloc/purchase_form_bloc.dart';
import '../../features/purchases/presentation/bloc/purchase_returns_bloc.dart';
import '../../features/purchases/presentation/bloc/purchase_return_form_bloc.dart';
import '../../features/sales/data/datasources/sale_local_datasource.dart';
import '../../features/sales/data/repositories/sale_repository_impl.dart';
import '../../features/sales/domain/repositories/sale_repository.dart';
import '../../features/sales/presentation/bloc/sales_bloc.dart';
import '../../features/sales/presentation/bloc/sale_form_bloc.dart';
import '../../features/sales/presentation/bloc/sale_returns_bloc.dart';
import '../../features/sales/presentation/bloc/sale_return_form_bloc.dart';
import '../../features/customers/domain/repositories/customer_repository.dart';
import '../../features/customers/domain/repositories/loyalty_repository.dart';
import '../../features/customers/data/datasources/customer_local_datasource.dart';
import '../../features/customers/data/repositories/customer_repository_impl.dart';
import '../../features/customers/data/repositories/loyalty_repository_impl.dart';
import '../../features/customers/presentation/bloc/customers_bloc.dart';
import '../../features/customers/presentation/bloc/customer_form_bloc.dart';
import '../../features/customers/presentation/bloc/customer_loyalty_bloc.dart';
import '../../features/customers/presentation/bloc/customer_profile_bloc.dart';
import '../database/daos/customer_dao.dart';
import '../database/daos/employee_dao.dart';
import '../database/daos/supplier_dao.dart';
import '../../features/suppliers/domain/repositories/supplier_repository.dart';
import '../../features/suppliers/data/datasources/supplier_local_datasource.dart';
import '../../features/suppliers/data/repositories/supplier_repository_impl.dart';
import '../../features/suppliers/presentation/bloc/suppliers_bloc.dart';
import '../../features/suppliers/presentation/bloc/supplier_form_bloc.dart';
import '../../features/suppliers/presentation/bloc/supplier_profile_bloc.dart';
import '../../features/employees/domain/repositories/employee_repository.dart';
import '../../features/employees/data/repositories/employee_repository_impl.dart';
import '../../features/employees/presentation/bloc/employees_bloc.dart';
import '../../features/employees/presentation/bloc/attendance_bloc.dart';
import '../../features/employees/presentation/bloc/leave_requests_bloc.dart';
import '../../features/employees/presentation/bloc/payroll_bloc.dart';
import '../../features/employees/presentation/bloc/roles_bloc.dart';
import '../database/daos/accounting_dao.dart';
import '../../features/expenses/domain/repositories/expense_repository.dart';
import '../../features/expenses/data/datasources/expense_local_datasource.dart';
import '../../features/expenses/data/repositories/expense_repository_impl.dart';
import '../../features/expenses/presentation/bloc/expenses_bloc.dart';
import '../../features/expenses/presentation/bloc/expense_form_bloc.dart';
import '../../features/expenses/presentation/bloc/expense_categories_bloc.dart';
import '../../features/accounting/domain/repositories/journal_repository.dart';
import '../../features/accounting/data/datasources/journal_local_datasource.dart';
import '../../features/accounting/data/repositories/journal_repository_impl.dart';
import '../../features/accounting/presentation/bloc/accounts_bloc.dart';
import '../../features/accounting/presentation/bloc/journal_entries_bloc.dart';
import '../../features/accounting/presentation/bloc/journal_entry_form_bloc.dart';
import '../../features/accounting/presentation/bloc/accounting_health_bloc.dart';
import '../../features/reports/presentation/bloc/reports_bloc.dart';
import '../../features/reports/presentation/bloc/inventory_reports_bloc.dart';
import '../../features/reports/presentation/bloc/customer_reports_bloc.dart';
import '../../features/reports/presentation/bloc/customer_sales_returns_reports_bloc.dart';
import '../../features/reports/presentation/bloc/top_customers_bloc.dart';
import '../../features/reports/presentation/bloc/customer_payment_reports_bloc.dart';
import '../../features/reports/presentation/bloc/customer_sales_report_bloc.dart';
import '../../features/reports/presentation/bloc/customer_aging_report_bloc.dart';

final sl = GetIt.instance;

Future<void> init() async {
  // External
  final sharedPreferences = await SharedPreferences.getInstance();
  sl.registerLazySingleton(() => sharedPreferences);

  // Database
  sl.registerLazySingleton(() => AppDatabase());
  
  // DAOs
  sl.registerLazySingleton(() => ProductDao(sl()));
  sl.registerLazySingleton(() => ProductVariantDao(sl()));
  sl.registerLazySingleton(() => ProductColorDao(sl()));
  sl.registerLazySingleton(() => CategoryDao(sl()));
  sl.registerLazySingleton(() => SizeDao(sl()));
  sl.registerLazySingleton(() => SettingsDao(sl()));
  sl.registerLazySingleton(() => BarcodeTemplateDao(sl()));
  sl.registerLazySingleton(() => PurchaseDao(sl()));
  sl.registerLazySingleton(() => SaleDao(sl()));
  sl.registerLazySingleton(() => CustomerDao(sl()));
  sl.registerLazySingleton(() => EmployeeDao(sl()));
  sl.registerLazySingleton(() => SupplierDao(sl()));
  sl.registerLazySingleton(() => AccountingDao(sl()));

  // Auth Services
  sl.registerLazySingleton(() => PasswordService());
  sl.registerLazySingleton(() => SessionService());
  sl.registerLazySingleton(() => PermissionService());
  sl.registerLazySingleton<AuthRepositoryInterface>(
    () => AuthRepository(
      database: sl(),
      passwordService: sl(),
      sessionService: sl(),
    ),
  );
  sl.registerLazySingleton<UserRepositoryInterface>(
    () => UserRepository(
      database: sl(),
      passwordService: sl(),
    ),
  );

  // Core Services
  sl.registerLazySingleton(() => ThemeService(sl()));
  sl.registerLazySingleton(() => LocalizationService(sl()));
  sl.registerLazySingleton(() => CurrencyService(sl()));
  sl.registerLazySingleton(() => AuditLogService(sl<AppDatabase>()));

  // Datasources
  sl.registerLazySingleton<ProductLocalDatasource>(
    () => ProductLocalDatasourceImpl(sl()),
  );
  sl.registerLazySingleton<VariantLocalDatasource>(
    () => VariantLocalDatasourceImpl(sl(), sl(), sl()),
  );

  // Feature Repositories
  sl.registerLazySingleton<ProductRepository>(
    () => ProductRepositoryImpl(sl()),
  );
  sl.registerLazySingleton<ProductVariantRepository>(
    () => ProductVariantRepositoryImpl(sl()),
  );
  sl.registerLazySingleton<CategoryRepository>(
    () => CategoryRepositoryImpl(sl()),
  );
  sl.registerLazySingleton<ProductColorRepository>(
    () => ProductColorRepositoryImpl(sl()),
  );
  sl.registerLazySingleton<SizeRepository>(
    () => SizeRepositoryImpl(sl()),
  );

  // Purchases
  sl.registerLazySingleton<PurchaseLocalDatasource>(
    () => PurchaseLocalDatasourceImpl(sl<PurchaseDao>()),
  );
  sl.registerLazySingleton<PurchaseRepository>(
    () => PurchaseRepositoryImpl(sl<PurchaseLocalDatasource>(), sl<AuditLogService>(), sl<SessionService>()),
  );

  // Sales
  sl.registerLazySingleton<SaleLocalDatasource>(
    () => SaleLocalDatasourceImpl(sl<SaleDao>()),
  );
  sl.registerLazySingleton<SaleRepository>(
    () => SaleRepositoryImpl(sl<SaleLocalDatasource>(), sl<SaleDao>()),
  );

  // Customers
  sl.registerLazySingleton<CustomerLocalDatasource>(
    () => CustomerLocalDatasourceImpl(sl<CustomerDao>()),
  );
  sl.registerLazySingleton<CustomerRepository>(
    () => CustomerRepositoryImpl(
      sl<CustomerLocalDatasource>(),
      sl<AuditLogService>(),
      sl<SessionService>(),
    ),
  );
  sl.registerLazySingleton<LoyaltyRepository>(
    () => LoyaltyRepositoryImpl(sl<AppDatabase>()),
  );

  // Suppliers
  sl.registerLazySingleton<SupplierLocalDatasource>(
    () => SupplierLocalDatasourceImpl(sl<SupplierDao>()),
  );
  sl.registerLazySingleton<SupplierRepository>(
    () => SupplierRepositoryImpl(
      sl<SupplierLocalDatasource>(),
      sl<AuditLogService>(),
      sl<SessionService>(),
    ),
  );

  // Employees
  sl.registerLazySingleton<EmployeeRepository>(
    () => EmployeeRepositoryImpl(sl<EmployeeDao>()),
  );

  // Blocs
  sl.registerFactory(() => ThemeBloc(sl()));
  sl.registerFactory(() => LocalizationBloc(sl()));
  sl.registerFactory(() => CurrencyBloc(sl<CurrencyService>()));
  // AuthBloc must be singleton so router and widgets share the same instance
  sl.registerLazySingleton(() => AuthBloc(repository: sl()));
  sl.registerFactory(() => UsersBloc(sl<UserRepositoryInterface>()));
  sl.registerFactory(() => UserStatsBloc(sl<UserRepositoryInterface>()));
  sl.registerFactory(() => UserFormBloc(sl<UserRepositoryInterface>()));
  
  // Import Products Services
  sl.registerLazySingleton<ParseImportFile>(() => FileImportService());
  sl.registerLazySingleton<ValidateImportData>(
    () => ImportValidationService(sl<ProductRepository>()),
  );
  sl.registerLazySingleton<ImportProducts>(
    () => ProductImportService(
      sl<ProductRepository>(),
      sl<ProductVariantRepository>(),
      sl<CategoryRepository>(),
    ),
  );

  // Export Products Services
  sl.registerLazySingleton<ExportService>(
    () => ExportServiceImpl(
      sl<ProductRepository>(),
      sl<ProductVariantRepository>(),
      sl<CategoryRepository>(),
    ),
  );

  // Feature Blocs
  sl.registerFactory(() => ProductsBloc(sl()));
  sl.registerFactory(() => ProductFormBloc(sl<ProductRepository>(), sl<ProductVariantRepository>()));
  sl.registerFactory(() => ProductVariantsBloc(sl<ProductVariantRepository>()));
  sl.registerFactory(() => BulkProductBloc(sl<ProductRepository>(), sl<ProductVariantRepository>()));
  sl.registerFactory(() => EditPricesBloc(sl<ProductRepository>()));
  sl.registerFactory(() => CategoriesBloc(sl<CategoryRepository>()));
  sl.registerFactory(() => ColorsBloc(sl<ProductColorRepository>()));
  sl.registerFactory(() => SizesBloc(sl<SizeRepository>()));
  sl.registerFactory(() => VariantSummariesBloc(sl<ProductVariantRepository>()));
  sl.registerFactory(() => VariantPreviewsBloc(sl<ProductVariantRepository>()));
  sl.registerFactory(() => ImportProductsBloc(
    parseImportFile: sl<ParseImportFile>(),
    validateImportData: sl<ValidateImportData>(),
    importProducts: sl<ImportProducts>(),
    currencyService: sl<CurrencyService>(),
  ));
  sl.registerFactory(() => ExportBloc(sl<ExportService>()));

  // Purchases Blocs
  sl.registerFactory(() => PurchasesBloc(sl<PurchaseRepository>()));
  sl.registerFactory(() => PurchaseFormBloc(sl<PurchaseRepository>(), sl<ProductVariantRepository>()));
  sl.registerFactory(() => PurchaseReturnsBloc(sl<PurchaseRepository>()));
  sl.registerFactory(() => PurchaseReturnFormBloc(sl<PurchaseRepository>()));

  // Sales Blocs
  sl.registerFactory(() => SalesBloc(sl<SaleRepository>()));
  sl.registerFactory(() => SaleFormBloc(sl<SaleRepository>(), sl<ProductVariantRepository>()));
  sl.registerFactory(() => SaleReturnsBloc(sl<SaleRepository>()));
  sl.registerFactory(() => SaleReturnFormBloc(sl<SaleRepository>()));

  // Customers Blocs
  sl.registerFactory(() => CustomersBloc(sl<CustomerRepository>()));
  sl.registerFactory(() => CustomerFormBloc(sl<CustomerRepository>()));
  sl.registerFactory(() => CustomerLoyaltyBloc(sl<LoyaltyRepository>()));
  sl.registerFactory(() => CustomerProfileBloc(sl<CustomerRepository>()));

  // Employees Blocs
  sl.registerFactory(() => EmployeesBloc(sl<EmployeeRepository>()));
  sl.registerFactory(() => EmployeeStatsBloc(sl<EmployeeRepository>()));
  sl.registerFactory(() => AttendanceBloc(sl<EmployeeRepository>()));
  sl.registerFactory(() => LeaveRequestsBloc(sl<EmployeeRepository>()));
  sl.registerFactory(() => PayrollBloc(sl<EmployeeRepository>()));
  sl.registerFactory(() => RolesBloc(sl<EmployeeRepository>()));

  // Suppliers Blocs
  sl.registerFactory(() => SuppliersBloc(sl<SupplierRepository>()));
  sl.registerFactory(() => SupplierFormBloc(sl<SupplierRepository>()));
  sl.registerFactory(() => SupplierProfileBloc(sl<SupplierRepository>()));

  // Expenses
  sl.registerLazySingleton<ExpenseLocalDatasource>(
    () => ExpenseLocalDatasourceImpl(sl<AccountingDao>()),
  );
  sl.registerLazySingleton<ExpenseRepository>(
    () => ExpenseRepositoryImpl(sl<ExpenseLocalDatasource>()),
  );

  // Expenses Blocs
  sl.registerFactory(() => ExpensesBloc(sl<ExpenseRepository>()));
  sl.registerFactory(() => ExpenseFormBloc(sl<ExpenseRepository>()));
  sl.registerFactory(() => ExpenseCategoriesBloc(sl<ExpenseRepository>()));

  // Accounting / Journal Entries
  sl.registerLazySingleton<JournalLocalDatasource>(
    () => JournalLocalDatasourceImpl(sl<AccountingDao>()),
  );
  sl.registerLazySingleton<JournalRepository>(
    () => JournalRepositoryImpl(sl<JournalLocalDatasource>()),
  );

  // Accounting Blocs
  sl.registerFactory(() => AccountsBloc(sl<JournalRepository>()));
  sl.registerFactory(() => JournalEntriesBloc(sl<JournalRepository>()));
  sl.registerFactory(() => JournalEntryFormBloc(sl<JournalRepository>()));
  sl.registerFactory(() => AccountingHealthBloc(sl<JournalRepository>()));
  sl.registerFactory(() => ReportsBloc(sl<JournalRepository>()));
  sl.registerFactory(() => InventoryReportsBloc(sl<AppDatabase>()));
  sl.registerFactory(() => CustomerReportsBloc(sl<AppDatabase>()));
  sl.registerFactory(() => CustomerSalesReturnsBloc(sl<AppDatabase>()));
  sl.registerFactory(() => TopCustomersBloc(sl<AppDatabase>()));
  sl.registerFactory(() => CustomerPaymentReportsBloc(sl<AppDatabase>()));
  sl.registerFactory(() => CustomerSalesReportBloc(sl<AppDatabase>()));
  sl.registerFactory(() => CustomerAgingReportBloc(sl<AppDatabase>()));

  // Barcode Services
  sl.registerLazySingleton(() => BarcodeValidationService());
  sl.registerLazySingleton(() => BarcodePrinterService(settingsDao: sl()));

  // Settings Services
  sl.registerLazySingleton(() => CompanyProfileService(sl()));
  
  // Settings Blocs
  sl.registerFactory(() => CompanyBloc(sl<CompanyProfileService>()));
  
  // Barcode Blocs
  sl.registerFactory(() => BarcodeScannerBloc(
    productRepository: sl(),
    validationService: sl(),
  ));
  sl.registerFactory(() => BarcodeDesignBloc(
    templateDao: sl<BarcodeTemplateDao>(),
    printerService: sl<BarcodePrinterService>(),
    companyProfileService: sl<CompanyProfileService>(),
    productVariantDao: sl<ProductVariantDao>(),
  ));
}
