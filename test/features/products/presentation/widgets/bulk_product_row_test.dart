import 'dart:ui' as ui;
import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tapix/core/bloc/currency_bloc.dart';
import 'package:tapix/core/services/currency_service.dart';
import 'package:tapix/features/products/domain/entities/product_color_entity.dart';
import 'package:tapix/features/products/domain/entities/size_entity.dart'
    as size_entity;
import 'package:tapix/features/products/domain/repositories/product_variant_repository.dart';
import 'package:tapix/features/products/domain/repositories/product_color_repository.dart';
import 'package:tapix/features/products/domain/repositories/size_repository.dart';
import 'package:tapix/features/products/domain/entities/category_entity.dart';
import 'package:tapix/features/products/domain/repositories/category_repository.dart';
import 'package:tapix/features/products/presentation/bloc/bulk_product_bloc.dart';
import 'package:tapix/features/products/presentation/bloc/categories_bloc.dart';
import 'package:tapix/features/products/presentation/bloc/colors_bloc.dart';
import 'package:tapix/features/products/presentation/bloc/sizes_bloc.dart';
import 'package:tapix/features/products/presentation/widgets/bulk_product_row.dart';

import 'bulk_product_row_test.mocks.dart';

class _TestAssetLoader extends AssetLoader {
  final Map<String, Map<String, dynamic>> _translationsByLocale;

  const _TestAssetLoader(this._translationsByLocale);

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async {
    return _translationsByLocale[locale.languageCode] ??
        const <String, dynamic>{};
  }
}

class _FakeSizeRepository implements SizeRepository {
  @override
  Stream<List<size_entity.Size>> watchAllSizes() =>
      Stream.value(const <size_entity.Size>[]);

  @override
  Stream<List<size_entity.Size>> watchSizesBySearch(String query) =>
      Stream.value(const <size_entity.Size>[]);

  @override
  Future<List<size_entity.Size>> getAllSizes() async =>
      const <size_entity.Size>[];

  @override
  Future<size_entity.Size?> getSizeById(int id) async => null;

  @override
  Future<int> createSize(size_entity.Size size) async => 0;

  @override
  Future<bool> updateSize(size_entity.Size size) async => true;

  @override
  Future<int> deleteSize(int id) async => 0;

  @override
  Future<bool> hasProducts(int sizeId) async => false;

  @override
  Future<int> getProductCountBySize(int sizeId) async => 0;
}

class _FakeCategoryRepository implements CategoryRepository {
  @override
  Stream<List<Category>> watchAllCategories() =>
      Stream.value(const <Category>[]);

  @override
  Stream<List<Category>> watchCategoriesBySearch(String query) =>
      Stream.value(const <Category>[]);

  @override
  Future<List<Category>> getAllCategories() async => const <Category>[];

  @override
  Future<Category?> getCategoryById(int id) async => null;

  @override
  Future<int> createCategory(Category category) async => 0;

  @override
  Future<bool> updateCategory(Category category) async => true;

  @override
  Future<int> deleteCategory(int id) async => 0;

  @override
  Future<bool> hasProducts(int categoryId) async => false;

  @override
  Future<int> getProductCountByCategory(int categoryId) async => 0;

  @override
  Future<bool> hasCircularReference(int categoryId, int? parentId) async =>
      false;

  @override
  Future<List<Category>> getSubcategories(int parentId) async =>
      const <Category>[];

  @override
  Stream<List<Category>> watchSubcategories(int parentId) =>
      Stream.value(const <Category>[]);
}

