import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tapix/core/di/injection_container.dart';
import 'package:tapix/core/services/currency_service.dart';
import 'package:tapix/core/services/lan/lan_network_service.dart';
import 'package:tapix/features/purchases/presentation/screens/purchase_detail_screen.dart';

class _Assets extends AssetLoader {
  const _Assets();
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(File('$path/${locale.languageCode}.json').readAsStringSync())
          as Map<String, dynamic>;
}

class _Branch extends Fake implements LanNetworkService {
  bool posted = false;
  bool failed = false;
  int postCalls = 0;
  int detailCalls = 0;

  @override
  LanNetworkSnapshot get snapshot =>
      const LanNetworkSnapshot(mode: LanMode.client);

  @override
  LanRemoteUser get remoteUser => LanRemoteUser(
    id: 3,
    username: 'warehouse',
    role: 'warehouseClerk',
    isActive: true,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
    permissions: const ['view_purchases', 'manage_purchases'],
  );

  @override
  Future<LanPurchaseDetails> fetchRemotePurchaseDetails(int id) async {
    detailCalls++;
    if (failed) {
      throw const LanBusinessException('offline', 'Branch unavailable');
    }
    return LanPurchaseDetails.fromJson({
      'purchase': {
        'id': id,
        'purchaseNumber': 'WAREHOUSE-PI-42',
        'supplierId': 7,
        'supplierName': 'Branch supplier',
        'subtotalCents': 12500,
        'discountCents': 0,
        'taxCents': 1250,
        'totalCents': 13750,
        'paidAmountCents': 0,
        'currencyId': 1,
        'status': posted ? 'posted' : 'draft',
        'paymentMethod': 'credit',
        'purchaseDate': '2026-10-01T09:00:00Z',
        'createdAt': '2026-10-01T09:00:00Z',
        'updatedAt': '2026-10-01T09:00:00Z',
      },
      'lines': [
        {
          'id': 21,
          'purchaseId': id,
          'productId': 9,
          'variantId': 10,
          'productName': 'Warehouse medicine',
          'variantSku': 'MED-10',
          'quantity': 5,
          'quantityScale': 1,
          'measurementType': 'piece',
          'unitCostCents': 2500,
          'subtotalCents': 12500,
          'discountCents': 0,
          'taxCents': 1250,
          'totalCents': 13750,
          'manufacturerLotNumber': 'LOT-2026',
          'expiryDate': '2028-10-01T00:00:00Z',
          'createdAt': '2026-10-01T09:00:00Z',
        },
      ],
      'returns': <Map<String, dynamic>>[],
      'supplierBalanceCents': 13750,
      'currencyCode': 'USD',
      'currencySymbol': r'$',
      'currencyDecimalDigits': 2,
      'currencySymbolAfter': false,
    });
  }

  @override
  Future<LanPurchaseResult> postRemotePurchase(int purchaseId) async {
    postCalls++;
    posted = true;
    return LanPurchaseResult.fromJson({
      'purchaseId': purchaseId,
      'purchaseNumber': 'WAREHOUSE-PI-42',
      'status': 'posted',
      'totalCents': 13750,
      'duplicate': false,
    });
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });
  tearDown(() async => sl.reset());

  Future<void> open(
    WidgetTester tester,
    _Branch branch, {
    Size size = const Size(1200, 1000),
    Locale locale = const Locale('en'),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    sl.registerSingleton<LanNetworkService>(branch);
    sl.registerSingleton<CurrencyService>(
      CurrencyService(await SharedPreferences.getInstance()),
    );
    final router = GoRouter(
      initialLocation: '/purchases/42',
      routes: [
        GoRoute(
          path: '/purchases/:id',
          builder: (_, _) => const PurchaseDetailScreen(purchaseId: 42),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en'), Locale('ar')],
        startLocale: locale,
        path: 'assets/translations',
        assetLoader: const _Assets(),
        saveLocale: false,
        child: Builder(
          builder: (context) => MaterialApp.router(
            routerConfig: router,
            locale: context.locale,
            supportedLocales: context.supportedLocales,
            localizationsDelegates: context.localizationDelegates,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'warehouse reads and posts the branch invoice without a local repository',
    (tester) async {
      final branch = _Branch();
      await open(tester, branch);
      expect(find.text('WAREHOUSE-PI-42'), findsWidgets);
      expect(find.text('Warehouse medicine'), findsOneWidget);
      expect(find.textContaining('LOT-2026'), findsOneWidget);
      await tester.tap(find.text('purchases.post'.tr()));
      await tester.pumpAndSettle();
      expect(branch.postCalls, 1);
      expect(branch.detailCalls, 2);
      expect(find.text('purchases.create_return'.tr()), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'connection failure offers retry and never reads a local invoice',
    (tester) async {
      final branch = _Branch()..failed = true;
      await open(tester, branch);
      expect(find.text('Branch unavailable'), findsOneWidget);
      branch.failed = false;
      await tester.tap(find.text('common.retry'.tr()));
      await tester.pumpAndSettle();
      expect(find.text('Warehouse medicine'), findsOneWidget);
      expect(branch.detailCalls, 2);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('Arabic warehouse invoice fits a narrow screen', (tester) async {
    await open(
      tester,
      _Branch(),
      size: const Size(400, 820),
      locale: const Locale('ar'),
    );
    expect(tester.takeException(), isNull);
    await tester.drag(find.byType(ListView).first, const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
