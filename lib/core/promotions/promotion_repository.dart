import 'package:drift/drift.dart';
import 'package:decimal/decimal.dart';

import '../database/app_database.dart';
import '../measurement/measurement.dart';
import '../money/money.dart';
import '../services/audit_log_service.dart';
import '../services/feature_gate_service.dart';
import 'promotion_engine.dart' as promo;
import 'promotion_sale_snapshot.dart';

class PromotionDraft {
  final int version;
  final String code;
  final String name;
  final promo.PromotionType type;
  final promo.PromotionRewardType rewardType;
  final promo.PromotionConcurrencyMode concurrencyMode;
  final String priceMode;
  final List<int> productIds;
  final List<int> variantIds;
  final List<int> categoryIds;
  final bool requireEachSelectedItem;
  final int minimumQuantity;
  final int quantityScale;
  final int rewardQuantity;
  final int percentBps;
  final int? amountCents;
  final int? fixedPriceCents;
  final int? minimumSpendCents;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final List<promo.PromotionScheduleWindow> schedule;
  final int priority;
  final int? maxApplicationsPerTransaction;
  final bool allowManualDiscountCombination;

  const PromotionDraft({
    this.version = 1,
    required this.code,
    required this.name,
    required this.type,
    required this.rewardType,
    this.concurrencyMode = promo.PromotionConcurrencyMode.bestPrice,
    this.priceMode = 'retail',
    this.productIds = const [],
    this.variantIds = const [],
    this.categoryIds = const [],
    this.requireEachSelectedItem = false,
    this.minimumQuantity = 0,
    this.quantityScale = 1,
    this.rewardQuantity = 0,
    this.percentBps = 0,
    this.amountCents,
    this.fixedPriceCents,
    this.minimumSpendCents,
    this.startsAt,
    this.endsAt,
    this.schedule = const [],
    this.priority = 0,
    this.maxApplicationsPerTransaction,
    this.allowManualDiscountCombination = false,
  });

  promo.PromotionRule asValidationRule() {
    final scopes = <promo.PromotionScope>[
      ...productIds.map(
        (id) => promo.PromotionScope.product(
          id,
          requiredQuantity: requireEachSelectedItem ? 1 : null,
        ),
      ),
      ...variantIds.map(
        (id) => promo.PromotionScope.variant(
          id,
          requiredQuantity: requireEachSelectedItem ? 1 : null,
        ),
      ),
      ...categoryIds.map((id) => promo.PromotionScope.category(id)),
    ];
    return promo.PromotionRule(
      id: 1,
      code: code.trim(),
      version: version,
      name: name.trim(),
      type: type,
      concurrencyMode: concurrencyMode,
      priceMode: priceMode,
      startsAt: startsAt,
      endsAt: endsAt,
      schedule: schedule,
      priority: priority,
      qualifierScopes: scopes,
      rewardScopes: scopes,
      minimumQuantity: requireEachSelectedItem
          ? productIds.toSet().length + variantIds.toSet().length
          : minimumQuantity,
      quantityScale: quantityScale,
      minimumSpend: minimumSpendCents == null
          ? null
          : Money.fromCents(minimumSpendCents!),
      rewardType: rewardType,
      percentBps: percentBps,
      amountOff: amountCents == null ? null : Money.fromCents(amountCents!),
      fixedBundlePrice: fixedPriceCents == null
          ? null
          : Money.fromCents(fixedPriceCents!),
      rewardQuantity: rewardQuantity,
      rewardUsesQualifierPool: type == promo.PromotionType.buyXGetY,
      maxApplicationsPerTransaction: maxApplicationsPerTransaction,
      allowManualDiscountCombination: allowManualDiscountCombination,
    );
  }

  List<String> validate() {
    final errors = asValidationRule().validate().toList();
    if (code.trim().length > 64) errors.add('code is too long');
    if (version <= 0) errors.add('version must be positive');
    if (name.trim().length > 160) errors.add('name is too long');
    if (productIds.any((id) => id <= 0)) {
      errors.add('productIds must contain positive IDs');
    }
    if (variantIds.any((id) => id <= 0)) {
      errors.add('variantIds must contain positive IDs');
    }
    if (categoryIds.any((id) => id <= 0)) {
      errors.add('categoryIds must contain positive IDs');
    }
    if (requireEachSelectedItem &&
        type != promo.PromotionType.quantity &&
        type != promo.PromotionType.fixedBundle) {
      errors.add('composed bundles require quantity or fixed bundle type');
    }
    if (requireEachSelectedItem && productIds.isEmpty && variantIds.isEmpty) {
      errors.add('composed bundles require selected items');
    }
    if (requireEachSelectedItem && categoryIds.isNotEmpty) {
      errors.add('composed bundles cannot use category scopes');
    }
    if (!const {'retail', 'wholesale', 'any'}.contains(priceMode)) {
      errors.add('priceMode must be retail, wholesale, or any');
    }
    return errors.toSet().toList(growable: false);
  }
}

/// Transactional persistence boundary for promotion definitions.
///
/// The sales flow consumes [promo.PromotionRule] only. UI code never writes the
/// normalized child tables itself, preventing half-saved definitions.
class PromotionRepository {
  final AppDatabase _db;
  final AuditLogService _audit;
  final FeatureGateService? _featureGate;

