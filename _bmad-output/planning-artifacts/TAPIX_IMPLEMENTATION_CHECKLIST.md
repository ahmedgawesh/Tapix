# TAPIX ERP - Implementation Checklist

> **Purpose**: Track progress during implementation  
> **Usage**: Check off items as you complete them  
> **Status**: ACTIVE

---

## PHASE 0: TECH STACK VALIDATION

### Dependencies to Verify

- [ ] **flutter_bloc** (8.1.4+)
  - [ ] Check pub.dev for latest version
  - [ ] Verify last update date ≤ 3 months
  - [ ] Test on Android
  - [ ] Test on iOS
  - [ ] Test on Windows
  - [ ] Test on Web
  - [ ] Test on Linux
  - [ ] Test on macOS

- [x] **drift** (2.23.0+) - BEST CHOICE FOR ERP
  - [x] Check pub.dev for latest version
  - [x] Verify last update date ≤ 3 months
  - [x] Test on Android
  - [ ] Test on iOS
  - [ ] Test on Windows
  - [x] Test on Web (WASM + IndexedDB working)
  - [x] Test on Linux
  - [ ] Test on macOS

- [ ] **go_router** (14.0.0+)
  - [ ] Check pub.dev
  - [ ] Verify compatibility

- [ ] **flex_color_scheme** (7.3.0+)
  - [ ] Check pub.dev
  - [ ] Test light theme
  - [ ] Test dark theme

- [ ] **easy_localization** (3.0.7+)
  - [ ] Check pub.dev
  - [ ] Test RTL (Arabic)
  - [ ] Test LTR (English, French)

- [ ] **printing** (5.11.0+)
  - [ ] Check pub.dev
  - [ ] Test PDF generation
  - [ ] Test printing on Windows
  - [ ] Test printing on Android
  - [ ] Test sharing on mobile

- [ ] **pdf** (3.10.0+)
  - [ ] Check pub.dev
  - [ ] Test Arabic font embedding
  - [ ] Test RTL layout

- [x] **Money class** (custom with int cents) - PERFECT FOR ERP
  - [x] Check pub.dev
  - [x] Test precision with large numbers

- [ ] **share_plus** (7.2.0+)
  - [ ] Check pub.dev
  - [ ] Test on all platforms

- [ ] **mobile_scanner** (4.0.0+)
  - [ ] Check pub.dev
  - [ ] Test on Android
  - [ ] Test on iOS

- [ ] **workmanager** (0.5.2+)
  - [ ] Check pub.dev
  - [ ] Test background tasks on Android
  - [ ] Test background tasks on iOS

- [ ] **responsive_framework** (1.1.0+)
  - [ ] Check pub.dev
  - [ ] Test on mobile
  - [ ] Test on tablet
  - [ ] Test on desktop

- [ ] **fl_chart** (0.66.0+)
  - [ ] Check pub.dev
  - [ ] Test chart rendering

### Validation Report

- [ ] Create tech-stack-validation-report.md
- [ ] Get user approval before proceeding

---

## PHASE 1: PROJECT BOOTSTRAP

### Project Setup

- [ ] Create new Flutter project: `flutter create tapix`
- [ ] Configure pubspec.yaml with all dependencies
- [ ] Run `flutter pub get`
- [ ] Verify no dependency conflicts

### Folder Structure

- [ ] Create `lib/core/` folder structure
  - [ ] `lib/core/bloc/`
  - [ ] `lib/core/database/`
  - [ ] `lib/core/router/`
  - [ ] `lib/core/services/`
  - [ ] `lib/core/theme/`
  - [ ] `lib/core/widgets/`
  - [ ] `lib/core/utils/`
  - [ ] `lib/core/localization/`

- [ ] Create `lib/features/` folder structure
  - [ ] `lib/features/auth/`
  - [ ] `lib/features/dashboard/`
  - [ ] `lib/features/products/`
  - [ ] `lib/features/customers/`
  - [ ] `lib/features/suppliers/`
  - [ ] `lib/features/sales/`
  - [ ] `lib/features/purchases/`
  - [ ] `lib/features/reports/`
  - [ ] `lib/features/settings/`
  - [ ] `lib/features/expenses/`
  - [ ] `lib/features/employees/`
  - [ ] `lib/features/users/`
  - [ ] `lib/features/accounting/`
  - [ ] `lib/features/notifications/`
  - [ ] `lib/features/database/`

