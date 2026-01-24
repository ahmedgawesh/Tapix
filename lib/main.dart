import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'core/bloc/localization_bloc.dart';
import 'core/bloc/realtime_bloc.dart';
import 'core/bloc/theme_bloc.dart';
import 'core/di/injection_container.dart' as di;
import 'core/services/localization_service.dart';
import 'core/theme/app_theme.dart';
import 'generated/codegen_loader.g.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();
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
      assetLoader: const CodegenLoader(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => di.sl<ThemeBloc>()),
        BlocProvider(create: (_) => di.sl<LocalizationBloc>()),
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

                return MaterialApp(
                  title: 'Tapix',
                  debugShowCheckedModeBanner: false,
                  localizationsDelegates: context.localizationDelegates,
                  supportedLocales: context.supportedLocales,
                  locale: locale,
                  theme: AppTheme.lightTheme,
                  darkTheme: AppTheme.darkTheme,
                  themeMode: themeMode,
                  home: const HomePage(),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('app.name').tr(),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'settings.title',
              style: Theme.of(context).textTheme.headlineMedium,
            ).tr(),
            const SizedBox(height: 32),
            // Theme Section
            Text(
              'settings.theme',
              style: Theme.of(context).textTheme.titleMedium,
            ).tr(),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: [
                FilledButton.tonal(
                  onPressed: () => context
                      .read<ThemeBloc>()
                      .add(const ThemeChanged(ThemeMode.light)),
                  child: const Text('settings.light').tr(),
                ),
                FilledButton.tonal(
                  onPressed: () => context
                      .read<ThemeBloc>()
                      .add(const ThemeChanged(ThemeMode.dark)),
                  child: const Text('settings.dark').tr(),
                ),
                FilledButton.tonal(
                  onPressed: () => context
                      .read<ThemeBloc>()
                      .add(const ThemeChanged(ThemeMode.system)),
                  child: const Text('settings.system').tr(),
                ),
              ],
            ),
            const SizedBox(height: 32),
            // Language Section
            Text(
              'settings.language',
              style: Theme.of(context).textTheme.titleMedium,
            ).tr(),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: [
                for (final locale in LocalizationService.supportedLocales)
                  OutlinedButton(
                    onPressed: () => context
                        .read<LocalizationBloc>()
                        .add(LocaleChanged(locale)),
                    child: Text(locale.languageCode.toUpperCase()),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
