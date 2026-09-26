import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tapix/features/business/data/online_branches_entitlement.dart';
import 'package:tapix/features/business/data/online_branches_purchase_service.dart';
import 'package:tapix/features/business/data/warehouse_setup_service.dart';
import 'package:tapix/features/business/data/warehouse_transfer_application_service.dart';
import 'package:tapix/features/business/presentation/screens/business_locations_hub_screen.dart';

class _Assets extends AssetLoader {
  const _Assets();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(File('$path/${locale.languageCode}.json').readAsStringSync())
          as Map<String, dynamic>;
}

class _Setup extends Fake implements WarehouseSetupService {}

class _Transfers extends Fake implements WarehouseTransferApplicationService {}

class _Entitlement implements OnlineBranchesEntitlement {
  const _Entitlement(this.snapshot);
  final OnlineBranchesEntitlementSnapshot snapshot;

  @override
  Future<OnlineBranchesEntitlementSnapshot> inspect() async => snapshot;
}

class _Purchases implements OnlineBranchesPurchaseService {
  @override
  Future<List<OnlineBranchesPlan>> loadPlans() async => const [];

  @override
  Future<bool> openManagement() async => false;

  @override
  Future<OnlineBranchesPurchaseOutcome> purchase(String planId) async =>
      const OnlineBranchesPurchaseOutcome(
        OnlineBranchesStoreResult.unavailable,
      );

  @override
  Future<OnlineBranchesPurchaseOutcome> restore() async =>
      const OnlineBranchesPurchaseOutcome(
        OnlineBranchesStoreResult.unavailable,
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  for (final language in ['ar', 'en', 'fr']) {
    for (final dark in [false, true]) {
      testWidgets('locations hub fits $language dark=$dark', (tester) async {
        tester.view.physicalSize = dark
            ? const Size(1200, 900)
            : const Size(360, 740);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final locale = Locale(language);
        await tester.pumpWidget(
          EasyLocalization(
            supportedLocales: const [Locale('ar'), Locale('en'), Locale('fr')],
            path: 'assets/translations',
            assetLoader: const _Assets(),
            startLocale: locale,
            saveLocale: false,
            child: Builder(
              builder: (context) => MaterialApp(
                locale: context.locale,
                supportedLocales: context.supportedLocales,
                localizationsDelegates: context.localizationDelegates,
                theme: ThemeData(
                  brightness: dark ? Brightness.dark : Brightness.light,
                ),
                home: BusinessLocationsHubScreen(
                  setupService: _Setup(),
                  transferService: _Transfers(),
                  onlineEntitlement: _Entitlement(
                    OnlineBranchesEntitlementPolicy.evaluate(
                      baseProActive: true,
                      addOnActive: true,
                      expirationDate: DateTime.utc(2027),
                      willRenew: true,
                      maxBranches: 5,
                      maxWarehouses: 15,
                      now: DateTime.utc(2026, 9, 25),
                    ),
                  ),
                  purchaseService: _Purchases(),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(BusinessLocationsHubScreen), findsOneWidget);
        expect(
          find.text('business_locations.primary_warehouse_title'.tr()),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.drag(
          find.byType(CustomScrollView),
          const Offset(0, -1200),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }
}
