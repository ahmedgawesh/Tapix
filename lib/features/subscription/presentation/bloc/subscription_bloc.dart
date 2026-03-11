import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../../../../core/services/revenuecat_service.dart';

part 'subscription_event.dart';
part 'subscription_state.dart';

class SubscriptionBloc extends Bloc<SubscriptionEvent, SubscriptionState> {
  final RevenueCatService _revenueCatService;
  StreamSubscription<SubscriptionStatus>? _statusSubscription;

  SubscriptionBloc({
    RevenueCatService? revenueCatService,
  })  : _revenueCatService = revenueCatService ?? RevenueCatService.instance,
        super(const SubscriptionInitial()) {
    on<SubscriptionInitialize>(_onInitialize);
    on<SubscriptionStatusChanged>(_onStatusChanged);
    on<SubscriptionRefresh>(_onRefresh);
    on<SubscriptionPurchasePackage>(_onPurchasePackage);
    on<SubscriptionPurchaseProduct>(_onPurchaseProduct);
    on<SubscriptionRestore>(_onRestore);
    on<SubscriptionPresentPaywall>(_onPresentPaywall);
    on<SubscriptionPresentPaywallIfNeeded>(_onPresentPaywallIfNeeded);
    on<SubscriptionPresentCustomerCenter>(_onPresentCustomerCenter);
    on<SubscriptionLogIn>(_onLogIn);
    on<SubscriptionLogOut>(_onLogOut);
  }

  Future<void> _onInitialize(
    SubscriptionInitialize event,
    Emitter<SubscriptionState> emit,
  ) async {
    emit(const SubscriptionLoading());

    try {
      await _revenueCatService.initialize(appUserId: event.appUserId);

      // Listen to status changes
      _statusSubscription?.cancel();
      _statusSubscription = _revenueCatService.subscriptionStatusStream.listen(
        (status) => add(SubscriptionStatusChanged(status)),
      );

      final status = await _revenueCatService.getSubscriptionStatus();
      final offerings = await _revenueCatService.getOfferings();

      emit(SubscriptionLoaded(
        status: status,
        offerings: offerings,
      ));
    } catch (e) {
      emit(SubscriptionError(e.toString()));
    }
  }

  void _onStatusChanged(
    SubscriptionStatusChanged event,
    Emitter<SubscriptionState> emit,
  ) {
    if (state is SubscriptionLoaded) {
      final currentState = state as SubscriptionLoaded;
      emit(currentState.copyWith(status: event.status));
    } else {
      emit(SubscriptionLoaded(status: event.status));
    }
  }

  Future<void> _onRefresh(
    SubscriptionRefresh event,
    Emitter<SubscriptionState> emit,
  ) async {
    try {
      final status = await _revenueCatService.refreshSubscriptionStatus();
      final offerings = await _revenueCatService.getOfferings();

      if (state is SubscriptionLoaded) {
        final currentState = state as SubscriptionLoaded;
        emit(currentState.copyWith(
          status: status,
          offerings: offerings,
        ));
      } else {
        emit(SubscriptionLoaded(
          status: status,
          offerings: offerings,
        ));
      }
    } catch (e) {
      emit(SubscriptionError(e.toString()));
    }
  }

  Future<void> _onPurchasePackage(
    SubscriptionPurchasePackage event,
    Emitter<SubscriptionState> emit,
  ) async {
    if (state is! SubscriptionLoaded) return;

    final currentState = state as SubscriptionLoaded;
    emit(currentState.copyWith(isPurchasing: true, purchaseError: null));

    try {
      final result = await _revenueCatService.purchasePackage(event.package);

      if (result.success) {
        final status = SubscriptionStatus.fromCustomerInfo(result.customerInfo);
        emit(currentState.copyWith(
          status: status,
          isPurchasing: false,
          purchaseSuccess: true,
        ));
      } else if (result.userCancelled) {
        emit(currentState.copyWith(isPurchasing: false));
      } else {
        emit(currentState.copyWith(
          isPurchasing: false,
          purchaseError: result.errorMessage,
        ));
      }
    } catch (e) {
      emit(currentState.copyWith(
        isPurchasing: false,
        purchaseError: e.toString(),
      ));
    }
  }

