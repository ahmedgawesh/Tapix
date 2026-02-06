# TAPIX Enhanced Purchase Invoice & Return Management MOC
> **Version**: 2.0 (Enhanced based on global best practices research)
> **Date**: February 2025
> **Epic**: EPIC-06 (Stories 6.1-6.13)

---

## 🎯 Design Philosophy

Based on research of leading solutions (Stampli, BILL, SAP Concur) and TAPIX's unique strengths:
- **Variant-first approach**: Unlike generic ERPs, TAPIX's deep variant integration is our key differentiator
- **Real-time transparency**: Every change immediately reflects across all screens
- **Offline-first resilience**: Works seamlessly even with intermittent connectivity
- **Mobile-native design**: Touch-friendly interfaces that adapt beautifully to all screen sizes

---

## 🏗️ Enhanced Screen Architecture

### 1. Purchase Invoice Form (Story 6.4) - Redesigned

#### Layout Pattern: Adaptive Split-Pane
```
┌─────────────────────────────────────────────────────────────┐
│ [← Back] New Purchase Invoice          [Save Draft] [Post] │
├─────────────────────────────────────────────────────────────┤
│ ┌─────────────────┐ ┌─────────────────────────────────────┐ │
│ │   Header Pane   │ │         Line Items Pane             │ │
│ │                 │ │                                     │ │
│ │ Supplier: [▼]   │ │ ┌─[+ Add Item]────────────────────┐ │ │
│ │ Invoice #: Auto │ │ │ Product Variant    | Qty | Cost │ │ │
│ │ Date: [📅]      │ │ │ ───────────────────────────────── │ │ │
│ │ Due: [📅]       │ │ │ T-Shirt Red L     | 100 | $5.00│ │ │
│ │ Ref: [______]   │ │ │ Jeans Blue M      |  50 | $25.00│ │ │
│ │                 │ │ │ [Scan 📷] [Search 🔍]           │ │ │
│ │ Status: Draft   │ │ └─────────────────────────────────┘ │ │
│ │                 │ │                                     │ │
│ │ 💬 Notes (3)    │ │ ┌─Summary─────────────────────────┐ │ │
│ │                 │ │ │ Subtotal: $1,750.00             │ │ │
│ │ ┌─Payments────┐ │ │ │ Discount (5%): $87.50           │ │ │
│ │ │ Paid: $0    │ │ │ │ Tax (15%): $249.38              │ │ │
│ │ │ Due: $1,912 │ │ │ │ Total: $1,911.88               │ │ │
│ │ └─────────────┘ │ │ └─────────────────────────────────┘ │ │
│ └─────────────────┘ └─────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

#### Key Enhancements:

1. **Variant-Aware Item Selection**
   - Inline variant picker showing color/size combinations
   - Real-time stock preview while selecting
   - Barcode scanner directly adds specific variant
   - Auto-suggest based on purchase history

2. **Three-Way Matching Visualizer** (Premium Feature)
   ```
   ┌─ Matching Status ─────────────────────────────────┐
   │ PO #001  ──✓──> Receipt #001  ──⚠──> Invoice #001 │
   │ 100 units        98 units           $1,911.88   │
   │                  ⚠ 2 units shortage             │
   └────────────────────────────────────────────────────┘
   ```

3. **Communication Center**
   - Threaded notes attached to invoice
   - @mentions for team members
   - Document attachments (scanned copies, agreements)
   - Timeline of all actions

4. **Smart Actions Toolbar**
   - Context-aware buttons that change based on status
   - Quick pay (integrates with payment dialog)
   - Return selected items
   - Duplicate invoice
   - Print/Export (PDF, Excel, JSON)

5. **Mobile Adaptations**
   - Stacked layout on small screens
   - Swipe gestures between header/items
   - Floating action button for quick actions
   - Touch-optimized number inputs

---

### 2. Purchase Returns Form (Story 6.12) - Enhanced

#### Return Flow with Original Invoice Reference
```
┌─────────────────────────────────────────────────────────────┐
│ [← Back] New Purchase Return            [Process Return]   │
├─────────────────────────────────────────────────────────────┤
│ ┌─────────────────┐ ┌─────────────────────────────────────┐ │
│ │   Return Info   │ │         Items to Return             │ │ │
│ │                 │ │                                     │ │ │
│ │ From: [▼]       │ │ ┌─[+ Add from Purchase]────────────┐ │ │
│ │ Original: #001  │ │ │ Product Variant    | Qty | Reason│ │ │
│ │ Date: [📅]      │ │ │ ───────────────────────────────── │ │ │
│ │ Type: [▼]       │ │ │ T-Shirt Red L     |  5 | Damaged│ │ │
│ │                 │ │ │ Jeans Blue M      |  2 | Wrong  │ │ │
│ │ ┌─Restock─────┐ │ │ │ [Select from original items]     │ │ │
│ │ │ ✓ Restock   │ │ │ └─────────────────────────────────┘ │ │
│ │ □ Write-off   │ │ │                                     │ │ │
│ │ □ Repair      │ │ │ ┌─Impact───────────────────────────┐ │ │
│ │ □ Replace     │ │ │ │ Inventory恢复: +7 units          │ │ │
│ │ □ Refund      │ │ │ │ Supplier Balance: -$175.00       │ │ │
│ └─────────────┘ │ │ │ Credit Note: Auto-generated       │ │ │
│                 │ │ └───────────────────────────────────┘ │ │
│ └─────────────────┘ └─────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

