import 'dart:convert';
import 'dart:io';
import 'package:bloc_test/bloc_test.dart';
import 'package:decimal/decimal.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tapix/core/di/injection_container.dart';
import 'package:tapix/core/services/currency_service.dart';
import 'package:tapix/core/services/feature_gate_service.dart';
import 'package:tapix/core/services/lan/lan_network_service.dart';
import 'package:tapix/features/products/domain/entities/product_entity.dart';
import 'package:tapix/features/purchases/presentation/bloc/purchase_form_bloc.dart';
import 'package:tapix/features/purchases/presentation/screens/purchase_form_screen.dart';
import 'package:tapix/features/settings/domain/entities/app_settings.dart';
import 'package:tapix/features/settings/presentation/bloc/app_settings_bloc.dart';

class _Form extends MockBloc<PurchaseFormEvent, PurchaseFormState>
    implements PurchaseFormBloc {}

class _Settings extends MockBloc<AppSettingsEvent, AppSettingsState>
    implements AppSettingsBloc {}

class _Gate extends Fake implements FeatureGateService {
  @override
  bool isEnabled(AppFeature feature, {required bool settingEnabled}) =>
      settingEnabled;
}

class _Network extends Fake implements LanNetworkService {
  @override
  LanNetworkSnapshot get snapshot =>
      const LanNetworkSnapshot(mode: LanMode.standalone);
}

class _Assets extends AssetLoader {
  const _Assets();
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(File('$path/${locale.languageCode}.json').readAsStringSync())
          as Map<String, dynamic>;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });
  tearDown(() async => sl.reset());
  for (final size in [
    const Size(820, 360),
    const Size(360, 740),
    const Size(1100, 360),
  ]) {
    testWidgets('purchase edit scrolls to totals without overflow at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final form = _Form();
      final settings = _Settings();
      final state = PurchaseFormState(
        purchaseId: 2,
        purchaseNumber: 'PI-202610-000002',
        currencyId: 1,
        purchaseDate: DateTime(2026, 10, 1),
        items: [
          PurchaseLineItem(
            tempId: '1',
            quantity: 10,
            unitCostCents: Decimal.fromInt(10000),
            discountCents: Decimal.fromInt(1000),
            originalCostCents: 10000,
            originalPriceCents: 15000,
            product: Product(
              id: 1,
              name: 'مستحضر تجميل',
              sku: '150',
              costCents: Decimal.fromInt(10000),
              priceCents: Decimal.fromInt(15000),
              stockQuantity: 0,
              minQuantity: 0,
              hasVariants: false,
              isTaxable: true,
              isActive: true,
              trackInventory: true,
              purchaseTaxRateBps: 100,
              salesTaxRateBps: 100,
            ),
          ),
        ],
      );
      when(() => form.state).thenReturn(state);
      when(
        () => settings.state,
      ).thenReturn(const AppSettingsState(settings: AppSettings()));
      sl.registerFactory<PurchaseFormBloc>(() => form);
      sl.registerSingleton<FeatureGateService>(_Gate());
      sl.registerSingleton<LanNetworkService>(_Network());
      sl.registerSingleton<CurrencyService>(
        CurrencyService(await SharedPreferences.getInstance()),
      );
      await tester.pumpWidget(
        EasyLocalization(
          supportedLocales: const [Locale('ar')],
          path: 'assets/translations',
          assetLoader: const _Assets(),
          startLocale: const Locale('ar'),
          saveLocale: false,
          child: Builder(
            builder: (context) => MaterialApp(
              locale: context.locale,
              supportedLocales: context.supportedLocales,
              localizationsDelegates: context.localizationDelegates,
              home: BlocProvider<AppSettingsBloc>.value(
                value: settings,
                child: const PurchaseFormScreen(purchaseId: 2),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final scroll = find
          .descendant(
            of: find.byKey(const ValueKey('purchase-form-scroll')),
            matching: find.byType(Scrollable),
          )
          .first;
      for (var i = 0; i < 8; i++) {
        await tester.drag(scroll, const Offset(0, -200));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      expect(
        find.text('purchases.checkout'.tr()).hitTestable(),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      await settings.close();
    });
  }
}
