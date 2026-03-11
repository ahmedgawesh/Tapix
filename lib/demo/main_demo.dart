import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/bloc/localization_bloc.dart';
import '../core/bloc/realtime_bloc.dart';
import '../core/bloc/theme_bloc.dart';
import '../core/bloc/currency_bloc.dart';
import '../core/database/app_database.dart';
import '../core/di/injection_container.dart' as di;
import '../core/router/app_router.dart';
import '../core/services/localization_service.dart';
import '../core/theme/app_theme.dart';
import '../features/auth/auth.dart';
import '../core/services/currency_service.dart';
import '../core/bloc/simple_bloc_observer.dart';
import '../features/settings/presentation/bloc/company_bloc.dart';
import '../features/settings/presentation/bloc/app_settings_bloc.dart';
import '../features/subscription/subscription.dart';
import 'demo_auth_bloc.dart';
import 'demo_config.dart';
import 'demo_overlay.dart';

/// Verify the app is running on an allowed domain.
/// Returns true if the domain is allowed.
bool _verifyDomain() {
  if (!kIsWeb) return true; // Only enforce on web

  // Use Uri.base which works on web to get the current URL
  final host = Uri.base.host;

  for (final domain in DemoConfig.allowedDomains) {
    if (host == domain || host.endsWith('.$domain')) {
      return true;
    }
  }
  return false;
}

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await EasyLocalization.ensureInitialized();

    // Domain lock check
    if (!_verifyDomain()) {
      runApp(const _UnauthorizedApp());
      return;
    }

    Bloc.observer = SimpleBlocObserver();

    // Initialize DI (database, repos, blocs, etc.)
    await di.init();

    // Replace the AuthBloc singleton with our DemoAuthBloc
    // First unregister the production one, then register demo version
    if (di.sl.isRegistered<AuthBloc>()) {
      await di.sl.unregister<AuthBloc>();
    }
    di.sl.registerLazySingleton<AuthBloc>(
      () => DemoAuthBloc(repository: di.sl<AuthRepositoryInterface>())
        ..add(const AuthCheckRequested()),
    );

    // Seed demo data into the database
    await _seedDemoData();

    final localizationService = di.sl<LocalizationService>();
    final startLocale = localizationService.getLocale();

    runApp(
      EasyLocalization(
        supportedLocales: LocalizationService.supportedLocales,
        path: 'assets/translations',
        fallbackLocale: const Locale('en'),
        startLocale: startLocale,
        saveLocale: false,
        child: const _DemoTapixApp(),
      ),
    );
  }, (error, stackTrace) {
    debugPrint('Demo runZonedGuarded error: $error');
  });
}

/// Seeds the database with demo data so the app looks alive.
Future<void> _seedDemoData() async {
  try {
    final db = di.sl<AppDatabase>();

    // Check if demo user already exists
    final existingUsers = await db.select(db.users).get();
    if (existingUsers.isNotEmpty) return; // Already seeded

    final passwordService = di.sl<PasswordService>();
    final hash = passwordService.hashPassword('demo1234');

    // Create demo manager user
    final now = DateTime.now();
    await db.into(db.users).insert(UsersCompanion.insert(
      username: DemoConfig.demoUsername,
      passwordHash: hash,
      role: 'manager',
      isActive: const Value(1),
      createdAt: now,
      updatedAt: now,
    ));

    // Seed categories
    final catIds = <int>[];
    for (final cat in _demoCategories) {
      final id = await db.into(db.productCategories).insert(
        ProductCategoriesCompanion.insert(name: cat),
      );
      catIds.add(id);
    }

    // Seed products and variants
    for (var i = 0; i < _demoProducts.length; i++) {
      final p = _demoProducts[i];
      final cost = Decimal.fromInt(p['cost']! as int);
      final price = Decimal.fromInt(p['price']! as int);
      final stock = p['stock']! as int;

      final productId = await db.into(db.products).insert(
        ProductsCompanion.insert(
          name: p['name'] as String,
          costCents: cost,
          priceCents: price,
          categoryId: Value(catIds[i % catIds.length]),
          description: Value(p['description'] as String? ?? ''),
          stockQuantity: Value(stock),
        ),
      );

      await db.into(db.productVariants).insert(
        ProductVariantsCompanion.insert(
          productId: productId,
          sku: Value('SKU-${1000 + i}'),
          barcode: Value(p['barcode'] as String),
          costCents: cost,
          priceCents: price,
          stockQuantity: Value(stock),
        ),
      );
    }

    // Seed customers
    for (final c in _demoCustomers) {
      await db.into(db.customers).insert(
        CustomersCompanion.insert(
          name: c['name'] as String,
          phone: Value(c['phone'] as String),
          email: Value(c['email'] ?? ''),
          currencyId: 1, // default currency
        ),
      );
    }

    // Seed suppliers
    for (final s in _demoSuppliers) {
      await db.into(db.suppliers).insert(
        SuppliersCompanion.insert(
          name: s['name'] as String,
          phone: Value(s['phone'] ?? ''),
          email: Value(s['email'] ?? ''),
          currencyId: 1, // default currency
        ),
      );
    }

    debugPrint('Demo data seeded successfully');
  } catch (e) {
    debugPrint('Demo data seed error (may already exist): $e');
  }
}