### Database Setup

- [x] Define Drift tables for Products, Customers, Sales
- [x] Generate Drift files
- [x] Test database initialization
- [ ] Create seed data for development
- [x] Setup reactive streams for real-time updates
- [x] Configure Web WASM support (sqlite3.wasm + drift_worker.dart.js)
- [x] Test cross-platform compatibility (Android/Linux/Web)

### Theme Setup

- [ ] Configure light theme with flex_color_scheme
- [ ] Configure dark theme with flex_color_scheme
- [ ] Create theme toggle functionality
- [ ] Test theme persistence

### Localization Setup

- [ ] Create `assets/translations/en.json`
- [ ] Create `assets/translations/ar.json`
- [ ] Create `assets/translations/fr.json`
- [ ] Configure easy_localization
- [ ] Test language switching
- [ ] Test RTL layout

### Router Setup

- [ ] Configure GoRouter with all routes
- [ ] Implement route guards for authentication
- [ ] Implement role-based route access
- [ ] Test deep linking

---

## PHASE 2: CORE INFRASTRUCTURE

### Real-Time Service

- [x] Implement Drift reactive streams
- [x] Create base reactive Bloc class
- [x] Test automatic UI updates on data change
- [x] Verify no manual refresh needed
- [x] Test real-time updates across all platforms (Web included)

### Money Calculation Service

- [ ] Implement MoneyCalculationService
- [ ] Implement SaleDraftTotalsCalculator
- [ ] Implement PurchaseDraftTotalsCalculator
- [ ] Implement CustomerBalanceCalculator
- [ ] Write unit tests for all calculations
- [ ] Test with edge cases (large numbers, decimals)

### PDF Service

- [ ] Create PDF service skeleton
- [ ] Implement invoice PDF template
- [ ] Implement report PDF template
- [ ] Implement thermal receipt template
- [ ] Test Arabic font embedding
- [ ] Test RTL layout in PDFs

### Core Widgets

- [ ] Implement MainNavigationDrawer
- [ ] Implement GlobalAppBar
- [ ] Implement DateRangeFilter
- [ ] Implement ReportActionButtons
- [ ] Implement AppButton
- [ ] Implement LoadingIndicator
- [ ] Implement EmptyState
- [ ] Implement ErrorState

---

## PHASE 3: AUTH MODULE

### Screens

- [ ] WelcomeScreen
  - [ ] UI implementation
  - [ ] Navigation to login/create admin
  - [ ] First-time setup detection

- [ ] LoginScreen
  - [ ] UI implementation
  - [ ] Form validation
  - [ ] Login logic
  - [ ] Error handling
  - [ ] Remember me functionality

- [ ] CreateAdminScreen
  - [ ] UI implementation
  - [ ] Admin creation logic
  - [ ] Password validation

### Business Logic

- [ ] AuthBloc implementation
- [ ] Session management
- [ ] Role-based access control
- [ ] Auto-logout on inactivity
- [ ] Password hashing

### Testing

- [ ] Unit tests for AuthBloc
- [ ] Widget tests for screens
- [ ] Integration test for login flow

---

## PHASE 4: PRODUCTS MODULE

### Screens

- [ ] ProductsMainScreen
- [x] ProductsScreen (list with search/filter/pagination)
- [ ] ProductFormScreen (add/edit)
- [ ] BulkProductFormScreen
- [ ] EditPricesScreen
- [ ] ImportProductsScreen
- [ ] SimpleExportScreen
- [ ] BarcodeDesignScreen
- [ ] CategoriesScreen
- [ ] ColorsScreen
- [ ] SizesScreen

### Features

- [x] Product CRUD operations
- [ ] Barcode scanning
- [ ] Category management
- [ ] Color management
- [ ] Size management
- [ ] Variant management
- [ ] Import from CSV/Excel
- [ ] Export to CSV/Excel
- [ ] Barcode label printing
- [x] Real-time stock updates

### Testing

- [ ] Unit tests for ProductBloc
- [ ] Widget tests for key screens
- [ ] Test on all platforms

---

