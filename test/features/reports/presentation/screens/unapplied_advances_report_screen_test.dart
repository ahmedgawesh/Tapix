import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/database/daos/cheque_confirmation_dao.dart';
import 'package:tapix/core/database/daos/cheque_instrument_dao.dart';
import 'package:tapix/core/di/injection_container.dart';
import 'package:tapix/features/reports/presentation/screens/unapplied_advances_report_screen.dart';

class _MapAssetLoader extends AssetLoader {
  const _MapAssetLoader(this.translations);

  final Map<String, dynamic> translations;

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) =>
      SynchronousFuture(translations);
}

void main() {
  late AppDatabase db;
  late Map<String, dynamic> arabicTranslations;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    arabicTranslations =
        jsonDecode(File('assets/translations/ar.json').readAsStringSync())
            as Map<String, dynamic>;
  });

  setUp(() async {
    await sl.reset();
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    await db.seedInitialDataForTest();
    sl.registerSingleton<AppDatabase>(db);

    final customerId = await db
        .into(db.customers)
        .insert(
          CustomersCompanion.insert(
            name: 'شركة العميل ذات الاسم الطويل جدًا لاختبار الشاشة الصغيرة',
            currencyId: 1,
          ),
        );
    final chequeId = await ChequeInstrumentDao(db).create(
      direction: ChequeDirectionValue.incoming,
      sourceTable: ChequeSourceTables.customerAccount,
      sourceId: customerId,
      amountCents: 123456789,
      currencyId: 1,
      dueDate: DateTime(2026, 9, 20),
      partyType: 'customer',
      partyId: customerId,
      chequeNumber: 'CUSTOMER-ADVANCE-CHEQUE-0000001',
    );
    await db
        .into(db.partyAccountPayments)
        .insert(
          PartyAccountPaymentsCompanion.insert(
            chequeInstrumentId: chequeId,
            partyType: 'customer',
            partyId: customerId,
            direction: ChequeDirectionValue.incoming,
            amountCents: Decimal.fromInt(123456789),
            currencyId: 1,
            recognizedAt: DateTime(2026, 9, 13),
          ),
        );
  });

  tearDown(() async {
    await sl.reset();
    await db.close();
  });

  testWidgets('renders Arabic report without overflow at 360 logical pixels', (
    tester,
  ) async {
    tester.view.physicalSize = const ui.Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('ar')],
        path: 'assets/translations',
        assetLoader: _MapAssetLoader(arabicTranslations),
        startLocale: const Locale('ar'),
        fallbackLocale: const Locale('ar'),
        child: Builder(
          builder: (context) => MaterialApp(
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            locale: context.locale,
            home: const UnappliedAdvancesReportScreen(),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(find.byType(UnappliedAdvancesReportScreen), findsOneWidget);
    expect(find.textContaining('CUSTOMER-ADVANCE'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
