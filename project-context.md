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

## � User Management & Role Permissions (IMPLEMENTED)

### Overview

The **User Management** feature provides comprehensive control over system access with fixed roles and granular permissions. This module is **offline-first** via Drift and **real-time** via `RealtimeBloc` streams.

### Core Architecture

#### Fixed Role System (4 Roles Only)

**NO dynamic roles** - The system uses exactly 4 fixed roles defined in `UserRole` enum:

```dart
enum UserRole {
  owner,      // Full system access
  manager,    // Business operations, no user/system management
  cashier,    // Sales processing only
  salesperson // Sales + customer management
}
```

**Critical**: NEVER add or modify roles. All permission logic is hardcoded for these 4 roles.

#### Permission System

**Permissions are checked via `PermissionService`** in `lib/features/auth/data/services/permission_service.dart`:

```dart
class PermissionService {
  bool canAccess(String permission, UserRole role) {
    // Hardcoded permission matrix for 4 roles
    switch (permission) {
      case 'module_dashboard':
        return true; // All roles can access
      case 'module_users':
        return role == UserRole.owner; // Only owner
      case 'manage_products':
        return role == UserRole.owner || role == UserRole.manager;
      // ... other permissions
    }
  }
}
```

### Database Schema

#### `users` table

```sql
CREATE TABLE users (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  username TEXT NOT NULL UNIQUE,           -- Login username
  password_hash TEXT NOT NULL,             -- bcrypt hashed password
  role TEXT NOT NULL,                      -- UserRole enum value
  is_active INTEGER NOT NULL DEFAULT 1,    -- Active/inactive flag
  employee_id INTEGER NULL,                -- Optional link to employee
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  last_login_at TEXT NULL,                 -- Track last login
  FOREIGN KEY (employee_id) REFERENCES employees(id)
);
```

### Domain & Data Layer

#### Key Entities
- `UserEntity` - Domain model with `UserRole` enum
- `UserRole` - Fixed enum with 4 values (owner, manager, cashier, salesperson)

#### Repository Pattern
- `UserRepositoryInterface` - Contract with watch/CRUD methods
- `UserRepository` - Implementation using Drift + PasswordService

**Key Methods:**
```dart
// Real-time streams
Stream<List<UserEntity>> watchAllUsers();
Stream<Map<UserRole, int>> watchRoleCounts();

// CRUD operations
Future<UserEntity> createUser({...});
Future<void> updateUser({...});
Future<void> toggleUserActive(int userId, bool isActive);

// Validation
Future<bool> isUsernameTaken(String username, {int? excludeUserId});
```

### Presentation Layer

#### Screens Implemented

1. **UsersScreen** (`/users`)
   - Main dashboard with search, role filter, user list
   - Quick stats cards (total, active, by role)
   - Real-time updates via `UsersBloc`
   - Responsive layout (mobile/tablet/desktop)

2. **UserFormScreen** (`/users/add` or `/users/:id/edit`)
   - Create/edit user with sections:
     - Account Info (username, password)
     - Role & Permissions (choice chips for 4 roles)
     - Link to Employee (optional bottom sheet selector)
   - Full validation via `UserFormBloc`
   - Password hashing via `PasswordService`

3. **RolesScreen** (`/users/roles`)
   - Role overview with descriptions
   - Permission matrix comparison table
   - Interactive role selection with detailed permissions

#### Blocs

1. **UsersBloc** (extends RealtimeBloc)
   - Events: `UsersInitialized`, `UserSearchRequested`, `UserFilterByRoleRequested`, `UserToggleActiveRequested`
   - Real-time user list with search/filter
   - Stores raw data separately for correct filter re-application

2. **UserStatsBloc** (extends RealtimeBloc)
   - Watches role counts via `watchRoleCounts()`
   - Used in `UserStatsCards` widget

3. **UserFormBloc** (extends RealtimeBloc)
   - Events: `UserFormLoadRequested`, `UserFormSubmitRequested`
   - Full validation:
     - Username required, min 3 chars, uniqueness check
     - Password required for new users, min 6 chars
     - Password confirmation matching
     - Role selection required

### UI Patterns & Components

#### UserCard Widget
- Displays user info with role badge
- Shows last login time (relative format)
- Popup menu for edit/deactivate actions
- Theme-aware colors for role badges

#### UserStatsCards Widget
- 4 stat cards: Total Users, Owners, Active Users, Managers
- Responsive layout: 2×2 on mobile, 4×1 on desktop
- Uses `LayoutBuilder` for breakpoint handling

#### Role Selection UI
- Choice chips for 4 fixed roles
- Role descriptions below selection
- Visual hierarchy with icons and colors

### Security Implementation

#### Password Management
- **PasswordService** handles hashing/verification
- Uses bcrypt with salt rounds of 12
- Passwords never stored in plain text
- Optional password change on edit (leave empty to keep)

#### Authentication Flow
- Users login via `AuthRepository` (existing)
- Session managed by `SessionService` (existing)
- Role permissions checked via `PermissionGate` widget

### Integration Points

#### Employee Linking (Optional)
- Users can be linked to employee records
- Facilitates payroll and attendance tracking
- Implemented via bottom sheet selector
- Uses existing `EmployeesBloc` for selection

#### Navigation Structure
```dart
// Routes in app_router.dart
/users                          // UsersScreen
/users/add                     // UserFormScreen (create)
/users/:id/edit                // UserFormScreen (edit)
/users/roles                   // RolesScreen
```

### Localization

All user management strings are under `users.*` in:
- `assets/translations/en.json`
- `assets/translations/ar.json`
- `assets/translations/fr.json`

Key keys:
- `users.title`, `users.add`, `users.edit`
- `users.role_*` (owner, manager, cashier, salesperson)
- `users.role_*_desc` (descriptions for each role)
- Validation messages: `username_required`, `password_min_length`, etc.

### Testing Coverage

**17 tests written and passing:**
- `users_bloc_test.dart` - 6 tests (list, filter, search, toggle)
- `user_form_bloc_test.dart` - 11 tests (create, edit, validation)

All tests follow bloc_test patterns with proper mocking.

### Usage Guidelines for Other Features

When implementing new features that need user context:

1. **Get Current User**: Use `AuthBloc` state to get current user
2. **Check Permissions**: Use `PermissionService.canAccess()`
3. **Role-Based UI**: Use `PermissionGate` widget to wrap components
4. **User Selection**: Use existing user management screens - don't recreate

**Example Permission Check:**
```dart
final permissionService = sl<PermissionService>();
if (permissionService.canAccess('manage_products', currentUser.role)) {
  // Show product management features
}
```

**Example Permission Gate:**
```dart
PermissionGate(
  permission: 'view_reports',
  child: ReportsButton(),
  fallback: Container(), // Hide if no permission
)
```

### What's NOT Supported

- ❌ Dynamic role creation/editing
- ❌ Custom permissions per user
- ❌ Role hierarchy (roles are flat, not hierarchical)
- ❌ Server-side validation (offline-first only)
- ❌ OAuth/external authentication (local users only)

