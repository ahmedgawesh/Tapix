import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../features/auth/auth.dart';
import '../../features/dashboard/presentation/screens/dashboard_screen.dart';
import '../../features/products/presentation/screens/product_list_screen.dart';
import '../../features/products/presentation/screens/product_form_screen.dart';
import '../../features/products/presentation/screens/bulk_product_form_screen.dart';
import '../../features/products/presentation/screens/edit_prices_screen.dart';
import '../../features/products/presentation/screens/import_products_screen.dart';
import '../../features/products/presentation/screens/simple_export_screen.dart';
import '../../features/products/presentation/screens/categories_screen.dart';
import '../../features/products/presentation/screens/category_form_screen.dart';
import '../../features/products/presentation/screens/colors_screen.dart';
import '../../features/products/presentation/screens/color_form_screen.dart';
import '../../features/products/presentation/screens/color_magazine_screen.dart';
import '../../features/products/presentation/screens/sizes_screen.dart';
import '../../features/products/presentation/screens/size_form_screen.dart';
import '../../features/products/presentation/screens/variants_screen.dart';
import '../../features/products/presentation/bloc/categories_bloc.dart';
import '../../features/products/presentation/bloc/colors_bloc.dart';
import '../../features/products/domain/entities/product_entity.dart';
import '../../features/barcode/data/models/invoice_print_data.dart';
import '../../features/auth/presentation/screens/audit_log_screen.dart';
import '../../features/purchases/presentation/screens/purchase_list_screen.dart';
import '../../features/purchases/presentation/screens/purchase_form_screen.dart';
import '../../features/purchases/presentation/screens/purchase_detail_screen.dart';
import '../../features/purchases/presentation/screens/purchase_returns_screen.dart';
import '../../features/purchases/presentation/screens/purchase_return_form_screen.dart';
import '../../features/purchases/presentation/screens/purchase_return_detail_screen.dart';
import '../../features/customers/presentation/screens/customer_hub_screen.dart';
import '../../features/customers/presentation/screens/customer_form_screen.dart';
import '../../features/customers/presentation/screens/customer_profile_screen.dart';
import '../../features/customers/presentation/screens/receive_payment_screen.dart';
import '../../features/sales/presentation/screens/sale_list_screen.dart';
import '../../features/sales/presentation/screens/sale_form_screen.dart';
import '../../features/sales/presentation/screens/sale_detail_screen.dart';
import '../../features/sales/presentation/screens/sale_returns_screen.dart';
import '../../features/sales/presentation/screens/sale_return_form_screen.dart';
import '../../features/sales/presentation/screens/sale_return_detail_screen.dart';
import '../../features/barcode/presentation/screens/barcode_scanner_screen.dart';
import '../../features/barcode/presentation/screens/barcode_label_designer_screen.dart';
import '../../features/barcode/presentation/screens/barcode_design_screen.dart';
import '../../features/settings/presentation/screens/settings_screen.dart';
import '../../features/settings/presentation/screens/admin_tools_screen.dart';
import '../../features/settings/presentation/screens/company_profile_screen.dart';
import '../../features/employees/presentation/screens/employees_screen.dart';
import '../../features/employees/presentation/screens/attendance_screen.dart';
import '../../features/employees/presentation/screens/leave_requests_screen.dart';
import '../../features/employees/presentation/screens/payroll_screen.dart';
import '../../features/employees/presentation/screens/employee_form_screen.dart';
import '../../features/employees/presentation/screens/employee_detail_screen.dart';
import '../../features/suppliers/presentation/screens/supplier_hub_screen.dart';
import '../../features/suppliers/presentation/screens/supplier_form_screen.dart';
import '../../features/suppliers/presentation/screens/supplier_profile_screen.dart';
import '../../features/expenses/presentation/screens/expenses_screen.dart';
import '../../features/expenses/presentation/screens/expense_form_screen.dart';
import '../../features/expenses/presentation/screens/expense_categories_screen.dart';
import '../../features/accounting/presentation/screens/journal_entries_list_screen.dart';
import '../../features/accounting/presentation/screens/journal_entry_form_screen.dart';
import '../../features/accounting/presentation/screens/journal_entry_detail_screen.dart';
import '../../features/reports/presentation/screens/reports_hub_screen.dart';
import '../../features/reports/presentation/screens/trial_balance_screen.dart';
import '../../features/reports/presentation/screens/profit_loss_screen.dart';
import '../../features/reports/presentation/screens/balance_sheet_screen.dart';
import '../../features/reports/presentation/screens/general_ledger_screen.dart';
import '../../features/reports/presentation/screens/accounting_health_screen.dart';
import '../../features/reports/presentation/screens/inventory_reports_screen.dart';
import '../../features/reports/presentation/screens/customer_reports_screen.dart';
import '../../features/reports/presentation/screens/customer_sales_returns_reports_screen.dart';
import '../../features/reports/presentation/screens/top_customers_screen.dart';
import '../../features/reports/presentation/screens/customer_payment_reports_screen.dart';
import '../../features/reports/presentation/screens/customer_sales_report_screen.dart';
import '../../features/reports/presentation/screens/customer_aging_report_screen.dart';
import '../../features/reports/presentation/screens/customer_statement_report_screen.dart';
import '../../features/reports/presentation/screens/customer_analysis_report_screen.dart';
import '../../features/reports/presentation/screens/supplier_balance_report_screen.dart';
import '../../features/reports/presentation/screens/supplier_debit_balance_report_screen.dart';
import '../../features/reports/presentation/screens/supplier_credit_balance_report_screen.dart';
import '../../features/reports/presentation/screens/supplier_analysis_report_screen.dart';
import '../../features/reports/presentation/screens/supplier_aging_report_screen.dart';
import '../../features/reports/presentation/screens/supplier_statement_report_screen.dart';
import '../../features/reports/presentation/screens/supplier_ledger_report_screen.dart';
import '../../features/reports/presentation/screens/supplier_stocktake_report_screen.dart';
import '../../features/reports/presentation/screens/supplier_balance_drilldown_screen.dart';
import '../../features/reports/presentation/screens/salespeople_commission_report_screen.dart';
import '../../features/reports/presentation/screens/expense_report_screen.dart';
import '../di/injection_container.dart';
import 'route_permissions.dart';

