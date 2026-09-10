import '../money/money.dart';

/// Version stamped on every persisted promotion calculation snapshot.
/// Bump only when qualification, allocation, or conflict semantics change.
abstract final class PromotionEngineVersion {
  static const String current = 'promotion-v4';
}

enum PromotionType { simple, quantity, fixedBundle, buyXGetY, threshold }

enum PromotionConcurrencyMode { exclusive, bestPrice, compound }

enum PromotionRewardType {
  percentageOff,
  amountOff,
  fixedBundlePrice,
  freeQuantity,
}

enum PromotionScopeType { all, product, variant, category }

/// Product membership rule. Exclusions always win over inclusions.
class PromotionScope {
  final PromotionScopeType type;
  final int? targetId;
  final bool excluded;
  final int? requiredQuantity;
  final int quantityScale;

  const PromotionScope._(
    this.type,
    this.targetId,
    this.excluded,
    this.requiredQuantity,
    this.quantityScale,
  );

  const PromotionScope.all({bool excluded = false})
    : this._(PromotionScopeType.all, null, excluded, null, 1);

  const PromotionScope.product(
    int id, {
    bool excluded = false,
    int? requiredQuantity,
    int quantityScale = 1,
  }) : this._(
         PromotionScopeType.product,
         id,
         excluded,
         requiredQuantity,
         quantityScale,
       );

  const PromotionScope.variant(
    int id, {
    bool excluded = false,
    int? requiredQuantity,
    int quantityScale = 1,
  }) : this._(
         PromotionScopeType.variant,
         id,
         excluded,
         requiredQuantity,
         quantityScale,
       );

  const PromotionScope.category(
    int id, {
    bool excluded = false,
    int? requiredQuantity,
    int quantityScale = 1,
  }) : this._(
         PromotionScopeType.category,
         id,
         excluded,
         requiredQuantity,
         quantityScale,
       );

  bool get isRequiredComponent =>
      !excluded && requiredQuantity != null && requiredQuantity! > 0;

  bool matches(PromotionCartLine line) => switch (type) {
    PromotionScopeType.all => true,
    PromotionScopeType.product => line.productId == targetId,
    PromotionScopeType.variant => line.variantId == targetId,
    PromotionScopeType.category => line.categoryId == targetId,
  };

  Map<String, Object?> toTransportMap() => {
    'type': type.name,
    'targetId': targetId,
    'excluded': excluded,
    'requiredQuantity': requiredQuantity,
    'quantityScale': quantityScale,
  };

  factory PromotionScope.fromTransportMap(Map<String, dynamic> map) {
    final excluded = map['excluded'] == true;
    final targetId = (map['targetId'] as num?)?.toInt();
    final requiredQuantity = (map['requiredQuantity'] as num?)?.toInt();
    final quantityScale = (map['quantityScale'] as num?)?.toInt() ?? 1;
    return switch (map['type']?.toString()) {
      'product' => PromotionScope.product(
        targetId!,
        excluded: excluded,
        requiredQuantity: requiredQuantity,
        quantityScale: quantityScale,
      ),
      'variant' => PromotionScope.variant(
        targetId!,
        excluded: excluded,
        requiredQuantity: requiredQuantity,
        quantityScale: quantityScale,
      ),
      'category' => PromotionScope.category(
        targetId!,
        excluded: excluded,
        requiredQuantity: requiredQuantity,
        quantityScale: quantityScale,
      ),
      _ => PromotionScope.all(excluded: excluded),
    };
  }
}

/// Recurring window in store-local time. An end before start represents an
/// overnight window (for example 22:00 through 02:00).
class PromotionScheduleWindow {
  final int? isoWeekday;
  final int startMinute;
  final int endMinute;

  const PromotionScheduleWindow({
    this.isoWeekday,
    this.startMinute = 0,
    this.endMinute = 1439,
  });

  bool matches(DateTime localTime) {
    if (isoWeekday != null && isoWeekday != localTime.weekday) return false;
    final minute = localTime.hour * 60 + localTime.minute;
    if (startMinute <= endMinute) {
      return minute >= startMinute && minute <= endMinute;
    }
    return minute >= startMinute || minute <= endMinute;
  }

  List<String> validate() {
    final errors = <String>[];
    if (isoWeekday != null && (isoWeekday! < 1 || isoWeekday! > 7)) {
      errors.add('isoWeekday must be between 1 and 7');
    }
    if (startMinute < 0 || startMinute > 1439) {
      errors.add('startMinute must be between 0 and 1439');
    }
    if (endMinute < 0 || endMinute > 1439) {
      errors.add('endMinute must be between 0 and 1439');
    }
    return errors;
  }

  Map<String, Object?> toTransportMap() => {
    'isoWeekday': isoWeekday,
    'startMinute': startMinute,
    'endMinute': endMinute,
  };

  factory PromotionScheduleWindow.fromTransportMap(Map<String, dynamic> map) {
    return PromotionScheduleWindow(
      isoWeekday: (map['isoWeekday'] as num?)?.toInt(),
      startMinute: (map['startMinute'] as num?)?.toInt() ?? 0,
      endMinute: (map['endMinute'] as num?)?.toInt() ?? 1439,
    );
  }
}

/// Typed, immutable promotion definition consumed by the pure engine.
/// Persistence adapters will map the normalized Drift tables to this model.
class PromotionRule {
  final int id;
  final String code;
  final int version;
  final String name;
  final PromotionType type;
  final PromotionConcurrencyMode concurrencyMode;
  final int priority;
  final bool enabled;
  final int? currencyId;
  final String priceMode;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final List<PromotionScheduleWindow> schedule;
  final List<PromotionScope> qualifierScopes;
  final List<PromotionScope> rewardScopes;
  final int minimumQuantity;
  final int quantityScale;
  final String? measurementType;
  final Money? minimumSpend;
  final PromotionRewardType rewardType;
  final int percentBps;
  final Money? amountOff;
  final Money? fixedBundlePrice;
  final int rewardQuantity;
  final int rewardQuantityScale;
  final bool rewardUsesQualifierPool;
  final Money? maxDiscount;
  final int? maxApplicationsPerTransaction;
  final bool allowManualDiscountCombination;

