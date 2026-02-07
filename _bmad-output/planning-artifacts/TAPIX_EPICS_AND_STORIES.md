# TAPIX ERP - Epics and Stories
> **Project**: Tapix
> **Generated**: January 2026
> **Source**: TAPIX_REBUILD_SPECIFICATION.md, TAPIX_TECHNICAL_INVENTORY.md

---

## 📋 Epic Overview

| Epic ID | Epic Name | Description | Priority |
|---------|-----------|-------------|----------|
| **EPIC-01** | **Core Infrastructure** | Project setup, architecture, database, theme, and localization | CRITICAL |
| **EPIC-02** | **Authentication** | User login, role-based access, and session management | HIGH |
| **EPIC-03** | **Product Management** | Product CRUD, variants, barcodes, and inventory tracking | CRITICAL |
| **EPIC-04** | **Parties Management** | Customer and Supplier profiles, balances, and ledgers | HIGH |
| **EPIC-05** | **Sales & POS** | Point of Sale interface, cart management, payments, and invoices | CRITICAL |
| **EPIC-06** | **Purchase Management** | Purchase orders, receiving stock, and supplier payments | HIGH |
| **EPIC-07** | **Finance & Accounting** | Expenses, journal entries, and chart of accounts | MEDIUM |
| **EPIC-08** | **Reporting** | Financial, inventory, and party reports with export | HIGH |
| **EPIC-09** | **Settings & Admin** | App configuration, database management, and audit logs | MEDIUM |
| **EPIC-10** | **Polish & QA** | UI refinement, animations, and comprehensive testing | HIGH |

---

## 🏗️ EPIC-01: Core Infrastructure

**Goal**: Establish a solid technical foundation with Clean Architecture, offline-first database, and real-time state management.

### STORY-01-01: Project Setup & Architecture
**As a** Developer
**I want** to initialize the Flutter project with Clean Architecture folders and core dependencies
**So that** the codebase is maintainable and scalable.

**Acceptance Criteria:**
- [ ] Flutter project created with `flutter create tapix`
- [ ] Folder structure established: `lib/core`, `lib/features`
- [ ] Core dependencies added (flutter_bloc, drift, go_router, etc.) matching `TAPIX_IMPLEMENTATION_CHECKLIST.md`
- [ ] `analysis_options.yaml` configured for strict linting

### STORY-01-02: Database Schema Implementation
**As a** Developer
**I want** to implement the Drift database tables and relationships
**So that** the app can store data offline and sync in real-time.

**Acceptance Criteria:**
- [ ] All tables from `TAPIX_TECHNICAL_INVENTORY.md` section 1 implemented in Drift
- [ ] Relationships defined (Sales -> SaleItems -> Products, etc.)
- [ ] Money fields defined as `Int` (cents)
- [ ] Web WASM support configured
- [ ] Database migration logic initialized

### STORY-01-03: Real-Time State Management Infrastructure
**As a** Developer
**I want** to set up a base Bloc pattern with database stream subscriptions
**So that** the UI updates automatically whenever data changes.

**Acceptance Criteria:**
- [ ] `RealtimeService` implemented using Drift streams
- [ ] Base Bloc class created handling stream subscriptions
- [ ] Test case: Database update triggers Bloc state emission without manual refresh

### STORY-01-04: Theme & Localization
**As a** User
**I want** to switch between Light/Dark themes and English/Arabic/French languages
**So that** I can use the app comfortably in my preferred context.

**Acceptance Criteria:**
- [ ] `flex_color_scheme` implemented with modern palette
- [ ] Semantic colors defined: Green (Success), Orange (Warning), Red (Error/Destructive)
- [ ] App theme configured to use semantic colors for buttons and text
- [ ] `easy_localization` set up with EN, AR, FR support
- [ ] RTL layout support verified for Arabic
- [ ] Theme/Language persistence in local storage

---

## 🔐 EPIC-02: Authentication

**Goal**: Secure user access with role-based permissions.

### STORY-02-01: Login Screen & Auth Logic
**As a** User
**I want** to log in with my username and password
**So that** I can access the system securely.

**Acceptance Criteria:**
- [ ] Login UI matches design specs (modern, clean)
- [ ] Password hashing implemented (no plain text storage)
- [ ] Session management with secure storage
- [ ] Error handling for invalid credentials

### STORY-02-02: Role-Based Access Control
**As a** Manager
**I want** to restrict sensitive features to specific roles
**So that** cashiers cannot perform unauthorized actions like modifying stock history.

**Acceptance Criteria:**
- [ ] Roles defined: Owner, Manager, Cashier, Salesperson
- [ ] `PermissionService` implemented
- [ ] UI elements hidden/disabled based on current user role

---

## 📦 EPIC-03: Product Management

**Goal**: Comprehensive inventory management with support for variants and barcodes.

### STORY-03-01: Product List Search & Filter ✅
**As a** User
**I want** to view, search, and filter products
**So that** I can quickly find items.

**Acceptance Criteria:**
- [ ] Product list is fed from Drift queries and updates in real-time (no manual refresh)
- [ ] Search by name, SKU, and barcode
- [ ] Filters include category and stock status at minimum
- [ ] No overflow on any screen size

### STORY-03-02: Product CRUD + Variants ✅
**As a** Manager
**I want** to create and edit products with variants
**So that** I can manage inventory correctly.

**Acceptance Criteria:**
- [ ] Product create/edit follows Clean Architecture + Bloc + DI
- [ ] Variant creation supports Color/Size combinations and default variant fallback
- [ ] All money fields use integer cents internally (no floating point)
- [ ] Validation prevents duplicate SKU/barcode per business rules

### STORY-03-03: Barcode Management ✅
**As a** User
**I want** to scan and manage barcodes
**So that** inventory workflows are fast.

**Acceptance Criteria:**
- [ ] Barcode scan/search works on supported platforms
- [ ] Barcode values are unique where required (variant-level uniqueness)
- [ ] Barcode generation/validation does not break accounting integrity

### STORY-03-04: Bulk Product Form ✅
**As a** Manager
**I want** to create/edit multiple products efficiently
**So that** data entry is fast.

**Acceptance Criteria:**
- [ ] Bulk workflow persists through Drift (no in-memory-only state)
- [ ] Realtime updates reflect immediately in product list

### STORY-03-05: Edit Prices Screen ✅
**As a** Manager
**I want** to edit prices safely
**So that** pricing stays correct.

**Acceptance Criteria:**
- [ ] All money math uses integer cents
- [ ] UI uses locale-aware formatting; no hardcoded currency symbols

### STORY-03-06: Import Products Screen ✅
**As a** Manager
**I want** to import products from file
**So that** onboarding is fast.

**Acceptance Criteria:**
- [ ] Import is offline-first and stores results in Drift
- [ ] Import can create Colors/Sizes and Variants when provided

### STORY-03-07: Simple Export Screen ✅
**As a** Manager
**I want** to export inventory data
**So that** I can share or back up my catalog.

**Acceptance Criteria:**
- [ ] Export runs entirely from local DB state (Drift)
- [ ] Export output is consistent across languages (headers localized where needed)

### STORY-03-08: Barcode Design Screen ✅
**As a** User
**I want** to design barcode labels and print them
**So that** labels match my needs.

**Acceptance Criteria:**
- [ ] Barcode design supports templates and preview
- [ ] Printing flow does not require manual refresh and persists settings

### STORY-03-09: Categories Screen ✅
**As a** Manager
**I want** to manage product categories
**So that** catalog organization is consistent.

**Acceptance Criteria:**
- [ ] Category CRUD is realtime via Drift streams
- [ ] Prevent deletion when referenced where needed

### STORY-03-10: Colors Screen ✅
**As a** Manager
**I want** to manage Colors
**So that** variants can reference consistent attributes.

**Acceptance Criteria:**
- [ ] Colors are normalized entities in DB and reused across products
- [ ] Realtime updates across screens

### STORY-03-11: Sizes Screen ✅
**As a** Manager
**I want** to manage Sizes
**So that** variants can reference consistent attributes.

**Acceptance Criteria:**
- [ ] Sizes are normalized entities in DB and reused across products
- [ ] Realtime updates across screens

### STORY-03-12: Products Main Screen ✅
**As a** User
**I want** a main products area that ties together product workflows
**So that** navigation is consistent.

**Acceptance Criteria:**
- [ ] Navigation uses GoRouter
- [ ] No overflow on any screen size

### STORY-03-13: Default Variant + Auto Barcode ✅
**As a** Manager
**I want** products to have a safe default variant and optional auto-barcode
**So that** variant-less products still work correctly.

