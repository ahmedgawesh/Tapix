part of 'subscription_bloc.dart';

abstract class SubscriptionState extends Equatable {
  const SubscriptionState();

  @override
  List<Object?> get props => [];
}

class SubscriptionInitial extends SubscriptionState {
  const SubscriptionInitial();
}

class SubscriptionLoading extends SubscriptionState {
  const SubscriptionLoading();
}

class SubscriptionLoaded extends SubscriptionState {
  final SubscriptionStatus status;
  final Offerings? offerings;
  final bool isPurchasing;
  final bool isRestoring;
  final bool purchaseSuccess;
  final bool restoreSuccess;
  final String? purchaseError;
  final String? restoreError;

  const SubscriptionLoaded({
    this.status = const SubscriptionStatus(),
    this.offerings,
    this.isPurchasing = false,
    this.isRestoring = false,
    this.purchaseSuccess = false,
    this.restoreSuccess = false,
    this.purchaseError,
    this.restoreError,
  });

  bool get isPro => status.isPro;
  bool get isActive => status.isActive;
  bool get isLifetime => status.isLifetime;

  Offering? get currentOffering => offerings?.current;

  List<Package> get availablePackages =>
      currentOffering?.availablePackages ?? [];

  Package? get weeklyPackage => _findPackageByType(PackageType.weekly);
  Package? get monthlyPackage => _findPackageByType(PackageType.monthly);
  Package? get annualPackage => _findPackageByType(PackageType.annual);
  Package? get lifetimePackage => _findPackageByType(PackageType.lifetime);

  Package? _findPackageByType(PackageType type) {
    try {
      return availablePackages.firstWhere((p) => p.packageType == type);
    } catch (_) {
      return null;
    }
  }

  SubscriptionLoaded copyWith({
    SubscriptionStatus? status,
    Offerings? offerings,
    bool? isPurchasing,
    bool? isRestoring,
    bool? purchaseSuccess,
    bool? restoreSuccess,
    String? purchaseError,
    String? restoreError,
  }) {
    return SubscriptionLoaded(
      status: status ?? this.status,
      offerings: offerings ?? this.offerings,
      isPurchasing: isPurchasing ?? this.isPurchasing,
      isRestoring: isRestoring ?? this.isRestoring,
      purchaseSuccess: purchaseSuccess ?? false,
      restoreSuccess: restoreSuccess ?? false,
      purchaseError: purchaseError,
      restoreError: restoreError,
    );
  }

  @override
  List<Object?> get props => [
        status,
        offerings,
        isPurchasing,
        isRestoring,
        purchaseSuccess,
        restoreSuccess,
        purchaseError,
        restoreError,
      ];
}

class SubscriptionError extends SubscriptionState {
  final String message;

  const SubscriptionError(this.message);

  @override
  List<Object?> get props => [message];
}
