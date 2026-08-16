import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/crashlytics_service.dart';
import '../bloc/currency_bloc.dart';
import '../bloc/localization_bloc.dart';
import '../bloc/theme_bloc.dart';
import '../database/app_database.dart';
import '../database/daos/product_dao.dart';
import '../database/daos/product_variant_dao.dart';
import '../database/daos/product_color_dao.dart';
import '../database/daos/category_dao.dart';
import '../database/daos/size_dao.dart';
import '../database/daos/settings_dao.dart';
import '../database/daos/barcode_template_dao.dart';
import '../database/daos/purchase_dao.dart';
import '../database/daos/sale_dao.dart';
import '../services/currency_service.dart';
import '../services/cashier_shift_service.dart';
import '../money/money_input_parser.dart';
import '../services/parties/party_balance_classifier.dart';
import '../services/pricing/discount_converter.dart';
import '../services/einvoice/einvoice_artifact_repository.dart';
import '../services/einvoice/einvoice_dispatch_service.dart';
import '../services/einvoice/einvoice_provider_registry.dart';
import '../services/localization_service.dart';
import '../services/audit_log_service.dart';
import '../services/below_cost_sale_service.dart';
import '../services/biometric_service.dart';
import '../services/pin_service.dart';
import '../services/theme_service.dart';
import '../../features/auth/auth.dart';
import '../../features/products/domain/repositories/product_repository.dart';
import '../../features/products/domain/repositories/product_variant_repository.dart';
import '../../features/products/domain/repositories/category_repository.dart';
import '../../features/products/domain/repositories/product_color_repository.dart';
import '../../features/products/domain/repositories/size_repository.dart';
import '../../features/products/data/datasources/product_local_datasource.dart';
import '../../features/products/data/datasources/variant_local_datasource.dart';
import '../../features/products/data/repositories/product_repository_impl.dart';
import '../../features/products/data/repositories/product_variant_repository_impl.dart';
import '../../features/products/data/repositories/category_repository_impl.dart';
import '../../features/products/data/repositories/product_color_repository_impl.dart';
import '../../features/products/data/repositories/size_repository_impl.dart';
import '../../features/products/presentation/bloc/products_bloc.dart';
import '../../features/products/presentation/bloc/product_form_bloc.dart';
import '../../features/products/presentation/bloc/product_variants_bloc.dart';
import '../../features/products/presentation/bloc/bulk_product_bloc.dart';
import '../../features/products/presentation/bloc/edit_prices_bloc.dart';
import '../../features/products/presentation/bloc/import_products_bloc.dart';
import '../../features/products/presentation/bloc/export_bloc.dart';
import '../../features/products/presentation/bloc/categories_bloc.dart';
import '../../features/products/presentation/bloc/colors_bloc.dart';
import '../../features/products/presentation/bloc/sizes_bloc.dart';
import '../../features/products/presentation/bloc/variant_summaries_bloc.dart';
import '../../features/products/presentation/bloc/variant_previews_bloc.dart';
import '../../features/products/presentation/bloc/expiry_summaries_bloc.dart';
import '../../features/products/services/file_import_service.dart';
import '../../features/products/services/import_validation_service.dart';
import '../../features/products/services/product_import_service.dart';
import '../../features/products/services/export_service.dart';
import '../../features/products/domain/usecases/parse_import_file.dart';
import '../../features/products/domain/usecases/validate_import_data.dart';
import '../../features/products/domain/usecases/import_products.dart';
import '../../features/barcode/services/barcode_validation_service.dart';
import '../../features/barcode/services/barcode_generation_service.dart';
import '../../features/barcode/services/barcode_printer_service.dart';
import '../../features/barcode/presentation/bloc/barcode_scanner_bloc.dart';
import '../../features/barcode/presentation/bloc/barcode_design_bloc.dart';
import '../../features/settings/data/services/company_profile_service.dart';
import '../../features/settings/data/services/app_settings_service.dart';
import '../../features/settings/presentation/bloc/company_bloc.dart';
import '../../features/settings/presentation/bloc/app_settings_bloc.dart';
import '../../features/purchases/data/datasources/purchase_local_datasource.dart';
import '../../features/purchases/data/repositories/purchase_repository_impl.dart';
import '../../features/purchases/domain/repositories/purchase_repository.dart';
import '../../features/purchases/presentation/bloc/purchases_bloc.dart';
import '../../features/purchases/presentation/bloc/purchase_form_bloc.dart';
import '../../features/purchases/presentation/bloc/purchase_returns_bloc.dart';
import '../../features/purchases/presentation/bloc/purchase_return_form_bloc.dart';
import '../../features/sales/data/datasources/sale_local_datasource.dart';
import '../../features/sales/data/repositories/sale_repository_impl.dart';
import '../../features/sales/domain/repositories/sale_repository.dart';
import '../../features/sales/presentation/bloc/sales_bloc.dart';
import '../../features/sales/presentation/bloc/sale_form_bloc.dart';
import '../../features/sales/presentation/bloc/sale_returns_bloc.dart';
import '../../features/sales/presentation/bloc/sale_return_form_bloc.dart';
import '../../features/customers/domain/repositories/customer_repository.dart';
import '../../features/customers/domain/repositories/loyalty_repository.dart';
import '../../features/customers/data/datasources/customer_local_datasource.dart';
import '../../features/customers/data/repositories/customer_repository_impl.dart';
import '../../features/customers/data/repositories/loyalty_repository_impl.dart';
import '../../features/customers/presentation/bloc/customers_bloc.dart';
import '../../features/customers/presentation/bloc/customer_form_bloc.dart';
import '../../features/customers/presentation/bloc/customer_loyalty_bloc.dart';
import '../../features/customers/presentation/bloc/customer_profile_bloc.dart';
import '../database/daos/customer_dao.dart';
import '../database/daos/employee_dao.dart';
import '../database/daos/supplier_dao.dart';
import '../../features/suppliers/domain/repositories/supplier_repository.dart';
import '../../features/suppliers/data/datasources/supplier_local_datasource.dart';
import '../../features/suppliers/data/repositories/supplier_repository_impl.dart';
import '../../features/suppliers/presentation/bloc/suppliers_bloc.dart';
import '../../features/suppliers/presentation/bloc/supplier_form_bloc.dart';
import '../../features/suppliers/presentation/bloc/supplier_profile_bloc.dart';
import '../../features/employees/domain/repositories/employee_repository.dart';
import '../../features/employees/data/repositories/employee_repository_impl.dart';
import '../../features/employees/presentation/bloc/employees_bloc.dart';
import '../../features/employees/presentation/bloc/employee_detail_bloc.dart';
import '../../features/employees/presentation/bloc/attendance_bloc.dart';
import '../../features/employees/presentation/bloc/leave_requests_bloc.dart';
import '../../features/employees/presentation/bloc/payroll_bloc.dart';
import '../../features/employees/presentation/bloc/roles_bloc.dart';
import '../database/daos/accounting_dao.dart';
import '../database/daos/adjustment_return_dao.dart';
import '../database/daos/cheque_confirmation_dao.dart';
import '../database/daos/inventory_adjustment_dao.dart';
import '../database/daos/batch_audit_dao.dart';
import '../services/inventory/inventory_adjustment_service.dart';
import '../services/inventory/inventory_valuation_service.dart';
import '../services/inventory/expiry_alert_service.dart';
import '../../features/inventory/presentation/bloc/expiry_alerts_bloc.dart';
import '../services/unified_return_service.dart';
import '../../features/expenses/domain/repositories/expense_repository.dart';
import '../../features/expenses/data/datasources/expense_local_datasource.dart';
import '../../features/expenses/data/repositories/expense_repository_impl.dart';
import '../../features/expenses/presentation/bloc/expenses_bloc.dart';
import '../../features/expenses/presentation/bloc/expense_form_bloc.dart';
import '../../features/expenses/presentation/bloc/expense_categories_bloc.dart';
import '../../features/accounting/domain/repositories/journal_repository.dart';
import '../../features/accounting/data/datasources/journal_local_datasource.dart';
import '../../features/accounting/data/repositories/journal_repository_impl.dart';
import '../../features/accounting/data/repositories/accounting_repository.dart';
import '../../features/accounting/domain/services/accounting_close_service.dart';
import '../services/cheque_lifecycle_service.dart';
import '../services/journal_entry_service.dart';
import '../services/owner_finance_service.dart';
import '../services/fixed_asset_service.dart';
import '../services/commissions/commission_service.dart';
import '../services/loyalty/loyalty_points_service.dart';
import '../services/returns/return_approval_service.dart';
import '../services/returns/return_journal_policy.dart';
import '../services/returns/return_posting_service.dart';
import '../services/returns/return_reason_code_service.dart';
import '../services/compliance/fiscal_period_service.dart';
import '../services/compliance/customer_credit_note_service.dart';
import '../services/data_integrity_service.dart';
import '../services/ledger_rebuild_service.dart';
import '../services/attendance_service.dart';
import '../../features/accounting/presentation/bloc/accounts_bloc.dart';
import '../../features/accounting/presentation/bloc/journal_entries_bloc.dart';
import '../../features/accounting/presentation/bloc/journal_entry_form_bloc.dart';
import '../../features/financial_management/presentation/bloc/accounting_periods_bloc.dart';
import '../../features/reports/presentation/bloc/reports_bloc.dart';
import '../../features/reports/presentation/bloc/inventory_reports_bloc.dart';
import '../../features/reports/presentation/bloc/product_movement_detail_bloc.dart';
import '../../features/reports/presentation/bloc/stock_movement_report_bloc.dart';
import '../../features/reports/presentation/bloc/product_variant_movement_bloc.dart';
import '../../features/reports/presentation/bloc/category_movement_bloc.dart';
import '../../features/reports/presentation/bloc/customer_reports_bloc.dart';
import '../../features/reports/presentation/bloc/customer_sales_returns_reports_bloc.dart';
import '../../features/reports/presentation/bloc/top_customers_bloc.dart';
import '../../features/reports/presentation/bloc/customer_payment_reports_bloc.dart';
import '../../features/reports/presentation/bloc/customer_sales_report_bloc.dart';
import '../../features/reports/presentation/bloc/customer_aging_report_bloc.dart';
import '../../features/reports/presentation/bloc/customer_statement_report_bloc.dart';
import '../../features/reports/presentation/bloc/customer_analysis_report_bloc.dart';
import '../../features/reports/presentation/bloc/supplier_balance_report_bloc.dart';
import '../../features/reports/presentation/bloc/supplier_debit_balance_report_bloc.dart';
import '../../features/reports/presentation/bloc/supplier_credit_balance_report_bloc.dart';
import '../../features/reports/presentation/bloc/supplier_analysis_report_bloc.dart';
import '../../features/reports/presentation/bloc/supplier_aging_report_bloc.dart';
import '../../features/reports/presentation/bloc/supplier_statement_report_bloc.dart';
import '../../features/reports/presentation/bloc/supplier_ledger_report_bloc.dart';
import '../../features/reports/presentation/bloc/customer_ledger_report_bloc.dart';
import '../../features/reports/presentation/bloc/customer_invoices_report_bloc.dart';
import '../../features/reports/presentation/bloc/supplier_invoices_report_bloc.dart';
import '../../features/reports/presentation/bloc/supplier_returns_report_bloc.dart';
import '../../features/reports/presentation/bloc/supplier_stocktake_report_bloc.dart';
import '../../features/reports/presentation/bloc/supplier_balance_drilldown_bloc.dart';
import '../../features/reports/presentation/bloc/salespeople_commission_report_bloc.dart';
import '../../features/reports/presentation/bloc/expense_report_bloc.dart';
import '../../features/reports/presentation/bloc/sales_tax_report_bloc.dart';
import '../../features/reports/presentation/bloc/purchase_tax_report_bloc.dart';
import '../../features/reports/presentation/bloc/sales_reports_bloc.dart';
import '../../features/reports/presentation/bloc/purchase_reports_bloc.dart';
import '../../features/reports/presentation/bloc/discount_reports_bloc.dart';
import '../../features/reports/presentation/bloc/profit_reports_bloc.dart';
import '../services/revenuecat_service.dart';
import '../services/device_fingerprint_service.dart';
import '../services/license_service.dart';
import '../services/connectivity_service.dart';
import '../services/remote_security_service.dart';
import '../services/code_integrity_service.dart';
import '../services/app_guard_service.dart';
import '../services/feature_gate_service.dart';
import '../services/free_quota_service.dart';
import '../../features/subscription/subscription.dart';

