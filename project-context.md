# Tapix Project Context

> **CRITICAL**: This document is the **SINGLE SOURCE OF TRUTH** for all cross-cutting concerns, architectural patterns, and system-wide constraints. Every story, every feature, every screen MUST follow these patterns automatically.

---

## 🎯 Purpose

This document eliminates the need to repeat foundational requirements in every story. All developers and AI agents working on Tapix MUST treat this as the bible for implementation.

---

## 📋 Project Overview

**Project Name**: Tapix  
**Type**: Brownfield Rebuild  
**Track**: BMad Method  
**Phase**: Implementation (Sprint Planning)

**Business Model**: B2C (Retail) + B2B (Wholesale)  
**Architecture**: Clean Architecture + Offline-First + Real-Time Updates

---

## 🏗️ Core Architecture Patterns

### Clean Architecture Structure

```
lib/
├── core/                    # Shared infrastructure (ALWAYS USE)
│   ├── bloc/               # Base Bloc classes (RealtimeBloc)
│   ├── database/           # Drift schemas, DAOs
│   ├── services/           # Cross-cutting services
│   ├── widgets/            # Reusable UI components
│   ├── theme/              # Theme configuration
│   ├── localization/       # i18n setup
│   ├── utils/              # Helpers, extensions
│   ├── router/             # GoRouter configuration
│   └── di/                 # Dependency injection (get_it)
│
├── features/               # Feature modules (vertical slices)
│   └── {feature}/
│       ├── data/          # Repositories, data sources
│       ├── domain/        # Entities, use cases
│       └── presentation/  # Blocs, screens, widgets
│
└── main.dart
```

---

## 🔄 Real-Time State Management (MANDATORY)

### RealtimeBloc Pattern

**EVERY feature Bloc MUST extend `RealtimeBloc`** from `lib/core/bloc/realtime_bloc.dart`.

```text
// CORRECT: All blocs follow this pattern
class MyFeatureBloc extends RealtimeBloc<MyData, MyEvent> {
  final MyRepository _repository;
  
  MyFeatureBloc(this._repository) : super(const RealtimeLoading()) {
    // Register custom event handlers
  }
  
  @override
  Stream<MyData> get dataStream => _repository.watchData();
  
  @override
  void registerEventHandlers() {
    on<MyCustomEvent>(_onCustomEvent);
  }
}
```

**Key Points:**
- UI updates automatically when database changes (NO manual refresh)
- Initial state is `RealtimeLoading()` by default
- Stream subscription is managed automatically
- Proper cleanup on bloc disposal
- Supports optimistic updates with rollback

**States Available:**
- `RealtimeInitial<T>` - Before any data
- `RealtimeLoading<T>` - Loading state
- `RealtimeSuccess<T>` - Data loaded successfully
- `RealtimeError<T>` - Error occurred
- `RealtimeOptimistic<T>` - Optimistic update pending

---

## 🎨 Theme System (MANDATORY)

### Semantic Colors

**ALWAYS use semantic colors** from `lib/core/theme/colors.dart`:

```text
// Access via Theme.of(context).colorScheme.extensions
final colors = Theme.of(context).colorScheme;

// Semantic colors (MUST USE for consistency)
colors.success    // Green - Success actions, confirmations
colors.warning    // Orange - Warnings, cautions
colors.error      // Red - Errors, destructive actions
colors.info       // Blue - Informational messages
```

### Theme Configuration

- **Light & Dark themes** - Both MUST work on every screen
- **Material 3 Design** - Using `flex_color_scheme`
- **Theme switching** - Real-time without app restart
- **System theme detection** - Automatic light/dark based on OS

**Theme Bloc**: `lib/core/bloc/theme_bloc.dart`  
**Theme Service**: `lib/core/services/theme_service.dart`

---

## 🌍 Localization (MANDATORY)

### Multi-Language Support

**ALL text MUST be localized** - NO hardcoded strings!

**Supported Languages:**
- English (en) - Primary
- Arabic (ar) - RTL support with IBM Plex Sans Arabic fonts
- French (fr)

### Usage Pattern

```text
import 'package:easy_localization/easy_localization.dart';

// In widgets
Text('welcome_message'.tr())
Text('greeting'.tr(args: ['Ahmed']))

// Translation files location
assets/translations/
├── en.json
├── ar.json
└── fr.json
```

### RTL Support

- **Arabic automatically uses RTL layout**
- **Directional widgets handle RTL automatically**## 📦 Product Variants System (CRITICAL)
 
> **REFERENCE**: See `docs/VARIANTS_IMPLEMENTATION_PLAN.md` for full implementation details and status.
 
### Core Variant Model
 
**EVERY sellable/stockable unit is a `ProductVariant`** - NOT the Product itself.
 
```dart
// Variant is the authoritative source for:
class ProductVariant {
  int id;
  int productId;                    // Links to Product (container)
  String? sku;                      // Optional SKU
  String? barcode;                  // Auto-generated deterministic barcode
  int? colorId;                     // Optional color reference
  int? sizeId;                      // Optional size reference
  int costCents;                    // Cost in cents (integer)
  int priceCents;                   // Price in cents (integer)
  int priceAdjustmentCents;         // Price adjustment (for future pricing rules)
  int stockQuantity;                // Stock quantity (authoritative)
  bool isActive;                    // Active/inactive status
}
```
 
### Product vs Variant Relationship
 
| Concept | Product | Variant |
|---------|---------|---------|
| **Role** | Container (name, category, description, image) | Sellable/stockable unit |
| **hasVariants=false** | Uses **single variant** as canonical unit | One variant (may have color/size) |
| **hasVariants=true** | No direct stock/cost/price | Multiple variants (each with stock/cost/price) |
| **Barcode Generation** | N/A | `29 + zeroPad(variantId, 11)` (deterministic) |
 
### Default/Single Variant Pattern
 
**Products without variants use ONE variant**:
- **Preferred**: `colorId=null, sizeId=null` (strict default)
- **Fallback**: First active variant for the product (DAO handles this)
- **Product form maps**: cost/price/stock ↔ single variant
 