#### Enhanced Features:

1. **Smart Return Options**
   - Suggest items from original purchase
   - Batch return by reason type
   - Partial return with automatic calculations
   - Return authorization workflow

2. **Disposition Management**
   - Restock to warehouse/location
   - Write-off with reason codes
   - Send for repair
   - Request replacement from supplier

3. **Financial Impact Preview**
   - Real-time balance updates
   - Automatic credit note generation
   - Tax implications calculation
   - Multi-currency support (future)

---

### 3. Purchase List Screen (Story 6.3) - Kanban Board View

#### Status-Based Pipeline
```
┌─────────────────────────────────────────────────────────────┐
│ Purchases                    [📊 Reports] [⁺ New Invoice]   │
├─────────────────────────────────────────────────────────────┤
│ ┌─ Draft ───────┐ ┌─ Pending ─────┐ ┌─ Partial ──────┐    │
│ │ #003          │ │ #001          │ │ #002           │    │
│ │ ABC Supplier  │ │ XYZ Corp      │ │ ABC Supplier   │    │
│ │ $1,200        │ │ $1,912        │ │ $850           │    │
│ │ 2 days ago    │ │ 5 days ago    │ │ 1 week ago     │    │
│ │ [Edit] [Post] │ │ [Pay] [Return]│ │ [Pay $400]     │    │
│ └───────────────┘ └───────────────┘ └────────────────┘    │
│                                                            │
│ ┌─ Paid ─────────┐ ┌─ Overdue ──────┐                     │
│ │ #004           │ │ #005           │                     │
│ │ Global Imports │ │ Fast Supply    │                     │
│ │ $3,500         │ │ $650           │                     │
│ │ 2 weeks ago    │ │ 3 days overdue │                     │
│ │ [View] [Print] │ │ [Pay Now]      │                     │
│ └────────────────┘ └────────────────┘                     │
└─────────────────────────────────────────────────────────────┘
```

#### Advanced Filtering & Search
- Date range picker with presets
- Supplier multi-select
- Status filters
- Amount range slider
- Full-text search across all fields
- Saved filter presets

---

## 📱 Responsive Design Strategy

### Breakpoints
```dart
// Mobile:    < 768px   (Stacked layout)
// Tablet:    768-1024px (Compact split)
// Desktop:   > 1024px  (Full split-pane)
// Wide:      > 1440px  (Extra margins)
```

### Mobile-First Patterns
1. **Bottom Sheet for Actions**
   - Swipe up to reveal actions
   - Haptic feedback on selection
   - Gesture-based navigation

2. **Floating Action Buttons**
   - Primary action always accessible
   - Speed dial for secondary actions
   - Smart positioning based on scroll

3. **Pull-to-Refresh**
   - Real-time data sync
   - Sync status indicators
   - Offline queue management

---

## 🔄 Real-Time State Management

### Bloc Integration
```dart
class PurchaseInvoiceBloc extends RealtimeBloc<PurchaseInvoiceState, PurchaseInvoiceEvent> {
  // Real-time updates for:
  // - Supplier balance changes
  // - Stock level updates
  // - Payment status changes
  // - Return processing
}
```

