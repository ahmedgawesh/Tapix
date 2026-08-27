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
    expect(result.success, isTrue);
  }

  setUp(() async {
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
    'master rejects a wrong code then pairs and authenticates a client device',
    () async {
      await master.startMaster(port: 0);

      expect(master.snapshot.mode, LanMode.master);
      expect(master.snapshot.status, LanConnectionStatus.online);
      expect(master.snapshot.port, greaterThan(0));
      expect(master.snapshot.pairingCode, hasLength(6));

      final rejected = await client.pairWithMaster(
        host: '127.0.0.1',
        port: master.snapshot.port,
        pairingCode: '000000',
        deviceName: 'Test cashier',
      );
      expect(rejected.success, isFalse);
      expect(master.snapshot.pairedDevices, 0);

      final correctCode = master.snapshot.pairingCode!;
      final paired = await client.pairWithMaster(
        host: '127.0.0.1',
        port: master.snapshot.port,
        pairingCode: correctCode,
        deviceName: 'Test cashier',
      );

      expect(paired.success, isTrue);
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

    final closed = await client.closeOwnRemoteShift(
      countedCashCents: 12400,
      notes: 'Counted at logout',
    );
    expect(closed.isOpen, isFalse);
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

      final created = await client.submitRemoteSale(request);
      final replayed = await client.submitRemoteSale(request);

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

      const request = LanSaleReturnRequest(
        idempotencyKey: 'lan-sale-return-safe-retry-001',
        saleId: 44,
        dispositionType: 'restock',
        refundMethod: 'cash',
        lines: [LanSaleReturnLineRequest(saleItemId: 70, quantity: 250)],
      );
      final created = await client.submitRemoteSaleReturn(request);
      final replayed = await client.submitRemoteSaleReturn(request);

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

    final request = LanSaleAdjustmentReturnRequest(
      idempotencyKey: 'lan-sale-adjustment-safe-retry-001',
      refundMethod: 'cash',
      returnDate: DateTime.utc(2026, 8, 25),
      reasonCode: 'noReceipt',
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

    expect(created.returnId, replayed.returnId);
    expect(created.duplicate, isFalse);
    expect(replayed.duplicate, isTrue);
    expect(businessGateway.createdAdjustmentReturnKeys, hasLength(1));
    expect(
      businessGateway.lastAdjustmentReturnRequest?.lines.single.quantity,
      500,
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
}

class _FakeBusinessGateway implements LanMasterBusinessGateway {
  final Set<String> createdKeys = <String>{};
  final Set<String> createdReturnKeys = <String>{};
  final Set<String> createdAdjustmentReturnKeys = <String>{};
  LanCashierShiftSnapshot? currentShift;
  LanSaleRequest? lastRequest;
  LanSaleReturnRequest? lastReturnRequest;
  LanSaleAdjustmentReturnRequest? lastAdjustmentReturnRequest;
  String? productImagePath;

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
        balanceCents: 0,
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
    required int countedCashCents,
    String? notes,
  }) async {
    final closed = _shift(actor, countedCashCents, status: 'closed');
    currentShift = null;
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
