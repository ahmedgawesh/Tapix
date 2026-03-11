import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';

import '../../../../core/di/injection_container.dart';
import '../bloc/subscription_bloc.dart';

class PaywallScreen extends StatelessWidget {
  const PaywallScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: sl<SubscriptionBloc>(),
      child: const _PaywallScreenContent(),
    );
  }
}

class _PaywallScreenContent extends StatelessWidget {
  const _PaywallScreenContent();

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<SubscriptionBloc, SubscriptionState>(
      listener: (context, state) {
        if (state is SubscriptionLoaded) {
          if (state.purchaseSuccess) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Purchase successful! Welcome to Tapix Pro.'),
                backgroundColor: Colors.green,
              ),
            );
            Navigator.of(context).pop(true);
          } else if (state.restoreSuccess) {
            if (state.isPro) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Purchases restored successfully!'),
                  backgroundColor: Colors.green,
                ),
              );
              Navigator.of(context).pop(true);
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('No previous purchases found.'),
                ),
              );
            }
          } else if (state.purchaseError != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.purchaseError!),
                backgroundColor: Colors.red,
              ),
            );
          } else if (state.restoreError != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.restoreError!),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      },
      builder: (context, state) {
        if (state is SubscriptionLoading) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (state is SubscriptionError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Subscription')),
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(state.message),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      context.read<SubscriptionBloc>().add(
                            const SubscriptionRefresh(),
                          );
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          );
        }

        if (state is SubscriptionLoaded) {
          final offering = state.currentOffering;

          if (offering == null) {
            return Scaffold(
              appBar: AppBar(title: const Text('Subscription')),
              body: const Center(
                child: Text('No subscription plans available'),
              ),
            );
          }

          return Scaffold(
            body: SafeArea(
              child: PaywallView(
                offering: offering,
                onRestoreCompleted: (CustomerInfo customerInfo) {
                  context.read<SubscriptionBloc>().add(
                        const SubscriptionRefresh(),
                      );
                },
                onDismiss: () {
                  Navigator.of(context).pop();
                },
              ),
            ),
          );
        }

        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      },
    );
  }
}

class SubscriptionSettingsCard extends StatelessWidget {
  const SubscriptionSettingsCard({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SubscriptionBloc, SubscriptionState>(
      bloc: sl<SubscriptionBloc>(),
      builder: (context, state) {
        if (state is! SubscriptionLoaded) {
          return const SizedBox.shrink();
        }

        final isPro = state.isPro;
        final isLifetime = state.isLifetime;
        final expirationDate = state.status.expirationDate;

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
                      isPro ? 'Tapix Pro' : 'Free Plan',
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
                        child: const Text(
                          'ACTIVE',
                          style: TextStyle(
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
                    'Renews on ${_formatDate(expirationDate)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                if (isPro && isLifetime) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Lifetime access',
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
                      onPressed: () => _showPaywall(context),
                      icon: const Icon(Icons.upgrade),
                      label: const Text('Upgrade to Pro'),
                    ),
                  )
                else
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _showCustomerCenter(context),
                      icon: const Icon(Icons.settings),
                      label: const Text('Manage Subscription'),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  void _showPaywall(BuildContext context) {
    sl<SubscriptionBloc>().add(const SubscriptionPresentPaywall());
  }

  void _showCustomerCenter(BuildContext context) {
    sl<SubscriptionBloc>().add(const SubscriptionPresentCustomerCenter());
  }
}

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

        if (isPro) {
          return child;
        }

        return lockedChild ??
            _DefaultLockedWidget(
              featureName: featureName,
              onUpgrade: () => _showPaywall(context),
            );
      },
    );
  }

  void _showPaywall(BuildContext context) {
    sl<SubscriptionBloc>().add(const SubscriptionPresentPaywall());
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
            const Icon(
              Icons.lock_outline,
              size: 48,
              color: Colors.amber,
            ),
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
              'Upgrade to Tapix Pro to unlock this feature',
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

extension SubscriptionBlocExtension on BuildContext {
  bool get isPro {
    final state = sl<SubscriptionBloc>().state;
    return state is SubscriptionLoaded && state.isPro;
  }

  void showPaywallIfNotPro() {
    if (!isPro) {
      sl<SubscriptionBloc>().add(const SubscriptionPresentPaywallIfNeeded());
    }
  }

  void showPaywall() {
    sl<SubscriptionBloc>().add(const SubscriptionPresentPaywall());
  }

  void showCustomerCenter() {
    sl<SubscriptionBloc>().add(const SubscriptionPresentCustomerCenter());
  }
}
