import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../../../core/di/injection_container.dart';
import '../../../../core/services/app_guard_service.dart';
import '../../../../core/services/revenuecat_service.dart';
import '../bloc/subscription_bloc.dart';
import 'custom_paywall_screen.dart';

/// Settings card showing subscription status with Manage/Upgrade button.
class SubscriptionSettingsCard extends StatelessWidget {
  const SubscriptionSettingsCard({super.key});

  void _showNoInternetDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('subscription.requires_internet_title'.tr()),
        content: Text('subscription.requires_internet'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('subscription.ok'.tr()),
          ),
        ],
      ),
    );
  }

  void _handleUpgrade(BuildContext context) {
    if (!RevenueCatConfig.isSupported ||
        !RevenueCatService.instance.isInitialized) {
      _showNoInternetDialog(context);
      return;
    }
    CustomPaywallScreen.show(context);
  }

  void _handleManage(BuildContext context) {
    if (!RevenueCatConfig.isSupported ||
        !RevenueCatService.instance.isInitialized) {
      _showNoInternetDialog(context);
      return;
    }
    sl<SubscriptionBloc>().add(const SubscriptionPresentCustomerCenter());
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SubscriptionBloc, SubscriptionState>(
      bloc: sl<SubscriptionBloc>(),
      builder: (context, state) {
        final isPro = state is SubscriptionLoaded && state.isPro;
        final isLifetime = state is SubscriptionLoaded && state.isLifetime;
        final expirationDate =
            state is SubscriptionLoaded ? state.status.expirationDate : null;

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      isPro ? Icons.star : Icons.star_border,
                      color: isPro ? Colors.amber : null,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isPro
                          ? 'subscription.tapix_pro'.tr()
                          : 'subscription.free_plan'.tr(),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    if (isPro) ...[
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'subscription.active'.tr(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (isPro && !isLifetime && expirationDate != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'subscription.renews_on'.tr(namedArgs: {
                      'date':
                          '${expirationDate.day}/${expirationDate.month}/${expirationDate.year}',
                    }),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                if (isPro && isLifetime) ...[
                  const SizedBox(height: 8),
                  Text(
                    'subscription.lifetime_access'.tr(),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.green,
                        ),
                  ),
                ],
                const SizedBox(height: 16),
                if (!isPro)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _handleUpgrade(context),
                      icon: const Icon(Icons.upgrade),
                      label: Text('subscription.upgrade_to_pro'.tr()),
                    ),
                  )
                else
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _handleManage(context),
                      icon: const Icon(Icons.settings),
                      label: Text('subscription.manage_subscription'.tr()),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Gate widget that shows [child] only if user has Pro.
class ProFeatureGate extends StatelessWidget {
  final Widget child;
  final Widget? lockedChild;
  final String? featureName;

  const ProFeatureGate({
    super.key,
    required this.child,
    this.lockedChild,
    this.featureName,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SubscriptionBloc, SubscriptionState>(
      bloc: sl<SubscriptionBloc>(),
      builder: (context, state) {
        final isPro = state is SubscriptionLoaded && state.isPro;

        if (isPro) return child;

        return lockedChild ??
            _DefaultLockedWidget(
              featureName: featureName,
              onUpgrade: () {
                CustomPaywallScreen.show(context);
              },
            );
      },
    );
  }
}

class _DefaultLockedWidget extends StatelessWidget {
  final String? featureName;
  final VoidCallback onUpgrade;

  const _DefaultLockedWidget({
    this.featureName,
    required this.onUpgrade,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, size: 48, color: Colors.amber),
            const SizedBox(height: 16),
            Text(
              featureName != null
                  ? '$featureName is a Pro feature'
                  : 'This is a Pro feature',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Upgrade to TapBix Pro to unlock this feature',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onUpgrade,
              icon: const Icon(Icons.star),
              label: const Text('Upgrade to Pro'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Full-screen lock screen shown when the app is locked.
class AppLockScreen extends StatelessWidget {
  const AppLockScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SubscriptionBloc, SubscriptionState>(
      bloc: sl<SubscriptionBloc>(),
      builder: (context, state) {
        if (state is! SubscriptionLocked) {
          return const SizedBox.shrink();
        }

        final reason = state.lockReason;
        final needsInternet = state.requiresInternet;
        final icon = _iconForReason(reason);
        final title = _titleForReason(reason);
        final description = _descriptionForReason(reason);

        return Scaffold(
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 80, color: Colors.red.shade400),
                    const SizedBox(height: 24),
                    Text(
                      title,
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      description,
                      style: Theme.of(context).textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                    if (needsInternet) ...[
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.wifi_off,
                              size: 16, color: Colors.orange.shade700),
                          const SizedBox(width: 6),
                          Text(
                            'Internet connection required',
                            style: TextStyle(color: Colors.orange.shade700),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 32),
                    // Show paywall button for subscription-related locks
                    if (_isSubscriptionLock(reason)) ...[
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            CustomPaywallScreen.show(context);
                          },
                          icon: const Icon(Icons.star),
                          label: const Text('Subscribe to TapBix Pro'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: () {
                            sl<SubscriptionBloc>()
                                .add(const SubscriptionRestore());
                          },
                          child: const Text('Restore Purchases'),
                        ),
                      ),
                    ],
                    // Show retry button for connectivity-related locks
                    if (needsInternet && !_isSubscriptionLock(reason)) ...[
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            sl<SubscriptionBloc>()
                                .add(const SubscriptionRefresh());
                          },
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  bool _isSubscriptionLock(AppLockReason reason) {
    return reason == AppLockReason.noSubscription ||
        reason == AppLockReason.licenseExpired;
  }

  IconData _iconForReason(AppLockReason reason) {
    switch (reason) {
      case AppLockReason.noSubscription:
        return Icons.lock_outline;
      case AppLockReason.licenseExpired:
        return Icons.timer_off_outlined;
      case AppLockReason.deviceMismatch:
        return Icons.devices_other;
      case AppLockReason.offlineTooLong:
        return Icons.wifi_off;
      case AppLockReason.licenseTampered:
        return Icons.gpp_bad;
      case AppLockReason.deviceBlocked:
        return Icons.block;
      case AppLockReason.versionUnsupported:
      case AppLockReason.versionKilled:
      case AppLockReason.forceUpdate:
        return Icons.system_update;
      case AppLockReason.codeTampered:
        return Icons.security;
      case AppLockReason.none:
        return Icons.check_circle;
    }
  }

  String _titleForReason(AppLockReason reason) {
    switch (reason) {
      case AppLockReason.noSubscription:
        return 'Subscription Required';
      case AppLockReason.licenseExpired:
        return 'Subscription Expired';
      case AppLockReason.deviceMismatch:
        return 'Device Not Authorized';
      case AppLockReason.offlineTooLong:
        return 'Verification Required';
      case AppLockReason.licenseTampered:
        return 'License Invalid';
      case AppLockReason.deviceBlocked:
        return 'Device Blocked';
      case AppLockReason.versionUnsupported:
        return 'Update Required';
      case AppLockReason.versionKilled:
        return 'Version Disabled';
      case AppLockReason.forceUpdate:
        return 'Update Required';
      case AppLockReason.codeTampered:
        return 'Security Alert';
      case AppLockReason.none:
        return '';
    }
  }

  String _descriptionForReason(AppLockReason reason) {
    switch (reason) {
      case AppLockReason.noSubscription:
        return 'Subscribe to TapBix Pro to use this application.';
      case AppLockReason.licenseExpired:
        return 'Your subscription has expired. Please renew to continue.';
      case AppLockReason.deviceMismatch:
        return 'This license is not valid for this device. Please contact support.';
      case AppLockReason.offlineTooLong:
        return 'You have been offline too long. Please connect to the internet to verify your subscription.';
      case AppLockReason.licenseTampered:
        return 'Your license data appears to be corrupted. Please connect to the internet to re-validate.';
      case AppLockReason.deviceBlocked:
        return 'This device has been blocked. Please contact support.';
      case AppLockReason.versionUnsupported:
        return 'This version of TapBix is no longer supported. Please update to the latest version.';
      case AppLockReason.versionKilled:
        return 'This version of TapBix has been disabled. Please update to the latest version.';
      case AppLockReason.forceUpdate:
        return 'A critical update is available. Please update to continue.';
      case AppLockReason.codeTampered:
        return 'The application integrity check failed. Please reinstall from the official store.';
      case AppLockReason.none:
        return '';
    }
  }
}

/// Convenience extension on BuildContext for subscription actions.
extension SubscriptionBlocExtension on BuildContext {
  bool get isPro {
    final state = sl<SubscriptionBloc>().state;
    return state is SubscriptionLoaded && state.isPro;
  }

  void showPaywall() {
    CustomPaywallScreen.show(this);
  }

  void showPaywallIfNotPro() {
    if (!isPro) {
      CustomPaywallScreen.show(this);
    }
  }

  void showCustomerCenter() {
    sl<SubscriptionBloc>().add(const SubscriptionPresentCustomerCenter());
  }
}
