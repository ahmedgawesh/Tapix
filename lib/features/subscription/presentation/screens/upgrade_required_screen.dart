import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection_container.dart';
import '../../../../core/services/feature_gate_service.dart';
import '../../../../core/services/revenuecat_service.dart';
import 'custom_paywall_screen.dart';

/// Full-screen page shown when a free-tier user tries to open a Pro-only
/// section. The router redirects locked paths here (see `ProRoutePolicy`).
///
/// It does NOT replace the modal paywall — it triggers it. When the user
/// completes a purchase, [FeatureGateService] flips to Pro and the screen
/// forwards them to the originally requested destination.
class UpgradeRequiredScreen extends StatelessWidget {
  /// The path the user originally tried to reach (for post-upgrade forwarding).
  final String? from;

  const UpgradeRequiredScreen({super.key, this.from});

  Future<void> _handleUpgrade(BuildContext context) async {
    if (!RevenueCatConfig.isSupported ||
        !RevenueCatService.instance.isInitialized) {
      _showNoInternetDialog(context);
      return;
    }

    await CustomPaywallScreen.show(context);
    if (!context.mounted) return;

    // After the paywall closes, if the user is now Pro, forward them on.
    await sl<FeatureGateService>().refresh();
    if (!context.mounted) return;

    if (sl<FeatureGateService>().isPro) {
      context.go(from ?? '/dashboard');
    }
  }

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'subscription.back_to_home'.tr(),
          onPressed: () => context.go('/dashboard'),
        ),
        title: Text('subscription.feature_locked_title'.tr()),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.workspace_premium,
                      size: 52, color: Colors.amber),
                ),
                const SizedBox(height: 24),
                Text(
                  'subscription.feature_locked_title'.tr(),
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'subscription.feature_locked_message'.tr(),
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'subscription.feature_locked_free_hint'.tr(),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.hintColor),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _handleUpgrade(context),
                    icon: const Icon(Icons.star),
                    label: Text('subscription.upgrade_to_pro'.tr()),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => context.go('/dashboard'),
                    child: Text('subscription.back_to_home'.tr()),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