### Key Files Reference

**Domain Layer:**
- `lib/features/auth/domain/entities/user_entity.dart` - User entity + enum
- `lib/features/auth/domain/repositories/user_repository_interface.dart` - Contract

**Data Layer:**
- `lib/features/auth/data/repositories/user_repository.dart` - Implementation
- `lib/features/auth/data/services/password_service.dart` - Password hashing
- `lib/features/auth/data/services/permission_service.dart` - Permission checks

**Presentation Layer:**
- `lib/features/auth/presentation/bloc/users_bloc.dart` - List management
- `lib/features/auth/presentation/bloc/user_form_bloc.dart` - Form validation
- `lib/features/auth/presentation/screens/users_screen.dart` - Main UI
- `lib/features/auth/presentation/screens/user_form_screen.dart` - Create/edit
- `lib/features/auth/presentation/screens/roles_screen.dart` - Role overview
- `lib/features/auth/presentation/widgets/user_card.dart` - User list item
- `lib/features/auth/presentation/widgets/user_stats_cards.dart` - Stats display

---

## �� Responsive Design (MANDATORY)

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

## 🛒 Sales & Purchases Module (Recent Implementation)

> **NOTE**: This section documents the recent Sales/POS and Purchases enhancements that mirror each other. Both modules follow the same patterns for consistency.

### Database Schema (Drift)

#### Sales Table (v10016)

```dart
class Sales extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get invoiceNumber => text().unique()();
  IntColumn get customerId => integer().nullable().references(Customers, #id)();
  IntColumn get employeeId => integer().nullable().references(Employees, #id)();
  IntColumn get subtotalCents => integer().map(const MoneyConverter())();
  IntColumn get taxCents => integer().map(const MoneyConverter())();
  IntColumn get discountCents => integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  IntColumn get totalCents => integer().map(const MoneyConverter())();
  IntColumn get paidAmountCents => integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  IntColumn get currencyId => integer().references(Currencies, #id)();
  TextColumn get paymentMethod => text()();
  TextColumn get status => text().withDefault(const Constant('draft'))();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get saleDate => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get dueDate => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
```

#### Purchases Table (v10015)

```dart
class Purchases extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get purchaseNumber => text().unique()();
  IntColumn get supplierId => integer().references(Suppliers, #id)();
  IntColumn get subtotalCents => integer().map(const MoneyConverter())();
  IntColumn get taxCents => integer().map(const MoneyConverter())();
  IntColumn get discountCents => integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  IntColumn get totalCents => integer().map(const MoneyConverter())();
  IntColumn get paidAmountCents => integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  IntColumn get currencyId => integer().references(Currencies, #id)();
  TextColumn get status => text().withDefault(const Constant('draft'))();
  TextColumn get paymentMethod => text().nullable()();
  TextColumn get supplierInvoiceRef => text().nullable()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get purchaseDate => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get dueDate => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
```

#### Sale Returns Table (with Status & Disposition)

```dart
class SaleReturns extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get saleId => integer().references(Sales, #id, onDelete: KeyAction.restrict)();
  TextColumn get returnNumber => text().unique()();
  IntColumn get totalCents => integer().map(const MoneyConverter())();
  IntColumn get currencyId => integer().references(Currencies, #id)();
  TextColumn get reason => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('draft'))(); // draft/posted/voided
  TextColumn get dispositionType => text().withDefault(const Constant('restock'))(); // restock/exchange/store_credit/refund/write_off
  DateTimeColumn get returnDate => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
```

#### Sale Return Items Table (with Per-Item Reason)

```dart
class SaleReturnItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get returnId => integer().references(SaleReturns, #id, onDelete: KeyAction.cascade)();
  IntColumn get saleItemId => integer().references(SaleItems, #id, onDelete: KeyAction.restrict)();
  IntColumn get quantity => integer()();
  IntColumn get refundCents => integer().map(const MoneyConverter())();
  TextColumn get reason => text().nullable()(); // Per-item reason (damaged/wrong_item/quality/overstock/other)
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
```

#### Payments Tables (Multi-Payment Tracking)

Both Sales and Purchases support partial payments:

```dart
// SalePayments table
class SalePayments extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get saleId => integer().references(Sales, #id, onDelete: KeyAction.cascade)();
  IntColumn get amountCents => integer().map(const MoneyConverter())();
  DateTimeColumn get paymentDate => dateTime()();
  TextColumn get paymentMethod => text()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

// PurchasePayments table (mirrors SalePayments)
class PurchasePayments extends Table { ... }
```

### Domain Entities

#### SaleEntity (with Computed Properties)

```dart
class SaleEntity extends Equatable {
  // ... fields
  
  // Computed payment status
  Decimal get remainingCents => totalCents - paidAmountCents;
  bool get isFullyPaid => paidAmountCents >= totalCents;
  bool get isOverdue => dueDate != null && !isFullyPaid && DateTime.now().isAfter(dueDate!);
  
  // Status helpers
  bool get isDraft => status == 'draft';
  bool get isCompleted => status == 'completed';
  bool get isVoided => status == 'voided';
}
```

### UI Patterns for Detail Screens

Both Sales and Purchases detail screens share identical UI patterns:

#### Payment Tracking Section (in Totals Card)

```dart
// Shows paid/remaining amounts with color coding
if (sale.totalCents > Decimal.zero)
  Container(
    decoration: BoxDecoration(
      color: sale.isFullyPaid
          ? Colors.green.withValues(alpha: 0.06)
          : sale.isOverdue
              ? colorScheme.error.withValues(alpha: 0.06)
              : colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
    ),
    child: Column(
      children: [
        // Paid row with checkmark icon (green when fully paid)
        Row(...),
        // Remaining row (red when overdue)
        if (!sale.isFullyPaid) Row(...),
      ],
    ),
  );
```

#### Overdue Badge Pattern

```dart
if (sale.isOverdue)
  Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: colorScheme.error.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: colorScheme.error.withValues(alpha: 0.3)),
    ),
    child: Row(
      children: [
        Icon(LucideIcons.alertTriangle, size: 16, color: colorScheme.error),
        const SizedBox(width: 8),
        Text('sales.overdue'.tr(), ...),
      ],
    ),
  );
```

#### Notes Card Pattern

```dart
// Only shows when notes exist
if (sale.notes != null && sale.notes!.isNotEmpty)
  Card(
    child: Column(
      children: [
        // Header with sticky note icon
        Row(...),
        // Notes text in container
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
          ),
          child: Text(sale.notes!, ...),
        ),
      ],
    ),
  );
```

### UI Patterns for Return Forms

Both Sale Returns and Purchase Returns share identical form patterns:

#### Disposition Type Selector

