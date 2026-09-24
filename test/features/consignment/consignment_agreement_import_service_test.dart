import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/features/consignment/data/consignment_agreement_import_service.dart';

void main() {
  late AppDatabase db;
  late int currencyId;
  late int supplierId;
  late int productId;
  late int variantId;

  Future<int> purchase({
    required String number,
    required DateTime date,
    required String status,
    required List<({int quantity, int gross, int discount, int value})> lines,
  }) async {
    final subtotal = lines.fold<int>(0, (sum, line) => sum + line.gross);
    final discount = lines.fold<int>(0, (sum, line) => sum + line.discount);
    final id = await db
        .into(db.purchases)
        .insert(
          PurchasesCompanion.insert(
            purchaseNumber: number,
            supplierId: supplierId,
            subtotalCents: Decimal.fromInt(subtotal),
            discountCents: Value(Decimal.fromInt(discount)),
            taxCents: Decimal.zero,
            totalCents: Decimal.fromInt(subtotal - discount),
            currencyId: currencyId,
            status: Value(status),
            purchaseDate: Value(date),
          ),
        );
    for (final line in lines) {
      await db
          .into(db.purchaseItems)
          .insert(
            PurchaseItemsCompanion.insert(
              purchaseId: id,
              productId: productId,
              variantId: const Value(null),
              quantity: line.quantity,
              unitCostCents: Decimal.fromInt(line.gross ~/ line.quantity),
              inventoryValueAtPostCents: Value(Decimal.fromInt(line.value)),
              discountCents: Value(Decimal.fromInt(line.discount)),
              subtotalCents: Decimal.fromInt(line.gross),
              taxCents: Value(Decimal.zero),
              totalCents: Decimal.fromInt(line.gross - line.discount),
            ),
          );
    }
    return id;
  }

  setUp(() async {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    await db.customSelect('SELECT 1').get();
    currencyId = (await (db.select(
      db.currencies,
    )..where((row) => row.code.equals('USD'))).getSingle()).id;
    supplierId = await db
        .into(db.suppliers)
        .insert(
          SuppliersCompanion.insert(
            name: 'Invoice import supplier',
            currencyId: currencyId,
          ),
        );
    productId = await db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            name: 'Imported item',
            sku: const Value('IMP-1'),
            currencyId: Value(currencyId),
            costCents: Decimal.fromInt(800),
            priceCents: Decimal.fromInt(1500),
          ),
        );
    variantId = await db
        .into(db.productVariants)
        .insert(
          ProductVariantsCompanion.insert(
            productId: productId,
            costCents: Decimal.fromInt(800),
            priceCents: Decimal.fromInt(1500),
          ),
        );
  });

  tearDown(() => db.close());

  test(
    'single invoice aggregates duplicate lines at exact posted inventory value',
    () async {
      final invoiceId = await purchase(
        number: 'PI-OLD',
        date: DateTime.utc(2026, 8, 1),
        status: 'posted',
        lines: [
          (quantity: 1, gross: 1000, discount: 100, value: 900),
          (quantity: 2, gross: 2000, discount: 200, value: 1800),
        ],
      );
      final service = ConsignmentAgreementImportService(db);
      final result = await service.buildTerms(
        supplierId: supplierId,
        currencyId: currencyId,
        purchaseId: invoiceId,
      );

      expect(result.skippedLines, 0);
      expect(result.variedCostItems, 0);
      expect(result.items, hasLength(1));
      expect(result.items.single.productId, productId);
      expect(result.items.single.variantId, variantId);
      expect(result.items.single.unitCostCents, 900);
      expect(result.items.single.sourcePurchaseId, invoiceId);
    },
  );

  test(
    'all invoices use latest posted cost and flag variation without writes',
    () async {
      final oldId = await purchase(
        number: 'PI-OLD',
        date: DateTime.utc(2026, 8, 1),
        status: 'posted',
        lines: [(quantity: 2, gross: 2000, discount: 200, value: 1800)],
      );
      final latestId = await purchase(
        number: 'PI-LATEST',
        date: DateTime.utc(2026, 9, 1),
        status: 'posted',
        lines: [
          (quantity: 1, gross: 1200, discount: 100, value: 1100),
          (quantity: 2, gross: 2400, discount: 200, value: 2200),
        ],
      );
      await purchase(
        number: 'PI-DRAFT',
        date: DateTime.utc(2026, 9, 2),
        status: 'draft',
        lines: [(quantity: 1, gross: 5000, discount: 0, value: 5000)],
      );
      final beforePurchases = await db.select(db.purchases).get();
      final beforeItems = await db.select(db.purchaseItems).get();
      final service = ConsignmentAgreementImportService(db);

      final listed = await service.listPostedPurchases(
        supplierId: supplierId,
        currencyId: currencyId,
      );
      expect(listed.map((row) => row.id), [latestId, oldId]);

      final result = await service.buildTerms(
        supplierId: supplierId,
        currencyId: currencyId,
      );
      expect(result.items, hasLength(1));
      expect(result.items.single.unitCostCents, 1100);
      expect(result.items.single.sourcePurchaseId, latestId);
      expect(result.items.single.costVariedAcrossPurchases, isTrue);
      expect(result.variedCostItems, 1);
      expect(await db.select(db.purchases).get(), beforePurchases);
      expect(await db.select(db.purchaseItems).get(), beforeItems);
      expect(await db.select(db.consignmentAgreements).get(), isEmpty);
    },
  );

  test('imported items follow the agreement-wide settlement method', () {
    final imported = ConsignmentPurchaseImportItem(
      productId: 10,
      variantId: 20,
      unitCostCents: 875,
      sourcePurchaseId: 30,
      sourcePurchaseNumber: 'PI-30',
      sourcePurchaseDate: DateTime.utc(2026, 9, 1),
      costVariedAcrossPurchases: false,
    );

    final fixed = ConsignmentAgreementImportService.toAgreementTerm(
      imported,
      settlementBasis: 'fixed_unit_cost',
    );
    expect(fixed.settlementBasis, 'fixed_unit_cost');
    expect(fixed.unitCostCents, 875);
    expect(fixed.supplierShareBps, isNull);

    final percentage = ConsignmentAgreementImportService.toAgreementTerm(
      imported,
      settlementBasis: 'net_sales_percentage',
      supplierShareBps: 6750,
    );
    expect(percentage.settlementBasis, 'net_sales_percentage');
    expect(percentage.unitCostCents, isNull);
    expect(percentage.supplierShareBps, 6750);

    expect(
      () => ConsignmentAgreementImportService.toAgreementTerm(
        imported,
        settlementBasis: 'net_sales_percentage',
      ),
      throwsArgumentError,
    );
    expect(
      () => ConsignmentAgreementImportService.toAgreementTerm(
        imported,
        settlementBasis: 'net_sales_percentage',
        supplierShareBps: 10001,
      ),
      throwsArgumentError,
    );
  });
}
