import 'dart:developer' as developer;

import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

/// Service for biometric authentication using the device's fingerprint or face recognition.
///
/// Best practices implemented:
/// - Checks device capability before attempting authentication
/// - Handles platform exceptions gracefully
/// - Uses localized reason strings
/// - Supports both fingerprint and face recognition
class BiometricService {
  final LocalAuthentication _auth;

  BiometricService({LocalAuthentication? auth})
    : _auth = auth ?? LocalAuthentication();

  /// Check if the device supports biometric authentication.
  Future<bool> isDeviceSupported() async {
    try {
      return await _auth.isDeviceSupported();
    } on LocalAuthException catch (e) {
      developer.log(
        'BiometricService.isDeviceSupported error: $e',
        name: 'BiometricService',
      );
      return false;
    } on PlatformException catch (e) {
      developer.log(
        'BiometricService.isDeviceSupported error: $e',
        name: 'BiometricService',
      );
      return false;
    }
  }

  /// Check if biometrics are enrolled on the device.
  Future<bool> canCheckBiometrics() async {
    try {
      return await _auth.canCheckBiometrics;
    } on LocalAuthException catch (e) {
      developer.log(
        'BiometricService.canCheckBiometrics error: $e',
        name: 'BiometricService',
      );
      return false;
    } on PlatformException catch (e) {
      developer.log(
        'BiometricService.canCheckBiometrics error: $e',
        name: 'BiometricService',
      );
      return false;
    }
  }

  /// Get the list of available biometric types on the device.
  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _auth.getAvailableBiometrics();
    } on LocalAuthException catch (e) {
      developer.log(
        'BiometricService.getAvailableBiometrics error: $e',
        name: 'BiometricService',
      );
      return [];
    } on PlatformException catch (e) {
      developer.log(
        'BiometricService.getAvailableBiometrics error: $e',
        name: 'BiometricService',
      );
      return [];
    }
  }

  /// Check if biometric authentication is available (device supported + biometrics enrolled).
  Future<bool> isBiometricAvailable() async {
    final supported = await isDeviceSupported();
    if (!supported) return false;
    final canCheck = await canCheckBiometrics();
    return canCheck;
  }

  /// Authenticate the user using biometrics.
  /// [localizedReason] is shown to the user explaining why authentication is needed.
  /// Returns true if authentication succeeded, false otherwise.
  Future<bool> authenticate({required String localizedReason}) async {
    try {
      final isAvailable = await isBiometricAvailable();
      if (!isAvailable) {
        developer.log(
          'BiometricService: Biometrics not available',
          name: 'BiometricService',
        );
        return false;
      }

      return await _auth.authenticate(
        localizedReason: localizedReason,
        persistAcrossBackgrounding: true,
        biometricOnly: true,
      );
    } on LocalAuthException catch (e) {
      developer.log(
        'BiometricService.authenticate error: ${e.code} - $e',
        name: 'BiometricService',
      );
      return false;
    } on PlatformException catch (e) {
      developer.log(
        'BiometricService.authenticate error: $e',
        name: 'BiometricService',
      );
      return false;
    }
  }
}