### Unique Constraints (Database)
 
```sql
-- Prevent duplicate SKUs/barcodes across system
UNIQUE(product_variants.sku)
UNIQUE(product_variants.barcode)
-- Prevent duplicate variant combinations per product
UNIQUE(product_variants.product_id, product_variants.color_id, product_variants.size_id)
```
 
### Variant Management Architecture
 
**Required Layers (Clean Architecture):**
```
lib/features/products/
├── data/
│   ├── datasources/variant_local_datasource.dart
│   └── repositories/product_variant_repository_impl.dart
├── domain/
│   ├── entities/product_variant_entity.dart
│   └── repositories/product_variant_repository.dart
└── presentation/
    ├── bloc/product_variants_bloc.dart
    ├── bloc/variant_summaries_bloc.dart
    ├── screens/variants_screen.dart
    └── widgets/variant_edit_dialog.dart
```
 
### RealtimeBloc Pattern for Variants
 
```dart
class ProductVariantsBloc extends RealtimeBloc<List<ProductVariant>, ProductVariantsEvent> {
  @override
  Stream<List<ProductVariant>> get dataStream => _repository.watchAllVariants();
 
  // Events: AllVariantsInitialized, VariantsByProductInitialized, 
  //         VariantCreateRequested, VariantUpdateRequested, VariantDeleteRequested
}
```
 
### Variant Summaries (for Product List)
 
**ProductVariantRepository provides:**
```dart
Stream<Map<int, ({int count, int totalStock})>> watchVariantSummaries();
Future<({int count, int totalStock})?> getVariantSummaryByProduct(int productId);
```
 
**Used in ProductListScreen to show:**
- Variant count badge
- Total stock across variants
- "N × Stock" format
 
### SKU/Barcode Uniqueness Validation
 
**ProductFormBloc validates before save:**
```dart
// Check both products and product_variants tables
Future<Map<String, String>> _validateSkuUniqueness() async {
  // Check product-level uniqueness
  // Check variant-level uniqueness
  // Allow current variant's own values during edit
}
```
 
### Database Repair on Startup
 
**AppDatabase runs idempotent dedupe beforeOpen:**
```dart
await _dedupeUniqueSkuBarcodeIfNeeded();
// Keeps first occurrence, sets duplicates to NULL
```
 
### Variant UI Patterns
 
#### VariantsScreen (Full Management)
- **Filters**: Product, Color, Size, Stock levels, Active status
- **Search**: Barcode, SKU, Color, Size
- **Bulk Actions**: Print labels, Activate/Deactivate
- **Quick Stock**: +/- buttons for instant adjustment
- **Split View**: List + Detail panel (desktop)
 
#### VariantEditDialog (Add/Edit)
- **Sections**: Attributes, Identity (SKU/Barcode), Pricing, Stock, Status
- **Auto-generate**: Barcode (deterministic) after save
- **Validation**: Real-time uniqueness checks
- **Responsive**: Dialog (desktop) / BottomSheet (mobile)
 
### Variant State Management Rules
 
1. **Stock Authority**: Variant.stockQuantity is the single source of truth
2. **Product Stock Display**: Sum of variant stocks when hasVariants=true
3. **Default Variant**: Single variant for hasVariants=false products
4. **Barcode Stability**: Never regenerate - deterministic per variantId
5. **Active/Inactive**: Use isActive flag instead of delete for data integrity
 
### Integration Points
 
**Purchases/Sales MUST reference variantId:**
```dart
class PurchaseItem {
  int variantId;  // REQUIRED - not productId
  int quantity;
  int unitCostCents;
}
```
 
**Printing uses variant data:**
- Barcode from variant.barcode
- Product name + variant color/size
- Price from variant.priceCents
 
### Key Variant Files
 
- `lib/core/database/daos/product_variant_dao.dart` - Database operations
- `lib/features/products/data/repositories/product_variant_repository_impl.dart` - Repository
- `lib/features/products/presentation/bloc/product_variants_bloc.dart` - State management
- `lib/features/products/presentation/screens/variants_screen.dart` - Management UI
- `lib/features/products/presentation/widgets/variant_edit_dialog.dart` - Add/Edit UI
 
---
- **Test EVERY screen in Arabic** to verify RTL works

**Localization Bloc**: `lib/core/bloc/localization_bloc.dart`  
**Localization Service**: `lib/core/services/localization_service.dart`

---

## 🧭 Navigation & Routing (MANDATORY)

### GoRouter Pattern

**ALL navigation MUST use GoRouter** from `lib/core/router/app_router.dart`.

### Adding New Screens

```text
// 1. Add route to app_router.dart
GoRoute(
  path: '/my-feature',
  builder: (context, state) => const MyFeatureScreen(),
  routes: [
    GoRoute(
      path: 'detail/:id',
      builder: (context, state) {
        final id = int.tryParse(state.pathParameters['id'] ?? '');
        return MyDetailScreen(id: id);
      },
    ),
  ],
),

// 2. Navigate using context.go() or context.push()
context.go('/my-feature');
context.push('/my-feature/detail/123');

// 3. Back navigation (CRITICAL for mobile/tablet)
// AppBar automatically shows back button
// Manual back: context.pop()
```

### Back Button Behavior

**EVERY screen MUST have proper back navigation:**
- Mobile/Tablet: Back button in AppBar (automatic with Scaffold)
- Desktop: Back button optional but recommended
- Web: Browser back button works automatically

---

## 👥 Customers Module (Segmentation + Loyalty + Analytics)

### Scope

The **Customers** feature is responsible for:
- Customer CRUD (create/edit/deactivate)
- Customer segmentation (Retail / Wholesale / Premium)
- Loyalty program (tiers, points, rewards, redemptions)
- Customer analytics (health score, KPIs, trends)

This module is **offline-first** via Drift and **real-time** via `RealtimeBloc` streams.

### UI Screens (Presentation)

