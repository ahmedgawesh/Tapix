# TAPIX Sales & POS Enhanced MOC
> **Version**: 1.0 (Based on global best practices research)
> **Date**: February 2025
> **Epic**: EPIC-05 (Stories 5.1-5.17)
> **Language**: English/Arabic/French (Full RTL Support)

---

## 🎯 Design Philosophy

Based on research of leading POS solutions (Square, Shopify POS, Toast, Lightspeed) and TAPIX's unique strengths:
- **Variant-first POS**: Unlike generic POS systems, TAPIX's deep variant integration is our key differentiator
- **Real-time transparency**: Every sale immediately updates inventory, accounting, and analytics
- **Offline-first resilience**: Works seamlessly even with internet interruptions
- **Mobile-native design**: Touch-optimized interfaces that adapt beautifully to all screen sizes
- **Single source of truth**: All financial data flows through the accounting integrity architecture

---

## 🏗️ Core Screen Architecture

### 1. POS Interface & Cart (Story 5.1) - Modern Split Design

#### Layout Pattern: Dynamic Three-Pane
```
┌─────────────────────────────────────────────────────────────┐
│ ☰ TAPIX POS          [Search...] [📷] [🔍]      [⚙️] [👤] │
├─────────────────────────────────────────────────────────────┤
│ ┌─────────────┐ ┌──────────────────┐ ┌─────────────────────┐ │
│ │   Products  │ │      Cart        │ │    Customer Info    │ │
│ │   Grid      │ │                  │ │    (Optional)       │ │
│ │             │ │ ┌─Item───────┐   │ │                     │ │
│ │ 📱 T-Shirt  │ │ │×2 Red L    │$2000│ │ Ahmed Mohamed      │ │
│ │ 👕 Jeans    │ │ │×1 Blue M   │$2500│ │ ─────────────────  │ │
│ │ 👟 Shoes    │ │ │────────────│   │ │ │ Balance: $15000   │ │
│ │ 🧢 Hat      │ │ │ Subtotal   │$6500│ │ │ Points: 1,250    │ │
│ │             │ │ │ Tax 15%    │$975 │ │ │ Tier: Gold       │ │
│ │ [Categories]│ │ │ Total      │$7475│ │ └────────────────  │ │
│ │             │ │ └────────────┘   │ │ [Select Customer]  │ │
│ │             │ │                 │ │ [Add New Customer]  │ │
│ │             │ │ ┌─Payment─────┐   │ │                     │ │
│ │             │ │ │ [💵 Cash]   │   │ │ ┌─Quick Actions───┐ │ │
│ │             │ │ │ [💳 Card]   │   │ │ │ [💳 Hold Sale]  │ │ │
│ │             │ │ │ [🏦 Bank]   │   │ │ │ [📄 Print]      │ │ │
│ │             │ │ │ [⏰ Credit] │   │ │ │ [🔄 Return]     │ │ │
│ │             │ │ └─────────────┘   │ │ └─────────────────┘ │ │
│ └─────────────┘ └──────────────────┘ └─────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

#### Key Enhancements:

1. **Smart Product Grid**
   - Dynamic tile sizes based on product image availability
   - Quick-add variant picker on hover/tap
   - Real-time stock badge on each product
   - Barcode scanner with vibration feedback
   - Voice search integration ("Red t-shirt large")

2. **Interactive Cart Sidebar**
   - Drag to reorder items
   - Swipe to delete with undo
   - Inline quantity editor with +/- buttons
   - Line-item discount with preset percentages
   - Split line items (e.g., sell 5 of 10 items)

3. **Customer Integration Panel**
   - Customer search with avatar display
   - Loyalty points and tier visualization
   - Quick customer creation
   - Credit limit warning
   - Recent purchase history

4. **Touch-Optimized Number Pad**
   ```dart
   NumberPad(
     layout: NumberPadLayout.pos,
     size: NumberPadSize.large,
     quickAmounts: [10, 20, 50, 100],
     onAmountChanged: (amount) => cart.updateTotal(amount),
   )
   ```

---

### 2. Checkout & Payment (Story 5.2) - Elegant Payment Flow

#### Modern Payment Interface
```
┌─────────────────────────────────────────────────────────────┐
│ [←] Checkout Payment                     Total: $1,250.00 │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│ ┌─ Payment Method Selection ─────────────────────────────┐ │
│ │                                                         │ │
│ │  [💵] Cash      [💳] Card      [🏦] Bank Transfer     │ │
│ │  [⏰] Credit    [📱] Mobile    [🎫] Gift Card        │ │
│ │                                                         │ │
│ │  Selected: [💳 Card Payment]                           │ │
│ └─────────────────────────────────────────────────────────┘ │
│                                                             │
│ ┌─ Card Entry ─────────────────────────────────────────┐ │
│ │ Card Number: [____ ____ ____ ____]                    │ │
│ │ Expiry: [__]/[__]  CVV: [___]                        │ │
│ │                                                         │ │
│ │ ┌─ Split Payment ─────────────────────────────────┐   │ │
│ │ │ Pay: $800.00 of $1,250.00                       │   │ │
│ │ │ Remaining: $450.00                              │   │ │
│ │ │ [Add Payment Method]                            │   │ │
│ │ └───────────────────────────────────────────────────┘   │ │
│ └─────────────────────────────────────────────────────────┘ │
│                                                             │
│ ┌─ Transaction Summary ─────────────────────────────────┐ │
│ │ Subtotal:     $1,086.96                               │ │
│ │ Tax (15%):    $163.04                                 │ │
│ │ Discount:     ($0.00)                                 │ │
│ │ ────────────────────────────────────                 │ │
│ │ Total:        $1,250.00                               │ │
│ │ Paid:         $800.00                                 │ │
│ │ Remaining:    $450.00                                 │ │
│ └─────────────────────────────────────────────────────────┘ │
│                                                             │
│                    [Cancel]  [Process Payment]            │
└─────────────────────────────────────────────────────────────┘
```

#### Payment Features:

1. **Multi-Payment Support**
   - Up to 4 payment methods per transaction
   - Visual payment breakdown
   - Automatic change calculation for cash
   - Tip calculation for card payments

2. **Integrated Payment Processing**
   - Card reader integration (Bluetooth/USB)
   - NFC tap-to-pay support
   - Digital wallet integration
   - Offline payment queue

3. **Security Features**
   - PCI compliance mode
   - Secure card tokenization
   - Receipt signature capture
   - Manager override for refunds

---

### 3. Sales Screen (Story 5.5) - Dashboard View

#### Sales Dashboard with Analytics
```
┌─────────────────────────────────────────────────────────────┐
│ Sales Dashboard                    [📊] [📥] [🔄] [⚙️]    │
├─────────────────────────────────────────────────────────────┤
│ ┌─ Today's Summary ───┐ ┌─ Quick Stats ─────────────────┐ │
│ │ Sales: $12,450      │ │ 📈 Trend: +15% vs yesterday   │ │
│ │ Transactions: 89    │ │ 🛒 Items: 342 units           │ │
│ │ Avg Sale: $140      │ │ 👥 Customers: 67 unique       │ │
│ │ Returns: $230       │ │ 💳 Card: 78% | Cash: 22%      │ │
│ └─────────────────────┘ └─────────────────────────────────┘ │
│                                                             │
│ ┌─ Recent Sales ─────────────────────────────────────────┐ │
│ │ #1234  Ahmed M.   $250.00  2 min ago   [📄][🔄]     │ │
│ │ #1233  Sara S.    $89.50   15 min ago  [📄][🔄]     │ │
│ │ #1232  Omar K.    $1,200   1 hour ago  [📄][🔄]     │ │
│ │ #1231  Fatima A.  $45.00   2 hours ago [📄][🔄]     │ │
│ └─────────────────────────────────────────────────────────┘ │
│                                                             │
│ ┌─ Filters ─────────────────────────────────────────────┐ │
│ │ Date: [Today ▼]  Status: [All ▼]  Payment: [All ▼]   │ │
│ │ Customer: [Search...]  Amount: $0 - $∞                │ │
│ └─────────────────────────────────────────────────────────┘ │
│                                                             │
│ ┌─ Sales List ───────────────────────────────────────────┐ │
│ │ ID    Customer        Total     Time      Status       │ │
│ │ ─────────────────────────────────────────────────────  │ │
│ │ #1234 Ahmed Mohamed   $250.00   14:23    ✅ Paid      │ │
│ │ #1233 Sara Saleh     $89.50    14:08    ✅ Paid      │ │
│ │ #1232 Omar Khalid    $1,200.00 13:15    ⏳ Partial   │ │
│ │ #1231 Fatima Ali     $45.00    12:30    ✅ Paid      │ │
│ │ #1230 Hassan R.      $340.00   11:45    💳 Card      │ │
│ └─────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

