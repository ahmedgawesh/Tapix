import 'package:drift/drift.dart';

import '../converters/money_converter.dart';
import 'products.dart';
import 'settings.dart';
import 'transactions.dart';
import 'users.dart';

/// Header for a versioned promotion definition.
///
/// Promotion rows are never rewritten after they have been used by a sale.
/// A material edit creates a new [version], preserving reproducible pricing
/// and a complete audit trail for returns.
@DataClassName('Promotion')
class Promotions extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get code => text().unique()();
  IntColumn get version => integer().withDefault(const Constant(1))();
  TextColumn get name => text()();
  TextColumn get nameAr => text().nullable()();
  TextColumn get nameFr => text().nullable()();
  TextColumn get description => text().nullable()();

  /// `simple` | `quantity` | `fixed_bundle` | `buy_x_get_y` | `threshold`.
  TextColumn get promotionType => text()();

  /// `draft` | `active` | `paused` | `archived`.
  TextColumn get status => text().withDefault(const Constant('draft'))();

  /// `automatic` | `manual` | `coupon`.
  TextColumn get applicationMode =>
      text().withDefault(const Constant('automatic'))();

  /// `exclusive` | `best_price` | `compound`.
  TextColumn get concurrencyMode =>
      text().withDefault(const Constant('best_price'))();
  IntColumn get priority => integer().withDefault(const Constant(0))();

  /// NULL means the promotion is valid in the sale currency selected later.
  IntColumn get currencyId => integer().nullable().references(
    Currencies,
    #id,
    onDelete: KeyAction.restrict,
  )();

  /// `retail` | `wholesale` | `any`.
  TextColumn get priceMode => text().withDefault(const Constant('retail'))();
  TextColumn get couponCode => text().nullable().unique()();
  DateTimeColumn get startsAt => dateTime().nullable()();
  DateTimeColumn get endsAt => dateTime().nullable()();
  IntColumn get maxApplicationsPerTransaction => integer().nullable()();
  IntColumn get maxApplicationsPerCustomer => integer().nullable()();
  BoolColumn get allowManualDiscountCombination =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get allowBelowCost =>
      boolean().withDefault(const Constant(false))();
  @ReferenceName('promotionsCreatedBy')
  IntColumn get createdBy => integer().nullable().references(
    Users,
    #id,
    onDelete: KeyAction.setNull,
  )();
  @ReferenceName('promotionsUpdatedBy')
  IntColumn get updatedBy => integer().nullable().references(
    Users,
    #id,
    onDelete: KeyAction.setNull,
  )();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

