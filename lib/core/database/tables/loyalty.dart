import 'package:drift/drift.dart';

@DataClassName('LoyaltyTier')
class LoyaltyTiers extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get nameAr => text().nullable()();
  TextColumn get nameFr => text().nullable()();
  IntColumn get minPoints => integer().withDefault(const Constant(0))();
  IntColumn get maxPoints => integer().nullable()();
  RealColumn get pointsMultiplier => real().withDefault(const Constant(1.0))();
  RealColumn get discountPercent => real().withDefault(const Constant(0.0))();
  BoolColumn get freeShipping => boolean().withDefault(const Constant(false))();
  IntColumn get freeShippingMinOrderCents => integer().nullable()();
  BoolColumn get prioritySupport =>
      boolean().withDefault(const Constant(false))();
  IntColumn get earlyAccessDays => integer().withDefault(const Constant(0))();
  BoolColumn get exclusiveOffers =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get birthdayBonus =>
      boolean().withDefault(const Constant(false))();
  IntColumn get birthdayBonusPoints =>
      integer().withDefault(const Constant(0))();
  RealColumn get birthdayDiscountPercent =>
      real().withDefault(const Constant(0.0))();
  TextColumn get color => text().withDefault(const Constant('#CD7F32'))();
  TextColumn get icon => text().nullable()();
  TextColumn get badgeText => text().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('LoyaltyPointTransaction')
class LoyaltyPointTransactions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get customerId => integer()();
  TextColumn get transactionType => text()();
  IntColumn get points => integer()();
  IntColumn get balanceAfter => integer()();
  TextColumn get source => text().nullable()();
  IntColumn get referenceId => integer().nullable()();
  TextColumn get referenceType => text().nullable()();
  TextColumn get description => text().nullable()();
  DateTimeColumn get expiresAt => dateTime().nullable()();
  DateTimeColumn get transactionDate =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('LoyaltyReward')
class LoyaltyRewards extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get nameAr => text().nullable()();
  TextColumn get nameFr => text().nullable()();
  TextColumn get description => text().nullable()();
  TextColumn get descriptionAr => text().nullable()();
  TextColumn get descriptionFr => text().nullable()();
  TextColumn get rewardType => text()();
  IntColumn get pointsCost => integer()();
  IntColumn get valueCents => integer().nullable()();
  RealColumn get valuePercent => real().nullable()();
  IntColumn get productId => integer().nullable()();
  IntColumn get minTierId => integer().nullable()();
  IntColumn get maxRedemptionsPerCustomer => integer().nullable()();
  IntColumn get totalRedemptions => integer().withDefault(const Constant(0))();
  IntColumn get maxTotalRedemptions => integer().nullable()();
  DateTimeColumn get validFrom => dateTime().nullable()();
  DateTimeColumn get validUntil => dateTime().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('CustomerRewardRedemption')
class CustomerRewardRedemptions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get customerId => integer()();
  IntColumn get rewardId => integer()();
  IntColumn get pointsSpent => integer()();
  TextColumn get status => text().withDefault(const Constant('pending'))();
  IntColumn get saleId => integer().nullable()();
  DateTimeColumn get usedAt => dateTime().nullable()();
  DateTimeColumn get expiresAt => dateTime().nullable()();
  DateTimeColumn get redeemedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('LoyaltySettings')
class LoyaltySettingsTable extends Table {
  @override
  String get tableName => 'loyalty_settings';

  IntColumn get id => integer().autoIncrement()();
  IntColumn get pointsPerCurrencyUnit =>
      integer().withDefault(const Constant(1))();
  IntColumn get minSpendForPoints => integer().withDefault(const Constant(0))();
  IntColumn get pointsExpiryDays => integer().nullable()();
  IntColumn get referralBonusPoints =>
      integer().withDefault(const Constant(100))();
  IntColumn get signupBonusPoints =>
      integer().withDefault(const Constant(50))();
  IntColumn get reviewBonusPoints =>
      integer().withDefault(const Constant(10))();
  BoolColumn get isEnabled => boolean().withDefault(const Constant(true))();

  /// How much 1 point is worth in cents (e.g., 1 = 1 cent, 10 = 10 cents)
  IntColumn get pointValueCents => integer().withDefault(const Constant(1))();

  /// Minimum points required before a customer can redeem at checkout
  IntColumn get minRedemptionPoints =>
      integer().withDefault(const Constant(100))();

  /// Maximum percentage of invoice total that can be paid with points (basis points: 5000 = 50%)
  IntColumn get maxRedemptionPercentBps =>
      integer().withDefault(const Constant(5000))();

  /// Whether points redemption at checkout is enabled
  BoolColumn get allowPointsRedemption =>
      boolean().withDefault(const Constant(true))();

  /// Business birthday date (month and day) for birthday bonus calculation
  /// This is the business/company anniversary, not individual customer birthdays
  DateTimeColumn get businessBirthdayDate => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