- **Customer Hub**: `lib/features/customers/presentation/screens/customer_hub_screen.dart`
  - Shows quick stats, segment counts, search, and customer list.
  - Must be responsive across mobile/tablet/desktop.
- **Customer Profile**: `lib/features/customers/presentation/screens/customer_profile_screen.dart`
  - 360° view: balance, loyalty, quick actions, contact information, recent transactions.
  - Uses realtime blocs to keep the profile always updated.
- **Customer Form (Add/Edit)**: `lib/features/customers/presentation/screens/customer_form_screen.dart`
  - Add/edit customer data with segmented sections.
  - Uses filled form fields and theme-aware colors.
- **Receive Payment**: `lib/features/customers/presentation/screens/receive_payment_screen.dart`
  - Record a payment for a selected customer (supports a preselected customer id via routing).

### Theme-Aware UI Rules (Light/Dark)

- Avoid hardcoded grays/whites/blacks for cards and typography.
- Prefer `Theme.of(context).colorScheme` for:
  - Backgrounds: `primaryContainer/secondaryContainer/tertiaryContainer/surface`
  - Text: `onSurface`, `onSurfaceVariant`, `onPrimaryContainer`
  - Borders: `outlineVariant`

### Loyalty Toggle + Contact Information (Customer Profile)

- `CustomerProfileScreen` includes a **loyalty enable/disable** card (switch) that updates the `customers.loyaltyEnabled` field.
- After toggling loyalty:
  - Refresh `CustomerProfileBloc` and `CustomerLoyaltyBloc` to ensure UI reflects realtime changes.
- The profile includes a **Contact Information** card which shows:
  - Email
  - Phone
  - Address
  - The section is hidden when all are null.

### Overflow Prevention Notes (Customers)

Recent fixes to eliminate `RenderFlex overflow` across devices:

- **CustomerHubScreen empty state**: replaced centered `Column` with `SingleChildScrollView` + `mainAxisSize: MainAxisSize.min`.
  - Prevents bottom overflow on short screens / large fonts.
- **CustomerHubScreen quick stats**: replaced a 3-card `Row` with a `LayoutBuilder` responsive layout.
  - Wide screens: 3 cards in one row.
  - Narrow screens: 2 cards in a row + 1 card below.
- **CustomerProfileScreen quick actions**: replaced a fixed 3-button `Row` with a `LayoutBuilder` responsive layout.
  - Wide screens: 3 buttons in one row.
  - Narrow screens: 2 buttons in a row + 1 button below.
  - Button labels enforce `maxLines: 1` and `TextOverflow.ellipsis`.
- **ReceivePaymentScreen selected customer tile**: made the customer name `Expanded` with ellipsis and wrapped the segment badge with `Flexible`.
  - Prevents overflow when names are long or text scale factor is high.

### Key Database Schema

#### `customers` table (advanced fields)

The following fields are authoritative for segmentation + loyalty + analytics:
- `segment` (TEXT, NOT NULL, default `retail`)
- `loyalty_tier_id` (INTEGER, nullable FK to `loyalty_tiers.id`)
- `loyalty_points_balance` (INTEGER, NOT NULL, default 0)
- `total_spent_cents` (INTEGER, NOT NULL, default 0)
- `total_transactions` (INTEGER, NOT NULL, default 0)
- `last_transaction_at` (TEXT/DateTime nullable)

#### Loyalty tables

- `loyalty_tiers`
  - Tiers are seeded and used to determine benefits.
  - Hybrid benefits fields:
    - `points_multiplier` (REAL)
    - `discount_percent` (REAL)
    - `free_shipping` (BOOL stored as INTEGER)
    - `free_shipping_min_order_cents` (INTEGER nullable)
    - `priority_support` (BOOL)
    - `early_access_days` (INTEGER)
    - `exclusive_offers` (BOOL)
    - `birthday_bonus` (BOOL)
    - `birthday_bonus_points` (INTEGER)
    - `birthday_discount_percent` (REAL)
    - `badge_text` (TEXT nullable)
- `loyalty_point_transactions` (earn/redeem ledger)
- `loyalty_rewards` (catalog)
- `customer_reward_redemptions` (redemption history)
- `loyalty_settings` (program-level knobs like points per currency unit)

### Migrations & Safety Nets (CRITICAL)

Because customers/loyalty evolved in a brownfield DB, the project relies on:
- Versioned migrations in `AppDatabase.migration.onUpgrade`
- `_ensureSchemaIntegrity()` as a fallback to add missing columns/tables

When adding new columns to an existing table:
- Add migration step using `_safeAddColumn()`
- Also add the same column inside `_ensureSchemaIntegrity()`

### Seeding (Idempotent)

Default loyalty tiers are seeded via `_seedDefaultLoyaltyTiers()`.
- The seed is **idempotent** (upsert by `name`) and safe to call repeatedly.
- It is called from `_seedInitialData()` and also in migration for older DBs.

Default tiers shipped:
- Bronze
- Silver
- Gold
- Premium

### Domain & Data Layer

#### Key entities
- `Customer` (from Drift `customers` table)
- `CustomerLoyaltySummary` (domain summary for profile UI)
- `TierBenefitsSummary` and `TierBenefit` (UI-friendly benefit mapping)

#### Repositories
- `CustomerRepository`
  - `createCustomer(...)` supports `segment` and persists it
  - `watchAllCustomers`, `watchCustomer`, `searchCustomers`, etc.
- `LoyaltyRepository`
  - Tier/points/rewards operations, settings updates

### Presentation Layer

#### Customer Form (segment selection)
- Screen: `lib/features/customers/presentation/screens/customer_form_screen.dart`
- Adds a segment dropdown with values:
  - `retail`
  - `wholesale`
  - `premium`
- Saves segment via `CustomerFormBloc` -> `CustomerRepository.createCustomer/updateCustomer`.

#### Customer Profile (loyalty hybrid benefits)
- Screen: `lib/features/customers/presentation/screens/customer_profile_screen.dart`
- Uses `CustomerLoyaltyBloc` to load `CustomerLoyaltySummary`
- Displays:
  - points balance
  - tier progress
  - **current tier benefits chips** (hybrid)
  - **next tier benefits** bottom sheet (to reduce confusion and show what to unlock)

