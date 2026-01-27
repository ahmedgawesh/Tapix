# TAPIX UI Architecture Specification

> **CRITICAL**: This document defines the complete UI architecture, screen placement, and navigation flow for the entire TAPIX application. All screens MUST follow this specification exactly.

---

## 🎯 Purpose

Defines the complete UI architecture, screen hierarchy, navigation patterns, and responsive design requirements for TAPIX. This eliminates ambiguity about where screens go and how they work together.

---

## 📱 Application Structure

### Main Navigation Areas

```
TAPIX Application
├── Authentication Flow
│   ├── Login Screen
│   └── Role Selection
├── Main Navigation (Bottom Bar - Mobile/Tablet, Sidebar - Desktop)
│   ├── Dashboard (Home)
│   ├── Products
│   ├── Sales
│   ├── Purchases  
│   ├── Parties (Customers/Suppliers)
│   ├── Finance
│   ├── Reports
│   └── Settings
└── Modal/Dialog System
    ├── Product Selection Dialogs
    ├── Payment Dialogs
    ├── Confirmation Dialogs
    └── Form Dialogs
```

---

## 🗺️ Screen Hierarchy & Placement

### EPIC-03: Product Management Screens

**Main Product Screens (Top-Level Navigation):**
- **Products Main Screen** (`/products`) - Primary product management hub
  - Grid view for desktop, list view for mobile/tablet
  - Quick actions: Add, Search, Filter, Import/Export
  - Navigation to detail screens via tap/click

**Product Form Screens (Modal/Overlay):**
- **Product CRUD Form** (`/products/new` or `/products/edit/:id`) - Slide-up modal on mobile, dialog on desktop
- **Bulk Product Form** (`/products/bulk`) - Full screen on mobile, modal on desktop
- **Edit Prices Screen** (`/products/prices`) - Modal overlay

**Product Management Screens (Sub-navigation):**
- **Barcode Management** (`/products/barcodes`) - Full screen
- **Categories Screen** (`/products/categories`) - Full screen  
- **Colors Screen** (`/products/colors`) - Full screen
- **Sizes Screen** (`/products/sizes`) - Full screen
- **Import Products** (`/products/import`) - Full screen with drag-drop
- **Export Products** (`/products/export`) - Full screen with options
- **Barcode Design** (`/products/barcode-design`) - Full screen designer

### EPIC-04: Parties Management Screens

**Customer Screens:**
- **Customer Management** (`/customers`) - List view with search/filter
- **Customer Form** (`/customers/new` or `/customers/edit/:id`) - Modal
- **Customer Profile** (`/customers/:id`) - Detail view
- **Customer Payment Dialog** (`/customers/:id/payment`) - Modal

**Supplier Screens:**
- **Supplier Management** (`/suppliers`) - List view with search/filter  
- **Supplier Form** (`/suppliers/new` or `/suppliers/edit/:id`) - Modal
- **Supplier Profile** (`/suppliers/:id`) - Detail view
- **Supplier Payment Dialog** (`/suppliers/:id/payment`) - Modal

### EPIC-05: Sales & POS Screens

**Sales Screens:**
- **POS Interface** (`/sales/pos`) - Full screen POS layout
- **Sales Screen** (`/sales`) - Sales history list
- **Sale Form** (`/sales/new`) - Full screen form
- **Sale Product Selection Dialog** (`/sales/products`) - Modal
- **Sale Product Edit Dialog** (`/sales/edit-product`) - Modal

**Payment & Invoice Screens:**
- **Checkout Payment** (`/sales/checkout`) - Full screen
- **Invoice Printing** (`/sales/invoice/:id`) - Print preview
- **Sale Returns Processing** (`/sales/returns`) - Full screen

---

## 🧭 Navigation Architecture

### GoRouter Structure

