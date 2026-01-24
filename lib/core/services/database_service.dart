import 'package:get_it/get_it.dart';
import '../database/app_database.dart';
import '../database/daos/product_dao.dart';
import '../../features/products/data/repositories/product_repository.dart';

final getIt = GetIt.instance;

void setupDatabase() {
  final database = AppDatabase();
  
  getIt.registerSingleton<AppDatabase>(database);
  
  getIt.registerLazySingleton(() => database.productDao);
  getIt.registerLazySingleton(() => database.saleDao);
  getIt.registerLazySingleton(() => database.customerDao);
  getIt.registerLazySingleton(() => database.accountingDao);
  
  getIt.registerLazySingleton(() => ProductRepository(getIt<ProductDao>()));
}