  Future<void> _onPurchaseProduct(
    SubscriptionPurchaseProduct event,
    Emitter<SubscriptionState> emit,
  ) async {
    if (state is! SubscriptionLoaded) return;

    final currentState = state as SubscriptionLoaded;
    emit(currentState.copyWith(isPurchasing: true, purchaseError: null));

    try {
      final result = await _revenueCatService.purchaseProduct(event.productId);

      if (result.success) {
        final status = SubscriptionStatus.fromCustomerInfo(result.customerInfo);
        emit(currentState.copyWith(
          status: status,
          isPurchasing: false,
          purchaseSuccess: true,
        ));
      } else if (result.userCancelled) {
        emit(currentState.copyWith(isPurchasing: false));
      } else {
        emit(currentState.copyWith(
          isPurchasing: false,
          purchaseError: result.errorMessage,
        ));
      }
    } catch (e) {
      emit(currentState.copyWith(
        isPurchasing: false,
        purchaseError: e.toString(),
      ));
    }
  }

  Future<void> _onRestore(
    SubscriptionRestore event,
    Emitter<SubscriptionState> emit,
  ) async {
    if (state is! SubscriptionLoaded) return;

    final currentState = state as SubscriptionLoaded;
    emit(currentState.copyWith(isRestoring: true, restoreError: null));

    try {
      final result = await _revenueCatService.restorePurchases();

      if (result.success) {
        final status = SubscriptionStatus.fromCustomerInfo(result.customerInfo);
        emit(currentState.copyWith(
          status: status,
          isRestoring: false,
          restoreSuccess: true,
        ));
      } else {
        emit(currentState.copyWith(
          isRestoring: false,
          restoreError: result.errorMessage,
        ));
      }
    } catch (e) {
      emit(currentState.copyWith(
        isRestoring: false,
        restoreError: e.toString(),
      ));
    }
  }

  Future<void> _onPresentPaywall(
    SubscriptionPresentPaywall event,
    Emitter<SubscriptionState> emit,
  ) async {
    try {
      await _revenueCatService.presentPaywall(offering: event.offering);
      // Refresh status after paywall closes
      add(const SubscriptionRefresh());
    } catch (e) {
      if (state is SubscriptionLoaded) {
        final currentState = state as SubscriptionLoaded;
        emit(currentState.copyWith(purchaseError: e.toString()));
      }
    }
  }

  Future<void> _onPresentPaywallIfNeeded(
    SubscriptionPresentPaywallIfNeeded event,
    Emitter<SubscriptionState> emit,
  ) async {
    try {
      await _revenueCatService.presentPaywallIfNeeded();
      // Refresh status after paywall closes
      add(const SubscriptionRefresh());
    } catch (e) {
      if (state is SubscriptionLoaded) {
        final currentState = state as SubscriptionLoaded;
        emit(currentState.copyWith(purchaseError: e.toString()));
      }
    }
  }

  Future<void> _onPresentCustomerCenter(
    SubscriptionPresentCustomerCenter event,
    Emitter<SubscriptionState> emit,
  ) async {
    try {
      await _revenueCatService.presentCustomerCenter();
      // Refresh status after customer center closes
      add(const SubscriptionRefresh());
    } catch (e) {
      if (state is SubscriptionLoaded) {
        final currentState = state as SubscriptionLoaded;
        emit(currentState.copyWith(purchaseError: e.toString()));
      }
    }
  }

  Future<void> _onLogIn(
    SubscriptionLogIn event,
    Emitter<SubscriptionState> emit,
  ) async {
    try {
      await _revenueCatService.logIn(event.appUserId);
      add(const SubscriptionRefresh());
    } catch (e) {
      if (state is SubscriptionLoaded) {
        final currentState = state as SubscriptionLoaded;
        emit(currentState.copyWith(purchaseError: e.toString()));
      }
    }
  }

  Future<void> _onLogOut(
    SubscriptionLogOut event,
    Emitter<SubscriptionState> emit,
  ) async {
    try {
      await _revenueCatService.logOut();
      add(const SubscriptionRefresh());
    } catch (e) {
      if (state is SubscriptionLoaded) {
        final currentState = state as SubscriptionLoaded;
        emit(currentState.copyWith(purchaseError: e.toString()));
      }
    }
  }

  @override
  Future<void> close() {
    _statusSubscription?.cancel();
    return super.close();
  }
}
