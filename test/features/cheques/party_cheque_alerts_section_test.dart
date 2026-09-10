import 'package:decimal/decimal.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/database/daos/cheque_confirmation_dao.dart';
import 'package:tapix/core/database/daos/cheque_instrument_dao.dart';
import 'package:tapix/core/di/injection_container.dart';
import 'package:tapix/core/services/cheque_management_service.dart';
import 'package:tapix/features/cheques/presentation/widgets/party_cheque_alerts_section.dart';

class _MockManagement extends Mock implements ChequeManagementService {}

class _MapAssetLoader extends AssetLoader {
  const _MapAssetLoader();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) =>
      SynchronousFuture({
        'cheques': {
          'party_alerts': 'Cheque Alerts',
          'no_party_alerts': 'No cheque alerts',
          'show_all_alerts': 'Show all alerts ({})',
          'alert_bounced_unresolved': 'Bounced cheque requires resolution',
          'alert_overdue': 'Past due',
          'alert_due': 'Due on {}',
          'source_sale': 'Sales invoice',
          'source_purchase': 'Purchase invoice',
          'source_sale_return': 'Sales return',
          'source_purchase_return': 'Purchase return',
          'source_sale_return_adjustment': 'Standalone sales return',
          'source_purchase_return_adjustment': 'Standalone purchase return',
        },
      });
}

void main() {
  late _MockManagement management;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  setUp(() async {
    await sl.reset();
    management = _MockManagement();
    sl.registerSingleton<ChequeManagementService>(management);
  });

  tearDown(() => sl.reset());

  ChequeRegisterEntry entry({
    required int id,
    required String source,
    required String partyType,
    required int partyId,
    String status = ChequeInstrumentStatus.received,
    DateTime? resolvedAt,
  }) {
    final now = DateTime(2026, 9, 9);
    return ChequeRegisterEntry(
      instrument: ChequeInstrument(
        id: id,
        direction: partyType == 'customer'
            ? ChequeDirectionValue.incoming
            : ChequeDirectionValue.outgoing,
        sourceTable: source,
        sourceId: id * 10,
        partyType: partyType,
        partyId: partyId,
        amountCents: Decimal.fromInt(id * 100),
        currencyId: 1,
        chequeNumber: 'CHK-$id',
        issueDate: now,
        dueDate: now.add(Duration(days: id)),
        status: status,
        resolvedAt: resolvedAt,
        legacyDirectBank: false,
        createdAt: now,
        updatedAt: now,
      ),
      referenceNumber: 'REF-$id',
      partyName: partyType,
      currencyCode: 'USD',
      currencySymbol: r'$',
    );
  }

  Future<void> pumpParty(
    WidgetTester tester, {
    required String partyType,
    required int partyId,
  }) async {
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en')],
        path: 'unused',
        assetLoader: const _MapAssetLoader(),
        startLocale: const Locale('en'),
        child: Builder(
          builder: (context) => MaterialApp(
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            locale: context.locale,
            home: Scaffold(
              body: PartyChequeAlertsSection(
                partyType: partyType,
                partyId: partyId,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows every relevant invoice and return cheque source', (
    tester,
  ) async {
    final entries = [
      entry(
        id: 1,
        source: ChequeSourceTables.sale,
        partyType: 'customer',
        partyId: 7,
      ),
      entry(
        id: 2,
        source: ChequeSourceTables.saleReturn,
        partyType: 'customer',
        partyId: 7,
      ),
      entry(
        id: 3,
        source: ChequeSourceTables.saleReturnAdjustment,
        partyType: 'customer',
        partyId: 7,
        status: ChequeInstrumentStatus.bounced,
      ),
      entry(
        id: 4,
        source: ChequeSourceTables.purchase,
        partyType: 'supplier',
        partyId: 8,
      ),
      entry(
        id: 5,
        source: ChequeSourceTables.purchaseReturn,
        partyType: 'supplier',
        partyId: 8,
      ),
      entry(
        id: 6,
        source: ChequeSourceTables.purchaseReturnAdjustment,
        partyType: 'supplier',
        partyId: 8,
        status: ChequeInstrumentStatus.bounced,
      ),
      entry(
        id: 7,
        source: ChequeSourceTables.sale,
        partyType: 'customer',
        partyId: 7,
        status: ChequeInstrumentStatus.bounced,
        resolvedAt: DateTime(2026, 9, 9),
      ),
      entry(
        id: 8,
        source: ChequeSourceTables.sale,
        partyType: 'customer',
        partyId: 99,
      ),
    ];
    when(
      () => management.watchRegister(),
    ).thenAnswer((_) => Stream.value(entries));

    await pumpParty(tester, partyType: 'customer', partyId: 7);
    expect(find.textContaining('REF-1'), findsOneWidget);
    expect(find.textContaining('REF-2'), findsOneWidget);
    expect(find.textContaining('REF-3'), findsOneWidget);
    expect(find.textContaining('REF-7'), findsNothing);
    expect(find.textContaining('REF-8'), findsNothing);
    expect(find.textContaining('alert_bounced_unresolved'), findsOneWidget);

    await pumpParty(tester, partyType: 'supplier', partyId: 8);
    expect(find.textContaining('REF-4'), findsOneWidget);
    expect(find.textContaining('REF-5'), findsOneWidget);
    expect(find.textContaining('REF-6'), findsOneWidget);
    expect(find.textContaining('REF-1'), findsNothing);
  });
}
