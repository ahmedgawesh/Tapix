import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../utils/platform_utils.dart';
import 'device_fingerprint_service.dart';

enum DesktopLicenseStatus {
  notApplicable,
  checking,
  valid,
  missing,
  invalidSignature,
  deviceMismatch,
  invalidProduct,
  platformMismatch,
  expired,
  offlineLeaseExpired,
  clockRollback,
  revoked,
  malformed,
}

class DesktopActivationResult {
  final bool success;
  final String? errorCode;
  final String? message;

  const DesktopActivationResult._({
    required this.success,
    this.errorCode,
    this.message,
  });

  const DesktopActivationResult.success() : this._(success: true);

  const DesktopActivationResult.failure(String code, String message)
    : this._(success: false, errorCode: code, message: message);
}

class _SignedLicenseInspection {
  final DesktopLicenseStatus status;
  final Map<String, dynamic>? payload;

  const _SignedLicenseInspection(this.status, [this.payload]);
}

/// Signed Desktop license for Windows and Linux.
///
/// The server owns the RSA private key. This application embeds only the
/// public key and therefore can verify licenses but can never issue one.
/// A per-device activation token is used for online refreshes and is stored
/// only in OS secure storage; the WordPress server stores its SHA-256 digest.
class DesktopLicenseService extends ChangeNotifier {
  static const _activateEndpoint =
      'https://tapixsolutions.com/wp-json/tapbix/v1/activate';
  static const _validateEndpoint =
      'https://tapixsolutions.com/wp-json/tapbix/v1/validate';
  static const _appId = 'com.tapix.pos';

  static const _envelopeKey = 'tapix_desktop_signed_license_v2';
  static const _activationTokenKey = 'tapix_desktop_activation_token_v2';
  static const _licenseIdKey = 'tapix_desktop_license_id_v2';

  static const manageLicenseUrl =
      'https://tapixsolutions.com/my-account/tapbix-licenses/';
  static const buyLicenseUrl = 'https://tapixsolutions.com/';

  // This is the public half of the existing production key pair. Rotating it
  // requires shipping a release that trusts both old and new public keys.
  static const _publicKeyPem = '''-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAqWbdNv6WJdmNlYWG3vA+
DI1seGTdXh5UaEG2kIAZVcno8BB3wfc3yRUGuWT9ZXQQQoRTSJJXEk9u0DdzprtK
LHJIS6tg6iSLsMQeflLmo/kbP2SN/PvvTdu9eyGQU9WbJmw6/jC0zFlhv1B/+twi
sCLsulPSlg7s7EfMCyNc/UjQJad05K2fUnmgpHALGzTZYjl1W/ielNmGprDxE8u0
zP+yMdssWeNQRiWUrEzhKhb9I6kvQcdsi3a2PtsiBlf03Ln+Klc1Q8IX6nyBdj7O
Qb9CRwPGHz7sMH8b3gnYppSFIm+KPlUlMibXap69f5hPvQ4UbYDaornSb6wh4lPe
rQIDAQAB
-----END PUBLIC KEY-----''';

  final DeviceFingerprintService _fingerprintService;
  final FlutterSecureStorage _secureStorage;
  final Dio _dio;
  final DateTime Function() _now;

  DesktopLicenseStatus _status = DesktopLicenseStatus.notApplicable;
  DesktopLicenseStatus get status => _status;
  bool get isActivated => !isSupported || _status == DesktopLicenseStatus.valid;
  bool get isSupported => PlatformUtils.isWindows || PlatformUtils.isLinux;
  bool get needsOnlineRefresh => _needsOnlineRefresh;
  bool _needsOnlineRefresh = false;
  Map<String, dynamic>? _verifiedPayload;
  Future<DesktopLicenseStatus>? _initializing;

  /// Features carried by the currently valid, RSA-signed desktop license.
  /// Legacy licenses without a `features` claim remain valid for the base
  /// product but do not acquire separately priced add-ons.
  bool hasSignedFeature(String featureId) {
    if (_status != DesktopLicenseStatus.valid || featureId.trim().isEmpty) {
      return false;
    }
    final raw = _verifiedPayload?['features'];
    if (raw is! List) return false;
    return raw.whereType<String>().contains(featureId);
  }