#### Customer Hub (segments + trends)
- Screen: `lib/features/customers/presentation/screens/customer_hub_screen.dart`
- Shows segment overview counts and analytics sections.

### Localization Keys

Customers keys are under `customers.*` in:
- `assets/translations/en.json`
- `assets/translations/ar.json`
- `assets/translations/fr.json`

Important keys:
- `customers.segment`, `customers.segment_hint`
- `customers.segment_retail`, `customers.segment_wholesale`, `customers.segment_premium`
- Loyalty benefit keys (hybrid):
  - `customers.benefit_points_multiplier`
  - `customers.benefit_discount`
  - `customers.benefit_free_shipping`
  - `customers.benefit_priority_support`
  - `customers.benefit_early_access`
  - `customers.benefit_exclusive_offers`
  - `customers.benefit_birthday_bonus`
  - `customers.your_benefits`, `customers.next_tier_benefits`, `customers.tier_progress`

### Integration Points

When implementing Sales/POS checkout logic later, integrate hybrid benefits as follows:
- **Discount**: apply `loyalty_tiers.discount_percent` automatically for the customer tier
- **Points**: earn base points from `loyalty_settings.points_per_currency_unit` then multiply by `loyalty_tiers.points_multiplier`
- **Redemptions**: use `loyalty_rewards` and persist to `customer_reward_redemptions`
- **Analytics counters**: update customer totals (`total_spent_cents`, `total_transactions`, `last_transaction_at`) during sale posting

UX rules learned from research:
- Always show "what I get" (benefits) directly in the customer view
- Show progress visually toward next tier
- Keep redemption flows simple (show eligible rewards clearly)

**DO NOT override back button** unless absolutely necessary!

---

## 📱 Responsive Design (MANDATORY)

### Platform Support

**EVERY screen MUST work on ALL platforms:**
- ✅ Mobile (Android, iOS) - 320px+ width
- ✅ Tablet - 768px+ width
- ✅ Desktop (Windows, Linux, macOS) - 1024px+ width
- ✅ Web (WASM) - All screen sizes

### Responsive Layout Pattern

```text
// Use LayoutBuilder or MediaQuery
LayoutBuilder(
  builder: (context, constraints) {
    if (constraints.maxWidth < 600) {
      return MobileLayout();
    } else if (constraints.maxWidth < 1024) {
      return TabletLayout();
    } else {
      return DesktopLayout();
    }
  },
)

// Or use responsive_framework (already in dependencies)
```

### Screen Size Testing

**MUST test on:**
- Mobile portrait (375x667)
- Mobile landscape (667x375)
- Tablet (768x1024)
- Desktop (1920x1080)
- NO overflow allowed on ANY screen size!

### Overflow Prevention Checklist (MANDATORY)

When adding or modifying UI (especially in Customers screens), apply these rules:

- **[Rows with text]**
  - If a `Row` contains text that can grow (names, emails, translated strings):
    - Wrap the text in `Expanded` or `Flexible`.
    - Add `maxLines: 1` + `overflow: TextOverflow.ellipsis`.
- **[Narrow screens]**
  - Any 3+ item horizontal layout must be responsive:
    - Use `LayoutBuilder` to switch to a 2+1 or vertical layout.
- **[Empty states & dialogs]**
  - If using a centered `Column`, prefer `SingleChildScrollView` to avoid vertical overflow.
- **[Wrap for chips]**
  - Use `Wrap` (not a fixed `Row`) for chips/buttons so they can flow to the next line.
- **[Text scale]**
  - Assume users can increase font size. Prevent overflow using flexible layouts and ellipsis.

---

## 💰 Money Calculations (CRITICAL)

### Integer Cents Pattern

**ALL money values MUST be stored as INTEGER cents** - NEVER use `double` or `float`!

```text
// CORRECT: Store in cents
int priceInCents = 1999; // $19.99
int totalCents = quantity * priceInCents;

// Display to user
String displayPrice = (priceInCents / 100).toStringAsFixed(2);

// WRONG: NEVER DO THIS
double price = 19.99; // ❌ FLOATING POINT ERRORS!
```

### Decimal Package

For complex calculations, use `decimal` package:

```text
import 'package:decimal/decimal.dart';

Decimal subtotal = Decimal.parse('100.00');
Decimal discount = Decimal.parse('15.50');
Decimal total = subtotal - discount; // Exact precision
```

**Database Schema:**
- All money columns are `INTEGER` (cents)
- Column naming: `price_cents`, `total_cents`, `balance_cents`

---

## 📦 Product Variants System (CRITICAL)

> **REFERENCE**: See `docs/VARIANTS_IMPLEMENTATION_PLAN.md` for full implementation details and status.

### Core Variant Model

**EVERY sellable/stockable unit is a `ProductVariant`** - NOT the Product itself.

```text
// Variant is the authoritative source for:
class ProductVariant {
  int id;
  int productId;                    // Links to Product (container)
  String? sku;                      // Optional SKU
  String? barcode;                  // Auto-generated deterministic barcode
  int? colorId;                     // Optional color reference
  int? sizeId;                      // Optional size reference
  int costCents;                    // Cost in cents (integer)
  int priceCents;                   // Price in cents (integer)
  int priceAdjustmentCents;         // Price adjustment (for future pricing rules)
  int stockQuantity;                // Stock quantity (authoritative)
  bool isActive;                    // Active/inactive status
}
```

### Product vs Variant Relationship

| Concept | Product | Variant |
|---------|---------|---------|
| **Role** | Container (name, category, description, image) | Sellable/stockable unit |
| **hasVariants=false** | Uses **single variant** as canonical unit | One variant (may have color/size) |
| **hasVariants=true** | No direct stock/cost/price | Multiple variants (each with stock/cost/price) |
| **Barcode Generation** | N/A | `29 + zeroPad(variantId, 11)` (deterministic) |

### Default/Single Variant Pattern

