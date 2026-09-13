import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:bcrypt/bcrypt.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../database/daos/settings_dao.dart';
import '../localization_service.dart';
import 'lan_business_models.dart';
import 'lan_models.dart';

/// Owns the first, deliberately narrow LAN protocol.
///
/// This phase exposes health/pairing only. Database and accounting operations
/// remain local until authenticated request signing and transactional API
/// endpoints are introduced. The SQLite file is never shared over the network.
class LanNetworkService {
  LanNetworkService(
    this._settingsDao, {
    LanMasterAuthGateway? authGateway,
    LanMasterBusinessGateway? businessGateway,
    LocalizationService? localizationService,
  }) : _authGateway = authGateway,
       _businessGateway = businessGateway,
       _localizationService = localizationService;

  static const int protocolVersion = 1;
  static const int defaultPort = 45820;
  static const int discoveryPort = 45821;
  static const _discoveryProbe = 'TAPIX_DISCOVER_V1';

  static const _modeKey = 'lan.mode';
  static const _portKey = 'lan.port';
  static const _deviceIdKey = 'lan.device_id';
  static const _masterHostKey = 'lan.master_host';
  static const _masterIdKey = 'lan.master_id';
  static const _clientTokenKey = 'lan.client_token';
  static const _clientDeviceNameKey = 'lan.client_device_name';
  static const _authorizedDevicesKey = 'lan.authorized_devices';
  static const _userSessionHeader = 'X-Tapix-User-Session';
  static const _platformHeader = 'X-Tapix-Platform';
  static const _deviceNameHeader = 'X-Tapix-Device-Name';
  static const _masterKeepAliveChannel = MethodChannel(
    'com.tapix.pos/master_keep_alive',
  );

  final SettingsDao _settingsDao;
  final LanMasterAuthGateway? _authGateway;
  final LanMasterBusinessGateway? _businessGateway;
  final LocalizationService? _localizationService;
  final _random = Random.secure();
  final _controller = StreamController<LanNetworkSnapshot>.broadcast();
  final _masterActivityController =
      StreamController<LanMasterActivityEvent>.broadcast();

  LanNetworkSnapshot _snapshot = const LanNetworkSnapshot();
  HttpServer? _server;
  Timer? _monitorTimer;
  Timer? _masterMonitorTimer;
  RawDatagramSocket? _discoverySocket;
  bool _masterRefreshInFlight = false;
  bool _clientMonitorInFlight = false;
  DateTime? _masterStartedAt;
  String? _deviceId;
  String? _clientDeviceName;
  Map<String, Map<String, dynamic>> _authorizedDevices = {};
  final Map<String, _LoginChallenge> _loginChallenges = {};
  final Map<String, _MasterUserSession> _userSessions = {};
  final Map<String, List<DateTime>> _failedLoginAttempts = {};
  LanRemoteUser? _remoteUser;
  String? _remoteSessionToken;

  LanNetworkSnapshot get snapshot => _snapshot;
  LanRemoteUser? get remoteUser => _remoteUser;
  bool get hasRemoteUserSession =>
      _remoteUser != null && _remoteSessionToken != null;
  Stream<LanNetworkSnapshot> get changes => _controller.stream;
  Stream<LanMasterActivityEvent> get masterActivityEvents =>
      _masterActivityController.stream;

  Future<void> initialize() async {
    _deviceId = await _loadOrCreateDeviceId();
    _clientDeviceName = await _settingsDao.getSetting(_clientDeviceNameKey);
    await _loadAuthorizedDevices();

    final storedMode = await _settingsDao.getSetting(_modeKey);
    final mode = LanMode.values.firstWhere(
      (item) => item.name == storedMode,
      orElse: () => LanMode.standalone,
    );
    final port =
        int.tryParse(await _settingsDao.getSetting(_portKey) ?? '') ??
        defaultPort;

    if (mode == LanMode.master) {
      try {
        await startMaster(port: port);
      } catch (_) {
        // Keep the app usable and expose the bind error on the settings screen.
      }
      return;
    }

    if (mode == LanMode.client) {
      final host = await _settingsDao.getSetting(_masterHostKey);
      final masterId = await _settingsDao.getSetting(_masterIdKey);
      _emit(
        LanNetworkSnapshot(
          mode: LanMode.client,
          status: LanConnectionStatus.connecting,
          port: port,
          masterHost: host,
          masterId: masterId,
        ),
      );
      _startClientMonitor();
      // Do not hold application startup behind a stale DHCP address.
      // Reconnection continues in the background and can discover the same
      // authorized master at its new local address.
      unawaited(_runClientMonitorCheck());
    }
  }

  Future<void> setStandalone() async {
    if (_snapshot.mode == LanMode.client) {
      await logoutFromMaster();
    }
    await stop();
    await _settingsDao.saveSetting(_modeKey, LanMode.standalone.name);
    await _settingsDao.saveSetting(_clientTokenKey, '');
    _emit(const LanNetworkSnapshot());
  }

  Future<void> startMaster({int port = defaultPort}) async {
    if (port != 0 && (port < 1024 || port > 65535)) {
      throw ArgumentError.value(port, 'port', 'Must be between 1024 and 65535');
    }

    await stop();
    _emit(
      LanNetworkSnapshot(
        mode: LanMode.master,
        status: LanConnectionStatus.starting,
        port: port,
      ),
    );

    try {
      _server = await HttpServer.bind(
        InternetAddress.anyIPv4,
        port,
        shared: false,
      );
      _server!.idleTimeout = const Duration(seconds: 20);
      _server!.listen(_handleRequest, onError: _handleServerError);
      _masterStartedAt = DateTime.now().toUtc();

      final addresses = await _localIpv4Addresses();
      final boundPort = _server!.port;
      final pairingCode = _newPairingCode();
      await _settingsDao.saveSetting(_modeKey, LanMode.master.name);
      await _settingsDao.saveSetting(_portKey, boundPort.toString());
      await _startAndroidMasterKeepAlive(boundPort);
      _emit(
        LanNetworkSnapshot(
          mode: LanMode.master,
          status: LanConnectionStatus.online,
          addresses: addresses,
          port: boundPort,
          pairingCode: pairingCode,
          masterId: _deviceId,
          pairedDevices: _authorizedDevices.length,
          connectedDevices: _connectedDeviceCount(),
        ),
      );
      if (port != 0) await _startMasterDiscovery();
      _startMasterMonitor();
    } catch (error) {
      final server = _server;
      _server = null;
      _masterStartedAt = null;
      await server?.close(force: true);
      _masterMonitorTimer?.cancel();
      _masterMonitorTimer = null;
      _discoverySocket?.close();
      _discoverySocket = null;
      await _stopAndroidMasterKeepAlive();
      _emit(
        LanNetworkSnapshot(
          mode: LanMode.master,
          status: LanConnectionStatus.error,
          port: port,
          error: error.toString(),
        ),
      );
      rethrow;
    }
  }

  Future<LanPairResult> pairWithMaster({
    required String host,
    required int port,
    required String pairingCode,
    required String deviceName,
  }) async {
    final cleanHost = _normalizeHost(host);
    if (cleanHost.isEmpty || pairingCode.trim().length != 6) {
      return const LanPairResult.failure('Invalid address or pairing code.');
    }

    if (_snapshot.mode == LanMode.client && hasRemoteUserSession) {
      await logoutFromMaster();
    }
    await stop();
    _emit(
      LanNetworkSnapshot(
        mode: LanMode.client,
        status: LanConnectionStatus.connecting,
        masterHost: cleanHost,
        port: port,
      ),
    );

    try {
      final health = await _jsonRequest(
        method: 'GET',
        host: cleanHost,
        port: port,
        path: '/v1/health',
      );
      if (health.statusCode != HttpStatus.ok ||
          health.body['protocolVersion'] != protocolVersion) {
        throw const FormatException('Incompatible Tapix master.');
      }
      final masterLocaleCode = _validLocaleCode(
        health.body['localeCode']?.toString(),
      );

      final pair = await _jsonRequest(
        method: 'POST',
        host: cleanHost,
        port: port,
        path: '/v1/pair',
        body: {
          'pairingCode': pairingCode.trim(),
          'deviceId': _deviceId,
          'deviceName': deviceName.trim().isEmpty
              ? 'Tapix device'
              : deviceName.trim(),
          'platform': Platform.operatingSystem,
        },
      );
      if (pair.statusCode != HttpStatus.ok) {
        final message = pair.body['message']?.toString();
        throw StateError(message ?? 'Pairing rejected.');
      }

      final token = pair.body['token']?.toString();
      final masterId = pair.body['masterId']?.toString();
      if (token == null || token.isEmpty || masterId == null) {
        throw const FormatException('Invalid pairing response.');
      }

      await _settingsDao.saveSetting(_modeKey, LanMode.client.name);
      await _settingsDao.saveSetting(_masterHostKey, cleanHost);
      await _settingsDao.saveSetting(_portKey, port.toString());
      await _settingsDao.saveSetting(_masterIdKey, masterId);
      await _settingsDao.saveSetting(_clientTokenKey, token);
      _clientDeviceName = deviceName.trim().isEmpty
          ? 'Tapix device'
          : deviceName.trim();
      await _settingsDao.saveSetting(_clientDeviceNameKey, _clientDeviceName!);

      _emit(
        LanNetworkSnapshot(
          mode: LanMode.client,
          status: LanConnectionStatus.paired,
          masterHost: cleanHost,
          masterId: masterId,
          masterLocaleCode:
              _validLocaleCode(pair.body['localeCode']?.toString()) ??
              masterLocaleCode,
          port: port,
        ),
      );
      _startClientMonitor();
      return LanPairResult.success(masterId);
    } catch (error) {
      _emit(
        LanNetworkSnapshot(
          mode: LanMode.client,
          status: LanConnectionStatus.error,
          masterHost: cleanHost,
          port: port,
          error: error.toString(),
        ),
      );
      return LanPairResult.failure(error.toString());
    }
  }

  Future<LanRemoteLoginResult> loginToMaster({
    required String username,
    required String password,
    bool rememberMe = false,
  }) async {
    final host =
        _snapshot.masterHost ?? await _settingsDao.getSetting(_masterHostKey);
    final deviceToken = await _settingsDao.getSetting(_clientTokenKey);
    final deviceId = _deviceId;
    if (_snapshot.mode != LanMode.client ||
        host == null ||
        deviceToken == null ||
        deviceId == null) {
      return const LanRemoteLoginResult.failure(
        'Connect this device to the master first.',
      );
    }

    try {
      final challenge = await _jsonRequest(
        method: 'POST',
        host: host,
        port: _snapshot.port,
        path: '/v1/auth/challenge',
        token: deviceToken,
        body: {'username': username.trim()},
      );
      if (challenge.statusCode != HttpStatus.ok) {
        return LanRemoteLoginResult.failure(
          challenge.body['message']?.toString() ??
              'Invalid username or password.',
        );
      }

      final challengeId = challenge.body['challengeId']?.toString();
      final nonce = challenge.body['nonce']?.toString();
      final salt = challenge.body['salt']?.toString();
      if (challengeId == null || nonce == null || salt == null) {
        throw const FormatException('Invalid authentication challenge.');
      }

      // The password itself never crosses the LAN. bcrypt derives the same
      // verifier held by the master, then HMAC binds proof to this one-time
      // challenge and this paired device.
      final verifier = BCrypt.hashpw(password, salt);
      final proof = Hmac(
        sha256,
        utf8.encode(verifier),
      ).convert(utf8.encode('$challengeId:$nonce:$deviceId')).toString();

      final response = await _jsonRequest(
        method: 'POST',
        host: host,
        port: _snapshot.port,
        path: '/v1/auth/login',
        token: deviceToken,
        body: {
          'challengeId': challengeId,
          'proof': proof,
          'rememberMe': rememberMe,
        },
      );
      if (response.statusCode != HttpStatus.ok) {
        return LanRemoteLoginResult.failure(
          response.body['message']?.toString() ??
              'Invalid username or password.',
        );
      }

      final sessionToken = response.body['sessionToken']?.toString();
      final userJson = response.body['user'];
      if (sessionToken == null ||
          sessionToken.isEmpty ||
          userJson is! Map<String, dynamic>) {
        throw const FormatException('Invalid login response.');
      }

      final user = LanRemoteUser.fromJson(userJson);
      _remoteSessionToken = sessionToken;
      _remoteUser = user;
      _emit(_snapshot.copyWith(clearError: true));
      return LanRemoteLoginResult.success(user);
    } catch (_) {
      return const LanRemoteLoginResult.failure(
        'Unable to authenticate with the master.',
      );
    }
  }

