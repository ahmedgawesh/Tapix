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

/// App is unlocked – user has an active subscription or valid local license.
class SubscriptionLoaded extends SubscriptionState {
  final SubscriptionStatus status;
  final AppGuardStatus? guardStatus;
  final bool isPurchasing;
  final bool isRestoring;
  final bool purchaseSuccess;
  final bool restoreSuccess;
  final String? purchaseError;
  final String? restoreError;

  const SubscriptionLoaded({
    this.status = const SubscriptionStatus(),
    this.guardStatus,
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

  SubscriptionLoaded copyWith({
    SubscriptionStatus? status,
    AppGuardStatus? guardStatus,
    bool? isPurchasing,
    bool? isRestoring,
    bool? purchaseSuccess,
    bool? restoreSuccess,
    String? purchaseError,
    String? restoreError,
  }) {
    return SubscriptionLoaded(
      status: status ?? this.status,
      guardStatus: guardStatus ?? this.guardStatus,
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
        guardStatus,
        isPurchasing,
        isRestoring,
        purchaseSuccess,
        restoreSuccess,
        purchaseError,
        restoreError,
      ];
}

/// App is locked – subscription invalid, license expired, offline too long, etc.
class SubscriptionLocked extends SubscriptionState {
  final AppLockReason lockReason;
  final bool requiresInternet;
  final SubscriptionStatus status;

  const SubscriptionLocked({
    required this.lockReason,
    this.requiresInternet = false,
    this.status = const SubscriptionStatus(),
  });

  @override
  List<Object?> get props => [lockReason, requiresInternet, status];
}

class SubscriptionError extends SubscriptionState {
  final String message;

  const SubscriptionError(this.message);

  @override
  List<Object?> get props => [message];
}