**Products without variants use ONE variant**:
- **Preferred**: `colorId=null, sizeId=null` (strict default)
- **Fallback**: First active variant for the product (DAO handles this)
- **Product form maps**: cost/price/stock ↔ single variant

### Unique Constraints (Database)

```sql
-- Prevent duplicate SKUs/barcodes across system
UNIQUE(product_variants.sku)
UNIQUE(product_variants.barcode)
-- Prevent duplicate variant combinations per product
UNIQUE(product_variants.product_id, product_variants.color_id, product_variants.size_id)
```

### Variant Management Architecture

**Required Layers (Clean Architecture):**
```
lib/features/products/
├── data/
│   ├── datasources/variant_local_datasource.dart
│   └── repositories/product_variant_repository_impl.dart
├── domain/
│   ├── entities/product_variant_entity.dart
│   └── repositories/product_variant_repository.dart
└── presentation/
    ├── bloc/product_variants_bloc.dart
    ├── bloc/variant_summaries_bloc.dart
    ├── screens/variants_screen.dart
    └── widgets/variant_edit_dialog.dart
```

### RealtimeBloc Pattern for Variants

```text
class ProductVariantsBloc extends RealtimeBloc<List<ProductVariant>, ProductVariantsEvent> {
  @override
  Stream<List<ProductVariant>> get dataStream => _repository.watchAllVariants();
  
  // Events: AllVariantsInitialized, VariantsByProductInitialized, 
  //         VariantCreateRequested, VariantUpdateRequested, VariantDeleteRequested
}
```

### Variant Summaries (for Product List)

**ProductVariantRepository provides:**
```text
Stream<Map<int, ({int count, int totalStock})>> watchVariantSummaries();
Future<({int count, int totalStock})?> getVariantSummaryByProduct(int productId);
```

**Used in ProductListScreen to show:**
- Variant count badge
- Total stock across variants
- "N × Stock" format

### SKU/Barcode Uniqueness Validation

**ProductFormBloc validates before save:**
```text
// Check both products and product_variants tables
Future<Map<String, String>> _validateSkuUniqueness() async {
  // Check product-level uniqueness
  // Check variant-level uniqueness
  // Allow current variant's own values during edit
}
```

### Database Repair on Startup

**AppDatabase runs idempotent dedupe beforeOpen:**
```text
await _dedupeUniqueSkuBarcodeIfNeeded();
// Keeps first occurrence, sets duplicates to NULL
```

### Variant UI Patterns

#### VariantsScreen (Full Management)
- **Filters**: Product, Color, Size, Stock levels, Active status
- **Search**: Barcode, SKU, Color, Size
- **Bulk Actions**: Print labels, Activate/Deactivate
- **Quick Stock**: +/- buttons for instant adjustment
- **Split View**: List + Detail panel (desktop)

#### VariantEditDialog (Add/Edit)
- **Sections**: Attributes, Identity (SKU/Barcode), Pricing, Stock, Status
- **Auto-generate**: Barcode (deterministic) after save
- **Validation**: Real-time uniqueness checks
- **Responsive**: Dialog (desktop) / BottomSheet (mobile)

### Variant State Management Rules

1. **Stock Authority**: Variant.stockQuantity is the single source of truth
2. **Product Stock Display**: Sum of variant stocks when hasVariants=true
3. **Default Variant**: Single variant for hasVariants=false products
4. **Barcode Stability**: Never regenerate - deterministic per variantId
5. **Active/Inactive**: Use isActive flag instead of delete for data integrity

### Integration Points

**Purchases/Sales MUST reference variantId:**
```text
class PurchaseItem {
  int variantId;  // REQUIRED - not productId
  int quantity;
  int unitCostCents;
}
```

**Printing uses variant data:**
- Barcode from variant.barcode
- Product name + variant color/size
- Price from variant.priceCents

### Key Variant Files

- `lib/core/database/daos/product_variant_dao.dart` - Database operations
- `lib/features/products/data/repositories/product_variant_repository_impl.dart` - Repository
- `lib/features/products/presentation/bloc/product_variants_bloc.dart` - State management
- `lib/features/products/presentation/screens/variants_screen.dart` - Management UI
- `lib/features/products/presentation/widgets/variant_edit_dialog.dart` - Add/Edit UI

---

## 🏦 Accounting Integrity (CRITICAL)

> **REFERENCE**: See `_bmad-output/planning-artifacts/TAPIX_ACCOUNTING_INTEGRITY_ARCHITECTURE.md` for complete details.

### Single Source of Truth Pattern

**ALL accounting operations MUST go through `AccountingRepository`**

```text
// ❌ WRONG: Direct database access
await db.into(accounts).insert(account);
await db.update(accounts).replace(account);

// ✅ CORRECT: Through AccountingRepository
await accountingRepository.createAccount(account);
await accountingRepository.createJournalEntry(entryData, userId);
```

### Seven Pillars of Accounting Integrity

| Pillar | Description | Implementation |
|--------|-------------|----------------|
| **Single Source of Truth** | ONE repository for all accounting data | `AccountingRepository` |
| **Immutable Transactions** | Posted transactions NEVER change | Void via reversal entries only |
| **Double-Entry Enforcement** | Every debit has matching credit | `JournalEntryService` validation |
| **Real-Time Validation** | Validate BEFORE committing | `ValidationEngine` |
| **Atomic Operations** | All-or-nothing transactions | Drift transactions |
| **Complete Audit Trail** | Every change tracked forever | `AuditLogService` |
| **Balance Reconciliation** | Continuous balance verification | `ReconciliationService` |

### Transaction Flow (MANDATORY)

**ALL financial operations MUST use `TransactionOrchestrator`:**

```text
// Sale transaction
final result = await transactionOrchestrator.executeSale(
  sale: saleData,
  userId: currentUserId,
);

// Payment transaction
final result = await transactionOrchestrator.recordCustomerPayment(
  customerId: customerId,
  amountCents: amountCents,
  paymentMethod: 'cash',
  currencyId: currencyId,
  userId: currentUserId,
);
```