**Acceptance Criteria:**
- [ ] Default variant exists per product where applicable
- [ ] Auto barcode generation respects uniqueness constraints

### STORY-03-14: Variants Manager UI (In Progress)
**As a** Manager
**I want** a dedicated variants management UI
**So that** I can manage SKU/barcode/stock per variant.

**Acceptance Criteria:**
- [ ] Variant list is realtime and supports search/filter
- [ ] CRUD respects unique constraints (barcode, product+color+size)
- [ ] Stock edits and adjustments are persisted and reflected immediately

### STORY-03-15: Purchases Use Variants
**As a** Manager
**I want** purchase line items to be variant-aware
**So that** stock and cost track per variant.

**Acceptance Criteria:**
- [ ] Purchase item stores `variantId` for every line (fallback to default variant)
- [ ] Posting purchase updates variant stock quantities correctly
- [ ] UI selection supports choosing variant (color/size) not just product

### STORY-03-16: A4 Label Printing Engine (Verify & Finalize)
**As a** User
**I want** reliable A4 labels printing
**So that** output is correct on paper.

**Acceptance Criteria:**
- [ ] Printing supports A4 grid layout with correct spacing/margins
- [ ] End-to-end verification of generated PDF and print output
- [ ] Settings persist and are reactive

### STORY-03-17: Print Labels From Invoice (Quantity + Variant-Aware)
**As a** User
**I want** to print labels from an invoice/purchase with correct quantities
**So that** label count matches the document lines.

**Acceptance Criteria:**
- [ ] Navigation to barcode design includes invoice line quantities (default copies = line quantity)
- [ ] Printing respects `variantId` on document lines (variant-aware)
- [ ] No reliance on stock quantity for invoice line copies

### STORY-03-18: Variant-Aware Import/Export (Roundtrip Safe)
**As a** Manager
**I want** export/import to preserve variants
**So that** multi-variant products roundtrip correctly.

**Acceptance Criteria:**
- [ ] Export format is variant-row-based (each row = Variant)
- [ ] Import consumes that format to recreate variants without data loss
- [ ] Roundtrip export → import preserves variants, colors, sizes, and barcodes

---

## EPIC-04: Parties Management

**Goal**: Manage relationships and financial balances with Customers and Suppliers.

### STORY-04-01: Customer Management
**As a** User
**I want** to manage customers
**So that** customer balances and statements are accurate.

**Acceptance Criteria:**
- [ ] Customer CRUD is persisted in Drift and exposed via realtime streams (no manual refresh)
- [ ] Customer balance is derived from persisted ledger/transactions (no cached/in-memory balances)
- [ ] Money stored as integer cents; no floating point; no hardcoded currency symbols

### STORY-04-02: Customer Form Screen
**As a** User
**I want** a customer create/edit form
**So that** data entry is validated and consistent.

**Acceptance Criteria:**
- [ ] Form validation for required fields
- [ ] Responsive layout: no overflow on any screen size
- [ ] Navigation uses GoRouter

### STORY-04-03: Customer Profile Screen
**As a** User
**I want** a customer profile screen
**So that** I can view balance, transactions, and related documents.

**Acceptance Criteria:**
- [ ] Balance + statement update in realtime when transactions change
- [ ] Transaction list supports filtering (at least date range)

### STORY-04-04: Customer Payment Dialog
**As a** User
**I want** to record customer payments
**So that** receivables and reports remain correct.

**Acceptance Criteria:**
- [ ] Payment inserts a persisted transaction/ledger entry in Drift
- [ ] All dependent UI updates in realtime

### STORY-04-05: Supplier Management
**As a** User
**I want** to manage suppliers
**So that** supplier balances and statements are accurate.

**Acceptance Criteria:**
- [ ] Supplier CRUD is persisted in Drift and exposed via realtime streams
- [ ] Supplier balance is derived from persisted ledger/transactions

### STORY-04-06: Supplier Form Screen
**As a** User
**I want** a supplier create/edit form
**So that** supplier data is validated and consistent.

**Acceptance Criteria:**
- [ ] Form validation for required fields
- [ ] No overflow on any screen size

### STORY-04-07: Supplier Profile Screen
**As a** User
**I want** a supplier profile screen
**So that** I can view balance, transactions, and related documents.

**Acceptance Criteria:**
- [ ] Balance + statement update in realtime
- [ ] Transaction list supports filtering (at least date range)

### STORY-04-08: Supplier Seasonal Discount Screen
**As a** User
**I want** to manage seasonal supplier discounts
**So that** costs and liabilities remain correct.

**Acceptance Criteria:**
- [ ] Discount rules are persisted in Drift
- [ ] Money math uses integer cents only

### STORY-04-09: Supplier Transaction Detail Screen
**As a** User
**I want** to view supplier transaction details
**So that** auditing and reconciliation are possible.

**Acceptance Criteria:**
- [ ] Detail screen shows source linkage and computed totals
- [ ] Works offline and updates in realtime

### STORY-04-10: Supplier Payment Dialog
**As a** User
**I want** to record supplier payments
**So that** payables and reports remain correct.

**Acceptance Criteria:**
- [ ] Payment inserts a persisted transaction/ledger entry
- [ ] Supplier balance updates everywhere in realtime

### STORY-04-11: Supplier Discount Dialog
**As a** User
**I want** to record supplier discounts/adjustments
**So that** balances match negotiated terms.

**Acceptance Criteria:**
- [ ] Adjustment is recorded as explicit transaction in DB
- [ ] Money math uses integer cents only

### STORY-04-12: Supplier Return Dialog
**As a** User
**I want** to process supplier returns
**So that** inventory and supplier balances are updated correctly.

**Acceptance Criteria:**
- [ ] Return affects inventory (variant-aware where applicable)
- [ ] Return is recorded in supplier ledger and updates in realtime

### STORY-04-13: Employee Management
**As a** Manager
**I want** to manage employees
**So that** staff records support sales attribution and operations.

**Acceptance Criteria:**
- [ ] Employee CRUD persisted in Drift and updates in realtime
- [ ] No overflow on any screen size

### STORY-04-14: Employee Form Screen
**As a** Manager
**I want** an employee form
**So that** employee data is validated and consistent.

**Acceptance Criteria:**
- [ ] Form validation
- [ ] Any money fields use integer cents

### STORY-04-15: User Account Management ✅ DONE
**As a** Owner
**I want** to manage user accounts
**So that** system access is controlled.

**Acceptance Criteria:**
- [x] CRUD for users with roles
- [x] Sensitive actions enforce permission checks

**Implementation Notes:**
- Implemented UserRepository with watch/CRUD methods
- Created UsersBloc and UserFormBloc extending RealtimeBloc
- Built UsersScreen with search, filter, and user list
- Added UserFormScreen for create/edit with validation
- 17 tests passing (6 for UsersBloc, 11 for UserFormBloc)
- Fixed 4-role system (owner, manager, cashier, salesperson)

### STORY-04-16: User Role Permissions ✅ DONE
**As a** Owner
**I want** role-based permissions
**So that** users only see allowed modules/actions.

**Acceptance Criteria:**
- [x] UI and business logic enforcement are consistent
- [x] GoRouter route guards follow current architecture

**Implementation Notes:**
- PermissionService implements hardcoded permission matrix
- RolesScreen shows role overview and permission matrix
- PermissionGate widget for conditional UI rendering
- Route guards in app_router.dart check user roles
- All permissions checked via PermissionService.canAccess()

### STORY-04-17: Employee Performance Tracking
**As a** Manager
**I want** to track employee performance
**So that** I can evaluate sales outcomes.

**Acceptance Criteria:**
- [ ] Metrics derive from persisted sales data (no in-memory summaries)
- [ ] Updates in realtime

---

## EPIC-05: Sales & POS

**Goal**: Fast, accurate, and offline-capable Point of Sale system.

### STORY-05-01: POS Interface & Cart
**As a** Cashier
**I want** to add items to a cart via search or scan
**So that** I can process sales quickly.

**Acceptance Criteria:**
- [ ] Fast product lookup/scan
- [ ] Cart shows line items, quantities, prices
- [ ] Line-level discounts and notes
- [ ] Real-time total calculation (subtotal, tax, discount)

### STORY-05-02: Checkout & Payment
**As a** Cashier
**I want** to process payments with multiple methods
**So that** I can close the sale.

**Acceptance Criteria:**
- [ ] Support Cash, Card, Bank, Credit (Pay Later)
- [ ] Split payment support (partial cash, partial card)
- [ ] Change calculation
- [ ] Invoice creation in database
- [ ] Stock deduction upon completion

### STORY-05-03: Invoice Printing
**As a** User
**I want** to print professional invoices
**So that** customers have a record of their purchase.