@GenerateMocks([
  CurrencyService,
  ProductVariantRepository,
  ProductColorRepository,
])
void main() {
  late MockCurrencyService mockCurrencyService;
  late MockProductColorRepository mockColorRepository;
  late SizeRepository sizeRepository;
  late CategoryRepository categoryRepository;
  late _TestAssetLoader assetLoader;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});

    Map<String, dynamic> readJson(String filePath) {
      final raw = File(filePath).readAsStringSync();
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      return <String, dynamic>{};
    }

    assetLoader = _TestAssetLoader({
      'en': readJson('assets/translations/en.json'),
      'ar': readJson('assets/translations/ar.json'),
      'fr': readJson('assets/translations/fr.json'),
    });

    await EasyLocalization.ensureInitialized();
  });

  setUp(() {
    mockCurrencyService = MockCurrencyService();
    mockColorRepository = MockProductColorRepository();
    sizeRepository = _FakeSizeRepository();
    categoryRepository = _FakeCategoryRepository();

    // Stub CurrencyService
    when(mockCurrencyService.currencyCode).thenReturn('USD');
    when(mockCurrencyService.currencySymbol).thenReturn('\$');
    when(
      mockCurrencyService.getCurrency(),
    ).thenReturn(Currency.fromCode('USD'));
    when(
      mockCurrencyService.currencyStream,
    ).thenAnswer((_) => Stream.value(Currency.fromCode('USD')));

    // Stub ProductColorRepository for ColorsBloc
    when(
      mockColorRepository.watchAllColors(),
    ).thenAnswer((_) => Stream.value(<ProductColor>[]));

    // _FakeSizeRepository already returns empty sizes stream.
  });

  group('BulkProductRow', () {
    Future<void> pumpUntilFound(
      WidgetTester tester,
      Finder finder, {
      Duration timeout = const Duration(seconds: 5),
      Duration step = const Duration(milliseconds: 20),
    }) async {
      final sw = Stopwatch()..start();
      while (sw.elapsed < timeout) {
        await tester.pump(step);
        if (finder.evaluate().isNotEmpty) {
          return;
        }
      }
      fail('Timed out waiting for: $finder');
    }

    Widget createWidget({
      required BulkProductRowData rowData,
      List<String>? errors,
      bool isDesktop = true,
      bool isTablet = false,
      bool canRemove = true,
      void Function(Map<String, dynamic>)? onUpdate,
      VoidCallback? onRemove,
    }) {
      return EasyLocalization(
        key: UniqueKey(),
        supportedLocales: const [Locale('en'), Locale('ar'), Locale('fr')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en'),
        startLocale: const Locale('en'),
        saveLocale: false,
        assetLoader: assetLoader,
        child: Builder(
          builder: (context) {
            return MaterialApp(
              localizationsDelegates: context.localizationDelegates,
              supportedLocales: context.supportedLocales,
              locale: context.locale,
              home: MultiBlocProvider(
                providers: [
                  BlocProvider<CurrencyBloc>(
                    create: (_) => CurrencyBloc(mockCurrencyService),
                  ),
                  BlocProvider<ColorsBloc>(
                    create: (_) => ColorsBloc(mockColorRepository),
                  ),
                  BlocProvider<SizesBloc>(
                    create: (_) => SizesBloc(sizeRepository),
                  ),
                  BlocProvider<CategoriesBloc>(
                    create: (_) => CategoriesBloc(categoryRepository),
                  ),
                ],
                child: Scaffold(
                  body: SingleChildScrollView(
                    child: BulkProductRow(
                      rowData: rowData,
                      errors: errors,
                      isDesktop: isDesktop,
                      isTablet: isTablet,
                      canRemove: canRemove,
                      onUpdate: onUpdate ?? (_) {},
                      onRemove: onRemove ?? () {},
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );
    }

    testWidgets('creates widget without errors', (tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      // Set a large screen size to avoid overflow
      tester.view.physicalSize = const ui.Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final rowData = BulkProductRowData.empty(0);

      await tester.pumpWidget(createWidget(rowData: rowData));
      await pumpUntilFound(tester, find.byType(BulkProductRow));

      expect(find.byType(BulkProductRow), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('shows error indicator when errors present', (tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      // Set a large screen size to avoid overflow
      tester.view.physicalSize = const ui.Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final rowData = BulkProductRowData.empty(0);

      await tester.pumpWidget(
        createWidget(
          rowData: rowData,
          errors: ['name_required', 'price_required'],
        ),
      );
      await pumpUntilFound(tester, find.byType(BulkProductRow));

      // The widget should render with errors - just verify it renders
      expect(find.byType(BulkProductRow), findsOneWidget);
      // Error icon should be present in the header
      expect(find.byIcon(Icons.error_outline), findsWidgets);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('calls onRemove when delete button tapped', (tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      // Set a large screen size to avoid overflow
      tester.view.physicalSize = const ui.Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final rowData = BulkProductRowData.empty(0);
      bool removeCalled = false;

      await tester.pumpWidget(
        createWidget(rowData: rowData, onRemove: () => removeCalled = true),
      );

      await pumpUntilFound(tester, find.byType(BulkProductRow));
      await pumpUntilFound(tester, find.byIcon(Icons.delete_outline));

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pump();

      expect(removeCalled, isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });
}
