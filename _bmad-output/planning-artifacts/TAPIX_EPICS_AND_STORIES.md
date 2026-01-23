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

### STORY-03-01: Product List with Search & Filter
**As a** User
**I want** to view, search, and filter products
**So that** I can quickly find items.

**Acceptance Criteria:**
- [ ] List displays name, price, stock, and image
- [ ] Search by name, SKU, or barcode
- [ ] Filter by category, supplier, or stock status (low/out)
- [ ] Pagination/Infinite scroll for large datasets

### STORY-03-02: Product CRUD & Variants
**As a** Manager
**I want** to add and edit products with size/color variants
**So that** I can manage my inventory details.

**Acceptance Criteria:**
- [ ] Product form includes all fields from spec (cost, price, tax, etc.)
- [ ] Support for multiple variants (Color/Size combinations)
- [ ] Money inputs handle cents correctly
- [ ] Validation for required fields

### STORY-03-03: Barcode Management
**As a** User
**I want** to scan barcodes to find products and print labels
**So that** inventory management is efficient.

**Acceptance Criteria:**
- [ ] `mobile_scanner` integrated for camera scanning
- [ ] `barcode_widget` used to generate labels
- [ ] Barcode printing layout designed

---

## 👥 EPIC-04: Parties Management

**Goal**: Manage relationships and financial balances with Customers and Suppliers.

### STORY-04-01: Customer Management
**As a** User
**I want** to manage customer profiles and view their balances
**So that** I can track who owes money.

**Acceptance Criteria:**
- [ ] Customer CRUD (Name, Phone, Limit, etc.)
- [ ] Customer balance calculated in real-time
- [ ] Ledger view showing sales, payments, and returns

### STORY-04-02: Supplier Management
**As a** User
**I want** to manage suppliers and track my debt to them
**So that** I can handle accounts payable.

**Acceptance Criteria:**
- [ ] Supplier CRUD
- [ ] Supplier balance tracking
- [ ] Payment recording dialog

---

## 🛒 EPIC-05: Sales & POS

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

---

## 🚚 EPIC-06: Purchase Management

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

---

## 💰 EPIC-07: Finance & Accounting

**Goal**: Accurate financial tracking and accounting.

### STORY-07-01: Expenses Management
**As a** User
**I want** to record operational expenses
**So that** my profit/loss is accurate.

**Acceptance Criteria:**
- [ ] Expense CRUD with categories
- [ ] Image attachment for receipts
- [ ] Cash flow updates

### STORY-07-02: Journal Entries & General Ledger
**As a** Accountant
**I want** the system to automatically generate journal entries
**So that** the books are always balanced.

**Acceptance Criteria:**
- [ ] Auto-generate entries for Sales, Purchases, Payments
- [ ] Double-entry bookkeeping structure
- [ ] Manual journal entry form

---

## 📊 EPIC-08: Reporting

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

---

## ⚙️ EPIC-09: Settings & Admin

**Goal**: System configuration and maintenance.

### STORY-09-01: App Configuration
**As a** User
**I want** to configure currency, tax rates, and company info
**So that** the invoices reflect my business details.

**Acceptance Criteria:**
- [ ] Settings screens for Company Info, Logo, Tax, Currency
- [ ] Backup and Restore database functionality

---

## ✨ EPIC-10: Polish & QA

**Goal**: Deliver a beautiful, bug-free experience.

### STORY-10-01: UI/UX Polish
**As a** User
**I want** smooth animations and responsive layouts
**So that** the app feels modern and high-quality.

**Acceptance Criteria:**
- [ ] No overflow on any screen size
- [ ] Loading skeletons/shimmers
- [ ] Consistent padding and typography

### STORY-10-02: Comprehensive Testing
**As a** Developer
**I want** to run full regression tests
**So that** I ensure no critical bugs exist.

**Acceptance Criteria:**
- [ ] Real-time sync verified
- [ ] Money calculations verified (100% accuracy)
- [ ] Cross-platform verification (Android, Windows, Web)