**Acceptance Criteria:**
- [ ] PDF generation using `pdf` package
- [ ] Template matches `TAPIX_TECHNICAL_INVENTORY.md` section 7
- [ ] Support for thermal printers (58mm/80mm) and A4
- [ ] Arabic font support (RTL)

### STORY-05-04: Sale Returns Processing
**As a** Cashier
**I want** to process customer returns
**So that** inventory and accounting remain accurate.

**Acceptance Criteria:**
- [ ] Return references original sale where applicable
- [ ] Return updates inventory (variant-aware)
- [ ] Money math uses integer cents only

### STORY-05-05: Sales Screen
**As a** User
**I want** a sales list screen
**So that** I can view and search previous sales.

**Acceptance Criteria:**
- [ ] Sales list is driven from Drift queries and updates in realtime
- [ ] Search/filter (at least date range)

### STORY-05-06: Sale Form Screen
**As a** Cashier
**I want** a sale form
**So that** I can create invoices reliably.

**Acceptance Criteria:**
- [ ] Variant-aware line items where applicable
- [ ] No overflow on any screen size

### STORY-05-07: Sale Product Selection Dialog
**As a** Cashier
**I want** a product selection dialog
**So that** adding items is fast.

**Acceptance Criteria:**
- [ ] Supports search and barcode scan where supported
- [ ] Realtime results from Drift

### STORY-05-08: Sale Product Edit Dialog
**As a** Cashier
**I want** to edit a sale line item
**So that** quantity/price/discount are correct.

**Acceptance Criteria:**
- [ ] Quantity validation
- [ ] All money fields use integer cents

### STORY-05-09: Customer Payment Dialog
**As a** User
**I want** to record customer payments from sales flow
**So that** receivables and balances stay correct.

**Acceptance Criteria:**
- [ ] Writes persisted ledger/transactions and updates UI in realtime

### STORY-05-10: Invoice Split Payment Dialog
**As a** Cashier
**I want** split payments
**So that** customers can pay with multiple methods.

**Acceptance Criteria:**
- [ ] Persisted payment breakdown
- [ ] Totals reconcile exactly (integer cents)

### STORY-05-11: Customer Settlement Dialog
**As a** User
**I want** a customer settlement dialog
**So that** I can settle outstanding balances accurately.

**Acceptance Criteria:**
- [ ] Settlement writes ledger entries and updates balances in realtime

### STORY-05-12: Void Invoice Dialog
**As a** Manager
**I want** to void an invoice safely
**So that** auditability and accounting integrity are preserved.

**Acceptance Criteria:**
- [ ] Void is recorded as explicit state/transaction (no hard delete)
- [ ] Inventory reversal is variant-aware

### STORY-05-13: Sale Invoice Print Dialog
**As a** User
**I want** a sale invoice print dialog
**So that** I can choose print options before printing.

**Acceptance Criteria:**
- [ ] Supports paper size/thermal options where applicable
- [ ] Arabic RTL supported

### STORY-05-14: Sale Return Print Dialog
**As a** User
**I want** a return print dialog
**So that** customers receive a proper return receipt.

**Acceptance Criteria:**
- [ ] Print includes return details and totals

### STORY-05-15: Quick Sale Summary Dialog
**As a** Cashier
**I want** a quick summary after completing a sale
**So that** I can confirm totals and next actions.

**Acceptance Criteria:**
- [ ] Shows totals and payment breakdown
- [ ] No manual refresh required

### STORY-05-16: Sale Returns Screen
**As a** User
**I want** a returns list screen
**So that** I can view and manage returns.

**Acceptance Criteria:**
- [ ] List is realtime from Drift
- [ ] Filters at least by date range

### STORY-05-17: Sale Return Form Screen
**As a** Cashier
**I want** a return form screen
**So that** I can process returns reliably.

**Acceptance Criteria:**
- [ ] Variant-aware return items
- [ ] Money math uses integer cents

---

## EPIC-06: Purchase Management

**Goal**: Handle stock intake and supplier interactions.

### STORY-06-01: Purchase Orders
**As a** Manager
**I want** to create purchase records when receiving goods
**So that** my inventory is updated.

**Acceptance Criteria:**
- [ ] Select supplier
- [ ] Add products and quantities
- [ ] Update product cost prices (Weighted Average optional, or Last Cost)
- [ ] Increase stock levels automatically

### STORY-06-02: Purchase Returns Processing
**As a** Manager
**I want** to return goods to suppliers
**So that** supplier balances and inventory remain accurate.

**Acceptance Criteria:**
- [ ] Return references original purchase where applicable
- [ ] Return updates inventory (variant-aware)
- [ ] Money math uses integer cents only

### STORY-06-03: Purchases Screen
**As a** User
**I want** a purchases list screen
**So that** I can view and search previous purchases.

**Acceptance Criteria:**
- [ ] Purchases list is driven from Drift queries and updates in realtime
- [ ] Search/filter (at least date range)

### STORY-06-04: Purchase Form Screen
**As a** Manager
**I want** a purchase form
**So that** I can record stock intake reliably.

**Acceptance Criteria:**
- [ ] Variant-aware line items where applicable
- [ ] No overflow on any screen size

### STORY-06-05: Purchase Detail Screen
**As a** User
**I want** a purchase detail screen
**So that** I can review a purchase and its items.

**Acceptance Criteria:**
- [ ] Displays items, totals, and status from persisted data
- [ ] Updates in realtime

### STORY-06-06: Product Selection Dialog
**As a** User
**I want** a product selection dialog for purchases
**So that** adding items is fast.

**Acceptance Criteria:**
- [ ] Supports search and barcode scan where supported
- [ ] Realtime results from Drift

### STORY-06-07: Product Edit Dialog
**As a** User
**I want** to edit a purchase line item
**So that** quantity/cost/discount are correct.

**Acceptance Criteria:**
- [ ] Quantity validation
- [ ] All money fields use integer cents

### STORY-06-08: Supplier Payment Dialog
**As a** User
**I want** to record supplier payments
**So that** payables and balances stay correct.

**Acceptance Criteria:**
- [ ] Writes persisted ledger/transactions and updates UI in realtime

### STORY-06-09: Supplier Refund Dialog
**As a** User
**I want** to record supplier refunds/credits
**So that** supplier balances stay correct.

**Acceptance Criteria:**
- [ ] Writes persisted ledger/transactions and updates UI in realtime

### STORY-06-10: Purchase Barcode Scanner
**As a** User
**I want** to scan barcodes in purchase flow
**So that** item selection is faster.

**Acceptance Criteria:**
- [ ] Scan triggers product/variant lookup
- [ ] Handles not-found gracefully

### STORY-06-11: Purchase Returns Screen
**As a** User
**I want** a purchase returns list screen
**So that** I can view and manage supplier returns.

**Acceptance Criteria:**
- [ ] List is realtime from Drift
- [ ] Filters at least by date range

### STORY-06-12: Purchase Return Form Screen
**As a** Manager
**I want** a purchase return form screen
**So that** I can process supplier returns reliably.

**Acceptance Criteria:**
- [ ] Variant-aware return items
- [ ] Money math uses integer cents

### STORY-06-13: Purchase Return Detail Screen
**As a** User
**I want** a purchase return detail screen
**So that** I can review a return and its items.

**Acceptance Criteria:**
- [ ] Displays return items, totals, and references
- [ ] Updates in realtime

---

## EPIC-07: Finance & Accounting

**Goal**: Accurate financial tracking and accounting.

### STORY-07-01: Expenses Management
**As a** User
**I want** to record operational expenses
**So that** my profit/loss is accurate.

**Acceptance Criteria:**
- [ ] Expense CRUD with categories
- [ ] Money math uses integer cents only

### STORY-07-02: Expenses Screen
**As a** User
**I want** an expenses list screen
**So that** I can view and filter expenses.

**Acceptance Criteria:**
- [ ] List is realtime from Drift
- [ ] Date range filter

### STORY-07-03: Expense Form Screen
**As a** User
**I want** an expense form
**So that** I can create and edit expenses reliably.

**Acceptance Criteria:**
- [ ] Validations shown using standard error dialogs
- [ ] Money math uses integer cents only

### STORY-07-04: Expense Categories Screen
**As a** User
**I want** to manage expense categories
**So that** reporting is consistent.

**Acceptance Criteria:**
- [ ] CRUD categories
- [ ] Updates in realtime

### STORY-07-05: Journal Entries & General Ledger
**As a** Accountant
**I want** the system to generate journal entries
**So that** the books are always balanced.

**Acceptance Criteria:**
- [ ] Double-entry structure is enforced
- [ ] Entries persist to Drift and update UI in realtime

