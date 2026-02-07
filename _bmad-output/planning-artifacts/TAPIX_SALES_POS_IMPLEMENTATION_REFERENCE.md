# TAPIX Sales & POS Implementation Reference
> **Companion guide to TAPIX_SALES_POS_ENHANCED_MOC.md**
> **Date**: February 2025
> **Epic**: EPIC-05 (Stories 5.1-5.17)

---

## 🎯 Critical Implementation Requirements

### 1. Single Source of Truth - Product Variants

Per project-context.md, **variants are the authoritative source**:

```dart
// ALWAYS use variantId, never productId
class SaleLineItem {
  final int id;
  final int saleId;
  final int variantId;  // REQUIRED - links to product_variants table
  final int quantity;
  final int unitPriceCents;  // From variant.priceCents at time of sale
  final int discountCents;
  final String? notes;
  
  // Calculate total in cents
  int get lineTotalCents => (quantity * unitPriceCents) - discountCents;
}

// Cart items also use variantId
class CartItem {
  final String id;  // UUID for session persistence
  final int variantId;
  final int quantity;
  final int unitPriceCents;  // Snapshot of price at add time
  final int discountCents;
  final DateTime addedAt;
}
```

### 2. Integer Cents Money Math

**NEVER use floating point for money**:

```dart
// CORRECT: Integer cents
class MoneyCalculations {
  static int calculateSubtotal(List<CartItem> items) {
    return items.fold(0, (sum, item) => sum + item.lineTotalCents);
  }
  
  static int calculateTax(int subtotalCents, int taxRatePerThousand) {
    // taxRatePerThousand: 150 for 15%
    return (subtotalCents * taxRatePerThousand) ~/ 1000;
  }
  
  static int calculateTotal(int subtotalCents, int taxCents, int discountCents) {
    return subtotalCents + taxCents - discountCents;
  }
  
  static String formatMoney(int cents, String currency) {
    final dollars = cents ~/ 100;
    final remainingCents = cents % 100;
    return '$currency$dollars.${remainingCents.toString().padLeft(2, '0')}';
  }
}

// WRONG: Never do this!
// double total = 25.99 * quantity;  // ❌ Floating point errors
```

### 3. Real-Time State Management

All POS features must extend `RealtimeBloc`:

```dart
class CartBloc extends RealtimeBloc<CartState, CartEvent> {
  final ProductVariantRepository _variantRepository;
  final CustomerRepository _customerRepository;
  
  CartBloc(this._variantRepository, this._customerRepository) 
    : super(const CartState.initial()) {
    on<CartEvent>(_onCartEvent);
  }
  
  @override
  Stream<CartState> get dataStream => 
    CombineLatestStream.combine4(
      _variantRepository.watchAllVariants(),
      _customerRepository.watchAllCustomers(),
      Stream.value(_currentCustomerId),
      Stream.value(_heldSales),
      _buildCartState,
    );
  
  void _onCartEvent(CartEvent event, Emitter<CartState> emit) {
    switch (event) {
      case AddItem(variantId, quantity):
        _addItem(variantId, quantity);
      case UpdateQuantity(itemId, quantity):
        _updateQuantity(itemId, quantity);
      case RemoveItem(itemId):
        _removeItem(itemId);
      case ApplyDiscount(itemId, discountCents):
        _applyDiscount(itemId, discountCents);
      case ClearCart():
        _clearCart();
      case HoldSale(customerId, notes):
        _holdSale(customerId, notes);
    }
  }
}
```

### 4. Database Schema (Drift)

```dart
// sales table
@DataClassName('Sale')
class Sales extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get customerId => integer().nullable().references(Customers, #id)();
  IntColumn get subtotalCents => integer()();
  IntColumn get taxCents => integer()();
  IntColumn get discountCents => integer()();
  IntColumn get totalCents => integer()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  TextColumn get status => text()(); // draft, posted, void
  TextColumn get paymentStatus => text()(); // unpaid, partial, paid
  TextColumn get notes => text().nullable()();
}

// sale_line_items table
@DataClassName('SaleLineItem')
class SaleLineItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get saleId => integer().references(Sales, #id)();
  IntColumn get variantId => integer().references(ProductVariants, #id)();
  IntColumn get quantity => integer()();
  IntColumn get unitPriceCents => integer()();
  IntColumn get discountCents => integer()();
  TextColumn get notes => text().nullable()();
  
  // Ensure we don't oversell
  @override
  Set<Column> get primaryKey => {saleId, variantId};
}

// payments table
@DataClassName('Payment')
class Payments extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get saleId => integer().references(Sales, #id)();
  TextColumn get method => text()(); // cash, card, bank, credit
  IntColumn get amountCents => integer()();
  DateTimeColumn get processedAt => dateTime()();
  TextColumn get reference => text().nullable()(); // card auth code, etc.
  TextColumn get status => text()(); // pending, completed, failed
}
```

### 5. Component Library

