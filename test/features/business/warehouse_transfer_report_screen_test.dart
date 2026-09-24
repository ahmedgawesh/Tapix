import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tapix/core/database/app_database.dart' hide Size;
import 'package:tapix/core/services/business/warehouse_read_scope.dart';
import 'package:tapix/features/business/data/warehouse_transfer_reporting_service.dart';
import 'package:tapix/features/business/presentation/screens/warehouse_transfer_report_screen.dart';
import 'package:tapix/features/reports/presentation/widgets/warehouse_report_context.dart';

class _Assets extends AssetLoader {
  const _Assets();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(File('$path/${locale.languageCode}.json').readAsStringSync())
          as Map<String, dynamic>;
}

class _Report extends Fake implements WarehouseTransferReportingService {
  _Report(this.warehouseId);
  final String warehouseId;

  @override
  Future<WarehouseTransferReportData> report({
    required String warehouseId,
    required DateTime from,
    required DateTime toExclusive,
    String direction = 'all',
    String ownership = 'all',
    String status = 'all',
    int? supplierId,
    String search = '',
    int limit = 1000,
  }) async => WarehouseTransferReportData(
    warehouseId: warehouseId,
    from: from,
    toExclusive: toExclusive,
    rows: [
      WarehouseTransferReportRow(
        transferId: '11111111-1111-4111-8111-111111111111',
        status: 'partially_received',
        recalled: false,
        dispatchedAt: DateTime.utc(2026, 9, 24, 12),
        sourceWarehouseId: warehouseId,
        sourceWarehouse: 'Main warehouse with a long name · MAIN',
        destinationWarehouseId: '22222222-2222-4222-8222-222222222222',
        destinationWarehouse: 'Destination warehouse with a long name · DST',
        productId: 1,
        variantId: 1,
        productName: 'Product with a long localized display name',
        variantLabel: 'Blue Extra Large',
        code: 'SKU-TRANSFER-0001',
        ownerType: 'owned',
        quantityScale: 1,
        measurementType: 'piece',
        dispatchedQuantity: 5,
        acceptedQuantity: 2,
        damagedQuantity: 1,
        lostQuantity: 0,
        recalledQuantity: 0,
        dispatchedValueCents: 5000,
        acceptedValueCents: 2000,
        varianceValueCents: 1000,
        recalledValueCents: 0,
        currencyCode: 'USD',
        sources: const [
          WarehouseTransferSourceSlice(
            quantity: 5,
            quality: 'allocated',
            supplierId: 1,
            supplierName: 'Supplier with a long business name',
            purchaseNumber: 'PI-202609-000001',
          ),
        ],
      ),
    ],
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
      testWidgets('transfer report is responsive in $language dark=$dark', (
        tester,
      ) async {
        tester.view.physicalSize = dark
            ? const Size(1200, 900)
            : const Size(360, 740);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final db = AppDatabase.connect(
          DatabaseConnection(NativeDatabase.memory()),
        );
        addTearDown(db.close);
        final scope = await WarehouseReadScope.resolve(db);

        await tester.pumpWidget(
          EasyLocalization(
            supportedLocales: const [Locale('ar'), Locale('en'), Locale('fr')],
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
                home: WarehouseReportContext(
                  scope: scope,
                  name: 'Main warehouse',
                  code: 'MAIN',
                  child: WarehouseTransferReportScreen(
                    service: _Report(scope.warehouseId),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(WarehouseTransferReportScreen), findsOneWidget);
        expect(find.byType(DropdownButtonFormField<String>), findsNWidgets(3));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      });
    }
  }
}