```dart
const dispositions = [
  ('restock', LucideIcons.package),      // Return to stock
  ('exchange', LucideIcons.repeat),      // Exchange for another item
  ('store_credit', LucideIcons.wallet),  // Store credit
  ('refund', LucideIcons.banknote),      // Cash refund
  ('write_off', LucideIcons.trash2),     // Damaged/unsellable
];

Wrap(
  spacing: 8,
  runSpacing: 8,
  children: dispositions.map((d) {
    final isSelected = state.dispositionType == d.$1;
    return ChoiceChip(
      avatar: Icon(d.$2, size: 16),
      label: Text('sales.disposition_${d.$1}'.tr()),
      selected: isSelected,
      onSelected: (_) => context
          .read<SaleReturnFormBloc>()
          .add(SaleReturnDispositionChanged(d.$1)),
    );
  }).toList(),
);
```

#### Per-Item Reason Input

When an item is selected for return, a reason text field appears below the quantity selector:

```dart
if (isSelected && returnItem.isNotEmpty) ...[
  const SizedBox(height: 8),
  Padding(
    padding: const EdgeInsets.only(left: 48),
    child: TextField(
      decoration: InputDecoration(
        hintText: 'sales.item_reason_hint'.tr(),
        isDense: true,
      ),
      onChanged: (v) => context
          .read<SaleReturnFormBloc>()
          .add(SaleReturnItemReasonChanged(item.id, v)),
    ),
  ),
];
```

#### Financial Impact Card

Shows items returned count and customer refund amount before submission:

```dart
Card(
  child: Column(
    children: [
      // Items returned row (+N items, green)
      Row(children: [Icon(LucideIcons.package), ..., Text('+N items')]),
      // Customer refund row (amount, red)
      Row(children: [Icon(LucideIcons.coins), ..., Text(refundAmount)]),
      // Total refund (highlighted)
      Container(
        decoration: BoxDecoration(
          color: colorScheme.error.withValues(alpha: 0.06),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('sales.total_refund'.tr()),
            Text(totalRefundAmount, style: boldRedStyle),
          ],
        ),
      ),
    ],
  ),
);
```

### Repository Methods

#### SaleRepository (new methods)

```dart
abstract class SaleRepository {
  // Create sale with new fields
  Future<int> createSale({
    required int customerId,
    required int employeeId,
    required int currencyId,
    required Decimal subtotalCents,
    required Decimal discountCents,
    required Decimal taxCents,
    required Decimal totalCents,
    required String paymentMethod,
    required List<SaleItemInput> items,
    String? notes,
    DateTime? saleDate,
    DateTime? dueDate,
  });

  // Payment tracking
  Future<void> recordPayment({
    required int saleId,
    required Decimal amountCents,
    required String paymentMethod,
    String? notes,
  });
  Stream<List<SalePaymentEntity>> watchSalePayments(int saleId);
  
  // Returns with disposition and per-item reasons
  Future<int> createSaleReturn({
    required int saleId,
    required String reason,
    required String dispositionType,
    required List<SaleReturnItemInput> items,
  });
  Future<void> voidSaleReturn(int returnId);
  
  // Track already returned quantities
  Future<int> getReturnedQuantity(int saleItemId);
}
```

### Key Localization Keys

**Sales Module:**
- `sales.due_date` - Due date label
- `sales.overdue` - Overdue badge text
- `sales.paid` - Paid amount label
- `sales.remaining` - Remaining amount label
- `sales.notes` - Notes section title
- `sales.disposition_type` - Disposition selector title
- `sales.disposition_restock` / `_exchange` / `_store_credit` / `_refund` / `_write_off`
- `sales.item_reason_hint` - Per-item reason placeholder
- `sales.financial_impact` - Financial impact card title
- `sales.process_return` - Submit button

**Purchases Module:**
- `purchases.due_date`, `purchases.payment_method`, `purchases.supplier_ref`
- `purchases.paid`, `purchases.remaining`, `purchases.overdue`
- `purchases.disposition_type`, `purchases.disposition_restock` / `_write_off` / `_repair` / `_replace` / `_refund`

### Critical Implementation Notes

1. **Monetary Values**: ALL stored as `INTEGER cents`, mapped to `Decimal` in domain layer via `MoneyConverter`

2. **Status Flow**:
   - Sales: `draft` → `completed` / `voided`
   - SaleReturns: `draft` → `posted` / `voided`

3. **Stock Adjustments**:
   - `restock`: Increase stock by returned quantity
   - `exchange`: No stock change (swap items)
   - `write_off`: No stock change (damaged)
   - `refund`/`store_credit`: Decrease stock if already restocked

4. **Overdue Calculation**:
   ```dart
   bool get isOverdue => dueDate != null && 
                         !isFullyPaid && 
                         DateTime.now().isAfter(dueDate!);
   ```

5. **Responsive Layout**:
   - Detail screens use `LayoutBuilder` for wide/narrow layouts
   - Wide: 380px info panel + expandable items area
   - Narrow: Stacked vertical layout

6. **Color Coding**:
   - Green: Fully paid, items returned
   - Red: Overdue, remaining amount, refund amounts
   - Amber: Notes section

### File Locations

**Sales:**
- `lib/core/database/tables/transactions.dart` - Sales/SaleReturns/SaleReturnItems tables
- `lib/core/database/daos/sale_dao.dart` - CRUD + void/return methods
- `lib/features/sales/domain/entities/sale_entity.dart` - Entities with computed properties
- `lib/features/sales/data/models/sale_model.dart` - SaleModel/SaleReturnModel/SalePaymentModel
- `lib/features/sales/presentation/screens/sale_detail_screen.dart` - Detail with payment tracking
- `lib/features/sales/presentation/screens/sale_return_form_screen.dart` - Return with disposition selector
- `lib/features/sales/presentation/bloc/sale_form_bloc.dart` - Form state with dueDate/notes
- `lib/features/sales/presentation/bloc/sale_return_form_bloc.dart` - Return with dispositionType

**Purchases:**
- `lib/core/database/tables/transactions.dart` - Purchases/PurchaseReturns tables
- `lib/core/database/daos/purchase_dao.dart` - CRUD + payment/return methods
- `lib/features/purchases/domain/entities/purchase_entity.dart` - Entities
- `lib/features/purchases/data/models/purchase_model.dart` - Models
- `lib/features/purchases/presentation/screens/purchase_detail_screen.dart` - Detail screen
- `lib/features/purchases/presentation/screens/purchase_return_form_screen.dart` - Return form
- `lib/features/purchases/presentation/bloc/purchase_form_bloc.dart` - Form bloc
- `lib/features/purchases/presentation/bloc/purchase_return_form_bloc.dart` - Return bloc

---

**Last Updated**: 2026-02-8 
**Version**: 1.0.0  
**Status**: ACTIVE - Follow strictly for all implementations

---

## 📦 PURCHASE MANAGEMENT SYSTEM (ENHANCED)

> **Last Enhanced**: 2026-02-07 (Schema v10017)
> 
> **Key Improvements**: Audit Trail Integration, Purchase-Specific Permissions, Validation Guards, Supplier Credit Notes

### Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         PURCHASE FLOW                                         │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                               │
│  Purchase Form → Create Draft → Save (Audit: create) → Post (Audit: post)   │
│                                     ↓                                         │
│                              Stock Updated                                    │
│                              Supplier Balance + Payable                       │
│                                     ↓                                         │
│                    Payment Recorded (Audit: payment)                        │
│                                     ↓                                         │
│                    Return Created (Audit: create_and_post)                   │
│                              ↓              ↓                                   │
│                    Stock Reversed      Supplier Credit Note                   │
│                              ↓              ↓                                 │
│                         Supplier Balance Decreased                            │
│                                                                               │
│  VOID Operations:                                                           │
│  - Purchase Void: Stock Reversed (if safe), Audit: void                     │
│  - Return Void: Stock Restored, Credit Note Reversed, Balance Restored        │
│                                                                               │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 1. Audit Trail Integration

**What Changed:** All purchase operations now log to `AuditLogs` table via `AuditLogService`.

**Operations Logged:**
| Operation | Action | Data Logged |
|-----------|--------|-------------|
| Create Purchase | `create` | purchaseNumber, supplierId, totalCents, itemCount |
| Update Purchase | `update` | supplierId, totalCents, itemCount |
| Post Purchase | `post` | status: 'posted' |
| Void Purchase | `void` | reason (via VoidLogs too) |
| Delete Purchase | `delete` | purchaseId (data gone after) |
| Create Return | `create_and_post` | purchaseId, returnNumber, totalCents, dispositionType |
| Post Return | `post` | status: 'posted' |
| Void Return | `void` | reason (via VoidLogs too) |
| Record Payment | `create` | purchaseId, amountCents, paymentMethod |
| Delete Payment | `delete` | paymentId |

**Files Modified:**
- `lib/core/di/injection_container.dart` - Registered `AuditLogService`
- `lib/features/purchases/data/repositories/purchase_repository_impl.dart` - Integrated audit logging

### 2. Purchase-Specific Permissions (Schema v10017)

**New Permission Strings:**
```dart
// View permissions
'purchases.view'           // View purchase list and details

// Create/Edit permissions
'purchases.create'         // Create new purchases
'purchases.edit'           // Edit draft purchases
'purchases.delete'         // Delete draft purchases

// Workflow permissions
'purchases.post'           // Post purchases (update stock)
'purchases.void'           // Void posted purchases
'purchases.approve'        // Approve purchases (future workflow)

// Return/Payment permissions
'purchases.returns'        // Create purchase returns
'purchases.payments'       // Record payments on purchases
```

**Role Assignments:**
| Role | Permissions |
|------|-------------|
| admin | ALL purchase permissions |
| manager | view, create, edit, post, approve, returns, payments |
| staff | view only |
| cashier | view only |
| salesperson | view only |

**Migration:** Existing databases upgraded via `_updateRolesWithPurchasePermissions()` in schema v10017.

### 3. Validation Guards

**Purchase Void Validation:**
```dart
// BEFORE voiding, check if stock can be reversed
// Throws: "Cannot void: variant #X stock (Y) is less than purchased quantity (Z). 
//          Some items may have been sold or returned."
```

**Return Quantity Validation:**
```dart
// BEFORE posting return, validate:
// maxReturnable = purchasedQuantity - alreadyReturned
// Throws: "Cannot return X units of item #Y. Only Z available 
//          (purchased: A, already returned: B)."
```

**Negative Stock Guard:**
```dart
// Stock operations guarded against negative:
// - postPurchase: increases stock (always safe)
// - voidPurchase: checks current stock >= purchased quantity
// - postPurchaseReturn: checks current stock >= return quantity
// - voidPurchaseReturn: restores stock (always safe)
```

**Files Modified:**
- `lib/core/database/daos/purchase_dao.dart` - Added validation in `voidPurchase()` and `postPurchaseReturn()`

### 4. Supplier Credit Note System

**When Purchase Return Posted:**
1. **Stock Update:** Decrease stock (if restock/refund/replace disposition)
2. **Credit Note Transaction:** Created in `supplier_transactions` table
   - `transactionType`: 'credit_note'
   - `amountCents`: -refundAmount (negative = supplier owes us)
   - `referenceId`: returnId
   - `referenceType`: 'purchase_return'
3. **Supplier Balance:** Decreased by refund amount

**When Purchase Return Voided:**
1. **Stock Reversal:** Restore stock (if was restock/refund/replace)
2. **Reversal Transaction:** Created in `supplier_transactions` table
   - `transactionType`: 'credit_note_reversal'
   - `amountCents`: +refundAmount (positive = restore balance)
   - `referenceId`: returnId
   - `referenceType`: 'purchase_return'
3. **Supplier Balance:** Restored by refund amount

**Accounting Impact:**
```
Purchase Return Posted:
  Supplier Balance ↓ (they owe us more)
  Inventory ↓ (items removed)
  
Purchase Return Voided:
  Supplier Balance ↑ (restore what we owed)
  Inventory ↑ (items restored)
```

**Files Modified:**
- `lib/core/database/daos/purchase_dao.dart` - Added `SupplierTransactions` to accessor, integrated credit note logic

### 5. Database Schema Changes

**Schema Version:** 10017

**Migration 10016 → 10017:**
```dart
// _updateRolesWithPurchasePermissions()
// Adds purchase permissions to existing roles if not already present
```

**No New Tables** - Used existing:
- `audit_logs` - Already existed, now being populated
- `void_logs` - Already existed, now being populated for void operations
- `supplier_transactions` - Already existed, now receiving credit_note entries

### 6. File Reference

**Core Infrastructure:**
- `lib/core/services/audit_log_service.dart` - Audit logging service
- `lib/core/di/injection_container.dart` - DI registration for AuditLogService + PurchaseRepository

**Data Layer:**
- `lib/core/database/daos/purchase_dao.dart` - DAO with validation + credit notes
- `lib/core/database/app_database.dart` - Schema v10017, role permission migration

**Repository Layer:**
- `lib/features/purchases/data/repositories/purchase_repository_impl.dart` - Audit integration

**Domain Layer:**
- `lib/features/purchases/domain/entities/purchase_entity.dart` - Entities (unchanged)
- `lib/features/purchases/domain/repositories/purchase_repository.dart` - Interface (unchanged)

**Presentation Layer:**
- `lib/features/purchases/presentation/screens/purchase_list_screen.dart` - List screen
- `lib/features/purchases/presentation/screens/purchase_form_screen.dart` - Create/Edit form
- `lib/features/purchases/presentation/screens/purchase_detail_screen.dart` - Detail with actions
- `lib/features/purchases/presentation/screens/purchase_return_form_screen.dart` - Return form
- `lib/features/purchases/presentation/screens/purchase_returns_screen.dart` - Returns list

**Bloc Layer:**
- `lib/features/purchases/presentation/bloc/purchases_bloc.dart` - List bloc
- `lib/features/purchases/presentation/bloc/purchase_form_bloc.dart` - Form bloc
- `lib/features/purchases/presentation/bloc/purchase_returns_bloc.dart` - Returns list bloc
- `lib/features/purchases/presentation/bloc/purchase_return_form_bloc.dart` - Return form bloc