class AppRouter {
  static final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>();
  static final AuthBloc _authBloc = sl<AuthBloc>();
  
  // Keys for tracking onboarding state
  static const String _hasSeenWelcomeKey = 'has_seen_welcome';
  
  // Session state (resets on app restart)
  static bool _hasCompletedSplash = false;
  static bool? _hasSeenWelcome;
  
  static Future<bool> hasSeenWelcome() async {
    if (_hasSeenWelcome != null) return _hasSeenWelcome!;
    final prefs = sl<SharedPreferences>();
    _hasSeenWelcome = prefs.getBool(_hasSeenWelcomeKey) ?? false;
    return _hasSeenWelcome!;
  }
  
  static Future<void> markWelcomeSeen() async {
    final prefs = sl<SharedPreferences>();
    await prefs.setBool(_hasSeenWelcomeKey, true);
    _hasSeenWelcome = true;
  }
  
  static void markSplashCompleted() {
    _hasCompletedSplash = true;
  }

  static final GoRouter router = GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/',
    refreshListenable: GoRouterRefreshStream(_authBloc.stream),
    redirect: (context, state) async {
      final currentPath = state.uri.path;
      final authState = _authBloc.state;
      
      // Show splash on first app launch (session-based)
      if (!_hasCompletedSplash && currentPath != '/splash') {
        return '/splash';
      }
      
      // Allow splash route
      if (currentPath == '/splash') {
        return null;
      }
      
      // After splash, check if user has seen welcome screen
      final seenWelcome = await hasSeenWelcome();
      if (!seenWelcome && currentPath != '/welcome') {
        return '/welcome';
      }
      
      // Allow welcome route
      if (currentPath == '/welcome') {
        return null;
      }

      // After welcome, handle auth states
      // If still loading, stay on current route (will re-redirect when state changes)
      if (authState is AuthInitial || authState is AuthLoading) {
        // Don't show HomePage while loading - stay on a loading state
        // The GoRouterRefreshStream will trigger redirect when auth state changes
        return null;
      }

      // No users exist - go to setup screen to create first owner
      if (authState is AuthNeedsSetup) {
        if (currentPath == '/setup') {
          return null;
        }
        return '/setup';
      }

      // User is authenticated - go to dashboard
      if (authState is AuthAuthenticated) {
        final user = authState.user;
        final requiredRoles = RoutePermissions.map[currentPath];
        if (requiredRoles != null) {
          final hasAccess = requiredRoles.contains(user.role);
          if (!hasAccess) {
            return '/access-denied';
          }
        }

        // Redirect away from auth screens to dashboard
        if (currentPath == '/login' || currentPath == '/setup' || currentPath == '/') {
          return '/dashboard';
        }

        return null;
      }

      // AuthUnauthenticated or AuthError - go to login
      if (currentPath == '/login') {
        return null;
      }

      return '/login';
    },
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const _AuthLoadingScreen(),
      ),
      GoRoute(
        path: '/splash',
        builder: (context, state) => SplashScreen(
          onComplete: () {
            markSplashCompleted();
            router.go('/');
          },
        ),
      ),
      GoRoute(
        path: '/welcome',
        builder: (context, state) => WelcomeScreen(
          onComplete: () async {
            await markWelcomeSeen();
            router.go('/');
          },
        ),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/setup',
        builder: (context, state) => const SetupScreen(),
      ),
      GoRoute(
        path: '/dashboard',
        builder: (context, state) => const DashboardScreen(),
      ),
      GoRoute(
        path: '/products',
        builder: (context, state) => const ProductListScreen(),
        routes: [
          GoRoute(
            path: 'new',
            builder: (context, state) {
              final extra = state.extra as Map<String, dynamic>?;
              final barcode = extra?['barcode'] as String?;
              return ProductFormScreen(initialBarcode: barcode);
            },
          ),
          GoRoute(
            path: ':id/edit',
            builder: (context, state) {
              final id = int.tryParse(state.pathParameters['id'] ?? '');
              return ProductFormScreen(productId: id);
            },
          ),
          GoRoute(
            path: 'bulk',
            builder: (context, state) => const BulkProductFormScreen(),
          ),
          GoRoute(
            path: 'edit-prices',
            builder: (context, state) => const EditPricesScreen(),
          ),
          GoRoute(
            path: 'import',
            builder: (context, state) => const ImportProductsScreen(),
          ),
          GoRoute(
            path: 'export',
            builder: (context, state) => const SimpleExportScreen(),
          ),
          GoRoute(
            path: 'variants',
            builder: (context, state) => const VariantsScreen(),
          ),
          GoRoute(
            path: 'categories',
            builder: (context, state) => const CategoriesScreen(),
            routes: [
              GoRoute(
                path: 'pick',
                builder: (context, state) => const CategoriesScreen(isPicker: true),
              ),
              GoRoute(
                path: 'new',
                builder: (context, state) => BlocProvider(
                  create: (_) => sl<CategoriesBloc>(),
                  child: const CategoryFormScreen(),
                ),
              ),
              GoRoute(
                path: ':id/edit',
                builder: (context, state) {
                  final id = int.tryParse(state.pathParameters['id'] ?? '');
                  return BlocProvider(
                    create: (_) => sl<CategoriesBloc>(),
                    child: CategoryFormScreen(categoryId: id),
                  );
                },
              ),
            ],
          ),
          GoRoute(
            path: 'colors',
            builder: (context, state) => const ColorsScreen(),
            routes: [
              GoRoute(
                path: 'magazine',
                builder: (context, state) => const ColorMagazineScreen(),
              ),
              GoRoute(
                path: 'new',
                builder: (context, state) => BlocProvider(
                  create: (_) => sl<ColorsBloc>(),
                  child: const ColorFormScreen(),
                ),
              ),
              GoRoute(
                path: ':id/edit',
                builder: (context, state) {
                  final id = int.tryParse(state.pathParameters['id'] ?? '');
                  return BlocProvider(
                    create: (_) => sl<ColorsBloc>(),
                    child: ColorFormScreen(colorId: id),
                  );
                },
              ),
            ],
          ),
          GoRoute(
            path: 'sizes',
            builder: (context, state) => const SizesScreen(),
            routes: [
              GoRoute(
                path: 'new',
                builder: (context, state) => const SizeFormScreen(),
              ),
              GoRoute(
                path: ':id/edit',
                builder: (context, state) {
                  final id = int.tryParse(state.pathParameters['id'] ?? '');
                  return SizeFormScreen(sizeId: id);
                },
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/sales',
        builder: (context, state) => const SaleListScreen(),
        routes: [
          GoRoute(
            path: 'new',
            builder: (context, state) => const SaleFormScreen(),
          ),
          GoRoute(
            path: 'returns',
            builder: (context, state) => const SaleReturnsScreen(),
            routes: [
              GoRoute(
                path: 'new',
                builder: (context, state) {
                  final saleId = int.tryParse(
                      state.uri.queryParameters['saleId'] ?? '');
                  if (saleId == null) return const SaleReturnsScreen();
                  return SaleReturnFormScreen(saleId: saleId);
                },
              ),
              GoRoute(
                path: ':returnId',
                builder: (context, state) {
                  final returnId = int.tryParse(
                      state.pathParameters['returnId'] ?? '');
                  if (returnId == null) return const SaleReturnsScreen();
                  return SaleReturnDetailScreen(returnId: returnId);
                },
              ),
            ],
          ),
          GoRoute(
            path: ':id',
            builder: (context, state) {
              final id = int.tryParse(state.pathParameters['id'] ?? '');
              if (id == null) return const SaleListScreen();
              return SaleDetailScreen(saleId: id);
            },
            routes: [
              GoRoute(
                path: 'edit',
                builder: (context, state) {
                  final id = int.tryParse(state.pathParameters['id'] ?? '');
                  return SaleFormScreen(saleId: id);
                },
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/customers',
        builder: (context, state) => const CustomerHubScreen(),
        routes: [
          GoRoute(
            path: 'new',
            builder: (context, state) => const CustomerFormScreen(),
          ),
          GoRoute(
            path: 'receive-payment',
            builder: (context, state) {
              final extra = state.extra as Map<String, dynamic>?;
              final customerId = extra?['customerId'] as int?;
              return ReceivePaymentScreen(preselectedCustomerId: customerId);
            },
          ),
          GoRoute(
            path: ':id',
            builder: (context, state) {
              final id = int.tryParse(state.pathParameters['id'] ?? '');
              if (id == null) return const CustomerHubScreen();
              return CustomerProfileScreen(customerId: id);
            },
            routes: [
              GoRoute(
                path: 'edit',
                builder: (context, state) {
                  final id = int.tryParse(state.pathParameters['id'] ?? '');
                  return CustomerFormScreen(customerId: id);
                },
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/suppliers',
        builder: (context, state) => const SupplierHubScreen(),
        routes: [
          GoRoute(
            path: 'new',
            builder: (context, state) => const SupplierFormScreen(),
          ),
          GoRoute(
            path: ':id',
            builder: (context, state) {
              final id = int.tryParse(state.pathParameters['id'] ?? '');
              if (id == null) return const SupplierHubScreen();
              return SupplierProfileScreen(supplierId: id);
            },
            routes: [
              GoRoute(
                path: 'edit',
                builder: (context, state) {
                  final id = int.tryParse(state.pathParameters['id'] ?? '');
                  return SupplierFormScreen(supplierId: id);
                },
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/purchases',
        builder: (context, state) => const PurchaseListScreen(),
        routes: [
          GoRoute(
            path: 'new',
            builder: (context, state) => const PurchaseFormScreen(),
          ),
          GoRoute(
            path: 'returns',
            builder: (context, state) => const PurchaseReturnsScreen(),
            routes: [
              GoRoute(
                path: 'new',
                builder: (context, state) {
                  final purchaseId = int.tryParse(
                      state.uri.queryParameters['purchaseId'] ?? '');
                  if (purchaseId == null) return const PurchaseReturnsScreen();
                  return PurchaseReturnFormScreen(purchaseId: purchaseId);
                },
              ),
              GoRoute(
                path: ':returnId',
                builder: (context, state) {
                  final returnId = int.tryParse(
                      state.pathParameters['returnId'] ?? '');
                  if (returnId == null) return const PurchaseReturnsScreen();
                  return PurchaseReturnDetailScreen(returnId: returnId);
                },
              ),
            ],
          ),
          GoRoute(
            path: ':id',
            builder: (context, state) {
              final id = int.tryParse(state.pathParameters['id'] ?? '');
              if (id == null) return const PurchaseListScreen();
              return PurchaseDetailScreen(purchaseId: id);
            },
            routes: [
              GoRoute(
                path: 'edit',
                builder: (context, state) {
                  final id = int.tryParse(state.pathParameters['id'] ?? '');
                  return PurchaseFormScreen(purchaseId: id);
                },
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/expenses',
        builder: (context, state) => const ExpensesScreen(),
        routes: [
          GoRoute(
            path: 'new',
            builder: (context, state) => const ExpenseFormScreen(),
          ),
          GoRoute(
            path: 'categories',
            builder: (context, state) => const ExpenseCategoriesScreen(),
          ),
          GoRoute(
            path: ':id/edit',
            builder: (context, state) {
              final id = int.tryParse(state.pathParameters['id'] ?? '');
              return ExpenseFormScreen(expenseId: id);
            },
          ),
        ],
      ),
      GoRoute(
        path: '/reports',
        builder: (context, state) => const ReportsHubScreen(),
        routes: [
          GoRoute(
            path: 'trial-balance',
            builder: (context, state) => const TrialBalanceScreen(),
          ),
          GoRoute(
            path: 'profit-loss',
            builder: (context, state) => const ProfitLossScreen(),
          ),
          GoRoute(
            path: 'balance-sheet',
            builder: (context, state) => const BalanceSheetScreen(),
          ),
          GoRoute(
            path: 'general-ledger',
            builder: (context, state) => const GeneralLedgerScreen(),
          ),
          GoRoute(
            path: 'health',
            builder: (context, state) => const AccountingHealthScreen(),
          ),
          GoRoute(
            path: 'inventory',
            builder: (context, state) => const InventoryReportsScreen(),
          ),
          GoRoute(
            path: 'customers',
            builder: (context, state) => const CustomerReportsScreen(),
          ),
          GoRoute(
            path: 'customer-returns',
            builder: (context, state) => const CustomerSalesReturnsReportsScreen(),
          ),
          GoRoute(
            path: 'top-customers',
            builder: (context, state) => const TopCustomersScreen(),
          ),
          GoRoute(
            path: 'customer-payments',
            builder: (context, state) => const CustomerPaymentReportsScreen(),
          ),
          GoRoute(
            path: 'customer-sales',
            builder: (context, state) => const CustomerSalesReportScreen(),
          ),
          GoRoute(
            path: 'customer-aging',
            builder: (context, state) => const CustomerAgingReportScreen(),
          ),
          GoRoute(
            path: 'customer-statement',
            builder: (context, state) => const CustomerStatementReportScreen(),
          ),
          GoRoute(
            path: 'customer-analysis',
            builder: (context, state) => const CustomerAnalysisReportScreen(),
          ),
          GoRoute(
            path: 'supplier-balance',
            builder: (context, state) => const SupplierBalanceReportScreen(),
          ),
          GoRoute(
            path: 'supplier-debit-balance',
            builder: (context, state) => const SupplierDebitBalanceReportScreen(),
          ),
          GoRoute(
            path: 'supplier-credit-balance',
            builder: (context, state) => const SupplierCreditBalanceReportScreen(),
          ),
          GoRoute(
            path: 'supplier-analysis',
            builder: (context, state) => const SupplierAnalysisReportScreen(),
          ),
          GoRoute(
            path: 'supplier-aging',
            builder: (context, state) => const SupplierAgingReportScreen(),
          ),
          GoRoute(
            path: 'supplier-statement',
            builder: (context, state) => const SupplierStatementReportScreen(),
          ),
          GoRoute(
            path: 'supplier-ledger',
            builder: (context, state) => const SupplierLedgerReportScreen(),
          ),
          GoRoute(
            path: 'supplier-stocktake',
            builder: (context, state) => const SupplierStocktakeReportScreen(),
          ),
          GoRoute(
            path: 'supplier-balance-drilldown',
            builder: (context, state) => const SupplierBalanceDrilldownScreen(),
          ),
          GoRoute(
            path: 'salespeople-commission',
            builder: (context, state) => const SalespeopleCommissionReportScreen(),
          ),
          GoRoute(
            path: 'expense-report',
            builder: (context, state) => const ExpenseReportScreen(),
          ),
        ],
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
        routes: [
          GoRoute(
            path: 'company',
            builder: (context, state) => const CompanyProfileScreen(),
          ),
          GoRoute(
            path: 'admin-tools',
            builder: (context, state) => const AdminToolsScreen(),
          ),
        ],
      ),
      GoRoute(
        path: '/barcode-scanner',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          final returnOnScan = extra?['returnOnScan'] as bool? ?? false;
          return BarcodeScannerScreen(returnOnScan: returnOnScan);
        },
      ),
      GoRoute(
        path: '/barcode-designer',
        builder: (context, state) {
          final product = state.extra as Product;
          return BarcodeLabelDesignerScreen(product: product);
        },
      ),
      GoRoute(
        path: '/products/barcode-design',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          final products = extra?['products'] as List<Product>?;
          final variantInfoByProductId = extra?['variantInfoByProductId'] as Map<int, String>?;
          final invoiceData = extra?['invoiceData'] as InvoicePrintData?;
          return BarcodeDesignScreen(
            initialProducts: products,
            variantInfoByProductId: variantInfoByProductId,
            invoiceData: invoiceData,
          );
        },
      ),
      GoRoute(
        path: '/users',
        builder: (context, state) => const UsersScreen(),
        routes: [
          GoRoute(
            path: 'add',
            builder: (context, state) => const UserFormScreen(),
          ),
          GoRoute(
            path: 'roles',
            builder: (context, state) => const RolesScreen(),
          ),
          GoRoute(
            path: ':id/edit',
            builder: (context, state) {
              final id = int.tryParse(state.pathParameters['id'] ?? '');
              return UserFormScreen(userId: id);
            },
          ),
        ],
      ),
      GoRoute(
        path: '/employees',
        builder: (context, state) => const EmployeesScreen(),
        routes: [
          GoRoute(
            path: 'attendance',
            builder: (context, state) => const AttendanceScreen(),
          ),
          GoRoute(
            path: 'leave-requests',
            builder: (context, state) => const LeaveRequestsScreen(),
          ),
          GoRoute(
            path: 'payroll',
            builder: (context, state) => const PayrollScreen(),
          ),
          GoRoute(
            path: 'create',
            builder: (context, state) => const EmployeeFormScreen(),
          ),
          GoRoute(
            path: ':id',
            builder: (context, state) {
              final id = int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
              return EmployeeDetailScreen(employeeId: id);
            },
            routes: [
              GoRoute(
                path: 'edit',
                builder: (context, state) {
                  final id = int.tryParse(state.pathParameters['id'] ?? '');
                  return EmployeeFormScreen(employeeId: id);
                },
              ),
            ],
          ),
          GoRoute(
            path: 'settings',
            builder: (context, state) => const PlaceholderScreen(title: 'Employees Settings'),
          ),
        ],
      ),
      GoRoute(
        path: '/accounting',
        builder: (context, state) => const JournalEntriesListScreen(),
        routes: [
          GoRoute(
            path: 'journal-entries',
            builder: (context, state) => const JournalEntriesListScreen(),
            routes: [
              GoRoute(
                path: 'add',
                builder: (context, state) => const JournalEntryFormScreen(),
              ),
              GoRoute(
                path: ':id',
                builder: (context, state) {
                  final id = int.tryParse(state.pathParameters['id'] ?? '');
                  if (id == null) return const JournalEntriesListScreen();
                  return JournalEntryDetailScreen(entryId: id);
                },
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/audit',
        builder: (context, state) => const AuditLogScreen(),
      ),
      GoRoute(
        path: '/access-denied',
        builder: (context, state) => const AccessDeniedScreen(
          message: 'You do not have permission to access this page.',
        ),
      ),
    ],
  );

}

class PlaceholderScreen extends StatelessWidget {
  final String title;
  const PlaceholderScreen({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              context.go('/dashboard');
            }
          },
          tooltip: 'Back',
        ),
        title: Text(title),
        centerTitle: true,
      ),
      body: Center(child: Text('$title ${'common.screen'.tr()}')),
    );
  }
}

class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _subscription = stream.listen((_) => notifyListeners());
  }

  late final StreamSubscription<dynamic> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

// Loading screen shown while auth state is being determined
class _AuthLoadingScreen extends StatelessWidget {
  const _AuthLoadingScreen();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/logos/logo.png',
              width: 120,
              height: 120,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 24),
            CircularProgressIndicator(
              color: colorScheme.primary,
            ),
          ],
        ),
      ),
    );
  }
}
