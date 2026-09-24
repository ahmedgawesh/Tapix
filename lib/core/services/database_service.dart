import 'package:get_it/get_it.dart';
import '../database/app_database.dart';
import '../database/daos/product_dao.dart';
import '../services/audit_log_service.dart';
import '../../features/auth/data/services/session_service.dart';
import '../../features/products/domain/repositories/product_repository.dart';
import '../../features/products/data/repositories/product_repository_impl.dart';
import '../../features/products/data/datasources/product_local_datasource.dart';

final getIt = GetIt.instance;

void setupDatabase() {
  final database = AppDatabase();

  getIt.registerSingleton<AppDatabase>(database);

  getIt.registerLazySingleton(() => database.productDao);
  getIt.registerLazySingleton(() => database.saleDao);
  getIt.registerLazySingleton(() => database.customerDao);
  getIt.registerLazySingleton(() => database.accountingDao);

  getIt.registerLazySingleton<ProductLocalDatasource>(
    () => ProductLocalDatasourceImpl(getIt<ProductDao>()),
  );
  getIt.registerLazySingleton<ProductRepository>(
    () => ProductRepositoryImpl(
      getIt<ProductLocalDatasource>(),
      getIt<AuditLogService>(),
      getIt<SessionService>(),
    ),
  );
}