// Demo seed data
const _demoCategories = [
  'Electronics',
  'Clothing',
  'Food & Beverages',
  'Home & Garden',
  'Office Supplies',
];

const _demoProducts = [
  {'name': 'Wireless Mouse', 'barcode': '8901234567890', 'cost': 1500, 'price': 2999, 'stock': 45, 'description': 'Ergonomic wireless mouse'},
  {'name': 'USB-C Cable', 'barcode': '8901234567891', 'cost': 300, 'price': 799, 'stock': 120, 'description': '1m USB-C charging cable'},
  {'name': 'Bluetooth Speaker', 'barcode': '8901234567892', 'cost': 3000, 'price': 5999, 'stock': 25, 'description': 'Portable Bluetooth speaker'},
  {'name': 'Phone Case', 'barcode': '8901234567893', 'cost': 200, 'price': 599, 'stock': 200, 'description': 'Protective phone case'},
  {'name': 'Screen Protector', 'barcode': '8901234567894', 'cost': 100, 'price': 399, 'stock': 300, 'description': 'Tempered glass screen protector'},
  {'name': 'Cotton T-Shirt', 'barcode': '8901234567895', 'cost': 800, 'price': 1999, 'stock': 80, 'description': 'Premium cotton t-shirt'},
  {'name': 'Denim Jeans', 'barcode': '8901234567896', 'cost': 2500, 'price': 4999, 'stock': 40, 'description': 'Classic fit denim jeans'},
  {'name': 'Coffee Beans 1kg', 'barcode': '8901234567897', 'cost': 1200, 'price': 2499, 'stock': 60, 'description': 'Premium arabica coffee beans'},
  {'name': 'Green Tea Box', 'barcode': '8901234567898', 'cost': 400, 'price': 899, 'stock': 90, 'description': '50 tea bags'},
  {'name': 'Chocolate Bar', 'barcode': '8901234567899', 'cost': 150, 'price': 399, 'stock': 150, 'description': 'Dark chocolate 100g'},
  {'name': 'Desk Lamp', 'barcode': '8901234567900', 'cost': 2000, 'price': 3999, 'stock': 30, 'description': 'LED desk lamp'},
  {'name': 'Plant Pot', 'barcode': '8901234567901', 'cost': 500, 'price': 1299, 'stock': 50, 'description': 'Ceramic plant pot'},
  {'name': 'Notebook A5', 'barcode': '8901234567902', 'cost': 200, 'price': 599, 'stock': 100, 'description': 'Lined notebook A5'},
  {'name': 'Ballpoint Pens (10)', 'barcode': '8901234567903', 'cost': 150, 'price': 449, 'stock': 200, 'description': 'Pack of 10 ballpoint pens'},
  {'name': 'Sticky Notes', 'barcode': '8901234567904', 'cost': 100, 'price': 299, 'stock': 250, 'description': 'Pack of 400 sticky notes'},
  {'name': 'Wireless Keyboard', 'barcode': '8901234567905', 'cost': 2000, 'price': 3999, 'stock': 35, 'description': 'Compact wireless keyboard'},
  {'name': 'HDMI Cable', 'barcode': '8901234567906', 'cost': 400, 'price': 999, 'stock': 75, 'description': '2m HDMI 2.1 cable'},
  {'name': 'Water Bottle', 'barcode': '8901234567907', 'cost': 300, 'price': 799, 'stock': 110, 'description': 'Stainless steel 500ml'},
  {'name': 'Backpack', 'barcode': '8901234567908', 'cost': 3000, 'price': 5999, 'stock': 20, 'description': 'Laptop backpack 15.6"'},
  {'name': 'Sunglasses', 'barcode': '8901234567909', 'cost': 1000, 'price': 2499, 'stock': 55, 'description': 'UV400 polarized sunglasses'},
];