### STORY-07-06: Journal Entries List Screen
**As a** User
**I want** a journal entries list
**So that** I can review posting history.

**Acceptance Criteria:**
- [ ] Realtime list from Drift
- [ ] Date range filter

### STORY-07-07: Journal Entry Form Screen
**As a** Accountant
**I want** a journal entry form
**So that** I can add manual adjustments.

**Acceptance Criteria:**
- [ ] Balanced debits/credits validation
- [ ] Money math uses integer cents only

### STORY-07-08: Journal Entry Detail Screen
**As a** User
**I want** to view journal entry details
**So that** I can audit the transaction.

**Acceptance Criteria:**
- [ ] Shows all lines and references
- [ ] Updates in realtime

---

## EPIC-08: Reporting

**Goal**: Data-driven insights.

### STORY-08-01: Financial Reports
**As a** Manager
**I want** to view Profit & Loss and Balance Sheet
**So that** I know the business health.

**Acceptance Criteria:**
- [ ] P&L report (Revenue - COGS - Expenses)
- [ ] Date range filtering
- [ ] PDF and Excel export

### STORY-08-02: Inventory Reports
**As a** Manager
**I want** to see stock valuation and low stock alerts
**So that** I can reorder in time.

**Acceptance Criteria:**
- [ ] Stock valuation report
- [ ] Low stock report
- [ ] Product movement history

### STORY-08-03: Customer Relationship Reports
**As a** Manager
**I want** customer analytics and statements
**So that** I can manage receivables and retention.

**Acceptance Criteria:**
- [ ] Customer statements, aging, and payment history
- [ ] Updates in realtime from Drift

### STORY-08-04: Supplier Performance Reports
**As a** Manager
**I want** supplier balance and performance reports
**So that** I can manage payables and suppliers effectively.

**Acceptance Criteria:**
- [ ] Supplier statements, aging, balance drilldowns
- [ ] Updates in realtime from Drift

### STORY-08-05: Salespeople Commission Reports
**As a** Manager
**I want** sales team performance and commission reports
**So that** I can track targets and incentives.

**Acceptance Criteria:**
- [ ] Salespeople performance and commission calculations
- [ ] Updates in realtime from Drift

### STORY-08-06: Expense Reports
**As a** Manager
**I want** expense reports
**So that** I can track operational costs over time.

**Acceptance Criteria:**
- [ ] Expense summaries by category and date range
- [ ] Updates in realtime from Drift

### STORY-08-07: Customer Sales Returns Reports
**As a** Manager
**I want** sales returns reports by customer
**So that** I can monitor return patterns.

**Acceptance Criteria:**
- [ ] Returns by customer and date range
- [ ] Export supported

### STORY-08-08: Top Customers Reports
**As a** Manager
**I want** top customers reports
**So that** I can identify key customers.

**Acceptance Criteria:**
- [ ] Top customers by revenue/volume
- [ ] Date range filter

### STORY-08-09: Customer Payment Reports
**As a** Manager
**I want** customer payment reports
**So that** I can audit collections.

**Acceptance Criteria:**
- [ ] Payments by method and date range
- [ ] Export supported

### STORY-08-10: Customer Sales Reports
**As a** Manager
**I want** customer sales reports
**So that** I can analyze customer purchasing.

**Acceptance Criteria:**
- [ ] Sales by customer and date range
- [ ] Export supported

### STORY-08-11: Customer Aging Reports
**As a** Manager
**I want** customer aging reports
**So that** I can manage overdue receivables.

**Acceptance Criteria:**
- [ ] Aging buckets derived from persisted data
- [ ] Updates in realtime

### STORY-08-12: Customer Statement Reports
**As a** Manager
**I want** customer statement reports
**So that** I can share account summaries.

**Acceptance Criteria:**
- [ ] Opening/closing balance and transaction list
- [ ] PDF export supported

### STORY-08-13: Customer Analysis Reports
**As a** Manager
**I want** customer analysis reports
**So that** I can understand buying patterns.

**Acceptance Criteria:**
- [ ] Frequency/value analysis with date range
- [ ] Updates in realtime

### STORY-08-14: Supplier Balance Reports
**As a** Manager
**I want** supplier balance reports
**So that** I know what we owe or are owed.

**Acceptance Criteria:**
- [ ] Supplier balances derived from persisted transactions
- [ ] Updates in realtime

### STORY-08-15: Supplier Debit Balance Reports
**As a** Manager
**I want** supplier debit balance reports
**So that** I can track payables.

**Acceptance Criteria:**
- [ ] Debit balances by supplier
- [ ] Date range filter

### STORY-08-16: Supplier Credit Balance Reports
**As a** Manager
**I want** supplier credit balance reports
**So that** I can track supplier credits.

**Acceptance Criteria:**
- [ ] Credit balances by supplier
- [ ] Date range filter

### STORY-08-17: Supplier Analysis Reports
**As a** Manager
**I want** supplier analysis reports
**So that** I can evaluate supplier performance.

**Acceptance Criteria:**
- [ ] Purchases, returns, and settlement analytics
- [ ] Export supported

### STORY-08-18: Supplier Aging Reports
**As a** Manager
**I want** supplier aging reports
**So that** I can plan payments.

**Acceptance Criteria:**
- [ ] Aging buckets derived from persisted data
- [ ] Updates in realtime

### STORY-08-19: Supplier Statement Reports
**As a** Manager
**I want** supplier statement reports
**So that** I can audit supplier accounts.

**Acceptance Criteria:**
- [ ] Opening/closing balance and transaction list
- [ ] PDF export supported

### STORY-08-20: Supplier Stocktake Reports
**As a** Manager
**I want** supplier stocktake reports
**So that** I can review inventory by supplier.

**Acceptance Criteria:**
- [ ] Inventory by supplier
- [ ] Export supported

### STORY-08-21: Supplier Balance Drilldown Reports
**As a** Manager
**I want** supplier balance drilldown reports
**So that** I can investigate balances.

**Acceptance Criteria:**
- [ ] Drilldown by transaction/reference
- [ ] Updates in realtime

### STORY-08-22: Inventory Stock Reports
**As a** Manager
**I want** inventory stock reports
**So that** I can monitor current quantities.

**Acceptance Criteria:**
- [ ] Stock by product/variant
- [ ] Updates in realtime

### STORY-08-23: Low Stock Reports
**As a** Manager
**I want** low stock reports
**So that** I can reorder on time.

**Acceptance Criteria:**
- [ ] Threshold-based low stock list
- [ ] Export supported

### STORY-08-24: Out of Stock Reports
**As a** Manager
**I want** out of stock reports
**So that** I can identify missing inventory.

**Acceptance Criteria:**
- [ ] Zero stock list
- [ ] Export supported

### STORY-08-25: Dead Stock Reports
**As a** Manager
**I want** dead stock reports
**So that** I can identify non-moving items.

**Acceptance Criteria:**
- [ ] No-movement list by date range
- [ ] Export supported

### STORY-08-26: Category Stocktake Reports
**As a** Manager
**I want** category stocktake reports
**So that** I can review inventory by category.

**Acceptance Criteria:**
- [ ] Inventory grouped by category
- [ ] Export supported

### STORY-08-27: Product Movement Reports
**As a** Manager
**I want** product movement reports
**So that** I can audit stock in/out.

**Acceptance Criteria:**
- [ ] Movement derived from persisted events/transactions
- [ ] Date range filter

### STORY-08-28: Financial Statements Reports
**As a** Manager
**I want** a financial statements suite
**So that** I can generate official statements.

**Acceptance Criteria:**
- [ ] P&L, Balance Sheet, Trial Balance, General Ledger, Cash Flow
- [ ] Export supported

### STORY-08-29: Profit & Loss Reports
**As a** Manager
**I want** dedicated Profit & Loss reports
**So that** I can analyze profitability.

**Acceptance Criteria:**
- [ ] Revenue/COGS/Expense breakdown
- [ ] Date range filter

### STORY-08-30: Balance Sheet Reports
**As a** Manager
**I want** Balance Sheet reports
**So that** I can see assets/liabilities/equity.

**Acceptance Criteria:**
- [ ] Derived from ledger and persisted balances
- [ ] Export supported

### STORY-08-31: Trial Balance Reports
**As a** Manager
**I want** Trial Balance reports
**So that** I can verify debits/credits.

**Acceptance Criteria:**
- [ ] Debit/Credit totals match
- [ ] Export supported

### STORY-08-32: General Ledger Reports
**As a** Manager
**I want** General Ledger reports
**So that** I can audit account transactions.