```dart
// Main Routes
GoRoute(
  path: '/',
  builder: (context, state) => const DashboardScreen(),
),

// Product Routes
GoRoute(
  path: '/products',
  builder: (context, state) => const ProductsMainScreen(),
  routes: [
    GoRoute(
      path: '/new',
      builder: (context, state) => const ProductFormScreen(),
    ),
    GoRoute(
      path: '/edit/:id',
      builder: (context, state) {
        final id = int.tryParse(state.pathParameters['id'] ?? '');
        return ProductFormScreen(productId: id);
      },
    ),
    GoRoute(
      path: '/bulk',
      builder: (context, state) => const BulkProductScreen(),
    ),
    GoRoute(
      path: '/prices',
      builder: (context, state) => const EditPricesScreen(),
    ),
    // ... other product routes
  ],
),

// Customer Routes  
GoRoute(
  path: '/customers',
  builder: (context, state) => const CustomerManagementScreen(),
  routes: [
    GoRoute(
      path: '/new',
      builder: (context, state) => const CustomerFormScreen(),
    ),
    GoRoute(
      path: '/:id',
      builder: (context, state) {
        final id = int.tryParse(state.pathParameters['id'] ?? '');
        return CustomerProfileScreen(customerId: id);
      },
    ),
  ],
),
```

### Navigation Patterns

**Mobile (< 768px):**
- Bottom navigation bar (5-7 items max)
- Slide-up modals for forms
- Full screen for complex workflows
- Back button in AppBar always visible

**Tablet (768px - 1024px):**
- Side navigation rail or bottom bar
- Dialog modals for forms
- Split view for master-detail (optional)
- Back button in AppBar

**Desktop (> 1024px):**
- Persistent sidebar navigation
- Dialog modals for forms
- Multiple windows support (future)
- Keyboard shortcuts enabled

---

## 📐 Responsive Design Requirements

### Screen Size Breakpoints

```dart
// Use these exact breakpoints
class ScreenBreakpoints {
  static const double mobile = 600;   // < 600px = Mobile
  static const double tablet = 1024;  // 600px - 1024px = Tablet  
  static const double desktop = 1024; // > 1024px = Desktop
}

// Implementation pattern
LayoutBuilder(
  builder: (context, constraints) {
    if (constraints.maxWidth < ScreenBreakpoints.mobile) {
      return MobileLayout();
    } else if (constraints.maxWidth < ScreenBreakpoints.tablet) {
      return TabletLayout();
    } else {
      return DesktopLayout();
    }
  },
)
```

### Layout Patterns by Screen Size

**Mobile Layout (< 600px):**
- Single column layouts
- Bottom navigation (4-5 items)
- Full-screen modals
- Vertical scrolling
- Touch-friendly targets (44px min)

**Tablet Layout (600px - 1024px):**
- Two-column layouts where appropriate
- Side rail or bottom navigation
- Dialog modals (50-70% width)
- Horizontal scrolling for tables
- Mix of touch and mouse interaction

**Desktop Layout (> 1024px):**
- Multi-column layouts
- Fixed sidebar navigation (240px width)
- Dialog modals (500px max width)
- No horizontal scrolling
- Mouse-optimized interactions

---

## 🎨 Component Architecture

### Screen Structure Pattern

**EVERY screen MUST follow this structure:**

```dart
Scaffold(
  appBar: AppBar(
    title: Text('screen_title'.tr()),
    // Back button automatic on mobile/tablet
    actions: [
      // Screen-specific actions
    ],
  ),
  body: SafeArea(
    child: BlocBuilder<FeatureBloc, RealtimeState<FeatureData>>(
      builder: (context, state) {
        if (state is RealtimeLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state is RealtimeError) {
          return ErrorWidget(error: state.error);
        }
        if (state is RealtimeSuccess) {
          return ResponsiveLayout(
            mobile: MobileContent(data: state.data),
            tablet: TabletContent(data: state.data),
            desktop: DesktopContent(data: state.data),
          );
        }
        return const SizedBox.shrink();
      },
    ),
  ),
  floatingActionButton: FloatingActionButton(...), // Optional
)
```