### Balance Changes - ALWAYS Through Journal Entries

```text
// ❌ WRONG: Direct balance update
account.balanceCents += 1000;
await db.update(accounts).replace(account);

// ✅ CORRECT: Through journal entry
await accountingRepository.createJournalEntry(
  entryData: JournalEntryData.simple(
    description: 'Sale #123',
    debitAccountId: cashAccountId,
    creditAccountId: revenueAccountId,
    amountCents: 1000,
    currencyId: currencyId,
    autoPost: true,
  ),
  userId: userId,
);
```

### Voiding Transactions (Immutability Pattern)

```text
// ❌ WRONG: Delete or modify posted transaction
await db.delete(journalEntries).delete(entry);

// ✅ CORRECT: Create reversal entry
await accountingRepository.voidJournalEntry(
  entryId: originalEntryId,
  reason: 'Customer requested cancellation',
  userId: userId,
);
```

### Key Accounting Files

- `lib/features/accounting/data/repositories/accounting_repository.dart` - Single source of truth
- `lib/core/services/transaction_orchestrator.dart` - Transaction coordination
- `lib/core/services/validation_engine.dart` - Pre-commit validation
- `lib/core/services/audit_log_service.dart` - Change tracking
- `lib/features/accounting/domain/models/journal_entry_data.dart` - Entry data models
- `lib/features/accounting/domain/exceptions/accounting_exception.dart` - Error handling

---

## 🗄️ Database Integration (MANDATORY)

### Universal Database Wiring

**ALL components MUST be wired to the database** - NO standalone components!

**Required for Every Feature:**
- **Services** → Repository → Database (Drift)
- **Blocs** → Services → Database streams
- **UI** → Blocs → Real-time database updates
- **NO in-memory state** - Everything persists to database

**Pattern:**
```text
// Service layer
class MyService {
  final MyRepository _repository;
  
  MyService(this._repository);
  
  Stream<List<MyData>> watchData() => _repository.watchData();
  Future<void> addData(MyData data) => _repository.insert(data);
}

// Repository layer  
class MyRepository {
  final MyDatabase _database;
  
  MyRepository(this._database);
  
  Stream<List<MyData>> watchData() => _database.watchMyData();
  Future<void> insert(MyData data) => _database.into(myTable).insert(data);
}
```

---

## 📝 Input Field Behavior (MANDATORY)

### Numeric Input Fields

**ALL numeric input fields MUST clear placeholder values on focus:**

```text
// CORRECT: Clear placeholder on focus
TextFormField(
  controller: _controller,
  keyboardType: TextInputType.number,
  decoration: InputDecoration(
    hintText: '0.00', // Placeholder only
  ),
  onTap: () {
    // Clear placeholder when user focuses
    if (_controller.text == '0.00' || _controller.text.isEmpty) {
      _controller.clear();
    }
  },
  // For money fields, use CurrencyService for formatting
  onChanged: (value) {
    if (value.isNotEmpty && isMoneyField) {
      // Format with current currency settings
      final formatted = currencyService.formatInput(value);
      _controller.value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
    }
  },
)
```

**Rules:**
- **Placeholder values like "0.00", "00.0" MUST be cleared** when user taps the field
- **Money fields MUST use CurrencyService** for symbol and formatting
- **Non-money numeric fields** should clear to empty on focus
- **Restore placeholder** if field is left empty after focus loss

---

## 💱 Currency Settings (CRITICAL)

### Dynamic Currency Display

**EVERY money display MUST use the user-selected currency** from App Settings.

**Currency Service**: `lib/core/services/currency_service.dart` (to be implemented)  
**Currency Bloc**: `lib/core/bloc/currency_bloc.dart` (to be implemented)

### Pattern for Displaying Money

```text
// CORRECT: Always use CurrencyService to format money
final currencyService = sl<CurrencyService>();
final formattedPrice = currencyService.format(priceInCents);
// Example output: "€19.99" or "$19.99" or "£19.99" based on user settings

// In widgets with context
final currencyService = context.read<CurrencyBloc>().currentCurrency;
Text(currencyService.format(priceInCents))

// WRONG: Hardcoded currency symbol
Text('\$${(priceInCents / 100).toStringAsFixed(2)}') // ❌ NEVER DO THIS
```

### Currency Configuration

**User can select ANY currency:**
- USD ($) - US Dollar
- EUR (€) - Euro
- GBP (£) - British Pound
- JPY (¥) - Japanese Yen
- SAR (﷼) - Saudi Riyal
- AED (د.إ) - UAE Dirham
- EGP (£) - Egyptian Pound
- And more...

**Currency Settings stored in:**
- Database: `app_settings` table
- Fields: `currency_code`, `currency_symbol`, `symbol_position` (before/after)
- Real-time updates: When user changes currency, ALL screens update immediately

### Implementation Requirements

**CurrencyService MUST provide:**
```text
class CurrencyService {
  // Format money with current currency
  String format(int cents, {bool showSymbol = true});
  
  // Format user input (for text fields)
  String formatInput(String rawInput);
  
  // Get current currency code (e.g., "USD", "EUR")
  String get currencyCode;
  
  // Get current currency symbol (e.g., "$", "€")
  String get currencySymbol;
  
  // Symbol position (before or after amount)
  SymbolPosition get symbolPosition;
  
  // Watch for currency changes (real-time)
  Stream<Currency> watchCurrency();
}
```

**CurrencyBloc MUST:**
- Extend `RealtimeBloc<Currency, CurrencyEvent>`
- Subscribe to currency settings changes
- Emit new state when currency changes
- Trigger UI rebuild across entire app

### Where Currency Display is Required

**EVERY screen that shows money MUST use CurrencyService:**
- ✅ Product prices (list, detail, form)
- ✅ Sale totals, subtotals, discounts
- ✅ Purchase amounts
- ✅ Customer balances
- ✅ Supplier balances
- ✅ Reports (all financial reports)
- ✅ Dashboard KPIs
- ✅ Invoice PDFs
- ✅ Receipt prints
- ✅ Expense amounts
- ✅ Payment amounts

