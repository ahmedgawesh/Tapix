import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../bloc/localization_bloc.dart';
import '../bloc/theme_bloc.dart';
import '../database/app_database.dart';
import '../services/localization_service.dart';
import '../services/theme_service.dart';
import '../../features/auth/auth.dart';

final sl = GetIt.instance;

Future<void> init() async {
  // External
  final sharedPreferences = await SharedPreferences.getInstance();
  sl.registerLazySingleton(() => sharedPreferences);

  // Database
  sl.registerLazySingleton(() => AppDatabase());

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

  // Blocs
  sl.registerFactory(() => ThemeBloc(sl()));
  sl.registerFactory(() => LocalizationBloc(sl()));
  // AuthBloc must be singleton so router and widgets share the same instance
  sl.registerLazySingleton(() => AuthBloc(repository: sl()));
}