### 7. Key Calculations

**Money Handling (Integer Cents):**
```dart
// All monetary values stored as INTEGER cents
final int totalCents = purchase.totalCents.toBigInt().toInt();
final String formatted = currencyService.format(totalCents);
```

**Return Quantity Available:**
```dart
final alreadyReturned = await dao.getReturnedQuantity(purchaseItemId);
final maxReturnable = purchaseItem.quantity - alreadyReturned;
```

**Supplier Balance Update:**
```dart
// Return posted: decrease supplier balance (they owe us)
newBalance = oldBalance - refundCents;

// Return voided: restore supplier balance
newBalance = oldBalance + refundCents;
```

### 8. Future Enhancements (Not Implemented)

**Planned but Deferred:**
- **Multi-Branch Support:** `branch_id` on all transaction tables
- **Purchase Orders:** Separate PO → GRN → Invoice three-way matching
- **Multi-Currency:** Exchange rates, base currency normalization
- **Approval Workflows:** Multi-step approval before posting
- **Landed Cost:** Freight/insurance/duty allocation to items
- **Supplier Price Lists:** Negotiated pricing with effective dates

**Reason for Deferral:** These require broader architectural changes across the entire app (sales, products, employees, etc.) and are too risky to implement in a single session.

---

---

## 🔍 Audit Log System

### Overview

The Audit Log system provides a **complete, immutable trail** of every change to financial and operational data. It is critical for accounting integrity, compliance, and debugging.

### Database Tables

| Table | Purpose | Key Columns |
|-------|---------|-------------|
| `audit_logs` | General action log | `id`, `target_table`, `record_id`, `action`, `changes` (JSON), `user_id` (nullable FK → users), `created_at` |
| `void_logs` | Void-specific log | `id`, `target_table`, `record_id`, `reason`, `voided_by` (nullable FK → users), `voided_at` |

- Both tables have **nullable** user FK columns — `null` means "system action" (e.g. migration, seed).
- `changes` column stores a JSON map with `old`, `new`, and `timestamp` keys.

### AuditLogService (`lib/core/services/audit_log_service.dart`)

Singleton registered in DI. Provides:

| Method | Purpose |
|--------|---------|
| `log(entityType, entityId, action, oldValue?, newValue?, userId?)` | General audit entry |
| `logVoid(entityType, entityId, reason, userId?)` | Void entry (writes to both `void_logs` AND `audit_logs`) |
| `logBalanceChange(...)` | Balance change with old/new cents |
| `logPriceChange(...)` | Price change with old/new cents |
| `logStockAdjustment(...)` | Stock adjustment with old/new qty |
| `watchAuditLogs(fromDate?, toDate?, entityType?, action?)` | **Reactive stream** for UI |
| `watchVoidLogs(fromDate?, toDate?, entityType?)` | Reactive stream for void logs |

### How userId Is Wired

Repositories that perform auditable actions receive `SessionService` via DI and call `_sessionService.getCurrentUserId()` before each audit log call. This ensures the **real logged-in user** is recorded.

```dart
// Pattern used in PurchaseRepositoryImpl:
class PurchaseRepositoryImpl implements PurchaseRepository {
  final AuditLogService _auditService;
  final SessionService _sessionService;

  Future<int?> _currentUserId() => _sessionService.getCurrentUserId();

  // Then in each method:
  await _auditService.log(
    entityType: 'purchase',
    entityId: id,
    action: 'create',
    newValue: {...},
    userId: await _currentUserId(),
  );
}
```

**When adding audit logging to NEW features**, follow this same pattern:
1. Inject `SessionService` into the repository implementation.
2. Add `Future<int?> _currentUserId() => _sessionService.getCurrentUserId();`
3. Pass `userId: await _currentUserId()` to every `_auditService.log()` / `_auditService.logVoid()` call.
4. Register the `SessionService` dependency in `injection_container.dart`.

### Audit Log UI

**Route:** `/audit` (accessible from Users & Permissions screen AppBar button)  
**Permission:** `view_audit_logs` — Owner only by default.

**Architecture:**
- `AuditLogBloc` extends `RealtimeBloc<AuditLogViewModel, AuditLogEvent>`
- Subscribes to `AuditLogService.watchAuditLogs()` for **real-time updates**
- Client-side filtering by entity type, action, and free-text search
- Loads user names from DB for display

**Screen Features:**
- Search bar (searches entity type, action, record ID, user name)
- Filter chips for entity type (Purchase, Sale, Product, etc.) with color coding
- Filter chips for action (Create, Update, Delete, Post, Void, etc.) with color coding
- Stats bar showing filtered/total count
- Log tiles with action icon, badges, user, relative time
- Detail bottom sheet with full JSON changes view

**Color Coding:**
| Entity Type | Color | Action | Color |
|-------------|-------|--------|-------|
| Purchase/Return/Payment | `primary` | Create | Green |
| Sale/Return | Green | Update | Blue |
| Product | Orange | Delete | Error (red) |
| Customer | Purple | Post | Teal |
| Supplier | Teal | Void | Error (red) |

### Localization

All audit keys live under the `"audit"` namespace in `en.json`, `ar.json`, `fr.json`:
- `audit.title`, `audit.search_hint`, `audit.filter_entity`, `audit.filter_action`
- `audit.entity_*` — entity type labels
- `audit.action_*` — action labels
- `audit.just_now`, `audit.minutes_ago`, `audit.hours_ago`, `audit.days_ago` — relative time
- `audit.detail_title`, `audit.entity`, `audit.record_id`, `audit.changes` — detail sheet

### Key File References

| File | Purpose |
|------|---------|
| `lib/core/services/audit_log_service.dart` | Core service — logging + reactive streams |
| `lib/core/database/tables/audit.dart` | Drift table definitions (`AuditLogs`, `VoidLogs`) |
| `lib/features/auth/presentation/bloc/audit_log_bloc.dart` | RealtimeBloc with filters |
| `lib/features/auth/presentation/screens/audit_log_screen.dart` | Full UI screen |
| `lib/core/di/injection_container.dart` | DI registration |
| `lib/core/router/app_router.dart` | Route `/audit` |
| `lib/core/router/route_permissions.dart` | Owner-only access |
| `lib/features/auth/domain/entities/permission_constants.dart` | `viewAuditLogs` permission |

### Extending Audit Logging to New Features

When implementing a new feature (e.g. Sales, Expenses, Employees):

1. **Inject** `AuditLogService` + `SessionService` into the repository implementation.
2. **Log** every create/update/delete/post/void action with appropriate `entityType` and `action`.
3. **Add entity type label** to `_FilterSection._entityTypeLabel()` and `_entityTypeColor()` in the audit screen.
4. **Add localization keys** `audit.entity_<new_type>` in all 3 language files.
5. The UI will **automatically** show the new entity type in filter chips and log tiles.

---

**Last Updated**: 2026-02-08 
**Version**: 1.0.0  
**Status**: ACTIVE - Follow strictly for all implementations

---

## 🏪 Suppliers Module - Seasonal Discount Feature