  const PromotionRule({
    required this.id,
    required this.code,
    this.version = 1,
    required this.name,
    required this.type,
    this.concurrencyMode = PromotionConcurrencyMode.bestPrice,
    this.priority = 0,
    this.enabled = true,
    this.currencyId,
    this.priceMode = 'retail',
    this.startsAt,
    this.endsAt,
    this.schedule = const [],
    this.qualifierScopes = const [],
    this.rewardScopes = const [],
    this.minimumQuantity = 0,
    this.quantityScale = 1,
    this.measurementType,
    this.minimumSpend,
    required this.rewardType,
    this.percentBps = 0,
    this.amountOff,
    this.fixedBundlePrice,
    this.rewardQuantity = 0,
    this.rewardQuantityScale = 1,
    this.rewardUsesQualifierPool = false,
    this.maxDiscount,
    this.maxApplicationsPerTransaction,
    this.allowManualDiscountCombination = false,
  });

  List<String> validate() {
    final errors = <String>[];
    if (id <= 0) errors.add('id must be positive');
    if (code.trim().isEmpty) errors.add('code is required');
    if (version <= 0) errors.add('version must be positive');
    if (name.trim().isEmpty) errors.add('name is required');
    if (currencyId != null && currencyId! <= 0) {
      errors.add('currencyId must be positive when provided');
    }
    if (!const {'retail', 'wholesale', 'any'}.contains(priceMode)) {
      errors.add('priceMode must be retail, wholesale, or any');
    }
    if (endsAt != null && startsAt != null && endsAt!.isBefore(startsAt!)) {
      errors.add('endsAt cannot be before startsAt');
    }
    if (quantityScale <= 0) errors.add('quantityScale must be positive');
    if (rewardQuantityScale <= 0) {
      errors.add('rewardQuantityScale must be positive');
    }
    if (maxApplicationsPerTransaction != null &&
        maxApplicationsPerTransaction! <= 0) {
      errors.add('maxApplicationsPerTransaction must be positive');
    }
    if (maxDiscount != null && maxDiscount!.isNegative) {
      errors.add('maxDiscount cannot be negative');
    }
    for (final window in schedule) {
      errors.addAll(window.validate());
    }
    final includedScopes = qualifierScopes
        .where((scope) => !scope.excluded)
        .toList(growable: false);
    final componentScopes = includedScopes
        .where((scope) => scope.requiredQuantity != null)
        .toList(growable: false);
    for (final scope in componentScopes) {
      if (scope.requiredQuantity! <= 0) {
        errors.add('component requiredQuantity must be positive');
      }
      if (scope.quantityScale <= 0) {
        errors.add('component quantityScale must be positive');
      }
    }
    if (componentScopes.isNotEmpty) {
      if (componentScopes.length != includedScopes.length) {
        errors.add('all included scopes must be components when one is');
      }
      if (type != PromotionType.quantity && type != PromotionType.fixedBundle) {
        errors.add('component scopes require a quantity or fixed bundle offer');
      }
    }

    switch (type) {
      case PromotionType.simple:
        break;
      case PromotionType.quantity:
      case PromotionType.fixedBundle:
      case PromotionType.buyXGetY:
        if (minimumQuantity <= 0) {
          errors.add('minimumQuantity must be positive for $type');
        }
      case PromotionType.threshold:
        if (minimumSpend == null || !minimumSpend!.isPositive) {
          errors.add('minimumSpend must be positive for threshold offers');
        }
    }

    switch (rewardType) {
      case PromotionRewardType.percentageOff:
        if (percentBps <= 0 || percentBps > 10000) {
          errors.add('percentBps must be between 1 and 10000');
        }
      case PromotionRewardType.amountOff:
        if (amountOff == null || !amountOff!.isPositive) {
          errors.add('amountOff must be positive');
        }
      case PromotionRewardType.fixedBundlePrice:
        if (type != PromotionType.fixedBundle) {
          errors.add('fixedBundlePrice reward requires a fixedBundle offer');
        }
        if (fixedBundlePrice == null || fixedBundlePrice!.isNegative) {
          errors.add('fixedBundlePrice cannot be negative');
        }
        if (concurrencyMode == PromotionConcurrencyMode.compound) {
          errors.add('fixed bundle offers cannot use compound concurrency');
        }
      case PromotionRewardType.freeQuantity:
        if (type != PromotionType.buyXGetY) {
          errors.add('freeQuantity reward requires a buyXGetY offer');
        }
        if (rewardQuantity <= 0) {
          errors.add('rewardQuantity must be positive');
        }
    }

    if (type == PromotionType.buyXGetY) {
      if (rewardQuantity <= 0) {
        errors.add('rewardQuantity must be positive for buyXGetY');
      }
      if (rewardUsesQualifierPool && rewardQuantityScale != quantityScale) {
        errors.add(
          'qualifier and reward scales must match when they share a pool',
        );
      }
    }
    return errors.toSet().toList(growable: false);
  }

  bool isActiveAt(DateTime localTime, int cartCurrencyId) {
    if (!enabled) return false;
    if (currencyId != null && currencyId != cartCurrencyId) return false;
    if (startsAt != null && localTime.isBefore(startsAt!)) return false;
    if (endsAt != null && localTime.isAfter(endsAt!)) return false;
    return schedule.isEmpty ||
        schedule.any((window) => window.matches(localTime));
  }

  /// Stable, JSON-safe representation used only to preview master-owned
  /// rules on LAN clients. The master always re-evaluates the cart before
  /// posting, so this payload is never an authority for financial writes.
  Map<String, Object?> toTransportMap() => {
    'id': id,
    'code': code,
    'version': version,
    'name': name,
    'type': type.name,
    'concurrencyMode': concurrencyMode.name,
    'priority': priority,
    'enabled': enabled,
    'currencyId': currencyId,
    'priceMode': priceMode,
    'startsAt': startsAt?.toUtc().toIso8601String(),
    'endsAt': endsAt?.toUtc().toIso8601String(),
    'schedule': schedule.map((row) => row.toTransportMap()).toList(),
    'qualifierScopes': qualifierScopes
        .map((row) => row.toTransportMap())
        .toList(),
    'rewardScopes': rewardScopes.map((row) => row.toTransportMap()).toList(),
    'minimumQuantity': minimumQuantity,
    'quantityScale': quantityScale,
    'measurementType': measurementType,
    'minimumSpendCents': minimumSpend?.cents,
    'rewardType': rewardType.name,
    'percentBps': percentBps,
    'amountOffCents': amountOff?.cents,
    'fixedBundlePriceCents': fixedBundlePrice?.cents,
    'rewardQuantity': rewardQuantity,
    'rewardQuantityScale': rewardQuantityScale,
    'rewardUsesQualifierPool': rewardUsesQualifierPool,
    'maxDiscountCents': maxDiscount?.cents,
    'maxApplicationsPerTransaction': maxApplicationsPerTransaction,
    'allowManualDiscountCombination': allowManualDiscountCombination,
  };

