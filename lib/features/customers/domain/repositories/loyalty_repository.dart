import '../../../../core/database/app_database.dart';

/// Domain model for customer loyalty summary
class CustomerLoyaltySummary {
  final int customerId;
  final int pointsBalance;
  final int totalPointsEarned;
  final int totalPointsRedeemed;
  final LoyaltyTier? currentTier;
  final LoyaltyTier? nextTier;
  final int pointsToNextTier;
  final List<TierBenefit> currentBenefits;

  const CustomerLoyaltySummary({
    required this.customerId,
    required this.pointsBalance,
    required this.totalPointsEarned,
    required this.totalPointsRedeemed,
    this.currentTier,
    this.nextTier,
    required this.pointsToNextTier,
    required this.currentBenefits,
  });
}

/// Represents a single tier benefit for UI display
class TierBenefit {
  final String key;
  final String labelKey;
  final String value;
  final bool isActive;

  const TierBenefit({
    required this.key,
    required this.labelKey,
    required this.value,
    required this.isActive,
  });
}

/// Summary of tier benefits for display
class TierBenefitsSummary {
  final String tierName;
  final String tierColor;
  final List<TierBenefit> benefits;

  const TierBenefitsSummary({
    required this.tierName,
    required this.tierColor,
    required this.benefits,
  });
}

/// Domain repository interface for loyalty operations
abstract class LoyaltyRepository {
  /// Watch all loyalty tiers
  Stream<List<LoyaltyTier>> watchAllTiers();

  /// Get all loyalty tiers
  Future<List<LoyaltyTier>> getAllTiers();

  /// Get tier by ID
  Future<LoyaltyTier?> getTier(int id);

  /// Get tier for a given points balance
  Future<LoyaltyTier?> getTierForPoints(int points);

  /// Get next tier after current points
  Future<LoyaltyTier?> getNextTier(int currentPoints);

  /// Watch customer loyalty summary
  Stream<CustomerLoyaltySummary?> watchCustomerLoyaltySummary(int customerId);

  /// Get customer loyalty summary
  Future<CustomerLoyaltySummary?> getCustomerLoyaltySummary(int customerId);

  /// Add points to customer
  Future<void> addPoints({
    required int customerId,
    required int points,
    required String source,
    int? referenceId,
    String? referenceType,
    String? description,
  });

  /// Redeem points from customer
  Future<void> redeemPoints({
    required int customerId,
    required int points,
    required String reason,
    int? referenceId,
    String? referenceType,
  });

  /// Watch loyalty point transactions for a customer
  Stream<List<LoyaltyPointTransaction>> watchPointTransactions(int customerId);

  /// Get loyalty settings
  Future<LoyaltySettings?> getLoyaltySettings();

  /// Watch loyalty settings
  Stream<LoyaltySettings?> watchLoyaltySettings();

  /// Update loyalty settings
  Future<void> updateLoyaltySettings(LoyaltySettings settings);

  /// Watch all rewards
  Stream<List<LoyaltyReward>> watchAllRewards({bool? isActive});

  /// Get available rewards for customer tier
  Future<List<LoyaltyReward>> getAvailableRewards(int customerId);

  /// Redeem a reward
  Future<void> redeemReward({
    required int customerId,
    required int rewardId,
  });

  /// Watch customer reward redemptions
  Stream<List<CustomerRewardRedemption>> watchCustomerRedemptions(int customerId);

  /// Get tier benefits summary for display
  TierBenefitsSummary getTierBenefitsSummary(LoyaltyTier tier);

  /// Calculate points to earn for a purchase amount
  int calculatePointsToEarn(int amountCents, double multiplier);
}
