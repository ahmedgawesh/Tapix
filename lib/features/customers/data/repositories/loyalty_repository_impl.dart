import 'dart:async';
import 'package:drift/drift.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/services/journal_entry_service.dart';
import '../../../../core/services/loyalty/loyalty_points_service.dart';
import '../../domain/repositories/loyalty_repository.dart';

/// Implementation of LoyaltyRepository
class LoyaltyRepositoryImpl implements LoyaltyRepository {
  final AppDatabase _database;
  final JournalEntryService? _journalService;

  LoyaltyRepositoryImpl(this._database, [this._journalService]);

  @override
  Stream<List<LoyaltyTier>> watchAllTiers() {
    return (_database.select(_database.loyaltyTiers)
          ..orderBy([(t) => OrderingTerm(expression: t.minPoints)]))
        .watch();
  }

  @override
  Future<List<LoyaltyTier>> getAllTiers() {
    return (_database.select(_database.loyaltyTiers)
          ..orderBy([(t) => OrderingTerm(expression: t.minPoints)]))
        .get();
  }

  @override
  Future<LoyaltyTier?> getTier(int id) {
    return (_database.select(_database.loyaltyTiers)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  @override
  Future<LoyaltyTier?> getTierForPoints(int points) async {
    final tiers = await getAllTiers();
    LoyaltyTier? matchingTier;
    for (final tier in tiers) {
      if (points >= tier.minPoints) {
        if (tier.maxPoints == null || points <= tier.maxPoints!) {
          matchingTier = tier;
        }
      }
    }
    return matchingTier;
  }

  @override
  Future<LoyaltyTier?> getNextTier(int currentPoints) async {
    final tiers = await getAllTiers();
    for (final tier in tiers) {
      if (tier.minPoints > currentPoints) {
        return tier;
      }
    }
    return null;
  }

  @override
  Stream<CustomerLoyaltySummary?> watchCustomerLoyaltySummary(int customerId) {
    // Use customer stream as the primary trigger and fetch other data
    return _database.customerDao.watchCustomer(customerId).asyncMap((customer) async {
      if (customer == null) return null;

      final tiers = await getAllTiers();
      final settings = await getLoyaltySettings();
      final transactions = await (_database.select(_database.loyaltyPointTransactions)
            ..where((t) => t.customerId.equals(customerId)))
          .get();

      final pointsBalance = customer.loyaltyPointsBalance;
      
      // Calculate totals from transactions
      int totalEarned = 0;
      int totalRedeemed = 0;
      for (final tx in transactions) {
        if (tx.transactionType == 'earn') {
          totalEarned += tx.points;
        } else if (tx.transactionType == 'redeem') {
          totalRedeemed += tx.points.abs();
        }
      }

      // Find current and next tier
      LoyaltyTier? currentTier;
      LoyaltyTier? nextTier;
      
      for (int i = 0; i < tiers.length; i++) {
        final tier = tiers[i];
        if (pointsBalance >= tier.minPoints) {
          if (tier.maxPoints == null || pointsBalance <= tier.maxPoints!) {
            currentTier = tier;
            if (i + 1 < tiers.length) {
              nextTier = tiers[i + 1];
            }
          }
        }
      }

      // Calculate points to next tier
      int pointsToNextTier = 0;
      if (nextTier != null) {
        pointsToNextTier = nextTier.minPoints - pointsBalance;
      }

      // Get current benefits
      final currentBenefits = currentTier != null 
          ? _extractBenefits(currentTier) 
          : <TierBenefit>[];

      return CustomerLoyaltySummary(
        customerId: customerId,
        pointsBalance: pointsBalance,
        totalPointsEarned: totalEarned,
        totalPointsRedeemed: totalRedeemed,
        currentTier: currentTier,
        nextTier: nextTier,
        pointsToNextTier: pointsToNextTier,
        currentBenefits: currentBenefits,
        pointValueCents: settings?.pointValueCents ?? 0,
      );
    });
  }

  Stream<List<LoyaltyPointTransaction>> _watchPointTransactionsInternal(int customerId) {
    return (_database.select(_database.loyaltyPointTransactions)
          ..where((t) => t.customerId.equals(customerId))
          ..orderBy([(t) => OrderingTerm(expression: t.transactionDate, mode: OrderingMode.desc)]))
        .watch();
  }

  @override
  Future<CustomerLoyaltySummary?> getCustomerLoyaltySummary(int customerId) async {
    final customer = await _database.customerDao.getCustomer(customerId);
    if (customer == null) return null;

    final tiers = await getAllTiers();
    final settings = await getLoyaltySettings();
    final transactions = await (_database.select(_database.loyaltyPointTransactions)
          ..where((t) => t.customerId.equals(customerId)))
        .get();

    final pointsBalance = customer.loyaltyPointsBalance;
    
    int totalEarned = 0;
    int totalRedeemed = 0;
    for (final tx in transactions) {
      if (tx.transactionType == 'earn') {
        totalEarned += tx.points;
      } else if (tx.transactionType == 'redeem') {
        totalRedeemed += tx.points.abs();
      }
    }

    LoyaltyTier? currentTier;
    LoyaltyTier? nextTier;
    
    for (int i = 0; i < tiers.length; i++) {
      final tier = tiers[i];
      if (pointsBalance >= tier.minPoints) {
        if (tier.maxPoints == null || pointsBalance <= tier.maxPoints!) {
          currentTier = tier;
          if (i + 1 < tiers.length) {
            nextTier = tiers[i + 1];
          }
        }
      }
    }

    int pointsToNextTier = 0;
    if (nextTier != null) {
      pointsToNextTier = nextTier.minPoints - pointsBalance;
    }

    final currentBenefits = currentTier != null 
        ? _extractBenefits(currentTier) 
        : <TierBenefit>[];

    return CustomerLoyaltySummary(
      customerId: customerId,
      pointsBalance: pointsBalance,
      totalPointsEarned: totalEarned,
      totalPointsRedeemed: totalRedeemed,
      currentTier: currentTier,
      nextTier: nextTier,
      pointsToNextTier: pointsToNextTier,
      currentBenefits: currentBenefits,
      pointValueCents: settings?.pointValueCents ?? 0,
    );
  }

  List<TierBenefit> _extractBenefits(LoyaltyTier tier) {
    final benefits = <TierBenefit>[];

    if (tier.pointsMultiplier > 1.0) {
      benefits.add(TierBenefit(
        key: 'points_multiplier',
        labelKey: 'customers.benefit_points_multiplier',
        value: '${tier.pointsMultiplier}x',
        isActive: true,
      ));
    }

    if (tier.discountPercent > 0) {
      benefits.add(TierBenefit(
        key: 'discount',
        labelKey: 'customers.benefit_discount',
        value: '${tier.discountPercent.toStringAsFixed(0)}%',
        isActive: true,
      ));
    }

    if (tier.freeShipping) {
      benefits.add(const TierBenefit(
        key: 'free_shipping',
        labelKey: 'customers.benefit_free_shipping',
        value: '✓',
        isActive: true,
      ));
    }

    if (tier.prioritySupport) {
      benefits.add(const TierBenefit(
        key: 'priority_support',
        labelKey: 'customers.benefit_priority_support',
        value: '✓',
        isActive: true,
      ));
    }

    if (tier.earlyAccessDays > 0) {
      benefits.add(TierBenefit(
        key: 'early_access',
        labelKey: 'customers.benefit_early_access',
        value: '${tier.earlyAccessDays}d',
        isActive: true,
      ));
    }

    if (tier.exclusiveOffers) {
      benefits.add(const TierBenefit(
        key: 'exclusive_offers',
        labelKey: 'customers.benefit_exclusive_offers',
        value: '✓',
        isActive: true,
      ));
    }

    if (tier.birthdayBonus) {
      benefits.add(TierBenefit(
        key: 'birthday_bonus',
        labelKey: 'customers.benefit_birthday_bonus',
        value: tier.birthdayBonusPoints > 0 
            ? '+${tier.birthdayBonusPoints}pts' 
            : '${tier.birthdayDiscountPercent.toStringAsFixed(0)}%',
        isActive: true,
      ));
    }

    return benefits;
  }

  @override
  Future<void> addPoints({
    required int customerId,
    required int points,
    required String source,
    int? referenceId,
    String? referenceType,
    String? description,
  }) async {
    final customer = await _database.customerDao.getCustomer(customerId);
    if (customer == null) return;

    final newBalance = customer.loyaltyPointsBalance + points;

    await _database.into(_database.loyaltyPointTransactions).insert(
      LoyaltyPointTransactionsCompanion(
        customerId: Value(customerId),
        transactionType: const Value('earn'),
        points: Value(points),
        balanceAfter: Value(newBalance),
        source: Value(source),
        referenceId: Value(referenceId),
        referenceType: Value(referenceType),
        description: Value(description),
        transactionDate: Value(DateTime.now()),
        createdAt: Value(DateTime.now()),
      ),
    );

    await (_database.update(_database.customers)
          ..where((c) => c.id.equals(customerId)))
        .write(CustomersCompanion(
          loyaltyPointsBalance: Value(newBalance),
          updatedAt: Value(DateTime.now()),
        ));
  }

  @override
  Future<void> redeemPoints({
    required int customerId,
    required int points,
    required String reason,
    int? referenceId,
    String? referenceType,
  }) async {
    final customer = await _database.customerDao.getCustomer(customerId);
    if (customer == null) return;

    final newBalance = customer.loyaltyPointsBalance - points;
    if (newBalance < 0) {
      throw Exception('Insufficient points balance');
    }

    await _database.into(_database.loyaltyPointTransactions).insert(
      LoyaltyPointTransactionsCompanion(
        customerId: Value(customerId),
        transactionType: const Value('redeem'),
        points: Value(-points),
        balanceAfter: Value(newBalance),
        source: const Value('redemption'),
        referenceId: Value(referenceId),
        referenceType: Value(referenceType),
        description: Value(reason),
        transactionDate: Value(DateTime.now()),
        createdAt: Value(DateTime.now()),
      ),
    );

    await (_database.update(_database.customers)
          ..where((c) => c.id.equals(customerId)))
        .write(CustomersCompanion(
          loyaltyPointsBalance: Value(newBalance),
          updatedAt: Value(DateTime.now()),
        ));
  }

  @override
  Stream<List<LoyaltyPointTransaction>> watchPointTransactions(int customerId) {
    return _watchPointTransactionsInternal(customerId);
  }

  @override
  Future<LoyaltySettings?> getLoyaltySettings() {
    return _database.select(_database.loyaltySettingsTable).getSingleOrNull();
  }

  @override
  Stream<LoyaltySettings?> watchLoyaltySettings() {
    return _database.select(_database.loyaltySettingsTable).watchSingleOrNull();
  }

  @override
  Future<void> updateLoyaltySettings(LoyaltySettings settings) async {
    await _database.update(_database.loyaltySettingsTable).replace(settings);
  }

  @override
  Stream<List<LoyaltyReward>> watchAllRewards({bool? isActive}) {
    final query = _database.select(_database.loyaltyRewards);
    if (isActive != null) {
      query.where((r) => r.isActive.equals(isActive));
    }
    return query.watch();
  }

  @override
  Future<List<LoyaltyReward>> getAvailableRewards(int customerId) async {
    final customer = await _database.customerDao.getCustomer(customerId);
    if (customer == null) return [];

    final rewards = await (_database.select(_database.loyaltyRewards)
          ..where((r) => r.isActive.equals(true)))
        .get();

    return rewards.where((reward) {
      // Check if customer has enough points
      if (customer.loyaltyPointsBalance < reward.pointsCost) {
        return false;
      }
      // Check tier requirement
      if (reward.minTierId != null && customer.loyaltyTierId != null) {
        // Simple check - could be enhanced with tier ordering
        if (customer.loyaltyTierId! < reward.minTierId!) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  @override
  Future<void> redeemReward({
    required int customerId,
    required int rewardId,
  }) async {
    final reward = await (_database.select(_database.loyaltyRewards)
          ..where((r) => r.id.equals(rewardId)))
        .getSingleOrNull();
    
    if (reward == null) {
      throw Exception('Reward not found');
    }

    // Redeem points
    await redeemPoints(
      customerId: customerId,
      points: reward.pointsCost,
      reason: 'Reward: ${reward.name}',
      referenceId: rewardId,
      referenceType: 'reward',
    );

    // Record redemption
    final redemptionId = await _database.into(_database.customerRewardRedemptions).insert(
      CustomerRewardRedemptionsCompanion(
        customerId: Value(customerId),
        rewardId: Value(rewardId),
        pointsSpent: Value(reward.pointsCost),
        status: const Value('pending'),
        redeemedAt: Value(DateTime.now()),
        createdAt: Value(DateTime.now()),
      ),
    );

    // Update reward total redemptions
    await (_database.update(_database.loyaltyRewards)
          ..where((r) => r.id.equals(rewardId)))
        .write(LoyaltyRewardsCompanion(
          totalRedemptions: Value(reward.totalRedemptions + 1),
          updatedAt: Value(DateTime.now()),
        ));

    // Post journal entry for monetary reward redemptions:
    // Dr Loyalty Points Liability (2300), Cr Discounts Given (5500)
    if (_journalService != null && reward.valueCents != null && reward.valueCents! > 0) {
      // Use currency from the first available source (default to 1)
      final customer = await _database.customerDao.getCustomer(customerId);
      final currencyId = customer?.currencyId ?? 1;
      await _journalService.recordLoyaltyRedemptionJournalEntry(
        redemptionId: redemptionId,
        valueCents: reward.valueCents!,
        currencyId: currencyId,
      );
    }
  }

  @override
  Stream<List<CustomerRewardRedemption>> watchCustomerRedemptions(int customerId) {
    return (_database.select(_database.customerRewardRedemptions)
          ..where((r) => r.customerId.equals(customerId))
          ..orderBy([(r) => OrderingTerm(expression: r.redeemedAt, mode: OrderingMode.desc)]))
        .watch();
  }

  @override
  TierBenefitsSummary getTierBenefitsSummary(LoyaltyTier tier) {
    return TierBenefitsSummary(
      tierName: tier.name,
      tierColor: tier.color,
      benefits: _extractBenefits(tier),
    );
  }

  @override
  int calculatePointsToEarn(int amountCents, double multiplier) {
    // Phase 6 — preview path delegates to LoyaltyPointsService so it
    // can never drift from the live award path. Default fallback of
    // `pointsPerCurrencyUnit = 1` preserves the legacy preview
    // contract for callers that don't have settings handy.
    return LoyaltyPointsService.previewSync(
      amountCents: amountCents,
      multiplier: multiplier,
    );
  }

  @override
  Future<int> calculatePointsToEarnWithSettings(
    int amountCents,
    double multiplier,
  ) async {
    final settings = await getLoyaltySettings();
    if (settings == null || !settings.isEnabled) return 0;
    // Phase 6 — funnel through LoyaltyPointsService.compute so the
    // settings-aware preview matches the award path byte-for-byte.
    return LoyaltyPointsService.previewSync(
      amountCents: amountCents,
      multiplier: multiplier,
      pointsPerCurrencyUnit: settings.pointsPerCurrencyUnit,
      minSpendForPoints: settings.minSpendForPoints,
    );
  }

  @override
  Future<int> createTier(LoyaltyTier tier) async {
    return _database.into(_database.loyaltyTiers).insert(
      LoyaltyTiersCompanion.insert(
        name: tier.name,
        nameAr: Value(tier.nameAr),
        nameFr: Value(tier.nameFr),
        minPoints: Value(tier.minPoints),
        maxPoints: Value(tier.maxPoints),
        pointsMultiplier: Value(tier.pointsMultiplier),
        discountPercent: Value(tier.discountPercent),
        freeShipping: Value(tier.freeShipping),
        freeShippingMinOrderCents: Value(tier.freeShippingMinOrderCents),
        prioritySupport: Value(tier.prioritySupport),
        earlyAccessDays: Value(tier.earlyAccessDays),
        exclusiveOffers: Value(tier.exclusiveOffers),
        birthdayBonus: Value(tier.birthdayBonus),
        birthdayBonusPoints: Value(tier.birthdayBonusPoints),
        birthdayDiscountPercent: Value(tier.birthdayDiscountPercent),
        color: Value(tier.color),
        icon: Value(tier.icon),
        badgeText: Value(tier.badgeText),
        sortOrder: Value(tier.sortOrder),
        isActive: Value(tier.isActive),
      ),
    );
  }

  @override
  Future<void> updateTier(LoyaltyTier tier) async {
    await (_database.update(_database.loyaltyTiers)
          ..where((t) => t.id.equals(tier.id)))
        .write(LoyaltyTiersCompanion(
          name: Value(tier.name),
          nameAr: Value(tier.nameAr),
          nameFr: Value(tier.nameFr),
          minPoints: Value(tier.minPoints),
          maxPoints: Value(tier.maxPoints),
          pointsMultiplier: Value(tier.pointsMultiplier),
          discountPercent: Value(tier.discountPercent),
          freeShipping: Value(tier.freeShipping),
          freeShippingMinOrderCents: Value(tier.freeShippingMinOrderCents),
          prioritySupport: Value(tier.prioritySupport),
          earlyAccessDays: Value(tier.earlyAccessDays),
          exclusiveOffers: Value(tier.exclusiveOffers),
          birthdayBonus: Value(tier.birthdayBonus),
          birthdayBonusPoints: Value(tier.birthdayBonusPoints),
          birthdayDiscountPercent: Value(tier.birthdayDiscountPercent),
          color: Value(tier.color),
          icon: Value(tier.icon),
          badgeText: Value(tier.badgeText),
          sortOrder: Value(tier.sortOrder),
          isActive: Value(tier.isActive),
          updatedAt: Value(DateTime.now()),
        ));
    
    // Reassign all customers to correct tiers based on their points
    await _reassignAllCustomerTiers();
  }
  
  /// Reassigns all customers to their correct tier based on their loyalty points balance
  Future<void> _reassignAllCustomerTiers() async {
    // Get all active tiers sorted by minPoints descending (highest tier first)
    final tiers = await (_database.select(_database.loyaltyTiers)
          ..where((t) => t.isActive.equals(true))
          ..orderBy([(t) => OrderingTerm.desc(t.minPoints)]))
        .get();
    
    if (tiers.isEmpty) return;
    
    // Get all customers with loyalty enabled
    final customers = await (_database.select(_database.customers)
          ..where((c) => c.loyaltyEnabled.equals(true)))
        .get();
    
    for (final customer in customers) {
      final points = customer.loyaltyPointsBalance;
      
      // Find the correct tier for this customer's points
      LoyaltyTier? correctTier;
      for (final tier in tiers) {
        final maxPoints = tier.maxPoints;
        if (points >= tier.minPoints && (maxPoints == null || points <= maxPoints)) {
          correctTier = tier;
          break;
        }
      }
      
      // Update customer's tier if it's different
      final newTierId = correctTier?.id;
      if (customer.loyaltyTierId != newTierId) {
        await (_database.update(_database.customers)
              ..where((c) => c.id.equals(customer.id)))
            .write(CustomersCompanion(
              loyaltyTierId: Value(newTierId),
              updatedAt: Value(DateTime.now()),
            ));
      }
    }
  }

  @override
  Future<void> deleteTier(int tierId) async {
    // Delete the tier first
    await (_database.delete(_database.loyaltyTiers)
          ..where((t) => t.id.equals(tierId)))
        .go();
    
    // Reassign all customers to correct tiers based on their points
    await _reassignAllCustomerTiers();
  }

  @override
  Future<void> assignTierToCustomer(int customerId, int? tierId) async {
    await (_database.update(_database.customers)
          ..where((c) => c.id.equals(customerId)))
        .write(CustomersCompanion(
          loyaltyTierId: Value(tierId),
          updatedAt: Value(DateTime.now()),
        ));
  }

  @override
  Future<List<LoyaltyPointTransaction>> getPointsTransactions(int customerId) async {
    return (_database.select(_database.loyaltyPointTransactions)
          ..where((t) => t.customerId.equals(customerId))
          ..orderBy([(t) => OrderingTerm.desc(t.transactionDate)]))
        .get();
  }
}
