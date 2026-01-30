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
import '../database/daos/employee_dao.dart';
import '../services/currency_service.dart';
import '../services/localization_service.dart';
import '../services/theme_service.dart';
import '../../features/auth/auth.dart';
import '../../features/users/data/repositories/user_repository.dart';
import '../../features/users/presentation/bloc/users_bloc.dart';
import '../../features/products/domain/repositories/product_repository.dart';
import '../../features/products/domain/repositories/product_variant_repository.dart';
import '../../features/products/domain/repositories/category_repository.dart';
import '../../features/products/domain/repositories/product_color_repository.dart';
import '../../features/products/domain/repositories/size_repository.dart';
import '../../features/products/data/repositories/product_repository_impl.dart';
import '../../features/products/data/repositories/product_variant_repository_impl.dart';
import '../../features/products/data/repositories/category_repository_impl.dart';
import '../../features/products/data/repositories/product_color_repository_impl.dart';
import '../../features/products/data/repositories/size_repository_impl.dart';
import '../../features/products/data/datasources/product_local_datasource.dart';
import '../../features/products/data/datasources/variant_local_datasource.dart';
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
import '../../features/products/presentation/bloc/product_variant_previews_bloc.dart';
import '../../features/purchases/domain/repositories/purchase_repository.dart';
import '../../features/purchases/data/repositories/purchase_repository_impl.dart';
import '../../features/purchases/data/datasources/purchase_local_datasource.dart';
import '../../features/purchases/presentation/bloc/purchases_bloc.dart';
import '../../features/purchases/presentation/bloc/purchase_form_bloc.dart';
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
import '../../features/barcode/data/repositories/barcode_repository.dart';
import '../../features/barcode/domain/usecases/get_invoice_print_data.dart';
import '../../features/settings/data/services/company_profile_service.dart';
import '../../features/settings/presentation/bloc/company_bloc.dart';
import '../database/daos/supplier_dao.dart';
import '../../features/suppliers/domain/repositories/supplier_repository.dart';
import '../../features/suppliers/data/repositories/supplier_repository_impl.dart';
import '../../features/suppliers/presentation/bloc/suppliers_bloc.dart';
import '../../features/suppliers/presentation/bloc/supplier_metrics_bloc.dart';
import '../../features/suppliers/presentation/bloc/supplier_form_bloc.dart';
import '../database/daos/customer_dao.dart';
import '../../features/customers/domain/repositories/customer_repository.dart';
import '../../features/customers/data/repositories/customer_repository_impl.dart';
import '../../features/customers/presentation/bloc/customers_bloc.dart';
import '../../features/customers/presentation/bloc/customer_metrics_bloc.dart';
import '../../features/customers/presentation/bloc/customer_form_bloc.dart';
import '../../features/customers/presentation/bloc/customer_analytics_bloc.dart';
import '../../features/customers/presentation/bloc/loyalty_bloc.dart';
import '../../features/customers/domain/repositories/loyalty_repository.dart';
import '../../features/customers/data/repositories/loyalty_repository_impl.dart';
import '../database/daos/loyalty_dao.dart';
import '../../features/employees/domain/repositories/employee_repository.dart';
import '../../features/employees/data/repositories/employee_repository_impl.dart';
import '../../features/employees/presentation/bloc/employees_bloc.dart';
import '../../features/employees/presentation/bloc/roles_bloc.dart';
import '../../features/employees/presentation/bloc/attendance_bloc.dart';
import '../../features/employees/presentation/bloc/payroll_bloc.dart';
import '../../features/employees/presentation/bloc/leave_requests_bloc.dart';
import '../../features/employees/presentation/bloc/performance_bloc.dart';

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
  sl.registerLazySingleton(() => SupplierDao(sl()));
  sl.registerLazySingleton(() => CustomerDao(sl()));
  sl.registerLazySingleton(() => LoyaltyDao(sl()));
  sl.registerLazySingleton(() => EmployeeDao(sl()));

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

  // Core Services
  sl.registerLazySingleton(() => ThemeService(sl()));
  sl.registerLazySingleton(() => LocalizationService(sl()));
  sl.registerLazySingleton(() => CurrencyService(sl()));

  // Datasources
  sl.registerLazySingleton<ProductLocalDatasource>(
    () => ProductLocalDatasourceImpl(sl()),
  );
  sl.registerLazySingleton<VariantLocalDatasource>(
    () => VariantLocalDatasourceImpl(sl(), sl(), sl()),
  );
  sl.registerLazySingleton<PurchaseLocalDatasource>(
    () => PurchaseLocalDatasourceImpl(sl()),
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
  sl.registerLazySingleton<PurchaseRepository>(
    () => PurchaseRepositoryImpl(sl()),
  );
  sl.registerLazySingleton<SupplierRepository>(
    () => SupplierRepositoryImpl(sl<SupplierDao>()),
  );
  sl.registerLazySingleton<CustomerRepository>(
    () => CustomerRepositoryImpl(sl<CustomerDao>()),
  );
  sl.registerLazySingleton<LoyaltyRepository>(
    () => LoyaltyRepositoryImpl(sl<LoyaltyDao>()),
  );
  sl.registerLazySingleton<EmployeeRepository>(
    () => EmployeeRepositoryImpl(sl<EmployeeDao>()),
  );

  // Blocs
  sl.registerFactory(() => ThemeBloc(sl()));
  sl.registerFactory(() => LocalizationBloc(sl()));
  sl.registerFactory(() => CurrencyBloc(sl<CurrencyService>()));
  // AuthBloc must be singleton so router and widgets share the same instance
  sl.registerLazySingleton(() => AuthBloc(repository: sl()));
  
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
  sl.registerFactory(() => ProductVariantPreviewsBloc(sl<ProductVariantRepository>()));
  sl.registerFactory(() => PurchasesBloc(sl<PurchaseRepository>()));
  sl.registerFactory(() => PurchaseFormBloc(sl<PurchaseRepository>()));
  sl.registerFactory(() => ImportProductsBloc(
    parseImportFile: sl<ParseImportFile>(),
    validateImportData: sl<ValidateImportData>(),
    importProducts: sl<ImportProducts>(),
    currencyService: sl<CurrencyService>(),
  ));
  sl.registerFactory(() => ExportBloc(sl<ExportService>()));
  
  // Supplier Blocs
  sl.registerFactory(() => SuppliersBloc(sl<SupplierRepository>()));
  sl.registerFactory(() => SupplierMetricsBloc(sl<SupplierRepository>()));
  sl.registerFactory(() => SupplierFormBloc(sl<SupplierRepository>()));

  // Customer Blocs
  sl.registerFactory(() => CustomersBloc(sl<CustomerRepository>()));
  sl.registerFactory(() => CustomerMetricsBloc(sl<CustomerRepository>()));
  sl.registerFactory(() => CustomerFormBloc(sl<CustomerRepository>()));
  sl.registerFactory(() => CustomerAnalyticsBloc(sl<CustomerRepository>()));
  sl.registerFactory(() => CustomerHealthBloc(sl<CustomerRepository>()));
  sl.registerFactory(() => CustomerDashboardBloc(sl<CustomerRepository>()));
  
  // Loyalty Blocs
  sl.registerFactory(() => LoyaltyTiersBloc(sl<LoyaltyRepository>()));
  sl.registerFactory(() => LoyaltyRewardsBloc(sl<LoyaltyRepository>()));
  sl.registerFactory(() => LoyaltyMetricsBloc(sl<LoyaltyRepository>()));

  // Employee Blocs
  sl.registerFactory(() => EmployeesBloc(sl<EmployeeRepository>()));
  sl.registerFactory(() => RolesBloc(sl<EmployeeRepository>()));
  sl.registerFactory(() => AttendanceBloc(sl<EmployeeRepository>()));
  sl.registerFactory(() => PayrollBloc(sl<EmployeeRepository>()));
  sl.registerFactory(() => LeaveRequestsBloc(sl<EmployeeRepository>()));
  sl.registerFactory(() => PerformanceBloc(sl<EmployeeRepository>()));

  // User Management
  sl.registerLazySingleton<UserRepository>(() => UserRepository(sl<AppDatabase>(), sl<PasswordService>()));
  sl.registerFactory(() => UsersBloc(sl<UserRepository>()));

  // Barcode Services
  sl.registerLazySingleton(() => BarcodeValidationService());
  sl.registerLazySingleton(() => BarcodePrinterService(settingsDao: sl()));
  
  // Barcode Repository & Use Cases
  sl.registerLazySingleton<BarcodeRepository>(() => BarcodeRepositoryImpl(sl<AppDatabase>()));
  sl.registerLazySingleton(() => GetInvoicePrintData(sl<BarcodeRepository>()));

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