**NO hardcoded currency symbols anywhere in the app!**

### Settings Screen Integration

**Currency Settings UI MUST include:**
- Currency selector dropdown (searchable)
- Live preview of formatted amount
- Symbol position toggle (before/after)
- Decimal separator preference
- Thousands separator preference

**Example:**
```
Currency: [Euro (EUR) ▼]
Symbol: €
Position: [Before Amount ⚫] [After Amount ⚪]
Preview: €1,234.56
```

### Real-Time Currency Updates

When user changes currency in settings:
1. Update `app_settings` table
2. CurrencyService stream emits new currency
3. CurrencyBloc receives update
4. ALL screens with BlocBuilder automatically rebuild
5. ALL money displays show new currency symbol

**NO app restart required!**

---

## 🗄️ Database (Drift) Patterns

### Drift ORM

**Database**: SQLite with Drift ORM  
**Location**: `lib/core/database/`

### Key Patterns

```text
// Watch for real-time updates (ALWAYS USE)
Stream<List<Product>> watchProducts() {
  return (select(products)..where((p) => p.isActive.equals(true)))
    .watch();
}

// Single query (use sparingly)
Future<Product?> getProduct(int id) {
  return (select(products)..where((p) => p.id.equals(id)))
    .getSingleOrNull();
}

// Insert/Update/Delete
Future<int> insertProduct(ProductsCompanion product) {
  return into(products).insert(product);
}
```

### Web WASM Support

- Drift configured for Web WASM (OPFS/IndexedDB)
- Worker file: `web/drift_worker.dart`
- NO platform-specific code in database layer

---

## 🔐 Dependency Injection (MANDATORY)

### GetIt Service Locator

**ALL services and blocs MUST be registered** in `lib/core/di/injection_container.dart`.

```text
// Register services
sl.registerLazySingleton<MyService>(() => MyServiceImpl());

// Register blocs (as factories for multiple instances)
sl.registerFactory<MyBloc>(() => MyBloc(sl()));

// Usage in widgets
final myBloc = sl<MyBloc>();

// Or with BlocProvider
BlocProvider<MyBloc>(
  create: (context) => sl<MyBloc>(),
  child: MyScreen(),
)
```

---

## 🎭 UI/UX Standards

### Scaffold Pattern

**EVERY screen MUST use Scaffold:**

```text
Scaffold(
  appBar: AppBar(
    title: Text('screen_title'.tr()),
    // Back button automatic on mobile/tablet
  ),
  body: SafeArea(
    child: YourContent(),
  ),
  floatingActionButton: FloatingActionButton(...), // Optional
)
```

### Loading States

```text
// Use BlocBuilder with RealtimeBloc states
BlocBuilder<MyBloc, RealtimeState<MyData>>(
  builder: (context, state) {
    if (state is RealtimeLoading) {
      return Center(child: CircularProgressIndicator());
    }
    if (state is RealtimeError) {
      return ErrorWidget(error: state.error);
    }
    if (state is RealtimeSuccess) {
      return SuccessContent(data: state.data);
    }
    return SizedBox.shrink();
  },
)
```

### Error Handling

```text
// Show errors with SnackBar using semantic colors
ScaffoldMessenger.of(context).showSnackBar(
  SnackBar(
    content: Text('error_message'.tr()),
    backgroundColor: Theme.of(context).colorScheme.error,
  ),
);
```

---

## ✅ Testing Requirements

### Every Feature MUST Have

- **Unit tests** for Blocs (90%+ coverage)
- **Unit tests** for Services (90%+ coverage)
- **Widget tests** for critical screens
- **Integration tests** for user flows

### Test Pattern

```text
// Bloc tests
blocTest<MyBloc, RealtimeState<MyData>>(
  'emits success when data loads',
  build: () => MyBloc(mockRepository),
  act: (bloc) => bloc.add(LoadData()),
  expect: () => [
    isA<RealtimeLoading>(),
    isA<RealtimeSuccess>(),
  ],
);
```

---

## 🚫 What NOT to Do

### Common Mistakes to AVOID

❌ **Manual refresh** - Use RealtimeBloc streams instead  
❌ **Hardcoded strings** - Use localization  
❌ **Hardcoded currency symbols** - Use CurrencyService  
❌ **Double for money** - Use integer cents  
❌ **Platform-specific code** - Make it work everywhere  
❌ **Ignoring RTL** - Test in Arabic  
❌ **Manual setState** - Use Bloc pattern  
❌ **Skipping tests** - Write tests first  
❌ **Breaking back button** - Keep default behavior  
❌ **Overflow errors** - Test all screen sizes  
❌ **Direct database access** - Use repositories  
❌ **Standalone components** - Everything must be database-wired  
❌ **Placeholder text that doesn't clear** - Clear "0.00", "00.0" on focus  
❌ **Money fields without CurrencyService** - Use currency settings for formatting  

---

## 📚 Key Files Reference

### Core Infrastructure (ALWAYS REFERENCE)

- `lib/core/bloc/realtime_bloc.dart` - Base Bloc pattern
- `lib/core/theme/app_theme.dart` - Theme configuration
- `lib/core/theme/colors.dart` - Semantic colors
- `lib/core/router/app_router.dart` - Navigation setup
- `lib/core/di/injection_container.dart` - DI container
- `lib/core/services/theme_service.dart` - Theme management
- `lib/core/services/localization_service.dart` - Language management
- `lib/core/services/currency_service.dart` - Currency formatting (to be implemented)
- `lib/core/bloc/currency_bloc.dart` - Currency state management (to be implemented)

### Documentation

- `_bmad-output/planning-artifacts/TAPIX_REBUILD_SPECIFICATION.md` - Full spec
- `_bmad-output/planning-artifacts/TAPIX_EPICS_AND_STORIES.md` - All stories
- `_bmad-output/implementation-artifacts/1-3-real-time-state-management-infrastructure.md` - RealtimeBloc guide
- `_bmad-output/implementation-artifacts/1-4-theme-localization.md` - Theme/i18n guide