> **Last Enhanced**: 2026-02-07 (Schema v10018)
> 
> **Feature**: Seasonal Discount Dialog with Period-Based Net Purchases Calculation

### Overview

The **Seasonal Discount** feature allows applying discounts to suppliers based on their **net purchases** (purchases minus returns) within a selected period. This is typically used for:
- End-of-season settlements with suppliers
- Volume-based discounts
- Promotional allowances
- Year-end reconciliations

### Access Point

**Location**: `SupplierProfileScreen` - Quick Actions section  
**Replaces**: The "New Purchase" button (changed to "Add Discount" with `LucideIcons.percent` icon)

```dart
// Quick action button in supplier profile
OutlinedButton.icon(
  onPressed: () => _showSeasonalDiscountDialog(context, supplier, profileBloc),
  icon: const Icon(LucideIcons.percent),
  label: Text('suppliers.add_discount'.tr()),
)
```

### Discount Base Calculation (Accounting-Excellent Accuracy)

The discount is calculated on **Net Posted Purchases Subtotal** (before tax, after returns):

```
Base = Posted Purchases Subtotal - Posted Returns Subtotal

Where:
- Posted Purchases Subtotal = SUM(purchases.subtotal_cents)
  WHERE status = 'posted' AND purchase_date IN [period]
  
- Posted Returns Subtotal = SUM(purchase_returns.subtotal_cents)
  WHERE status = 'posted' AND return_date IN [period]
  
Both amounts are PRE-TAX (subtotal only, excluding tax)
```

**Implementation** (`SupplierProfileScreen`):

```dart
Future<int> _getNetPostedPurchasesSubtotalCents({
  required int supplierId,
  required DateTime start,
  required DateTime end,
}) async {
  final db = sl<AppDatabase>();

  // Get posted purchases subtotal in period
  final purchasesRow = await db.customSelect(
    'SELECT COALESCE(SUM(p.subtotal_cents), 0) AS total '
    'FROM purchases p '
    'WHERE p.supplier_id = ? AND p.status = ? '
    'AND p.purchase_date >= ? AND p.purchase_date <= ?',
    variables: [Variable.withInt(supplierId), 'posted', start, end],
  ).getSingle();

  // Get posted returns subtotal in period (from stored subtotal_cents)
  final returnsRow = await db.customSelect(
    'SELECT COALESCE(SUM(pr.subtotal_cents), 0) AS total '
    'FROM purchase_returns pr '
    'JOIN purchases p ON p.id = pr.purchase_id '
    'WHERE p.supplier_id = ? AND pr.status = ? '
    'AND pr.return_date >= ? AND pr.return_date <= ?',
    variables: [Variable.withInt(supplierId), 'posted', start, end],
  ).getSingle();

  final purchasesSubtotal = purchasesRow.read<int>('total');
  final returnsSubtotal = returnsRow.read<int>('total');
  final net = purchasesSubtotal - returnsSubtotal;
  return net < 0 ? 0 : net; // Never negative
}
```

### Database Schema Enhancement (v10018)

**Problem**: Original `purchase_returns` table only had `total_cents` (tax-inclusive). For accurate pre-tax calculations, we added:

```dart
// In PurchaseReturns table (transactions.dart)
class PurchaseReturns extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get purchaseId => integer().references(Purchases, #id)();
  TextColumn get returnNumber => text().unique()();
  IntColumn get totalCents => integer().map(const MoneyConverter())();
  // NEW: Accounting-excellent fields (Schema v10018)
  IntColumn get subtotalCents => integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  IntColumn get taxCents => integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  // ... other fields
}
```

**Migration** (`app_database.dart`):

```dart
// Schema version bumped to 10018
@override
int get schemaVersion => 10018;

// In onUpgrade:
if (from < 10018) {
  await _safeAddColumn('purchase_returns', 'subtotal_cents', 'INTEGER NOT NULL DEFAULT 0');
  await _safeAddColumn('purchase_returns', 'tax_cents', 'INTEGER NOT NULL DEFAULT 0');
}
```

**Calculation on Return Creation** (`PurchaseDao`):

```dart
Future<void> updatePurchaseReturnTotals(int returnId) async {
  final totalsRow = await customSelect(
    'SELECT '
    '  COALESCE(SUM((pi.subtotal_cents * pri.quantity) / pi.quantity), 0) AS subtotal, '
    '  COALESCE(SUM((pi.tax_cents * pri.quantity) / pi.quantity), 0) AS tax '
    'FROM purchase_return_items pri '
    'JOIN purchase_items pi ON pi.id = pri.purchase_item_id '
    'WHERE pri.return_id = ?',
    variables: [Variable.withInt(returnId)],
  ).getSingle();

  final subtotalCents = totalsRow.read<int>('subtotal');
  final taxCents = totalsRow.read<int>('tax');

  await customStatement(
    'UPDATE purchase_returns '
    'SET subtotal_cents = ?, tax_cents = ? '
    'WHERE id = ?',
    [subtotalCents, taxCents, returnId],
  );
}
```

### UI Dialog Features

**Period Selection** (SegmentedButton with 3 options):

```dart
SegmentedButton<String>(
  segments: [
    ButtonSegment(
      value: 'month',
      label: Text('suppliers.period_this_month'.tr()),
      icon: const Icon(LucideIcons.calendarDays),
    ),
    ButtonSegment(
      value: 'last30',
      label: Text('suppliers.period_last_30_days'.tr()),
      icon: const Icon(LucideIcons.calendarClock),
    ),
    ButtonSegment(
      value: 'custom',
      label: Text('suppliers.period_custom'.tr()),
      icon: const Icon(LucideIcons.calendarRange),
    ),
  ],
  selected: {periodMode},
  onSelectionChanged: (v) {
    setState(() {
      periodMode = v.first;
      final n = DateTime.now();
      if (periodMode == 'month') {
        startDate = DateTime(n.year, n.month, 1);
        endDate = n;
      } else if (periodMode == 'last30') {
        startDate = n.subtract(const Duration(days: 30));
        endDate = n;
      }
      reloadBase(); // Recalculate base amount
    });
  },
)
```

**Custom Date Range** (appears when 'custom' selected):

```dart
Row(
  children: [
    Expanded(
      child: OutlinedButton.icon(
        onPressed: () async {
          final picked = await showDatePicker(
            context: dialogContext,
            initialDate: startDate,
            firstDate: DateTime(2000),
            lastDate: DateTime(2100),
          );
          if (picked != null) {
            setState(() {
              startDate = DateTime(picked.year, picked.month, picked.day);
              if (startDate.isAfter(endDate)) endDate = startDate;
              reloadBase();
            });
          }
        },
        icon: const Icon(LucideIcons.calendar),
        label: Text('suppliers.start_date'.tr()),
      ),
    ),
    const SizedBox(width: 12),
    Expanded(
      child: OutlinedButton.icon(
        onPressed: () async { /* Similar for endDate */ },
        icon: const Icon(LucideIcons.calendar),
        label: Text('suppliers.end_date'.tr()),
      ),
    ),
  ],
)
```