  PromotionRepository(this._db, this._audit, {FeatureGateService? featureGate})
    : _featureGate = featureGate;

  bool get _hasProAccess =>
      _featureGate?.canAccess(AppFeature.promotions).granted ?? true;

  void _requireProAccess() {
    if (!_hasProAccess) throw StateError('promotion_requires_pro');
  }

  Stream<List<Promotion>> watchAll() {
    return (_db.select(_db.promotions)..orderBy([
          // Status changes update `updatedAt`. Ordering by it made cards jump
          // after every toggle and looked like another switch had changed.
          (row) => OrderingTerm.desc(row.createdAt),
          (row) => OrderingTerm.desc(row.id),
        ]))
        .watch();
  }

  Future<List<PromotionUsageReportRow>> loadUsageReport({
    DateTime? from,
    DateTime? toExclusive,
    int? promotionId,
    String? status,
  }) async {
    final filter = _usageFilter(
      from: from,
      toExclusive: toExclusive,
      promotionId: promotionId,
      status: status,
    );
    final rows = await _db
        .customSelect(
          '''
      ${_usageCtes(filter.sql)}
      SELECT
        lt.promotion_id,
        lt.promotion_code,
        lt.promotion_name,
        lt.promotion_version,
        lt.promotion_status,
        lt.currency_id,
        lt.currency_code,
        lt.currency_symbol,
        COUNT(*) AS transaction_count,
        COALESCE(SUM(at.application_count), 0) AS application_count,
        COALESCE(SUM(lt.gross_sales_cents), 0) AS gross_sales_cents,
        COALESCE(SUM(lt.returned_gross_sales_cents), 0)
          AS returned_gross_sales_cents,
        COALESCE(SUM(lt.discount_cents), 0) AS discount_cents,
        COALESCE(SUM(lt.returned_discount_cents), 0)
          AS returned_discount_cents,
        COALESCE(SUM(lt.cost_cents), 0) AS cost_cents,
        COALESCE(SUM(lt.returned_cost_cents), 0) AS returned_cost_cents
      FROM line_totals lt
      INNER JOIN application_totals at
        ON at.promotion_id = lt.promotion_id AND at.sale_id = lt.sale_id
      GROUP BY
        lt.promotion_id,
        lt.promotion_code,
        lt.promotion_name,
        lt.promotion_version,
        lt.promotion_status,
        lt.currency_id,
        lt.currency_code,
        lt.currency_symbol
      ORDER BY lt.currency_code, lt.promotion_name, lt.promotion_version DESC
      ''',
          variables: filter.variables,
          readsFrom: _usageReadsFrom,
        )
        .get();
    return rows.map(_readUsageReportRow).toList(growable: false);
  }

  Future<List<PromotionUsageInvoiceRow>> loadUsageInvoices({
    required int promotionId,
    required int currencyId,
    DateTime? from,
    DateTime? toExclusive,
    String? status,
  }) async {
    if (promotionId <= 0 || currencyId <= 0) return const [];
    final filter = _usageFilter(
      from: from,
      toExclusive: toExclusive,
      promotionId: promotionId,
      status: status,
    );
    final rows = await _db
        .customSelect(
          '''
      ${_usageCtes(filter.sql)}
      SELECT
        lt.sale_id,
        lt.invoice_number,
        lt.sale_date,
        lt.currency_id,
        lt.currency_code,
        lt.currency_symbol,
        at.application_count,
        lt.gross_sales_cents,
        lt.returned_gross_sales_cents,
        lt.discount_cents,
        lt.returned_discount_cents,
        lt.cost_cents,
        lt.returned_cost_cents
      FROM line_totals lt
      INNER JOIN application_totals at
        ON at.promotion_id = lt.promotion_id AND at.sale_id = lt.sale_id
      WHERE lt.currency_id = ?
      ORDER BY lt.sale_date DESC, lt.sale_id DESC
      ''',
          variables: [...filter.variables, Variable.withInt(currencyId)],
          readsFrom: _usageReadsFrom,
        )
        .get();
    return rows
        .map(
          (row) => PromotionUsageInvoiceRow(
            saleId: row.read<int>('sale_id'),
            invoiceNumber: row.read<String>('invoice_number'),
            saleDate: row.read<DateTime>('sale_date'),
            currencyId: row.read<int>('currency_id'),
            currencyCode: row.read<String>('currency_code'),
            currencySymbol: row.read<String>('currency_symbol'),
            applicationCount: row.read<int>('application_count'),
            grossSalesCents: row.read<int>('gross_sales_cents'),
            returnedGrossSalesCents: row.read<int>(
              'returned_gross_sales_cents',
            ),
            discountCents: row.read<int>('discount_cents'),
            returnedDiscountCents: row.read<int>('returned_discount_cents'),
            costCents: row.read<int>('cost_cents'),
            returnedCostCents: row.read<int>('returned_cost_cents'),
          ),
        )
        .toList(growable: false);
  }

