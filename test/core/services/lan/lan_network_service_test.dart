import 'dart:convert';
import 'package:bcrypt/bcrypt.dart';
import 'package:crypto/crypto.dart';
import 'package:tapix/core/services/business/local_branch_scope.dart';
import 'package:tapix/core/services/lan/lan_tls_identity.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/database/daos/settings_dao.dart';
import 'package:tapix/core/services/audit_log_service.dart';
import 'package:tapix/core/services/lan/lan_network_service.dart';
import 'package:tapix/core/services/localization_service.dart';
import 'package:tapix/features/auth/data/services/lan_master_auth_gateway.dart';
import 'package:tapix/features/auth/data/services/password_service.dart';
import 'package:tapix/features/auth/data/services/permission_service.dart';
import 'package:tapix/features/auth/domain/entities/permission_constants.dart';

void main() {
  late AppDatabase masterDb;
  late AppDatabase clientDb;
  late LanNetworkService master;
  late LanNetworkService client;
  late LocalizationService masterLocalization;
  late _FakeBusinessGateway businessGateway;

  Future<int> addMasterUser({
    required String username,
    required String password,
    required String role,
  }) {
    final now = DateTime.now();
    return masterDb
        .into(masterDb.users)
        .insert(
          UsersCompanion.insert(
            username: username,
            passwordHash: PasswordService().hashPassword(password),
            role: role,
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  Future<void> pairClient([String name = 'Test cashier']) async {
    await master.startMaster(port: 0);
    final result = await client.pairWithMaster(
      host: '127.0.0.1',
      port: master.snapshot.port,
      pairingCode: master.snapshot.pairingCode!,
      deviceName: name,
    );
    expect(result.success, isTrue, reason: result.message);
  }

  Future<({int status, Map<String, dynamic> body})> rawRequest({
    String path = '/v1/business/scope',
    String method = 'GET',
    Map<String, String> headers = const {},
    Map<String, dynamic>? body,
    String? userToken,
    bool authorizeDevice = true,
  }) async {
    final http = HttpClient();
    final fingerprint = master.snapshot.pairingCode!.split(':').last;
    http.badCertificateCallback = (certificate, host, port) =>
        sha256.convert(certificate.der).toString() == fingerprint;
    try {
      final request = await http.openUrl(
        method,
        Uri.parse('https://127.0.0.1:${master.snapshot.port}$path'),
      );
      if (authorizeDevice) {
        final token = await SettingsDao(
          clientDb,
        ).getSetting('lan.client_token.v2');
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }
      if (userToken != null) {
        request.headers.set('X-Tapix-User-Session', userToken);
      }
      headers.forEach(request.headers.set);
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }
      final response = await request.close();
      final decoded = jsonDecode(await utf8.decoder.bind(response).join());
      return (
        status: response.statusCode,
        body: Map<String, dynamic>.from(decoded as Map),
      );
    } finally {
      http.close(force: true);
    }
  }

  Future<String> rawLogin() async {
    await addMasterUser(
      username: 'scope-manager',
      password: 'scope-password',
      role: 'manager',
    );
    final challenge = await rawRequest(
      method: 'POST',
      path: '/v1/auth/challenge',
      body: {'username': 'scope-manager'},
    );
    expect(challenge.status, 200);
    final id = challenge.body['challengeId'];
    final nonce = challenge.body['nonce'];
    final deviceId = await SettingsDao(clientDb).getSetting('lan.device_id');
    final verifier = BCrypt.hashpw(
      'scope-password',
      challenge.body['salt'] as String,
    );
    final proof = Hmac(
      sha256,
      utf8.encode(verifier),
    ).convert(utf8.encode('$id:$nonce:$deviceId')).toString();
    final login = await rawRequest(
      method: 'POST',
      path: '/v1/auth/login',
      body: {'challengeId': id, 'proof': proof},
    );
    expect(login.status, 200);
    return login.body['sessionToken'] as String;
  }

  Future<void> modifyStoredBinding(
    Object? Function(Map<String, dynamic>) update, {
    bool legacy = false,
  }) async {
    await master.stop();
    final settings = SettingsDao(masterDb);
    final devices =
        jsonDecode((await settings.getSetting('lan.authorized_devices.v2'))!)
            as Map<String, dynamic>;
    for (final value in devices.values) {
      final device = value as Map<String, dynamic>;
      final replacement = update(device);
      if (replacement == null) {
        device.remove('businessScope');
      } else {
        device['businessScope'] = replacement;
      }
    }
    await settings.saveSetting(
      'lan.authorized_devices.v2',
      jsonEncode(devices),
    );
    if (legacy) {
      await (masterDb.delete(
        masterDb.appSettings,
      )..where((s) => s.key.equals('lan.scope_binding.v1'))).go();
    }
    await master.initialize();
  }

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    masterDb = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    clientDb = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    final gateway = LanMasterAuthGatewayImpl(
      database: masterDb,
      permissionService: PermissionService(),
      auditLogService: AuditLogService(masterDb),
    );
    businessGateway = _FakeBusinessGateway();
    SharedPreferences.setMockInitialValues({'locale_code': 'ar'});
    masterLocalization = LocalizationService(
      await SharedPreferences.getInstance(),
    );
    master = LanNetworkService(
      SettingsDao(masterDb),
      authGateway: gateway,
      businessGateway: businessGateway,
      localizationService: masterLocalization,
    );
    client = LanNetworkService(SettingsDao(clientDb));
    await master.initialize();
    await client.initialize();
  });

  tearDown(() async {
    await client.stop();
    await master.stop();
    await clientDb.close();
    await masterDb.close();
  });

  test(
    'checkout balance and points require a paired authenticated cashier',
    () async {
      await pairClient();
      expect(
        (await rawRequest(
          path: '/v1/customers/3/checkout',
          authorizeDevice: false,
        )).status,
        401,
      );
      expect((await rawRequest(path: '/v1/customers/3/checkout')).status, 401);
      final user = await addMasterUser(
        username: 'checkout',
        password: 'checkout-secret',
        role: 'cashier',
      );
      expect(
        (await client.loginToMaster(
          username: 'checkout',
          password: 'checkout-secret',
        )).success,
        isTrue,
      );
      final result = await client.fetchRemoteCustomerCheckout(3);
      expect(result.balanceCents, 12345);
      expect(result.pointsBalance, 765);
      expect(result.currencyCode, 'USD');
      await (masterDb.update(masterDb.users)..where((u) => u.id.equals(user)))
          .write(const UsersCompanion(isActive: Value(0)));
      await expectLater(
        client.fetchRemoteCustomerCheckout(3),
        throwsA(isA<LanBusinessException>()),
      );
    },
  );

  test(
    'customer directory minimizes financial data and checkout requires sales access',
    () async {
      await pairClient();
      await addMasterUser(
        username: 'directory-accountant',
        password: 'accountant-secret',
        role: 'accountant',
      );
      expect(
        (await client.loginToMaster(
          username: 'directory-accountant',
          password: 'accountant-secret',
        )).success,
        isTrue,
      );

      final customers = await client.fetchRemoteCustomers();
      expect(customers.single.name, 'Network Customer');
      expect(
        customers.single.balanceCents,
        0,
        reason: 'Directory DTO must not disclose the stored balance.',
      );
      await expectLater(
        client.fetchRemoteCustomerCheckout(3),
        throwsA(
          isA<LanBusinessException>().having(
            (error) => error.code,
            'code',
            'permission_denied',
          ),
        ),
      );

      final token = await rawLogin();
      final directory = await rawRequest(
        path: '/v1/customers',
        userToken: token,
      );
      expect(directory.status, 200);
      final row = (directory.body['customers'] as List).single as Map;
      expect(row, isNot(contains('balanceCents')));

      final checkout = await rawRequest(
        path: '/v1/customers/3/checkout',
        userToken: token,
      );
      expect(checkout.status, 200);
      expect(checkout.body['balanceCents'], 12345);
      expect(checkout.body['pointsBalance'], 765);
    },
  );

  test(
    'master rejects a wrong code then pairs and authenticates a client device',
    () async {
      await master.startMaster(port: 0);

      expect(master.snapshot.mode, LanMode.master);
      expect(master.snapshot.status, LanConnectionStatus.online);
      expect(master.snapshot.port, greaterThan(0));
      expect(master.snapshot.pairingCode, matches(r'^[0-9]{6}:[a-f0-9]{64}$'));

      final rejected = await client.pairWithMaster(
        host: '127.0.0.1',
        port: master.snapshot.port,
        pairingCode: '000000:${master.snapshot.pairingCode!.split(':').last}',
        deviceName: 'Test cashier',
      );
      expect(rejected.success, isFalse);
      expect(master.snapshot.pairedDevices, 0);

      final unchangedCode = master.snapshot.pairingCode!;
      final invalidMetadata = await rawRequest(
        method: 'POST',
        path: '/v1/pair',
        authorizeDevice: false,
        body: {
          'pairingCode': unchangedCode,
          'deviceId': 'invalid-name-device',
          'deviceName': List.filled(81, 'x').join(),
          'platform': 'linux',
        },
      );
      expect(invalidMetadata.status, 400);
      expect(master.snapshot.pairedDevices, 0);
      expect(
        master.snapshot.pairingCode,
        unchangedCode,
        reason: 'Invalid metadata must not consume a valid one-time code.',
      );

      final correctCode = master.snapshot.pairingCode!;
      final paired = await client.pairWithMaster(
        host: '127.0.0.1',
        port: master.snapshot.port,
        pairingCode: correctCode,
        deviceName: 'Test cashier',
      );

      expect(paired.success, isTrue, reason: paired.message);
      expect(paired.masterId, isNotEmpty);
      expect(client.snapshot.mode, LanMode.client);
      expect(client.snapshot.status, LanConnectionStatus.paired);
      expect(master.snapshot.pairedDevices, 1);
      expect(master.snapshot.connectedDevices, 1);
      expect(master.snapshot.pairingCode, isNot(correctCode));
      expect(await client.testConnection(), isTrue);

      final audit = await masterDb.select(masterDb.auditLogs).get();
      expect(audit.map((row) => row.action), contains('device_paired'));
    },
  );

  test('client follows the master locale on pairing and reconnect', () async {
    await pairClient();

    expect(client.snapshot.masterLocaleCode, 'ar');

    await masterLocalization.setLocale(const Locale('fr'));
    expect(await client.testConnection(), isTrue);
    expect(client.snapshot.masterLocaleCode, 'fr');
  });

  test(
    'master account logs in without sending the password and logout is audited',
    () async {
      final cashierId = await addMasterUser(
        username: 'cashier-1',
        password: 'cashier-secret',
        role: 'cashier',
      );
      await pairClient('Linux POS');

      final rejected = await client.loginToMaster(
        username: 'cashier-1',
        password: 'wrong-password',
      );
      expect(rejected.success, isFalse);
      expect(client.remoteUser, isNull);

      final accepted = await client.loginToMaster(
        username: 'cashier-1',
        password: 'cashier-secret',
      );
      expect(accepted.success, isTrue);
      expect(accepted.user?.id, cashierId);
      expect(accepted.user?.role, 'cashier');
      expect(accepted.user?.permissions, contains(Permissions.processSales));
      expect(client.hasRemoteUserSession, isTrue);
      expect(await client.validateRemoteSession(), isTrue);

      await client.logoutFromMaster();
      expect(client.remoteUser, isNull);
      expect(client.hasRemoteUserSession, isFalse);

      final audit = await (masterDb.select(
        masterDb.auditLogs,
      )..where((row) => row.targetTable.equals('lan_session'))).get();
      final actions = audit.map((row) => row.action).toList();
      expect(actions, containsAll(['login_failed', 'login', 'logout']));
      final failed = audit.firstWhere((row) => row.action == 'login_failed');
      expect(failed.userId, isNull);
      final login = audit.firstWhere((row) => row.action == 'login');
      expect(login.userId, cashierId);
      expect(login.changes['deviceName'], 'Linux POS');
    },
  );

  test(
    'master manages device sessions separately from device authorization',
    () async {
      final ownerId = await addMasterUser(
        username: 'owner-1',
        password: 'owner-secret',
        role: 'owner',
      );
      final cashierId = await addMasterUser(
        username: 'cashier-1',
        password: 'cashier-secret',
        role: 'cashier',
      );
      await pairClient('Linux register');

      var device = master.getMasterDevices().single;
      expect(device.name, 'Linux register');
      expect(device.isConnected, isTrue);
      expect(device.platform, Platform.operatingSystem);
      expect(device.remoteAddress, isNotEmpty);
      expect(device.hasUserSession, isFalse);
      expect(device.scopeVerified, isTrue);
      expect(device.branchName, isNotEmpty);
      expect(device.warehouseName, isNotEmpty);

      expect(
        (await client.loginToMaster(
          username: 'cashier-1',
          password: 'cashier-secret',
        )).success,
        isTrue,
      );
      device = master.getMasterDevices().single;
      expect(device.userId, cashierId);
      expect(device.username, 'cashier-1');
      expect(device.sessionStartedAt, isNotNull);

      expect(
        await master.logoutMasterDevice(
          deviceId: device.id,
          actorUserId: ownerId,
          actorUsername: 'owner-1',
          reason: 'End unattended session',
        ),
        isTrue,
      );
      expect(master.getMasterDevices().single.hasUserSession, isFalse);
      expect(await client.validateRemoteSession(), isFalse);

      expect(
        (await client.loginToMaster(
          username: 'cashier-1',
          password: 'cashier-secret',
        )).success,
        isTrue,
      );
      expect(
        await master.renameMasterDevice(
          deviceId: device.id,
          name: 'Front register',
          actorUserId: ownerId,
          actorUsername: 'owner-1',
        ),
        isTrue,
      );
      expect(master.getMasterDevices().single.name, 'Front register');

      expect(
        await master.revokeMasterDevice(
          deviceId: device.id,
          actorUserId: ownerId,
          actorUsername: 'owner-1',
          reason: 'Device retired',
        ),
        isTrue,
      );
      expect(master.getMasterDevices(), isEmpty);
      expect(master.snapshot.pairedDevices, 0);
      expect(await client.testConnection(), isFalse);
      expect(client.hasRemoteUserSession, isFalse);
      expect(client.remoteUser, isNull);

      final audit = await (masterDb.select(
        masterDb.auditLogs,
      )..where((row) => row.targetTable.equals('lan_session'))).get();
      final actions = audit.map((row) => row.action).toList();
      expect(
        actions,
        containsAll([
          'device_remote_logout',
          'device_renamed',
          'device_revoked',
        ]),
      );
      expect(
        audit
            .where(
              (row) =>
                  row.action == 'device_remote_logout' ||
                  row.action == 'device_renamed' ||
                  row.action == 'device_revoked',
            )
            .every((row) => row.userId == ownerId),
        isTrue,
      );
    },
  );

  test(
    'two paired clients keep isolated sessions and revocation affects only its device',
    () async {
      final ownerId = await addMasterUser(
        username: 'multi-owner',
        password: 'owner-secret',
        role: 'owner',
      );
      await addMasterUser(
        username: 'front-cashier',
        password: 'front-secret',
        role: 'cashier',
      );
      await addMasterUser(
        username: 'back-cashier',
        password: 'back-secret',
        role: 'cashier',
      );
      await pairClient('Front register');

      final secondDb = AppDatabase.connect(
        DatabaseConnection(NativeDatabase.memory()),
      );
      final secondClient = LanNetworkService(SettingsDao(secondDb));
      try {
        await secondClient.initialize();
        final secondPair = await secondClient.pairWithMaster(
          host: '127.0.0.1',
          port: master.snapshot.port,
          pairingCode: master.snapshot.pairingCode!,
          deviceName: 'Back register',
        );
        expect(secondPair.success, isTrue, reason: secondPair.message);
        expect(master.snapshot.pairedDevices, 2);
        expect(master.getMasterDevices(), hasLength(2));

        expect(
          (await client.loginToMaster(
            username: 'front-cashier',
            password: 'front-secret',
          )).success,
          isTrue,
        );
        expect(
          (await secondClient.loginToMaster(
            username: 'back-cashier',
            password: 'back-secret',
          )).success,
          isTrue,
        );
        await client.openOwnRemoteShift(openingCashCents: 10000);
        await secondClient.openOwnRemoteShift(openingCashCents: 8000);

        const frontSale = LanSaleRequest(
          idempotencyKey: 'multi-client-front-sale-001',
          paymentMethod: 'cash',
          paidAmountCents: 250,
          lines: [LanSaleLineRequest(productId: 7, quantity: 1)],
        );
        const backSale = LanSaleRequest(
          idempotencyKey: 'multi-client-back-sale-001',
          paymentMethod: 'cash',
          paidAmountCents: 250,
          lines: [LanSaleLineRequest(productId: 7, quantity: 1)],
        );
        await Future.wait([
          client.submitRemoteSale(frontSale),
          secondClient.submitRemoteSale(backSale),
        ]);
        expect(
          businessGateway.createdKeys,
          containsAll([frontSale.idempotencyKey, backSale.idempotencyKey]),
        );

        final frontDevice = master.getMasterDevices().singleWhere(
          (device) => device.name == 'Front register',
        );
        expect(
          await master.revokeMasterDevice(
            deviceId: frontDevice.id,
            actorUserId: ownerId,
            actorUsername: 'multi-owner',
            reason: 'Register removed from this branch',
          ),
          isTrue,
        );
        expect(master.getMasterDevices(), hasLength(1));
        expect(await client.testConnection(), isFalse);
        expect(await secondClient.testConnection(), isTrue);
        expect(await secondClient.validateRemoteSession(), isTrue);

        final replay = await secondClient.submitRemoteSale(backSale);
        expect(replay.duplicate, isTrue);
        expect(businessGateway.createdKeys, hasLength(2));
      } finally {
        await secondClient.stop();
        await secondDb.close();
      }
    },
  );

  test('a manager can replace a cashier session on the same device', () async {
    await addMasterUser(
      username: 'cashier-1',
      password: 'cashier-secret',
      role: 'cashier',
    );
    final managerId = await addMasterUser(
      username: 'manager-1',
      password: 'manager-secret',
      role: 'manager',
    );
    await pairClient();

    expect(
      (await client.loginToMaster(
        username: 'cashier-1',
        password: 'cashier-secret',
      )).success,
      isTrue,
    );
    final managerLogin = await client.loginToMaster(
      username: 'manager-1',
      password: 'manager-secret',
    );

    expect(managerLogin.success, isTrue);
    expect(client.remoteUser?.id, managerId);
    expect(client.remoteUser?.role, 'manager');

    final audit = await (masterDb.select(
      masterDb.auditLogs,
    )..where((row) => row.targetTable.equals('lan_session'))).get();
    expect(audit.map((row) => row.action), contains('session_replaced'));
  });

  test(
    'disabling a master account revokes its LAN session immediately',
    () async {
      final userId = await addMasterUser(
        username: 'accountant-1',
        password: 'accountant-secret',
        role: 'accountant',
      );
      await pairClient();

      final login = await client.loginToMaster(
        username: 'accountant-1',
        password: 'accountant-secret',
      );
      expect(login.success, isTrue);

      await (masterDb.update(masterDb.users)
            ..where((user) => user.id.equals(userId)))
          .write(const UsersCompanion(isActive: Value(0)));

      expect(await client.validateRemoteSession(), isFalse);
      expect(client.remoteUser, isNull);

      final audit = await (masterDb.select(
        masterDb.auditLogs,
      )..where((row) => row.targetTable.equals('lan_session'))).get();
      expect(audit.map((row) => row.action), contains('session_revoked'));
    },
  );

  test(
    'role changes refresh permissions on the next authenticated request',
    () async {
      final userId = await addMasterUser(
        username: 'role-change-user',
        password: 'role-change-secret',
        role: 'cashier',
      );
      await pairClient('Role refresh register');
      expect(
        (await client.loginToMaster(
          username: 'role-change-user',
          password: 'role-change-secret',
        )).success,
        isTrue,
      );
      expect((await client.fetchRemoteCustomerCheckout(3)).balanceCents, 12345);

      await (masterDb.update(
        masterDb.users,
      )..where((row) => row.id.equals(userId))).write(
        UsersCompanion(
          role: const Value('accountant'),
          updatedAt: Value(DateTime.now()),
        ),
      );

      await expectLater(
        client.fetchRemoteCustomerCheckout(3),
        throwsA(
          isA<LanBusinessException>().having(
            (error) => error.code,
            'code',
            'permission_denied',
          ),
        ),
      );
      expect(await client.validateRemoteSession(), isTrue);
      expect(client.remoteUser?.role, 'accountant');
      expect(client.remoteUser?.permissions, isNot(contains('process_sales')));
    },
  );

  test(
    'five failed passwords temporarily rate-limit the paired device',
    () async {
      await addMasterUser(
        username: 'cashier-1',
        password: 'cashier-secret',
        role: 'cashier',
      );
      await pairClient();

      for (var attempt = 0; attempt < 5; attempt++) {
        final rejected = await client.loginToMaster(
          username: 'cashier-1',
          password: 'wrong-password',
        );
        expect(rejected.success, isFalse);
      }
      final limited = await client.loginToMaster(
        username: 'cashier-1',
        password: 'cashier-secret',
      );
      expect(limited.success, isFalse);

      final audit = await (masterDb.select(
        masterDb.auditLogs,
      )..where((row) => row.targetTable.equals('lan_session'))).get();
      expect(audit.where((row) => row.action == 'login_failed'), hasLength(5));
      expect(audit.map((row) => row.action), contains('login_rate_limited'));
    },
  );

  test('cashier opens and closes only their remote shift', () async {
    await addMasterUser(
      username: 'cashier-1',
      password: 'cashier-secret',
      role: 'cashier',
    );
    await pairClient('Linux POS');
    expect(
      (await client.loginToMaster(
        username: 'cashier-1',
        password: 'cashier-secret',
      )).success,
      isTrue,
    );

    expect(await client.fetchOwnRemoteShift(), isNull);
    final opened = await client.openOwnRemoteShift(openingCashCents: 12500);
    expect(opened.isOpen, isTrue);
    expect(opened.openingCashCents, 12500);
    expect((await client.fetchOwnRemoteShift())?.id, opened.id);
    final retriedOpen = await client.openOwnRemoteShift(
      openingCashCents: 12500,
    );
    expect(retriedOpen.id, opened.id);

    final closed = await client.closeOwnRemoteShift(
      shiftId: opened.id,
      countedCashCents: 12400,
      notes: 'Counted at logout',
    );
    expect(closed.isOpen, isFalse);
    final retriedClose = await client.closeOwnRemoteShift(
      shiftId: opened.id,
      countedCashCents: 12400,
      notes: ' Counted at logout ',
    );
    expect(retriedClose.id, closed.id);
    expect(retriedClose.isOpen, isFalse);
    expect(await client.fetchOwnRemoteShift(), isNull);

    final audit = await masterDb.select(masterDb.auditLogs).get();
    expect(
      audit.map((row) => row.action),
      containsAll(['cashier_shift_opened', 'cashier_shift_closed']),
    );
  });

  test(
    'cashier reads master catalog and safely retries one network sale',
    () async {
      await addMasterUser(
        username: 'cashier-1',
        password: 'cashier-secret',
        role: 'cashier',
      );
      await pairClient('Linux POS');
      expect(
        (await client.loginToMaster(
          username: 'cashier-1',
          password: 'cashier-secret',
        )).success,
        isTrue,
      );

      final catalog = await client.fetchRemoteCatalog(query: 'Milk');
      expect(catalog.products.single.name, 'Milk');
      expect(catalog.products.single.stockQuantity, 2500);
      expect(catalog.products.single.costCents, isNull);
      expect(catalog.enablePharmacyFeatures, isTrue);
      expect(
        catalog.products.single.medicine?.ingredients.single.canonicalName,
        'ibuprofen',
      );
      expect(catalog.products.single.toJson(), isNot(contains('costCents')));

      final sourceSnapshot = await client.fetchRemoteInventoryStockSources(
        productId: 7,
      );
      expect(sourceSnapshot.productId, 7);
      expect(sourceSnapshot.physicalQuantity, 2);
      expect(sourceSnapshot.consignmentQuantity, 1);
      expect(sourceSnapshot.sources.single.isConsignment, isTrue);
      expect(
        sourceSnapshot.sources.single.sourceCode,
        'C-11111111-1111-4111-8111-111111111111',
      );

      final alternatives = await client.fetchRemoteMedicineAlternatives(7);
      expect(alternatives.sourceProductId, 7);
      expect(alternatives.alternatives.single.id, 8);
      expect(
        alternatives
            .alternatives
            .single
            .medicine
            ?.ingredients
            .single
            .canonicalName,
        'ibuprofen',
      );
      expect(
        alternatives.alternatives.single.toJson(),
        isNot(contains('costCents')),
      );

      final managementCatalog = await client.fetchRemoteCatalog(
        management: true,
      );
      expect(managementCatalog.products.single.minQuantity, 500);
      expect(
        managementCatalog.products.single.costCents,
        isNull,
        reason: 'A cashier must never receive product cost over LAN',
      );
      final customers = await client.fetchRemoteCustomers();
      expect(customers.single.name, 'Network Customer');

      const request = LanSaleRequest(
        idempotencyKey: 'lan-sale-safe-retry-001',
        paymentMethod: 'cash',
        paidAmountCents: 250,
        lines: [
          LanSaleLineRequest(
            productId: 7,
            quantity: 500,
            discountType: 'percentage',
            discountValue: 1000,
          ),
        ],
      );
      await expectLater(
        client.submitRemoteSale(request),
        throwsA(
          isA<LanBusinessException>().having(
            (error) => error.code,
            'code',
            'shift_required',
          ),
        ),
      );
      await client.openOwnRemoteShift(openingCashCents: 10000);

      businessGateway.nextSaleError = const LanBusinessException(
        'sale_below_cost',
        'The discount would sell an item below its recorded cost.',
        statusCode: 409,
        details: {
          'lineIndex': 0,
          'productId': 7,
          'productName': 'Milk',
          'canOverride': false,
        },
      );
      try {
        await client.submitRemoteSale(request);
        fail('The below-cost request should have been rejected.');
      } on LanBusinessException catch (error) {
        expect(error.code, 'sale_below_cost');
        expect(error.details['lineIndex'], 0);
        expect(error.details['productId'], 7);
        expect(error.details['productName'], 'Milk');
        expect(error.details['canOverride'], isFalse);
        expect(
          error.details,
          isNot(contains('costCents')),
          reason: 'A cashier must not receive cost through an error response',
        );
      }

      final activities = <LanMasterActivityEvent>[];
      final activitySub = master.masterActivityEvents.listen(activities.add);
      addTearDown(activitySub.cancel);
      final created = await client.submitRemoteSale(request);
      final replayed = await client.submitRemoteSale(request);
      await Future<void>.delayed(Duration.zero);

      expect(activities, hasLength(1));
      expect(activities.single.type, LanMasterActivityType.sale);
      expect(activities.single.actorName, 'cashier-1');
      expect(activities.single.deviceName, 'Linux POS');
      expect(activities.single.documentNumber, 'SI-202608-0044');
      expect(activities.single.totalCents, 250);
      expect(created.saleId, replayed.saleId);
      expect(created.duplicate, isFalse);
      expect(replayed.duplicate, isTrue);
      expect(businessGateway.createdKeys, hasLength(1));
      expect(
        businessGateway.lastRequest?.lines.single.discountType,
        'percentage',
      );
      expect(businessGateway.lastRequest?.lines.single.discountValue, 1000);

      final audit = await masterDb.select(masterDb.auditLogs).get();
      expect(
        audit.map((row) => row.action),
        containsAll(['remote_sale_created', 'remote_sale_replayed']),
      );
    },
  );

  test('cashier securely downloads a product image from the master', () async {
    await addMasterUser(
      username: 'cashier-image',
      password: 'cashier-secret',
      role: 'cashier',
    );
    await pairClient('Linux image POS');
    expect(
      (await client.loginToMaster(
        username: 'cashier-image',
        password: 'cashier-secret',
      )).success,
      isTrue,
    );

    final directory = await Directory.systemTemp.createTemp('tapix-lan-image-');
    try {
      final bytes = <int>[137, 80, 78, 71, 13, 10, 26, 10, 1, 2, 3, 4];
      final image = File('${directory.path}/product.png');
      await image.writeAsBytes(bytes);
      businessGateway.productImagePath = image.path;

      final catalog = await client.fetchRemoteCatalog();
      expect(catalog.products.single.hasImage, isTrue);
      expect(await client.fetchRemoteProductImage(7), bytes);
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('accountant can inspect catalog but cannot submit a LAN sale', () async {
    await addMasterUser(
      username: 'accountant-1',
      password: 'accountant-secret',
      role: 'accountant',
    );
    await pairClient();
    expect(
      (await client.loginToMaster(
        username: 'accountant-1',
        password: 'accountant-secret',
      )).success,
      isTrue,
    );

    expect((await client.fetchRemoteCatalog()).products, isNotEmpty);
    final salesPage = await client.fetchRemoteSales();
    expect(salesPage.sales.single.invoiceNumber, 'SI-202608-0044');
    expect(salesPage.sales.single.employeeName, 'Cashier One');
    expect(salesPage.stats.totalSalesCents, 250);
    expect(salesPage.saleIdsWithReturns, contains(44));
    expect(salesPage.productSearchTerms[44], contains('MILK-1'));
    final saleDetails = await client.fetchRemoteSaleDetails(44);
    expect(saleDetails.sale.invoiceNumber, 'SI-202608-0044');
    expect(saleDetails.lines.single.productName, 'Milk');
    expect(saleDetails.lines.single.quantity, 500);
    expect(saleDetails.cashierName, 'Cashier One');
    expect(saleDetails.toJson().toString(), isNot(contains('costCents')));
    final managementCatalog = await client.fetchRemoteCatalog(management: true);
    expect(managementCatalog.products.single.minQuantity, 500);
    expect(managementCatalog.products.single.costCents, 275);
    await expectLater(
      client.submitRemoteSale(
        const LanSaleRequest(
          idempotencyKey: 'forbidden-sale-001',
          paymentMethod: 'cash',
          paidAmountCents: 250,
          lines: [LanSaleLineRequest(productId: 7, quantity: 500)],
        ),
      ),
      throwsA(
        isA<LanBusinessException>()
            .having((error) => error.statusCode, 'statusCode', 403)
            .having((error) => error.code, 'code', 'permission_denied'),
      ),
    );
    expect(businessGateway.createdKeys, isEmpty);
  });

  test('cashier securely reads only returnable sale snapshots', () async {
    await addMasterUser(
      username: 'cashier-returns',
      password: 'cashier-secret',
      role: 'cashier',
    );
    await pairClient();
    expect(
      (await client.loginToMaster(
        username: 'cashier-returns',
        password: 'cashier-secret',
      )).success,
      isTrue,
    );

    final page = await client.fetchRemoteReturnableSales(query: '0044');
    expect(page.sales.single.invoiceNumber, 'SI-202608-0044');
    final details = await client.fetchRemoteReturnableSale(44);
    expect(details.lines.single.availableQuantity, 750);
    expect(details.lines.single.measurementType, 'volume');
  });

  test('cashier cannot void a master sale', () async {
    await addMasterUser(
      username: 'cashier-no-void',
      password: 'cashier-secret',
      role: 'cashier',
    );
    await pairClient();
    expect(
      (await client.loginToMaster(
        username: 'cashier-no-void',
        password: 'cashier-secret',
      )).success,
      isTrue,
    );

    await expectLater(
      client.voidRemoteSale(44),
      throwsA(
        isA<LanBusinessException>()
            .having((error) => error.statusCode, 'statusCode', 403)
            .having((error) => error.code, 'code', 'permission_denied'),
      ),
    );
    expect(businessGateway.voidedSaleId, isNull);
  });

  test(
    'manager can void a master sale and the action reaches the gateway',
    () async {
      await addMasterUser(
        username: 'manager-void',
        password: 'manager-secret',
        role: 'manager',
      );
      await pairClient();
      expect(
        (await client.loginToMaster(
          username: 'manager-void',
          password: 'manager-secret',
        )).success,
        isTrue,
      );

      final result = await client.voidRemoteSale(44);
      expect(result.status, 'voided');
      expect(businessGateway.voidedSaleId, 44);
    },
  );

  test(
    'cashier lists returns and safely retries one network sale return',
    () async {
      await addMasterUser(
        username: 'cashier-return-write',
        password: 'cashier-secret',
        role: 'cashier',
      );
      await pairClient();
      expect(
        (await client.loginToMaster(
          username: 'cashier-return-write',
          password: 'cashier-secret',
        )).success,
        isTrue,
      );

      final returns = await client.fetchRemoteSaleReturns();
      expect(returns.returns.single.returnNumber, 'SR-202608-0005');
      final returnDetails = await client.fetchRemoteSaleReturnDetails(
        returnId: 5,
        adjustment: false,
      );
      expect(returnDetails.summary.saleId, 44);
      expect(returnDetails.lines.single.productName, 'Milk');
      expect(returnDetails.lines.single.totalCents, 125);
      final activities = <LanMasterActivityEvent>[];
      final activitySub = master.masterActivityEvents.listen(activities.add);
      addTearDown(activitySub.cancel);

      const request = LanSaleReturnRequest(
        idempotencyKey: 'lan-sale-return-safe-retry-001',
        saleId: 44,
        dispositionType: 'restock',
        refundMethod: 'cash',
        lines: [LanSaleReturnLineRequest(saleItemId: 70, quantity: 250)],
      );
      final created = await client.submitRemoteSaleReturn(request);
      final replayed = await client.submitRemoteSaleReturn(request);
      await Future<void>.delayed(Duration.zero);

      expect(activities, hasLength(1));
      expect(activities.single.type, LanMasterActivityType.saleReturn);
      expect(activities.single.documentNumber, 'SR-202608-0005');
      expect(activities.single.totalCents, 125);
      expect(created.returnId, replayed.returnId);
      expect(created.duplicate, isFalse);
      expect(replayed.duplicate, isTrue);
      expect(businessGateway.createdReturnKeys, hasLength(1));
      expect(businessGateway.lastReturnRequest?.lines.single.quantity, 250);

      final audit = await masterDb.select(masterDb.auditLogs).get();
      expect(
        audit.map((row) => row.action),
        containsAll([
          'remote_sale_return_created',
          'remote_sale_return_replayed',
        ]),
      );
    },
  );

  test('cashier safely retries one network sale adjustment return', () async {
    await addMasterUser(
      username: 'cashier-adjustment-return',
      password: 'cashier-secret',
      role: 'cashier',
    );
    await pairClient();
    expect(
      (await client.loginToMaster(
        username: 'cashier-adjustment-return',
        password: 'cashier-secret',
      )).success,
      isTrue,
    );

    final activities = <LanMasterActivityEvent>[];
    final activitySub = master.masterActivityEvents.listen(activities.add);
    addTearDown(activitySub.cancel);
    final request = LanSaleAdjustmentReturnRequest(
      idempotencyKey: 'lan-sale-adjustment-safe-retry-001',
      refundMethod: 'cash',
      returnDate: DateTime.utc(2026, 8, 25),
      reasonCode: 'noReceipt',
      payments: [
        LanCheckoutPaymentRequest(
          method: 'cheque',
          amountCents: 100,
          reference: 'LAN-RETURN-CHK-1',
          dueDate: DateTime.utc(2026, 9, 25),
        ),
      ],
      lines: const [
        LanSaleAdjustmentReturnLineRequest(
          productId: 7,
          quantity: 500,
          unitPriceCents: 500,
        ),
      ],
    );
    final created = await client.submitRemoteSaleAdjustmentReturn(request);
    final replayed = await client.submitRemoteSaleAdjustmentReturn(request);
    await Future<void>.delayed(Duration.zero);

    expect(activities, hasLength(1));
    expect(activities.single.type, LanMasterActivityType.saleAdjustmentReturn);
    expect(activities.single.documentNumber, 'SRS-202608-0008');
    expect(activities.single.totalCents, 250);
    expect(created.returnId, replayed.returnId);
    expect(created.duplicate, isFalse);
    expect(replayed.duplicate, isTrue);
    expect(businessGateway.createdAdjustmentReturnKeys, hasLength(1));
    expect(
      businessGateway.lastAdjustmentReturnRequest?.lines.single.quantity,
      500,
    );
    expect(
      businessGateway.lastAdjustmentReturnRequest?.payments.single.reference,
      'LAN-RETURN-CHK-1',
    );

    final audit = await masterDb.select(masterDb.auditLogs).get();
    expect(
      audit.map((row) => row.action),
      containsAll([
        'remote_sale_adjustment_return_created',
        'remote_sale_adjustment_return_replayed',
      ]),
    );
  });

  test(
    'accountant can inspect purchase returns but cannot create or void them',
    () async {
      await addMasterUser(
        username: 'accountant-purchase-returns',
        password: 'accountant-secret',
        role: 'accountant',
      );
      await pairClient('Purchase returns viewer');
      expect(
        (await client.loginToMaster(
          username: 'accountant-purchase-returns',
          password: 'accountant-secret',
        )).success,
        isTrue,
      );

      expect((await client.fetchRemoteSuppliers()).single.id, 6);
      final purchases = await client.fetchRemoteReturnablePurchases();
      expect(purchases.purchases.single.purchaseId, 55);
      final purchase = await client.fetchRemoteReturnablePurchase(55);
      expect(purchase.lines.single.availableQuantity, 1500);
      final returns = await client.fetchRemotePurchaseReturns();
      expect(returns.returns.single.returnNumber, 'PR-202608-0009');
      final details = await client.fetchRemotePurchaseReturnDetails(
        returnId: 9,
        adjustment: false,
      );
      expect(details.lines.single.purchaseItemId, 88);

      await expectLater(
        client.submitRemotePurchaseReturn(
          const LanPurchaseReturnRequest(
            idempotencyKey: 'accountant-forbidden-purchase-return',
            purchaseId: 55,
            dispositionType: 'restock',
            refundMethod: 'credit',
            lines: [
              LanPurchaseReturnLineRequest(purchaseItemId: 88, quantity: 1000),
            ],
          ),
        ),
        throwsA(
          isA<LanBusinessException>()
              .having((error) => error.statusCode, 'statusCode', 403)
              .having((error) => error.code, 'code', 'permission_denied'),
        ),
      );
      await expectLater(
        client.voidRemotePurchaseReturn(returnId: 9, adjustment: false),
        throwsA(
          isA<LanBusinessException>()
              .having((error) => error.statusCode, 'statusCode', 403)
              .having((error) => error.code, 'code', 'permission_denied'),
        ),
      );
      expect(businessGateway.lastPurchaseReturnRequest, isNull);
      expect(businessGateway.voidedPurchaseReturnId, isNull);
    },
  );

  test('cashier cannot access purchase returns over LAN', () async {
    await addMasterUser(
      username: 'cashier-no-purchases',
      password: 'cashier-secret',
      role: 'cashier',
    );
    await pairClient('Cashier without purchase permission');
    expect(
      (await client.loginToMaster(
        username: 'cashier-no-purchases',
        password: 'cashier-secret',
      )).success,
      isTrue,
    );

    await expectLater(
      client.fetchRemotePurchaseReturns(),
      throwsA(
        isA<LanBusinessException>()
            .having((error) => error.statusCode, 'statusCode', 403)
            .having((error) => error.code, 'code', 'permission_denied'),
      ),
    );
  });

  test(
    'manager creates linked and adjustment purchase returns and can void',
    () async {
      await addMasterUser(
        username: 'manager-purchase-returns',
        password: 'manager-secret',
        role: 'manager',
      );
      await pairClient('Purchase returns manager');
      expect(
        (await client.loginToMaster(
          username: 'manager-purchase-returns',
          password: 'manager-secret',
        )).success,
        isTrue,
      );

      const linkedRequest = LanPurchaseReturnRequest(
        idempotencyKey: 'lan-purchase-return-safe-retry-001',
        purchaseId: 55,
        dispositionType: 'restock',
        refundMethod: 'credit',
        lines: [
          LanPurchaseReturnLineRequest(purchaseItemId: 88, quantity: 1000),
        ],
      );
      final created = await client.submitRemotePurchaseReturn(linkedRequest);
      final replayed = await client.submitRemotePurchaseReturn(linkedRequest);
      expect(created.returnId, replayed.returnId);
      expect(created.duplicate, isFalse);
      expect(replayed.duplicate, isTrue);
      expect(businessGateway.createdPurchaseReturnKeys, hasLength(1));

      final adjustment = await client.submitRemotePurchaseAdjustmentReturn(
        LanPurchaseAdjustmentReturnRequest(
          idempotencyKey: 'lan-purchase-adjustment-return-001',
          supplierId: 6,
          refundMethod: 'credit',
          returnDate: DateTime.utc(2026, 8, 25),
          reasonCode: 'other',
          lines: const [
            LanPurchaseAdjustmentReturnLineRequest(
              productId: 7,
              quantity: 1000,
              unitPriceCents: 500,
            ),
          ],
        ),
      );
      expect(adjustment.returnNumber, 'PRS-202608-0010');
      expect(
        businessGateway.lastPurchaseAdjustmentReturnRequest?.supplierId,
        6,
      );

      await client.voidRemotePurchaseReturn(
        returnId: created.returnId,
        adjustment: false,
      );
      expect(businessGateway.voidedPurchaseReturnId, created.returnId);

      final audit = await masterDb.select(masterDb.auditLogs).get();
      expect(
        audit.map((row) => row.action),
        containsAll([
          'remote_purchase_return_created',
          'remote_purchase_return_replayed',
        ]),
      );
    },
  );

  test(
    'standalone mode closes the master listener and persists the role',
    () async {
      await master.startMaster(port: 0);
      await master.setStandalone();

      expect(master.snapshot.mode, LanMode.standalone);
      expect(master.snapshot.status, LanConnectionStatus.idle);
      expect(
        await SettingsDao(masterDb).getSetting('lan.mode'),
        LanMode.standalone.name,
      );
    },
  );

  test(
    'client restores its authorized master connection after restart',
    () async {
      await pairClient('Restartable register');
      final port = master.snapshot.port;

      final restartedClient = LanNetworkService(SettingsDao(clientDb));
      final reconnected = restartedClient.changes.firstWhere(
        (snapshot) =>
            snapshot.mode == LanMode.client &&
            snapshot.status == LanConnectionStatus.paired,
      );
      await client.stop();
      client = restartedClient;
      await client.initialize();
      await reconnected.timeout(const Duration(seconds: 3));

      expect(client.snapshot.masterHost, '127.0.0.1');
      expect(client.snapshot.port, port);
      expect(client.snapshot.status, LanConnectionStatus.paired);
      expect(await client.testConnection(), isTrue);
    },
  );

  test('master restart does not report stale devices as connected', () async {
    await pairClient('Presence register');
    expect(master.snapshot.connectedDevices, 1);
    final port = master.snapshot.port;

    await master.stop();
    await master.startMaster(port: port);

    expect(master.snapshot.pairedDevices, 1);
    expect(master.snapshot.connectedDevices, 0);
    expect(master.getMasterDevices().single.isConnected, isFalse);

    expect(await client.testConnection(host: '127.0.0.1', port: port), isTrue);
    expect(master.snapshot.connectedDevices, 1);
    expect(master.getMasterDevices().single.isConnected, isTrue);
  });

  test(
    'remote device logout is idempotent when no user session exists',
    () async {
      final ownerId = await addMasterUser(
        username: 'owner-idempotent',
        password: 'owner-secret',
        role: 'owner',
      );
      await pairClient('Idle register');
      final device = master.getMasterDevices().single;

      expect(
        await master.logoutMasterDevice(
          deviceId: device.id,
          actorUserId: ownerId,
          actorUsername: 'owner-idempotent',
          reason: 'Ensure signed out',
        ),
        isTrue,
      );
    },
  );

  test('local logout succeeds when the master becomes unreachable', () async {
    await addMasterUser(
      username: 'cashier-offline',
      password: 'cashier-secret',
      role: 'cashier',
    );
    await pairClient('Offline register');
    expect(
      (await client.loginToMaster(
        username: 'cashier-offline',
        password: 'cashier-secret',
      )).success,
      isTrue,
    );

    await master.stop();
    await client.logoutFromMaster();

    expect(client.remoteUser, isNull);
    expect(client.hasRemoteUserSession, isFalse);
  });
  test('certificate identity survives recreating the master service', () async {
    await pairClient();
    final fingerprint = master.snapshot.pairingCode!.split(':').last;
    await master.stop();
    master = LanNetworkService(SettingsDao(masterDb));
    await master.initialize();
    expect(master.snapshot.pairingCode!.split(':').last, fingerprint);
    expect(await client.testConnection(), isTrue);
  });

  test(
    'a replacement server cannot receive existing session credentials',
    () async {
      await addMasterUser(
        username: 'tls-cashier',
        password: 'secret-password',
        role: 'cashier',
      );
      await pairClient();
      expect(
        (await client.loginToMaster(
          username: 'tls-cashier',
          password: 'secret-password',
        )).success,
        isTrue,
      );
      final port = master.snapshot.port;
      await master.stop();
      final identity = await LanTlsIdentity.loadOrCreate('different-device');
      final rogue = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        port,
        identity.context,
      );
      var requests = 0;
      rogue.listen((request) async {
        requests++;
        request.response.write('{}');
        await request.response.close();
      }, onError: (Object _) {});
      try {
        await expectLater(client.fetchRemoteCatalog(), throwsA(anything));
        expect(requests, 0);
      } finally {
        await rogue.close(force: true);
      }
    },
  );

  test(
    'paired device is bound to the master scope, not the client database',
    () async {
      await pairClient();
      final masterScope = await LocalBranchScope.read(masterDb);
      final clientScope = await LocalBranchScope.read(clientDb);
      expect(masterScope.databaseId, isNot(clientScope.databaseId));
      final stored =
          jsonDecode(
                (await SettingsDao(
                  masterDb,
                ).getSetting('lan.authorized_devices.v2'))!,
              )
              as Map;
      expect(
        masterScope.matchesBinding(
          (stored.values.single as Map)['businessScope'],
        ),
        isTrue,
      );
      expect(await client.testConnection(), isTrue);
    },
  );

  test(
    'scope endpoint requires both device authorization and a user session',
    () async {
      await pairClient();
      expect((await rawRequest(authorizeDevice: false)).status, 401);
      expect((await rawRequest()).status, 401);
      final token = await rawLogin();
      final response = await rawRequest(userToken: token);
      expect(response.status, 200);
      expect(
        response.body['scope'],
        (await LocalBranchScope.read(masterDb)).toJson(),
      );
      final health = await rawRequest(
        path: '/v1/health',
        authorizeDevice: false,
      );
      expect(health.body.containsKey('scope'), isFalse);
      expect(health.body.containsKey('branchId'), isFalse);
      expect(
        health.body['capabilities'],
        contains(LanNetworkService.consignmentSourceCapability),
      );
      expect(
        health.body['capabilities'],
        contains(LanNetworkService.consignmentAdjustmentReturnCapability),
      );
      expect(
        client.supportsCapability(
          LanNetworkService.consignmentAdjustmentReturnCapability,
        ),
        isTrue,
      );
    },
  );

  test(
    'even a manager cannot select another scope through headers, query or JSON',
    () async {
      await pairClient();
      final token = await rawLogin();
      final scope = await LocalBranchScope.read(masterDb);
      for (final entry in scope.toJson().entries) {
        expect(
          (await rawRequest(
            path: '/v1/business/scope?${entry.key}=foreign',
            userToken: token,
          )).status,
          403,
        );
      }
      expect(
        (await rawRequest(
          headers: {'X-Tapix-Branch-Id': 'foreign'},
          userToken: token,
        )).status,
        403,
      );
      expect(
        (await rawRequest(
          path:
              '/v1/business/scope?branchId=${scope.branchId}&branchId=foreign',
          userToken: token,
        )).status,
        403,
      );
      expect(
        (await rawRequest(
          method: 'POST',
          path: '/v1/shifts/open',
          userToken: token,
          body: {'warehouse_id': 'foreign'},
        )).status,
        403,
      );
      expect(businessGateway.currentShift, isNull);
      final matching = await rawRequest(
        path: '/v1/business/scope?warehouseId=${scope.warehouseId}',
        userToken: token,
      );
      expect(matching.status, 200);
    },
  );

  test(
    'a foreign or partial device binding is rejected without reassignment',
    () async {
      await pairClient();
      await modifyStoredBinding(
        (device) => {...device['businessScope'] as Map, 'branchId': 'foreign'},
      );
      expect(await client.testConnection(), isFalse);
      final saved =
          jsonDecode(
                (await SettingsDao(
                  masterDb,
                ).getSetting('lan.authorized_devices.v2'))!,
              )
              as Map;
      expect(
        ((saved.values.single as Map)['businessScope'] as Map)['branchId'],
        'foreign',
      );
    },
  );

  test('legacy TLS devices are bound once and keep their credential', () async {
    await pairClient();
    final token = await SettingsDao(clientDb).getSetting('lan.client_token.v2');
    await modifyStoredBinding((_) => null, legacy: true);
    expect(await client.testConnection(), isTrue);
    expect(
      await SettingsDao(clientDb).getSetting('lan.client_token.v2'),
      token,
    );
    final saved =
        jsonDecode(
              (await SettingsDao(
                masterDb,
              ).getSetting('lan.authorized_devices.v2'))!,
            )
            as Map;
    expect(
      (await LocalBranchScope.read(
        masterDb,
      )).matchesBinding((saved.values.single as Map)['businessScope']),
      isTrue,
    );
    await modifyStoredBinding((_) => null);
    expect(await client.testConnection(), isFalse);
  });

  test(
    'partial legacy bindings are never upgraded into authorization',
    () async {
      await pairClient();
      await modifyStoredBinding((_) => {'branchId': 'partial'}, legacy: true);
      expect(await client.testConnection(), isFalse);
    },
  );

  test(
    'deactivating the master warehouse stops authenticated network operations',
    () async {
      await pairClient();
      final token = await rawLogin();
      final scope = await LocalBranchScope.read(masterDb);
      await (masterDb.update(masterDb.businessWarehouses)
            ..where((w) => w.id.equals(scope.warehouseId)))
          .write(const BusinessWarehousesCompanion(isActive: Value(false)));
      expect((await rawRequest(userToken: token)).status, 503);
      expect(await client.testConnection(), isFalse);
      await (masterDb.update(masterDb.businessWarehouses)
            ..where((w) => w.id.equals(scope.warehouseId)))
          .write(const BusinessWarehousesCompanion(isActive: Value(true)));
      expect((await rawRequest(userToken: token)).status, 200);
    },
  );

  test(
    'legacy plaintext device tokens are not imported into TLS authorization',
    () async {
      await SettingsDao(masterDb).saveSetting(
        'lan.authorized_devices',
        jsonEncode({
          'legacy-device': {'tokenHash': 'legacy-hash', 'name': 'Old device'},
        }),
      );
      await master.initialize();
      await master.startMaster(port: 0);
      expect(master.snapshot.pairedDevices, 0);
    },
  );

  test(
    'warehouse transfers require owner role and preserve operation keys over TLS',
    () async {
      await master.stop();
      final transferGateway = _FakeWarehouseTransferBusinessGateway();
      master = LanNetworkService(
        SettingsDao(masterDb),
        authGateway: LanMasterAuthGatewayImpl(
          database: masterDb,
          permissionService: PermissionService(),
          auditLogService: AuditLogService(masterDb),
        ),
        businessGateway: transferGateway,
        localizationService: masterLocalization,
      );
      await master.initialize();

      await addMasterUser(
        username: 'transfer-cashier',
        password: 'cashier-secret',
        role: 'cashier',
      );
      await addMasterUser(
        username: 'transfer-owner',
        password: 'owner-secret',
        role: 'owner',
      );
      await pairClient('Warehouse terminal');

      expect(
        (await client.loginToMaster(
          username: 'transfer-cashier',
          password: 'cashier-secret',
        )).success,
        isTrue,
      );
      await expectLater(
        client.fetchRemoteTransferWarehouses(),
        throwsA(
          isA<LanBusinessException>().having(
            (error) => error.code,
            'code',
            'permission_denied',
          ),
        ),
      );
      await client.logoutFromMaster();

      expect(
        (await client.loginToMaster(
          username: 'transfer-owner',
          password: 'owner-secret',
        )).success,
        isTrue,
      );
      expect(
        client.supportsCapability(
          LanNetworkService.warehouseTransfersCapability,
        ),
        isTrue,
      );
      expect(await client.fetchRemoteTransferWarehouses(), hasLength(2));
      expect(
        await client.fetchRemoteWarehouseTransferCatalog(
          warehouseId: 'warehouse-main',
        ),
        hasLength(1),
      );

      final request = LanWarehouseTransferCreateRequest(
        requestKey: '11111111-1111-4111-8111-111111111111',
        sourceWarehouseId: 'warehouse-main',
        destinationWarehouseId: 'warehouse-branch',
        lines: const [
          LanWarehouseTransferLineRequest(
            productId: 7,
            variantId: 70,
            quantity: 2,
          ),
        ],
      );
      final created = await client.submitRemoteWarehouseTransfer(request);
      final replayed = await client.submitRemoteWarehouseTransfer(request);
      expect(created.id, replayed.id);
      expect(transferGateway.createCalls, 2);
      expect(transferGateway.uniqueCreateKeys, hasLength(1));

      final dispatched = await client.dispatchRemoteWarehouseTransfer(
        transferId: created.id,
        requestKey: '22222222-2222-4222-8222-222222222222',
      );
      expect(dispatched.status, 'in_transit');
      final pending = await client.fetchRemoteWarehouseTransferPending(
        created.id,
      );
      expect(pending.single.ownerType, 'consignment');

      final completed = await client.receiveRemoteWarehouseTransfer(
        transferId: created.id,
        request: LanWarehouseTransferReceiptRequest(
          requestKey: '33333333-3333-4333-8333-333333333333',
          items: [
            LanWarehouseTransferReceiptItemRequest(
              allocationId: pending.single.allocationId,
              acceptedQuantity: 2,
            ),
          ],
        ),
      );
      expect(completed.status, 'completed');
      expect(transferGateway.lastActor?.username, 'transfer-owner');
    },
  );
}

class _FakeBusinessGateway implements LanMasterBusinessGateway {
  @override
  Future<LanProductStockSourceSnapshot> fetchInventoryStockSources({
    required int productId,
    int? variantId,
  }) async => LanProductStockSourceSnapshot(
    productId: productId,
    warehouseId: 'warehouse-main',
    physicalQuantity: 2,
    enterpriseQuantity: 1,
    consignmentQuantity: 1,
    quantityScale: 1,
    measurementType: 'piece',
    reconciled: true,
    sources: [
      LanInventoryStockSource(
        productId: productId,
        variantId: variantId ?? 70,
        quantity: 1,
        quantityScale: 1,
        measurementType: 'piece',
        ownership: 'consignment',
        variantLabel: 'Default',
        supplierId: 3,
        supplierName: 'Supplier',
        consignmentLayerId: '11111111-1111-4111-8111-111111111111',
        sourceCode: 'C-11111111-1111-4111-8111-111111111111',
        receiptNumber: 'CR-1',
      ),
    ],
  );

  @override
  Future<LanCustomerCheckout> fetchCustomerCheckout(int customerId) async =>
      LanCustomerCheckout(
        customerId: customerId,
        currencyId: 1,
        currencyCode: 'USD',
        balanceCents: 12345,
        pointsBalance: 765,
      );

  final Set<String> createdKeys = <String>{};
  final Set<String> createdReturnKeys = <String>{};
  final Set<String> createdAdjustmentReturnKeys = <String>{};
  final Set<String> createdPurchaseReturnKeys = <String>{};
  final Set<String> createdPurchaseAdjustmentReturnKeys = <String>{};
  LanCashierShiftSnapshot? currentShift;
  LanCashierShiftSnapshot? lastClosedShift;
  LanSaleRequest? lastRequest;
  LanSaleReturnRequest? lastReturnRequest;
  LanSaleAdjustmentReturnRequest? lastAdjustmentReturnRequest;
  LanPurchaseReturnRequest? lastPurchaseReturnRequest;
  LanPurchaseAdjustmentReturnRequest? lastPurchaseAdjustmentReturnRequest;
  String? productImagePath;
  int? voidedSaleId;
  int? voidedPurchaseReturnId;
  LanBusinessException? nextSaleError;

  @override
  Future<LanSalesPage> fetchSales({required int limit}) async {
    final now = DateTime.utc(2026, 8, 25);
    return LanSalesPage(
      currencyCode: 'USD',
      currencySymbol: r'$',
      currencyDecimalDigits: 2,
      currencySymbolAfter: false,
      sales: [
        LanSaleSummary(
          id: 44,
          invoiceNumber: 'SI-202608-0044',
          customerId: 3,
          customerName: 'Network Customer',
          employeeId: 9,
          employeeName: 'Cashier One',
          subtotalCents: 250,
          taxCents: 0,
          discountCents: 0,
          totalCents: 250,
          paidAmountCents: 250,
          currencyId: 1,
          paymentMethod: 'cash',
          status: 'completed',
          saleDate: now,
          taxInclusiveAtPost: false,
          createdAt: now,
          updatedAt: now,
        ),
      ],
      stats: const LanSaleDashboardStats(
        totalCount: 1,
        completedCount: 1,
        voidedCount: 0,
        totalSalesCents: 250,
        totalPaidCents: 250,
        returnsCount: 1,
        totalReturnsCents: 125,
        todaySalesCents: 250,
        todayCount: 1,
      ),
      saleIdsWithReturns: const {44},
      productSearchTerms: const {
        44: ['Milk', 'MILK-1', '123456789'],
      },
    );
  }

  @override
  Future<LanSaleDetails?> fetchSaleDetails({required int saleId}) async {
    if (saleId != 44) return null;
    final page = await fetchSales(limit: 1);
    final now = DateTime.utc(2026, 8, 25);
    return LanSaleDetails(
      sale: page.sales.single,
      lines: [
        LanSaleDetailLine(
          id: 70,
          saleId: 44,
          productId: 7,
          productName: 'Milk',
          productSku: 'MILK-1',
          quantity: 500,
          quantityScale: 1000,
          measurementType: 'volume',
          unitPriceCents: 500,
          subtotalCents: 250,
          discountCents: 0,
          taxCents: 0,
          totalCents: 250,
          employeeId: 9,
          employeeName: 'Salesperson',
          createdAt: now,
        ),
      ],
      currencyCode: 'USD',
      currencySymbol: r'$',
      currencyDecimalDigits: 2,
      currencySymbolAfter: false,
      cashierName: 'Cashier One',
      cashierShiftNumber: 'SHIFT-202608-0001',
    );
  }

  @override
  Future<LanSaleVoidResult> voidSale({
    required LanRemoteUser actor,
    required int saleId,
  }) async {
    voidedSaleId = saleId;
    return LanSaleVoidResult(saleId: saleId, status: 'voided');
  }

  @override
  Future<LanCatalogPage> fetchCatalog({
    required String query,
    required int offset,
    required int limit,
  }) async {
    return LanCatalogPage(
      products: [
        LanCatalogProduct(
          id: 7,
          name: 'Milk',
          sku: 'MILK-1',
          barcode: '123456789',
          priceCents: 500,
          stockQuantity: 2500,
          hasVariants: false,
          isTaxable: false,
          salesTaxRateBps: 0,
          trackInventory: true,
          measurementType: 'volume',
          quantityScale: 1000,
          hasImage: productImagePath != null,
          costCents: 275,
          lastPurchasePriceCents: 300,
          minQuantity: 500,
          medicine: const LanMedicineProfile(
            dosageForm: 'suspension',
            administrationRoute: 'oral',
            substitutionEligible: true,
            ingredients: [
              LanMedicineIngredient(
                ingredientId: 1,
                canonicalName: 'ibuprofen',
                nameAr: 'إيبوبروفين',
                strengthValueMicros: 100000000,
                strengthUnit: 'mg',
                basisValueMicros: 5000000,
                basisUnit: 'ml',
              ),
            ],
          ),
        ),
      ],
      offset: 0,
      limit: 100,
      hasMore: false,
      currencyId: 1,
      currencyCode: 'USD',
      currencySymbol: r'$',
      enableTaxCalculations: false,
      defaultSalesTaxRateBps: 0,
      taxInclusivePricing: false,
      allowNegativeStock: false,
      allowPartialPayments: false,
      requireCustomerForSales: false,
      enablePharmacyFeatures: true,
    );
  }

  @override
  Future<LanMedicineAlternativesResult> fetchMedicineAlternatives({
    required int productId,
  }) async {
    return LanMedicineAlternativesResult(
      sourceProductId: productId,
      alternatives: [
        const LanCatalogProduct(
          id: 8,
          name: 'Alternative Milk',
          priceCents: 450,
          stockQuantity: 1200,
          hasVariants: false,
          isTaxable: false,
          salesTaxRateBps: 0,
          trackInventory: true,
          measurementType: 'volume',
          quantityScale: 1000,
          medicine: LanMedicineProfile(
            dosageForm: 'suspension',
            administrationRoute: 'oral',
            substitutionEligible: true,
            ingredients: [
              LanMedicineIngredient(
                ingredientId: 1,
                canonicalName: 'ibuprofen',
                nameAr: 'إيبوبروفين',
                strengthValueMicros: 100000000,
                strengthUnit: 'mg',
                basisValueMicros: 5000000,
                basisUnit: 'ml',
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Future<String?> resolveProductImagePath({required int productId}) async =>
      productId == 7 ? productImagePath : null;

  @override
  Future<List<LanCustomerSummary>> fetchCustomers({
    required String query,
    required int limit,
  }) async {
    return const [
      LanCustomerSummary(
        id: 3,
        name: 'Network Customer',
        segment: 'retail',
        balanceCents: 24680,
      ),
    ];
  }

  @override
  Future<List<LanEmployeeSummary>> fetchSalespeople({
    required String query,
    required int limit,
  }) async => const [LanEmployeeSummary(id: 9, name: 'Salesperson')];

  @override
  Future<LanReturnableSalesPage> fetchReturnableSales({
    required String query,
    required int offset,
    required int limit,
  }) async {
    return LanReturnableSalesPage(
      sales: [
        LanReturnableSaleSummary(
          saleId: 44,
          invoiceNumber: 'SI-202608-0044',
          customerName: 'Network Customer',
          saleDate: DateTime.utc(2026, 8, 25),
          totalCents: 250,
          paymentMethod: 'cash',
          currencyCode: 'USD',
          currencySymbol: r'$',
          returnableLineCount: 1,
        ),
      ],
      offset: offset,
      limit: limit,
      hasMore: false,
    );
  }

  @override
  Future<LanReturnableSaleDetails?> fetchReturnableSale({
    required int saleId,
  }) async {
    if (saleId != 44) return null;
    final summary = (await fetchReturnableSales(
      query: '',
      offset: 0,
      limit: 1,
    )).sales.single;
    return LanReturnableSaleDetails(
      sale: summary,
      lines: const [
        LanReturnableSaleLine(
          saleItemId: 70,
          productId: 7,
          productName: 'Milk',
          originalQuantity: 1000,
          returnedQuantity: 250,
          availableQuantity: 750,
          quantityScale: 1000,
          measurementType: 'volume',
          unitPriceCents: 500,
          subtotalCents: 500,
          discountCents: 0,
          taxCents: 0,
          totalCents: 500,
        ),
      ],
    );
  }

  @override
  Future<LanSaleReturnsPage> fetchSaleReturns({
    required String query,
    required int offset,
    required int limit,
  }) async {
    return LanSaleReturnsPage(
      returns: [
        LanSaleReturnSummary(
          id: 5,
          saleId: 44,
          saleInvoiceNumber: 'SI-202608-0044',
          customerName: 'Network Customer',
          returnNumber: 'SR-202608-0005',
          subtotalCents: 125,
          discountCents: 0,
          taxCents: 0,
          totalCents: 125,
          currencyId: 1,
          status: 'posted',
          dispositionType: 'restock',
          refundMethod: 'cash',
          returnDate: DateTime.utc(2026, 8, 25),
          createdAt: DateTime.utc(2026, 8, 25),
          isAdjustment: false,
          unifiedId: 'SR-5',
        ),
      ],
      offset: offset,
      limit: limit,
      hasMore: false,
    );
  }

  @override
  Future<LanSaleReturnDetails?> fetchSaleReturnDetails({
    required int returnId,
    required bool adjustment,
  }) async {
    if (returnId != 5 || adjustment) return null;
    final summary = (await fetchSaleReturns(
      query: '',
      offset: 0,
      limit: 1,
    )).returns.single;
    return LanSaleReturnDetails(
      summary: summary,
      lines: [
        LanSaleReturnDetailLine(
          id: 12,
          returnId: returnId,
          saleItemId: 70,
          productId: 7,
          productName: 'Milk',
          productSku: 'MILK-1',
          quantity: 250,
          quantityScale: 1000,
          measurementType: 'volume',
          unitPriceCents: 500,
          subtotalCents: 125,
          discountCents: 0,
          taxCents: 0,
          totalCents: 125,
          dispositionType: 'restock',
          createdAt: DateTime.utc(2026, 8, 25),
        ),
      ],
      currencyCode: 'USD',
      currencySymbol: r'$',
      currencyDecimalDigits: 2,
      currencySymbolAfter: false,
    );
  }

  @override
  Future<LanSaleReturnResult> createSaleReturn({
    required LanRemoteUser actor,
    required LanSaleReturnRequest request,
  }) async {
    lastReturnRequest = request;
    final duplicate = !createdReturnKeys.add(request.idempotencyKey);
    return LanSaleReturnResult(
      returnId: 5,
      returnNumber: 'SR-202608-0005',
      totalCents: 125,
      duplicate: duplicate,
    );
  }

  @override
  Future<LanSaleReturnResult> createSaleAdjustmentReturn({
    required LanRemoteUser actor,
    required LanSaleAdjustmentReturnRequest request,
  }) async {
    lastAdjustmentReturnRequest = request;
    final duplicate = !createdAdjustmentReturnKeys.add(request.idempotencyKey);
    return LanSaleReturnResult(
      returnId: 8,
      returnNumber: 'SRS-202608-0008',
      totalCents: 250,
      duplicate: duplicate,
    );
  }

  @override
  Future<List<LanConsignmentReturnSource>>
  fetchConsignmentAdjustmentReturnSources({
    required int productId,
    int? variantId,
  }) async => const [];

  @override
  Future<List<LanSupplierSummary>> fetchSuppliers({
    required String query,
    required int limit,
  }) async => const [
    LanSupplierSummary(id: 6, name: 'Network Supplier', phone: '01000000000'),
  ];

  @override
  Future<LanReturnablePurchasesPage> fetchReturnablePurchases({
    required String query,
    required int offset,
    required int limit,
  }) async => LanReturnablePurchasesPage(
    purchases: [
      LanReturnablePurchaseSummary(
        purchaseId: 55,
        purchaseNumber: 'PI-202608-0055',
        supplierId: 6,
        supplierName: 'Network Supplier',
        purchaseDate: DateTime.utc(2026, 8, 25),
        totalCents: 800,
        paymentMethod: 'credit',
        currencyId: 1,
        taxInclusiveAtPost: false,
        returnableLineCount: 1,
      ),
    ],
    offset: offset,
    limit: limit,
    hasMore: false,
  );

  @override
  Future<LanReturnablePurchaseDetails?> fetchReturnablePurchase({
    required int purchaseId,
  }) async {
    if (purchaseId != 55) return null;
    final summary = (await fetchReturnablePurchases(
      query: '',
      offset: 0,
      limit: 1,
    )).purchases.single;
    return LanReturnablePurchaseDetails(
      purchase: summary,
      lines: const [
        LanReturnablePurchaseLine(
          purchaseItemId: 88,
          productId: 7,
          productName: 'Milk',
          originalQuantity: 2000,
          returnedQuantity: 500,
          availableQuantity: 1500,
          currentStockQuantity: 3000,
          tracksInventory: true,
          quantityScale: 1000,
          measurementType: 'volume',
          unitCostCents: 400,
          subtotalCents: 800,
          discountCents: 0,
          taxCents: 0,
          totalCents: 800,
        ),
      ],
    );
  }

  @override
  Future<LanPurchaseReturnsPage> fetchPurchaseReturns({
    required String query,
    required int offset,
    required int limit,
  }) async => LanPurchaseReturnsPage(
    returns: [
      LanPurchaseReturnSummary(
        id: 9,
        purchaseId: 55,
        purchaseNumber: 'PI-202608-0055',
        supplierId: 6,
        supplierName: 'Network Supplier',
        returnNumber: 'PR-202608-0009',
        subtotalCents: 400,
        discountCents: 0,
        taxCents: 0,
        totalCents: 400,
        currencyId: 1,
        status: 'posted',
        dispositionType: 'restock',
        refundMethod: 'credit',
        returnDate: DateTime.utc(2026, 8, 25),
        createdAt: DateTime.utc(2026, 8, 25),
        isAdjustment: false,
        unifiedId: 'PR-9',
      ),
    ],
    offset: offset,
    limit: limit,
    hasMore: false,
  );

  @override
  Future<LanPurchaseReturnDetails?> fetchPurchaseReturnDetails({
    required int returnId,
    required bool adjustment,
  }) async {
    if (returnId != 9 || adjustment) return null;
    final summary = (await fetchPurchaseReturns(
      query: '',
      offset: 0,
      limit: 1,
    )).returns.single;
    return LanPurchaseReturnDetails(
      summary: summary,
      lines: [
        LanPurchaseReturnDetailLine(
          id: 21,
          returnId: returnId,
          purchaseItemId: 88,
          productId: 7,
          productName: 'Milk',
          quantity: 1000,
          quantityScale: 1000,
          measurementType: 'volume',
          unitPriceCents: 400,
          subtotalCents: 400,
          discountCents: 0,
          taxCents: 0,
          totalCents: 400,
          dispositionType: 'restock',
          createdAt: DateTime.utc(2026, 8, 25),
        ),
      ],
    );
  }

  @override
  Future<LanPurchaseReturnResult> createPurchaseReturn({
    required LanRemoteUser actor,
    required LanPurchaseReturnRequest request,
  }) async {
    lastPurchaseReturnRequest = request;
    final duplicate = !createdPurchaseReturnKeys.add(request.idempotencyKey);
    return LanPurchaseReturnResult(
      returnId: 9,
      returnNumber: 'PR-202608-0009',
      totalCents: 400,
      duplicate: duplicate,
    );
  }

  @override
  Future<LanPurchaseReturnResult> createPurchaseAdjustmentReturn({
    required LanRemoteUser actor,
    required LanPurchaseAdjustmentReturnRequest request,
  }) async {
    lastPurchaseAdjustmentReturnRequest = request;
    final duplicate = !createdPurchaseAdjustmentReturnKeys.add(
      request.idempotencyKey,
    );
    return LanPurchaseReturnResult(
      returnId: 10,
      returnNumber: 'PRS-202608-0010',
      totalCents: 500,
      duplicate: duplicate,
    );
  }

  @override
  Future<void> voidPurchaseReturn({
    required LanRemoteUser actor,
    required int returnId,
    required bool adjustment,
  }) async {
    voidedPurchaseReturnId = returnId;
  }

  @override
  Future<LanCashierShiftSnapshot?> getOwnShift({
    required LanRemoteUser actor,
  }) async => currentShift;

  @override
  Future<LanCashierShiftSnapshot> openOwnShift({
    required LanRemoteUser actor,
    required int openingCashCents,
    String? notes,
  }) async {
    currentShift = _shift(actor, openingCashCents);
    return currentShift!;
  }

  @override
  Future<LanCashierShiftSnapshot> closeOwnShift({
    required LanRemoteUser actor,
    int? shiftId,
    required int countedCashCents,
    String? notes,
  }) async {
    if (lastClosedShift != null &&
        (shiftId == null || lastClosedShift?.id == shiftId)) {
      return lastClosedShift!;
    }
    final closed = _shift(actor, countedCashCents, status: 'closed');
    currentShift = null;
    lastClosedShift = closed;
    return closed;
  }

  LanCashierShiftSnapshot _shift(
    LanRemoteUser actor,
    int cash, {
    String status = 'open',
  }) {
    return LanCashierShiftSnapshot(
      id: 1,
      shiftNumber: 'SH-TEST-1',
      status: status,
      cashierUserId: actor.id,
      employeeId: actor.employeeId,
      cashierName: actor.employeeName ?? actor.username,
      currencyCode: 'USD',
      currencySymbol: r'$',
      openingCashCents: cash,
      expectedCashCents: cash,
      salesCount: 0,
      returnsCount: 0,
      openedAt: DateTime(2026),
    );
  }

  @override
  Future<LanSaleResult> createSale({
    required LanRemoteUser actor,
    required LanSaleRequest request,
  }) async {
    final pendingError = nextSaleError;
    if (pendingError != null) {
      nextSaleError = null;
      throw pendingError;
    }
    lastRequest = request;
    final duplicate = !createdKeys.add(request.idempotencyKey);
    return LanSaleResult(
      saleId: 44,
      invoiceNumber: 'SI-202608-0044',
      subtotalCents: 250,
      discountCents: 0,
      taxCents: 0,
      totalCents: 250,
      paidAmountCents: 250,
      duplicate: duplicate,
    );
  }
}

class _FakeWarehouseTransferBusinessGateway extends _FakeBusinessGateway
    implements LanWarehouseTransferGateway {
  final Set<String> uniqueCreateKeys = {};
  int createCalls = 0;
  LanRemoteUser? lastActor;
  LanWarehouseTransferDocument? document;

  @override
  Future<List<LanWarehouseTransferWarehouse>> fetchTransferWarehouses({
    required LanRemoteUser actor,
  }) async {
    lastActor = actor;
    return const [
      LanWarehouseTransferWarehouse(
        id: 'warehouse-main',
        code: 'MAIN',
        name: 'Main warehouse',
      ),
      LanWarehouseTransferWarehouse(
        id: 'warehouse-branch',
        code: 'B02',
        name: 'Branch warehouse',
      ),
    ];
  }

  @override
  Future<List<LanWarehouseTransferDocument>> fetchWarehouseTransfers({
    required LanRemoteUser actor,
    required Set<String> statuses,
    required int limit,
  }) async {
    lastActor = actor;
    final row = document;
    return row != null && statuses.contains(row.status) ? [row] : const [];
  }

  @override
  Future<List<LanWarehouseTransferCatalogItem>> fetchWarehouseTransferCatalog({
    required LanRemoteUser actor,
    required String warehouseId,
    required String query,
    required int offset,
  }) async {
    lastActor = actor;
    return const [
      LanWarehouseTransferCatalogItem(
        productId: 7,
        variantId: 70,
        name: 'Consignment item',
        code: 'ITEM-7',
        quantity: 6,
        supplierOwnedQuantity: 6,
        quantityScale: 1,
        measurementType: 'piece',
      ),
    ];
  }

  @override
  Future<LanWarehouseTransferDocument> createWarehouseTransfer({
    required LanRemoteUser actor,
    required LanWarehouseTransferCreateRequest request,
  }) async {
    lastActor = actor;
    createCalls++;
    uniqueCreateKeys.add(request.requestKey);
    return document ??= LanWarehouseTransferDocument(
      id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      sourceWarehouseId: request.sourceWarehouseId,
      destinationWarehouseId: request.destinationWarehouseId,
      status: 'draft',
      lineCount: request.lines.length,
      notes: request.notes,
      recalled: false,
    );
  }

  @override
  Future<LanWarehouseTransferDocument> cancelWarehouseTransfer({
    required LanRemoteUser actor,
    required String transferId,
    required LanWarehouseTransferReasonRequest request,
  }) async {
    lastActor = actor;
    return document = _status('cancelled');
  }

  @override
  Future<LanWarehouseTransferDocument> dispatchWarehouseTransfer({
    required LanRemoteUser actor,
    required String transferId,
    required String requestKey,
  }) async {
    lastActor = actor;
    return document = _status('in_transit');
  }

  @override
  Future<List<LanWarehouseTransferPendingAllocation>>
  fetchWarehouseTransferPending({
    required LanRemoteUser actor,
    required String transferId,
  }) async {
    lastActor = actor;
    return const [
      LanWarehouseTransferPendingAllocation(
        allocationId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
        remainingQuantity: 2,
        quantityScale: 1,
        productName: 'Consignment item',
        code: 'ITEM-7',
        ownerType: 'consignment',
      ),
    ];
  }

  @override
  Future<LanWarehouseTransferDocument> receiveWarehouseTransfer({
    required LanRemoteUser actor,
    required String transferId,
    required LanWarehouseTransferReceiptRequest request,
  }) async {
    lastActor = actor;
    return document = _status('completed');
  }

  @override
  Future<LanWarehouseTransferDocument> recallWarehouseTransfer({
    required LanRemoteUser actor,
    required String transferId,
    required LanWarehouseTransferReasonRequest request,
  }) async {
    lastActor = actor;
    final row = _status('cancelled');
    return document = LanWarehouseTransferDocument(
      id: row.id,
      sourceWarehouseId: row.sourceWarehouseId,
      destinationWarehouseId: row.destinationWarehouseId,
      status: row.status,
      lineCount: row.lineCount,
      notes: row.notes,
      recalled: true,
    );
  }

  LanWarehouseTransferDocument _status(String status) {
    final row = document!;
    return LanWarehouseTransferDocument(
      id: row.id,
      sourceWarehouseId: row.sourceWarehouseId,
      destinationWarehouseId: row.destinationWarehouseId,
      status: status,
      lineCount: row.lineCount,
      notes: row.notes,
      recalled: row.recalled,
    );
  }
}
