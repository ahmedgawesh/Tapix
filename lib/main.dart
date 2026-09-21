import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'core/services/crashlytics_service.dart';
import 'core/services/push_notification_service.dart';
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
import 'core/services/lan/lan_network_service.dart';
import 'core/services/lan/device_mode_reset_service.dart';
import 'core/services/desktop_license_service.dart';
import 'core/utils/platform_utils.dart';
import 'core/widgets/desktop_license_gate.dart';

/// Check if running on Linux desktop (not web)
bool get _isLinuxDesktop => !kIsWeb && PlatformUtils.isLinux;

void main() {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      await EasyLocalization.ensureInitialized();

      // Initialize Firebase (not supported on Linux desktop)
      if (!_isLinuxDesktop) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }

      // Push notifications are deliberately independent from licensing.
      // Android/iOS devices register with the standalone TapBix Notifications
      // WordPress plugin; Windows is handled separately in a later phase.
      if (!kIsWeb && (PlatformUtils.isAndroid || PlatformUtils.isIOS)) {
        await PushNotificationService.instance.initialize();
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

      // Restore the selected standalone/master/client role. The SQLite file is
      // never shared; the master exposes only explicit local-network APIs.
      await di.sl<LanNetworkService>().initialize();

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
    },
    (error, stackTrace) {
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
    },
  );
}

class TapixApp extends StatefulWidget {
  const TapixApp({super.key});

  @override
  State<TapixApp> createState() => _TapixAppState();
}

class _TapixAppState extends State<TapixApp> {
  StreamSubscription<LanNetworkSnapshot>? _lanLocaleSubscription;
  StreamSubscription<LanMasterActivityEvent>? _lanActivitySubscription;
  StreamSubscription<RealtimeState<UserEntity?>>?
  _pendingDeviceModeSubscription;
  final _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
  String? _appliedMasterLocaleCode;

  @override
  void initState() {
    super.initState();
    _setupBackButtonHandler();
    final lan = di.sl<LanNetworkService>();
    _lanLocaleSubscription = lan.changes.listen(_syncMasterLocale);
    _lanActivitySubscription = lan.masterActivityEvents.listen(
      _showMasterActivity,
    );
    _pendingDeviceModeSubscription = di.sl<AuthBloc>().stream.listen(
      _applyPendingDeviceMode,
    );
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _syncMasterLocale(lan.snapshot),
    );
  }

  Future<void> _syncMasterLocale(LanNetworkSnapshot snapshot) async {
    if (snapshot.mode != LanMode.client) {
      _appliedMasterLocaleCode = null;
      return;
    }
    final code = snapshot.masterLocaleCode;
    if (!mounted ||
        !const {'ar', 'en', 'fr'}.contains(code) ||
        _appliedMasterLocaleCode == code) {
      return;
    }
    _appliedMasterLocaleCode = code;
    final locale = Locale(code!);
    if (context.locale.languageCode != code) {
      await context.setLocale(locale);
    }
    await di.sl<LocalizationService>().setLocale(locale);
  }

  void _applyPendingDeviceMode(RealtimeState<UserEntity?> state) {
    if (state is! AuthAuthenticated) return;
    unawaited(
      di
          .sl<DeviceModeResetService>()
          .applyPendingTargetForOwner(state.user)
          .catchError((Object error, StackTrace stackTrace) {
            LoggingService.error(
              'Unable to apply pending fresh device mode',
              error: error,
              stackTrace: stackTrace,
            );
          }),
    );
  }

  void _showMasterActivity(LanMasterActivityEvent event) {
    if (!mounted ||
        di.sl<LanNetworkService>().snapshot.mode != LanMode.master) {
      return;
    }
    final titleKey = switch (event.type) {
      LanMasterActivityType.sale => 'settings.network.activity.sale',
      LanMasterActivityType.saleReturn =>
        'settings.network.activity.sale_return',
      LanMasterActivityType.saleAdjustmentReturn =>
        'settings.network.activity.sale_adjustment_return',
    };
    final color = event.type == LanMasterActivityType.sale
        ? const Color(0xFF1B5E20)
        : const Color(0xFFE65100);
    final amount = di.sl<CurrencyService>().formatCents(event.totalCents);
    final details = 'settings.network.activity.details'.tr(
      args: [event.actorName, event.deviceName, event.documentNumber, amount],
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final messenger = _scaffoldMessengerKey.currentState;
      if (!mounted || messenger == null) return;
      messenger.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
          backgroundColor: color,
          content: Row(
            children: [
              Icon(
                event.type == LanMasterActivityType.sale
                    ? Icons.point_of_sale
                    : Icons.assignment_return,
                color: Colors.white,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titleKey.tr(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(details, style: const TextStyle(color: Colors.white)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    });
  }

  @override
  void dispose() {
    _lanLocaleSubscription?.cancel();
    _lanActivitySubscription?.cancel();
    _pendingDeviceModeSubscription?.cancel();
    super.dispose();
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
      providers: [RepositoryProvider(create: (_) => di.sl<CurrencyService>())],
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
            final themeMode = (themeState is RealtimeSuccess<ThemeMode>)
                ? themeState.data
                : ThemeMode.system;

            return MaterialApp.router(
              title: 'TapBix',
              scaffoldMessengerKey: _scaffoldMessengerKey,
              debugShowCheckedModeBanner: false,
              localizationsDelegates: context.localizationDelegates,
              supportedLocales: context.supportedLocales,
              locale: context.locale,
              theme: AppTheme.lightTheme,
              darkTheme: AppTheme.darkTheme,
              themeMode: themeMode,
              routerConfig: AppRouter.router,
              // Wrap every route in a bottom-only SafeArea so content never
              // renders behind the system navigation bar (edge-to-edge mode).
              // top: false because AppBar handles status-bar insets itself.
              builder: (context, child) {
                return DesktopLicenseGate(
                  service: di.sl<DesktopLicenseService>(),
                  child: SafeArea(
                    top: false,
                    bottom: true,
                    child: child ?? const SizedBox.shrink(),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