### Offline-First Features
1. **Sync Indicators**
   - Green: All synced
   - Orange: Pending sync
   - Red: Sync failed
   - Gray: Offline mode

2. **Conflict Resolution**
   - Visual diff for conflicting changes
   - Smart merge suggestions
   - Manual override options

---

## 🎨 Modern UI Components

### 1. Variant Selector Widget
```dart
VariantPicker(
  productId: 'xxx',
  onVariantSelected: (variant) {
    // Update line item with variant details
    // Show real-time stock
    // Calculate costs
  },
)
```

### 2. Smart Number Input
```dart
MoneyInput(
  initialValue: 0,
  currency: 'USD',
  allowNegative: false, // For quantities
  integerCents: true,   // For money fields
)
```

### 3. Status Timeline
```dart
StatusTimeline(
  statuses: [
    Status('Draft', completed: true),
    Status('Posted', completed: true),
    Status('Partial', completed: true),
    Status('Paid', completed: false),
  ],
)
```

---

## 📊 Enhanced Reports & Analytics

### 1. Purchase Dashboard Widget
- Monthly purchase trend
- Top suppliers by volume
- Average payment terms
- Pending returns overview
- Budget vs actual

### 2. Supplier Performance Card
```
┌─ Supplier Performance ─────────────────────────────┐
│ ABC Trading                              ⭐ 4.8/5 │
│ ┌──────────────────────────────────────────────┐ │
│ │ On-Time Delivery: 95%  📈                  │ │
│ │ Quality Score: 98%    ✅                   │ │
│ │ Returns: 2%          ⬇️                   │ │
│ │ Avg Payment: 15 days ⏱️                   │ │
│ └──────────────────────────────────────────────┘ │
│ [View Full Profile] [Contact]                  │
└──────────────────────────────────────────────────┘
```

---

## 🌐 Localization & RTL Support

### Arabic (RTL) Adaptations
- Flip all layouts
- Adjust icon positioning
- Right-align text fields
- Proper number formatting for Arabic numerals

### Currency & Number Formatting
- Locale-aware decimal separators
- Currency symbol positioning
- Right-to-left number support for Arabic

---

## 🔐 Security & Permissions

### Role-Based Access
- **Owner**: Full access
- **Manager**: Create, edit, approve purchases
- **Cashier**: View only, process returns
- **Salesperson**: Limited view

### Audit Trail
- Every change logged with user, timestamp, and previous values
- Immutable record for compliance
- Export audit logs

---

## 🚀 Performance Optimizations

### Lazy Loading
- Paginate large purchase lists
- Virtual scroll for line items
- On-demand image loading

### Caching Strategy
- Supplier list cache
- Product variant cache
- Recent searches cache

---

## ✅ Implementation Checklist

### Story 6.1 - Purchase Orders
- [ ] Enhanced form with variant picker
- [ ] Three-way matching UI
- [ ] Communication thread
- [ ] Mobile responsive layout

### Story 6.2 - Purchase Returns
- [ ] Original invoice reference
- [ ] Disposition management
- [ ] Financial impact preview
- [ ] Batch return processing

### Story 6.3 - Purchases Screen
- [ ] Kanban board view
- [ ] Advanced filtering
- [ ] Real-time status updates
- [ ] Quick action buttons

### Stories 6.4-6.13
- [ ] All forms use enhanced components
- [ ] Consistent design language
- [ ] Accessibility compliance
- [ ] Cross-platform testing

---

## 🎯 Success Metrics

1. **User Efficiency**
   - Reduce invoice creation time by 40%
   - 90% of purchases created in under 2 minutes
   - 95% user satisfaction score

2. **Data Accuracy**
   - Zero accounting integrity violations
   - 100% variant-aware transactions
   - Automatic discrepancy detection

3. **System Performance**
   - < 500ms response time for all actions
   - 100% offline functionality
   - Real-time sync within 2 seconds

---

## 📝 Next Steps

1. **Prototype Development**
   - Create interactive mockups
   - Test with actual users
   - Iterate based on feedback

2. **Technical Implementation**
   - Set up Bloc architecture
   - Implement Drift schemas
   - Build reusable components

3. **Testing & Validation**
   - Unit tests for all calculations
   - Integration tests for workflows
   - Cross-platform compatibility tests

---

*This enhanced MOC design positions TAPIX as a modern, competitive purchase management solution while maintaining its unique strengths in variant management and real-time accuracy.*