**Acceptance Criteria:**
- [ ] Ledger entries list by account and date range
- [ ] Export supported

### STORY-08-33: Cash Flow Reports
**As a** Manager
**I want** Cash Flow reports
**So that** I can understand cash movement.

**Acceptance Criteria:**
- [ ] Operating/Investing/Financing sections
- [ ] Export supported

### STORY-08-34: Tax Reports
**As a** Manager
**I want** tax reports
**So that** I can track tax collected and paid.

**Acceptance Criteria:**
- [ ] Tax summary by date range
- [ ] Export supported

### STORY-08-35: Sales Summary Reports
**As a** Manager
**I want** sales summary reports
**So that** I can track sales performance.

**Acceptance Criteria:**
- [ ] Sales totals by day/week/month (aggregated)
- [ ] Date range filter

### STORY-08-36: Void Logs Reports
**As a** Manager
**I want** void logs reports
**So that** I can audit voided transactions.

**Acceptance Criteria:**
- [ ] Voided invoices and reasons
- [ ] Date range filter

### STORY-08-37: Reconciliation Diagnostics Reports
**As a** Manager
**I want** reconciliation diagnostics
**So that** I can detect accounting/inventory mismatches.

**Acceptance Criteria:**
- [ ] Reports highlight mismatches and provide drilldowns
- [ ] Export supported

---

## EPIC-09: Settings & Admin

**Goal**: System configuration and maintenance.

### STORY-09-01: App Configuration
**As a** User
**I want** to configure currency, tax rates, and company info
**So that** the invoices reflect my business details.

**Acceptance Criteria:**
- [ ] Settings screens for Company Info, Logo, Tax, Currency
- [ ] Backup and Restore database functionality

### STORY-09-02: Currency Settings
**As a** Owner
**I want** to configure currency format and precision
**So that** money is displayed consistently across the app.

**Acceptance Criteria:**
- [ ] Currency selection and symbol/position formatting
- [ ] All UI uses integer-based money formatting
- [ ] Changes propagate via app services/blocs

### STORY-09-03: Security Settings
**As a** Owner
**I want** security settings for sessions and access
**So that** I can control app usage and reduce risk.

**Acceptance Criteria:**
- [ ] Session timeout / auto-logout settings
- [ ] Role-based access enforcement verified across routes/screens
- [ ] Sensitive actions require proper authorization

### STORY-09-04: Printing Settings
**As a** User
**I want** printing settings for invoices and labels
**So that** printing works consistently per device.

**Acceptance Criteria:**
- [ ] Default printer / page size / margins / template options
- [ ] Settings persisted locally and applied in print flows
- [ ] Cross-platform behavior verified (desktop/mobile where applicable)

### STORY-09-05: Database Management
**As a** Owner
**I want** database backup/restore and maintenance tools
**So that** I can protect and manage business data.

**Acceptance Criteria:**
- [ ] Manual backup and restore flows
- [ ] Clear confirmations and error handling
- [ ] Data integrity preserved after restore

### STORY-09-06: Database Health
**As a** Owner
**I want** database health diagnostics
**So that** I can detect issues early.

**Acceptance Criteria:**
- [ ] Health checks (e.g., schema version, migrations state)
- [ ] Index/FK constraints status surfaced if possible
- [ ] User-friendly diagnostics report

### STORY-09-07: Audit Log
**As a** Owner
**I want** an audit log of key actions
**So that** I can track who did what and when.

**Acceptance Criteria:**
- [ ] Record key actions (create/update/delete/post/void)
- [ ] Filter by date/user/action type
- [ ] Updates in realtime from Drift

### STORY-09-08: Notifications
**As a** User
**I want** notifications for important events
**So that** I don't miss critical operational issues.

**Acceptance Criteria:**
- [ ] Low stock / mismatches / failed operations notifications
- [ ] Works offline-first; queued events handled safely
- [ ] User can enable/disable per type

### STORY-09-09: Supplier Balance Fix
**As a** Manager
**I want** a supplier balance correction workflow
**So that** legacy data issues can be resolved without breaking accounting integrity.

**Acceptance Criteria:**
- [ ] Safe correction mechanism (ledger-aware)
- [ ] Full audit trail of adjustments
- [ ] Validation prevents inconsistent states

### STORY-09-10: Mismatch Detection
**As a** Manager
**I want** mismatch detection between inventory and accounting views
**So that** I can investigate integrity issues.

**Acceptance Criteria:**
- [ ] Detect and list mismatches (with drilldown)
- [ ] Realtime updates
- [ ] Export supported

---

## EPIC-10: Polish & QA

**Goal**: Deliver a beautiful, bug-free experience.

### STORY-10-01: UI/UX Polish
**As a** User
**I want** smooth animations and responsive layouts
**So that** the app feels modern and high-quality.

**Acceptance Criteria:**
- [ ] No overflow on any screen size
- [ ] Loading skeletons/shimmers
- [ ] Pull-to-refresh
- [ ] Swipe actions
- [ ] Hover states (desktop)

### STORY-10-02: Comprehensive Testing
**As a** Developer
**I want** to run full regression tests
**So that** I ensure no critical bugs exist.

**Acceptance Criteria:**
- [ ] Real-time sync verified
- [ ] Money calculations verified (100% accuracy)
- [ ] Cross-platform verification (Android, Windows, Web)

---

## 👥 EPIC-11: Employee & User Management

**Goal**: Manage staff accounts and role-based permissions.

### STORY-11-01: Employee Management
**As a** Manager
**I want** to manage employee records
**So that** I can track staff information.

**Acceptance Criteria:**
- [ ] Employee CRUD (Name, Position, Phone, Email)
- [ ] Hire date and salary tracking
- [ ] Commission rate setup for salespeople
- [ ] Monthly target setting
- [ ] Active/Inactive status

### STORY-11-02: User Account Management
**As a** Owner
**I want** to create user accounts with specific roles
**So that** I can control system access.

**Acceptance Criteria:**
- [ ] User CRUD (Username, Password, Role)
- [ ] Link to employee record
- [ ] Role-based permission matrix implemented
- [ ] Password hashing and security
- [ ] Session management
- [ ] Auto-logout on inactivity

---

## 🎨 EPIC-12: Advanced UI/UX Features

**Goal**: Modern, responsive UI with advanced interactions.

### STORY-12-01: Responsive Design System
**As a** User
**I want** the app to work perfectly on any screen size
**So that** I can use it on any device.

**Acceptance Criteria:**
- [ ] Mobile layout (320px+)
- [ ] Tablet layout (768px+)
- [ ] Desktop layout (1024px+)
- [ ] No overflow on any screen
- [ ] Adaptive components

### STORY-12-02: Advanced Interactions
**As a** User
**I want** smooth animations and micro-interactions
**So that** the app feels premium.

**Acceptance Criteria:**
- [ ] Page transitions
- [ ] Loading skeletons
- [ ] Pull-to-refresh
- [ ] Swipe actions
- [ ] Hover states (desktop)

---

## 🔧 EPIC-13: Core Services Implementation

**Goal**: Implement all critical business services and utilities.

### STORY-13-01: Transaction Orchestrator Service
**As a** Developer
**I want** a centralized transaction service
**So that** all business operations are consistent.

**Acceptance Criteria:**
- [ ] TransactionOrchestrator implemented
- [ ] Sales transaction flow
- [ ] Purchase transaction flow
- [ ] Payment transaction flow
- [ ] Return transaction flow
- [ ] Rollback capability

### STORY-13-02: Business Rules Engine
**As a** Developer
**I want** to validate all business rules
**So that** data integrity is maintained.

**Acceptance Criteria:**
- [ ] BusinessRulesEngine implemented
- [ ] Stock validation rules
- [ ] Payment validation rules
- [ ] Permission validation rules
- [ ] Custom rule configuration

### STORY-13-03: Accounting Services
**As a** Developer
**I want** automated accounting services
**So that** financial records are always accurate.

**Acceptance Criteria:**
- [ ] JournalEntryService (Auto-generate entries)
- [ ] ChartOfAccountsService (Manage accounts)
- [ ] AccountingPeriodService (Period management)
- [ ] TrialBalanceService (Generate reports)
- [ ] IncomeStatementService (P&L generation)
- [ ] BalanceSheetService (Balance sheet)
- [ ] CashFlowStatementService (Cash flow)

### STORY-13-04: Document Generation Services
**As a** User
**I want** to generate professional documents
**So that** I can share business records.

**Acceptance Criteria:**
- [ ] PdfService (All PDF documents)
- [ ] PrinterDiscoveryService (Find printers)
- [ ] CsvSaver (Export functionality)
- [ ] Multi-language PDF support (EN/AR/FR)
- [ ] Thermal printer support
- [ ] A4 printer support

