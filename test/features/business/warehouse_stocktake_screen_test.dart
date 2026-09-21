import 'dart:convert';
import 'dart:io';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tapix/core/services/business/warehouse_operation_scope.dart';
import 'package:tapix/core/services/business/warehouse_stocktake_service.dart';
import 'package:tapix/core/services/inventory/inventory_adjustment_service.dart';
import 'package:tapix/core/services/journal_entry_service.dart';
import 'package:tapix/features/accounting/data/repositories/accounting_repository.dart';
import 'package:tapix/features/business/data/warehouse_setup_service.dart';
import 'package:tapix/features/business/presentation/screens/warehouse_stocktake_screen.dart';
import 'business_foundation_test.dart' as fixtures;

class _Assets extends AssetLoader {
  const _Assets();
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(File('$path/${locale.languageCode}.json').readAsStringSync())
          as Map<String, dynamic>;
}

class _Service extends Fake implements WarehouseSetupService {
  late WarehouseCountItem item;
  int calls = 0;
  @override
  Future<List<WarehouseCountItem>> countItems(
    String warehouseId, {
    String query = '',
    int offset = 0,
  }) async => [item];
  @override
  Future<void> postCount({
    required WarehouseCountItem item,
    required String countedQuantity,
    required String reason,
  }) async {
    expect(item.parseQuantity(countedQuantity), 3);
    expect(reason, 'Counted');
    calls++;
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
      testWidgets('stocktake $language dark=$dark previews and submits once', (
        tester,
      ) async {
        tester.view.physicalSize = dark
            ? const Size(1200, 900)
            : const Size(360, 740);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final db = fixtures.memoryDb();
        addTearDown(db.close);
        await fixtures.seedLegacyData(db);
        final scope = await WarehouseOperationScope.resolve(db);
        final variant = (await db.select(db.productVariants).get()).first;
        final stocktake = WarehouseStocktakeService(
          db,
          InventoryAdjustmentService(
            db: db,
            dao: db.inventoryAdjustmentDao,
            journal: JournalEntryService(AccountingRepository(db)),
          ),
        );
        final service = _Service()
          ..item = WarehouseCountItem(
            snapshot: await stocktake.capture(
              scope: scope,
              variantId: variant.id,
            ),
            name: 'Product',
            label: 'Blue',
            quantityScale: 1,
          );
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
                home: WarehouseStocktakeScreen(
                  service: service,
                  warehouseId: scope.warehouseId,
                  warehouseName: 'Warehouse 2',
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final dropdown = find.byType(
          DropdownButtonFormField<WarehouseCountItem>,
        );
        await tester.ensureVisible(dropdown);
        await tester.tap(dropdown);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Product · Blue').last);
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextFormField).at(0), '3');
        await tester.enterText(find.byType(TextFormField).at(1), 'Counted');
        tester.testTextInput.hide();
        await tester.pumpAndSettle();
        final button = find.byType(FilledButton);
        await tester.scrollUntilVisible(
          button,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(service.calls, 0);
        await tester.scrollUntilVisible(
          button,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(service.calls, 1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      });
    }
  }
}
