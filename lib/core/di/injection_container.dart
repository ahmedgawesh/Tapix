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
import '../services/currency_service.dart';
import '../services/localization_service.dart';
import '../services/theme_service.dart';
import '../../features/auth/auth.dart';
import '../../features/products/domain/repositories/product_repository.dart';
import '../../features/products/domain/repositories/product_variant_repository.dart';
import '../../features/products/domain/repositories/category_repository.dart';
import '../../features/products/data/repositories/product_repository_impl.dart';
import '../../features/products/data/repositories/product_variant_repository_impl.dart';
import '../../features/products/data/repositories/category_repository_impl.dart';
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
    () => ProductImportService(sl<ProductRepository>()),
  );

  // Export Products Services
  sl.registerLazySingleton<ExportService>(
    () => ExportServiceImpl(sl<ProductRepository>()),
  );

  // Feature Blocs
  sl.registerFactory(() => ProductsBloc(sl()));
  sl.registerFactory(() => ProductFormBloc(sl()));
  sl.registerFactory(() => ProductVariantsBloc(sl<ProductVariantRepository>()));
  sl.registerFactory(() => BulkProductBloc(sl<ProductRepository>()));
  sl.registerFactory(() => EditPricesBloc(sl<ProductRepository>()));
  sl.registerFactory(() => ColorsBloc(sl<ProductVariantRepository>()));
  sl.registerFactory(() => SizesBloc(sl<ProductVariantRepository>()));
  sl.registerFactory(() => CategoriesBloc(sl<CategoryRepository>()));
  sl.registerFactory(() => ImportProductsBloc(
    parseImportFile: sl<ParseImportFile>(),
    validateImportData: sl<ValidateImportData>(),
    importProducts: sl<ImportProducts>(),
    currencyService: sl<CurrencyService>(),
  ));
  sl.registerFactory(() => ExportBloc(sl<ExportService>()));

  // Barcode Services
  sl.registerLazySingleton(() => BarcodeValidationService());
  sl.registerLazySingleton(() => BarcodePrinterService(settingsDao: sl()));

  // Settings Services
  sl.registerLazySingleton(() => CompanyProfileService(sl()));
  
  // Barcode Blocs
  sl.registerFactory(() => BarcodeScannerBloc(
    productRepository: sl(),
    validationService: sl(),
  ));
  sl.registerFactory(() => BarcodeDesignBloc(
    templateDao: sl<BarcodeTemplateDao>(),
    printerService: sl<BarcodePrinterService>(),
    companyProfileService: sl<CompanyProfileService>(),
  ));
}
