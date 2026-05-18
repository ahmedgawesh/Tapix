import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/di/injection_container.dart';
import '../../../../core/services/revenuecat_service.dart';
import '../bloc/subscription_bloc.dart';

/// Custom paywall screen — fully translated, integrated with RevenueCat.
class CustomPaywallScreen extends StatefulWidget {
  const CustomPaywallScreen({super.key});

  /// Show the paywall as a modal bottom sheet or full-screen route.
  static Future<void> show(BuildContext context) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const CustomPaywallScreen()),
    );
  }

  @override
  State<CustomPaywallScreen> createState() => _CustomPaywallScreenState();
}

class _CustomPaywallScreenState extends State<CustomPaywallScreen> {
  Offerings? _offerings;
  bool _isLoading = true;
  bool _isPurchasing = false;
  bool _isRestoring = false;
  String? _error;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadOfferings();
  }

  Future<void> _loadOfferings() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final offerings = await RevenueCatService.instance.getOfferings();
      if (!mounted) return;
      setState(() {
        _offerings = offerings;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'paywall.error_network'.tr();
        _isLoading = false;
      });
    }
  }

  List<Package> get _availablePackages {
    final offering = _offerings?.current;
    if (offering == null) return [];

    // Collect all packages — both from availablePackages and named accessors
    // This ensures lifetime (non-subscription) packages are included
    final Map<String, Package> packageMap = {};

    debugPrint('=== CHATGPT DEBUG TEST ===');
    for (final p in offering.availablePackages) {
      debugPrint('PACKAGE: ${p.identifier} - ${p.storeProduct.identifier}');
    }
    debugPrint('==========================');

    // First add all available packages
    for (final pkg in offering.availablePackages) {
      packageMap[pkg.storeProduct.identifier] = pkg;
    }

    // Then add named packages (these may include packages not in availablePackages)
    final namedPackages = [
      offering.weekly,
      offering.monthly,
      offering.annual,
      offering.lifetime,
    ];
    for (final pkg in namedPackages) {
      if (pkg != null) {
        packageMap[pkg.storeProduct.identifier] = pkg;
      }
    }

    debugPrint('Paywall: Found ${packageMap.length} packages: '
        '${packageMap.keys.join(', ')}');

    return packageMap.values.toList();
  }

  String _packageTitle(Package package) {
    final id = package.storeProduct.identifier;
    if (id.contains('lifetime')) return 'paywall.lifetime'.tr();
    if (id.contains('yearly') || id.contains('year')) return 'paywall.yearly'.tr();
    if (id.contains('monthly') || id.contains('month')) return 'paywall.monthly'.tr();
    if (id.contains('weekly') || id.contains('week')) return 'paywall.weekly'.tr();
    // Fallback to store title
    return package.storeProduct.title;
  }

  String _packagePeriod(Package package) {
    final id = package.storeProduct.identifier;
    if (id.contains('lifetime')) return 'paywall.one_time'.tr();
    if (id.contains('yearly') || id.contains('year')) return 'paywall.per_year'.tr();
    if (id.contains('monthly') || id.contains('month')) return 'paywall.per_month'.tr();
    if (id.contains('weekly') || id.contains('week')) return 'paywall.per_week'.tr();
    return '';
  }

  String? _packageBadge(Package package) {
    final id = package.storeProduct.identifier;
    if (id.contains('yearly') || id.contains('year')) return 'paywall.best_value'.tr();
    if (id.contains('monthly') || id.contains('month')) return 'paywall.most_popular'.tr();
    return null;
  }

  int _packageSortOrder(Package package) {
    final id = package.storeProduct.identifier;
    if (id.contains('weekly') || id.contains('week')) return 0;
    if (id.contains('monthly') || id.contains('month')) return 1;
    if (id.contains('yearly') || id.contains('year')) return 2;
    if (id.contains('lifetime')) return 3;
    return 4;
  }

  Future<void> _purchase(Package package) async {
    setState(() {
      _isPurchasing = true;
      _error = null;
    });

    try {
      final result = await RevenueCatService.instance.purchasePackage(package);
      if (!mounted) return;

      if (result.success) {
        // Refresh subscription state
        sl<SubscriptionBloc>().add(const SubscriptionRefresh());
        if (!mounted) return;
        _showSuccessAndPop('paywall.purchase_success'.tr());
      } else if (result.userCancelled) {
        setState(() => _isPurchasing = false);
      } else {
        setState(() {
          _isPurchasing = false;
          _error = result.errorMessage ?? 'paywall.error_purchase'.tr();
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isPurchasing = false;
        _error = 'paywall.error_purchase'.tr();
      });
    }
  }

  Future<void> _restore() async {
    setState(() {
      _isRestoring = true;
      _error = null;
    });

    try {
      final result = await RevenueCatService.instance.restorePurchases();
      if (!mounted) return;

      if (result.success) {
        final status = SubscriptionStatus.fromCustomerInfo(result.customerInfo);
        sl<SubscriptionBloc>().add(const SubscriptionRefresh());
        if (!mounted) return;

        if (status.isPro) {
          _showSuccessAndPop('paywall.restore_success'.tr());
        } else {
          setState(() {
            _isRestoring = false;
            _error = 'paywall.restore_empty'.tr();
          });
        }
      } else {
        setState(() {
          _isRestoring = false;
          _error = result.errorMessage ?? 'paywall.error_purchase'.tr();
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isRestoring = false;
        _error = 'paywall.error_network'.tr();
      });
    }
  }

  void _showSuccessAndPop(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('paywall.title'.tr()),
        centerTitle: true,
        elevation: 0,
      ),
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text('paywall.loading'.tr()),
                ],
              ),
            )
          : _buildContent(theme, colorScheme),
    );
  }

  Widget _buildContent(ThemeData theme, ColorScheme colorScheme) {
    final packages = _availablePackages;
    packages.sort((a, b) => _packageSortOrder(a).compareTo(_packageSortOrder(b)));

    if (packages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.cloud_off, size: 64, color: colorScheme.onSurfaceVariant),
              const SizedBox(height: 16),
              Text(
                'paywall.no_plans'.tr(),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _loadOfferings,
                icon: const Icon(Icons.refresh),
                label: Text('paywall.restore'.tr()),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // ── Header ──
                const SizedBox(height: 8),
                Icon(Icons.star_rounded, size: 56, color: Colors.amber.shade600),
                const SizedBox(height: 12),
                Text(
                  'paywall.subtitle'.tr(),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),

                // ── Features ──
                _buildFeaturesList(theme, colorScheme),
                const SizedBox(height: 24),

                // ── Plan cards ──
                ...List.generate(packages.length, (index) {
                  return _buildPlanCard(
                    theme,
                    colorScheme,
                    packages[index],
                    isSelected: index == _selectedIndex,
                    onTap: () => setState(() => _selectedIndex = index),
                  );
                }),

                // ── Error ──
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline, color: colorScheme.error, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _error!,
                            style: TextStyle(color: colorScheme.onErrorContainer),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),

        // ── Bottom actions ──
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Subscribe button
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    onPressed: (_isPurchasing || _isRestoring || packages.isEmpty)
                        ? null
                        : () => _purchase(packages[_selectedIndex]),
                    child: _isPurchasing
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text('paywall.purchasing'.tr()),
                            ],
                          )
                        : Text(
                            _isLifetimePlan(packages[_selectedIndex])
                                ? 'paywall.purchase'.tr()
                                : 'paywall.subscribe'.tr(),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 8),
                // Restore button
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: (_isPurchasing || _isRestoring)
                        ? null
                        : _restore,
                    child: _isRestoring
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                              const SizedBox(width: 8),
                              Text('paywall.restoring'.tr()),
                            ],
                          )
                        : Text('paywall.restore'.tr()),
                  ),
                ),
                const SizedBox(height: 16),
                // Auto-renewal and Legal Boilerplate (Required for App Store / Play Store)
                Text(
                  'paywall.subscription_terms'.tr(),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 10,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    InkWell(
                      onTap: () => _launchURL('https://tapixsolutions.com/terms-of-service.html'),
                      child: Text(
                        'paywall.terms_of_service'.tr(),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.primary,
                          decoration: TextDecoration.underline,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      '•',
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(width: 16),
                    InkWell(
                      onTap: () => _launchURL('https://tapixsolutions.com/privacy-policy.html'),
                      child: Text(
                        'paywall.privacy_policy'.tr(),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.primary,
                          decoration: TextDecoration.underline,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _launchURL(String urlString) async {
    final Uri url = Uri.parse(urlString);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      debugPrint('Could not launch $url');
    }
  }

  bool _isLifetimePlan(Package package) {
    return package.storeProduct.identifier.contains('lifetime');
  }

  Widget _buildFeaturesList(ThemeData theme, ColorScheme colorScheme) {
    final features = [
      'paywall.feature_1'.tr(),
      'paywall.feature_2'.tr(),
      'paywall.feature_3'.tr(),
      'paywall.feature_4'.tr(),
      'paywall.feature_5'.tr(),
      'paywall.feature_6'.tr(),
    ];

    return Column(
      children: features.map((feature) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green.shade600, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  feature,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildPlanCard(
    ThemeData theme,
    ColorScheme colorScheme,
    Package package, {
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final badge = _packageBadge(package);
    final price = package.storeProduct.priceString;
    final title = _packageTitle(package);
    final period = _packagePeriod(package);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? colorScheme.primary : colorScheme.outlineVariant,
              width: isSelected ? 2 : 1,
            ),
            color: isSelected
                ? colorScheme.primaryContainer.withAlpha(50)
                : colorScheme.surface,
          ),
          child: Row(
            children: [
              // Radio indicator
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? colorScheme.primary : colorScheme.outline,
                    width: 2,
                  ),
                  color: isSelected ? colorScheme.primary : Colors.transparent,
                ),
                child: isSelected
                    ? const Icon(Icons.check, size: 16, color: Colors.white)
                    : null,
              ),
              const SizedBox(width: 14),
              // Title & period
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: isSelected ? colorScheme.primary : null,
                          ),
                        ),
                        if (badge != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.primary,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              badge,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (period.isNotEmpty)
                      Text(
                        period,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              // Price
              Text(
                price,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isSelected ? colorScheme.primary : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
