import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:bloc_test/bloc_test.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tapix/core/database/daos/adjustment_return_dao.dart';
import 'package:tapix/core/di/injection_container.dart';
import 'package:tapix/core/services/currency_service.dart';
import 'package:tapix/core/services/lan/lan_network_service.dart';
import 'package:tapix/features/purchases/presentation/bloc/purchase_adj_return_form_bloc.dart';
import 'package:tapix/features/sales/presentation/bloc/sale_adj_return_form_bloc.dart';
import 'package:tapix/features/sales/presentation/screens/sale_adj_return_form_screen.dart';

class _Bloc extends MockBloc<SaleAdjReturnFormEvent, SaleAdjReturnFormState>
    implements SaleAdjReturnFormBloc {}

class _Dao extends Mock implements AdjustmentReturnDao {}

class _Lan extends Mock implements LanNetworkService {}

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
  for (final language in ['ar', 'en', 'fr']) {
    for (final dark in [false, true]) {
      testWidgets(
        'checkout warnings lead fields and follow customer changes $language dark=$dark',
        (tester) async {
          await sl.reset();
          addTearDown(sl.reset);
          tester.view.physicalSize = dark
              ? const Size(1000, 900)
              : const Size(420, 1000);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final dao = _Dao(), lan = _Lan(), bloc = _Bloc();
          when(() => lan.snapshot).thenReturn(const LanNetworkSnapshot());
          when(
            () => dao.getCustomerProductPurchasedQty(
              customerId: 1,
              productId: 1,
              variantId: 1,
            ),
          ).thenAnswer((_) async => 2);
          when(
            () => dao.getCustomerProductPurchasedQty(
              customerId: 2,
              productId: 1,
              variantId: 1,
            ),
          ).thenAnswer((_) async => 5);
          when(
            () => dao.getEmployeeProductSoldQty(
              employeeId: 1,
              productId: 1,
              variantId: 1,
            ),
          ).thenAnswer((_) async => 0);
          when(
            () => dao.getEmployeeProductSoldQty(
              employeeId: 2,
              productId: 1,
              variantId: 1,
            ),
          ).thenAnswer((_) async => 5);
          sl.registerSingleton<AdjustmentReturnDao>(dao);
          sl.registerSingleton<LanNetworkService>(lan);
          final initial = SaleAdjReturnFormState(
            customerId: 1,
            customerName: 'Buyer A',
            employeeId: 1,
            employeeName: 'Seller A',
            items: const [
              AdjReturnLineItem(
                productId: 1,
                variantId: 1,
                productName: 'Test item',
                quantity: 3,
                unitPriceCents: 13000,
              ),
            ],
          );
          final changes = StreamController<SaleAdjReturnFormState>.broadcast();
          addTearDown(changes.close);
          whenListen(bloc, changes.stream, initialState: initial);
          final currency = CurrencyService(
            await SharedPreferences.getInstance(),
          );
          await tester.pumpWidget(
            EasyLocalization(
              supportedLocales: const [
                Locale('ar'),
                Locale('en'),
                Locale('fr'),
              ],
              path: 'assets/translations',
              assetLoader: const _Assets(),
              startLocale: Locale(language),
              child: Builder(
                builder: (context) => MaterialApp(
                  locale: context.locale,
                  supportedLocales: context.supportedLocales,
                  localizationsDelegates: context.localizationDelegates,
                  theme: dark ? ThemeData.dark() : ThemeData.light(),
                  home: Scaffold(
                    body: BlocProvider<SaleAdjReturnFormBloc>.value(
                      value: bloc,
                      child: SaleAdjustmentCheckoutSheet(
                        currencyService: currency,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final warnings = find.text('returns.fraud_warnings_title'.tr());
          expect(warnings, findsOneWidget);
          expect(
            find.text('returns.adjustment_return_warning_title'.tr()),
            findsOneWidget,
          );
          final customer = find.text('sales.customer'.tr());
          expect(
            tester.getTopLeft(warnings).dy,
            lessThan(tester.getTopLeft(customer).dy),
          );
          expect(tester.takeException(), isNull);
          changes.add(
            initial.copyWith(
              customerId: 2,
              customerName: 'Buyer B',
              employeeId: 2,
              employeeName: 'Seller B',
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('returns.fraud_warnings_title'.tr()), findsNothing);
          expect(
            find.text('returns.adjustment_return_warning_title'.tr()),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
        },
      );
    }
  }
}