  /// Expiry carried by the verified license envelope. It is exposed only
  /// while the signature, device binding and offline lease are all valid.
  DateTime? get signedLicenseExpiration {
    if (_status != DesktopLicenseStatus.valid) return null;
    return _parseUtc(_verifiedPayload?['expires_at'], nullable: true);
  }

  /// Optional positive plan limit signed by the licensing server.
  /// Expected payload shape:
  /// `feature_limits: {featureId: {limitName: positiveInteger}}`.
  int? signedFeatureLimit(String featureId, String limitName) {
    if (!hasSignedFeature(featureId)) return null;
    final allLimits = _verifiedPayload?['feature_limits'];
    if (allLimits is! Map) return null;
    final feature = allLimits[featureId];
    if (feature is! Map) return null;
    final raw = feature[limitName];
    final value = raw is int ? raw : int.tryParse(raw?.toString() ?? '');
    return value != null && value > 0 ? value : null;
  }

  DesktopLicenseService({
    required DeviceFingerprintService fingerprintService,
    FlutterSecureStorage? secureStorage,
    Dio? dio,
    DateTime Function()? now,
  }) : _fingerprintService = fingerprintService,
       _secureStorage = secureStorage ?? const FlutterSecureStorage(),
       _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 15),
               receiveTimeout: const Duration(seconds: 20),
               sendTimeout: const Duration(seconds: 15),
             ),
           ),
       _now = now ?? DateTime.now;

  String get platformName => PlatformUtils.isWindows ? 'windows' : 'linux';

  Future<DesktopLicenseStatus> initialize({bool force = false}) {
    if (!isSupported) {
      _setStatus(DesktopLicenseStatus.notApplicable);
      return Future.value(_status);
    }
    if (!force && _status == DesktopLicenseStatus.valid) {
      return Future.value(_status);
    }
    if (!force && _initializing != null) return _initializing!;
    final future = _initializeInternal();
    _initializing = future;
    return future.whenComplete(() {
      if (identical(_initializing, future)) _initializing = null;
    });
  }

  Future<DesktopLicenseStatus> _initializeInternal() async {
    _setStatus(DesktopLicenseStatus.checking);
    final stored = await _secureStorage.read(key: _envelopeKey);
    if (stored == null || stored.trim().isEmpty) {
      _setStatus(DesktopLicenseStatus.missing);
      return _status;
    }
    final inspection = await _inspectEnvelope(stored);
    _needsOnlineRefresh = _isRefreshDue(inspection.payload);
    _verifiedPayload = inspection.status == DesktopLicenseStatus.valid
        ? inspection.payload
        : null;
    _setStatus(inspection.status);
    return inspection.status;
  }

  Future<DesktopActivationResult> activate(String rawLicenseKey) async {
    if (!isSupported) {
      return const DesktopActivationResult.failure(
        'unsupported_platform',
        'Desktop activation is available on Windows and Linux only.',
      );
    }
    final key = rawLicenseKey.trim().toUpperCase();
    if (!RegExp(r'^TBX(?:-[A-HJ-NP-Z2-9]{4}){5}$').hasMatch(key)) {
      return const DesktopActivationResult.failure(
        'invalid_key_format',
        'Enter a valid TapBix license key.',
      );
    }
    final fingerprint = await _fingerprintService.getFingerprint();
    final deviceName = await _fingerprintService.getDeviceModel();
    final package = await PackageInfo.fromPlatform();

    try {
      final response = await _dio.post<dynamic>(
        _activateEndpoint,
        data: <String, dynamic>{
          'license_key': key,
          'device_id': fingerprint,
          'device_name': deviceName,
          'platform': platformName,
          'app_version': package.version,
        },
        options: _requestOptions,
      );
      return await _acceptActivationResponse(response);
    } on DioException catch (error) {
      if (error.response != null) return _serverFailure(error.response!);
      return const DesktopActivationResult.failure(
        'network_error',
        'Could not reach the activation server.',
      );
    } catch (error) {
      if (kDebugMode) debugPrint('Desktop activation failed: $error');
      return const DesktopActivationResult.failure(
        'activation_error',
        'Activation failed.',
      );
    }
  }

  Future<DesktopActivationResult> refreshOnline() async {
    if (!isSupported) return const DesktopActivationResult.success();
    final idText = await _secureStorage.read(key: _licenseIdKey);
    final token = await _secureStorage.read(key: _activationTokenKey);
    final licenseId = int.tryParse(idText ?? '');
    if (licenseId == null || token == null || token.length < 32) {
      _setStatus(DesktopLicenseStatus.missing);
      return const DesktopActivationResult.failure(
        'activation_required',
        'Activate this device again.',
      );
    }
    final fingerprint = await _fingerprintService.getFingerprint();
    final package = await PackageInfo.fromPlatform();
    try {
      final response = await _dio.post<dynamic>(
        _validateEndpoint,
        data: <String, dynamic>{
          'license_id': licenseId,
          'activation_token': token,
          'device_id': fingerprint,
          'platform': platformName,
          'app_version': package.version,
        },
        options: _requestOptions,
      );
      if (response.statusCode != 200) {
        final failure = _serverFailure(response);
        if (response.statusCode == 403) {
          _setStatus(DesktopLicenseStatus.revoked);
        }
        return failure;
      }
      final body = response.data;
      if (body is! Map || body['ok'] != true || body['license'] is! Map) {
        return const DesktopActivationResult.failure(
          'malformed_response',
          'The activation server returned invalid data.',
        );
      }
      final encoded = jsonEncode(
        Map<String, dynamic>.from(body['license'] as Map),
      );
      final inspection = await _inspectEnvelope(encoded);
      if (inspection.status != DesktopLicenseStatus.valid) {
        _setStatus(inspection.status);
        return DesktopActivationResult.failure(
          'local_verification_failed',
          inspection.status.name,
        );
      }
      await _secureStorage.write(key: _envelopeKey, value: encoded);
      _needsOnlineRefresh = false;
      _verifiedPayload = inspection.payload;
      _setStatus(DesktopLicenseStatus.valid);
      return const DesktopActivationResult.success();
    } on DioException catch (error) {
      if (error.response != null) {
        final response = error.response!;
        if (response.statusCode == 403) {
          _setStatus(DesktopLicenseStatus.revoked);
        }
        return _serverFailure(response);
      }
      return const DesktopActivationResult.failure(
        'network_error',
        'Could not reach the activation server.',
      );
    }
  }

  Future<DesktopActivationResult> _acceptActivationResponse(
    Response<dynamic> response,
  ) async {
    if (response.statusCode != 200) return _serverFailure(response);
    final body = response.data;
    if (body is! Map ||
        body['ok'] != true ||
        body['license'] is! Map ||
        body['license_id'] is! num ||
        body['activation_token'] is! String) {
      return const DesktopActivationResult.failure(
        'malformed_response',
        'The activation server returned invalid data.',
      );
    }
    final token = body['activation_token'] as String;
    if (token.length < 32) {
      return const DesktopActivationResult.failure(
        'malformed_response',
        'The activation token is invalid.',
      );
    }
    final encoded = jsonEncode(
      Map<String, dynamic>.from(body['license'] as Map),
    );
    final inspection = await _inspectEnvelope(encoded);
    if (inspection.status != DesktopLicenseStatus.valid) {
      _setStatus(inspection.status);
      return DesktopActivationResult.failure(
        'local_verification_failed',
        inspection.status.name,
      );
    }
    // Persist only after the RSA signature, app identity, platform, device,
    // and validity window have all passed locally.
    await _secureStorage.write(key: _envelopeKey, value: encoded);
    await _secureStorage.write(
      key: _licenseIdKey,
      value: (body['license_id'] as num).toInt().toString(),
    );
    await _secureStorage.write(key: _activationTokenKey, value: token);
    _needsOnlineRefresh = false;
    _verifiedPayload = inspection.payload;
    _setStatus(DesktopLicenseStatus.valid);
    return const DesktopActivationResult.success();
  }

  Future<void> clearLocalLicense() async {
    await _secureStorage.delete(key: _envelopeKey);
    await _secureStorage.delete(key: _licenseIdKey);
    await _secureStorage.delete(key: _activationTokenKey);
    _needsOnlineRefresh = false;
    _verifiedPayload = null;
    _setStatus(
      isSupported
          ? DesktopLicenseStatus.missing
          : DesktopLicenseStatus.notApplicable,
    );
  }

  Future<_SignedLicenseInspection> _inspectEnvelope(String encoded) async {
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map) {
        return const _SignedLicenseInspection(DesktopLicenseStatus.malformed);
      }
      final envelope = Map<String, dynamic>.from(decoded);
      final payloadJson = envelope['payload_json'];
      final signatureText = envelope['signature'];
      if (payloadJson is! String ||
          signatureText is! String ||
          envelope['algorithm'] != 'RSA-SHA256') {
        return const _SignedLicenseInspection(DesktopLicenseStatus.malformed);
      }
      final validSignature = RsaSha256LicenseVerifier.verify(
        publicKeyPem: _publicKeyPem,
        message: utf8.encode(payloadJson),
        signature: base64Decode(signatureText),
      );
      if (!validSignature) {
        return const _SignedLicenseInspection(
          DesktopLicenseStatus.invalidSignature,
        );
      }
      final rawPayload = jsonDecode(payloadJson);
      if (rawPayload is! Map) {
        return const _SignedLicenseInspection(DesktopLicenseStatus.malformed);
      }
      final payload = Map<String, dynamic>.from(rawPayload);
      if (payload['schema'] != 2 || payload['app_id'] != _appId) {
        return _SignedLicenseInspection(
          DesktopLicenseStatus.invalidProduct,
          payload,
        );
      }
      final product = payload['product'];
      final acceptedProduct =
          product == 'tapbix-desktop' ||
          (platformName == 'windows' && product == 'tapbix-windows') ||
          (platformName == 'linux' && product == 'tapbix-linux');
      if (!acceptedProduct) {
        return _SignedLicenseInspection(
          DesktopLicenseStatus.invalidProduct,
          payload,
        );
      }
      if (payload['platform'] != platformName ||
          payload['platforms'] is! List) {
        return _SignedLicenseInspection(
          DesktopLicenseStatus.platformMismatch,
          payload,
        );
      }
      final platforms = (payload['platforms'] as List).whereType<String>();
      if (!platforms.contains(platformName)) {
        return _SignedLicenseInspection(
          DesktopLicenseStatus.platformMismatch,
          payload,
        );
      }
      final fingerprint = await _fingerprintService.getFingerprint();
      if (payload['device_id'] != fingerprint) {
        return _SignedLicenseInspection(
          DesktopLicenseStatus.deviceMismatch,
          payload,
        );
      }
      final issuedAt = _parseUtc(payload['issued_at']);
      final offlineUntil = _parseUtc(payload['offline_valid_until']);
      if (issuedAt == null || offlineUntil == null) {
        return _SignedLicenseInspection(
          DesktopLicenseStatus.malformed,
          payload,
        );
      }
      final now = _now().toUtc();
      if (now.isBefore(issuedAt.subtract(const Duration(minutes: 5)))) {
        return _SignedLicenseInspection(
          DesktopLicenseStatus.clockRollback,
          payload,
        );
      }
      final expiresAt = _parseUtc(payload['expires_at'], nullable: true);
      if (expiresAt != null && now.isAfter(expiresAt)) {
        return _SignedLicenseInspection(DesktopLicenseStatus.expired, payload);
      }
      if (now.isAfter(offlineUntil)) {
        return _SignedLicenseInspection(
          DesktopLicenseStatus.offlineLeaseExpired,
          payload,
        );
      }
      return _SignedLicenseInspection(DesktopLicenseStatus.valid, payload);
    } catch (error) {
      if (kDebugMode) debugPrint('Desktop license validation failed: $error');
      return const _SignedLicenseInspection(DesktopLicenseStatus.malformed);
    }
  }

  bool _isRefreshDue(Map<String, dynamic>? payload) {
    if (payload == null) return false;
    final due = _parseUtc(payload['revalidate_after']);
    return due != null && _now().toUtc().isAfter(due);
  }

  DateTime? _parseUtc(dynamic value, {bool nullable = false}) {
    if (value == null && nullable) return null;
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value)?.toUtc();
  }

  Options get _requestOptions => Options(
    headers: const <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'Cache-Control': 'no-store',
    },
    validateStatus: (status) => status != null && status < 500,
  );

  DesktopActivationResult _serverFailure(Response<dynamic> response) {
    var code = response.statusCode == 429 ? 'rate_limited' : 'server_rejected';
    var message = 'The activation server rejected this request.';
    final body = response.data;
    if (body is Map) {
      final map = Map<String, dynamic>.from(body);
      if (map['code'] is String) code = map['code'] as String;
      if (map['message'] is String) message = map['message'] as String;
    }
    return DesktopActivationResult.failure(code, message);
  }

  void _setStatus(DesktopLicenseStatus value) {
    if (_status == value) return;
    _status = value;
    notifyListeners();
  }
}