  ({String sql, List<Variable<Object>> variables}) _usageFilter({
    DateTime? from,
    DateTime? toExclusive,
    int? promotionId,
    String? status,
  }) {
    final clauses = <String>["s.status != 'voided'"];
    final variables = <Variable<Object>>[];
    if (from != null) {
      clauses.add('s.sale_date >= ?');
      variables.add(Variable<DateTime>(from));
    }
    if (toExclusive != null) {
      clauses.add('s.sale_date < ?');
      variables.add(Variable<DateTime>(toExclusive));
    }
    if (promotionId != null && promotionId > 0) {
      clauses.add('spa.promotion_id = ?');
      variables.add(Variable<int>(promotionId));
    }
    if (status != null && status.isNotEmpty && status != 'all') {
      clauses.add('p.status = ?');
      variables.add(Variable<String>(status));
    }
    return (sql: clauses.join(' AND '), variables: variables);
  }

  String _usageCtes(String whereSql) =>
      '''
      WITH allocation_base AS (
        SELECT
          spa.id AS application_id,
          spa.promotion_id,
          spa.promotion_code,
          spa.promotion_name,
          spa.promotion_version,
          p.status AS promotion_status,
          spa.application_count,
          s.id AS sale_id,
          s.invoice_number,
          s.sale_date,
          s.currency_id,
          c.code AS currency_code,
          c.symbol AS currency_symbol,
          CAST(ROUND(
            1.0 * sia.original_unit_price_cents * sia.applied_quantity /
            CASE WHEN sia.quantity_scale > 0 THEN sia.quantity_scale ELSE 1 END
          ) AS INTEGER) AS gross_sales_cents,
          sia.discount_cents AS discount_cents,
          CAST(ROUND(
            1.0 * COALESCE(
              si.inventory_value_at_post_cents,
              CAST(ROUND(
                1.0 * COALESCE(si.cost_cents, pv.cost_cents, pr.cost_cents, 0)
                * si.quantity /
                CASE WHEN si.quantity_scale > 0 THEN si.quantity_scale ELSE 1 END
              ) AS INTEGER)
            ) * sia.applied_quantity *
            CASE WHEN si.quantity_scale > 0 THEN si.quantity_scale ELSE 1 END /
            CASE
              WHEN si.quantity > 0
                THEN si.quantity * CASE WHEN sia.quantity_scale > 0
                  THEN sia.quantity_scale ELSE 1 END
              ELSE 1
            END
          ) AS INTEGER) AS cost_cents,
          CASE
            WHEN si.quantity <= 0 THEN 0
            ELSE MIN(
              si.quantity,
              MAX(0, si.qty_returned_linked + si.qty_returned_adjustment)
            )
          END AS returned_quantity,
          si.quantity AS sold_quantity
        FROM sale_item_promotion_allocations sia
        INNER JOIN sale_promotion_applications spa
          ON spa.id = sia.application_id
        INNER JOIN promotions p ON p.id = spa.promotion_id
        INNER JOIN sales s ON s.id = spa.sale_id
        INNER JOIN currencies c ON c.id = s.currency_id
        INNER JOIN sale_items si ON si.id = sia.sale_item_id
        INNER JOIN products pr ON pr.id = si.product_id
        LEFT JOIN product_variants pv ON pv.id = si.variant_id
        WHERE $whereSql
      ), allocation_net AS (
        SELECT
          *,
          CASE WHEN sold_quantity <= 0 THEN 0 ELSE CAST(ROUND(
            1.0 * gross_sales_cents * returned_quantity / sold_quantity
          ) AS INTEGER) END AS returned_gross_sales_cents,
          CASE WHEN sold_quantity <= 0 THEN 0 ELSE CAST(ROUND(
            1.0 * discount_cents * returned_quantity / sold_quantity
          ) AS INTEGER) END AS returned_discount_cents,
          CASE WHEN sold_quantity <= 0 THEN 0 ELSE CAST(ROUND(
            1.0 * cost_cents * returned_quantity / sold_quantity
          ) AS INTEGER) END AS returned_cost_cents
        FROM allocation_base
      ), line_totals AS (
        SELECT
          promotion_id,
          promotion_code,
          promotion_name,
          promotion_version,
          promotion_status,
          sale_id,
          invoice_number,
          sale_date,
          currency_id,
          currency_code,
          currency_symbol,
          SUM(gross_sales_cents) AS gross_sales_cents,
          SUM(returned_gross_sales_cents) AS returned_gross_sales_cents,
          SUM(discount_cents) AS discount_cents,
          SUM(returned_discount_cents) AS returned_discount_cents,
          SUM(cost_cents) AS cost_cents,
          SUM(returned_cost_cents) AS returned_cost_cents
        FROM allocation_net
        GROUP BY promotion_id, sale_id
      ), application_totals AS (
        SELECT
          promotion_id,
          sale_id,
          SUM(application_count) AS application_count
        FROM (
          SELECT DISTINCT application_id, promotion_id, sale_id,
            application_count
          FROM allocation_base
        )
        GROUP BY promotion_id, sale_id
      )
  ''';

  Set<ResultSetImplementation<dynamic, dynamic>> get _usageReadsFrom => {
    _db.promotions,
    _db.salePromotionApplications,
    _db.saleItemPromotionAllocations,
    _db.sales,
    _db.saleItems,
    _db.products,
    _db.productVariants,
    _db.currencies,
  };

