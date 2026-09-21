import 'dart:convert';
import 'dart:io';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tapix/core/database/app_database.dart' hide Size;
import 'package:tapix/core/di/injection_container.dart';
import 'package:tapix/core/services/business/warehouse_read_scope.dart';
import 'package:tapix/core/services/currency_service.dart';
import 'package:tapix/features/business/data/warehouse_setup_service.dart';
import 'package:tapix/features/business/presentation/screens/warehouse_reports_screen.dart';
import 'package:tapix/features/reports/presentation/bloc/inventory_reports_bloc.dart';
import 'package:tapix/features/reports/presentation/screens/inventory_reports_screen.dart';
import 'package:tapix/features/reports/presentation/widgets/warehouse_report_context.dart';
import 'package:tapix/features/settings/domain/entities/company_profile.dart';
import 'business_foundation_test.dart' as fixtures;

class _Assets extends AssetLoader {
  const _Assets();
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(File('$path/${locale.languageCode}.json').readAsStringSync())
          as Map<String, dynamic>;
}

class _Service extends Fake implements WarehouseSetupService {
  _Service(this.db, this.warehouse);
  final AppDatabase db;
  final BusinessWarehouse warehouse;
  @override
  Future<List<BusinessWarehouse>> warehouses() async => [warehouse];
  @override
  Future<WarehouseReadScope> reportScope(String id) =>
      WarehouseReadScope.resolve(db, warehouseId: id);
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
        'warehouse report $language dark=$dark keeps scope and export label',
        (tester) async {
          await sl.reset();
          addTearDown(sl.reset);
          tester.view.physicalSize = dark
              ? const Size(1200, 900)
              : const Size(360, 740);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final db = fixtures.memoryDb();
          addTearDown(db.close);
          final scope = await WarehouseReadScope.resolve(db);
          final warehouse =
              (await db.select(db.businessWarehouses).get()).single;
          sl.registerSingleton<CurrencyService>(
            CurrencyService(await SharedPreferences.getInstance()),
          );
          WarehouseReadScope? passedScope;
          sl.registerFactoryParam<
            InventoryReportsBloc,
            WarehouseReadScope?,
            void
          >((selected, _) {
            passedScope = selected;
            return InventoryReportsBloc(db, warehouseScope: selected);
          });
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
              saveLocale: false,
              child: Builder(
                builder: (context) => MaterialApp(
                  locale: context.locale,
                  supportedLocales: context.supportedLocales,
                  localizationsDelegates: context.localizationDelegates,
                  theme: ThemeData(
                    brightness: dark ? Brightness.dark : Brightness.light,
                  ),
                  home: WarehouseReportsScreen(
                    service: _Service(db, warehouse),
                    warehouseId: scope.warehouseId,
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.enterText(
            find.byType(TextField),
            'reports.inventory_reports'.tr(),
          );
          await tester.pumpAndSettle();
          tester.testTextInput.hide();
          await tester.tap(find.text('reports.inventory_reports'.tr()).last);
          await tester.pumpAndSettle();
          expect(passedScope?.warehouseId, warehouse.id);
          final location = WarehouseReportContext.maybeOf(
            tester.element(find.byType(InventoryReportsScreen)),
          )!;
          const company = CompanyProfile(name: 'Company');
          expect(
            location.decorateCompany(company).name,
            contains(warehouse.code),
          );
          expect(company.name, 'Company');
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
        },
      );
    }
  }
}
