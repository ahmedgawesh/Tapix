import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tapix/core/database/app_database.dart' hide Size;
import 'package:tapix/features/business/data/company_branch_monitor_service.dart';
import 'package:tapix/features/business/presentation/screens/company_branch_monitor_screen.dart';
import 'package:tapix/features/business/presentation/screens/company_document_detail_screen.dart';

class _Assets extends AssetLoader {
  const _Assets();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(File('$path/${locale.languageCode}.json').readAsStringSync())
          as Map<String, dynamic>;
}

class _Monitor extends CompanyBranchMonitorService {
  _Monitor(this.snapshot)
    : super(AppDatabase.connect(DatabaseConnection(NativeDatabase.memory())));

  final CompanyBranchMonitorSnapshot snapshot;

  @override
  Future<CompanyBranchMonitorSnapshot> load({DateTime? now}) async => snapshot;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  final snapshot = CompanyBranchMonitorSnapshot(
    generatedAt: DateTime.utc(2026, 9, 30, 8),
    locations: [
      const CompanyLocationStatus(
        branchId: 'main',
        branchCode: 'MAIN',
        branchName: 'Main branch',
        warehouses: [
          CompanyWarehouseStatus(
            id: 'main-wh',
            branchId: 'main',
            code: 'MAIN-WH',
            name: 'Main warehouse',
            isActive: true,
          ),
        ],
        isLocal: true,
        isEnrolled: true,
        isOnline: true,
      ),
      CompanyLocationStatus(
        branchId: 'cairo',
        branchCode: 'CAIRO',
        branchName: 'Cairo cosmetics branch with a long responsive name',
        warehouses: const [
          CompanyWarehouseStatus(
            id: 'cairo-wh',
            branchId: 'cairo',
            code: 'CAIRO-WH',
            name: 'Cairo default warehouse',
            isActive: true,
          ),
        ],
        isLocal: false,
        isEnrolled: true,
        isOnline: false,
        lastSeenAt: DateTime.utc(2026, 9, 30, 7),
      ),
    ],
    documents: [
      CompanyDocumentSnapshot(
        documentId: 'purchase-1',
        sourceDatabaseId: 'remote-db',
        branchId: 'cairo',
        branchName: 'Cairo cosmetics branch with a long responsive name',
        warehouseId: 'cairo-wh',
        warehouseName: 'Cairo default warehouse',
        kind: CompanyDocumentKind.purchase,
        number: 'PI-CAIRO-202609-000001',
        documentDate: DateTime.utc(2026, 9, 30, 7, 30),
        currencyCode: 'USD',
        totalMinor: 125050,
        itemCount: 12,
        isRemote: true,
        isVoided: false,
        occurredAt: DateTime.utc(2026, 9, 30, 7, 31),
        partyName: 'Supplier one',
        paymentMethod: 'credit',
        subtotalMinor: 125050,
        taxMinor: 0,
        paidMinor: 0,
        lines: const [
          CompanyDocumentLineSnapshot(
            productName: 'Tracked medicine',
            variantName: 'Pack 20',
            quantityScaled: 2,
            quantityScale: 1,
            measurementType: 'piece',
            unitMinor: 62525,
            subtotalMinor: 125050,
            discountMinor: 0,
            taxMinor: 0,
            totalMinor: 125050,
            batches: [
              CompanyDocumentBatchSnapshot(
                number: 'LOT-2026',
                quantityScaled: 2,
              ),
            ],
          ),
        ],
      ),
    ],
  );

  for (final language in ['ar', 'en', 'fr']) {
    for (final dark in [false, true]) {
      testWidgets('company monitor fits $language dark=$dark', (tester) async {
        tester.view.physicalSize = dark
            ? const Size(1200, 900)
            : const Size(360, 740);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
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
                home: CompanyBranchMonitorScreen(service: _Monitor(snapshot)),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(CompanyBranchMonitorScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -900));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final documentCard = find.byKey(
          const ValueKey('company-document-purchase-1'),
        );
        await tester.ensureVisible(documentCard);
        await tester.tap(documentCard);
        await tester.pumpAndSettle();
        expect(find.byType(CompanyDocumentDetailScreen), findsOneWidget);
        expect(find.byIcon(Icons.print_outlined), findsOneWidget);
        expect(find.byIcon(Icons.share_outlined), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('Tracked medicine'),
          220,
          scrollable: find.byType(Scrollable).last,
        );
        expect(find.text('Tracked medicine'), findsOneWidget);
        expect(find.text('LOT-2026'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