  PromotionUsageReportRow _readUsageReportRow(QueryRow row) =>
      PromotionUsageReportRow(
        promotionId: row.read<int>('promotion_id'),
        promotionCode: row.read<String>('promotion_code'),
        promotionName: row.read<String>('promotion_name'),
        promotionVersion: row.read<int>('promotion_version'),
        status: row.read<String>('promotion_status'),
        currencyId: row.read<int>('currency_id'),
        currencyCode: row.read<String>('currency_code'),
        currencySymbol: row.read<String>('currency_symbol'),
        transactionCount: row.read<int>('transaction_count'),
        applicationCount: row.read<int>('application_count'),
        grossSalesCents: row.read<int>('gross_sales_cents'),
        returnedGrossSalesCents: row.read<int>('returned_gross_sales_cents'),
        discountCents: row.read<int>('discount_cents'),
        returnedDiscountCents: row.read<int>('returned_discount_cents'),
        costCents: row.read<int>('cost_cents'),
        returnedCostCents: row.read<int>('returned_cost_cents'),
      );

  Future<List<SalePromotionSnapshot>> loadSaleApplications(int saleId) async {
    if (saleId <= 0) return const [];
    final applications =
        await (_db.select(_db.salePromotionApplications)
              ..where((row) => row.saleId.equals(saleId))
              ..orderBy([(row) => OrderingTerm.asc(row.id)]))
            .get();
    if (applications.isEmpty) return const [];

    final applicationIds = applications.map((row) => row.id).toList();
    final allocations =
        await (_db.select(_db.saleItemPromotionAllocations)
              ..where((row) => row.applicationId.isIn(applicationIds))
              ..orderBy([(row) => OrderingTerm.asc(row.id)]))
            .get();
    final allocationsByApplication = <int, List<SalePromotionLineSnapshot>>{};
    for (final row in allocations) {
      allocationsByApplication
          .putIfAbsent(row.applicationId, () => [])
          .add(
            SalePromotionLineSnapshot(
              saleItemId: row.saleItemId,
              discountCents: row.discountCents.toBigInt().toInt(),
              appliedQuantity: row.appliedQuantity,
              quantityScale: row.quantityScale,
              originalUnitPriceCents: row.originalUnitPriceCents
                  .toBigInt()
                  .toInt(),
              rewardType: row.rewardType,
            ),
          );
    }
    return applications
        .map(
          (row) => SalePromotionSnapshot(
            applicationId: row.id,
            promotionId: row.promotionId,
            code: row.promotionCode,
            name: row.promotionName,
            version: row.promotionVersion,
            type: row.promotionType,
            concurrencyMode: row.concurrencyMode,
            applicationCount: row.applicationCount,
            discountCents: row.discountCents.toBigInt().toInt(),
            engineVersion: row.promotionEngineVersion,
            allocations: List.unmodifiable(
              allocationsByApplication[row.id] ?? const [],
            ),
          ),
        )
        .toList(growable: false);
  }

  Future<List<PromotionCurrencyPerformance>> loadPerformance(
    int promotionId,
  ) async {
    if (promotionId <= 0) return const [];
    final rows = await loadUsageReport(promotionId: promotionId);
    return rows
        .map(
          (row) => PromotionCurrencyPerformance(
            currencyId: row.currencyId,
            currencyCode: row.currencyCode,
            currencySymbol: row.currencySymbol,
            transactionCount: row.transactionCount,
            applicationCount: row.applicationCount,
            discountCents: row.netDiscountCents,
            netSalesCents: row.netSalesCents,
            revenueCents: row.netSalesCents,
            costCents: row.netCostCents,
            grossProfitCents: row.grossProfitCents,
          ),
        )
        .toList(growable: false);
  }

  Future<List<promo.PromotionRule>> loadActiveRules() async {
    if (!_hasProAccess) return const [];
    final rows =
        await (_db.select(_db.promotions)
              ..where(
                (row) =>
                    row.status.equals('active') &
                    row.applicationMode.equals('automatic'),
              )
              ..orderBy([
                (row) => OrderingTerm.desc(row.priority),
                (row) => OrderingTerm.asc(row.id),
              ]))
            .get();
    final rules = <promo.PromotionRule>[];
    for (final row in rows) {
      final rule = await loadRule(row.id);
      if (rule != null && rule.validate().isEmpty) rules.add(rule);
    }
    return List.unmodifiable(rules);
  }