## PHASE 5: CUSTOMERS & SUPPLIERS

### Customer Module

- [ ] CustomersScreen
- [ ] CustomerFormScreen
- [ ] CustomerProfileScreen
- [ ] CustomerPaymentDialog
- [ ] Customer CRUD operations
- [ ] Balance tracking
- [ ] Transaction ledger

### Supplier Module

- [ ] SuppliersScreen
- [ ] SupplierFormScreen
- [ ] SupplierProfileScreen
- [ ] SupplierSeasonalDiscountScreen
- [ ] SupplierTransactionDetailScreen
- [ ] SupplierPaymentDialog
- [ ] SupplierDiscountDialog
- [ ] SupplierReturnDialog
- [ ] Supplier CRUD operations
- [ ] Balance tracking
- [ ] Transaction ledger

---

## PHASE 6: SALES MODULE

### Screens

- [ ] SalesScreen (list with filters)
- [ ] SaleFormScreen (full POS)
- [ ] SaleReturnsScreen
- [ ] SaleReturnFormScreen

### Dialogs

- [ ] SaleProductSelectionDialog
- [ ] SaleProductEditDialog
- [ ] CustomerPaymentDialog
- [ ] InvoiceSplitPaymentDialog
- [ ] CustomerSettlementDialog
- [ ] VoidInvoiceDialog
- [ ] SaleInvoicePrintDialog
- [ ] SaleReturnPrintDialog
- [ ] QuickSaleSummaryDialog

### Features

- [ ] Product search in sale form
- [ ] Barcode scanning
- [ ] Customer selection
- [ ] Salesperson assignment
- [ ] Line item management
- [ ] Discount handling (line & invoice level)
- [ ] Tax calculation
- [ ] Multiple payment methods
- [ ] Split payment
- [ ] Change calculation
- [ ] Overpayment handling
- [ ] Invoice printing
- [ ] Invoice sharing
- [ ] Sale returns with refund
- [ ] Inventory auto-update
- [ ] Customer balance auto-update
- [ ] Accounting entries auto-generated

### Testing

- [ ] Unit tests for sale calculations
- [ ] Widget tests for sale form
- [ ] Integration test for full sale flow
- [ ] Test on all platforms

---

## PHASE 7: PURCHASES MODULE

### Screens

- [ ] PurchasesScreen
- [ ] PurchaseFormScreen
- [ ] PurchaseDetailScreen
- [ ] PurchaseReturnsScreen
- [ ] PurchaseReturnFormScreen
- [ ] PurchaseReturnDetailScreen

### Dialogs

- [ ] ProductSelectionDialog
- [ ] ProductEditDialog
- [ ] SupplierPaymentDialog
- [ ] SupplierRefundDialog
- [ ] PurchaseBarcodeScanner

### Features

- [ ] Supplier selection
- [ ] Product selection
- [ ] Line item management
- [ ] Discount handling
- [ ] Tax handling
- [ ] Payment to supplier
- [ ] Purchase returns
- [ ] Inventory auto-update
- [ ] Supplier balance auto-update
- [ ] Accounting entries auto-generated

---

## PHASE 8: EXPENSES & ACCOUNTING

### Expenses Module

- [ ] ExpensesScreen
- [ ] ExpenseFormScreen
- [ ] ExpenseCategoriesScreen
- [ ] Expense CRUD operations
- [ ] Category management
- [ ] Receipt image storage

### Accounting Module

- [ ] JournalEntriesListScreen
- [ ] JournalEntryFormScreen
- [ ] JournalEntryDetailScreen
- [ ] Chart of accounts initialization
- [ ] Manual journal entry creation
- [ ] Accounting period management
- [ ] Auto-generated entries verification

---

## PHASE 9: REPORTS

### Financial Reports

- [ ] FinancialStatementsScreen
- [ ] ProfitLossReportScreen
- [ ] BalanceSheetReportScreen
- [ ] TrialBalanceReportScreen
- [ ] GeneralLedgerReportScreen
- [ ] CashFlowReportScreen
- [ ] TaxReportScreen
- [ ] SalesSummaryReportScreen

### Inventory Reports

