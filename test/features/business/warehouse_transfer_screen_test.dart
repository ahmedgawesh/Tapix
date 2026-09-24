import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tapix/core/services/lan/lan_business_models.dart';
import 'package:tapix/features/business/data/warehouse_transfer_application_service.dart';
import 'package:tapix/features/business/presentation/screens/warehouse_transfer_screen.dart';

class _Assets extends AssetLoader {
  const _Assets();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(File('$path/${locale.languageCode}.json').readAsStringSync())
          as Map<String, dynamic>;
}

class _Service extends Fake implements WarehouseTransferApplicationService {
  _Service(this.rows);
  final List<WarehouseTransferAppWarehouse> rows;

  @override
  Future<List<WarehouseTransferAppWarehouse>> warehouses() async => rows;

  @override
  Future<List<WarehouseTransferAppDocument>> list({
    required Set<String> statuses,
    int limit = 100,
  }) async => const [];
}

class _RetryingOperationService extends Fake
    implements WarehouseTransferApplicationService {
  final List<String> dispatchKeys = [];
  var failFirstDispatch = true;

  static const warehousesList = [
    WarehouseTransferAppWarehouse(
      id: '11111111-1111-4111-8111-111111111111',
      code: 'MAIN',
      name: 'Main warehouse',
    ),
    WarehouseTransferAppWarehouse(
      id: '44444444-4444-4444-8444-444444444444',
      code: 'B02',
      name: 'Branch warehouse',
    ),
  ];

  static const draft = WarehouseTransferAppDocument(
    id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    sourceWarehouseId: '11111111-1111-4111-8111-111111111111',
    destinationWarehouseId: '44444444-4444-4444-8444-444444444444',
    status: 'draft',
    lineCount: 1,
    notes: '',
    recalled: false,
  );

  @override
  Future<List<WarehouseTransferAppWarehouse>> warehouses() async =>
      warehousesList;

  @override
  Future<List<WarehouseTransferAppDocument>> list({
    required Set<String> statuses,
    int limit = 100,
  }) async => statuses.contains('draft') ? const [draft] : const [];

  @override
  Future<void> dispatch({
    required String transferId,
    required String requestKey,
  }) async {
    dispatchKeys.add(requestKey);
    if (failFirstDispatch) {
      failFirstDispatch = false;
      throw const LanBusinessException(
        'remote_request_failed',
        'Response lost after sending.',
      );
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets(
    'retry keeps the dispatch operation key and success survives refresh',
    (tester) async {
      tester.view.physicalSize = const Size(400, 820);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = _RetryingOperationService();

      await tester.pumpWidget(
        EasyLocalization(
          supportedLocales: const [Locale('ar'), Locale('en'), Locale('fr')],
          path: 'assets/translations',
          assetLoader: const _Assets(),
          startLocale: const Locale('en'),
          saveLocale: false,
          child: Builder(
            builder: (context) => MaterialApp(
              locale: context.locale,
              supportedLocales: context.supportedLocales,
              localizationsDelegates: context.localizationDelegates,
              home: WarehouseTransferScreen(service: service),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      Future<void> confirmDispatch() async {
        final cardButton = find.widgetWithText(FilledButton, 'Dispatch').first;
        await tester.ensureVisible(cardButton);
        await tester.pumpAndSettle();
        await tester.tap(cardButton);
        await tester.pumpAndSettle();
        final dialogButton = find.widgetWithText(FilledButton, 'Dispatch').last;
        await tester.tap(dialogButton);
        await tester.pumpAndSettle();
      }

      await confirmDispatch();
      expect(
        find.text(
          'The operation could not be completed. Refresh data and check stock and access before retrying.',
        ),
        findsOneWidget,
      );
      await confirmDispatch();

      expect(service.dispatchKeys, hasLength(2));
      expect(service.dispatchKeys[1], service.dispatchKeys[0]);
      expect(
        find.text(
          'The transfer was dispatched and the stock is now in transit.',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final language in ['ar', 'en', 'fr']) {
    for (final dark in [false, true]) {
      testWidgets('transfer home is responsive in $language dark=$dark', (
        tester,
      ) async {
        tester.view.physicalSize = dark
            ? const Size(1200, 900)
            : const Size(360, 740);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        const warehouses = [
          WarehouseTransferAppWarehouse(
            id: '11111111-1111-4111-8111-111111111111',
            code: 'MAIN',
            name: 'Main warehouse',
          ),
          WarehouseTransferAppWarehouse(
            id: '44444444-4444-4444-8444-444444444444',
            code: 'B02',
            name: 'Branch warehouse',
          ),
        ];

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
                home: WarehouseTransferScreen(service: _Service(warehouses)),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(WarehouseTransferScreen), findsOneWidget);
        expect(find.byType(FloatingActionButton), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      });
    }
  }
}
