import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tapix/core/database/app_database.dart' hide Size;
import 'package:tapix/core/di/injection_container.dart';
import 'package:tapix/core/promotions/promotion_repository.dart';
import 'package:tapix/core/promotions/promotion_sale_snapshot.dart';
import 'package:tapix/features/promotions/presentation/screens/promotion_usage_report_screen.dart';

class _MockPromotionRepository extends Mock implements PromotionRepository {}

class _EmptyAssetLoader extends AssetLoader {
  const _EmptyAssetLoader();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async => {};
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await initializeDateFormatting('ar');
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('filters do not overflow on a narrow RTL screen', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _MockPromotionRepository();
    when(
      repository.watchAll,
    ).thenAnswer((_) => Stream<List<Promotion>>.value(const []));
    when(
      () => repository.loadUsageReport(
        from: any(named: 'from'),
        toExclusive: any(named: 'toExclusive'),
        promotionId: any(named: 'promotionId'),
        status: any(named: 'status'),
      ),
    ).thenAnswer((_) async => const <PromotionUsageReportRow>[]);

    await sl.reset();
    sl.registerSingleton<PromotionRepository>(repository);
    addTearDown(sl.reset);

    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('ar')],
        path: 'unused',
        assetLoader: const _EmptyAssetLoader(),
        startLocale: const Locale('ar'),
        fallbackLocale: const Locale('ar'),
        child: const MaterialApp(home: PromotionUsageReportScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(DropdownButtonFormField<int?>), findsOneWidget);
  });
}