---

### 4. Sale Returns Processing (Story 5.4 & 5.16-5.17) - Streamlined Flow

#### Return from Original Sale
```
┌─────────────────────────────────────────────────────────────┐
│ [←] Process Return                         [Process Return] │
├─────────────────────────────────────────────────────────────┤
│ ┌─ Original Sale ─────────────────────────────────────────┐ │
│ │ Sale #1234 • Ahmed Mohamed • Feb 7, 2025 • $250.00     │ │
│ └─────────────────────────────────────────────────────────┘ │
│                                                             │
│ ┌─ Items to Return ───────────────────────────────────────┐ │
│ │ ☑ T-Shirt Red Large    ×2  $50.00  Reason: [Wrong Size ▼]│ │
│ │ ☑ Jeans Blue Medium    ×1  $75.00  Reason: [Defective ▼] │ │
│ │ ☐ Shoes Black 9        ×1  $120.00 Reason: [Select...]   │ │
│ │                                                         │ │
│ │ Return Options:                                         │ │
│ │ ◉ Refund to Original Payment Method                      │ │
│ │ ○ Store Credit                                          │ │
│ │ ○ Exchange for Different Items                          │ │
│ └─────────────────────────────────────────────────────────┘ │
│                                                             │
│ ┌─ Impact Summary ─────────────────────────────────────────┐ │
│ │ Items to Return: 3 items                               │ │
│ │ Refund Amount: $125.00                                  │ │
│ │ Tax to Refund: $18.75                                   │ │
│ │ Total Refund: $143.75                                   │ │
│ │                                                         │ │
│ │ Inventory Updates:                                      │ │
│ │ + T-Shirt Red Large: +2 units                           │ │
│ │ + Jeans Blue Medium: +1 unit                            │ │
│ │                                                         │ │
│ │ Customer Balance:                                       │ │
│ │ ◉ Apply refund to outstanding balance                   │ │
│ │ ○ Process as store credit                               │ │
│ └─────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

---

### 5. Invoice Printing (Story 5.3 & 5.13) - Professional Templates

#### Modern Invoice Design
```
┌─────────────────────────────────────────────────────────────┐
│ ┌─ Logo ─────┐ TAPIX STORE              Invoice #1234    │
│ │             │ 123 Main Street          Date: Feb 7, 2025│
│ │   [Logo]    │ Cairo, Egypt             Time: 14:23     │
│ └─────────────┘ Tel: +20 123 456 7890                     │
├─────────────────────────────────────────────────────────────┤
│ Customer: Ahmed Mohamed                                   │
│ Address: 45 El Tahrir St, Cairo                          │
│ Phone: +20 100 123 4567                                   │
├─────────────────────────────────────────────────────────────┤
│ Qty  Description                 Price      Total         │
│ ───────────────────────────────────────────────────────  │
│ 2    T-Shirt - Red, Large        $25.00     $50.00       │
│ 1    Jeans - Blue, Medium        $75.00     $75.00       │
│ 1    Shoes - Black, Size 9       $120.00    $120.00      │
│ ───────────────────────────────────────────────────────  │
│                              Subtotal:    $245.00       │
│                              Tax (15%):    $36.75       │
│                              Discount:     ($5.00)      │
│                              ─────────────             │
│                              TOTAL:       $276.75       │
├─────────────────────────────────────────────────────────────┤
│ Payment: Card (**** **** **** 1234)                       │
│ Auth Code: 123456                                         │
│                                                             │
│ Thank you for your purchase!                               │
│ Return policy: 7 days with receipt                         │
├─────────────────────────────────────────────────────────────┤
│ QR Code: [████████████]    Powered by TAPIX               │
└─────────────────────────────────────────────────────────────┘
```

#### Printing Features:
- Thermal printer optimization (58mm/80mm)
- A4 format for detailed invoices
- Arabic RTL support with proper font rendering
- QR code for digital receipt
- Email/SMS receipt options
- Batch printing for end-of-day

---

## 🎨 Modern UI Components Library

### 1. Product Card Widget
```dart
ProductCard(
  product: product,
  variants: variants,
  layout: ProductCardLayout.grid,
  onTap: () => showVariantSelector(),
  onLongPress: () => quickAddToCart(),
  showStockBadge: true,
  showDiscountBadge: true,
)
```

### 2. Cart Item Widget
```dart
CartItemTile(
  item: cartItem,
  onQuantityChanged: (qty) => updateQuantity(qty),
  onDiscount: () => showDiscountDialog(),
  onRemove: () => removeFromCart(),
  editable: true,
  showImage: true,
)
```

### 3. Payment Method Button
```dart
PaymentMethodButton(
  method: PaymentMethod.card,
  selected: paymentMethod == PaymentMethod.card,
  onTap: () => selectPaymentMethod(PaymentMethod.card),
  icon: Icons.credit_card,
  label: 'Card Payment',
)
```

### 4. Sale Status Badge
```dart
StatusBadge(
  status: SaleStatus.paid,
  style: StatusBadgeStyle.compact,
  showIcon: true,
)
```

---

## 📱 Responsive Design Strategy

### Breakpoints & Adaptations
```dart
// Mobile:    < 600px   (Single column, bottom sheets)
// Tablet:    600-1024px (Two-column, compact UI)
// Desktop:   > 1024px  (Three-column, full features)
// Wide:      > 1440px  (Extra spacing, preview panels)
```

### Mobile-First Patterns
1. **Bottom Sheet for Actions**
   - Swipe up to reveal cart
   - Haptic feedback on actions
   - Gesture-based navigation

2. **Floating Action Button**
   - Quick sale mode toggle
   - Hold for advanced options
   - Smart positioning

3. **Pull-to-Refresh**
   - Real-time sync indicator
   - Offline queue status
   - Last sync timestamp

---

## 🔄 Real-Time State Management

### Sales Bloc Architecture
```dart
class SalesBloc extends RealtimeBloc<SalesState, SalesEvent> {
  // Real-time streams for:
  // - Cart updates
  // - Payment processing
  // - Inventory changes
  // - Customer balances
  // - Offline sync queue
}

