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
import 'package:tapix/core/bloc/realtime_bloc.dart';
import 'package:tapix/core/bloc/theme_bloc.dart';
import 'package:tapix/core/di/injection_container.dart';
import 'package:tapix/core/services/currency_service.dart';
import 'package:tapix/core/services/feature_gate_service.dart';
import 'package:tapix/core/services/lan/lan_network_service.dart';
import 'package:tapix/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:tapix/features/auth/domain/entities/user_entity.dart';
import 'package:tapix/features/products/domain/entities/product_entity.dart';
import 'package:tapix/features/sales/presentation/bloc/sale_form_bloc.dart';
import 'package:tapix/features/sales/presentation/screens/sale_form_screen.dart';
import 'package:tapix/features/settings/domain/entities/app_settings.dart';
import 'package:tapix/features/settings/presentation/bloc/app_settings_bloc.dart';

class _Sale extends MockBloc<SaleFormEvent, SaleFormState>
    implements SaleFormBloc {}

class _Auth extends MockBloc<RealtimeEvent, RealtimeState<UserEntity?>>
    implements AuthBloc {}

class _Settings extends MockBloc<AppSettingsEvent, AppSettingsState>
    implements AppSettingsBloc {}

class _Theme extends MockBloc<RealtimeEvent, RealtimeState<ThemeMode>>
    implements ThemeBloc {}

class _Features extends Mock implements FeatureGateService {}

class _Assets extends AssetLoader {
  const _Assets();
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(File('assets/translations/en.json').readAsStringSync())
          as Map<String, dynamic>;
}

class _Lan extends Fake implements LanNetworkService {
  int checks = 0;
  @override
  bool get hasRemoteUserSession => true;
  @override
  LanNetworkSnapshot get snapshot =>
      const LanNetworkSnapshot(mode: LanMode.client);
  @override
  Future<LanProductStockSourceSnapshot> fetchRemoteInventoryStockSources({
    required int productId,
    int? variantId,
  }) async {
    checks++;
    return const LanProductStockSourceSnapshot(
      productId: 1,
      warehouseId: 'branch',
      physicalQuantity: 8,
      enterpriseQuantity: 8,
      consignmentQuantity: 0,
      quantityScale: 1,
      measurementType: 'piece',
      reconciled: true,
      sources: [
        LanInventoryStockSource(
          productId: 1,
          variantId: 2,
          quantity: 8,
          quantityScale: 1,
          measurementType: 'piece',
          ownership: 'enterprise',
          variantLabel: '',
        ),
      ],
    );
  }
}

void main() {
  testWidgets(
    'editing a remote line discount validates stock using the owning form bloc',
    (tester) async {
      registerFallbackValue(const SaleCustomerChanged());
      SharedPreferences.setMockInitialValues({});
      await EasyLocalization.ensureInitialized();
      final prefs = await SharedPreferences.getInstance();
      final sale = _Sale();
      final auth = _Auth();
      final settings = _Settings();
      final theme = _Theme();
      final features = _Features();
      final lan = _Lan();
      final product = Product(
        id: 1,
        name: 'Remote shirt',
        costCents: Decimal.zero,
        priceCents: Decimal.fromInt(15000),
        stockQuantity: 8,
        minQuantity: 0,
        hasVariants: false,
        isTaxable: false,
        purchaseTaxRateBps: 0,
        salesTaxRateBps: 0,
        isActive: true,
        trackInventory: true,
      );
      when(() => sale.state).thenReturn(
        SaleFormState(
          currencyId: 1,
          saleDate: DateTime(2026),
          items: [
            SaleLineItem(
              tempId: 'line1',
              product: product,
              quantity: 1,
              unitPriceCents: Decimal.fromInt(15000),
              stockSourceVariantId: 2,
            ),
          ],
        ),
      );
      when(() => auth.state).thenReturn(const AuthUnauthenticated());
      when(
        () => settings.state,
      ).thenReturn(const AppSettingsState(settings: AppSettings()));
      when(
        () => theme.state,
      ).thenReturn(RealtimeSuccess(data: ThemeMode.light));
      when(
        () => features.isEnabled(
          AppFeature.promotions,
          settingEnabled: any(named: 'settingEnabled'),
        ),
      ).thenReturn(false);
      sl.registerSingleton<SaleFormBloc>(sale);
      sl.registerSingleton<LanNetworkService>(lan);
      sl.registerSingleton<CurrencyService>(CurrencyService(prefs));
      sl.registerSingleton<FeatureGateService>(features);
      addTearDown(() => sl.reset());
      tester.view.physicalSize = const Size(1200, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        EasyLocalization(
          supportedLocales: const [Locale('en')],
          path: 'assets/translations',
          assetLoader: const _Assets(),
          child: MultiBlocProvider(
            providers: [
              BlocProvider<AuthBloc>.value(value: auth),
              BlocProvider<AppSettingsBloc>.value(value: settings),
              BlocProvider<ThemeBloc>.value(value: theme),
            ],
            child: Builder(
              builder: (context) => MaterialApp(
                locale: context.locale,
                supportedLocales: context.supportedLocales,
                localizationsDelegates: context.localizationDelegates,
                home: const SaleFormScreen(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remote shirt').first);
      await tester.pumpAndSettle();
      final discount = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == '0.00',
      );
      expect(discount, findsOneWidget);
      await tester.enterText(discount, '10');
      await tester.tap(find.text('Save').last);
      await tester.pumpAndSettle();
      expect(lan.checks, 1);
      verify(
        () => sale.add(
          any(
            that: isA<SaleLineItemUpdated>().having(
              (e) => e.discountCents,
              'discount',
              Decimal.fromInt(1000),
            ),
          ),
        ),
      ).called(1);
      expect(find.textContaining('Failed to load stock'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