**Discount Type Selection** (Fixed vs Percentage):

```dart
SegmentedButton<String>(
  segments: [
    ButtonSegment(
      value: 'fixed',
      label: Text('suppliers.discount_fixed'.tr()),
      icon: const Icon(LucideIcons.badgeDollarSign),
    ),
    ButtonSegment(
      value: 'percent',
      label: Text('suppliers.discount_percent'.tr()),
      icon: const Icon(LucideIcons.percent),
    ),
  ],
  selected: {selectedMode},
  onSelectionChanged: (v) {
    setState(() {
      selectedMode = v.first;
      if (selectedMode == 'percent') {
        updateFromAmount(baseCents);
      } else {
        updateFromPercent(baseCents);
      }
    });
  },
)
```

**Two-Way Calculation** (Amount ↔ Percentage):

```dart
void updateFromPercent(int baseCents) {
  if (baseCents == 0) return;
  final percent = double.tryParse(percentController.text) ?? 0;
  final amount = (baseCents * percent / 100) / 100; // Convert to dollars
  amountController.text = amount.toStringAsFixed(2);
}

void updateFromAmount(int baseCents) {
  if (baseCents == 0) return;
  final amount = double.tryParse(amountController.text) ?? 0;
  final percent = (amount * 100 / (baseCents / 100)); // Calculate percent
  percentController.text = percent.toStringAsFixed(2);
}
```

### Accounting Treatment

When discount is recorded:

1. **Supplier Transaction Created** (`supplier_transactions` table):
   ```dart
   await sl<SupplierRepository>().recordTransaction(
     supplierId: supplier.id,
     transactionType: 'discount',
     amountCents: -amountCents, // Negative = we owe supplier less
     currencyId: supplier.currencyId,
     description: descriptionController.text.isEmpty
         ? 'suppliers.seasonal_discount'.tr()
         : descriptionController.text,
   );
   ```

2. **Supplier Balance Updated**:
   ```dart
   final currentBalance = supplier.balanceCents.toDouble().round();
   await sl<SupplierRepository>().updateSupplierBalance(
     supplier.id,
     currentBalance - amountCents, // Decrease balance by discount amount
   );
   ```

3. **Audit Log Entry** (via `AuditLogService`):
   - Entity Type: `supplier`
   - Action: `discount`
   - Old Value: Previous balance
   - New Value: New balance after discount
   - User ID: Current logged-in user (via `SessionService`)

### Localization Keys

**English (en.json)**:
```json
"suppliers": {
  "seasonal_discount": "Seasonal Discount",
  "seasonal_discount_title": "Record Seasonal Discount",
  "seasonal_discount_hint": "e.g., Seasonal promotion, Year-end allowance",
  "seasonal_discount_recorded": "Seasonal discount recorded successfully",
  "discount_fixed": "Fixed amount",
  "discount_percent": "Percent",
  "discount_base_hint": "Base: {0}",
  "discount_base_zero": "No posted purchases found in the selected period",
  "period_this_month": "This month",
  "period_last_30_days": "Last 30 days",
  "period_custom": "Custom",
  "start_date": "Start",
  "end_date": "End",
  "record_discount": "Record Discount"
}
```

**Arabic (ar.json)**:
```json
"suppliers": {
  "seasonal_discount": "خصم موسمي",
  "seasonal_discount_title": "تسجيل خصم موسمي",
  "discount_fixed": "مبلغ ثابت",
  "discount_percent": "نسبة مئوية",
  "discount_base_hint": "الأساس: {0}",
  "discount_base_zero": "لا توجد مشتريات مُرحّلة في الفترة المحددة",
  "period_this_month": "هذا الشهر",
  "period_last_30_days": "آخر 30 يوم",
  "period_custom": "مخصص",
  "start_date": "من",
  "end_date": "إلى"
}
```

**French (fr.json)**:
```json
"suppliers": {
  "seasonal_discount": "Remise saisonnière",
  "seasonal_discount_title": "Enregistrer une remise saisonnière",
  "discount_fixed": "Montant fixe",
  "discount_percent": "Pourcentage",
  "discount_base_hint": "Base : {0}",
  "discount_base_zero": "Aucun achat validé trouvé sur la période sélectionnée",
  "period_this_month": "Ce mois-ci",
  "period_last_30_days": "30 derniers jours",
  "period_custom": "Personnalisé",
  "start_date": "Début",
  "end_date": "Fin"
}
```

### Key Files Reference

| File | Purpose |
|------|---------|
| `lib/features/suppliers/presentation/screens/supplier_profile_screen.dart` | Seasonal discount dialog UI and base calculation |
| `lib/core/database/app_database.dart` | Schema v10018 with `subtotal_cents`/`tax_cents` columns |
| `lib/core/database/daos/purchase_dao.dart` | `updatePurchaseReturnTotals()` method |
| `lib/core/database/tables/transactions.dart` | `PurchaseReturns` table definition |
| `lib/features/purchases/data/datasources/purchase_local_datasource.dart` | Exposes `updatePurchaseReturnTotals` |
| `lib/features/purchases/data/repositories/purchase_repository_impl.dart` | Calls `updatePurchaseReturnTotals` on return creation |
| `lib/features/suppliers/data/repositories/supplier_repository_impl.dart` | Records discount transaction + balance update |
| `assets/translations/en.json` / `ar.json` / `fr.json` | Localization keys |

### Validation & Error Handling

1. **Zero Base Check**: If no posted purchases in selected period:
   ```dart
   if (baseCents <= 0) {
     scaffoldMessenger.showSnackBar(
       SnackBar(content: Text('suppliers.discount_base_zero'.tr())),
     );
     return;
   }
   ```

2. **Invalid Amount**: Discount must be > 0

3. **Date Validation**: Start date cannot be after end date (auto-corrected)

### Summary

The Seasonal Discount feature provides **accounting-excellent accuracy** by:
- Using pre-tax subtotals for both purchases and returns
- Storing calculated subtotal/tax in database (not deriving on-the-fly)
- Supporting flexible period selection (month/30-days/custom)
- Enabling two-way calculation (amount ↔ percentage)
- Recording proper supplier transactions with audit trail
- Supporting all 3 languages (EN/AR/FR) with RTL

This ensures accurate supplier settlements and maintains accounting integrity across the system.

---

## 📊 Financial Reports System

### Architecture Overview

The reports system follows the same Clean Architecture + RealtimeBloc pattern as the rest of Tapix. All financial reports are **date-range aware** and update in **real-time** via Drift stream subscriptions. There are **no manual refresh buttons** — data flows reactively from the database.

### Key Components

