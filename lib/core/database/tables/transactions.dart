import 'package:drift/drift.dart';
import '../converters/money_converter.dart';
import 'settings.dart';
import 'products.dart';
import 'parties.dart';
import 'people.dart';
import 'users.dart';
import 'cashier_shifts.dart';

/// Phase 3 — Normalised reason codes for sale & purchase returns.
///
/// A lookup table so reporting / BI can slice returns by a **stable
/// machine code** rather than free-text `reason` strings. The code is
/// also used by some regulators (ZATCA Phase 2, ETA) as the
/// "reason-for-return" field on the credit-note XML.
///
/// Rows with [isSystem]`=true` are seeded by the app and cannot be
/// deleted — deleting them would break existing return references.
@DataClassName('ReturnReasonCode')
class ReturnReasonCodes extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get code => text().unique()();
  TextColumn get labelEn => text()();
  TextColumn get labelAr => text()();

  /// `sale` | `purchase` | `both`.
  TextColumn get side => text().withDefault(const Constant('both'))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  BoolColumn get isSystem => boolean().withDefault(const Constant(false))();
  TextColumn get description => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('Sale')
class Sales extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get invoiceNumber => text().unique()();
  IntColumn get customerId => integer().nullable().references(
    Customers,
    #id,
    onDelete: KeyAction.restrict,
  )();
  @ReferenceName('salesAsEmployee')
  IntColumn get employeeId => integer().nullable().references(
    Employees,
    #id,
    onDelete: KeyAction.restrict,
  )();
  IntColumn get cashierShiftId => integer().nullable().references(
    CashierShifts,
    #id,
    onDelete: KeyAction.setNull,
  )();
  IntColumn get subtotalCents => integer().map(const MoneyConverter())();
  IntColumn get taxCents => integer().map(const MoneyConverter())();
  IntColumn get discountCents =>
      integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  IntColumn get totalCents => integer().map(const MoneyConverter())();
  IntColumn get paidAmountCents =>
      integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  IntColumn get currencyId =>
      integer().references(Currencies, #id, onDelete: KeyAction.restrict)();
  TextColumn get paymentMethod => text()();
  TextColumn get status => text().withDefault(const Constant('completed'))();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get saleDate => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get dueDate => dateTime().nullable()();

  /// Phase 11.2 — pricing engine version that produced this row's
  /// `subtotal/discount/tax/total`. NULL for legacy rows. See
  /// `PricingEngineVersion`.
  TextColumn get pricingEngineVersion => text().nullable()();

  /// Phase 11.2 — tax-inclusive setting in force at post time. NULL for
  /// legacy rows. Used by audit / replay to reproduce the breakdown.
  BoolColumn get taxInclusiveAtPost => boolean().nullable()();

  /// Phase 11.2 — rounding mode in force at post time (`halfUp` |
  /// `halfEven` | `down`). NULL for legacy rows.
  TextColumn get roundingModeAtPost => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('SaleItem')
class SaleItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get saleId =>
      integer().references(Sales, #id, onDelete: KeyAction.cascade)();
  IntColumn get productId =>
      integer().references(Products, #id, onDelete: KeyAction.restrict)();
  IntColumn get variantId => integer().nullable().references(
    ProductVariants,
    #id,
    onDelete: KeyAction.restrict,
  )();
  @ReferenceName('saleItemsAsEmployee')
  IntColumn get employeeId => integer().nullable().references(
    Employees,
    #id,
    onDelete: KeyAction.setNull,
  )();
  IntColumn get quantity => integer()();
  IntColumn get quantityScale => integer().withDefault(const Constant(1))();
  TextColumn get measurementType =>
      text().withDefault(const Constant('piece'))();
  IntColumn get unitPriceCents => integer().map(const MoneyConverter())();
  IntColumn get subtotalCents => integer().map(const MoneyConverter())();
  IntColumn get discountCents =>
      integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  IntColumn get taxCents =>
      integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  IntColumn get totalCents => integer().map(const MoneyConverter())();

  /// Frozen cost-per-unit at the time the sale was posted.
  /// NULL for legacy rows created before this column existed.
  IntColumn get costCents => integer().nullable().map(const MoneyConverter())();

  /// Exact rounded-pool value removed from inventory when this sale posted.
  IntColumn get inventoryValueAtPostCents =>
      integer().nullable().map(const MoneyConverter())();

  /// Atomic returned-quantity counter (linked path).
  /// Bumped inside `postSaleReturn`, decremented inside `voidSaleReturn`.
  /// Used as the authoritative server-side cap so an over-return cannot slip
  /// through any UI / reporting drift (Phase 0 hard guard).
  IntColumn get qtyReturnedLinked => integer().withDefault(const Constant(0))();

  /// Atomic returned-quantity counter (adjustment / unlinked path).
  /// Bumped inside `postSaleAdjReturn`, decremented inside `voidSaleAdjReturn`.
  /// Combined with `qtyReturnedLinked` to form the total returned units
  /// against the original `quantity`, regardless of which return flow a
  /// user picked (linked vs adjustment).
  IntColumn get qtyReturnedAdjustment =>
      integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('SaleTaxBand')
class SaleTaxBands extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get saleId =>
      integer().references(Sales, #id, onDelete: KeyAction.cascade)();
  TextColumn get taxName => text()();
  IntColumn get taxRateBps => integer().map(const BasisPointsConverter())();
  IntColumn get taxAmountCents => integer().map(const MoneyConverter())();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('SaleReturn')
class SaleReturns extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get saleId =>
      integer().references(Sales, #id, onDelete: KeyAction.restrict)();
  IntColumn get cashierShiftId => integer().nullable().references(
    CashierShifts,
    #id,
    onDelete: KeyAction.setNull,
  )();
  TextColumn get returnNumber => text().unique()();
  IntColumn get subtotalCents =>
      integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  IntColumn get discountCents =>
      integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  IntColumn get taxCents =>
      integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  IntColumn get totalCents => integer().map(const MoneyConverter())();
  IntColumn get currencyId =>
      integer().references(Currencies, #id, onDelete: KeyAction.restrict)();

  /// draft, posted, voided
  TextColumn get status => text().withDefault(const Constant('draft'))();

  /// restock, write_off, exchange, store_credit, refund
  TextColumn get dispositionType =>
      text().withDefault(const Constant('restock'))();

  /// cash, credit, cheque
  TextColumn get refundMethod => text().withDefault(const Constant('cash'))();
  TextColumn get reason => text().nullable()();

  /// Client-generated idempotency token. Unique when present so a duplicated
  /// submission (double-tap, network retry) can never create two ledgers.
  TextColumn get idempotencyKey => text().nullable().unique()();

  /// Phase 2.4: FX rate to the base/reporting currency on the post date,
  /// stored as Decimal-as-TEXT for full precision (e.g. "3.7500"). NULL
  /// for legacy rows and same-currency returns. Used to revalue the JE
  /// at base currency and book the realized FX gain/loss.
  TextColumn get fxRateToBase => text().nullable()();

  // ── Phase 3 — approval, audit & reason codes ────────────────────────
  /// `auto_approved` | `pending` | `approved` | `rejected`.
  /// Always `auto_approved` unless `ReturnApprovalService` flagged the
  /// return for manager review at draft time. `ReturnPostingService.post`
  /// rejects anything that isn't `auto_approved` or `approved`.
  TextColumn get approvalStatus =>
      text().withDefault(const Constant('auto_approved'))();

  /// Set at draft-creation time by `ReturnApprovalService.evaluate()`.
  /// Cached here so reports / UI don't need to re-run policy.
  BoolColumn get approvalRequired =>
      boolean().withDefault(const Constant(false))();

  /// Comma-separated machine codes: `threshold_exceeded,no_invoice,override_used`.
  TextColumn get approvalReason => text().nullable()();

  @ReferenceName('saleReturnApprovedBy')
  IntColumn get approvedBy => integer().nullable().references(
    Users,
    #id,
    onDelete: KeyAction.setNull,
  )();
  DateTimeColumn get approvedAt => dateTime().nullable()();

  /// Free-text justification when an operator uses an override
  /// (e.g. `allowOverHistory`, no-invoice refund).
  TextColumn get overrideReason => text().nullable()();
  @ReferenceName('saleReturnOverrideBy')
  IntColumn get overrideBy => integer().nullable().references(
    Users,
    #id,
    onDelete: KeyAction.setNull,
  )();

  @ReferenceName('saleReturnPostedBy')
  IntColumn get postedBy => integer().nullable().references(
    Users,
    #id,
    onDelete: KeyAction.setNull,
  )();
  DateTimeColumn get postedAt => dateTime().nullable()();

  @ReferenceName('saleReturnVoidedBy')
  IntColumn get voidedBy => integer().nullable().references(
    Users,
    #id,
    onDelete: KeyAction.setNull,
  )();
  DateTimeColumn get voidedAt => dateTime().nullable()();
  TextColumn get voidReason => text().nullable()();

  /// Normalised reason code pulled from `return_reason_codes`.
  /// Free-text [reason] stays as operator remarks; the code drives
  /// reporting / analytics and is never translated at the call site.
  @ReferenceName('saleReturnReasonCode')
  IntColumn get reasonCodeId => integer().nullable().references(
    ReturnReasonCodes,
    #id,
    onDelete: KeyAction.setNull,
  )();

  DateTimeColumn get returnDate => dateTime().withDefault(currentDateAndTime)();

  /// Phase 14.0 — cheque due date for refunds paid by cheque.
  /// NULL for cash / credit refunds and legacy rows. Drives the dashboard
  /// cheque reminders (alongside the existing `sales.due_date`,
  /// `purchases.due_date`, and `*_return_adjustments.due_date`).
  DateTimeColumn get dueDate => dateTime().nullable()();

  /// Phase 11.2 — pricing engine version snapshot. See `Sales`.
  TextColumn get pricingEngineVersion => text().nullable()();

  /// Phase 11.2 — tax-inclusive setting at post time.
  BoolColumn get taxInclusiveAtPost => boolean().nullable()();

  /// Phase 11.2 — rounding mode at post time.
  TextColumn get roundingModeAtPost => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('SaleReturnItem')
class SaleReturnItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get returnId =>
      integer().references(SaleReturns, #id, onDelete: KeyAction.cascade)();
  IntColumn get saleItemId =>
      integer().references(SaleItems, #id, onDelete: KeyAction.restrict)();
  IntColumn get quantity => integer()();
  IntColumn get quantityScale => integer().withDefault(const Constant(1))();
  TextColumn get measurementType =>
      text().withDefault(const Constant('piece'))();
  IntColumn get subtotalCents =>
      integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  IntColumn get discountCents =>
      integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  IntColumn get taxCents =>
      integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  IntColumn get refundCents => integer().map(const MoneyConverter())();

  /// wrong_size, defective, wrong_item, changed_mind, other
  TextColumn get reason => text().nullable()();

  /// Phase 2.1 — frozen tax rate (basis points) sourced from the
  /// originating sale_item at post-time. Guarantees a future rate change
  /// (e.g. VAT 14%→15%) does not retroactively distort this return.
  IntColumn get taxRateBpsAtPost => integer().nullable()();

  /// Phase 2.1 — frozen unit cost at post-time (cents). Authoritative
  /// COGS reversal value; defends against WAC/FIFO drift between sale
  /// and return.
  IntColumn get unitCostAtPostCents =>
      integer().nullable().map(const MoneyConverter())();

  /// Exact rounded-pool value moved by this return line at posting time.
  IntColumn get inventoryValueAtPostCents =>
      integer().nullable().map(const MoneyConverter())();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('SalePayment')
class SalePayments extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get saleId =>
      integer().references(Sales, #id, onDelete: KeyAction.cascade)();
  IntColumn get cashierShiftId => integer().nullable().references(
    CashierShifts,
    #id,
    onDelete: KeyAction.setNull,
  )();
  IntColumn get amountCents => integer().map(const MoneyConverter())();
  IntColumn get currencyId =>
      integer().references(Currencies, #id, onDelete: KeyAction.restrict)();

  /// cash, card, bank_transfer, mobile, credit
  TextColumn get paymentMethod => text()();
  TextColumn get reference => text().nullable()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get paymentDate =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('Purchase')
class Purchases extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get purchaseNumber => text().unique()();
  IntColumn get supplierId =>
      integer().references(Suppliers, #id, onDelete: KeyAction.restrict)();
  IntColumn get subtotalCents => integer().map(const MoneyConverter())();
  IntColumn get discountCents =>
      integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  IntColumn get taxCents => integer().map(const MoneyConverter())();
  IntColumn get totalCents => integer().map(const MoneyConverter())();
  IntColumn get paidAmountCents =>
      integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  IntColumn get currencyId =>
      integer().references(Currencies, #id, onDelete: KeyAction.restrict)();
  TextColumn get status => text().withDefault(const Constant('draft'))();
  TextColumn get paymentMethod => text().nullable()();
  TextColumn get supplierInvoiceRef => text().nullable()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get purchaseDate =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get dueDate => dateTime().nullable()();

  /// Phase 11.2 — pricing engine version snapshot. See `Sales` for docs.
  TextColumn get pricingEngineVersion => text().nullable()();

  /// Phase 11.2 — tax-inclusive setting at post time.
  BoolColumn get taxInclusiveAtPost => boolean().nullable()();

  /// Phase 11.2 — rounding mode at post time.
  TextColumn get roundingModeAtPost => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('PurchaseItem')
class PurchaseItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get purchaseId =>
      integer().references(Purchases, #id, onDelete: KeyAction.cascade)();
  IntColumn get productId =>
      integer().references(Products, #id, onDelete: KeyAction.restrict)();
  IntColumn get variantId => integer().nullable().references(
    ProductVariants,
    #id,
    onDelete: KeyAction.restrict,
  )();
  IntColumn get quantity => integer()();
  IntColumn get quantityScale => integer().withDefault(const Constant(1))();
  TextColumn get measurementType =>
      text().withDefault(const Constant('piece'))();
  IntColumn get unitCostCents => integer().map(const MoneyConverter())();

  /// Exact rounded-pool value added to inventory when this purchase posted.
  IntColumn get inventoryValueAtPostCents =>
      integer().nullable().map(const MoneyConverter())();
  IntColumn get discountCents =>
      integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  IntColumn get subtotalCents => integer().map(const MoneyConverter())();
  IntColumn get taxCents =>
      integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  IntColumn get totalCents => integer().map(const MoneyConverter())();
  IntColumn get originalCostCents =>
      integer().map(const MoneyConverter()).nullable()();
  IntColumn get originalPriceCents =>
      integer().map(const MoneyConverter()).nullable()();
  IntColumn get originalWholesalePriceCents =>
      integer().map(const MoneyConverter()).nullable()();
  IntColumn get newSellPriceCents =>
      integer().map(const MoneyConverter()).nullable()();
  IntColumn get newWholesalePriceCents =>
      integer().map(const MoneyConverter()).nullable()();
  DateTimeColumn get expiryDate => dateTime().nullable()();

  /// Atomic returned-quantity counter (linked path).
  /// Bumped inside `postPurchaseReturn`, decremented inside `voidPurchaseReturn`.
  /// Phase 0 server-side cap to stop over-returning across multiple invoices.
  IntColumn get qtyReturnedLinked => integer().withDefault(const Constant(0))();

  /// Atomic returned-quantity counter (adjustment / unlinked path).
  /// Bumped inside `postPurchaseAdjReturn`, decremented inside `voidPurchaseAdjReturn`.
  /// Combined with `qtyReturnedLinked` to form the total returned units.
  IntColumn get qtyReturnedAdjustment =>
      integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('PurchaseReturn')
class PurchaseReturns extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get purchaseId =>
      integer().references(Purchases, #id, onDelete: KeyAction.restrict)();
  TextColumn get returnNumber => text().unique()();
  IntColumn get subtotalCents =>
      integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  IntColumn get discountCents =>
      integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  IntColumn get taxCents =>
      integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  IntColumn get totalCents => integer().map(const MoneyConverter())();
  IntColumn get currencyId =>
      integer().references(Currencies, #id, onDelete: KeyAction.restrict)();

  /// draft, posted, voided
  TextColumn get status => text().withDefault(const Constant('draft'))();

  /// restock, write_off, repair, replace, refund
  TextColumn get dispositionType =>
      text().withDefault(const Constant('restock'))();

  /// cash, credit, cheque
  TextColumn get refundMethod => text().withDefault(const Constant('credit'))();
  TextColumn get reason => text().nullable()();

  /// Client-generated idempotency token. Unique when present so a duplicated
  /// submission (double-tap, network retry) can never create two ledgers.
  TextColumn get idempotencyKey => text().nullable().unique()();

  /// Phase 2.4 — FX rate to base currency on post date (Decimal as TEXT).
  TextColumn get fxRateToBase => text().nullable()();

  // ── Phase 3 — approval, audit & reason codes ────────────────────────
  TextColumn get approvalStatus =>
      text().withDefault(const Constant('auto_approved'))();
  BoolColumn get approvalRequired =>
      boolean().withDefault(const Constant(false))();
  TextColumn get approvalReason => text().nullable()();
  @ReferenceName('purchaseReturnApprovedBy')
  IntColumn get approvedBy => integer().nullable().references(
    Users,
    #id,
    onDelete: KeyAction.setNull,
  )();
  DateTimeColumn get approvedAt => dateTime().nullable()();
  TextColumn get overrideReason => text().nullable()();
  @ReferenceName('purchaseReturnOverrideBy')
  IntColumn get overrideBy => integer().nullable().references(
    Users,
    #id,
    onDelete: KeyAction.setNull,
  )();
  @ReferenceName('purchaseReturnPostedBy')
  IntColumn get postedBy => integer().nullable().references(
    Users,
    #id,
    onDelete: KeyAction.setNull,
  )();
  DateTimeColumn get postedAt => dateTime().nullable()();
  @ReferenceName('purchaseReturnVoidedBy')
  IntColumn get voidedBy => integer().nullable().references(
    Users,
    #id,
    onDelete: KeyAction.setNull,
  )();
  DateTimeColumn get voidedAt => dateTime().nullable()();
  TextColumn get voidReason => text().nullable()();
  @ReferenceName('purchaseReturnReasonCode')
  IntColumn get reasonCodeId => integer().nullable().references(
    ReturnReasonCodes,
    #id,
    onDelete: KeyAction.setNull,
  )();

  DateTimeColumn get returnDate => dateTime().withDefault(currentDateAndTime)();

  /// Phase 14.0 — cheque due date for refunds paid by cheque.
  /// Symmetric to `SaleReturns.dueDate`. NULL for cash / credit refunds
  /// and legacy rows.
  DateTimeColumn get dueDate => dateTime().nullable()();

  /// Phase 11.2 — pricing engine version snapshot. See `Sales`.
  TextColumn get pricingEngineVersion => text().nullable()();

  /// Phase 11.2 — tax-inclusive setting at post time.
  BoolColumn get taxInclusiveAtPost => boolean().nullable()();

  /// Phase 11.2 — rounding mode at post time.
  TextColumn get roundingModeAtPost => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('PurchaseReturnItem')
class PurchaseReturnItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get returnId =>
      integer().references(PurchaseReturns, #id, onDelete: KeyAction.cascade)();
  IntColumn get purchaseItemId =>
      integer().references(PurchaseItems, #id, onDelete: KeyAction.restrict)();
  IntColumn get quantity => integer()();
  IntColumn get quantityScale => integer().withDefault(const Constant(1))();
  TextColumn get measurementType =>
      text().withDefault(const Constant('piece'))();
  IntColumn get subtotalCents =>
      integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  IntColumn get discountCents =>
      integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  IntColumn get taxCents =>
      integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  IntColumn get refundCents => integer().map(const MoneyConverter())();

  /// damaged, wrong_item, quality, overstock, other
  TextColumn get reason => text().nullable()();

  /// Phase 2.1 — frozen tax rate at post-time (basis points).
  IntColumn get taxRateBpsAtPost => integer().nullable()();

  /// Phase 2.1 — frozen unit cost at post-time. Sourced from the original
  /// purchase_item.unit_cost_cents (or batch cost for FIFO products).
  IntColumn get unitCostAtPostCents =>
      integer().nullable().map(const MoneyConverter())();

  /// Exact rounded-pool value moved by this return line at posting time.
  IntColumn get inventoryValueAtPostCents =>
      integer().nullable().map(const MoneyConverter())();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('PurchasePayment')
class PurchasePayments extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get purchaseId =>
      integer().references(Purchases, #id, onDelete: KeyAction.cascade)();
  IntColumn get amountCents => integer().map(const MoneyConverter())();
  IntColumn get currencyId =>
      integer().references(Currencies, #id, onDelete: KeyAction.restrict)();

  /// cash, card, cheque, bank_transfer
  TextColumn get paymentMethod => text()();
  TextColumn get reference => text().nullable()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get paymentDate =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

// ══════════════════════════════════════════════════════════════════════════════
// ADJUSTMENT RETURNS — Separate flow, NOT linked to any invoice
// ══════════════════════════════════════════════════════════════════════════════

/// Purchase return adjustment — product-based, not invoice-linked.
/// Used when quantity exceeds a single invoice, price was renegotiated, etc.
@DataClassName('PurchaseReturnAdjustment')
class PurchaseReturnAdjustments extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get returnNumber => text().unique()();
  IntColumn get supplierId =>
      integer().references(Suppliers, #id, onDelete: KeyAction.restrict)();
  IntColumn get currencyId =>
      integer().references(Currencies, #id, onDelete: KeyAction.restrict)();
  IntColumn get subtotalCents =>
      integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  IntColumn get discountCents =>
      integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  IntColumn get taxCents =>
      integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  IntColumn get totalCents => integer().map(const MoneyConverter())();

  /// draft, posted, voided
  TextColumn get status => text().withDefault(const Constant('draft'))();

  /// cash, credit, cheque
  TextColumn get refundMethod => text().withDefault(const Constant('credit'))();

  /// auto_adjustment, price_mismatch, no_invoice, quantity_overflow
  TextColumn get returnMode => text().nullable()();

  /// Human-readable reason the system chose this mode
  TextColumn get modeReason => text().nullable()();

  /// Groups linked + adjustment records created in the same unified return submission
  TextColumn get batchId => text().nullable()();

  /// Client-generated idempotency token. Unique when present so a duplicated
  /// submission (double-tap, network retry) can never create two ledgers.
  TextColumn get idempotencyKey => text().nullable().unique()();

  /// Phase 2.4 — FX rate to base currency on post date (Decimal as TEXT).
  TextColumn get fxRateToBase => text().nullable()();
  TextColumn get notes => text().nullable()();

  // ── Phase 3 — approval, audit & reason codes ────────────────────────
  TextColumn get approvalStatus =>
      text().withDefault(const Constant('auto_approved'))();
  BoolColumn get approvalRequired =>
      boolean().withDefault(const Constant(false))();
  TextColumn get approvalReason => text().nullable()();
  @ReferenceName('purchaseReturnAdjApprovedBy')
  IntColumn get approvedBy => integer().nullable().references(
    Users,
    #id,
    onDelete: KeyAction.setNull,
  )();
  DateTimeColumn get approvedAt => dateTime().nullable()();
  TextColumn get overrideReason => text().nullable()();
  @ReferenceName('purchaseReturnAdjOverrideBy')
  IntColumn get overrideBy => integer().nullable().references(
    Users,
    #id,
    onDelete: KeyAction.setNull,
  )();
  @ReferenceName('purchaseReturnAdjPostedBy')
  IntColumn get postedBy => integer().nullable().references(
    Users,
    #id,
    onDelete: KeyAction.setNull,
  )();
  DateTimeColumn get postedAt => dateTime().nullable()();
  @ReferenceName('purchaseReturnAdjVoidedBy')
  IntColumn get voidedBy => integer().nullable().references(
    Users,
    #id,
    onDelete: KeyAction.setNull,
  )();
  DateTimeColumn get voidedAt => dateTime().nullable()();
  TextColumn get voidReason => text().nullable()();
  @ReferenceName('purchaseReturnAdjReasonCode')
  IntColumn get reasonCodeId => integer().nullable().references(
    ReturnReasonCodes,
    #id,
    onDelete: KeyAction.setNull,
  )();

  DateTimeColumn get returnDate => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get dueDate => dateTime().nullable()();

  /// Phase 11.2 — pricing engine version snapshot. See `Sales`.
  TextColumn get pricingEngineVersion => text().nullable()();

  /// Phase 11.2 — tax-inclusive setting at post time.
  BoolColumn get taxInclusiveAtPost => boolean().nullable()();

  /// Phase 11.2 — rounding mode at post time.
  TextColumn get roundingModeAtPost => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('PurchaseReturnAdjustmentItem')
class PurchaseReturnAdjustmentItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get returnId => integer().references(
    PurchaseReturnAdjustments,
    #id,
    onDelete: KeyAction.cascade,
  )();
  IntColumn get productId =>
      integer().references(Products, #id, onDelete: KeyAction.restrict)();
  IntColumn get variantId => integer().nullable().references(
    ProductVariants,
    #id,
    onDelete: KeyAction.restrict,
  )();
  IntColumn get quantity => integer()();
  IntColumn get quantityScale => integer().withDefault(const Constant(1))();
  TextColumn get measurementType =>
      text().withDefault(const Constant('piece'))();
  IntColumn get unitPriceCents => integer().map(const MoneyConverter())();

  /// Frozen average cost at the moment of return creation (from products.cost_cents).
  /// Used for the Inventory GL leg of the journal entry.
  IntColumn get unitCostCents =>
      integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  IntColumn get discountCents =>
      integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  IntColumn get taxCents =>
      integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  IntColumn get totalCents => integer().map(const MoneyConverter())();
  TextColumn get reason => text().nullable()();

  /// Phase 2.1 — frozen tax rate at post-time (basis points).
  IntColumn get taxRateBpsAtPost => integer().nullable()();

  /// Phase 2.1 — frozen unit cost at post-time. Authoritative inventory
  /// value for the GL line; defends against WAC/FIFO drift between post
  /// and any later void.
  IntColumn get unitCostAtPostCents =>
      integer().nullable().map(const MoneyConverter())();

  /// Exact rounded-pool value moved by this return line at posting time.
  IntColumn get inventoryValueAtPostCents =>
      integer().nullable().map(const MoneyConverter())();

  /// Phase 2.1 — optional reference to the original purchase invoice this
  /// adjustment line is implicitly correcting (operator hint, not a hard FK
  /// constraint). Unbound when no specific invoice exists.
  IntColumn get originalInvoiceId => integer().nullable()();

  /// Phase 2.2 — per-line disposition: `restock` | `damaged` | `scrap` |
  /// `send_back`. Routes the inventory leg in `ReturnJournalPolicy` to
  /// 1200 / 5800 / 1290 accordingly.
  TextColumn get dispositionType =>
      text().withDefault(const Constant('restock'))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// Sale return adjustment — product-based, not invoice-linked.
/// Used when customer returns goods outside of a specific invoice context.
@DataClassName('SaleReturnAdjustment')
class SaleReturnAdjustments extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get returnNumber => text().unique()();
  IntColumn get customerId => integer().nullable().references(
    Customers,
    #id,
    onDelete: KeyAction.restrict,
  )();
  @ReferenceName('saleReturnAdjAsEmployee')
  IntColumn get employeeId => integer().nullable().references(
    Employees,
    #id,
    onDelete: KeyAction.setNull,
  )();
  IntColumn get cashierShiftId => integer().nullable().references(
    CashierShifts,
    #id,
    onDelete: KeyAction.setNull,
  )();
  IntColumn get currencyId =>
      integer().references(Currencies, #id, onDelete: KeyAction.restrict)();
  IntColumn get subtotalCents =>
      integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  IntColumn get discountCents =>
      integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  IntColumn get taxCents =>
      integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  IntColumn get totalCents => integer().map(const MoneyConverter())();

  /// draft, posted, voided
  TextColumn get status => text().withDefault(const Constant('draft'))();

  /// cash, credit, cheque
  TextColumn get refundMethod => text().withDefault(const Constant('cash'))();

  /// auto_adjustment, price_mismatch, no_invoice, quantity_overflow
  TextColumn get returnMode => text().nullable()();

  /// Human-readable reason the system chose this mode
  TextColumn get modeReason => text().nullable()();

  /// Groups linked + adjustment records created in the same unified return submission
  TextColumn get batchId => text().nullable()();

  /// Client-generated idempotency token. Unique when present so a duplicated
  /// submission (double-tap, network retry) can never create two ledgers.
  TextColumn get idempotencyKey => text().nullable().unique()();

  /// Phase 2.4 — FX rate to base currency on post date (Decimal as TEXT).
  TextColumn get fxRateToBase => text().nullable()();
  TextColumn get notes => text().nullable()();

  // ── Phase 3 — approval, audit & reason codes ────────────────────────
  TextColumn get approvalStatus =>
      text().withDefault(const Constant('auto_approved'))();
  BoolColumn get approvalRequired =>
      boolean().withDefault(const Constant(false))();
  TextColumn get approvalReason => text().nullable()();
  @ReferenceName('saleReturnAdjApprovedBy')
  IntColumn get approvedBy => integer().nullable().references(
    Users,
    #id,
    onDelete: KeyAction.setNull,
  )();
  DateTimeColumn get approvedAt => dateTime().nullable()();
  TextColumn get overrideReason => text().nullable()();
  @ReferenceName('saleReturnAdjOverrideBy')
  IntColumn get overrideBy => integer().nullable().references(
    Users,
    #id,
    onDelete: KeyAction.setNull,
  )();
  @ReferenceName('saleReturnAdjPostedBy')
  IntColumn get postedBy => integer().nullable().references(
    Users,
    #id,
    onDelete: KeyAction.setNull,
  )();
  DateTimeColumn get postedAt => dateTime().nullable()();
  @ReferenceName('saleReturnAdjVoidedBy')
  IntColumn get voidedBy => integer().nullable().references(
    Users,
    #id,
    onDelete: KeyAction.setNull,
  )();
  DateTimeColumn get voidedAt => dateTime().nullable()();
  TextColumn get voidReason => text().nullable()();
  @ReferenceName('saleReturnAdjReasonCode')
  IntColumn get reasonCodeId => integer().nullable().references(
    ReturnReasonCodes,
    #id,
    onDelete: KeyAction.setNull,
  )();

  DateTimeColumn get returnDate => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get dueDate => dateTime().nullable()();

  /// Phase 11.2 — pricing engine version snapshot. See `Sales`.
  TextColumn get pricingEngineVersion => text().nullable()();

  /// Phase 11.2 — tax-inclusive setting at post time.
  BoolColumn get taxInclusiveAtPost => boolean().nullable()();

  /// Phase 11.2 — rounding mode at post time.
  TextColumn get roundingModeAtPost => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('SaleReturnAdjustmentItem')
class SaleReturnAdjustmentItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get returnId => integer().references(
    SaleReturnAdjustments,
    #id,
    onDelete: KeyAction.cascade,
  )();
  IntColumn get productId =>
      integer().references(Products, #id, onDelete: KeyAction.restrict)();
  IntColumn get variantId => integer().nullable().references(
    ProductVariants,
    #id,
    onDelete: KeyAction.restrict,
  )();
  IntColumn get quantity => integer()();
  IntColumn get quantityScale => integer().withDefault(const Constant(1))();
  TextColumn get measurementType =>
      text().withDefault(const Constant('piece'))();
  IntColumn get unitPriceCents => integer().map(const MoneyConverter())();

  /// Frozen average cost at the moment of return creation (from products.cost_cents).
  /// Used for the Inventory GL leg of the journal entry.
  IntColumn get unitCostCents =>
      integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  IntColumn get discountCents =>
      integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  IntColumn get taxCents =>
      integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  IntColumn get totalCents => integer().map(const MoneyConverter())();
  TextColumn get reason => text().nullable()();

  /// Phase 2.1 — frozen tax rate at post-time (basis points).
  IntColumn get taxRateBpsAtPost => integer().nullable()();

  /// Phase 2.1 — frozen unit cost at post-time.
  IntColumn get unitCostAtPostCents =>
      integer().nullable().map(const MoneyConverter())();

  /// Exact rounded-pool value moved by this return line at posting time.
  IntColumn get inventoryValueAtPostCents =>
      integer().nullable().map(const MoneyConverter())();

  /// Phase 2.1 — optional reference to the original sale invoice this
  /// adjustment line is implicitly correcting (operator hint).
  IntColumn get originalInvoiceId => integer().nullable()();

  /// Phase 2.2 — per-line disposition: `restock` | `damaged` | `scrap`.
  /// Routes the inventory leg to 1200 (restock) or 5800 (damaged/scrap).
  TextColumn get dispositionType =>
      text().withDefault(const Constant('restock'))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
