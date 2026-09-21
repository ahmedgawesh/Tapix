import 'dart:convert';
import 'dart:io';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tapix/core/di/injection_container.dart';
import 'package:tapix/core/services/business/warehouse_read_scope.dart';
import 'package:tapix/features/reports/presentation/bloc/supplier_sales_report_bloc.dart';
import 'package:tapix/features/reports/presentation/screens/supplier_sales_report_screen.dart';
import 'business_foundation_test.dart' as fixtures;

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
      testWidgets('supplier search $language dark=$dark', (tester) async {
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
        await db.customSelect('SELECT 1').get();
        final currency = (await db.select(db.currencies).get()).first.id;
        await db.customStatement(
          'INSERT INTO suppliers(name,currency_id) VALUES(?,?)',
          ['Shoes Supplier', currency],
        );
        await db.customStatement(
          'INSERT INTO suppliers(name,currency_id) VALUES(?,?)',
          ['Other Supplier', currency],
        );
        sl.registerFactoryParam<
          SupplierSalesReportBloc,
          WarehouseReadScope?,
          void
        >((scope, _) => SupplierSalesReportBloc(db, warehouseScope: scope));
        await tester.pumpWidget(
          EasyLocalization(
            supportedLocales: const [Locale('ar'), Locale('en'), Locale('fr')],
            path: 'assets/translations',
            assetLoader: const _Assets(),
            startLocale: Locale(language),
            child: Builder(
              builder: (ctx) => MaterialApp(
                locale: ctx.locale,
                supportedLocales: ctx.supportedLocales,
                localizationsDelegates: ctx.localizationDelegates,
                theme: dark ? ThemeData.dark() : ThemeData.light(),
                home: const SupplierSalesReportScreen(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextFormField), 'Shoes');
        await tester.pumpAndSettle();
        expect(find.text('Shoes Supplier'), findsOneWidget);
        expect(find.text('Other Supplier'), findsNothing);
        await tester.tap(find.text('Shoes Supplier'));
        await tester.pumpAndSettle();
        expect(find.text('Shoes Supplier'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byIcon(Icons.clear));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      });
    }
  }
}