  Future<void> logoutFromMaster() async {
    final host =
        _snapshot.masterHost ?? await _settingsDao.getSetting(_masterHostKey);
    final deviceToken = await _settingsDao.getSetting(_clientTokenKey);
    final sessionToken = _remoteSessionToken;
    try {
      if (host != null && deviceToken != null && sessionToken != null) {
        await _jsonRequest(
          method: 'POST',
          host: host,
          port: _snapshot.port,
          path: '/v1/auth/logout',
          token: deviceToken,
          userToken: sessionToken,
        );
      }
    } catch (_) {
      // Signing out is local-first. A remote logout may race with an owner
      // ending the same session or with a temporary Wi-Fi interruption. In
      // both cases the local identity must still be cleared without showing a
      // false authentication error.
    } finally {
      _remoteSessionToken = null;
      _remoteUser = null;
      _emit(_snapshot.copyWith(clearError: true));
    }
  }

  Future<bool> validateRemoteSession() async {
    final host =
        _snapshot.masterHost ?? await _settingsDao.getSetting(_masterHostKey);
    final deviceToken = await _settingsDao.getSetting(_clientTokenKey);
    final sessionToken = _remoteSessionToken;
    if (host == null || deviceToken == null || sessionToken == null) {
      return false;
    }
    try {
      final response = await _jsonRequest(
        method: 'GET',
        host: host,
        port: _snapshot.port,
        path: '/v1/auth/session',
        token: deviceToken,
        userToken: sessionToken,
      );
      if (response.statusCode != HttpStatus.ok) {
        _remoteSessionToken = null;
        _remoteUser = null;
        _emit(_snapshot.copyWith(clearError: true));
        return false;
      }
      final userJson = response.body['user'];
      if (userJson is! Map<String, dynamic>) return false;
      _remoteUser = LanRemoteUser.fromJson(userJson);
      return true;
    } catch (_) {
      // A transient network failure is not proof that the master revoked the
      // session. Keep it in memory but deny network operations until retry.
      return false;
    }
  }

  Future<LanCatalogPage> fetchRemoteCatalog({
    String query = '',
    int offset = 0,
    int limit = 100,
    bool management = false,
  }) async {
    final response = await _authenticatedClientRequest(
      method: 'GET',
      path: '/v1/catalog',
      queryParameters: {
        'q': query,
        'offset': offset.toString(),
        'limit': limit.toString(),
        if (management) 'view': 'management',
      },
    );
    return LanCatalogPage.fromJson(response.body);
  }

  Future<LanMedicineAlternativesResult> fetchRemoteMedicineAlternatives(
    int productId,
  ) async {
    if (productId <= 0) {
      throw const LanBusinessException(
        'invalid_product',
        'A valid product is required.',
      );
    }
    final response = await _authenticatedClientRequest(
      method: 'GET',
      path: '/v1/pharmacy/alternatives/$productId',
    );
    return LanMedicineAlternativesResult.fromJson(response.body);
  }

