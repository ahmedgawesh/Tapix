import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tapix/core/database/app_database.dart' hide Size;
import 'package:tapix/core/di/injection_container.dart';
import 'package:tapix/core/services/currency_service.dart';
import 'package:tapix/features/consignment/data/consignment_reporting_service.dart';
import 'package:tapix/features/consignment/presentation/screens/consignment_hub_screen.dart';

class _Assets extends AssetLoader {
  const _Assets();
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(File('$path/${locale.languageCode}.json').readAsStringSync())
          as Map<String, dynamic>;
}

final _date = DateTime(2026, 9, 23);
ConsignmentSettlementStatement _statement(int id, String status) =>
    ConsignmentSettlementStatement(
      id: id,
      organizationId: 'org',
      branchId: 'branch',
      databaseId: 'db',
      supplierId: 1,
      agreementId: 'agreement',
      currencyId: 1,
      statementNumber: 'STATEMENT-$id',
      periodStart: _date,
      periodEnd: _date,
      taxRateBps: 0,
      taxInclusive: false,
      obligationSubtotalCents: 1000,
      taxCents: 0,
      totalCents: 1000,
      paidCents: status == 'partially_paid' ? 100 : 0,
      lineCount: 1,
      status: status,
      dueDate: _date,
      requestKey: 'key-$id',
      requestHash: 'hash',
      notes: '',
      createdBy: 1,
      voidReason: '',
      createdAt: _date,
      updatedAt: _date,
    );

class _Reports implements ConsignmentReportingService {
  _Reports(this.canManage);
  final bool canManage;
  @override
  Future<ConsignmentDashboardSnapshot> load() async =>
      ConsignmentDashboardSnapshot(
        agreements: const [],
        receipts: const [],
        custodyDocuments: const [],
        ownershipConversions: const [],
        statements: [
          _statement(1, 'draft'),
          _statement(2, 'reviewed'),
          _statement(3, 'partially_paid'),
        ],
        payments: [
          ConsignmentSettlementPayment(
            id: 1,
            statementId: 3,
            amountCents: 100,
            paymentMethod: 'cash',
            reference: '',
            status: 'posted',
            requestKey: 'payment-key',
            supplierTransactionId: 1,
            journalEntryId: 1,
            paidAt: _date,
            createdBy: 1,
            reversalReason: '',
            createdAt: _date,
          ),
        ],
        suppliers: const {},
        currencyCodes: const {1: 'USD'},
        // New work is disabled; historical documents still need completing.
        operationsEnabled: false,
        historicalManagementEnabled: canManage,
        openCustodyAgreementIds: const {},
        reportRows: const [],
      );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });
  for (final canManage in [true, false]) {
    testWidgets(
      'disabled module preserves historical permissions: manager=$canManage',
      (tester) async {
        await sl.reset();
        addTearDown(sl.reset);
        tester.view.physicalSize = const Size(1400, 2200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        sl.registerSingleton<ConsignmentReportingService>(_Reports(canManage));
        sl.registerSingleton<CurrencyService>(
          CurrencyService(await SharedPreferences.getInstance()),
        );
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
                home: const ConsignmentHubScreen(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('consignment.settlements'.tr()).first);
        await tester.pumpAndSettle();
        for (final action in ['review', 'post', 'pay', 'void_statement']) {
          final buttons = tester.widgetList<IconButton>(
            find.byWidgetPredicate(
              (w) => w is IconButton && w.tooltip == 'consignment.$action'.tr(),
            ),
          );
          expect(buttons, isNotEmpty, reason: action);
          for (final button in buttons) {
            expect(button.onPressed != null, canManage, reason: action);
          }
        }
        // Read-only users can inspect payments but cannot reverse them.
        await tester.tap(find.byTooltip('consignment.payments'.tr()));
        await tester.pumpAndSettle();
        final reverse = tester.widget<TextButton>(
          find.widgetWithText(TextButton, 'consignment.reverse_payment'.tr()),
        );
        expect(reverse.onPressed != null, canManage);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