### Modal/Dialog Pattern

**Form Dialogs:**
```dart
// Mobile: Full screen modal
showModalBottomSheet(
  context: context,
  isScrollControlled: true,
  builder: (context) => DraggableScrollableSheet(
    initialChildSize: 0.9,
    maxChildSize: 0.95,
    builder: (context, scrollController) => FormScreen(),
  ),
);

// Desktop: Dialog
showDialog(
  context: context,
  builder: (context) => Dialog(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 500),
      child: FormScreen(),
    ),
  ),
);
```

---

## 🔗 Screen Integration Requirements

### Database Integration (MANDATORY)

**EVERY screen MUST be database-wired:**
```dart
// Screen Bloc extends RealtimeBloc
class ProductScreenBloc extends RealtimeBloc<List<Product>, ProductEvent> {
  @override
  Stream<List<Product>> get dataStream => _repository.watchProducts();
}

// UI automatically updates when database changes
BlocBuilder<ProductScreenBloc, RealtimeState<List<Product>>>(
  builder: (context, state) {
    // UI rebuilds automatically when products change
  },
)
```

### Currency Integration (MANDATORY)

**ALL money displays MUST use CurrencyService:**
```dart
// In widgets with currency
final currencyService = context.read<CurrencyBloc>().state.data;
Text(currencyService.format(priceInCents))

// Input fields MUST use CurrencyService.formatInput()
TextFormField(
  onChanged: (value) {
    final formatted = currencyService.formatInput(value);
    _controller.value = TextEditingValue(text: formatted);
  },
)
```

### Localization Integration (MANDATORY)

**ALL text MUST be localized:**
```dart
Text('screen_title'.tr())
Text('button_label'.tr())
hintText: 'field_hint'.tr()
```

---

## 🚫 What NOT to Do

### Common UI Architecture Mistakes

❌ **Hardcoded navigation paths** - Use GoRouter constants  
❌ **Platform-specific layouts** - Make responsive layouts work everywhere  
❌ **Standalone components** - Everything must be database-wired  
❌ **Hardcoded currency symbols** - Use CurrencyService  
❌ **Missing back navigation** - Keep default AppBar behavior  
❌ **Overflow on any screen size** - Test all breakpoints  
❌ **Non-localized text** - Use .tr() for everything  
❌ **Manual state management** - Use RealtimeBloc pattern  

---

## 📋 Screen Implementation Checklist

When implementing ANY screen, verify:

- [ ] Follows responsive breakpoint pattern (mobile/tablet/desktop)
- [ ] Uses Scaffold with proper AppBar
- [ ] Bloc extends RealtimeBloc with database stream
- [ ] All text is localized (.tr())
- [ ] Money displays use CurrencyService
- [ ] Money inputs use CurrencyService.formatInput()
- [ ] Navigation uses GoRouter
- [ ] Back button works correctly
- [ ] No overflow on any screen size
- [ ] Semantic colors (success/warning/error)
- [ ] Works in Light AND Dark themes
- [ ] Tested in English, Arabic (RTL), French
- [ ] Real-time updates work without manual refresh

---

## 🎯 Quick Reference

### Common Screen Patterns

**List Screen:** Search/Filter + List + Add Button  
**Form Screen:** Form Fields + Validation + Save/Cancel  
**Detail Screen:** Info Display + Edit/Delete Actions  
**Modal Dialog:** Focused Task + Close Button  
**POS Screen:** Product Grid + Cart + Checkout

### Navigation Helpers

```dart
// Navigate to screen
context.go('/products');

// Navigate with parameters
context.go('/products/edit/123');

// Modal navigation
context.push('/customers/new');

// Back navigation
context.pop();
```

---

**Last Updated**: 2026-01-26  
**Version**: 1.0.0  
**Status**: ACTIVE - Follow strictly for all screen implementations
