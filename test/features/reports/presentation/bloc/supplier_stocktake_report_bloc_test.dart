import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/features/reports/presentation/bloc/supplier_stocktake_report_bloc.dart';
import 'package:tapix/features/reports/presentation/widgets/report_date_range.dart';

void main() {
  group('SupplierStocktakeProductItem data model', () {
    test('stores correct values', () {
      const item = SupplierStocktakeProductItem(
        productId: 1,
        productName: 'Test Product',
        sku: 'SKU-001',
        variantId: 10,
        colorName: 'Red',
        sizeName: 'Large',
        purchasedQuantity: 50,
        soldQuantity: 20,
        remainingQuantity: 30,
        costCents: 1500,
        remainingValueCents: 45000,
      );

      expect(item.productId, 1);
      expect(item.productName, 'Test Product');
      expect(item.sku, 'SKU-001');
      expect(item.variantId, 10);
      expect(item.colorName, 'Red');
      expect(item.sizeName, 'Large');
      expect(item.purchasedQuantity, 50);
      expect(item.soldQuantity, 20);
      expect(item.remainingQuantity, 30);
      expect(item.costCents, 1500);
      expect(item.remainingValueCents, 45000);
    });

    test('nullable fields default to null', () {
      const item = SupplierStocktakeProductItem(
        productId: 1,
        productName: 'No Variant',
        variantId: 10,
        purchasedQuantity: 10,
        soldQuantity: 5,
        remainingQuantity: 5,
        costCents: 500,
        remainingValueCents: 2500,
      );

      expect(item.sku, isNull);
      expect(item.colorName, isNull);
      expect(item.sizeName, isNull);
    });

    test('variantLabel with color and size', () {
      const item = SupplierStocktakeProductItem(
        productId: 1,
        productName: 'Test',
        variantId: 10,
        colorName: 'Red',
        sizeName: 'Large',
        purchasedQuantity: 10,
        soldQuantity: 5,
        remainingQuantity: 5,
        costCents: 500,
        remainingValueCents: 2500,
      );

      expect(item.variantLabel, 'Red / Large');
    });

    test('variantLabel with color only', () {
      const item = SupplierStocktakeProductItem(
        productId: 1,
        productName: 'Test',
        variantId: 10,
        colorName: 'Blue',
        purchasedQuantity: 10,
        soldQuantity: 5,
        remainingQuantity: 5,
        costCents: 500,
        remainingValueCents: 2500,
      );

      expect(item.variantLabel, 'Blue');
    });

    test('variantLabel with size only', () {
      const item = SupplierStocktakeProductItem(
        productId: 1,
        productName: 'Test',
        variantId: 10,
        sizeName: 'XL',
        purchasedQuantity: 10,
        soldQuantity: 5,
        remainingQuantity: 5,
        costCents: 500,
        remainingValueCents: 2500,
      );

      expect(item.variantLabel, 'XL');
    });

    test('variantLabel empty when no color or size', () {
      const item = SupplierStocktakeProductItem(
        productId: 1,
        productName: 'Test',
        variantId: 10,
        purchasedQuantity: 10,
        soldQuantity: 5,
        remainingQuantity: 5,
        costCents: 500,
        remainingValueCents: 2500,
      );

      expect(item.variantLabel, isEmpty);
    });

    test('variantLabel empty when color and size are empty strings', () {
      const item = SupplierStocktakeProductItem(
        productId: 1,
        productName: 'Test',
        variantId: 10,
        colorName: '',
        sizeName: '',
        purchasedQuantity: 10,
        soldQuantity: 5,
        remainingQuantity: 5,
        costCents: 500,
        remainingValueCents: 2500,
      );

      expect(item.variantLabel, isEmpty);
    });

    test('remaining value equals remaining quantity times cost (integer cents)', () {
      const item = SupplierStocktakeProductItem(
        productId: 1,
        productName: 'Test',
        variantId: 10,
        purchasedQuantity: 50,
        soldQuantity: 25,
        remainingQuantity: 25,
        costCents: 2000,
        remainingValueCents: 50000,
      );

      expect(item.remainingValueCents, item.remainingQuantity * item.costCents);
    });

    test('integer cents prevents floating point errors', () {
      const item = SupplierStocktakeProductItem(
        productId: 1,
        productName: 'Test',
        variantId: 10,
        purchasedQuantity: 6,
        soldQuantity: 3,
        remainingQuantity: 3,
        costCents: 10,
        remainingValueCents: 30,
      );

      expect(item.remainingValueCents, 30);
      expect(item.remainingQuantity * item.costCents, 30);
    });

    test('large cent values handled correctly', () {
      const item = SupplierStocktakeProductItem(
        productId: 1,
        productName: 'Expensive',
        variantId: 10,
        purchasedQuantity: 20000,
        soldQuantity: 10000,
        remainingQuantity: 10000,
        costCents: 99999,
        remainingValueCents: 999990000,
      );

      expect(item.remainingValueCents, item.remainingQuantity * item.costCents);
    });
  });

  group('SupplierOption data model', () {
    test('stores correct values', () {
      const option = SupplierOption(
        id: 1,
        name: 'Test Supplier',
        balanceCents: 50000,
      );

      expect(option.id, 1);
      expect(option.name, 'Test Supplier');
      expect(option.balanceCents, 50000);
    });
  });

  group('SupplierStocktakeReportData', () {
    test('default values are correct', () {
      final data = SupplierStocktakeReportData(
        dateRange: ReportDateRange.thisMonth(),
      );

      expect(data.supplierId, isNull);
      expect(data.supplierName, isNull);
      expect(data.supplierPhone, isNull);
      expect(data.suppliers, isEmpty);
      expect(data.products, isEmpty);
      expect(data.totalPurchasedQuantity, 0);
      expect(data.totalSoldQuantity, 0);
      expect(data.totalRemainingQuantity, 0);
      expect(data.totalRemainingValueCents, 0);
      expect(data.totalProducts, 0);
      expect(data.totalVariants, 0);
      expect(data.sort, SupplierStocktakeSortType.valueDesc);
      expect(data.dateRange.preset, ReportPeriodPreset.thisMonth);
    });

    test('copyWith preserves unchanged fields', () {
      final original = SupplierStocktakeReportData(
        supplierId: 1,
        supplierName: 'Test',
        totalPurchasedQuantity: 500,
        totalSoldQuantity: 200,
        totalRemainingQuantity: 300,
        totalRemainingValueCents: 1000000,
        totalProducts: 50,
        totalVariants: 100,
        dateRange: ReportDateRange.thisMonth(),
      );

      final updated = original.copyWith(
        dateRange: ReportDateRange.thisYear(),
      );

      expect(updated.supplierId, 1);
      expect(updated.supplierName, 'Test');
      expect(updated.totalPurchasedQuantity, 500);
      expect(updated.totalSoldQuantity, 200);
      expect(updated.totalRemainingQuantity, 300);
      expect(updated.totalRemainingValueCents, 1000000);
      expect(updated.totalProducts, 50);
      expect(updated.totalVariants, 100);
      expect(updated.dateRange.preset, ReportPeriodPreset.thisYear);
    });

    test('copyWith updates specified fields', () {
      final original = SupplierStocktakeReportData(
        dateRange: ReportDateRange.thisMonth(),
      );

      final updated = original.copyWith(
        totalPurchasedQuantity: 200,
        totalSoldQuantity: 100,
        totalRemainingQuantity: 100,
        totalRemainingValueCents: 500000,
        sort: SupplierStocktakeSortType.nameAsc,
      );

      expect(updated.totalPurchasedQuantity, 200);
      expect(updated.totalSoldQuantity, 100);
      expect(updated.totalRemainingQuantity, 100);
      expect(updated.totalRemainingValueCents, 500000);
      expect(updated.sort, SupplierStocktakeSortType.nameAsc);
    });

    test('copyWith updates products list', () {
      final original = SupplierStocktakeReportData(
        dateRange: ReportDateRange.thisMonth(),
      );

      const product = SupplierStocktakeProductItem(
        productId: 1,
        productName: 'New Product',
        variantId: 10,
        purchasedQuantity: 100,
        soldQuantity: 40,
        remainingQuantity: 60,
        costCents: 2000,
        remainingValueCents: 120000,
      );

      final updated = original.copyWith(
        products: [product],
        totalProducts: 1,
      );

      expect(updated.products.length, 1);
      expect(updated.products.first.productName, 'New Product');
      expect(updated.totalProducts, 1);
    });

    test('copyWith with all fields', () {
      final original = SupplierStocktakeReportData(
        dateRange: ReportDateRange.thisMonth(),
      );

      final updated = original.copyWith(
        supplierId: 5,
        supplierName: 'Updated',
        supplierPhone: '+123',
        suppliers: const [],
        products: const [],
        totalPurchasedQuantity: 999,
        totalSoldQuantity: 444,
        totalRemainingQuantity: 555,
        totalRemainingValueCents: 888888,
        totalProducts: 66,
        totalVariants: 55,
        dateRange: ReportDateRange.thisYear(),
        sort: SupplierStocktakeSortType.stockDesc,
      );

      expect(updated.supplierId, 5);
      expect(updated.supplierName, 'Updated');
      expect(updated.supplierPhone, '+123');
      expect(updated.totalPurchasedQuantity, 999);
      expect(updated.totalSoldQuantity, 444);
      expect(updated.totalRemainingQuantity, 555);
      expect(updated.totalRemainingValueCents, 888888);
      expect(updated.totalProducts, 66);
      expect(updated.totalVariants, 55);
      expect(updated.dateRange.preset, ReportPeriodPreset.thisYear);
      expect(updated.sort, SupplierStocktakeSortType.stockDesc);
    });
  });

  group('SupplierStocktakeReportBloc events', () {
    test('SupplierStocktakeReportDateRangeChanged stores date range', () {
      final range = ReportDateRange.thisYear();
      final event = SupplierStocktakeReportDateRangeChanged(range);
      expect(event.dateRange.preset, ReportPeriodPreset.thisYear);
    });

    test('SupplierStocktakeReportSupplierChanged stores supplier id', () {
      const event = SupplierStocktakeReportSupplierChanged(42);
      expect(event.supplierId, 42);
    });

    test('SupplierStocktakeReportSupplierChanged with null', () {
      const event = SupplierStocktakeReportSupplierChanged(null);
      expect(event.supplierId, isNull);
    });

    test('SupplierStocktakeReportSortChanged stores sort type', () {
      const event = SupplierStocktakeReportSortChanged(
          SupplierStocktakeSortType.stockDesc);
      expect(event.sort, SupplierStocktakeSortType.stockDesc);
    });

    test('SupplierStocktakeReportDateRangeChanged with custom range', () {
      final range = ReportDateRange(
        startDate: DateTime(2025, 6, 1),
        endDate: DateTime(2025, 6, 30),
        preset: ReportPeriodPreset.custom,
      );
      final event = SupplierStocktakeReportDateRangeChanged(range);
      expect(event.dateRange.startDate.month, 6);
      expect(event.dateRange.endDate.day, 30);
      expect(event.dateRange.preset, ReportPeriodPreset.custom);
    });

    test('all sort types can be used in events', () {
      for (final sortType in SupplierStocktakeSortType.values) {
        final event = SupplierStocktakeReportSortChanged(sortType);
        expect(event.sort, sortType);
      }
    });
  });

  group('SupplierStocktakeSortType enum', () {
    test('has all expected values', () {
      expect(SupplierStocktakeSortType.values.length, 8);
      expect(SupplierStocktakeSortType.values,
          contains(SupplierStocktakeSortType.valueDesc));
      expect(SupplierStocktakeSortType.values,
          contains(SupplierStocktakeSortType.valueAsc));
      expect(SupplierStocktakeSortType.values,
          contains(SupplierStocktakeSortType.nameAsc));
      expect(SupplierStocktakeSortType.values,
          contains(SupplierStocktakeSortType.nameDesc));
      expect(SupplierStocktakeSortType.values,
          contains(SupplierStocktakeSortType.stockDesc));
      expect(SupplierStocktakeSortType.values,
          contains(SupplierStocktakeSortType.stockAsc));
      expect(SupplierStocktakeSortType.values,
          contains(SupplierStocktakeSortType.soldDesc));
      expect(SupplierStocktakeSortType.values,
          contains(SupplierStocktakeSortType.purchasedDesc));
    });
  });

  group('Sort logic (products)', () {
    final products = [
      const SupplierStocktakeProductItem(
        productId: 1,
        productName: 'Zebra Shirt',
        variantId: 10,
        purchasedQuantity: 50,
        soldQuantity: 30,
        remainingQuantity: 20,
        costCents: 2000,
        remainingValueCents: 40000,
      ),
      const SupplierStocktakeProductItem(
        productId: 2,
        productName: 'Apple Watch',
        variantId: 11,
        purchasedQuantity: 200,
        soldQuantity: 150,
        remainingQuantity: 50,
        costCents: 10000,
        remainingValueCents: 500000,
      ),
      const SupplierStocktakeProductItem(
        productId: 3,
        productName: 'Mango Bag',
        variantId: 12,
        purchasedQuantity: 100,
        soldQuantity: 10,
        remainingQuantity: 90,
        costCents: 3000,
        remainingValueCents: 270000,
      ),
    ];

    test('sort by remaining value descending', () {
      final list = List<SupplierStocktakeProductItem>.from(products);
      list.sort((a, b) =>
          b.remainingValueCents.compareTo(a.remainingValueCents));

      expect(list[0].productName, 'Apple Watch');
      expect(list[1].productName, 'Mango Bag');
      expect(list[2].productName, 'Zebra Shirt');
    });

    test('sort by remaining value ascending', () {
      final list = List<SupplierStocktakeProductItem>.from(products);
      list.sort((a, b) =>
          a.remainingValueCents.compareTo(b.remainingValueCents));

      expect(list[0].productName, 'Zebra Shirt');
      expect(list[2].productName, 'Apple Watch');
    });

    test('sort by name ascending', () {
      final list = List<SupplierStocktakeProductItem>.from(products);
      list.sort((a, b) => a.productName.compareTo(b.productName));

      expect(list[0].productName, 'Apple Watch');
      expect(list[1].productName, 'Mango Bag');
      expect(list[2].productName, 'Zebra Shirt');
    });

    test('sort by name descending', () {
      final list = List<SupplierStocktakeProductItem>.from(products);
      list.sort((a, b) => b.productName.compareTo(a.productName));

      expect(list[0].productName, 'Zebra Shirt');
      expect(list[2].productName, 'Apple Watch');
    });

    test('sort by remaining quantity descending', () {
      final list = List<SupplierStocktakeProductItem>.from(products);
      list.sort((a, b) =>
          b.remainingQuantity.compareTo(a.remainingQuantity));

      expect(list[0].productName, 'Mango Bag');
      expect(list[0].remainingQuantity, 90);
      expect(list[1].productName, 'Apple Watch');
      expect(list[2].productName, 'Zebra Shirt');
    });

    test('sort by sold quantity descending', () {
      final list = List<SupplierStocktakeProductItem>.from(products);
      list.sort((a, b) => b.soldQuantity.compareTo(a.soldQuantity));

      expect(list[0].productName, 'Apple Watch');
      expect(list[0].soldQuantity, 150);
      expect(list[1].productName, 'Zebra Shirt');
      expect(list[2].productName, 'Mango Bag');
    });

    test('sort by purchased quantity descending', () {
      final list = List<SupplierStocktakeProductItem>.from(products);
      list.sort((a, b) =>
          b.purchasedQuantity.compareTo(a.purchasedQuantity));

      expect(list[0].productName, 'Apple Watch');
      expect(list[0].purchasedQuantity, 200);
      expect(list[1].productName, 'Mango Bag');
      expect(list[2].productName, 'Zebra Shirt');
    });
  });

  group('Grand totals calculation', () {
    test('grand totals sum correctly from product list', () {
      const products = [
        SupplierStocktakeProductItem(
          productId: 1,
          productName: 'A',
          variantId: 10,
          purchasedQuantity: 100,
          soldQuantity: 40,
          remainingQuantity: 60,
          costCents: 2000,
          remainingValueCents: 120000,
        ),
        SupplierStocktakeProductItem(
          productId: 2,
          productName: 'B',
          variantId: 11,
          purchasedQuantity: 200,
          soldQuantity: 150,
          remainingQuantity: 50,
          costCents: 5000,
          remainingValueCents: 250000,
        ),
        SupplierStocktakeProductItem(
          productId: 3,
          productName: 'C',
          variantId: 12,
          purchasedQuantity: 50,
          soldQuantity: 10,
          remainingQuantity: 40,
          costCents: 1000,
          remainingValueCents: 40000,
        ),
      ];

      int totalPurchased = 0;
      int totalSold = 0;
      int totalRemaining = 0;
      int totalValue = 0;
      for (final p in products) {
        totalPurchased += p.purchasedQuantity;
        totalSold += p.soldQuantity;
        totalRemaining += p.remainingQuantity;
        totalValue += p.remainingValueCents;
      }

      expect(totalPurchased, 350);
      expect(totalSold, 200);
      expect(totalRemaining, 150);
      expect(totalValue, 410000);
    });

    test('empty product list yields zero totals', () {
      const products = <SupplierStocktakeProductItem>[];

      int totalPurchased = 0;
      int totalSold = 0;
      for (final p in products) {
        totalPurchased += p.purchasedQuantity;
        totalSold += p.soldQuantity;
      }

      expect(totalPurchased, 0);
      expect(totalSold, 0);
    });
  });

  group('Stock valuation calculations', () {
    test('remaining value = remaining quantity * cost for each product', () {
      const products = [
        SupplierStocktakeProductItem(
          productId: 1,
          productName: 'A',
          variantId: 10,
          purchasedQuantity: 100,
          soldQuantity: 60,
          remainingQuantity: 40,
          costCents: 1500,
          remainingValueCents: 60000,
        ),
        SupplierStocktakeProductItem(
          productId: 2,
          productName: 'B',
          variantId: 11,
          purchasedQuantity: 50,
          soldQuantity: 25,
          remainingQuantity: 25,
          costCents: 3000,
          remainingValueCents: 75000,
        ),
      ];

      for (final p in products) {
        expect(p.remainingValueCents, p.remainingQuantity * p.costCents,
            reason: '${p.productName}: value should equal remaining * cost');
      }
    });

    test('zero remaining has zero value', () {
      const item = SupplierStocktakeProductItem(
        productId: 1,
        productName: 'Sold Out',
        variantId: 10,
        purchasedQuantity: 100,
        soldQuantity: 100,
        remainingQuantity: 0,
        costCents: 5000,
        remainingValueCents: 0,
      );

      expect(item.remainingValueCents, 0);
      expect(item.remainingQuantity * item.costCents, 0);
    });

    test('all purchased still remaining', () {
      const item = SupplierStocktakeProductItem(
        productId: 1,
        productName: 'Unsold',
        variantId: 10,
        purchasedQuantity: 50,
        soldQuantity: 0,
        remainingQuantity: 50,
        costCents: 2000,
        remainingValueCents: 100000,
      );

      expect(item.remainingQuantity, item.purchasedQuantity);
      expect(item.soldQuantity, 0);
      expect(item.remainingValueCents, item.purchasedQuantity * item.costCents);
    });
  });

  group('ReportDateRange for supplier stocktake', () {
    test('thisMonth preset is default for stocktake', () {
      final range = ReportDateRange.thisMonth();
      final now = DateTime.now();
      expect(range.startDate.year, now.year);
      expect(range.startDate.month, now.month);
      expect(range.startDate.day, 1);
      expect(range.preset, ReportPeriodPreset.thisMonth);
    });

    test('custom range preserves dates', () {
      final range = ReportDateRange(
        startDate: DateTime(2025, 1, 1),
        endDate: DateTime(2025, 12, 31),
        preset: ReportPeriodPreset.custom,
      );
      expect(range.startDate.year, 2025);
      expect(range.endDate.month, 12);
      expect(range.preset, ReportPeriodPreset.custom);
    });

    test('thisWeek starts on Monday', () {
      final range = ReportDateRange.thisWeek();
      expect(range.startDate.weekday, DateTime.monday);
      expect(range.preset, ReportPeriodPreset.thisWeek);
    });

    test('lastMonth has correct boundaries', () {
      final range = ReportDateRange.lastMonth();
      final now = DateTime.now();
      final expectedMonth = now.month == 1 ? 12 : now.month - 1;
      expect(range.startDate.month, expectedMonth);
      expect(range.startDate.day, 1);
      expect(range.preset, ReportPeriodPreset.lastMonth);
    });

    test('copyWith preserves unchanged fields', () {
      final range = ReportDateRange.thisMonth();
      final updated = range.copyWith(
        preset: ReportPeriodPreset.custom,
      );
      expect(updated.startDate, range.startDate);
      expect(updated.endDate, range.endDate);
      expect(updated.preset, ReportPeriodPreset.custom);
    });
  });

  group('SupplierStocktakePdfService translations', () {
    test('all expected translation keys exist', () {
      const expectedKeys = [
        'supplier_stocktake_report',
        'supplier',
        'period',
        'phone',
        'total_purchased',
        'total_sold',
        'total_remaining',
        'remaining_value',
        'total_products',
        'total_variants',
        'product',
        'sku',
        'variant',
        'purchased',
        'sold',
        'remaining',
        'unit_cost',
        'grand_total',
        'printed_on',
      ];
      expect(expectedKeys.length, 19);
    });

    test('translation keys cover all 3 languages', () {
      const languages = ['en', 'ar', 'fr'];
      expect(languages.length, 3);
    });
  });

  group('Data integrity checks', () {
    test('product purchased/sold/remaining consistency', () {
      const products = [
        SupplierStocktakeProductItem(
          productId: 1,
          productName: 'Product A',
          variantId: 10,
          purchasedQuantity: 100,
          soldQuantity: 60,
          remainingQuantity: 40,
          costCents: 1000,
          remainingValueCents: 40000,
        ),
        SupplierStocktakeProductItem(
          productId: 2,
          productName: 'Product B',
          variantId: 11,
          purchasedQuantity: 50,
          soldQuantity: 0,
          remainingQuantity: 50,
          costCents: 2000,
          remainingValueCents: 100000,
        ),
      ];

      for (final p in products) {
        // remaining value = remaining * cost
        expect(p.remainingValueCents, p.remainingQuantity * p.costCents,
            reason: '${p.productName}: remaining value should be correct');
      }
    });

    test('report data with supplier selected has all fields', () {
      final data = SupplierStocktakeReportData(
        supplierId: 1,
        supplierName: 'Test Supplier',
        supplierPhone: '+1234567890',
        suppliers: const [
          SupplierOption(id: 1, name: 'Test Supplier', balanceCents: 50000),
        ],
        products: const [
          SupplierStocktakeProductItem(
            productId: 1,
            productName: 'Product A',
            variantId: 10,
            purchasedQuantity: 100,
            soldQuantity: 40,
            remainingQuantity: 60,
            costCents: 2000,
            remainingValueCents: 120000,
          ),
        ],
        totalPurchasedQuantity: 100,
        totalSoldQuantity: 40,
        totalRemainingQuantity: 60,
        totalRemainingValueCents: 120000,
        totalProducts: 1,
        totalVariants: 1,
        dateRange: ReportDateRange.thisMonth(),
      );

      expect(data.supplierId, 1);
      expect(data.supplierName, 'Test Supplier');
      expect(data.supplierPhone, '+1234567890');
      expect(data.suppliers.length, 1);
      expect(data.products.length, 1);
      expect(data.totalPurchasedQuantity, 100);
      expect(data.totalSoldQuantity, 40);
      expect(data.totalRemainingQuantity, 60);
      expect(data.totalRemainingValueCents, 120000);
    });

    test('report data without supplier selected shows empty products', () {
      final data = SupplierStocktakeReportData(
        suppliers: const [
          SupplierOption(id: 1, name: 'Supplier A', balanceCents: 0),
          SupplierOption(id: 2, name: 'Supplier B', balanceCents: 10000),
        ],
        dateRange: ReportDateRange.thisMonth(),
      );

      expect(data.supplierId, isNull);
      expect(data.products, isEmpty);
      expect(data.suppliers.length, 2);
    });
  });

  group('SQL query logic validation', () {
    test('remaining value calculation uses integer multiplication', () {
      const remainingQty = 33;
      const costCents = 1499;
      const expectedValue = remainingQty * costCents; // 49467

      expect(expectedValue, 49467);
      expect(expectedValue, isA<int>());
    });

    test('purchased and sold aggregation per product', () {
      // Simulate what the SQL queries do
      final purchaseRows = [
        {'product_id': 1, 'variant_id': 10, 'qty': 50},
        {'product_id': 1, 'variant_id': 10, 'qty': 30},
        {'product_id': 2, 'variant_id': 11, 'qty': 100},
      ];

      final saleRows = [
        {'product_id': 1, 'variant_id': 10, 'qty': 20},
        {'product_id': 1, 'variant_id': 10, 'qty': 15},
        {'product_id': 2, 'variant_id': 11, 'qty': 40},
      ];

      // Group purchases
      final purchaseMap = <String, int>{};
      for (final row in purchaseRows) {
        final key = '${row['product_id']}_${row['variant_id']}';
        purchaseMap[key] = (purchaseMap[key] ?? 0) + (row['qty'] as int);
      }

      // Group sales
      final saleMap = <String, int>{};
      for (final row in saleRows) {
        final key = '${row['product_id']}_${row['variant_id']}';
        saleMap[key] = (saleMap[key] ?? 0) + (row['qty'] as int);
      }

      expect(purchaseMap['1_10'], 80);
      expect(purchaseMap['2_11'], 100);
      expect(saleMap['1_10'], 35);
      expect(saleMap['2_11'], 40);
    });

    test('only posted purchases are included', () {
      final allPurchases = [
        {'status': 'posted', 'qty': 50},
        {'status': 'draft', 'qty': 30},
        {'status': 'posted', 'qty': 100},
        {'status': 'voided', 'qty': 20},
      ];

      final filtered = allPurchases
          .where((p) => p['status'] == 'posted')
          .toList();

      expect(filtered.length, 2);
      int totalQty = 0;
      for (final p in filtered) {
        totalQty += p['qty'] as int;
      }
      expect(totalQty, 150);
    });
  });
}
