import 'package:drift/drift.dart';
import '../converters/money_converter.dart';
import 'products.dart';
import 'settings.dart';
import 'users.dart';
import 'business.dart';

/// Audit + accounting trail for every manual inventory adjustment.
///
/// Every row corresponds to exactly ONE posted journal entry so the ledger
/// and the stock ledger can never drift (the fundamental invariant of
/// perpetual inventory accounting used by QuickBooks / Odoo / SAP B1).
///
/// Three semantic types:
///   - `shrinkage`   → loss / theft / damage / expired
///                     (Dr 5800 Inventory Shrinkage  / Cr 1200 Inventory)
///   - `gain`        → count surplus / found stock
///                     (Dr 1200 Inventory            / Cr 4200 Inventory Gain)
///   - `revaluation` → unit-cost change while on hand
///                     (Δ>0 → Dr 1200 / Cr 5900 ; Δ<0 → Dr 5900 / Cr 1200)
///
/// [costingMethod] is stored on every row so that when the app upgrades to
/// FIFO for a future product class, historical WAC-based adjustments stay
/// auditable and reproducible.
@DataClassName('InventoryAdjustment')
class InventoryAdjustments extends Table {
  /// Optional creation route; the immutable document location owns history.
  TextColumn get warehouseId => text().nullable().references(
    BusinessWarehouses,
    #id,
    onDelete: KeyAction.restrict,
  )();
  IntColumn get id => integer().autoIncrement()();

  TextColumn get adjustmentNumber => text().unique()();

  IntColumn get productId =>
      integer().references(Products, #id, onDelete: KeyAction.restrict)();
  IntColumn get variantId => integer().nullable().references(
    ProductVariants,
    #id,
    onDelete: KeyAction.restrict,
  )();

  /// 'shrinkage' | 'gain' | 'revaluation'
  TextColumn get adjustmentType => text()();

  /// Signed change in on-hand quantity (0 for pure revaluations).
  IntColumn get quantityDelta => integer()();

  /// Unit cost used to value this adjustment. For revaluations this is the
  /// NEW unit cost. For shrinkage/gain this is the cost at time of event.
  IntColumn get unitCostCents => integer().map(const MoneyConverter())();

  /// |quantityDelta| × unitCostCents for shrinkage/gain; for revaluation it
  /// equals (newCost − oldCost) × onHandQty (sign preserved).
  IntColumn get totalValueCents => integer().map(const MoneyConverter())();

  /// Previous unit cost — only meaningful for revaluations (nullable).
  IntColumn get previousUnitCostCents =>
      integer().nullable().map(const MoneyConverter())();

  /// Mandatory human-readable reason. Enforced non-empty by the service.
  TextColumn get reason => text()();

  TextColumn get notes => text().nullable()();

  IntColumn get currencyId =>
      integer().references(Currencies, #id, onDelete: KeyAction.restrict)();

  IntColumn get userId => integer().nullable().references(
    Users,
    #id,
    onDelete: KeyAction.setNull,
  )();

  /// FK to the posted journal entry. Never null after post; nullable only to
  /// survive a partial insert that gets rolled back.
  IntColumn get journalEntryId => integer().nullable()();

  /// Costing method active when this adjustment was recorded. Enables a
  /// future FIFO migration without losing historical WAC semantics.
  TextColumn get costingMethod =>
      text().withDefault(const Constant('weighted_average'))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

/// Immutable explanation of a FIFO revaluation. The old layer's historical
/// cost stays frozen; only its remaining stock moves into the new layer.
@DataClassName('InventoryRevaluationLayer')
class InventoryRevaluationLayers extends Table {
  IntColumn get adjustmentId => integer().references(
    InventoryAdjustments,
    #id,
    onDelete: KeyAction.restrict,
  )();
  @ReferenceName('revaluationsFromLayer')
  IntColumn get oldBatchId =>
      integer().references(ProductBatches, #id, onDelete: KeyAction.restrict)();
  @ReferenceName('revaluationsToLayer')
  IntColumn get newBatchId => integer().unique().references(
    ProductBatches,
    #id,
    onDelete: KeyAction.restrict,
  )();
  IntColumn get quantity => integer()();
  IntColumn get quantityScale => integer()();
  IntColumn get oldUnitCostCents => integer()();
  IntColumn get newUnitCostCents => integer()();
  IntColumn get previousValueCents => integer()();
  IntColumn get newValueCents => integer()();
  @override
  Set<Column> get primaryKey => {adjustmentId, oldBatchId};
}