@visibleForTesting
class RsaSha256LicenseVerifier {
  static const _digestInfoPrefix = <int>[
    0x30,
    0x31,
    0x30,
    0x0d,
    0x06,
    0x09,
    0x60,
    0x86,
    0x48,
    0x01,
    0x65,
    0x03,
    0x04,
    0x02,
    0x01,
    0x05,
    0x00,
    0x04,
    0x20,
  ];

  static bool verify({
    required String publicKeyPem,
    required List<int> message,
    required List<int> signature,
  }) {
    try {
      final key = _parsePublicKey(publicKeyPem);
      final length = (key.$1.bitLength + 7) ~/ 8;
      if (signature.length != length) return false;
      final signatureInt = _bytesToBigInt(signature);
      if (signatureInt >= key.$1) return false;
      final actual = _bigIntToBytes(
        signatureInt.modPow(key.$2, key.$1),
        length,
      );
      final digestInfo = <int>[
        ..._digestInfoPrefix,
        ...sha256.convert(message).bytes,
      ];
      final paddingLength = length - digestInfo.length - 3;
      if (paddingLength < 8) return false;
      final expected = <int>[
        0,
        1,
        ...List<int>.filled(paddingLength, 0xff),
        0,
        ...digestInfo,
      ];
      var difference = actual.length ^ expected.length;
      if (actual.length != expected.length) return false;
      for (var index = 0; index < actual.length; index++) {
        difference |= actual[index] ^ expected[index];
      }
      return difference == 0;
    } catch (_) {
      return false;
    }
  }

