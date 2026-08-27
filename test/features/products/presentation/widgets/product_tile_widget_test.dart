import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mocktail/mocktail.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:tapix/core/bloc/currency_bloc.dart';
import 'package:tapix/core/bloc/realtime_bloc.dart';
import 'package:tapix/core/services/currency_service.dart';
import 'package:tapix/features/products/domain/entities/product_entity.dart';
import 'package:tapix/features/products/presentation/widgets/product_tile_widget.dart';

class MockCurrencyService extends Mock implements CurrencyService {}

class MockCurrencyBloc extends Mock implements CurrencyBloc {}

class _TestAssetLoader extends AssetLoader {
  const _TestAssetLoader();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async {
    return <String, dynamic>{};
  }
}

void main() {
  group('ProductTileWidget', () {
    late Product testProduct;
    late MockCurrencyService currencyService;
    late MockCurrencyBloc currencyBloc;

    setUp(() {
      currencyService = MockCurrencyService();
      currencyBloc = MockCurrencyBloc();
      when(() => currencyService.currencySymbol).thenReturn('\$');
      when(() => currencyService.currencyCode).thenReturn('USD');
      when(
        () => currencyService.getCurrency(),
      ).thenReturn(Currency.fromCode('USD'));
      when(
        () => currencyService.currencyStream,
      ).thenAnswer((_) => Stream.value(Currency.fromCode('USD')));
      when(() => currencyService.format(any())).thenAnswer((invocation) {
        final cents = invocation.positionalArguments[0] as int;
        return '\$${(cents / 100).toStringAsFixed(2)}';
      });
      when(
        () => currencyBloc.state,
      ).thenReturn(RealtimeSuccess<Currency>(data: Currency.fromCode('USD')));
      when(() => currencyBloc.stream).thenAnswer(
        (_) => Stream.value(
          RealtimeSuccess<Currency>(data: Currency.fromCode('USD')),
        ),
      );
      when(() => currencyBloc.close()).thenAnswer((_) async {});

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
        purchaseTaxRateBps: 0,
        salesTaxRateBps: 0,
        isActive: true,
        trackInventory: true,
      );
    });

    Widget createWidget(Widget child) {
      return EasyLocalization(
        supportedLocales: const [Locale('en')],
        path: 'assets/translations',
        assetLoader: const _TestAssetLoader(),
        fallbackLocale: const Locale('en'),
        startLocale: const Locale('en'),
        child: Builder(
          builder: (context) => MaterialApp(
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            locale: context.locale,
            home: Scaffold(
              body: MultiBlocProvider(
                providers: [
                  RepositoryProvider<CurrencyService>.value(
                    value: currencyService,
                  ),
                  BlocProvider<CurrencyBloc>.value(value: currencyBloc),
                ],
                child: child,
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('displays product name and SKU', (tester) async {
      await tester.pumpWidget(
        createWidget(ProductTileWidget(product: testProduct)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Test Product'), findsOneWidget);
      expect(find.text('SKU: TEST-001'), findsOneWidget);
    });

    testWidgets('displays formatted price', (tester) async {
      await tester.pumpWidget(
        createWidget(ProductTileWidget(product: testProduct)),
      );
      await tester.pumpAndSettle();

      expect(find.text('\$15.00'), findsOneWidget);
    });

    testWidgets('displays normal stock indicator when stock is adequate', (
      tester,
    ) async {
      await tester.pumpWidget(
        createWidget(ProductTileWidget(product: testProduct)),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('normal_stock_indicator')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('normal_stock_indicator')),
          matching: find.textContaining('50'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('displays low stock indicator when stock is low', (
      tester,
    ) async {
      final lowStockProduct = testProduct.copyWith(stockQuantity: 5);

      await tester.pumpWidget(
        createWidget(ProductTileWidget(product: lowStockProduct)),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('low_stock_indicator')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('low_stock_indicator')),
          matching: find.textContaining('5'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('displays out of stock indicator when stock is zero', (
      tester,
    ) async {
      final outOfStockProduct = testProduct.copyWith(stockQuantity: 0);

      await tester.pumpWidget(
        createWidget(ProductTileWidget(product: outOfStockProduct)),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('out_of_stock_indicator')), findsOneWidget);
      expect(find.text('0'), findsOneWidget);
    });

    testWidgets('displays a product image received from the master', (
      tester,
    ) async {
      final bytes = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      );

      await tester.pumpWidget(
        createWidget(
          ProductTileWidget(
            product: testProduct,
            remoteImage: Future.value(bytes),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('calls onTap when tapped', (tester) async {
      Product? tappedProduct;

      await tester.pumpWidget(
        createWidget(
          ProductTileWidget(
            product: testProduct,
            onTap: (product) {
              tappedProduct = product;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(InkWell));
      await tester.pumpAndSettle();

      expect(tappedProduct, equals(testProduct));
    });

    testWidgets('calls onLongPress when long pressed', (tester) async {
      Product? longPressedProduct;

      await tester.pumpWidget(
        createWidget(
          ProductTileWidget(
            product: testProduct,
            onLongPress: (product) {
              longPressedProduct = product;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.longPress(find.byType(InkWell));
      await tester.pumpAndSettle();

      expect(longPressedProduct, equals(testProduct));
    });

    testWidgets('handles empty SKU gracefully', (tester) async {
      final noSkuProduct = testProduct.copyWith(sku: '');

      await tester.pumpWidget(
        createWidget(ProductTileWidget(product: noSkuProduct)),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('SKU:'), findsNothing);
    });
  });
}
