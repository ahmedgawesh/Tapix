import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:tapix/core/services/app_guard_service.dart';
import 'package:tapix/core/services/revenuecat_service.dart';
import 'package:tapix/features/subscription/presentation/bloc/subscription_bloc.dart';

class _RevenueCat extends Mock implements RevenueCatService {}

class _AppGuard extends Mock implements AppGuardService {}

void main() {
  test(
    'emits local unlocked state before RevenueCat initialization completes',
    () async {
      final revenueCat = _RevenueCat();
      final appGuard = _AppGuard();
      final revenueCatReady = Completer<void>();
      const localStatus = AppGuardStatus.unlocked(
        subscriptionStatus: SubscriptionStatus(
          isActive: true,
          isPro: true,
          subscriptionType: SubscriptionType.lifetime,
        ),
      );

      when(() => appGuard.initialize()).thenAnswer((_) async => localStatus);
      when(() => appGuard.statusStream).thenAnswer((_) => const Stream.empty());
      when(
        () => revenueCat.initialize(appUserId: any(named: 'appUserId')),
      ).thenAnswer((_) => revenueCatReady.future);
      when(() => appGuard.startListening()).thenReturn(null);
      when(
        () => appGuard.revalidateOnline(),
      ).thenAnswer((_) async => localStatus);

      final bloc = SubscriptionBloc(
        revenueCatService: revenueCat,
        appGuardService: appGuard,
      );
      addTearDown(bloc.close);

      bloc.add(const SubscriptionStartGuard(appUserId: 'owner'));
      await expectLater(
        bloc.stream
            .where((state) => state is SubscriptionLoaded)
            .cast<SubscriptionLoaded>()
            .first
            .timeout(const Duration(seconds: 1)),
        completion(
          isA<SubscriptionLoaded>().having(
            (state) => state.isPro,
            'isPro',
            isTrue,
          ),
        ),
      );
      expect(revenueCatReady.isCompleted, isFalse);

      revenueCatReady.complete();
      await Future<void>.delayed(Duration.zero);
    },
  );
}
