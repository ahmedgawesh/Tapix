import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'core/bloc/localization_bloc.dart';
import 'core/bloc/realtime_bloc.dart';
import 'core/bloc/theme_bloc.dart';
import 'core/bloc/currency_bloc.dart';
import 'core/di/injection_container.dart' as di;
import 'core/router/app_router.dart';
import 'core/services/localization_service.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/auth.dart';
import 'core/services/currency_service.dart';
import 'core/bloc/simple_bloc_observer.dart';
import 'features/settings/presentation/bloc/company_bloc.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();
  
  Bloc.observer = SimpleBlocObserver();
  
  await di.init();

  final localizationService = di.sl<LocalizationService>();
  final startLocale = localizationService.getLocale();

  runApp(
    EasyLocalization(
      supportedLocales: LocalizationService.supportedLocales,
      path: 'assets/translations',
      fallbackLocale: const Locale('en'),
      startLocale: startLocale,
      saveLocale: false,
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Get the singleton AuthBloc and trigger auth check
    final authBloc = di.sl<AuthBloc>()..add(const AuthCheckRequested());
    
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider(create: (_) => di.sl<CurrencyService>()),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider(create: (_) => di.sl<ThemeBloc>()),
          BlocProvider(create: (_) => di.sl<LocalizationBloc>()),
          BlocProvider(create: (_) => di.sl<CurrencyBloc>()),
          BlocProvider(create: (_) => di.sl<CompanyBloc>()),
          BlocProvider.value(value: authBloc),
        ],
        child: BlocListener<LocalizationBloc, RealtimeState<Locale>>(
          listener: (context, state) {
            if (state is RealtimeSuccess<Locale>) {
              context.setLocale(state.data);
            }
          },
          child: BlocBuilder<ThemeBloc, RealtimeState<ThemeMode>>(
            builder: (context, themeState) {
              return BlocBuilder<LocalizationBloc, RealtimeState<Locale>>(
                builder: (context, localeState) {
                  final themeMode =
                      (themeState is RealtimeSuccess<ThemeMode>)
                          ? themeState.data
                          : ThemeMode.system;
                  
                  final locale =
                      (localeState is RealtimeSuccess<Locale>)
                          ? localeState.data
                          : context.locale;

                  return MaterialApp.router(
                    key: ValueKey('app_${locale.languageCode}'),
                    title: 'Tapix',
                    debugShowCheckedModeBanner: false,
                    localizationsDelegates: context.localizationDelegates,
                    supportedLocales: context.supportedLocales,
                    locale: locale,
                    theme: AppTheme.lightTheme,
                    darkTheme: AppTheme.darkTheme,
                    themeMode: themeMode,
                    routerConfig: AppRouter.router,
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