  Future<int> create(PromotionDraft draft, {int? userId}) async {
    _requireProAccess();
    final errors = draft.validate();
    if (errors.isNotEmpty) {
      throw ArgumentError('Invalid promotion: ${errors.join(', ')}');
    }
    return _db.transaction(() async {
      final normalizedCode = draft.code.trim().toUpperCase();
      final duplicate = await (_db.select(
        _db.promotions,
      )..where((row) => row.code.equals(normalizedCode))).getSingleOrNull();
      if (duplicate != null) {
        throw StateError('promotion_code_exists');
      }

      final promotionId = await _db
          .into(_db.promotions)
          .insert(
            PromotionsCompanion.insert(
              code: normalizedCode,
              version: Value(draft.version),
              name: draft.name.trim(),
              promotionType: _typeToDb(draft.type),
              status: const Value('draft'),
              concurrencyMode: Value(_concurrencyToDb(draft.concurrencyMode)),
              priority: Value(draft.priority),
              priceMode: Value(draft.priceMode),
              startsAt: Value(draft.startsAt),
              endsAt: Value(draft.endsAt),
              maxApplicationsPerTransaction: Value(
                draft.maxApplicationsPerTransaction,
              ),
              allowManualDiscountCombination: Value(
                draft.allowManualDiscountCombination,
              ),
              createdBy: Value(userId),
              updatedBy: Value(userId),
            ),
          );

      if (draft.type == promo.PromotionType.threshold) {
        await _db
            .into(_db.promotionConditions)
            .insert(
              PromotionConditionsCompanion.insert(
                promotionId: promotionId,
                conditionType: 'minimum_spend',
                minimumSpendCents: Value(
                  draft.minimumSpendCents == null
                      ? null
                      : Decimal.fromInt(draft.minimumSpendCents!),
                ),
              ),
            );
      } else if (draft.type != promo.PromotionType.simple) {
        final minimumQuantity = draft.requireEachSelectedItem
            ? draft.productIds.toSet().length + draft.variantIds.toSet().length
            : draft.minimumQuantity;
        await _db
            .into(_db.promotionConditions)
            .insert(
              PromotionConditionsCompanion.insert(
                promotionId: promotionId,
                conditionType: 'minimum_quantity',
                minimumQuantity: Value(minimumQuantity),
                quantityScale: Value(draft.quantityScale),
              ),
            );
      }

      if (draft.productIds.isEmpty &&
          draft.variantIds.isEmpty &&
          draft.categoryIds.isEmpty) {
        await _db
            .into(_db.promotionScopes)
            .insert(
              PromotionScopesCompanion.insert(
                promotionId: promotionId,
                scopeRole: 'eligible',
                targetType: 'all',
              ),
            );
      } else {
        var sortOrder = 0;
        for (final productId in draft.productIds.toSet()) {
          final componentScale = draft.requireEachSelectedItem
              ? await _productQuantityScale(productId)
              : draft.quantityScale;
          await _db
              .into(_db.promotionScopes)
              .insert(
                PromotionScopesCompanion.insert(
                  promotionId: promotionId,
                  scopeRole: 'eligible',
                  targetType: 'product',
                  productId: Value(productId),
                  requiredQuantity: draft.requireEachSelectedItem
                      ? Value(componentScale)
                      : const Value.absent(),
                  quantityScale: Value(componentScale),
                  sortOrder: Value(sortOrder++),
                ),
              );
        }
        for (final variantId in draft.variantIds.toSet()) {
          final componentScale = draft.requireEachSelectedItem
              ? await _variantQuantityScale(variantId)
              : draft.quantityScale;
          await _db
              .into(_db.promotionScopes)
              .insert(
                PromotionScopesCompanion.insert(
                  promotionId: promotionId,
                  scopeRole: 'eligible',
                  targetType: 'variant',
                  variantId: Value(variantId),
                  requiredQuantity: draft.requireEachSelectedItem
                      ? Value(componentScale)
                      : const Value.absent(),
                  quantityScale: Value(componentScale),
                  sortOrder: Value(sortOrder++),
                ),
              );
        }
        for (final categoryId in draft.categoryIds.toSet()) {
          await _db
              .into(_db.promotionScopes)
              .insert(
                PromotionScopesCompanion.insert(
                  promotionId: promotionId,
                  scopeRole: 'eligible',
                  targetType: 'category',
                  categoryId: Value(categoryId),
                  quantityScale: Value(draft.quantityScale),
                  sortOrder: Value(sortOrder++),
                ),
              );
        }
      }

      for (final window in draft.schedule) {
        await _db
            .into(_db.promotionSchedules)
            .insert(
              PromotionSchedulesCompanion.insert(
                promotionId: promotionId,
                weekday: Value(window.isoWeekday),
                startMinute: Value(window.startMinute),
                endMinute: Value(window.endMinute),
              ),
            );
      }

      await _db
          .into(_db.promotionRewards)
          .insert(
            PromotionRewardsCompanion.insert(
              promotionId: promotionId,
              rewardType: _rewardToDb(draft.rewardType),
              percentBps: draft.percentBps > 0
                  ? Value(draft.percentBps)
                  : const Value.absent(),
              amountCents: draft.amountCents == null
                  ? const Value.absent()
                  : Value(Decimal.fromInt(draft.amountCents!)),
              fixedPriceCents: draft.fixedPriceCents == null
                  ? const Value.absent()
                  : Value(Decimal.fromInt(draft.fixedPriceCents!)),
              rewardQuantity: draft.rewardQuantity > 0
                  ? Value(draft.rewardQuantity)
                  : const Value.absent(),
              quantityScale: Value(draft.quantityScale),
            ),
          );
      await _audit.log(
        entityType: 'promotion',
        entityId: promotionId,
        action: 'create',
        userId: userId,
        newValue: {
          'code': normalizedCode,
          'name': draft.name.trim(),
          'type': _typeToDb(draft.type),
          'status': 'draft',
          'productIds': draft.productIds.toSet().toList(growable: false),
          'variantIds': draft.variantIds.toSet().toList(growable: false),
          'categoryIds': draft.categoryIds.toSet().toList(growable: false),
          'requireEachSelectedItem': draft.requireEachSelectedItem,
        },
      );
      return promotionId;
    });
  }