### STORY-13-05: Security Services
**As a** Developer
**I want** robust security services
**So that** user data is protected.

**Acceptance Criteria:**
- [ ] PasswordService (Hash/verify)
- [ ] SessionService (Manage sessions)
- [ ] SecureSessionService (Secure storage)
- [ ] PermissionService (Check permissions)
- [ ] AuditLogService (Track actions)

### STORY-13-06: Utility Services
**As a** Developer
**I want** essential utility services
**So that** the app runs smoothly.

**Acceptance Criteria:**
- [ ] LoggerService (Application logging)
- [ ] NotificationService (In-app notifications)
- [ ] FeatureFlagService (Feature toggles)
- [ ] CurrencyService (Formatting)
- [ ] RealtimeService (Real-time sync)

---

## 💬 EPIC-14: Dialogs & Workflows

**Goal**: Implement all critical dialogs for smooth user workflows.

### STORY-14-01: Sales Workflow Dialogs
**As a** Cashier
**I want** intuitive dialogs for sales operations
**So that** I can process sales efficiently.

**Acceptance Criteria:**
- [ ] SaleProductSelectionDialog (Add products)
- [ ] SaleProductEditDialog (Edit line items)
- [ ] CustomerPaymentDialog (Record payments)
- [ ] InvoiceSplitPaymentDialog (Split payments)
- [ ] CustomerSettlementDialog (Settle balances)
- [ ] VoidInvoiceDialog (Cancel invoices)
- [ ] SaleInvoicePrintDialog (Print options)
- [ ] SaleReturnPrintDialog (Print returns)
- [ ] QuickSaleSummaryDialog (Quick checkout)

### STORY-14-02: Purchase Workflow Dialogs
**As a** Manager
**I want** dedicated dialogs for purchase operations
**So that** I can manage purchases efficiently.

**Acceptance Criteria:**
- [ ] ProductSelectionDialog (Select products)
- [ ] ProductEditDialog (Edit line items)
- [ ] SupplierPaymentDialog (Pay suppliers)
- [ ] SupplierRefundDialog (Get refunds)
- [ ] PurchaseBarcodeScanner (Scan products)

### STORY-14-03: Customer & Supplier Dialogs
**As a** User
**I want** quick action dialogs for parties
**So that** I can manage relationships efficiently.

**Acceptance Criteria:**
- [ ] CustomerPaymentDialog (Record payments)
- [ ] SupplierDiscountDialog (Add discounts)
- [ ] SupplierPaymentDialog (Pay suppliers)
- [ ] SupplierReturnDialog (Return items)

### STORY-14-04: Core System Dialogs
**As a** User
**I want** consistent error and confirmation dialogs
**So that** the app experience is uniform.

**Acceptance Criteria:**
- [ ] BusinessRuleErrorDialog (Show validation errors) - Uses Red/Error styling
- [ ] VoidReturnDialog (Confirm actions) - Uses Red/Destructive styling
- [ ] DateRangeFilter (Filter by date)
- [ ] ConfirmationDialog (Generic confirmations) - Uses Green/Success or Neutral styling

---

## ⚙️ EPIC-15: Advanced Settings & Configuration

**Goal**: Complete settings module with all configuration options.

### STORY-15-01: Company Configuration
**As a** Owner
**I want** to configure company details
**So that** documents reflect my business.

**Acceptance Criteria:**
- [ ] Company info (Name, Address, Phone, Email)
- [ ] Logo upload and management
- [ ] Tax ID and registration
- [ ] Business hours setup

### STORY-15-02: Financial Settings
**As a** Manager
**I want** to configure financial parameters
**So that** calculations are accurate.

**Acceptance Criteria:**
- [ ] Currency settings (Default, symbol, format)
- [ ] Tax configuration (Rates, rules)
- [ ] Payment method setup
- [ ] Credit limit policies

### STORY-15-03: Printing & Export Settings
**As a** User
**I want** to configure printing and export options
**So that** documents output correctly.

**Acceptance Criteria:**
- [ ] Printer setup (Thermal, A4, Bluetooth)
- [ ] Paper size configuration
- [ ] Template customization
- [ ] Export format settings

### STORY-15-04: Security & Access Settings
**As a** Owner
**I want** to configure security policies
**So that** the system is secure.

**Acceptance Criteria:**
- [ ] Password policies (Length, complexity)
- [ ] Auto-logout timeout
- [ ] Session management
- [ ] Access log configuration

---

## 📱 EPIC-16: Mobile-Specific Features

**Goal**: Leverage mobile device capabilities.

### STORY-16-01: Mobile Camera Integration
**As a** User
**I want** to use camera for barcodes and receipts
**So that** data entry is faster.

**Acceptance Criteria:**
- [ ] Barcode scanning with camera
- [ ] Receipt photo capture
- [ ] Image storage and management
- [ ] OCR for receipt processing (optional)

### STORY-16-02: Mobile Notifications
**As a** User
**I want** push notifications for important events
**So that** I stay informed.

**Acceptance Criteria:**
- [ ] Low stock alerts
- [ ] Payment reminders
- [ ] Overdue invoice notifications
- [ ] System messages

---

## 🌐 EPIC-17: Web-Specific Features

**Goal**: Optimize for web platform.

### STORY-17-01: Web Responsive Design
**As a** Web User
**I want** the app to work perfectly in browsers
**So that** I can use it on any computer.

**Acceptance Criteria:**
- [ ] Keyboard navigation support
- [ ] Mouse hover states
- [ ] Browser printing optimization
- [ ] Web-specific shortcuts

### STORY-17-02: Web Performance
**As a** Web User
**I want** fast loading and smooth performance
**So that** the web app is responsive.

**Acceptance Criteria:**
- [ ] Lazy loading for large datasets
- [ ] Virtual scrolling for lists
- [ ] Caching strategies
- [ ] Progressive Web App features

---

## 🧪 EPIC-18: Testing & Quality Assurance

**Goal**: Comprehensive testing strategy.

### STORY-18-01: Unit Testing Suite
**As a** Developer
**I want** complete unit test coverage
**So that** code quality is high.

**Acceptance Criteria:**
- [ ] All services unit tested
- [ ] All Blocs unit tested
- [ ] All utilities unit tested
- [ ] Minimum 80% code coverage

### STORY-18-02: Integration Testing
**As a** Developer
**I want** integration tests for critical flows
**So that** components work together.

**Acceptance Criteria:**
- [ ] Sales flow integration test
- [ ] Purchase flow integration test
- [ ] Database integration tests
- [ ] API integration tests (Phase 2)

### STORY-18-03: UI Testing
**As a** QA Engineer
**I want** automated UI tests
**So that** user flows are verified.

**Acceptance Criteria:**
- [ ] Critical user journey tests
- [ ] Cross-platform UI tests
- [ ] Accessibility tests
- [ ] Performance tests

### STORY-18-04: Performance Testing
**As a** Developer
**I want** to verify performance under load
**So that** the app handles large data.

**Acceptance Criteria:**
- [ ] Large dataset handling (10k+ products)
- [ ] Memory usage monitoring
- [ ] Database query optimization
- [ ] Real-time sync performance

---

## 📚 EPIC-19: Documentation & Training

**Goal**: Complete documentation and training materials.

### STORY-19-01: Technical Documentation
**As a** Developer
**I want** comprehensive technical documentation
**So that** onboarding is smooth.

**Acceptance Criteria:**
- [ ] API documentation
- [ ] Database schema documentation
- [ ] Architecture documentation
- [ ] Deployment guide

### STORY-19-02: User Documentation
**As a** User
**I want** clear user guides
**So that** I can learn the system.

**Acceptance Criteria:**
- [ ] User manual
- [ ] Video tutorials (optional)
- [ ] FAQ section
- [ ] Contextual help

---

## 🚀 EPIC-20: Future Enhancements

**Goal**: Prepare for future features and scalability.

### STORY-20-01: Multi-Store Support
**As a** Business Owner
**I want** to manage multiple stores
**So that** I can expand my business.

**Acceptance Criteria:**
- [ ] Store switching
- [ ] Inter-store transfers
- [ ] Consolidated reporting
- [ ] Store-specific settings

### STORY-20-02: Online Sync (Phase 2)
**As a** User
**I want** to sync data across devices
**So that** I can access data anywhere.

**Acceptance Criteria:**
- [ ] Cloud sync setup
- [ ] Conflict resolution
- [ ] Offline-first sync
- [ ] Multi-device support

### STORY-20-03: Advanced Analytics
**As a** Manager
**I want** advanced business analytics
**So that** I can make data-driven decisions.

