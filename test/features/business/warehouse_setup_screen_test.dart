import 'dart:convert';
import 'dart:io';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tapix/core/database/app_database.dart' show BusinessWarehouse;
import 'package:tapix/features/business/data/warehouse_setup_service.dart';
import 'package:tapix/features/business/presentation/screens/warehouse_setup_screen.dart';

class _Assets extends AssetLoader {
  const _Assets();
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(File('$path/${locale.languageCode}.json').readAsStringSync())
          as Map<String, dynamic>;
}

class _Service extends Fake implements WarehouseSetupService {
  bool saved = false;
  int calls = 0;
  @override
  Future<bool> canCreateWarehouse() async => false;
  @override
  Future<List<BusinessWarehouse>> warehouses() async => [
    BusinessWarehouse(
      id: 'warehouse',
      organizationId: 'org',
      branchId: 'branch',
      code: 'W2',
      name: 'Warehouse Two',
      isActive: true,
      createdAt: DateTime(2026),
    ),
  ];
  @override
  Future<List<WarehouseSetupItem>> items(
    String warehouseId, {
    String query = '',
    int offset = 0,
  }) async => saved
      ? []
      : [
          const WarehouseSetupItem(
            variantId: 1,
            name: 'Product sample',
            label: 'Blue / XL',
            currencyId: 1,
            currencyCode: 'KWD',
            decimalDigits: 3,
            quantityScale: 1000,
          ),
        ];
  @override
  Future<int> initializeOpening({
    required String warehouseId,
    required WarehouseSetupItem item,
    required String cost,
    required String quantity,
    required String reason,
    DateTime? expiryDate,
    String? manufacturerLotNumber,
  }) async {
    expect(item.parseQuantity(quantity), 1500);
    expect(reason, 'Initial count');
    return initialize(warehouseId: warehouseId, item: item, cost: cost);
  }

  @override
  Future<int> initialize({
    required String warehouseId,
    required WarehouseSetupItem item,
    required String cost,
  }) async {
    expect(item.parseCost(cost), 12345);
    calls++;
    saved = true;
    return 1;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });
  for (final language in ['ar', 'en', 'fr']) {
    for (final dark in [false, true]) {
      for (final opening in [false, true]) {
        testWidgets(
          'setup $language dark=$dark opening=$opening fits and submits once',
          (tester) async {
            tester.view.physicalSize = dark
                ? const Size(1200, 900)
                : const Size(360, 740);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final service = _Service();
            final locale = Locale(language);
            await tester.pumpWidget(
              EasyLocalization(
                supportedLocales: const [
                  Locale('ar'),
                  Locale('en'),
                  Locale('fr'),
                ],
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
                    home: WarehouseSetupScreen(service: service),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            final dropdown = find.byType(DropdownButtonFormField<String>);
            await tester.ensureVisible(dropdown);
            await tester.tap(dropdown);
            await tester.pumpAndSettle();
            await tester.tap(find.text('Warehouse Two · W2').last);
            await tester.pumpAndSettle();
            await tester.scrollUntilVisible(
              find.text('Product sample'),
              150,
              scrollable: find.byType(Scrollable).first,
            );
            await tester.pumpAndSettle();
            await tester.tap(find.text('Product sample'));
            await tester.pumpAndSettle();
            final cost = find.widgetWithText(
              TextFormField,
              'warehouse_setup.cost'.tr(),
            );
            await tester.scrollUntilVisible(
              cost,
              180,
              scrollable: find.byType(Scrollable).first,
            );
            await tester.enterText(cost, '12.345');
            tester.testTextInput.hide();
            if (opening) {
              final toggle = find.byType(SwitchListTile);
              await tester.ensureVisible(toggle);
              await tester.tap(toggle);
              await tester.pumpAndSettle();
              final quantity = find.widgetWithText(
                TextFormField,
                'warehouse_setup.quantity'.tr(),
              );
              await tester.ensureVisible(quantity);
              await tester.enterText(quantity, '1.5');
              final reason = find.widgetWithText(
                TextFormField,
                'warehouse_setup.reason'.tr(),
              );
              await tester.ensureVisible(reason);
              await tester.enterText(reason, 'Initial count');
              tester.testTextInput.hide();
            }
            final save = find.byType(FilledButton);
            await tester.ensureVisible(save);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            await tester.tap(save);
            await tester.pumpAndSettle();
            if (opening) {
              expect(service.calls, 0);
              expect(find.byType(AlertDialog), findsOneWidget);
              await tester.tap(find.text('warehouse_setup.back'.tr()));
              await tester.pumpAndSettle();
              expect(service.calls, 0);
              await tester.tap(save);
              await tester.pumpAndSettle();
              await tester.tap(find.text('warehouse_setup.confirm'.tr()));
              await tester.pumpAndSettle();
            }
            expect(service.calls, 1);
            expect(
              find.text(
                (opening
                        ? 'warehouse_setup.opening_saved'
                        : 'warehouse_setup.saved')
                    .tr(),
              ),
              findsOneWidget,
            );
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox());
          },
        );
      }
    }
  }
}