/// Conditions that qualify a cart for a promotion.
///
/// Multiple rows in the same [conditionGroup] are OR-ed; different groups
/// are AND-ed. Phase one persists the general model while the pure engine
/// exposes the first supported templates through typed definitions.
@DataClassName('PromotionCondition')
class PromotionConditions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get promotionId =>
      integer().references(Promotions, #id, onDelete: KeyAction.cascade)();

  /// `minimum_quantity` | `minimum_spend` | `payment_method` | `coupon`.
  TextColumn get conditionType => text()();
  TextColumn get conditionGroup =>
      text().withDefault(const Constant('default'))();
  IntColumn get minimumQuantity => integer().nullable()();
  IntColumn get quantityScale => integer().withDefault(const Constant(1))();
  TextColumn get measurementType => text().nullable()();
  IntColumn get minimumSpendCents =>
      integer().nullable().map(const MoneyConverter())();
  TextColumn get paymentMethod => text().nullable()();
  TextColumn get couponCode => text().nullable()();
  TextColumn get metadataJson => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// Product, variant, or category membership for qualifiers and rewards.
@DataClassName('PromotionScope')
class PromotionScopes extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get promotionId =>
      integer().references(Promotions, #id, onDelete: KeyAction.cascade)();

  /// `qualifier` | `reward` | `eligible`.
  TextColumn get scopeRole => text()();

  /// `all` | `product` | `variant` | `category`.
  TextColumn get targetType => text()();
  IntColumn get productId => integer().nullable().references(
    Products,
    #id,
    onDelete: KeyAction.restrict,
  )();
  IntColumn get variantId => integer().nullable().references(
    ProductVariants,
    #id,
    onDelete: KeyAction.restrict,
  )();
  IntColumn get categoryId => integer().nullable().references(
    ProductCategories,
    #id,
    onDelete: KeyAction.restrict,
  )();
  BoolColumn get isExcluded => boolean().withDefault(const Constant(false))();
  TextColumn get lineGroup => text().withDefault(const Constant('A'))();
  IntColumn get requiredQuantity => integer().nullable()();
  IntColumn get quantityScale => integer().withDefault(const Constant(1))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// Reward granted after all promotion conditions are satisfied.
@DataClassName('PromotionReward')
class PromotionRewards extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get promotionId =>
      integer().references(Promotions, #id, onDelete: KeyAction.cascade)();

  /// `percentage_off` | `amount_off` | `fixed_bundle_price` |
  /// `free_quantity`.
  TextColumn get rewardType => text()();

  /// `qualifying_lines` | `reward_lines` | `entire_cart` |
  /// `cheapest_reward_lines`.
  TextColumn get applyTo =>
      text().withDefault(const Constant('qualifying_lines'))();
  IntColumn get percentBps => integer().nullable()();
  IntColumn get amountCents =>
      integer().nullable().map(const MoneyConverter())();
  IntColumn get fixedPriceCents =>
      integer().nullable().map(const MoneyConverter())();
  IntColumn get rewardQuantity => integer().nullable()();
  IntColumn get quantityScale => integer().withDefault(const Constant(1))();
  IntColumn get maxDiscountCents =>
      integer().nullable().map(const MoneyConverter())();
  IntColumn get productId => integer().nullable().references(
    Products,
    #id,
    onDelete: KeyAction.restrict,
  )();
  IntColumn get variantId => integer().nullable().references(
    ProductVariants,
    #id,
    onDelete: KeyAction.restrict,
  )();
  IntColumn get categoryId => integer().nullable().references(
    ProductCategories,
    #id,
    onDelete: KeyAction.restrict,
  )();
  BoolColumn get cheapestFirst => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// Optional recurring local-time windows for a promotion.
@DataClassName('PromotionSchedule')
class PromotionSchedules extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get promotionId =>
      integer().references(Promotions, #id, onDelete: KeyAction.cascade)();

  /// ISO weekday 1 (Monday) through 7 (Sunday); NULL means every day.
  IntColumn get weekday => integer().nullable()();
  IntColumn get startMinute => integer().withDefault(const Constant(0))();
  IntColumn get endMinute => integer().withDefault(const Constant(1439))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// Immutable promotion snapshot attached to a posted sale.
@DataClassName('SalePromotionApplication')
class SalePromotionApplications extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get saleId =>
      integer().references(Sales, #id, onDelete: KeyAction.cascade)();
  IntColumn get promotionId =>
      integer().references(Promotions, #id, onDelete: KeyAction.restrict)();
  TextColumn get promotionCode => text()();
  TextColumn get promotionName => text()();
  IntColumn get promotionVersion => integer()();
  TextColumn get promotionType => text()();
  TextColumn get concurrencyMode => text()();
  IntColumn get applicationCount => integer().withDefault(const Constant(1))();
  IntColumn get discountCents => integer().map(const MoneyConverter())();
  TextColumn get promotionEngineVersion => text()();
  TextColumn get calculationSnapshotJson => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// Exact cent and quantity allocation of an applied promotion to sale lines.
/// Returns consume this frozen allocation rather than re-evaluating a campaign
/// that may have since expired or changed.
@DataClassName('SaleItemPromotionAllocation')
class SaleItemPromotionAllocations extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get applicationId => integer().references(
    SalePromotionApplications,
    #id,
    onDelete: KeyAction.cascade,
  )();
  IntColumn get saleItemId =>
      integer().references(SaleItems, #id, onDelete: KeyAction.cascade)();
  IntColumn get discountCents => integer().map(const MoneyConverter())();
  IntColumn get appliedQuantity => integer()();
  IntColumn get quantityScale => integer().withDefault(const Constant(1))();
  IntColumn get originalUnitPriceCents =>
      integer().map(const MoneyConverter())();
  TextColumn get rewardType => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