| Component | File | Purpose |
|-----------|------|---------|
| **ReportsBloc** | `lib/features/reports/presentation/bloc/reports_bloc.dart` | Central RealtimeBloc for all financial reports. Watches posted journal entry lines within a date range, computes trial balance, and supports reconciliation. |
| **ReportDateRange** | `lib/features/reports/presentation/widgets/report_date_range.dart` | Model class representing a date range with preset periods (today, this week, this month, last month, this quarter, this year, last year, all time, custom). |
| **DateRangeSelector** | `lib/features/reports/presentation/widgets/date_range_selector.dart` | Reusable widget with preset FilterChips + custom date range picker. Used on every report screen. |
| **JournalPdfService** | `lib/features/accounting/presentation/services/journal_pdf_service.dart` | PDF generation, print, and share for Trial Balance, Profit & Loss, and Balance Sheet. Supports multi-language (EN/AR/FR) with RTL for Arabic. |

### Report Screens

All screens are under `lib/features/reports/presentation/screens/`:

| Screen | File | Features |
|--------|------|----------|
| **Reports Hub** | `reports_hub_screen.dart` | Dashboard with health banner, navigation cards to sub-reports, settings gear icon |
| **Trial Balance** | `trial_balance_screen.dart` | Date range selector, balance status banner, account table, totals footer, print/share + audit |
| **Profit & Loss** | `profit_loss_screen.dart` | Date range selector, net profit/loss card, revenue/expense sections, summary card, print/share + audit |
| **Balance Sheet** | `balance_sheet_screen.dart` | Date range selector, balance indicator, asset/liability/equity sections with retained earnings, print/share + audit |
| **General Ledger** | `general_ledger_screen.dart` | Date range selector, account dropdown (AccountsBloc), running balance table with stream subscription per account |
| **Accounting Health** | `accounting_health_screen.dart` | Date range selector, health status card, trial balance check, journal entries check, issues list |

### How Date Range Filtering Works

1. **Data Layer**: `AccountingDao` has two join queries:
   - `watchPostedLinesByDateRange(start, end)` — joins `journal_entry_lines` with `journal_entries`, filters by `status='posted'` and `entry_date` within range
   - `watchPostedLinesByAccountAndDateRange(accountId, start, end)` — same but also filters by account (for General Ledger)

2. **Repository Layer**: `JournalRepository` exposes these as streams through the datasource.

3. **Bloc Layer**: `ReportsBloc` subscribes to `watchPostedLinesByDateRange` using the current `_dateRange`. When the user changes the date range:
   - `ReportsDateRangeChanged` event is dispatched
   - Bloc updates `_dateRange` and calls `refresh()` (from `RealtimeBloc`)
   - `refresh()` re-subscribes to `dataStream`, which now reads the new `_dateRange`
   - Trial balance is recomputed from the new set of journal entry lines

4. **UI Layer**: Each report screen wraps its body with `BlocBuilder<ReportsBloc, RealtimeState<ReportsData>>` and places a `DateRangeSelector` widget at the top. The selector dispatches `ReportsDateRangeChanged` on change.

### ReportsBloc Data Flow

```
User selects date range
  → ReportsDateRangeChanged event
    → _dateRange updated
      → refresh() → re-subscribe to dataStream
        → watchPostedLinesByDateRange(start, end)
          → Drift emits List<JournalEntryLine>
            → _computeFromLines() aggregates per account
              → TrialBalance built
                → RealtimeSuccess<ReportsData> emitted
                  → UI rebuilds with new data
```

### ReportsData Model

```dart
class ReportsData {
  final TrialBalance trialBalance;       // Computed from lines in date range
  final ReconciliationResult? reconciliation; // Optional health check result
  final ReportDateRange dateRange;       // Current date range
  bool get isHealthy;                    // TB balanced + reconciliation OK
  int get issueCount;                    // Number of reconciliation issues
}
```

### Trial Balance Computation from Lines

Unlike the cumulative `account.balanceCents` approach, the date-range system computes trial balance by:
1. Fetching all posted journal entry lines within the date range
2. Aggregating `debitCents` and `creditCents` per `accountId`
3. Computing net balance per account
4. Assigning to debit/credit column based on account type (asset/expense = debit-normal, liability/equity/revenue = credit-normal)

This ensures reports reflect **only the activity within the selected period**.

### PDF Export / Print / Share

`JournalPdfService` provides static methods:
- `printTrialBalance()` / `shareTrialBalance()` — takes raw `Account` list
- `printProfitLoss()` / `shareProfitLoss()` — takes `PnlSection` list with revenue/expense breakdown
- `printBalanceSheet()` / `shareBalanceSheet()` — takes `BalanceSheetSection` list

All methods:
- Accept `BuildContext` for locale detection
- Load IBM Plex Sans Arabic font for RTL support
- Use `pdf` package for document generation
- Use `printing` package for print dialog
- Use `share_plus` for sharing (writes temp file, shares via platform sheet)

### Audit Logging

Every print/share action logs to `AuditLogService`:
```dart
sl<AuditLogService>().log(
  entityType: 'report',
  entityId: 0,
  action: 'print_trial_balance', // or share_trial_balance, print_profit_loss, etc.
);
```
General Ledger logs `view_general_ledger` with the selected `accountId`.

### Translation Keys

Date range keys are under `reports.date_range.*` in all 3 language files:
- `today`, `this_week`, `this_month`, `last_month`, `this_quarter`, `this_year`, `last_year`, `all_time`, `custom`, `select_period`

Print/share use `common.print` and `common.share` (already existed).

### DI Registration

`ReportsBloc` is registered in `lib/core/di/injection_container.dart`:
```dart
sl.registerFactory(() => ReportsBloc(sl<JournalRepository>()));
```

### Adding a New Report

To add a new financial report:
1. Add any needed DAO query methods in `accounting_dao.dart`
2. Expose through datasource → repository layers
3. Create a new screen under `lib/features/reports/presentation/screens/`
4. Use `BlocProvider(create: (_) => sl<ReportsBloc>())` as the wrapper
5. Add `DateRangeSelector` at the top of the body
6. Use `BlocBuilder<ReportsBloc, RealtimeState<ReportsData>>` for state handling
7. Add print/share if needed via `JournalPdfService`
8. Add audit logging for all export actions
9. Add route in GoRouter
10. Add navigation card in Reports Hub
11. Add translation keys in all 3 language files

### Important Notes for Future AI Models

- **Never add manual refresh buttons** — the RealtimeBloc pattern handles all updates automatically via Drift streams
- **Always use integer cents** for money math — never use `double` or `Decimal` in UI calculations
- **Always include DateRangeSelector** on every report screen — it's the standard UX pattern
- **Always log to AuditLogService** when generating/exporting reports
- **Default date range is "This Month"** — set in `ReportsBloc._dateRange`
- **General Ledger is special** — it uses `AccountsBloc` for the account list + a manual `StreamSubscription` for lines (not `ReportsBloc`), because it needs per-account filtering
- **Reports Hub uses ReportsBloc** for the health banner but doesn't show date range selector (it's a navigation hub, not a report)
- The `_accountsCache` in `ReportsBloc` keeps a live subscription to all accounts for name/type lookups when computing trial balance from lines

---

**Last Updated**: 2026-02-09 
**Version**: 1.0.0  
**Status**: ACTIVE - Follow strictly for all implementations
