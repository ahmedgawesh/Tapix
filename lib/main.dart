import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'core/services/logging_service.dart';
import 'core/bloc/simple_bloc_observer.dart';
import 'features/settings/presentation/bloc/company_bloc.dart';

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await EasyLocalization.ensureInitialized();

    Bloc.observer = SimpleBlocObserver();

    FlutterError.onError = (details) {
      LoggingService.error(
        'FlutterError.onError',
        error: details.exception,
        stackTrace: details.stack,
      );
      FlutterError.presentError(details);
    };

    WidgetsBinding.instance.platformDispatcher.onError = (error, stackTrace) {
      LoggingService.error(
        'PlatformDispatcher.onError',
        error: error,
        stackTrace: stackTrace,
      );
      return true;
    };

    ErrorWidget.builder = (details) {
      LoggingService.error(
        'ErrorWidget.builder',
        error: details.exception,
        stackTrace: details.stack,
      );
      return ErrorWidget(details.exception);
    };

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
        child: const TapixApp(),
      ),
    );
  }, (error, stackTrace) {
    LoggingService.error(
      'runZonedGuarded',
      error: error,
      stackTrace: stackTrace,
    );
  });
}

class TapixApp extends StatefulWidget {
  const TapixApp({super.key});

  @override
  State<TapixApp> createState() => _TapixAppState();
}

class _TapixAppState extends State<TapixApp> {

  @override
  void initState() {
    super.initState();
    _setupBackButtonHandler();
  }

  void _setupBackButtonHandler() {
    SystemChannels.platform.setMethodCallHandler((call) async {
      if (call.method == 'SystemNavigator.pop') {
        final router = AppRouter.router;
        
        if (router.canPop()) {
          router.pop();
          return null;
        }
        
        final currentPath = router.routeInformationProvider.value.uri.path;
        if (currentPath != '/dashboard') {
          router.go('/dashboard');
          return null;
        }
        
        // At dashboard: consume the back event to prevent app exit
        return null;
      }
      return null;
    });
  }

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
        child: BlocBuilder<ThemeBloc, RealtimeState<ThemeMode>>(
          builder: (context, themeState) {
            final themeMode =
                (themeState is RealtimeSuccess<ThemeMode>)
                    ? themeState.data
                    : ThemeMode.system;

            return MaterialApp.router(
              title: 'Tapix',
              debugShowCheckedModeBanner: false,
              localizationsDelegates: context.localizationDelegates,
              supportedLocales: context.supportedLocales,
              locale: context.locale,
              theme: AppTheme.lightTheme,
              darkTheme: AppTheme.darkTheme,
              themeMode: themeMode,
              routerConfig: AppRouter.router,
            );
          },
        ),
      ),
    );
  }
}