- [ ] InventoryStockReportScreen
- [ ] LowStockReportScreen
- [ ] OutOfStockReportScreen
- [ ] DeadStockReportScreen
- [ ] CategoryStocktakeReportScreen
- [ ] ProductMovementReportScreen

### Customer Reports

- [ ] CustomerAgingReportScreen
- [ ] CustomerStatementReportScreen
- [ ] CustomerAnalysisReportScreen
- [ ] CustomerPaymentReportScreen
- [ ] CustomerSalesReportScreen
- [ ] CustomerSalesReturnsReportScreen
- [ ] TopCustomersReportScreen

### Supplier Reports

- [ ] SupplierBalanceReportScreen
- [ ] SupplierDebitBalanceReportScreen
- [ ] SupplierCreditBalanceReportScreen
- [ ] SupplierAnalysisReportScreen
- [ ] SupplierAgingReportScreen
- [ ] SupplierStatementReportScreen
- [ ] SupplierStocktakeReportScreen
- [ ] SupplierBalanceDrilldownScreen

### Other Reports

- [ ] SalespeopleReportScreen
- [ ] CommissionsReportScreen
- [ ] ExpenseReportScreen
- [ ] VoidLogsReportScreen
- [ ] ReconciliationDiagnosticsScreen

### Report Features (ALL)

- [ ] Date range filter
- [ ] PDF export (AR/EN/FR)
- [ ] Excel/CSV export
- [ ] Share functionality
- [ ] Print functionality

---

## PHASE 10: SETTINGS & ADMIN

### Settings

- [ ] SettingsScreen
- [ ] CurrencySettingsScreen
- [ ] SecuritySettingsScreen
- [ ] PrintingSettingsScreen

### Database Management

- [ ] DatabaseManagementScreen
- [ ] DatabaseHealthScreen
- [ ] AuditLogScreen
- [ ] Backup functionality
- [ ] Restore functionality
- [ ] Reset functionality

### Admin Tools

- [ ] SupplierBalanceFixScreen
- [ ] MismatchDetectionScreen
- [ ] Balance rebuild functionality

---

## PHASE 11: DASHBOARD & POLISH

### Dashboard

- [ ] DashboardScreen
- [ ] Today's sales KPI card
- [ ] Weekly sales chart
- [ ] Monthly sales chart
- [ ] Low stock alerts
- [ ] Recent transactions
- [ ] Quick "New Sale" FAB
- [ ] Store logo display

### Notifications

- [ ] NotificationsScreen
- [ ] Low stock notifications
- [ ] Payment due notifications
- [ ] In-app notification badge

### Final Polish

- [ ] Consistent styling across all screens
- [ ] Loading states
- [ ] Empty states
- [ ] Error states
- [ ] Animations/transitions
- [ ] Performance optimization

---

## PHASE 12: TESTING & QA

### Unit Tests

- [ ] All calculation services
- [ ] All business logic
- [ ] All Blocs

### Widget Tests

- [ ] Key screens
- [ ] Complex dialogs
- [ ] Form validation

### Integration Tests

- [ ] Login flow
- [ ] Sale flow
- [ ] Purchase flow
- [ ] Return flow

### Platform Testing

- [x] Android (physical device)
- [ ] iOS (physical device)
- [ ] Windows
- [x] Web (Chrome, Firefox) - FIXED: WASM + IndexedDB working
- [x] Linux
- [ ] macOS

### Language Testing

- [ ] English - all screens
- [ ] Arabic - all screens (RTL)
- [ ] French - all screens

### Performance Testing

- [ ] 1,000 products
- [ ] 10,000 products
- [ ] 1,000 sales
- [ ] 10,000 sales

---

## FINAL CHECKLIST

Before declaring the project complete:

- [ ] All features from TAPIX_REBUILD_SPECIFICATION.md implemented
- [ ] All screens from TAPIX_TECHNICAL_INVENTORY.md implemented
- [ ] All dialogs from inventory implemented
- [ ] All reports with PDF/Excel export
- [ ] Real-time updates working everywhere
- [ ] No overflow on any screen size
- [ ] Light theme working
- [ ] Dark theme working
- [ ] Arabic localization complete
- [ ] English localization complete
- [ ] French localization complete
- [ ] All platforms tested
- [ ] Performance acceptable
- [ ] No critical bugs

---

**Document End**
