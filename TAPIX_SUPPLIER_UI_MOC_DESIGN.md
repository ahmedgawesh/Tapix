# TAPIX Supplier Management UI - MOC Design Analysis
> **Based on Stories 4.5-4.12, Global Best Practices, and TAPIX Architecture Patterns**

---

## Core Architecture Compliance

### TAPIX Patterns Applied
- **RealtimeBloc** for all supplier state management (auto-updates from DB streams)
- **Clean Architecture**: Domain → Data → Presentation layers
- **CurrencyService** for all money displays (NO hardcoded symbols)
- **Localization**: EN, AR (RTL), FR — all strings via `easy_localization`
- **Integer Cents**: All money stored as `int` cents, displayed via CurrencyService
- **Responsive**: Mobile / Tablet / Desktop / Web — no overflow
- **Theme-aware**: Light & Dark modes, semantic colors from `colorScheme`

---

## Database Schema (Already Exists in `parties.dart`)

### `suppliers` Table
| Column | Type | Notes |
|--------|------|-------|
| id | INTEGER PK | Auto-increment |
| name | TEXT | Required |
| email | TEXT? | Nullable |
| phone | TEXT? | Nullable |
| address | TEXT? | Nullable |
| balance_cents | INTEGER | MoneyConverter, default 0 |
| currency_id | INTEGER FK | References currencies |
| is_active | BOOLEAN | Default true |
| created_at | DATETIME | Default now |
| updated_at | DATETIME | Default now |

### `supplier_transactions` Table
| Column | Type | Notes |
|--------|------|-------|
| id | INTEGER PK | Auto-increment |
| supplier_id | INTEGER FK | References suppliers |
| transaction_type | TEXT | payment/purchase/return/discount |
| amount_cents | INTEGER | MoneyConverter |
| currency_id | INTEGER FK | References currencies |
| description | TEXT? | Nullable |
| reference_id | INTEGER? | Links to purchase/return |
| reference_type | TEXT? | purchase/return/payment |
| transaction_date | DATETIME | Default now |
| created_at | DATETIME | Default now |

---

## Feature Structure

```
lib/features/suppliers/
├── data/
│   ├── datasources/
│   │   └── supplier_local_datasource.dart
│   └── repositories/
│       └── supplier_repository_impl.dart
├── domain/
│   └── repositories/
│       └── supplier_repository.dart
└── presentation/
    ├── bloc/
    │   ├── suppliers_bloc.dart
    │   ├── supplier_form_bloc.dart
    │   └── supplier_profile_bloc.dart
    └── screens/
        ├── supplier_hub_screen.dart
        ├── supplier_form_screen.dart
        └── supplier_profile_screen.dart
```

---

## Screens Design

### 1. Supplier Hub Dashboard (`/suppliers`)
- **Quick Stats Cards** (responsive 3-col → 2+1 on narrow):
  - Active Suppliers count (icon: `Icons.local_shipping_outlined`)
  - Total Payables in currency (icon: `Icons.account_balance_wallet_outlined`)
  - Suppliers with Balance (icon: `Icons.receipt_long_outlined`)
- **Search Bar** with real-time filtering
- **Quick Actions** (Wrap chips): Add Supplier, Make Payment, View Reports
- **Supplier List** with:
  - Avatar (first letter), name, contact info
  - Balance display (color-coded: red for owed, green for credit)
  - Active/Inactive badge
- **FAB**: Add Supplier

### 2. Supplier Form (`/suppliers/new`, `/suppliers/:id/edit`)
- **Sections**:
  - Basic Information: Name*, Email, Phone
  - Contact Details: Address
  - Financial: Opening Balance (create only)
- **Validation**: Name required, email format
- **Pattern**: BlocConsumer with form state management (mirrors CustomerFormBloc)

### 3. Supplier Profile (`/suppliers/:id`)
- **Profile Header**: Avatar, name, contact chips
- **Balance Card**: Color-coded payable/credit display
- **Quick Actions** (responsive): Make Payment, New Purchase, Return Items
- **Contact Information Card**: Email, phone, address
- **Recent Transactions**: Real-time stream with type icons

---

## BLoC Architecture

### SuppliersBloc (extends RealtimeBloc)
- Stream: `watchAllSuppliers(isActive: true)`
- Events: search, delete, toggle active
- Data class: `SuppliersData { suppliers, searchQuery, isSearching }`

### SupplierFormBloc (standard Bloc)
- Events: load, field changes, submit
- States: initial → loading → ready → success/error
- Handles create and edit with validation

### SupplierProfileBloc (extends RealtimeBloc)
- Stream: `watchSupplier(id)`
- Auto-updates when supplier data changes

---

## Translation Keys (`suppliers.*`)

All under `suppliers` namespace in en.json, ar.json, fr.json:
- title, add, edit, create, update, delete
- name, email, phone, address
- basic_info, contact_info, financial_info
- opening_balance, current_balance
- balance_payable, balance_credit
- active_suppliers, total_payables, with_balance
- quick_stats, search_hint, all_suppliers
- empty, empty_hint, add_first
- payment, new_purchase, return_items
- recent_transactions, no_transactions, view_all
- created_success, updated_success, deleted_success
- deactivate, activate, make_payment
- name_required, email_invalid, amount_invalid
- delete_confirm_title, delete_confirm_message
- delete_not_allowed_title, delete_not_allowed_message
- view_reports, suppliers

---

## Implementation Priority

1. **DAO** → SupplierDao (database operations)
2. **Domain** → SupplierRepository interface
3. **Data** → Datasource + Repository implementation
4. **BLoCs** → SuppliersBloc, SupplierFormBloc, SupplierProfileBloc
5. **Screens** → Hub, Form, Profile
6. **Translations** → EN, AR, FR
7. **DI + Routing** → injection_container.dart + app_router.dart
8. **Tests** → Bloc tests, widget tests
