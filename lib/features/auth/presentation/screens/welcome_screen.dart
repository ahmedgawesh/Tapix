import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/bloc/localization_bloc.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/bloc/theme_bloc.dart';
import '../../../../core/services/localization_service.dart';

class WelcomeScreen extends StatefulWidget {
  final VoidCallback onComplete;
  
  const WelcomeScreen({super.key, required this.onComplete});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  late ThemeMode _selectedTheme;
  late Locale _selectedLocale;

  @override
  void initState() {
    super.initState();
    // Get current values from blocs
    final themeState = context.read<ThemeBloc>().state;
    _selectedTheme = (themeState is RealtimeSuccess<ThemeMode>) 
        ? themeState.data 
        : ThemeMode.system;
    
    _selectedLocale = context.read<LocalizationBloc>().state.locale;
  }

  void _onThemeChanged(ThemeMode theme) {
    setState(() {
      _selectedTheme = theme;
    });
    // Apply theme immediately
    context.read<ThemeBloc>().add(ThemeChanged(theme));
  }

  void _onLocaleChanged(Locale locale) {
    setState(() {
      _selectedLocale = locale;
    });
    // Apply locale immediately
    context.read<LocalizationBloc>().add(LocaleChanged(locale));
    context.setLocale(locale);
  }

  void _onContinue() {
    widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final screenWidth = MediaQuery.of(context).size.width;
    
    // Responsive breakpoints
    final isDesktop = screenWidth >= 1024;
    final isTablet = screenWidth >= 600 && screenWidth < 1024;
    
    // Responsive sizing
    final logoSize = isDesktop ? 160.0 : (isTablet ? 140.0 : 120.0);
    final maxWidth = isDesktop ? 500.0 : (isTablet ? 450.0 : 400.0);
    final padding = isDesktop ? 32.0 : (isTablet ? 28.0 : 24.0);
    final titleStyle = isDesktop 
        ? theme.textTheme.headlineLarge 
        : (isTablet ? theme.textTheme.headlineMedium : theme.textTheme.headlineSmall);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(padding),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Logo
                  Image.asset(
                    'assets/logos/logo.png',
                    width: logoSize,
                    height: logoSize,
                    fit: BoxFit.contain,
                  ),
                  SizedBox(height: isDesktop ? 32 : 24),
                  
                  // Welcome Title
                  Text(
                    'welcome.title',
                    style: titleStyle?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                    ),
                    textAlign: TextAlign.center,
                  ).tr(),
                  const SizedBox(height: 8),
                  
                  Text(
                    'welcome.subtitle',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ).tr(),
                  SizedBox(height: isDesktop ? 48 : 40),

                  // Language Selection
                  Card(
                    elevation: 0,
                    color: colorScheme.surfaceContainerHighest,
                    child: Padding(
                      padding: EdgeInsets.all(isDesktop ? 20 : 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(LucideIcons.languages, color: colorScheme.primary),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'welcome.select_language',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ).tr(),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          ...LocalizationService.supportedLocales.map((locale) {
                            final isSelected = _selectedLocale.languageCode == locale.languageCode;
                            return _LanguageOption(
                              locale: locale,
                              isSelected: isSelected,
                              onTap: () => _onLocaleChanged(locale),
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Theme Selection
                  Card(
                    elevation: 0,
                    color: colorScheme.surfaceContainerHighest,
                    child: Padding(
                      padding: EdgeInsets.all(isDesktop ? 20 : 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(LucideIcons.palette, color: colorScheme.primary),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'welcome.select_theme',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ).tr(),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          _ThemeOption(
                            icon: LucideIcons.sun,
                            label: 'welcome.theme_light'.tr(),
                            isSelected: _selectedTheme == ThemeMode.light,
                            onTap: () => _onThemeChanged(ThemeMode.light),
                          ),
                          _ThemeOption(
                            icon: LucideIcons.moon,
                            label: 'welcome.theme_dark'.tr(),
                            isSelected: _selectedTheme == ThemeMode.dark,
                            onTap: () => _onThemeChanged(ThemeMode.dark),
                          ),
                          _ThemeOption(
                            icon: LucideIcons.monitor,
                            label: 'welcome.theme_system'.tr(),
                            isSelected: _selectedTheme == ThemeMode.system,
                            onTap: () => _onThemeChanged(ThemeMode.system),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: isDesktop ? 40 : 32),

                  // Continue Button
                  FilledButton.icon(
                    onPressed: _onContinue,
                    icon: const Icon(LucideIcons.arrowRight),
                    label: Text('welcome.continue'.tr()),
                    style: FilledButton.styleFrom(
                      padding: EdgeInsets.symmetric(
                        vertical: isDesktop ? 20 : 16,
                        horizontal: 24,
                      ),
                      textStyle: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LanguageOption extends StatelessWidget {
  final Locale locale;
  final bool isSelected;
  final VoidCallback onTap;

  const _LanguageOption({
    required this.locale,
    required this.isSelected,
    required this.onTap,
  });

  String get _languageName {
    switch (locale.languageCode) {
      case 'en':
        return 'english'.tr();
      case 'ar':
        return 'arabic'.tr();
      case 'fr':
        return 'french'.tr();
      default:
        return locale.languageCode;
    }
  }

  String get _languageFlag {
    switch (locale.languageCode) {
      case 'en':
        return '🇺🇸';
      case 'ar':
        return '🇸🇦';
      case 'fr':
        return '🇫🇷';
      default:
        return '🌐';
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: isSelected ? colorScheme.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Text(_languageFlag, style: const TextStyle(fontSize: 24)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _languageName,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      color: isSelected 
                          ? colorScheme.onPrimaryContainer 
                          : colorScheme.onSurface,
                    ),
                  ),
                ),
                if (isSelected)
                  Icon(
                    LucideIcons.check,
                    color: colorScheme.primary,
                    size: 20,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ThemeOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _ThemeOption({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: isSelected ? colorScheme.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: isSelected 
                      ? colorScheme.onPrimaryContainer 
                      : colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      color: isSelected 
                          ? colorScheme.onPrimaryContainer 
                          : colorScheme.onSurface,
                    ),
                  ),
                ),
                if (isSelected)
                  Icon(
                    LucideIcons.check,
                    color: colorScheme.primary,
                    size: 20,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
