part of 'subscription_bloc.dart';

abstract class SubscriptionEvent extends Equatable {
  const SubscriptionEvent();

  @override
  List<Object?> get props => [];
}

class SubscriptionInitialize extends SubscriptionEvent {
  final String? appUserId;

  const SubscriptionInitialize({this.appUserId});

  @override
  List<Object?> get props => [appUserId];
}

class SubscriptionStatusChanged extends SubscriptionEvent {
  final SubscriptionStatus status;

  const SubscriptionStatusChanged(this.status);

  @override
  List<Object?> get props => [status];
}

class SubscriptionRefresh extends SubscriptionEvent {
  const SubscriptionRefresh();
}

class SubscriptionPurchasePackage extends SubscriptionEvent {
  final Package package;

  const SubscriptionPurchasePackage(this.package);

  @override
  List<Object?> get props => [package];
}

class SubscriptionPurchaseProduct extends SubscriptionEvent {
  final String productId;

  const SubscriptionPurchaseProduct(this.productId);

  @override
  List<Object?> get props => [productId];
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