final sl = GetIt.instance;

Future<void> init() async {
  // External
  final sharedPreferences = await SharedPreferences.getInstance();
  sl.registerLazySingleton(() => sharedPreferences);

  // Database
  sl.registerLazySingleton(() => AppDatabase());

  // DAOs
  sl.registerLazySingleton(() => ProductDao(sl()));
  sl.registerLazySingleton(() => ProductVariantDao(sl()));
  sl.registerLazySingleton(() => ProductColorDao(sl()));
  sl.registerLazySingleton(() => CategoryDao(sl()));
  sl.registerLazySingleton(() => SizeDao(sl()));
  sl.registerLazySingleton(() => SettingsDao(sl()));
  sl.registerLazySingleton(() => BarcodeTemplateDao(sl()));
  sl.registerLazySingleton(() => PurchaseDao(sl()));
  sl.registerLazySingleton(() => SaleDao(sl()));
  sl.registerLazySingleton(() => CustomerDao(sl()));
  sl.registerLazySingleton(() => EmployeeDao(sl()));
  sl.registerLazySingleton(() => SupplierDao(sl()));
  sl.registerLazySingleton(() => AccountingDao(sl()));
  sl.registerLazySingleton(() => AdjustmentReturnDao(sl()));
  sl.registerLazySingleton(() => InventoryAdjustmentDao(sl()));
  sl.registerLazySingleton(() => BatchAuditDao(sl()));
  // Phase 14.0 — cheque confirmation lifecycle (DB-backed).
  sl.registerLazySingleton(() => ChequeConfirmationDao(sl()));

  // Auth Services
  sl.registerLazySingleton(() => PasswordService());
  sl.registerLazySingleton(() => SessionService());
  sl.registerLazySingleton(() => PermissionService());
  sl.registerLazySingleton(() => PinService());
  sl.registerLazySingleton(() => BiometricService());
  sl.registerLazySingleton<AuthRepositoryInterface>(
    () => AuthRepository(
      database: sl(),
      passwordService: sl(),
      sessionService: sl(),
    ),
  );
  sl.registerLazySingleton<UserRepositoryInterface>(
    () => UserRepository(database: sl(), passwordService: sl()),
  );

  // Core Services
  sl.registerLazySingleton(() => ThemeService(sl()));
  sl.registerLazySingleton(() => LocalizationService(sl()));
  sl.registerLazySingleton(() => CurrencyService(sl()));
  sl.registerLazySingleton(() => CashierShiftService(sl<AppDatabase>()));
  // Phase 3.5.1 — single source of truth for free-form text → cents.
  // All UI forms must obtain cents via this parser instead of doing
  // `double.parse(text) * 100`, which silently loses precision on edges
  // like `99999.99 * 100` and ignores currencies with non-2 decimal digits
  // (JOD/KWD/BHD/OMR/JPY/IQD/...).
  sl.registerLazySingleton(() => MoneyInputParser(sl<CurrencyService>()));
  // Phase 3.5.2 — classifier centralises the sign convention that
  // customer / supplier hubs and profile screens used to hand-roll
  // inline. See `party_balance_classifier.dart` for the convention.
  sl.registerLazySingleton(() => const PartyBalanceClassifier());
  // Phase 3.5.5 — single source of truth for fixed <-> percent discount
  // conversions. Replaces the `double * 100 / 100` helpers that used to
  // live inline in `sale_form_dialogs.dart`.
  sl.registerLazySingleton(() => const DiscountConverter());
  sl.registerLazySingleton(
    () => AuditLogService(sl<AppDatabase>(), sl<SessionService>()),
  );
  sl.registerLazySingleton(() => const BelowCostSaleService());
  sl.registerLazySingleton(() => DataIntegrityService(sl<AppDatabase>()));
  sl.registerLazySingleton(
    () => UnifiedReturnService(
      sl<AppDatabase>(),
      sl<PurchaseDao>(),
      sl<SaleDao>(),
      sl<AdjustmentReturnDao>(),
      sl<JournalEntryService>(),
      sl<CommissionService>(),
      sl<LoyaltyPointsService>(),
      sessionService: sl<SessionService>(),
      cashierShiftService: sl<CashierShiftService>(),
    ),
  );

  // Datasources
  sl.registerLazySingleton<ProductLocalDatasource>(
    () => ProductLocalDatasourceImpl(sl()),
  );
  sl.registerLazySingleton<VariantLocalDatasource>(
    () => VariantLocalDatasourceImpl(sl(), sl(), sl()),
  );

  // Feature Repositories
  sl.registerLazySingleton<ProductRepository>(
    () => ProductRepositoryImpl(
      sl(),
      sl<AuditLogService>(),
      sl<SessionService>(),
      // Wired so smartDelete / writeOffAndDeleteProduct can post a balanced
      // shrinkage entry per variant before removing the row, keeping the
      // 1200 Inventory ledger in sync with Σ(stock × cost).
      variantDatasource: sl<VariantLocalDatasource>(),
      adjustmentService: sl<InventoryAdjustmentService>(),
      // Phase B4 — enforce free-tier 100-product cumulative cap.
      freeQuotaService: sl<FreeQuotaService>(),
    ),
  );
  sl.registerLazySingleton<ProductVariantRepository>(
    () => ProductVariantRepositoryImpl(
      sl<VariantLocalDatasource>(),
      sl<InventoryAdjustmentService>(),
    ),
  );
  sl.registerLazySingleton<CategoryRepository>(
    () => CategoryRepositoryImpl(sl()),
  );
  sl.registerLazySingleton<ProductColorRepository>(
    () => ProductColorRepositoryImpl(sl()),
  );
  sl.registerLazySingleton<SizeRepository>(() => SizeRepositoryImpl(sl()));

  // Phase 11.1 — fiscal-period guard. Registered BEFORE AccountingRepository
  // because every JE post/void path now consults it. (Lazy singletons so
  // ordering is purely declarative; this is a readability + future-proofing
  // move.) The same instance is also injected into ReturnPostingService.
  sl.registerLazySingleton<FiscalPeriodService>(
    () => FiscalPeriodService(sl<AppDatabase>()),
  );

  // Accounting Repository & Journal Entry Service (needed by Sales/Purchases)
  // Phase 11.1 — wired through `withFiscalPeriodGuard` so every
  // createJournalEntry / postJournalEntry / voidJournalEntry asserts
  // the effective date falls in an OPEN fiscal period. Closes the
  // backdating loophole that previously existed only on returns.
  sl.registerLazySingleton<AccountingRepository>(
    () => AccountingRepository.withFiscalPeriodGuard(
      sl<AppDatabase>(),
      fiscalPeriodService: sl<FiscalPeriodService>(),
    ),
  );
  sl.registerLazySingleton(
    () => AccountingCloseService(sl<AppDatabase>(), sl<AccountingRepository>()),
  );
  sl.registerLazySingleton<OwnerFinanceService>(
    () => OwnerFinanceService(
      db: sl<AppDatabase>(),
      accounting: sl<AccountingRepository>(),
    ),
  );
  sl.registerLazySingleton<FixedAssetService>(
    () => FixedAssetService(
      db: sl<AppDatabase>(),
      accounting: sl<AccountingRepository>(),
    ),
  );
  // Unified return-posting pipeline (Phase 1).
  // ReturnJournalPolicy is the single source of truth for return JE shape;
  // ReturnPostingService is the single API every flow (linked + adjustment)
  // funnels through. The legacy `JournalEntryService.record*ReturnJournalEntry`
  // methods now delegate here.
  sl.registerLazySingleton<ReturnJournalPolicy>(
    () => ReturnJournalPolicy(sl<AccountingRepository>()),
  );
  // Phase 2 compliance services — customer-credit-note sub-ledger.
  // ReturnPostingService also receives the FiscalPeriodService (registered
  // above) so every return post (linked + adjustment) enforces the same
  // period guard the JE pipeline now enforces.
  sl.registerLazySingleton<CustomerCreditNoteService>(
    () => CustomerCreditNoteService(
      db: sl<AppDatabase>(),
      accountingRepo: sl<AccountingRepository>(),
    ),
  );
  sl.registerLazySingleton<ReturnPostingService>(
    () => ReturnPostingService(
      accountingRepo: sl<AccountingRepository>(),
      policy: sl<ReturnJournalPolicy>(),
      fiscalPeriodService: sl<FiscalPeriodService>(),
      creditNoteService: sl<CustomerCreditNoteService>(),
    ),
  );
  // Phase 3 — return approval policy + reason-codes registry. Both read
  // from `app_settings` / `return_reason_codes` and are the single
  // sources of truth for the approval pipeline; DAOs receive the
  // approval service via method args, never re-implement policy.
  sl.registerLazySingleton<ReturnApprovalService>(
    () => ReturnApprovalService(sl<SettingsDao>()),
  );
  sl.registerLazySingleton<ReturnReasonCodeService>(
    () => ReturnReasonCodeService(sl<AppDatabase>()),
  );
  // Phase 4 — e-invoicing. All three services funnel every outgoing
  // artifact through a single chokepoint:
  //   EInvoiceDispatchService.dispatch(subject)
  // Providers are registered empty by default (NullEInvoiceProvider is
  // the fallback). Per-market providers (ZatcaPhase2Provider, EtaProvider,
  // PeppolUblProvider) are added here once the tenant has onboarded with
  // the relevant tax authority (certificates, OAuth creds, Access Point).
  sl.registerLazySingleton<EInvoiceProviderRegistry>(
    () => EInvoiceProviderRegistry(providers: const []),
  );
  sl.registerLazySingleton<EInvoiceArtifactRepository>(
    () => EInvoiceArtifactRepository(sl<AppDatabase>()),
  );
  sl.registerLazySingleton<EInvoiceDispatchService>(
    () => EInvoiceDispatchService(
      registry: sl<EInvoiceProviderRegistry>(),
      artifactRepository: sl<EInvoiceArtifactRepository>(),
      settingsDao: sl<SettingsDao>(),
    ),
  );
  sl.registerLazySingleton<JournalEntryService>(
    () => JournalEntryService(
      sl<AccountingRepository>(),
      returnPostingService: sl<ReturnPostingService>(),
    ),
  );

  // Phase 6 — single sources of truth for commission + loyalty math.
  // SaleRepositoryImpl is the only legitimate consumer of CommissionService;
  // LoyaltyRepositoryImpl additionally calls LoyaltyPointsService.previewSync
  // via the static API (no DI handle needed for the preview path).
  sl.registerLazySingleton<CommissionService>(
    () => CommissionService(sl<EmployeeDao>()),
  );
  sl.registerLazySingleton<LoyaltyPointsService>(
    () => LoyaltyPointsService(
      sl<LoyaltyRepository>(),
      sl<JournalEntryService>(),
      sl<AppDatabase>(),
    ),
  );

  // Inventory adjustments (manual stock shrinkage / gain / revaluation).
  // Single sanctioned entry point — must be used by any UI that mutates
  // on-hand stock outside of purchase / sale flows.
  sl.registerLazySingleton<InventoryAdjustmentService>(
    () => InventoryAdjustmentService(
      db: sl<AppDatabase>(),
      dao: sl<InventoryAdjustmentDao>(),
      journal: sl<JournalEntryService>(),
    ),
  );

  // Purchases
  sl.registerLazySingleton<PurchaseLocalDatasource>(
    () => PurchaseLocalDatasourceImpl(
      sl<PurchaseDao>(),
      sl<AdjustmentReturnDao>(),
    ),
  );
  sl.registerLazySingleton<PurchaseRepository>(
    () => PurchaseRepositoryImpl(
      sl<PurchaseLocalDatasource>(),
      sl<AuditLogService>(),
      sl<SessionService>(),
      sl<JournalEntryService>(),
      sl<AppDatabase>(),
    ),
  );

  // Sales
  sl.registerLazySingleton<SaleLocalDatasource>(
    () => SaleLocalDatasourceImpl(sl<SaleDao>(), sl<AdjustmentReturnDao>()),
  );
  sl.registerLazySingleton<SaleRepository>(
    () => SaleRepositoryImpl(
      sl<SaleLocalDatasource>(),
      sl<SaleDao>(),
      sl<JournalEntryService>(),
      sl<AuditLogService>(),
      sl<SessionService>(),
      sl<LoyaltyRepository>(),
      sl<CommissionService>(),
      sl<LoyaltyPointsService>(),
      einvoiceDispatch: sl<EInvoiceDispatchService>(),
      // Phase B4 — enforce free-tier 100-invoice cumulative cap.
      freeQuotaService: sl<FreeQuotaService>(),
      cashierShiftService: sl<CashierShiftService>(),
    ),
  );

  // Phase 15.0 — cheque lifecycle JE wiring. Orchestrates `cleared` /
  // `bounced` / `cancelled` transitions across the cheque_confirmations
  // DAO + the matching Purchase / Sale payment SoT, so a confirmed
  // cheque actually settles the AP/AR balance + posts the Dr/Cr Bank
  // journal entry.
  sl.registerLazySingleton(
    () => ChequeLifecycleService(
      db: sl<AppDatabase>(),
      confirmationDao: sl<ChequeConfirmationDao>(),
      purchaseRepository: sl<PurchaseRepository>(),
      saleRepository: sl<SaleRepository>(),
    ),
  );

  // Customers
  sl.registerLazySingleton<CustomerLocalDatasource>(
    () => CustomerLocalDatasourceImpl(sl<CustomerDao>()),
  );
  sl.registerLazySingleton<CustomerRepository>(
    () => CustomerRepositoryImpl(
      sl<CustomerLocalDatasource>(),
      sl<AuditLogService>(),
      sl<SessionService>(),
      sl<JournalEntryService>(),
      sl<AppDatabase>(),
    ),
  );
  sl.registerLazySingleton<LoyaltyRepository>(
    () => LoyaltyRepositoryImpl(sl<AppDatabase>(), sl<JournalEntryService>()),
  );

  // Suppliers
  sl.registerLazySingleton<SupplierLocalDatasource>(
    () => SupplierLocalDatasourceImpl(sl<SupplierDao>()),
  );
  sl.registerLazySingleton<SupplierRepository>(
    () => SupplierRepositoryImpl(
      sl<SupplierLocalDatasource>(),
      sl<SessionService>(),
      sl<JournalEntryService>(),
      sl<AppDatabase>(),
      sl<AuditLogService>(),
    ),
  );

  // Employees
  sl.registerLazySingleton<EmployeeRepository>(
    () => EmployeeRepositoryImpl(sl<EmployeeDao>(), sl<JournalEntryService>()),
  );
  sl.registerLazySingleton<AttendanceService>(
    () => AttendanceService(sl<EmployeeDao>()),
  );

  // Blocs
  sl.registerFactory(() => ThemeBloc(sl()));
  sl.registerFactory(() => LocalizationBloc(sl()));
  sl.registerFactory(() => CurrencyBloc(sl<CurrencyService>()));
  // AuthBloc must be singleton so router and widgets share the same instance
  sl.registerLazySingleton(() => AuthBloc(repository: sl()));
  sl.registerFactory(() => UsersBloc(sl<UserRepositoryInterface>()));
  sl.registerFactory(() => UserStatsBloc(sl<UserRepositoryInterface>()));
  sl.registerFactory(() => UserFormBloc(sl<UserRepositoryInterface>()));

  // Import Products Services
  sl.registerLazySingleton<ParseImportFile>(() => FileImportService());
  sl.registerLazySingleton<ValidateImportData>(
    () => ImportValidationService(sl<ProductRepository>()),
  );
  sl.registerLazySingleton<ImportProducts>(
    () => ProductImportService(
      sl<ProductRepository>(),
      sl<ProductVariantRepository>(),
      sl<CategoryRepository>(),
    ),
  );

  // Export Products Services
  sl.registerLazySingleton<ExportService>(
    () => ExportServiceImpl(
      sl<ProductRepository>(),
      sl<ProductVariantRepository>(),
      sl<CategoryRepository>(),
    ),
  );

  // Feature Blocs
  sl.registerFactory(() => ProductsBloc(sl()));
  sl.registerFactory(
    () => ProductFormBloc(
      sl<ProductRepository>(),
      sl<ProductVariantRepository>(),
    ),
  );
  sl.registerFactory(() => ProductVariantsBloc(sl<ProductVariantRepository>()));
  sl.registerFactory(
    () => BulkProductBloc(
      sl<ProductRepository>(),
      sl<ProductVariantRepository>(),
    ),
  );
  sl.registerFactory(
    () =>
        EditPricesBloc(sl<ProductRepository>(), sl<ProductVariantRepository>()),
  );
  sl.registerFactory(() => CategoriesBloc(sl<CategoryRepository>()));
  sl.registerFactory(() => ColorsBloc(sl<ProductColorRepository>()));
  sl.registerFactory(() => SizesBloc(sl<SizeRepository>()));
  sl.registerFactory(
    () => VariantSummariesBloc(sl<ProductVariantRepository>()),
  );
  sl.registerFactory(() => VariantPreviewsBloc(sl<ProductVariantRepository>()));
  sl.registerFactory(() => ExpirySummariesBloc(sl<ProductRepository>()));
  sl.registerFactory(
    () => ImportProductsBloc(
      parseImportFile: sl<ParseImportFile>(),
      validateImportData: sl<ValidateImportData>(),
      importProducts: sl<ImportProducts>(),
      currencyService: sl<CurrencyService>(),
    ),
  );
  sl.registerFactory(() => ExportBloc(sl<ExportService>()));

  // Purchases Blocs
  sl.registerFactory(() => PurchasesBloc(sl<PurchaseRepository>()));
  sl.registerFactory(
    () => PurchaseFormBloc(
      sl<PurchaseRepository>(),
      sl<ProductVariantRepository>(),
      sl<ProductRepository>(),
    ),
  );
  sl.registerFactory(() => PurchaseReturnsBloc(sl<PurchaseRepository>()));
  sl.registerFactory(() => PurchaseReturnFormBloc(sl<PurchaseRepository>()));

  // Sales Blocs
  sl.registerFactory(() => SalesBloc(sl<SaleRepository>()));
  sl.registerFactory(
    () => SaleFormBloc(
      sl<SaleRepository>(),
      sl<ProductVariantRepository>(),
      sl<ProductRepository>(),
      sl<AuditLogService>(),
      belowCostService: sl<BelowCostSaleService>(),
      loyaltyRepository: sl<LoyaltyRepository>(),
    ),
  );
  sl.registerFactory(() => SaleReturnsBloc(sl<SaleRepository>()));
  sl.registerFactory(() => SaleReturnFormBloc(sl<SaleRepository>()));

  // Customers Blocs
  sl.registerFactory(() => CustomersBloc(sl<CustomerRepository>()));
  sl.registerFactory(() => CustomerFormBloc(sl<CustomerRepository>()));
  sl.registerFactory(() => CustomerLoyaltyBloc(sl<LoyaltyRepository>()));
  sl.registerFactory(() => CustomerProfileBloc(sl<CustomerRepository>()));

  // Employees Blocs
  sl.registerFactory(() => EmployeesBloc(sl<EmployeeRepository>()));
  sl.registerFactory(
    () => EmployeeDetailBloc(sl<EmployeeRepository>(), sl<EmployeeDao>()),
  );
  sl.registerFactory(
    () => AttendanceBloc(sl<EmployeeRepository>(), sl<AttendanceService>()),
  );
  sl.registerFactory(() => LeaveRequestsBloc(sl<EmployeeRepository>()));
  sl.registerFactory(() => PayrollBloc(sl<EmployeeRepository>()));
  sl.registerFactory(() => RolesBloc(sl<EmployeeRepository>()));

  // Suppliers Blocs
  sl.registerFactory(() => SuppliersBloc(sl<SupplierRepository>()));
  sl.registerFactory(() => SupplierFormBloc(sl<SupplierRepository>()));
  sl.registerFactory(() => SupplierProfileBloc(sl<SupplierRepository>()));

  // Expenses
  sl.registerLazySingleton<ExpenseLocalDatasource>(
    () => ExpenseLocalDatasourceImpl(sl<AccountingDao>()),
  );
  sl.registerLazySingleton<ExpenseRepository>(
    () => ExpenseRepositoryImpl(
      sl<ExpenseLocalDatasource>(),
      sl<JournalEntryService>(),
      sl<AuditLogService>(),
      sl<AppDatabase>(),
    ),
  );

  // Expenses Blocs
  sl.registerFactory(() => ExpensesBloc(sl<ExpenseRepository>()));
  sl.registerFactory(() => ExpenseFormBloc(sl<ExpenseRepository>()));
  sl.registerFactory(() => ExpenseCategoriesBloc(sl<ExpenseRepository>()));

  // Accounting / Journal Entries
  sl.registerLazySingleton<JournalLocalDatasource>(
    () => JournalLocalDatasourceImpl(sl<AccountingDao>()),
  );
  sl.registerLazySingleton<JournalRepository>(
    () => JournalRepositoryImpl(
      sl<JournalLocalDatasource>(),
      sl<AccountingRepository>(),
    ),
  );

  // Accounting Blocs
  sl.registerFactory(() => AccountsBloc(sl<JournalRepository>()));
  sl.registerFactory(
    () => AccountingPeriodsBloc(
      sl<JournalRepository>(),
      sl<AppDatabase>(),
      sl<AuditLogService>(),
      sl<AccountingCloseService>(),
      sl<SessionService>(),
    ),
  );
  sl.registerFactory(() => JournalEntriesBloc(sl<JournalRepository>()));
  sl.registerFactory(() => JournalEntryFormBloc(sl<JournalRepository>()));

  // Report blocs - use defaultDateRange from AppSettings
  sl.registerFactory(() {
    final defaultRange =
        sl<AppSettingsBloc>().state.settings.defaultReportDateRange;
    return ReportsBloc(
      sl<JournalRepository>(),
      sl<AppDatabase>(),
      defaultDateRange: defaultRange,
    );
  });
  sl.registerFactory(() {
    final defaultRange =
        sl<AppSettingsBloc>().state.settings.defaultReportDateRange;
    return InventoryReportsBloc(
      sl<AppDatabase>(),
      defaultDateRange: defaultRange,
    );
  });
  sl.registerFactory(() {
    final defaultRange =
        sl<AppSettingsBloc>().state.settings.defaultReportDateRange;
    return ProductMovementDetailBloc(
      sl<AppDatabase>(),
      defaultDateRange: defaultRange,
    );
  });
  sl.registerFactory(() {
    final defaultRange =
        sl<AppSettingsBloc>().state.settings.defaultReportDateRange;
    return StockMovementReportBloc(
      sl<AppDatabase>(),
      defaultDateRange: defaultRange,
    );
  });
  sl.registerFactory(() {
    final defaultRange =
        sl<AppSettingsBloc>().state.settings.defaultReportDateRange;
    return ProductVariantMovementBloc(
      sl<AppDatabase>(),
      defaultDateRange: defaultRange,
    );
  });
  sl.registerFactory(() {
    final defaultRange =
        sl<AppSettingsBloc>().state.settings.defaultReportDateRange;
    return CategoryMovementBloc(
      sl<AppDatabase>(),
      defaultDateRange: defaultRange,
    );
  });
  sl.registerFactory(() {
    final defaultRange =
        sl<AppSettingsBloc>().state.settings.defaultReportDateRange;
    return CustomerReportsBloc(
      sl<AppDatabase>(),
      defaultDateRange: defaultRange,
    );
  });
  sl.registerFactory(() {
    final defaultRange =
        sl<AppSettingsBloc>().state.settings.defaultReportDateRange;
    return CustomerSalesReturnsBloc(
      sl<AppDatabase>(),
      defaultDateRange: defaultRange,
    );
  });
  sl.registerFactory(() {
    final defaultRange =
        sl<AppSettingsBloc>().state.settings.defaultReportDateRange;
    return TopCustomersBloc(sl<AppDatabase>(), defaultDateRange: defaultRange);
  });
  sl.registerFactory(() {
    final defaultRange =
        sl<AppSettingsBloc>().state.settings.defaultReportDateRange;
    return CustomerPaymentReportsBloc(
      sl<AppDatabase>(),
      defaultDateRange: defaultRange,
    );
  });
  sl.registerFactory(() {
    final defaultRange =
        sl<AppSettingsBloc>().state.settings.defaultReportDateRange;
    return CustomerSalesReportBloc(
      sl<AppDatabase>(),
      defaultDateRange: defaultRange,
    );
  });
  sl.registerFactory(() {
    final defaultRange =
        sl<AppSettingsBloc>().state.settings.defaultReportDateRange;
    return CustomerAgingReportBloc(
      sl<AppDatabase>(),
      defaultDateRange: defaultRange,
    );
  });
  sl.registerFactory(() {
    final defaultRange =
        sl<AppSettingsBloc>().state.settings.defaultReportDateRange;
    return CustomerStatementReportBloc(
      sl<AppDatabase>(),
      defaultDateRange: defaultRange,
    );
  });
  sl.registerFactory(() {
    final defaultRange =
        sl<AppSettingsBloc>().state.settings.defaultReportDateRange;
    return CustomerAnalysisReportBloc(
      sl<AppDatabase>(),
      defaultDateRange: defaultRange,
    );
  });
  sl.registerFactory(() {
    final defaultRange =
        sl<AppSettingsBloc>().state.settings.defaultReportDateRange;
    return SupplierBalanceReportBloc(
      sl<AppDatabase>(),
      defaultDateRange: defaultRange,
    );
  });
  sl.registerFactory(() {
    final defaultRange =
        sl<AppSettingsBloc>().state.settings.defaultReportDateRange;
    return SupplierDebitBalanceReportBloc(
      sl<AppDatabase>(),
      defaultDateRange: defaultRange,
    );
  });
  sl.registerFactory(() {
    final defaultRange =
        sl<AppSettingsBloc>().state.settings.defaultReportDateRange;
    return SupplierCreditBalanceReportBloc(
      sl<AppDatabase>(),
      defaultDateRange: defaultRange,
    );
  });
  sl.registerFactory(() {
    final defaultRange =
        sl<AppSettingsBloc>().state.settings.defaultReportDateRange;
    return SupplierAnalysisReportBloc(
      sl<AppDatabase>(),
      defaultDateRange: defaultRange,
    );
  });
  sl.registerFactory(() {
    final defaultRange =
        sl<AppSettingsBloc>().state.settings.defaultReportDateRange;
    return SupplierAgingReportBloc(
      sl<AppDatabase>(),
      defaultDateRange: defaultRange,
    );
  });
  sl.registerFactory(() {
    final defaultRange =
        sl<AppSettingsBloc>().state.settings.defaultReportDateRange;
    return SupplierStatementReportBloc(
      sl<AppDatabase>(),
      defaultDateRange: defaultRange,
    );
  });
  sl.registerFactory(() {
    final defaultRange =
        sl<AppSettingsBloc>().state.settings.defaultReportDateRange;
    return SupplierLedgerReportBloc(
      sl<AppDatabase>(),
      defaultDateRange: defaultRange,
    );
  });
  sl.registerFactory(() {
    final defaultRange =
        sl<AppSettingsBloc>().state.settings.defaultReportDateRange;
    return CustomerLedgerReportBloc(
      sl<AppDatabase>(),
      defaultDateRange: defaultRange,
    );
  });
  sl.registerFactory(() {
    final defaultRange =
        sl<AppSettingsBloc>().state.settings.defaultReportDateRange;
    return CustomerInvoicesReportBloc(
      sl<AppDatabase>(),
      defaultDateRange: defaultRange,
    );
  });
  sl.registerFactory(() {
    final defaultRange =
        sl<AppSettingsBloc>().state.settings.defaultReportDateRange;
    return SupplierInvoicesReportBloc(
      sl<AppDatabase>(),
      defaultDateRange: defaultRange,
    );
  });
  sl.registerFactory(() {
    final defaultRange =
        sl<AppSettingsBloc>().state.settings.defaultReportDateRange;
    return SupplierReturnsReportBloc(
      sl<AppDatabase>(),
      defaultDateRange: defaultRange,
    );
  });
  sl.registerFactory(() {
    final defaultRange =
        sl<AppSettingsBloc>().state.settings.defaultReportDateRange;
    return SupplierStocktakeReportBloc(
      sl<AppDatabase>(),
      defaultDateRange: defaultRange,
    );
  });
  sl.registerFactory(() {
    final defaultRange =
        sl<AppSettingsBloc>().state.settings.defaultReportDateRange;
    return SupplierBalanceDrilldownBloc(
      sl<AppDatabase>(),
      defaultDateRange: defaultRange,
    );
  });
  sl.registerFactory(() {
    final defaultRange =
        sl<AppSettingsBloc>().state.settings.defaultReportDateRange;
    return SalespeopleCommissionReportBloc(
      sl<AppDatabase>(),
      defaultDateRange: defaultRange,
    );
  });
  sl.registerFactory(() {
    final defaultRange =
        sl<AppSettingsBloc>().state.settings.defaultReportDateRange;
    return ExpenseReportBloc(sl<AppDatabase>(), defaultDateRange: defaultRange);
  });
  sl.registerFactory(() {
    final defaultRange =
        sl<AppSettingsBloc>().state.settings.defaultReportDateRange;
    return SalesTaxReportBloc(
      sl<AppDatabase>(),
      defaultDateRange: defaultRange,
    );
  });
  sl.registerFactory(() {
    final defaultRange =
        sl<AppSettingsBloc>().state.settings.defaultReportDateRange;
    return PurchaseTaxReportBloc(
      sl<AppDatabase>(),
      defaultDateRange: defaultRange,
    );
  });
  sl.registerFactory(() {
    final defaultRange =
        sl<AppSettingsBloc>().state.settings.defaultReportDateRange;
    return SalesReportsBloc(sl<AppDatabase>(), defaultDateRange: defaultRange);
  });
  sl.registerFactory(() {
    final defaultRange =
        sl<AppSettingsBloc>().state.settings.defaultReportDateRange;
    return PurchaseReportsBloc(
      sl<AppDatabase>(),
      defaultDateRange: defaultRange,
    );
  });
  sl.registerFactory(() {
    final defaultRange =
        sl<AppSettingsBloc>().state.settings.defaultReportDateRange;
    return DiscountReportsBloc(
      sl<AppDatabase>(),
      defaultDateRange: defaultRange,
    );
  });
  sl.registerFactory(() {
    final defaultRange =
        sl<AppSettingsBloc>().state.settings.defaultReportDateRange;
    return ProfitReportsBloc(sl<AppDatabase>(), defaultDateRange: defaultRange);
  });

  // Ledger Rebuild Service
  sl.registerLazySingleton<LedgerRebuildService>(
    () => LedgerRebuildService(
      db: sl<AppDatabase>(),
      accountingRepo: sl<AccountingRepository>(),
      journalService: sl<JournalEntryService>(),
    ),
  );

  // Barcode Services
  // Crashlytics Service (singleton instance)
  sl.registerLazySingleton(() => CrashlyticsService.instance);

  sl.registerLazySingleton(() => BarcodeValidationService());
  sl.registerLazySingleton(() => BarcodeGenerationService());
  sl.registerLazySingleton(() => BarcodePrinterService(settingsDao: sl()));

  // Settings Services
  sl.registerLazySingleton(() => CompanyProfileService(sl()));
  sl.registerLazySingleton(() => AppSettingsService(sl()));

  // Inventory Valuation Service — single source of truth for the
  // business-wide inventory valuation method (WAC | FIFO). Lives in the
  // settings cluster because it reads/writes a single row in app_settings.
  sl.registerLazySingleton(() => InventoryValuationService(sl<SettingsDao>()));

  // Expiry Alert Service — single owner of the SQL that powers the Phase E
  // dashboard widget AND the full report screen. Both surfaces render
  // identical numbers because they read through the same service stream.
  sl.registerLazySingleton(() => ExpiryAlertService(sl<AppDatabase>()));
  sl.registerFactory(() => ExpiryAlertsBloc(sl<ExpiryAlertService>()));

  // Settings Blocs
  sl.registerFactory(() => CompanyBloc(sl<CompanyProfileService>()));
  sl.registerLazySingleton(() => AppSettingsBloc(sl<AppSettingsService>()));

  // Security & Licensing Services
  sl.registerLazySingleton(() => DeviceFingerprintService());
  sl.registerLazySingleton(
    () => LicenseService(fingerprintService: sl<DeviceFingerprintService>()),
  );
  sl.registerLazySingleton(() => ConnectivityService());
  sl.registerLazySingleton(() => RemoteSecurityService());
  sl.registerLazySingleton(() => CodeIntegrityService());

  // RevenueCat / Subscription / AppGuard
  sl.registerLazySingleton(() => RevenueCatService.instance);
  sl.registerLazySingleton(
    () => AppGuardService(
      revenueCat: sl<RevenueCatService>(),
      licenseService: sl<LicenseService>(),
      fingerprintService: sl<DeviceFingerprintService>(),
      connectivityService: sl<ConnectivityService>(),
      remoteSecurityService: sl<RemoteSecurityService>(),
      codeIntegrityService: sl<CodeIntegrityService>(),
    ),
  );
  sl.registerLazySingleton(
    () => SubscriptionBloc(
      revenueCatService: sl<RevenueCatService>(),
      appGuardService: sl<AppGuardService>(),
    ),
  );
  sl.registerLazySingleton(
    () => FeatureGateService(revenueCatService: sl<RevenueCatService>()),
  );
  sl.registerLazySingleton(
    () => FreeQuotaService(
      prefs: sl<SharedPreferences>(),
      featureGateService: sl<FeatureGateService>(),
    ),
  );

  // Configure SessionService to use AppSettings for timeout
  sl<SessionService>().configureTimeoutSettings(() {
    final settings = sl<AppSettingsBloc>().state.settings;
    return (
      enabled: settings.enableSessionTimeout,
      timeoutMinutes: settings.sessionTimeoutMinutes,
      rememberMeDurationHours: settings.rememberMeDurationHours,
    );
  });

  // Barcode Blocs
  sl.registerFactory(
    () => BarcodeScannerBloc(productRepository: sl(), validationService: sl()),
  );
  sl.registerFactory(
    () => BarcodeDesignBloc(
      templateDao: sl<BarcodeTemplateDao>(),
      printerService: sl<BarcodePrinterService>(),
      companyProfileService: sl<CompanyProfileService>(),
      productVariantDao: sl<ProductVariantDao>(),
      appSettings: sl<AppSettingsBloc>().state.settings,
    ),
  );

  // ONE-TIME REPAIR: Fix journal entries (draft purchase orphans + overpayments).
  // Uses a SharedPreferences flag to ensure it only runs once per version.
  const repairKey = 'overpayment_journal_repair_done_v2';
  if (!sharedPreferences.containsKey(repairKey)) {
    try {
      final repaired = await sl<JournalEntryService>()
          .repairOverpaymentJournalEntries();
      await sharedPreferences.setBool(repairKey, true);
      debugPrint(
        'Overpayment journal repair complete: $repaired entries fixed',
      );
    } catch (e, st) {
      debugPrint(
        'Overpayment journal repair failed (will retry next launch): $e',
      );
      debugPrint('$st');
    }
  }
}
