import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:easy_localization/easy_localization.dart';
import 'dart:async';

import '../../../../core/bloc/theme_bloc.dart';
import '../../../../core/bloc/localization_bloc.dart';
import '../../../../core/bloc/currency_bloc.dart';
import '../../../../core/services/currency_service.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../widgets/receipt_settings_section.dart';
import '../widgets/barcode_label_settings_section.dart';
import '../widgets/tax_settings_section.dart';
import '../widgets/inventory_settings_section.dart';
import '../widgets/sales_settings_section.dart';
import '../widgets/security_settings_section.dart';
import '../widgets/reports_settings_section.dart';
import '../widgets/notification_settings_section.dart';
import '../widgets/printer_settings_section.dart';
import '../../../subscription/presentation/screens/paywall_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Timer? _adminPressTimer;

  @override
  void dispose() {
    _adminPressTimer?.cancel();
    super.dispose();
  }

  Future<void> _promptAdminPassword() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => const _AdminPasswordDialog(),
    );

    if (!mounted) return;
    if (ok == true) {
      context.go('/settings/admin-tools');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/dashboard');
            }
          },
          tooltip: 'common.back'.tr(),
        ),
        title: GestureDetector(
          onLongPressStart: (_) {
            _adminPressTimer?.cancel();
            _adminPressTimer = Timer(const Duration(seconds: 3), _promptAdminPassword);
          },
          onLongPressEnd: (_) {
            _adminPressTimer?.cancel();
          },
          child: Text('settings.title'.tr()),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── General ──
          _buildSectionCard(
            context: context,
            title: 'settings.theme'.tr(),
            icon: LucideIcons.palette,
            child: BlocBuilder<ThemeBloc, RealtimeState<ThemeMode>>(
              builder: (context, state) {
                final currentMode = state is RealtimeSuccess<ThemeMode>
                    ? state.data
                    : ThemeMode.system;

                return Column(
                  children: [
                    _buildThemeTile(
                      context: context,
                      title: 'settings.light'.tr(),
                      icon: LucideIcons.sun,
                      mode: ThemeMode.light,
                      currentMode: currentMode,
                      onTap: () {
                        context.read<ThemeBloc>().add(const ThemeChanged(ThemeMode.light));
                      },
                    ),
                    _buildThemeTile(
                      context: context,
                      title: 'settings.dark'.tr(),
                      icon: LucideIcons.moon,
                      mode: ThemeMode.dark,
                      currentMode: currentMode,
                      onTap: () {
                        context.read<ThemeBloc>().add(const ThemeChanged(ThemeMode.dark));
                      },
                    ),
                    _buildThemeTile(
                      context: context,
                      title: 'settings.system'.tr(),
                      icon: LucideIcons.monitor,
                      mode: ThemeMode.system,
                      currentMode: currentMode,
                      onTap: () {
                        context.read<ThemeBloc>().add(const ThemeChanged(ThemeMode.system));
                      },
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          _buildSectionCard(
            context: context,
            title: 'settings.language'.tr(),
            icon: LucideIcons.languages,
            child: BlocBuilder<LocalizationBloc, LocalizationState>(
              builder: (context, state) {
                final currentLocale = state.locale;

                return Column(
                  children: [
                    _buildLanguageTile(
                      context: context,
                      title: 'common.english'.tr(),
                      locale: const Locale('en'),
                      currentLocale: currentLocale,
                      onTap: () {
                        context.read<LocalizationBloc>().add(const LocaleChanged(Locale('en')));
                        context.setLocale(const Locale('en'));
                      },
                    ),
                    _buildLanguageTile(
                      context: context,
                      title: 'common.arabic'.tr(),
                      locale: const Locale('ar'),
                      currentLocale: currentLocale,
                      onTap: () {
                        context.read<LocalizationBloc>().add(const LocaleChanged(Locale('ar')));
                        context.setLocale(const Locale('ar'));
                      },
                    ),
                    _buildLanguageTile(
                      context: context,
                      title: 'common.french'.tr(),
                      locale: const Locale('fr'),
                      currentLocale: currentLocale,
                      onTap: () {
                        context.read<LocalizationBloc>().add(const LocaleChanged(Locale('fr')));
                        context.setLocale(const Locale('fr'));
                      },
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          _buildSectionCard(
            context: context,
            title: 'settings.company.section_title'.tr(),
            icon: LucideIcons.building2,
            child: Column(
              children: [
                ListTile(
                  leading: Icon(
                    LucideIcons.badgeInfo,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  title: Text('settings.company.title'.tr()),
                  subtitle: Text('settings.company.subtitle'.tr()),
                  trailing: const Icon(LucideIcons.chevronRight),
                  onTap: () => context.push('/settings/company'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildSectionCard(
            context: context,
            title: 'settings.currency'.tr(),
            icon: LucideIcons.dollarSign,
            child: BlocBuilder<CurrencyBloc, RealtimeState<Currency>>(
              builder: (context, state) {
                final currentCurrency = state is RealtimeSuccess<Currency>
                    ? state.data
                    : Currency.supportedCurrencies.first;

                final previewAmount = 123456;
                final formattedPreview = context.read<CurrencyService>().format(previewAmount);

                return Column(
                  children: [
                    Theme(
                      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            currentCurrency.symbol,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        title: Text(
                          'currency.${currentCurrency.code}'.tr(),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(currentCurrency.code),
                        children: Currency.supportedCurrencies.map((currency) {
                          return _buildCurrencyTile(
                            context: context,
                            title: 'currency.${currency.code}'.tr(),
                            code: currency.code,
                            symbol: currency.symbol,
                            currentCode: currentCurrency.code,
                            onTap: () {
                              context.read<CurrencyBloc>().add(CurrencyChanged(currency.code));
                            },
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          Icon(
                            LucideIcons.info,
                            size: 16,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'settings.currency_preview'.tr(args: [formattedPreview]),
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),

          // ── Subscription ──
          const SizedBox(height: 16),
          const SubscriptionSettingsCard(),

          // ── Business Settings (expandable sections) ──
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              'app_settings.section_business'.tr(),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const TaxSettingsSection(),
          const SizedBox(height: 8),
          const SalesSettingsSection(),
          const SizedBox(height: 8),
          const InventorySettingsSection(),

          // ── POS & Printing ──
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              'app_settings.section_pos'.tr(),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const ReceiptSettingsSection(),
          const SizedBox(height: 8),
          const BarcodeLabelSettingsSection(),
          const SizedBox(height: 8),
          const PrinterSettingsSection(),

          // ── System ──
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              'app_settings.section_system'.tr(),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SecuritySettingsSection(),
          const SizedBox(height: 8),
          const ReportsSettingsSection(),
          const SizedBox(height: 8),
          const NotificationSettingsSection(),
          const SizedBox(height: 8),
          _buildSectionCard(
            context: context,
            title: 'settings.backup.section_title'.tr(),
            icon: LucideIcons.hardDrive,
            child: Column(
              children: [
                ListTile(
                  leading: Icon(
                    LucideIcons.databaseBackup,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  title: Text('settings.backup.title'.tr()),
                  subtitle: Text('settings.backup.subtitle'.tr()),
                  trailing: const Icon(LucideIcons.chevronRight),
                  onTap: () => context.push('/settings/backup'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSectionCard({
    required BuildContext context,
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildThemeTile({
    required BuildContext context,
    required String title,
    required IconData icon,
    required ThemeMode mode,
    required ThemeMode currentMode,
    required VoidCallback onTap,
  }) {
    final isSelected = mode == currentMode;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ListTile(
      leading: Icon(
        icon,
        color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
      ),
      title: Text(title),
      trailing: isSelected
          ? Icon(LucideIcons.check, color: colorScheme.primary)
          : null,
      selected: isSelected,
      onTap: onTap,
    );
  }

  Widget _buildLanguageTile({
    required BuildContext context,
    required String title,
    required Locale locale,
    required Locale currentLocale,
    required VoidCallback onTap,
  }) {
    final isSelected = locale.languageCode == currentLocale.languageCode;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ListTile(
      title: Text(title),
      trailing: isSelected
          ? Icon(LucideIcons.check, color: colorScheme.primary)
          : null,
      selected: isSelected,
      onTap: onTap,
    );
  }

  Widget _buildCurrencyTile({
    required BuildContext context,
    required String title,
    required String code,
    required String symbol,
    required String currentCode,
    required VoidCallback onTap,
  }) {
    final isSelected = code == currentCode;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ListTile(
      leading: Text(
        symbol,
        style: theme.textTheme.titleLarge?.copyWith(
          color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
        ),
      ),
      title: Text(title),
      subtitle: Text(code),
      trailing: isSelected
          ? Icon(LucideIcons.check, color: colorScheme.primary)
          : null,
      selected: isSelected,
      onTap: onTap,
    );
  }
}

class _AdminPasswordDialog extends StatefulWidget {
  const _AdminPasswordDialog();

  @override
  State<_AdminPasswordDialog> createState() => _AdminPasswordDialogState();
}

class _AdminPasswordDialogState extends State<_AdminPasswordDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('admin'.tr()),
      content: TextField(
        controller: _controller,
        obscureText: true,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text('common.cancel'.tr()),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop(_controller.text.trim() == '123456');
          },
          child: Text('common.confirm'.tr()),
        ),
      ],
    );
  }
}