  static (BigInt, BigInt) _parsePublicKey(String pem) {
    final der = base64Decode(
      pem
          .replaceAll('-----BEGIN PUBLIC KEY-----', '')
          .replaceAll('-----END PUBLIC KEY-----', '')
          .replaceAll(RegExp(r'\s+'), ''),
    );
    final outer = _DerReader(Uint8List.fromList(der));
    final spki = _DerReader(outer.read(0x30));
    spki.read(0x30);
    final bitString = spki.read(0x03);
    if (bitString.isEmpty || bitString.first != 0) {
      throw const FormatException('Invalid public key.');
    }
    final rsaOuter = _DerReader(bitString.sublist(1));
    final rsa = _DerReader(rsaOuter.read(0x30));
    final modulus = _trimZero(rsa.read(0x02));
    final exponent = _trimZero(rsa.read(0x02));
    return (_bytesToBigInt(modulus), _bytesToBigInt(exponent));
  }

  static Uint8List _trimZero(Uint8List value) =>
      value.length > 1 && value.first == 0
      ? Uint8List.fromList(value.sublist(1))
      : value;

  static BigInt _bytesToBigInt(List<int> bytes) {
    var value = BigInt.zero;
    for (final byte in bytes) {
      value = (value << 8) | BigInt.from(byte);
    }
    return value;
  }