**Acceptance Criteria:**
- [ ] Sales trend analysis
- [ ] Customer segmentation
- [ ] Product performance analytics
- [ ] Predictive inventory

---

## 📊 EPIC-21: Advanced Dashboard & Analytics

**Goal**: Comprehensive dashboard with real-time KPIs, charts, and business insights.

### STORY-21-01: Executive Dashboard
**As a** Manager
**I want** a comprehensive dashboard with KPIs and charts
**So that** I can monitor business performance at a glance.

**Acceptance Criteria:**
- [ ] Today's sales summary with real-time updates
- [ ] Weekly/monthly sales chart using fl_chart
- [ ] Low stock alerts with quick re-order links
- [ ] Recent transactions list with drill-down
- [ ] Quick "New Sale" FAB
- [ ] Store logo and company name display
- [ ] Currency switcher (if multiple currencies enabled)
- [ ] Date range selector for dashboard data

### STORY-21-02: Advanced Analytics Widgets
**As a** Business Owner
**I want** customizable dashboard widgets
**So that** I can track metrics important to my business.

**Acceptance Criteria:**
- [ ] Drag-and-drop widget arrangement
- [ ] Widget library: Sales, Inventory, Financial, Customer metrics
- [ ] Custom date ranges for each widget
- [ ] Widget resizing options
- [ ] Save/load dashboard layouts
- [ ] Export dashboard as PDF
- [ ] Real-time widget updates

### STORY-21-03: Business Intelligence Insights
**As a** Manager
**I want** AI-powered business insights
**So that** I can make data-driven decisions.

**Acceptance Criteria:**
- [ ] Sales trend analysis with predictions
- [ ] Best-selling products identification
- [ ] Customer purchase patterns
- [ ] Seasonal trend detection
- [ ] Profit margin analysis
- [ ] Inventory turnover recommendations

---

## 🔍 EPIC-22: Advanced Search & Filtering

**Goal**: Powerful search capabilities with autocomplete and smart filters.

### STORY-22-01: Universal Search
**As a** User
**I want** a universal search bar across all modules
**So that** I can find anything quickly.

**Acceptance Criteria:**
- [ ] Global search bar in app header
- [ ] Search across products, customers, suppliers, transactions
- [ ] Autocomplete suggestions as you type
- [ ] Recent searches history
- [ ] Search result categorization
- [ ] Quick actions from search results
- [ ] Keyboard shortcut (Ctrl+K) for desktop

### STORY-22-02: Advanced Filtering System
**As a** Power User
**I want** advanced filtering with saved presets
**So that** I can quickly access filtered views.

**Acceptance Criteria:**
- [ ] Multi-field filtering with AND/OR logic
- [ ] Date range presets (Today, This Week, This Month, etc.)
- [ ] Save filter presets with custom names
- [ ] Share filter presets with other users
- [ ] Filter combinations (complex queries)
- [ ] Quick filter buttons for common scenarios

### STORY-22-03: Smart Search AI
**As a** User
**I want** intelligent search that understands my intent
**So that** I can find what I need even with typos.

**Acceptance Criteria:**
- [ ] Fuzzy search with typo tolerance
- [ ] Synonym recognition (e.g., "client" = "customer")
- [ ] Search by partial matches
- [ ] Search by attributes (e.g., "red products")
- [ ] Voice search support (mobile)
- [ ] Search result relevance scoring

---

## ⚡ EPIC-23: Performance & Optimization

**Goal**: Ensure smooth performance with large datasets.

### STORY-23-01: Lazy Loading & Virtual Scrolling
**As a** User
**I want** the app to remain fast with thousands of records
**So that** performance doesn't degrade as data grows.

**Acceptance Criteria:**
- [ ] Lazy loading for product lists (load 50 at a time)
- [ ] Virtual scrolling for large lists
- [ ] Infinite scroll with loading indicators
- [ ] Pagination controls for reports
- [ ] Background data pre-fetching
- [ ] Memory usage optimization

### STORY-23-02: Smart Caching Strategy
**As a** User
**I want** instant loading of frequently accessed data
**So that** the app feels responsive.

**Acceptance Criteria:**
- [ ] In-memory caching for recent data
- [ ] Persistent cache for frequently accessed reports
- [ ] Cache invalidation on data changes
- [ ] Offline cache management
- [ ] Cache size limits and cleanup
- [ ] Cache statistics for debugging

### STORY-23-03: Database Optimization
**As a** Developer
**I want** optimized database queries
**So that** the app remains fast with large datasets.

**Acceptance Criteria:**
- [ ] Database indexes on frequently queried fields
- [ ] Query optimization for reports
- [ ] Connection pooling for database access
- [ ] Query performance monitoring
- [ ] Database health checks
- [ ] Automatic query plan analysis

---

## 🎨 EPIC-24: Enhanced User Experience

**Goal**: Modern UX with advanced interactions and accessibility.

### STORY-24-01: Advanced Interactions
**As a** User
**I want** modern UI interactions
**So that** the app feels intuitive and responsive.

**Acceptance Criteria:**
- [ ] Drag & drop for list reordering
- [ ] Swipe actions for mobile (archive, delete, etc.)
- [ ] Pull-to-refresh on all lists
- [ ] Hover states and micro-animations
- [ ] Loading skeletons for better perceived performance
- [ ] Haptic feedback on mobile

### STORY-24-02: Keyboard Shortcuts
**As a** Desktop User
**I want** keyboard shortcuts for common actions
**So that** I can work more efficiently.

**Acceptance Criteria:**
- [ ] Ctrl+N: New sale
- [ ] Ctrl+K: Global search
- [ ] Ctrl+S: Save current form
- [ ] Escape: Close dialog/cancel
- [ ] Ctrl+P: Print current document
- [ ] Shortcut help dialog (Ctrl+?)
- [ ] Customizable shortcuts

### STORY-24-03: Accessibility Features
**As a** User with Disabilities
**I want** the app to be fully accessible
**So that** I can use it regardless of my abilities.

**Acceptance Criteria:**
- [ ] Screen reader support
- [ ] High contrast mode
- [ ] Large text option
- [ ] Focus management for keyboard navigation
- [ ] ARIA labels for all interactive elements
- [ ] Color blind friendly palette
- [ ] Voice control support (optional)

---

## 📱 EPIC-25: Mobile-First Features

**Goal**: Leverage mobile device capabilities for enhanced functionality.

### STORY-25-01: Advanced Camera Features
**As a** Mobile User
**I want** advanced camera integration
**So that** data entry is faster and more accurate.

**Acceptance Criteria:**
- [ ] Barcode scanning with auto-focus
- [ ] QR code scanning for quick actions
- [ ] Receipt OCR for expense entry
- [ ] Document scanning for attachments
- [ ] Image cropping and enhancement
- [ ] Batch barcode scanning

### STORY-25-02: Mobile Gestures
**As a** Mobile User
**I want** intuitive gesture controls
**So that** navigation is natural on touch devices.

**Acceptance Criteria:**
- [ ] Swipe to delete/archive
- [ ] Pinch to zoom on images and documents
- [ ] Long press for context menus
- [ ] Two-finger tap for quick actions
- [ ] Swipe between screens
- [ ] Gesture tutorial for new users

### STORY-25-03: Offline Sync Indicators
**As a** Mobile User
**I want** clear sync status indicators
**So that** I know when data is synchronized.

**Acceptance Criteria:**
- [ ] Sync status indicator in app bar
- [ ] Last sync timestamp
- [ ] Pending changes counter
- [ ] Sync progress indicators
- [ ] Offline mode banner
- [ ] Manual sync button
- [ ] Sync conflict notifications

---

## 🔔 EPIC-26: Advanced Notifications System

**Goal**: Comprehensive notification system with smart alerts.

### STORY-26-01: Smart Notifications
**As a** User
**I want** intelligent notifications for important events
**So that** I never miss critical business events.

**Acceptance Criteria:**
- [ ] Low stock alerts with re-order links
- [ ] Payment reminders for overdue invoices
- [ ] Sales milestone achievements
- [ ] Unusual activity alerts
- [ ] Daily/weekly business summaries
- [ ] Custom notification rules
- [ ] Do not disturb hours

### STORY-26-02: Notification Management
**As a** User
**I want** control over my notifications
**So that** I'm not overwhelmed.

**Acceptance Criteria:**
- [ ] Notification preferences per type
- [ ] Quiet hours configuration
- [ ] Notification history (last 30 days)
- [ ] Mark as read/unread functionality
- [ ] Notification search and filtering
- [ ] Bulk notification actions
- [ ] Export notification logs

