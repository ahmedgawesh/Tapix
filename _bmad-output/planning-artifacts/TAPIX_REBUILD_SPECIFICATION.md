# TAPIX ERP - Complete Rebuild Specification

> **Document Version**: 1.0  
> **Created**: January 2026  
> **Purpose**: Official reference for rebuilding Tapix ERP from scratch  
> **Language**: English (for technical accuracy)  
> **Status**: ACTIVE - Follow this document exactly

---

## TABLE OF CONTENTS

1. [Project Overview](#1-project-overview)
2. [Critical Requirements](#2-critical-requirements)
3. [Technical Architecture](#3-technical-architecture)
4. [Technology Stack](#4-technology-stack)
5. [Complete Feature Inventory](#5-complete-feature-inventory)
6. [Reports Inventory](#6-reports-inventory)
7. [Dialogs & Workflows Inventory](#7-dialogs--workflows-inventory)
8. [Core Services Inventory](#8-core-services-inventory)
9. [Database Schema Requirements](#9-database-schema-requirements)
10. [Implementation Phases](#10-implementation-phases)
11. [AI Model Allocation](#11-ai-model-allocation)
12. [Quality Checklist](#12-quality-checklist)
13. [Known Issues to Avoid](#13-known-issues-to-avoid)

---

## 1. PROJECT OVERVIEW

### 1.1 Project Name
**Tapix** (not "Tapix ERP" - cleaner branding)

### 1.2 Project Goal
Rebuild the existing Tapix ERP application from scratch with:
- **Correct implementation** of all existing features
- **Beautiful modern design** with attractive colors
- **Real-time updates** throughout the entire application (NO app restart required)
- **Accurate financial calculations** (100% correct money math)
- **Smooth performance** handling large datasets
- **Multi-platform support** (Windows, Android, iOS, Web, Linux, macOS)

### 1.3 Business Model
- **B2C** (Retail)
- **B2B** (Wholesale)
- **Hybrid** offline-first architecture (Phase 1: Offline-first, Phase 2: Online sync)

### 1.4 Target Markets
- Global (international app stores)
- Primary focus: Arabic-speaking markets, with English and French support

---

## 2. CRITICAL REQUIREMENTS

### 2.1 Non-Negotiable Requirements

| Requirement | Description | Priority |
|------------|-------------|----------|
| **Real-time Updates** | ALL data changes must reflect instantly in UI without app restart | CRITICAL |
| **Offline-First** | App must work 100% offline with local database | CRITICAL |
| **Multi-Platform** | Windows, Android, iOS, Web, Linux, macOS | CRITICAL |
| **3 Languages** | English (primary), Arabic, French | CRITICAL |
| **Semantic Colors** | Red (Error/Destructive), Orange (Warning), Green (Success) | CRITICAL |
| **Light/Dark Themes** | Both themes with beautiful, modern colors | CRITICAL |
| **Responsive Design** | No overflow on ANY screen size (mobile, tablet, desktop) | CRITICAL |
| **Accurate Calculations** | 100% correct money math (use cents/smallest unit) | CRITICAL |
| **PDF Export** | Multi-language PDF for invoices, reports, payments | CRITICAL |
| **Share/Print** | Share to any app, Bluetooth printers | CRITICAL |
| **Large Data Handling** | Must handle thousands of products/transactions smoothly | CRITICAL |
| **Clean Code** | Maintainable, testable, well-structured code | HIGH |

### 2.2 What NOT to Do (Lessons from Current App)

| Problem | Solution |
|---------|----------|
| No real-time updates (requires app restart) | Use Bloc + Database streams/watchers |
| Manual refresh everywhere | Automatic state invalidation on data change |
| Complex spaghetti code | Clean Architecture with clear separation |
| Hardcoded strings | Full localization from day 1 |
| Inconsistent UI | Reusable component library |
| Money calculation errors | Use integer cents, Decimal package |
| Platform-specific bugs | Test on ALL platforms continuously |

---

## 3. TECHNICAL ARCHITECTURE

### 3.1 Architecture Pattern
**Clean Architecture** with the following layers:

```
lib/
├── core/                    # Shared infrastructure
│   ├── database/           # Drift schemas, DAOs
│   ├── bloc/               # Base Bloc classes, mixins
│   ├── services/           # Cross-cutting services (PDF, printing, etc.)
│   ├── widgets/            # Reusable UI components
│   ├── theme/              # Theme configuration
│   ├── localization/       # i18n setup
│   ├── utils/              # Helpers, extensions
│   └── router/             # GoRouter configuration
│
├── features/               # Feature modules (vertical slices)
│   ├── auth/
│   │   ├── data/          # Repositories, data sources
│   │   ├── domain/        # Entities, use cases
│   │   └── presentation/  # Blocs, screens, widgets
│   ├── sales/
│   ├── purchases/
│   ├── products/
│   ├── customers/
│   ├── suppliers/
│   ├── reports/
│   ├── settings/
│   └── ...
│
└── main.dart
```

### 3.2 State Management
**Bloc/Cubit** with the following rules:
- One Bloc per feature/screen
- Use streams for real-time data
- Emit new states on ANY data change
- Never cache stale data

### 3.3 Real-Time Update Architecture

```dart
// CORRECT: Reactive data flow
Database Change → Stream → Bloc → UI Update

// WRONG: Manual refresh
User Action → API Call → Manual setState/refresh
```

**Implementation Pattern:**
```dart
class SalesBloc extends Bloc<SalesEvent, SalesState> {
  final SalesRepository _repository;
  StreamSubscription? _salesSubscription;

  SalesBloc(this._repository) : super(SalesInitial()) {
    // Subscribe to database changes
    _salesSubscription = _repository.watchAllSales().listen((sales) {
      add(SalesUpdated(sales)); // Automatically emit new state
    });
  }

  @override
  Future<void> close() {
    _salesSubscription?.cancel();
    return super.close();
  }
}
```

### 3.4 Money Calculation Rules

**CRITICAL**: All money values stored and calculated in **cents (smallest currency unit)**

```dart
// CORRECT
int priceInCents = 1999; // $19.99
int totalCents = quantity * priceInCents;
String display = (totalCents / 100).toStringAsFixed(2);

// WRONG
double price = 19.99; // NEVER use double for money
```

**Use Decimal package for complex calculations:**
```dart
import 'package:decimal/decimal.dart';

Decimal subtotal = Decimal.parse('100.00');
Decimal discount = Decimal.parse('15.50');
Decimal total = subtotal - discount; // Exact precision
```

---

## 4. TECHNOLOGY STACK

### 4.1 Core Dependencies (MUST VALIDATE BEFORE USE)

| Category | Package | Min Version | Purpose |
|----------|---------|-------------|---------|
| **Framework** | Flutter | 3.24+ | Cross-platform UI |
| **Language** | Dart | 3.5+ | Programming language |
| **State Management** | flutter_bloc | 8.1.4+ | Reactive state management |
| **Local Database** | isar | 4.0.0+ | High-performance NoSQL DB |
| **Router** | go_router | 14.0.0+ | Declarative routing |
| **Theme** | flex_color_scheme | 7.3.0+ | Beautiful theming |
| **Localization** | easy_localization | 3.0.7+ | i18n support |
| **PDF** | printing | 5.11.0+ | PDF generation |
| **PDF Builder** | pdf | 3.10.0+ | PDF document creation |
| **HTTP** | dio | 5.4.0+ | HTTP client (for Phase 2) |
| **Dependency Injection** | get_it | 7.6.0+ | Service locator |
| **Background Sync** | workmanager | 0.5.2+ | Background tasks |
| **Responsive** | responsive_framework | 1.1.0+ | Responsive layouts |
| **Charts** | fl_chart | 0.66.0+ | Data visualization |
| **Barcode** | barcode_widget | 2.0.4+ | Barcode generation |
| **Scanner** | mobile_scanner | 4.0.0+ | Barcode/QR scanning |
| **Share** | share_plus | 7.2.0+ | Share to other apps |
| **Database** | drift (SQLite) | 2.23.0+ | Reactive SQL ORM with Web WASM support |
| **Money** | decimal | 2.3.0+ | Precise decimal math |
| **Icons** | lucide_icons | 0.0.1+ | Modern icons |

### 4.2 Tech Stack Validation Checklist

Before using ANY package, verify:
- [ ] Last update ≤ 3 months ago
- [ ] Active GitHub issues resolution
- [ ] Null-safety support
- [ ] Flutter 3.24+ compatibility
- [ ] All target platforms supported
- [ ] No breaking changes in latest version
- [ ] Comprehensive documentation available

---

## 5. COMPLETE FEATURE INVENTORY

### 5.1 Authentication Module

| Screen | Description | Features |
|--------|-------------|----------|
| `WelcomeScreen` | Initial landing page | App intro, navigation to login/create admin |
| `LoginScreen` | User authentication | Username/password login, remember me |
| `CreateAdminScreen` | First-time setup | Create owner/admin account |

**Business Logic:**
- Role-based access control (Owner, Manager, Cashier, Salesperson)
- Session management with secure storage
- Auto-logout on inactivity (configurable)
- Password hashing (never store plain text)

### 5.2 Dashboard Module

| Screen | Description | Features |
|--------|-------------|----------|
| `DashboardScreen` | Main overview | KPIs, charts, quick actions |

**Dashboard Components:**
- Today's sales summary
- Weekly/monthly sales chart (fl_chart)
- Low stock alerts
- Recent transactions
- Quick "New Sale" FAB
- Store logo display
- Company name from settings

### 5.3 Products Module

| Screen | Description | Features |
|--------|-------------|----------|
| `ProductsMainScreen` | Products hub | Navigation to sub-screens |
| `ProductsScreen` | Product list | Search, filter, sort, bulk actions |
| `ProductFormScreen` | Add/Edit product | All product fields, variants |
| `BulkProductFormScreen` | Bulk add products | Add multiple products at once |
| `EditPricesScreen` | Bulk price edit | Update prices for multiple products |
| `ImportProductsScreen` | Import from file | CSV/Excel import |
| `SimpleExportScreen` | Export products | CSV/Excel export |
| `BarcodeDesignScreen` | Barcode printing | Design and print barcode labels |
| `CategoriesScreen` | Manage categories | CRUD for product categories |
| `ColorsScreen` | Manage colors | CRUD for product colors |
| `SizesScreen` | Manage sizes | CRUD for product sizes |

**Product Fields:**
- Name (localized)
- SKU / Barcode
- Category
- Cost price (cents)
- Selling price (cents)
- Wholesale price (cents)
- Quantity in stock
- Minimum stock level
- Color variants
- Size variants
- Images
- Description
- Active/Inactive status
- Tax applicable (yes/no)
- Tax rate

### 5.4 Customers Module

| Screen | Description | Features |
|--------|-------------|----------|
| `CustomersScreen` | Customer list | Search, filter, add/edit |
| `CustomerFormScreen` | Add/Edit customer | All customer fields |
| `CustomerProfileScreen` | Customer details | Balance, transactions, history |

**Customer Fields:**
- Name
- Phone
- Email
- Address
- Tax ID
- Credit limit (cents)
- Current balance (cents)
- Notes
- Active/Inactive

### 5.5 Suppliers Module

| Screen | Description | Features |
|--------|-------------|----------|
| `SuppliersScreen` | Supplier list | Search, filter, add/edit |
| `SupplierFormScreen` | Add/Edit supplier | All supplier fields |
| `SupplierProfileScreen` | Supplier details | Balance, transactions, purchases |
| `SupplierSeasonalDiscountScreen` | Seasonal discounts | Configure supplier discounts |
| `SupplierTransactionDetailScreen` | Transaction details | View specific transaction |

**Supplier Fields:**
- Name
- Contact person
- Phone
- Email
- Address
- Tax ID
- Current balance (cents)
- Payment terms
- Notes
- Active/Inactive

### 5.6 Sales Module

| Screen | Description | Features |
|--------|-------------|----------|
| `SalesScreen` | Sales list | Search, filter, date range |
| `SaleFormScreen` | Create/Edit sale | Full POS functionality |

**Sale Form Features:**
- Product search/scan
- Barcode scanner integration
- Customer selection (optional)
- Salesperson assignment
- Line items with:
  - Quantity
  - Unit price
  - Line discount (amount or %)
  - Line total
- Invoice-level discount
- Tax calculation (before/after discount configurable)
- Subtotal, discount, tax, grand total display
- Multiple payment methods:
  - Cash
  - Card
  - Bank transfer
  - Credit (on account)
  - Split payment
- Change calculation
- Overpayment handling (credit to customer)
- Notes field
- Print/share invoice

### 5.7 Sale Returns Module

| Screen | Description | Features |
|--------|-------------|----------|
| `SaleReturnsScreen` | Returns list | Search, filter |
| `SaleReturnFormScreen` | Create/Edit return | Link to original sale or standalone |

**Return Features:**
- Link to original sale (optional)
- Return specific items or full invoice
- Return quantity per item
- Return reason
- Refund method (cash, credit to account)
- Inventory auto-update
- Accounting entries auto-generated

### 5.8 Purchases Module

| Screen | Description | Features |
|--------|-------------|----------|
| `PurchasesScreen` | Purchase list | Search, filter, date range |
| `PurchaseFormScreen` | Create/Edit purchase | Full purchase functionality |
| `PurchaseDetailScreen` | Purchase details | View, print, actions |

**Purchase Form Features:**
- Supplier selection
- Product search/scan
- Line items with quantities, costs
- Discount handling
- Tax handling
- Payment to supplier
- Inventory auto-update
- Notes

### 5.9 Purchase Returns Module

| Screen | Description | Features |
|--------|-------------|----------|
| `PurchaseReturnsScreen` | Returns list | Search, filter |
| `PurchaseReturnFormScreen` | Create/Edit return | Return to supplier |
| `PurchaseReturnDetailScreen` | Return details | View, print |

### 5.10 Employees Module

| Screen | Description | Features |
|--------|-------------|----------|
| `EmployeesScreen` | Employee list | CRUD operations |
| `EmployeeFormScreen` | Add/Edit employee | All fields |

**Employee Fields:**
- Name
- Position
- Phone
- Email
- Hire date
- Salary
- Commission rate (for salespeople)
- Monthly target
- Active/Inactive

### 5.11 Users Module

| Screen | Description | Features |
|--------|-------------|----------|
| `UsersScreen` | User list | App users management |
| `UserFormScreen` | Add/Edit user | Credentials, role |

**User Fields:**
- Username
- Password (hashed)
- Role (Owner, Manager, Cashier, Salesperson)
- Linked employee (optional)
- Active/Inactive

**Role Permissions:**
| Permission | Owner | Manager | Cashier | Salesperson |
|------------|-------|---------|---------|-------------|
| View Dashboard | ✓ | ✓ | ✓ | ✓ |
| Create Sales | ✓ | ✓ | ✓ | ✓ |
| Edit Sales | ✓ | ✓ | ✗ | ✗ |
| Void Sales | ✓ | ✓ | ✗ | ✗ |
| View Reports | ✓ | ✓ | ✓ | ✗ |
| Export Reports | ✓ | ✓ | ✗ | ✗ |
| Manage Products | ✓ | ✓ | ✗ | ✗ |
| Manage Users | ✓ | ✓ | ✗ | ✗ |
| Settings | ✓ | ✗ | ✗ | ✗ |
| Database Management | ✓ | ✗ | ✗ | ✗ |

### 5.12 Expenses Module

| Screen | Description | Features |
|--------|-------------|----------|
| `ExpensesScreen` | Expense list | Track business expenses |
| `ExpenseFormScreen` | Add/Edit expense | All fields |
| `ExpenseCategoriesScreen` | Categories | Manage expense categories |

**Expense Fields:**
- Date
- Category
- Amount (cents)
- Description
- Payment method
- Receipt image (optional)
- Recurring (yes/no)

### 5.13 Accounting Module

| Screen | Description | Features |
|--------|-------------|----------|
| `JournalEntriesListScreen` | Journal list | View all entries |
| `JournalEntryFormScreen` | Create entry | Manual journal entry |
| `JournalEntryDetailScreen` | Entry details | View debits/credits |

**Accounting Features:**
- Chart of Accounts (auto-initialized)
- Double-entry bookkeeping
- Auto-generated entries for:
  - Sales
  - Purchases
  - Returns
  - Payments
  - Expenses
- Manual journal entries
- Accounting periods (monthly/yearly)

### 5.14 Settings Module

| Screen | Description | Features |
|--------|-------------|----------|
| `SettingsScreen` | Main settings | All configuration |
| `CurrencySettingsScreen` | Currency config | Default currency, format |
| `SecuritySettingsScreen` | Security options | Password policy, timeout |
| `PrintingSettingsScreen` | Print config | Paper size, template, printer |

**Settings Categories:**
- **Company Info**: Name, address, phone, logo
- **Currency**: Default currency, symbol position, decimals
- **Tax**: Tax rates, tax on discount behavior
- **Invoice**: Numbering, template, default notes
- **Print**: Paper size (A4/thermal), margins, logo on invoice
- **Security**: Auto-logout timeout, password requirements
- **Language**: UI language selection
- **Theme**: Light/Dark mode
- **Backup**: Auto-backup settings

### 5.15 Database Management Module

| Screen | Description | Features |
|--------|-------------|----------|
| `DatabaseManagementScreen` | DB operations | Backup, restore, reset |
| `DatabaseHealthScreen` | Health check | Integrity verification |
| `AuditLogScreen` | Activity log | Track all actions |

### 5.16 Notifications Module

| Screen | Description | Features |
|--------|-------------|----------|
| `NotificationsScreen` | Notification center | View alerts |

**Notification Types:**
- Low stock alerts
- Payment reminders
- Overdue invoices
- System messages

### 5.17 Admin/Diagnostic Tools

| Screen | Description | Features |
|--------|-------------|----------|
| `SupplierBalanceFixScreen` | Balance repair | Fix supplier balance issues |
| `MismatchDetectionScreen` | Data validation | Detect and fix mismatches |

---

## 6. REPORTS INVENTORY

### 6.1 Financial Reports

| Report | Description | Features |
|--------|-------------|----------|
| `FinancialStatementsScreen` | Overview | Links to all financial reports |
| `ProfitLossReportScreen` | P&L Statement | Revenue, expenses, net profit |
| `BalanceSheetReportScreen` | Balance Sheet | Assets, liabilities, equity |
| `TrialBalanceReportScreen` | Trial Balance | Debit/credit verification |
| `GeneralLedgerReportScreen` | General Ledger | All account transactions |
| `CashFlowReportScreen` | Cash Flow | Cash in/out by period |
| `TaxReportScreen` | Tax Summary | Tax collected, tax paid |
| `SalesSummaryReportScreen` | Sales Summary | Daily/weekly/monthly sales |

### 6.2 Inventory Reports

| Report | Description | Features |
|--------|-------------|----------|
| `InventoryStockReportScreen` | Stock Levels | Current stock for all products |
| `LowStockReportScreen` | Low Stock Alert | Products below minimum |
| `OutOfStockReportScreen` | Out of Stock | Products with zero stock |
| `DeadStockReportScreen` | Dead Stock | Products not sold in X days |
| `CategoryStocktakeReportScreen` | By Category | Stock grouped by category |
| `ProductMovementReportScreen` | Movement History | In/out movements per product |

### 6.3 Customer Reports

| Report | Description | Features |
|--------|-------------|----------|
| `CustomerAgingReportScreen` | Aging Analysis | Overdue receivables by period |
| `CustomerStatementReportScreen` | Statement | Customer account statement |
| `CustomerAnalysisReportScreen` | Analysis | Customer buying patterns |
| `CustomerPaymentReportScreen` | Payments | Payment history |
| `CustomerSalesReportScreen` | Sales by Customer | Sales per customer |
| `CustomerSalesReturnsReportScreen` | Returns | Returns by customer |
| `TopCustomersReportScreen` | Top Customers | Best customers by sales |

### 6.4 Supplier Reports

| Report | Description | Features |
|--------|-------------|----------|
| `SupplierBalanceReportScreen` | Balances | All supplier balances |
| `SupplierDebitBalanceReportScreen` | Debit Balances | What we owe suppliers |
| `SupplierCreditBalanceReportScreen` | Credit Balances | Supplier credits |
| `SupplierAnalysisReportScreen` | Analysis | Supplier performance |
| `SupplierAgingReportScreen` | Aging | Overdue payables |
| `SupplierStatementReportScreen` | Statement | Supplier account statement |
| `SupplierStocktakeReportScreen` | Stocktake | Products by supplier |
| `SupplierBalanceDrilldownScreen` | Drilldown | Detailed balance breakdown |

### 6.5 Salespeople Reports

| Report | Description | Features |
|--------|-------------|----------|
| `SalespeopleReportScreen` | Performance | Sales by salesperson |
| `CommissionsReportScreen` | Commissions | Commission calculations |

### 6.6 Expense Reports

| Report | Description | Features |
|--------|-------------|----------|
| `ExpenseReportScreen` | Expenses | Expenses by category/period |

### 6.7 Audit Reports

| Report | Description | Features |
|--------|-------------|----------|
| `VoidLogsReportScreen` | Void Logs | Voided transactions |
| `ReconciliationDiagnosticsScreen` | Reconciliation | Data integrity checks |

### 6.8 Report Features (All Reports)

Every report MUST support:
- [ ] Date range filter
- [ ] Export to PDF (Arabic/English/French)
- [ ] Export to Excel/CSV
- [ ] Share via any app
- [ ] Print (A4 and thermal)
- [ ] Totals and summaries
- [ ] Sorting options
- [ ] Search/filter

---

## 7. DIALOGS & WORKFLOWS INVENTORY

### 7.1 Sales Dialogs

| Dialog | Purpose | Trigger |
|--------|---------|---------|
| `SaleProductSelectionDialog` | Select products to add | Add product button |
| `SaleProductEditDialog` | Edit line item (qty, price, discount) | Tap line item |
| `CustomerPaymentDialog` | Record payment | Pay button |
| `InvoiceSplitPaymentDialog` | Split payment methods | Split payment option |
| `CustomerSettlementDialog` | Settle customer balance | Settlement action |
| `VoidInvoiceDialog` | Void/cancel invoice | Void button |
| `SaleInvoicePrintDialog` | Print options | Print button |
| `SaleReturnPrintDialog` | Print return | Print button |
| `QuickSaleSummaryDialog` | Quick sale checkout | Quick sale flow |

### 7.2 Purchase Dialogs

| Dialog | Purpose | Trigger |
|--------|---------|---------|
| `ProductSelectionDialog` | Select products | Add product |
| `ProductEditDialog` | Edit line item | Tap line item |
| `SupplierPaymentDialog` | Pay supplier | Pay button |
| `SupplierRefundDialog` | Refund from supplier | Refund action |
| `PurchaseOtherDialogs` | Misc purchase dialogs | Various |
| `PurchaseBarcodeScanner` | Scan products | Scan button |

### 7.3 Customer Dialogs

| Dialog | Purpose | Trigger |
|--------|---------|---------|
| `CustomerPaymentDialog` | Record customer payment | Pay button |

### 7.4 Supplier Dialogs

| Dialog | Purpose | Trigger |
|--------|---------|---------|
| `SupplierDiscountDialog` | Add discount | Discount action |
| `SupplierPaymentDialog` | Pay supplier | Pay button |
| `SupplierReturnDialog` | Return to supplier | Return action |

### 7.5 Core Dialogs

| Dialog | Purpose | Location |
|--------|---------|----------|
| `BusinessRuleErrorDialog` | Show validation errors | Anywhere |
| `VoidReturnDialog` | Void/return confirmation | Sales/Purchases |
| `DateRangeFilter` | Filter by date | Reports, lists |

---

## 8. CORE SERVICES INVENTORY

### 8.1 Business Logic Services

| Service | Purpose | Critical |
|---------|---------|----------|
| `TransactionOrchestrator` | Orchestrate all transactions (sales, purchases, payments) | YES |
| `BusinessRulesEngine` | Validate business rules before actions | YES |
| `JournalEntryService` | Create accounting entries | YES |
| `ChartOfAccountsService` | Manage chart of accounts | YES |
| `AccountingPeriodService` | Manage accounting periods | YES |

### 8.2 Financial Services

| Service | Purpose | Critical |
|---------|---------|----------|
| `TrialBalanceService` | Generate trial balance | YES |
| `IncomeStatementService` | Generate P&L | YES |
| `BalanceSheetService` | Generate balance sheet | YES |
| `CashFlowStatementService` | Generate cash flow | YES |
| `CurrencyService` | Currency formatting | YES |

### 8.3 Document Services

| Service | Purpose | Critical |
|---------|---------|----------|
| `PdfService` | Generate all PDF documents | YES |
| `PrinterDiscoveryService` | Find available printers | YES |
| `CsvSaver` | Export to CSV | YES |

### 8.4 Security Services

| Service | Purpose | Critical |
|---------|---------|----------|
| `PasswordService` | Hash/verify passwords | YES |
| `SessionService` | Manage user sessions | YES |
| `SecureSessionService` | Secure storage | YES |
| `PermissionService` | Check user permissions | YES |

### 8.5 Utility Services

| Service | Purpose | Critical |
|---------|---------|----------|
| `LoggerService` | Application logging | YES |
| `NotificationService` | In-app notifications | YES |
| `AuditLogService` | Track user actions | YES |
| `FeatureFlagService` | Feature toggles | NO |
| `RollbackService` | Rollback transactions | YES |

### 8.6 Database Services

| Service | Purpose | Critical |
|---------|---------|----------|
| `RealtimeService` | Real-time data sync | CRITICAL |
| `DatabaseHealthService` | DB health checks | YES |
| `DatabaseCleanupService` | Cleanup old data | YES |
| `MigrationService` | Schema migrations | YES |
| `BalanceRebuildService` | Rebuild balances | YES |
| `MismatchDetectionService` | Find data mismatches | YES |

---

## 9. DATABASE SCHEMA REQUIREMENTS

### 9.1 Core Tables

| Table | Purpose |
|-------|---------|
| `users` | App users with roles |
| `employees` | Employee records |
| `products` | Product catalog |
| `product_variants` | Size/color variants |
| `categories` | Product categories |
| `colors` | Product colors |
| `sizes` | Product sizes |
| `customers` | Customer records |
| `suppliers` | Supplier records |
| `sales` | Sale headers |
| `sale_items` | Sale line items |
| `sale_returns` | Sale return headers |
| `sale_return_items` | Return line items |
| `purchases` | Purchase headers |
| `purchase_items` | Purchase line items |
| `purchase_returns` | Purchase return headers |
| `purchase_return_items` | Return line items |
| `payments` | All payment records |
| `expenses` | Expense records |
| `expense_categories` | Expense categories |
| `journal_entries` | Accounting entries |
| `journal_entry_lines` | Entry line items |
| `accounts` | Chart of accounts |
| `accounting_periods` | Periods |
| `app_settings` | App configuration |
| `store_logos` | Store branding |
| `currencies` | Currency definitions |
| `notifications` | In-app notifications |
| `audit_logs` | Action tracking |

### 9.2 Key Relationships

```
sales → sale_items → products
sales → customers
sales → employees (salesperson)
sales → payments

purchases → purchase_items → products
purchases → suppliers
purchases → payments

sale_returns → sale_return_items → sales
purchase_returns → purchase_return_items → purchases

journal_entries → journal_entry_lines → accounts
```

### 9.3 Money Fields (ALL in cents)

Every money field MUST be `INTEGER` (cents):
- `price_cents`
- `cost_cents`
- `subtotal_cents`
- `discount_cents`
- `tax_cents`
- `total_cents`
- `paid_cents`
- `balance_cents`

---

## 10. IMPLEMENTATION PHASES

### Phase 0: Tech Stack Validation (1-2 days)
- [ ] Verify ALL packages on pub.dev
- [ ] Test compatibility with Flutter 3.24+
- [ ] Test on ALL target platforms
- [ ] Create validation report
- [ ] Get user approval before proceeding

### Phase 1: Project Bootstrap (2-3 days)
- [ ] Create new Flutter project
- [ ] Setup Clean Architecture folders
- [ ] Configure Bloc
- [ ] Setup Drift database with schema
- [ ] Configure themes (light/dark)
- [ ] Setup localization (AR/EN/FR)
- [ ] Configure GoRouter
- [ ] Create base widgets

### Phase 2: Core Infrastructure (3-5 days)
- [ ] Implement RealtimeService with database streams
- [ ] Implement base Bloc with stream subscription pattern
- [ ] Implement money calculation utilities
- [ ] Implement PDF service skeleton
- [ ] Implement navigation drawer
- [ ] Implement global app bar
- [ ] Implement date range filter

### Phase 3: Auth Module (2-3 days)
- [ ] Welcome screen
- [ ] Login screen
- [ ] Create admin screen
- [ ] Auth bloc with session management
- [ ] Role-based access control

### Phase 4: Products Module (5-7 days)
- [ ] Products list with search/filter
- [ ] Product form (add/edit)
- [ ] Bulk add
- [ ] Categories, colors, sizes
- [ ] Import/export
- [ ] Barcode design/print
- [ ] Real-time stock updates

### Phase 5: Customers & Suppliers (3-4 days)
- [ ] Customer list/form/profile
- [ ] Customer payment dialog
- [ ] Supplier list/form/profile
- [ ] Supplier payment/discount dialogs

### Phase 6: Sales Module (7-10 days)
- [ ] Sales list screen
- [ ] Sale form with full POS
- [ ] All dialogs (payment, split, void, etc.)
- [ ] Invoice PDF generation
- [ ] Print/share
- [ ] Sale returns
- [ ] Inventory auto-update
- [ ] Accounting auto-entries

### Phase 7: Purchases Module (5-7 days)
- [ ] Purchases list screen
- [ ] Purchase form
- [ ] Purchase detail screen
- [ ] All dialogs
- [ ] Purchase returns
- [ ] Supplier balance updates

### Phase 8: Expenses & Accounting (4-5 days)
- [ ] Expenses module
- [ ] Journal entries module
- [ ] Chart of accounts
- [ ] Automatic entry generation

### Phase 9: Reports (7-10 days)
- [ ] Reports hub screen
- [ ] All financial reports
- [ ] All inventory reports
- [ ] All customer reports
- [ ] All supplier reports
- [ ] Salespeople/commission reports
- [ ] PDF export for all
- [ ] Excel/CSV export

### Phase 10: Settings & Admin (3-4 days)
- [ ] All settings screens
- [ ] Database management
- [ ] Audit logs
- [ ] Diagnostic tools

### Phase 11: Dashboard & Polish (3-5 days)
- [ ] Dashboard with KPIs
- [ ] Charts
- [ ] Notifications
- [ ] Final UI polish
- [ ] Performance optimization

### Phase 12: Testing & QA (5-7 days)
- [ ] Unit tests for all services
- [ ] Widget tests for key screens
- [ ] Integration tests
- [ ] Platform-specific testing
- [ ] RTL testing (Arabic)
- [ ] Performance testing with large data

---

## 11. AI MODEL ALLOCATION

### 11.1 Recommended AI Models by Task

| Task | Primary Model | Secondary Model |
|------|--------------|-----------------|
| Architecture decisions | Claude Opus | - |
| Complex business logic | Claude Opus | - |
| Transaction orchestration | Claude Opus | - |
| Financial calculations | Claude Opus | - |
| Database schema design | Claude Opus | - |
| Real-time sync engine | Claude Opus | - |
| Testing strategy | Claude Opus | Sonnet |
| UI/UX design specs | Gemini 2.0 Flash | Claude Sonnet |
| Component styling | Gemini 2.0 Flash | - |
| Visual validation | Gemini 2.0 Flash | - |
| Code refactoring | Claude Sonnet | - |
| Bug fixes | Claude Sonnet | - |
| Quick improvements | Claude Sonnet | Claude Haiku |
| Linting/formatting | Claude Haiku | - |
| Simple code review | Claude Haiku | - |
| Documentation | Claude Sonnet | Haiku |

### 11.2 When to Switch Models

- **Use Opus** when: Creating new architecture, financial logic, complex algorithms
- **Use Gemini** when: Designing UI, choosing colors, layout decisions
- **Use Sonnet** when: Implementing features from specs, fixing bugs
- **Use Haiku** when: Quick tasks, formatting, simple reviews

---

## 12. QUALITY CHECKLIST

### 12.1 Before Every Commit

- [ ] Code compiles without errors
- [ ] No lint warnings
- [ ] New code has tests
- [ ] Existing tests pass
- [ ] RTL layout works
- [ ] Light theme works
- [ ] Dark theme works
- [ ] Mobile layout works
- [ ] Desktop layout works

### 12.2 Before Every Feature Merge

- [ ] Feature works on Android
- [ ] Feature works on iOS
- [ ] Feature works on Windows
- [ ] Feature works on Web
- [ ] Feature works on Linux
- [ ] Feature works in Arabic
- [ ] Feature works in English
- [ ] Feature works in French
- [ ] Real-time updates work
- [ ] Money calculations are correct
- [ ] PDF export works

### 12.3 Before Release

- [ ] All features from inventory implemented
- [ ] All reports functional
- [ ] Performance acceptable with 10,000+ products
- [ ] No memory leaks
- [ ] App size acceptable
- [ ] All platforms tested
- [ ] All languages tested
- [ ] Security audit passed

---

## 13. KNOWN ISSUES TO AVOID

### 13.1 From Current App

| Issue | Root Cause | Solution |
|-------|------------|----------|
| No real-time updates | No database streams | Use Drift streams + Bloc |
| Requires app restart | Stale state caching | Automatic state invalidation |
| Calculation errors | Using double for money | Use int cents + Decimal |
| UI overflow on some screens | Fixed sizes | Use responsive_framework |
| Slow with large data | Loading all data at once | Pagination + lazy loading |
| Inconsistent UI | No component library | Create reusable widgets first |

### 13.2 Architecture Anti-Patterns to Avoid

| Don't Do This | Do This Instead |
|---------------|-----------------|
| `setState()` for data updates | Emit new Bloc state |
| Manual `refresh()` calls | Database stream subscriptions |
| `double` for money | `int` cents or `Decimal` |
| Hardcoded strings | Localization keys |
| Platform-specific code in UI | Conditional imports |
| Large monolithic widgets | Small, focused widgets |
| Business logic in UI | Services and Blocs |

### 13.3 Testing Anti-Patterns

| Don't Do This | Do This Instead |
|---------------|-----------------|
| Skip testing | Test everything |
| Test only happy path | Test edge cases |
| Test only one platform | Test ALL platforms |
| Test only one language | Test AR/EN/FR |
| Ignore performance | Profile regularly |

---

## APPENDIX A: LOCALIZATION KEYS STRUCTURE

```yaml
# Organize by feature
auth:
  login: "Login"
  logout: "Logout"
  
products:
  addProduct: "Add Product"
  editProduct: "Edit Product"
  
sales:
  newSale: "New Sale"
  addToCart: "Add to Cart"
  
# Organize common strings
common:
  save: "Save"
  cancel: "Cancel"
  delete: "Delete"
  
# Organize errors
errors:
  networkError: "Network error"
  validationError: "Please check your input"
```

---

## APPENDIX B: THEME COLOR GUIDELINES

### Light Theme
- Primary: Deep Blue (#1565C0)
- Secondary: Teal (#00897B)
- Background: White (#FFFFFF)
- Surface: Light Gray (#F5F5F5)
- Error: Red (#D32F2F)
- Success: Green (#388E3C)
- Warning: Orange (#F57C00)

### Dark Theme
- Primary: Light Blue (#64B5F6)
- Secondary: Teal (#4DB6AC)
- Background: Dark Gray (#121212)
- Surface: Dark Gray (#1E1E1E)
- Error: Light Red (#EF5350)
- Success: Light Green (#81C784)
- Warning: Light Orange (#FFB74D)

---

## APPENDIX C: PDF TEMPLATE STRUCTURE

Every PDF must include:
1. **Header**: Logo, company name, document title
2. **Document Info**: Number, date, customer/supplier
3. **Body**: Table with items/data
4. **Summary**: Totals, taxes, discounts
5. **Footer**: Notes, terms, signature area, page number

Support for:
- A4 paper (210mm x 297mm)
- Thermal paper (80mm, 58mm widths)
- RTL for Arabic
- LTR for English/French

---

## DOCUMENT END

**This document is the SINGLE SOURCE OF TRUTH for the Tapix rebuild.**

Follow it exactly. Do not skip any feature. Do not take shortcuts.

When in doubt, refer to this document.

**Last Updated**: January 2026  
**Next Review**: Before Phase 1 begins