---

## 🎯 Story Implementation Checklist

When implementing ANY story, verify:

### Core Requirements
- [ ] Bloc extends `RealtimeBloc` with proper stream subscription
- [ ] All text is localized (no hardcoded strings)
- [ ] Theme colors use semantic extensions (success/warning/error)
- [ ] **Money displays use CurrencyService (NO hardcoded currency symbols)**
- [ ] **All components wired to database (no standalone components)**
- [ ] **Numeric input fields clear placeholders on focus**
- [ ] **Money input fields use CurrencyService.formatInput()**
- [ ] Works on mobile, tablet, desktop, and web
- [ ] Must support ALL screen sizes: mobile / tablet / desktop / laptop
- [ ] Must support ALL platforms: iOS / Android / Windows / Linux / Web
- [ ] Tested in Light AND Dark themes
- [ ] Tested in English, Arabic (RTL), and French
- [ ] **Tested with different currencies (USD, EUR, GBP, etc.)**
- [ ] Back button works correctly on mobile/tablet
- [ ] No overflow on any screen size (no RenderFlex overflow, no clipped content)
- [ ] Money values use integer cents
- [ ] Services registered in DI container
- [ ] Routes added to GoRouter
- [ ] Unit tests written (90%+ coverage)
- [ ] Widget tests for critical UI
- [ ] Real-time updates work without manual refresh

### 🏦 Accounting Integrity (For Financial Stories)

**If the story involves money, balances, or transactions:**

- [ ] All money values stored as integer cents
- [ ] All balance changes go through `AccountingRepository`
- [ ] All transactions use `TransactionOrchestrator`
- [ ] All operations validated via `ValidationEngine` BEFORE commit
- [ ] All changes logged via `AuditLogService`
- [ ] Journal entries created for balance changes (double-entry)
- [ ] Atomic transactions wrap all related changes
- [ ] Void/reversal pattern used (no direct updates to posted entries)
- [ ] Single Source of Truth: accounting calculations must be implemented once and reused
- [ ] Reports must be derived from the authoritative accounting sources (journals/ledger) without duplicating business logic
- [ ] Unit tests cover all calculations
- [ ] Integration tests verify journal entries created correctly
- [ ] Reconciliation tests pass after operation

**Affected Story Types:**
- Sales, Sale Returns
- Purchases, Purchase Returns
- Customer/Supplier Payments
- Expenses
- Price Changes
- Stock Adjustments
- Any balance modifications

### 📦 Product Variants (For Product/Variant Stories)

**If the story involves products or variants:**

- [ ] Use `ProductVariant` as sellable/stockable unit (not Product)
- [ ] For hasVariants=false: Use single variant pattern
- [ ] For hasVariants=true: Product has no direct stock/cost/price
- [ ] Barcode generation: `29 + zeroPad(variantId, 11)` (deterministic)
- [ ] SKU/Barcode uniqueness validation across products and variants
- [ ] Stock updates go to variant.stockQuantity (authoritative)
- [ ] Purchase/Sales line items use variantId (not productId)
- [ ] Use `ProductVariantsBloc` extending `RealtimeBloc`
- [ ] Use `VariantSummariesBloc` for product list variant counts
- [ ] Follow variant UI patterns (filters, bulk actions, quick stock)
- [ ] Use `VariantEditDialog` for add/edit operations
- [ ] Test with default variant fallback (null/null or first active)
- [ ] Verify database repair runs on startup for legacy duplicates

**Affected Story Types:**
- Product management (create/edit/delete)
- Variant management (add/edit/delete/bulk)
- Purchase/Sales operations
- Barcode scanning and printing
- Stock adjustments
- Import/Export operations
- Reporting by variant

---

## 🔄 Real-Time Update Flow

**Standard Pattern for ALL Features:**

```
User Action → Repository Method → Database Change → 
Drift Stream Emission → RealtimeBloc Event → 
State Update → UI Rebuild (Automatic)
```

**NO manual refresh required!** The UI updates automatically.

---

## 🌐 Platform-Specific Notes

Tapix is designed as a true multi-platform, multi-form-factor application:
- **Form factors**: mobile / tablet / desktop / laptop
- **Platforms**: iOS / Android / Windows / Linux / Web

All UI must be responsive and MUST NOT overflow on any screen.

### Web (WASM)
- Drift uses OPFS/IndexedDB backend
- Worker configured in `web/drift_worker.dart`
- Slightly higher latency (~50ms vs ~10ms native)

### Mobile (Android/iOS)
- Direct SQLite access
- Back button behavior critical
- Test on physical devices

### Desktop (Windows/Linux/macOS)
- Larger screen real estate
- Mouse hover states
- Keyboard shortcuts recommended

---

## 💡 Best Practices

1. **Always use RealtimeBloc** - Never manual state management
2. **Localize everything** - Think global from day one
3. **Test responsive** - Mobile-first, scale up
4. **Semantic colors** - Consistent UI/UX
5. **Integer cents** - Accurate money math
6. **Clean Architecture** - Separation of concerns
7. **Write tests** - Before implementation when possible
8. **Document as you go** - Update this file when patterns change

---

## 🚀 Quick Start for New Features

1. **Read this document** - Understand all patterns
2. **Check existing features** - See patterns in action (products, auth)
3. **Create feature folder** - Follow Clean Architecture structure
4. **Extend RealtimeBloc** - Use base pattern
5. **Add to DI container** - Register services/blocs
6. **Add routes** - Update GoRouter
7. **Localize strings** - Add to translation files
8. **Test everywhere** - All platforms, themes, languages
9. **Write tests** - Unit, widget, integration
10. **Update documentation** - If new patterns emerge

---

## 📞 Questions?

If you're unsure about any pattern:
1. Check this document first
2. Look at existing implementations (products, auth features)
3. Review Epic 1 & 2 implementation artifacts
4. Ask for clarification before implementing

---

**Last Updated**: 2026-01-25  
**Version**: 1.0.0  
**Status**: ACTIVE - Follow strictly for all implementations
