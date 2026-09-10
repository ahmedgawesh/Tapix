import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/database/daos/cheque_confirmation_dao.dart';
import 'package:tapix/core/database/daos/cheque_instrument_dao.dart';
import 'package:tapix/core/di/injection_container.dart';
import 'package:tapix/core/services/cheque_lifecycle_service.dart';
import 'package:tapix/core/services/cheque_management_service.dart';
import 'package:tapix/features/auth/auth.dart';
import 'package:tapix/features/cheques/presentation/screens/cheque_management_screen.dart';

class _MockManagement extends Mock implements ChequeManagementService {}

class _MockLifecycle extends Mock implements ChequeLifecycleService {}

class _MockAuthBloc extends Mock implements AuthBloc {}

class _MapAssetLoader extends AssetLoader {
  const _MapAssetLoader(this.translations);

  final Map<String, dynamic> translations;

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) =>
      SynchronousFuture(translations);
}

void main() {
  late _MockManagement management;
  late _MockLifecycle lifecycle;
  late _MockAuthBloc auth;
  late StreamController<List<ChequeRegisterEntry>> register;
  late ChequeRegisterEntry entry;
  late Map<String, dynamic> englishTranslations;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    englishTranslations =
        jsonDecode(File('assets/translations/en.json').readAsStringSync())
            as Map<String, dynamic>;
  });

  setUp(() async {
    await sl.reset();
    management = _MockManagement();
    lifecycle = _MockLifecycle();
    auth = _MockAuthBloc();
    final now = DateTime(2026, 9, 7);
    entry = ChequeRegisterEntry(
      instrument: ChequeInstrument(
        id: 1,
        direction: ChequeDirectionValue.incoming,
        sourceTable: ChequeSourceTables.sale,
        sourceId: 10,
        amountCents: Decimal.fromInt(10000),
        currencyId: 1,
        chequeNumber: 'OLD-100',
        issueDate: now,
        dueDate: now.add(const Duration(days: 5)),
        status: ChequeInstrumentStatus.received,
        legacyDirectBank: false,
        createdAt: now,
        updatedAt: now,
      ),
      referenceNumber: 'SI-10',
      partyName: 'Customer',
      currencyCode: 'USD',
      currencySymbol: r'$',
    );
    register = StreamController<List<ChequeRegisterEntry>>.broadcast(
      onListen: () => scheduleMicrotask(() => register.add([entry])),
    );
    when(() => management.watchRegister()).thenAnswer((_) => register.stream);
    when(() => auth.state).thenReturn(
      AuthAuthenticated(
        user: UserEntity(
          id: 1,
          username: 'owner',
          role: UserRole.owner,
          isActive: true,
          createdAt: now,
          updatedAt: now,
        ),
      ),
    );
    when(
      () => management.updateDetails(
        entry: entry,
        chequeNumber: any(named: 'chequeNumber'),
        issueDate: any(named: 'issueDate'),
        dueDate: any(named: 'dueDate'),
        bankName: any(named: 'bankName'),
        branchName: any(named: 'branchName'),
        accountNumber: any(named: 'accountNumber'),
        drawerName: any(named: 'drawerName'),
        note: any(named: 'note'),
        userId: any(named: 'userId'),
      ),
    ).thenAnswer((_) async {});
    sl.registerSingleton<ChequeManagementService>(management);
    sl.registerSingleton<ChequeLifecycleService>(lifecycle);
  });

  tearDown(() async {
    await register.close();
    await sl.reset();
  });

  testWidgets(
    'saving details does not dispose controllers during dialog exit animation',
    (tester) async {
      await tester.pumpWidget(
        EasyLocalization(
          supportedLocales: const [Locale('en')],
          path: 'assets/translations',
          assetLoader: _MapAssetLoader(englishTranslations),
          startLocale: const Locale('en'),
          fallbackLocale: const Locale('en'),
          child: Builder(
            builder: (context) => MaterialApp(
              localizationsDelegates: context.localizationDelegates,
              supportedLocales: context.supportedLocales,
              locale: context.locale,
              home: BlocProvider<AuthBloc>.value(
                value: auth,
                child: const ChequeManagementScreen(),
              ),
            ),
          ),
        ),
      );
      // Allow EasyLocalization to finish loading before publishing the
      // register snapshot. A broadcast stream does not replay an event that
      // was emitted while the localized child was still being mounted.
      await tester.pump(const Duration(milliseconds: 100));
      register.add([entry]);
      await tester.pump();
      final cardTitle = find.textContaining('OLD-100');
      for (var i = 0; i < 20 && cardTitle.evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(cardTitle, findsOneWidget);

      await tester.tap(cardTitle);
      await tester.pumpAndSettle();
      final numberField = find.byWidgetPredicate(
        (widget) => widget is TextField && widget.controller?.text == 'OLD-100',
        description: 'cheque number field',
      );
      expect(numberField, findsOneWidget);

      await tester.enterText(numberField, 'NEW-100');
      await tester.tap(find.byType(FilledButton).last);
      await tester.pump();

      // Rebuild the register while the DialogRoute is reversing. Before the
      // fix this tried to reattach animation listeners to disposed text
      // controllers and produced the full-screen ErrorWidget.
      register.add([entry]);
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