#### Variant-Aware Product Selector
```dart
class VariantProductSelector extends StatelessWidget {
  const VariantProductSelector({super.key});
  
  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProductVariantsBloc, ProductVariantsState>(
      builder: (context, state) {
        return state.when(
          loading: () => const CircularProgressIndicator(),
          error: (error) => Text('Error: $error'),
          loaded: (variants) => GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              childAspectRatio: 0.8,
            ),
            itemCount: variants.length,
            itemBuilder: (context, index) {
              final variant = variants[index];
              return ProductVariantCard(
                variant: variant,
                onTap: () => context.read<CartBloc>().add(
                  AddItem(variant.id, 1),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class ProductVariantCard extends StatelessWidget {
  final ProductVariant variant;
  final VoidCallback onTap;
  
  const ProductVariantCard({
    super.key,
    required this.variant,
    required this.onTap,
  });
  
  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: variant.imageUrl != null
                    ? Image.network(variant.imageUrl!, fit: BoxFit.cover)
                    : const Icon(Icons.image, size: 48),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                variant.productName,
                style: Theme.of(context).textTheme.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (variant.colorName != null || variant.sizeName != null)
                Text(
                  '${variant.colorName ?? ''} ${variant.sizeName ?? ''}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              Text(
                MoneyCalculations.formatMoney(variant.priceCents, '$'),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              Row(
                children: [
                  Icon(
                    Icons.inventory_2,
                    size: 16,
                    color: variant.stockQuantity > 0 
                      ? Colors.green 
                      : Colors.red,
                  ),
                  Text(
                    '${variant.stockQuantity}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

#### Payment Method Selector
```dart
class PaymentMethodSelector extends StatefulWidget {
  final int totalCents;
  final Function(List<Payment>) onPaymentsComplete;
  
  const PaymentMethodSelector({
    super.key,
    required this.totalCents,
    required this.onPaymentsComplete,
  });
  
  @override
  State<PaymentMethodSelector> createState() => _PaymentMethodSelectorState();
}

class _PaymentMethodSelectorState extends State<PaymentMethodSelector> {
  final List<Payment> _payments = [];
  int _remainingAmount = 0;
  
  @override
  void initState() {
    super.initState();
    _remainingAmount = widget.totalCents;
  }
  
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Payment method grid
        GridView.count(
          shrinkWrap: true,
          crossAxisCount: 3,
          childAspectRatio: 2,
          children: PaymentMethod.values.map((method) {
            return PaymentMethodButton(
              method: method,
              onTap: () => _selectPaymentMethod(method),
            );
          }).toList(),
        ),
        
        // Payment breakdown
        if (_payments.isNotEmpty) ...[
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Payment Breakdown',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  ..._payments.map((payment) => ListTile(
                    dense: true,
                    leading: Icon(_getPaymentIcon(payment.method)),
                    title: Text(payment.method.name),
                    trailing: Text(
                      MoneyCalculations.formatMoney(payment.amountCents, '$'),
                    ),
                  )),
                  const Divider(),
                  ListTile(
                    dense: true,
                    title: const Text('Remaining'),
                    trailing: Text(
                      MoneyCalculations.formatMoney(_remainingAmount, '$'),
                      style: TextStyle(
                        color: _remainingAmount > 0 
                          ? Theme.of(context).colorScheme.error
                          : Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        
        // Action buttons
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: _remainingAmount <= 0 
                ? () => widget.onPaymentsComplete(_payments)
                : null,
              child: const Text('Process Payment'),
            ),
          ],
        ),
      ],
    );
  }
  
  void _selectPaymentMethod(PaymentMethod method) {
    // Show payment amount dialog based on method
    showDialog(
      context: context,
      builder: (context) => PaymentAmountDialog(
        method: method,
        maxAmount: _remainingAmount,
        onConfirm: (amountCents) {
          setState(() {
            _payments.add(Payment(
              method: method,
              amountCents: amountCents,
              processedAt: DateTime.now(),
              status: 'pending',
            ));
            _remainingAmount -= amountCents;
          });
          Navigator.of(context).pop();
        },
      ),
    );
  }
}
```

### 6. Loyalty Integration

```dart
class LoyaltyIntegration {
  static Future<LoyaltyDiscount> calculateLoyaltyDiscount(
    Customer customer,
    int subtotalCents,
    LoyaltyRepository loyaltyRepo,
  ) async {
    if (!customer.loyaltyEnabled) {
      return LoyaltyDiscount.none();
    }
    
    final loyaltySummary = await loyaltyRepo.getLoyaltySummary(customer.id);
    
    // Apply tier-based discount
    int discountCents = 0;
    switch (loyaltySummary.tierName) {
      case 'Bronze':
        discountCents = (subtotalCents * 0.01).round(); // 1%
        break;
      case 'Silver':
        discountCents = (subtotalCents * 0.025).round(); // 2.5%
        break;
      case 'Gold':
        discountCents = (subtotalCents * 0.05).round(); // 5%
        break;
      case 'Premium':
        discountCents = (subtotalCents * 0.075).round(); // 7.5%
        break;
    }
    
    return LoyaltyDiscount(
      discountCents: discountCents,
      tierName: loyaltySummary.tierName,
      pointsEarned: ((subtotalCents - discountCents) * 0.01).round(),
    );
  }
}
```

### 7. Offline-First Implementation

```dart
class OfflineSaleQueue {
  final Database _db;
  final Queue<Sale> _pendingSales = Queue();
  