class CartBloc extends RealtimeBloc<CartState, CartEvent> {
  // Optimistic updates
  // Conflict resolution
  // Persistence across sessions
}
```

### Offline-First Features
1. **Sync Indicators**
   - 🟢 All changes synced
   - 🟡 Pending sync (3 items)
   - 🔴 Sync failed
   - ⚪ Offline mode

2. **Offline Queue**
   - Sales queued when offline
   - Automatic retry on reconnect
   - Conflict resolution UI

---

## 🌐 Localization & RTL Support

### Arabic RTL Adaptations
- Complete layout mirroring
- Arabic number formatting
- Proper text alignment
- Icon positioning adjustments
- Font: IBM Plex Sans Arabic

### Multi-Currency Support
- Dynamic currency symbols
- Locale-aware formatting
- Real-time conversion rates
- Dual currency display

---

## 🔐 Security & Permissions

### Role-Based Access
- **Owner**: Full access, refunds, voids
- **Manager**: Sales, returns, reports
- **Cashier**: Sales only, limited returns
- **Salesperson**: Sales with customer management

### Audit Trail
- Every sale logged with user ID
- Void/return requires authorization
- Tamper-evident logs
- Daily closure reports

---

## 📊 Analytics & Reporting

### Real-Time Dashboard Widgets
1. **Sales Velocity**
   - Items per hour
   - Peak hours identification
   - Staff performance

2. **Product Performance**
   - Top selling items
   - Low stock alerts
   - Margin analysis

3. **Payment Analytics**
   - Payment method distribution
   - Average transaction value
   - Cash handling efficiency

---

## 🚀 Performance Optimizations

### Instant Response
- Preload popular products
- Cache customer data
- Optimistic UI updates
- Virtualized long lists

### Battery Optimization
- Minimal background sync
- Efficient barcode scanning
- Smart refresh intervals
- Dark mode support

---

## ✅ Implementation Checklist

### Core Stories (5.1-5.4)
- [ ] POS interface with variant-aware cart
- [ ] Multi-payment processing with split payments
- [ ] Professional invoice templates (RTL support)
- [ ] Return processing with original sale reference

### Management Screens (5.5-5.6)
- [ ] Sales dashboard with real-time analytics
- [ ] Sale form with customer integration
- [ ] Advanced search and filtering
- [ ] Bulk operations support

### Dialogs & Interactions (5.7-5.15)
- [ ] Product selection with barcode support
- [ ] Line item editing with validation
- [ ] Customer payment processing
- [ ] Split payment interface
- [ ] Settlement calculations
- [ ] Void authorization workflow
- [ ] Print options dialog
- [ ] Quick sale summary

### Returns Management (5.16-5.17)
- [ ] Returns list with filters
- [ ] Return form with reason codes
- [ ] Inventory restoration
- [ ] Refund processing

---

## 🎯 Success Metrics

1. **User Experience**
   - Complete sale in under 60 seconds
   - < 3 taps to add any product
   - 99.9% uptime offline
   - 95% user satisfaction

2. **Business Impact**
   - Increase average transaction value by 15%
   - Reduce checkout time by 40%
   - Improve inventory accuracy to 99.95%
   - Zero accounting discrepancies

3. **Technical Excellence**
   - < 200ms response time
   - 100% data integrity
   - Seamless cross-platform experience
   - Automatic conflict resolution

---

## 📝 Development Notes

### Key Dependencies
```yaml
dependencies:
  flutter_bloc: ^8.1.3
  drift: ^2.14.1
  pdf: ^3.10.4
  qr_flutter: ^4.1.0
  mobile_scanner: ^3.5.6
  vibration: ^1.8.4
  local_auth: ^2.1.6
