import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tapix/core/services/currency_service.dart';
import 'package:tapix/features/products/domain/entities/product_entity.dart';
import 'package:tapix/features/products/presentation/widgets/product_tile_widget.dart';

class MockCurrencyService extends Mock implements CurrencyService {}

void main() {
  group('ProductTileWidget', () {
    late Product testProduct;
    late MockCurrencyService currencyService;

    setUp(() {
      currencyService = MockCurrencyService();
      when(() => currencyService.currencySymbol).thenReturn('\$');
      when(() => currencyService.format(any())).thenAnswer((invocation) {
        final cents = invocation.positionalArguments[0] as int;
        return '\$${(cents / 100).toStringAsFixed(2)}';
      });
      
      testProduct = Product(
        id: 1,
        name: 'Test Product',
        nameAr: null,
        nameFr: null,
        description: 'Test Description',
        sku: 'TEST-001',
        barcode: null,
        costCents: Decimal.fromInt(1000),
        priceCents: Decimal.fromInt(1500),
        wholesalePriceCents: null,
        stockQuantity: 50,
        minQuantity: 10,
        categoryId: null,
        supplierId: null,
        currencyId: 1,
        imagePath: null,
        hasVariants: false,
        isTaxable: false,
        taxRateBps: 0,
        isActive: true,
        trackInventory: true,
      );
    });

    Widget createWidget(Widget child) {
      return MaterialApp(
        home: Scaffold(
          body: RepositoryProvider<CurrencyService>.value(
            value: currencyService,
            child: child,
          ),
        ),
      );
    }

    testWidgets('displays product name and SKU', (tester) async {
      await tester.pumpWidget(createWidget(
        ProductTileWidget(product: testProduct),
      ));

      expect(find.text('Test Product'), findsOneWidget);
      expect(find.text('SKU: TEST-001'), findsOneWidget);
    });

    testWidgets('displays formatted price', (tester) async {
      await tester.pumpWidget(createWidget(
        ProductTileWidget(product: testProduct),
      ));

      expect(find.text('\$15.00'), findsOneWidget);
    });

    testWidgets('displays normal stock indicator when stock is adequate', (tester) async {
      await tester.pumpWidget(createWidget(
        ProductTileWidget(product: testProduct),
      ));

      expect(find.byKey(const Key('normal_stock_indicator')), findsOneWidget);
      expect(find.text('50'), findsOneWidget);
    });

    testWidgets('displays low stock indicator when stock is low', (tester) async {
      final lowStockProduct = testProduct.copyWith(stockQuantity: 5);

      await tester.pumpWidget(createWidget(
        ProductTileWidget(product: lowStockProduct),
      ));

      expect(find.byKey(const Key('low_stock_indicator')), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
    });

    testWidgets('displays out of stock indicator when stock is zero', (tester) async {
      final outOfStockProduct = testProduct.copyWith(stockQuantity: 0);

      await tester.pumpWidget(createWidget(
        ProductTileWidget(product: outOfStockProduct),
      ));

      expect(find.byKey(const Key('out_of_stock_indicator')), findsOneWidget);
      expect(find.text('0'), findsOneWidget);
    });

    testWidgets('calls onTap when tapped', (tester) async {
      Product? tappedProduct;

      await tester.pumpWidget(createWidget(
        ProductTileWidget(
          product: testProduct,
          onTap: (product) {
            tappedProduct = product;
          },
        ),
      ));

      await tester.tap(find.byType(InkWell));
      await tester.pumpAndSettle();

      expect(tappedProduct, equals(testProduct));
    });

    testWidgets('calls onLongPress when long pressed', (tester) async {
      Product? longPressedProduct;

      await tester.pumpWidget(createWidget(
        ProductTileWidget(
          product: testProduct,
          onLongPress: (product) {
            longPressedProduct = product;
          },
        ),
      ));

      await tester.longPress(find.byType(InkWell));
      await tester.pumpAndSettle();

      expect(longPressedProduct, equals(testProduct));
    });

    testWidgets('handles empty SKU gracefully', (tester) async {
      final noSkuProduct = testProduct.copyWith(sku: '');

      await tester.pumpWidget(createWidget(
        ProductTileWidget(product: noSkuProduct),
      ));

      expect(find.textContaining('SKU:'), findsNothing);
    });
  });
}