  /// Creates a new immutable definition version and archives the disabled
  /// predecessor. Existing invoices continue pointing at their frozen sale
  /// snapshots and are never recalculated.
  Future<int> revise(
    int promotionId,
    PromotionDraft draft, {
    int? userId,
  }) async {
    _requireProAccess();
    final current = await (_db.select(
      _db.promotions,
    )..where((row) => row.id.equals(promotionId))).getSingleOrNull();
    if (current == null) throw StateError('promotion_not_found');
    if (current.status == 'active') throw StateError('promotion_active');
    if (current.status == 'archived') throw StateError('promotion_archived');
    final nextVersion = current.version + 1;
    final requestedCode = draft.code.trim().toUpperCase();
    final nextCode = requestedCode == current.code
        ? '${current.code}-V$nextVersion'
        : requestedCode;
    final revised = PromotionDraft(
      version: nextVersion,
      code: nextCode,
      name: draft.name,
      type: draft.type,
      rewardType: draft.rewardType,
      concurrencyMode: draft.concurrencyMode,
      priceMode: draft.priceMode,
      productIds: draft.productIds,
      variantIds: draft.variantIds,
      categoryIds: draft.categoryIds,
      requireEachSelectedItem: draft.requireEachSelectedItem,
      minimumQuantity: draft.minimumQuantity,
      quantityScale: draft.quantityScale,
      rewardQuantity: draft.rewardQuantity,
      percentBps: draft.percentBps,
      amountCents: draft.amountCents,
      fixedPriceCents: draft.fixedPriceCents,
      minimumSpendCents: draft.minimumSpendCents,
      startsAt: draft.startsAt,
      endsAt: draft.endsAt,
      schedule: draft.schedule,
      priority: draft.priority,
      maxApplicationsPerTransaction: draft.maxApplicationsPerTransaction,
      allowManualDiscountCombination: draft.allowManualDiscountCombination,
    );
    return _db.transaction(() async {
      final newId = await create(revised, userId: userId);
      await archive(promotionId, userId: userId);
      await _audit.log(
        entityType: 'promotion',
        entityId: newId,
        action: 'revise',
        userId: userId,
        oldValue: {
          'sourcePromotionId': promotionId,
          'sourceCode': current.code,
          'sourceVersion': current.version,
        },
        newValue: {
          'promotionId': newId,
          'code': nextCode,
          'version': nextVersion,
        },
      );
      return newId;
    });
  }

  Future<int> duplicate(int promotionId, {int? userId}) async {
    _requireProAccess();
    final rule = await loadRule(promotionId);
    if (rule == null) throw StateError('promotion_not_found');
    var suffix = 1;
    var code = '${rule.code}-COPY';
    while (await (_db.select(
          _db.promotions,
        )..where((row) => row.code.equals(code))).getSingleOrNull() !=
        null) {
      code = '${rule.code}-COPY-${++suffix}';
    }
    final included = rule.qualifierScopes.where((scope) => !scope.excluded);
    final copyId = await create(
      PromotionDraft(
        code: code,
        name: '${rule.name} (Copy)',
        type: rule.type,
        rewardType: rule.rewardType,
        concurrencyMode: rule.concurrencyMode,
        priceMode: rule.priceMode,
        productIds: included
            .where((scope) => scope.type == promo.PromotionScopeType.product)
            .map((scope) => scope.targetId!)
            .toList(growable: false),
        variantIds: included
            .where((scope) => scope.type == promo.PromotionScopeType.variant)
            .map((scope) => scope.targetId!)
            .toList(growable: false),
        categoryIds: included
            .where((scope) => scope.type == promo.PromotionScopeType.category)
            .map((scope) => scope.targetId!)
            .toList(growable: false),
        requireEachSelectedItem: included.any(
          (scope) => scope.isRequiredComponent,
        ),
        minimumQuantity: rule.minimumQuantity,
        quantityScale: rule.quantityScale,
        rewardQuantity: rule.rewardQuantity,
        percentBps: rule.percentBps,
        amountCents: rule.amountOff?.cents,
        fixedPriceCents: rule.fixedBundlePrice?.cents,
        minimumSpendCents: rule.minimumSpend?.cents,
        startsAt: rule.startsAt,
        endsAt: rule.endsAt,
        schedule: rule.schedule,
        priority: rule.priority,
        maxApplicationsPerTransaction: rule.maxApplicationsPerTransaction,
        allowManualDiscountCombination: rule.allowManualDiscountCombination,
      ),
      userId: userId,
    );
    await _audit.log(
      entityType: 'promotion',
      entityId: copyId,
      action: 'duplicate',
      userId: userId,
      oldValue: {
        'sourcePromotionId': promotionId,
        'sourceVersion': rule.version,
      },
      newValue: {'copyPromotionId': copyId},
    );
    return copyId;
  }

