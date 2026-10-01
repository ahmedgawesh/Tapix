import 'dart:async';
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

class _ComposerService extends _Service {
  _ComposerService() : super(_RetryingOperationService.warehousesList);

  @override
  Future<List<WarehouseTransferAppCatalogItem>> catalog(
    String warehouseId, {
    String query = '',
    int offset = 0,
  }) async => const [
    WarehouseTransferAppCatalogItem(
      productId: 1,
      variantId: 11,
      name: 'Mixed ownership product',
      code: 'MIX-11',
      quantity: 10,
      supplierOwnedQuantity: 4,
      quantityScale: 1,
      measurementType: 'piece',
    ),
  ];
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

class _ReceiptService extends _Service {
  _ReceiptService() : super(_RetryingOperationService.warehousesList);
  @override
  Future<List<WarehouseTransferAppDocument>> list({
    required Set<String> statuses,
    int limit = 100,
  }) async => const [
    WarehouseTransferAppDocument(
      id: 'transfer',
      sourceWarehouseId: '11111111-1111-4111-8111-111111111111',
      destinationWarehouseId: '44444444-4444-4444-8444-444444444444',
      status: 'in_transit',
      lineCount: 1,
      notes: '',
      recalled: false,
    ),
  ];
  @override
  Future<List<WarehouseTransferAppPending>> pending(String transferId) async =>
      const [
        WarehouseTransferAppPending(
          allocationId: 'allocation',
          remainingQuantity: 2,
          quantityScale: 1,
          productName: 'Pending product',
          code: 'P1',
          ownerType: 'owned',
        ),
      ];
}

class _AutoRefreshService extends _Service {
  _AutoRefreshService() : super(_RetryingOperationService.warehousesList);

  bool completed = false;
  int listCalls = 0;

  static const _transferId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

  @override
  Future<List<WarehouseTransferAppDocument>> list({
    required Set<String> statuses,
    int limit = 100,
  }) async {
    listCalls++;
    final status = completed ? 'completed' : 'in_transit';
    if (!statuses.contains(status)) return const [];
    return [
      WarehouseTransferAppDocument(
        id: _transferId,
        sourceWarehouseId: '11111111-1111-4111-8111-111111111111',
        destinationWarehouseId: '44444444-4444-4444-8444-444444444444',
        status: status,
        lineCount: 1,
        notes: '',
        recalled: false,
      ),
    ];
  }
}

class _DelayedRefreshService extends _AutoRefreshService {
  final delayed = Completer<List<WarehouseTransferAppDocument>>();

  @override
  Future<List<WarehouseTransferAppDocument>> list({
    required Set<String> statuses,
    int limit = 100,
  }) async {
    if (listCalls == 1) {
      listCalls++;
      return delayed.future;
    }
    return super.list(statuses: statuses, limit: limit);
  }
}

class _PerspectiveService extends _ReceiptService {
  _PerspectiveService(this.sender);
  final bool sender;
  @override
  Future<List<WarehouseTransferAppDocument>> list({
    required Set<String> statuses,
    int limit = 100,
  }) async => (await super.list(statuses: statuses, limit: limit))
      .map(
        (row) => row.viewedFrom(
          sender ? row.sourceWarehouseId : row.destinationWarehouseId,
        ),
      )
      .toList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  for (final sender in [true, false]) {
    testWidgets(
      'same branch transfer shows only ${sender ? "sender" : "receiver"} actions',
      (tester) async {
        tester.view.physicalSize = const Size(1100, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          EasyLocalization(
            supportedLocales: const [Locale('en')],
            path: 'assets/translations',
            assetLoader: const _Assets(),
            startLocale: const Locale('en'),
            saveLocale: false,
            child: Builder(
              builder: (context) => MaterialApp(
                locale: context.locale,
                supportedLocales: context.supportedLocales,
                localizationsDelegates: context.localizationDelegates,
                home: WarehouseTransferScreen(
                  service: _PerspectiveService(sender),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(
            sender
                ? 'Outgoing — awaiting destination receipt'
                : 'Incoming — awaiting your receipt',
          ),
          findsOneWidget,
        );
        expect(
          find.text('warehouse_transfer.receive'.tr()),
          sender ? findsNothing : findsOneWidget,
        );
        expect(
          find.text('warehouse_transfer.recall'.tr()),
          sender ? findsOneWidget : findsNothing,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }

  testWidgets(
    'refreshes a transfer completed on another device without manual input',
    (tester) async {
      tester.view.physicalSize = const Size(400, 820);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = _AutoRefreshService();

      await tester.pumpWidget(
        EasyLocalization(
          supportedLocales: const [Locale('en')],
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

      expect(find.text('#BBBBBBBB'), findsOneWidget);
      final callsBeforeCompletion = service.listCalls;
      service.completed = true;

      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();

      expect(service.listCalls, greaterThan(callsBeforeCompletion));
      expect(find.text('#BBBBBBBB'), findsNothing);

      await tester.tap(find.text('Completed'));
      await tester.pumpAndSettle();
      expect(find.text('#BBBBBBBB'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets('a delayed automatic refresh cannot overwrite the selected tab', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = _DelayedRefreshService();

    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en')],
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

    expect(find.text('#BBBBBBBB'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pump();
    expect(service.listCalls, 2);
    await tester.tap(find.text('Completed'));
    await tester.pumpAndSettle();
    expect(find.text('#BBBBBBBB'), findsNothing);

    service.delayed.complete(const [
      WarehouseTransferAppDocument(
        id: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
        sourceWarehouseId: '11111111-1111-4111-8111-111111111111',
        destinationWarehouseId: '44444444-4444-4444-8444-444444444444',
        status: 'in_transit',
        lineCount: 1,
        notes: '',
        recalled: false,
      ),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('#BBBBBBBB'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('receipt dialog renders pending quantities on a narrow screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en')],
        path: 'assets/translations',
        assetLoader: const _Assets(),
        startLocale: const Locale('en'),
        saveLocale: false,
        child: Builder(
          builder: (context) => MaterialApp(
            locale: context.locale,
            supportedLocales: context.supportedLocales,
            localizationsDelegates: context.localizationDelegates,
            home: WarehouseTransferScreen(service: _ReceiptService()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final receive = find.widgetWithText(FilledButton, 'Receive');
    await tester.ensureVisible(receive);
    await tester.pumpAndSettle();
    await tester.tap(receive);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    expect(find.text('Pending product'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Back'));
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
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

  testWidgets(
    'quantity dialog survives its closing animation and explains mixed ownership',
    (tester) async {
      tester.view.physicalSize = const Size(400, 820);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

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
              home: WarehouseTransferScreen(service: _ComposerService()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      final sourceButton = find.ancestor(
        of: find.byIcon(Icons.upload_outlined),
        matching: find.byType(OutlinedButton),
      );
      await tester.tap(sourceButton);
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Main warehouse').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Add').last);
      await tester.pumpAndSettle();
      expect(find.text('Company-owned: 6'), findsOneWidget);
      expect(find.text('Consignment: 4'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pump();
      expect(
        find.text(
          'Enter a valid quantity for each ownership type within its available balance.',
        ),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const ValueKey('transfer-consignment-quantity')),
        '1',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pumpAndSettle();

      expect(find.text('Mixed ownership product'), findsWidgets);
      expect(find.textContaining('consignment 1'), findsWidgets);
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