  Future<void> queueSale(Sale sale) async {
    // Mark as pending sync
    final pendingSale = sale.copyWith(syncStatus: 'pending');
    await _db.insertPendingSale(pendingSale);
    _pendingSales.add(pendingSale);
  }
  
  Future<void> syncPendingSales() async {
    while (_pendingSales.isNotEmpty) {
      final sale = _pendingSales.first;
      try {
        // Attempt to sync
        await _syncSaleToServer(sale);
        _pendingSales.removeFirst();
        await _db.updateSaleSyncStatus(sale.id, 'synced');
      } catch (e) {
        // Keep in queue for next retry
        break;
      }
    }
  }
  
  Future<void> _syncSaleToServer(Sale sale) async {
    // Implement server sync logic
  }
}
```

### 8. Testing Strategy

```dart
// Unit tests for money calculations
void main() {
  group('MoneyCalculations', () {
    test('calculateSubtotal sums correctly', () {
      final items = [
        CartItem(variantId: 1, quantity: 2, unitPriceCents: 2500, discountCents: 0),
        CartItem(variantId: 2, quantity: 1, unitPriceCents: 7500, discountCents: 500),
      ];
      
      final subtotal = MoneyCalculations.calculateSubtotal(items);
      expect(subtotal, equals(12000)); // $120.00
    });
    
    test('calculateTax handles rounding correctly', () {
      final tax = MoneyCalculations.calculateTax(3333, 150); // 15% of $33.33
      expect(tax, equals(499)); // $4.99 (rounded down)
    });
  });
}

// Integration tests for POS workflow
void main() {
  testWidgets('complete sale workflow', (tester) async {
    // 1. Add items to cart
    await tester.pumpWidget(TestApp(child: POSScreen()));
    await tester.tap(find.byKey(Key('product_tshirt_red_large')));
    await tester.pump();
    
    // 2. Verify cart total
    expect(find.text('$50.00'), findsOneWidget);
    
    // 3. Proceed to payment
    await tester.tap(find.byKey(Key('checkout_button')));
    await tester.pumpAndSettle();
    
    // 4. Select payment method
    await tester.tap(find.byKey(Key('payment_cash')));
    await tester.pump();
    
    // 5. Enter amount
    await tester.enterText(find.byKey(Key('cash_amount')), '60.00');
    await tester.tap(find.byKey(Key('process_payment')));
    await tester.pumpAndSettle();
    
    // 6. Verify sale completed
    expect(find.byType(SuccessDialog), findsOneWidget);
  });
}
```

---

## 📋 Story Implementation Checklist

### Story 5.1 - POS Interface & Cart
- [ ] Product grid with variant selection
- [ ] Real-time stock badges
- [ ] Cart with variantId storage
- [ ] Integer cents calculations
- [ ] Barcode scanner integration
- [ ] Voice search capability

### Story 5.2 - Checkout & Payment
- [ ] Multi-payment support
- [ ] Split payment UI
- [ ] Payment method persistence
- [ ] Change calculation
- [ ] Card reader integration
- [ ] Offline payment queue

### Story 5.3 - Invoice Printing
- [ ] PDF generation with integer cents
- [ ] Thermal printer support
- [ ] Arabic RTL layout
- [ ] QR code generation
- [ ] Email/SMS receipts
- [ ] Batch printing

### Story 5.4 - Sale Returns Processing
- [ ] Original sale reference
- [ ] Variant-aware returns
- [ ] Inventory restoration
- [ ] Refund calculations
- [ ] Return reason codes
- [ ] Store credit option

### Stories 5.5-5.17
- [ ] All screens use RealtimeBloc
- [ ] All money values in cents
- [ ] All references use variantId
- [ ] Responsive design tested
- [ ] RTL support verified
- [ ] Offline functionality tested

---

## 🎨 Icon Resources

Recommended icon sets for consistent design:
- Material Design Icons (built-in)
- Lucide Icons (modern, clean)
- Custom POS icons: 🛒 💳 💵 🏦 ⏰ 📄 🔄 📊 📥 ⚙️

---

## ⚠️ Critical Reminders

1. **NEVER store productId in cart/sale lines - always variantId**
2. **ALWAYS use integer cents for money - NEVER floating point**
3. **ALL BLoCs must extend RealtimeBloc for real-time updates**
4. **EVERY screen must work offline and sync when online**
5. **ARABIC RTL support is mandatory - test with Arabic text**
6. **RESPONSIVE design is required - test on all screen sizes**
7. **VARIANT stock is authoritative - check before adding to cart**

---

*This implementation reference ensures TAPIX Sales & POS maintains architectural integrity while delivering world-class user experience.*