  static Uint8List _bigIntToBytes(BigInt value, int length) {
    final bytes = Uint8List(length);
    var remaining = value;
    for (var index = length - 1; index >= 0; index--) {
      bytes[index] = (remaining & BigInt.from(0xff)).toInt();
      remaining >>= 8;
    }
    return bytes;
  }
}

class _DerReader {
  final Uint8List bytes;
  int offset = 0;

  _DerReader(this.bytes);

  Uint8List read(int expectedTag) {
    if (offset >= bytes.length || bytes[offset++] != expectedTag) {
      throw const FormatException('Unexpected DER tag.');
    }
    final length = _readLength();
    if (length < 0 || offset + length > bytes.length) {
      throw const FormatException('Invalid DER length.');
    }
    final value = Uint8List.fromList(bytes.sublist(offset, offset + length));
    offset += length;
    return value;
  }

  int _readLength() {
    if (offset >= bytes.length) throw const FormatException('Missing length.');
    final first = bytes[offset++];
    if ((first & 0x80) == 0) return first;
    final count = first & 0x7f;
    if (count == 0 || count > 4 || offset + count > bytes.length) {
      throw const FormatException('Unsupported DER length.');
    }
    var length = 0;
    for (var index = 0; index < count; index++) {
      length = (length << 8) | bytes[offset++];
    }
    return length;
  }
}
