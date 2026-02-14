import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/bloc/realtime_bloc.dart';
import 'package:tapix/core/database/app_database.dart' hide Product;
import 'package:tapix/features/products/domain/entities/product_entity.dart';
import 'package:tapix/features/products/data/repositories/product_repository_impl.dart';
import 'package:tapix/features/products/data/datasources/product_local_datasource.dart';
import 'package:tapix/features/products/presentation/bloc/products_bloc.dart';
import 'package:tapix/core/services/audit_log_service.dart';
import 'package:tapix/features/auth/data/services/session_service.dart';

void main() {
  testWidgets('UI updates when database changes via ProductsBloc stream', (tester) async {
    final database = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));

    ProductsBloc? bloc;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      await bloc?.close().timeout(const Duration(seconds: 2));
      await database.close().timeout(const Duration(seconds: 2));
    });

    Future<void> pumpUntilFound(
      Finder finder, {
      Duration timeout = const Duration(seconds: 2),
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

    final currencyId = await database.into(database.currencies).insert(
      CurrenciesCompanion.insert(
        code: 'TST',
        name: 'Test Currency',
        symbol: 'T',
        exchangeRate: Decimal.fromInt(1),
      ),
    );

    final repository = ProductRepositoryImpl(ProductLocalDatasourceImpl(database.productDao), AuditLogService(database), SessionService());
    bloc = ProductsBloc(repository);

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(
          value: bloc,
          child: BlocBuilder<ProductsBloc, RealtimeState<List<Product>>>(
            builder: (context, state) {
              final count = switch (state) {
                RealtimeSuccess<List<Product>> s => s.data.length,
                RealtimeLoading<List<Product>> s => s.previousData?.length ?? 0,
                RealtimeError<List<Product>> s => s.previousData?.length ?? 0,
                RealtimeOptimistic<List<Product>> s => s.optimisticData.length,
                RealtimeInitial<List<Product>>() => 0,
                _ => 0,
              };
              return Text('$count', textDirection: TextDirection.ltr);
            },
          ),
        ),
      ),
    );

    await pumpUntilFound(find.text('0'));
    expect(find.text('0'), findsOneWidget);

    await database.into(database.products).insert(
      ProductsCompanion.insert(
        sku: const Value<String?>('WGT-001'),
        name: 'Widget Product',
        costCents: Decimal.fromInt(1000),
        priceCents: Decimal.fromInt(2000),
        currencyId: Value(currencyId),
      ),
    );

    await pumpUntilFound(find.text('1'));
    expect(find.text('1'), findsOneWidget);
  });
}
