import 'package:flutter_test/flutter_test.dart';

import 'package:tapix/core/services/app_guard_service.dart';

void main() {
  group('AppGuardStatus — three terminal states', () {
    test('unlocked() is Pro: isUnlocked=true, isFreeTier=false', () {
      const s = AppGuardStatus.unlocked();
      expect(s.isUnlocked, isTrue);
      expect(s.isFreeTier, isFalse);
      expect(s.lockReason, AppLockReason.none);
      expect(s.requiresInternet, isFalse);
    });

    test('freeTier() is unlocked but free: isUnlocked=true, isFreeTier=true', () {
      const s = AppGuardStatus.freeTier();
      expect(s.isUnlocked, isTrue, reason: 'free tier must NOT lock the app');
      expect(s.isFreeTier, isTrue);
      // Default hint for the upsell UI.
      expect(s.lockReason, AppLockReason.noSubscription);
    });

    test('freeTier() preserves explicit reason hint (licenseExpired)', () {
      const s = AppGuardStatus.freeTier(
        lockReason: AppLockReason.licenseExpired,
        requiresInternet: true,
      );
      expect(s.isUnlocked, isTrue);
      expect(s.isFreeTier, isTrue);
      expect(s.lockReason, AppLockReason.licenseExpired);
      expect(s.requiresInternet, isTrue);
    });

    test('freeTier() preserves explicit reason hint (offlineTooLong)', () {
      const s = AppGuardStatus.freeTier(
        lockReason: AppLockReason.offlineTooLong,
        requiresInternet: true,
      );
      expect(s.isUnlocked, isTrue);
      expect(s.isFreeTier, isTrue);
      expect(s.lockReason, AppLockReason.offlineTooLong);
    });

    test('locked() is a hard lock: isUnlocked=false, isFreeTier=false', () {
      const s = AppGuardStatus.locked(lockReason: AppLockReason.codeTampered);
      expect(s.isUnlocked, isFalse);
      expect(s.isFreeTier, isFalse);
      expect(s.lockReason, AppLockReason.codeTampered);
    });
  });

  group('AppGuardStatus — invariants (security policy pins)', () {
    test('noSubscription is NEVER a hard lock anymore', () {
      // This is the central architectural decision of Phase B3:
      // freemium model means "no subscription" must boot the app.
      const s = AppGuardStatus.freeTier(
        lockReason: AppLockReason.noSubscription,
      );
      expect(s.isUnlocked, isTrue);
      expect(s.isFreeTier, isTrue);
    });

    test('licenseExpired is NEVER a hard lock anymore', () {
      // Phase B3: subscription lapse demotes to free tier, never locks.
      const s = AppGuardStatus.freeTier(
        lockReason: AppLockReason.licenseExpired,
      );
      expect(s.isUnlocked, isTrue);
      expect(s.isFreeTier, isTrue);
    });

    test('offlineTooLong is NEVER a hard lock anymore', () {
      const s = AppGuardStatus.freeTier(
        lockReason: AppLockReason.offlineTooLong,
      );
      expect(s.isUnlocked, isTrue);
      expect(s.isFreeTier, isTrue);
    });

    test('deviceMismatch IS a hard lock (security violation)', () {
      const s = AppGuardStatus.locked(lockReason: AppLockReason.deviceMismatch);
      expect(s.isUnlocked, isFalse);
    });

    test('licenseTampered IS a hard lock (security violation)', () {
      const s = AppGuardStatus.locked(lockReason: AppLockReason.licenseTampered);
      expect(s.isUnlocked, isFalse);
    });

    test('codeTampered IS a hard lock (security violation)', () {
      const s = AppGuardStatus.locked(lockReason: AppLockReason.codeTampered);
      expect(s.isUnlocked, isFalse);
    });

    test('deviceBlocked IS a hard lock', () {
      const s = AppGuardStatus.locked(lockReason: AppLockReason.deviceBlocked);
      expect(s.isUnlocked, isFalse);
    });

    test('versionKilled IS a hard lock', () {
      const s = AppGuardStatus.locked(lockReason: AppLockReason.versionKilled);
      expect(s.isUnlocked, isFalse);
    });
  });
}