  Future<Uint8List?> fetchRemoteProductImage(int productId) async {
    final host =
        _snapshot.masterHost ?? await _settingsDao.getSetting(_masterHostKey);
    final deviceToken = await _settingsDao.getSetting(_clientTokenKey);
    final sessionToken = _remoteSessionToken;
    if (host == null || deviceToken == null || sessionToken == null) {
      throw const LanBusinessException(
        'authentication_required',
        'Sign in to the master first.',
        statusCode: 401,
      );
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client
          .getUrl(
            Uri(
              scheme: 'http',
              host: host,
              port: _snapshot.port,
              path: '/v1/catalog/images/$productId',
            ),
          )
          .timeout(const Duration(seconds: 6));
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer $deviceToken',
      );
      request.headers.set(_userSessionHeader, sessionToken);
      final response = await request.close().timeout(
        const Duration(seconds: 8),
      );
      if (response.statusCode == HttpStatus.notFound) return null;
      if (response.statusCode == HttpStatus.unauthorized) {
        _remoteSessionToken = null;
        _remoteUser = null;
        throw const LanBusinessException(
          'authentication_required',
          'Sign in to the master first.',
          statusCode: 401,
        );
      }
      if (response.statusCode != HttpStatus.ok) {
        throw LanBusinessException(
          'product_image_failed',
          'Unable to load the product image from the master.',
          statusCode: response.statusCode,
        );
      }
      const maxBytes = 8 * 1024 * 1024;
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response) {
        if (bytes.length + chunk.length > maxBytes) {
          throw const LanBusinessException(
            'product_image_too_large',
            'The product image is too large.',
          );
        }
        bytes.add(chunk);
      }
      return bytes.takeBytes();
    } finally {
      client.close(force: true);
    }
  }

  Future<LanSalesPage> fetchRemoteSales({int limit = 500}) async {
    final response = await _authenticatedClientRequest(
      method: 'GET',
      path: '/v1/sales',
      queryParameters: {'limit': limit.toString()},
    );
    return LanSalesPage.fromJson(response.body);
  }

  Future<LanSaleDetails> fetchRemoteSaleDetails(int saleId) async {
    final response = await _authenticatedClientRequest(
      method: 'GET',
      path: '/v1/sales/$saleId',
    );
    return LanSaleDetails.fromJson(response.body);
  }

  Future<LanSaleVoidResult> voidRemoteSale(int saleId) async {
    final response = await _authenticatedClientRequest(
      method: 'POST',
      path: '/v1/sales/$saleId/void',
    );
    return LanSaleVoidResult.fromJson(response.body);
  }

  Future<List<LanCustomerSummary>> fetchRemoteCustomers({
    String query = '',
    int limit = 100,
  }) async {
    final response = await _authenticatedClientRequest(
      method: 'GET',
      path: '/v1/customers',
      queryParameters: {'q': query, 'limit': limit.toString()},
    );
    return (response.body['customers'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(LanCustomerSummary.fromJson)
        .toList(growable: false);
  }

  Future<List<LanEmployeeSummary>> fetchRemoteSalespeople({
    String query = '',
    int limit = 100,
  }) async {
    final response = await _authenticatedClientRequest(
      method: 'GET',
      path: '/v1/salespeople',
      queryParameters: {'q': query, 'limit': limit.toString()},
    );
    return (response.body['employees'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(LanEmployeeSummary.fromJson)
        .toList(growable: false);
  }

  Future<LanReturnableSalesPage> fetchRemoteReturnableSales({
    String query = '',
    int offset = 0,
    int limit = 50,
  }) async {
    final response = await _authenticatedClientRequest(
      method: 'GET',
      path: '/v1/sales/returnable',
      queryParameters: {
        'q': query,
        'offset': offset.toString(),
        'limit': limit.toString(),
      },
    );
    return LanReturnableSalesPage.fromJson(response.body);
  }

  Future<LanReturnableSaleDetails> fetchRemoteReturnableSale(int saleId) async {
    final response = await _authenticatedClientRequest(
      method: 'GET',
      path: '/v1/sales/$saleId/returnable',
    );
    return LanReturnableSaleDetails.fromJson(response.body);
  }

  Future<LanSaleReturnsPage> fetchRemoteSaleReturns({
    String query = '',
    int offset = 0,
    int limit = 100,
  }) async {
    final response = await _authenticatedClientRequest(
      method: 'GET',
      path: '/v1/sale-returns',
      queryParameters: {
        'q': query,
        'offset': offset.toString(),
        'limit': limit.toString(),
      },
    );
    return LanSaleReturnsPage.fromJson(response.body);
  }

  Future<LanSaleReturnDetails> fetchRemoteSaleReturnDetails({
    required int returnId,
    required bool adjustment,
  }) async {
    if (returnId <= 0) {
      throw const LanBusinessException(
        'invalid_sale_return',
        'A valid sale return is required.',
      );
    }
    final response = await _authenticatedClientRequest(
      method: 'GET',
      path:
          '/v1/sale-returns/${adjustment ? 'adjustment' : 'linked'}/$returnId',
    );
    return LanSaleReturnDetails.fromJson(response.body);
  }

  Future<LanSaleReturnResult> submitRemoteSaleReturn(
    LanSaleReturnRequest saleReturn,
  ) async {
    final response = await _authenticatedClientRequest(
      method: 'POST',
      path: '/v1/sale-returns',
      body: saleReturn.toJson(),
    );
    return LanSaleReturnResult.fromJson(response.body);
  }

  Future<LanSaleReturnResult> submitRemoteSaleAdjustmentReturn(
    LanSaleAdjustmentReturnRequest saleReturn,
  ) async {
    final response = await _authenticatedClientRequest(
      method: 'POST',
      path: '/v1/sale-adjustment-returns',
      body: saleReturn.toJson(),
    );
    return LanSaleReturnResult.fromJson(response.body);
  }

  Future<List<LanSupplierSummary>> fetchRemoteSuppliers({
    String query = '',
    int limit = 100,
  }) async {
    final response = await _authenticatedClientRequest(
      method: 'GET',
      path: '/v1/suppliers',
      queryParameters: {'q': query, 'limit': limit.toString()},
    );
    return (response.body['suppliers'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(LanSupplierSummary.fromJson)
        .toList(growable: false);
  }

  Future<LanReturnablePurchasesPage> fetchRemoteReturnablePurchases({
    String query = '',
    int offset = 0,
    int limit = 50,
  }) async {
    final response = await _authenticatedClientRequest(
      method: 'GET',
      path: '/v1/purchases/returnable',
      queryParameters: {
        'q': query,
        'offset': offset.toString(),
        'limit': limit.toString(),
      },
    );
    return LanReturnablePurchasesPage.fromJson(response.body);
  }

  Future<LanReturnablePurchaseDetails> fetchRemoteReturnablePurchase(
    int purchaseId,
  ) async {
    final response = await _authenticatedClientRequest(
      method: 'GET',
      path: '/v1/purchases/$purchaseId/returnable',
    );
    return LanReturnablePurchaseDetails.fromJson(response.body);
  }

  Future<LanPurchaseReturnsPage> fetchRemotePurchaseReturns({
    String query = '',
    int offset = 0,
    int limit = 100,
  }) async {
    final response = await _authenticatedClientRequest(
      method: 'GET',
      path: '/v1/purchase-returns',
      queryParameters: {
        'q': query,
        'offset': offset.toString(),
        'limit': limit.toString(),
      },
    );
    return LanPurchaseReturnsPage.fromJson(response.body);
  }

  Future<LanPurchaseReturnDetails> fetchRemotePurchaseReturnDetails({
    required int returnId,
    required bool adjustment,
  }) async {
    final response = await _authenticatedClientRequest(
      method: 'GET',
      path:
          '/v1/purchase-returns/${adjustment ? 'adjustment' : 'linked'}/$returnId',
    );
    return LanPurchaseReturnDetails.fromJson(response.body);
  }

  Future<LanPurchaseReturnResult> submitRemotePurchaseReturn(
    LanPurchaseReturnRequest purchaseReturn,
  ) async {
    final response = await _authenticatedClientRequest(
      method: 'POST',
      path: '/v1/purchase-returns',
      body: purchaseReturn.toJson(),
    );
    return LanPurchaseReturnResult.fromJson(response.body);
  }

  Future<LanPurchaseReturnResult> submitRemotePurchaseAdjustmentReturn(
    LanPurchaseAdjustmentReturnRequest purchaseReturn,
  ) async {
    final response = await _authenticatedClientRequest(
      method: 'POST',
      path: '/v1/purchase-adjustment-returns',
      body: purchaseReturn.toJson(),
    );
    return LanPurchaseReturnResult.fromJson(response.body);
  }

  Future<void> voidRemotePurchaseReturn({
    required int returnId,
    required bool adjustment,
  }) async {
    await _authenticatedClientRequest(
      method: 'POST',
      path:
          '/v1/purchase-returns/${adjustment ? 'adjustment' : 'linked'}/$returnId/void',
    );
  }

  Future<LanCashierShiftSnapshot?> fetchOwnRemoteShift() async {
    final response = await _authenticatedClientRequest(
      method: 'GET',
      path: '/v1/shifts/current',
    );
    final raw = response.body['shift'];
    return raw is Map<String, dynamic>
        ? LanCashierShiftSnapshot.fromJson(raw)
        : null;
  }

  Future<LanCashierShiftSnapshot> openOwnRemoteShift({
    required int openingCashCents,
    String? notes,
  }) async {
    final response = await _authenticatedClientRequest(
      method: 'POST',
      path: '/v1/shifts/open',
      body: {'openingCashCents': openingCashCents, 'notes': notes},
    );
    return LanCashierShiftSnapshot.fromJson(
      response.body['shift'] as Map<String, dynamic>,
    );
  }

  Future<LanCashierShiftSnapshot> closeOwnRemoteShift({
    required int countedCashCents,
    String? notes,
  }) async {
    final response = await _authenticatedClientRequest(
      method: 'POST',
      path: '/v1/shifts/close',
      body: {'countedCashCents': countedCashCents, 'notes': notes},
    );
    return LanCashierShiftSnapshot.fromJson(
      response.body['shift'] as Map<String, dynamic>,
    );
  }

  Future<LanSaleResult> submitRemoteSale(LanSaleRequest sale) async {
    if (_remoteUser?.role == 'cashier') {
      final shift = await fetchOwnRemoteShift();
      if (shift?.isOpen != true) {
        throw const LanBusinessException(
          'shift_required',
          'Open your cashier shift before starting a sale.',
          statusCode: 409,
        );
      }
    }
    final response = await _authenticatedClientRequest(
      method: 'POST',
      path: '/v1/sales',
      body: sale.toJson(),
    );
    return LanSaleResult.fromJson(response.body);
  }

  Future<_JsonResponse> _authenticatedClientRequest({
    required String method,
    required String path,
    Map<String, String>? queryParameters,
    Map<String, dynamic>? body,
  }) async {
    final host =
        _snapshot.masterHost ?? await _settingsDao.getSetting(_masterHostKey);
    final deviceToken = await _settingsDao.getSetting(_clientTokenKey);
    final sessionToken = _remoteSessionToken;
    if (host == null || deviceToken == null || sessionToken == null) {
      throw const LanBusinessException(
        'authentication_required',
        'Sign in to the master first.',
        statusCode: 401,
      );
    }
    final response = await _jsonRequest(
      method: method,
      host: host,
      port: _snapshot.port,
      path: path,
      queryParameters: queryParameters,
      token: deviceToken,
      userToken: sessionToken,
      body: body,
    );
    if (response.statusCode == HttpStatus.unauthorized) {
      _remoteSessionToken = null;
      _remoteUser = null;
      _emit(_snapshot.copyWith(clearError: true));
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw LanBusinessException(
        response.body['code']?.toString() ?? 'remote_request_failed',
        response.body['message']?.toString() ?? 'Master request failed.',
        statusCode: response.statusCode,
        details: response.body['details'] is Map
            ? Map<String, dynamic>.from(response.body['details'] as Map)
            : const {},
      );
    }
    return response;
  }

  Future<bool> testConnection({String? host, int? port}) async {
    var targetHost = _normalizeHost(
      host ??
          _snapshot.masterHost ??
          await _settingsDao.getSetting(_masterHostKey) ??
          '',
    );
    var targetPort = port ?? _snapshot.port;
    final token = await _settingsDao.getSetting(_clientTokenKey);
    if (targetHost.isEmpty || token == null || token.isEmpty) return false;

    Future<_JsonResponse> requestStatus() async {
      final response = await _jsonRequest(
        method: 'GET',
        host: targetHost,
        port: targetPort,
        path: '/v1/status',
        token: token,
      );
      if (response.statusCode != HttpStatus.ok) {
        if (response.statusCode == HttpStatus.unauthorized) {
          _remoteSessionToken = null;
          _remoteUser = null;
          _emit(_snapshot.copyWith(clearError: true));
        }
        throw StateError('Master rejected this device.');
      }
      return response;
    }

    Object? lastError;
    _JsonResponse? response;
    try {
      response = await requestStatus();
    } catch (error) {
      lastError = error;
      final expectedMasterId =
          _snapshot.masterId ?? await _settingsDao.getSetting(_masterIdKey);
      if (expectedMasterId != null && expectedMasterId.isNotEmpty) {
        final discovered = await _discoverMaster(
          expectedMasterId,
          preferredPort: targetPort,
        );
        if (discovered != null) {
          targetHost = discovered.host;
          targetPort = discovered.port;
          try {
            response = await requestStatus();
          } catch (retryError) {
            lastError = retryError;
          }
        }
      }
    }

    if (response != null) {
      await _settingsDao.saveSetting(_masterHostKey, targetHost);
      await _settingsDao.saveSetting(_portKey, targetPort.toString());
      final responseMasterId = response.body['masterId']?.toString();
      if (responseMasterId != null && responseMasterId.isNotEmpty) {
        await _settingsDao.saveSetting(_masterIdKey, responseMasterId);
      }
      _emit(
        _snapshot.copyWith(
          mode: LanMode.client,
          status: LanConnectionStatus.paired,
          masterHost: targetHost,
          port: targetPort,
          masterId: responseMasterId,
          masterLocaleCode: _validLocaleCode(
            response.body['localeCode']?.toString(),
          ),
          clearError: true,
        ),
      );
      if (_remoteSessionToken != null) {
        await validateRemoteSession();
      }
      return true;
    }

    _emit(
      _snapshot.copyWith(
        mode: LanMode.client,
        status: LanConnectionStatus.error,
        masterHost: targetHost,
        port: targetPort,
        error: lastError?.toString() ?? 'Master is not reachable.',
      ),
    );
    return false;
  }

  Future<void> refreshMasterNetwork() async {
    if (_snapshot.mode != LanMode.master ||
        _server == null ||
        _masterRefreshInFlight) {
      return;
    }
    _masterRefreshInFlight = true;
    try {
      final addresses = await _localIpv4Addresses();
      final connectedDevices = _connectedDeviceCount();
      final addressChanged =
          addresses.length != _snapshot.addresses.length ||
          !addresses.asMap().entries.every(
            (entry) => _snapshot.addresses[entry.key] == entry.value,
          );
      if (addressChanged || connectedDevices != _snapshot.connectedDevices) {
        _emit(
          _snapshot.copyWith(
            addresses: addresses,
            connectedDevices: connectedDevices,
          ),
        );
      }
    } on SocketException {
      // Network interfaces can disappear briefly while Wi-Fi reconnects or
      // Android moves the app between foreground/background states. The
      // listener remains valid, so retry on the next monitor tick.
    } finally {
      _masterRefreshInFlight = false;
    }
  }

  void _startMasterMonitor() {
    _masterMonitorTimer?.cancel();
    unawaited(refreshMasterNetwork());
    _masterMonitorTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => unawaited(refreshMasterNetwork()),
    );
  }

  int _connectedDeviceCount() {
    final cutoff = DateTime.now().toUtc().subtract(const Duration(seconds: 45));
    final presenceBoundary = _masterStartedAt;
    return _authorizedDevices.values.where((device) {
      final lastSeen = DateTime.tryParse(
        device['lastSeenAt']?.toString() ?? '',
      );
      return lastSeen != null &&
          lastSeen.isAfter(cutoff) &&
          (presenceBoundary == null || lastSeen.isAfter(presenceBoundary));
    }).length;
  }

  Future<void> _startMasterDiscovery() async {
    _discoverySocket?.close();
    _discoverySocket = null;
    try {
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        discoveryPort,
        reuseAddress: true,
      );
      _discoverySocket = socket;
      socket.listen(
        (event) {
          if (event != RawSocketEvent.read) return;
          try {
            final datagram = socket.receive();
            if (datagram == null) return;
            final probe = utf8
                .decode(datagram.data, allowMalformed: true)
                .trim();
            if (probe != _discoveryProbe) return;
            final response = utf8.encode(
              jsonEncode({
                'app': 'Tapix',
                'protocolVersion': protocolVersion,
                'masterId': _deviceId,
                'port': _server?.port ?? _snapshot.port,
                'localeCode': _masterLocaleCode,
              }),
            );
            socket.send(response, datagram.address, datagram.port);
          } on SocketException {
            // A client may disappear between receiving the discovery probe and
            // sending the reply. Discovery is best-effort and direct IP access
            // remains available.
          }
        },
        onError: (Object _) {
          if (identical(_discoverySocket, socket)) {
            _discoverySocket = null;
          }
          socket.close();
        },
        cancelOnError: true,
      );
    } catch (_) {
      // Discovery is a convenience. Direct IP pairing remains available.
      _discoverySocket?.close();
      _discoverySocket = null;
    }
  }

  Future<_DiscoveredMaster?> _discoverMaster(
    String expectedMasterId, {
    required int preferredPort,
  }) async {
    RawDatagramSocket? socket;
    StreamSubscription<RawSocketEvent>? subscription;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;
      final completer = Completer<_DiscoveredMaster?>();
      subscription = socket.listen(
        (event) {
          if (event != RawSocketEvent.read || completer.isCompleted) return;
          final datagram = socket?.receive();
          if (datagram == null) return;
          try {
            final decoded = jsonDecode(utf8.decode(datagram.data));
            if (decoded is! Map<String, dynamic> ||
                decoded['app']?.toString() != 'Tapix' ||
                decoded['masterId']?.toString() != expectedMasterId) {
              return;
            }
            final discoveredPort = (decoded['port'] as num?)?.toInt();
            if (discoveredPort == null ||
                discoveredPort < 1 ||
                discoveredPort > 65535) {
              return;
            }
            completer.complete(
              _DiscoveredMaster(datagram.address.address, discoveredPort),
            );
          } catch (_) {
            // Ignore unrelated UDP traffic on the discovery response socket.
          }
        },
        onError: (Object _) {
          // Android reports broadcast send failures asynchronously through the
          // socket stream (for example while Wi-Fi is disabled). Complete this
          // best-effort phase normally instead of leaking a fatal zone error.
          if (!completer.isCompleted) completer.complete(null);
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete(null);
        },
        cancelOnError: true,
      );
      socket.send(
        utf8.encode(_discoveryProbe),
        InternetAddress('255.255.255.255'),
        discoveryPort,
      );
      final broadcastResult = await completer.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () => null,
      );
      if (broadcastResult != null) return broadcastResult;
    } catch (_) {
      // Some routers isolate or drop broadcast packets. Fall through to a
      // bounded local /24 scan and verify the master's persisted identity.
    } finally {
      await subscription?.cancel();
      socket?.close();
    }
    try {
      return await _scanLocalSubnetsForMaster(expectedMasterId, preferredPort);
    } on SocketException {
      // No active local interface is a normal offline state.
      return null;
    }
  }

  Future<_DiscoveredMaster?> _scanLocalSubnetsForMaster(
    String expectedMasterId,
    int port,
  ) async {
    final localAddresses = await _localIpv4Addresses();
    final candidates = <String>[];
    for (final local in localAddresses) {
      final parts = local.split('.');
      if (parts.length != 4) continue;
      final prefix = '${parts[0]}.${parts[1]}.${parts[2]}';
      for (var host = 1; host < 255; host++) {
        final candidate = '$prefix.$host';
        if (candidate != local && !candidates.contains(candidate)) {
          candidates.add(candidate);
        }
      }
    }

    const batchSize = 48;
    for (var offset = 0; offset < candidates.length; offset += batchSize) {
      final end = min(offset + batchSize, candidates.length);
      final results = await Future.wait(
        candidates
            .sublist(offset, end)
            .map((host) => _probeMasterIdentity(host, port, expectedMasterId)),
      );
      for (final result in results) {
        if (result != null) return result;
      }
    }
    return null;
  }

  Future<_DiscoveredMaster?> _probeMasterIdentity(
    String host,
    int port,
    String expectedMasterId,
  ) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(milliseconds: 350);
    try {
      final request = await client
          .getUrl(
            Uri(scheme: 'http', host: host, port: port, path: '/v1/health'),
          )
          .timeout(const Duration(milliseconds: 450));
      final response = await request.close().timeout(
        const Duration(milliseconds: 450),
      );
      if (response.statusCode != HttpStatus.ok) return null;
      final raw = await utf8.decoder
          .bind(response)
          .join()
          .timeout(const Duration(milliseconds: 450));
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic> &&
          decoded['app']?.toString() == 'Tapix' &&
          decoded['protocolVersion'] == protocolVersion &&
          decoded['masterId']?.toString() == expectedMasterId) {
        return _DiscoveredMaster(host, port);
      }
    } catch (_) {
      // An unreachable address is expected while scanning the local subnet.
    } finally {
      client.close(force: true);
    }
    return null;
  }

  Future<void> regeneratePairingCode() async {
    if (_snapshot.mode != LanMode.master || _server == null) return;
    _emit(_snapshot.copyWith(pairingCode: _newPairingCode(), clearError: true));
  }

  List<LanMasterDeviceInfo> getMasterDevices() {
    if (_snapshot.mode != LanMode.master) return const [];
    final now = DateTime.now().toUtc();
    final cutoff = now.subtract(const Duration(seconds: 45));
    final presenceBoundary = _masterStartedAt;
    final devices = _authorizedDevices.entries
        .map((entry) {
          _MasterUserSession? activeSession;
          for (final session in _userSessions.values) {
            if (session.deviceId == entry.key &&
                now.isBefore(session.expiresAt)) {
              activeSession = session;
              break;
            }
          }
          final data = entry.value;
          final lastSeenAt = DateTime.tryParse(
            data['lastSeenAt']?.toString() ?? '',
          );
          return LanMasterDeviceInfo(
            id: entry.key,
            name: data['name']?.toString() ?? 'Tapix device',
            platform: data['platform']?.toString() ?? 'unknown',
            remoteAddress: data['lastAddress']?.toString(),
            pairedAt: DateTime.tryParse(data['pairedAt']?.toString() ?? ''),
            lastSeenAt: lastSeenAt,
            isConnected:
                lastSeenAt != null &&
                lastSeenAt.isAfter(cutoff) &&
                (presenceBoundary == null ||
                    lastSeenAt.isAfter(presenceBoundary)),
            userId: activeSession?.user.id,
            username: activeSession?.user.username,
            userRole: activeSession?.user.role,
            employeeName: activeSession?.user.employeeName,
            sessionStartedAt: activeSession?.signedInAt,
            sessionExpiresAt: activeSession?.expiresAt,
          );
        })
        .toList(growable: false);
    return devices..sort((a, b) {
      if (a.isConnected != b.isConnected) return a.isConnected ? -1 : 1;
      final aSeen = a.lastSeenAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bSeen = b.lastSeenAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bSeen.compareTo(aSeen);
    });
  }

  Future<bool> logoutMasterDevice({
    required String deviceId,
    required int actorUserId,
    required String actorUsername,
    required String reason,
  }) async {
    final device = _authorizedDevices[deviceId];
    if (_snapshot.mode != LanMode.master || device == null) return false;
    final sessions = _userSessions.entries
        .where((entry) => entry.value.deviceId == deviceId)
        .toList(growable: false);
    // Idempotent success: a client heartbeat may notice an expired session at
    // the same moment the owner presses this action. The requested end state
    // (no active user session) is already satisfied.
    if (sessions.isEmpty) {
      _emit(_snapshot.copyWith(clearError: true));
      return true;
    }
    for (final entry in sessions) {
      _userSessions.remove(entry.key);
      final session = entry.value;
      await _recordSecurityEventSafe(
        LanAuthAuditEvent(
          action: 'device_remote_logout',
          targetUserId: session.user.id,
          username: session.user.username,
          role: session.user.role,
          deviceId: deviceId,
          deviceName: device['name']?.toString() ?? 'Tapix device',
          remoteAddress: device['lastAddress']?.toString(),
          actorUserId: actorUserId,
          actorUsername: actorUsername,
          reason: reason.trim(),
        ),
      );
    }
    _emit(_snapshot.copyWith(clearError: true));
    return true;
  }

  Future<bool> renameMasterDevice({
    required String deviceId,
    required String name,
    required int actorUserId,
    required String actorUsername,
  }) async {
    final device = _authorizedDevices[deviceId];
    final cleanName = name.trim();
    if (_snapshot.mode != LanMode.master ||
        device == null ||
        cleanName.isEmpty ||
        cleanName.length > 80) {
      return false;
    }
    final oldName = device['name']?.toString() ?? 'Tapix device';
    if (oldName == cleanName) return true;
    device['name'] = cleanName;
    await _saveAuthorizedDevices();
    final session = _sessionForDevice(deviceId);
    await _recordSecurityEventSafe(
      LanAuthAuditEvent(
        action: 'device_renamed',
        targetUserId: session?.user.id,
        username: session?.user.username,
        role: session?.user.role,
        deviceId: deviceId,
        deviceName: cleanName,
        remoteAddress: device['lastAddress']?.toString(),
        actorUserId: actorUserId,
        actorUsername: actorUsername,
        reason: '$oldName → $cleanName',
      ),
    );
    _emit(_snapshot.copyWith(clearError: true));
    return true;
  }

  Future<bool> revokeMasterDevice({
    required String deviceId,
    required int actorUserId,
    required String actorUsername,
    required String reason,
  }) async {
    if (_snapshot.mode != LanMode.master) return false;
    final device = _authorizedDevices.remove(deviceId);
    if (device == null) return false;
    final sessions = _userSessions.entries
        .where((entry) => entry.value.deviceId == deviceId)
        .toList(growable: false);
    for (final entry in sessions) {
      _userSessions.remove(entry.key);
    }
    final session = sessions.isEmpty ? null : sessions.first.value;
    _loginChallenges.removeWhere((_, value) => value.deviceId == deviceId);
    _failedLoginAttempts.removeWhere((key, _) => key.startsWith('$deviceId:'));
    await _saveAuthorizedDevices();
    await _recordSecurityEventSafe(
      LanAuthAuditEvent(
        action: 'device_revoked',
        targetUserId: session?.user.id,
        username: session?.user.username,
        role: session?.user.role,
        deviceId: deviceId,
        deviceName: device['name']?.toString() ?? 'Tapix device',
        remoteAddress: device['lastAddress']?.toString(),
        actorUserId: actorUserId,
        actorUsername: actorUsername,
        reason: reason.trim(),
      ),
    );
    _emit(
      _snapshot.copyWith(
        pairedDevices: _authorizedDevices.length,
        connectedDevices: _connectedDeviceCount(),
        clearError: true,
      ),
    );
    return true;
  }

  _MasterUserSession? _sessionForDevice(String deviceId) {
    final now = DateTime.now().toUtc();
    for (final session in _userSessions.values) {
      if (session.deviceId == deviceId && now.isBefore(session.expiresAt)) {
        return session;
      }
    }
    return null;
  }

  Future<void> stop() async {
    _monitorTimer?.cancel();
    _monitorTimer = null;
    _masterMonitorTimer?.cancel();
    _masterMonitorTimer = null;
    _discoverySocket?.close();
    _discoverySocket = null;
    final server = _server;
    _server = null;
    _masterStartedAt = null;
    await server?.close(force: true);
    await _stopAndroidMasterKeepAlive();
  }

  Future<void> _startAndroidMasterKeepAlive(int port) async {
    if (!Platform.isAndroid) return;
    await _masterKeepAliveChannel.invokeMethod<void>('start', {'port': port});
  }

  Future<void> _stopAndroidMasterKeepAlive() async {
    if (!Platform.isAndroid) return;
    try {
      await _masterKeepAliveChannel.invokeMethod<void>('stop');
    } on MissingPluginException {
      // Native keep-alive is Android-only and may be unavailable in unit tests.
    }
  }

  void _startClientMonitor() {
    _monitorTimer?.cancel();
    _monitorTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => unawaited(_runClientMonitorCheck()),
    );
  }

  Future<void> _runClientMonitorCheck() async {
    if (_clientMonitorInFlight || _snapshot.mode != LanMode.client) return;
    _clientMonitorInFlight = true;
    try {
      await testConnection();
    } on Object catch (error) {
      // Reconnection is background best-effort work. A transient socket,
      // interface, or platform failure must never escape into the app's fatal
      // error zone; expose it as connection state and retry on the next tick.
      _emit(
        _snapshot.copyWith(
          status: LanConnectionStatus.error,
          error: error.toString(),
        ),
      );
    } finally {
      _clientMonitorInFlight = false;
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    request.response.headers
      ..contentType = ContentType.json
      ..set('Cache-Control', 'no-store')
      ..set('X-Content-Type-Options', 'nosniff');

    try {
      if (request.method == 'OPTIONS') {
        request.response.statusCode = HttpStatus.noContent;
        await request.response.close();
        return;
      }

      final path = request.uri.path;
      if (request.method == 'GET' && path == '/v1/health') {
        await _respond(request, HttpStatus.ok, {
          'app': 'Tapix',
          'role': 'master',
          'protocolVersion': protocolVersion,
          'masterId': _deviceId,
          'pairingAvailable': _snapshot.pairingCode != null,
          'localeCode': _masterLocaleCode,
        });
        return;
      }

      if (request.method == 'POST' && path == '/v1/pair') {
        final body = await _readJson(request);
        if (body['pairingCode']?.toString() != _snapshot.pairingCode) {
          await _respond(request, HttpStatus.forbidden, {
            'message': 'Invalid pairing code.',
          });
          return;
        }

        final deviceId = body['deviceId']?.toString().trim() ?? '';
        if (deviceId.isEmpty) {
          await _respond(request, HttpStatus.badRequest, {
            'message': 'Missing device identity.',
          });
          return;
        }

        final token = _newToken();
        _authorizedDevices[deviceId] = {
          'name': body['deviceName']?.toString() ?? 'Tapix device',
          'platform': body['platform']?.toString() ?? 'unknown',
          'tokenHash': sha256.convert(utf8.encode(token)).toString(),
          'pairedAt': DateTime.now().toUtc().toIso8601String(),
          'lastSeenAt': DateTime.now().toUtc().toIso8601String(),
          'lastAddress': _remoteAddress(request),
        };
        await _saveAuthorizedDevices();
        await _recordSecurityEventSafe(
          LanAuthAuditEvent(
            action: 'device_paired',
            deviceId: deviceId,
            deviceName: body['deviceName']?.toString() ?? 'Tapix device',
            remoteAddress: _remoteAddress(request),
          ),
        );
        // Pairing codes are single-use. Rotating immediately prevents a code
        // seen by a previous cashier from enrolling another device later.
        _emit(
          _snapshot.copyWith(
            pairingCode: _newPairingCode(),
            pairedDevices: _authorizedDevices.length,
            connectedDevices: _connectedDeviceCount(),
          ),
        );
        await _respond(request, HttpStatus.ok, {
          'token': token,
          'masterId': _deviceId,
          'protocolVersion': protocolVersion,
          'localeCode': _masterLocaleCode,
        });
        return;
      }

      if (request.method == 'POST' && path == '/v1/auth/challenge') {
        final device = _authorizeDevice(request);
        if (device == null) {
          await _respond(request, HttpStatus.unauthorized, {
            'message': 'Device is not authorized.',
          });
          return;
        }
        if (_authGateway == null) {
          await _respond(request, HttpStatus.serviceUnavailable, {
            'message': 'Master authentication is not available.',
          });
          return;
        }

        final body = await _readJson(request);
        final username = body['username']?.toString().trim() ?? '';
        if (username.isEmpty || username.length > 128) {
          await _respond(request, HttpStatus.badRequest, {
            'message': 'Invalid username or password.',
          });
          return;
        }
        _pruneAuthState();
        if (_isRateLimited(device.id, username)) {
          await _recordSecurityEventSafe(
            LanAuthAuditEvent(
              action: 'login_rate_limited',
              username: username,
              deviceId: device.id,
              deviceName: device.name,
              remoteAddress: _remoteAddress(request),
              reason: 'Too many failed login attempts.',
            ),
          );
          await _respond(request, HttpStatus.tooManyRequests, {
            'message': 'Too many attempts. Try again later.',
          });
          return;
        }

        final account = await _authGateway.findActiveAccount(username);
        final salt = account != null && account.passwordHash.length >= 29
            ? account.passwordHash.substring(0, 29)
            : BCrypt.gensalt(logRounds: 12);
        final verifier =
            account?.passwordHash ?? BCrypt.hashpw(_newToken(), salt);
        final challengeId = const Uuid().v4();
        final nonce = _newToken();
        _loginChallenges[challengeId] = _LoginChallenge(
          id: challengeId,
          deviceId: device.id,
          username: username,
          nonce: nonce,
          verifier: verifier,
          account: account,
          expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 1)),
        );
        await _respond(request, HttpStatus.ok, {
          'challengeId': challengeId,
          'nonce': nonce,
          'salt': salt,
        });
        return;
      }

      if (request.method == 'POST' && path == '/v1/auth/login') {
        final device = _authorizeDevice(request);
        if (device == null) {
          await _respond(request, HttpStatus.unauthorized, {
            'message': 'Device is not authorized.',
          });
          return;
        }
        if (_authGateway == null) {
          await _respond(request, HttpStatus.serviceUnavailable, {
            'message': 'Master authentication is not available.',
          });
          return;
        }

        final body = await _readJson(request);
        final challengeId = body['challengeId']?.toString() ?? '';
        final proof = body['proof']?.toString() ?? '';
        final challenge = _loginChallenges.remove(challengeId);
        final now = DateTime.now().toUtc();
        var failureReason = 'Invalid challenge.';
        var valid =
            challenge != null &&
            challenge.deviceId == device.id &&
            now.isBefore(challenge.expiresAt);
        if (valid) {
          final expected = Hmac(sha256, utf8.encode(challenge.verifier))
              .convert(
                utf8.encode('$challengeId:${challenge.nonce}:${device.id}'),
              )
              .toString();
          valid =
              _constantTimeEquals(expected, proof) && challenge.account != null;
          failureReason = 'Invalid credentials.';
        }

        final challengeUsername = challenge?.username;
        final challengedAccount = valid ? challenge?.account : null;
        final currentAccount =
            valid && challengeUsername != null && challengedAccount != null
            ? await _authGateway.findActiveAccount(challengeUsername)
            : null;
        valid =
            currentAccount != null &&
            challengedAccount != null &&
            currentAccount.user.id == challengedAccount.user.id &&
            _constantTimeEquals(
              currentAccount.passwordHash,
              challengedAccount.passwordHash,
            );

        if (!valid) {
          final attemptedUsername = challenge?.username ?? '';
          _registerFailedAttempt(device.id, attemptedUsername);
          await _recordSecurityEventSafe(
            LanAuthAuditEvent(
              action: 'login_failed',
              targetUserId: challenge?.account?.user.id,
              username: attemptedUsername,
              role: challenge?.account?.user.role,
              deviceId: device.id,
              deviceName: device.name,
              remoteAddress: _remoteAddress(request),
              reason: failureReason,
            ),
          );
          await _respond(request, HttpStatus.unauthorized, {
            'message': 'Invalid username or password.',
          });
          return;
        }

        _clearFailedAttempts(device.id, currentAccount.user.username);
        await _replaceDeviceSessions(device);
        await _authGateway.markLoginSucceeded(currentAccount.user.id);

        final rawSessionToken = _newToken();
        final sessionHash = sha256
            .convert(utf8.encode(rawSessionToken))
            .toString();
        final rememberMe = body['rememberMe'] == true;
        final expiresAt = now.add(
          rememberMe ? const Duration(days: 7) : const Duration(hours: 12),
        );
        _userSessions[sessionHash] = _MasterUserSession(
          deviceId: device.id,
          user: currentAccount.user,
          signedInAt: now,
          expiresAt: expiresAt,
        );
        _emit(_snapshot.copyWith(clearError: true));
        await _recordSecurityEventSafe(
          LanAuthAuditEvent(
            action: 'login',
            targetUserId: currentAccount.user.id,
            username: currentAccount.user.username,
            role: currentAccount.user.role,
            deviceId: device.id,
            deviceName: device.name,
            remoteAddress: _remoteAddress(request),
            authenticatedActor: true,
          ),
        );
        await _respond(request, HttpStatus.ok, {
          'sessionToken': rawSessionToken,
          'expiresAt': expiresAt.toIso8601String(),
          'user': currentAccount.user.toJson(),
        });
        return;
      }

      if (request.method == 'GET' && path == '/v1/auth/session') {
        final device = _authorizeDevice(request);
        if (device == null) {
          await _respond(request, HttpStatus.unauthorized, {
            'message': 'Device is not authorized.',
          });
          return;
        }
        final session = await _authorizeUserSession(request, device);
        if (session == null) {
          await _respond(request, HttpStatus.unauthorized, {
            'message': 'User session is invalid or expired.',
          });
          return;
        }
        await _respond(request, HttpStatus.ok, {
          'user': session.user.toJson(),
          'expiresAt': session.expiresAt.toIso8601String(),
        });
        return;
      }

      if (request.method == 'POST' && path == '/v1/auth/logout') {
        final device = _authorizeDevice(request);
        if (device == null) {
          await _respond(request, HttpStatus.unauthorized, {
            'message': 'Device is not authorized.',
          });
          return;
        }
        final session = _removeUserSession(request, device.id);
        if (session != null) {
          await _recordSecurityEventSafe(
            LanAuthAuditEvent(
              action: 'logout',
              targetUserId: session.user.id,
              username: session.user.username,
              role: session.user.role,
              deviceId: device.id,
              deviceName: device.name,
              remoteAddress: _remoteAddress(request),
              authenticatedActor: true,
            ),
          );
          _emit(_snapshot.copyWith(clearError: true));
        }
        await _respond(request, HttpStatus.ok, {'success': true});
        return;
      }

      if (request.method == 'GET' && path.startsWith('/v1/catalog/images/')) {
        final device = _authorizeDevice(request);
        if (device == null) {
          await _respond(request, HttpStatus.unauthorized, {
            'code': 'device_unauthorized',
            'message': 'Device is not authorized.',
          });
          return;
        }
        final session = await _authorizeUserSession(request, device);
        if (session == null) {
          await _respond(request, HttpStatus.unauthorized, {
            'code': 'authentication_required',
            'message': 'User session is invalid or expired.',
          });
          return;
        }
        if (!_hasAnyPermission(session.user, const [
          'view_products',
          'create_sales',
          'process_sales',
          'manage_sales',
        ])) {
          await _respond(request, HttpStatus.forbidden, {
            'code': 'permission_denied',
            'message': 'This user cannot view products.',
          });
          return;
        }
        final productId = int.tryParse(
          path.substring('/v1/catalog/images/'.length),
        );
        if (productId == null || productId <= 0 || _businessGateway == null) {
          await _respond(request, HttpStatus.notFound, {
            'code': 'product_image_not_found',
            'message': 'Product image not found.',
          });
          return;
        }
        final imagePath = await _businessGateway.resolveProductImagePath(
          productId: productId,
        );
        if (imagePath == null) {
          await _respond(request, HttpStatus.notFound, {
            'code': 'product_image_not_found',
            'message': 'Product image not found.',
          });
          return;
        }
        final file = File(imagePath);
        if (!await file.exists()) {
          await _respond(request, HttpStatus.notFound, {
            'code': 'product_image_not_found',
            'message': 'Product image not found.',
          });
          return;
        }
        final length = await file.length();
        if (length <= 0 || length > 8 * 1024 * 1024) {
          await _respond(request, HttpStatus.requestEntityTooLarge, {
            'code': 'product_image_too_large',
            'message': 'Product image is too large.',
          });
          return;
        }
        request.response
          ..statusCode = HttpStatus.ok
          ..contentLength = length
          ..headers.contentType = _imageContentType(imagePath)
          ..headers.set('Cache-Control', 'private, max-age=300');
        await request.response.addStream(file.openRead());
        await request.response.close();
        return;
      }

      if (request.method == 'GET' && path == '/v1/catalog') {
        final device = _authorizeDevice(request);
        if (device == null) {
          await _respond(request, HttpStatus.unauthorized, {
            'code': 'device_unauthorized',
            'message': 'Device is not authorized.',
          });
          return;
        }
        final session = await _authorizeUserSession(request, device);
        if (session == null) {
          await _respond(request, HttpStatus.unauthorized, {
            'code': 'authentication_required',
            'message': 'User session is invalid or expired.',
          });
          return;
        }
        final management = request.uri.queryParameters['view'] == 'management';
        if (management &&
            !_hasAnyPermission(session.user, const [
              'view_products',
              'manage_purchases',
            ])) {
          await _respond(request, HttpStatus.forbidden, {
            'code': 'permission_denied',
            'message': 'This user cannot open product management.',
          });
          return;
        }
        if (!management &&
            !_hasAnyPermission(session.user, const [
              'view_products',
              'create_sales',
              'process_sales',
              'manage_sales',
            ])) {
          await _respond(request, HttpStatus.forbidden, {
            'code': 'permission_denied',
            'message': 'This user cannot view products.',
          });
          return;
        }
        if (_businessGateway == null) {
          await _respond(request, HttpStatus.serviceUnavailable, {
            'code': 'business_api_unavailable',
            'message': 'Master business services are unavailable.',
          });
          return;
        }
        final offset = int.tryParse(
          request.uri.queryParameters['offset'] ?? '',
        );
        final limit = int.tryParse(request.uri.queryParameters['limit'] ?? '');
        final result = await _businessGateway.fetchCatalog(
          query: request.uri.queryParameters['q'] ?? '',
          offset: offset ?? 0,
          limit: limit ?? 100,
        );
        final includeCost =
            management &&
            _hasAnyPermission(session.user, const [
              'view_product_cost',
              'manage_purchases',
            ]);
        await _respond(
          request,
          HttpStatus.ok,
          result.toJson(
            includeManagement: management,
            includeCost: includeCost,
          ),
        );
        return;
      }

      if (request.method == 'GET' &&
          path.startsWith('/v1/pharmacy/alternatives/')) {
        final device = _authorizeDevice(request);
        if (device == null) {
          await _respond(request, HttpStatus.unauthorized, {
            'code': 'device_unauthorized',
            'message': 'Device is not authorized.',
          });
          return;
        }
        final session = await _authorizeUserSession(request, device);
        if (session == null) {
          await _respond(request, HttpStatus.unauthorized, {
            'code': 'authentication_required',
            'message': 'User session is invalid or expired.',
          });
          return;
        }
        if (!_hasAnyPermission(session.user, const [
          'view_products',
          'create_sales',
          'process_sales',
          'manage_sales',
        ])) {
          await _respond(request, HttpStatus.forbidden, {
            'code': 'permission_denied',
            'message': 'This user cannot view products.',
          });
          return;
        }
        final productId = int.tryParse(
          path.substring('/v1/pharmacy/alternatives/'.length),
        );
        if (productId == null || productId <= 0) {
          await _respond(request, HttpStatus.badRequest, {
            'code': 'invalid_product',
            'message': 'A valid product is required.',
          });
          return;
        }
        if (_businessGateway == null) {
          await _respond(request, HttpStatus.serviceUnavailable, {
            'code': 'business_api_unavailable',
            'message': 'Master business services are unavailable.',
          });
          return;
        }
        final result = await _businessGateway.fetchMedicineAlternatives(
          productId: productId,
        );
        await _respond(request, HttpStatus.ok, result.toJson());
        return;
      }

      if (request.method == 'GET' && path == '/v1/customers') {
        final device = _authorizeDevice(request);
        if (device == null) {
          await _respond(request, HttpStatus.unauthorized, {
            'code': 'device_unauthorized',
            'message': 'Device is not authorized.',
          });
          return;
        }
        final session = await _authorizeUserSession(request, device);
        if (session == null) {
          await _respond(request, HttpStatus.unauthorized, {
            'code': 'authentication_required',
            'message': 'User session is invalid or expired.',
          });
          return;
        }
        if (!_hasAnyPermission(session.user, const [
          'view_customers',
          'create_sales',
          'process_sales',
          'manage_sales',
        ])) {
          await _respond(request, HttpStatus.forbidden, {
            'code': 'permission_denied',
            'message': 'This user cannot view customers.',
          });
          return;
        }
        if (_businessGateway == null) {
          await _respond(request, HttpStatus.serviceUnavailable, {
            'code': 'business_api_unavailable',
            'message': 'Master business services are unavailable.',
          });
          return;
        }
        final limit = int.tryParse(request.uri.queryParameters['limit'] ?? '');
        final customers = await _businessGateway.fetchCustomers(
          query: request.uri.queryParameters['q'] ?? '',
          limit: limit ?? 100,
        );
        await _respond(request, HttpStatus.ok, {
          'customers': customers.map((value) => value.toJson()).toList(),
        });
        return;
      }

      if (request.method == 'GET' && path == '/v1/salespeople') {
        final device = _authorizeDevice(request);
        if (device == null) {
          await _respond(request, HttpStatus.unauthorized, {
            'code': 'device_unauthorized',
            'message': 'Device is not authorized.',
          });
          return;
        }
        final session = await _authorizeUserSession(request, device);
        if (session == null) {
          await _respond(request, HttpStatus.unauthorized, {
            'code': 'authentication_required',
            'message': 'User session is invalid or expired.',
          });
          return;
        }
        if (!_hasAnyPermission(session.user, const [
          'create_sales',
          'process_sales',
          'manage_sales',
        ])) {
          await _respond(request, HttpStatus.forbidden, {
            'code': 'permission_denied',
            'message': 'This user cannot select a salesperson.',
          });
          return;
        }
        final limit = int.tryParse(request.uri.queryParameters['limit'] ?? '');
        final employees = await _businessGateway!.fetchSalespeople(
          query: request.uri.queryParameters['q'] ?? '',
          limit: limit ?? 100,
        );
        await _respond(request, HttpStatus.ok, {
          'employees': employees.map((value) => value.toJson()).toList(),
        });
        return;
      }

      if (request.method == 'GET' && path == '/v1/shifts/current') {
        if (_businessGateway == null) {
          await _respond(request, HttpStatus.serviceUnavailable, {
            'code': 'business_gateway_unavailable',
            'message': 'Business services are unavailable.',
          });
          return;
        }
        final device = _authorizeDevice(request);
        if (device == null) {
          await _respond(request, HttpStatus.unauthorized, {
            'code': 'device_unauthorized',
            'message': 'Device is not authorized.',
          });
          return;
        }
        final session = await _authorizeUserSession(request, device);
        if (session == null) {
          await _respond(request, HttpStatus.unauthorized, {
            'code': 'authentication_required',
            'message': 'User session is invalid or expired.',
          });
          return;
        }
        final shift = await _businessGateway.getOwnShift(actor: session.user);
        await _respond(request, HttpStatus.ok, {'shift': shift?.toJson()});
        return;
      }

      if (request.method == 'POST' &&
          (path == '/v1/shifts/open' || path == '/v1/shifts/close')) {
        if (_businessGateway == null) {
          await _respond(request, HttpStatus.serviceUnavailable, {
            'code': 'business_gateway_unavailable',
            'message': 'Business services are unavailable.',
          });
          return;
        }
        final device = _authorizeDevice(request);
        if (device == null) {
          await _respond(request, HttpStatus.unauthorized, {
            'code': 'device_unauthorized',
            'message': 'Device is not authorized.',
          });
          return;
        }
        final session = await _authorizeUserSession(request, device);
        if (session == null) {
          await _respond(request, HttpStatus.unauthorized, {
            'code': 'authentication_required',
            'message': 'User session is invalid or expired.',
          });
          return;
        }
        try {
          final body = await _readJson(request);
          final opening = (body['openingCashCents'] as num?)?.toInt();
          final counted = (body['countedCashCents'] as num?)?.toInt();
          final isOpen = path.endsWith('/open');
          if (!isOpen && counted == null) {
            throw const LanBusinessException(
              'counted_cash_required',
              'Counted closing cash is required.',
            );
          }
          if ((opening != null && opening < 0) ||
              (counted != null && counted < 0)) {
            throw const LanBusinessException(
              'invalid_shift_amount',
              'Shift cash amount cannot be negative.',
            );
          }
          final shift = isOpen
              ? await _businessGateway.openOwnShift(
                  actor: session.user,
                  openingCashCents: opening ?? 0,
                  notes: body['notes']?.toString(),
                )
              : await _businessGateway.closeOwnShift(
                  actor: session.user,
                  countedCashCents: counted!,
                  notes: body['notes']?.toString(),
                );
          await _recordSecurityEventSafe(
            LanAuthAuditEvent(
              action: isOpen ? 'cashier_shift_opened' : 'cashier_shift_closed',
              targetUserId: session.user.id,
              username: session.user.employeeName ?? session.user.username,
              role: session.user.role,
              deviceId: device.id,
              deviceName: device.name,
              remoteAddress: _remoteAddress(request),
              authenticatedActor: true,
              reason: shift.shiftNumber,
            ),
          );
          await _respond(request, HttpStatus.ok, {'shift': shift.toJson()});
        } on LanBusinessException catch (error) {
          await _respond(request, error.statusCode, {
            'code': error.code,
            'message': error.message,
            if (error.details.isNotEmpty) 'details': error.details,
          });
        }
        return;
      }

      if (request.method == 'GET' && path == '/v1/sales') {
        final device = _authorizeDevice(request);
        if (device == null) {
          await _respond(request, HttpStatus.unauthorized, {
            'code': 'device_unauthorized',
            'message': 'Device is not authorized.',
          });
          return;
        }
        final session = await _authorizeUserSession(request, device);
        if (session == null) {
          await _respond(request, HttpStatus.unauthorized, {
            'code': 'authentication_required',
            'message': 'User session is invalid or expired.',
          });
          return;
        }
        if (!_hasAnyPermission(session.user, const [
          'view_daily_reports',
          'process_sales',
          'manage_sales',
        ])) {
          await _respond(request, HttpStatus.forbidden, {
            'code': 'permission_denied',
            'message': 'This user cannot view sales.',
          });
          return;
        }
        if (_businessGateway == null) {
          await _respond(request, HttpStatus.serviceUnavailable, {
            'code': 'business_api_unavailable',
            'message': 'Master business services are unavailable.',
          });
          return;
        }
        final limit = int.tryParse(request.uri.queryParameters['limit'] ?? '');
        final result = await _businessGateway.fetchSales(limit: limit ?? 500);
        await _respond(request, HttpStatus.ok, result.toJson());
        return;
      }

      if (request.method == 'POST' &&
          path.startsWith('/v1/sales/') &&
          path.endsWith('/void')) {
        final device = _authorizeDevice(request);
        if (device == null) {
          await _respond(request, HttpStatus.unauthorized, {
            'code': 'device_unauthorized',
            'message': 'Device is not authorized.',
          });
          return;
        }
        final session = await _authorizeUserSession(request, device);
        if (session == null) {
          await _respond(request, HttpStatus.unauthorized, {
            'code': 'authentication_required',
            'message': 'User session is invalid or expired.',
          });
          return;
        }
        if (!session.user.permissions.contains('void_transactions')) {
          await _respond(request, HttpStatus.forbidden, {
            'code': 'permission_denied',
            'message': 'This user cannot void sales.',
          });
          return;
        }
        if (_businessGateway == null) {
          await _respond(request, HttpStatus.serviceUnavailable, {
            'code': 'business_api_unavailable',
            'message': 'Master business services are unavailable.',
          });
          return;
        }
        final rawId = path.substring(
          '/v1/sales/'.length,
          path.length - '/void'.length,
        );
        final saleId = int.tryParse(rawId);
        if (saleId == null || saleId <= 0) {
          await _respond(request, HttpStatus.badRequest, {
            'code': 'invalid_sale',
            'message': 'Invalid sale.',
          });
          return;
        }
        try {
          final result = await _businessGateway.voidSale(
            actor: session.user,
            saleId: saleId,
          );
          await _recordSecurityEventSafe(
            LanAuthAuditEvent(
              action: 'remote_sale_voided',
              targetUserId: session.user.id,
              username: session.user.username,
              role: session.user.role,
              deviceId: device.id,
              deviceName: device.name,
              remoteAddress: _remoteAddress(request),
              authenticatedActor: true,
              reason: 'sale:$saleId',
            ),
          );
          await _respond(request, HttpStatus.ok, result.toJson());
        } on LanBusinessException catch (error) {
          await _respond(request, error.statusCode, {
            'code': error.code,
            'message': error.message,
          });
        }
        return;
      }

      if (request.method == 'GET' &&
          path.startsWith('/v1/sales/') &&
          !path.endsWith('/returnable')) {
        final device = _authorizeDevice(request);
        if (device == null) {
          await _respond(request, HttpStatus.unauthorized, {
            'code': 'device_unauthorized',
            'message': 'Device is not authorized.',
          });
          return;
        }
        final session = await _authorizeUserSession(request, device);
        if (session == null) {
          await _respond(request, HttpStatus.unauthorized, {
            'code': 'authentication_required',
            'message': 'User session is invalid or expired.',
          });
          return;
        }
        if (!_hasAnyPermission(session.user, const [
          'view_daily_reports',
          'process_sales',
          'manage_sales',
        ])) {
          await _respond(request, HttpStatus.forbidden, {
            'code': 'permission_denied',
            'message': 'This user cannot view sale details.',
          });
          return;
        }
        if (_businessGateway == null) {
          await _respond(request, HttpStatus.serviceUnavailable, {
            'code': 'business_api_unavailable',
            'message': 'Master business services are unavailable.',
          });
          return;
        }
        final saleId = int.tryParse(path.substring('/v1/sales/'.length));
        if (saleId == null || saleId <= 0) {
          await _respond(request, HttpStatus.badRequest, {
            'code': 'invalid_sale',
            'message': 'Invalid sale.',
          });
          return;
        }
        final details = await _businessGateway.fetchSaleDetails(saleId: saleId);
        if (details == null) {
          await _respond(request, HttpStatus.notFound, {
            'code': 'sale_not_found',
            'message': 'Sale not found.',
          });
          return;
        }
        await _respond(request, HttpStatus.ok, details.toJson());
        return;
      }

      if (request.method == 'GET' &&
          (path == '/v1/sales/returnable' ||
              (path.startsWith('/v1/sales/') &&
                  path.endsWith('/returnable')))) {
        final device = _authorizeDevice(request);
        if (device == null) {
          await _respond(request, HttpStatus.unauthorized, {
            'code': 'device_unauthorized',
            'message': 'Device is not authorized.',
          });
          return;
        }
        final session = await _authorizeUserSession(request, device);
        if (session == null) {
          await _respond(request, HttpStatus.unauthorized, {
            'code': 'authentication_required',
            'message': 'User session is invalid or expired.',
          });
          return;
        }
        if (!_hasAnyPermission(session.user, const [
          'handle_returns',
          'manage_sales',
        ])) {
          await _respond(request, HttpStatus.forbidden, {
            'code': 'permission_denied',
            'message': 'This user cannot process sale returns.',
          });
          return;
        }
        if (_businessGateway == null) {
          await _respond(request, HttpStatus.serviceUnavailable, {
            'code': 'business_api_unavailable',
            'message': 'Master business services are unavailable.',
          });
          return;
        }

        if (path == '/v1/sales/returnable') {
          final offset = int.tryParse(
            request.uri.queryParameters['offset'] ?? '',
          );
          final limit = int.tryParse(
            request.uri.queryParameters['limit'] ?? '',
          );
          final result = await _businessGateway.fetchReturnableSales(
            query: request.uri.queryParameters['q'] ?? '',
            offset: offset ?? 0,
            limit: limit ?? 50,
          );
          await _respond(request, HttpStatus.ok, result.toJson());
          return;
        }

        final rawId = path.substring(
          '/v1/sales/'.length,
          path.length - '/returnable'.length,
        );
        final saleId = int.tryParse(rawId);
        if (saleId == null || saleId <= 0) {
          await _respond(request, HttpStatus.badRequest, {
            'code': 'invalid_sale',
            'message': 'Invalid sale.',
          });
          return;
        }
        final details = await _businessGateway.fetchReturnableSale(
          saleId: saleId,
        );
        if (details == null) {
          await _respond(request, HttpStatus.notFound, {
            'code': 'sale_not_returnable',
            'message': 'Sale not found or has no returnable items.',
          });
          return;
        }
        await _respond(request, HttpStatus.ok, details.toJson());
        return;
      }

      if (request.method == 'GET' &&
          path.startsWith('/v1/sale-returns/') &&
          path != '/v1/sale-returns/') {
        final device = _authorizeDevice(request);
        if (device == null) {
          await _respond(request, HttpStatus.unauthorized, {
            'code': 'device_unauthorized',
            'message': 'Device is not authorized.',
          });
          return;
        }
        final session = await _authorizeUserSession(request, device);
        if (session == null) {
          await _respond(request, HttpStatus.unauthorized, {
            'code': 'authentication_required',
            'message': 'User session is invalid or expired.',
          });
          return;
        }
        if (!_hasAnyPermission(session.user, const [
          'view_daily_reports',
          'process_sales',
          'handle_returns',
          'manage_sales',
        ])) {
          await _respond(request, HttpStatus.forbidden, {
            'code': 'permission_denied',
            'message': 'This user cannot view sale return details.',
          });
          return;
        }
        if (_businessGateway == null) {
          await _respond(request, HttpStatus.serviceUnavailable, {
            'code': 'business_api_unavailable',
            'message': 'Master business services are unavailable.',
          });
          return;
        }
        final segments = request.uri.pathSegments;
        final kind = segments.length > 2 ? segments[2] : '';
        final returnId = segments.length > 3 ? int.tryParse(segments[3]) : null;
        if ((kind != 'linked' && kind != 'adjustment') ||
            returnId == null ||
            returnId <= 0) {
          await _respond(request, HttpStatus.badRequest, {
            'code': 'invalid_sale_return',
            'message': 'Invalid sale return.',
          });
          return;
        }
        final details = await _businessGateway.fetchSaleReturnDetails(
          returnId: returnId,
          adjustment: kind == 'adjustment',
        );
        if (details == null) {
          await _respond(request, HttpStatus.notFound, {
            'code': 'sale_return_not_found',
            'message': 'Sale return not found.',
          });
          return;
        }
        await _respond(request, HttpStatus.ok, details.toJson());
        return;
      }

      if (request.method == 'GET' && path == '/v1/sale-returns') {
        final device = _authorizeDevice(request);
        if (device == null) {
          await _respond(request, HttpStatus.unauthorized, {
            'code': 'device_unauthorized',
            'message': 'Device is not authorized.',
          });
          return;
        }
        final session = await _authorizeUserSession(request, device);
        if (session == null) {
          await _respond(request, HttpStatus.unauthorized, {
            'code': 'authentication_required',
            'message': 'User session is invalid or expired.',
          });
          return;
        }
        if (!_hasAnyPermission(session.user, const [
          'handle_returns',
          'manage_sales',
        ])) {
          await _respond(request, HttpStatus.forbidden, {
            'code': 'permission_denied',
            'message': 'This user cannot view sale returns.',
          });
          return;
        }
        if (_businessGateway == null) {
          await _respond(request, HttpStatus.serviceUnavailable, {
            'code': 'business_api_unavailable',
            'message': 'Master business services are unavailable.',
          });
          return;
        }
        final offset = int.tryParse(
          request.uri.queryParameters['offset'] ?? '',
        );
        final limit = int.tryParse(request.uri.queryParameters['limit'] ?? '');
        final result = await _businessGateway.fetchSaleReturns(
          query: request.uri.queryParameters['q'] ?? '',
          offset: offset ?? 0,
          limit: limit ?? 100,
        );
        await _respond(request, HttpStatus.ok, result.toJson());
        return;
      }

      if (request.method == 'POST' && path == '/v1/sale-returns') {
        final device = _authorizeDevice(request);
        if (device == null) {
          await _respond(request, HttpStatus.unauthorized, {
            'code': 'device_unauthorized',
            'message': 'Device is not authorized.',
          });
          return;
        }
        final session = await _authorizeUserSession(request, device);
        if (session == null) {
          await _respond(request, HttpStatus.unauthorized, {
            'code': 'authentication_required',
            'message': 'User session is invalid or expired.',
          });
          return;
        }
        if (!_hasAnyPermission(session.user, const [
          'handle_returns',
          'manage_sales',
        ])) {
          await _respond(request, HttpStatus.forbidden, {
            'code': 'permission_denied',
            'message': 'This user cannot process sale returns.',
          });
          return;
        }
        if (_businessGateway == null) {
          await _respond(request, HttpStatus.serviceUnavailable, {
            'code': 'business_api_unavailable',
            'message': 'Master business services are unavailable.',
          });
          return;
        }
        try {
          final body = await _readJson(request);
          final result = await _businessGateway.createSaleReturn(
            actor: session.user,
            request: LanSaleReturnRequest.fromJson(body),
          );
          await _recordSecurityEventSafe(
            LanAuthAuditEvent(
              action: result.duplicate
                  ? 'remote_sale_return_replayed'
                  : 'remote_sale_return_created',
              targetUserId: session.user.id,
              username: session.user.username,
              role: session.user.role,
              deviceId: device.id,
              deviceName: device.name,
              remoteAddress: _remoteAddress(request),
              authenticatedActor: true,
              reason: result.returnNumber,
            ),
          );
          _publishMasterActivity(
            type: LanMasterActivityType.saleReturn,
            actor: session.user,
            deviceName: device.name,
            documentNumber: result.returnNumber,
            totalCents: result.totalCents,
            duplicate: result.duplicate,
          );
          await _respond(request, HttpStatus.ok, result.toJson());
        } on LanBusinessException catch (error) {
          await _respond(request, error.statusCode, {
            'code': error.code,
            'message': error.message,
          });
        } on FormatException catch (error) {
          await _respond(request, HttpStatus.badRequest, {
            'code': 'invalid_request',
            'message': error.message,
          });
        }
        return;
      }

      if (request.method == 'POST' && path == '/v1/sale-adjustment-returns') {
        final device = _authorizeDevice(request);
        if (device == null) {
          await _respond(request, HttpStatus.unauthorized, {
            'code': 'device_unauthorized',
            'message': 'Device is not authorized.',
          });
          return;
        }
        final session = await _authorizeUserSession(request, device);
        if (session == null) {
          await _respond(request, HttpStatus.unauthorized, {
            'code': 'authentication_required',
            'message': 'User session is invalid or expired.',
          });
          return;
        }
        if (!_hasAnyPermission(session.user, const [
          'handle_returns',
          'manage_sales',
        ])) {
          await _respond(request, HttpStatus.forbidden, {
            'code': 'permission_denied',
            'message': 'This user cannot process sale returns.',
          });
          return;
        }
        if (_businessGateway == null) {
          await _respond(request, HttpStatus.serviceUnavailable, {
            'code': 'business_api_unavailable',
            'message': 'Master business services are unavailable.',
          });
          return;
        }
        try {
          final body = await _readJson(request);
          final result = await _businessGateway.createSaleAdjustmentReturn(
            actor: session.user,
            request: LanSaleAdjustmentReturnRequest.fromJson(body),
          );
          await _recordSecurityEventSafe(
            LanAuthAuditEvent(
              action: result.duplicate
                  ? 'remote_sale_adjustment_return_replayed'
                  : 'remote_sale_adjustment_return_created',
              targetUserId: session.user.id,
              username: session.user.username,
              role: session.user.role,
              deviceId: device.id,
              deviceName: device.name,
              remoteAddress: _remoteAddress(request),
              authenticatedActor: true,
              reason: result.returnNumber,
            ),
          );
          _publishMasterActivity(
            type: LanMasterActivityType.saleAdjustmentReturn,
            actor: session.user,
            deviceName: device.name,
            documentNumber: result.returnNumber,
            totalCents: result.totalCents,
            duplicate: result.duplicate,
          );
          await _respond(request, HttpStatus.ok, result.toJson());
        } on LanBusinessException catch (error) {
          await _respond(request, error.statusCode, {
            'code': error.code,
            'message': error.message,
          });
        } on FormatException catch (error) {
          await _respond(request, HttpStatus.badRequest, {
            'code': 'invalid_request',
            'message': error.message,
          });
        }
        return;
      }

      final isPurchaseReturnApi =
          path == '/v1/suppliers' ||
          path == '/v1/purchases/returnable' ||
          (path.startsWith('/v1/purchases/') && path.endsWith('/returnable')) ||
          path == '/v1/purchase-returns' ||
          path.startsWith('/v1/purchase-returns/') ||
          path == '/v1/purchase-adjustment-returns';
      if (isPurchaseReturnApi) {
        final device = _authorizeDevice(request);
        if (device == null) {
          await _respond(request, HttpStatus.unauthorized, {
            'code': 'device_unauthorized',
            'message': 'Device is not authorized.',
          });
          return;
        }
        final session = await _authorizeUserSession(request, device);
        if (session == null) {
          await _respond(request, HttpStatus.unauthorized, {
            'code': 'authentication_required',
            'message': 'User session is invalid or expired.',
          });
          return;
        }
        final canView = _hasAnyPermission(session.user, const [
          'view_purchases',
          'manage_purchases',
        ]);
        final canManage = _hasAnyPermission(session.user, const [
          'manage_purchases',
        ]);
        final mutating = request.method != 'GET';
        if ((!mutating && !canView) || (mutating && !canManage)) {
          await _respond(request, HttpStatus.forbidden, {
            'code': 'permission_denied',
            'message': mutating
                ? 'This user cannot process purchase returns.'
                : 'This user cannot view purchase returns.',
          });
          return;
        }
        final isVoid = request.method == 'POST' && path.endsWith('/void');
        if (isVoid &&
            !_hasAnyPermission(session.user, const ['void_transactions'])) {
          await _respond(request, HttpStatus.forbidden, {
            'code': 'permission_denied',
            'message': 'This user cannot void purchase returns.',
          });
          return;
        }
        if (_businessGateway == null) {
          await _respond(request, HttpStatus.serviceUnavailable, {
            'code': 'business_api_unavailable',
            'message': 'Master business services are unavailable.',
          });
          return;
        }
        try {
          if (request.method == 'GET' && path == '/v1/suppliers') {
            final limit = int.tryParse(
              request.uri.queryParameters['limit'] ?? '',
            );
            final suppliers = await _businessGateway.fetchSuppliers(
              query: request.uri.queryParameters['q'] ?? '',
              limit: limit ?? 100,
            );
            await _respond(request, HttpStatus.ok, {
              'suppliers': suppliers.map((value) => value.toJson()).toList(),
            });
            return;
          }
          if (request.method == 'GET' && path == '/v1/purchases/returnable') {
            final result = await _businessGateway.fetchReturnablePurchases(
              query: request.uri.queryParameters['q'] ?? '',
              offset:
                  int.tryParse(request.uri.queryParameters['offset'] ?? '') ??
                  0,
              limit:
                  int.tryParse(request.uri.queryParameters['limit'] ?? '') ??
                  50,
            );
            await _respond(request, HttpStatus.ok, result.toJson());
            return;
          }
          if (request.method == 'GET' &&
              path.startsWith('/v1/purchases/') &&
              path.endsWith('/returnable')) {
            final rawId = path.substring(
              '/v1/purchases/'.length,
              path.length - '/returnable'.length,
            );
            final purchaseId = int.tryParse(rawId);
            final details = purchaseId == null
                ? null
                : await _businessGateway.fetchReturnablePurchase(
                    purchaseId: purchaseId,
                  );
            if (details == null) {
              await _respond(request, HttpStatus.notFound, {
                'code': 'purchase_not_returnable',
                'message': 'Purchase not found or has no returnable items.',
              });
            } else {
              await _respond(request, HttpStatus.ok, details.toJson());
            }
            return;
          }
          if (request.method == 'GET' && path == '/v1/purchase-returns') {
            final result = await _businessGateway.fetchPurchaseReturns(
              query: request.uri.queryParameters['q'] ?? '',
              offset:
                  int.tryParse(request.uri.queryParameters['offset'] ?? '') ??
                  0,
              limit:
                  int.tryParse(request.uri.queryParameters['limit'] ?? '') ??
                  100,
            );
            await _respond(request, HttpStatus.ok, result.toJson());
            return;
          }
          if (request.method == 'GET' &&
              path.startsWith('/v1/purchase-returns/')) {
            final segments = request.uri.pathSegments;
            final kind = segments.length > 2 ? segments[2] : '';
            final returnId = segments.length > 3
                ? int.tryParse(segments[3])
                : null;
            final details = returnId == null
                ? null
                : await _businessGateway.fetchPurchaseReturnDetails(
                    returnId: returnId,
                    adjustment: kind == 'adjustment',
                  );
            if ((kind != 'linked' && kind != 'adjustment') || details == null) {
              await _respond(request, HttpStatus.notFound, {
                'code': 'purchase_return_not_found',
                'message': 'Purchase return not found.',
              });
            } else {
              await _respond(request, HttpStatus.ok, details.toJson());
            }
            return;
          }
          if (isVoid) {
            final segments = request.uri.pathSegments;
            final kind = segments.length > 2 ? segments[2] : '';
            final returnId = segments.length > 3
                ? int.tryParse(segments[3])
                : null;
            if (returnId == null ||
                (kind != 'linked' && kind != 'adjustment')) {
              throw const FormatException('Invalid purchase return.');
            }
            await _businessGateway.voidPurchaseReturn(
              actor: session.user,
              returnId: returnId,
              adjustment: kind == 'adjustment',
            );
            await _respond(request, HttpStatus.ok, {'status': 'voided'});
            return;
          }
          if (request.method != 'POST' ||
              (path != '/v1/purchase-returns' &&
                  path != '/v1/purchase-adjustment-returns')) {
            await _respond(request, HttpStatus.notFound, {
              'code': 'not_found',
              'message': 'Endpoint not found.',
            });
            return;
          }
          final body = await _readJson(request);
          final result = path == '/v1/purchase-adjustment-returns'
              ? await _businessGateway.createPurchaseAdjustmentReturn(
                  actor: session.user,
                  request: LanPurchaseAdjustmentReturnRequest.fromJson(body),
                )
              : await _businessGateway.createPurchaseReturn(
                  actor: session.user,
                  request: LanPurchaseReturnRequest.fromJson(body),
                );
          await _recordSecurityEventSafe(
            LanAuthAuditEvent(
              action: result.duplicate
                  ? 'remote_purchase_return_replayed'
                  : 'remote_purchase_return_created',
              targetUserId: session.user.id,
              username: session.user.username,
              role: session.user.role,
              deviceId: device.id,
              deviceName: device.name,
              remoteAddress: _remoteAddress(request),
              authenticatedActor: true,
              reason: result.returnNumber,
            ),
          );
          await _respond(request, HttpStatus.ok, result.toJson());
        } on LanBusinessException catch (error) {
          await _respond(request, error.statusCode, {
            'code': error.code,
            'message': error.message,
            if (error.details.isNotEmpty) 'details': error.details,
          });
        } on FormatException catch (error) {
          await _respond(request, HttpStatus.badRequest, {
            'code': 'invalid_request',
            'message': error.message,
          });
        }
        return;
      }

      if (request.method == 'POST' && path == '/v1/sales') {
        final device = _authorizeDevice(request);
        if (device == null) {
          await _respond(request, HttpStatus.unauthorized, {
            'code': 'device_unauthorized',
            'message': 'Device is not authorized.',
          });
          return;
        }
        final session = await _authorizeUserSession(request, device);
        if (session == null) {
          await _respond(request, HttpStatus.unauthorized, {
            'code': 'authentication_required',
            'message': 'User session is invalid or expired.',
          });
          return;
        }
        if (!_hasAnyPermission(session.user, const [
          'create_sales',
          'process_sales',
          'manage_sales',
        ])) {
          await _respond(request, HttpStatus.forbidden, {
            'code': 'permission_denied',
            'message': 'This user cannot create sales.',
          });
          return;
        }
        if (_businessGateway == null) {
          await _respond(request, HttpStatus.serviceUnavailable, {
            'code': 'business_api_unavailable',
            'message': 'Master business services are unavailable.',
          });
          return;
        }
        try {
          final body = await _readJson(request);
          final result = await _businessGateway.createSale(
            actor: session.user,
            request: LanSaleRequest.fromJson(body),
          );
          await _recordSecurityEventSafe(
            LanAuthAuditEvent(
              action: result.duplicate
                  ? 'remote_sale_replayed'
                  : 'remote_sale_created',
              targetUserId: session.user.id,
              username: session.user.username,
              role: session.user.role,
              deviceId: device.id,
              deviceName: device.name,
              remoteAddress: _remoteAddress(request),
              authenticatedActor: true,
              reason: result.invoiceNumber,
            ),
          );
          _publishMasterActivity(
            type: LanMasterActivityType.sale,
            actor: session.user,
            deviceName: device.name,
            documentNumber: result.invoiceNumber,
            totalCents: result.totalCents,
            duplicate: result.duplicate,
          );
          await _respond(request, HttpStatus.ok, result.toJson());
        } on LanBusinessException catch (error) {
          await _respond(request, error.statusCode, {
            'code': error.code,
            'message': error.message,
            if (error.details.isNotEmpty) 'details': error.details,
          });
        }
        return;
      }

      if (request.method == 'GET' && path == '/v1/status') {
        final device = _authorizeDevice(request);
        if (device == null) {
          await _respond(request, HttpStatus.unauthorized, {
            'message': 'Device is not authorized.',
          });
          return;
        }
        device.data['lastSeenAt'] = DateTime.now().toUtc().toIso8601String();
        await _saveAuthorizedDevices();
        await _respond(request, HttpStatus.ok, {
          'masterId': _deviceId,
          'protocolVersion': protocolVersion,
          'serverTime': DateTime.now().toUtc().toIso8601String(),
          'localeCode': _masterLocaleCode,
        });
        return;
      }

      await _respond(request, HttpStatus.notFound, {'message': 'Not found.'});
    } catch (error) {
      try {
        await _respond(request, HttpStatus.internalServerError, {
          'message': 'Request failed.',
        });
      } catch (_) {
        // The response may already have been closed by a completed handler.
        await request.response.close();
      }
    }
  }

  _AuthorizedDevice? _authorizeDevice(HttpRequest request) {
    final header = request.headers.value(HttpHeaders.authorizationHeader);
    if (header == null || !header.startsWith('Bearer ')) return null;
    final candidateHash = sha256
        .convert(utf8.encode(header.substring('Bearer '.length)))
        .toString();
    for (final entry in _authorizedDevices.entries) {
      if (_constantTimeEquals(
        entry.value['tokenHash']?.toString() ?? '',
        candidateHash,
      )) {
        entry.value['lastSeenAt'] = DateTime.now().toUtc().toIso8601String();
        entry.value['lastAddress'] = _remoteAddress(request);
        final platform = request.headers.value(_platformHeader)?.trim();
        if (platform != null && platform.isNotEmpty) {
          entry.value['platform'] = platform;
        }
        final connectedDevices = _connectedDeviceCount();
        if (_snapshot.mode == LanMode.master &&
            connectedDevices != _snapshot.connectedDevices) {
          _emit(_snapshot.copyWith(connectedDevices: connectedDevices));
        }
        return _AuthorizedDevice(entry.key, entry.value);
      }
    }
    return null;
  }

  Future<_MasterUserSession?> _authorizeUserSession(
    HttpRequest request,
    _AuthorizedDevice device,
  ) async {
    final rawToken = request.headers.value(_userSessionHeader);
    if (rawToken == null || rawToken.isEmpty) return null;
    final hash = sha256.convert(utf8.encode(rawToken)).toString();
    final session = _userSessions[hash];
    if (session == null || session.deviceId != device.id) return null;

    final now = DateTime.now().toUtc();
    if (!now.isBefore(session.expiresAt)) {
      _userSessions.remove(hash);
      await _recordSecurityEventSafe(
        LanAuthAuditEvent(
          action: 'session_expired',
          targetUserId: session.user.id,
          username: session.user.username,
          role: session.user.role,
          deviceId: device.id,
          deviceName: device.name,
          remoteAddress: _remoteAddress(request),
          authenticatedActor: true,
        ),
      );
      return null;
    }

    final current = await _authGateway?.findActiveAccount(
      session.user.username,
    );
    if (current == null || current.user.id != session.user.id) {
      _userSessions.remove(hash);
      await _recordSecurityEventSafe(
        LanAuthAuditEvent(
          action: 'session_revoked',
          targetUserId: session.user.id,
          username: session.user.username,
          role: session.user.role,
          deviceId: device.id,
          deviceName: device.name,
          remoteAddress: _remoteAddress(request),
          authenticatedActor: true,
          reason: 'Account disabled or removed.',
        ),
      );
      return null;
    }

    // Roles and permissions may change while the user is signed in. Refresh
    // them from the master for every authenticated request.
    session.user = current.user;
    return session;
  }

  _MasterUserSession? _removeUserSession(HttpRequest request, String deviceId) {
    final rawToken = request.headers.value(_userSessionHeader);
    if (rawToken == null || rawToken.isEmpty) return null;
    final hash = sha256.convert(utf8.encode(rawToken)).toString();
    final session = _userSessions[hash];
    if (session == null || session.deviceId != deviceId) return null;
    return _userSessions.remove(hash);
  }

  Future<void> _replaceDeviceSessions(_AuthorizedDevice device) async {
    final previous = _userSessions.entries
        .where((entry) => entry.value.deviceId == device.id)
        .toList(growable: false);
    for (final entry in previous) {
      _userSessions.remove(entry.key);
      final session = entry.value;
      await _recordSecurityEventSafe(
        LanAuthAuditEvent(
          action: 'session_replaced',
          targetUserId: session.user.id,
          username: session.user.username,
          role: session.user.role,
          deviceId: device.id,
          deviceName: device.name,
          authenticatedActor: true,
          reason: 'Another user signed in on this device.',
        ),
      );
    }
  }

  bool _isRateLimited(String deviceId, String username) {
    final key = '$deviceId:${username.toLowerCase()}';
    final cutoff = DateTime.now().toUtc().subtract(const Duration(minutes: 5));
    final attempts = _failedLoginAttempts[key]
        ?.where((time) => time.isAfter(cutoff))
        .toList(growable: true);
    if (attempts == null || attempts.isEmpty) {
      _failedLoginAttempts.remove(key);
      return false;
    }
    _failedLoginAttempts[key] = attempts;
    return attempts.length >= 5;
  }

  void _registerFailedAttempt(String deviceId, String username) {
    final key = '$deviceId:${username.toLowerCase()}';
    _failedLoginAttempts.putIfAbsent(key, () => []).add(DateTime.now().toUtc());
  }

  void _clearFailedAttempts(String deviceId, String username) {
    _failedLoginAttempts.remove('$deviceId:${username.toLowerCase()}');
  }

  void _pruneAuthState() {
    final now = DateTime.now().toUtc();
    _loginChallenges.removeWhere((_, value) => !now.isBefore(value.expiresAt));
    final cutoff = now.subtract(const Duration(minutes: 5));
    _failedLoginAttempts.removeWhere((_, attempts) {
      attempts.removeWhere((time) => !time.isAfter(cutoff));
      return attempts.isEmpty;
    });
  }

  String? _remoteAddress(HttpRequest request) =>
      request.connectionInfo?.remoteAddress.address;

  void _publishMasterActivity({
    required LanMasterActivityType type,
    required LanRemoteUser actor,
    required String deviceName,
    required String documentNumber,
    required int totalCents,
    required bool duplicate,
  }) {
    if (duplicate || _masterActivityController.isClosed) return;
    final employeeName = actor.employeeName?.trim();
    _masterActivityController.add(
      LanMasterActivityEvent(
        type: type,
        actorName: employeeName != null && employeeName.isNotEmpty
            ? employeeName
            : actor.username,
        deviceName: deviceName,
        documentNumber: documentNumber,
        totalCents: totalCents,
      ),
    );
  }

  Future<void> _recordSecurityEventSafe(LanAuthAuditEvent event) async {
    try {
      await _authGateway?.recordSecurityEvent(event);
    } catch (_) {
      // Security logging must not expose database details to the LAN peer.
      // Authentication itself remains authoritative even if the audit UI is
      // temporarily unavailable.
    }
  }

  ContentType _imageContentType(String path) {
    final extension = path.toLowerCase().split('.').last;
    return switch (extension) {
      'png' => ContentType('image', 'png'),
      'webp' => ContentType('image', 'webp'),
      'gif' => ContentType('image', 'gif'),
      _ => ContentType('image', 'jpeg'),
    };
  }

  bool _hasAnyPermission(LanRemoteUser user, List<String> permissions) {
    return permissions.any(user.permissions.contains);
  }

  bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var mismatch = 0;
    for (var i = 0; i < a.length; i++) {
      mismatch |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return mismatch == 0;
  }

  Future<Map<String, dynamic>> _readJson(HttpRequest request) async {
    final content = await utf8.decoder.bind(request).join();
    if (content.length > 65536) {
      throw const FormatException('Request body is too large.');
    }
    if (content.isEmpty) return {};
    final decoded = jsonDecode(content);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Expected a JSON object.');
    }
    return decoded;
  }

  Future<void> _respond(
    HttpRequest request,
    int status,
    Map<String, dynamic> body,
  ) async {
    request.response.statusCode = status;
    request.response.write(jsonEncode(body));
    await request.response.close();
  }

  Future<_JsonResponse> _jsonRequest({
    required String method,
    required String host,
    required int port,
    required String path,
    Map<String, String>? queryParameters,
    Map<String, dynamic>? body,
    String? token,
    String? userToken,
  }) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client
          .openUrl(
            method,
            Uri(
              scheme: 'http',
              host: host,
              port: port,
              path: path,
              queryParameters: queryParameters,
            ),
          )
          .timeout(const Duration(seconds: 6));
      request.headers.contentType = ContentType.json;
      request.headers.set(_platformHeader, Platform.operatingSystem);
      if (_clientDeviceName != null && _clientDeviceName!.trim().isNotEmpty) {
        request.headers.set(_deviceNameHeader, _clientDeviceName!.trim());
      }
      if (token != null) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }
      if (userToken != null) {
        request.headers.set(_userSessionHeader, userToken);
      }
      if (body != null) request.write(jsonEncode(body));
      final response = await request.close().timeout(
        const Duration(seconds: 6),
      );
      final raw = await utf8.decoder.bind(response).join();
      final decoded = raw.isEmpty ? <String, dynamic>{} : jsonDecode(raw);
      return _JsonResponse(
        response.statusCode,
        decoded is Map<String, dynamic> ? decoded : <String, dynamic>{},
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<String> _loadOrCreateDeviceId() async {
    final existing = await _settingsDao.getSetting(_deviceIdKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final created = const Uuid().v4();
    await _settingsDao.saveSetting(_deviceIdKey, created);
    return created;
  }

  Future<void> _loadAuthorizedDevices() async {
    final raw = await _settingsDao.getSetting(_authorizedDevicesKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        _authorizedDevices = decoded.map(
          (key, value) => MapEntry(
            key,
            value is Map<String, dynamic>
                ? value
                : Map<String, dynamic>.from(value as Map),
          ),
        );
      }
    } catch (_) {
      _authorizedDevices = {};
    }
  }

  Future<void> _saveAuthorizedDevices() => _settingsDao.saveSetting(
    _authorizedDevicesKey,
    jsonEncode(_authorizedDevices),
  );

  String _newPairingCode() => (100000 + _random.nextInt(900000)).toString();

  String _newToken() {
    final bytes = List<int>.generate(32, (_) => _random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  String _normalizeHost(String input) {
    var value = input.trim();
    if (value.contains('://')) {
      value = Uri.tryParse(value)?.host ?? '';
    }
    if (value.contains(':') && !value.contains(']')) {
      value = value.split(':').first;
    }
    return value;
  }

  Future<List<String>> _localIpv4Addresses() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
      includeLinkLocal: false,
    );
    final addresses = <String>{};
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        if (_isPrivateIpv4(address.address)) addresses.add(address.address);
      }
    }
    return addresses.toList()..sort();
  }

  bool _isPrivateIpv4(String value) {
    final parts = value.split('.').map(int.tryParse).toList();
    if (parts.length != 4 || parts.any((part) => part == null)) return false;
    final a = parts[0]!;
    final b = parts[1]!;
    return a == 10 ||
        (a == 172 && b >= 16 && b <= 31) ||
        (a == 192 && b == 168);
  }

  void _handleServerError(Object error, StackTrace stackTrace) {
    _emit(
      _snapshot.copyWith(
        status: LanConnectionStatus.error,
        error: error.toString(),
      ),
    );
  }

  void _emit(LanNetworkSnapshot value) {
    _snapshot = value;
    if (!_controller.isClosed) _controller.add(value);
  }

  String get _masterLocaleCode =>
      _validLocaleCode(_localizationService?.getLocale().languageCode) ?? 'en';

  static String? _validLocaleCode(String? value) {
    final normalized = value?.trim().toLowerCase();
    return const {'ar', 'en', 'fr'}.contains(normalized) ? normalized : null;
  }
}

class _DiscoveredMaster {
  const _DiscoveredMaster(this.host, this.port);

  final String host;
  final int port;
}

class _JsonResponse {
  const _JsonResponse(this.statusCode, this.body);
  final int statusCode;
  final Map<String, dynamic> body;
}

class _AuthorizedDevice {
  const _AuthorizedDevice(this.id, this.data);

  final String id;
  final Map<String, dynamic> data;

  String get name => data['name']?.toString() ?? 'Tapix device';
}

class _LoginChallenge {
  const _LoginChallenge({
    required this.id,
    required this.deviceId,
    required this.username,
    required this.nonce,
    required this.verifier,
    required this.account,
    required this.expiresAt,
  });

  final String id;
  final String deviceId;
  final String username;
  final String nonce;
  final String verifier;
  final LanAuthAccount? account;
  final DateTime expiresAt;
}

class _MasterUserSession {
  _MasterUserSession({
    required this.deviceId,
    required this.user,
    required this.signedInAt,
    required this.expiresAt,
  });

  final String deviceId;
  LanRemoteUser user;
  final DateTime signedInAt;
  final DateTime expiresAt;
}
