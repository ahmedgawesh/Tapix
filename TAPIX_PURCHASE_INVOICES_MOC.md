# TAPIX Purchase Invoices & Returns — World-Class UI/UX MOC

## Overview

This document describes the phased UI/UX enhancement plan for Epic 6 (Purchase Management).
The goal: make Tapix's purchase invoices and purchase returns rival the best commercial POS/ERP apps worldwide (Loyverse, Vend, Square, Odoo).

## Current State Analysis

### What Exists (5 Screens)
1. **PurchaseListScreen** — Hub with stats cards, search, status filters, purchase tiles
2. **PurchaseFormScreen** — Create/edit purchase with supplier, dates, items, discounts, totals
3. **PurchaseDetailScreen** — View purchase with timeline, info, items, totals, returns history
4. **PurchaseReturnsScreen** — Returns list with search, date filter, summary bar
5. **PurchaseReturnFormScreen** — Create return from purchase with item selection, reason, financial impact

### What Needs Improvement
- **List screens** lack visual polish — tiles are flat, no micro-animations, no swipe actions
- **Form screens** work but feel "developer-made" — need premium feel with better spacing, visual hierarchy, and micro-interactions
- **Detail screen** is functional but not impressive — needs a proper invoice-style layout
- **Dialogs** (supplier picker, product picker, edit item) need refinement
- **Returns** need a more professional flow with better visual feedback
- **No barcode scanner integration** in purchase flow (Story 6-10)
- **Missing supplier payment/refund dialogs** (Stories 6-8, 6-9)

---

## Phase 1: Purchase List Screen (Stories 6-1, 6-3)

### Enhancements
- **Animated stat cards** with subtle scale-on-appear animation
- **Gradient accent** on stat card icons for premium feel
- **Purchase tiles** with:
  - Left color accent bar based on status (orange=draft, green=posted, red=voided)
  - Supplier avatar with initials
  - Item count badge
  - Swipe-to-reveal actions (edit draft / view detail)
  - Subtle shadow elevation on hover/press
- **Sticky search bar** that collapses into app bar on scroll
- **Date range filter** chip alongside status filters
- **Empty state** with illustration-style icon composition
- **Pull-to-refresh** with custom indicator
- **Quick action FAB** with speed dial (New Purchase, New Return)

### Files Modified
- `purchase_list_screen.dart` — Enhanced tiles, animations, filters

---

## Phase 2: Purchase Form Screen (Stories 6-1, 6-4, 6-6, 6-7)

### Enhancements
- **Step indicator** at top showing progress (Supplier → Items → Review)
- **Supplier card** with avatar, balance preview, recent purchase count
- **Items card** with:
  - Drag-to-reorder capability
  - Swipe-to-delete with undo snackbar
  - Animated item addition (slide-in from right)
  - Better quantity stepper with long-press for fast increment
  - Inline cost editing with tap-to-edit pattern
  - Color-coded variant chips
- **Totals card** with animated counter for total amount
- **Bottom bar** with glassmorphism effect and prominent save button
- **Product selection dialog** with:
  - Category tabs for faster browsing
  - Grid/list toggle
  - Recently purchased products section
  - Barcode scan button (Story 6-10)
- **Edit item sheet** with:
  - Product image placeholder
  - Better field layout with icons
  - Live total preview as you type

### Files Modified
- `purchase_form_screen.dart` — Premium form UX

---

## Phase 3: Purchase Detail Screen (Stories 6-5)

### Enhancements
- **Invoice-style header** with:
  - Large purchase number with status badge
  - Supplier info block with name, phone, address
  - Date block with purchase date and due date
  - Supplier invoice reference
- **Professional items table** with:
  - Header row (Product, Qty, Unit Cost, Discount, Total)
  - Alternating row colors for readability
  - Variant info as subtitle
  - Expiry date warning badges
- **Totals section** styled like a real invoice footer
  - Subtotal, Discount, Tax, Grand Total
  - Payment status indicator
- **Action buttons** redesigned:
  - Post button with confirmation animation
  - Return button with clear visual hierarchy
  - Void with danger styling and double-confirm
- **Returns history** with expandable cards showing return items
- **Print/Share** action in app bar

### Files Modified
- `purchase_detail_screen.dart` — Invoice-style detail view

---

## Phase 4: Purchase Returns Screen (Stories 6-2, 6-11)

### Enhancements
- **Summary dashboard** at top with:
  - Total returns count
  - Total refund amount
  - Returns this month trend
- **Return tiles** with:
  - Status indicator (processed/pending)
  - Original purchase reference link
  - Item count and refund amount
  - Reason preview
  - Tap to expand and see return items inline
- **Date range filter** with preset options (Today, This Week, This Month)
- **Search** across return numbers, supplier names, reasons

### Files Modified
- `purchase_returns_screen.dart` — Premium returns list

---

## Phase 5: Purchase Return Form Screen (Stories 6-2, 6-12, 6-13)

### Enhancements
- **Original purchase preview** card with:
  - Purchase number, supplier, date, total
  - Visual link showing "Returning from..."
- **Item selection** with:
  - Select All / Deselect All toggle
  - Visual quantity slider instead of just +/- buttons
  - Max quantity indicator (X of Y available)
  - Running refund total per item
  - Color-coded selection (red border when selected)
- **Reason section** with:
  - Quick-select reason chips (Defective, Wrong Item, Damaged, Other)
  - Free-text area for details
- **Financial impact card** with:
  - Before/After comparison
  - Animated refund amount
  - Inventory impact visualization
- **Confirmation dialog** before processing with summary

### Files Modified
- `purchase_return_form_screen.dart` — World-class return flow

---

## Phase 6: Supplier Payment & Refund Dialogs (Stories 6-8, 6-9)

### New Components
- **Supplier Payment Dialog** — Record payment to supplier
  - Amount input with remaining balance display
  - Payment method selector (Cash, Bank Transfer, Check)
  - Reference number field
  - Date picker
  - Running balance preview
- **Supplier Refund Dialog** — Record refund/credit from supplier
  - Similar to payment but for credits
  - Link to return if applicable

### Files Created
- Dialogs integrated into purchase detail screen actions

---

## Implementation Rules

1. **No breaking changes** — All enhancements are additive to existing working code
2. **Integer cents** — All money math uses Decimal/integer cents
3. **Variant-aware** — All item displays show variant info when applicable
4. **Realtime** — All lists use RealtimeBloc pattern with Drift streams
5. **Responsive** — Wide (desktop) and narrow (mobile) layouts
6. **i18n** — All strings use easy_localization `.tr()`
7. **Architecture** — Clean Architecture + Bloc + DI via get_it
8. **No new dependencies** — Use existing packages only

---

## Execution Order

1. Phase 1 → Purchase List Screen polish
2. Phase 2 → Purchase Form Screen premium UX
3. Phase 3 → Purchase Detail Screen invoice-style
4. Phase 4 → Purchase Returns Screen polish
5. Phase 5 → Purchase Return Form Screen premium UX
6. Phase 6 → Payment/Refund dialogs
7. Run `flutter analyze` → Fix all issues
8. Update `sprint-status.yaml` → Mark all Epic 6 stories done
