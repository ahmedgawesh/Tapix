import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../../../../core/services/app_guard_service.dart';
import '../../../../core/services/revenuecat_service.dart';

part 'subscription_event.dart';
part 'subscription_state.dart';

class SubscriptionBloc extends Bloc<SubscriptionEvent, SubscriptionState> {
  final RevenueCatService _revenueCatService;
  final AppGuardService _appGuardService;
  StreamSubscription<AppGuardStatus>? _guardSubscription;

  SubscriptionBloc({
    required RevenueCatService revenueCatService,
    required AppGuardService appGuardService,
  }) : _revenueCatService = revenueCatService,
       _appGuardService = appGuardService,
       super(const SubscriptionInitial()) {
    on<SubscriptionStartGuard>(_onStartGuard);
    on<SubscriptionGuardStatusChanged>(_onGuardStatusChanged);
    on<SubscriptionRefresh>(_onRefresh);
    on<SubscriptionPresentPaywall>(_onPresentPaywall);
    on<SubscriptionPresentCustomerCenter>(_onPresentCustomerCenter);
    on<SubscriptionRestore>(_onRestore);
    on<SubscriptionLogIn>(_onLogIn);
    on<SubscriptionLogOut>(_onLogOut);
  }

  /// Run the full AppGuard initialization and start listening.
  Future<void> _onStartGuard(
    SubscriptionStartGuard event,
    Emitter<SubscriptionState> emit,
  ) async {
    emit(const SubscriptionLoading());

    try {
      // Resolve the signed local licence first. The initial UI state must not
      // wait for the store or any remote endpoint.
      final guardStatus = await _appGuardService.initialize();

      // Subscribe before starting the background refresh so no update can be
      // missed between the local and online decisions.
      _guardSubscription?.cancel();
      _guardSubscription = _appGuardService.statusStream.listen(
        (gs) => add(SubscriptionGuardStatusChanged(gs)),
      );

      emit(_stateFromGuardStatus(guardStatus));
      unawaited(_initializeOnlineServices(event.appUserId));
    } catch (e) {
      emit(SubscriptionError(e.toString()));
    }
  }

  Future<void> _initializeOnlineServices(String? appUserId) async {
    try {
      await _revenueCatService.initialize(appUserId: appUserId);
      _appGuardService.startListening();
      await _appGuardService.revalidateOnline();
    } catch (error) {
      // Network/store failure never replaces a valid local startup decision.
      debugPrint(
        'SubscriptionBloc: background entitlement refresh failed: $error',
      );
    }
  }

  void _onGuardStatusChanged(
    SubscriptionGuardStatusChanged event,
    Emitter<SubscriptionState> emit,
  ) {
    emit(_stateFromGuardStatus(event.guardStatus));
  }

  Future<void> _onRefresh(
    SubscriptionRefresh event,
    Emitter<SubscriptionState> emit,
  ) async {
    try {
      final guardStatus = await _appGuardService.revalidateOnline();
      emit(_stateFromGuardStatus(guardStatus));
    } catch (e) {
      emit(SubscriptionError(e.toString()));
    }
  }

  Future<void> _onPresentPaywall(
    SubscriptionPresentPaywall event,
    Emitter<SubscriptionState> emit,
  ) async {
    // Custom paywall is now shown via direct navigation.
    // This event is kept for backwards compatibility but is a no-op.
  }

  Future<void> _onPresentCustomerCenter(
    SubscriptionPresentCustomerCenter event,
    Emitter<SubscriptionState> emit,
  ) async {
    if (!RevenueCatConfig.isSupported || !_revenueCatService.isInitialized) {
      return;
    }
    try {
      await _revenueCatService.openSubscriptionManagement();
      add(const SubscriptionRefresh());
    } catch (e) {
      _emitError(emit, e.toString());
    }
  }

  Future<void> _onRestore(
    SubscriptionRestore event,
    Emitter<SubscriptionState> emit,
  ) async {
    if (!RevenueCatConfig.isSupported || !_revenueCatService.isInitialized) {
      return;
    }

    if (state is SubscriptionLoaded) {
      emit((state as SubscriptionLoaded).copyWith(isRestoring: true));
    }

    try {
      final result = await _revenueCatService.restorePurchases();
      if (result.success) {
        add(const SubscriptionRefresh());
      } else {
        _emitError(emit, result.errorMessage ?? 'Restore failed');
      }
    } catch (e) {
      _emitError(emit, e.toString());
    }
  }

  Future<void> _onLogIn(
    SubscriptionLogIn event,
    Emitter<SubscriptionState> emit,
  ) async {
    if (!RevenueCatConfig.isSupported || !_revenueCatService.isInitialized) {
      return;
    }
    try {
      await _revenueCatService.logIn(event.appUserId);
      add(const SubscriptionRefresh());
    } catch (e) {
      _emitError(emit, e.toString());
    }
  }

  Future<void> _onLogOut(
    SubscriptionLogOut event,
    Emitter<SubscriptionState> emit,
  ) async {
    if (!RevenueCatConfig.isSupported || !_revenueCatService.isInitialized) {
      return;
    }
    try {
      await _revenueCatService.logOut();
      add(const SubscriptionRefresh());
    } catch (e) {
      _emitError(emit, e.toString());
    }
  }

  /// Map [AppGuardStatus] to [SubscriptionState].
  SubscriptionState _stateFromGuardStatus(AppGuardStatus gs) {
    if (gs.isUnlocked) {
      return SubscriptionLoaded(
        status: gs.subscriptionStatus ?? const SubscriptionStatus(),
        guardStatus: gs,
      );
    }

    return SubscriptionLocked(
      lockReason: gs.lockReason,
      requiresInternet: gs.requiresInternet,
      status: gs.subscriptionStatus ?? const SubscriptionStatus(),
    );
  }

  void _emitError(Emitter<SubscriptionState> emit, String message) {
    if (state is SubscriptionLoaded) {
      emit((state as SubscriptionLoaded).copyWith(purchaseError: message));
    } else {
      emit(SubscriptionError(message));
    }
  }

  @override
  Future<void> close() {
    _guardSubscription?.cancel();
    return super.close();
  }
}
