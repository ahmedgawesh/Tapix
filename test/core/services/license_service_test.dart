import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:tapix/core/services/device_fingerprint_service.dart';
import 'package:tapix/core/services/license_service.dart';
import 'package:tapix/core/services/local_integrity_key_service.dart';
import 'package:tapix/core/services/revenuecat_service.dart';

class _MemoryLicenseStorage implements LicenseStorage {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async => this.value = value;

  @override
  Future<void> delete() async => value = null;
}

class _FingerprintService extends DeviceFingerprintService {
  _FingerprintService(this.fingerprint);

  final String fingerprint;

  @override
  Future<String> getFingerprint() async => fingerprint;

  @override
  Future<bool> verifyFingerprint(String fingerprint) async =>
      fingerprint == this.fingerprint;
}

void main() {
  late _MemoryLicenseStorage storage;
  late LocalIntegrityKeyService signer;

  setUp(() {
    storage = _MemoryLicenseStorage();
    signer = LocalIntegrityKeyService.testing(List<int>.generate(32, (i) => i));
  });

  LicenseService service({
    LocalIntegritySigner? integritySigner,
    String fingerprint = 'device-a',
  }) => LicenseService(
    fingerprintService: _FingerprintService(fingerprint),
    integritySigner: integritySigner ?? signer,
    storage: storage,
  );

  test(
    'version 2 license validates with installation key and device',
    () async {
      final licenses = service();
      await licenses.createLicense(
        userId: 'user-1',
        subscriptionType: SubscriptionType.monthly,
        expiryDate: DateTime.now().add(const Duration(days: 20)),
      );

      expect(await licenses.validateLicense(), LicenseValidationResult.valid);
    },
  );

  test('editing protected license fields is detected', () async {
    final licenses = service();
    await licenses.createLicense(
      userId: 'user-1',
      subscriptionType: SubscriptionType.monthly,
      expiryDate: DateTime.now().add(const Duration(days: 20)),
    );
    final json = jsonDecode(storage.value!) as Map<String, dynamic>;
    json['subscriptionType'] = SubscriptionType.lifetime.name;
    storage.value = jsonEncode(json);

    expect(
      await service().validateLicense(),
      LicenseValidationResult.integrityFailed,
    );
  });

  test('license copied from another installation key is rejected', () async {
    await service().createLicense(
      userId: 'user-1',
      subscriptionType: SubscriptionType.yearly,
      expiryDate: DateTime.now().add(const Duration(days: 20)),
    );
    final otherSigner = LocalIntegrityKeyService.testing(
      List<int>.filled(32, 99),
    );

    expect(
      await service(integritySigner: otherSigner).validateLicense(),
      LicenseValidationResult.integrityFailed,
    );
  });

  test(
    'legacy embedded-secret license requires RevenueCat validation',
    () async {
      storage.value = jsonEncode({
        'userId': 'legacy-user',
        'deviceFingerprint': 'device-a',
        'subscriptionType': 'lifetime',
        'expiryDate': DateTime.now()
            .add(const Duration(days: 100))
            .toIso8601String(),
        'lastOnlineValidation': DateTime.now().toIso8601String(),
        'integrityHash': 'legacy-value',
      });

      expect(
        await service().validateLicense(),
        LicenseValidationResult.onlineValidationRequired,
      );
    },
  );

  test('valid signed license remains bound to its device', () async {
    await service().createLicense(
      userId: 'user-1',
      subscriptionType: SubscriptionType.lifetime,
      expiryDate: null,
    );

    expect(
      await service(fingerprint: 'device-b').validateLicense(),
      LicenseValidationResult.deviceMismatch,
    );
  });
}