  factory PromotionRule.fromTransportMap(Map<String, dynamic> map) {
    List<PromotionScope> scopes(String key) =>
        (map[key] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(PromotionScope.fromTransportMap)
            .toList(growable: false);
    final startsAt = DateTime.tryParse(map['startsAt']?.toString() ?? '');
    final endsAt = DateTime.tryParse(map['endsAt']?.toString() ?? '');
    return PromotionRule(
      id: (map['id'] as num).toInt(),
      code: map['code']?.toString() ?? '',
      version: (map['version'] as num?)?.toInt() ?? 1,
      name: map['name']?.toString() ?? '',
      type: PromotionType.values.firstWhere(
        (value) => value.name == map['type'],
        orElse: () => PromotionType.simple,
      ),
      concurrencyMode: PromotionConcurrencyMode.values.firstWhere(
        (value) => value.name == map['concurrencyMode'],
        orElse: () => PromotionConcurrencyMode.bestPrice,
      ),
      priority: (map['priority'] as num?)?.toInt() ?? 0,
      enabled: map['enabled'] != false,
      currencyId: (map['currencyId'] as num?)?.toInt(),
      priceMode: map['priceMode']?.toString() ?? 'retail',
      startsAt: startsAt?.toLocal(),
      endsAt: endsAt?.toLocal(),
      schedule: (map['schedule'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(PromotionScheduleWindow.fromTransportMap)
          .toList(growable: false),
      qualifierScopes: scopes('qualifierScopes'),
      rewardScopes: scopes('rewardScopes'),
      minimumQuantity: (map['minimumQuantity'] as num?)?.toInt() ?? 0,
      quantityScale: (map['quantityScale'] as num?)?.toInt() ?? 1,
      measurementType: map['measurementType']?.toString(),
      minimumSpend: map['minimumSpendCents'] == null
          ? null
          : Money.fromCents((map['minimumSpendCents'] as num).toInt()),
      rewardType: PromotionRewardType.values.firstWhere(
        (value) => value.name == map['rewardType'],
        orElse: () => PromotionRewardType.percentageOff,
      ),
      percentBps: (map['percentBps'] as num?)?.toInt() ?? 0,
      amountOff: map['amountOffCents'] == null
          ? null
          : Money.fromCents((map['amountOffCents'] as num).toInt()),
      fixedBundlePrice: map['fixedBundlePriceCents'] == null
          ? null
          : Money.fromCents((map['fixedBundlePriceCents'] as num).toInt()),
      rewardQuantity: (map['rewardQuantity'] as num?)?.toInt() ?? 0,
      rewardQuantityScale: (map['rewardQuantityScale'] as num?)?.toInt() ?? 1,
      rewardUsesQualifierPool: map['rewardUsesQualifierPool'] == true,
      maxDiscount: map['maxDiscountCents'] == null
          ? null
          : Money.fromCents((map['maxDiscountCents'] as num).toInt()),
      maxApplicationsPerTransaction:
          (map['maxApplicationsPerTransaction'] as num?)?.toInt(),
      allowManualDiscountCombination:
          map['allowManualDiscountCombination'] == true,
    );
  }
}

class PromotionCartLine {
  final String lineId;
  final int productId;
  final int? variantId;
  final int? categoryId;
  final String measurementType;
  final String priceMode;
  final int quantity;
  final int quantityScale;
  final Money unitPrice;

  /// Manual/loyalty discount already committed to this line. Promotions
  /// never discount more than the remaining amount.
  final Money existingDiscount;

  PromotionCartLine({
    required this.lineId,
    required this.productId,
    this.variantId,
    this.categoryId,
    this.measurementType = 'piece',
    this.priceMode = 'retail',
    required this.quantity,
    this.quantityScale = 1,
    required this.unitPrice,
    Money? existingDiscount,
  }) : existingDiscount = existingDiscount ?? Money.zero;

  Money get subtotal =>
      unitPrice.multiplyRatio(quantity, quantityScale).round();

  Money get availableSubtotal =>
      (subtotal - existingDiscount).clampNonNegative();

  void validate() {
    if (lineId.isEmpty) throw ArgumentError('lineId is required');
    if (productId <= 0) throw ArgumentError('productId must be positive');
    if (quantity < 0) throw ArgumentError('quantity cannot be negative');
    if (quantityScale <= 0) {
      throw ArgumentError('quantityScale must be positive');
    }
    if (!const {'retail', 'wholesale'}.contains(priceMode)) {
      throw ArgumentError('priceMode must be retail or wholesale');
    }
    if (unitPrice.isNegative) {
      throw ArgumentError('unitPrice cannot be negative');
    }
    if (existingDiscount.isNegative || existingDiscount > subtotal) {
      throw ArgumentError('existingDiscount must be within the line subtotal');
    }
  }
}

class PromotionCart {
  final int currencyId;
  final DateTime evaluatedAt;
  final List<PromotionCartLine> lines;

  const PromotionCart({
    required this.currencyId,
    required this.evaluatedAt,
    required this.lines,
  });
}

class PromotionAllocation {
  final String lineId;
  final Money discount;
  final int appliedQuantity;
  final int quantityScale;
  final PromotionRewardType rewardType;

  const PromotionAllocation({
    required this.lineId,
    required this.discount,
    required this.appliedQuantity,
    required this.quantityScale,
    required this.rewardType,
  });

  Map<String, Object> toSnapshotMap() => {
    'lineId': lineId,
    'discountCents': discount.cents,
    'appliedQuantity': appliedQuantity,
    'quantityScale': quantityScale,
    'rewardType': rewardType.name,
  };
}

class AppliedPromotion {
  final int promotionId;
  final String code;
  final String name;
  final int version;
  final PromotionType type;
  final PromotionConcurrencyMode concurrencyMode;
  final int priority;
  final int applicationCount;
  final List<PromotionAllocation> allocations;

  const AppliedPromotion({
    required this.promotionId,
    required this.code,
    required this.name,
    required this.version,
    required this.type,
    required this.concurrencyMode,
    required this.priority,
    required this.applicationCount,
    required this.allocations,
  });

  Money get totalDiscount => allocations.fold(
    Money.zero,
    (total, allocation) => total + allocation.discount,
  );

  Map<String, Object> toSnapshotMap() => {
    'engineVersion': PromotionEngineVersion.current,
    'promotionId': promotionId,
    'code': code,
    'name': name,
    'version': version,
    'type': type.name,
    'concurrencyMode': concurrencyMode.name,
    'priority': priority,
    'applicationCount': applicationCount,
    'discountCents': totalDiscount.cents,
    'allocations': allocations.map((a) => a.toSnapshotMap()).toList(),
  };
}

class PromotionEvaluationResult {
  final List<AppliedPromotion> applications;
  final Map<String, List<String>> rejectedPromotions;

  const PromotionEvaluationResult({
    required this.applications,
    this.rejectedPromotions = const {},
  });

  Money get totalDiscount => applications.fold(
    Money.zero,
    (total, application) => total + application.totalDiscount,
  );

  Map<String, Money> get discountByLine {
    final result = <String, Money>{};
    for (final application in applications) {
      for (final allocation in application.allocations) {
        result.update(
          allocation.lineId,
          (value) => value + allocation.discount,
          ifAbsent: () => allocation.discount,
        );
      }
    }
    return result;
  }
}

class _SelectedQuantity {
  final PromotionCartLine line;
  final int quantity;
  final Money base;

  const _SelectedQuantity(this.line, this.quantity, this.base);
}

class _ComponentSelection {
  final int applicationCount;
  final List<_SelectedQuantity> quantities;

  const _ComponentSelection(this.applicationCount, this.quantities);
}

/// Pure, deterministic promotion resolver. It does not access the database,
/// mutate inventory, or post accounting entries.
abstract final class PromotionEngine {
  static const int _exactConflictSearchLimit = 20;

  static PromotionEvaluationResult evaluate({
    required PromotionCart cart,
    required Iterable<PromotionRule> promotions,
  }) {
    if (cart.currencyId <= 0) {
      throw ArgumentError('cart.currencyId must be positive');
    }
    final lineIds = <String>{};
    for (final line in cart.lines) {
      line.validate();
      if (!lineIds.add(line.lineId)) {
        throw ArgumentError('Duplicate cart lineId: ${line.lineId}');
      }
    }

    final rejected = <String, List<String>>{};
    final candidates = <AppliedPromotion>[];
    for (final promotion in promotions) {
      final errors = promotion.validate();
      if (errors.isNotEmpty) {
        rejected[promotion.code] = errors;
        continue;
      }
      if (!promotion.isActiveAt(cart.evaluatedAt, cart.currencyId)) continue;
      final candidate = _evaluateOne(cart, promotion);
      if (candidate != null && candidate.totalDiscount.isPositive) {
        candidates.add(candidate);
      }
    }

    return PromotionEvaluationResult(
      applications: _resolveConflicts(cart, candidates),
      rejectedPromotions: rejected,
    );
  }

  static AppliedPromotion? _evaluateOne(
    PromotionCart cart,
    PromotionRule rule,
  ) {
    final qualifiers = _eligibleLines(cart.lines, rule.qualifierScopes, rule);
    final rewardScopes = rule.rewardScopes.isEmpty
        ? rule.qualifierScopes
        : rule.rewardScopes;
    final rewardLines = _eligibleLines(cart.lines, rewardScopes, rule);

    return switch (rule.type) {
      PromotionType.simple => _rewardWholeLines(rule, rewardLines, 1),
      PromotionType.quantity => _evaluateQuantity(
        rule,
        qualifiers,
        rewardLines,
      ),
      PromotionType.fixedBundle => _evaluateFixedBundle(rule, qualifiers),
      PromotionType.buyXGetY => _evaluateBuyXGetY(
        rule,
        qualifiers,
        rewardLines,
      ),
      PromotionType.threshold => _evaluateThreshold(cart, rule, rewardLines),
    };
  }

  static List<PromotionCartLine> _eligibleLines(
    List<PromotionCartLine> lines,
    List<PromotionScope> scopes,
    PromotionRule rule,
  ) => lines
      .where((line) {
        if (line.quantity == 0 || line.availableSubtotal.isZero) return false;
        if (!rule.allowManualDiscountCombination &&
            line.existingDiscount.isPositive) {
          return false;
        }
        if (rule.measurementType != null &&
            line.measurementType != rule.measurementType) {
          return false;
        }
        if (rule.priceMode != 'any' && line.priceMode != rule.priceMode) {
          return false;
        }
        if (scopes.any((scope) => scope.excluded && scope.matches(line))) {
          return false;
        }
        final included = scopes.where((scope) => !scope.excluded).toList();
        return included.isEmpty || included.any((scope) => scope.matches(line));
      })
      .toList(growable: false);

  static AppliedPromotion? _evaluateQuantity(
    PromotionRule rule,
    List<PromotionCartLine> qualifiers,
    List<PromotionCartLine> rewardLines,
  ) {
    final componentSelection = _selectRequiredComponents(rule, qualifiers);
    if (componentSelection != null) {
      final selected = componentSelection.quantities;
      final totalBase = selected.fold(
        Money.zero,
        (sum, item) => sum + item.base,
      );
      final discount = switch (rule.rewardType) {
        PromotionRewardType.percentageOff => _sumMoney(
          selected.map((item) => item.base.percentage(rule.percentBps)),
        ),
        PromotionRewardType.amountOff =>
          (rule.amountOff! * componentSelection.applicationCount).min(
            totalBase,
          ),
        PromotionRewardType.freeQuantity => totalBase,
        PromotionRewardType.fixedBundlePrice => Money.zero,
      };
      if (discount.isZero) return null;
      return _buildAllocatedApplication(
        rule,
        componentSelection.applicationCount,
        selected,
        discount,
        preservePerLinePercentage:
            rule.rewardType == PromotionRewardType.percentageOff,
      );
    }
    final useSellingUnits = _usesSellingUnitQuantities(rule);
    final compatible = useSellingUnits
        ? qualifiers
        : qualifiers
              .where((line) => line.quantityScale == rule.quantityScale)
              .toList(growable: false);
    var applications = useSellingUnits
        ? _sellingUnitApplicationCount(compatible, rule.minimumQuantity)
        : compatible.fold<int>(0, (sum, line) => sum + line.quantity) ~/
              rule.minimumQuantity;
    if (applications <= 0) return null;
    applications = _capApplicationCount(rule, applications);
    if (rule.maxApplicationsPerTransaction != null) {
      final compatibleRewards = useSellingUnits
          ? rewardLines
          : rewardLines
                .where((line) => line.quantityScale == rule.quantityScale)
                .toList(growable: false);
      final selected = useSellingUnits
          ? _selectSellingUnits(
              compatibleRewards,
              applications * rule.minimumQuantity,
              cheapestFirst: false,
            )
          : _selectQuantity(
              compatibleRewards,
              applications * rule.minimumQuantity,
              cheapestFirst: false,
            );
      if (selected.isEmpty) return null;
      final selectedSubtotal = selected.fold(
        Money.zero,
        (sum, item) => sum + item.base,
      );
      final discount = switch (rule.rewardType) {
        PromotionRewardType.percentageOff => _sumMoney(
          selected.map((item) => item.base.percentage(rule.percentBps)),
        ),
        PromotionRewardType.amountOff => (rule.amountOff! * applications).min(
          selectedSubtotal,
        ),
        PromotionRewardType.freeQuantity => selectedSubtotal,
        PromotionRewardType.fixedBundlePrice => Money.zero,
      };
      if (discount.isZero) return null;
      return _buildAllocatedApplication(
        rule,
        applications,
        selected,
        discount,
        preservePerLinePercentage:
            rule.rewardType == PromotionRewardType.percentageOff,
      );
    }
    return _rewardWholeLines(rule, rewardLines, applications);
  }

  static AppliedPromotion? _evaluateThreshold(
    PromotionCart cart,
    PromotionRule rule,
    List<PromotionCartLine> rewardLines,
  ) {
    final qualifyingSubtotal = _eligibleLines(
      cart.lines,
      rule.qualifierScopes,
      rule,
    ).fold(Money.zero, (sum, line) => sum + line.availableSubtotal);
    if (qualifyingSubtotal < rule.minimumSpend!) return null;
    return _rewardWholeLines(rule, rewardLines, 1);
  }

  static AppliedPromotion? _evaluateFixedBundle(
    PromotionRule rule,
    List<PromotionCartLine> qualifiers,
  ) {
    final componentSelection = _selectRequiredComponents(rule, qualifiers);
    if (componentSelection != null) {
      final selectedSubtotal = componentSelection.quantities.fold(
        Money.zero,
        (sum, item) => sum + item.base,
      );
      final bundleTotal =
          rule.fixedBundlePrice! * componentSelection.applicationCount;
      final discount = (selectedSubtotal - bundleTotal).clampNonNegative();
      if (discount.isZero) return null;
      return _buildAllocatedApplication(
        rule,
        componentSelection.applicationCount,
        componentSelection.quantities,
        discount,
      );
    }
    final useSellingUnits = _usesSellingUnitQuantities(rule);
    final compatible = useSellingUnits
        ? qualifiers
        : qualifiers
              .where((line) => line.quantityScale == rule.quantityScale)
              .toList(growable: false);
    var applications = useSellingUnits
        ? _sellingUnitApplicationCount(compatible, rule.minimumQuantity)
        : compatible.fold<int>(0, (sum, line) => sum + line.quantity) ~/
              rule.minimumQuantity;
    applications = _capApplicationCount(rule, applications);
    if (applications <= 0) return null;

    final selected = useSellingUnits
        ? _selectSellingUnits(
            compatible,
            applications * rule.minimumQuantity,
            cheapestFirst: false,
          )
        : _selectQuantity(
            compatible,
            applications * rule.minimumQuantity,
            cheapestFirst: false,
          );
    final selectedSubtotal = selected.fold(
      Money.zero,
      (sum, item) => sum + item.base,
    );
    final bundleTotal = rule.fixedBundlePrice! * applications;
    final discount = (selectedSubtotal - bundleTotal).clampNonNegative();
    if (discount.isZero) return null;
    return _buildAllocatedApplication(rule, applications, selected, discount);
  }

  /// Selects an exact composed bundle (for example one shampoo + one cream +
  /// one measured metre). Each scope owns its quantity scale, so unlike pooled
  /// quantity offers this never adds pieces and metres together.
  static _ComponentSelection? _selectRequiredComponents(
    PromotionRule rule,
    List<PromotionCartLine> qualifiers,
  ) {
    final components = rule.qualifierScopes
        .where((scope) => scope.isRequiredComponent)
        .toList(growable: false);
    if (components.isEmpty) return null;

    int? applicationCount;
    for (final component in components) {
      final available = qualifiers
          .where(
            (line) =>
                component.matches(line) &&
                line.quantityScale == component.quantityScale,
          )
          .fold<int>(0, (sum, line) => sum + line.quantity);
      final count = available ~/ component.requiredQuantity!;
      applicationCount = applicationCount == null
          ? count
          : _minInt(applicationCount, count);
    }
    final capped = _capApplicationCount(rule, applicationCount ?? 0);
    if (capped <= 0) return const _ComponentSelection(0, []);

    final selected = <_SelectedQuantity>[];
    for (final component in components) {
      final candidates = qualifiers
          .where(
            (line) =>
                component.matches(line) &&
                line.quantityScale == component.quantityScale,
          )
          .toList(growable: false);
      selected.addAll(
        _selectQuantity(
          candidates,
          component.requiredQuantity! * capped,
          cheapestFirst: false,
        ),
      );
    }
    return _ComponentSelection(capped, selected);
  }

  static AppliedPromotion? _evaluateBuyXGetY(
    PromotionRule rule,
    List<PromotionCartLine> qualifiers,
    List<PromotionCartLine> rewardLines,
  ) {
    final useSellingUnits = _usesSellingUnitQuantities(rule);
    final compatibleQualifiers = useSellingUnits
        ? qualifiers
        : qualifiers
              .where((line) => line.quantityScale == rule.quantityScale)
              .toList(growable: false);
    final compatibleRewards = useSellingUnits
        ? rewardLines
        : rewardLines
              .where((line) => line.quantityScale == rule.rewardQuantityScale)
              .toList(growable: false);

    int applications;
    if (useSellingUnits && rule.rewardUsesQualifierPool) {
      applications = _sellingUnitApplicationCount(
        compatibleQualifiers,
        rule.minimumQuantity + rule.rewardQuantity,
      );
    } else if (useSellingUnits) {
      applications = _minInt(
        _sellingUnitApplicationCount(
          compatibleQualifiers,
          rule.minimumQuantity,
        ),
        _sellingUnitApplicationCount(compatibleRewards, rule.rewardQuantity),
      );
    } else if (rule.rewardUsesQualifierPool) {
      final qualifierQuantity = compatibleQualifiers.fold<int>(
        0,
        (sum, line) => sum + line.quantity,
      );
      applications =
          qualifierQuantity ~/ (rule.minimumQuantity + rule.rewardQuantity);
    } else {
      final qualifierQuantity = compatibleQualifiers.fold<int>(
        0,
        (sum, line) => sum + line.quantity,
      );
      final rewardQuantity = compatibleRewards.fold<int>(
        0,
        (sum, line) => sum + line.quantity,
      );
      applications = _minInt(
        qualifierQuantity ~/ rule.minimumQuantity,
        rewardQuantity ~/ rule.rewardQuantity,
      );
    }
    applications = _capApplicationCount(rule, applications);
    if (applications <= 0) return null;

    final rewardSelection = useSellingUnits
        ? _selectSellingUnits(
            compatibleRewards,
            applications * rule.rewardQuantity,
            cheapestFirst: true,
          )
        : _selectQuantity(
            compatibleRewards,
            applications * rule.rewardQuantity,
            cheapestFirst: true,
          );
    if (rewardSelection.isEmpty) return null;

    final selectedSubtotal = rewardSelection.fold(
      Money.zero,
      (sum, item) => sum + item.base,
    );
    final discount = switch (rule.rewardType) {
      PromotionRewardType.freeQuantity => selectedSubtotal,
      PromotionRewardType.percentageOff => selectedSubtotal.percentage(
        rule.percentBps,
      ),
      PromotionRewardType.amountOff => (rule.amountOff! * applications).min(
        selectedSubtotal,
      ),
      PromotionRewardType.fixedBundlePrice => Money.zero,
    };
    if (discount.isZero) return null;

    // A cheapest-item-free promotion is priced as one transaction-level
    // bundle. Distributing the value of the free item across every
    // participating unit preserves the same customer total while making
    // partial returns safe: a customer cannot return only the paid items at
    // full price and keep the free item. It also gives the profitability
    // guard the exact qualifier/reward quantities that belong to the bundle.
    if (rule.rewardType == PromotionRewardType.freeQuantity) {
      final participants = _selectBuyXGetYParticipants(
        rule: rule,
        compatibleQualifiers: compatibleQualifiers,
        rewardSelection: rewardSelection,
        applications: applications,
        useSellingUnits: useSellingUnits,
      );
      if (participants.isEmpty) return null;
      return _buildAllocatedApplication(
        rule,
        applications,
        participants,
        discount,
        retainZeroAllocations: true,
      );
    }

    return _buildAllocatedApplication(
      rule,
      applications,
      rewardSelection,
      discount,
    );
  }

  static AppliedPromotion? _rewardWholeLines(
    PromotionRule rule,
    List<PromotionCartLine> lines,
    int applicationCount,
  ) {
    if (lines.isEmpty || applicationCount <= 0) return null;
    final selected = lines
        .map(
          (line) =>
              _SelectedQuantity(line, line.quantity, line.availableSubtotal),
        )
        .toList(growable: false);
    final totalBase = selected.fold(Money.zero, (sum, item) => sum + item.base);
    final discount = switch (rule.rewardType) {
      PromotionRewardType.percentageOff => _sumMoney(
        selected.map((item) => item.base.percentage(rule.percentBps)),
      ),
      PromotionRewardType.amountOff => (rule.amountOff! * applicationCount).min(
        totalBase,
      ),
      PromotionRewardType.freeQuantity => totalBase,
      PromotionRewardType.fixedBundlePrice => Money.zero,
    };
    if (discount.isZero) return null;
    return _buildAllocatedApplication(
      rule,
      applicationCount,
      selected,
      discount,
      preservePerLinePercentage:
          rule.rewardType == PromotionRewardType.percentageOff,
    );
  }

  static AppliedPromotion _buildAllocatedApplication(
    PromotionRule rule,
    int applicationCount,
    List<_SelectedQuantity> selected,
    Money requestedDiscount, {
    bool preservePerLinePercentage = false,
    bool retainZeroAllocations = false,
  }) {
    var discount = requestedDiscount;
    if (rule.maxDiscount != null) discount = discount.min(rule.maxDiscount!);
    final totalBase = selected.fold(Money.zero, (sum, item) => sum + item.base);
    discount = discount.min(totalBase);

    List<Money> shares;
    if (preservePerLinePercentage &&
        rule.maxDiscount == null &&
        discount.cents == requestedDiscount.cents) {
      shares = selected
          .map((item) => item.base.percentage(rule.percentBps))
          .toList(growable: false);
    } else {
      shares = discount.allocate(
        selected.map((item) => item.base.cents).toList(growable: false),
      );
    }

    final allocations = <PromotionAllocation>[];
    for (var i = 0; i < selected.length; i++) {
      if (shares[i].isZero && !retainZeroAllocations) continue;
      allocations.add(
        PromotionAllocation(
          lineId: selected[i].line.lineId,
          discount: shares[i],
          appliedQuantity: selected[i].quantity,
          quantityScale: selected[i].line.quantityScale,
          rewardType: rule.rewardType,
        ),
      );
    }
    return AppliedPromotion(
      promotionId: rule.id,
      code: rule.code,
      name: rule.name,
      version: rule.version,
      type: rule.type,
      concurrencyMode: rule.concurrencyMode,
      priority: rule.priority,
      applicationCount: applicationCount,
      allocations: allocations,
    );
  }

  static List<_SelectedQuantity> _selectQuantity(
    List<PromotionCartLine> lines,
    int requestedQuantity, {
    required bool cheapestFirst,
  }) {
    if (requestedQuantity <= 0) return const [];
    final sorted = [...lines]
      ..sort((a, b) {
        final left = a.availableSubtotal.cents * b.quantity;
        final right = b.availableSubtotal.cents * a.quantity;
        final comparison = left.compareTo(right);
        if (comparison != 0) return cheapestFirst ? comparison : -comparison;
        return a.lineId.compareTo(b.lineId);
      });
    var remaining = requestedQuantity;
    final result = <_SelectedQuantity>[];
    for (final line in sorted) {
      if (remaining <= 0) break;
      final take = _minInt(line.quantity, remaining);
      final base = take == line.quantity
          ? line.availableSubtotal
          : line.availableSubtotal.multiplyRatio(take, line.quantity).round();
      if (take > 0 && base.isPositive) {
        result.add(_SelectedQuantity(line, take, base));
      }
      remaining -= take;
    }
    return remaining == 0 ? result : const [];
  }

  /// Promotions created from the UI express quantities in customer-facing
  /// selling units (pieces, metres, kilograms...), while cart quantities are
  /// stored in each line's integer base scale. A generic "buy 2" offer must
  /// therefore see two metres stored as 2000/1000 exactly like two pieces
  /// stored as 2/1. Explicit measurement rules keep their strict legacy scale.
  static bool _usesSellingUnitQuantities(PromotionRule rule) =>
      rule.measurementType == null && rule.quantityScale == 1;

  static int _sellingUnitApplicationCount(
    List<PromotionCartLine> lines,
    int unitsPerApplication,
  ) {
    if (lines.isEmpty || unitsPerApplication <= 0) return 0;
    final commonScale = _commonQuantityScale(lines);
    final total = lines.fold<int>(
      0,
      (sum, line) => sum + line.quantity * (commonScale ~/ line.quantityScale),
    );
    return total ~/ (unitsPerApplication * commonScale);
  }

  /// Selects an exact number of customer-facing selling units and returns
  /// quantities in every line's original base scale for persistence.
  static List<_SelectedQuantity> _selectSellingUnits(
    List<PromotionCartLine> lines,
    int requestedUnits, {
    required bool cheapestFirst,
  }) {
    if (requestedUnits <= 0 || lines.isEmpty) return const [];
    final commonScale = _commonQuantityScale(lines);
    var remaining = requestedUnits * commonScale;
    final sorted = [...lines]
      ..sort((a, b) {
        final left =
            BigInt.from(a.availableSubtotal.cents) *
            BigInt.from(a.quantityScale) *
            BigInt.from(b.quantity);
        final right =
            BigInt.from(b.availableSubtotal.cents) *
            BigInt.from(b.quantityScale) *
            BigInt.from(a.quantity);
        final comparison = left.compareTo(right);
        if (comparison != 0) return cheapestFirst ? comparison : -comparison;
        return a.lineId.compareTo(b.lineId);
      });
    final selectedByLine = <String, int>{};

    // Prefer complete selling units first. This preserves indivisible piece
    // semantics while still allowing metres/weights to contribute precisely.
    for (final line in sorted) {
      if (remaining <= 0) break;
      final wholeBaseQuantity =
          (line.quantity ~/ line.quantityScale) * line.quantityScale;
      final available = wholeBaseQuantity * (commonScale ~/ line.quantityScale);
      final take = _minInt(available, (remaining ~/ commonScale) * commonScale);
      if (take <= 0) continue;
      final baseQuantity = take * line.quantityScale ~/ commonScale;
      selectedByLine[line.lineId] = baseQuantity;
      remaining -= take;
    }

    // Fractional measured remainders can combine across variants (for example
    // 1.5 m + 0.5 m). Finer scales go first so an exact total is never rounded.
    if (remaining > 0) {
      final fractional =
          sorted
              .where((line) => line.quantity % line.quantityScale != 0)
              .toList()
            ..sort((a, b) {
              final scale = b.quantityScale.compareTo(a.quantityScale);
              if (scale != 0) return scale;
              return a.lineId.compareTo(b.lineId);
            });
      for (final line in fractional) {
        if (remaining <= 0) break;
        final alreadySelected = selectedByLine[line.lineId] ?? 0;
        final availableBase = line.quantity - alreadySelected;
        final maxBase = remaining * line.quantityScale ~/ commonScale;
        final takeBase = _minInt(availableBase, maxBase);
        if (takeBase <= 0) continue;
        selectedByLine[line.lineId] = alreadySelected + takeBase;
        remaining -= takeBase * (commonScale ~/ line.quantityScale);
      }
    }
    if (remaining != 0) return const [];

    return sorted
        .where((line) => (selectedByLine[line.lineId] ?? 0) > 0)
        .map((line) {
          final quantity = selectedByLine[line.lineId]!;
          final base = quantity == line.quantity
              ? line.availableSubtotal
              : line.availableSubtotal
                    .multiplyRatio(quantity, line.quantity)
                    .round();
          return _SelectedQuantity(line, quantity, base);
        })
        .where((item) => item.base.isPositive)
        .toList(growable: false);
  }

  static List<_SelectedQuantity> _selectBuyXGetYParticipants({
    required PromotionRule rule,
    required List<PromotionCartLine> compatibleQualifiers,
    required List<_SelectedQuantity> rewardSelection,
    required int applications,
    required bool useSellingUnits,
  }) {
    final qualifierCandidates = rule.rewardUsesQualifierPool
        ? _subtractSelection(compatibleQualifiers, rewardSelection)
        : compatibleQualifiers;
    final qualifierQuantity = applications * rule.minimumQuantity;
    final qualifierSelection = useSellingUnits
        ? _selectSellingUnits(
            qualifierCandidates,
            qualifierQuantity,
            cheapestFirst: false,
          )
        : _selectQuantity(
            qualifierCandidates,
            qualifierQuantity,
            cheapestFirst: false,
          );
    if (qualifierSelection.isEmpty) return const [];

    final originals = {
      for (final line in <PromotionCartLine>[
        ...qualifierCandidates,
        ...compatibleQualifiers,
      ])
        line.lineId: line,
    };
    final merged = <String, _SelectedQuantity>{};
    for (final selection in <_SelectedQuantity>[
      ...rewardSelection,
      ...qualifierSelection,
    ]) {
      final current = merged[selection.line.lineId];
      final quantity = (current?.quantity ?? 0) + selection.quantity;
      final original = originals[selection.line.lineId] ?? selection.line;
      if (quantity > original.quantity) return const [];
      merged[selection.line.lineId] = _SelectedQuantity(
        original,
        quantity,
        (current?.base ?? Money.zero) + selection.base,
      );
    }
    return merged.values.toList(growable: false);
  }

  static List<PromotionCartLine> _subtractSelection(
    List<PromotionCartLine> lines,
    List<_SelectedQuantity> selected,
  ) {
    final selectedByLine = <String, int>{};
    for (final item in selected) {
      selectedByLine.update(
        item.line.lineId,
        (value) => value + item.quantity,
        ifAbsent: () => item.quantity,
      );
    }
    final result = <PromotionCartLine>[];
    for (final line in lines) {
      final remaining = line.quantity - (selectedByLine[line.lineId] ?? 0);
      if (remaining <= 0) continue;
      final remainingDiscount = line.existingDiscount
          .multiplyRatio(remaining, line.quantity)
          .round();
      result.add(
        PromotionCartLine(
          lineId: line.lineId,
          productId: line.productId,
          variantId: line.variantId,
          categoryId: line.categoryId,
          measurementType: line.measurementType,
          priceMode: line.priceMode,
          quantity: remaining,
          quantityScale: line.quantityScale,
          unitPrice: line.unitPrice,
          existingDiscount: remainingDiscount,
        ),
      );
    }
    return result;
  }

  static int _commonQuantityScale(List<PromotionCartLine> lines) => lines
      .map((line) => line.quantityScale)
      .fold<int>(1, _leastCommonMultiple);

  static int _leastCommonMultiple(int a, int b) =>
      a ~/ _greatestCommonDivisor(a, b) * b;

  static int _greatestCommonDivisor(int a, int b) {
    var left = a.abs();
    var right = b.abs();
    while (right != 0) {
      final remainder = left % right;
      left = right;
      right = remainder;
    }
    return left == 0 ? 1 : left;
  }

  static List<AppliedPromotion> _resolveConflicts(
    PromotionCart cart,
    List<AppliedPromotion> candidates,
  ) {
    final exclusive = candidates
        .where((c) => c.concurrencyMode == PromotionConcurrencyMode.exclusive)
        .toList();
    final bestPrice = candidates
        .where((c) => c.concurrencyMode == PromotionConcurrencyMode.bestPrice)
        .toList();
    final compound = candidates
        .where((c) => c.concurrencyMode == PromotionConcurrencyMode.compound)
        .toList();

    final selectedExclusive = _chooseBestNonOverlapping(exclusive, const {});
    final exclusiveLines = selectedExclusive
        .expand((candidate) => candidate.allocations.map((a) => a.lineId))
        .toSet();
    final selectedBest = _chooseBestNonOverlapping(bestPrice, exclusiveLines);

    final result = <AppliedPromotion>[...selectedExclusive, ...selectedBest];
    final usedByLine = <String, Money>{};
    for (final application in result) {
      for (final allocation in application.allocations) {
        usedByLine.update(
          allocation.lineId,
          (value) => value + allocation.discount,
          ifAbsent: () => allocation.discount,
        );
      }
    }
    final lineById = {for (final line in cart.lines) line.lineId: line};

    compound.sort(_candidateOrder);
    for (final candidate in compound) {
      if (candidate.allocations.any((a) => exclusiveLines.contains(a.lineId))) {
        continue;
      }
      final adjusted = <PromotionAllocation>[];
      for (final allocation in candidate.allocations) {
        final line = lineById[allocation.lineId];
        if (line == null) continue;
        final alreadyUsed = usedByLine[allocation.lineId] ?? Money.zero;
        final remaining = (line.availableSubtotal - alreadyUsed)
            .clampNonNegative();
        final amount = allocation.discount.min(remaining);
        if (amount.isZero) {
          if (allocation.discount.isZero) adjusted.add(allocation);
          continue;
        }
        adjusted.add(
          PromotionAllocation(
            lineId: allocation.lineId,
            discount: amount,
            appliedQuantity: allocation.appliedQuantity,
            quantityScale: allocation.quantityScale,
            rewardType: allocation.rewardType,
          ),
        );
        usedByLine.update(
          allocation.lineId,
          (value) => value + amount,
          ifAbsent: () => amount,
        );
      }
      if (adjusted.isNotEmpty) {
        result.add(
          AppliedPromotion(
            promotionId: candidate.promotionId,
            code: candidate.code,
            name: candidate.name,
            version: candidate.version,
            type: candidate.type,
            concurrencyMode: candidate.concurrencyMode,
            priority: candidate.priority,
            applicationCount: candidate.applicationCount,
            allocations: adjusted,
          ),
        );
      }
    }

    result.sort(_candidateOrder);
    return List.unmodifiable(result);
  }

  static List<AppliedPromotion> _chooseBestNonOverlapping(
    List<AppliedPromotion> source,
    Set<String> lockedLines,
  ) {
    final candidates =
        source
            .where(
              (candidate) => candidate.allocations.every(
                (allocation) => !lockedLines.contains(allocation.lineId),
              ),
            )
            .toList()
          ..sort(_candidateOrder);
    if (candidates.length > _exactConflictSearchLimit) {
      final chosen = <AppliedPromotion>[];
      final used = <String>{...lockedLines};
      final byValue = [...candidates]
        ..sort((a, b) {
          final amount = b.totalDiscount.cents.compareTo(a.totalDiscount.cents);
          return amount != 0 ? amount : _candidateOrder(a, b);
        });
      for (final candidate in byValue) {
        final lines = candidate.allocations.map((a) => a.lineId);
        if (lines.any(used.contains)) continue;
        chosen.add(candidate);
        used.addAll(lines);
      }
      return chosen;
    }

    List<AppliedPromotion> best = const [];
    var bestCents = -1;
    var bestPriority = -1;
    final suffix = List<int>.filled(candidates.length + 1, 0);
    for (var i = candidates.length - 1; i >= 0; i--) {
      suffix[i] = suffix[i + 1] + candidates[i].totalDiscount.cents;
    }

    void search(
      int index,
      Set<String> used,
      List<AppliedPromotion> selected,
      int cents,
      int priority,
    ) {
      if (cents + suffix[index] < bestCents) return;
      if (index == candidates.length) {
        if (cents > bestCents ||
            (cents == bestCents && priority > bestPriority)) {
          bestCents = cents;
          bestPriority = priority;
          best = List.of(selected);
        }
        return;
      }

      final candidate = candidates[index];
      final lines = candidate.allocations.map((a) => a.lineId).toSet();
      if (!lines.any(used.contains)) {
        selected.add(candidate);
        search(
          index + 1,
          {...used, ...lines},
          selected,
          cents + candidate.totalDiscount.cents,
          priority + candidate.priority,
        );
        selected.removeLast();
      }
      search(index + 1, used, selected, cents, priority);
    }

    search(0, {...lockedLines}, <AppliedPromotion>[], 0, 0);
    return best;
  }

  static int _candidateOrder(AppliedPromotion a, AppliedPromotion b) {
    final priority = b.priority.compareTo(a.priority);
    if (priority != 0) return priority;
    final code = a.code.compareTo(b.code);
    if (code != 0) return code;
    return a.promotionId.compareTo(b.promotionId);
  }

  static int _capApplicationCount(PromotionRule rule, int count) {
    final max = rule.maxApplicationsPerTransaction;
    return max == null ? count : _minInt(count, max);
  }

  static int _minInt(int a, int b) => a < b ? a : b;

  static Money _sumMoney(Iterable<Money> values) =>
      values.fold(Money.zero, (sum, value) => sum + value);
}