const _demoCustomers = [
  {'name': 'Ahmed Ali', 'phone': '+201001234567', 'email': 'ahmed@example.com'},
  {'name': 'Sara Mohamed', 'phone': '+201001234568', 'email': 'sara@example.com'},
  {'name': 'Mohamed Hassan', 'phone': '+201001234569', 'email': ''},
  {'name': 'Fatima Ibrahim', 'phone': '+201001234570', 'email': 'fatima@example.com'},
  {'name': 'Omar Khaled', 'phone': '+201001234571', 'email': ''},
];

const _demoSuppliers = [
  {'name': 'Tech Supplies Co.', 'phone': '+201001234580', 'email': 'tech@example.com'},
  {'name': 'Fashion Wholesale', 'phone': '+201001234581', 'email': 'fashion@example.com'},
  {'name': 'Food Distributors', 'phone': '+201001234582', 'email': 'food@example.com'},
];

/// Demo version of the main app widget. Shows the demo overlay on every screen.
class _DemoTapixApp extends StatelessWidget {
  const _DemoTapixApp();

  @override
  Widget build(BuildContext context) {
    final authBloc = di.sl<AuthBloc>()..add(const AuthCheckRequested());

    // Skip splash and welcome screens in demo
    AppRouter.markSplashCompleted();
    AppRouter.markWelcomeSeen();

    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider(create: (_) => di.sl<CurrencyService>()),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider(create: (_) => di.sl<ThemeBloc>()),
          BlocProvider(create: (_) => di.sl<LocalizationBloc>()),
          BlocProvider(create: (_) => di.sl<CurrencyBloc>()),
          BlocProvider(create: (_) => di.sl<CompanyBloc>()),
          BlocProvider.value(value: di.sl<AppSettingsBloc>()),
          BlocProvider.value(value: authBloc),
          BlocProvider.value(value: di.sl<SubscriptionBloc>()),
        ],
        child: BlocBuilder<ThemeBloc, RealtimeState<ThemeMode>>(
          builder: (context, themeState) {
            final themeMode =
                (themeState is RealtimeSuccess<ThemeMode>)
                    ? themeState.data
                    : ThemeMode.system;

            return MaterialApp.router(
              title: 'Tapix Demo',
              debugShowCheckedModeBanner: false,
              localizationsDelegates: context.localizationDelegates,
              supportedLocales: context.supportedLocales,
              locale: context.locale,
              theme: AppTheme.lightTheme,
              darkTheme: AppTheme.darkTheme,
              themeMode: themeMode,
              routerConfig: AppRouter.router,
              builder: (context, child) {
                return DemoOverlay(child: child ?? const SizedBox.shrink());
              },
            );
          },
        ),
      ),
    );
  }
}

/// Shown when the app is loaded on an unauthorized domain.
class _UnauthorizedApp extends StatelessWidget {
  const _UnauthorizedApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Unauthorized',
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.block, size: 80, color: Colors.red.shade400),
              const SizedBox(height: 24),
              Text(
                'Unauthorized Copy',
                style: TextStyle(
                  color: Colors.red.shade400,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'This demo can only run on tapixsolutions.com',
                style: TextStyle(color: Colors.white70, fontSize: 16),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