### STORY-26-03: Push Notifications (Mobile)
**As a** Mobile User
**I want** push notifications for critical events
**So that** I stay informed even when app is closed.

**Acceptance Criteria:**
- [ ] Push notification setup and permissions
- [ ] Critical alerts (stock out, payment due)
- [ ] Daily sales summary notifications
- [ ] Achievement notifications
- [ ] Deep linking from notifications
- [ ] Notification grouping
- [ ] Notification scheduling

---

## 🛒 EPIC-27: Advanced Sales Features

**Goal**: Enhanced POS capabilities for better sales experience.

### STORY-27-01: Quick Sale Mode
**As a** Cashier
**I want** a simplified quick sale interface
**So that** I can process high-volume sales faster.

**Acceptance Criteria:**
- [ ] Simplified POS interface with essential fields only
- [ ] Product search by barcode or name
- [ ] Quick cash payment option
- [ ] Automatic receipt printing
- [ ] Customer selection optional
- [ ] One-click sale completion
- [ ] Toggle between full and quick mode

### STORY-27-02: Customer Loyalty Program
**As a** Business Owner
**I want** a customer loyalty system
**So that** I can reward repeat customers.

**Acceptance Criteria:**
- [ ] Points accumulation system
- [ ] Loyalty tiers (Bronze, Silver, Gold)
- [ ] Rewards redemption system
- [ ] Special discounts for loyal customers
- [ ] Loyalty card generation
- [ ] Points expiration management
- [ ] Loyalty analytics reports

### STORY-27-03: Advanced Discount System
**As a** Manager
**I want** flexible discount options
**So that** I can run various promotions.

**Acceptance Criteria:**
- [ ] Percentage discounts
- [ ] Fixed amount discounts
- [ ] Buy X get Y free promotions
- [ ] Category-wide discounts
- [ ] Time-limited promotions
- [ ] Customer-specific discounts
- [ ] Discount analytics and impact tracking

---

## 📦 EPIC-28: Advanced Inventory Management

**Goal**: Sophisticated inventory control and optimization.

### STORY-28-01: Inventory Forecasting
**As a** Manager
**I want** inventory demand forecasting
**So that** I can optimize stock levels.

**Acceptance Criteria:**
- [ ] Sales trend analysis for forecasting
- [ ] Seasonal demand prediction
- [ ] Automated reorder point calculation
- [ ] Stock optimization recommendations
- [ ] Excess stock identification
- [ ] Forecast accuracy tracking
- [ ] Manual forecast adjustments

### STORY-28-02: Batch Tracking
**As a** Business Owner
**I want** to track product batches
**So that** I can manage expiration and recalls.

**Acceptance Criteria:**
- [ ] Batch number assignment
- [ ] Expiration date tracking
- [ ] Batch-specific cost tracking
- [ ] FIFO/LIFO costing methods
- [ ] Batch recall functionality
- [ ] Expiration alerts
- [ ] Batch profitability analysis

### STORY-28-03: Multi-Location Inventory
**As a** Multi-Store Owner
**I want** to track inventory across locations
**So that** I can optimize stock distribution.

**Acceptance Criteria:**
- [ ] Location-based inventory tracking
- [ ] Inter-store transfer management
- [ ] Consolidated inventory view
- [ ] Location-specific reorder points
- [ ] Transfer cost tracking
- [ ] Location performance comparison
- [ ] Automated transfer suggestions

---

## 🔐 EPIC-29: Advanced Security & Compliance

**Goal**: Enterprise-grade security with audit trails.

### STORY-29-01: Advanced Security Features
**As a** Business Owner
**I want** enhanced security controls
**So that** my business data is protected.

**Acceptance Criteria:**
- [ ] Two-factor authentication (2FA)
- [ ] Session timeout configuration
- [ ] Concurrent session limits
- [ ] IP address restrictions
- [ ] Failed login lockout
- [ ] Password strength requirements
- [ ] Security audit logs

### STORY-29-02: Data Encryption
**As a** Developer
**I want** data encryption at rest and in transit
**So that** sensitive data is always protected.

**Acceptance Criteria:**
- [ ] Database encryption
- [ ] API communication encryption
- [ ] Backup encryption
- [ ] Sensitive field encryption (SSN, etc.)
- [ ] Key management system
- [ ] Encryption compliance reporting

### STORY-29-03: Compliance Features
**As a** Business Owner
**I want** compliance with regulations
**So that** I meet legal requirements.

**Acceptance Criteria:**
- [ ] GDPR compliance features
- [ ] Data retention policies
- [ ] Right to be forgotten
- [ ] Audit trail for all actions
- [ ] Compliance reporting
- [ ] Data export for portability
- [ ] Privacy policy integration

---

## 📊 EPIC-30: Business Intelligence & Reporting

**Goal**: Advanced analytics and custom reporting capabilities.

### STORY-30-01: Custom Report Builder
**As a** Manager
**I want** to create custom reports
**So that** I can analyze data specific to my needs.

**Acceptance Criteria:**
- [ ] Drag-and-drop report builder
- [ ] Custom field selection
- [ ] Filter and grouping options
- [ ] Chart type selection
- [ ] Report template library
- [ ] Save and share custom reports
- [ ] Scheduled report generation

### STORY-30-02: Data Visualization Suite
**As a** Business Analyst
**I want** advanced data visualization
**So that** I can present data effectively.

**Acceptance Criteria:**
- [ ] Multiple chart types (bar, line, pie, area, scatter)
- [ ] Interactive dashboards
- [ ] Drill-down capabilities
- [ ] Heat maps for geographic data
- [ ] Trend analysis with annotations
- [ ] Comparison views
- [ ] Export visualizations as images

### STORY-30-03: Predictive Analytics
**As a** Business Owner
**I want** predictive analytics for business planning
**So that** I can make proactive decisions.

**Acceptance Criteria:**
- [ ] Sales forecasting with ML
- [ ] Customer churn prediction
- [ ] Inventory optimization suggestions
- [ ] Cash flow forecasting
- [ ] Market trend analysis
- [ ] What-if scenario modeling
- [ ] Prediction accuracy tracking

---

## 🌐 EPIC-31: Multi-Store & Franchise Support

**Goal**: Support for multiple stores and franchise operations.

### STORY-31-01: Multi-Store Management
**As a** Franchise Owner
**I want** to manage multiple stores
**So that** I can oversee my entire operation.

**Acceptance Criteria:**
- [ ] Store switching interface
- [ ] Consolidated reporting across stores
- [ ] Store-specific settings
- [ ] Inter-store inventory transfers
- [ ] Centralized user management
- [ ] Store performance comparison
- [ ] Franchise fee tracking

### STORY-31-02: Role-Based Store Access
**As a** Multi-Store Manager
**I want** to control user access per store
**So that** staff only see relevant stores.

**Acceptance Criteria:**
- [ ] Store-specific user roles
- [ ] Permission matrix per store
- [ ] Temporary access grants
- [ ] Access request workflow
- [ ] Audit trail for store access
- [ ] Bulk user management

### STORY-31-03: Consolidated Operations
**As a** Regional Manager
**I want** consolidated view of all operations
**So that** I can make strategic decisions.

**Acceptance Criteria:**
- [ ] Multi-store dashboard
- [ ] Consolidated financial reports
- [ ] Cross-store inventory view
- [ ] Regional performance metrics
- [ ] Bulk operations across stores
- [ ] Store benchmarking

---

## 🔧 EPIC-32: Developer Experience & Tools

**Goal**: Excellent developer experience with comprehensive tooling.

### STORY-32-01: Development Tools
**As a** Developer
**I want** comprehensive development tools
**So that** I can build and debug efficiently.

**Acceptance Criteria:**
- [ ] Debug mode with detailed logging
- [ ] Database inspector tool
- [ ] API response viewer
- [ ] Performance profiler
- [ ] Memory leak detector
- [ ] State inspector for Bloc
- [ ] Hot reload for all changes

### STORY-32-02: Automated Testing Suite
**As a** Developer
**I want** comprehensive automated testing
**So that** I can ensure code quality.

**Acceptance Criteria:**
- [ ] Unit test coverage reporting
- [ ] Integration test automation
- [ ] UI test recording and playback
- [ ] Performance regression testing
- [ ] Accessibility testing automation
- [ ] Security vulnerability scanning
- [ ] Continuous integration setup

### STORY-32-03: Documentation Generator
**As a** Developer
**I want** automatic documentation generation
**So that** documentation is always up-to-date.

**Acceptance Criteria:**
- [ ] API documentation from code comments
- [ ] Database schema documentation
- [ ] User guide generation
- [ ] Component library documentation
- [ ] Deployment guide automation
- [ ] Change log generation
