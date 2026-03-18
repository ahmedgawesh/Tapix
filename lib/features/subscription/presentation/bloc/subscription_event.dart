part of 'subscription_bloc.dart';

abstract class SubscriptionEvent extends Equatable {
  const SubscriptionEvent();

  @override
  List<Object?> get props => [];
}

/// Start the full guard sequence (RevenueCat init + AppGuard).
class SubscriptionStartGuard extends SubscriptionEvent {
  final String? appUserId;

  const SubscriptionStartGuard({this.appUserId});

  @override
  List<Object?> get props => [appUserId];
}

/// Internal: guard status changed via stream.
class SubscriptionGuardStatusChanged extends SubscriptionEvent {
  final AppGuardStatus guardStatus;

  const SubscriptionGuardStatusChanged(this.guardStatus);

  @override
  List<Object?> get props => [guardStatus];
}

class SubscriptionRefresh extends SubscriptionEvent {
  const SubscriptionRefresh();
}

class SubscriptionRestore extends SubscriptionEvent {
  const SubscriptionRestore();
}

class SubscriptionPresentPaywall extends SubscriptionEvent {
  final Offering? offering;

  const SubscriptionPresentPaywall({this.offering});

  @override
  List<Object?> get props => [offering];
}

class SubscriptionPresentPaywallIfNeeded extends SubscriptionEvent {
  const SubscriptionPresentPaywallIfNeeded();
}

class SubscriptionPresentCustomerCenter extends SubscriptionEvent {
  const SubscriptionPresentCustomerCenter();
}

class SubscriptionLogIn extends SubscriptionEvent {
  final String appUserId;

  const SubscriptionLogIn(this.appUserId);

  @override
  List<Object?> get props => [appUserId];
}

class SubscriptionLogOut extends SubscriptionEvent {
  const SubscriptionLogOut();
}