  Future<void> setActive(int promotionId, bool active, {int? userId}) async {
    _requireProAccess();
    await _db.transaction(() async {
      final row =
          await (_db.select(_db.promotions)
                ..where((promotion) => promotion.id.equals(promotionId)))
              .getSingleOrNull();
      if (row == null) throw StateError('promotion_not_found');
      if (row.status == 'archived') throw StateError('promotion_archived');
      if (active) {
        final rule = await loadRule(promotionId);
        final errors = rule?.validate() ?? const ['promotion_not_found'];
        if (errors.isNotEmpty) {
          throw StateError('promotion_invalid:${errors.join('|')}');
        }
      }
      await (_db.update(
        _db.promotions,
      )..where((promotion) => promotion.id.equals(promotionId))).write(
        PromotionsCompanion(
          status: Value(active ? 'active' : 'paused'),
          updatedBy: Value(userId),
          updatedAt: Value(DateTime.now()),
        ),
      );
      await _audit.log(
        entityType: 'promotion',
        entityId: promotionId,
        action: active ? 'activate' : 'pause',
        userId: userId,
        oldValue: {'status': row.status},
        newValue: {'status': active ? 'active' : 'paused'},
      );
    });
  }

  Future<void> archive(int promotionId, {int? userId}) async {
    _requireProAccess();
    await _db.transaction(() async {
      final row =
          await (_db.select(_db.promotions)
                ..where((promotion) => promotion.id.equals(promotionId)))
              .getSingleOrNull();
      if (row == null) throw StateError('promotion_not_found');
      await (_db.update(
        _db.promotions,
      )..where((promotion) => promotion.id.equals(promotionId))).write(
        PromotionsCompanion(
          status: const Value('archived'),
          updatedBy: Value(userId),
          updatedAt: Value(DateTime.now()),
        ),
      );
      await _audit.log(
        entityType: 'promotion',
        entityId: promotionId,
        action: 'archive',
        userId: userId,
        oldValue: {'status': row.status},
        newValue: const {'status': 'archived'},
      );
    });
  }

  /// Permanently removes a promotion definition only while no posted sale has
  /// referenced it. The database FK remains the final safety net, while this
  /// explicit check provides a stable domain error for every caller (UI, LAN,
  /// or future API) instead of exposing a low-level constraint exception.
  Future<void> deleteUnused(int promotionId, {int? userId}) async {
    _requireProAccess();
    await _db.transaction(() async {
      final row =
          await (_db.select(_db.promotions)
                ..where((promotion) => promotion.id.equals(promotionId)))
              .getSingleOrNull();
      if (row == null) throw StateError('promotion_not_found');

      final application =
          await (_db.select(_db.salePromotionApplications)
                ..where((item) => item.promotionId.equals(promotionId))
                ..limit(1))
              .getSingleOrNull();
      if (application != null) throw StateError('promotion_used');

      await _audit.log(
        entityType: 'promotion',
        entityId: promotionId,
        action: 'delete',
        userId: userId,
        oldValue: {
          'code': row.code,
          'name': row.name,
          'version': row.version,
          'status': row.status,
        },
        newValue: const {'deleted': true, 'reason': 'unused'},
      );
      await (_db.delete(
        _db.promotions,
      )..where((promotion) => promotion.id.equals(promotionId))).go();
    });
  }

  Future<promo.PromotionRule?> loadRule(int promotionId) async {
    final header = await (_db.select(
      _db.promotions,
    )..where((row) => row.id.equals(promotionId))).getSingleOrNull();
    if (header == null) return null;
    final conditions = await (_db.select(
      _db.promotionConditions,
    )..where((row) => row.promotionId.equals(promotionId))).get();
    final scopes = await (_db.select(
      _db.promotionScopes,
    )..where((row) => row.promotionId.equals(promotionId))).get();
    final rewards = await (_db.select(
      _db.promotionRewards,
    )..where((row) => row.promotionId.equals(promotionId))).get();
    final schedules = await (_db.select(
      _db.promotionSchedules,
    )..where((row) => row.promotionId.equals(promotionId))).get();
    if (rewards.length != 1) return null;

    final quantityCondition = conditions
        .where((row) => row.conditionType == 'minimum_quantity')
        .firstOrNull;
    final spendCondition = conditions
        .where((row) => row.conditionType == 'minimum_spend')
        .firstOrNull;
    final reward = rewards.single;
    final mappedScopes = scopes.map(_scopeFromDb).toList(growable: false);
    final rewardUsesQualifierPool =
        _typeFromDb(header.promotionType) == promo.PromotionType.buyXGetY &&
        !scopes.any((row) => row.scopeRole == 'reward');

    return promo.PromotionRule(
      id: header.id,
      code: header.code,
      version: header.version,
      name: header.name,
      type: _typeFromDb(header.promotionType),
      concurrencyMode: _concurrencyFromDb(header.concurrencyMode),
      priority: header.priority,
      enabled: header.status == 'active',
      currencyId: header.currencyId,
      priceMode: header.priceMode,
      startsAt: header.startsAt,
      endsAt: header.endsAt,
      schedule: schedules
          .map(
            (row) => promo.PromotionScheduleWindow(
              isoWeekday: row.weekday,
              startMinute: row.startMinute,
              endMinute: row.endMinute,
            ),
          )
          .toList(growable: false),
      qualifierScopes: mappedScopes,
      rewardScopes: mappedScopes,
      minimumQuantity: quantityCondition?.minimumQuantity ?? 0,
      quantityScale: quantityCondition?.quantityScale ?? reward.quantityScale,
      measurementType: quantityCondition?.measurementType,
      minimumSpend: spendCondition?.minimumSpendCents == null
          ? null
          : Money.fromCents(
              spendCondition!.minimumSpendCents!.toBigInt().toInt(),
            ),
      rewardType: _rewardFromDb(reward.rewardType),
      percentBps: reward.percentBps ?? 0,
      amountOff: reward.amountCents == null
          ? null
          : Money.fromCents(reward.amountCents!.toBigInt().toInt()),
      fixedBundlePrice: reward.fixedPriceCents == null
          ? null
          : Money.fromCents(reward.fixedPriceCents!.toBigInt().toInt()),
      rewardQuantity: reward.rewardQuantity ?? 0,
      rewardQuantityScale: reward.quantityScale,
      rewardUsesQualifierPool: rewardUsesQualifierPool,
      maxDiscount: reward.maxDiscountCents == null
          ? null
          : Money.fromCents(reward.maxDiscountCents!.toBigInt().toInt()),
      maxApplicationsPerTransaction: header.maxApplicationsPerTransaction,
      allowManualDiscountCombination: header.allowManualDiscountCombination,
    );
  }

