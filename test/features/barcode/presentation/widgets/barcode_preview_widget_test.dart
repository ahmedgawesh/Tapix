import 'package:barcode_widget/barcode_widget.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tapix/core/di/injection_container.dart';
import 'package:tapix/core/services/currency_service.dart';
import 'package:tapix/features/barcode/domain/models/barcode_design_state.dart';
import 'package:tapix/features/barcode/presentation/widgets/barcode_preview_widget.dart';
import 'package:tapix/features/barcode/services/barcode_printer_service.dart';
import 'package:tapix/features/products/domain/entities/product_entity.dart';
import 'package:tapix/features/settings/domain/entities/company_profile.dart';

class _Printer extends Fake implements BarcodePrinterService {
  @override
  Barcode getBarcodeTypeAuto(String data, String typeString) =>
      Barcode.code128();
  @override
  Barcode getBarcodeTypeFromString(String typeString) => Barcode.code128();
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    sl.registerSingleton<CurrencyService>(
      CurrencyService(await SharedPreferences.getInstance()),
    );
    sl.registerSingleton<BarcodePrinterService>(_Printer());
  });
  tearDown(() => sl.reset());
  testWidgets(
    'dark app keeps barcode digits black and prints only supplied company data',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: Center(
              child: BarcodePreviewWidget(
                product: Product(
                  id: 1,
                  name: 'Product',
                  barcode: '123456789012',
                  sku: '150',
                  costCents: Decimal.fromInt(10000),
                  priceCents: Decimal.fromInt(15000),
                  stockQuantity: 0,
                  minQuantity: 0,
                  hasVariants: false,
                  isTaxable: false,
                  isActive: true,
                  trackInventory: true,
                  purchaseTaxRateBps: 0,
                  salesTaxRateBps: 0,
                ),
                settings: const BarcodeDesignSettings(
                  includeCompanyContact: true,
                ),
                companyProfile: const CompanyProfile(name: 'My company'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('My company'), findsOneWidget);
      expect(find.text('بيئة اختبار معزولة'), findsNothing);
      expect(find.text('01000000000'), findsNothing);
      expect(
        tester.widget<BarcodeWidget>(find.byType(BarcodeWidget)).style?.color,
        Colors.black,
      );
    },
  );
}