```

### Critical Architecture Requirements

#### 1. Integer Cents Implementation
All monetary values MUST use integer cents:
```dart
class CartItem {
  final int variantId;  // REQUIRED - not productId
  final int quantity;
  final int unitPriceCents;  // e.g., 2500 for $25.00
  final int discountCents;   // e.g., 500 for $5.00
  
  int get lineTotalCents => quantity * unitPriceCents - discountCents;
}

class Sale {
  final List<SaleLineItem> lineItems;  // Each contains variantId
  final int subtotalCents;
  final int taxCents;
  final int totalCents;
}
```

#### 2. Variant-First Architecture
Per project-context.md, variants are the authoritative source:
- Cart stores `variantId` (not `productId`)
- Stock checks use `variant.stockQuantity`
- Price comes from `variant.priceCents`
- Barcode links to specific variant

#### 3. Loyalty Integration
Integration with CustomerLoyaltyBloc during checkout:
```dart
// Apply loyalty benefits during payment
final loyaltySummary = await customerLoyaltyBloc.getLoyaltySummary(customerId);
final discountCents = applyLoyaltyDiscount(subtotalCents, loyaltySummary.tier);
final pointsEarned = calculatePoints(subtotalCents - discountCents);
```

#### 4. Hold Sale Persistence
For offline scenarios:
```dart
class HeldSale {
  final String id;
  final List<CartItem> items;
  final Customer? customer;
  final DateTime createdAt;
  final String? notes;
  // Persisted locally, synced when online
}
```

### Testing Strategy
- Unit tests for all integer cents calculations
- Integration tests for variant workflows
- UI tests for critical paths
- Performance tests for large datasets
- Accessibility tests for screen readers

### Opus 4.5 Review Summary
✅ All 17 stories covered
✅ Clean Architecture compliance
⚠️ Must implement integer cents (not floats)
⚠️ Must use variantId (not productId) 
⚠️ Add loyalty tier integration
⚠️ Include hold sale persistence

---

*This MOC positions TAPIX Sales & POS as a world-class, modern point-of-sale solution that leverages our unique variant management and real-time architecture while delivering exceptional user experience across all platforms.*