  promo.PromotionScope _scopeFromDb(PromotionScope row) =>
      switch (row.targetType) {
        'product' => promo.PromotionScope.product(
          row.productId!,
          excluded: row.isExcluded,
          requiredQuantity: row.requiredQuantity,
          quantityScale: row.quantityScale,
        ),
        'variant' => promo.PromotionScope.variant(
          row.variantId!,
          excluded: row.isExcluded,
          requiredQuantity: row.requiredQuantity,
          quantityScale: row.quantityScale,
        ),
        'category' => promo.PromotionScope.category(
          row.categoryId!,
          excluded: row.isExcluded,
          requiredQuantity: row.requiredQuantity,
          quantityScale: row.quantityScale,
        ),
        _ => promo.PromotionScope.all(excluded: row.isExcluded),
      };

  Future<int> _productQuantityScale(int productId) async {
    final row = await (_db.select(
      _db.products,
    )..where((product) => product.id.equals(productId))).getSingleOrNull();
    if (row == null) throw StateError('promotion_product_not_found');
    return MeasurementType.fromDb(row.measurementType).quantityScale;
  }

  Future<int> _variantQuantityScale(int variantId) async {
    final variant = await (_db.select(
      _db.productVariants,
    )..where((row) => row.id.equals(variantId))).getSingleOrNull();
    if (variant == null) throw StateError('promotion_variant_not_found');
    return _productQuantityScale(variant.productId);
  }

  static String _typeToDb(promo.PromotionType type) => switch (type) {
    promo.PromotionType.simple => 'simple',
    promo.PromotionType.quantity => 'quantity',
    promo.PromotionType.fixedBundle => 'fixed_bundle',
    promo.PromotionType.buyXGetY => 'buy_x_get_y',
    promo.PromotionType.threshold => 'threshold',
  };

  static promo.PromotionType _typeFromDb(String value) => switch (value) {
    'quantity' => promo.PromotionType.quantity,
    'fixed_bundle' => promo.PromotionType.fixedBundle,
    'buy_x_get_y' => promo.PromotionType.buyXGetY,
    'threshold' => promo.PromotionType.threshold,
    _ => promo.PromotionType.simple,
  };

  static String _rewardToDb(promo.PromotionRewardType type) => switch (type) {
    promo.PromotionRewardType.percentageOff => 'percentage_off',
    promo.PromotionRewardType.amountOff => 'amount_off',
    promo.PromotionRewardType.fixedBundlePrice => 'fixed_bundle_price',
    promo.PromotionRewardType.freeQuantity => 'free_quantity',
  };

  static promo.PromotionRewardType _rewardFromDb(String value) =>
      switch (value) {
        'amount_off' => promo.PromotionRewardType.amountOff,
        'fixed_bundle_price' => promo.PromotionRewardType.fixedBundlePrice,
        'free_quantity' => promo.PromotionRewardType.freeQuantity,
        _ => promo.PromotionRewardType.percentageOff,
      };

  static String _concurrencyToDb(promo.PromotionConcurrencyMode mode) =>
      switch (mode) {
        promo.PromotionConcurrencyMode.exclusive => 'exclusive',
        promo.PromotionConcurrencyMode.bestPrice => 'best_price',
        promo.PromotionConcurrencyMode.compound => 'compound',
      };

  static promo.PromotionConcurrencyMode _concurrencyFromDb(String value) =>
      switch (value) {
        'exclusive' => promo.PromotionConcurrencyMode.exclusive,
        'compound' => promo.PromotionConcurrencyMode.compound,
        _ => promo.PromotionConcurrencyMode.bestPrice,
      };
}
