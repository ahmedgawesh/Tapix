import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_core/firebase_core.dart';
import '../firebase_options.dart';
import 'core/services/crashlytics_service.dart';
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
import 'core/widgets/app_error_widget.dart';
import 'features/settings/presentation/bloc/company_bloc.dart';
import 'features/settings/presentation/bloc/app_settings_bloc.dart';
import 'features/subscription/subscription.dart';
import 'core/services/connectivity_service.dart';
import 'core/utils/platform_utils.dart';

/// Check if running on Linux desktop (not web)
bool get _isLinuxDesktop => !kIsWeb && PlatformUtils.isLinux;

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await EasyLocalization.ensureInitialized();

    // Initialize Firebase (not supported on Linux desktop)
    if (!_isLinuxDesktop) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }

    // Initialize Crashlytics
    final crashlytics = CrashlyticsService.instance;
    await crashlytics.initialize();

    Bloc.observer = SimpleBlocObserver();

    // Flutter framework errors
    FlutterError.onError = (details) {
      LoggingService.error(
        'FlutterError.onError',
        error: details.exception,
        stackTrace: details.stack,
      );
      // Report to Crashlytics
      crashlytics.recordFlutterFatalError(details);
      FlutterError.presentError(details);
    };

    // Platform dispatcher errors (async errors not caught by Flutter)
    WidgetsBinding.instance.platformDispatcher.onError = (error, stackTrace) {
      LoggingService.error(
        'PlatformDispatcher.onError',
        error: error,
        stackTrace: stackTrace,
      );
      // Report to Crashlytics
      crashlytics.recordError(error, stackTrace: stackTrace, fatal: true);
      return true;
    };

    ErrorWidget.builder = (details) {
      LoggingService.error(
        'ErrorWidget.builder',
        error: details.exception,
        stackTrace: details.stack,
      );
      return AppErrorWidget(details: details);
    };

    await di.init();

    // Initialize connectivity service
    await di.sl<ConnectivityService>().initialize();

    // Start the subscription guard (RevenueCat + License + Security)
    di.sl<SubscriptionBloc>().add(const SubscriptionStartGuard());

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
    // Report uncaught errors to Crashlytics
    CrashlyticsService.instance.recordError(
      error,
      stackTrace: stackTrace,
      fatal: true,
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
          BlocProvider.value(value: di.sl<AppSettingsBloc>()),
          BlocProvider.value(value: authBloc),
          BlocProvider.value(value: di.sl<SubscriptionBloc>()),
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

