import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:tapix/core/services/app_guard_service.dart';
import 'package:tapix/core/services/code_integrity_service.dart';
import 'package:tapix/core/services/connectivity_service.dart';
import 'package:tapix/core/services/device_fingerprint_service.dart';
import 'package:tapix/core/services/license_service.dart';
import 'package:tapix/core/services/remote_security_service.dart';
import 'package:tapix/core/services/revenuecat_service.dart';

class _RevenueCat extends Mock implements RevenueCatService {}

class _License extends Mock implements LicenseService {}

class _Fingerprint extends Mock implements DeviceFingerprintService {}

class _Connectivity extends Mock implements ConnectivityService {}

class _RemoteSecurity extends Mock implements RemoteSecurityService {}

class _CodeIntegrity extends Mock implements CodeIntegrityService {}

void main() {
  late _RevenueCat revenueCat;
  late _License license;
  late _Fingerprint fingerprint;
  late _Connectivity connectivity;
  late _RemoteSecurity remoteSecurity;
  late _CodeIntegrity codeIntegrity;
  late AppGuardService guard;

  setUp(() {
    revenueCat = _RevenueCat();
    license = _License();
    fingerprint = _Fingerprint();
    connectivity = _Connectivity();
    remoteSecurity = _RemoteSecurity();
    codeIntegrity = _CodeIntegrity();

    when(
      () => codeIntegrity.verify(),
    ).thenAnswer((_) async => IntegrityCheckResult.passed);
    when(() => fingerprint.getFingerprint()).thenAnswer((_) async => 'device');
    when(
      () => remoteSecurity.runChecks(deviceFingerprint: 'device'),
    ).thenAnswer((_) async => SecurityCheckResult.passed);

    guard = AppGuardService(
      revenueCat: revenueCat,
      licenseService: license,
      fingerprintService: fingerprint,
      connectivityService: connectivity,
      remoteSecurityService: remoteSecurity,
      codeIntegrityService: codeIntegrity,
      revenueCatSupported: () => true,
    );
    addTearDown(guard.dispose);
  });

  test(
    'startup unlocks a valid local licence without any network call',
    () async {
      final now = DateTime.now();
      when(
        () => license.validateLicense(),
      ).thenAnswer((_) async => LicenseValidationResult.valid);
      when(() => license.loadLicense()).thenAnswer(
        (_) async => DeviceLicense(
          userId: 'offline-owner',
          deviceFingerprint: 'device',
          subscriptionType: SubscriptionType.lifetime.name,
          expiryDate: now.add(const Duration(days: 300)),
          lastOnlineValidation: now,
          integrityHash: 'signed',
        ),
      );

      final status = await guard.initialize().timeout(
        const Duration(seconds: 1),
      );

      expect(status.isUnlocked, isTrue);
      expect(status.isFreeTier, isFalse);
      expect(status.subscriptionStatus?.isPro, isTrue);
      verifyNever(() => connectivity.checkNow());
      verifyNever(() => remoteSecurity.fetchConfig());
      verifyNever(
        () => revenueCat.checkSubscription(
          throwOnError: any(named: 'throwOnError'),
        ),
      );
    },
  );

  test(
    'stale inactive store cache cannot revoke a valid local licence',
    () async {
      final now = DateTime.now();
      when(() => connectivity.checkNow()).thenAnswer((_) async => true);
      when(
        () => remoteSecurity.fetchConfig(),
      ).thenAnswer((_) async => SecurityConfig.defaultConfig());
      when(
        () => license.validateLicense(),
      ).thenAnswer((_) async => LicenseValidationResult.valid);
      when(() => license.loadLicense()).thenAnswer(
        (_) async => DeviceLicense(
          userId: 'offline-owner',
          deviceFingerprint: 'device',
          subscriptionType: SubscriptionType.yearly.name,
          expiryDate: now.add(const Duration(days: 30)),
          lastOnlineValidation: now,
          integrityHash: 'signed',
        ),
      );
      when(() => revenueCat.checkSubscription(throwOnError: true)).thenAnswer(
        (_) async => SubscriptionStatus(
          checkedAt: now.subtract(const Duration(days: 1)),
        ),
      );

      final status = await guard.revalidateOnline();

      expect(status.isUnlocked, isTrue);
      expect(status.isFreeTier, isFalse);
      verifyNever(() => license.revokeLicense());
    },
  );
}
